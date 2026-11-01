--!strict
--[[
	@module WorldController
	@owner Agent B (anarugod)
	@description Универсальный контроллер игрового мира и зон: синхронизация открытых локаций,
	кастомные валидаторы доступа, барьеры зон (ZoneGateManager), отображение мобов и сундуков
	по зонам + портал добровольной PvP-арены (WorldMobChestManager), общая зона добычи
	(ExpeditionZoneManager) и визуал экипировки (ItemDisplayManager).
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
local WorldMobChestManager = require(WorldFolder:WaitForChild("WorldMobChestManager"))

local ExpeditionZoneManagerModule = WorldFolder:FindFirstChild("ExpeditionZoneManager")
local ExpeditionZoneManager: any = if ExpeditionZoneManagerModule and ExpeditionZoneManagerModule:IsA("ModuleScript")
	then require(ExpeditionZoneManagerModule)
	else nil

local WorldController = {
	Name = "WorldController",
	Dependencies = { "UIController", "AudioController", "CombatController" },
	OnZoneEntered = Signal.new(),
	OnZonesSynced = Signal.new(),
}

local log = Logger.new("WorldController")
local uiController: any = nil
local audioController: any = nil
local expeditionController: any = nil
local combatController: any = nil

local currentZoneId = WorldConfig.DefaultStartingZoneId
local unlockedZonesState: { [string]: boolean } = {
	[WorldConfig.DefaultStartingZoneId] = true,
}
local customUnlockValidators: { [string]: WorldTypes.ZoneUnlockValidator } = {}
local connections: { Signal.SignalConnection } = {}

function WorldController:Init(registry: any): ()
	uiController = registry:TryGet("UIController")
	audioController = registry:TryGet("AudioController")
	combatController = registry:TryGet("CombatController")
	expeditionController = registry:TryGet("ExpeditionController")
	log:Info("Initialized WorldController")
end

function WorldController:Start(): ()
	self:SyncUnlockedZones(unlockedZonesState)

	if WorldConfig.AutoSyncGatesToWorkspace then
		WorldMobChestManager.EnsureWorld({
			OnMobAttackTriggered = function(mobInstanceId: string)
				if combatController then
					combatController:SelectMobTarget(mobInstanceId)
					combatController:RequestAttackMob(mobInstanceId, self:GetEquippedToolUid())
				end
			end,
			OnChestOpenTriggered = function(chestId: string)
				if combatController then
					combatController:RequestOpenChest(chestId)
				end
				if uiController then
					uiController:OpenScreen("Chests")
				end
			end,
			OnArenaPortalTriggered = function()
				if combatController then
					local st = combatController:GetArenaState()
					if st.isSafeZone then
						combatController:RequestEnterArena()
					else
						combatController:RequestLeaveArena()
					end
				end
				if uiController then
					uiController:OpenScreen("Arena")
				end
			end,
		})

		if ExpeditionZoneManager then
			ExpeditionZoneManager.EnsureWorld({
				OnCollectNodeTriggered = function(nodeId: string)
					if expeditionController then
						expeditionController:RequestCollect(nodeId, self:GetEquippedToolUid())
					end
				end,
				OnDepositStationTriggered = function(stationId: string)
					if expeditionController then
						expeditionController:RequestDeposit(stationId)
					end
				end,
			})
		end
	end

	if combatController then
		WorldMobChestManager.SyncMobs(combatController:GetZoneMobs())
		WorldMobChestManager.SyncChests(combatController:GetZoneChests())

		table.insert(
			connections,
			combatController.OnStateChanged:Connect(function()
				WorldMobChestManager.SyncMobs(combatController:GetZoneMobs())
				WorldMobChestManager.SyncChests(combatController:GetZoneChests())
			end)
		)

		table.insert(
			connections,
			combatController.OnCombatHitFeedback:Connect(function(feedback: any)
				local uid = type(feedback) == "table" and (feedback.mobUid or feedback.mobInstanceId)
				if type(uid) == "string" then
					WorldMobChestManager.PlayMobHitEffect(
						uid,
						feedback.damageDealt or 0,
						feedback.defeated == true
					)
				end
			end)
		)
	end

	if expeditionController and ExpeditionZoneManager then
		ExpeditionZoneManager.SyncBagAndDepositState(expeditionController:GetBagState())
		ExpeditionZoneManager.SyncTeamMonument(expeditionController:GetTeamProgress())

		table.insert(
			connections,
			expeditionController.OnStateChanged:Connect(function()
				ExpeditionZoneManager.SyncBagAndDepositState(expeditionController:GetBagState())
				ExpeditionZoneManager.SyncTeamMonument(expeditionController:GetTeamProgress())
			end)
		)

		table.insert(
			connections,
			expeditionController.OnCollectFeedback:Connect(function(nodeId: string)
				ExpeditionZoneManager.PlayNodePulse(nodeId)
			end)
		)

		table.insert(
			connections,
			expeditionController.OnStageUnlocked:Connect(function(teamVm: any)
				if type(teamVm) == "table" and type(teamVm.stageId) == "string" then
					local updated = table.clone(unlockedZonesState)
					updated[teamVm.stageId] = true
					self:SyncUnlockedZones(updated)
				end
			end)
		)
	end

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

function WorldController:GetEquippedBodyParts(): { [string]: string }
	return ItemDisplayManager.GetEquippedBodyParts()
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
	WorldMobChestManager.Cleanup()
	if ExpeditionZoneManager then
		ExpeditionZoneManager.Cleanup()
	end
	log:Info("Shutdown WorldController")
end

return WorldController
