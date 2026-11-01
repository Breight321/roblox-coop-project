--!strict
--[[
	@module EconomyService
	@owner Agent A (Breight321)
	@description Универсальный серверный модуль экономики (Модуль 4): мультивалютность, настраиваемые лимиты, адаптеры множителей и журнал транзакций. Не зависит от Inventory, Items или World.
]]

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local SharedTypes = require(Shared:WaitForChild("Core"):WaitForChild("Types"))
local Logger = require(Shared:WaitForChild("Core"):WaitForChild("Logger"))
local Signal = require(Shared:WaitForChild("Core"):WaitForChild("Signal"))
local Network = require(Shared:WaitForChild("Core"):WaitForChild("Network"))

local GameConfig = require(Shared:WaitForChild("Config"):WaitForChild("GameConfig"))
local CurrenciesConfig = require(Shared:WaitForChild("Config"):WaitForChild("CurrenciesConfig"))

local EconomyTypes = require(script:WaitForChild("Types"))
local EconomyConfig = require(script:WaitForChild("Config"))

export type MultiplierModifierFn = (player: any, currencyId: EconomyTypes.CurrencyId) -> number

local EconomyService = {
	Name = "EconomyService",
	Dependencies = { "PlayerDataService" },
	OnCurrencyChanged = Signal.new(),
	OnSimulatorClickProcessed = Signal.new(),
}

local log = Logger.new("EconomyService")
local playerDataService: any = nil
local lastClickTimestamps: { [any]: number } = {}
local transactionLogs: { [any]: { EconomyTypes.EconomyTransactionRecord } } = {}
local registeredCurrencies: { [string]: SharedTypes.CurrencyDef } = {}
local customLimitRules: { [string]: EconomyTypes.CurrencyLimitRule } = {}
local multiplierModifiers: { [string]: MultiplierModifierFn } = {}
local clickConn: RBXScriptConnection? = nil

-- Инициализация базовых валют из конфига
for currencyId, def in pairs(CurrenciesConfig) do
	registeredCurrencies[currencyId] = def
end
for currencyId, rule in pairs(EconomyConfig.LimitsByCurrency) do
	customLimitRules[currencyId] = rule
end

local function isValidPlayerKey(player: any): boolean
	return player ~= nil and (typeof(player) == "Instance" or type(player) == "table")
end

local function getPlayerUserId(player: any): number
	if typeof(player) == "Instance" and player:IsA("Player") then
		return player.UserId
	elseif type(player) == "table" and type(player.UserId) == "number" then
		return player.UserId
	end
	return 0
end

local function isRealPlayer(player: any): boolean
	return typeof(player) == "Instance" and player:IsA("Player")
end

function EconomyService:RegisterCurrency(
	currencyDef: SharedTypes.CurrencyDef,
	limitRule: EconomyTypes.CurrencyLimitRule?
): ()
	assert(type(currencyDef) == "table" and type(currencyDef.id) == "string", "Invalid CurrencyDef")
	registeredCurrencies[currencyDef.id] = currencyDef
	customLimitRules[currencyDef.id] = limitRule or {
		minBalance = 0,
		maxBalance = currencyDef.maxAmount or 1e15,
		maxSingleTransaction = currencyDef.maxAmount or 1e12,
		allowNegative = false,
	}
end

function EconomyService:RegisterMultiplierModifier(modifierId: string, callback: MultiplierModifierFn): ()
	assert(type(modifierId) == "string" and #modifierId > 0, "modifierId must be a non-empty string")
	assert(type(callback) == "function", "callback must be a function")
	multiplierModifiers[modifierId] = callback
end

function EconomyService:RemoveMultiplierModifier(modifierId: string): ()
	multiplierModifiers[modifierId] = nil
end

function EconomyService:ValidateAmount(
	currencyId: EconomyTypes.CurrencyId,
	amount: any
): EconomyTypes.Result<number, EconomyTypes.EconomyErrorCode>
	if type(currencyId) ~= "string" or registeredCurrencies[currencyId] == nil then
		return SharedTypes.Err("UNKNOWN_CURRENCY")
	end
	if type(amount) ~= "number" or amount ~= amount or amount <= 0 or amount == math.huge then
		return SharedTypes.Err("INVALID_AMOUNT")
	end

	local limitRule = customLimitRules[currencyId]
	if limitRule and amount > limitRule.maxSingleTransaction then
		return SharedTypes.Err("AMOUNT_EXCEEDS_MAX_TRANSACTION")
	end

	return SharedTypes.Ok(math.floor(amount))
end

local function appendTransactionLog(
	player: any,
	currencyId: EconomyTypes.CurrencyId,
	delta: number,
	balanceBefore: number,
	balanceAfter: number,
	reason: string
): ()
	local history = transactionLogs[player]
	if not history then
		history = {}
		transactionLogs[player] = history
	end

	local record: EconomyTypes.EconomyTransactionRecord = {
		id = HttpService:GenerateGUID(false),
		timestamp = os.time(),
		userId = getPlayerUserId(player),
		currencyId = currencyId,
		delta = delta,
		balanceBefore = balanceBefore,
		balanceAfter = balanceAfter,
		reason = reason,
	}

	table.insert(history, record)
	if #history > EconomyConfig.MaxTransactionHistoryPerPlayer then
		table.remove(history, 1)
	end

	log:Debug(
		"Tx [%s] user=%d currency=%s delta=%d (%d -> %d) reason=%s",
		record.id,
		record.userId,
		currencyId,
		delta,
		balanceBefore,
		balanceAfter,
		reason
	)
end

function EconomyService:Init(registry: any): ()
	playerDataService = registry:Get("PlayerDataService")
	log:Info("Initialized universal EconomyService")
end

function EconomyService:Start(): ()
	clickConn = Network.OnServerEvent(Network.Events.RequestActionClick, function(player: Player, clientToolUid: any)
		local validToolUid = if type(clientToolUid) == "string" and #clientToolUid <= 64 then clientToolUid else nil
		self:ProcessSimulatorClick(player, validToolUid)
	end)
	log:Info("Started EconomyService")
end

function EconomyService:GetBalance(player: Player, currencyId: EconomyTypes.CurrencyId): number
	if not isValidPlayerKey(player) or type(currencyId) ~= "string" then
		return 0
	end
	local res = playerDataService:GetProfile(player)
	if not res.ok or not res.value then
		return 0
	end
	return res.value.currencies[currencyId] or 0
end

function EconomyService:CanAfford(player: Player, currencyId: EconomyTypes.CurrencyId, amount: number): boolean
	if not isValidPlayerKey(player) then
		return false
	end
	if type(currencyId) ~= "string" or registeredCurrencies[currencyId] == nil then
		return false
	end
	if type(amount) ~= "number" or amount ~= amount or amount < 0 or amount == math.huge then
		return false
	end
	return self:GetBalance(player, currencyId) >= math.floor(amount)
end

function EconomyService:GetMultiplierBreakdown(
	player: Player,
	currencyId: EconomyTypes.CurrencyId
): EconomyTypes.MultiplierBreakdown
	local breakdown: EconomyTypes.MultiplierBreakdown = {
		base = 1.0,
		rebirthBonus = 1.0,
		equippedItemsBonus = 1.0,
		zoneBonus = 1.0,
		customModifiersBonus = 1.0,
		total = 1.0,
	}

	if not isValidPlayerKey(player) then
		return breakdown
	end

	local res = playerDataService:GetProfile(player)
	if res.ok and res.value then
		local profile: SharedTypes.PlayerProfileData = res.value
		local rebirths = profile.rebirths or 0
		breakdown.rebirthBonus = 1.0 + (rebirths * GameConfig.Progression.RebirthBonusMultiplierPerRebirth)
	end

	local customTotal = 1.0
	for modId, modFn in pairs(multiplierModifiers) do
		local ok, factor = pcall(modFn, player, currencyId)
		if ok and type(factor) == "number" and factor == factor and factor > 0 then
			if modId == "EquippedItemsBonus" then
				breakdown.equippedItemsBonus = factor
			elseif modId == "ZoneBonus" then
				breakdown.zoneBonus = factor
			else
				customTotal *= factor
			end
		end
	end
	breakdown.customModifiersBonus = customTotal

	breakdown.total = breakdown.base
		* breakdown.rebirthBonus
		* breakdown.equippedItemsBonus
		* breakdown.zoneBonus
		* (breakdown.customModifiersBonus or 1.0)
	return breakdown
end

function EconomyService:GetMultiplier(player: Player, currencyId: EconomyTypes.CurrencyId): number
	return self:GetMultiplierBreakdown(player, currencyId).total
end

function EconomyService:AddCurrency(
	player: Player,
	currencyId: EconomyTypes.CurrencyId,
	amount: number,
	reason: string?
): EconomyTypes.Result<number, EconomyTypes.EconomyErrorCode>
	if not isValidPlayerKey(player) then
		return SharedTypes.Err("INVALID_PLAYER")
	end

	local validRes = self:ValidateAmount(currencyId, amount)
	if not validRes.ok or not validRes.value then
		return SharedTypes.Err((validRes.error :: any) or "INVALID_AMOUNT")
	end
	local cleanAmount = validRes.value
	local def = registeredCurrencies[currencyId]
	local limitRule = customLimitRules[currencyId]
	local maxCap = if limitRule then limitRule.maxBalance else def.maxAmount

	local balanceBefore = 0
	local balanceAfter = 0
	local actualDelta = 0

	local updateRes = playerDataService:UpdateProfile(player, function(profile: SharedTypes.PlayerProfileData)
		balanceBefore = profile.currencies[currencyId] or 0
		balanceAfter = math.min(maxCap, balanceBefore + cleanAmount)
		actualDelta = balanceAfter - balanceBefore
		profile.currencies[currencyId] = balanceAfter
		if currencyId == "Coins" and actualDelta > 0 then
			profile.stats.totalCoinsEarned += actualDelta
		end
		return true
	end)

	if not updateRes.ok then
		return SharedTypes.Err((updateRes.error :: any) or "UPDATE_FAILED")
	end

	local txReason = reason or "AddCurrency"
	appendTransactionLog(player, currencyId, actualDelta, balanceBefore, balanceAfter, txReason)

	self.OnCurrencyChanged:Fire(player, currencyId, balanceAfter, actualDelta, txReason)
	if isRealPlayer(player) then
		Network.FireClient(player, Network.Events.CurrencyUpdated, currencyId, balanceAfter, actualDelta)
	end
	return SharedTypes.Ok(balanceAfter)
end

function EconomyService:RemoveCurrency(
	player: Player,
	currencyId: EconomyTypes.CurrencyId,
	amount: number,
	reason: string?
): EconomyTypes.Result<number, EconomyTypes.EconomyErrorCode>
	if not isValidPlayerKey(player) then
		return SharedTypes.Err("INVALID_PLAYER")
	end

	local validRes = self:ValidateAmount(currencyId, amount)
	if not validRes.ok or not validRes.value then
		return SharedTypes.Err((validRes.error :: any) or "INVALID_AMOUNT")
	end
	local cleanAmount = validRes.value

	local limitRule = customLimitRules[currencyId]
	local allowNegative = if limitRule then limitRule.allowNegative else false
	local minBalance = if limitRule then limitRule.minBalance else 0

	local balanceBefore = 0
	local balanceAfter = 0
	local insufficient = false

	local updateRes = playerDataService:UpdateProfile(player, function(profile: SharedTypes.PlayerProfileData)
		balanceBefore = profile.currencies[currencyId] or 0
		if not allowNegative and (balanceBefore - cleanAmount) < minBalance then
			insufficient = true
			return false
		end
		balanceAfter = balanceBefore - cleanAmount
		profile.currencies[currencyId] = balanceAfter
		return true
	end)

	if insufficient then
		return SharedTypes.Err("INSUFFICIENT_FUNDS")
	end
	if not updateRes.ok then
		return SharedTypes.Err((updateRes.error :: any) or "UPDATE_FAILED")
	end

	local txReason = reason or "RemoveCurrency"
	appendTransactionLog(player, currencyId, -cleanAmount, balanceBefore, balanceAfter, txReason)

	self.OnCurrencyChanged:Fire(player, currencyId, balanceAfter, -cleanAmount, txReason)
	if isRealPlayer(player) then
		Network.FireClient(player, Network.Events.CurrencyUpdated, currencyId, balanceAfter, -cleanAmount)
	end
	return SharedTypes.Ok(balanceAfter)
end

function EconomyService:ProcessSimulatorClick(
	player: Player,
	clientToolUid: string?
): EconomyTypes.Result<number, EconomyTypes.EconomyErrorCode>
	if not isValidPlayerKey(player) then
		return SharedTypes.Err("INVALID_PLAYER")
	end

	local now = os.clock()
	local lastClick = lastClickTimestamps[player] or 0
	local effectiveCooldown = GameConfig.Simulator.ClickCooldownSeconds * EconomyConfig.ClickCooldownJitterTolerance
	if (now - lastClick) < effectiveCooldown then
		return SharedTypes.Err("CLICK_COOLDOWN")
	end
	lastClickTimestamps[player] = now

	local profRes = playerDataService:GetProfile(player)
	if not profRes.ok or not profRes.value then
		return SharedTypes.Err("PROFILE_NOT_LOADED")
	end

	local gain = math.max(1, math.floor(GameConfig.Simulator.BaseCoinsPerClick * self:GetMultiplier(player, "Coins")))

	playerDataService:UpdateProfile(player, function(profile: SharedTypes.PlayerProfileData)
		profile.stats.totalClicks += 1
		return false
	end)

	local addRes = self:AddCurrency(player, "Coins", gain, "PrimaryAction")
	if addRes.ok then
		self.OnSimulatorClickProcessed:Fire(player, gain, clientToolUid)
	end
	return addRes
end

function EconomyService:GetTransactionHistory(player: Player): { EconomyTypes.EconomyTransactionRecord }
	local history = transactionLogs[player]
	if not history then
		return {}
	end
	return table.clone(history)
end

function EconomyService:ClearPlayerState(player: any): ()
	lastClickTimestamps[player] = nil
	transactionLogs[player] = nil
end

function EconomyService:Shutdown(): ()
	if clickConn then
		clickConn:Disconnect()
		clickConn = nil
	end
	table.clear(lastClickTimestamps)
	table.clear(transactionLogs)
	log:Info("Shutdown EconomyService")
end

return EconomyService
