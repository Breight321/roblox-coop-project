--!strict
--[[
	@module SkillTreeView
	@owner Agent B (anarugod)
	@description Компактный экран дерева навыков с ветками Урона (Damage), Защиты (Defense) и Мобильности (Mobility),
	отображением доступных очков навыков (SkillTreeSummaryViewModel), стоимости узла, требований уровня/ветки
	и состояний (Loading / Success / Error / Locked / Insufficient Points).
]]

local Theme = require(script.Parent.Parent:WaitForChild("Theme"))
local CombatTypes = require(script.Parent.Parent.Parent:WaitForChild("Controllers"):WaitForChild("CombatController"):WaitForChild("Types"))

local SkillTreeView = {}

local activeBranchFilter: CombatTypes.SkillBranch? = nil

local BRANCH_TABS: { { id: CombatTypes.SkillBranch?, label: string } } = {
	{ id = nil, label = "Все ветки (9)" },
	{ id = "Damage", label = "⚔️ Урон" },
	{ id = "Defense", label = "🛡️ Защита" },
	{ id = "Mobility", label = "⚡ Мобильность" },
}

local BRANCH_LABELS: { [string]: string } = {
	Damage = "⚔️ Ветка Урона",
	Defense = "🛡️ Ветка Защиты",
	Mobility = "⚡ Ветка Мобильности",
}

function SkillTreeView.Render(
	contentFrame: ScrollingFrame,
	nodes: { CombatTypes.SkillNodeViewModel },
	skillSummary: CombatTypes.SkillTreeSummaryViewModel,
	onUnlockSkill: (skillId: string) -> ()
): ()
	for _, child in ipairs(contentFrame:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end

	local layoutOrder = 1

	-- Верхняя панель очков навыков
	local summaryBar = Instance.new("Frame")
	summaryBar.Name = "SkillPointsBanner"
	summaryBar.Size = UDim2.new(1, -8, 0, 38)
	summaryBar.BackgroundColor3 = Theme.Colors.Background
	summaryBar.BorderSizePixel = 0
	summaryBar.LayoutOrder = layoutOrder
	summaryBar.Parent = contentFrame
	layoutOrder += 1

	local sCorner = Instance.new("UICorner")
	sCorner.CornerRadius = Theme.CornerRadius.Small
	sCorner.Parent = summaryBar

	local sText = Instance.new("TextLabel")
	sText.Position = UDim2.new(0, 12, 0, 4)
	sText.Size = UDim2.new(1, -24, 1, -8)
	sText.BackgroundTransparency = 1
	sText.Font = Theme.Fonts.Heading
	sText.TextColor3 = Theme.Colors.Primary
	sText.TextSize = 14
	sText.TextXAlignment = Enum.TextXAlignment.Left
	sText.Text = string.format(
		"🌟 Доступно очков навыков: %d   |   Изучено узлов: %d/9   (Вложено очков: %d)",
		skillSummary.availablePoints,
		skillSummary.unlockedCount,
		skillSummary.spentPoints
	)
	sText.Parent = summaryBar

	-- Полоса выбора ветки
	local tabBar = Instance.new("Frame")
	tabBar.Name = "BranchTabBar"
	tabBar.Size = UDim2.new(1, -8, 0, 36)
	tabBar.BackgroundTransparency = 1
	tabBar.LayoutOrder = layoutOrder
	tabBar.Parent = contentFrame
	layoutOrder += 1

	local tabLayout = Instance.new("UIListLayout")
	tabLayout.FillDirection = Enum.FillDirection.Horizontal
	tabLayout.Padding = UDim.new(0, 6)
	tabLayout.SortOrder = Enum.SortOrder.LayoutOrder
	tabLayout.Parent = tabBar

	for idx, tab in ipairs(BRANCH_TABS) do
		local isSelected = activeBranchFilter == tab.id
		local btn = Instance.new("TextButton")
		btn.Name = "BranchTab_" .. tostring(tab.id or "All")
		btn.Size = UDim2.new(0.24, -4, 1, 0)
		btn.BackgroundColor3 = if isSelected then Theme.Colors.Primary else Theme.Colors.Surface
		btn.Font = Theme.Fonts.Heading
		btn.TextColor3 = Theme.Colors.TextPrimary
		btn.TextSize = 13
		btn.Text = tab.label
		btn.LayoutOrder = idx
		btn.Parent = tabBar

		local corner = Instance.new("UICorner")
		corner.CornerRadius = Theme.CornerRadius.Small
		corner.Parent = btn

		btn.Activated:Connect(function()
			activeBranchFilter = tab.id
			SkillTreeView.Render(contentFrame, nodes, skillSummary, onUnlockSkill)
		end)
	end

	for _, node in ipairs(nodes) do
		if activeBranchFilter == nil or activeBranchFilter == node.branch then
			local card = Instance.new("Frame")
			card.Name = "SkillNode_" .. node.id
			card.Size = UDim2.new(1, -8, 0, 88)
			card.BackgroundColor3 = Theme.Colors.Surface
			card.BorderSizePixel = 0
			card.LayoutOrder = layoutOrder
			card.Parent = contentFrame
			layoutOrder += 1

			local corner = Instance.new("UICorner")
			corner.CornerRadius = Theme.CornerRadius.Medium
			corner.Parent = card

			local stroke = Instance.new("UIStroke")
			stroke.Color = if node.isUnlocked
				then Theme.Colors.Success
				elseif node.status == "Error" then Theme.Colors.Danger
				elseif node.canUnlock then Theme.Colors.Primary
				else Theme.Colors.Border
			stroke.Thickness = if node.isUnlocked or node.canUnlock then 2 else 1
			stroke.Parent = card

			local title = Instance.new("TextLabel")
			title.Name = "Title"
			title.Position = UDim2.new(0, 12, 0, 6)
			title.Size = UDim2.new(1, -165, 0, 22)
			title.BackgroundTransparency = 1
			title.Font = Theme.Fonts.Heading
			title.TextColor3 = Theme.Colors.TextPrimary
			title.TextSize = 15
			title.TextXAlignment = Enum.TextXAlignment.Left
			title.Text = string.format(
				"%s  •  [Ранг %d | Ур. %d+]  •  %s",
				node.displayName,
				node.tier,
				node.requiredLevel,
				BRANCH_LABELS[node.branch] or node.branch
			)
			title.Parent = card

			local desc = Instance.new("TextLabel")
			desc.Name = "Description"
			desc.Position = UDim2.new(0, 12, 0, 30)
			desc.Size = UDim2.new(1, -165, 0, 20)
			desc.BackgroundTransparency = 1
			desc.Font = Theme.Fonts.Body
			desc.TextColor3 = Theme.Colors.TextSecondary
			desc.TextSize = 13
			desc.TextXAlignment = Enum.TextXAlignment.Left
			desc.Text = string.format("%s (%s)", node.description, node.bonusText)
			desc.Parent = card

			local stateLabel = Instance.new("TextLabel")
			stateLabel.Name = "StatusText"
			stateLabel.Position = UDim2.new(0, 12, 0, 54)
			stateLabel.Size = UDim2.new(1, -165, 0, 22)
			stateLabel.BackgroundTransparency = 1
			stateLabel.Font = Theme.Fonts.Heading
			stateLabel.TextSize = 12
			stateLabel.TextXAlignment = Enum.TextXAlignment.Left

			if node.status == "Loading" then
				stateLabel.TextColor3 = Theme.Colors.Warning
				stateLabel.Text = node.statusMessage or "⏳ Отправка запроса серверу..."
			elseif node.status == "Error" and node.statusMessage then
				stateLabel.TextColor3 = Theme.Colors.Danger
				stateLabel.Text = node.statusMessage
			elseif node.isUnlocked then
				stateLabel.TextColor3 = Theme.Colors.Success
				stateLabel.Text = "✓ Навык изучен и активен"
			elseif not node.meetsPrereqs then
				stateLabel.TextColor3 = Theme.Colors.TextSecondary
				stateLabel.Text = "🔒 Требуется предыдущий навык ветки"
			elseif not node.meetsLevel then
				stateLabel.TextColor3 = Theme.Colors.Warning
				stateLabel.Text = string.format("🔒 Требуется %d уровень персонажа", node.requiredLevel)
			elseif not node.hasEnoughPoints then
				stateLabel.TextColor3 = Theme.Colors.Warning
				stateLabel.Text = string.format("Стоимость: %d очк. (недостаточно очков навыков)", node.costPoints)
			else
				stateLabel.TextColor3 = Theme.Colors.Primary
				stateLabel.Text = string.format("Доступно к изучению • Стоимость: %d очк.", node.costPoints)
			end
			stateLabel.Parent = card

			local actionBtn = Instance.new("TextButton")
			actionBtn.Name = "UnlockSkillButton"
			actionBtn.AnchorPoint = Vector2.new(1, 0.5)
			actionBtn.Position = UDim2.new(1, -12, 0.5, 0)
			actionBtn.Size = UDim2.new(0, 140, 0, 42)
			actionBtn.Font = Theme.Fonts.Heading
			actionBtn.TextColor3 = Theme.Colors.TextPrimary
			actionBtn.TextSize = 13

			if node.isUnlocked then
				actionBtn.BackgroundColor3 = Theme.Colors.Success
				actionBtn.Text = "✓ ИЗУЧЕНО"
			elseif node.status == "Loading" then
				actionBtn.BackgroundColor3 = Theme.Colors.Warning
				actionBtn.Text = "⏳ ЗАГРУЗКА..."
			elseif not node.meetsPrereqs or not node.meetsLevel then
				actionBtn.BackgroundColor3 = Theme.Colors.Border
				actionBtn.Text = "🔒 ЗАКРЫТО"
			elseif not node.hasEnoughPoints then
				actionBtn.BackgroundColor3 = Theme.Colors.Border
				actionBtn.Text = string.format("НУЖНО %d ОЧК.", node.costPoints)
			else
				actionBtn.BackgroundColor3 = Theme.Colors.Primary
				actionBtn.Text = string.format("ИЗУЧИТЬ (%d ОЧК.)", node.costPoints)
			end
			actionBtn.Parent = card

			local bCorner = Instance.new("UICorner")
			bCorner.CornerRadius = Theme.CornerRadius.Small
			bCorner.Parent = actionBtn

			actionBtn.Activated:Connect(function()
				if not node.isUnlocked and node.status ~= "Loading" then
					onUnlockSkill(node.id)
				end
			end)
		end
	end
end

return SkillTreeView
