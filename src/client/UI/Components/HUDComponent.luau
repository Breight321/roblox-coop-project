--!strict
--[[
	@module HUDComponent
	@owner Agent B (anarugod)
	@description Главный игровой HUD для «Sunforge Expedition»:
	- Отображает подтверждённый сданный баланс (Банк), заполненность сумки и вместимость (Сумка).
	- Показывает общую командную цель этапа и прогресс открытия следующей локации.
	- Содержит индикатор «пора на станцию сдачи», кнопку добычи, кнопку сдачи добычи со статусами
	  Idle / Loading / Success / Error и кнопку повторного запроса (Retry).
]]

local Theme = require(script.Parent.Parent:WaitForChild("Theme"))
local ControllersFolder = script.Parent.Parent.Parent:WaitForChild("Controllers")
local ExpeditionTypes = require(ControllersFolder:WaitForChild("ExpeditionController"):WaitForChild("Types"))

export type HUDCallbacks = {
	OnToggleScreen: (screenName: string) -> (),
	OnPrimaryClick: (button: GuiObject) -> (),
	OnDepositClick: ((button: GuiObject) -> ())?,
	OnRetryDepositClick: ((button: GuiObject) -> ())?,
	OnSyncTeamClick: (() -> ())?,
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
	ClickButton: TextButton,
	DepositButton: TextButton,
	RetryDepositButton: TextButton,
	UpdateCurrencies: (self: HUDHandle, coins: number, gems: number) -> (),
	UpdateProgression: (self: HUDHandle, level: number, xp: number, rebirths: number) -> (),
	UpdateBagState: (self: HUDHandle, bagState: ExpeditionTypes.BagStateViewModel, toolPower: number?) -> (),
	UpdateTeamProgress: (self: HUDHandle, teamState: ExpeditionTypes.TeamProgressViewModel) -> (),
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
	badge.Size = UDim2.new(0, width, 0, 44)
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
	label.Size = UDim2.new(1, -16, 1, 0)
	label.Position = UDim2.new(0, 8, 0, 0)
	label.BackgroundTransparency = 1
	label.Font = Theme.Fonts.Heading
	label.TextColor3 = Theme.Colors.TextPrimary
	label.TextSize = 14
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
	-- 1. Top-Left Banked Balance, Bag Capacity & Progression Bar
	-- ========================================================================
	local statsBar = Instance.new("Frame")
	statsBar.Name = "StatsBar"
	statsBar.Position = UDim2.new(0, 16, 0, 14)
	statsBar.Size = UDim2.new(0, 460, 0, 102)
	statsBar.BackgroundTransparency = 1
	statsBar.Parent = root

	local topRow = Instance.new("Frame")
	topRow.Name = "TopRow"
	topRow.Size = UDim2.new(1, 0, 0, 44)
	topRow.BackgroundTransparency = 1
	topRow.Parent = statsBar

	local topLayout = Instance.new("UIListLayout")
	topLayout.FillDirection = Enum.FillDirection.Horizontal
	topLayout.Padding = UDim.new(0, 8)
	topLayout.SortOrder = Enum.SortOrder.LayoutOrder
	topLayout.Parent = topRow

	local _, coinsLabel = createStatBadge(topRow, "Coins", "🏦 Банк: 0 Монет", Theme.Colors.Coins, 175, 1)
	local _, gemsLabel = createStatBadge(topRow, "Gems", "💎 Кристаллы: 0", Theme.Colors.Gems, 135, 2)
	local _, levelLabel = createStatBadge(topRow, "Progression", "Ур. 1 | R: 0", Theme.Colors.Rebirth, 125, 3)

	-- Индикатор заполненности сумки (Bag Meter Card)
	local bagCard = Instance.new("Frame")
	bagCard.Name = "BagCapacityCard"
	bagCard.Position = UDim2.new(0, 0, 0, 52)
	bagCard.Size = UDim2.new(0, 451, 0, 48)
	bagCard.BackgroundColor3 = Theme.Colors.Surface
	bagCard.BorderSizePixel = 0
	bagCard.Parent = statsBar

	local bagCorner = Instance.new("UICorner")
	bagCorner.CornerRadius = Theme.CornerRadius.Medium
	bagCorner.Parent = bagCard

	local bagStroke = Instance.new("UIStroke")
	bagStroke.Name = "BagStroke"
	bagStroke.Color = Theme.Colors.Primary
	bagStroke.Thickness = 1.5
	bagStroke.Parent = bagCard

	local bagLabel = Instance.new("TextLabel")
	bagLabel.Name = "BagLabel"
	bagLabel.Position = UDim2.new(0, 12, 0, 4)
	bagLabel.Size = UDim2.new(1, -24, 0, 20)
	bagLabel.BackgroundTransparency = 1
	bagLabel.Font = Theme.Fonts.Heading
	bagLabel.TextColor3 = Theme.Colors.TextPrimary
	bagLabel.TextSize = 14
	bagLabel.TextXAlignment = Enum.TextXAlignment.Left
	bagLabel.Text = "🎒 Сумка: 0 / 20 (0%) — Свободно"
	bagLabel.Parent = bagCard

	local bagBarBg = Instance.new("Frame")
	bagBarBg.Name = "BagBarBackground"
	bagBarBg.Position = UDim2.new(0, 12, 0, 28)
	bagBarBg.Size = UDim2.new(1, -24, 0, 12)
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
	-- 2. Top-Right Shared Team Expedition Progress Panel
	-- ========================================================================
	local teamPanel = Instance.new("Frame")
	teamPanel.Name = "TeamProgressPanel"
	teamPanel.AnchorPoint = Vector2.new(1, 0)
	teamPanel.Position = UDim2.new(1, -16, 0, 14)
	teamPanel.Size = UDim2.new(0, 390, 0, 100)
	teamPanel.BackgroundColor3 = Theme.Colors.Surface
	teamPanel.BorderSizePixel = 0
	teamPanel.Parent = root

	local teamCorner = Instance.new("UICorner")
	teamCorner.CornerRadius = Theme.CornerRadius.Medium
	teamCorner.Parent = teamPanel

	local teamStroke = Instance.new("UIStroke")
	teamStroke.Name = "TeamStroke"
	teamStroke.Color = Theme.Colors.Accent
	teamStroke.Thickness = 1.5
	teamStroke.Parent = teamPanel

	local gameBrandLabel = Instance.new("TextLabel")
	gameBrandLabel.Name = "GameBrandLabel"
	gameBrandLabel.Position = UDim2.new(0, 12, 0, 6)
	gameBrandLabel.Size = UDim2.new(1, -54, 0, 16)
	gameBrandLabel.BackgroundTransparency = 1
	gameBrandLabel.Font = Theme.Fonts.Heading
	gameBrandLabel.TextColor3 = Theme.Colors.Accent
	gameBrandLabel.TextSize = 11
	gameBrandLabel.TextXAlignment = Enum.TextXAlignment.Left
	gameBrandLabel.Text = "✨ SUNFORGE EXPEDITION (КООПЕРАТИВ)"
	gameBrandLabel.Parent = teamPanel

	local syncBtn = Instance.new("TextButton")
	syncBtn.Name = "SyncTeamButton"
	syncBtn.AnchorPoint = Vector2.new(1, 0)
	syncBtn.Position = UDim2.new(1, -8, 0, 6)
	syncBtn.Size = UDim2.new(0, 34, 0, 22)
	syncBtn.BackgroundColor3 = Theme.Colors.SurfaceLight
	syncBtn.Font = Theme.Fonts.Heading
	syncBtn.TextColor3 = Theme.Colors.TextPrimary
	syncBtn.TextSize = 12
	syncBtn.Text = "🔄"
	syncBtn.Parent = teamPanel

	local syncCorner = Instance.new("UICorner")
	syncCorner.CornerRadius = Theme.CornerRadius.Small
	syncCorner.Parent = syncBtn

	syncBtn.Activated:Connect(function()
		if callbacks.OnSyncTeamClick then
			callbacks.OnSyncTeamClick()
		end
	end)

	local teamTitleLabel = Instance.new("TextLabel")
	teamTitleLabel.Name = "TeamTitleLabel"
	teamTitleLabel.Position = UDim2.new(0, 12, 0, 24)
	teamTitleLabel.Size = UDim2.new(1, -24, 0, 20)
	teamTitleLabel.BackgroundTransparency = 1
	teamTitleLabel.Font = Theme.Fonts.Heading
	teamTitleLabel.TextColor3 = Theme.Colors.TextPrimary
	teamTitleLabel.TextSize = 14
	teamTitleLabel.TextXAlignment = Enum.TextXAlignment.Left
	teamTitleLabel.Text = "🌟 Stage I: Awakening the Forge"
	teamTitleLabel.Parent = teamPanel

	local teamProgressLabel = Instance.new("TextLabel")
	teamProgressLabel.Name = "TeamProgressLabel"
	teamProgressLabel.Position = UDim2.new(0, 12, 0, 46)
	teamProgressLabel.Size = UDim2.new(1, -24, 0, 18)
	teamProgressLabel.BackgroundTransparency = 1
	teamProgressLabel.Font = Theme.Fonts.Body
	teamProgressLabel.TextColor3 = Theme.Colors.TextSecondary
	teamProgressLabel.TextSize = 12
	teamProgressLabel.TextXAlignment = Enum.TextXAlignment.Left
	teamProgressLabel.Text = "Командная цель: 0 / 100 (0%)"
	teamProgressLabel.Parent = teamPanel

	local teamBarBg = Instance.new("Frame")
	teamBarBg.Name = "TeamBarBackground"
	teamBarBg.Position = UDim2.new(0, 12, 0, 70)
	teamBarBg.Size = UDim2.new(1, -24, 0, 14)
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
	-- 3. Left Navigation Buttons (Upgrades, Shop, Inventory, Quests, Rebirth)
	-- ========================================================================
	local navBar = Instance.new("Frame")
	navBar.Name = "NavBar"
	navBar.AnchorPoint = Vector2.new(0, 0.5)
	navBar.Position = UDim2.new(0, 16, 0.54, 0)
	navBar.Size = UDim2.new(0, 156, 0, 265)
	navBar.BackgroundTransparency = 1
	navBar.Parent = root

	local navLayout = Instance.new("UIListLayout")
	navLayout.Padding = UDim.new(0, 8)
	navLayout.SortOrder = Enum.SortOrder.LayoutOrder
	navLayout.Parent = navBar

	local navEntries = {
		{ id = "Upgrades", label = "🛠️ Улучшения [U]", accent = Theme.Colors.Primary },
		{ id = "Shop", label = "🛒 Магазин [B]", accent = Theme.Colors.SurfaceLight },
		{ id = "Inventory", label = "🎒 Инвентарь [I]", accent = Theme.Colors.SurfaceLight },
		{ id = "Quests", label = "📜 Задания [Q]", accent = Theme.Colors.SurfaceLight },
		{ id = "Rebirth", label = "🔥 Возрождение [R]", accent = Theme.Colors.SurfaceLight },
	}

	for idx, entry in ipairs(navEntries) do
		local btn = Instance.new("TextButton")
		btn.Name = entry.id .. "Button"
		btn.Size = UDim2.new(1, 0, 0, 44)
		btn.BackgroundColor3 = entry.accent
		btn.Font = Theme.Fonts.Heading
		btn.TextColor3 = Theme.Colors.TextPrimary
		btn.TextSize = 14
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
	-- 4. Bottom-Center Gameplay Loop Dock (Guidance + Collect + Deposit + Retry)
	-- ========================================================================
	local actionDock = Instance.new("Frame")
	actionDock.Name = "GameplayActionDock"
	actionDock.AnchorPoint = Vector2.new(0.5, 1)
	actionDock.Position = UDim2.new(0.5, 0, 1, -18)
	actionDock.Size = UDim2.new(0, 560, 0, 108)
	actionDock.BackgroundTransparency = 1
	actionDock.Parent = root

	-- Баннер подсказки игрового цикла (что собирать и когда идти на станцию)
	local guidanceBanner = Instance.new("Frame")
	guidanceBanner.Name = "GuidanceBanner"
	guidanceBanner.Size = UDim2.new(1, 0, 0, 34)
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
	guidanceLabel.TextSize = 13
	guidanceLabel.Text = "⛏️ Собирайте Solar Shards в кратере Sunforge и сдавайте на Станции Переплавки!"
	guidanceLabel.Parent = guidanceBanner

	-- Ряд кнопок действий (Добыть | Сдать на станции | Повторить)
	local buttonsRow = Instance.new("Frame")
	buttonsRow.Name = "ActionButtonsRow"
	buttonsRow.Position = UDim2.new(0, 0, 0, 42)
	buttonsRow.Size = UDim2.new(1, 0, 0, 62)
	buttonsRow.BackgroundTransparency = 1
	buttonsRow.Parent = actionDock

	local rowLayout = Instance.new("UIListLayout")
	rowLayout.FillDirection = Enum.FillDirection.Horizontal
	rowLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	rowLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	rowLayout.Padding = UDim.new(0, 12)
	rowLayout.SortOrder = Enum.SortOrder.LayoutOrder
	rowLayout.Parent = buttonsRow

	local clickButton = Instance.new("TextButton")
	clickButton.Name = "PrimaryActionButton"
	clickButton.Size = UDim2.new(0, 220, 0, 58)
	clickButton.BackgroundColor3 = Theme.Colors.Primary
	clickButton.Font = Theme.Fonts.Heading
	clickButton.TextColor3 = Theme.Colors.TextPrimary
	clickButton.TextSize = 16
	clickButton.Text = "⛏️ ДОБЫТЬ ОСКОЛКИ (+2)"
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
	depositButton.Size = UDim2.new(0, 220, 0, 58)
	depositButton.BackgroundColor3 = Theme.Colors.SurfaceLight
	depositButton.Font = Theme.Fonts.Heading
	depositButton.TextColor3 = Theme.Colors.TextSecondary
	depositButton.TextSize = 15
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
	retryDepositButton.Size = UDim2.new(0, 100, 0, 58)
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
		ClickButton = clickButton,
		DepositButton = depositButton,
		RetryDepositButton = retryDepositButton,
		UpdateCurrencies = function(_self: HUDHandle, coins: number, gems: number)
			coinsLabel.Text = string.format("🏦 Банк: %d Монет", math.floor(coins))
			gemsLabel.Text = string.format("💎 Кристаллы: %d", math.floor(gems))
		end,
		UpdateProgression = function(_self: HUDHandle, level: number, _xp: number, rebirths: number)
			levelLabel.Text = string.format("Ур. %d | R: %d", level, rebirths)
		end,
		UpdateBagState = function(_self: HUDHandle, bagState: ExpeditionTypes.BagStateViewModel, toolPower: number?)
			local pct = math.floor(bagState.fillRatio * 100)
			local stateTag = if bagState.isFull
				then "ПОЛНА! К СТАНЦИИ!"
				elseif bagState.isNearlyFull then "Почти полна"
				else "Свободно"

			bagLabel.Text = string.format(
				"🎒 Сумка: %d / %d (%d%%) — %s",
				bagState.current,
				bagState.capacity,
				pct,
				stateTag
			)
			bagFillBar.Size = UDim2.new(bagState.fillRatio, 0, 1, 0)

			if bagState.isFull then
				bagFillBar.BackgroundColor3 = Theme.Colors.Error
				bagStroke.Color = Theme.Colors.Error
				guidanceStroke.Color = Theme.Colors.Accent
				guidanceLabel.TextColor3 = Theme.Colors.Accent
			elseif bagState.isNearlyFull then
				bagFillBar.BackgroundColor3 = Theme.Colors.Warning
				bagStroke.Color = Theme.Colors.Warning
				guidanceStroke.Color = Theme.Colors.Warning
				guidanceLabel.TextColor3 = Theme.Colors.Warning
			else
				bagFillBar.BackgroundColor3 = Theme.Colors.Primary
				bagStroke.Color = Theme.Colors.Primary
				guidanceStroke.Color = Theme.Colors.SurfaceLight
				guidanceLabel.TextColor3 = Theme.Colors.TextPrimary
			end

			guidanceLabel.Text = bagState.guidanceText

			local powerVal = toolPower or 2
			if bagState.isFull then
				clickButton.BackgroundColor3 = Color3.fromRGB(92, 54, 62)
				clickButton.Text = "🚨 СУМКА ПОЛНА"
			elseif bagState.collectStatus == "Loading" then
				clickButton.BackgroundColor3 = Theme.Colors.Primary
				clickButton.Text = string.format("⛏️ ДОБЫЧА... (+%d)", powerVal)
			else
				clickButton.BackgroundColor3 = Theme.Colors.Primary
				clickButton.Text = string.format("⛏️ ДОБЫТЬ ОСКОЛКИ (+%d)", powerVal)
			end

			-- Состояние кнопки сдачи на станции
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
				retryDepositButton.Visible = bagState.canRetryDeposit
			elseif bagState.isFull then
				depositButton.BackgroundColor3 = Theme.Colors.Accent
				depositButton.TextColor3 = Theme.Colors.Background
				depositButton.Text = string.format("🚨 СДАТЬ СУМКУ (+%d)", bagState.current)
				retryDepositButton.Visible = false
			elseif bagState.current > 0 then
				depositButton.BackgroundColor3 = Theme.Colors.Success
				depositButton.TextColor3 = Theme.Colors.TextPrimary
				depositButton.Text = string.format("🏦 СДАТЬ НА СТАНЦИИ (+%d)", bagState.current)
				retryDepositButton.Visible = false
			else
				depositButton.BackgroundColor3 = Theme.Colors.SurfaceLight
				depositButton.TextColor3 = Theme.Colors.TextSecondary
				depositButton.Text = "🏦 СТАНЦИЯ СДАЧИ (0)"
				retryDepositButton.Visible = false
			end
		end,
		UpdateTeamProgress = function(_self: HUDHandle, teamState: ExpeditionTypes.TeamProgressViewModel)
			local pct = math.floor(teamState.progressRatio * 100)
			if teamState.isUnlocked then
				teamTitleLabel.Text = string.format("🔓 %s (Этап %d)", teamState.stageName, teamState.stageNumber)
				teamTitleLabel.TextColor3 = Theme.Colors.Success
				teamStroke.Color = Theme.Colors.Success
				teamBarFill.BackgroundColor3 = Theme.Colors.Success
			else
				teamTitleLabel.Text = string.format("🌟 %s", teamState.stageName)
				teamTitleLabel.TextColor3 = Theme.Colors.TextPrimary
				teamStroke.Color = Theme.Colors.Accent
				teamBarFill.BackgroundColor3 = Theme.Colors.Primary
			end

			teamProgressLabel.Text = string.format(
				"Командная цель: %d / %d (%d%%) • След.: %s",
				teamState.currentAmount,
				teamState.targetAmount,
				pct,
				teamState.nextStageName
			)
			teamBarFill.Size = UDim2.new(teamState.progressRatio, 0, 1, 0)
		end,
	}

	return handle
end

return HUDComponent
