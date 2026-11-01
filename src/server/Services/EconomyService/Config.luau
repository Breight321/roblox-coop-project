--!strict
--[[
	@module EconomyService.Config
	@owner Agent A (Breight321)
	@description Настраиваемые ограничения, лимиты транзакций и параметры защиты EconomyService.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CurrenciesConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("CurrenciesConfig"))
local EconomyTypes = require(script.Parent:WaitForChild("Types"))

local Config: EconomyTypes.EconomyConfigSchema = {
	-- Допуск 15% на сетевой джиттер при проверке кулдауна кликов
	ClickCooldownJitterTolerance = 0.85,

	-- Максимальное число хранимых записей истории транзакций на игрока в памяти
	MaxTransactionHistoryPerPlayer = 50,

	-- Минимальный интервал для защиты от дублирования идентичных сетевых запросов
	MinTransactionIntervalSeconds = 0.05,

	LimitsByCurrency = {
		Coins = {
			minBalance = 0,
			maxBalance = CurrenciesConfig.Coins.maxAmount,
			maxSingleTransaction = 1e12,
			allowNegative = false,
		},
		Gems = {
			minBalance = 0,
			maxBalance = CurrenciesConfig.Gems.maxAmount,
			maxSingleTransaction = 1e9,
			allowNegative = false,
		},
	},
}

return table.freeze(Config)
