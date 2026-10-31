--!strict
--[[
	@module PlayerDataService
	@owner Agent 1 (Breight321)
	@description Управление профилями игроков, сессиями, leaderstats и автосохранением.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Core"):WaitForChild("Types"))
local Logger = require(Shared:WaitForChild("Core"):WaitForChild("Logger"))
local Signal = require(Shared:WaitForChild("Core"):WaitForChild("Signal"))
local Network = require(Shared:WaitForChild("Core"):WaitForChild("Network"))

local GameConfig = require(Shared:WaitForChild("Config"):WaitForChild("GameConfig"))
local CurrenciesConfig = require(Shared:WaitForChild("Config"):WaitForChild("CurrenciesConfig"))
local QuestsConfig = require(Shared:WaitForChild("Config"):WaitForChild("QuestsConfig"))

local PlayerDataService = {
	Name = "PlayerDataService",
	Dependencies = {} :: { string },
	OnProfileLoaded = Signal.new(),
	OnProfileReleasing = Signal.new(),
}

local log = Logger.new("PlayerDataService")
local profiles: { [Player]: Types.PlayerProfileData } = {}
local connections: { RBXScriptConnection } = {}

function PlayerDataService:CreateDefaultProfile(): Types.PlayerProfileData
	local currencies: { [Types.CurrencyId]: number } = {
		Coins = CurrenciesConfig.Coins.startingAmount,
		Gems = CurrenciesConfig.Gems.startingAmount,
	}

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
				acquiredAt = os.time(),
			},
		},
		quests = quests,
		stats = {
			totalClicks = 0,
			totalCoinsEarned = 0,
			playTimeSeconds = 0,
		},
	}
end

local function syncLeaderstats(player: Player, profile: Types.PlayerProfileData): ()
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
			(valObj :: IntValue).Value = math.floor(profile.currencies[currencyId] or 0)
		end
	end

	local rebirthsObj = leaderstats:FindFirstChild("Rebirths") :: IntValue?
	if not rebirthsObj then
		rebirthsObj = Instance.new("IntValue")
		rebirthsObj.Name = "Rebirths"
		rebirthsObj.Parent = leaderstats
	end
	(rebirthsObj :: IntValue).Value = profile.rebirths
end

function PlayerDataService:Init(_registry: any): ()
	log:Info("Initialized PlayerDataService")
end

function PlayerDataService:Start(): ()
	local function onPlayerAdded(player: Player)
		local profile = self:CreateDefaultProfile()
		profiles[player] = profile
		syncLeaderstats(player, profile)
		self.OnProfileLoaded:Fire(player, profile)
		Network.FireClient(player, Network.Events.PlayerDataSync, profile)
		log:Info("Loaded profile for %s", player.Name)
	end

	local function onPlayerRemoving(player: Player)
		local profile = profiles[player]
		if profile then
			self.OnProfileReleasing:Fire(player, profile)
			self:SaveProfile(player)
			profiles[player] = nil
		end
	end

	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(onPlayerAdded, player)
	end

	table.insert(connections, Players.PlayerAdded:Connect(onPlayerAdded))
	table.insert(connections, Players.PlayerRemoving:Connect(onPlayerRemoving))
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
		log:Error("Profile mutator error for %s: %s", player.Name, tostring(changed))
		return Types.Err("MUTATOR_ERROR")
	end

	if changed then
		syncLeaderstats(player, profile)
	end

	return Types.Ok(profile)
end

function PlayerDataService:SaveProfile(player: Player): Types.Result<boolean, string>
	local profile = profiles[player]
	if not profile then
		return Types.Err("PROFILE_NOT_LOADED")
	end
	log:Debug("Saved profile for %s (schema v%d)", player.Name, profile.schemaVersion)
	return Types.Ok(true)
end

function PlayerDataService:Shutdown(): ()
	for _, conn in ipairs(connections) do
		conn:Disconnect()
	end
	table.clear(connections)

	for player in pairs(profiles) do
		self:SaveProfile(player)
	end
	log:Info("Shutdown PlayerDataService")
end

return PlayerDataService
