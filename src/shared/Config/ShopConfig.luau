--!strict
--[[
	@module ShopConfig
	@owner Shared (Agent A & Agent B)
	@description Каталог товаров магазина симулятора с поддержкой категорий.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Types = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Core"):WaitForChild("Types"))

local ShopConfig: { [string]: Types.ShopItemDef } = {
	shop_iron_wand = {
		id = "shop_iron_wand",
		itemId = "iron_wand",
		category = "Tools",
		currencyId = "Coins",
		price = 100,
		requiredZoneId = "spawn_meadow",
		requiredRebirths = 0,
	},
	shop_golden_scepter = {
		id = "shop_golden_scepter",
		itemId = "golden_scepter",
		category = "Tools",
		currencyId = "Coins",
		price = 1500,
		requiredZoneId = "crystal_cavern",
		requiredRebirths = 0,
	},
	shop_ember_fox_pet = {
		id = "shop_ember_fox_pet",
		itemId = "ember_fox_pet",
		category = "Pets",
		currencyId = "Gems",
		price = 15,
		requiredZoneId = "spawn_meadow",
		requiredRebirths = 0,
	},
}

return table.freeze(ShopConfig)
