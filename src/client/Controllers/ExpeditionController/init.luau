--!strict
--[[
	@module ExpeditionController
	@owner Agent B (anarugod)
	@description Контроллер клиентского игрового цикла первого вертикального среза «Sunforge Expedition»:
	- Интегрирован с серверным HarvestService (Agent A) через согласованный контракт в Network.Events и HarvestConfig:
	  - RequestHarvest(nodeId) -> HarvestResult, HarvestStateSync
	  - RequestDeposit(stationId) -> DepositResult, HarvestStateSync, ServerProgressUpdated
	  - RequestHarvestUpgrade(upgradeType) -> HarvestUpgradeResult, HarvestStateSync
	- Никогда не изменяет баланс, вместимость сумки, уровни улучшений и общий прогресс сервера локально как финальные значения.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Core"):WaitForChild("Types"))
local Logger = require(Shared:WaitForChild("Core"):WaitForChild("Logger"))
local Signal = require(Shared:WaitForChild("Core"):WaitForChild("Signal"))
local Network = require(Shared:WaitForChild("Core"):WaitForChild("Network"))
local HarvestConfig = require(Shared:WaitForChild("Config"):WaitForChild("HarvestConfig"))

local ExpeditionTypes = require(script:WaitForChild("Types"))
local Config = require(script:WaitForChild("Config"))

local ExpeditionController = {
	Name = "ExpeditionController",
	Dependencies = { "AudioController", "AnimationController" },
	OnStateChanged = Signal.new(),
	OnBagUpdated = Signal.new(),
	OnDepositResolved = Signal.new(),
	OnUpgradeResolved = Signal.new(),
	OnTeamProgressChanged = Signal.new(),
	OnStageUnlocked = Signal.new(),
	OnCollectFeedback = Signal.new(),
}

local log = Logger.new("ExpeditionController")
local audioController: any = nil
local animationController: any = nil

-- Подтверждённые сервером данные (клиент НИКОГДА не мутирует их локально как финальные значения)
local bankedCoins = 0
local bagCurrent = 0
local bagCapacity = HarvestConfig.BagUpgrades[1].capacity

local toolLevel = 1
local bagLevel = 1
local serverHarvestPower: number? = nil
local serverNextToolPrice: number? = nil
local serverNextBagPrice: number? = nil

local currentServerStage = 1
local serverTotalDeposited = 0
local currentStageTarget = HarvestConfig.ServerMilestones[1].targetDeposited
local currentStageRatio = 0
local currentStageTitle = HarvestConfig.ServerMilestones[1].title
local currentStageDescription = HarvestConfig.ServerMilestones[1].description
local isMaxServerStage = false
local unlockedExtractionZones: { [string]: boolean } = {
	[HarvestConfig.DefaultNodeId] = true,
}

-- Клиентские состояния запросов (UI State Machine)
local collectStatus: ExpeditionTypes.OperationStatus = "Idle"
local depositStatus: ExpeditionTypes.OperationStatus = "Idle"
local bagStatusMessage = "Добывайте Solar Shards в кратере Sunforge и сдавайте на Станции Переплавки"
local lastDepositError: string? = nil
local lastStationId: string = HarvestConfig.DefaultStationId
local activeExtractionNodeId: string = HarvestConfig.DefaultNodeId

local upgradeTransientState: { [ExpeditionTypes.UpgradeTrackId]: ExpeditionTypes.OperationStatus } = {
	Tool = "Idle",
	Bag = "Idle",
}
local upgradeStatusMessage: { [ExpeditionTypes.UpgradeTrackId]: string } = {
	Tool = "Готово к улучшению",
	Bag = "Готово к улучшению",
}
local upgradeCanRetry: { [ExpeditionTypes.UpgradeTrackId]: boolean } = {
	Tool = false,
	Bag = false,
}

local teamSyncStatus: ExpeditionTypes.OperationStatus = "Idle"

local lastCollectClock = 0
local lastDepositClock = 0
local lastUpgradeClock = 0

local rbxConnections: { RBXScriptConnection } = {}

local function normalizeNodeId(rawNodeId: string?): string
	if type(rawNodeId) == "string" and #rawNodeId > 0 then
		if HarvestConfig.ExtractionZones[rawNodeId] then
			return rawNodeId
		end
	end
	return activeExtractionNodeId or HarvestConfig.DefaultNodeId
end

local function normalizeStationId(rawStationId: string?): string
	if type(rawStationId) == "string" and #rawStationId > 0 then
		if HarvestConfig.DepositStations[rawStationId] then
			return rawStationId
		end
	end
	return HarvestConfig.DefaultStationId
end

local function emitStateChanged(): ()
	ExpeditionController.OnStateChanged:Fire()
end

function ExpeditionController:Init(registry: any): ()
	audioController = registry:TryGet("AudioController")
	animationController = registry:TryGet("AnimationController")
	log:Info("Initialized ExpeditionController (%s)", Config.GameTitle)
end

function ExpeditionController:Start(): ()
	table.insert(
		rbxConnections,
		Network.OnClientEvent(Network.Events.PlayerDataSync, function(profile: Types.PlayerProfileData)
			self:ApplyServerProfileSync(profile)
		end)
	)

	table.insert(
		rbxConnections,
		Network.OnClientEvent(
			Network.Events.CurrencyUpdated,
			function(currencyId: Types.CurrencyId, newBalance: number, delta: number)
				self:ApplyServerCurrencyUpdate(currencyId, newBalance, delta)
			end
		)
	)

	table.insert(
		rbxConnections,
		Network.OnClientEvent(Network.Events.HarvestStateSync, function(state: Types.HarvestStatePayload)
			self:ApplyServerHarvestStateSync(state)
		end)
	)

	table.insert(
		rbxConnections,
		Network.OnClientEvent(Network.Events.HarvestResult, function(result: Types.HarvestResultPayload)
			self:ApplyServerHarvestResult(result)
		end)
	)

	table.insert(
		rbxConnections,
		Network.OnClientEvent(Network.Events.DepositResult, function(result: Types.DepositResultPayload)
			self:ApplyServerDepositResult(result)
		end)
	)

	table.insert(
		rbxConnections,
		Network.OnClientEvent(Network.Events.HarvestUpgradeResult, function(result: Types.UpgradeResultPayload)
			self:ApplyServerUpgradeResult(result)
		end)
	)

	table.insert(
		rbxConnections,
		Network.OnClientEvent(Network.Events.ServerProgressUpdated, function(progress: Types.ServerProgressPayload)
			self:ApplyServerProgressUpdated(progress)
		end)
	)

	log:Info("Started ExpeditionController")
end

-- ============================================================================
-- VIEW MODEL GETTERS (Read-only snapshots of server-confirmed state + UI status)
-- ============================================================================

function ExpeditionController:GetBankedBalance(): number
	return bankedCoins
end

function ExpeditionController:SetActiveExtractionZone(nodeId: string): ()
	if HarvestConfig.ExtractionZones[nodeId] then
		activeExtractionNodeId = nodeId
		emitStateChanged()
	end
end

function ExpeditionController:GetActiveExtractionZone(): string
	return activeExtractionNodeId
end

function ExpeditionController:IsExtractionZoneUnlocked(nodeId: string): boolean
	return unlockedExtractionZones[nodeId] == true
end

function ExpeditionController:GetBagState(): ExpeditionTypes.BagStateViewModel
	local safeCapacity = math.max(1, bagCapacity)
	local fillRatio = math.clamp(bagCurrent / safeCapacity, 0, 1)
	local isFull = bagCurrent >= safeCapacity
	local isNearlyFull = not isFull and fillRatio >= Config.BagAlmostFullThreshold

	local guidance = "⛏️ Собирайте Solar Shards в кратере Sunforge (Клик / [E])"
	if depositStatus == "Loading" then
		guidance = "⏳ Сдача добычи на Станции Переплавки... Ожидание подтверждения сервера"
	elseif depositStatus == "Error" then
		guidance = string.format(
			"⚠️ Отказ сдачи: %s. Подойдите к станции или нажмите «Повтор».",
			lastDepositError or "ошибка сдачи"
		)
	elseif depositStatus == "Success" then
		guidance = "✓ Добыча переплавлена в Монеты и зачислена в общую цель сервера!"
	elseif isFull then
		guidance = "🚨 СУМКА ПОЛНА! Отнесите Solar Shards на Станцию Переплавки (Central Refinery)!"
	elseif isNearlyFull then
		guidance = "⚠️ Сумка почти заполнена — пора отнести добычу на Станцию Переплавки!"
	elseif bagCurrent > 0 then
		guidance = string.format(
			"🎒 В сумке %d / %d Solar Shards — сдайте на Станции Переплавки для получения Монет",
			bagCurrent,
			safeCapacity
		)
	end

	return {
		current = bagCurrent,
		capacity = safeCapacity,
		fillRatio = fillRatio,
		isNearlyFull = isNearlyFull,
		isFull = isFull,
		collectStatus = collectStatus,
		depositStatus = depositStatus,
		statusMessage = bagStatusMessage,
		guidanceText = guidance,
		canDeposit = bagCurrent > 0 and depositStatus ~= "Loading",
		canRetryDeposit = depositStatus == "Error" and bagCurrent > 0,
		lastError = lastDepositError,
	}
end

function ExpeditionController:GetUpgradeTrack(
	trackId: ExpeditionTypes.UpgradeTrackId
): ExpeditionTypes.UpgradeTrackViewModel
	local isTool = trackId == "Tool"
	local meta = if isTool then Config.ToolTrackMeta else Config.BagTrackMeta
	local maxLvl = if isTool then #HarvestConfig.ToolUpgrades else #HarvestConfig.BagUpgrades
	local currentLvl = math.clamp(if isTool then toolLevel else bagLevel, 1, maxLvl)
	local isMax = currentLvl >= maxLvl

	local currentVal = 0
	local nextVal = 0
	local nextCost = 0
	local currentTierName = ""
	local nextTierName = ""

	if isTool then
		local currDef = HarvestConfig.ToolUpgrades[currentLvl] or HarvestConfig.ToolUpgrades[1]
		local nextDef = HarvestConfig.ToolUpgrades[currentLvl + 1]
		currentVal = serverHarvestPower or currDef.harvestPower
		nextVal = if nextDef then nextDef.harvestPower else currentVal
		nextCost = if nextDef then (serverNextToolPrice or nextDef.priceCoins) else 0
		currentTierName = currDef.displayName
		nextTierName = if nextDef then nextDef.displayName else currDef.displayName
		if serverNextToolPrice == nil and nextDef == nil then
			isMax = true
		end
	else
		local currDef = HarvestConfig.BagUpgrades[currentLvl] or HarvestConfig.BagUpgrades[1]
		local nextDef = HarvestConfig.BagUpgrades[currentLvl + 1]
		currentVal = bagCapacity
		nextVal = if nextDef then nextDef.capacity else currentVal
		nextCost = if nextDef then (serverNextBagPrice or nextDef.priceCoins) else 0
		currentTierName = currDef.displayName
		nextTierName = if nextDef then nextDef.displayName else currDef.displayName
		if serverNextBagPrice == nil and nextDef == nil then
			isMax = true
		end
	end

	local canAfford = (not isMax) and (bankedCoins >= nextCost)
	local shortage = if isMax then 0 else math.max(0, nextCost - bankedCoins)
	local transient = upgradeTransientState[trackId] or "Idle"

	local buttonState: ExpeditionTypes.UpgradeButtonState = "Available"
	local buttonText = string.format("УЛУЧШИТЬ • %d Монет", nextCost)

	if transient == "Loading" then
		buttonState = "Loading"
		buttonText = "⏳ УЛУЧШЕНИЕ..."
	elseif transient == "Success" then
		buttonState = "Success"
		buttonText = string.format("✓ УРОВЕНЬ %d!", currentLvl)
	elseif transient == "Error" then
		buttonState = "Error"
		buttonText = if upgradeCanRetry[trackId] then "✗ ОШИБКА (ПОВТОР)" else "✗ ОТКАЗ"
	elseif isMax then
		buttonState = "MaxLevel"
		buttonText = "МАКС. УРОВЕНЬ"
	elseif not canAfford then
		buttonState = "InsufficientFunds"
		buttonText = string.format("НУЖНО %d МОНЕТ", nextCost)
	end

	local descText = if isMax
		then string.format("%s (Максимум)", currentTierName)
		else string.format("Сейчас: %s → След.: %s", currentTierName, nextTierName)

	return {
		trackId = trackId,
		displayName = meta.displayName,
		description = descText,
		icon = meta.icon,
		level = currentLvl,
		maxLevel = maxLvl,
		currentValue = currentVal,
		nextValue = nextVal,
		valueUnit = meta.valueUnit,
		nextCost = nextCost,
		currencyId = meta.currencyId,
		bankedBalance = bankedCoins,
		shortageAmount = shortage,
		canAfford = canAfford,
		isMaxLevel = isMax,
		buttonState = buttonState,
		buttonText = buttonText,
		statusMessage = upgradeStatusMessage[trackId] or "",
		canRetry = upgradeCanRetry[trackId] == true,
	}
end

function ExpeditionController:GetTeamProgress(): ExpeditionTypes.TeamProgressViewModel
	local nextMilestone = HarvestConfig.ServerMilestones[currentServerStage + 1]
	local nextStageLabel = if nextMilestone
		then nextMilestone.title
		else "Все этапы Горна открыты (Бонус x2.0)"

	return {
		stageId = if currentServerStage >= 3
			then "helios_vault"
			elseif currentServerStage == 2 then "amber_canyon"
			else "sunforge_crater",
		stageNumber = currentServerStage,
		stageName = currentStageTitle,
		currentAmount = serverTotalDeposited,
		targetAmount = math.max(1, currentStageTarget),
		progressRatio = math.clamp(currentStageRatio, 0, 1),
		isUnlocked = currentServerStage > 1 or isMaxServerStage,
		nextStageName = nextStageLabel,
		lastContributorName = nil,
		lastContributionAmount = nil,
		syncStatus = teamSyncStatus,
		statusMessage = currentStageDescription,
	}
end

-- ============================================================================
-- CLIENT -> SERVER INTENT REQUESTS (Never mutates authoritative values locally)
-- ============================================================================

function ExpeditionController:RequestCollect(
	nodeId: string?,
	_equippedToolUid: string?
): Types.Result<boolean, string>
	local bag = self:GetBagState()
	if bag.isFull then
		collectStatus = "Error"
		bagStatusMessage = "Сумка полна! Сдайте Solar Shards на Станции Переплавки (Central Refinery)."
		if audioController then
			audioController:PlaySFX("Error")
		end
		emitStateChanged()
		return Types.Err("BAG_FULL")
	end

	local now = os.clock()
	if (now - lastCollectClock) < Config.CollectCooldownSeconds then
		return Types.Err("COLLECT_COOLDOWN")
	end
	lastCollectClock = now

	local targetNodeId = normalizeNodeId(nodeId)
	collectStatus = "Loading"
	bagStatusMessage = "Добыча Solar Shards... ожидание ответа сервера"

	if audioController then
		audioController:PlaySFX("Click", 0.08)
	end
	if animationController then
		animationController:PlayActionAnimation("SunforgeHarvestSwing")
	end

	self.OnCollectFeedback:Fire(targetNodeId)
	Network.FireServer(Network.Events.RequestHarvest, targetNodeId)

	emitStateChanged()
	return Types.Ok(true)
end

function ExpeditionController:RequestDeposit(stationId: string?): Types.Result<boolean, string>
	if depositStatus == "Loading" then
		return Types.Err("DEPOSIT_IN_PROGRESS")
	end

	if bagCurrent <= 0 then
		depositStatus = "Error"
		lastDepositError = "Сумка пуста — сначала соберите Solar Shards в кратере"
		bagStatusMessage = lastDepositError
		if audioController then
			audioController:PlaySFX("Error")
		end
		emitStateChanged()
		return Types.Err("BAG_EMPTY")
	end

	local now = os.clock()
	if (now - lastDepositClock) < Config.DepositCooldownSeconds then
		return Types.Err("RATE_LIMITED")
	end
	lastDepositClock = now

	lastStationId = normalizeStationId(stationId)
	depositStatus = "Loading"
	lastDepositError = nil
	bagStatusMessage = "⏳ Отправка добычи на Станцию Переплавки..."

	if audioController then
		audioController:PlaySFX("UIButton")
	end

	Network.FireServer(Network.Events.RequestDeposit, lastStationId)
	emitStateChanged()
	return Types.Ok(true)
end

function ExpeditionController:RetryDeposit(): Types.Result<boolean, string>
	if depositStatus == "Loading" then
		return Types.Err("DEPOSIT_IN_PROGRESS")
	end
	depositStatus = "Idle"
	lastDepositClock = 0
	return self:RequestDeposit(lastStationId)
end

function ExpeditionController:RequestUpgrade(
	trackId: ExpeditionTypes.UpgradeTrackId
): Types.Result<boolean, string>
	if trackId ~= "Tool" and trackId ~= "Bag" then
		return Types.Err("INVALID_UPGRADE_TYPE")
	end

	if upgradeTransientState[trackId] == "Loading" then
		return Types.Err("UPGRADE_IN_PROGRESS")
	end

	local now = os.clock()
	if (now - lastUpgradeClock) < Config.UpgradeCooldownSeconds then
		return Types.Err("RATE_LIMITED")
	end

	local vm = self:GetUpgradeTrack(trackId)
	if vm.isMaxLevel then
		upgradeTransientState[trackId] = "Error"
		upgradeStatusMessage[trackId] = "Достигнут максимальный уровень улучшения!"
		emitStateChanged()
		return Types.Err("MAX_LEVEL_REACHED")
	end

	if not vm.canAfford then
		upgradeTransientState[trackId] = "Error"
		upgradeCanRetry[trackId] = false
		upgradeStatusMessage[trackId] = string.format(
			"Не хватает средств в банке! Нужно %d Монет (не хватает ещё %d).",
			vm.nextCost,
			vm.shortageAmount
		)
		if audioController then
			audioController:PlaySFX("Error")
		end
		emitStateChanged()

		task.delay(Config.FeedbackResetSeconds, function()
			if upgradeTransientState[trackId] == "Error" and not upgradeCanRetry[trackId] then
				upgradeTransientState[trackId] = "Idle"
				emitStateChanged()
			end
		end)
		return Types.Err("INSUFFICIENT_FUNDS")
	end

	lastUpgradeClock = now
	upgradeTransientState[trackId] = "Loading"
	upgradeCanRetry[trackId] = false
	upgradeStatusMessage[trackId] = "⏳ Отправка запроса на улучшение серверу..."

	if audioController then
		audioController:PlaySFX("UIButton")
	end

	Network.FireServer(Network.Events.RequestHarvestUpgrade, trackId)
	emitStateChanged()
	return Types.Ok(true)
end

function ExpeditionController:RetryUpgrade(
	trackId: ExpeditionTypes.UpgradeTrackId
): Types.Result<boolean, string>
	if trackId ~= "Tool" and trackId ~= "Bag" then
		return Types.Err("INVALID_UPGRADE_TYPE")
	end
	if upgradeTransientState[trackId] == "Loading" then
		return Types.Err("UPGRADE_IN_PROGRESS")
	end
	upgradeTransientState[trackId] = "Idle"
	upgradeCanRetry[trackId] = false
	lastUpgradeClock = 0
	return self:RequestUpgrade(trackId)
end

function ExpeditionController:RequestTeamSync(): Types.Result<boolean, string>
	teamSyncStatus = "Idle"
	emitStateChanged()
	return Types.Ok(true)
end

-- ============================================================================
-- SERVER -> CLIENT CONFIRMATION HANDLERS (Single source of truth)
-- ============================================================================

function ExpeditionController:ApplyServerProfileSync(profile: Types.PlayerProfileData): ()
	if type(profile) ~= "table" then
		return
	end

	if profile.currencies and type(profile.currencies.Coins) == "number" then
		bankedCoins = profile.currencies.Coins
	end

	if type(profile.harvestState) == "table" then
		local hs = profile.harvestState
		if type(hs.toolLevel) == "number" then
			toolLevel = math.clamp(hs.toolLevel, 1, #HarvestConfig.ToolUpgrades)
		end
		if type(hs.bagLevel) == "number" then
			bagLevel = math.clamp(hs.bagLevel, 1, #HarvestConfig.BagUpgrades)
			local bagDef = HarvestConfig.BagUpgrades[bagLevel]
			if bagDef then
				bagCapacity = bagDef.capacity
			end
		end
		if type(hs.bagStored) == "number" then
			bagCurrent = math.clamp(hs.bagStored, 0, bagCapacity)
		end
	end

	emitStateChanged()
end

function ExpeditionController:ApplyServerCurrencyUpdate(
	currencyId: Types.CurrencyId,
	newBalance: number,
	_delta: number
): ()
	if currencyId == "Coins" and type(newBalance) == "number" then
		bankedCoins = newBalance
		emitStateChanged()
	end
end

function ExpeditionController:ApplyServerHarvestStateSync(state: Types.HarvestStatePayload): ()
	if type(state) ~= "table" then
		return
	end

	if type(state.bagCapacity) == "number" and state.bagCapacity > 0 then
		bagCapacity = state.bagCapacity
	end
	if type(state.bagStored) == "number" then
		bagCurrent = math.clamp(state.bagStored, 0, bagCapacity)
	end
	if type(state.toolLevel) == "number" and state.toolLevel >= 1 then
		toolLevel = state.toolLevel
	end
	if type(state.bagLevel) == "number" and state.bagLevel >= 1 then
		bagLevel = state.bagLevel
	end
	if type(state.harvestPower) == "number" then
		serverHarvestPower = state.harvestPower
	end
	serverNextToolPrice = state.nextToolPrice
	serverNextBagPrice = state.nextBagPrice

	self.OnBagUpdated:Fire(self:GetBagState())
	emitStateChanged()
end

function ExpeditionController:ApplyServerHarvestResult(result: Types.HarvestResultPayload): ()
	if type(result) ~= "table" then
		return
	end

	if type(result.bagCapacity) == "number" and result.bagCapacity > 0 then
		bagCapacity = result.bagCapacity
	end
	if type(result.bagStored) == "number" then
		bagCurrent = math.clamp(result.bagStored, 0, bagCapacity)
	end

	if result.ok then
		collectStatus = "Success"
		local added = result.addedAmount or 0
		if result.isBagFull or bagCurrent >= bagCapacity then
			bagStatusMessage = "🚨 Сумка заполнена! Отнесите Solar Shards на Станцию Переплавки!"
		else
			bagStatusMessage = string.format(
				"✓ Добыто +%d Solar Shards (%d / %d в сумке)",
				added,
				bagCurrent,
				bagCapacity
			)
		end
	else
		collectStatus = "Error"
		bagStatusMessage = tostring(result.message or result.errorCode or "Ошибка добычи")
		if result.errorCode ~= "HARVEST_COOLDOWN" and audioController then
			audioController:PlaySFX("Error")
		end
	end

	self.OnBagUpdated:Fire(self:GetBagState())
	emitStateChanged()
end

-- Совместимый адаптер для модульных тестов и прямого обновления сумки
function ExpeditionController:ApplyServerBagUpdate(arg1: any, arg2: any, arg3: any): ()
	if type(arg1) == "table" then
		if arg1.bagStored ~= nil then
			self:ApplyServerHarvestStateSync(arg1)
			return
		end
		local cap = arg1.capacity or arg1.bagCapacity or bagCapacity
		local curr = arg1.current or arg1.bagCurrent or bagCurrent
		local delta = arg1.delta or 0
		self:ApplyServerHarvestResult({
			ok = true,
			nodeId = activeExtractionNodeId,
			addedAmount = delta,
			bagStored = curr,
			bagCapacity = cap,
			isBagFull = curr >= cap,
			message = "Synced",
		})
	elseif type(arg1) == "number" then
		local cap = if type(arg2) == "number" and arg2 > 0 then arg2 else bagCapacity
		local curr = math.clamp(arg1, 0, cap)
		local delta = if type(arg3) == "number" then arg3 else 0
		self:ApplyServerHarvestResult({
			ok = true,
			nodeId = activeExtractionNodeId,
			addedAmount = delta,
			bagStored = curr,
			bagCapacity = cap,
			isBagFull = curr >= cap,
			message = "Synced",
		})
	end
end

function ExpeditionController:ApplyServerDepositResult(response: any): ()
	if type(response) ~= "table" then
		return
	end

	if response.ok then
		local earned = response.coinsEarned or response.depositedAmount or 0
		if type(response.newCoinsBalance) == "number" then
			bankedCoins = response.newCoinsBalance
		elseif type(response.newBalance) == "number" then
			bankedCoins = response.newBalance
		end
		if type(response.bagCapacity) == "number" and response.bagCapacity > 0 then
			bagCapacity = response.bagCapacity
		end
		if type(response.bagStored) == "number" then
			bagCurrent = math.clamp(response.bagStored, 0, bagCapacity)
		elseif type(response.bagCurrent) == "number" then
			bagCurrent = math.clamp(response.bagCurrent, 0, bagCapacity)
		else
			bagCurrent = 0
		end

		if type(response.serverTotalDeposited) == "number" then
			serverTotalDeposited = response.serverTotalDeposited
		elseif type(response.teamCurrent) == "number" then
			serverTotalDeposited = response.teamCurrent
		end
		if type(response.serverStage) == "number" and response.serverStage >= 1 then
			currentServerStage = response.serverStage
		end

		depositStatus = "Success"
		lastDepositError = nil
		bagStatusMessage = string.format("✓ Сдано! Получено +%d Монет в банк!", earned)

		if audioController then
			audioController:PlaySFX("Purchase")
		end

		task.delay(Config.FeedbackResetSeconds, function()
			if depositStatus == "Success" then
				depositStatus = "Idle"
				emitStateChanged()
			end
		end)
	else
		depositStatus = "Error"
		lastDepositError = tostring(response.message or response.errorCode or "Сервер отклонил сдачу добычи")
		bagStatusMessage = "✗ Отказ сдачи: " .. (lastDepositError :: string)
		if audioController then
			audioController:PlaySFX("Error")
		end
	end

	self.OnDepositResolved:Fire(response)
	self.OnBagUpdated:Fire(self:GetBagState())
	emitStateChanged()
end

function ExpeditionController:ApplyServerUpgradeResult(response: any): ()
	if type(response) ~= "table" then
		return
	end

	local rawTrack = tostring(response.upgradeType or "Tool")
	local trackId: ExpeditionTypes.UpgradeTrackId = if rawTrack == "Bag" then "Bag" else "Tool"

	if response.ok then
		if type(response.newCoinsBalance) == "number" then
			bankedCoins = response.newCoinsBalance
		elseif type(response.newBalance) == "number" then
			bankedCoins = response.newBalance
		end

		if type(response.harvestState) == "table" then
			self:ApplyServerHarvestStateSync(response.harvestState)
		else
			if trackId == "Tool" then
				if type(response.newLevel) == "number" and response.newLevel >= 1 then
					toolLevel = response.newLevel
					local def = HarvestConfig.ToolUpgrades[toolLevel]
					if def then
						serverHarvestPower = def.harvestPower
					end
					local nextDef = HarvestConfig.ToolUpgrades[toolLevel + 1]
					serverNextToolPrice = if nextDef then nextDef.priceCoins else nil
				end
				if type(response.newValue) == "number" then
					serverHarvestPower = response.newValue
				end
			else
				if type(response.newLevel) == "number" and response.newLevel >= 1 then
					bagLevel = response.newLevel
					local def = HarvestConfig.BagUpgrades[bagLevel]
					if def then
						bagCapacity = def.capacity
					end
					local nextDef = HarvestConfig.BagUpgrades[bagLevel + 1]
					serverNextBagPrice = if nextDef then nextDef.priceCoins else nil
				end
				if type(response.newValue) == "number" and response.newValue > 0 then
					bagCapacity = response.newValue
				end
			end
		end

		upgradeTransientState[trackId] = "Success"
		upgradeCanRetry[trackId] = false
		upgradeStatusMessage[trackId] = tostring(
			response.message or string.format("✓ %s улучшен до ур. %d!", trackId, response.newLevel or 2)
		)

		if audioController then
			audioController:PlaySFX("LevelUp")
		end

		task.delay(Config.FeedbackResetSeconds, function()
			if upgradeTransientState[trackId] == "Success" then
				upgradeTransientState[trackId] = "Idle"
				emitStateChanged()
			end
		end)
	else
		upgradeTransientState[trackId] = "Error"
		local errCode = tostring(response.errorCode or "UPGRADE_FAILED")
		upgradeCanRetry[trackId] = (errCode ~= "INSUFFICIENT_FUNDS" and errCode ~= "MAX_LEVEL_REACHED")
		upgradeStatusMessage[trackId] = tostring(response.message or ("Ошибка улучшения: " .. errCode))

		if audioController then
			audioController:PlaySFX("Error")
		end
	end

	self.OnUpgradeResolved:Fire(response)
	emitStateChanged()
end

function ExpeditionController:ApplyServerProgressUpdated(progress: any): ()
	if type(progress) ~= "table" then
		return
	end

	local prevStage = currentServerStage
	local wasMax = isMaxServerStage

	if type(progress.totalDeposited) == "number" then
		serverTotalDeposited = math.max(0, progress.totalDeposited)
	elseif type(progress.currentAmount) == "number" then
		serverTotalDeposited = math.max(0, progress.currentAmount)
	end

	if type(progress.currentStage) == "number" and progress.currentStage >= 1 then
		currentServerStage = progress.currentStage
	elseif type(progress.stageNumber) == "number" and progress.stageNumber >= 1 then
		currentServerStage = progress.stageNumber
	end

	if type(progress.currentStageTarget) == "number" and progress.currentStageTarget > 0 then
		currentStageTarget = progress.currentStageTarget
	elseif type(progress.targetAmount) == "number" and progress.targetAmount > 0 then
		currentStageTarget = progress.targetAmount
	end

	if type(progress.stageTitle) == "string" then
		currentStageTitle = progress.stageTitle
	elseif type(progress.stageName) == "string" then
		currentStageTitle = progress.stageName
	end

	if type(progress.stageDescription) == "string" then
		currentStageDescription = progress.stageDescription
	end

	if type(progress.progressRatio) == "number" then
		currentStageRatio = math.clamp(progress.progressRatio, 0, 1)
	else
		currentStageRatio = math.clamp(serverTotalDeposited / math.max(1, currentStageTarget), 0, 1)
	end

	if type(progress.unlockedExtractionZones) == "table" then
		unlockedExtractionZones = table.clone(progress.unlockedExtractionZones)
	end

	if type(progress.isMaxStage) == "boolean" then
		isMaxServerStage = progress.isMaxStage
	elseif type(progress.isUnlocked) == "boolean" and progress.isUnlocked then
		if currentServerStage == 1 then
			currentServerStage = 2
		end
	end

	teamSyncStatus = "Success"
	local vm = self:GetTeamProgress()
	self.OnTeamProgressChanged:Fire(vm)

	if currentServerStage > prevStage or (isMaxServerStage and not wasMax) or progress.isUnlocked == true then
		if audioController then
			audioController:PlaySFX("ZoneUnlock")
		end
		self.OnStageUnlocked:Fire(vm)
	end

	emitStateChanged()
end

function ExpeditionController:ApplyServerTeamProgress(arg1: any, arg2: any, arg3: any, arg4: any): ()
	if type(arg1) == "table" then
		self:ApplyServerProgressUpdated(arg1)
	elseif type(arg1) == "number" then
		self:ApplyServerProgressUpdated({
			totalDeposited = arg1,
			currentStageTarget = arg2 or currentStageTarget,
			currentStage = arg3 or currentServerStage,
			isUnlocked = arg4 == true,
		})
	end
end

function ExpeditionController:ResetStateForTests(): ()
	bankedCoins = 0
	bagCurrent = 0
	bagCapacity = HarvestConfig.BagUpgrades[1].capacity
	toolLevel = 1
	bagLevel = 1
	serverHarvestPower = nil
	serverNextToolPrice = nil
	serverNextBagPrice = nil
	currentServerStage = 1
	serverTotalDeposited = 0
	currentStageTarget = HarvestConfig.ServerMilestones[1].targetDeposited
	currentStageRatio = 0
	currentStageTitle = HarvestConfig.ServerMilestones[1].title
	currentStageDescription = HarvestConfig.ServerMilestones[1].description
	isMaxServerStage = false
	unlockedExtractionZones = {
		[HarvestConfig.DefaultNodeId] = true,
	}
	collectStatus = "Idle"
	depositStatus = "Idle"
	bagStatusMessage = "Добывайте Solar Shards в кратере Sunforge"
	lastDepositError = nil
	lastStationId = HarvestConfig.DefaultStationId
	activeExtractionNodeId = HarvestConfig.DefaultNodeId
	upgradeTransientState.Tool = "Idle"
	upgradeTransientState.Bag = "Idle"
	upgradeStatusMessage.Tool = "Готово к улучшению"
	upgradeStatusMessage.Bag = "Готово к улучшению"
	upgradeCanRetry.Tool = false
	upgradeCanRetry.Bag = false
	teamSyncStatus = "Idle"
	lastCollectClock = 0
	lastDepositClock = 0
	lastUpgradeClock = 0
end

function ExpeditionController:Shutdown(): ()
	for _, conn in ipairs(rbxConnections) do
		conn:Disconnect()
	end
	table.clear(rbxConnections)
	log:Info("Shutdown ExpeditionController")
end

return ExpeditionController
