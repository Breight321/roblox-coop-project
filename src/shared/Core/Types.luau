--!strict
--[[
	@module Types
	@owner Shared (Agent A: Breight321 & Agent B: anarugod)
	@description Универсальные строгие Luau-типы и контракты для Universal Reusable Roblox Framework, Sunforge Expedition и Combat Loop v1.
]]

export type Result<T, E = string> = {
	ok: boolean,
	value: T?,
	error: E?,
}

-- Универсальные идентификаторы (не привязаны к одной игре)
export type CurrencyId = string
export type ItemCategory = string
export type ShopCategory = string

export type Rarity = "Common" | "Uncommon" | "Rare" | "Epic" | "Legendary" | "Mythic" | string

export type CurrencyDef = {
	id: CurrencyId,
	displayName: string,
	startingAmount: number,
	maxAmount: number,
	showInLeaderstats: boolean,
}

export type ItemDef = {
	id: string,
	displayName: string,
	category: ItemCategory,
	rarity: Rarity,
	stackable: boolean?,
	maxStack: number?,
	powerMultiplier: number,
	coinMultiplier: number,
	description: string,
	metadata: { [string]: any }?,
}

export type ZoneDef = {
	id: string,
	displayName: string,
	order: number,
	costCurrency: CurrencyId,
	costAmount: number,
	requiredRebirths: number,
	zoneMultiplier: number,
	requirements: { [string]: any }?,
}

export type ShopItemDef = {
	id: string,
	itemId: string,
	category: ShopCategory?,
	currencyId: CurrencyId,
	price: number,
	requiredZoneId: string?,
	requiredRebirths: number?,
	requirements: { [string]: any }?,
}

export type ShopPurchaseResponse = {
	ok: boolean,
	shopItemId: string,
	itemId: string?,
	itemUid: string?,
	currencyId: CurrencyId?,
	pricePaid: number?,
	newBalance: number?,
	errorCode: string?,
	message: string,
}

export type MultiplierBreakdown = {
	base: number,
	rebirthBonus: number,
	equippedItemsBonus: number,
	zoneBonus: number,
	customModifiersBonus: number?,
	total: number,
}

export type EconomyTransactionRecord = {
	id: string,
	timestamp: number,
	userId: number,
	currencyId: CurrencyId,
	delta: number,
	balanceBefore: number,
	balanceAfter: number,
	reason: string,
}

export type InventoryCapacityInfo = {
	usedSlots: number,
	maxSlots: number,
	equippedPetsCount: number,
	maxEquippedPets: number,
	equippedByCategory: { [string]: number }?,
}

export type QuestDef = {
	id: string,
	title: string,
	description: string,
	objectiveType: string,
	targetAmount: number,
	rewardCurrency: CurrencyId,
	rewardAmount: number,
	rewardXP: number,
}

export type InventoryItem = {
	uid: string,
	itemId: string,
	category: ItemCategory,
	equipped: boolean,
	level: number,
	quantity: number?,
	acquiredAt: number,
	metadata: { [string]: any }?,
}

export type QuestState = {
	questId: string,
	progress: number,
	target: number,
	completed: boolean,
	claimed: boolean,
}

export type PlayerStats = {
	totalClicks: number,
	totalCoinsEarned: number,
	playTimeSeconds: number,
	[string]: number,
}

-- Типы вертикального среза "Sunforge Expedition" (добыча -> сумка -> сдача -> улучшения -> цель сервера)
export type HarvestUpgradeType = "Tool" | "Bag"

export type HarvestErrorCode =
	"INVALID_PLAYER"
	| "PROFILE_NOT_LOADED"
	| "CHARACTER_NOT_READY"
	| "UNKNOWN_EXTRACTION_ZONE"
	| "STAGE_LOCKED"
	| "OUT_OF_ZONE_RANGE"
	| "HARVEST_COOLDOWN"
	| "BAG_FULL"
	| "INVALID_STATION"
	| "STATION_INACTIVE"
	| "TOO_FAR_FROM_STATION"
	| "BAG_EMPTY"
	| "INVALID_UPGRADE_TYPE"
	| "MAX_LEVEL_REACHED"
	| "INSUFFICIENT_FUNDS"
	| "UPDATE_FAILED"

export type ExtractionZoneDef = {
	id: string,
	displayName: string,
	description: string,
	centerPosition: Vector3,
	radius: number,
	yieldMultiplier: number,
	requiredServerStage: number,
}

export type DepositStationDef = {
	id: string,
	displayName: string,
	position: Vector3,
	interactionRadius: number,
	exchangeRate: number,
	requiredServerStage: number,
	active: boolean,
}

export type ToolUpgradeTierDef = {
	level: number,
	id: string,
	displayName: string,
	harvestPower: number,
	cooldownSeconds: number,
	priceCoins: number,
	description: string,
}

export type BagUpgradeTierDef = {
	level: number,
	id: string,
	displayName: string,
	capacity: number,
	priceCoins: number,
	description: string,
}

export type ServerMilestoneDef = {
	stage: number,
	title: string,
	description: string,
	targetDeposited: number,
	stageBonusMultiplier: number,
	unlockedZoneIds: { string },
}

export type PlayerHarvestState = {
	bagStored: number,
	toolLevel: number,
	bagLevel: number,
	totalHarvested: number,
	totalDeposited: number,
}

export type HarvestStatePayload = {
	bagStored: number,
	bagCapacity: number,
	toolLevel: number,
	toolId: string,
	toolName: string,
	harvestPower: number,
	cooldownSeconds: number,
	bagLevel: number,
	bagId: string,
	bagName: string,
	nextToolPrice: number?,
	nextBagPrice: number?,
	totalHarvested: number,
	totalDeposited: number,
}

export type HarvestResultPayload = {
	ok: boolean,
	nodeId: string,
	addedAmount: number,
	bagStored: number,
	bagCapacity: number,
	isBagFull: boolean,
	errorCode: HarvestErrorCode?,
	message: string,
}

export type DepositResultPayload = {
	ok: boolean,
	stationId: string,
	depositedAmount: number,
	coinsEarned: number,
	newCoinsBalance: number,
	bagStored: number,
	bagCapacity: number,
	serverTotalDeposited: number,
	serverStage: number,
	errorCode: HarvestErrorCode?,
	message: string,
}

export type UpgradeResultPayload = {
	ok: boolean,
	upgradeType: HarvestUpgradeType,
	newLevel: number,
	pricePaid: number,
	newCoinsBalance: number,
	harvestState: HarvestStatePayload?,
	errorCode: HarvestErrorCode?,
	message: string,
}

export type ServerProgressPayload = {
	totalDeposited: number,
	currentStage: number,
	stageTitle: string,
	stageDescription: string,
	currentStageTarget: number,
	previousStageThreshold: number,
	progressRatio: number,
	stageBonusMultiplier: number,
	unlockedExtractionZones: { [string]: boolean },
	isMaxStage: boolean,
}

-- ============================================================================
-- COMBAT LOOP v1: Мобы, Детали тела, Сундуки, Дерево навыков и PvP-арена
-- ============================================================================

export type BodySlot = "Head" | "Arms" | "Torso" | "Legs"
export type SkillBranch = "Damage" | "Defense" | "Mobility"

export type BodyStatBlock = {
	attackPower: number?,
	critChance: number?,
	critMultiplier: number?,
	maxHealth: number?,
	defense: number?,
	moveSpeed: number?,
	attackCooldownReduction: number?,
	attackPowerPct: number?,
	maxHealthPct: number?,
}

export type BodySetDef = {
	id: string,
	displayName: string,
	description: string,
	requiredPieceCount: number,
	fullSetBonus: BodyStatBlock,
	visualTheme: {
		style: string,
		primaryColor: string,
		accentColor: string,
		material: string,
		glow: boolean,
	},
}

export type CharacterStatsPayload = {
	level: number,
	attackPower: number,
	critChance: number,
	critMultiplier: number,
	maxHealth: number,
	defense: number,
	damageReduction: number,
	moveSpeed: number,
	attackCooldown: number,
	equippedBodyParts: { [BodySlot]: string },
	activeSetBonus: string?,
}

export type CombatErrorCode =
	"INVALID_PLAYER"
	| "PROFILE_NOT_LOADED"
	| "CHARACTER_NOT_READY"
	| "PLAYER_DEAD"
	| "INVALID_TARGET"
	| "TARGET_DEAD"
	| "OUT_OF_RANGE"
	| "ATTACK_COOLDOWN"
	| "ZONE_LOCKED"
	| "LEVEL_TOO_LOW"
	| "IN_ARENA"

export type LootDrop = {
	kind: "Currency" | "XP" | "Item",
	id: string,
	amount: number,
	itemUid: string?,
}

export type LootEntryDef = {
	kind: "Currency" | "XP" | "Item",
	id: string,
	minAmount: number,
	maxAmount: number,
	weight: number,
	guaranteed: boolean?,
}

export type LootTableDef = {
	id: string,
	rolls: number,
	entries: { LootEntryDef },
}

export type MobDef = {
	id: string,
	displayName: string,
	zoneId: string,
	level: number,
	maxHealth: number,
	attackDamage: number,
	attackIntervalSeconds: number,
	aggroRange: number,
	respawnSeconds: number,
	rewardXP: number,
	rewardCoins: number,
	lootTableId: string?,
	spawnPositions: { Vector3 },
}

export type CombatResultPayload = {
	ok: boolean,
	mobUid: string,
	damageDealt: number,
	isCritical: boolean,
	mobHealth: number,
	mobMaxHealth: number,
	killed: boolean,
	errorCode: CombatErrorCode?,
	message: string,
}

export type MobDefeatedPayload = {
	mobUid: string,
	mobId: string,
	zoneId: string,
	xpGained: number,
	coinsGained: number,
	drops: { LootDrop },
	totalMobKills: number,
}

export type ChestErrorCode =
	"INVALID_PLAYER"
	| "PROFILE_NOT_LOADED"
	| "CHARACTER_NOT_READY"
	| "UNKNOWN_CHEST"
	| "ZONE_LOCKED"
	| "LEVEL_TOO_LOW"
	| "OUT_OF_RANGE"
	| "CHEST_COOLDOWN"
	| "NOT_ENOUGH_KILLS"
	| "REQUEST_IN_PROGRESS"

export type ChestDef = {
	id: string,
	displayName: string,
	zoneId: string,
	position: Vector3,
	interactionRadius: number,
	minPlayerLevel: number,
	cooldownSeconds: number,
	requiredKillsSinceLastOpen: number,
	lootTableId: string,
}

export type ChestStatePayload = {
	chestId: string,
	readyAtUnix: number,
	requiredKills: number,
	killsSinceLastOpen: number,
	isReady: boolean,
}

export type ChestOpenResultPayload = {
	ok: boolean,
	chestId: string,
	drops: { LootDrop },
	state: ChestStatePayload?,
	errorCode: ChestErrorCode?,
	message: string,
}

export type SkillErrorCode =
	"INVALID_PLAYER"
	| "PROFILE_NOT_LOADED"
	| "UNKNOWN_SKILL"
	| "ALREADY_UNLOCKED"
	| "PREREQUISITE_MISSING"
	| "LEVEL_TOO_LOW"
	| "NOT_ENOUGH_POINTS"
	| "RATE_LIMITED"

export type SkillNodeDef = {
	id: string,
	displayName: string,
	branch: SkillBranch,
	tier: number,
	cost: number,
	requiredLevel: number,
	requires: { string },
	bonuses: BodyStatBlock,
	description: string,
}

export type SkillTreeStatePayload = {
	unlocked: { [string]: boolean },
	earnedPoints: number,
	spentPoints: number,
	availablePoints: number,
}

export type SkillUnlockResultPayload = {
	ok: boolean,
	skillId: string,
	state: SkillTreeStatePayload,
	errorCode: SkillErrorCode?,
	message: string,
}

export type ArenaErrorCode =
	"INVALID_PLAYER"
	| "PROFILE_NOT_LOADED"
	| "CHARACTER_NOT_READY"
	| "PLAYER_DEAD"
	| "NOT_AT_ARENA_ENTRANCE"
	| "ALREADY_IN_ARENA"
	| "NOT_IN_ARENA"
	| "COMBAT_TAGGED"
	| "LEVEL_TOO_LOW"
	| "INVALID_TARGET"
	| "SELF_TARGET"
	| "TARGET_NOT_IN_ARENA"
	| "OUT_OF_RANGE"
	| "ATTACK_COOLDOWN"
	| "RATE_LIMITED"

export type ArenaStatePayload = {
	inArena: boolean,
	arenaId: string,
	combatTaggedUntil: number,
	reason: string?,
	errorCode: ArenaErrorCode?,
	message: string,
}

export type PvPCombatResultPayload = {
	ok: boolean,
	attackerUserId: number,
	targetUserId: number,
	damageDealt: number,
	isCritical: boolean,
	targetHealth: number,
	targetMaxHealth: number,
	killed: boolean,
	errorCode: ArenaErrorCode?,
	message: string,
}

export type PlayerProfileData = {
	schemaVersion: number,
	currencies: { [CurrencyId]: number },
	rebirths: number,
	level: number,
	xp: number,
	unlockedZones: { [string]: boolean },
	inventory: { [string]: InventoryItem },
	quests: { [string]: QuestState },
	stats: PlayerStats,
	harvestState: PlayerHarvestState?,
	customData: { [string]: any }?,
}

export type LifecycleModule = {
	Name: string,
	Dependencies: { string }?,
	Init: ((self: any, registry: any) -> ())?,
	Start: ((self: any) -> ())?,
	Shutdown: ((self: any) -> ())?,
	[string]: any,
}

local Types = {}

function Types.Ok<T>(value: T): Result<T, string>
	return {
		ok = true,
		value = value,
		error = nil,
	}
end

function Types.Err<T>(errorMessage: string): Result<T, string>
	return {
		ok = false,
		value = nil,
		error = errorMessage,
	}
end

return Types
