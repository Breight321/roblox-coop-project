--!strict
--[[
	@module ExpeditionController.Config
	@owner Agent B (anarugod)
	@description Клиентская конфигурация для «Sunforge Expedition», синхронизированная с общим HarvestConfig (Agent A & Agent B).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local HarvestConfig = require(Shared:WaitForChild("Config"):WaitForChild("HarvestConfig"))

local Config = {
	GameTitle = HarvestConfig.GameTitle or "Sunforge Expedition",
	ResourceName = HarvestConfig.ResourceName or "Solar Shards",
	RewardCurrencyId = HarvestConfig.RewardCurrencyId or "Coins",
	DefaultNodeId = HarvestConfig.DefaultNodeId or "sunforge_crater",
	DefaultStationId = HarvestConfig.DefaultStationId or "central_refinery",

	DefaultBagCapacity = HarvestConfig.BagUpgrades[1].capacity,
	BagAlmostFullThreshold = 0.80,

	CollectCooldownSeconds = 0.10,
	DepositCooldownSeconds = 0.25,
	UpgradeCooldownSeconds = 0.20,
	FeedbackResetSeconds = 1.6,

	StageMonumentPosition = Vector3.new(0, 6, -48),

	ToolTrackMeta = {
		displayName = "⛏️ Инструмент добычи (Sunforge Extractor)",
		description = "Увеличивает добычу Solar Shards за один импульс и ускоряет перезарядку.",
		icon = "⛏️",
		valueUnit = "осколков/сбор",
		currencyId = "Coins",
	},

	BagTrackMeta = {
		displayName = "🎒 Переносной Контейнер (Sun-Satchel)",
		description = "Увеличивает вместимость сумки для переноски Solar Shards до Станции Переплавки.",
		icon = "🎒",
		valueUnit = "вместимость",
		currencyId = "Coins",
	},

	HarvestConfig = HarvestConfig,
}

return table.freeze(Config)
