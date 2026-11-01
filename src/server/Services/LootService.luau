--!strict
--[[
	@module LootService
	@owner Agent A (Breight321)
	@description Универсальный серверный сервис выбора и выдачи добычи (LootTables) для мобов и сундуков.
	Поддерживает гарантированные дропы (guaranteed), взвешенный случайный выбор (weight),
	детерминированный Random для модульных тестов и выдачу Currency, XP и Item.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Core"):WaitForChild("Types"))
local Logger = require(Shared:WaitForChild("Core"):WaitForChild("Logger"))
local Signal = require(Shared:WaitForChild("Core"):WaitForChild("Signal"))
local CombatConfig = require(Shared:WaitForChild("Config"):WaitForChild("CombatConfig"))

local LootService = {
	Name = "LootService",
	Dependencies = { "PlayerDataService", "EconomyService", "InventoryService", "ProgressionService" },
	OnLootGranted = Signal.new(),
}

local log = Logger.new("LootService")
local playerDataService: any = nil
local economyService: any = nil
local inventoryService: any = nil
local progressionService: any = nil
local defaultRng = Random.new()

local function isValidPlayerKey(player: any): boolean
	return player ~= nil and (typeof(player) == "Instance" or type(player) == "table")
end

local function rollAmount(entry: Types.LootEntryDef, rng: Random): number
	local minA = math.max(1, math.floor(entry.minAmount))
	local maxA = math.max(minA, math.floor(entry.maxAmount))
	if minA == maxA then
		return minA
	end
	return rng:NextInteger(minA, maxA)
end

local function pickWeightedEntry(entries: { Types.LootEntryDef }, rng: Random): Types.LootEntryDef?
	local totalWeight = 0
	for _, entry in ipairs(entries) do
		if not entry.guaranteed and entry.weight > 0 then
			totalWeight += entry.weight
		end
	end
	if totalWeight <= 0 then
		return nil
	end

	local roll = rng:NextNumber(0, totalWeight)
	local accum = 0
	for _, entry in ipairs(entries) do
		if not entry.guaranteed and entry.weight > 0 then
			accum += entry.weight
			if roll <= accum then
				return entry
			end
		end
	end
	return entries[#entries]
end

local function appendOrMergeDrop(drops: { Types.LootDrop }, dropType: "Currency" | "Item" | "XP", id: string, amount: number): ()
	if amount <= 0 then
		return
	end
	-- Валюту и XP одного типа объединяем в один элемент списка, а предметы с количеством также суммируем по id
	for _, existing in ipairs(drops) do
		if existing.dropType == dropType and existing.id == id then
			existing.amount += amount
			return
		end
	end
	table.insert(drops, {
		dropType = dropType,
		id = id,
		amount = amount,
	})
end

function LootService:Init(registry: any): ()
	playerDataService = registry:Get("PlayerDataService")
	economyService = registry:Get("EconomyService")
	inventoryService = registry:Get("InventoryService")
	progressionService = registry:Get("ProgressionService")
	log:Info("Initialized.")
end

function LootService:Start(): ()
	log:Info("Started.")
end

function LootService:Shutdown(): () end

function LootService:RollLootTable(lootTableId: string, customRng: Random?): { Types.LootDrop }
	local drops: { Types.LootDrop } = {}
	if type(lootTableId) ~= "string" then
		return drops
	end

	local tableDef: Types.LootTableDef? = CombatConfig.LootTables[lootTableId]
	if not tableDef then
		log:Warn("Unknown lootTableId '%s'", tostring(lootTableId))
		return drops
	end

	local rng = customRng or defaultRng

	-- 1. Гарантированные позиции
	for _, entry in ipairs(tableDef.entries) do
		if entry.guaranteed then
			local amount = rollAmount(entry, rng)
			appendOrMergeDrop(drops, entry.dropType, entry.id, amount)
		end
	end

	-- 2. Случайные взвешенные роллы
	local numRolls = math.max(0, math.floor(tableDef.rolls or 1))
	for _ = 1, numRolls do
		local picked = pickWeightedEntry(tableDef.entries, rng)
		if picked then
			local amount = rollAmount(picked, rng)
			appendOrMergeDrop(drops, picked.dropType, picked.id, amount)
		end
	end

	return drops
end

function LootService:GrantDrops(player: any, drops: { Types.LootDrop }, reason: string?): { Types.LootDrop }
	local granted: { Types.LootDrop } = {}
	if not isValidPlayerKey(player) or type(drops) ~= "table" then
		return granted
	end

	local profRes = playerDataService:GetProfile(player)
	if not profRes or (type(profRes) == "table" and profRes.ok == false) then
		return granted
	end

	local cleanReason = if type(reason) == "string" and #reason > 0 then reason else "LootDrop"

	for _, drop in ipairs(drops) do
		local amount = math.floor(drop.amount or 0)
		if amount > 0 then
			if drop.dropType == "Currency" then
				local res = economyService:AddCurrency(player, drop.id, amount, cleanReason)
				if res and res.ok then
					table.insert(granted, {
						dropType = "Currency",
						id = drop.id,
						amount = amount,
					})
				end
			elseif drop.dropType == "XP" then
				local res = progressionService:AddXP(player, amount)
				if res and res.ok then
					table.insert(granted, {
						dropType = "XP",
						id = "XP",
						amount = amount,
					})
				end
			elseif drop.dropType == "Item" and drop.id ~= "none" then
				local res = inventoryService:GrantItem(player, drop.id, amount)
				if res and res.ok then
					table.insert(granted, {
						dropType = "Item",
						id = drop.id,
						amount = amount,
					})
				end
			end
		end
	end

	if #granted > 0 then
		self.OnLootGranted:Fire(player, granted, cleanReason)
	end

	return granted
end

return LootService
