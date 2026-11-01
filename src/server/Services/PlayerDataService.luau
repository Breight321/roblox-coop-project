--!strict
--[[
	@module PlayerDataService (Module 3: Data)
	@owner Agent A (Breight321)
	@description Универсальный сервис профилей игроков: Session Locking, миграции, настраиваемые секции схемы (RegisterSchemaSection) и автосохранение.
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Core"):WaitForChild("Types"))
local Logger = require(Shared:WaitForChild("Core"):WaitForChild("Logger"))
local Signal = require(Shared:WaitForChild("Core"):WaitForChild("Signal"))
local Network = require(Shared:WaitForChild("Core"):WaitForChild("Network"))

local GameConfig = require(Shared:WaitForChild("Config"):WaitForChild("GameConfig"))
local CurrenciesConfig = require(Shared:WaitForChild("Config"):WaitForChild("CurrenciesConfig"))
local QuestsConfig = require(Shared:WaitForChild("Config"):WaitForChild("QuestsConfig"))

local SESSION_LOCK_TIMEOUT_SECONDS = 300

local PlayerDataService = {
	Name = "PlayerDataService",
	Dependencies = {} :: { string },
	OnProfileLoaded = Signal.new(),
	OnProfileReleasing = Signal.new(),
}

local log = Logger.new("PlayerDataService")
local profiles: { [any]: Types.PlayerProfileData } = {}
local dirtyProfiles: { [any]: boolean } = {}
local inMemoryStore: { [string]: any } = {}
local customSchemaSections: { [string]: any } = {}
local customMigrations: { [number]: (rawProfile: any) -> any } = {}
local connections: { RBXScriptConnection } = {}
local autoSaveThread: thread? = nil
local liveDataStore: DataStore? = nil
local useMockStore = true

local function deepCopy(val: any): any
	if type(val) ~= "table" then
		return val
	end
	local copy = {}
	for k, v in pairs(val) do
		copy[deepCopy(k)] = deepCopy(v)
	end
	return copy
end

local function isRealPlayer(player: any): boolean
	return typeof(player) == "Instance" and player:IsA("Player")
end

local function getStoreKey(player: any): string
	if isRealPlayer(player) then
		return "Player_" .. tostring(player.UserId)
	elseif type(player) == "table" and type(player.UserId) == "number" then
		return "TestPlayer_" .. tostring(player.UserId)
	end
	return "UnknownPlayer"
end

function PlayerDataService:RegisterSchemaSection(sectionKey: string, defaultValue: any): ()
	assert(type(sectionKey) == "string" and #sectionKey > 0, "sectionKey must be a non-empty string")
	customSchemaSections[sectionKey] = deepCopy(defaultValue)
end

function PlayerDataService:RegisterMigration(fromVersion: number, migrateFn: (rawProfile: any) -> any): ()
	assert(type(fromVersion) == "number" and fromVersion >= 1, "fromVersion must be >= 1")
	assert(type(migrateFn) == "function", "migrateFn must be a function")
	customMigrations[fromVersion] = migrateFn
end

function PlayerDataService:CreateDefaultProfile(): Types.PlayerProfileData
	local currencies: { [Types.CurrencyId]: number } = {}
	for currId, def in pairs(CurrenciesConfig) do
		currencies[currId] = def.startingAmount
	end

	local quests: { [string]: Types.QuestState } = {}
	for questId, def in pairs(QuestsConfig) do
		quests[questId] = {
			questId = questId,
			progress = 0,
			target = def.targetAmount,
			completed = false,
			claimed = false,
		}
	end

	local customData: { [string]: any } = {}
	for key, defaultVal in pairs(customSchemaSections) do
		customData[key] = deepCopy(defaultVal)
	end

	return {
		schemaVersion = GameConfig.DataSchemaVersion,
		currencies = currencies,
		rebirths = 0,
		level = 1,
		xp = 0,
		unlockedZones = {
			spawn_meadow = true,
		},
		inventory = {
			starter_wand_default = {
				uid = "starter_wand_default",
				itemId = "starter_wand",
				category = "Tool",
				equipped = true,
				level = 1,
				quantity = 1,
				acquiredAt = os.time(),
			},
		},
		quests = quests,
		stats = {
			totalClicks = 0,
			totalCoinsEarned = 0,
			playTimeSeconds = 0,
		},
		customData = customData,
	}
end

function PlayerDataService:ReconcileAndSanitize(rawData: any): Types.PlayerProfileData
	local defaultProfile = self:CreateDefaultProfile()
	if type(rawData) ~= "table" then
		return defaultProfile
	end

	-- Run registered migrations if schemaVersion is older
	local rawVersion = if type(rawData.schemaVersion) == "number" then rawData.schemaVersion else 1
	while rawVersion < GameConfig.DataSchemaVersion do
		local migrateFn = customMigrations[rawVersion]
		if migrateFn then
			local ok, migrated = pcall(migrateFn, rawData)
			if ok and type(migrated) == "table" then
				rawData = migrated
			end
		end
		rawVersion += 1
	end

	if type(rawData.currencies) == "table" then
		for currId, val in pairs(rawData.currencies) do
			if type(currId) == "string" and type(val) == "number" and val == val and val >= 0 then
				local def = CurrenciesConfig[currId]
				local maxCap = if def then def.maxAmount else 1e15
				defaultProfile.currencies[currId] = math.min(maxCap, math.floor(val))
			end
		end
	end

	if type(rawData.rebirths) == "number" and rawData.rebirths == rawData.rebirths and rawData.rebirths >= 0 then
		defaultProfile.rebirths = math.floor(rawData.rebirths)
	end
	if type(rawData.level) == "number" and rawData.level == rawData.level and rawData.level >= 1 then
		defaultProfile.level = math.floor(rawData.level)
	end
	if type(rawData.xp) == "number" and rawData.xp == rawData.xp and rawData.xp >= 0 then
		defaultProfile.xp = math.floor(rawData.xp)
	end

	if type(rawData.unlockedZones) == "table" then
		for zoneId, unlocked in pairs(rawData.unlockedZones) do
			if type(zoneId) == "string" and unlocked == true then
				defaultProfile.unlockedZones[zoneId] = true
			end
		end
	end

	if type(rawData.inventory) == "table" then
		for uid, item in pairs(rawData.inventory) do
			if type(uid) == "string" and type(item) == "table" and type(item.itemId) == "string" then
				defaultProfile.inventory[uid] = {
					uid = uid,
					itemId = item.itemId,
					category = item.category or "Tool",
					equipped = item.equipped == true,
					level = if type(item.level) == "number" then math.max(1, math.floor(item.level)) else 1,
					quantity = if type(item.quantity) == "number" then math.max(1, math.floor(item.quantity)) else 1,
					acquiredAt = if type(item.acquiredAt) == "number" then item.acquiredAt else os.time(),
					metadata = if type(item.metadata) == "table" then deepCopy(item.metadata) else nil,
				}
			end
		end
	end

	if type(rawData.quests) == "table" then
		for questId, qState in pairs(rawData.quests) do
			if defaultProfile.quests[questId] and type(qState) == "table" then
				local target = defaultProfile.quests[questId].target
				local progress = if type(qState.progress) == "number" then math.clamp(math.floor(qState.progress), 0, target) else 0
				defaultProfile.quests[questId] = {
					questId = questId,
					progress = progress,
					target = target,
					completed = (qState.completed == true) or (progress >= target),
					claimed = qState.claimed == true,
				}
			end
		end
	end

	if type(rawData.stats) == "table" then
		for statKey, statVal in pairs(rawData.stats) do
			if type(statKey) == "string" and type(statVal) == "number" and statVal == statVal and statVal >= 0 then
				defaultProfile.stats[statKey] = math.floor(statVal)
			end
		end
	end

	if type(rawData.customData) == "table" and defaultProfile.customData then
		for key, val in pairs(rawData.customData) do
			if type(key) == "string" then
				defaultProfile.customData[key] = deepCopy(val)
			end
		end
	end

	defaultProfile.schemaVersion = GameConfig.DataSchemaVersion
	return defaultProfile
end

local function syncLeaderstats(player: any, profile: Types.PlayerProfileData): ()
	if not isRealPlayer(player) then
		return
	end

	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then
		leaderstats = Instance.new("Folder")
		leaderstats.Name = "leaderstats"
		leaderstats.Parent = player
	end

	for currencyId, def in pairs(CurrenciesConfig) do
		if def.showInLeaderstats then
			local valObj = leaderstats:FindFirstChild(def.displayName) :: IntValue?
			if not valObj then
				valObj = Instance.new("IntValue")
				valObj.Name = def.displayName
				valObj.Parent = leaderstats
			end
			local intVal = valObj :: IntValue; intVal.Value = math.floor(profile.currencies[currencyId] or 0)
		end
	end

	local rebirthsObj = leaderstats:FindFirstChild("Rebirths") :: IntValue?
	if not rebirthsObj then
		rebirthsObj = Instance.new("IntValue")
		rebirthsObj.Name = "Rebirths"
		rebirthsObj.Parent = leaderstats
	end
	local intReb = rebirthsObj :: IntValue; intReb.Value = profile.rebirths
end

function PlayerDataService:Init(_registry: any): ()
	if not RunService:IsStudio() or game.PlaceId > 0 then
		local ok, ds = pcall(function()
			return DataStoreService:GetDataStore(GameConfig.DataStoreName)
		end)
		if ok and ds then
			liveDataStore = ds
			useMockStore = false
		else
			useMockStore = true
			log:Warn("DataStore unavailable in current environment; using safe InMemoryStore fallback.")
		end
	else
		useMockStore = true
		log:Info("Running in unpublished Studio place; using safe InMemoryStore fallback.")
	end
	log:Info("Initialized universal PlayerDataService")
end

function PlayerDataService:_loadFromStore(player: any): Types.PlayerProfileData
	local key = getStoreKey(player)
	local now = os.time()
	local currentJobId = if #game.JobId > 0 then game.JobId else "StudioSession"

	if useMockStore or not liveDataStore then
		local existingEnvelope = inMemoryStore[key]
		local reconciled = self:ReconcileAndSanitize(if existingEnvelope then existingEnvelope.data else nil)
		inMemoryStore[key] = {
			meta = {
				sessionJobId = currentJobId,
				sessionLockTimestamp = now,
				updatedAt = now,
				saveCount = if existingEnvelope and existingEnvelope.meta then (existingEnvelope.meta.saveCount + 1) else 1,
			},
			data = reconciled,
		}
		return reconciled
	end

	local loadedProfile: Types.PlayerProfileData? = nil
	for attempt = 1, 3 do
		local ok, err = pcall(function()
			local ds = liveDataStore :: DataStore; ds:UpdateAsync(key, function(oldEnvelope: any)
				if type(oldEnvelope) == "table" and type(oldEnvelope.meta) == "table" then
					local ownerJob = oldEnvelope.meta.sessionJobId
					local lockTime = oldEnvelope.meta.sessionLockTimestamp or 0
					if ownerJob ~= nil and ownerJob ~= currentJobId and (now - lockTime) < SESSION_LOCK_TIMEOUT_SECONDS then
						return nil
					end
				end

				local rawData = if type(oldEnvelope) == "table" and oldEnvelope.data then oldEnvelope.data else oldEnvelope
				local reconciled = self:ReconcileAndSanitize(rawData)
				loadedProfile = reconciled

				local prevSaves = if type(oldEnvelope) == "table" and type(oldEnvelope.meta) == "table"
					then (oldEnvelope.meta.saveCount or 0)
					else 0

				return {
					meta = {
						sessionJobId = currentJobId,
						sessionLockTimestamp = now,
						updatedAt = now,
						saveCount = prevSaves + 1,
					},
					data = reconciled,
				}
			end)
		end)

		if ok and loadedProfile then
			return loadedProfile
		end
		log:Warn("DataStore load attempt %d failed for %s: %s", attempt, key, tostring(err))
		task.wait(0.5 * attempt)
	end

	return self:CreateDefaultProfile()
end

function PlayerDataService:Start(): ()
	local function onPlayerAdded(player: Player)
		local profile = self:_loadFromStore(player)
		profiles[player] = profile
		dirtyProfiles[player] = false
		syncLeaderstats(player, profile)
		self.OnProfileLoaded:Fire(player, profile)
		Network.FireClient(player, Network.Events.PlayerDataSync, profile)
		task.delay(0.5, function()
			if profiles[player] then
				Network.FireClient(player, Network.Events.PlayerDataSync, profiles[player])
			end
		end)
		log:Info("Loaded profile for %s", player.Name)
	end

	local function onPlayerRemoving(player: Player)
		local profile = profiles[player]
		if profile then
			self.OnProfileReleasing:Fire(player, profile)
			self:SaveProfile(player, true)
			profiles[player] = nil
			dirtyProfiles[player] = nil
		end
	end

	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(onPlayerAdded, player)
	end

	table.insert(connections, Players.PlayerAdded:Connect(onPlayerAdded))
	table.insert(connections, Players.PlayerRemoving:Connect(onPlayerRemoving))

	autoSaveThread = task.spawn(function()
		while true do
			task.wait(GameConfig.AutoSaveIntervalSeconds)
			for player, isDirty in pairs(dirtyProfiles) do
				if isDirty and profiles[player] then
					self:SaveProfile(player, false)
				end
			end
		end
	end)
end

function PlayerDataService:CreateSessionForTest(mockPlayer: any): Types.PlayerProfileData
	local profile = self:CreateDefaultProfile()
	profiles[mockPlayer] = profile
	dirtyProfiles[mockPlayer] = false
	return profile
end

function PlayerDataService:RemoveSessionForTest(mockPlayer: any): ()
	profiles[mockPlayer] = nil
	dirtyProfiles[mockPlayer] = nil
end

function PlayerDataService:GetProfile(player: Player): Types.Result<Types.PlayerProfileData, string>
	local profile = profiles[player]
	if not profile then
		return Types.Err("PROFILE_NOT_LOADED")
	end
	return Types.Ok(profile)
end

function PlayerDataService:UpdateProfile(
	player: Player,
	mutator: (Types.PlayerProfileData) -> boolean
): Types.Result<Types.PlayerProfileData, string>
	local profile = profiles[player]
	if not profile then
		return Types.Err("PROFILE_NOT_LOADED")
	end

	local ok, changed = pcall(mutator, profile)
	if not ok then
		log:Error("Profile mutator error for %s: %s", tostring(player), tostring(changed))
		return Types.Err("MUTATOR_ERROR")
	end

	if changed then
		dirtyProfiles[player] = true
		syncLeaderstats(player, profile)
	end

	return Types.Ok(profile)
end

function PlayerDataService:SaveProfile(player: Player, releaseLock: boolean?): Types.Result<boolean, string>
	local profile = profiles[player]
	if not profile then
		return Types.Err("PROFILE_NOT_LOADED")
	end

	local key = getStoreKey(player)
	local now = os.time()
	local currentJobId = if #game.JobId > 0 then game.JobId else "StudioSession"
	local nextJobId: string? = if releaseLock then nil else currentJobId

	if useMockStore or not liveDataStore then
		inMemoryStore[key] = {
			meta = {
				sessionJobId = nextJobId,
				sessionLockTimestamp = now,
				updatedAt = now,
				saveCount = 1,
			},
			data = profile,
		}
		dirtyProfiles[player] = false
		return Types.Ok(true)
	end

	local ok, err = pcall(function()
		local ds = liveDataStore :: DataStore; ds:UpdateAsync(key, function(oldEnvelope: any)
			local prevSaves = if type(oldEnvelope) == "table" and type(oldEnvelope.meta) == "table"
				then (oldEnvelope.meta.saveCount or 0)
				else 0
			return {
				meta = {
					sessionJobId = nextJobId,
					sessionLockTimestamp = now,
					updatedAt = now,
					saveCount = prevSaves + 1,
				},
				data = profile,
			}
		end)
	end)

	if not ok then
		log:Warn("Failed to save profile for %s: %s", key, tostring(err))
		return Types.Err("DATASTORE_SAVE_FAILED")
	end

	dirtyProfiles[player] = false
	return Types.Ok(true)
end

function PlayerDataService:Shutdown(): ()
	if autoSaveThread then
		task.cancel(autoSaveThread)
		autoSaveThread = nil
	end

	for _, conn in ipairs(connections) do
		conn:Disconnect()
	end
	table.clear(connections)

	for player in pairs(profiles) do
		self:SaveProfile(player, true)
	end
	log:Info("Shutdown PlayerDataService")
end

return PlayerDataService
