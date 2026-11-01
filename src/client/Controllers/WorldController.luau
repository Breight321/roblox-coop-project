--!strict
--[[
	@module WorldController
	@owner Agent 2 (anarugod)
	@description Контроллер игрового мира на клиенте: управление зонами (ZoneGateManager), экипированными предметами (ItemDisplayManager) и триггерами локаций.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Core"):WaitForChild("Types"))
local Logger = require(Shared:WaitForChild("Core"):WaitForChild("Logger"))
local Signal = require(Shared:WaitForChild("Core"):WaitForChild("Signal"))
local Network = require(Shared:WaitForChild("Core"):WaitForChild("Network"))
local ZonesConfig = require(Shared:WaitForChild("Config"):WaitForChild("ZonesConfig"))

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

local currentZoneId = "spawn_meadow"
local unlockedZonesState: { [string]: boolean } = {
	spawn_meadow = true,
}
local connections: { Signal.SignalConnection } = {}

function WorldController:Init(registry: any): ()
	uiController = registry:Get("UIController")
	audioController = registry:Get("AudioController")
	log:Info("Initialized WorldController")
end

function WorldController:Start(): ()
	self:SyncUnlockedZones(unlockedZonesState)

	table.insert(
		connections,
		uiController.OnStateUpdated:Connect(function(profile: Types.PlayerProfileData)
			self:SyncUnlockedZones(profile.unlockedZones)
			ItemDisplayManager.SyncInventory(profile.inventory)
		end)
	)

	table.insert(
		connections,
		uiController.OnProgressionUpdated:Connect(
			function(_level: number, _xp: number, _rebirths: number, unlockedZones: { [string]: boolean })
				self:SyncUnlockedZones(unlockedZones)
			end
		)
	)

	table.insert(
		connections,
		uiController.OnInventoryUpdated:Connect(function(inventory: { [string]: Types.InventoryItem })
			ItemDisplayManager.SyncInventory(inventory)
		end)
	)

	log:Info("Started WorldController")
end

function WorldController:SyncUnlockedZones(unlockedZones: { [string]: boolean }): ()
	unlockedZonesState = table.clone(unlockedZones)
	unlockedZonesState.spawn_meadow = true

	ZoneGateManager.SyncGates(unlockedZonesState, function(zoneId: string)
		self:RequestUnlockZone(zoneId)
	end)

	self.OnZonesSynced:Fire(unlockedZonesState)
end

function WorldController:RequestUnlockZone(zoneId: string): ()
	if not ZonesConfig[zoneId] then
		return
	end
	if self:IsZoneUnlocked(zoneId) then
		return
	end
	audioController:PlaySFX("ZoneUnlock")
	Network.FireServer(Network.Events.RequestUnlockZone, zoneId)
end

function WorldController:IsZoneUnlocked(zoneId: string): boolean
	return unlockedZonesState[zoneId] == true
end

function WorldController:SetCurrentZone(zoneId: string): ()
	if not ZonesConfig[zoneId] or currentZoneId == zoneId then
		return
	end
	currentZoneId = zoneId
	self.OnZoneEntered:Fire(zoneId)
end

function WorldController:GetCurrentZone(): string
	return currentZoneId
end

function WorldController:GetEquippedToolUid(): string?
	return ItemDisplayManager.GetEquippedToolUid()
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
