--!strict
--[[
	@module CombatConfig
	@owner Shared (Agent A: Breight321 & Agent B: anarugod)
	@description Конфигурация боевого цикла: базовые характеристики персонажа, правила зон, мобы, таблицы добычи, сундуки и добровольная PvP-арена.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Types = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Core"):WaitForChild("Types"))

local CombatConfig = {
	-- Базовые характеристики персонажа (на 1 уровне без экипировки и навыков)
	BaseStats = {
		attackPower = 10,
		critChance = 0.05,
		critMultiplier = 1.5,
		maxHealth = 100,
		defense = 0,
		moveSpeed = 16,
		attackCooldown = 0.45,
	},

	-- Прирост характеристик за каждый уровень (ProgressionService)
	PerLevelStats = {
		attackPower = 2,
		maxHealth = 12,
		defense = 1,
	},

	-- Ограничения и константы боевой математики
	MeleeRange = 20,
	MinAttackCooldown = 0.18,
	MaxCritChance = 0.75,
	DefenseConstant = 100, -- damageReduction = defense / (defense + 100)
	MaxDamageReduction = 0.75,
	RewardContributionThreshold = 0.15, -- минимум 15% урона по мобу для получения полной награды

	-- Требования к зонам для боя и открытия сундуков
	ZoneRules = {
		spawn_meadow = {
			zoneId = "spawn_meadow",
			minPlayerLevel = 1,
		},
		crystal_cavern = {
			zoneId = "crystal_cavern",
			minPlayerLevel = 2,
		},
		volcanic_peaks = {
			zoneId = "volcanic_peaks",
			minPlayerLevel = 4,
		},
	},

	-- Определения мобов по зонам
	Mobs = {
		meadow_scrap_drone = {
			id = "meadow_scrap_drone",
			displayName = "Scrap Drone",
			zoneId = "spawn_meadow",
			level = 1,
			maxHealth = 40,
			attackDamage = 6,
			attackIntervalSeconds = 2.0,
			aggroRange = 14,
			respawnSeconds = 4.0,
			rewardXP = 35,
			rewardCoins = 15,
			lootTableId = "loot_mob_meadow",
			spawnPositions = {
				Vector3.new(-28, 3, -10),
				Vector3.new(-28, 3, 10),
			},
		},
		meadow_rust_beetle = {
			id = "meadow_rust_beetle",
			displayName = "Rust Stalker",
			zoneId = "spawn_meadow",
			level = 2,
			maxHealth = 75,
			attackDamage = 10,
			attackIntervalSeconds = 1.8,
			aggroRange = 15,
			respawnSeconds = 5.0,
			rewardXP = 60,
			rewardCoins = 30,
			lootTableId = "loot_mob_meadow",
			spawnPositions = {
				Vector3.new(-42, 3, 0),
			},
		},
		cavern_ember_golem = {
			id = "cavern_ember_golem",
			displayName = "Crystal Sentinel",
			zoneId = "crystal_cavern",
			level = 3,
			maxHealth = 180,
			attackDamage = 22,
			attackIntervalSeconds = 1.8,
			aggroRange = 16,
			respawnSeconds = 6.0,
			rewardXP = 140,
			rewardCoins = 95,
			lootTableId = "loot_mob_cavern",
			spawnPositions = {
				Vector3.new(28, 3, -12),
				Vector3.new(28, 3, 12),
			},
		},
		peaks_frost_colossus = {
			id = "peaks_frost_colossus",
			displayName = "Obsidian Colossus",
			zoneId = "volcanic_peaks",
			level = 5,
			maxHealth = 480,
			attackDamage = 48,
			attackIntervalSeconds = 1.6,
			aggroRange = 18,
			respawnSeconds = 8.0,
			rewardXP = 360,
			rewardCoins = 280,
			lootTableId = "loot_mob_peaks",
			spawnPositions = {
				Vector3.new(0, 3, -55),
			},
		},
	} :: { [string]: Types.MobDef },

	-- Таблицы добычи (серверный взвешенный выбор)
	LootTables = {
		loot_mob_meadow = {
			id = "loot_mob_meadow",
			rolls = 1,
			entries = {
				{ kind = "Currency", id = "Coins", minAmount = 5, maxAmount = 12, weight = 50 },
				{ kind = "Item", id = "scrap_head", minAmount = 1, maxAmount = 1, weight = 13 },
				{ kind = "Item", id = "scrap_arms", minAmount = 1, maxAmount = 1, weight = 13 },
				{ kind = "Item", id = "scrap_torso", minAmount = 1, maxAmount = 1, weight = 12 },
				{ kind = "Item", id = "scrap_legs", minAmount = 1, maxAmount = 1, weight = 12 },
			},
		},
		loot_mob_cavern = {
			id = "loot_mob_cavern",
			rolls = 1,
			entries = {
				{ kind = "Currency", id = "Coins", minAmount = 25, maxAmount = 50, weight = 48 },
				{ kind = "Item", id = "ember_head", minAmount = 1, maxAmount = 1, weight = 13 },
				{ kind = "Item", id = "ember_arms", minAmount = 1, maxAmount = 1, weight = 13 },
				{ kind = "Item", id = "ember_torso", minAmount = 1, maxAmount = 1, weight = 13 },
				{ kind = "Item", id = "ember_legs", minAmount = 1, maxAmount = 1, weight = 13 },
			},
		},
		loot_mob_peaks = {
			id = "loot_mob_peaks",
			rolls = 1,
			entries = {
				{ kind = "Currency", id = "Coins", minAmount = 80, maxAmount = 150, weight = 44 },
				{ kind = "Item", id = "frost_head", minAmount = 1, maxAmount = 1, weight = 14 },
				{ kind = "Item", id = "frost_arms", minAmount = 1, maxAmount = 1, weight = 14 },
				{ kind = "Item", id = "frost_torso", minAmount = 1, maxAmount = 1, weight = 14 },
				{ kind = "Item", id = "frost_legs", minAmount = 1, maxAmount = 1, weight = 14 },
			},
		},
		loot_chest_meadow = {
			id = "loot_chest_meadow",
			rolls = 2,
			entries = {
				{ kind = "Currency", id = "Coins", minAmount = 25, maxAmount = 45, weight = 30, guaranteed = true },
				{ kind = "XP", id = "XP", minAmount = 30, maxAmount = 50, weight = 25 },
				{ kind = "Item", id = "scrap_head", minAmount = 1, maxAmount = 1, weight = 12 },
				{ kind = "Item", id = "scrap_arms", minAmount = 1, maxAmount = 1, weight = 12 },
				{ kind = "Item", id = "scrap_torso", minAmount = 1, maxAmount = 1, weight = 11 },
				{ kind = "Item", id = "scrap_legs", minAmount = 1, maxAmount = 1, weight = 10 },
			},
		},
		loot_chest_cavern = {
			id = "loot_chest_cavern",
			rolls = 2,
			entries = {
				{ kind = "Currency", id = "Coins", minAmount = 90, maxAmount = 160, weight = 30, guaranteed = true },
				{ kind = "XP", id = "XP", minAmount = 80, maxAmount = 130, weight = 22 },
				{ kind = "Item", id = "ember_head", minAmount = 1, maxAmount = 1, weight = 12 },
				{ kind = "Item", id = "ember_arms", minAmount = 1, maxAmount = 1, weight = 12 },
				{ kind = "Item", id = "ember_torso", minAmount = 1, maxAmount = 1, weight = 12 },
				{ kind = "Item", id = "ember_legs", minAmount = 1, maxAmount = 1, weight = 12 },
			},
		},
		loot_chest_peaks = {
			id = "loot_chest_peaks",
			rolls = 2,
			entries = {
				{ kind = "Currency", id = "Coins", minAmount = 300, maxAmount = 500, weight = 28, guaranteed = true },
				{ kind = "XP", id = "XP", minAmount = 200, maxAmount = 320, weight = 20 },
				{ kind = "Item", id = "frost_head", minAmount = 1, maxAmount = 1, weight = 13 },
				{ kind = "Item", id = "frost_arms", minAmount = 1, maxAmount = 1, weight = 13 },
				{ kind = "Item", id = "frost_torso", minAmount = 1, maxAmount = 1, weight = 13 },
				{ kind = "Item", id = "frost_legs", minAmount = 1, maxAmount = 1, weight = 13 },
			},
		},
	} :: { [string]: Types.LootTableDef },

	-- Сундуки в зонах (дополняют фарм мобов: требуют N побеждённых мобов с прошлого открытия + кулдаун)
	Chests = {
		meadow_supply_cache = {
			id = "meadow_supply_cache",
			displayName = "Scrapper Supply Cache",
			zoneId = "spawn_meadow",
			position = Vector3.new(-22, 1, 20),
			interactionRadius = 18,
			minPlayerLevel = 1,
			cooldownSeconds = 60,
			requiredKillsSinceLastOpen = 2,
			lootTableId = "loot_chest_meadow",
		},
		cavern_relic_chest = {
			id = "cavern_relic_chest",
			displayName = "Ember Relic Vault",
			zoneId = "crystal_cavern",
			position = Vector3.new(38, 1, 22),
			interactionRadius = 18,
			minPlayerLevel = 2,
			cooldownSeconds = 120,
			requiredKillsSinceLastOpen = 3,
			lootTableId = "loot_chest_cavern",
		},
		peaks_titan_coffer = {
			id = "peaks_titan_coffer",
			displayName = "Frostforged Coffer",
			zoneId = "volcanic_peaks",
			position = Vector3.new(15, 1, -55),
			interactionRadius = 18,
			minPlayerLevel = 4,
			cooldownSeconds = 180,
			requiredKillsSinceLastOpen = 4,
			lootTableId = "loot_chest_peaks",
		},
	} :: { [string]: Types.ChestDef },

	-- Отдельная добровольная PvP-арена и отдельный от PvE баланс
	Arena = {
		ArenaId = "sunforge_duel_ring",
		DisplayName = "Sunforge Duel Ring",
		EntrancePosition = Vector3.new(0, 1, 42),
		EntranceRadius = 22,
		ArenaCenter = Vector3.new(0, 1, 85),
		ArenaRadius = 36,
		SafeExitPosition = Vector3.new(0, 2, 36),
		MinPlayerLevel = 2,
		CombatTagSeconds = 6.0,
		PvPAttackRange = 18,
		PvPAttackCooldownSeconds = 0.55,

		-- Отдельный баланс PvP (чтобы высокие PvE-множители не убивали с одного удара)
		Balance = {
			DamageScale = 0.45,
			CritMultiplierCap = 1.35,
			MaxSingleHitHealthFraction = 0.35, -- один удар в PvP не может снять более 35% MaxHealth цели
			DefenseEffectivenessMultiplier = 1.25,
		},
	},
}

return table.freeze(CombatConfig)
