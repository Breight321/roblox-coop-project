--!strict
--[[
	@module ClientBootstrap (init.client.luau)
	@owner Agent B (anarugod) & Shared Bootstrap
	@description Точка входа клиентской части универсального фреймворка. Запускает изолированные клиентские тесты и автоматически загружает контроллеры.
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
	"Bootstrapping Universal Roblox Framework v%s (Client) for %s...",
	GameConfig.GameVersion,
	if localPlayer then localPlayer.Name else "LocalPlayer"
)

local controllersFolder = script:FindFirstChild("Controllers")

if GameConfig.RunTestsOnStartup then
	local uiFolder = script:FindFirstChild("UI")
	local shopUIFolder = if uiFolder then uiFolder:FindFirstChild("ShopUI") else nil
	local shopTestsFolder = if shopUIFolder then shopUIFolder:FindFirstChild("tests") else nil
	local shopTestsMod = if shopTestsFolder then shopTestsFolder:FindFirstChild("ShopUITests") else nil
	if shopTestsMod and shopTestsMod:IsA("ModuleScript") then
		local shopUITests = require(shopTestsMod) :: any
		TestRunner.RunSuite("ClientShopUISuite", shopUITests.GetTestCases())
	end

	if controllersFolder then
		local interactionMod = controllersFolder:FindFirstChild("InteractionController")
		local intTestsFolder = if interactionMod then interactionMod:FindFirstChild("tests") else nil
		local intTestsMod = if intTestsFolder then intTestsFolder:FindFirstChild("InteractionTests") else nil
		if intTestsMod and intTestsMod:IsA("ModuleScript") then
			local intTests = require(intTestsMod) :: any
			TestRunner.RunSuite("ClientInteractionSuite", intTests.GetTestCases())
		end

		local worldMod = controllersFolder:FindFirstChild("WorldController")
		local worldTestsFolder = if worldMod then worldMod:FindFirstChild("tests") else nil
		local worldTestsMod = if worldTestsFolder then worldTestsFolder:FindFirstChild("WorldTests") else nil
		if worldTestsMod and worldTestsMod:IsA("ModuleScript") then
			local worldTests = require(worldTestsMod) :: any
			TestRunner.RunSuite("ClientWorldSuite", worldTests.GetTestCases())
		end
	end
end

local clientRegistry = Registry.new("Client")

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
