--!strict
-- Главный серверный скрипт (ServerScriptService.Server)
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))

print("[Server] Сервер успешно запущен!")

Players.PlayerAdded:Connect(function(player: Player)
	print(string.format("[Server] Игрок %s присоединился к игре!", player.Name))
end)
