--!strict
--[[
	@module Types
	@owner Shared (Agent A: Breight321 & Agent B: anarugod)
	@description Универсальные строгие Luau-типы и контракты для Universal Reusable Roblox Framework.
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
