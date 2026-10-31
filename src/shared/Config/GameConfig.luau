--!strict
--[[
	@module GameConfig
	@owner Shared (Agent 1 & Agent 2)
	@description Глобальные параметры игры и симулятора.
]]

local GameConfig = {
	GameVersion = "0.1.0",
	DataSchemaVersion = 1,
	DataStoreName = "SimulatorProfileStore_v1",
	AutoSaveIntervalSeconds = 60,
	RunTestsOnStartup = true,

	Simulator = {
		ClickCooldownSeconds = 0.15,
		BaseCoinsPerClick = 1,
		BaseXPPerClick = 2,
		MaxEquippedPets = 3,
		MaxInventorySlots = 50,
	},

	Progression = {
		BaseXPToLevelUp = 100,
		XPGrindingGrowthFactor = 1.35,
		BaseRebirthCostCoins = 1000,
		RebirthCostMultiplier = 2.5,
		RebirthBonusMultiplierPerRebirth = 0.5,
		RebirthGemsReward = 10,
	},
}

return table.freeze(GameConfig)
