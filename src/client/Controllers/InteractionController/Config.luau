--!strict
--[[
	@module InteractionController.Config
	@owner Agent B (anarugod)
	@description Конфигурация по умолчанию для универсального InteractionController.
]]

local InteractionConfig = {
	DefaultActionCooldownSeconds = 0.15,

	DefaultWindowHotkeys = {
		[Enum.KeyCode.U] = "Upgrades",
		[Enum.KeyCode.B] = "Shop",
		[Enum.KeyCode.I] = "Inventory",
		[Enum.KeyCode.Q] = "Quests",
		[Enum.KeyCode.R] = "Rebirth",
	} :: { [Enum.KeyCode]: string },

	CloseModalKeyCodes = {
		Enum.KeyCode.Escape,
		Enum.KeyCode.ButtonB,
	} :: { Enum.KeyCode },
}

return table.freeze(InteractionConfig)
