--!strict
--[[
	@module ChestService
	@owner Agent A (Breight321)
	@description Серверно-авторитетная система сундуков с добычей.
	Проверяет открытие зоны, уровень игрока, дистанцию, персональный кулдаун,
	защиту от повторных запросов (REQUEST_IN_PROGRESS) и минимальное число убитых мобов
	с прошлого открытия (NOT_ENOUGH_KILLS), чтобы сундуки дополняли фарм мобов, а не заменяли его.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Core"):WaitForChild("Types"))
local Logger = require(Shared:WaitForChild("Core"):WaitForChild("Logger"))
local Signal = require(Shared:WaitForChild("Core"):WaitForChild("Signal"))
local Network = require(Shared:WaitForChild("Core"):WaitForChild("Network"))
local CombatConfig = require(Shared:WaitForChild("Config"):WaitForChild("CombatConfig"))

type PlayerChestRecord = {
	lastOpenedAt: number,
	killsAtLastOpen: number,
	openCount: number,
}

local ChestService = {
	Name = "ChestService",
	Dependencies = { "PlayerDataService", "ProgressionService", "LootService", "CombatService" },
	OnChestOpened = Signal.new(),
}

local log = Logger.new("ChestService")
local playerDataService: any = nil
local lootService: any = nil
local combatService: any = nil

local openingLocks: { [any]: boolean } = {}
local connections: { RBXScriptConnection } = {}
local customTimeFn: (() -> number)? = nil

local function getNow(): number
	if customTimeFn then
		return customTimeFn()
	end
	return os.time()
end

local function isValidPlayerKey(player: any): boolean
	return player ~= nil and (typeof(player) == "Instance" or type(player) == "table")
end

local function isRealPlayer(player: any): boolean
	return typeof(player) == "Instance" and player:IsA("Player")
end

local function unwrapProfile(player: any): Types.PlayerProfileData?
	if not playerDataService then
		return nil
	end
	local res = playerDataService:GetProfile(player)
	if type(res) == "table" and res.ok ~= nil then
		if res.ok and res.value then
			return res.value
		end
		return nil
	end
	return res
end

local function getPlayerPosition(player: any, fallbackPos: Vector3): (boolean, Vector3?)
	if isRealPlayer(player) then
		local character = (player :: Player).Character
		if not character then
			return false, nil
		end
		local rootPart = character:FindFirstChild("HumanoidRootPart")
		if not rootPart or not rootPart:IsA("BasePart") then
			return false, nil
		end
		return true, rootPart.Position
	elseif type(player) == "table" then
		if player.CharacterMissing == true then
			return false, nil
		end
		if typeof(player.Position) == "Vector3" then
			return true, player.Position
		end
		return true, fallbackPos
	end
	return false, nil
end

local function ensureChestsSection(profile: Types.PlayerProfileData): { [string]: PlayerChestRecord }
	if type(profile.customData) ~= "table" then
		profile.customData = {}
	end
	local raw = profile.customData.chests
	if type(raw) ~= "table" then
		raw = {}
		profile.customData.chests = raw
	end
	return raw
end

local function ensureChestWorldMarkers(): ()
	local worldFolder = Workspace:FindFirstChild("CombatWorld") :: Folder?
	if not worldFolder then
		local newWorld = Instance.new("Folder")
		newWorld.Name = "CombatWorld"
		newWorld.Parent = Workspace
		worldFolder = newWorld
	end
	local validWorld = worldFolder :: Folder
	local chestsFolder = validWorld:FindFirstChild("Chests") :: Folder?
	if not chestsFolder then
		local newChests = Instance.new("Folder")
		newChests.Name = "Chests"
		newChests.Parent = validWorld
		chestsFolder = newChests
	end
	local validChests = chestsFolder :: Folder

	for chestId, def in pairs(CombatConfig.Chests) do
		if not validChests:FindFirstChild(chestId) then
			local part = Instance.new("Part")
			part.Name = chestId
			part.Anchored = true
			part.CanCollide = true
			part.Material = Enum.Material.Metal
			part.Color = Color3.fromRGB(230, 185, 65)
			part.Size = Vector3.new(5, 3.5, 3.5)
			part.Position = def.position + Vector3.new(0, 1.75, 0)
			part:SetAttribute("ChestId", def.id)
			part:SetAttribute("ZoneId", def.zoneId)
			part:SetAttribute("DisplayName", def.displayName)
			part:SetAttribute("MinPlayerLevel", def.minPlayerLevel)
			part:SetAttribute("RequiredPlayerLevel", def.minPlayerLevel)
			part:SetAttribute("RequiredKillsSinceLastOpen", def.requiredKillsSinceLastOpen)
			part:SetAttribute("CooldownSeconds", def.cooldownSeconds)
			part.Parent = validChests
		end
	end
end

local function buildSingleChestState(
	profile: Types.PlayerProfileData,
	chestDef: Types.ChestDef,
	totalMobKills: number,
	now: number
): Types.ChestStatePayload
	local chestsSec = ensureChestsSection(profile)
	local rec = chestsSec[chestDef.id]
	local lastOpenedAt = if rec and type(rec.lastOpenedAt) == "number" then rec.lastOpenedAt else 0
	local killsAtLastOpen = if rec and type(rec.killsAtLastOpen) == "number" then rec.killsAtLastOpen else 0
	local readyAtUnix = if lastOpenedAt > 0 then (lastOpenedAt + chestDef.cooldownSeconds) else 0
	local killsSinceLast = math.max(0, totalMobKills - killsAtLastOpen)
	local killsProgress = math.min(chestDef.requiredKillsSinceLastOpen, killsSinceLast)

	local zoneUnlocked = chestDef.zoneId == "spawn_meadow" or profile.unlockedZones[chestDef.zoneId] == true
	local levelOk = profile.level >= chestDef.minPlayerLevel
	local cooldownOk = now >= readyAtUnix
	local killsOk = killsSinceLast >= chestDef.requiredKillsSinceLastOpen

	return {
		chestId = chestDef.id,
		readyAtUnix = readyAtUnix,
		requiredKills = chestDef.requiredKillsSinceLastOpen,
		killsSinceLastOpen = killsProgress,
		isReady = zoneUnlocked and levelOk and cooldownOk and killsOk,
	}
end

local function sendChestSync(player: any): ()
	if not isRealPlayer(player) then
		return
	end
	local states = ChestService:GetChestStates(player)
	Network.FireClient(player, Network.Events.ChestStateSync, states)
end

function ChestService:Init(registry: any): ()
	playerDataService = registry:Get("PlayerDataService")
	lootService = registry:Get("LootService")
	combatService = registry:Get("CombatService")

	playerDataService:RegisterSchemaSection("chests", {})
	log:Info("Initialized.")
end

function ChestService:Start(): ()
	ensureChestWorldMarkers()

	table.insert(
		connections,
		playerDataService.OnProfileLoaded:Connect(function(player: any)
			sendChestSync(player)
		end)
	)

	table.insert(
		connections,
		playerDataService.OnProfileReleasing:Connect(function(player: any)
			openingLocks[player] = nil
		end)
	)

	if combatService and combatService.OnMobDefeated then
		table.insert(
			connections,
			combatService.OnMobDefeated:Connect(function(player: any)
				sendChestSync(player)
			end)
		)
	end

	table.insert(
		connections,
		Network.OnServerEvent(Network.Events.RequestOpenChest, function(player: Player, rawChestId: any)
			local chestId = if type(rawChestId) == "string" and #rawChestId <= 64 then rawChestId else ""
			local res = self:OpenChest(player, chestId)
			Network.FireClient(player, Network.Events.ChestResult, res)
			if res.ok then
				sendChestSync(player)
			end
		end)
	)

	log:Info("Started.")
end

function ChestService:Shutdown(): ()
	for _, conn in ipairs(connections) do
		conn:Disconnect()
	end
	table.clear(connections)
	table.clear(openingLocks)
end

function ChestService:GetChestStates(player: any): { [string]: Types.ChestStatePayload }
	local result: { [string]: Types.ChestStatePayload } = {}
	if not isValidPlayerKey(player) then
		return result
	end
	local profile = unwrapProfile(player)
	if not profile then
		return result
	end
	local combatRecord = combatService:GetPlayerCombatRecord(player)
	local now = getNow()

	for chestId, def in pairs(CombatConfig.Chests) do
		result[chestId] = buildSingleChestState(profile, def, combatRecord.totalMobKills, now)
	end

	return result
end

function ChestService:OpenChest(player: any, chestId: string): Types.ChestOpenResultPayload
	local function fail(
		code: Types.ChestErrorCode,
		msg: string,
		cId: string,
		state: Types.ChestStatePayload?
	): Types.ChestOpenResultPayload
		return {
			ok = false,
			chestId = cId,
			drops = {},
			state = state,
			errorCode = code,
			message = msg,
		}
	end

	if not isValidPlayerKey(player) then
		return fail("INVALID_PLAYER", "Некорректный игрок.", tostring(chestId or ""), nil)
	end

	local profile = unwrapProfile(player)
	if not profile then
		return fail("PROFILE_NOT_LOADED", "Профиль ещё не загружен.", tostring(chestId or ""), nil)
	end

	if type(chestId) ~= "string" or CombatConfig.Chests[chestId] == nil then
		return fail("UNKNOWN_CHEST", "Сундук не найден.", tostring(chestId or ""), nil)
	end

	local chestDef = CombatConfig.Chests[chestId]
	local combatRecord = combatService:GetPlayerCombatRecord(player)
	local now = getNow()
	local currentState = buildSingleChestState(profile, chestDef, combatRecord.totalMobKills, now)

	if openingLocks[player] == true then
		return fail("REQUEST_IN_PROGRESS", "Запрос уже обрабатывается.", chestId, currentState)
	end

	openingLocks[player] = true

	local function unlockAndReturn(payload: Types.ChestOpenResultPayload): Types.ChestOpenResultPayload
		openingLocks[player] = nil
		return payload
	end

	if chestDef.zoneId ~= "spawn_meadow" and not profile.unlockedZones[chestDef.zoneId] then
		return unlockAndReturn(fail("ZONE_LOCKED", "Зона с этим сундуком ещё не открыта.", chestId, currentState))
	end

	if profile.level < chestDef.minPlayerLevel then
		return unlockAndReturn(
			fail(
				"LEVEL_TOO_LOW",
				string.format("Требуется уровень %d для открытия сундука.", chestDef.minPlayerLevel),
				chestId,
				currentState
			)
		)
	end

	local hasPos, playerPos = getPlayerPosition(player, chestDef.position)
	if not hasPos or not playerPos then
		return unlockAndReturn(fail("CHARACTER_NOT_READY", "Персонаж не готов.", chestId, currentState))
	end

	local dist = (playerPos - chestDef.position).Magnitude
	if dist > chestDef.interactionRadius then
		return unlockAndReturn(fail("OUT_OF_RANGE", "Подойдите ближе к сундуку.", chestId, currentState))
	end

	if now < currentState.readyAtUnix then
		return unlockAndReturn(fail("CHEST_COOLDOWN", "Сундук ещё перезаряжается.", chestId, currentState))
	end

	if currentState.killsSinceLastOpen < chestDef.requiredKillsSinceLastOpen then
		return unlockAndReturn(
			fail(
				"NOT_ENOUGH_KILLS",
				string.format(
					"Победите ещё мобов (%d/%d), чтобы распечатать сундук.",
					currentState.killsSinceLastOpen,
					chestDef.requiredKillsSinceLastOpen
				),
				chestId,
				currentState
			)
		)
	end

	-- Фиксируем открытие сундука в профиле игрока
	playerDataService:UpdateProfile(player, function(p: Types.PlayerProfileData)
		local chestsSec = ensureChestsSection(p)
		local prev = chestsSec[chestId]
		local prevCount = if prev and type(prev.openCount) == "number" then prev.openCount else 0
		chestsSec[chestId] = {
			lastOpenedAt = now,
			killsAtLastOpen = combatRecord.totalMobKills,
			openCount = prevCount + 1,
		}
		return true
	end)

	local rolledDrops = lootService:RollLootTable(chestDef.lootTableId)
	local grantedDrops = lootService:GrantDrops(player, rolledDrops, "Chest:" .. chestId)

	local refreshedProfile = unwrapProfile(player) or profile
	local updatedState = buildSingleChestState(refreshedProfile, chestDef, combatRecord.totalMobKills, now)

	self.OnChestOpened:Fire(player, chestId, grantedDrops, updatedState)

	return unlockAndReturn({
		ok = true,
		chestId = chestId,
		drops = grantedDrops,
		state = updatedState,
		errorCode = nil,
		message = string.format("Сундук «%s» открыт!", chestDef.displayName),
	})
end

function ChestService:SetClockForTests(clockFn: (() -> number)?): ()
	customTimeFn = clockFn
end

return ChestService
