--!strict
--[[
	@module ItemsConfig
	@owner Shared (Agent 1 & Agent 2)
	@description Конфигурация предметов, инструментов и питомцев.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Types = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Core"):WaitForChild("Types"))

local ItemsConfig: { [string]: Types.ItemDef } = {
	starter_wand = {
		id = "starter_wand",
		displayName = "Wooden Wand",
		category = "Tool",
		rarity = "Common",
		powerMultiplier = 1.0,
		coinMultiplier = 1.0,
		description = "Базовый инструмент начинающего игрока.",
	},
	iron_wand = {
		id = "iron_wand",
		displayName = "Iron Collector",
		category = "Tool",
		rarity = "Uncommon",
		powerMultiplier = 2.0,
		coinMultiplier = 1.5,
		description = "Увеличивает добычу монет за клик в 1.5 раза.",
	},
	golden_scepter = {
		id = "golden_scepter",
		displayName = "Golden Scepter",
		category = "Tool",
		rarity = "Rare",
		powerMultiplier = 5.0,
		coinMultiplier = 3.0,
		description = "Утраивает получаемые за клик монеты.",
	},
	ember_fox_pet = {
		id = "ember_fox_pet",
		displayName = "Ember Fox",
		category = "Pet",
		rarity = "Rare",
		powerMultiplier = 1.5,
		coinMultiplier = 1.25,
		description = "Даёт +25% к фарму монет.",
	},
}

return table.freeze(ItemsConfig)
