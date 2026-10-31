--!strict
--[[
	@module ZonesConfig
	@owner Shared (Agent 1 & Agent 2)
	@description Конфигурация игровых локаций / зон симулятора.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Types = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Core"):WaitForChild("Types"))

local ZonesConfig: { [string]: Types.ZoneDef } = {
	spawn_meadow = {
		id = "spawn_meadow",
		displayName = "Spawn Meadow",
		order = 1,
		costCurrency = "Coins",
		costAmount = 0,
		requiredRebirths = 0,
		zoneMultiplier = 1.0,
	},
	crystal_cavern = {
		id = "crystal_cavern",
		displayName = "Crystal Cavern",
		order = 2,
		costCurrency = "Coins",
		costAmount = 500,
		requiredRebirths = 0,
		zoneMultiplier = 2.0,
	},
	volcanic_peaks = {
		id = "volcanic_peaks",
		displayName = "Volcanic Peaks",
		order = 3,
		costCurrency = "Coins",
		costAmount = 5000,
		requiredRebirths = 1,
		zoneMultiplier = 5.0,
	},
}

return table.freeze(ZonesConfig)
