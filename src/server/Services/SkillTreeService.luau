--!strict
--[[
	@module SkillTreeService
	@owner Agent A (Breight321)
	@description Серверно-авторитетное дерево пассивных навыков (ветки Damage, Defense, Mobility).
	Проверяет очки навыков, уровень игрока и предварительные узлы (requires), сохраняя прогресс в профиле игрока.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Core"):WaitForChild("Types"))
local Logger = require(Shared:WaitForChild("Core"):WaitForChild("Logger"))
local Signal = require(Shared:WaitForChild("Core"):WaitForChild("Signal"))
local Network = require(Shared:WaitForChild("Core"):WaitForChild("Network"))
local SkillTreeConfig = require(Shared:WaitForChild("Config"):WaitForChild("SkillTreeConfig"))

local SkillTreeService = {
	Name = "SkillTreeService",
	Dependencies = { "PlayerDataService", "ProgressionService" },
	OnSkillUnlocked = Signal.new(),
}

local log = Logger.new("SkillTreeService")
local playerDataService: any = nil
local progressionService: any = nil
local connections: { RBXScriptConnection } = {}

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

local function createDefaultSkillData(): { unlocked: { [string]: boolean }, earnedPoints: number }
	return {
		unlocked = {},
		earnedPoints = SkillTreeConfig.StartingPoints,
	}
end

local function ensureSkillSection(profile: Types.PlayerProfileData): { unlocked: { [string]: boolean }, earnedPoints: number }
	if type(profile.customData) ~= "table" then
		profile.customData = {}
	end
	local raw = profile.customData.skillTree
	if type(raw) ~= "table" then
		local def = createDefaultSkillData()
		profile.customData.skillTree = def
		raw = def
	end
	if type(raw.unlocked) ~= "table" then
		raw.unlocked = {}
	end
	local levelPoints = SkillTreeConfig.StartingPoints + math.max(0, (profile.level - 1) * SkillTreeConfig.PointsPerLevel)
	if type(raw.earnedPoints) ~= "number" or raw.earnedPoints < levelPoints then
		raw.earnedPoints = levelPoints
	end
	return raw
end

local function calculateSpentPoints(unlocked: { [string]: boolean }): number
	local spent = 0
	for skillId, isUnlocked in pairs(unlocked) do
		if isUnlocked then
			local node = SkillTreeConfig.Nodes[skillId]
			if node then
				spent += node.cost
			end
		end
	end
	return spent
end

local function buildStatePayload(profile: Types.PlayerProfileData): Types.SkillTreeStatePayload
	local section = ensureSkillSection(profile)
	local unlockedCopy: { [string]: boolean } = {}
	for k, v in pairs(section.unlocked) do
		if v == true then
			unlockedCopy[k] = true
		end
	end
	local spent = calculateSpentPoints(unlockedCopy)
	local available = math.max(0, section.earnedPoints - spent)
	return {
		unlocked = unlockedCopy,
		earnedPoints = section.earnedPoints,
		spentPoints = spent,
		availablePoints = available,
	}
end

local function sendStateSync(player: any, state: Types.SkillTreeStatePayload): ()
	if not isRealPlayer(player) then
		return
	end
	Network.FireClient(player, Network.Events.SkillTreeSync, state)
end

local function sendUnlockResult(player: any, result: Types.SkillUnlockResultPayload): ()
	if not isRealPlayer(player) then
		return
	end
	Network.FireClient(player, Network.Events.SkillUnlockResult, result)
end

function SkillTreeService:Init(registry: any): ()
	playerDataService = registry:Get("PlayerDataService")
	progressionService = registry:Get("ProgressionService")
	playerDataService:RegisterSchemaSection("skillTree", createDefaultSkillData())
	log:Info("Initialized.")
end

function SkillTreeService:Start(): ()
	table.insert(
		connections,
		playerDataService.OnProfileLoaded:Connect(function(player: any, profile: Types.PlayerProfileData)
			local state = buildStatePayload(profile)
			sendStateSync(player, state)
		end)
	)

	if progressionService and progressionService.OnLevelUp then
		table.insert(
			connections,
			progressionService.OnLevelUp:Connect(function(player: any, newLevel: number, oldLevel: number)
				local gainedLevels = math.max(0, newLevel - oldLevel)
				if gainedLevels <= 0 then
					return
				end
				playerDataService:UpdateProfile(player, function(p: Types.PlayerProfileData)
					local section = ensureSkillSection(p)
					local expectedMin = SkillTreeConfig.StartingPoints + math.max(0, (p.level - 1) * SkillTreeConfig.PointsPerLevel)
					if section.earnedPoints < expectedMin then
						section.earnedPoints = expectedMin
					end
					return true
				end)
				local state = self:GetState(player)
				if state then
					sendStateSync(player, state)
				end
			end)
		)
	end

	table.insert(
		connections,
		Network.OnServerEvent(Network.Events.RequestUnlockSkill, function(player: Player, skillId: any)
			local cleanId = if type(skillId) == "string" then skillId else ""
			local res = self:UnlockSkill(player, cleanId)
			sendUnlockResult(player, res)
			if res.ok then
				sendStateSync(player, res.state)
			end
		end)
	)

	log:Info("Started.")
end

function SkillTreeService:Shutdown(): ()
	for _, conn in ipairs(connections) do
		conn:Disconnect()
	end
	table.clear(connections)
end

function SkillTreeService:GetState(player: any): Types.SkillTreeStatePayload?
	if not isValidPlayerKey(player) then
		return nil
	end
	local profile: Types.PlayerProfileData? = unwrapProfile(player)
	if not profile then
		return nil
	end
	return buildStatePayload(profile)
end

function SkillTreeService:UnlockSkill(player: any, skillId: string): Types.SkillUnlockResultPayload
	local emptyState: Types.SkillTreeStatePayload = {
		unlocked = {},
		earnedPoints = 0,
		spentPoints = 0,
		availablePoints = 0,
	}

	local function fail(
		code: Types.SkillErrorCode,
		msg: string,
		state: Types.SkillTreeStatePayload
	): Types.SkillUnlockResultPayload
		return {
			ok = false,
			skillId = tostring(skillId or ""),
			state = state,
			errorCode = code,
			message = msg,
		}
	end

	if not isValidPlayerKey(player) then
		return fail("INVALID_PLAYER", "Некорректный игрок.", emptyState)
	end

	local profile: Types.PlayerProfileData? = unwrapProfile(player)
	if not profile then
		return fail("PROFILE_NOT_LOADED", "Профиль игрока ещё не загружен.", emptyState)
	end

	local currentState = buildStatePayload(profile)

	if type(skillId) ~= "string" or SkillTreeConfig.Nodes[skillId] == nil then
		return fail("UNKNOWN_SKILL", "Неизвестный узел навыка.", currentState)
	end

	local node = SkillTreeConfig.Nodes[skillId]

	if currentState.unlocked[skillId] == true then
		return fail("ALREADY_UNLOCKED", "Этот навык уже изучен.", currentState)
	end

	if profile.level < node.requiredLevel then
		return fail(
			"LEVEL_TOO_LOW",
			string.format("Требуется уровень %d для изучения навыка.", node.requiredLevel),
			currentState
		)
	end

	for _, prereqId in ipairs(node.requires) do
		if currentState.unlocked[prereqId] ~= true then
			return fail("PREREQUISITE_MISSING", "Сначала изучите предыдущий узел ветки.", currentState)
		end
	end

	if currentState.availablePoints < node.cost then
		return fail("NOT_ENOUGH_POINTS", "Недостаточно очков навыков.", currentState)
	end

	local updatedState: Types.SkillTreeStatePayload = currentState
	playerDataService:UpdateProfile(player, function(p: Types.PlayerProfileData)
		local section = ensureSkillSection(p)
		section.unlocked[skillId] = true
		updatedState = buildStatePayload(p)
		return true
	end)

	self.OnSkillUnlocked:Fire(player, skillId, updatedState)

	return {
		ok = true,
		skillId = skillId,
		state = updatedState,
		errorCode = nil,
		message = string.format("Навык «%s» успешно изучен!", node.displayName),
	}
end

function SkillTreeService:GetSkillBonuses(player: any): Types.BodyStatBlock
	local bonuses: Types.BodyStatBlock = {
		attackPower = 0,
		critChance = 0,
		critMultiplier = 0,
		maxHealth = 0,
		defense = 0,
		moveSpeed = 0,
		attackCooldownReduction = 0,
		attackPowerPct = 0,
		maxHealthPct = 0,
	}

	local state = self:GetState(player)
	if not state then
		return bonuses
	end

	for skillId, isUnlocked in pairs(state.unlocked) do
		if isUnlocked then
			local node = SkillTreeConfig.Nodes[skillId]
			if node and node.bonuses then
				local b = node.bonuses
				bonuses.attackPower = (bonuses.attackPower or 0) + (b.attackPower or 0)
				bonuses.critChance = (bonuses.critChance or 0) + (b.critChance or 0)
				bonuses.critMultiplier = (bonuses.critMultiplier or 0) + (b.critMultiplier or 0)
				bonuses.maxHealth = (bonuses.maxHealth or 0) + (b.maxHealth or 0)
				bonuses.defense = (bonuses.defense or 0) + (b.defense or 0)
				bonuses.moveSpeed = (bonuses.moveSpeed or 0) + (b.moveSpeed or 0)
				bonuses.attackCooldownReduction = (bonuses.attackCooldownReduction or 0) + (b.attackCooldownReduction or 0)
				bonuses.attackPowerPct = (bonuses.attackPowerPct or 0) + (b.attackPowerPct or 0)
				bonuses.maxHealthPct = (bonuses.maxHealthPct or 0) + (b.maxHealthPct or 0)
			end
		end
	end

	return bonuses
end

function SkillTreeService:GrantPointsForTest(player: any, extraPoints: number): ()
	if not isValidPlayerKey(player) or type(extraPoints) ~= "number" or extraPoints <= 0 then
		return
	end
	playerDataService:UpdateProfile(player, function(p: Types.PlayerProfileData)
		local section = ensureSkillSection(p)
		section.earnedPoints += math.floor(extraPoints)
		return true
	end)
end

return SkillTreeService
