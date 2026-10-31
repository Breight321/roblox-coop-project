--!strict
--[[
	@module CurrenciesConfig
	@owner Shared (Agent 1 & Agent 2)
	@description Конфигурация игровых валют симулятора.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Types = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Core"):WaitForChild("Types"))

local CurrenciesConfig: { [Types.CurrencyId]: Types.CurrencyDef } = {
	Coins = {
		id = "Coins",
		displayName = "Coins",
		startingAmount = 0,
		maxAmount = 1e15,
		showInLeaderstats = true,
	},
	Gems = {
		id = "Gems",
		displayName = "Gems",
		startingAmount = 0,
		maxAmount = 1e12,
		showInLeaderstats = true,
	},
}

return table.freeze(CurrenciesConfig)
