--!strict
--[[
	@module HarvestService
	@owner Agent A (Breight321)
	@description Серверно-авторитетный сервис вертикального среза "Sunforge Expedition":
	1. Добыча ресурса из общих зон (проверка этапа сервера, дистанции, инструмента, cooldown и вместимости сумки).
	2. Переносимая сумка с ограниченной вместимостью (хранится в PlayerDataService).
	3. Сдача добычи на активных станциях с серверным расчётом выплаты в валюте через EconomyService.
	4. Покупка улучшений инструмента ("Tool") и сумки ("Bag") с проверкой цены и баланса на сервере.
	5. Общий прогресс команды на сервере с автоматическим открытием новых этапов и зон.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Core"):WaitForChild("Types"))
local Logger = require(Shared:WaitForChild("Core"):WaitForChild("Logger"))
local Signal = require(Shared:WaitForChild("Core"):WaitForChild("Signal"))
local Network = require(Shared:WaitForChild("Core"):WaitForChild("Network"))
local HarvestConfig = require(Shared:WaitForChild("Config"):WaitForChild("HarvestConfig"))

local HarvestService = {
	Name = "HarvestService",
	Dependencies = { "PlayerDataService", "EconomyService" },
	OnResourceHarvested = Signal.new(),
	OnLootDeposited = Signal.new(),
	OnUpgradePurchased = Signal.new(),
	OnServerStageAdvanced = Signal.new(),
}

local log = Logger.new("HarvestService")
local playerDataService: any = nil
local economyService: any = nil

local lastHarvestTimestamps: { [any]: number } = {}
local serverTotalDeposited: number = 0
local serverStage: number = 1
local connections: { RBXScriptConnection } = {}

local function isValidPlayerKey(player: any): boolean
	return player ~= nil and (typeof(player) == "Instance" or type(player) == "table")
end

local function isRealPlayer(player: any): boolean
	return typeof(player) == "Instance" and player:IsA("Player")
end

local function createDefaultHarvestState(): Types.PlayerHarvestState
	return {
		bagStored = 0,
		toolLevel = 1,
		bagLevel = 1,
		totalHarvested = 0,
		totalDeposited = 0,
	}
end

local function sanitizeHarvestState(raw: any): Types.PlayerHarvestState
	local def = createDefaultHarvestState()
	if type(raw) ~= "table" then
		return def
	end

	local maxToolLevel = #HarvestConfig.ToolUpgrades
	local maxBagLevel = #HarvestConfig.BagUpgrades

	local toolLevel = if type(raw.toolLevel) == "number" and raw.toolLevel >= 1
		then math.clamp(math.floor(raw.toolLevel), 1, maxToolLevel)
		else 1
	local bagLevel = if type(raw.bagLevel) == "number" and raw.bagLevel >= 1
		then math.clamp(math.floor(raw.bagLevel), 1, maxBagLevel)
		else 1

	local bagCap = HarvestConfig.BagUpgrades[bagLevel].capacity
	local bagStored = if type(raw.bagStored) == "number" and raw.bagStored >= 0
		then math.clamp(math.floor(raw.bagStored), 0, bagCap)
		else 0
	local totalHarvested = if type(raw.totalHarvested) == "number" and raw.totalHarvested >= 0
		then math.floor(raw.totalHarvested)
		else 0
	local totalDeposited = if type(raw.totalDeposited) == "number" and raw.totalDeposited >= 0
		then math.floor(raw.totalDeposited)
		else 0

	return {
		bagStored = bagStored,
		toolLevel = toolLevel,
		bagLevel = bagLevel,
		totalHarvested = totalHarvested,
		totalDeposited = totalDeposited,
	}
end

local function ensureProfileHarvestState(profile: Types.PlayerProfileData): Types.PlayerHarvestState
	if type(profile.harvestState) ~= "table" then
		profile.harvestState = createDefaultHarvestState()
	else
		profile.harvestState = sanitizeHarvestState(profile.harvestState)
	end
	return profile.harvestState :: Types.PlayerHarvestState
end

local function syncBagLeaderstat(player: any, bagStored: number): ()
	if not isRealPlayer(player) then
		return
	end
	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then
		return
	end
	local bagVal = leaderstats:FindFirstChild("Bag")
	if not bagVal then
		local newVal = Instance.new("IntValue")
		newVal.Name = "Bag"
		newVal.Parent = leaderstats
		bagVal = newVal
	end
	local intBag = bagVal :: IntValue
	intBag.Value = math.floor(bagStored)
end

local function getPlayerPosition(player: any, fallbackCenter: Vector3): (boolean, Vector3?)
	if isRealPlayer(player) then
		local character = player.Character
		if not character then
			return false, nil
		end
		local rootPart = character:FindFirstChild("HumanoidRootPart")
		if not rootPart or not rootPart:IsA("BasePart") then
			return false, nil
		end
		return true, rootPart.Position
	elseif type(player) == "table" then
		if player.CharacterMissing == true then
			return false, nil
		end
		if typeof(player.Position) == "Vector3" then
			return true, player.Position
		end
		return true, fallbackCenter
	end
	return false, nil
end

local function buildHarvestStatePayload(state: Types.PlayerHarvestState): Types.HarvestStatePayload
	local toolDef = HarvestConfig.ToolUpgrades[state.toolLevel] or HarvestConfig.ToolUpgrades[1]
	local bagDef = HarvestConfig.BagUpgrades[state.bagLevel] or HarvestConfig.BagUpgrades[1]
	local nextToolDef = HarvestConfig.ToolUpgrades[state.toolLevel + 1]
	local nextBagDef = HarvestConfig.BagUpgrades[state.bagLevel + 1]

	return {
		bagStored = state.bagStored,
		bagCapacity = bagDef.capacity,
		toolLevel = state.toolLevel,
		toolId = toolDef.id,
		toolName = toolDef.displayName,
		harvestPower = toolDef.harvestPower,
		cooldownSeconds = toolDef.cooldownSeconds,
		bagLevel = state.bagLevel,
		bagId = bagDef.id,
		bagName = bagDef.displayName,
		nextToolPrice = if nextToolDef then nextToolDef.priceCoins else nil,
		nextBagPrice = if nextBagDef then nextBagDef.priceCoins else nil,
		totalHarvested = state.totalHarvested,
		totalDeposited = state.totalDeposited,
	}
end

function HarvestService:GetServerProgress(): Types.ServerProgressPayload
	local maxStages = #HarvestConfig.ServerMilestones
	local currentMilestone = HarvestConfig.ServerMilestones[serverStage] or HarvestConfig.ServerMilestones[1]
	local prevThreshold = if serverStage > 1
		then HarvestConfig.ServerMilestones[serverStage - 1].targetDeposited
		else 0
	local target = currentMilestone.targetDeposited
	local span = math.max(1, target - prevThreshold)
	local ratio = math.clamp((serverTotalDeposited - prevThreshold) / span, 0, 1)

	local unlockedMap: { [string]: boolean } = {}
	for _, zId in ipairs(currentMilestone.unlockedZoneIds) do
		unlockedMap[zId] = true
	end

	return {
		totalDeposited = serverTotalDeposited,
		currentStage = serverStage,
		stageTitle = currentMilestone.title,
		stageDescription = currentMilestone.description,
		currentStageTarget = target,
		previousStageThreshold = prevThreshold,
		progressRatio = ratio,
		stageBonusMultiplier = currentMilestone.stageBonusMultiplier,
		unlockedExtractionZones = unlockedMap,
		isMaxStage = serverStage >= maxStages and serverTotalDeposited >= target,
	}
end

local function evaluateServerMilestones(): boolean
	local maxStages = #HarvestConfig.ServerMilestones
	local advanced = false

	while serverStage < maxStages do
		local currentMilestone = HarvestConfig.ServerMilestones[serverStage]
		if serverTotalDeposited >= currentMilestone.targetDeposited then
			serverStage += 1
			advanced = true
			local newMilestone = HarvestConfig.ServerMilestones[serverStage]
			log:Info(
				"Server Co-op Goal reached Stage %d (%s) at %d deposited!",
				serverStage,
				newMilestone.title,
				serverTotalDeposited
			)
		else
			break
		end
	end

	if advanced then
		local progressPayload = HarvestService:GetServerProgress()
		HarvestService.OnServerStageAdvanced:Fire(serverStage, progressPayload)
		Network.FireAllClients(
			Network.Events.Notification,
			"Reward",
			string.format("🔥 Командный этап %d открыт: %s!", serverStage, progressPayload.stageTitle)
		)
	end

	return advanced
end

local function ensureWorldMarkers(): ()
	local existingFolder = Workspace:FindFirstChild("SunforgeWorld")
	if existingFolder then
		return
	end

	local worldFolder = Instance.new("Folder")
	worldFolder.Name = "SunforgeWorld"
	worldFolder.Parent = Workspace

	local zonesFolder = Instance.new("Folder")
	zonesFolder.Name = "ExtractionZones"
	zonesFolder.Parent = worldFolder

	for _, zoneDef in pairs(HarvestConfig.ExtractionZones) do
		local pad = Instance.new("Part")
		pad.Name = zoneDef.id
		pad.Anchored = true
		pad.CanCollide = false
		pad.Transparency = 0.45
		pad.Material = Enum.Material.Neon
		pad.Color = if zoneDef.requiredServerStage == 1
			then Color3.fromRGB(255, 176, 46)
			elseif zoneDef.requiredServerStage == 2 then Color3.fromRGB(255, 110, 38)
			else Color3.fromRGB(92, 214, 255)
		pad.Size = Vector3.new(zoneDef.radius * 1.2, 0.6, zoneDef.radius * 1.2)
		pad.Position = zoneDef.centerPosition + Vector3.new(0, 0.3, 0)
		pad:SetAttribute("NodeId", zoneDef.id)
		pad:SetAttribute("RequiredServerStage", zoneDef.requiredServerStage)
		pad.Parent = zonesFolder
	end

	local stationsFolder = Instance.new("Folder")
	stationsFolder.Name = "DepositStations"
	stationsFolder.Parent = worldFolder

	for _, stationDef in pairs(HarvestConfig.DepositStations) do
		if stationDef.active then
			local stationPart = Instance.new("Part")
			stationPart.Name = stationDef.id
			stationPart.Anchored = true
			stationPart.CanCollide = false
			stationPart.Transparency = 0.25
			stationPart.Material = Enum.Material.Neon
			stationPart.Color = Color3.fromRGB(76, 224, 130)
			stationPart.Size = Vector3.new(12, 1, 12)
			stationPart.Position = stationDef.position + Vector3.new(0, 0.5, 0)
			stationPart:SetAttribute("StationId", stationDef.id)
			stationPart.Parent = stationsFolder
		end
	end
end

function HarvestService:Init(registry: any): ()
	playerDataService = registry:Get("PlayerDataService")
	economyService = registry:Get("EconomyService")

	playerDataService:RegisterSchemaSection("harvestState", createDefaultHarvestState(), sanitizeHarvestState)
	log:Info("Initialized HarvestService (%s)", HarvestConfig.GameTitle)
end

function HarvestService:Start(): ()
	ensureWorldMarkers()

	table.insert(
		connections,
		playerDataService.OnProfileLoaded:Connect(function(player: Player, profile: Types.PlayerProfileData)
			local state = ensureProfileHarvestState(profile)
			syncBagLeaderstat(player, state.bagStored)
			if isRealPlayer(player) then
				local statePayload = buildHarvestStatePayload(state)
				local progressPayload = self:GetServerProgress()
				Network.FireClient(player, Network.Events.HarvestStateSync, statePayload)
				Network.FireClient(player, Network.Events.ServerProgressUpdated, progressPayload)
				task.delay(0.5, function()
					if player.Parent then
						Network.FireClient(player, Network.Events.HarvestStateSync, statePayload)
						Network.FireClient(player, Network.Events.ServerProgressUpdated, progressPayload)
					end
				end)
			end
		end)
	)

	table.insert(
		connections,
		Network.OnServerEvent(Network.Events.RequestHarvest, function(player: Player, rawNodeId: any)
			local nodeId = if type(rawNodeId) == "string" and #rawNodeId <= 64 then rawNodeId else nil
			self:HarvestFromNode(player, nodeId)
		end)
	)

	table.insert(
		connections,
		Network.OnServerEvent(Network.Events.RequestDeposit, function(player: Player, rawStationId: any)
			local stationId = if type(rawStationId) == "string" and #rawStationId <= 64 then rawStationId else nil
			self:DepositAtStation(player, stationId)
		end)
	)

	table.insert(
		connections,
		Network.OnServerEvent(Network.Events.RequestHarvestUpgrade, function(player: Player, rawUpgradeType: any)
			if rawUpgradeType == "Tool" or rawUpgradeType == "Bag" then
				self:PurchaseUpgrade(player, rawUpgradeType)
			else
				local errPayload: Types.UpgradeResultPayload = {
					ok = false,
					upgradeType = "Tool",
					newLevel = 0,
					pricePaid = 0,
					newCoinsBalance = economyService:GetBalance(player, HarvestConfig.RewardCurrencyId),
					harvestState = nil,
					errorCode = "INVALID_UPGRADE_TYPE",
					message = "Unknown upgrade type requested.",
				}
				Network.FireClient(player, Network.Events.HarvestUpgradeResult, errPayload)
			end
		end)
	)

	log:Info("Started HarvestService")
end

function HarvestService:GetHarvestState(
	player: Player
): Types.Result<Types.HarvestStatePayload, Types.HarvestErrorCode>
	if not isValidPlayerKey(player) then
		return Types.Err("INVALID_PLAYER")
	end

	local profileRes = playerDataService:GetProfile(player)
	if not profileRes.ok or not profileRes.value then
		return Types.Err("PROFILE_NOT_LOADED")
	end

	local state = ensureProfileHarvestState(profileRes.value)
	return Types.Ok(buildHarvestStatePayload(state))
end

function HarvestService:HarvestFromNode(
	player: Player,
	nodeId: string?
): Types.Result<Types.HarvestResultPayload, Types.HarvestErrorCode>
	local targetNodeId = if type(nodeId) == "string" and #nodeId > 0 then nodeId else HarvestConfig.DefaultNodeId

	local function fail(code: Types.HarvestErrorCode, msg: string, stored: number, cap: number)
		local payload: Types.HarvestResultPayload = {
			ok = false,
			nodeId = targetNodeId,
			addedAmount = 0,
			bagStored = stored,
			bagCapacity = cap,
			isBagFull = stored >= cap and cap > 0,
			errorCode = code,
			message = msg,
		}
		if isRealPlayer(player) then
			Network.FireClient(player, Network.Events.HarvestResult, payload)
		end
		return Types.Err(code)
	end

	if not isValidPlayerKey(player) then
		return fail("INVALID_PLAYER", "Invalid player reference.", 0, 0)
	end

	local profileRes = playerDataService:GetProfile(player)
	if not profileRes.ok or not profileRes.value then
		return fail("PROFILE_NOT_LOADED", "Player profile is not loaded yet.", 0, 0)
	end

	local profile: Types.PlayerProfileData = profileRes.value
	local state = ensureProfileHarvestState(profile)
	local toolDef = HarvestConfig.ToolUpgrades[state.toolLevel] or HarvestConfig.ToolUpgrades[1]
	local bagDef = HarvestConfig.BagUpgrades[state.bagLevel] or HarvestConfig.BagUpgrades[1]

	local zoneDef = HarvestConfig.ExtractionZones[targetNodeId]
	if not zoneDef then
		return fail("UNKNOWN_EXTRACTION_ZONE", "Extraction zone does not exist.", state.bagStored, bagDef.capacity)
	end

	if serverStage < zoneDef.requiredServerStage then
		return fail(
			"STAGE_LOCKED",
			string.format("Requires Server Stage %d to harvest here.", zoneDef.requiredServerStage),
			state.bagStored,
			bagDef.capacity
		)
	end

	local hasPos, playerPos = getPlayerPosition(player, zoneDef.centerPosition)
	if not hasPos or not playerPos then
		return fail("CHARACTER_NOT_READY", "Player character is not spawned.", state.bagStored, bagDef.capacity)
	end

	local distance = (playerPos - zoneDef.centerPosition).Magnitude
	if distance > zoneDef.radius then
		return fail(
			"OUT_OF_ZONE_RANGE",
			"Move closer to the extraction zone to harvest.",
			state.bagStored,
			bagDef.capacity
		)
	end

	local now = os.clock()
	local lastHarvest = lastHarvestTimestamps[player] or 0
	if (now - lastHarvest) < toolDef.cooldownSeconds then
		return fail("HARVEST_COOLDOWN", "Extractor is cooling down.", state.bagStored, bagDef.capacity)
	end

	if state.bagStored >= bagDef.capacity then
		if isRealPlayer(player) then
			Network.FireClient(
				player,
				Network.Events.Notification,
				"Warning",
				"🎒 Сумка заполнена! Сдайте добычу на станции Горна."
			)
		end
		return fail("BAG_FULL", "Satchel is full! Deposit shards at a station.", state.bagStored, bagDef.capacity)
	end

	lastHarvestTimestamps[player] = now

	local rawYield = math.max(1, math.floor(toolDef.harvestPower * zoneDef.yieldMultiplier))
	local freeSpace = bagDef.capacity - state.bagStored
	local addedAmount = math.min(freeSpace, rawYield)

	local updateRes = playerDataService:UpdateProfile(player, function(prof: Types.PlayerProfileData)
		local hs = ensureProfileHarvestState(prof)
		hs.bagStored += addedAmount
		hs.totalHarvested += addedAmount
		prof.stats.totalClicks = (prof.stats.totalClicks or 0) + 1
		return true
	end)

	if not updateRes.ok then
		return fail("UPDATE_FAILED", "Failed to update harvest state.", state.bagStored, bagDef.capacity)
	end

	syncBagLeaderstat(player, state.bagStored)

	local resultPayload: Types.HarvestResultPayload = {
		ok = true,
		nodeId = targetNodeId,
		addedAmount = addedAmount,
		bagStored = state.bagStored,
		bagCapacity = bagDef.capacity,
		isBagFull = state.bagStored >= bagDef.capacity,
		errorCode = nil,
		message = string.format("+%d %s (%d/%d)", addedAmount, HarvestConfig.ResourceName, state.bagStored, bagDef.capacity),
	}

	self.OnResourceHarvested:Fire(player, resultPayload)

	if isRealPlayer(player) then
		Network.FireClient(player, Network.Events.HarvestResult, resultPayload)
		Network.FireClient(player, Network.Events.HarvestStateSync, buildHarvestStatePayload(state))
	end

	return Types.Ok(resultPayload)
end

function HarvestService:DepositAtStation(
	player: Player,
	stationId: string?
): Types.Result<Types.DepositResultPayload, Types.HarvestErrorCode>
	local targetStationId = if type(stationId) == "string" and #stationId > 0
		then stationId
		else HarvestConfig.DefaultStationId

	local function fail(code: Types.HarvestErrorCode, msg: string, stored: number, cap: number, coinsBal: number)
		local payload: Types.DepositResultPayload = {
			ok = false,
			stationId = targetStationId,
			depositedAmount = 0,
			coinsEarned = 0,
			newCoinsBalance = coinsBal,
			bagStored = stored,
			bagCapacity = cap,
			serverTotalDeposited = serverTotalDeposited,
			serverStage = serverStage,
			errorCode = code,
			message = msg,
		}
		if isRealPlayer(player) then
			Network.FireClient(player, Network.Events.DepositResult, payload)
		end
		return Types.Err(code)
	end

	if not isValidPlayerKey(player) then
		return fail("INVALID_PLAYER", "Invalid player reference.", 0, 0, 0)
	end

	local profileRes = playerDataService:GetProfile(player)
	if not profileRes.ok or not profileRes.value then
		return fail("PROFILE_NOT_LOADED", "Player profile is not loaded yet.", 0, 0, 0)
	end

	local profile: Types.PlayerProfileData = profileRes.value
	local state = ensureProfileHarvestState(profile)
	local bagDef = HarvestConfig.BagUpgrades[state.bagLevel] or HarvestConfig.BagUpgrades[1]
	local currentCoins = economyService:GetBalance(player, HarvestConfig.RewardCurrencyId)

	local stationDef = HarvestConfig.DepositStations[targetStationId]
	if not stationDef then
		return fail("INVALID_STATION", "Deposit station does not exist.", state.bagStored, bagDef.capacity, currentCoins)
	end

	if not stationDef.active then
		return fail(
			"STATION_INACTIVE",
			"This deposit station is currently offline.",
			state.bagStored,
			bagDef.capacity,
			currentCoins
		)
	end

	if serverStage < stationDef.requiredServerStage then
		return fail(
			"STAGE_LOCKED",
			string.format("Station requires Server Stage %d.", stationDef.requiredServerStage),
			state.bagStored,
			bagDef.capacity,
			currentCoins
		)
	end

	local hasPos, playerPos = getPlayerPosition(player, stationDef.position)
	if not hasPos or not playerPos then
		return fail(
			"CHARACTER_NOT_READY",
			"Player character is not spawned.",
			state.bagStored,
			bagDef.capacity,
			currentCoins
		)
	end

	local distance = (playerPos - stationDef.position).Magnitude
	if distance > stationDef.interactionRadius then
		return fail(
			"TOO_FAR_FROM_STATION",
			"Move closer to the deposit station to turn in loot.",
			state.bagStored,
			bagDef.capacity,
			currentCoins
		)
	end

	if state.bagStored <= 0 then
		return fail("BAG_EMPTY", "Your satchel is empty!", 0, bagDef.capacity, currentCoins)
	end

	local depositedAmount = state.bagStored
	local milestoneDef = HarvestConfig.ServerMilestones[serverStage] or HarvestConfig.ServerMilestones[1]
	local econMultiplier = economyService:GetMultiplier(player, HarvestConfig.RewardCurrencyId)
	local coinsEarned = math.max(
		1,
		math.floor(depositedAmount * stationDef.exchangeRate * milestoneDef.stageBonusMultiplier * econMultiplier)
	)

	local updateRes = playerDataService:UpdateProfile(player, function(prof: Types.PlayerProfileData)
		local hs = ensureProfileHarvestState(prof)
		hs.bagStored = 0
		hs.totalDeposited += depositedAmount
		return true
	end)

	if not updateRes.ok then
		return fail("UPDATE_FAILED", "Failed to clear bag on deposit.", state.bagStored, bagDef.capacity, currentCoins)
	end

	local addRes = economyService:AddCurrency(
		player,
		HarvestConfig.RewardCurrencyId,
		coinsEarned,
		"HarvestDeposit:" .. targetStationId
	)
	local newBalance = if addRes.ok and addRes.value then addRes.value else currentCoins

	syncBagLeaderstat(player, 0)

	serverTotalDeposited += depositedAmount
	evaluateServerMilestones()

	local progressPayload = self:GetServerProgress()
	local resultPayload: Types.DepositResultPayload = {
		ok = true,
		stationId = targetStationId,
		depositedAmount = depositedAmount,
		coinsEarned = coinsEarned,
		newCoinsBalance = newBalance,
		bagStored = 0,
		bagCapacity = bagDef.capacity,
		serverTotalDeposited = serverTotalDeposited,
		serverStage = serverStage,
		errorCode = nil,
		message = string.format("Deposited %d %s for +%d Coins!", depositedAmount, HarvestConfig.ResourceName, coinsEarned),
	}

	self.OnLootDeposited:Fire(player, resultPayload)

	if isRealPlayer(player) then
		Network.FireClient(player, Network.Events.DepositResult, resultPayload)
		Network.FireClient(player, Network.Events.HarvestStateSync, buildHarvestStatePayload(state))
		Network.FireClient(
			player,
			Network.Events.Notification,
			"Reward",
			string.format("💰 Сдано %d ед. → +%d Coins!", depositedAmount, coinsEarned)
		)
	end
	Network.FireAllClients(Network.Events.ServerProgressUpdated, progressPayload)

	return Types.Ok(resultPayload)
end

function HarvestService:PurchaseUpgrade(
	player: Player,
	upgradeType: Types.HarvestUpgradeType
): Types.Result<Types.UpgradeResultPayload, Types.HarvestErrorCode>
	local function fail(code: Types.HarvestErrorCode, msg: string, curLevel: number, coinsBal: number)
		local payload: Types.UpgradeResultPayload = {
			ok = false,
			upgradeType = upgradeType,
			newLevel = curLevel,
			pricePaid = 0,
			newCoinsBalance = coinsBal,
			harvestState = nil,
			errorCode = code,
			message = msg,
		}
		if isRealPlayer(player) then
			Network.FireClient(player, Network.Events.HarvestUpgradeResult, payload)
		end
		return Types.Err(code)
	end

	if not isValidPlayerKey(player) then
		return fail("INVALID_PLAYER", "Invalid player reference.", 0, 0)
	end

	if upgradeType ~= "Tool" and upgradeType ~= "Bag" then
		return fail("INVALID_UPGRADE_TYPE", "Upgrade type must be 'Tool' or 'Bag'.", 0, 0)
	end

	local profileRes = playerDataService:GetProfile(player)
	if not profileRes.ok or not profileRes.value then
		return fail("PROFILE_NOT_LOADED", "Player profile is not loaded yet.", 0, 0)
	end

	local profile: Types.PlayerProfileData = profileRes.value
	local state = ensureProfileHarvestState(profile)
	local currentCoins = economyService:GetBalance(player, HarvestConfig.RewardCurrencyId)

	local currentLevel = if upgradeType == "Tool" then state.toolLevel else state.bagLevel
	local nextLevel = currentLevel + 1
	local nextDef: any = if upgradeType == "Tool"
		then HarvestConfig.ToolUpgrades[nextLevel]
		else HarvestConfig.BagUpgrades[nextLevel]

	if not nextDef then
		return fail("MAX_LEVEL_REACHED", "Maximum upgrade tier already reached.", currentLevel, currentCoins)
	end

	local price: number = nextDef.priceCoins
	if not economyService:CanAfford(player, HarvestConfig.RewardCurrencyId, price) then
		if isRealPlayer(player) then
			Network.FireClient(
				player,
				Network.Events.Notification,
				"Error",
				string.format("Недостаточно монет! Нужно %d Coins.", price)
			)
		end
		return fail("INSUFFICIENT_FUNDS", "Insufficient Coins for upgrade.", currentLevel, currentCoins)
	end

	local removeRes = economyService:RemoveCurrency(
		player,
		HarvestConfig.RewardCurrencyId,
		price,
		string.format("HarvestUpgrade:%s:L%d", upgradeType, nextLevel)
	)
	if not removeRes.ok then
		return fail("INSUFFICIENT_FUNDS", "Failed to deduct upgrade cost.", currentLevel, currentCoins)
	end

	local updateRes = playerDataService:UpdateProfile(player, function(prof: Types.PlayerProfileData)
		local hs = ensureProfileHarvestState(prof)
		if upgradeType == "Tool" then
			hs.toolLevel = nextLevel
		else
			hs.bagLevel = nextLevel
		end
		return true
	end)

	if not updateRes.ok then
		economyService:AddCurrency(player, HarvestConfig.RewardCurrencyId, price, "UpgradeRollback")
		return fail("UPDATE_FAILED", "Failed to apply upgrade; coins refunded.", currentLevel, currentCoins)
	end

	local newBalance = economyService:GetBalance(player, HarvestConfig.RewardCurrencyId)
	local statePayload = buildHarvestStatePayload(state)
	local resultPayload: Types.UpgradeResultPayload = {
		ok = true,
		upgradeType = upgradeType,
		newLevel = nextLevel,
		pricePaid = price,
		newCoinsBalance = newBalance,
		harvestState = statePayload,
		errorCode = nil,
		message = string.format("Upgraded %s to Level %d (%s)!", upgradeType, nextLevel, tostring(nextDef.displayName)),
	}

	self.OnUpgradePurchased:Fire(player, resultPayload)

	if isRealPlayer(player) then
		Network.FireClient(player, Network.Events.HarvestUpgradeResult, resultPayload)
		Network.FireClient(player, Network.Events.HarvestStateSync, statePayload)
		Network.FireClient(
			player,
			Network.Events.Notification,
			"Success",
			string.format("⚡ Улучшено: %s (Ур. %d)!", tostring(nextDef.displayName), nextLevel)
		)
	end

	return Types.Ok(resultPayload)
end

function HarvestService:ClearCooldownForTest(mockPlayer: any): ()
	lastHarvestTimestamps[mockPlayer] = nil
end

function HarvestService:ResetServerProgressForTests(): ()
	serverTotalDeposited = 0
	serverStage = 1
	table.clear(lastHarvestTimestamps)
end

function HarvestService:Shutdown(): ()
	for _, conn in ipairs(connections) do
		conn:Disconnect()
	end
	table.clear(connections)
	table.clear(lastHarvestTimestamps)
	log:Info("Shutdown HarvestService")
end

return HarvestService
