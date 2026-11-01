--!strict
--[[
	@module UIController
	@owner Agent B (anarugod)
	@description Оркестратор пользовательского интерфейса:
	управление экранами через WindowManager, HUD (бой с мобами, сборка деталей тела, статус PvP-зоны,
	сумка и командная цель), инвентарь деталей тела (InventoryView), сундуки (ChestsView),
	дерево навыков (SkillTreeView), добровольная PvP-арена (ArenaView), ShopUI, квесты и ребирты.
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
local ChestsView = require(ComponentsFolder:WaitForChild("ChestsView"))
local SkillTreeView = require(ComponentsFolder:WaitForChild("SkillTreeView"))
local ArenaView = require(ComponentsFolder:WaitForChild("ArenaView"))
local QuestsView = require(ComponentsFolder:WaitForChild("QuestsView"))
local RebirthView = require(ComponentsFolder:WaitForChild("RebirthView"))

local UpgradesViewModule = ComponentsFolder:FindFirstChild("UpgradesView")
local UpgradesView: any = if UpgradesViewModule and UpgradesViewModule:IsA("ModuleScript")
	then require(UpgradesViewModule)
	else nil

local UIController = {
	Name = "UIController",
	Dependencies = { "AudioController", "AnimationController", "CombatController" },
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
local expeditionController: any = nil
local combatController: any = nil

local screenGui: ScreenGui? = nil
local hudHandle: HUDComponent.HUDHandle? = nil
local notificationContainer: Frame? = nil
local windowManager: WindowManager.WindowManagerInstance? = nil
local shopUI: ShopUI.ShopUIInstance? = nil

local cachedProfile: Types.PlayerProfileData? = nil
local connections: { RBXScriptConnection } = {}
local signalConnections: { any } = {}

function UIController:Init(registry: any): ()
	audioController = registry:Get("AudioController")
	animationController = registry:Get("AnimationController")
	combatController = registry:TryGet("CombatController")
	expeditionController = registry:TryGet("ExpeditionController")

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

function UIController:_refreshExpeditionUI(): ()
	if not expeditionController then
		return
	end

	local bagState = expeditionController:GetBagState()
	local bankedCoins = expeditionController:GetBankedBalance()
	local toolVm = expeditionController:GetUpgradeTrack("Tool")
	local bagVm = expeditionController:GetUpgradeTrack("Bag")
	local teamState = expeditionController:GetTeamProgress()

	if hudHandle then
		local gems = if cachedProfile and cachedProfile.currencies then (cachedProfile.currencies.Gems or 0) else 0
		hudHandle:UpdateCurrencies(bankedCoins, gems)
		hudHandle:UpdateBagState(bagState, toolVm.currentValue)
		hudHandle:UpdateTeamProgress(teamState)
	end

	if windowManager and UpgradesView then
		local upgradesWin = windowManager:GetWindow("Upgrades")
		if upgradesWin then
			UpgradesView.Render(upgradesWin.Content, bagState, bankedCoins, toolVm, bagVm, {
				OnRequestUpgrade = function(trackId)
					expeditionController:RequestUpgrade(trackId)
				end,
				OnRetryUpgrade = function(trackId)
					expeditionController:RetryUpgrade(trackId)
				end,
				OnRequestDeposit = function()
					expeditionController:RequestDeposit("ui_quick_deposit")
				end,
			})
		end
	end
end

function UIController:_refreshCombatAndAssemblyUI(): ()
	if not combatController then
		return
	end

	local mobTarget = combatController:GetActiveMobTarget()
	local assemblySummary = combatController:GetAssemblySummary()
	local arenaState = combatController:GetArenaState()
	local coins = if cachedProfile and cachedProfile.currencies
		then (cachedProfile.currencies.Coins or 0)
		elseif expeditionController then expeditionController:GetBankedBalance()
		else 0
	local unlockedZones = if cachedProfile then cachedProfile.unlockedZones else nil

	if hudHandle then
		hudHandle:UpdateCombatState(mobTarget, assemblySummary, arenaState)
	end

	if not windowManager then
		return
	end

	local invWin = windowManager:GetWindow("Inventory")
	if invWin then
		local invDict = if cachedProfile and cachedProfile.inventory then cachedProfile.inventory else {}
		local bodyPartsList = combatController:GetBodyPartsBySlot("All")
		InventoryView.Render(
			invWin.Content,
			invDict,
			function(itemUid: string, equip: boolean)
				combatController:RequestEquipBodyPart(itemUid, equip)
			end,
			assemblySummary,
			bodyPartsList
		)
	end

	local chestsWin = windowManager:GetWindow("Chests")
	if chestsWin then
		ChestsView.Render(
			chestsWin.Content,
			combatController:GetZoneChests(),
			coins,
			unlockedZones,
			function(chestId: string)
				combatController:RequestOpenChest(chestId)
			end
		)
	end

	local skillsWin = windowManager:GetWindow("Skills")
	if skillsWin then
		SkillTreeView.Render(
			skillsWin.Content,
			combatController:GetSkillTreeNodes(),
			combatController:GetSkillTreeSummary(),
			function(skillId: string)
				combatController:RequestUnlockSkill(skillId)
			end
		)
	end

	local arenaWin = windowManager:GetWindow("Arena")
	if arenaWin then
		ArenaView.Render(
			arenaWin.Content,
			arenaState,
			assemblySummary,
			function()
				combatController:RequestEnterArena()
			end,
			function()
				combatController:RequestLeaveArena()
			end
		)
	end
end

function UIController:_refreshDynamicViews(): ()
	self:_refreshExpeditionUI()
	self:_refreshCombatAndAssemblyUI()

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
		OnDepositClick = function(button: GuiObject)
			animationController:PlayUIEffect("Bounce", button)
			if expeditionController then
				local res = expeditionController:RequestDeposit("hud_deposit_button")
				if not res.ok and res.error == "BAG_EMPTY" then
					self:ShowNotification("Warning", "Сумка пуста! Сначала соберите ресурсы.")
				end
			end
		end,
		OnRetryDepositClick = function(button: GuiObject)
			animationController:PlayUIEffect("Bounce", button)
			if expeditionController then
				expeditionController:RetryDeposit()
			end
		end,
		OnSyncTeamClick = function()
			if expeditionController then
				expeditionController:RequestTeamSync()
				self:ShowNotification("Success", "Запрос синхронизации командной цели отправлен.")
			end
		end,
	})

	local modalDefinitions = {
		{ Name = "Inventory", Title = "🦾 Сборка Персонажа и Детали Тела (Голова, Корпус, Руки, Ноги)" },
		{ Name = "Skills", Title = "🌳 Дерево Навыков (Урон • Защита • Мобильность)" },
		{ Name = "Chests", Title = "🧰 Сундуки Локаций (Награды по подтверждению сервера)" },
		{ Name = "Arena", Title = "⚔️ Добровольная PvP-Арена (Обычные зоны безопасны)" },
		{ Name = "Shop", Title = "🛒 Магазин Экипировки и Питомцев" },
		{ Name = "Upgrades", Title = "🛠️ Мастерская Улучшений (Инструмент и Сумка)" },
		{ Name = "Quests", Title = "📜 Задания" },
		{ Name = "Rebirth", Title = "🔥 Алтарь Возрождения" },
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

	self:_refreshDynamicViews()
end

function UIController:Start(): ()
	self:_mountInterface()

	if combatController then
		table.insert(
			signalConnections,
			combatController.OnStateChanged:Connect(function()
				self:_refreshCombatAndAssemblyUI()
			end)
		)

		table.insert(
			signalConnections,
			combatController.OnMobDefeated:Connect(function(feedback: any)
				if type(feedback) == "table" then
					self:ShowNotification(
						"Reward",
						string.format(
							"🏆 Моб повержен! %s",
							tostring(feedback.rewardText or "Награда начислена сервером!")
						)
					)
				end
			end)
		)

		table.insert(
			signalConnections,
			combatController.OnAssemblyUpdated:Connect(function(summary: any)
				if type(summary) == "table" and type(summary.lastDeltaSummary) == "string" then
					self:ShowNotification("Success", "🦾 " .. summary.lastDeltaSummary)
				end
			end)
		)

		table.insert(
			signalConnections,
			combatController.OnChestResolved:Connect(function(chestVm: any)
				if type(chestVm) == "table" then
					if chestVm.status == "Success" and chestVm.lastRewardText then
						self:ShowNotification("Reward", chestVm.lastRewardText)
					elseif chestVm.status == "Error" and chestVm.statusMessage then
						self:ShowNotification("Error", chestVm.statusMessage)
					end
				end
			end)
		)

		table.insert(
			signalConnections,
			combatController.OnArenaMatchResolved:Connect(function(arenaVm: any)
				if type(arenaVm) == "table" and type(arenaVm.lastMatchMessage) == "string" then
					local notifKind = if arenaVm.lastMatchOutcome == "Victory" then "Reward" else "Warning"
					self:ShowNotification(notifKind, arenaVm.lastMatchMessage)
				end
			end)
		)
	end

	if expeditionController then
		table.insert(
			signalConnections,
			expeditionController.OnStateChanged:Connect(function()
				self:_refreshExpeditionUI()
			end)
		)

		table.insert(
			signalConnections,
			expeditionController.OnDepositResolved:Connect(function(response: any)
				if type(response) == "table" then
					if response.ok then
						self:ShowNotification(
							"Success",
							response.message
								or string.format("Сдано +%d Монет в банк и цель команды!", response.depositedAmount or 0)
						)
					else
						self:ShowNotification("Error", response.message or "Отказ сдачи добычи на станции.")
					end
				end
			end)
		)

		table.insert(
			signalConnections,
			expeditionController.OnUpgradeResolved:Connect(function(response: any)
				if type(response) == "table" then
					if response.ok then
						self:ShowNotification("Success", response.message or "Улучшение успешно приобретено!")
					else
						self:ShowNotification("Error", response.message or "Не удалось выполнить улучшение.")
					end
				end
			end)
		)

		table.insert(
			signalConnections,
			expeditionController.OnStageUnlocked:Connect(function(teamVm: any)
				if type(teamVm) == "table" then
					self:ShowNotification(
						"Reward",
						string.format("🎉 Командная цель достигнута! Открыт этап: %s!", tostring(teamVm.nextStageName))
					)
				end
			end)
		)
	end

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

function UIController:GetHUDHandle(): HUDComponent.HUDHandle?
	return hudHandle
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

	for _, conn in ipairs(signalConnections) do
		conn:Disconnect()
	end
	table.clear(signalConnections)

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
