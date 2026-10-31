--!strict
--[[
	@module Types
	@owner Shared (Agent 1: Breight321 & Agent 2: anarugod)
	@description Единые строгие Luau-типы для всех 15 систем Roblox Simulator Framework.
]]

export type Result<T, E = string> = {
	ok: boolean,
	value: T?,
	error: E?,
}

export type CurrencyId = "Coins" | "Gems"

export type ItemCategory = "Tool" | "Pet" | "Consumable"

export type Rarity = "Common" | "Uncommon" | "Rare" | "Epic" | "Legendary" | "Mythic"

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
	powerMultiplier: number,
	coinMultiplier: number,
	description: string,
}

export type ZoneDef = {
	id: string,
	displayName: string,
	order: number,
	costCurrency: CurrencyId,
	costAmount: number,
	requiredRebirths: number,
	zoneMultiplier: number,
}

export type ShopItemDef = {
	id: string,
	itemId: string,
	currencyId: CurrencyId,
	price: number,
	requiredZoneId: string?,
	requiredRebirths: number?,
}

export type QuestDef = {
	id: string,
	title: string,
	description: string,
	objectiveType: "Clicks" | "EarnCoins" | "Rebirths" | "UnlockZones",
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
	acquiredAt: number,
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
