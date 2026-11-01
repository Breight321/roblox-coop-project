--!strict
--[[
	@module CombatController/Config
	@owner Agent B (anarugod)
	@description Клиентская конфигурация отображения для Combat Loop v1:
	ссылается на Shared/Config/CombatConfig, BodySetsConfig, SkillTreeConfig и ItemsConfig.
	Все боевые числа, кулдауны, таблицы дропа, сундуки, дерево навыков и правила арены
	берутся напрямую из общих серверно-клиентских конфигов Agent A.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local ConfigFolder = Shared:WaitForChild("Config")

local CombatConfig = require(ConfigFolder:WaitForChild("CombatConfig"))
local BodySetsConfig = require(ConfigFolder:WaitForChild("BodySetsConfig"))
local SkillTreeConfig = require(ConfigFolder:WaitForChild("SkillTreeConfig"))
local ItemsConfig = require(ConfigFolder:WaitForChild("ItemsConfig"))

local ClientCombatConfig = {
	-- Shared configs (single source of truth)
	SharedCombat = CombatConfig,
	BodySets = BodySetsConfig,
	SkillTree = SkillTreeConfig,
	Items = ItemsConfig,

	-- Настройки локального ввода (клиентский анти-спам перед отправкой RequestAttackMob)
	AttackInputCooldownSec = 0.20,
	MaxCombatLockRange = CombatConfig.MeleeRange or 24,

	-- Слоты деталей тела и русские подписи для UI
	BodyPartSlotsOrder = { "Head", "Arms", "Torso", "Legs" },
	SlotLabels = {
		Head = "Голова (Head)",
		Arms = "Руки (Arms)",
		Torso = "Корпус (Torso)",
		Legs = "Ноги (Legs)",
	},
	SlotIcons = {
		Head = "[HEAD]",
		Arms = "[ARMS]",
		Torso = "[CORE]",
		Legs = "[LEGS]",
	},

	-- Ветки дерева навыков
	SkillBranchesOrder = { "Damage", "Defense", "Mobility" },
	BranchLabels = {
		Damage = "Урон",
		Defense = "Защита",
		Mobility = "Мобильность",
	},
	BranchSubtitles = {
		Damage = "Сила удара и криты",
		Defense = "Броня и живучесть",
		Mobility = "Скорость и темп боя",
	},

	-- Краткое описание правил добровольной PvP-арены из CombatConfig.Arena
	ArenaRulesSummary = {
		string.format(
			"Добровольный вход (требуется ур. %d+); обычные зоны полностью безопасны",
			CombatConfig.Arena and CombatConfig.Arena.MinPlayerLevel or 2
		),
		string.format(
			"Отдельный PvP-баланс: урон x%.2f, максимум %.0f%% HP за один удар",
			CombatConfig.Arena and CombatConfig.Arena.Balance and CombatConfig.Arena.Balance.DamageScale or 0.45,
			(CombatConfig.Arena and CombatConfig.Arena.Balance and CombatConfig.Arena.Balance.MaxSingleHitHealthFraction or 0.35) * 100
		),
		string.format(
			"Выход из арены доступен вне боя (Combat Tag: %.0f сек после удара)",
			CombatConfig.Arena and CombatConfig.Arena.CombatTagSeconds or 6
		),
	},
}

return table.freeze(ClientCombatConfig)
