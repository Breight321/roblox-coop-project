--!strict
--[[
	@module ShopService
	@owner Agent 1 (Breight321)
	@description Серверный бэкенд магазина: проверка условий покупки, списание валюты и выдача предмета.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Core"):WaitForChild("Types"))
local Logger = require(Shared:WaitForChild("Core"):WaitForChild("Logger"))
local Signal = require(Shared:WaitForChild("Core"):WaitForChild("Signal"))
local Network = require(Shared:WaitForChild("Core"):WaitForChild("Network"))

local ShopConfig = require(Shared:WaitForChild("Config"):WaitForChild("ShopConfig"))

local ShopService = {
	Name = "ShopService",
	Dependencies = { "PlayerDataService", "EconomyService", "InventoryService" },
	OnPurchaseCompleted = Signal.new(),
}

local log = Logger.new("ShopService")
local playerDataService: any = nil
local economyService: any = nil
local inventoryService: any = nil
local purchaseConn: RBXScriptConnection? = nil

function ShopService:Init(registry: any): ()
	playerDataService = registry:Get("PlayerDataService")
	economyService = registry:Get("EconomyService")
	inventoryService = registry:Get("InventoryService")
	log:Info("Initialized ShopService")
end

function ShopService:Start(): ()
	purchaseConn = Network.OnServerEvent(Network.Events.RequestShopPurchase, function(player: Player, shopItemId: any)
		if type(shopItemId) == "string" then
			self:PurchaseItem(player, shopItemId)
		end
	end)
end

function ShopService:GetCatalog(): { [string]: Types.ShopItemDef }
	return ShopConfig
end

function ShopService:PurchaseItem(player: Player, shopItemId: string): Types.Result<Types.InventoryItem, string>
	local offer = ShopConfig[shopItemId]
	if not offer then
		return Types.Err("UNKNOWN_SHOP_OFFER")
	end

	local profRes = playerDataService:GetProfile(player)
	if not profRes.ok or not profRes.value then
		return Types.Err("PROFILE_NOT_LOADED")
	end
	local profile: Types.PlayerProfileData = profRes.value

	if offer.requiredRebirths and profile.rebirths < offer.requiredRebirths then
		return Types.Err("INSUFFICIENT_REBIRTHS")
	end

	if offer.requiredZoneId and not profile.unlockedZones[offer.requiredZoneId] then
		return Types.Err("ZONE_LOCKED")
	end

	if not economyService:CanAfford(player, offer.currencyId, offer.price) then
		return Types.Err("INSUFFICIENT_FUNDS")
	end

	local deductRes = economyService:RemoveCurrency(player, offer.currencyId, offer.price, "ShopPurchase:" .. shopItemId)
	if not deductRes.ok then
		return Types.Err(deductRes.error or "PAYMENT_FAILED")
	end

	local grantRes = inventoryService:GrantItem(player, offer.itemId)
	if not grantRes.ok or not grantRes.value then
		-- Rollback currency on inventory failure
		economyService:AddCurrency(player, offer.currencyId, offer.price, "ShopRollback:" .. shopItemId)
		return Types.Err(grantRes.error or "GRANT_FAILED")
	end

	self.OnPurchaseCompleted:Fire(player, shopItemId, grantRes.value)
	Network.FireClient(player, Network.Events.Notification, "Success", "Purchased item: " .. offer.itemId)
	return Types.Ok(grantRes.value)
end

function ShopService:Shutdown(): ()
	if purchaseConn then
		purchaseConn:Disconnect()
		purchaseConn = nil
	end
	log:Info("Shutdown ShopService")
end

return ShopService
