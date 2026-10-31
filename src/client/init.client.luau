--!strict
-- Главный клиентский скрипт (StarterPlayerScripts.Client)
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local _Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))
local localPlayer = Players.LocalPlayer

print(string.format("[Client] Клиент запущен для игрока %s", localPlayer.Name))
