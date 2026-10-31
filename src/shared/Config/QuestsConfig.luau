--!strict
--[[
	@module QuestsConfig
	@owner Shared (Agent 1 & Agent 2)
	@description Конфигурация стартовых квестов симулятора.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Types = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Core"):WaitForChild("Types"))

local QuestsConfig: { [string]: Types.QuestDef } = {
	quest_first_clicks = {
		id = "quest_first_clicks",
		title = "First Steps",
		description = "Сделай 25 кликов в симуляторе.",
		objectiveType = "Clicks",
		targetAmount = 25,
		rewardCurrency = "Coins",
		rewardAmount = 150,
		rewardXP = 50,
	},
	quest_coin_collector = {
		id = "quest_coin_collector",
		title = "Coin Collector",
		description = "Собери суммарно 500 монет.",
		objectiveType = "EarnCoins",
		targetAmount = 500,
		rewardCurrency = "Gems",
		rewardAmount = 10,
		rewardXP = 120,
	},
}

return table.freeze(QuestsConfig)
