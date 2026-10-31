--!strict
-- Модуль общих событий и контрактов между Сервером и Клиентом
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = {}

function Remotes.getOrCreateEvent(name: string): RemoteEvent
	local existing = ReplicatedStorage:FindFirstChild(name)
	if existing and existing:IsA("RemoteEvent") then
		return existing
	end
	local event = Instance.new("RemoteEvent")
	event.Name = name
	event.Parent = ReplicatedStorage
	return event
end

return Remotes
