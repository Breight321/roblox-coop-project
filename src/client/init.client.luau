--!strict
--[[
	@module ClientBootstrap (init.client.luau)
	@owner Agent B (anarugod) & Shared Bootstrap
	@description Точка входа клиентской части фреймворка. Запускает клиентские тесты и автоматически загружает контроллеры из папки Controllers.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Core = Shared:WaitForChild("Core")
local Logger = require(Core:WaitForChild("Logger"))
local Registry = require(Core:WaitForChild("Registry"))
local TestRunner = require(Core:WaitForChild("TestRunner"))
local GameConfig = require(Shared:WaitForChild("Config"):WaitForChild("GameConfig"))

local log = Logger.new("ClientBootstrap")
local localPlayer = Players.LocalPlayer

log:Info(
	"Bootstrapping Roblox Simulator Framework v%s (Client) for %s...",
	GameConfig.GameVersion,
	if localPlayer then localPlayer.Name else "LocalPlayer"
)

if GameConfig.RunTestsOnStartup then
	local uiFolder = script:FindFirstChild("UI")
	local shopUIFolder = if uiFolder then uiFolder:FindFirstChild("ShopUI") else nil
	local testsFolder = if shopUIFolder then shopUIFolder:FindFirstChild("tests") else nil
	local shopTestsMod = if testsFolder then testsFolder:FindFirstChild("ShopUITests") else nil
	if shopTestsMod and shopTestsMod:IsA("ModuleScript") then
		local shopUITests = require(shopTestsMod) :: any
		TestRunner.RunSuite("ClientShopUISuite", shopUITests.GetTestCases())
	end
end

local clientRegistry = Registry.new("Client")
local controllersFolder = script:FindFirstChild("Controllers")

if controllersFolder then
	for _, child in ipairs(controllersFolder:GetChildren()) do
		if child:IsA("ModuleScript") then
			local mod = require(child) :: any
			local regRes = clientRegistry:Register(mod)
			if not regRes.ok then
				log:Error("Failed to register controller '%s': %s", child.Name, tostring(regRes.error))
			end
		end
	end
end

local initRes = clientRegistry:InitAll()
if initRes.ok then
	clientRegistry:StartAll()
	log:Info("Client Bootstrap complete.")
else
	log:Error("Client Bootstrap failed: %s", tostring(initRes.error))
end
