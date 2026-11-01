--!strict
--[[
	@module ArenaView
	@owner Agent B (anarugod)
	@description Экран добровольной PvP-арены (CombatConfig.Arena):
	статус зоны (Безопасная зона vs В зоне PvP-арены), правила отдельного PvP-баланса,
	кнопки входа (RequestArenaEnter) и выхода (RequestArenaLeave), а также отображение результата боя (PvPCombatResult).
]]

local Theme = require(script.Parent.Parent:WaitForChild("Theme"))
local CombatTypes = require(script.Parent.Parent.Parent:WaitForChild("Controllers"):WaitForChild("CombatController"):WaitForChild("Types"))

local ArenaView = {}

function ArenaView.Render(
	contentFrame: ScrollingFrame,
	arenaState: CombatTypes.ArenaStateViewModel,
	assemblySummary: CombatTypes.AssemblyStatsSummary,
	onEnterArena: () -> (),
	onLeaveArena: () -> ()
): ()
	for _, child in ipairs(contentFrame:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end

	local inPvp = not arenaState.isSafeZone
	local isTransitioning = arenaState.zoneState == "Entering" or arenaState.zoneState == "Leaving"

	-- 1. Баннер статуса зоны (Безопасная PvE зона vs PvP Арена)
	local statusCard = Instance.new("Frame")
	statusCard.Name = "ArenaZoneStatusCard"
	statusCard.Size = UDim2.new(1, -8, 0, 126)
	statusCard.BackgroundColor3 = Theme.Colors.Surface
	statusCard.BorderSizePixel = 0
	statusCard.LayoutOrder = 1
	statusCard.Parent = contentFrame

	local sCorner = Instance.new("UICorner")
	sCorner.CornerRadius = Theme.CornerRadius.Medium
	sCorner.Parent = statusCard

	local sStroke = Instance.new("UIStroke")
	sStroke.Color = if inPvp then Theme.Colors.Danger else Theme.Colors.Success
	sStroke.Thickness = 2
	sStroke.Parent = statusCard

	local zoneBadge = Instance.new("TextLabel")
	zoneBadge.Name = "ZoneBadge"
	zoneBadge.Position = UDim2.new(0, 12, 0, 10)
	zoneBadge.Size = UDim2.new(1, -24, 0, 24)
	zoneBadge.BackgroundTransparency = 1
	zoneBadge.Font = Theme.Fonts.Heading
	zoneBadge.TextColor3 = if inPvp then Theme.Colors.Danger else Theme.Colors.Success
	zoneBadge.TextSize = 16
	zoneBadge.TextXAlignment = Enum.TextXAlignment.Left
	zoneBadge.Text = string.format("%s  •  [%s]", arenaState.arenaDisplayName, arenaState.statusText)
	zoneBadge.Parent = statusCard

	local buildStats = Instance.new("TextLabel")
	buildStats.Name = "BuildStats"
	buildStats.Position = UDim2.new(0, 12, 0, 38)
	buildStats.Size = UDim2.new(1, -24, 0, 22)
	buildStats.BackgroundTransparency = 1
	buildStats.Font = Theme.Fonts.Body
	buildStats.TextColor3 = Theme.Colors.TextSecondary
	buildStats.TextSize = 13
	buildStats.TextXAlignment = Enum.TextXAlignment.Left
	buildStats.Text = string.format(
		"Ваша сборка: ⚔️ АТК %d  |  🛡️ Броня %d  |  ❤️ HP %d  |  ⚡ Скор %d  |  Дуэли: Побед %d / Поражений %d",
		assemblySummary.attackPower,
		assemblySummary.defense,
		assemblySummary.maxHealth,
		assemblySummary.moveSpeed,
		arenaState.pvpKills,
		arenaState.pvpDeaths
	)
	buildStats.Parent = statusCard

	-- Кнопки добровольного входа и выхода
	local enterBtn = Instance.new("TextButton")
	enterBtn.Name = "EnterArenaButton"
	enterBtn.Position = UDim2.new(0, 12, 0, 70)
	enterBtn.Size = UDim2.new(0.48, -14, 0, 42)
	enterBtn.BackgroundColor3 = if inPvp or isTransitioning then Theme.Colors.Border else Theme.Colors.Danger
	enterBtn.Font = Theme.Fonts.Heading
	enterBtn.TextColor3 = Theme.Colors.TextPrimary
	enterBtn.TextSize = 14
	enterBtn.Text = if arenaState.zoneState == "Entering"
		then "⏳ ВХОД НА АРЕНУ..."
		elseif inPvp then "✓ ВЫ НА PvP-АРЕНЕ"
		else string.format("⚔️ ВОЙТИ НА АРЕНУ (Ур. %d+)", arenaState.minPlayerLevel)
	enterBtn.Parent = statusCard

	local eCorner = Instance.new("UICorner")
	eCorner.CornerRadius = Theme.CornerRadius.Small
	eCorner.Parent = enterBtn

	enterBtn.Activated:Connect(function()
		if not inPvp and not isTransitioning then
			onEnterArena()
		end
	end)

	local leaveBtn = Instance.new("TextButton")
	leaveBtn.Name = "LeaveArenaButton"
	leaveBtn.Position = UDim2.new(0.52, 2, 0, 70)
	leaveBtn.Size = UDim2.new(0.48, -14, 0, 42)
	leaveBtn.BackgroundColor3 = if inPvp then Theme.Colors.Success else Theme.Colors.Border
	leaveBtn.Font = Theme.Fonts.Heading
	leaveBtn.TextColor3 = Theme.Colors.TextPrimary
	leaveBtn.TextSize = 14
	leaveBtn.Text = if arenaState.zoneState == "Leaving"
		then "⏳ ВЫХОД В БЕЗОПАСНУЮ ЗОНУ..."
		else "🏳️ ПОКИНУТЬ АРЕНУ (БЕЗОПАСНАЯ ЗОНА)"
	leaveBtn.Parent = statusCard

	local lCorner = Instance.new("UICorner")
	lCorner.CornerRadius = Theme.CornerRadius.Small
	lCorner.Parent = leaveBtn

	leaveBtn.Activated:Connect(function()
		if inPvp or arenaState.zoneState == "Entering" then
			onLeaveArena()
		end
	end)

	-- 2. Блок последнего результата боя на арене
	local resultCard = Instance.new("Frame")
	resultCard.Name = "MatchResultCard"
	resultCard.Size = UDim2.new(1, -8, 0, 74)
	resultCard.BackgroundColor3 = Theme.Colors.Background
	resultCard.BorderSizePixel = 0
	resultCard.LayoutOrder = 2
	resultCard.Parent = contentFrame

	local rCorner = Instance.new("UICorner")
	rCorner.CornerRadius = Theme.CornerRadius.Medium
	rCorner.Parent = resultCard

	local rStroke = Instance.new("UIStroke")
	rStroke.Color = if arenaState.lastMatchOutcome == "Victory"
		then Theme.Colors.Success
		elseif arenaState.lastMatchOutcome == "Defeat" then Theme.Colors.Warning
		else Theme.Colors.Border
	rStroke.Thickness = 1.5
	rStroke.Parent = resultCard

	local resTitle = Instance.new("TextLabel")
	resTitle.Position = UDim2.new(0, 12, 0, 8)
	resTitle.Size = UDim2.new(1, -24, 0, 22)
	resTitle.BackgroundTransparency = 1
	resTitle.Font = Theme.Fonts.Heading
	resTitle.TextColor3 = Theme.Colors.TextPrimary
	resTitle.TextSize = 14
	resTitle.TextXAlignment = Enum.TextXAlignment.Left
	resTitle.Text = "📊 РЕЗУЛЬТАТ БОЯ НА АРЕНЕ"
	resTitle.Parent = resultCard

	local resBody = Instance.new("TextLabel")
	resBody.Name = "MatchOutcomeText"
	resBody.Position = UDim2.new(0, 12, 0, 32)
	resBody.Size = UDim2.new(1, -24, 0, 34)
	resBody.BackgroundTransparency = 1
	resBody.Font = Theme.Fonts.Body
	resBody.TextColor3 = if arenaState.lastMatchOutcome == "Victory"
		then Theme.Colors.Success
		elseif arenaState.lastMatchOutcome == "Defeat" then Theme.Colors.Warning
		else Theme.Colors.TextSecondary
	resBody.TextSize = 13
	resBody.TextWrapped = true
	resBody.TextXAlignment = Enum.TextXAlignment.Left
	resBody.Text = arenaState.lastMatchMessage
		or "Пока нет завершённых дуэлей. Войдите на добровольную арену, чтобы испытать свою сборку!"
	resBody.Parent = resultCard

	-- 3. Правила добровольной PvP-арены
	local rulesCard = Instance.new("Frame")
	rulesCard.Name = "ArenaRulesCard"
	rulesCard.Size = UDim2.new(1, -8, 0, 118)
	rulesCard.BackgroundColor3 = Theme.Colors.Surface
	rulesCard.BorderSizePixel = 0
	rulesCard.LayoutOrder = 3
	rulesCard.Parent = contentFrame

	local ruCorner = Instance.new("UICorner")
	ruCorner.CornerRadius = Theme.CornerRadius.Medium
	ruCorner.Parent = rulesCard

	local ruTitle = Instance.new("TextLabel")
	ruTitle.Position = UDim2.new(0, 12, 0, 8)
	ruTitle.Size = UDim2.new(1, -24, 0, 20)
	ruTitle.BackgroundTransparency = 1
	ruTitle.Font = Theme.Fonts.Heading
	ruTitle.TextColor3 = Theme.Colors.TextPrimary
	ruTitle.TextSize = 14
	ruTitle.TextXAlignment = Enum.TextXAlignment.Left
	ruTitle.Text = "📜 ПРАВИЛА ДОБРОВОЛЬНОЙ PvP-АРЕНЫ"
	ruTitle.Parent = rulesCard

	local ruBody = Instance.new("TextLabel")
	ruBody.Position = UDim2.new(0, 12, 0, 30)
	ruBody.Size = UDim2.new(1, -24, 0, 82)
	ruBody.BackgroundTransparency = 1
	ruBody.Font = Theme.Fonts.Body
	ruBody.TextColor3 = Theme.Colors.TextSecondary
	ruBody.TextSize = 12
	ruBody.TextWrapped = true
	ruBody.TextXAlignment = Enum.TextXAlignment.Left
	ruBody.TextYAlignment = Enum.TextYAlignment.Top
	ruBody.Text = table.concat(arenaState.rulesSummary, "\n")
	ruBody.Parent = rulesCard
end

return ArenaView
