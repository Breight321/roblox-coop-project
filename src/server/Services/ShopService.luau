--!strict
--[[
	@module ShopService
	@owner Agent A (Breight321)
	@description Серверный бэкенд магазина: валидация запросов, защита от дублирования транзакций, списание валюты через EconomyService и выдача предмета.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Core"):WaitForChild("Types"))
local Logger = require(Shared:WaitForChild("Core"):WaitForChild("Logger"))
local Signal = require(Shared:WaitForChild("Core"):WaitForChild("Signal"))
local Network = require(Shared:WaitForChild("Core"):WaitForChild("Network"))

local ShopConfig = require(Shared:WaitForChild("Config"):WaitForChild("ShopConfig"))
local ItemsConfig = require(Shared:WaitForChild("Config"):WaitForChild("ItemsConfig"))

local PURCHASE_COOLDOWN_SECONDS = 0.25

local ShopService = {
	Name = "ShopService",
	Dependencies = { "PlayerDataService", "EconomyService", "InventoryService" },
	OnPurchaseCompleted = Signal.new(),
	OnPurchaseFailed = Signal.new(),
}

local log = Logger.new("ShopService")
local playerDataService: any = nil
local economyService: any = nil
local inventoryService: any = nil
local purchaseConn: RBXScriptConnection? = nil
local inFlightPurchases: { [any]: boolean } = {}
local lastPurchaseClock: { [any]: number } = {}

local function isRealPlayer(player: any): boolean
	return typeof(player) == "Instance" and player:IsA("Player")
end

local function emitPurchaseFailure(
	player: any,
	shopItemId: string,
	errorCode: string,
	message: string
): Types.Result<Types.InventoryItem, string>
	ShopService.OnPurchaseFailed:Fire(player, shopItemId, errorCode)
	if isRealPlayer(player) then
		local response: Types.ShopPurchaseResponse = {
			ok = false,
			shopItemId = shopItemId,
			errorCode = errorCode,
			message = message,
		}
		Network.FireClient(player, Network.Events.ShopPurchaseResult, response)
		Network.FireClient(player, Network.Events.Notification, "Error", message)
	end
	return Types.Err(errorCode)
end

function ShopService:Init(registry: any): ()
	playerDataService = registry:Get("PlayerDataService")
	economyService = registry:Get("EconomyService")
	inventoryService = registry:Get("InventoryService")
	log:Info("Initialized ShopService")
end

function ShopService:Start(): ()
	purchaseConn = Network.OnServerEvent(Network.Events.RequestShopPurchase, function(player: Player, shopItemId: any)
		if type(shopItemId) ~= "string" or #shopItemId == 0 or #shopItemId > 64 then
			emitPurchaseFailure(player, tostring(shopItemId), "INVALID_REQUEST", "Invalid shop item request.")
			return
		end

		local now = os.clock()
		if (now - (lastPurchaseClock[player] or 0)) < PURCHASE_COOLDOWN_SECONDS then
			emitPurchaseFailure(player, shopItemId, "RATE_LIMITED", "Please wait before making another purchase.")
			return
		end
		lastPurchaseClock[player] = now

		self:PurchaseItem(player, shopItemId)
	end)
end

function ShopService:GetCatalog(): { [string]: Types.ShopItemDef }
	return ShopConfig
end

function ShopService:GetCatalogByCategory(category: Types.ShopCategory): { Types.ShopItemDef }
	local list: { Types.ShopItemDef } = {}
	for _, offer in pairs(ShopConfig) do
		if offer.category == category then
			table.insert(list, offer)
		end
	end
	return list
end

function ShopService:PurchaseItem(player: Player, shopItemId: string): Types.Result<Types.InventoryItem, string>
	if type(shopItemId) ~= "string" or #shopItemId == 0 then
		return emitPurchaseFailure(player, tostring(shopItemId), "INVALID_REQUEST", "Invalid shop offer ID.")
	end

	if inFlightPurchases[player] then
		return emitPurchaseFailure(player, shopItemId, "TRANSACTION_IN_PROGRESS", "Transaction already in progress.")
	end
	inFlightPurchases[player] = true

	local offer = ShopConfig[shopItemId]
	if not offer then
		inFlightPurchases[player] = nil
		return emitPurchaseFailure(player, shopItemId, "UNKNOWN_SHOP_OFFER", "Item does not exist in shop.")
	end

	local profRes = playerDataService:GetProfile(player)
	if not profRes.ok or not profRes.value then
		inFlightPurchases[player] = nil
		return emitPurchaseFailure(player, shopItemId, "PROFILE_NOT_LOADED", "Player profile is not loaded yet.")
	end
	local profile: Types.PlayerProfileData = profRes.value

	local itemDef = ItemsConfig[offer.itemId]
	if itemDef and itemDef.category == "Tool" and inventoryService:HasItemByTemplate(player, offer.itemId) then
		inFlightPurchases[player] = nil
		return emitPurchaseFailure(player, shopItemId, "ALREADY_OWNED", "You already own this tool!")
	end

	if offer.requiredRebirths and profile.rebirths < offer.requiredRebirths then
		inFlightPurchases[player] = nil
		return emitPurchaseFailure(
			player,
			shopItemId,
			"INSUFFICIENT_REBIRTHS",
			string.format("Requires %d Rebirths!", offer.requiredRebirths)
		)
	end

	if offer.requiredZoneId and not profile.unlockedZones[offer.requiredZoneId] then
		inFlightPurchases[player] = nil
		return emitPurchaseFailure(player, shopItemId, "ZONE_LOCKED", "Unlock the required zone first!")
	end

	-- Цена и валюта берутся строго из серверного ShopConfig
	local serverPrice = offer.price
	local serverCurrency = offer.currencyId

	if not economyService:CanAfford(player, serverCurrency, serverPrice) then
		inFlightPurchases[player] = nil
		return emitPurchaseFailure(
			player,
			shopItemId,
			"INSUFFICIENT_FUNDS",
			string.format("Not enough %s! Need %d.", serverCurrency, serverPrice)
		)
	end

	local deductRes = economyService:RemoveCurrency(player, serverCurrency, serverPrice, "ShopPurchase:" .. shopItemId)
	if not deductRes.ok then
		inFlightPurchases[player] = nil
		return emitPurchaseFailure(
			player,
			shopItemId,
			deductRes.error or "PAYMENT_FAILED",
			"Could not process currency payment."
		)
	end

	local grantRes = inventoryService:GrantItem(player, offer.itemId)
	if not grantRes.ok or not grantRes.value then
		-- Автоматический возврат средств при ошибке выдачи предмета
		economyService:AddCurrency(player, serverCurrency, serverPrice, "ShopRollback:" .. shopItemId)
		inFlightPurchases[player] = nil
		return emitPurchaseFailure(
			player,
			shopItemId,
			grantRes.error or "GRANT_FAILED",
			"Inventory is full! Currency refunded."
		)
	end

	inFlightPurchases[player] = nil
	local grantedItem = grantRes.value
	local displayName = if itemDef then itemDef.displayName else offer.itemId
	local successMsg = string.format("Purchased %s for %d %s!", displayName, serverPrice, serverCurrency)

	self.OnPurchaseCompleted:Fire(player, shopItemId, grantedItem)
	if isRealPlayer(player) then
		local response: Types.ShopPurchaseResponse = {
			ok = true,
			shopItemId = shopItemId,
			itemId = offer.itemId,
			itemUid = grantedItem.uid,
			currencyId = serverCurrency,
			pricePaid = serverPrice,
			newBalance = deductRes.value,
			message = successMsg,
		}
		Network.FireClient(player, Network.Events.ShopPurchaseResult, response)
		Network.FireClient(player, Network.Events.Notification, "Success", successMsg)
	end

	return Types.Ok(grantedItem)
end

function ShopService:Shutdown(): ()
	if purchaseConn then
		purchaseConn:Disconnect()
		purchaseConn = nil
	end
	table.clear(inFlightPurchases)
	table.clear(lastPurchaseClock)
	log:Info("Shutdown ShopService")
end

return ShopService
