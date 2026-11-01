--!strict
--[[
	@module WorldController
	@owner Agent B (anarugod)
	@description Универсальный контроллер игрового мира и зон: синхронизация открытых локаций, кастомные валидаторы доступа, барьеры зон и визуал экипировки.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Core"):WaitForChild("Types"))
local Logger = require(Shared:WaitForChild("Core"):WaitForChild("Logger"))
local Signal = require(Shared:WaitForChild("Core"):WaitForChild("Signal"))
local Network = require(Shared:WaitForChild("Core"):WaitForChild("Network"))
local ZonesConfig = require(Shared:WaitForChild("Config"):WaitForChild("ZonesConfig"))

local WorldTypes = require(script:WaitForChild("Types"))
local WorldConfig = require(script:WaitForChild("Config"))

local WorldFolder = script.Parent.Parent:WaitForChild("World")
local ZoneGateManager = require(WorldFolder:WaitForChild("Zones"):WaitForChild("ZoneGateManager"))
local ItemDisplayManager = require(WorldFolder:WaitForChild("Items"):WaitForChild("ItemDisplayManager"))

local WorldController = {
	Name = "WorldController",
	Dependencies = { "UIController", "AudioController" },
	OnZoneEntered = Signal.new(),
	OnZonesSynced = Signal.new(),
}

local log = Logger.new("WorldController")
local uiController: any = nil
local audioController: any = nil

local currentZoneId = WorldConfig.DefaultStartingZoneId
local unlockedZonesState: { [string]: boolean } = {
	[WorldConfig.DefaultStartingZoneId] = true,
}
local customUnlockValidators: { [string]: WorldTypes.ZoneUnlockValidator } = {}
local connections: { Signal.SignalConnection } = {}

function WorldController:Init(registry: any): ()
	uiController = registry:TryGet("UIController")
	audioController = registry:TryGet("AudioController")
	log:Info("Initialized WorldController")
end

function WorldController:Start(): ()
	self:SyncUnlockedZones(unlockedZonesState)

	if uiController then
		table.insert(
			connections,
			uiController.OnStateUpdated:Connect(function(profile: Types.PlayerProfileData)
				if profile.unlockedZones then
					self:SyncUnlockedZones(profile.unlockedZones)
				end
				if profile.inventory then
					ItemDisplayManager.SyncInventory(profile.inventory)
				end
			end)
		)

		table.insert(
			connections,
			uiController.OnProgressionUpdated:Connect(
				function(_level: number, _xp: number, _rebirths: number, unlockedZones: { [string]: boolean })
					if unlockedZones then
						self:SyncUnlockedZones(unlockedZones)
					end
				end
			)
		)

		table.insert(
			connections,
			uiController.OnInventoryUpdated:Connect(function(inventory: { [string]: Types.InventoryItem })
				ItemDisplayManager.SyncInventory(inventory)
			end)
		)
	end

	log:Info("Started WorldController")
end

function WorldController:RegisterUnlockValidator(validatorId: string, fn: WorldTypes.ZoneUnlockValidator): ()
	if type(validatorId) == "string" and #validatorId > 0 and type(fn) == "function" then
		customUnlockValidators[validatorId] = fn
	end
end

function WorldController:UnregisterUnlockValidator(validatorId: string): ()
	customUnlockValidators[validatorId] = nil
end

function WorldController:CanRequestUnlockZone(zoneId: string): Types.Result<boolean, string>
	local zoneDef = ZonesConfig[zoneId]
	if not zoneDef then
		return Types.Err("UNKNOWN_ZONE")
	end
	if self:IsZoneUnlocked(zoneId) then
		return Types.Err("ZONE_ALREADY_UNLOCKED")
	end

	for _, validator in pairs(customUnlockValidators) do
		local ok, errReason = validator(zoneId, zoneDef)
		if not ok then
			return Types.Err(errReason or "CUSTOM_REQUIREMENT_FAILED")
		end
	end

	return Types.Ok(true)
end

function WorldController:SyncUnlockedZones(unlockedZones: { [string]: boolean }): ()
	unlockedZonesState = table.clone(unlockedZones)
	unlockedZonesState[WorldConfig.DefaultStartingZoneId] = true

	if WorldConfig.AutoSyncGatesToWorkspace then
		ZoneGateManager.SyncGates(unlockedZonesState, function(zoneId: string)
			self:RequestUnlockZone(zoneId)
		end)
	end

	self.OnZonesSynced:Fire(unlockedZonesState)
end

function WorldController:RequestUnlockZone(zoneId: string): Types.Result<boolean, string>
	local canRes = self:CanRequestUnlockZone(zoneId)
	if not canRes.ok then
		return canRes
	end
	if audioController then
		audioController:PlaySFX("ZoneUnlock")
	end
	Network.FireServer(Network.Events.RequestUnlockZone, zoneId)
	return Types.Ok(true)
end

function WorldController:IsZoneUnlocked(zoneId: string): boolean
	return unlockedZonesState[zoneId] == true
end

function WorldController:SetCurrentZone(zoneId: string): boolean
	if not ZonesConfig[zoneId] or currentZoneId == zoneId then
		return false
	end
	currentZoneId = zoneId
	self.OnZoneEntered:Fire(zoneId)
	return true
end

function WorldController:GetCurrentZone(): string
	return currentZoneId
end

function WorldController:GetZoneDef(zoneId: string?): Types.ZoneDef?
	local targetId = zoneId or currentZoneId
	return ZonesConfig[targetId]
end

function WorldController:GetEquippedToolUid(): string?
	return ItemDisplayManager.GetEquippedToolUid()
end

function WorldController:GetEquippedPetUids(): { string }
	return ItemDisplayManager.GetEquippedPetUids()
end

function WorldController:ResetStateForTests(): ()
	currentZoneId = WorldConfig.DefaultStartingZoneId
	unlockedZonesState = {
		[WorldConfig.DefaultStartingZoneId] = true,
	}
	table.clear(customUnlockValidators)
end

function WorldController:Shutdown(): ()
	for _, conn in ipairs(connections) do
		conn:Disconnect()
	end
	table.clear(connections)
	ZoneGateManager.Cleanup()
	ItemDisplayManager.Cleanup()
	log:Info("Shutdown WorldController")
end

return WorldController
