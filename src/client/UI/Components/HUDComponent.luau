--!strict
--[[
	@module HUDComponent
	@owner Agent B (anarugod)
	@description Компактный, читаемый игровой HUD:
	- Отображает баланс (Coins, Gems), уровень/ребирты, сводку характеристик сборки (Урон, Защита, Мобильность).
	- Показывает здоровье текущего моба-цели, индикатор попадания и полученную награду.
	- Показывает статус зоны (Безопасная PvE зона vs Добровольная PvP-арена).
	- Сохраняет обратную совместимость с индикатором сумки и общей цели сервера.
]]

local Theme = require(script.Parent.Parent:WaitForChild("Theme"))
local ControllersFolder = script.Parent.Parent.Parent:WaitForChild("Controllers")
local CombatTypes = require(ControllersFolder:WaitForChild("CombatController"):WaitForChild("Types"))

export type HUDCallbacks = {
	OnToggleScreen: (screenName: string) -> (),
	OnPrimaryClick: (button: GuiObject) -> (),
	OnDepositClick: ((button: GuiObject) -> ())?,
	OnRetryDepositClick: ((button: GuiObject) -> ())?,
	OnSyncTeamClick: (() -> ())?,
	OnAttackClick: ((button: GuiObject) -> ())?,
	OnLeaveArenaClick: (() -> ())?,
}

export type HUDHandle = {
	Root: Frame,
	CoinsLabel: TextLabel,
	GemsLabel: TextLabel,
	LevelLabel: TextLabel,
	BagLabel: TextLabel,
	BagFillBar: Frame,
	GuidanceLabel: TextLabel,
	TeamTitleLabel: TextLabel,
	TeamProgressLabel: TextLabel,
	TeamBarFill: Frame,
	MobTargetLabel: TextLabel,
	MobHpBarFill: Frame,
	PvpStatusLabel: TextLabel,
	ClickButton: TextButton,
	DepositButton: TextButton,
	RetryDepositButton: TextButton,
	UpdateCurrencies: (self: HUDHandle, coins: number, gems: number) -> (),
	UpdateProgression: (self: HUDHandle, level: number, xp: number, rebirths: number) -> (),
	UpdateBagState: (self: HUDHandle, bagState: any, toolPower: number?) -> (),
	UpdateTeamProgress: (self: HUDHandle, teamState: any) -> (),
	UpdateCombatState: (
		self: HUDHandle,
		mobTarget: CombatTypes.MobTargetViewModel,
		assemblySummary: CombatTypes.AssemblyStatsSummary,
		arenaState: CombatTypes.ArenaStateViewModel
	) -> (),
}

local HUDComponent = {}

local function createStatBadge(
	parent: Instance,
	name: string,
	initialText: string,
	accentColor: Color3,
	width: number,
	order: number
): (Frame, TextLabel)
	local badge = Instance.new("Frame")
	badge.Name = name .. "Badge"
	badge.Size = UDim2.new(0, width, 0, 40)
	badge.BackgroundColor3 = Theme.Colors.Surface
	badge.BorderSizePixel = 0
	badge.LayoutOrder = order
	badge.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = Theme.CornerRadius.Medium
	corner.Parent = badge

	local stroke = Instance.new("UIStroke")
	stroke.Name = "BadgeStroke"
	stroke.Color = accentColor
	stroke.Thickness = 1.5
	stroke.Parent = badge

	local label = Instance.new("TextLabel")
	label.Name = "ValueLabel"
	label.Size = UDim2.new(1, -14, 1, 0)
	label.Position = UDim2.new(0, 7, 0, 0)
	label.BackgroundTransparency = 1
	label.Font = Theme.Fonts.Heading
	label.TextColor3 = Theme.Colors.TextPrimary
	label.TextSize = 13
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Text = initialText
	label.Parent = badge

	return badge, label
end

function HUDComponent.Create(parent: ScreenGui, callbacks: HUDCallbacks): HUDHandle
	local root = Instance.new("Frame")
	root.Name = "HUDRoot"
	root.Size = UDim2.new(1, 0, 1, 0)
	root.BackgroundTransparency = 1
	root.Parent = parent

	-- ========================================================================
	-- 1. Top-Left: Валюты, Уровень, Статус PvP-зоны и Сумка
	-- ========================================================================
	local statsBar = Instance.new("Frame")
	statsBar.Name = "StatsBar"
	statsBar.Position = UDim2.new(0, 16, 0, 12)
	statsBar.Size = UDim2.new(0, 470, 0, 134)
	statsBar.BackgroundTransparency = 1
	statsBar.Parent = root

	local topRow = Instance.new("Frame")
	topRow.Name = "TopRow"
	topRow.Size = UDim2.new(1, 0, 0, 40)
	topRow.BackgroundTransparency = 1
	topRow.Parent = statsBar

	local topLayout = Instance.new("UIListLayout")
	topLayout.FillDirection = Enum.FillDirection.Horizontal
	topLayout.Padding = UDim.new(0, 8)
	topLayout.SortOrder = Enum.SortOrder.LayoutOrder
	topLayout.Parent = topRow

	local _, coinsLabel = createStatBadge(topRow, "Coins", "💰 Монеты: 0", Theme.Colors.Coins, 165, 1)
	local _, gemsLabel = createStatBadge(topRow, "Gems", "💎 Кристаллы: 0", Theme.Colors.Gems, 135, 2)
	local _, levelLabel = createStatBadge(topRow, "Progression", "Ур. 1 | R: 0", Theme.Colors.Rebirth, 140, 3)

	-- Индикатор статуса зоны (Безопасная PvE зона vs PvP Арена) + Статы сборки
	local pvpBadgeFrame = Instance.new("Frame")
	pvpBadgeFrame.Name = "ZoneAndBuildBadge"
	pvpBadgeFrame.Position = UDim2.new(0, 0, 0, 46)
	pvpBadgeFrame.Size = UDim2.new(0, 456, 0, 34)
	pvpBadgeFrame.BackgroundColor3 = Theme.Colors.Surface
	pvpBadgeFrame.BorderSizePixel = 0
	pvpBadgeFrame.Parent = statsBar

	local pvpCorner = Instance.new("UICorner")
	pvpCorner.CornerRadius = Theme.CornerRadius.Small
	pvpCorner.Parent = pvpBadgeFrame

	local pvpStroke = Instance.new("UIStroke")
	pvpStroke.Name = "PvpStroke"
	pvpStroke.Color = Theme.Colors.Success
	pvpStroke.Thickness = 1.5
	pvpStroke.Parent = pvpBadgeFrame

	local pvpStatusLabel = Instance.new("TextLabel")
	pvpStatusLabel.Name = "PvpStatusLabel"
	pvpStatusLabel.Position = UDim2.new(0, 10, 0, 0)
	pvpStatusLabel.Size = UDim2.new(1, -20, 1, 0)
	pvpStatusLabel.BackgroundTransparency = 1
	pvpStatusLabel.Font = Theme.Fonts.Heading
	pvpStatusLabel.TextColor3 = Theme.Colors.Success
	pvpStatusLabel.TextSize = 12
	pvpStatusLabel.TextXAlignment = Enum.TextXAlignment.Left
	pvpStatusLabel.Text = "🛡️ Безопасная зона (PvE)  |  ⚔️ Урон: 10  🛡️ Защ: 5  ⚡ Моб: 100"
	pvpStatusLabel.Parent = pvpBadgeFrame

	-- Карточка сумки (сохранена компактно)
	local bagCard = Instance.new("Frame")
	bagCard.Name = "BagCapacityCard"
	bagCard.Position = UDim2.new(0, 0, 0, 86)
	bagCard.Size = UDim2.new(0, 456, 0, 44)
	bagCard.BackgroundColor3 = Theme.Colors.Surface
	bagCard.BorderSizePixel = 0
	bagCard.Parent = statsBar

	local bagCorner = Instance.new("UICorner")
	bagCorner.CornerRadius = Theme.CornerRadius.Medium
	bagCorner.Parent = bagCard

	local bagStroke = Instance.new("UIStroke")
	bagStroke.Name = "BagStroke"
	bagStroke.Color = Theme.Colors.Primary
	bagStroke.Thickness = 1.2
	bagStroke.Parent = bagCard

	local bagLabel = Instance.new("TextLabel")
	bagLabel.Name = "BagLabel"
	bagLabel.Position = UDim2.new(0, 10, 0, 4)
	bagLabel.Size = UDim2.new(1, -20, 0, 18)
	bagLabel.BackgroundTransparency = 1
	bagLabel.Font = Theme.Fonts.Heading
	bagLabel.TextColor3 = Theme.Colors.TextPrimary
	bagLabel.TextSize = 13
	bagLabel.TextXAlignment = Enum.TextXAlignment.Left
	bagLabel.Text = "🎒 Сумка: 0 / 20 (0%) — Свободно"
	bagLabel.Parent = bagCard

	local bagBarBg = Instance.new("Frame")
	bagBarBg.Name = "BagBarBackground"
	bagBarBg.Position = UDim2.new(0, 10, 0, 26)
	bagBarBg.Size = UDim2.new(1, -20, 0, 10)
	bagBarBg.BackgroundColor3 = Theme.Colors.SurfaceLight
	bagBarBg.BorderSizePixel = 0
	bagBarBg.Parent = bagCard

	local bagBarCorner = Instance.new("UICorner")
	bagBarCorner.CornerRadius = Theme.CornerRadius.Pill
	bagBarCorner.Parent = bagBarBg

	local bagFillBar = Instance.new("Frame")
	bagFillBar.Name = "BagFillBar"
	bagFillBar.Size = UDim2.new(0, 0, 1, 0)
	bagFillBar.BackgroundColor3 = Theme.Colors.Primary
	bagFillBar.BorderSizePixel = 0
	bagFillBar.Parent = bagBarBg

	local bagFillCorner = Instance.new("UICorner")
	bagFillCorner.CornerRadius = Theme.CornerRadius.Pill
	bagFillCorner.Parent = bagFillBar

	-- ========================================================================
	-- 2. Top-Right: Здоровье текущего моба-цели + Командный прогресс
	-- ========================================================================
	local rightPanel = Instance.new("Frame")
	rightPanel.Name = "TopRightCombatAndTeamPanel"
	rightPanel.AnchorPoint = Vector2.new(1, 0)
	rightPanel.Position = UDim2.new(1, -16, 0, 12)
	rightPanel.Size = UDim2.new(0, 390, 0, 134)
	rightPanel.BackgroundTransparency = 1
	rightPanel.Parent = root

	-- Панель цели боя (Mob Health & Combat Feedback)
	local mobPanel = Instance.new("Frame")
	mobPanel.Name = "MobTargetPanel"
	mobPanel.Size = UDim2.new(1, 0, 0, 62)
	mobPanel.BackgroundColor3 = Theme.Colors.Surface
	mobPanel.BorderSizePixel = 0
	mobPanel.Parent = rightPanel

	local mobCorner = Instance.new("UICorner")
	mobCorner.CornerRadius = Theme.CornerRadius.Medium
	mobCorner.Parent = mobPanel

	local mobStroke = Instance.new("UIStroke")
	mobStroke.Color = Theme.Colors.Danger
	mobStroke.Thickness = 1.5
	mobStroke.Parent = mobPanel

	local mobTargetLabel = Instance.new("TextLabel")
	mobTargetLabel.Name = "MobTargetLabel"
	mobTargetLabel.Position = UDim2.new(0, 10, 0, 6)
	mobTargetLabel.Size = UDim2.new(1, -20, 0, 20)
	mobTargetLabel.BackgroundTransparency = 1
	mobTargetLabel.Font = Theme.Fonts.Heading
	mobTargetLabel.TextColor3 = Theme.Colors.TextPrimary
	mobTargetLabel.TextSize = 13
	mobTargetLabel.TextXAlignment = Enum.TextXAlignment.Left
	mobTargetLabel.Text = "👾 Цель: Луговой Автоматон-Страж (Ур. 1) • HP: 100 / 100"
	mobTargetLabel.Parent = mobPanel

	local mobFeedbackLabel = Instance.new("TextLabel")
	mobFeedbackLabel.Name = "MobFeedbackLabel"
	mobFeedbackLabel.Position = UDim2.new(0, 10, 0, 25)
	mobFeedbackLabel.Size = UDim2.new(1, -20, 0, 16)
	mobFeedbackLabel.BackgroundTransparency = 1
	mobFeedbackLabel.Font = Theme.Fonts.Body
	mobFeedbackLabel.TextColor3 = Theme.Colors.TextSecondary
	mobFeedbackLabel.TextSize = 11
	mobFeedbackLabel.TextXAlignment = Enum.TextXAlignment.Left
	mobFeedbackLabel.Text = "Нажмите ЛКМ / кнопку атаки для боя (урон подтверждается сервером)"
	mobFeedbackLabel.Parent = mobPanel

	local mobHpBg = Instance.new("Frame")
	mobHpBg.Name = "MobHpBackground"
	mobHpBg.Position = UDim2.new(0, 10, 0, 44)
	mobHpBg.Size = UDim2.new(1, -20, 0, 10)
	mobHpBg.BackgroundColor3 = Theme.Colors.SurfaceLight
	mobHpBg.BorderSizePixel = 0
	mobHpBg.Parent = mobPanel

	local mobHpCorner = Instance.new("UICorner")
	mobHpCorner.CornerRadius = Theme.CornerRadius.Pill
	mobHpCorner.Parent = mobHpBg

	local mobHpBarFill = Instance.new("Frame")
	mobHpBarFill.Name = "MobHpBarFill"
	mobHpBarFill.Size = UDim2.new(1, 0, 1, 0)
	mobHpBarFill.BackgroundColor3 = Theme.Colors.Danger
	mobHpBarFill.BorderSizePixel = 0
	mobHpBarFill.Parent = mobHpBg

	local mobHpFillCorner = Instance.new("UICorner")
	mobHpFillCorner.CornerRadius = Theme.CornerRadius.Pill
	mobHpFillCorner.Parent = mobHpBarFill

	-- Компактная панель общей цели сервера
	local teamPanel = Instance.new("Frame")
	teamPanel.Name = "TeamProgressPanel"
	teamPanel.Position = UDim2.new(0, 0, 0, 68)
	teamPanel.Size = UDim2.new(1, 0, 0, 64)
	teamPanel.BackgroundColor3 = Theme.Colors.Surface
	teamPanel.BorderSizePixel = 0
	teamPanel.Parent = rightPanel

	local teamCorner = Instance.new("UICorner")
	teamCorner.CornerRadius = Theme.CornerRadius.Medium
	teamCorner.Parent = teamPanel

	local teamStroke = Instance.new("UIStroke")
	teamStroke.Name = "TeamStroke"
	teamStroke.Color = Theme.Colors.Accent
	teamStroke.Thickness = 1.2
	teamStroke.Parent = teamPanel

	local teamTitleLabel = Instance.new("TextLabel")
	teamTitleLabel.Name = "TeamTitleLabel"
	teamTitleLabel.Position = UDim2.new(0, 10, 0, 4)
	teamTitleLabel.Size = UDim2.new(1, -20, 0, 18)
	teamTitleLabel.BackgroundTransparency = 1
	teamTitleLabel.Font = Theme.Fonts.Heading
	teamTitleLabel.TextColor3 = Theme.Colors.TextPrimary
	teamTitleLabel.TextSize = 13
	teamTitleLabel.TextXAlignment = Enum.TextXAlignment.Left
	teamTitleLabel.Text = "🌟 Этап мира: Awakening the Forge"
	teamTitleLabel.Parent = teamPanel

	local teamProgressLabel = Instance.new("TextLabel")
	teamProgressLabel.Name = "TeamProgressLabel"
	teamProgressLabel.Position = UDim2.new(0, 10, 0, 23)
	teamProgressLabel.Size = UDim2.new(1, -20, 0, 16)
	teamProgressLabel.BackgroundTransparency = 1
	teamProgressLabel.Font = Theme.Fonts.Body
	teamProgressLabel.TextColor3 = Theme.Colors.TextSecondary
	teamProgressLabel.TextSize = 11
	teamProgressLabel.TextXAlignment = Enum.TextXAlignment.Left
	teamProgressLabel.Text = "Командная цель: 0 / 100 (0%)"
	teamProgressLabel.Parent = teamPanel

	local teamBarBg = Instance.new("Frame")
	teamBarBg.Name = "TeamBarBackground"
	teamBarBg.Position = UDim2.new(0, 10, 0, 43)
	teamBarBg.Size = UDim2.new(1, -20, 0, 10)
	teamBarBg.BackgroundColor3 = Theme.Colors.SurfaceLight
	teamBarBg.BorderSizePixel = 0
	teamBarBg.Parent = teamPanel

	local teamBarCorner = Instance.new("UICorner")
	teamBarCorner.CornerRadius = Theme.CornerRadius.Pill
	teamBarCorner.Parent = teamBarBg

	local teamBarFill = Instance.new("Frame")
	teamBarFill.Name = "TeamBarFill"
	teamBarFill.Size = UDim2.new(0, 0, 1, 0)
	teamBarFill.BackgroundColor3 = Theme.Colors.Primary
	teamBarFill.BorderSizePixel = 0
	teamBarFill.Parent = teamBarBg

	local teamFillCorner = Instance.new("UICorner")
	teamFillCorner.CornerRadius = Theme.CornerRadius.Pill
	teamFillCorner.Parent = teamBarFill

	-- ========================================================================
	-- 3. Left Navigation Buttons (Сборка, Навыки, Сундуки, Арена, Магазин, Квесты, Ребирт, Улучшения)
	-- ========================================================================
	local navBar = Instance.new("Frame")
	navBar.Name = "NavBar"
	navBar.AnchorPoint = Vector2.new(0, 0.5)
	navBar.Position = UDim2.new(0, 16, 0.56, 0)
	navBar.Size = UDim2.new(0, 162, 0, 336)
	navBar.BackgroundTransparency = 1
	navBar.Parent = root

	local navLayout = Instance.new("UIListLayout")
	navLayout.Padding = UDim.new(0, 6)
	navLayout.SortOrder = Enum.SortOrder.LayoutOrder
	navLayout.Parent = navBar

	local navEntries = {
		{ id = "Inventory", label = "🦾 Сборка тела [I]", accent = Theme.Colors.Primary },
		{ id = "Skills", label = "🌳 Навыки [K]", accent = Theme.Colors.SurfaceLight },
		{ id = "Chests", label = "🧰 Сундуки [C]", accent = Theme.Colors.SurfaceLight },
		{ id = "Arena", label = "⚔️ PvP Арена [P]", accent = Theme.Colors.SurfaceLight },
		{ id = "Shop", label = "🛒 Магазин [B]", accent = Theme.Colors.SurfaceLight },
		{ id = "Upgrades", label = "🛠️ Мастерская [U]", accent = Theme.Colors.SurfaceLight },
		{ id = "Quests", label = "📜 Задания [Q]", accent = Theme.Colors.SurfaceLight },
		{ id = "Rebirth", label = "🔥 Возрождение [R]", accent = Theme.Colors.SurfaceLight },
	}

	for idx, entry in ipairs(navEntries) do
		local btn = Instance.new("TextButton")
		btn.Name = entry.id .. "Button"
		btn.Size = UDim2.new(1, 0, 0, 36)
		btn.BackgroundColor3 = entry.accent
		btn.Font = Theme.Fonts.Heading
		btn.TextColor3 = Theme.Colors.TextPrimary
		btn.TextSize = 13
		btn.Text = entry.label
		btn.LayoutOrder = idx
		btn.Parent = navBar

		local btnCorner = Instance.new("UICorner")
		btnCorner.CornerRadius = Theme.CornerRadius.Medium
		btnCorner.Parent = btn

		btn.Activated:Connect(function()
			callbacks.OnToggleScreen(entry.id)
		end)
	end

	-- ========================================================================
	-- 4. Bottom-Center Gameplay Loop Dock (Бой с мобами + Сдача добычи)
	-- ========================================================================
	local actionDock = Instance.new("Frame")
	actionDock.Name = "GameplayActionDock"
	actionDock.AnchorPoint = Vector2.new(0.5, 1)
	actionDock.Position = UDim2.new(0.5, 0, 1, -16)
	actionDock.Size = UDim2.new(0, 560, 0, 100)
	actionDock.BackgroundTransparency = 1
	actionDock.Parent = root

	local guidanceBanner = Instance.new("Frame")
	guidanceBanner.Name = "GuidanceBanner"
	guidanceBanner.Size = UDim2.new(1, 0, 0, 32)
	guidanceBanner.BackgroundColor3 = Theme.Colors.Surface
	guidanceBanner.BackgroundTransparency = 0.08
	guidanceBanner.BorderSizePixel = 0
	guidanceBanner.Parent = actionDock

	local guidanceCorner = Instance.new("UICorner")
	guidanceCorner.CornerRadius = Theme.CornerRadius.Small
	guidanceCorner.Parent = guidanceBanner

	local guidanceStroke = Instance.new("UIStroke")
	guidanceStroke.Name = "GuidanceStroke"
	guidanceStroke.Color = Theme.Colors.SurfaceLight
	guidanceStroke.Thickness = 1.5
	guidanceStroke.Parent = guidanceBanner

	local guidanceLabel = Instance.new("TextLabel")
	guidanceLabel.Name = "GuidanceLabel"
	guidanceLabel.Size = UDim2.new(1, -16, 1, 0)
	guidanceLabel.Position = UDim2.new(0, 8, 0, 0)
	guidanceLabel.BackgroundTransparency = 1
	guidanceLabel.Font = Theme.Fonts.Body
	guidanceLabel.TextColor3 = Theme.Colors.TextPrimary
	guidanceLabel.TextSize = 12
	guidanceLabel.Text = "⚔️ Сражайтесь с мобами, собирайте детали тела (Голова, Корпус, Руки, Ноги) и открывайте новые зоны!"
	guidanceLabel.Parent = guidanceBanner

	local buttonsRow = Instance.new("Frame")
	buttonsRow.Name = "ActionButtonsRow"
	buttonsRow.Position = UDim2.new(0, 0, 0, 38)
	buttonsRow.Size = UDim2.new(1, 0, 0, 58)
	buttonsRow.BackgroundTransparency = 1
	buttonsRow.Parent = actionDock

	local rowLayout = Instance.new("UIListLayout")
	rowLayout.FillDirection = Enum.FillDirection.Horizontal
	rowLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	rowLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	rowLayout.Padding = UDim.new(0, 10)
	rowLayout.SortOrder = Enum.SortOrder.LayoutOrder
	rowLayout.Parent = buttonsRow

	local clickButton = Instance.new("TextButton")
	clickButton.Name = "PrimaryActionButton"
	clickButton.Size = UDim2.new(0, 225, 0, 52)
	clickButton.BackgroundColor3 = Theme.Colors.Primary
	clickButton.Font = Theme.Fonts.Heading
	clickButton.TextColor3 = Theme.Colors.TextPrimary
	clickButton.TextSize = 15
	clickButton.Text = "⚔️ АТАКОВАТЬ / ДОБЫТЬ"
	clickButton.LayoutOrder = 1
	clickButton.Parent = buttonsRow

	local clickCorner = Instance.new("UICorner")
	clickCorner.CornerRadius = Theme.CornerRadius.Pill
	clickCorner.Parent = clickButton

	clickButton.Activated:Connect(function()
		callbacks.OnPrimaryClick(clickButton)
	end)

	local depositButton = Instance.new("TextButton")
	depositButton.Name = "DepositStationButton"
	depositButton.Size = UDim2.new(0, 210, 0, 52)
	depositButton.BackgroundColor3 = Theme.Colors.SurfaceLight
	depositButton.Font = Theme.Fonts.Heading
	depositButton.TextColor3 = Theme.Colors.TextSecondary
	depositButton.TextSize = 14
	depositButton.Text = "🏦 СТАНЦИЯ СДАЧИ (0)"
	depositButton.LayoutOrder = 2
	depositButton.Parent = buttonsRow

	local depCorner = Instance.new("UICorner")
	depCorner.CornerRadius = Theme.CornerRadius.Pill
	depCorner.Parent = depositButton

	depositButton.Activated:Connect(function()
		if callbacks.OnDepositClick then
			callbacks.OnDepositClick(depositButton)
		end
	end)

	local retryDepositButton = Instance.new("TextButton")
	retryDepositButton.Name = "RetryDepositButton"
	retryDepositButton.Size = UDim2.new(0, 96, 0, 52)
	retryDepositButton.BackgroundColor3 = Theme.Colors.Error
	retryDepositButton.Font = Theme.Fonts.Heading
	retryDepositButton.TextColor3 = Theme.Colors.TextPrimary
	retryDepositButton.TextSize = 13
	retryDepositButton.Text = "🔄 ПОВТОР"
	retryDepositButton.Visible = false
	retryDepositButton.LayoutOrder = 3
	retryDepositButton.Parent = buttonsRow

	local retryCorner = Instance.new("UICorner")
	retryCorner.CornerRadius = Theme.CornerRadius.Pill
	retryCorner.Parent = retryDepositButton

	retryDepositButton.Activated:Connect(function()
		if callbacks.OnRetryDepositClick then
			callbacks.OnRetryDepositClick(retryDepositButton)
		end
	end)

	local handle: HUDHandle = {
		Root = root,
		CoinsLabel = coinsLabel,
		GemsLabel = gemsLabel,
		LevelLabel = levelLabel,
		BagLabel = bagLabel,
		BagFillBar = bagFillBar,
		GuidanceLabel = guidanceLabel,
		TeamTitleLabel = teamTitleLabel,
		TeamProgressLabel = teamProgressLabel,
		TeamBarFill = teamBarFill,
		MobTargetLabel = mobTargetLabel,
		MobHpBarFill = mobHpBarFill,
		PvpStatusLabel = pvpStatusLabel,
		ClickButton = clickButton,
		DepositButton = depositButton,
		RetryDepositButton = retryDepositButton,
		UpdateCurrencies = function(_self: HUDHandle, coins: number, gems: number)
			coinsLabel.Text = string.format("💰 Монеты: %d", math.floor(coins))
			gemsLabel.Text = string.format("💎 Кристаллы: %d", math.floor(gems))
		end,
		UpdateProgression = function(_self: HUDHandle, level: number, _xp: number, rebirths: number)
			levelLabel.Text = string.format("Ур. %d | R: %d", level, rebirths)
		end,
		UpdateBagState = function(_self: HUDHandle, bagState: any, toolPower: number?)
			if type(bagState) ~= "table" then
				return
			end
			local pct = math.floor((bagState.fillRatio or 0) * 100)
			local stateTag = if bagState.isFull
				then "ПОЛНА! К СТАНЦИИ!"
				elseif bagState.isNearlyFull then "Почти полна"
				else "Свободно"

			bagLabel.Text = string.format(
				"🎒 Сумка: %d / %d (%d%%) — %s",
				bagState.current or 0,
				bagState.capacity or 20,
				pct,
				stateTag
			)
			bagFillBar.Size = UDim2.new(bagState.fillRatio or 0, 0, 1, 0)

			if bagState.isFull then
				bagFillBar.BackgroundColor3 = Theme.Colors.Error
				bagStroke.Color = Theme.Colors.Error
			elseif bagState.isNearlyFull then
				bagFillBar.BackgroundColor3 = Theme.Colors.Warning
				bagStroke.Color = Theme.Colors.Warning
			else
				bagFillBar.BackgroundColor3 = Theme.Colors.Primary
				bagStroke.Color = Theme.Colors.Primary
			end

			if type(bagState.guidanceText) == "string" then
				guidanceLabel.Text = bagState.guidanceText
			end

			local powerVal = toolPower or 2
			if bagState.isFull then
				clickButton.BackgroundColor3 = Color3.fromRGB(92, 54, 62)
				clickButton.Text = "🚨 СУМКА ПОЛНА"
			else
				clickButton.BackgroundColor3 = Theme.Colors.Primary
				clickButton.Text = string.format("⚔️ УДАР / ДОБЫЧА (+%d)", powerVal)
			end

			if bagState.depositStatus == "Loading" then
				depositButton.BackgroundColor3 = Theme.Colors.Warning
				depositButton.TextColor3 = Theme.Colors.Background
				depositButton.Text = "⏳ СДАЧА ДОБЫЧИ..."
				retryDepositButton.Visible = false
			elseif bagState.depositStatus == "Success" then
				depositButton.BackgroundColor3 = Theme.Colors.Primary
				depositButton.TextColor3 = Theme.Colors.TextPrimary
				depositButton.Text = "✓ ДОБЫЧА СДАНА!"
				retryDepositButton.Visible = false
			elseif bagState.depositStatus == "Error" then
				depositButton.BackgroundColor3 = Theme.Colors.Error
				depositButton.TextColor3 = Theme.Colors.TextPrimary
				depositButton.Text = "✗ ОТКАЗ СДАЧИ"
				retryDepositButton.Visible = bagState.canRetryDeposit == true
			elseif bagState.isFull then
				depositButton.BackgroundColor3 = Theme.Colors.Accent
				depositButton.TextColor3 = Theme.Colors.Background
				depositButton.Text = string.format("🚨 СДАТЬ СУМКУ (+%d)", bagState.current or 0)
				retryDepositButton.Visible = false
			elseif (bagState.current or 0) > 0 then
				depositButton.BackgroundColor3 = Theme.Colors.Success
				depositButton.TextColor3 = Theme.Colors.TextPrimary
				depositButton.Text = string.format("🏦 СДАТЬ НА СТАНЦИИ (+%d)", bagState.current or 0)
				retryDepositButton.Visible = false
			else
				depositButton.BackgroundColor3 = Theme.Colors.SurfaceLight
				depositButton.TextColor3 = Theme.Colors.TextSecondary
				depositButton.Text = "🏦 СТАНЦИЯ СДАЧИ (0)"
				retryDepositButton.Visible = false
			end
		end,
		UpdateTeamProgress = function(_self: HUDHandle, teamState: any)
			if type(teamState) ~= "table" then
				return
			end
			local pct = math.floor((teamState.progressRatio or 0) * 100)
			teamTitleLabel.Text = string.format("🌟 %s", tostring(teamState.stageName or "Stage 1"))
			teamProgressLabel.Text = string.format(
				"Командная цель: %d / %d (%d%%) • След.: %s",
				teamState.currentAmount or 0,
				teamState.targetAmount or 100,
				pct,
				tostring(teamState.nextStageName or "")
			)
			teamBarFill.Size = UDim2.new(teamState.progressRatio or 0, 0, 1, 0)
		end,
		UpdateCombatState = function(
			_self: HUDHandle,
			mobTarget: CombatTypes.MobTargetViewModel?,
			assemblySummary: CombatTypes.AssemblyStatsSummary,
			arenaState: CombatTypes.ArenaStateViewModel
		)
			local zoneTag = if arenaState.isSafeZone
				then "🛡️ Безопасная зона (PvE)"
				else "⚔️ В ЗОНЕ PvP-АРЕНЫ"
			pvpStatusLabel.Text = string.format(
				"%s  |  ⚔️ АТК: %d  🛡️ Броня: %d (-%d%%)  ❤️ HP: %d  ⚡ Скор: %d",
				zoneTag,
				assemblySummary.attackPower,
				assemblySummary.defense,
				assemblySummary.damageReductionPct,
				assemblySummary.maxHealth,
				assemblySummary.moveSpeed
			)
			pvpStatusLabel.TextColor3 = if arenaState.isSafeZone then Theme.Colors.Success else Theme.Colors.Danger
			pvpStroke.Color = if arenaState.isSafeZone then Theme.Colors.Success else Theme.Colors.Danger

			if not mobTarget then
				return
			end

			mobTargetLabel.Text = string.format(
				"👾 %s (Ур. %d) • HP: %d / %d",
				mobTarget.displayName,
				mobTarget.level,
				mobTarget.currentHp,
				mobTarget.maxHp
			)
			mobHpBarFill.Size = UDim2.new(math.clamp(mobTarget.hpRatio, 0, 1), 0, 1, 0)

			local hitParts: { string } = {}
			if mobTarget.lastHitDamage then
				table.insert(
					hitParts,
					string.format(
						"%s-%d HP",
						if mobTarget.lastHitCrit then "💥 КРИТ " else "Удар: ",
						mobTarget.lastHitDamage
					)
				)
			end
			if mobTarget.defeated then
				table.insert(hitParts, "🏆 Моб повержен!")
			end
			if mobTarget.lastRewardText then
				table.insert(hitParts, mobTarget.lastRewardText)
			end
			if #hitParts > 0 then
				mobFeedbackLabel.Text = table.concat(hitParts, "  •  ")
				mobFeedbackLabel.TextColor3 = Theme.Colors.Success
			end
		end,
	}

	return handle
end

return HUDComponent
