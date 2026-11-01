--!strict
--[[
	@module UIController
	@owner Agent B (anarugod)
	@description Оркестратор пользовательского интерфейса: управление экранами через WindowManager, HUD, модульным ShopUI, инвентарём, квестами, ребиртами и уведомлениями.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Core"):WaitForChild("Types"))
local Logger = require(Shared:WaitForChild("Core"):WaitForChild("Logger"))
local Signal = require(Shared:WaitForChild("Core"):WaitForChild("Signal"))
local Network = require(Shared:WaitForChild("Core"):WaitForChild("Network"))

local UIFolder = script.Parent.Parent:WaitForChild("UI")
local WindowManager = require(UIFolder:WaitForChild("WindowManager"))
local ShopUI = require(UIFolder:WaitForChild("ShopUI"))
local ComponentsFolder = UIFolder:WaitForChild("Components")
local HUDComponent = require(ComponentsFolder:WaitForChild("HUDComponent"))
local WindowComponent = require(ComponentsFolder:WaitForChild("WindowComponent"))
local NotificationComponent = require(ComponentsFolder:WaitForChild("NotificationComponent"))
local InventoryView = require(ComponentsFolder:WaitForChild("InventoryView"))
local QuestsView = require(ComponentsFolder:WaitForChild("QuestsView"))
local RebirthView = require(ComponentsFolder:WaitForChild("RebirthView"))

local UIController = {
	Name = "UIController",
	Dependencies = { "AudioController", "AnimationController" },
	OnScreenChanged = Signal.new(),
	OnStateUpdated = Signal.new(),
	OnCurrencyUpdated = Signal.new(),
	OnInventoryUpdated = Signal.new(),
	OnProgressionUpdated = Signal.new(),
	OnQuestUpdated = Signal.new(),
	OnShopPurchaseResolved = Signal.new(),
	OnPrimaryClickRequested = Signal.new(),
}

local log = Logger.new("UIController")
local audioController: any = nil
local animationController: any = nil

local screenGui: ScreenGui? = nil
local hudHandle: HUDComponent.HUDHandle? = nil
local notificationContainer: Frame? = nil
local windowManager: WindowManager.WindowManagerInstance? = nil
local shopUI: ShopUI.ShopUIInstance? = nil

local cachedProfile: Types.PlayerProfileData? = nil
local connections: { RBXScriptConnection } = {}

function UIController:Init(registry: any): ()
	audioController = registry:Get("AudioController")
	animationController = registry:Get("AnimationController")

	windowManager = WindowManager.new({
		OnWindowOpened = function(name: string, handle: WindowComponent.WindowHandle)
			animationController:PlayUIEffect("PopIn", handle.Root)
			audioController:PlaySFX("UIButton")
			self.OnScreenChanged:Fire(name, true)
		end,
		OnWindowClosed = function(name: string, _handle: WindowComponent.WindowHandle)
			audioController:PlaySFX("UIButton")
			self.OnScreenChanged:Fire(name, false)
		end,
	})

	shopUI = ShopUI.new()
	if shopUI then
		shopUI.OnPurchaseRequested:Connect(function(shopItemId: string)
			audioController:PlaySFX("UIButton")
			Network.FireServer(Network.Events.RequestShopPurchase, shopItemId)
		end)
	end

	log:Info("Initialized UIController")
end

function UIController:_refreshDynamicViews(): ()
	if not cachedProfile or not windowManager then
		return
	end

	if shopUI then
		shopUI:UpdatePlayerContext({
			currencies = cachedProfile.currencies,
			rebirths = cachedProfile.rebirths,
			unlockedZones = cachedProfile.unlockedZones,
		})
	end

	local invWin = windowManager:GetWindow("Inventory")
	if invWin then
		InventoryView.Render(invWin.Content, cachedProfile.inventory, function(itemUid: string, equip: boolean)
			audioController:PlaySFX("UIButton")
			Network.FireServer(Network.Events.RequestEquipItem, itemUid, equip)
		end)
	end

	local questsWin = windowManager:GetWindow("Quests")
	if questsWin then
		QuestsView.Render(questsWin.Content, cachedProfile.quests, function(questId: string)
			audioController:PlaySFX("UIButton")
			Network.FireServer(Network.Events.RequestClaimQuest, questId)
		end)
	end

	local rebirthWin = windowManager:GetWindow("Rebirth")
	if rebirthWin then
		RebirthView.Render(
			rebirthWin.Content,
			cachedProfile.rebirths,
			cachedProfile.currencies.Coins or 0,
			function()
				audioController:PlaySFX("UIButton")
				Network.FireServer(Network.Events.RequestRebirth)
			end
		)
	end
end

function UIController:_mountInterface(): ()
	local localPlayer = Players.LocalPlayer
	if not localPlayer or not windowManager then
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
		local handle = WindowComponent.Create(gui, def.Name, def.Title, function()
			self:CloseScreen(def.Name)
		end)
		windowManager:RegisterWindow(def.Name, handle)
	end

	local shopWin = windowManager:GetWindow("Shop")
	if shopWin and shopUI then
		shopUI:Mount(shopWin.Content)
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
			self:_refreshDynamicViews()
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
				self:_refreshDynamicViews()
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
				if shopUI and shopUI:GetStatus() == "Loading" then
					shopUI:ResolvePurchase(nil, true, "Purchase complete!")
				end
				self:_refreshDynamicViews()
				self.OnInventoryUpdated:Fire(inventory)
			end
		)
	)

	local shopResultEventName = (Network.Events :: any).ShopPurchaseResult or "ShopPurchaseResult"
	table.insert(
		connections,
		Network.OnClientEvent(shopResultEventName, function(response: any)
			if type(response) == "table" and shopUI then
				shopUI:ResolvePurchase(response.shopItemId, response.ok == true, response.message)
				self.OnShopPurchaseResolved:Fire(response)
			end
		end)
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
				self:_refreshDynamicViews()
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
			self:_refreshDynamicViews()
			self.OnQuestUpdated:Fire(questState)
		end)
	)

	table.insert(
		connections,
		Network.OnClientEvent(Network.Events.Notification, function(notifType: string, message: string)
			if shopUI and shopUI:GetStatus() == "Loading" and notifType == "Error" then
				shopUI:ResolvePurchase(nil, false, message)
			end
			self:ShowNotification(notifType, message)
		end)
	)

	log:Info("Started UIController")
end

function UIController:OpenScreen(screenName: string): ()
	self:_refreshDynamicViews()
	if windowManager then
		windowManager:Open(screenName)
	end
end

function UIController:CloseScreen(screenName: string): ()
	if windowManager then
		windowManager:Close(screenName)
	end
end

function UIController:CloseAllScreens(): ()
	if windowManager then
		windowManager:CloseAll()
	end
end

function UIController:ToggleScreen(screenName: string): ()
	self:_refreshDynamicViews()
	if windowManager then
		windowManager:Toggle(screenName)
	end
end

function UIController:GetActiveScreen(): string?
	if windowManager then
		return windowManager:GetActiveWindow()
	end
	return nil
end

function UIController:IsAnyWindowOpen(): boolean
	if windowManager then
		return windowManager:IsAnyWindowOpen()
	end
	return false
end

function UIController:GetWindowManager(): WindowManager.WindowManagerInstance?
	return windowManager
end

function UIController:GetShopUI(): ShopUI.ShopUIInstance?
	return shopUI
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

	if shopUI then
		shopUI:Destroy()
		shopUI = nil
	end

	if windowManager then
		windowManager:Destroy()
		windowManager = nil
	end

	if screenGui then
		screenGui:Destroy()
		screenGui = nil
	end

	log:Info("Shutdown UIController")
end

return UIController
