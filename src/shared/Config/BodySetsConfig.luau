--!strict
--[[
	@module BodySetsConfig
	@owner Shared (Agent A: Breight321 & Agent B: anarugod)
	@description Конфигурация комплектов деталей тела (Body Sets) и бонусов за сборку полного набора (4 слота: Head, Arms, Torso, Legs).
	Все наборы совместимы между собой благодаря единому стандарту креплений ModularMech и общему золотому акценту (#E0A84A).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Types = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Core"):WaitForChild("Types"))

local BodySetsConfig: { [string]: Types.BodySetDef } = {
	scrapper = {
		id = "scrapper",
		displayName = "Scrapper Rig",
		description = "Надёжный стартовый экзо-комплект: +10% к силе атаки и +10% к макс. здоровью при полной сборке.",
		requiredPieceCount = 4,
		fullSetBonus = {
			attackPowerPct = 0.10,
			maxHealthPct = 0.10,
		},
		visualTheme = {
			style = "ModularMech",
			primaryColor = "#7A6F64",
			accentColor = "#E0A84A",
			material = "Metal",
			glow = false,
		},
	},
	ember = {
		id = "ember",
		displayName = "Ember Vanguard",
		description = "Боевой комплект Солнечного Горна: +20% к атаке, +15% к здоровью и +5% к крит. шансу.",
		requiredPieceCount = 4,
		fullSetBonus = {
			attackPowerPct = 0.20,
			maxHealthPct = 0.15,
			critChance = 0.05,
		},
		visualTheme = {
			style = "ModularMech",
			primaryColor = "#8C3B2B",
			accentColor = "#E0A84A",
			material = "Neon",
			glow = true,
		},
	},
	frostforged = {
		id = "frostforged",
		displayName = "Frostforged Aegis",
		description = "Элитный крио-доспех: +35% к атаке, +30% к здоровью и +2 к скорости передвижения.",
		requiredPieceCount = 4,
		fullSetBonus = {
			attackPowerPct = 0.35,
			maxHealthPct = 0.30,
			moveSpeed = 2,
		},
		visualTheme = {
			style = "ModularMech",
			primaryColor = "#2E5B88",
			accentColor = "#E0A84A",
			material = "Glass",
			glow = true,
		},
	},
}

return table.freeze(BodySetsConfig)
