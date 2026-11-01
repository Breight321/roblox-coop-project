--!strict
--[[
	@module InventoryService
	@owner Agent A (Breight321)
	@description Управление инвентарём игрока, проверка лимитов слотов, выдача предметов и экипировка.
]]

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Core"):WaitForChild("Types"))
local Logger = require(Shared:WaitForChild("Core"):WaitForChild("Logger"))
local Signal = require(Shared:WaitForChild("Core"):WaitForChild("Signal"))
local Network = require(Shared:WaitForChild("Core"):WaitForChild("Network"))

local GameConfig = require(Shared:WaitForChild("Config"):WaitForChild("GameConfig"))
local ItemsConfig = require(Shared:WaitForChild("Config"):WaitForChild("ItemsConfig"))

local InventoryService = {
	Name = "InventoryService",
	Dependencies = { "PlayerDataService" },
	OnItemGranted = Signal.new(),
	OnItemRemoved = Signal.new(),
	OnEquipmentChanged = Signal.new(),
}

local log = Logger.new("InventoryService")
local playerDataService: any = nil
local equipConn: RBXScriptConnection? = nil
local lastEquipClock: { [any]: number } = {}

local function isRealPlayer(player: any): boolean
	return typeof(player) == "Instance" and player:IsA("Player")
end

function InventoryService:Init(registry: any): ()
	playerDataService = registry:Get("PlayerDataService")
	log:Info("Initialized InventoryService")
end

function InventoryService:Start(): ()
	equipConn = Network.OnServerEvent(Network.Events.RequestEquipItem, function(player: Player, itemUid: any, equip: any)
		if type(itemUid) ~= "string" or #itemUid == 0 or #itemUid > 64 or type(equip) ~= "boolean" then
			return
		end
		local now = os.clock()
		if (now - (lastEquipClock[player] or 0)) < 0.1 then
			return
		end
		lastEquipClock[player] = now
		self:EquipItem(player, itemUid, equip)
	end)
end

function InventoryService:GetInventory(player: Player): { [string]: Types.InventoryItem }
	local res = playerDataService:GetProfile(player)
	if not res.ok or not res.value then
		return {}
	end
	return res.value.inventory
end

function InventoryService:GetItem(player: Player, itemUid: string): Types.InventoryItem?
	if type(itemUid) ~= "string" then
		return nil
	end
	local inv = self:GetInventory(player)
	return inv[itemUid]
end

function InventoryService:HasItemByTemplate(player: Player, itemId: string): boolean
	if type(itemId) ~= "string" then
		return false
	end
	for _, item in pairs(self:GetInventory(player)) do
		if item.itemId == itemId then
			return true
		end
	end
	return false
end

function InventoryService:GetCapacityInfo(player: Player): Types.InventoryCapacityInfo
	local usedSlots = 0
	local equippedPets = 0
	for _, item in pairs(self:GetInventory(player)) do
		usedSlots += 1
		if item.category == "Pet" and item.equipped then
			equippedPets += 1
		end
	end
	return {
		usedSlots = usedSlots,
		maxSlots = GameConfig.Simulator.MaxInventorySlots,
		equippedPetsCount = equippedPets,
		maxEquippedPets = GameConfig.Simulator.MaxEquippedPets,
	}
end

function InventoryService:GrantItem(player: Player, itemId: string): Types.Result<Types.InventoryItem, string>
	if type(itemId) ~= "string" then
		return Types.Err("UNKNOWN_ITEM_ID")
	end
	local def = ItemsConfig[itemId]
	if not def then
		return Types.Err("UNKNOWN_ITEM_ID")
	end

	local grantedItem: Types.InventoryItem? = nil
	local errReason: string? = nil

	local updateRes = playerDataService:UpdateProfile(player, function(profile: Types.PlayerProfileData)
		local count = 0
		for _ in pairs(profile.inventory) do
			count += 1
		end
		if count >= GameConfig.Simulator.MaxInventorySlots then
			errReason = "INVENTORY_FULL"
			return false
		end

		local uid = HttpService:GenerateGUID(false)
		local newItem: Types.InventoryItem = {
			uid = uid,
			itemId = itemId,
			category = def.category,
			equipped = false,
			level = 1,
			acquiredAt = os.time(),
		}
		profile.inventory[uid] = newItem
		grantedItem = newItem
		return true
	end)

	if errReason then
		return Types.Err(errReason)
	end
	if not updateRes.ok or not grantedItem then
		return Types.Err(updateRes.error or "GRANT_FAILED")
	end

	self.OnItemGranted:Fire(player, grantedItem)
	if isRealPlayer(player) then
		Network.FireClient(player, Network.Events.InventoryUpdated, self:GetInventory(player))
	end
	return Types.Ok(grantedItem)
end

function InventoryService:RemoveItem(player: Player, itemUid: string): Types.Result<boolean, string>
	if type(itemUid) ~= "string" or itemUid == "starter_wand_default" then
		return Types.Err("ITEM_NOT_FOUND")
	end

	local removed = false
	playerDataService:UpdateProfile(player, function(profile: Types.PlayerProfileData)
		if profile.inventory[itemUid] then
			profile.inventory[itemUid] = nil
			removed = true
			return true
		end
		return false
	end)

	if not removed then
		return Types.Err("ITEM_NOT_FOUND")
	end

	self.OnItemRemoved:Fire(player, itemUid)
	if isRealPlayer(player) then
		Network.FireClient(player, Network.Events.InventoryUpdated, self:GetInventory(player))
	end
	return Types.Ok(true)
end

function InventoryService:EquipItem(
	player: Player,
	itemUid: string,
	equipped: boolean
): Types.Result<Types.InventoryItem, string>
	local targetItem: Types.InventoryItem? = nil
	local errCode: string? = nil

	playerDataService:UpdateProfile(player, function(profile: Types.PlayerProfileData)
		local item = profile.inventory[itemUid]
		if not item then
			errCode = "ITEM_NOT_FOUND"
			return false
		end

		if equipped and item.category == "Tool" then
			for _, other in pairs(profile.inventory) do
				if other.category == "Tool" then
					other.equipped = false
				end
			end
		elseif equipped and item.category == "Pet" then
			local equippedPets = 0
			for _, other in pairs(profile.inventory) do
				if other.category == "Pet" and other.equipped and other.uid ~= itemUid then
					equippedPets += 1
				end
			end
			if equippedPets >= GameConfig.Simulator.MaxEquippedPets then
				errCode = "MAX_PETS_EQUIPPED"
				return false
			end
		end

		item.equipped = equipped
		targetItem = item
		return true
	end)

	if errCode then
		if isRealPlayer(player) and errCode == "MAX_PETS_EQUIPPED" then
			Network.FireClient(
				player,
				Network.Events.Notification,
				"Warning",
				string.format("Maximum %d pets can be equipped!", GameConfig.Simulator.MaxEquippedPets)
			)
		end
		return Types.Err(errCode)
	end
	if not targetItem then
		return Types.Err("EQUIP_FAILED")
	end

	self.OnEquipmentChanged:Fire(player, targetItem)
	if isRealPlayer(player) then
		Network.FireClient(player, Network.Events.InventoryUpdated, self:GetInventory(player))
	end
	return Types.Ok(targetItem)
end

function InventoryService:GetEquippedItems(
	player: Player,
	category: Types.ItemCategory?
): { Types.InventoryItem }
	local result = {}
	for _, item in pairs(self:GetInventory(player)) do
		if item.equipped and (category == nil or item.category == category) then
			table.insert(result, item)
		end
	end
	return result
end

function InventoryService:Shutdown(): ()
	if equipConn then
		equipConn:Disconnect()
		equipConn = nil
	end
	table.clear(lastEquipClock)
	log:Info("Shutdown InventoryService")
end

return InventoryService
