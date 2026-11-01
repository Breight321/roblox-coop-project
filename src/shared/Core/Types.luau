--!strict
--[[
	@module Types
	@owner Shared (Agent A: Breight321 & Agent B: anarugod)
	@description Универсальные строгие Luau-типы и контракты для Universal Reusable Roblox Framework и вертикального среза Sunforge Expedition.
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
