--!strict
--[[
	@module HUDComponent
	@owner Agent 2 (anarugod)
	@description Главный игровой HUD: панели валют (Coins, Gems), уровень/XP, кнопки экранов и кнопка клика симулятора.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Types = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Core"):WaitForChild("Types"))
local Theme = require(script.Parent.Parent:WaitForChild("Theme"))

export type HUDCallbacks = {
	OnToggleScreen: (screenName: string) -> (),
	OnPrimaryClick: (button: GuiObject) -> (),
}

export type HUDHandle = {
	Root: Frame,
	CoinsLabel: TextLabel,
	GemsLabel: TextLabel,
	LevelLabel: TextLabel,
	ClickButton: TextButton,
	UpdateCurrencies: (self: HUDHandle, coins: number, gems: number) -> (),
	UpdateProgression: (self: HUDHandle, level: number, xp: number, rebirths: number) -> (),
}

local HUDComponent = {}

local function createStatBadge(parent: Instance, name: string, labelPrefix: string, accentColor: Color3, order: number): TextLabel
	local badge = Instance.new("Frame")
	badge.Name = name .. "Badge"
	badge.Size = UDim2.new(0, 165, 0, 42)
	badge.BackgroundColor3 = Theme.Colors.Surface
	badge.BorderSizePixel = 0
	badge.LayoutOrder = order
	badge.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = Theme.CornerRadius.Medium
	corner.Parent = badge

	local stroke = Instance.new("UIStroke")
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
	label.TextSize = 16
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Text = string.format("%s: 0", labelPrefix)
	label.Parent = badge

	return label
end

function HUDComponent.Create(parent: ScreenGui, callbacks: HUDCallbacks): HUDHandle
	local root = Instance.new("Frame")
	root.Name = "HUDRoot"
	root.Size = UDim2.new(1, 0, 1, 0)
	root.BackgroundTransparency = 1
	root.Parent = parent

	-- Top-Left Currency & Progression Bar
	local statsBar = Instance.new("Frame")
	statsBar.Name = "StatsBar"
	statsBar.Position = UDim2.new(0, 16, 0, 16)
	statsBar.Size = UDim2.new(0, 520, 0, 46)
	statsBar.BackgroundTransparency = 1
	statsBar.Parent = root

	local statsLayout = Instance.new("UIListLayout")
	statsLayout.FillDirection = Enum.FillDirection.Horizontal
	statsLayout.Padding = UDim.new(0, 10)
	statsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	statsLayout.Parent = statsBar

	local coinsLabel = createStatBadge(statsBar, "Coins", "Coins", Theme.Colors.Coins, 1)
	local gemsLabel = createStatBadge(statsBar, "Gems", "Gems", Theme.Colors.Gems, 2)
	local levelLabel = createStatBadge(statsBar, "Progression", "Lv. 1 | R: 0", Theme.Colors.Rebirth, 3)

	-- Left Navigation Buttons (Shop, Inventory, Quests, Rebirth)
	local navBar = Instance.new("Frame")
	navBar.Name = "NavBar"
	navBar.AnchorPoint = Vector2.new(0, 0.5)
	navBar.Position = UDim2.new(0, 16, 0.5, 0)
	navBar.Size = UDim2.new(0, 130, 0, 220)
	navBar.BackgroundTransparency = 1
	navBar.Parent = root

	local navLayout = Instance.new("UIListLayout")
	navLayout.Padding = UDim.new(0, 10)
	navLayout.SortOrder = Enum.SortOrder.LayoutOrder
	navLayout.Parent = navBar

	local navScreens = { "Shop", "Inventory", "Quests", "Rebirth" }
	for idx, screenName in ipairs(navScreens) do
		local btn = Instance.new("TextButton")
		btn.Name = screenName .. "Button"
		btn.Size = UDim2.new(1, 0, 0, 44)
		btn.BackgroundColor3 = Theme.Colors.SurfaceLight
		btn.Font = Theme.Fonts.Heading
		btn.TextColor3 = Theme.Colors.TextPrimary
		btn.TextSize = 16
		btn.Text = screenName
		btn.LayoutOrder = idx
		btn.Parent = navBar

		local btnCorner = Instance.new("UICorner")
		btnCorner.CornerRadius = Theme.CornerRadius.Medium
		btnCorner.Parent = btn

		btn.Activated:Connect(function()
			callbacks.OnToggleScreen(screenName)
		end)
	end

	-- Bottom-Center Primary Simulator Click Button
	local clickButton = Instance.new("TextButton")
	clickButton.Name = "PrimaryActionButton"
	clickButton.AnchorPoint = Vector2.new(0.5, 1)
	clickButton.Position = UDim2.new(0.5, 0, 1, -28)
	clickButton.Size = UDim2.new(0, 220, 0, 64)
	clickButton.BackgroundColor3 = Theme.Colors.Primary
	clickButton.Font = Theme.Fonts.Heading
	clickButton.TextColor3 = Theme.Colors.TextPrimary
	clickButton.TextSize = 20
	clickButton.Text = "⚡ COLLECT POWER"
	clickButton.Parent = root

	local clickCorner = Instance.new("UICorner")
	clickCorner.CornerRadius = Theme.CornerRadius.Pill
	clickCorner.Parent = clickButton

	clickButton.Activated:Connect(function()
		callbacks.OnPrimaryClick(clickButton)
	end)

	local handle: HUDHandle = {
		Root = root,
		CoinsLabel = coinsLabel,
		GemsLabel = gemsLabel,
		LevelLabel = levelLabel,
		ClickButton = clickButton,
		UpdateCurrencies = function(_self: HUDHandle, coins: number, gems: number)
			coinsLabel.Text = string.format("Coins: %d", math.floor(coins))
			gemsLabel.Text = string.format("Gems: %d", math.floor(gems))
		end,
		UpdateProgression = function(_self: HUDHandle, level: number, _xp: number, rebirths: number)
			levelLabel.Text = string.format("Lv. %d | R: %d", level, rebirths)
		end,
	}

	return handle
end

return HUDComponent
