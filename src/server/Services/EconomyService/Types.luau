--!strict
--[[
	@module EconomyService.Types
	@owner Agent A (Breight321)
	@description Типы данных, коды ошибок и структуры транзакций модуля EconomyService.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SharedTypes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Core"):WaitForChild("Types"))

export type CurrencyId = SharedTypes.CurrencyId
export type Result<T, E = string> = SharedTypes.Result<T, E>
export type MultiplierBreakdown = SharedTypes.MultiplierBreakdown
export type EconomyTransactionRecord = SharedTypes.EconomyTransactionRecord

export type EconomyErrorCode =
	"INVALID_PLAYER"
	| "PROFILE_NOT_LOADED"
	| "UNKNOWN_CURRENCY"
	| "INVALID_AMOUNT"
	| "AMOUNT_EXCEEDS_MAX_TRANSACTION"
	| "NEGATIVE_BALANCE_FORBIDDEN"
	| "INSUFFICIENT_FUNDS"
	| "CLICK_COOLDOWN"
	| "RATE_LIMITED"
	| "UPDATE_FAILED"

export type CurrencyLimitRule = {
	minBalance: number,
	maxBalance: number,
	maxSingleTransaction: number,
	allowNegative: boolean,
}

export type EconomyConfigSchema = {
	ClickCooldownJitterTolerance: number,
	MaxTransactionHistoryPerPlayer: number,
	MinTransactionIntervalSeconds: number,
	LimitsByCurrency: { [CurrencyId]: CurrencyLimitRule },
}

local EconomyTypes = {}

return table.freeze(EconomyTypes)
