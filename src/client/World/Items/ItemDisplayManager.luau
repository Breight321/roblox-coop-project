--!strict
--[[
	@module ItemDisplayManager
	@owner Agent B (anarugod)
	@description Управление визуализацией экипированных деталей тела (Head, Arms, Torso, Legs —
	единый модульный стандарт ModularMech с золотым акцентом #E0A84A), инструментов (Tools) и питомцев (Pets).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Core"):WaitForChild("Types"))
local ItemsConfig = require(Shared:WaitForChild("Config"):WaitForChild("ItemsConfig"))

local ItemDisplayManager = {}

local activeEquippedToolUid: string? = nil
local activeEquippedPetUids: { string } = {}
local activeEquippedBodyParts: { [string]: string } = {}

function ItemDisplayManager.SyncInventory(inventory: { [string]: Types.InventoryItem }): ()
	activeEquippedToolUid = nil
	table.clear(activeEquippedPetUids)
	table.clear(activeEquippedBodyParts)

	for uid, item in pairs(inventory) do
		if item.equipped then
			local itemId = (item :: any).id or (item :: any).itemId
			local def = itemId and ItemsConfig[itemId] or nil
			local category = item.category or (if def then def.category else "")
			local meta = (def and def.metadata) or item.metadata
			local metaSlot = if type(meta) == "table" then (meta.bodySlot or meta.slot) else nil

			if metaSlot == "Head" or metaSlot == "Arms" or metaSlot == "Torso" or metaSlot == "Legs" then
				activeEquippedBodyParts[metaSlot] = uid
			elseif category == "BodyHead" or category == "Head" then
				activeEquippedBodyParts["Head"] = uid
			elseif category == "BodyArms" or category == "Arms" then
				activeEquippedBodyParts["Arms"] = uid
			elseif category == "BodyTorso" or category == "Torso" then
				activeEquippedBodyParts["Torso"] = uid
			elseif category == "BodyLegs" or category == "Legs" then
				activeEquippedBodyParts["Legs"] = uid
			end

			if category == "Tool" or (def and def.category == "Tool") then
				activeEquippedToolUid = uid
			elseif category == "Pet" or (def and def.category == "Pet") then
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

function ItemDisplayManager.GetEquippedBodyParts(): { [string]: string }
	return table.clone(activeEquippedBodyParts)
end

function ItemDisplayManager.Cleanup(): ()
	activeEquippedToolUid = nil
	table.clear(activeEquippedPetUids)
	table.clear(activeEquippedBodyParts)
end

return ItemDisplayManager
