--!strict
--[[
	@module RebirthView
	@owner Agent 2 (anarugod)
	@description Отрисовка окна перерождений (Rebirth): расчёт стоимости, текущего бонуса множителя и кнопка Rebirth.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("Config"):WaitForChild("GameConfig"))
local Theme = require(script.Parent.Parent:WaitForChild("Theme"))

local RebirthView = {}

function RebirthView.Render(
	contentFrame: ScrollingFrame,
	currentRebirths: number,
	currentCoins: number,
	onRebirthClicked: () -> ()
): ()
	for _, child in ipairs(contentFrame:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end

	local cost = math.floor(
		GameConfig.Progression.BaseRebirthCostCoins * (GameConfig.Progression.RebirthCostMultiplier ^ currentRebirths)
	)
	local currentMult = 1.0 + (currentRebirths * GameConfig.Progression.RebirthBonusMultiplierPerRebirth)
	local nextMult = 1.0 + ((currentRebirths + 1) * GameConfig.Progression.RebirthBonusMultiplierPerRebirth)
	local canAfford = currentCoins >= cost

	local infoCard = Instance.new("Frame")
	infoCard.Name = "RebirthInfoCard"
	infoCard.Size = UDim2.new(1, -8, 0, 180)
	infoCard.BackgroundColor3 = Theme.Colors.Surface
	infoCard.BorderSizePixel = 0
	infoCard.Parent = contentFrame

	local corner = Instance.new("UICorner")
	corner.CornerRadius = Theme.CornerRadius.Medium
	corner.Parent = infoCard

	local infoLabel = Instance.new("TextLabel")
	infoLabel.Name = "Summary"
	infoLabel.Position = UDim2.new(0, 16, 0, 16)
	infoLabel.Size = UDim2.new(1, -32, 0, 96)
	infoLabel.BackgroundTransparency = 1
	infoLabel.Font = Theme.Fonts.Body
	infoLabel.TextColor3 = Theme.Colors.TextPrimary
	infoLabel.TextSize = 16
	infoLabel.TextWrapped = true
	infoLabel.TextXAlignment = Enum.TextXAlignment.Left
	infoLabel.Text = string.format(
		"Текущие ребирты: %d\nМножитель монет: x%.2f -> x%.2f\nНаграда: +%d Gems\nСтоимость: %d Coins",
		currentRebirths,
		currentMult,
		nextMult,
		GameConfig.Progression.RebirthGemsReward,
		cost
	)
	infoLabel.Parent = infoCard

	local rebirthBtn = Instance.new("TextButton")
	rebirthBtn.Name = "ConfirmRebirthButton"
	rebirthBtn.AnchorPoint = Vector2.new(0.5, 1)
	rebirthBtn.Position = UDim2.new(0.5, 0, 1, -16)
	rebirthBtn.Size = UDim2.new(0, 220, 0, 46)
	rebirthBtn.BackgroundColor3 = if canAfford then Theme.Colors.Rebirth else Theme.Colors.SurfaceLight
	rebirthBtn.Font = Theme.Fonts.Heading
	rebirthBtn.TextColor3 = Theme.Colors.TextPrimary
	rebirthBtn.TextSize = 16
	rebirthBtn.Text = if canAfford then "🔥 REBIRTH NOW" else string.format("NEED %d COINS", cost)
	rebirthBtn.Parent = infoCard

	local btnCorner = Instance.new("UICorner")
	btnCorner.CornerRadius = Theme.CornerRadius.Medium
	btnCorner.Parent = rebirthBtn

	rebirthBtn.Activated:Connect(function()
		onRebirthClicked()
	end)
end

return RebirthView
