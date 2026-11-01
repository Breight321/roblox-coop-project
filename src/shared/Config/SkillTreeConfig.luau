--!strict
--[[
	@module SkillTreeConfig
	@owner Shared (Agent A: Breight321 & Agent B: anarugod)
	@description Конфигурация пассивного дерева навыков (ветки Damage, Defense, Mobility).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Types = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Core"):WaitForChild("Types"))

local SkillTreeConfig = {
	PointsPerLevel = 1,
	StartingPoints = 1,

	Nodes = {
		-- ====================================================================
		-- ВЕТКА УРОНА (Damage)
		-- ====================================================================
		dmg_1 = {
			id = "dmg_1",
			displayName = "Kinetic Calibration I",
			branch = "Damage",
			tier = 1,
			cost = 1,
			requiredLevel = 1,
			requires = {},
			bonuses = {
				attackPower = 4,
			},
			description = "+4 к базовой силе атаки.",
		},
		dmg_2 = {
			id = "dmg_2",
			displayName = "Precision Optics II",
			branch = "Damage",
			tier = 2,
			cost = 1,
			requiredLevel = 2,
			requires = { "dmg_1" },
			bonuses = {
				critChance = 0.06,
				critMultiplier = 0.15,
			},
			description = "+6% к шансу крита и +0.15x к критическому урону.",
		},
		dmg_3 = {
			id = "dmg_3",
			displayName = "Overcharge Core III",
			branch = "Damage",
			tier = 3,
			cost = 2,
			requiredLevel = 4,
			requires = { "dmg_2" },
			bonuses = {
				attackPowerPct = 0.15,
			},
			description = "+15% к итоговой силе атаки.",
		},

		-- ====================================================================
		-- ВЕТКА ЗАЩИТЫ (Defense)
		-- ====================================================================
		def_1 = {
			id = "def_1",
			displayName = "Plating Reinforcement I",
			branch = "Defense",
			tier = 1,
			cost = 1,
			requiredLevel = 1,
			requires = {},
			bonuses = {
				maxHealth = 25,
				defense = 6,
			},
			description = "+25 к здоровью и +6 к броне.",
		},
		def_2 = {
			id = "def_2",
			displayName = "Shock Absorbers II",
			branch = "Defense",
			tier = 2,
			cost = 1,
			requiredLevel = 2,
			requires = { "def_1" },
			bonuses = {
				maxHealth = 50,
				defense = 14,
			},
			description = "+50 к здоровью и +14 к броне.",
		},
		def_3 = {
			id = "def_3",
			displayName = "Bastion Protocol III",
			branch = "Defense",
			tier = 3,
			cost = 2,
			requiredLevel = 4,
			requires = { "def_2" },
			bonuses = {
				maxHealthPct = 0.20,
				defense = 25,
			},
			description = "+20% к максимальному здоровью и +25 к броне.",
		},

		-- ====================================================================
		-- ВЕТКА МОБИЛЬНОСТИ (Mobility)
		-- ====================================================================
		mob_1 = {
			id = "mob_1",
			displayName = "Servo Tuning I",
			branch = "Mobility",
			tier = 1,
			cost = 1,
			requiredLevel = 1,
			requires = {},
			bonuses = {
				moveSpeed = 2,
			},
			description = "+2 к скорости передвижения.",
		},
		mob_2 = {
			id = "mob_2",
			displayName = "Rapid Actuators II",
			branch = "Mobility",
			tier = 2,
			cost = 1,
			requiredLevel = 2,
			requires = { "mob_1" },
			bonuses = {
				attackCooldownReduction = 0.05,
				moveSpeed = 1,
			},
			description = "-0.05с к перезарядке атаки и +1 к скорости передвижения.",
		},
		mob_3 = {
			id = "mob_3",
			displayName = "Phase Thrusters III",
			branch = "Mobility",
			tier = 3,
			cost = 2,
			requiredLevel = 4,
			requires = { "mob_2" },
			bonuses = {
				moveSpeed = 3,
				attackCooldownReduction = 0.05,
			},
			description = "+3 к скорости передвижения и ещё -0.05с к перезарядке атаки.",
		},
	} :: { [string]: Types.SkillNodeDef },
}

return table.freeze(SkillTreeConfig)
