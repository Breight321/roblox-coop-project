--!strict
--[[
	@module ExpeditionZoneManager
	@owner Agent B (anarugod)
	@description 3D-представление общих зон добычи (ExtractionZones), Станций Переплавки (DepositStations)
	и Монумента Командного Этапа для «Sunforge Expedition», полностью синхронизированное с HarvestConfig (Agent A).
	Использует компактные кластерные узлы вместо спавна тысяч отдельных объектов-монет.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local HarvestConfig = require(Shared:WaitForChild("Config"):WaitForChild("HarvestConfig"))

local ControllersFolder = script.Parent.Parent:WaitForChild("Controllers")
local ExpeditionFolder = ControllersFolder:WaitForChild("ExpeditionController")
local ExpeditionTypes = require(ExpeditionFolder:WaitForChild("Types"))
local ExpeditionConfig = require(ExpeditionFolder:WaitForChild("Config"))
local Theme = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("Theme"))

export type WorldCallbacks = {
	OnCollectNodeTriggered: (nodeId: string) -> (),
	OnDepositStationTriggered: (stationId: string) -> (),
}

local ExpeditionZoneManager = {}

local clientDecorFolder: Folder? = nil
local zoneClusterParts: { [string]: { Part } } = {}
local stationParts: { [string]: Part } = {}
local stationTitleLabels: { [string]: TextLabel } = {}
local stationSubLabels: { [string]: TextLabel } = {}
local stationPrompts: { [string]: ProximityPrompt } = {}

local monumentTitleLabel: TextLabel? = nil
local monumentProgressLabel: TextLabel? = nil
local monumentBarFill: Frame? = nil

local function createBillboard(
	parent: Instance,
	name: string,
	sizeOffset: Vector2,
	studsOffset: Vector3
): (BillboardGui, Frame)
	local bb = Instance.new("BillboardGui")
	bb.Name = name
	bb.Size = UDim2.new(0, sizeOffset.X, 0, sizeOffset.Y)
	bb.StudsOffset = studsOffset
	bb.AlwaysOnTop = true
	bb.MaxDistance = 100
	bb.Parent = parent

	local card = Instance.new("Frame")
	card.Name = "Card"
	card.Size = UDim2.new(1, 0, 1, 0)
	card.BackgroundColor3 = Theme.Colors.Background
	card.BackgroundTransparency = 0.12
	card.BorderSizePixel = 0
	card.Parent = bb

	local corner = Instance.new("UICorner")
	corner.CornerRadius = Theme.CornerRadius.Medium
	corner.Parent = card

	local stroke = Instance.new("UIStroke")
	stroke.Name = "BorderStroke"
	stroke.Color = Theme.Colors.Primary
	stroke.Thickness = 1.5
	stroke.Parent = card

	return bb, card
end

function ExpeditionZoneManager.EnsureWorld(callbacks: WorldCallbacks): Folder
	if clientDecorFolder and clientDecorFolder.Parent then
		return clientDecorFolder
	end

	local existing = Workspace:FindFirstChild("SunforgeClientDecor")
	if existing and existing:IsA("Folder") then
		existing:Destroy()
	end

	local root = Instance.new("Folder")
	root.Name = "SunforgeClientDecor"
	root.Parent = Workspace
	clientDecorFolder = root

	-- 1. Кластерные жилы внутри каждой зоны добычи из HarvestConfig.ExtractionZones
	for zoneId, zoneDef in pairs(HarvestConfig.ExtractionZones) do
		local zoneContainer = Instance.new("Folder")
		zoneContainer.Name = "Zone_" .. zoneId
		zoneContainer.Parent = root

		local centerHub = Instance.new("Part")
		centerHub.Name = "Hub_" .. zoneId
		centerHub.Anchored = true
		centerHub.CanCollide = true
		centerHub.Size = Vector3.new(6, 4.5, 6)
		centerHub.Position = zoneDef.centerPosition + Vector3.new(0, 2.25, 0)
		centerHub.Material = Enum.Material.Neon
		centerHub.Color = if zoneDef.requiredServerStage == 1
			then Color3.fromRGB(255, 196, 54)
			elseif zoneDef.requiredServerStage == 2 then Color3.fromRGB(255, 118, 48)
			else Color3.fromRGB(88, 214, 255)
		centerHub.Parent = zoneContainer

		local _, card = createBillboard(centerHub, "ZoneBillboard", Vector2.new(230, 56), Vector3.new(0, 4.5, 0))
		local title = Instance.new("TextLabel")
		title.Name = "Title"
		title.Size = UDim2.new(1, -12, 0, 24)
		title.Position = UDim2.new(0, 6, 0, 4)
		title.BackgroundTransparency = 1
		title.Font = Theme.Fonts.Heading
		title.TextColor3 = Theme.Colors.Coins
		title.TextSize = 14
		title.Text = string.format("⛏️ %s (x%.1f)", zoneDef.displayName, zoneDef.yieldMultiplier)
		title.Parent = card

		local sub = Instance.new("TextLabel")
		sub.Name = "Sub"
		sub.Size = UDim2.new(1, -12, 0, 22)
		sub.Position = UDim2.new(0, 6, 0, 28)
		sub.BackgroundTransparency = 1
		sub.Font = Theme.Fonts.Body
		sub.TextColor3 = Theme.Colors.TextSecondary
		sub.TextSize = 11
		sub.Text = string.format("Этап %d+ • Клик / [E] — Добывать Solar Shards", zoneDef.requiredServerStage)
		sub.Parent = card

		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "HarvestPrompt"
		prompt.ActionText = "Добывать Solar Shards"
		prompt.ObjectText = zoneDef.displayName
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = 24
		prompt.RequiresLineOfSight = false
		prompt.Parent = centerHub

		prompt.Triggered:Connect(function()
			callbacks.OnCollectNodeTriggered(zoneId)
		end)

		local detector = Instance.new("ClickDetector")
		detector.Name = "HarvestClickDetector"
		detector.MaxActivationDistance = 42
		detector.Parent = centerHub

		detector.MouseClick:Connect(function()
			callbacks.OnCollectNodeTriggered(zoneId)
		end)

		zoneClusterParts[zoneId] = { centerHub }

		-- 4 кристаллических спутника вокруг ядра зоны (компактная визуализация без спама объектами)
		for idx = 1, 4 do
			local angle = (idx - 1) * (math.pi / 2)
			local offset = Vector3.new(math.cos(angle) * 11, 1.5, math.sin(angle) * 11)
			local crystal = Instance.new("Part")
			crystal.Name = string.format("%s_Crystal_%d", zoneId, idx)
			crystal.Anchored = true
			crystal.CanCollide = true
			crystal.Size = Vector3.new(3.2, 3.0, 3.2)
			crystal.Position = zoneDef.centerPosition + offset
			crystal.Material = Enum.Material.Neon
			crystal.Color = centerHub.Color
			crystal.Parent = zoneContainer

			local crDetector = Instance.new("ClickDetector")
			crDetector.MaxActivationDistance = 38
			crDetector.Parent = crystal
			crDetector.MouseClick:Connect(function()
				callbacks.OnCollectNodeTriggered(zoneId)
			end)

			table.insert(zoneClusterParts[zoneId], crystal)
		end
	end

	-- 2. Станции Сдачи из HarvestConfig.DepositStations
	for stationId, stationDef in pairs(HarvestConfig.DepositStations) do
		if stationDef.active then
			local pillar = Instance.new("Part")
			pillar.Name = "Station_" .. stationId
			pillar.Anchored = true
			pillar.CanCollide = true
			pillar.Size = Vector3.new(8, 5.5, 5)
			pillar.Position = stationDef.position + Vector3.new(0, 2.75, 0)
			pillar.Material = Enum.Material.Neon
			pillar.Color = Theme.Colors.Success
			pillar.Parent = root
			stationParts[stationId] = pillar

			local _, stCard = createBillboard(pillar, "StationBillboard", Vector2.new(255, 66), Vector3.new(0, 5.0, 0))
			local stTitle = Instance.new("TextLabel")
			stTitle.Name = "StationTitle"
			stTitle.Size = UDim2.new(1, -14, 0, 24)
			stTitle.Position = UDim2.new(0, 7, 0, 6)
			stTitle.BackgroundTransparency = 1
			stTitle.Font = Theme.Fonts.Heading
			stTitle.TextColor3 = Theme.Colors.Success
			stTitle.TextSize = 14
			stTitle.Text = string.format("🏦 %s (x%.2f)", stationDef.displayName, stationDef.exchangeRate)
			stTitle.Parent = stCard
			stationTitleLabels[stationId] = stTitle

			local stSub = Instance.new("TextLabel")
			stSub.Name = "StationSub"
			stSub.Size = UDim2.new(1, -14, 0, 30)
			stSub.Position = UDim2.new(0, 7, 0, 30)
			stSub.BackgroundTransparency = 1
			stSub.Font = Theme.Fonts.Body
			stSub.TextColor3 = Theme.Colors.TextPrimary
			stSub.TextSize = 12
			stSub.TextWrapped = true
			stSub.Text = "Подойдите и нажмите [F] или кнопку HUD для сдачи добычи"
			stSub.Parent = stCard
			stationSubLabels[stationId] = stSub

			local depPrompt = Instance.new("ProximityPrompt")
			depPrompt.Name = "DepositPrompt"
			depPrompt.ActionText = "Сдать Solar Shards"
			depPrompt.ObjectText = stationDef.displayName
			depPrompt.KeyboardKeyCode = Enum.KeyCode.F
			depPrompt.HoldDuration = 0
			depPrompt.MaxActivationDistance = stationDef.interactionRadius
			depPrompt.RequiresLineOfSight = false
			depPrompt.Parent = pillar
			stationPrompts[stationId] = depPrompt

			depPrompt.Triggered:Connect(function()
				callbacks.OnDepositStationTriggered(stationId)
			end)

			local depDetector = Instance.new("ClickDetector")
			depDetector.Name = "DepositClickDetector"
			depDetector.MaxActivationDistance = stationDef.interactionRadius
			depDetector.Parent = pillar

			depDetector.MouseClick:Connect(function()
				callbacks.OnDepositStationTriggered(stationId)
			end)
		end
	end

	-- 3. Монумент Командного Этапа (Team Stage Monument)
	local monument = Instance.new("Part")
	monument.Name = "SunforgeStageMonument"
	monument.Anchored = true
	monument.CanCollide = true
	monument.Size = Vector3.new(14, 9, 2.5)
	monument.Position = ExpeditionConfig.StageMonumentPosition
	monument.Material = Enum.Material.SmoothPlastic
	monument.Color = Color3.fromRGB(45, 50, 70)
	monument.Parent = root

	local _, monCard = createBillboard(monument, "MonumentBillboard", Vector2.new(310, 84), Vector3.new(0, 6.8, 0))
	local monTitle = Instance.new("TextLabel")
	monTitle.Name = "MonumentTitle"
	monTitle.Size = UDim2.new(1, -16, 0, 24)
	monTitle.Position = UDim2.new(0, 8, 0, 6)
	monTitle.BackgroundTransparency = 1
	monTitle.Font = Theme.Fonts.Heading
	monTitle.TextColor3 = Theme.Colors.Accent
	monTitle.TextSize = 14
	monTitle.Text = "🌟 Stage I: Awakening the Forge"
	monTitle.Parent = monCard
	monumentTitleLabel = monTitle

	local monProg = Instance.new("TextLabel")
	monProg.Name = "MonumentProgress"
	monProg.Size = UDim2.new(1, -16, 0, 22)
	monProg.Position = UDim2.new(0, 8, 0, 30)
	monProg.BackgroundTransparency = 1
	monProg.Font = Theme.Fonts.Body
	monProg.TextColor3 = Theme.Colors.TextPrimary
	monProg.TextSize = 13
	monProg.Text = "Сдано командой: 0 / 100 (0%)"
	monProg.Parent = monCard
	monumentProgressLabel = monProg

	local barBg = Instance.new("Frame")
	barBg.Name = "BarBackground"
	barBg.Size = UDim2.new(1, -20, 0, 14)
	barBg.Position = UDim2.new(0, 10, 0, 58)
	barBg.BackgroundColor3 = Theme.Colors.SurfaceLight
	barBg.BorderSizePixel = 0
	barBg.Parent = monCard

	local barCorner = Instance.new("UICorner")
	barCorner.CornerRadius = Theme.CornerRadius.Pill
	barCorner.Parent = barBg

	local barFill = Instance.new("Frame")
	barFill.Name = "BarFill"
	barFill.Size = UDim2.new(0, 0, 1, 0)
	barFill.BackgroundColor3 = Theme.Colors.Primary
	barFill.BorderSizePixel = 0
	barFill.Parent = barBg
	monumentBarFill = barFill

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = Theme.CornerRadius.Pill
	fillCorner.Parent = barFill

	return root
end

function ExpeditionZoneManager.PlayNodePulse(nodeId: string): ()
	local parts = zoneClusterParts[nodeId] or zoneClusterParts[HarvestConfig.DefaultNodeId]
	if not parts then
		return
	end
	for _, part in ipairs(parts) do
		if part and part.Parent then
			local baseSize = part.Size
			local shrink = TweenService:Create(
				part,
				TweenInfo.new(0.06, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ Size = baseSize * 0.88 }
			)
			local expand = TweenService:Create(
				part,
				TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
				{ Size = baseSize }
			)
			shrink:Play()
			shrink.Completed:Once(function()
				expand:Play()
			end)
		end
	end
end

function ExpeditionZoneManager.SyncBagAndDepositState(bagState: ExpeditionTypes.BagStateViewModel): ()
	for stationId, pillar in pairs(stationParts) do
		local titleLbl = stationTitleLabels[stationId]
		local subLbl = stationSubLabels[stationId]
		local prompt = stationPrompts[stationId]
		local stationDef = HarvestConfig.DepositStations[stationId]
		local stationName = if stationDef then stationDef.displayName else stationId

		if bagState.depositStatus == "Loading" then
			pillar.Color = Theme.Colors.Warning
			if titleLbl then
				titleLbl.Text = "⏳ ПЕРЕПЛАВКА ДОБЫЧИ..."
				titleLbl.TextColor3 = Theme.Colors.Warning
			end
			if subLbl then
				subLbl.Text = "Ожидание подтверждения от сервера..."
			end
		elseif bagState.depositStatus == "Error" then
			pillar.Color = Theme.Colors.Error
			if titleLbl then
				titleLbl.Text = "✗ ОТКАЗ СДАЧИ НА СТАНЦИИ"
				titleLbl.TextColor3 = Theme.Colors.Error
			end
			if subLbl then
				subLbl.Text = tostring(bagState.lastError or "Подойдите ближе и нажмите [F]")
			end
		elseif bagState.isFull then
			pillar.Color = Theme.Colors.Accent
			if titleLbl then
				titleLbl.Text = "🚨 СУМКА ПОЛНА — СДАЙТЕ ЗДЕСЬ!"
				titleLbl.TextColor3 = Theme.Colors.Accent
			end
			if subLbl then
				subLbl.Text = string.format(
					"В сумке %d / %d Solar Shards • Нажмите [F] для сдачи!",
					bagState.current,
					bagState.capacity
				)
			end
		elseif bagState.isNearlyFull then
			pillar.Color = Theme.Colors.Warning
			if titleLbl then
				titleLbl.Text = "⚠️ ПОРА НА СТАНЦИЮ СДАЧИ!"
				titleLbl.TextColor3 = Theme.Colors.Warning
			end
			if subLbl then
				subLbl.Text = string.format(
					"Сумка почти полна (%d / %d) • Сдайте на %s [F]",
					bagState.current,
					bagState.capacity,
					stationName
				)
			end
		else
			pillar.Color = Theme.Colors.Success
			if titleLbl then
				titleLbl.Text = string.format("🏦 %s", stationName)
				titleLbl.TextColor3 = Theme.Colors.Success
			end
			if subLbl then
				subLbl.Text = string.format(
					"В сумке: %d / %d Solar Shards • Нажмите [F] для сдачи",
					bagState.current,
					bagState.capacity
				)
			end
		end

		if prompt then
			prompt.ActionText = if bagState.current > 0
				then string.format("Сдать добычу (%d Solar Shards)", bagState.current)
				else "Сумка пуста (соберите Solar Shards)"
		end
	end
end

function ExpeditionZoneManager.SyncTeamMonument(teamState: ExpeditionTypes.TeamProgressViewModel): ()
	if monumentTitleLabel then
		monumentTitleLabel.Text = string.format("🌟 %s (Этап %d)", teamState.stageName, teamState.stageNumber)
		monumentTitleLabel.TextColor3 = if teamState.isUnlocked
			then Theme.Colors.Success
			else Theme.Colors.Accent
	end

	if monumentProgressLabel then
		local pct = math.floor(teamState.progressRatio * 100)
		monumentProgressLabel.Text = string.format(
			"Командный вклад: %d / %d (%d%%) • %s",
			teamState.currentAmount,
			teamState.targetAmount,
			pct,
			teamState.nextStageName
		)
	end

	if monumentBarFill then
		monumentBarFill.Size = UDim2.new(teamState.progressRatio, 0, 1, 0)
		monumentBarFill.BackgroundColor3 = if teamState.isUnlocked
			then Theme.Colors.Success
			else Theme.Colors.Primary
	end
end

function ExpeditionZoneManager.Cleanup(): ()
	table.clear(zoneClusterParts)
	table.clear(stationParts)
	table.clear(stationTitleLabels)
	table.clear(stationSubLabels)
	table.clear(stationPrompts)
	monumentTitleLabel = nil
	monumentProgressLabel = nil
	monumentBarFill = nil
	if clientDecorFolder then
		clientDecorFolder:Destroy()
		clientDecorFolder = nil
	end
end

return ExpeditionZoneManager
