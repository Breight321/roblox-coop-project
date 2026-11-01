--!strict
--[[
	@module ServerBootstrap (init.server.luau)
	@owner Agent A (Breight321)
	@description Точка входа серверной части фреймворка. Инициализирует Network, Services и запускает модульные и интеграционные тесты.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Core = Shared:WaitForChild("Core")
local Logger = require(Core:WaitForChild("Logger"))
local Network = require(Core:WaitForChild("Network"))
local Registry = require(Core:WaitForChild("Registry"))
local GameConfig = require(Shared:WaitForChild("Config"):WaitForChild("GameConfig"))
local FrameworkTests = require(Shared:WaitForChild("Tests"):WaitForChild("FrameworkTests"))
local CombatLoopTests = require(Shared:WaitForChild("Tests"):WaitForChild("CombatLoopTests"))

local log = Logger.new("ServerBootstrap")
log:Info("Bootstrapping Roblox Simulator Framework v%s (Server)...", GameConfig.GameVersion)

-- 1. Инициализация всех сетевых событий (RemoteEvents)
Network.BootstrapServer()

-- 2. Регистрация и запуск всех серверных сервисов (Services)
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

	-- 3. Запуск модульных и интеграционных тестов фреймворка, экономики, вертикального среза добычи и Combat Loop v1
	if GameConfig.RunTestsOnStartup then
		local coreSummary = FrameworkTests.RunAll()
		if coreSummary.failed > 0 then
			log:Warn("CoreFrameworkSuite reported %d failures!", coreSummary.failed)
		end

		local economyModule = if servicesFolder then servicesFolder:FindFirstChild("EconomyService") else nil
		local testsFolder = if economyModule then economyModule:FindFirstChild("tests") else nil
		local economyTestsScript = if testsFolder then testsFolder:FindFirstChild("EconomyTests") else nil
		if economyTestsScript and economyTestsScript:IsA("ModuleScript") then
			local EconomyTests = require(economyTestsScript) :: any
			local econSummary = EconomyTests.RunAll()
			if econSummary.failed > 0 then
				log:Warn("EconomyAndShopBackendSuite reported %d failures!", econSummary.failed)
			end
		end

		local harvestModule = if servicesFolder then servicesFolder:FindFirstChild("HarvestService") else nil
		local harvestTestsFolder = if harvestModule then harvestModule:FindFirstChild("tests") else nil
		local harvestTestsScript = if harvestTestsFolder then harvestTestsFolder:FindFirstChild("HarvestTests") else nil
		if harvestTestsScript and harvestTestsScript:IsA("ModuleScript") then
			local HarvestTests = require(harvestTestsScript) :: any
			local harvestSummary = HarvestTests.RunAll()
			if harvestSummary.failed > 0 then
				log:Warn("SunforgeHarvestBackendSuite reported %d failures!", harvestSummary.failed)
			end
		end

		local combatSummary = CombatLoopTests.RunAll()
		if combatSummary.failed > 0 then
			log:Warn("CombatLoopBackendSuite reported %d failures!", combatSummary.failed)
		end
	end
else
	log:Error("Server Bootstrap aborted due to initialization error: %s", tostring(initRes.error))
end

game:BindToClose(function()
	serverRegistry:ShutdownAll()
end)
