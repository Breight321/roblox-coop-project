--!strict
--[[
	@module StatsService
	@owner Agent A (Breight321)
	@description Агрегатор боевых характеристик игрока:
	базовые статы + бонусы уровня + экипированные детали тела (Head, Arms, Torso, Legs) +
	бонус полного комплекта (4/4 из BodySetsConfig) + пассивные навыки из SkillTreeService.
	Автоматически обновляет MaxHealth и WalkSpeed у Humanoid и рассылает событие StatsUpdated.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Core"):WaitForChild("Types"))
local Logger = require(Shared:WaitForChild("Core"):WaitForChild("Logger"))
local Signal = require(Shared:WaitForChild("Core"):WaitForChild("Signal"))
local Network = require(Shared:WaitForChild("Core"):WaitForChild("Network"))

local ItemsConfig = require(Shared:WaitForChild("Config"):WaitForChild("ItemsConfig"))
local BodySetsConfig = require(Shared:WaitForChild("Config"):WaitForChild("BodySetsConfig"))
local CombatConfig = require(Shared:WaitForChild("Config"):WaitForChild("CombatConfig"))

local StatsService = {
	Name = "StatsService",
	Dependencies = { "PlayerDataService", "InventoryService", "SkillTreeService", "ProgressionService" },
	OnStatsChanged = Signal.new(),
}

local log = Logger.new("StatsService")
local playerDataService: any = nil
local inventoryService: any = nil
local skillTreeService: any = nil
local progressionService: any = nil

local cachedStats: { [any]: Types.CharacterStatsPayload } = {}
local connections: { RBXScriptConnection } = {}

local CATEGORY_TO_SLOT: { [string]: Types.BodySlot } = {
	BodyHead = "Head",
	BodyArms = "Arms",
	BodyTorso = "Torso",
	BodyLegs = "Legs",
}

local ALL_SLOTS: { Types.BodySlot } = { "Head", "Arms", "Torso", "Legs" }

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

local function createDefaultStats(): Types.CharacterStatsPayload
	local base = CombatConfig.BaseStats
	return {
		level = 1,
		attackPower = base.attackPower,
		critChance = base.critChance,
		critMultiplier = base.critMultiplier,
		maxHealth = base.maxHealth,
		defense = base.defense,
		damageReduction = 0,
		moveSpeed = base.moveSpeed,
		attackCooldown = base.attackCooldown,
		equippedBodyParts = {},
		activeSetBonus = nil,
	}
end

local function applyStatsToCharacter(player: any, stats: Types.CharacterStatsPayload): ()
	if not isRealPlayer(player) then
		return
	end
	local character: Model? = (player :: Player).Character
	if not character then
		return
	end

	character:SetAttribute("EquippedBodyHead", stats.equippedBodyParts.Head or "")
	character:SetAttribute("EquippedBodyArms", stats.equippedBodyParts.Arms or "")
	character:SetAttribute("EquippedBodyTorso", stats.equippedBodyParts.Torso or "")
	character:SetAttribute("EquippedBodyLegs", stats.equippedBodyParts.Legs or "")
	character:SetAttribute("ActiveBodySetId", stats.activeSetBonus or "")

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		local prevMax = math.max(1, humanoid.MaxHealth)
		local healthRatio = math.clamp(humanoid.Health / prevMax, 0, 1)
		humanoid.MaxHealth = stats.maxHealth
		if humanoid.Health > 0 then
			humanoid.Health = math.max(1, math.floor(stats.maxHealth * healthRatio + 0.5))
		end
		humanoid.WalkSpeed = stats.moveSpeed
	end
end

local function sendStatsSync(player: any, stats: Types.CharacterStatsPayload): ()
	if not isRealPlayer(player) then
		return
	end
	Network.FireClient(player, Network.Events.StatsUpdated, stats)
end

function StatsService:Init(registry: any): ()
	playerDataService = registry:Get("PlayerDataService")
	inventoryService = registry:Get("InventoryService")
	skillTreeService = registry:Get("SkillTreeService")
	progressionService = registry:Get("ProgressionService")
	log:Info("Initialized.")
end

function StatsService:Start(): ()
	table.insert(
		connections,
		playerDataService.OnProfileLoaded:Connect(function(player: any)
			self:RecalculateAndApply(player)
		end)
	)

	table.insert(
		connections,
		playerDataService.OnProfileReleasing:Connect(function(player: any)
			cachedStats[player] = nil
		end)
	)

	if inventoryService and inventoryService.OnEquipmentChanged then
		table.insert(
			connections,
			inventoryService.OnEquipmentChanged:Connect(function(player: any)
				self:RecalculateAndApply(player)
			end)
		)
	end

	if skillTreeService and skillTreeService.OnSkillUnlocked then
		table.insert(
			connections,
			skillTreeService.OnSkillUnlocked:Connect(function(player: any)
				self:RecalculateAndApply(player)
			end)
		)
	end

	if progressionService and progressionService.OnLevelUp then
		table.insert(
			connections,
			progressionService.OnLevelUp:Connect(function(player: any)
				self:RecalculateAndApply(player)
			end)
		)
	end

	local function hookPlayerCharacter(player: Player): ()
		table.insert(
			connections,
			player.CharacterAdded:Connect(function()
				task.defer(function()
					local current = self:GetStats(player)
					applyStatsToCharacter(player, current)
				end)
			end)
		)
	end

	for _, player in ipairs(Players:GetPlayers()) do
		hookPlayerCharacter(player)
	end
	table.insert(connections, Players.PlayerAdded:Connect(hookPlayerCharacter))

	log:Info("Started.")
end

function StatsService:Shutdown(): ()
	for _, conn in ipairs(connections) do
		conn:Disconnect()
	end
	table.clear(connections)
	table.clear(cachedStats)
end

function StatsService:GetEquippedBodyParts(player: any): { [Types.BodySlot]: Types.InventoryItem? }
	local result: { [Types.BodySlot]: Types.InventoryItem? } = {}
	if not isValidPlayerKey(player) then
		return result
	end
	local profile: Types.PlayerProfileData? = unwrapProfile(player)
	if not profile or type(profile.inventory) ~= "table" then
		return result
	end

	for _, item in pairs(profile.inventory) do
		if item.equipped then
			local slot = CATEGORY_TO_SLOT[item.category]
			if not slot then
				local def = ItemsConfig[item.itemId]
				if def and def.metadata and type(def.metadata.bodySlot) == "string" then
					slot = def.metadata.bodySlot :: Types.BodySlot
				end
			end
			if slot and result[slot] == nil then
				result[slot] = item
			end
		end
	end

	return result
end

function StatsService:RecalculateAndApply(player: any): Types.CharacterStatsPayload
	if not isValidPlayerKey(player) then
		return createDefaultStats()
	end

	local profile: Types.PlayerProfileData? = unwrapProfile(player)
	if not profile then
		return createDefaultStats()
	end

	local base = CombatConfig.BaseStats
	local perLevel = CombatConfig.PerLevelStats
	local levelAboveOne = math.max(0, profile.level - 1)

	local flatAttackPower = base.attackPower + levelAboveOne * perLevel.attackPower
	local flatMaxHealth = base.maxHealth + levelAboveOne * perLevel.maxHealth
	local flatDefense = base.defense + levelAboveOne * perLevel.defense
	local moveSpeed = base.moveSpeed
	local critChance = base.critChance
	local critMultiplier = base.critMultiplier
	local cooldownReduction = 0
	local attackPowerPct = 0
	local maxHealthPct = 0

	local function addStatBlock(block: any): ()
		if type(block) ~= "table" then
			return
		end
		flatAttackPower += (block.attackPower or 0)
		flatMaxHealth += (block.maxHealth or 0)
		flatDefense += (block.defense or 0)
		moveSpeed += (block.moveSpeed or 0)
		critChance += (block.critChance or 0)
		critMultiplier += (block.critMultiplier or 0)
		cooldownReduction += (block.attackCooldownReduction or 0)
		attackPowerPct += (block.attackPowerPct or 0)
		maxHealthPct += (block.maxHealthPct or 0)
	end

	-- 1. Бонусы от экипированных деталей тела (Head, Arms, Torso, Legs)
	local equippedBySlot = self:GetEquippedBodyParts(player)
	local equippedItemIds: { [Types.BodySlot]: string } = {}
	local setCounts: { [string]: number } = {}

	for _, slot in ipairs(ALL_SLOTS) do
		local invItem = equippedBySlot[slot]
		if invItem then
			equippedItemIds[slot] = invItem.itemId
			local def = ItemsConfig[invItem.itemId]
			local meta = if def and type(def.metadata) == "table" then def.metadata else invItem.metadata
			if type(meta) == "table" then
				addStatBlock(meta.stats)
				if type(meta.setId) == "string" then
					local setId = meta.setId :: string
					setCounts[setId] = (setCounts[setId] or 0) + 1
				end
			end
		end
	end

	-- 2. Бонус полного набора (4 детали одного setId)
	local activeSetBonus: string? = nil
	for setId, count in pairs(setCounts) do
		local setDef = BodySetsConfig[setId]
		if setDef and count >= (setDef.requiredPieceCount or 4) then
			activeSetBonus = setId
			addStatBlock(setDef.fullSetBonus)
			break
		end
	end

	-- 3. Бонусы от дерева пассивных навыков (SkillTreeService)
	if skillTreeService then
		local skillBonuses: Types.BodyStatBlock = skillTreeService:GetSkillBonuses(player)
		addStatBlock(skillBonuses)
	end

	local finalAttackPower = math.max(1, math.floor(flatAttackPower * (1 + math.max(0, attackPowerPct)) + 0.5))
	local finalMaxHealth = math.max(1, math.floor(flatMaxHealth * (1 + math.max(0, maxHealthPct)) + 0.5))
	local finalDefense = math.max(0, math.floor(flatDefense + 0.5))
	local rawReduction = finalDefense / (finalDefense + CombatConfig.DefenseConstant)
	local damageReduction = math.clamp(rawReduction, 0, CombatConfig.MaxDamageReduction)
	local effectiveCooldown = math.max(
		CombatConfig.MinAttackCooldown,
		math.floor((base.attackCooldown - math.max(0, cooldownReduction)) * 1000 + 0.5) / 1000
	)

	local payload: Types.CharacterStatsPayload = {
		level = profile.level,
		attackPower = finalAttackPower,
		critChance = math.clamp(critChance, 0, CombatConfig.MaxCritChance),
		critMultiplier = math.max(1.0, critMultiplier),
		maxHealth = finalMaxHealth,
		defense = finalDefense,
		damageReduction = damageReduction,
		moveSpeed = math.clamp(moveSpeed, 8, 45),
		attackCooldown = effectiveCooldown,
		equippedBodyParts = equippedItemIds,
		activeSetBonus = activeSetBonus,
	}

	cachedStats[player] = payload
	applyStatsToCharacter(player, payload)
	sendStatsSync(player, payload)
	self.OnStatsChanged:Fire(player, payload)

	return payload
end

function StatsService:GetStats(player: any): Types.CharacterStatsPayload
	if not isValidPlayerKey(player) then
		return createDefaultStats()
	end
	local cached = cachedStats[player]
	if cached then
		return cached
	end
	return self:RecalculateAndApply(player)
end

function StatsService:ComputeMitigatedDamage(rawDamage: number, defense: number): number
	local cleanDamage = math.max(1, rawDamage)
	local cleanDefense = math.max(0, defense)
	local rawReduction = cleanDefense / (cleanDefense + CombatConfig.DefenseConstant)
	local reduction = math.clamp(rawReduction, 0, CombatConfig.MaxDamageReduction)
	return math.max(1, math.floor(cleanDamage * (1 - reduction) + 0.5))
end

return StatsService
