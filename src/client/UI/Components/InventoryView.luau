--!strict
--[[
	@module InventoryView
	@owner Agent B (anarugod)
	@description Интерфейс инвентаря и сборки деталей тела (Голова / Head, Руки / Arms, Корпус / Torso, Ноги / Legs):
	просмотр текущей сборки и бонуса комплекта 4/4 (BodySetsConfig), сводка характеристик из StatsUpdated,
	индикация изменений после ответа сервера, фильтрация по слотам, сравнение бонусов с надетой деталью и экипировка.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Core"):WaitForChild("Types"))
local ItemsConfig = require(Shared:WaitForChild("Config"):WaitForChild("ItemsConfig"))
local Theme = require(script.Parent.Parent:WaitForChild("Theme"))

local CombatTypes = require(script.Parent.Parent.Parent:WaitForChild("Controllers"):WaitForChild("CombatController"):WaitForChild("Types"))
local CombatConfig = require(script.Parent.Parent.Parent:WaitForChild("Controllers"):WaitForChild("CombatController"):WaitForChild("Config"))

local InventoryView = {}

local activeSlotFilter: string = "All"

local SLOT_TABS = {
	{ id = "All", label = "Все детали" },
	{ id = "Head", label = "Голова" },
	{ id = "Arms", label = "Руки" },
	{ id = "Torso", label = "Корпус" },
	{ id = "Legs", label = "Ноги" },
}

local function formatDelta(label: string, delta: number): string
	if delta > 0 then
		return string.format("%s +%d ▲", label, delta)
	elseif delta < 0 then
		return string.format("%s %d ▼", label, delta)
	end
	return string.format("%s =0", label)
end

function InventoryView.Render(
	contentFrame: ScrollingFrame,
	inventory: { [string]: Types.InventoryItem },
	onEquipToggle: (itemUid: string, equip: boolean) -> (),
	assemblySummary: CombatTypes.AssemblyStatsSummary?,
	bodyPartsList: { CombatTypes.BodyPartViewModel }?
): ()
	for _, child in ipairs(contentFrame:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end

	local layoutOrder = 1

	-- 1. Карточка текущей сборки и итоговых характеристик персонажа
	if assemblySummary then
		local hasSetBanner = assemblySummary.activeSetName ~= nil
		local hasDeltaBanner = assemblySummary.lastDeltaSummary ~= nil
		local cardHeight = 114 + (hasSetBanner and 22 or 0) + (hasDeltaBanner and 22 or 0)

		local summaryCard = Instance.new("Frame")
		summaryCard.Name = "AssemblySummaryCard"
		summaryCard.Size = UDim2.new(1, -8, 0, cardHeight)
		summaryCard.BackgroundColor3 = Theme.Colors.Background
		summaryCard.BorderSizePixel = 0
		summaryCard.LayoutOrder = layoutOrder
		summaryCard.Parent = contentFrame
		layoutOrder += 1

		local sCorner = Instance.new("UICorner")
		sCorner.CornerRadius = Theme.CornerRadius.Medium
		sCorner.Parent = summaryCard

		local sStroke = Instance.new("UIStroke")
		sStroke.Color = Theme.Colors.Primary
		sStroke.Thickness = 1.5
		sStroke.Parent = summaryCard

		local headerLabel = Instance.new("TextLabel")
		headerLabel.Name = "AssemblyHeader"
		headerLabel.Position = UDim2.new(0, 12, 0, 8)
		headerLabel.Size = UDim2.new(1, -24, 0, 22)
		headerLabel.BackgroundTransparency = 1
		headerLabel.Font = Theme.Fonts.Heading
		headerLabel.TextColor3 = Theme.Colors.TextPrimary
		headerLabel.TextSize = 14
		headerLabel.TextXAlignment = Enum.TextXAlignment.Left
		headerLabel.Text = string.format(
			"СБОРКА (%d/4)  |  ⚔️ АТК: %d   🛡️ Броня: %d (-%d%%)   ❤️ HP: %d   ⚡ Скор: %d   🎯 Крит: %d%%",
			assemblySummary.equippedCount,
			assemblySummary.attackPower,
			assemblySummary.defense,
			assemblySummary.damageReductionPct,
			assemblySummary.maxHealth,
			assemblySummary.moveSpeed,
			assemblySummary.critChancePct
		)
		headerLabel.Parent = summaryCard

		-- Отображение 4 слотов тела (Head, Arms, Torso, Legs)
		local slotsRow = Instance.new("Frame")
		slotsRow.Name = "EquippedSlotsRow"
		slotsRow.Position = UDim2.new(0, 12, 0, 34)
		slotsRow.Size = UDim2.new(1, -24, 0, 68)
		slotsRow.BackgroundTransparency = 1
		slotsRow.Parent = summaryCard

		local slotsGrid = Instance.new("UIGridLayout")
		slotsGrid.CellSize = UDim2.new(0.24, 0, 0, 64)
		slotsGrid.CellPadding = UDim2.new(0.012, 0, 0, 4)
		slotsGrid.SortOrder = Enum.SortOrder.LayoutOrder
		slotsGrid.Parent = slotsRow

		for slotIdx, slotKey in ipairs(CombatConfig.BodyPartSlotsOrder) do
			local equippedPart = assemblySummary.equippedBySlot[slotKey]
			local slotLabelRu = (CombatConfig.SlotLabels :: any)[slotKey] or slotKey

			local slotBox = Instance.new("Frame")
			slotBox.Name = "Slot_" .. slotKey
			slotBox.BackgroundColor3 = Theme.Colors.Surface
			slotBox.BorderSizePixel = 0
			slotBox.LayoutOrder = slotIdx
			slotBox.Parent = slotsRow

			local boxCorner = Instance.new("UICorner")
			boxCorner.CornerRadius = Theme.CornerRadius.Small
			boxCorner.Parent = slotBox

			local boxStroke = Instance.new("UIStroke")
			boxStroke.Color = if equippedPart
				then (Theme.RarityColors[equippedPart.rarity] or Theme.Colors.Success)
				else Theme.Colors.Border
			boxStroke.Thickness = if equippedPart then 1.5 else 1
			boxStroke.Parent = slotBox

			local slotTitle = Instance.new("TextLabel")
			slotTitle.Position = UDim2.new(0, 8, 0, 4)
			slotTitle.Size = UDim2.new(1, -16, 0, 18)
			slotTitle.BackgroundTransparency = 1
			slotTitle.Font = Theme.Fonts.Heading
			slotTitle.TextColor3 = Theme.Colors.TextSecondary
			slotTitle.TextSize = 11
			slotTitle.TextXAlignment = Enum.TextXAlignment.Left
			slotTitle.Text = slotLabelRu
			slotTitle.Parent = slotBox

			local partName = Instance.new("TextLabel")
			partName.Position = UDim2.new(0, 8, 0, 22)
			partName.Size = UDim2.new(1, -16, 0, 20)
			partName.BackgroundTransparency = 1
			partName.Font = Theme.Fonts.Heading
			partName.TextColor3 = if equippedPart then Theme.Colors.TextPrimary else Theme.Colors.TextSecondary
			partName.TextSize = 13
			partName.TextTruncate = Enum.TextTruncate.AtEnd
			partName.TextXAlignment = Enum.TextXAlignment.Left
			partName.Text = if equippedPart then equippedPart.displayName else "Пустой слот"
			partName.Parent = slotBox

			local partStats = Instance.new("TextLabel")
			partStats.Position = UDim2.new(0, 8, 0, 42)
			partStats.Size = UDim2.new(1, -16, 0, 16)
			partStats.BackgroundTransparency = 1
			partStats.Font = Theme.Fonts.Body
			partStats.TextColor3 = Theme.Colors.Success
			partStats.TextSize = 11
			partStats.TextXAlignment = Enum.TextXAlignment.Left
			partStats.Text = if equippedPart
				then string.format(
					"+%d АТК | +%d Защ | +%d HP",
					equippedPart.bonuses.attackPower,
					equippedPart.bonuses.defense,
					equippedPart.bonuses.maxHealth
				)
				else "Бонусы: нет"
			partStats.Parent = slotBox
		end

		local nextBannerY = 106
		if assemblySummary.activeSetName then
			local setBanner = Instance.new("TextLabel")
			setBanner.Name = "ActiveSetBanner"
			setBanner.Position = UDim2.new(0, 12, 0, nextBannerY)
			setBanner.Size = UDim2.new(1, -24, 0, 20)
			setBanner.BackgroundTransparency = 1
			setBanner.Font = Theme.Fonts.Heading
			setBanner.TextColor3 = Theme.Colors.Primary
			setBanner.TextSize = 12
			setBanner.TextXAlignment = Enum.TextXAlignment.Left
			setBanner.Text = string.format(
				"★ Бонус комплекта 4/4 [%s]: %s",
				assemblySummary.activeSetName,
				assemblySummary.activeSetDescription or "Активен"
			)
			setBanner.Parent = summaryCard
			nextBannerY += 22
		end

		if assemblySummary.lastDeltaSummary then
			local deltaBanner = Instance.new("TextLabel")
			deltaBanner.Name = "AssemblyDeltaBanner"
			deltaBanner.Position = UDim2.new(0, 12, 0, nextBannerY)
			deltaBanner.Size = UDim2.new(1, -24, 0, 20)
			deltaBanner.BackgroundTransparency = 1
			deltaBanner.Font = Theme.Fonts.Heading
			deltaBanner.TextColor3 = Theme.Colors.Success
			deltaBanner.TextSize = 12
			deltaBanner.TextXAlignment = Enum.TextXAlignment.Left
			deltaBanner.Text = "✨ " .. assemblySummary.lastDeltaSummary
			deltaBanner.Parent = summaryCard
		end
	end

	-- 2. Вкладки фильтрации по частям тела (Все, Голова, Руки, Корпус, Ноги)
	local filterBar = Instance.new("Frame")
	filterBar.Name = "SlotFilterBar"
	filterBar.Size = UDim2.new(1, -8, 0, 36)
	filterBar.BackgroundTransparency = 1
	filterBar.LayoutOrder = layoutOrder
	filterBar.Parent = contentFrame
	layoutOrder += 1

	local filterLayout = Instance.new("UIListLayout")
	filterLayout.FillDirection = Enum.FillDirection.Horizontal
	filterLayout.Padding = UDim.new(0, 6)
	filterLayout.SortOrder = Enum.SortOrder.LayoutOrder
	filterLayout.Parent = filterBar

	for tabIdx, tab in ipairs(SLOT_TABS) do
		local isSelected = activeSlotFilter == tab.id
		local tabBtn = Instance.new("TextButton")
		tabBtn.Name = "Tab_" .. tab.id
		tabBtn.Size = UDim2.new(0.19, -4, 1, 0)
		tabBtn.BackgroundColor3 = if isSelected then Theme.Colors.Primary else Theme.Colors.Surface
		tabBtn.Font = Theme.Fonts.Heading
		tabBtn.TextColor3 = Theme.Colors.TextPrimary
		tabBtn.TextSize = 13
		tabBtn.Text = tab.label
		tabBtn.LayoutOrder = tabIdx
		tabBtn.Parent = filterBar

		local tCorner = Instance.new("UICorner")
		tCorner.CornerRadius = Theme.CornerRadius.Small
		tCorner.Parent = tabBtn

		tabBtn.Activated:Connect(function()
			activeSlotFilter = tab.id
			InventoryView.Render(contentFrame, inventory, onEquipToggle, assemblySummary, bodyPartsList)
		end)
	end

	-- 3. Список карточек деталей тела со сравнением бонусов
	if bodyPartsList and #bodyPartsList > 0 then
		local shownCount = 0
		for _, part in ipairs(bodyPartsList) do
			if activeSlotFilter == "All" or activeSlotFilter == part.slot then
				shownCount += 1
				local rarityColor = Theme.RarityColors[part.rarity] or Theme.Colors.Primary
				local slotRu = (CombatConfig.SlotLabels :: any)[part.slot] or part.slot

				local card = Instance.new("Frame")
				card.Name = "InvItem_" .. part.uid
				card.Size = UDim2.new(1, -8, 0, 84)
				card.BackgroundColor3 = Theme.Colors.Surface
				card.BorderSizePixel = 0
				card.LayoutOrder = layoutOrder
				card.Parent = contentFrame
				layoutOrder += 1

				local corner = Instance.new("UICorner")
				corner.CornerRadius = Theme.CornerRadius.Medium
				corner.Parent = card

				local stroke = Instance.new("UIStroke")
				stroke.Color = rarityColor
				stroke.Thickness = if part.equipped then 2.5 else 1
				stroke.Parent = card

				local title = Instance.new("TextLabel")
				title.Name = "Title"
				title.Position = UDim2.new(0, 12, 0, 6)
				title.Size = UDim2.new(1, -150, 0, 22)
				title.BackgroundTransparency = 1
				title.Font = Theme.Fonts.Heading
				title.TextColor3 = Theme.Colors.TextPrimary
				title.TextSize = 15
				title.TextXAlignment = Enum.TextXAlignment.Left
				title.Text = string.format(
					"%s  •  [%s]  •  %s (%s)",
					part.displayName,
					slotRu,
					part.rarity,
					part.bonuses.setName
				)
				title.Parent = card

				local sub = Instance.new("TextLabel")
				sub.Name = "Stats"
				sub.Position = UDim2.new(0, 12, 0, 30)
				sub.Size = UDim2.new(1, -150, 0, 20)
				sub.BackgroundTransparency = 1
				sub.Font = Theme.Fonts.Body
				sub.TextColor3 = Theme.Colors.TextSecondary
				sub.TextSize = 13
				sub.TextXAlignment = Enum.TextXAlignment.Left
				sub.Text = string.format(
					"Бонусы: ⚔️ +%d АТК  |  🛡️ +%d Броня  |  ❤️ +%d HP  |  ⚡ +%d Скор  |  🎯 +%d%% Крит",
					part.bonuses.attackPower,
					part.bonuses.defense,
					part.bonuses.maxHealth,
					part.bonuses.moveSpeed,
					math.floor(part.bonuses.critChance * 100 + 0.5)
				)
				sub.Parent = card

				local compareLabel = Instance.new("TextLabel")
				compareLabel.Name = "Comparison"
				compareLabel.Position = UDim2.new(0, 12, 0, 52)
				compareLabel.Size = UDim2.new(1, -150, 0, 20)
				compareLabel.BackgroundTransparency = 1
				compareLabel.Font = Theme.Fonts.Heading
				compareLabel.TextSize = 12
				compareLabel.TextXAlignment = Enum.TextXAlignment.Left
				if part.equipped then
					compareLabel.TextColor3 = Theme.Colors.Success
					compareLabel.Text = "✓ Экипировано в слот [" .. slotRu .. "]"
				else
					local netDiff = part.deltaAttackPower + part.deltaDefense + part.deltaMaxHealth + part.deltaMoveSpeed
					compareLabel.TextColor3 = if netDiff > 0
						then Theme.Colors.Success
						elseif netDiff < 0 then Theme.Colors.Warning
						else Theme.Colors.TextSecondary
					compareLabel.Text = string.format(
						"Сравнение со слотом: %s | %s | %s | %s",
						formatDelta("АТК", part.deltaAttackPower),
						formatDelta("Броня", part.deltaDefense),
						formatDelta("HP", part.deltaMaxHealth),
						formatDelta("Скор", part.deltaMoveSpeed)
					)
				end
				compareLabel.Parent = card

				local equipBtn = Instance.new("TextButton")
				equipBtn.Name = "EquipButton"
				equipBtn.AnchorPoint = Vector2.new(1, 0.5)
				equipBtn.Position = UDim2.new(1, -12, 0.5, 0)
				equipBtn.Size = UDim2.new(0, 124, 0, 42)
				equipBtn.BackgroundColor3 = if part.isPendingEquip
					then Theme.Colors.Surface
					elseif part.equipped then Theme.Colors.Warning
					else Theme.Colors.Primary
				equipBtn.Font = Theme.Fonts.Heading
				equipBtn.TextColor3 = Theme.Colors.TextPrimary
				equipBtn.TextSize = 13
				equipBtn.Text = if part.isPendingEquip
					then "⏳ СЕРВЕР..."
					elseif part.equipped then "СНЯТЬ"
					else "НАДЕТЬ"
				equipBtn.Parent = card

				local btnCorner = Instance.new("UICorner")
				btnCorner.CornerRadius = Theme.CornerRadius.Small
				btnCorner.Parent = equipBtn

				equipBtn.Activated:Connect(function()
					if not part.isPendingEquip then
						onEquipToggle(part.uid, not part.equipped)
					end
				end)
			end
		end

		if shownCount == 0 then
			local emptyLabel = Instance.new("TextLabel")
			emptyLabel.Name = "EmptySlotNotice"
			emptyLabel.Size = UDim2.new(1, -8, 0, 48)
			emptyLabel.BackgroundTransparency = 1
			emptyLabel.Font = Theme.Fonts.Body
			emptyLabel.TextColor3 = Theme.Colors.TextSecondary
			emptyLabel.TextSize = 14
			emptyLabel.Text = "В этом слоте пока нет деталей тела. Побеждайте мобов или открывайте сундуки локаций!"
			emptyLabel.LayoutOrder = layoutOrder
			emptyLabel.Parent = contentFrame
		end
	end

	-- 4. Также показываем обычные предметы (инструменты и питомцы), если выбран фильтр "All"
	if activeSlotFilter == "All" then
		local miscList: { Types.InventoryItem } = {}
		for _, item in pairs(inventory) do
			if item.category == "Tool" or item.category == "Pet" then
				table.insert(miscList, item)
			end
		end
		table.sort(miscList, function(a, b)
			if a.equipped ~= b.equipped then
				return a.equipped
			end
			return a.uid < b.uid
		end)

		for _, item in ipairs(miscList) do
			local def = ItemsConfig[item.id]
			local displayName = if def then def.displayName else item.id
			local rarityColor = if def then (Theme.RarityColors[def.rarity] or Theme.Colors.Primary) else Theme.Colors.Primary

			local card = Instance.new("Frame")
			card.Name = "InvItem_" .. item.uid
			card.Size = UDim2.new(1, -8, 0, 64)
			card.BackgroundColor3 = Theme.Colors.Surface
			card.BorderSizePixel = 0
			card.LayoutOrder = layoutOrder
			card.Parent = contentFrame
			layoutOrder += 1

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
			title.TextSize = 15
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
			equipBtn.Size = UDim2.new(0, 124, 0, 40)
			equipBtn.BackgroundColor3 = if item.equipped then Theme.Colors.Warning else Theme.Colors.Primary
			equipBtn.Font = Theme.Fonts.Heading
			equipBtn.TextColor3 = Theme.Colors.TextPrimary
			equipBtn.TextSize = 13
			equipBtn.Text = if item.equipped then "СНЯТЬ" else "НАДЕТЬ"
			equipBtn.Parent = card

			local btnCorner = Instance.new("UICorner")
			btnCorner.CornerRadius = Theme.CornerRadius.Small
			btnCorner.Parent = equipBtn

			equipBtn.Activated:Connect(function()
				onEquipToggle(item.uid, not item.equipped)
			end)
		end
	end
end

return InventoryView
