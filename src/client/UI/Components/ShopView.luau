--!strict
--[[
	@module ShopView
	@owner Agent 2 (anarugod)
	@description Отрисовка каталога товаров магазина (ShopConfig + ItemsConfig) внутри окна Shop.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ShopConfig = require(Shared:WaitForChild("Config"):WaitForChild("ShopConfig"))
local ItemsConfig = require(Shared:WaitForChild("Config"):WaitForChild("ItemsConfig"))
local Theme = require(script.Parent.Parent:WaitForChild("Theme"))

local ShopView = {}

function ShopView.Populate(contentFrame: ScrollingFrame, onPurchaseClicked: (shopItemId: string) -> ()): ()
	for _, child in ipairs(contentFrame:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end

	local sortedIds: { string } = {}
	for shopId in pairs(ShopConfig) do
		table.insert(sortedIds, shopId)
	end
	table.sort(sortedIds)

	for idx, shopId in ipairs(sortedIds) do
		local shopDef = ShopConfig[shopId]
		local itemDef = ItemsConfig[shopDef.itemId]
		local displayName = if itemDef then itemDef.displayName else shopDef.itemId
		local description = if itemDef then itemDef.description else ""
		local rarityColor = if itemDef then (Theme.RarityColors[itemDef.rarity] or Theme.Colors.Primary) else Theme.Colors.Primary

		local card = Instance.new("Frame")
		card.Name = "ShopCard_" .. shopId
		card.Size = UDim2.new(1, -8, 0, 74)
		card.BackgroundColor3 = Theme.Colors.Surface
		card.BorderSizePixel = 0
		card.LayoutOrder = idx
		card.Parent = contentFrame

		local corner = Instance.new("UICorner")
		corner.CornerRadius = Theme.CornerRadius.Medium
		corner.Parent = card

		local stroke = Instance.new("UIStroke")
		stroke.Color = rarityColor
		stroke.Thickness = 1.5
		stroke.Parent = card

		local title = Instance.new("TextLabel")
		title.Name = "Title"
		title.Position = UDim2.new(0, 12, 0, 8)
		title.Size = UDim2.new(1, -150, 0, 24)
		title.BackgroundTransparency = 1
		title.Font = Theme.Fonts.Heading
		title.TextColor3 = Theme.Colors.TextPrimary
		title.TextSize = 16
		title.TextXAlignment = Enum.TextXAlignment.Left
		title.Text = displayName
		title.Parent = card

		local desc = Instance.new("TextLabel")
		desc.Name = "Description"
		desc.Position = UDim2.new(0, 12, 0, 34)
		desc.Size = UDim2.new(1, -150, 0, 32)
		desc.BackgroundTransparency = 1
		desc.Font = Theme.Fonts.Body
		desc.TextColor3 = Theme.Colors.TextSecondary
		desc.TextSize = 13
		desc.TextWrapped = true
		desc.TextXAlignment = Enum.TextXAlignment.Left
		desc.Text = description
		desc.Parent = card

		local buyBtn = Instance.new("TextButton")
		buyBtn.Name = "BuyButton"
		buyBtn.AnchorPoint = Vector2.new(1, 0.5)
		buyBtn.Position = UDim2.new(1, -12, 0.5, 0)
		buyBtn.Size = UDim2.new(0, 120, 0, 42)
		buyBtn.BackgroundColor3 = Theme.Colors.Success
		buyBtn.Font = Theme.Fonts.Heading
		buyBtn.TextColor3 = Theme.Colors.TextPrimary
		buyBtn.TextSize = 14
		buyBtn.Text = string.format("%d %s", shopDef.price, shopDef.currencyId)
		buyBtn.Parent = card

		local btnCorner = Instance.new("UICorner")
		btnCorner.CornerRadius = Theme.CornerRadius.Small
		btnCorner.Parent = buyBtn

		buyBtn.Activated:Connect(function()
			onPurchaseClicked(shopId)
		end)
	end
end

return ShopView
