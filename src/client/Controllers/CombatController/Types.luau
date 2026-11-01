--!strict
--[[
	@module CombatController/Types
	@owner Agent B (anarugod)
	@description Строгие типы клиентского контроллера Combat Loop v1:
	бой с мобами, инвентарь и сборка деталей тела (Head, Arms, Torso, Legs + BodySetsConfig),
	сундуки (ChestStateSync / ChestResult), дерево навыков (SkillTreeConfig: Damage, Defense, Mobility)
	и добровольная PvP-арена (ArenaStateChanged / PvPCombatResult).
]]

export type BodyPartSlot = "Head" | "Arms" | "Torso" | "Legs"
export type SkillBranch = "Damage" | "Defense" | "Mobility"
export type ActionAsyncStatus = "Idle" | "Loading" | "Success" | "Error"
export type PvpZoneState = "SafeZone" | "Entering" | "InArena" | "Leaving"

export type BodyPartBonuses = {
	attackPower: number,
	defense: number,
	maxHealth: number,
	moveSpeed: number,
	critChance: number,
	critMultiplier: number,
	attackCooldownReduction: number,
	setId: string,
	setName: string,
	visualStyle: string,
	primaryColorHex: string,
	accentColorHex: string,
}

export type BodyPartViewModel = {
	uid: string,
	itemId: string,
	displayName: string,
	slot: BodyPartSlot,
	category: string,
	rarity: string,
	level: number,
	equipped: boolean,
	description: string,
	bonuses: BodyPartBonuses,
	deltaAttackPower: number,
	deltaDefense: number,
	deltaMaxHealth: number,
	deltaMoveSpeed: number,
	deltaCritChance: number,
	isPendingEquip: boolean,
}

export type AssemblyStatsSummary = {
	level: number,
	attackPower: number,
	defense: number,
	damageReductionPct: number,
	maxHealth: number,
	moveSpeed: number,
	critChancePct: number,
	critMultiplier: number,
	attackCooldown: number,
	equippedCount: number,
	equippedBySlot: { [string]: BodyPartViewModel? },
	activeSetId: string?,
	activeSetName: string?,
	activeSetDescription: string?,
	setCounts: { [string]: number },
	lastDeltaSummary: string?,
}

export type MobTargetViewModel = {
	mobUid: string,
	mobId: string,
	zoneId: string,
	displayName: string,
	level: number,
	currentHp: number,
	maxHp: number,
	hpRatio: number,
	defeated: boolean,
	lastHitDamage: number?,
	lastHitCrit: boolean?,
	lastRewardText: string?,
	lastErrorText: string?,
}

export type CombatHitFeedback = {
	ok: boolean,
	mobUid: string,
	mobId: string,
	damageDealt: number,
	isCrit: boolean,
	currentHp: number,
	maxHp: number,
	defeated: boolean,
	rewardText: string?,
	errorCode: string?,
	message: string?,
}

export type ChestDefViewModel = {
	id: string,
	zoneId: string,
	displayName: string,
	minPlayerLevel: number,
	cooldownSeconds: number,
	requiredKills: number,
	killsProgress: number,
	readyAtUnix: number,
	isReady: boolean,
	description: string,
	dropPreviewText: string,
	status: ActionAsyncStatus,
	statusMessage: string?,
	lastRewardText: string?,
	lastDropsCount: number,
}

export type SkillNodeViewModel = {
	id: string,
	branch: SkillBranch,
	tier: number,
	displayName: string,
	description: string,
	bonusText: string,
	costPoints: number,
	requiredLevel: number,
	requires: { string },
	isUnlocked: boolean,
	canUnlock: boolean,
	hasEnoughPoints: boolean,
	meetsLevel: boolean,
	meetsPrereqs: boolean,
	status: ActionAsyncStatus,
	statusMessage: string?,
}

export type SkillTreeSummaryViewModel = {
	availablePoints: number,
	spentPoints: number,
	earnedPoints: number,
	unlockedCount: number,
}

export type ArenaStateViewModel = {
	zoneState: PvpZoneState,
	isSafeZone: boolean,
	arenaId: string,
	arenaDisplayName: string,
	minPlayerLevel: number,
	combatTaggedSeconds: number,
	statusText: string,
	rulesSummary: { string },
	lastMatchOutcome: ("Victory" | "Defeat" | "Hit" | "None")?,
	lastMatchMessage: string?,
	pvpKills: number,
	pvpDeaths: number,
}

return {}
