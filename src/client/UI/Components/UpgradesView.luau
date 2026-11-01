--!strict
--[[
	@module UpgradesView
	@owner Agent B (anarugod)
	@description Экран улучшений инструмента (Tool) и вместимости сумки (Bag) для «Aetherfall: Expedition Core»:
	показывает текущий уровень, прирост характеристик, цену, недоступное состояние при нехватке средств,
	состояния Loading / Success / Error и кнопку повторного запроса (Retry).
]]

local Theme = require(script.Parent.Parent:WaitForChild("Theme"))
local ControllersFolder = script.Parent.Parent.Parent:WaitForChild("Controllers")
local ExpeditionTypes = require(ControllersFolder:WaitForChild("ExpeditionController"):WaitForChild("Types"))

export type UpgradesViewCallbacks = {
	OnRequestUpgrade: (trackId: ExpeditionTypes.UpgradeTrackId) -> (),
	OnRetryUpgrade: (trackId: ExpeditionTypes.UpgradeTrackId) -> (),
	OnRequestDeposit: () -> (),
}

local UpgradesView = {}

local function renderUpgradeCard(
	parent: ScrollingFrame,
	vm: ExpeditionTypes.UpgradeTrackViewModel,
	layoutOrder: number,
	callbacks: UpgradesViewCallbacks
): ()
	local card = Instance.new("Frame")
	card.Name = "UpgradeCard_" .. vm.trackId
	card.Size = UDim2.new(1, -8, 0, 118)
	card.BackgroundColor3 = Theme.Colors.Surface
	card.BorderSizePixel = 0
	card.LayoutOrder = layoutOrder
	card.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = Theme.CornerRadius.Medium
	corner.Parent = card

	local stroke = Instance.new("UIStroke")
	stroke.Color = if vm.buttonState == "Available"
		then Theme.Colors.Success
		elseif vm.buttonState == "Success" then Theme.Colors.Primary
		elseif vm.buttonState == "Loading" then Theme.Colors.Warning
		elseif vm.buttonState == "Error" then Theme.Colors.Error
		else Theme.Colors.SurfaceLight
	stroke.Thickness = 1.5
	stroke.Parent = card

	-- Заголовок и текущий уровень
	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "TitleLabel"
	titleLabel.Position = UDim2.new(0, 14, 0, 10)
	titleLabel.Size = UDim2.new(1, -185, 0, 22)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Font = Theme.Fonts.Heading
	titleLabel.TextColor3 = Theme.Colors.TextPrimary
	titleLabel.TextSize = 16
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.Text = string.format("%s  [Ур. %d / %d]", vm.displayName, vm.level, vm.maxLevel)
	titleLabel.Parent = card

	-- Описание и переход характеристик (Текущее -> Следующее)
	local statsLabel = Instance.new("TextLabel")
	statsLabel.Name = "StatsLabel"
	statsLabel.Position = UDim2.new(0, 14, 0, 34)
	statsLabel.Size = UDim2.new(1, -185, 0, 38)
	statsLabel.BackgroundTransparency = 1
	statsLabel.Font = Theme.Fonts.Body
	statsLabel.TextColor3 = Theme.Colors.TextSecondary
	statsLabel.TextSize = 13
	statsLabel.TextWrapped = true
	statsLabel.TextXAlignment = Enum.TextXAlignment.Left
	if vm.isMaxLevel then
		statsLabel.Text = string.format(
			"%s\nТекущий параметр: %d %s (Достигнут максимум)",
			vm.description,
			vm.currentValue,
			vm.valueUnit
		)
	else
		statsLabel.Text = string.format(
			"%s\nЭффект: %d → %d %s  |  Цена: %d Монет",
			vm.description,
			vm.currentValue,
			vm.nextValue,
			vm.valueUnit,
			vm.nextCost
		)
	end
	statsLabel.Parent = card

	-- Статусная строка обратной связи (нехватка средств / загрузка / успех / ошибка)
	local feedbackLabel = Instance.new("TextLabel")
	feedbackLabel.Name = "FeedbackLabel"
	feedbackLabel.Position = UDim2.new(0, 14, 0, 78)
	feedbackLabel.Size = UDim2.new(1, -185, 0, 28)
	feedbackLabel.BackgroundTransparency = 1
	feedbackLabel.Font = Theme.Fonts.Body
	feedbackLabel.TextSize = 12
	feedbackLabel.TextXAlignment = Enum.TextXAlignment.Left

	if vm.buttonState == "InsufficientFunds" then
		feedbackLabel.TextColor3 = Theme.Colors.Warning
		feedbackLabel.Text = string.format(
			"🔒 Недостаточно сданных монет в банке: нужно %d (не хватает ещё %d)",
			vm.nextCost,
			vm.shortageAmount
		)
	elseif vm.buttonState == "Loading" then
		feedbackLabel.TextColor3 = Theme.Colors.Warning
		feedbackLabel.Text = "⏳ Запрос отправлен на сервер..."
	elseif vm.buttonState == "Success" then
		feedbackLabel.TextColor3 = Theme.Colors.Success
		feedbackLabel.Text = vm.statusMessage
	elseif vm.buttonState == "Error" then
		feedbackLabel.TextColor3 = Theme.Colors.Error
		feedbackLabel.Text = "✗ " .. vm.statusMessage
	elseif vm.isMaxLevel then
		feedbackLabel.TextColor3 = Theme.Colors.Accent
		feedbackLabel.Text = "★ Максимальный уровень разблокирован!"
	else
		feedbackLabel.TextColor3 = Theme.Colors.Success
		feedbackLabel.Text = "✓ Доступно для покупки за сданный баланс"
	end
	feedbackLabel.Parent = card

	-- Кнопка покупки улучшения
	local actionBtn = Instance.new("TextButton")
	actionBtn.Name = "UpgradeButton"
	actionBtn.AnchorPoint = Vector2.new(1, 0)
	actionBtn.Position = UDim2.new(1, -14, 0, 16)
	actionBtn.Size = UDim2.new(0, 154, 0, 44)
	actionBtn.Font = Theme.Fonts.Heading
	actionBtn.TextColor3 = Theme.Colors.TextPrimary
	actionBtn.TextSize = 13
	actionBtn.Text = vm.buttonText
	actionBtn.AutoButtonColor = (vm.buttonState == "Available" or vm.buttonState == "Error")

	if vm.buttonState == "Available" then
		actionBtn.BackgroundColor3 = Theme.Colors.Success
	elseif vm.buttonState == "Loading" then
		actionBtn.BackgroundColor3 = Theme.Colors.Warning
	elseif vm.buttonState == "Success" then
		actionBtn.BackgroundColor3 = Theme.Colors.Primary
	elseif vm.buttonState == "Error" then
		actionBtn.BackgroundColor3 = Theme.Colors.Error
	elseif vm.buttonState == "InsufficientFunds" then
		actionBtn.BackgroundColor3 = Color3.fromRGB(78, 52, 60)
	else
		actionBtn.BackgroundColor3 = Theme.Colors.SurfaceLight
	end
	actionBtn.Parent = card

	local btnCorner = Instance.new("UICorner")
	btnCorner.CornerRadius = Theme.CornerRadius.Small
	btnCorner.Parent = actionBtn

	actionBtn.Activated:Connect(function()
		if vm.buttonState == "Error" and vm.canRetry then
			callbacks.OnRetryUpgrade(vm.trackId)
		else
			callbacks.OnRequestUpgrade(vm.trackId)
		end
	end)

	-- Кнопка повторного запроса (если произошла ошибка связи/отказа)
	if vm.buttonState == "Error" and vm.canRetry then
		local retryBtn = Instance.new("TextButton")
		retryBtn.Name = "RetryUpgradeButton"
		retryBtn.AnchorPoint = Vector2.new(1, 0)
		retryBtn.Position = UDim2.new(1, -14, 0, 66)
		retryBtn.Size = UDim2.new(0, 154, 0, 34)
		retryBtn.BackgroundColor3 = Theme.Colors.Primary
		retryBtn.Font = Theme.Fonts.Heading
		retryBtn.TextColor3 = Theme.Colors.TextPrimary
		retryBtn.TextSize = 12
		retryBtn.Text = "🔄 ПОВТОРИТЬ ЗАПРОС"
		retryBtn.Parent = card

		local retryCorner = Instance.new("UICorner")
		retryCorner.CornerRadius = Theme.CornerRadius.Small
		retryCorner.Parent = retryBtn

		retryBtn.Activated:Connect(function()
			callbacks.OnRetryUpgrade(vm.trackId)
		end)
	end
end

function UpgradesView.Render(
	contentFrame: ScrollingFrame,
	bagState: ExpeditionTypes.BagStateViewModel,
	bankedCoins: number,
	toolVm: ExpeditionTypes.UpgradeTrackViewModel,
	bagVm: ExpeditionTypes.UpgradeTrackViewModel,
	callbacks: UpgradesViewCallbacks
): ()
	for _, child in ipairs(contentFrame:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end

	-- 1. Верхняя информационная панель (Сданный баланс + состояние сумки)
	local header = Instance.new("Frame")
	header.Name = "UpgradesBalanceBanner"
	header.Size = UDim2.new(1, -8, 0, 56)
	header.BackgroundColor3 = Theme.Colors.Surface
	header.BorderSizePixel = 0
	header.LayoutOrder = 1
	header.Parent = contentFrame

	local headerCorner = Instance.new("UICorner")
	headerCorner.CornerRadius = Theme.CornerRadius.Small
	headerCorner.Parent = header

	local balanceText = Instance.new("TextLabel")
	balanceText.Name = "BankedBalanceLabel"
	balanceText.Position = UDim2.new(0, 12, 0, 6)
	balanceText.Size = UDim2.new(0.65, -12, 0, 22)
	balanceText.BackgroundTransparency = 1
	balanceText.Font = Theme.Fonts.Heading
	balanceText.TextColor3 = Theme.Colors.Coins
	balanceText.TextSize = 15
	balanceText.TextXAlignment = Enum.TextXAlignment.Left
	balanceText.Text = string.format("🏦 Сданный баланс: %d Монет", math.floor(bankedCoins))
	balanceText.Parent = header

	local bagHint = Instance.new("TextLabel")
	bagHint.Name = "BagHintLabel"
	bagHint.Position = UDim2.new(0, 12, 0, 28)
	bagHint.Size = UDim2.new(0.65, -12, 0, 20)
	bagHint.BackgroundTransparency = 1
	bagHint.Font = Theme.Fonts.Body
	bagHint.TextColor3 = if bagState.current > 0 then Theme.Colors.Warning else Theme.Colors.TextSecondary
	bagHint.TextSize = 12
	bagHint.TextXAlignment = Enum.TextXAlignment.Left
	bagHint.Text = if bagState.current > 0
		then string.format(
			"🎒 В сумке не сдано: %d / %d Монет (сдайте на станции, чтобы тратить!)",
			bagState.current,
			bagState.capacity
		)
		else string.format("🎒 Сумка: 0 / %d • Улучшения покупаются за сданный баланс", bagState.capacity)
	bagHint.Parent = header

	if bagState.current > 0 then
		local quickDepositBtn = Instance.new("TextButton")
		quickDepositBtn.Name = "QuickDepositButton"
		quickDepositBtn.AnchorPoint = Vector2.new(1, 0.5)
		quickDepositBtn.Position = UDim2.new(1, -12, 0.5, 0)
		quickDepositBtn.Size = UDim2.new(0, 148, 0, 36)
		quickDepositBtn.BackgroundColor3 = Theme.Colors.Accent
		quickDepositBtn.Font = Theme.Fonts.Heading
		quickDepositBtn.TextColor3 = Theme.Colors.Background
		quickDepositBtn.TextSize = 12
		quickDepositBtn.Text = string.format("🏦 СДАТЬ СУМКУ (+%d)", bagState.current)
		quickDepositBtn.Parent = header

		local qdCorner = Instance.new("UICorner")
		qdCorner.CornerRadius = Theme.CornerRadius.Small
		qdCorner.Parent = quickDepositBtn

		quickDepositBtn.Activated:Connect(function()
			callbacks.OnRequestDeposit()
		end)
	end

	-- 2. Карточка улучшения Инструмента (Tool)
	renderUpgradeCard(contentFrame, toolVm, 2, callbacks)

	-- 3. Карточка улучшения Сумки (Bag)
	renderUpgradeCard(contentFrame, bagVm, 3, callbacks)
end

return UpgradesView
