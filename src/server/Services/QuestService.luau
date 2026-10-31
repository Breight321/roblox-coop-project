--!strict
--[[
	@module QuestService
	@owner Agent 1 (Breight321)
	@description Серверный бэкенд квестов: отслеживание прогресса и выдача наград.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Core"):WaitForChild("Types"))
local Logger = require(Shared:WaitForChild("Core"):WaitForChild("Logger"))
local Signal = require(Shared:WaitForChild("Core"):WaitForChild("Signal"))
local Network = require(Shared:WaitForChild("Core"):WaitForChild("Network"))

local QuestsConfig = require(Shared:WaitForChild("Config"):WaitForChild("QuestsConfig"))

local QuestService = {
	Name = "QuestService",
	Dependencies = { "PlayerDataService", "EconomyService", "ProgressionService" },
	OnQuestCompleted = Signal.new(),
	OnQuestClaimed = Signal.new(),
}

local log = Logger.new("QuestService")
local playerDataService: any = nil
local economyService: any = nil
local progressionService: any = nil
local claimConn: RBXScriptConnection? = nil

function QuestService:Init(registry: any): ()
	playerDataService = registry:Get("PlayerDataService")
	economyService = registry:Get("EconomyService")
	progressionService = registry:Get("ProgressionService")
	log:Info("Initialized QuestService")
end

function QuestService:Start(): ()
	claimConn = Network.OnServerEvent(Network.Events.RequestClaimQuest, function(player: Player, questId: any)
		if type(questId) == "string" then
			self:ClaimReward(player, questId)
		end
	end)
end

function QuestService:GetPlayerQuests(player: Player): { [string]: Types.QuestState }
	local profRes = playerDataService:GetProfile(player)
	if not profRes.ok or not profRes.value then
		return {}
	end
	return profRes.value.quests
end

function QuestService:IncrementProgress(
	player: Player,
	objectiveType: "Clicks" | "EarnCoins" | "Rebirths" | "UnlockZones",
	amount: number
): ()
	if amount <= 0 then
		return
	end

	local newlyCompleted: { Types.QuestState } = {}

	playerDataService:UpdateProfile(player, function(profile: Types.PlayerProfileData)
		local anyChanged = false
		for questId, def in pairs(QuestsConfig) do
			if def.objectiveType == objectiveType then
				local qState = profile.quests[questId]
				if qState and not qState.completed then
					qState.progress = math.min(qState.target, qState.progress + amount)
					anyChanged = true
					if qState.progress >= qState.target then
						qState.completed = true
						table.insert(newlyCompleted, qState)
					end
				end
			end
		end
		return anyChanged
	end)

	for _, qState in ipairs(newlyCompleted) do
		self.OnQuestCompleted:Fire(player, qState.questId)
		Network.FireClient(player, Network.Events.QuestUpdated, qState)
	end
end

function QuestService:ClaimReward(player: Player, questId: string): Types.Result<boolean, string>
	local def = QuestsConfig[questId]
	if not def then
		return Types.Err("UNKNOWN_QUEST")
	end

	local errCode: string? = nil
	local claimedState: Types.QuestState? = nil

	playerDataService:UpdateProfile(player, function(profile: Types.PlayerProfileData)
		local qState = profile.quests[questId]
		if not qState then
			errCode = "QUEST_STATE_MISSING"
			return false
		end
		if not qState.completed then
			errCode = "QUEST_NOT_COMPLETED"
			return false
		end
		if qState.claimed then
			errCode = "QUEST_ALREADY_CLAIMED"
			return false
		end
		qState.claimed = true
		claimedState = qState
		return true
	end)

	if errCode then
		return Types.Err(errCode)
	end

	economyService:AddCurrency(player, def.rewardCurrency, def.rewardAmount, "QuestReward:" .. questId)
	if def.rewardXP > 0 then
		progressionService:AddXP(player, def.rewardXP)
	end

	if claimedState then
		Network.FireClient(player, Network.Events.QuestUpdated, claimedState)
	end
	self.OnQuestClaimed:Fire(player, questId)
	return Types.Ok(true)
end

function QuestService:Shutdown(): ()
	if claimConn then
		claimConn:Disconnect()
		claimConn = nil
	end
	log:Info("Shutdown QuestService")
end

return QuestService
