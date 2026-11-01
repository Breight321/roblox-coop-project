--!strict
--[[
	@module ShopUI.Types
	@owner Agent B (anarugod)
	@description Строгие типы данных и состояний для модульного Shop UI.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SharedTypes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Core"):WaitForChild("Types"))

export type ShopUIStatus = "Idle" | "Loading" | "Success" | "Error"

export type OfferButtonState = "Available" | "InsufficientFunds" | "LockedZone" | "LockedRebirth" | "Loading" | "Success" | "Error"

export type ShopCategoryId = "All" | "Tool" | "Pet" | "Consumable" | string

export type ShopCategoryDef = {
	id: ShopCategoryId,
	displayName: string,
	order: number,
}

export type ShopPlayerContext = {
	currencies: { [SharedTypes.CurrencyId]: number },
	rebirths: number,
	unlockedZones: { [string]: boolean },
}

export type ShopOfferViewModel = {
	shopItemId: string,
	itemId: string,
	displayName: string,
	description: string,
	category: SharedTypes.ItemCategory,
	rarity: SharedTypes.Rarity,
	currencyId: SharedTypes.CurrencyId,
	price: number,
	powerMultiplier: number,
	coinMultiplier: number,
	buttonState: OfferButtonState,
	statusText: string,
	canPurchase: boolean,
}

return {}
