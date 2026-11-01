--!strict
--[[
	@module ItemsConfig
	@owner Shared (Agent A: Breight321 & Agent B: anarugod)
	@description Конфигурация предметов, инструментов, питомцев и экипируемых деталей тела (Head, Arms, Torso, Legs).
	Детали тела используют единый визуальный стиль "ModularMech" и совместимы между наборами (scrapper, ember, frostforged).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Types = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Core"):WaitForChild("Types"))

local ItemsConfig: { [string]: Types.ItemDef } = {
	-- Существующие инструменты и питомцы (100% обратная совместимость)
	starter_wand = {
		id = "starter_wand",
		displayName = "Wooden Wand",
		category = "Tool",
		rarity = "Common",
		powerMultiplier = 1.0,
		coinMultiplier = 1.0,
		description = "Базовый инструмент начинающего игрока.",
	},
	iron_wand = {
		id = "iron_wand",
		displayName = "Iron Collector",
		category = "Tool",
		rarity = "Uncommon",
		powerMultiplier = 2.0,
		coinMultiplier = 1.5,
		description = "Увеличивает добычу монет за клик в 1.5 раза.",
	},
	golden_scepter = {
		id = "golden_scepter",
		displayName = "Golden Scepter",
		category = "Tool",
		rarity = "Rare",
		powerMultiplier = 5.0,
		coinMultiplier = 3.0,
		description = "Утраивает получаемые за клик монеты.",
	},
	ember_fox_pet = {
		id = "ember_fox_pet",
		displayName = "Ember Fox",
		category = "Pet",
		rarity = "Rare",
		powerMultiplier = 1.5,
		coinMultiplier = 1.25,
		description = "Даёт +25% к фарму монет.",
	},

	-- ========================================================================
	-- НАБОР 1: SCRAPPER (Common, Зона 1 — spawn_meadow)
	-- ========================================================================
	scrap_head = {
		id = "scrap_head",
		displayName = "Scrapper Optic Visor",
		category = "BodyHead",
		rarity = "Common",
		stackable = false,
		powerMultiplier = 1.0,
		coinMultiplier = 1.0,
		description = "Оптический визор сборщика: +4% к шансу критического удара и +10 HP.",
		metadata = {
			bodySlot = "Head",
			setId = "scrapper",
			stats = {
				critChance = 0.04,
				maxHealth = 10,
			},
			visual = {
				style = "ModularMech",
				mountSocket = "StdNeckRing_v1",
				primaryColor = "#7A6F64",
				accentColor = "#E0A84A",
				material = "Metal",
				glow = false,
			},
		},
	},
	scrap_arms = {
		id = "scrap_arms",
		displayName = "Scrapper Piston Arms",
		category = "BodyArms",
		rarity = "Common",
		stackable = false,
		powerMultiplier = 1.0,
		coinMultiplier = 1.0,
		description = "Поршневые манипуляторы: +6 к силе атаки.",
		metadata = {
			bodySlot = "Arms",
			setId = "scrapper",
			stats = {
				attackPower = 6,
			},
			visual = {
				style = "ModularMech",
				mountSocket = "StdShoulderMount_v1",
				primaryColor = "#7A6F64",
				accentColor = "#E0A84A",
				material = "Metal",
				glow = false,
			},
		},
	},
	scrap_torso = {
		id = "scrap_torso",
		displayName = "Scrapper Riveted Core",
		category = "BodyTorso",
		rarity = "Common",
		stackable = false,
		powerMultiplier = 1.0,
		coinMultiplier = 1.0,
		description = "Клёпаный нагрудник: +35 HP и +8 к защите.",
		metadata = {
			bodySlot = "Torso",
			setId = "scrapper",
			stats = {
				maxHealth = 35,
				defense = 8,
			},
			visual = {
				style = "ModularMech",
				mountSocket = "StdSpineFrame_v1",
				primaryColor = "#7A6F64",
				accentColor = "#E0A84A",
				material = "Metal",
				glow = false,
			},
		},
	},
	scrap_legs = {
		id = "scrap_legs",
		displayName = "Scrapper Spring Greaves",
		category = "BodyLegs",
		rarity = "Common",
		stackable = false,
		powerMultiplier = 1.0,
		coinMultiplier = 1.0,
		description = "Пружинные поножи: +2 к скорости передвижения и +4 к защите.",
		metadata = {
			bodySlot = "Legs",
			setId = "scrapper",
			stats = {
				moveSpeed = 2,
				defense = 4,
			},
			visual = {
				style = "ModularMech",
				mountSocket = "StdHipJoint_v1",
				primaryColor = "#7A6F64",
				accentColor = "#E0A84A",
				material = "Metal",
				glow = false,
			},
		},
	},

	-- ========================================================================
	-- НАБОР 2: EMBER (Rare, Зона 2 — crystal_cavern)
	-- ========================================================================
	ember_head = {
		id = "ember_head",
		displayName = "Ember Solar Helm",
		category = "BodyHead",
		rarity = "Rare",
		stackable = false,
		powerMultiplier = 1.0,
		coinMultiplier = 1.0,
		description = "Гелио-шлем: +8% к шансу крита, +0.15 к множителю крита и +25 HP.",
		metadata = {
			bodySlot = "Head",
			setId = "ember",
			stats = {
				critChance = 0.08,
				critMultiplier = 0.15,
				maxHealth = 25,
			},
			visual = {
				style = "ModularMech",
				mountSocket = "StdNeckRing_v1",
				primaryColor = "#8C3B2B",
				accentColor = "#E0A84A",
				material = "Neon",
				glow = true,
			},
		},
	},
	ember_arms = {
		id = "ember_arms",
		displayName = "Ember Thermal Gauntlets",
		category = "BodyArms",
		rarity = "Rare",
		stackable = false,
		powerMultiplier = 1.0,
		coinMultiplier = 1.0,
		description = "Термальные рукавицы: +15 к силе атаки и -0.03с к перезарядке удара.",
		metadata = {
			bodySlot = "Arms",
			setId = "ember",
			stats = {
				attackPower = 15,
				attackCooldownReduction = 0.03,
			},
			visual = {
				style = "ModularMech",
				mountSocket = "StdShoulderMount_v1",
				primaryColor = "#8C3B2B",
				accentColor = "#E0A84A",
				material = "Neon",
				glow = true,
			},
		},
	},
	ember_torso = {
		id = "ember_torso",
		displayName = "Ember Furnace Chestplate",
		category = "BodyTorso",
		rarity = "Rare",
		stackable = false,
		powerMultiplier = 1.0,
		coinMultiplier = 1.0,
		description = "Реакторный корпус Горна: +80 HP и +18 к защите.",
		metadata = {
			bodySlot = "Torso",
			setId = "ember",
			stats = {
				maxHealth = 80,
				defense = 18,
			},
			visual = {
				style = "ModularMech",
				mountSocket = "StdSpineFrame_v1",
				primaryColor = "#8C3B2B",
				accentColor = "#E0A84A",
				material = "Neon",
				glow = true,
			},
		},
	},
	ember_legs = {
		id = "ember_legs",
		displayName = "Ember Thruster Striders",
		category = "BodyLegs",
		rarity = "Rare",
		stackable = false,
		powerMultiplier = 1.0,
		coinMultiplier = 1.0,
		description = "Реактивные поножи: +4 к скорости передвижения и +8 к защите.",
		metadata = {
			bodySlot = "Legs",
			setId = "ember",
			stats = {
				moveSpeed = 4,
				defense = 8,
			},
			visual = {
				style = "ModularMech",
				mountSocket = "StdHipJoint_v1",
				primaryColor = "#8C3B2B",
				accentColor = "#E0A84A",
				material = "Neon",
				glow = true,
			},
		},
	},

	-- ========================================================================
	-- НАБОР 3: FROSTFORGED (Epic, Зона 3 — volcanic_peaks)
	-- ========================================================================
	frost_head = {
		id = "frost_head",
		displayName = "Frostforged Aegis Crown",
		category = "BodyHead",
		rarity = "Epic",
		stackable = false,
		powerMultiplier = 1.0,
		coinMultiplier = 1.0,
		description = "Крио-корона Эгиды: +12% к шансу крита, +0.30 к множителю крита и +60 HP.",
		metadata = {
			bodySlot = "Head",
			setId = "frostforged",
			stats = {
				critChance = 0.12,
				critMultiplier = 0.30,
				maxHealth = 60,
			},
			visual = {
				style = "ModularMech",
				mountSocket = "StdNeckRing_v1",
				primaryColor = "#2E5B88",
				accentColor = "#E0A84A",
				material = "Glass",
				glow = true,
			},
		},
	},
	frost_arms = {
		id = "frost_arms",
		displayName = "Frostforged TitanVanguard Arms",
		category = "BodyArms",
		rarity = "Epic",
		stackable = false,
		powerMultiplier = 1.0,
		coinMultiplier = 1.0,
		description = "Крио-кулаки Авангарда: +35 к силе атаки и -0.05с к перезарядке удара.",
		metadata = {
			bodySlot = "Arms",
			setId = "frostforged",
			stats = {
				attackPower = 35,
				attackCooldownReduction = 0.05,
			},
			visual = {
				style = "ModularMech",
				mountSocket = "StdShoulderMount_v1",
				primaryColor = "#2E5B88",
				accentColor = "#E0A84A",
				material = "Glass",
				glow = true,
			},
		},
	},
	frost_torso = {
		id = "frost_torso",
		displayName = "Frostforged Cryo-Core",
		category = "BodyTorso",
		rarity = "Epic",
		stackable = false,
		powerMultiplier = 1.0,
		coinMultiplier = 1.0,
		description = "Крио-ядро: +180 HP и +40 к защите.",
		metadata = {
			bodySlot = "Torso",
			setId = "frostforged",
			stats = {
				maxHealth = 180,
				defense = 40,
			},
			visual = {
				style = "ModularMech",
				mountSocket = "StdSpineFrame_v1",
				primaryColor = "#2E5B88",
				accentColor = "#E0A84A",
				material = "Glass",
				glow = true,
			},
		},
	},
	frost_legs = {
		id = "frost_legs",
		displayName = "Frostforged Glacier Walkers",
		category = "BodyLegs",
		rarity = "Epic",
		stackable = false,
		powerMultiplier = 1.0,
		coinMultiplier = 1.0,
		description = "Крио-приводы: +6 к скорости передвижения и +20 к защите.",
		metadata = {
			bodySlot = "Legs",
			setId = "frostforged",
			stats = {
				moveSpeed = 6,
				defense = 20,
			},
			visual = {
				style = "ModularMech",
				mountSocket = "StdHipJoint_v1",
				primaryColor = "#2E5B88",
				accentColor = "#E0A84A",
				material = "Glass",
				glow = true,
			},
		},
	},
}

return table.freeze(ItemsConfig)
