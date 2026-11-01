--!strict
--[[
	@module UIController
	@owner Agent 2 (anarugod)
	@description Оркестратор пользовательского интерфейса: управление экранами, HUD, уведомлениями и реактивной синхронизацией с сервером.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Core"):WaitForChild("Types"))
local Logger = require(Shared:WaitForChild("Core"):WaitForChild("Logger"))
local Signal = require(Shared:WaitForChild("Core"):WaitForChild("Signal"))
local Network = require(Shared:WaitForChild("Core"):WaitForChild("Network"))

local UIFolder = script.Parent.Parent:WaitForChild("UI")
local ComponentsFolder = UIFolder:WaitForChild("Components")
local HUDComponent = require(ComponentsFolder:WaitForChild("HUDComponent"))
local WindowComponent = require(ComponentsFolder:WaitForChild("WindowComponent"))
local NotificationComponent = require(ComponentsFolder:WaitForChild("NotificationComponent"))

local UIController = {
	Name = "UIController",
	Dependencies = { "AudioController", "AnimationController" },
	OnScreenChanged = Signal.new(),
	OnStateUpdated = Signal.new(),
	OnCurrencyUpdated = Signal.new(),
	OnInventoryUpdated = Signal.new(),
	OnProgressionUpdated = Signal.new(),
	OnQuestUpdated = Signal.new(),
	OnPrimaryClickRequested = Signal.new(),
}

local log = Logger.new("UIController")
local audioController: any = nil
local animationController: any = nil

local screenGui: ScreenGui? = nil
local hudHandle: HUDComponent.HUDHandle? = nil
local notificationContainer: Frame? = nil
local windows: { [string]: WindowComponent.WindowHandle } = {}
local activeScreen: string? = nil

local cachedProfile: Types.PlayerProfileData? = nil
local connections: { RBXScriptConnection } = {}

function UIController:Init(registry: any): ()
	audioController = registry:Get("AudioController")
	animationController = registry:Get("AnimationController")
	log:Info("Initialized UIController")
end

function UIController:_mountInterface(): ()
	local localPlayer = Players.LocalPlayer
	if not localPlayer then
		return
	end

	local playerGui = localPlayer:WaitForChild("PlayerGui", 5) :: PlayerGui?
	if not playerGui then
		return
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "SimulatorUI"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = playerGui
	screenGui = gui

	notificationContainer = NotificationComponent.CreateContainer(gui)

	hudHandle = HUDComponent.Create(gui, {
		OnToggleScreen = function(screenName: string)
			self:ToggleScreen(screenName)
		end,
		OnPrimaryClick = function(button: GuiObject)
			animationController:PlayUIEffect("Bounce", button)
			self.OnPrimaryClickRequested:Fire()
		end,
	})

	local modalDefinitions = {
		{ Name = "Shop", Title = "🛒 Simulator Shop" },
		{ Name = "Inventory", Title = "🎒 Inventory & Pets" },
		{ Name = "Quests", Title = "📜 Active Quests" },
		{ Name = "Rebirth", Title = "🔥 Rebirth Altar" },
	}

	for _, def in ipairs(modalDefinitions) do
		windows[def.Name] = WindowComponent.Create(gui, def.Name, def.Title, function()
			self:CloseScreen(def.Name)
		end)
	end
end

function UIController:Start(): ()
	self:_mountInterface()

	table.insert(
		connections,
		Network.OnClientEvent(Network.Events.PlayerDataSync, function(profile: Types.PlayerProfileData)
			cachedProfile = profile
			if hudHandle then
				hudHandle:UpdateCurrencies(profile.currencies.Coins or 0, profile.currencies.Gems or 0)
				hudHandle:UpdateProgression(profile.level, profile.xp, profile.rebirths)
			end
			self.OnStateUpdated:Fire(profile)
		end)
	)

	table.insert(
		connections,
		Network.OnClientEvent(
			Network.Events.CurrencyUpdated,
			function(currencyId: Types.CurrencyId, newBalance: number, delta: number)
				if cachedProfile then
					cachedProfile.currencies[currencyId] = newBalance
				end
				if hudHandle and cachedProfile then
					hudHandle:UpdateCurrencies(cachedProfile.currencies.Coins or 0, cachedProfile.currencies.Gems or 0)
				end
				self.OnCurrencyUpdated:Fire(currencyId, newBalance, delta)
			end
		)
	)

	table.insert(
		connections,
		Network.OnClientEvent(
			Network.Events.InventoryUpdated,
			function(inventory: { [string]: Types.InventoryItem })
				if cachedProfile then
					cachedProfile.inventory = inventory
				end
				self.OnInventoryUpdated:Fire(inventory)
			end
		)
	)

	table.insert(
		connections,
		Network.OnClientEvent(
			Network.Events.ProgressionUpdated,
			function(level: number, xp: number, rebirths: number, unlockedZones: { [string]: boolean })
				if cachedProfile then
					cachedProfile.level = level
					cachedProfile.xp = xp
					cachedProfile.rebirths = rebirths
					cachedProfile.unlockedZones = unlockedZones
				end
				if hudHandle then
					hudHandle:UpdateProgression(level, xp, rebirths)
				end
				self.OnProgressionUpdated:Fire(level, xp, rebirths, unlockedZones)
			end
		)
	)

	table.insert(
		connections,
		Network.OnClientEvent(Network.Events.QuestUpdated, function(questState: Types.QuestState)
			if cachedProfile then
				cachedProfile.quests[questState.questId] = questState
			end
			self.OnQuestUpdated:Fire(questState)
		end)
	)

	table.insert(
		connections,
		Network.OnClientEvent(Network.Events.Notification, function(notifType: string, message: string)
			self:ShowNotification(notifType, message)
		end)
	)

	log:Info("Started UIController")
end

function UIController:OpenScreen(screenName: string): ()
	if activeScreen and activeScreen ~= screenName then
		self:CloseScreen(activeScreen)
	end

	local win = windows[screenName]
	if win then
		win:SetVisible(true)
		animationController:PlayUIEffect("PopIn", win.Root)
	end

	activeScreen = screenName
	audioController:PlaySFX("UIButton")
	self.OnScreenChanged:Fire(screenName, true)
end

function UIController:CloseScreen(screenName: string): ()
	local win = windows[screenName]
	if win then
		win:SetVisible(false)
	end

	if activeScreen == screenName then
		activeScreen = nil
	end

	audioController:PlaySFX("UIButton")
	self.OnScreenChanged:Fire(screenName, false)
end

function UIController:ToggleScreen(screenName: string): ()
	if activeScreen == screenName then
		self:CloseScreen(screenName)
	else
		self:OpenScreen(screenName)
	end
end

function UIController:GetActiveScreen(): string?
	return activeScreen
end

function UIController:ShowNotification(notifType: string, message: string): ()
	if notificationContainer then
		NotificationComponent.ShowToast(notificationContainer, notifType, message, 3.0)
	end
	if notifType == "Error" then
		audioController:PlaySFX("Error")
	elseif notifType == "Reward" or notifType == "Success" then
		audioController:PlaySFX("Purchase")
	end
end

function UIController:GetClientState(): Types.PlayerProfileData?
	return cachedProfile
end

function UIController:Shutdown(): ()
	for _, conn in ipairs(connections) do
		conn:Disconnect()
	end
	table.clear(connections)
	table.clear(windows)

	if screenGui then
		screenGui:Destroy()
		screenGui = nil
	end

	activeScreen = nil
	log:Info("Shutdown UIController")
end

return UIController
