--!strict
--[[
	@module ProgressionService
	@owner Agent 1 (Breight321)
	@description Система уровней, опыта (XP), перерождений (Rebirths) и открытия зон.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Core"):WaitForChild("Types"))
local Logger = require(Shared:WaitForChild("Core"):WaitForChild("Logger"))
local Signal = require(Shared:WaitForChild("Core"):WaitForChild("Signal"))
local Network = require(Shared:WaitForChild("Core"):WaitForChild("Network"))

local GameConfig = require(Shared:WaitForChild("Config"):WaitForChild("GameConfig"))
local ZonesConfig = require(Shared:WaitForChild("Config"):WaitForChild("ZonesConfig"))

local ProgressionService = {
	Name = "ProgressionService",
	Dependencies = { "PlayerDataService", "EconomyService" },
	OnRebirth = Signal.new(),
	OnZoneUnlocked = Signal.new(),
}

local log = Logger.new("ProgressionService")
local playerDataService: any = nil
local economyService: any = nil
local connections: { RBXScriptConnection } = {}

function ProgressionService:Init(registry: any): ()
	playerDataService = registry:Get("PlayerDataService")
	economyService = registry:Get("EconomyService")
	log:Info("Initialized ProgressionService")
end

function ProgressionService:Start(): ()
	table.insert(
		connections,
		Network.OnServerEvent(Network.Events.RequestRebirth, function(player: Player)
			self:PerformRebirth(player)
		end)
	)

	table.insert(
		connections,
		Network.OnServerEvent(Network.Events.RequestUnlockZone, function(player: Player, zoneId: any)
			if type(zoneId) == "string" then
				self:UnlockZone(player, zoneId)
			end
		end)
	)
end

function ProgressionService:GetRebirthCost(currentRebirths: number): number
	return math.floor(
		GameConfig.Progression.BaseRebirthCostCoins
			* (GameConfig.Progression.RebirthCostMultiplier ^ currentRebirths)
	)
end

function ProgressionService:CanRebirth(player: Player): Types.Result<boolean, string>
	local profRes = playerDataService:GetProfile(player)
	if not profRes.ok or not profRes.value then
		return Types.Err("PROFILE_NOT_LOADED")
	end

	local cost = self:GetRebirthCost(profRes.value.rebirths)
	if not economyService:CanAfford(player, "Coins", cost) then
		return Types.Err("INSUFFICIENT_COINS_FOR_REBIRTH")
	end

	return Types.Ok(true)
end

function ProgressionService:PerformRebirth(player: Player): Types.Result<number, string>
	local canRes = self:CanRebirth(player)
	if not canRes.ok then
		return Types.Err(canRes.error or "CANNOT_REBIRTH")
	end

	local newRebirths = 0
	local updateRes = playerDataService:UpdateProfile(player, function(profile: Types.PlayerProfileData)
		profile.currencies.Coins = 0
		profile.rebirths += 1
		newRebirths = profile.rebirths
		return true
	end)

	if not updateRes.ok then
		return Types.Err("REBIRTH_UPDATE_FAILED")
	end

	economyService:AddCurrency(player, "Gems", GameConfig.Progression.RebirthGemsReward, "RebirthReward")

	local prof = playerDataService:GetProfile(player).value
	if prof then
		Network.FireClient(
			player,
			Network.Events.ProgressionUpdated,
			prof.level,
			prof.xp,
			prof.rebirths,
			prof.unlockedZones
		)
	end

	self.OnRebirth:Fire(player, newRebirths)
	return Types.Ok(newRebirths)
end

function ProgressionService:IsZoneUnlocked(player: Player, zoneId: string): boolean
	local profRes = playerDataService:GetProfile(player)
	if not profRes.ok or not profRes.value then
		return false
	end
	return profRes.value.unlockedZones[zoneId] == true
end

function ProgressionService:UnlockZone(player: Player, zoneId: string): Types.Result<boolean, string>
	local zoneDef = ZonesConfig[zoneId]
	if not zoneDef then
		return Types.Err("UNKNOWN_ZONE")
	end
	if self:IsZoneUnlocked(player, zoneId) then
		return Types.Err("ZONE_ALREADY_UNLOCKED")
	end

	local profRes = playerDataService:GetProfile(player)
	if not profRes.ok or not profRes.value then
		return Types.Err("PROFILE_NOT_LOADED")
	end

	if profRes.value.rebirths < zoneDef.requiredRebirths then
		return Types.Err("INSUFFICIENT_REBIRTHS")
	end

	if zoneDef.costAmount > 0 then
		local deductRes = economyService:RemoveCurrency(player, zoneDef.costCurrency, zoneDef.costAmount, "UnlockZone")
		if not deductRes.ok then
			return Types.Err(deductRes.error or "INSUFFICIENT_FUNDS")
		end
	end

	playerDataService:UpdateProfile(player, function(profile: Types.PlayerProfileData)
		profile.unlockedZones[zoneId] = true
		return true
	end)

	local prof = playerDataService:GetProfile(player).value
	if prof then
		Network.FireClient(
			player,
			Network.Events.ProgressionUpdated,
			prof.level,
			prof.xp,
			prof.rebirths,
			prof.unlockedZones
		)
	end

	self.OnZoneUnlocked:Fire(player, zoneId)
	return Types.Ok(true)
end

function ProgressionService:AddXP(
	player: Player,
	amount: number
): Types.Result<{ level: number, xp: number }, string>
	if amount <= 0 then
		return Types.Err("INVALID_XP_AMOUNT")
	end

	local newLevel = 1
	local newXP = 0

	playerDataService:UpdateProfile(player, function(profile: Types.PlayerProfileData)
		profile.xp += amount
		local required = math.floor(
			GameConfig.Progression.BaseXPToLevelUp
				* (GameConfig.Progression.XPGrindingGrowthFactor ^ (profile.level - 1))
		)
		while profile.xp >= required do
			profile.xp -= required
			profile.level += 1
			required = math.floor(
				GameConfig.Progression.BaseXPToLevelUp
					* (GameConfig.Progression.XPGrindingGrowthFactor ^ (profile.level - 1))
			)
		end
		newLevel = profile.level
		newXP = profile.xp
		return true
	end)

	return Types.Ok({ level = newLevel, xp = newXP })
end

function ProgressionService:Shutdown(): ()
	for _, conn in ipairs(connections) do
		conn:Disconnect()
	end
	table.clear(connections)
	log:Info("Shutdown ProgressionService")
end

return ProgressionService
