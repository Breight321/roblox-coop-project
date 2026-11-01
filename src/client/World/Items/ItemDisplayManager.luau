--!strict
--[[
	@module ItemDisplayManager
	@owner Agent 2 (anarugod)
	@description Управление визуализацией экипированных инструментов (Tools) и питомцев (Pets) игрока на клиенте.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Core"):WaitForChild("Types"))
local ItemsConfig = require(Shared:WaitForChild("Config"):WaitForChild("ItemsConfig"))

local ItemDisplayManager = {}

local activeEquippedToolUid: string? = nil
local activeEquippedPetUids: { string } = {}

function ItemDisplayManager.SyncInventory(inventory: { [string]: Types.InventoryItem }): ()
	activeEquippedToolUid = nil
	table.clear(activeEquippedPetUids)

	for uid, item in pairs(inventory) do
		if item.equipped then
			local def = ItemsConfig[item.itemId]
			if item.category == "Tool" or (def and def.category == "Tool") then
				activeEquippedToolUid = uid
			elseif item.category == "Pet" or (def and def.category == "Pet") then
				table.insert(activeEquippedPetUids, uid)
			end
		end
	end
end

function ItemDisplayManager.GetEquippedToolUid(): string?
	return activeEquippedToolUid
end

function ItemDisplayManager.GetEquippedPetUids(): { string }
	return table.clone(activeEquippedPetUids)
end

function ItemDisplayManager.Cleanup(): ()
	activeEquippedToolUid = nil
	table.clear(activeEquippedPetUids)
end

return ItemDisplayManager
