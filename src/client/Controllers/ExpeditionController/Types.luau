--!strict
--[[
	@module ExpeditionController.Types
	@owner Agent B (anarugod)
	@description Типы состояний и ViewModel для клиентского игрового цикла первого вертикального среза («Aetherfall: Expedition Core»).
]]

export type OperationStatus = "Idle" | "Loading" | "Success" | "Error"

export type UpgradeTrackId = "Tool" | "Bag"

export type UpgradeButtonState =
	"Available"
	| "InsufficientFunds"
	| "MaxLevel"
	| "Loading"
	| "Success"
	| "Error"

export type BagStateViewModel = {
	current: number,
	capacity: number,
	fillRatio: number,
	isNearlyFull: boolean,
	isFull: boolean,
	collectStatus: OperationStatus,
	depositStatus: OperationStatus,
	statusMessage: string,
	guidanceText: string,
	canDeposit: boolean,
	canRetryDeposit: boolean,
	lastError: string?,
}

export type UpgradeTrackViewModel = {
	trackId: UpgradeTrackId,
	displayName: string,
	description: string,
	icon: string,
	level: number,
	maxLevel: number,
	currentValue: number,
	nextValue: number,
	valueUnit: string,
	nextCost: number,
	currencyId: string,
	bankedBalance: number,
	shortageAmount: number,
	canAfford: boolean,
	isMaxLevel: boolean,
	buttonState: UpgradeButtonState,
	buttonText: string,
	statusMessage: string,
	canRetry: boolean,
}

export type TeamProgressViewModel = {
	stageId: string,
	stageNumber: number,
	stageName: string,
	currentAmount: number,
	targetAmount: number,
	progressRatio: number,
	isUnlocked: boolean,
	nextStageName: string,
	lastContributorName: string?,
	lastContributionAmount: number?,
	syncStatus: OperationStatus,
	statusMessage: string,
}

export type UpgradeLevelSpec = {
	level: number,
	value: number,
	upgradeCost: number, -- cost to upgrade FROM this level to level + 1 (0 if max level)
}

export type StageSpec = {
	stageId: string,
	stageNumber: number,
	stageName: string,
	targetAmount: number,
	nextStageName: string,
}

return {}
