--!strict
--[[
	@module EconomyService
	@owner Agent 1 (Breight321)
	@description Управление валютами игрока, расчёт множителей и обработка кликов симулятора.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Core"):WaitForChild("Types"))
local Logger = require(Shared:WaitForChild("Core"):WaitForChild("Logger"))
local Signal = require(Shared:WaitForChild("Core"):WaitForChild("Signal"))
local Network = require(Shared:WaitForChild("Core"):WaitForChild("Network"))

local GameConfig = require(Shared:WaitForChild("Config"):WaitForChild("GameConfig"))
local CurrenciesConfig = require(Shared:WaitForChild("Config"):WaitForChild("CurrenciesConfig"))
local ItemsConfig = require(Shared:WaitForChild("Config"):WaitForChild("ItemsConfig"))

local EconomyService = {
	Name = "EconomyService",
	Dependencies = { "PlayerDataService" },
	OnCurrencyChanged = Signal.new(),
}

local log = Logger.new("EconomyService")
local playerDataService: any = nil
local lastClickTimestamps: { [Player]: number } = {}
local clickConn: RBXScriptConnection? = nil

function EconomyService:Init(registry: any): ()
	playerDataService = registry:Get("PlayerDataService")
	log:Info("Initialized EconomyService")
end

function EconomyService:Start(): ()
	clickConn = Network.OnServerEvent(Network.Events.RequestActionClick, function(player: Player)
		self:ProcessSimulatorClick(player)
	end)
end

function EconomyService:GetBalance(player: Player, currencyId: Types.CurrencyId): number
	local res = playerDataService:GetProfile(player)
	if not res.ok or not res.value then
		return 0
	end
	return res.value.currencies[currencyId] or 0
end

function EconomyService:CanAfford(player: Player, currencyId: Types.CurrencyId, amount: number): boolean
	if amount < 0 then
		return false
	end
	return self:GetBalance(player, currencyId) >= amount
end

function EconomyService:GetMultiplier(player: Player, currencyId: Types.CurrencyId): number
	local res = playerDataService:GetProfile(player)
	if not res.ok or not res.value then
		return 1.0
	end

	local profile: Types.PlayerProfileData = res.value
	local multiplier = 1.0 + (profile.rebirths * GameConfig.Progression.RebirthBonusMultiplierPerRebirth)

	if currencyId == "Coins" then
		for _, item in pairs(profile.inventory) do
			if item.equipped then
				local def = ItemsConfig[item.itemId]
				if def and def.coinMultiplier > 0 then
					multiplier *= def.coinMultiplier
				end
			end
		end
	end

	return multiplier
end

function EconomyService:AddCurrency(
	player: Player,
	currencyId: Types.CurrencyId,
	amount: number,
	_reason: string?
): Types.Result<number, string>
	if amount <= 0 then
		return Types.Err("INVALID_AMOUNT")
	end

	local def = CurrenciesConfig[currencyId]
	if not def then
		return Types.Err("UNKNOWN_CURRENCY")
	end

	local newBalance = 0
	local updateRes = playerDataService:UpdateProfile(player, function(profile: Types.PlayerProfileData)
		local current = profile.currencies[currencyId] or 0
		newBalance = math.min(def.maxAmount, current + amount)
		profile.currencies[currencyId] = newBalance
		if currencyId == "Coins" then
			profile.stats.totalCoinsEarned += amount
		end
		return true
	end)

	if not updateRes.ok then
		return Types.Err(updateRes.error or "UPDATE_FAILED")
	end

	self.OnCurrencyChanged:Fire(player, currencyId, newBalance, amount)
	Network.FireClient(player, Network.Events.CurrencyUpdated, currencyId, newBalance, amount)
	return Types.Ok(newBalance)
end

function EconomyService:RemoveCurrency(
	player: Player,
	currencyId: Types.CurrencyId,
	amount: number,
	_reason: string?
): Types.Result<number, string>
	if amount <= 0 then
		return Types.Err("INVALID_AMOUNT")
	end
	if not self:CanAfford(player, currencyId, amount) then
		return Types.Err("INSUFFICIENT_FUNDS")
	end

	local newBalance = 0
	local updateRes = playerDataService:UpdateProfile(player, function(profile: Types.PlayerProfileData)
		local current = profile.currencies[currencyId] or 0
		newBalance = math.max(0, current - amount)
		profile.currencies[currencyId] = newBalance
		return true
	end)

	if not updateRes.ok then
		return Types.Err(updateRes.error or "UPDATE_FAILED")
	end

	self.OnCurrencyChanged:Fire(player, currencyId, newBalance, -amount)
	Network.FireClient(player, Network.Events.CurrencyUpdated, currencyId, newBalance, -amount)
	return Types.Ok(newBalance)
end

function EconomyService:ProcessSimulatorClick(player: Player): Types.Result<number, string>
	local now = os.clock()
	local lastClick = lastClickTimestamps[player] or 0
	if (now - lastClick) < GameConfig.Simulator.ClickCooldownSeconds then
		return Types.Err("CLICK_COOLDOWN")
	end
	lastClickTimestamps[player] = now

	local gain = math.floor(GameConfig.Simulator.BaseCoinsPerClick * self:GetMultiplier(player, "Coins"))
	playerDataService:UpdateProfile(player, function(profile: Types.PlayerProfileData)
		profile.stats.totalClicks += 1
		return false
	end)

	return self:AddCurrency(player, "Coins", math.max(1, gain), "SimulatorClick")
end

function EconomyService:Shutdown(): ()
	if clickConn then
		clickConn:Disconnect()
		clickConn = nil
	end
	table.clear(lastClickTimestamps)
	log:Info("Shutdown EconomyService")
end

return EconomyService
