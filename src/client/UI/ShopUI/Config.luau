--!strict
--[[
	@module ShopUI.Config
	@owner Agent B (anarugod)
	@description Конфигурация категорий, таймингов состояний и лимитов запросов для Shop UI.
]]

local ShopUITypes = require(script.Parent:WaitForChild("Types"))

local ShopUIConfig = {
	RequestCooldownSeconds = 0.35,
	LoadingTimeoutSeconds = 5.0,
	FeedbackResetSeconds = 1.5,

	DefaultCategories = {
		{ id = "All", displayName = "All Items", order = 1 },
		{ id = "Tools", displayName = "Tools", order = 2 },
		{ id = "Pets", displayName = "Pets", order = 3 },
		{ id = "Boosts", displayName = "Boosts", order = 4 },
	} :: { ShopUITypes.ShopCategoryDef },
}

return table.freeze(ShopUIConfig)
