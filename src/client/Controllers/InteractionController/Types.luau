--!strict
--[[
	@module InteractionController.Types
	@owner Agent B (anarugod)
	@description Универсальные типы для модульной системы ввода и интеракций (Interaction Framework).
]]

export type InteractionErrorCode =
	"INTERACTION_DISABLED"
	| "INVALID_ACTION_DEF"
	| "ACTION_ALREADY_REGISTERED"
	| "UNKNOWN_ACTION"
	| "ACTION_COOLDOWN"
	| "MODAL_BLOCKED"
	| "CLICK_COOLDOWN"

export type ActionDefinition = {
	id: string,
	displayName: string?,
	keyCodes: { Enum.KeyCode }?,
	userInputTypes: { Enum.UserInputType }?,
	cooldownSeconds: number?,
	allowWhenModalOpen: boolean?,
	callback: ((actionId: string, ...any) -> ())?,
}

return {}
