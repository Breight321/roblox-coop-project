--!strict
--[[
	@module InventoryService
	@owner Agent 1 (Breight321)
	@description Управление инвентарём игрока, выдача предметов и экипировка.
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
	OnEquipmentChanged = Signal.new(),
}

local log = Logger.new("InventoryService")
local playerDataService: any = nil
local equipConn: RBXScriptConnection? = nil

function InventoryService:Init(registry: any): ()
	playerDataService = registry:Get("PlayerDataService")
	log:Info("Initialized InventoryService")
end

function InventoryService:Start(): ()
	equipConn = Network.OnServerEvent(Network.Events.RequestEquipItem, function(player: Player, itemUid: any, equip: any)
		if type(itemUid) == "string" and type(equip) == "boolean" then
			self:EquipItem(player, itemUid, equip)
		end
	end)
end

function InventoryService:GetInventory(player: Player): { [string]: Types.InventoryItem }
	local res = playerDataService:GetProfile(player)
	if not res.ok or not res.value then
		return {}
	end
	return res.value.inventory
end

function InventoryService:GrantItem(player: Player, itemId: string): Types.Result<Types.InventoryItem, string>
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
	Network.FireClient(player, Network.Events.InventoryUpdated, self:GetInventory(player))
	return Types.Ok(grantedItem)
end

function InventoryService:RemoveItem(player: Player, itemUid: string): Types.Result<boolean, string>
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

	Network.FireClient(player, Network.Events.InventoryUpdated, self:GetInventory(player))
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
		return Types.Err(errCode)
	end
	if not targetItem then
		return Types.Err("EQUIP_FAILED")
	end

	self.OnEquipmentChanged:Fire(player, targetItem)
	Network.FireClient(player, Network.Events.InventoryUpdated, self:GetInventory(player))
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
	log:Info("Shutdown InventoryService")
end

return InventoryService
