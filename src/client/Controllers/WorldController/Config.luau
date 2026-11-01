--!strict
--[[
	@module WorldController.Config
	@owner Agent B (anarugod)
	@description Конфигурация по умолчанию для универсального WorldController.
]]

local WorldConfig = {
	DefaultStartingZoneId = "spawn_meadow",
	AutoSyncGatesToWorkspace = true,
}

return table.freeze(WorldConfig)
