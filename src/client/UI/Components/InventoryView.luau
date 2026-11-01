--!strict
--[[
	@module InventoryView
	@owner Agent 2 (anarugod)
	@description Отрисовка предметов инвентаря игрока и переключение экипировки (Equip / Unequip).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Core"):WaitForChild("Types"))
local ItemsConfig = require(Shared:WaitForChild("Config"):WaitForChild("ItemsConfig"))
local Theme = require(script.Parent.Parent:WaitForChild("Theme"))

local InventoryView = {}

function InventoryView.Render(
	contentFrame: ScrollingFrame,
	inventory: { [string]: Types.InventoryItem },
	onEquipToggle: (itemUid: string, equip: boolean) -> ()
): ()
	for _, child in ipairs(contentFrame:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end

	local itemsList: { Types.InventoryItem } = {}
	for _, item in pairs(inventory) do
		table.insert(itemsList, item)
	end
	table.sort(itemsList, function(a, b)
		if a.equipped ~= b.equipped then
			return a.equipped
		end
		return a.uid < b.uid
	end)

	for idx, item in ipairs(itemsList) do
		local def = ItemsConfig[item.itemId]
		local displayName = if def then def.displayName else item.itemId
		local rarityColor = if def then (Theme.RarityColors[def.rarity] or Theme.Colors.Primary) else Theme.Colors.Primary

		local card = Instance.new("Frame")
		card.Name = "InvItem_" .. item.uid
		card.Size = UDim2.new(1, -8, 0, 64)
		card.BackgroundColor3 = Theme.Colors.Surface
		card.BorderSizePixel = 0
		card.LayoutOrder = idx
		card.Parent = contentFrame

		local corner = Instance.new("UICorner")
		corner.CornerRadius = Theme.CornerRadius.Medium
		corner.Parent = card

		local stroke = Instance.new("UIStroke")
		stroke.Color = rarityColor
		stroke.Thickness = if item.equipped then 2.5 else 1
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
		title.Text = string.format("%s [%s]", displayName, item.category)
		title.Parent = card

		local sub = Instance.new("TextLabel")
		sub.Name = "Stats"
		sub.Position = UDim2.new(0, 12, 0, 32)
		sub.Size = UDim2.new(1, -150, 0, 24)
		sub.BackgroundTransparency = 1
		sub.Font = Theme.Fonts.Body
		sub.TextColor3 = Theme.Colors.TextSecondary
		sub.TextSize = 13
		sub.TextXAlignment = Enum.TextXAlignment.Left
		sub.Text = if def
			then string.format("Coin x%.2f | Power x%.2f", def.coinMultiplier, def.powerMultiplier)
			else "Lv. " .. tostring(item.level)
		sub.Parent = card

		local equipBtn = Instance.new("TextButton")
		equipBtn.Name = "EquipButton"
		equipBtn.AnchorPoint = Vector2.new(1, 0.5)
		equipBtn.Position = UDim2.new(1, -12, 0.5, 0)
		equipBtn.Size = UDim2.new(0, 115, 0, 40)
		equipBtn.BackgroundColor3 = if item.equipped then Theme.Colors.Warning else Theme.Colors.Primary
		equipBtn.Font = Theme.Fonts.Heading
		equipBtn.TextColor3 = Theme.Colors.TextPrimary
		equipBtn.TextSize = 14
		equipBtn.Text = if item.equipped then "UNEQUIP" else "EQUIP"
		equipBtn.Parent = card

		local btnCorner = Instance.new("UICorner")
		btnCorner.CornerRadius = Theme.CornerRadius.Small
		btnCorner.Parent = equipBtn

		equipBtn.Activated:Connect(function()
			onEquipToggle(item.uid, not item.equipped)
		end)
	end
end

return InventoryView
