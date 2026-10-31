--!strict
--[[
	@module ServerBootstrap (init.server.luau)
	@owner Agent 1 (Breight321)
	@description Точка входа серверной части фреймворка. Инициализирует Network, Services и запускает тесты.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Core = Shared:WaitForChild("Core")
local Logger = require(Core:WaitForChild("Logger"))
local Network = require(Core:WaitForChild("Network"))
local Registry = require(Core:WaitForChild("Registry"))
local GameConfig = require(Shared:WaitForChild("Config"):WaitForChild("GameConfig"))
local FrameworkTests = require(Shared:WaitForChild("Tests"):WaitForChild("FrameworkTests"))

local log = Logger.new("ServerBootstrap")
log:Info("Bootstrapping Roblox Simulator Framework v%s (Server)...", GameConfig.GameVersion)

-- 1. Инициализация всех сетевых событий (RemoteEvents)
Network.BootstrapServer()

-- 2. Запуск встроенных модульных тестов фреймворка
if GameConfig.RunTestsOnStartup then
	local summary = FrameworkTests.RunAll()
	if summary.failed > 0 then
		log:Warn("Framework self-test reported %d failures!", summary.failed)
	end
end

-- 3. Регистрация и запуск всех серверных сервисов (Services)
local serverRegistry = Registry.new("Server")
local servicesFolder = script:WaitForChild("Services", 5)

if servicesFolder then
	for _, child in ipairs(servicesFolder:GetChildren()) do
		if child:IsA("ModuleScript") then
			local mod = require(child) :: any
			local regRes = serverRegistry:Register(mod)
			if not regRes.ok then
				log:Error("Failed to register service '%s': %s", child.Name, tostring(regRes.error))
			end
		end
	end
end

local initRes = serverRegistry:InitAll()
if initRes.ok then
	serverRegistry:StartAll()
	log:Info("Server Bootstrap complete.")
else
	log:Error("Server Bootstrap aborted due to initialization error: %s", tostring(initRes.error))
end

game:BindToClose(function()
	serverRegistry:ShutdownAll()
end)
