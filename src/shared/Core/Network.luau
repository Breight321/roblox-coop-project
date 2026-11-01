--!strict
--[[
	@module Network
	@owner Agent A (Breight321) & Agent B (anarugod)
	@description Универсальный типизированный сетевой слой поверх src/shared/Remotes.luau с поддержкой регистрации пользовательских событий.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))

local Network = {}

Network.Events = {
	-- Server -> Client
	PlayerDataSync = "PlayerDataSync",
	CurrencyUpdated = "CurrencyUpdated",
	InventoryUpdated = "InventoryUpdated",
	ProgressionUpdated = "ProgressionUpdated",
	QuestUpdated = "QuestUpdated",
	ShopPurchaseResult = "ShopPurchaseResult",
	Notification = "Notification",

	-- Client -> Server
	RequestActionClick = "RequestActionClick",
	RequestShopPurchase = "RequestShopPurchase",
	RequestEquipItem = "RequestEquipItem",
	RequestRebirth = "RequestRebirth",
	RequestUnlockZone = "RequestUnlockZone",
	RequestClaimQuest = "RequestClaimQuest",
}

function Network.RegisterEvent(eventName: string): string
	assert(type(eventName) == "string" and #eventName > 0, "eventName must be a non-empty string")
	local eventsTable: any = Network.Events; eventsTable[eventName] = eventName
	if RunService:IsServer() then
		Remotes.getOrCreateEvent(eventName)
	end
	return eventName
end

function Network.BootstrapServer(): ()
	if not RunService:IsServer() then
		return
	end
	for _, eventName in pairs(Network.Events) do
		Remotes.getOrCreateEvent(eventName)
	end
end

function Network.GetEvent(eventName: string): RemoteEvent
	if RunService:IsServer() then
		return Remotes.getOrCreateEvent(eventName)
	else
		local existing = ReplicatedStorage:WaitForChild(eventName, 10)
		if existing and existing:IsA("RemoteEvent") then
			return existing
		end
		return Remotes.getOrCreateEvent(eventName)
	end
end

function Network.FireClient(player: Player, eventName: string, ...: any): ()
	assert(RunService:IsServer(), "FireClient can only be called from the Server")
	local remote = Network.GetEvent(eventName)
	remote:FireClient(player, ...)
end

function Network.FireAllClients(eventName: string, ...: any): ()
	assert(RunService:IsServer(), "FireAllClients can only be called from the Server")
	local remote = Network.GetEvent(eventName)
	remote:FireAllClients(...)
end

function Network.FireServer(eventName: string, ...: any): ()
	assert(RunService:IsClient(), "FireServer can only be called from the Client")
	local remote = Network.GetEvent(eventName)
	remote:FireServer(...)
end

function Network.OnServerEvent(eventName: string, handler: (player: Player, ...any) -> ()): RBXScriptConnection
	assert(RunService:IsServer(), "OnServerEvent can only be called from the Server")
	local remote = Network.GetEvent(eventName)
	return remote.OnServerEvent:Connect(handler)
end

function Network.OnClientEvent(eventName: string, handler: (...any) -> ()): RBXScriptConnection
	assert(RunService:IsClient(), "OnClientEvent can only be called from the Client")
	local remote = Network.GetEvent(eventName)
	return remote.OnClientEvent:Connect(handler)
end

return Network
