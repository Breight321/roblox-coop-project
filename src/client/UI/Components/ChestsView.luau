--!strict
--[[
	@module ChestsView
	@owner Agent B (anarugod)
	@description Экран сундуков локаций (CombatConfig.Chests): отображение прогресса убийств мобов (killsProgress / requiredKills),
	перезарядки, таблиц добычи деталей тела, отправка RequestOpenChest(chestId) и показ выигрыша
	строго после серверного подтверждения ChestResult.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ZonesConfig = require(Shared:WaitForChild("Config"):WaitForChild("ZonesConfig"))
local Theme = require(script.Parent.Parent:WaitForChild("Theme"))
local CombatTypes = require(script.Parent.Parent.Parent:WaitForChild("Controllers"):WaitForChild("CombatController"):WaitForChild("Types"))

local ChestsView = {}

function ChestsView.Render(
	contentFrame: ScrollingFrame,
	chests: { CombatTypes.ChestDefViewModel },
	coinsBalance: number,
	unlockedZones: { [string]: boolean }?,
	onOpenChest: (chestId: string) -> ()
): ()
	for _, child in ipairs(contentFrame:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end

	local infoBanner = Instance.new("Frame")
	infoBanner.Name = "ChestsInfoBanner"
	infoBanner.Size = UDim2.new(1, -8, 0, 44)
	infoBanner.BackgroundColor3 = Theme.Colors.Background
	infoBanner.BorderSizePixel = 0
	infoBanner.LayoutOrder = 1
	infoBanner.Parent = contentFrame

	local bCorner = Instance.new("UICorner")
	bCorner.CornerRadius = Theme.CornerRadius.Small
	bCorner.Parent = infoBanner

	local bText = Instance.new("TextLabel")
	bText.Position = UDim2.new(0, 12, 0, 6)
	bText.Size = UDim2.new(1, -24, 1, -12)
	bText.BackgroundTransparency = 1
	bText.Font = Theme.Fonts.Body
	bText.TextColor3 = Theme.Colors.TextSecondary
	bText.TextSize = 13
	bText.TextXAlignment = Enum.TextXAlignment.Left
	bText.Text = string.format(
		"🧰 Сундуки локаций открываются за победы над мобами в мире (подойдите к сундуку и нажмите E или кнопку ниже). Баланс: %d монет.",
		coinsBalance
	)
	bText.Parent = infoBanner

	for idx, chest in ipairs(chests) do
		local zoneDef = ZonesConfig[chest.zoneId]
		local zoneName = if zoneDef then zoneDef.displayName else chest.zoneId
		local isZoneOpen = if unlockedZones
			then (unlockedZones[chest.zoneId] == true or (zoneDef and zoneDef.costAmount == 0))
			else true
		local isLoading = chest.status == "Loading"

		local card = Instance.new("Frame")
		card.Name = "ChestCard_" .. chest.id
		card.Size = UDim2.new(1, -8, 0, 108)
		card.BackgroundColor3 = Theme.Colors.Surface
		card.BorderSizePixel = 0
		card.LayoutOrder = idx + 1
		card.Parent = contentFrame

		local corner = Instance.new("UICorner")
		corner.CornerRadius = Theme.CornerRadius.Medium
		corner.Parent = card

		local stroke = Instance.new("UIStroke")
		stroke.Color = if chest.status == "Success"
			then Theme.Colors.Success
			elseif chest.status == "Error" then Theme.Colors.Danger
			elseif chest.isReady then Theme.Colors.Primary
			else Theme.Colors.Border
		stroke.Thickness = if chest.status == "Success" or chest.isReady then 2 else 1
		stroke.Parent = card

		local title = Instance.new("TextLabel")
		title.Name = "Title"
		title.Position = UDim2.new(0, 12, 0, 8)
		title.Size = UDim2.new(1, -165, 0, 22)
		title.BackgroundTransparency = 1
		title.Font = Theme.Fonts.Heading
		title.TextColor3 = Theme.Colors.TextPrimary
		title.TextSize = 15
		title.TextXAlignment = Enum.TextXAlignment.Left
		title.Text = string.format(
			"🧰 %s  •  [%s]  •  Ур. %d+",
			chest.displayName,
			zoneName,
			chest.minPlayerLevel
		)
		title.Parent = card

		local desc = Instance.new("TextLabel")
		desc.Name = "Description"
		desc.Position = UDim2.new(0, 12, 0, 32)
		desc.Size = UDim2.new(1, -165, 0, 20)
		desc.BackgroundTransparency = 1
		desc.Font = Theme.Fonts.Body
		desc.TextColor3 = Theme.Colors.TextSecondary
		desc.TextSize = 13
		desc.TextXAlignment = Enum.TextXAlignment.Left
		desc.Text = chest.description
		desc.Parent = card

		local odds = Instance.new("TextLabel")
		odds.Name = "DropPreview"
		odds.Position = UDim2.new(0, 12, 0, 54)
		odds.Size = UDim2.new(1, -165, 0, 18)
		odds.BackgroundTransparency = 1
		odds.Font = Theme.Fonts.Body
		odds.TextColor3 = Theme.Colors.Primary
		odds.TextSize = 12
		odds.TextTruncate = Enum.TextTruncate.AtEnd
		odds.TextXAlignment = Enum.TextXAlignment.Left
		odds.Text = chest.dropPreviewText
		odds.Parent = card

		-- Строка результата (награда показывается ТОЛЬКО после подтверждения сервером)
		local resultLabel = Instance.new("TextLabel")
		resultLabel.Name = "ResultStatus"
		resultLabel.Position = UDim2.new(0, 12, 0, 76)
		resultLabel.Size = UDim2.new(1, -165, 0, 22)
		resultLabel.BackgroundTransparency = 1
		resultLabel.Font = Theme.Fonts.Heading
		resultLabel.TextSize = 13
		resultLabel.TextXAlignment = Enum.TextXAlignment.Left
		if chest.status == "Loading" then
			resultLabel.TextColor3 = Theme.Colors.Warning
			resultLabel.Text = chest.statusMessage or "⏳ Открываем сундук (ожидание ответа сервера)..."
		elseif chest.status == "Success" and chest.lastRewardText then
			resultLabel.TextColor3 = Theme.Colors.Success
			resultLabel.Text = "✨ Выигрыш: " .. chest.lastRewardText
		elseif chest.status == "Error" then
			resultLabel.TextColor3 = Theme.Colors.Danger
			resultLabel.Text = chest.statusMessage or "❌ Ошибка открытия сундука"
		else
			resultLabel.TextColor3 = if chest.isReady then Theme.Colors.Success else Theme.Colors.TextSecondary
			resultLabel.Text = chest.statusMessage
				or string.format("Побеждено мобов: %d/%d", chest.killsProgress, chest.requiredKills)
		end
		resultLabel.Parent = card

		local openBtn = Instance.new("TextButton")
		openBtn.Name = "OpenChestButton"
		openBtn.AnchorPoint = Vector2.new(1, 0.5)
		openBtn.Position = UDim2.new(1, -12, 0.5, 0)
		openBtn.Size = UDim2.new(0, 140, 0, 44)
		openBtn.Font = Theme.Fonts.Heading
		openBtn.TextColor3 = Theme.Colors.TextPrimary
		openBtn.TextSize = 13

		if isLoading then
			openBtn.BackgroundColor3 = Theme.Colors.Warning
			openBtn.Text = "⏳ ОТКРЫТИЕ..."
		elseif not isZoneOpen then
			openBtn.BackgroundColor3 = Theme.Colors.Border
			openBtn.Text = "🔒 ЗОНА ЗАКРЫТА"
		elseif chest.isReady then
			openBtn.BackgroundColor3 = Theme.Colors.Primary
			openBtn.Text = "ОТКРЫТЬ СУНДУК"
		else
			openBtn.BackgroundColor3 = Theme.Colors.Surface
			openBtn.Text = string.format("МОБЫ: %d/%d", chest.killsProgress, chest.requiredKills)
		end
		openBtn.Parent = card

		local btnCorner = Instance.new("UICorner")
		btnCorner.CornerRadius = Theme.CornerRadius.Small
		btnCorner.Parent = openBtn

		openBtn.Activated:Connect(function()
			if not isLoading then
				onOpenChest(chest.id)
			end
		end)
	end
end

return ChestsView
