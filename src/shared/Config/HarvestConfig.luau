--!strict
--[[
	@module HarvestConfig
	@owner Shared (Agent A: Breight321 & Agent B: anarugod)
	@description Конфигурация первого вертикального среза "Sunforge Expedition":
	зоны добычи, станции сдачи, уровни улучшения инструмента и сумки, а также этапы общей цели сервера.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Types = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Core"):WaitForChild("Types"))

local HarvestConfig = {
	GameTitle = "Sunforge Expedition",
	ResourceName = "Solar Shards",
	RewardCurrencyId = "Coins",
	DefaultNodeId = "sunforge_crater",
	DefaultStationId = "central_refinery",

	-- Зоны совместной добычи (проверяются по этапу сервера и дистанции игрока)
	ExtractionZones = {
		sunforge_crater = {
			id = "sunforge_crater",
			displayName = "Sunforge Crater",
			description = "Стартовый кратер солнечной руды в центре экспедиции.",
			centerPosition = Vector3.new(0, 0, -24),
			radius = 45,
			yieldMultiplier = 1.0,
			requiredServerStage = 1,
		},
		amber_canyon = {
			id = "amber_canyon",
			displayName = "Amber Rift Canyon",
			description = "Каньон янтарных кристаллов (открывается на II этапе сервера, x2.5 к добыче).",
			centerPosition = Vector3.new(45, 0, -24),
			radius = 45,
			yieldMultiplier = 2.5,
			requiredServerStage = 2,
		},
		helios_vault = {
			id = "helios_vault",
			displayName = "Helios Core Vault",
			description = "Древнее хранилище Гелиоса (открывается на III этапе сервера, x6.0 к добыче).",
			centerPosition = Vector3.new(-45, 0, -24),
			radius = 45,
			yieldMultiplier = 6.0,
			requiredServerStage = 3,
		},
	} :: { [string]: Types.ExtractionZoneDef },

	-- Станции сдачи добычи (только активные станции принимают ресурс и начисляют валюту)
	DepositStations = {
		central_refinery = {
			id = "central_refinery",
			displayName = "Central Sunforge Refinery",
			position = Vector3.new(0, 0, 18),
			interactionRadius = 35,
			exchangeRate = 1.0,
			requiredServerStage = 1,
			active = true,
		},
		solar_conduit = {
			id = "solar_conduit",
			displayName = "High-Yield Solar Conduit",
			position = Vector3.new(35, 0, 18),
			interactionRadius = 35,
			exchangeRate = 1.25,
			requiredServerStage = 2,
			active = true,
		},
		dormant_relay = {
			id = "dormant_relay",
			displayName = "Offline Maintenance Relay",
			position = Vector3.new(-35, 0, 18),
			interactionRadius = 25,
			exchangeRate = 1.0,
			requiredServerStage = 1,
			active = false,
		},
	} :: { [string]: Types.DepositStationDef },

	-- Линейка улучшений инструмента добычи (ToolUpgrades[level])
	ToolUpgrades = {
		[1] = {
			level = 1,
			id = "copper_extractor",
			displayName = "Copper Resonance Pick",
			harvestPower = 2,
			cooldownSeconds = 0.25,
			priceCoins = 0,
			description = "Базовый резонансный резак (+2 за импульс).",
		},
		[2] = {
			level = 2,
			id = "bronze_extractor",
			displayName = "Sunbronze Drill",
			harvestPower = 5,
			cooldownSeconds = 0.22,
			priceCoins = 25,
			description = "Ускоренный бур из солнечной бронзы (+5 за импульс).",
		},
		[3] = {
			level = 3,
			id = "cobalt_extractor",
			displayName = "Cobalt Pulse Cutter",
			harvestPower = 12,
			cooldownSeconds = 0.18,
			priceCoins = 100,
			description = "Импульсный резак (+12 за импульс).",
		},
		[4] = {
			level = 4,
			id = "aether_extractor",
			displayName = "Aether Beam Lance",
			harvestPower = 30,
			cooldownSeconds = 0.15,
			priceCoins = 400,
			description = "Лучевое копьё эфира (+30 за импульс).",
		},
		[5] = {
			level = 5,
			id = "helios_extractor",
			displayName = "Helios Core Harvester",
			harvestPower = 75,
			cooldownSeconds = 0.12,
			priceCoins = 1500,
			description = "Тяжёлый экстрактор ядра Гелиоса (+75 за импульс).",
		},
	} :: { [number]: Types.ToolUpgradeTierDef },

	-- Линейка улучшений переносимой сумки/ранца (BagUpgrades[level])
	BagUpgrades = {
		[1] = {
			level = 1,
			id = "canvas_pouch",
			displayName = "Canvas Shard Pouch",
			capacity = 20,
			priceCoins = 0,
			description = "Походная сумка исследователя (вместимость: 20).",
		},
		[2] = {
			level = 2,
			id = "reinforced_satchel",
			displayName = "Reinforced Sun-Satchel",
			capacity = 50,
			priceCoins = 20,
			description = "Укреплённый ранец (вместимость: 50).",
		},
		[3] = {
			level = 3,
			id = "pressurized_canister",
			displayName = "Pressurized Shard Canister",
			capacity = 125,
			priceCoins = 85,
			description = "Герметичный контейнер для руды (вместимость: 125).",
		},
		[4] = {
			level = 4,
			id = "magnetic_rig",
			displayName = "Magnetic Containment Rig",
			capacity = 300,
			priceCoins = 350,
			description = "Магнитный ранец удержания (вместимость: 300).",
		},
		[5] = {
			level = 5,
			id = "dimensional_pack",
			displayName = "Solaris Pocket Vault",
			capacity = 800,
			priceCoins = 1200,
			description = "Портативное хранилище Соляриса (вместимость: 800).",
		},
	} :: { [number]: Types.BagUpgradeTierDef },

	-- Этапы совместного прогресса сервера (ServerMilestones[stage])
	ServerMilestones = {
		[1] = {
			stage = 1,
			title = "Stage I: Awakening the Forge",
			description = "Сдайте 100 ед. добычи всей командой, чтобы открыть Amber Rift Canyon и бонус x1.25!",
			targetDeposited = 100,
			stageBonusMultiplier = 1.0,
			unlockedZoneIds = { "sunforge_crater" },
		},
		[2] = {
			stage = 2,
			title = "Stage II: Amber Canyon Breach",
			description = "Сдайте 500 ед. добычи всей командой, чтобы открыть Helios Core Vault и бонус x1.6!",
			targetDeposited = 500,
			stageBonusMultiplier = 1.25,
			unlockedZoneIds = { "sunforge_crater", "amber_canyon" },
		},
		[3] = {
			stage = 3,
			title = "Stage III: Helios Vault Overdrive",
			description = "Сдайте 2000 ед. добычи всей командой для выхода на пиковую мощность Горна (x2.0)!",
			targetDeposited = 2000,
			stageBonusMultiplier = 1.6,
			unlockedZoneIds = { "sunforge_crater", "amber_canyon", "helios_vault" },
		},
		[4] = {
			stage = 4,
			title = "Stage IV: Ascendant Sunforge",
			description = "Максимальный этап достигнут! Все зоны открыты, действует командный бонус x2.0 к сдаче.",
			targetDeposited = 10000,
			stageBonusMultiplier = 2.0,
			unlockedZoneIds = { "sunforge_crater", "amber_canyon", "helios_vault" },
		},
	} :: { [number]: Types.ServerMilestoneDef },
}

return table.freeze(HarvestConfig)
