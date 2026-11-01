--!strict
--[[
	@module WorldMobChestManager
	@owner Agent B (anarugod)
	@description Клиентский менеджер отображения и интеракций мобов, сундуков по зонам
	и портала добровольной PvP-арены в Workspace.
	Интегрируется как с серверными папками Workspace.CombatWorld (Mobs, Chests, Arena),
	так и с клиентским визуальным оформлением (ModularMech, BillboardGui, ProximityPrompt).
]]

local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local ControllersFolder = script.Parent.Parent:WaitForChild("Controllers")
local CombatConfig = require(ControllersFolder:WaitForChild("CombatController"):WaitForChild("Config"))
local CombatTypes = require(ControllersFolder:WaitForChild("CombatController"):WaitForChild("Types"))

export type WorldCombatCallbacks = {
	OnMobAttackTriggered: (mobUid: string) -> (),
	OnChestOpenTriggered: (chestId: string) -> (),
	OnArenaPortalTriggered: () -> (),
}

local WorldMobChestManager = {}

local mobVisuals: { [string]: BasePart } = {}
local chestVisuals: { [string]: BasePart } = {}
local boundPrompts: { [Instance]: boolean } = {}

local function getOrCreateBillboard(part: BasePart, name: string, offset: Vector3): (Frame, TextLabel, TextLabel, Frame?)
	local existing = part:FindFirstChild(name)
	if existing and existing:IsA("BillboardGui") then
		local container = existing:FindFirstChild("Container") :: Frame
		local title = container and container:FindFirstChild("TitleLabel") :: TextLabel
		local sub = container and container:FindFirstChild("StatusLabel") :: TextLabel
		local barBg = container and container:FindFirstChild("BarBg")
		local barFill = barBg and barBg:FindFirstChild("BarFill") :: Frame?
		if container and title and sub then
			return container, title, sub, barFill
		end
	end

	local bb = Instance.new("BillboardGui")
	bb.Name = name
	bb.Size = UDim2.new(0, 210, 0, 54)
	bb.StudsOffset = offset
	bb.AlwaysOnTop = true
	bb.Parent = part

	local bg = Instance.new("Frame")
	bg.Name = "Container"
	bg.Size = UDim2.new(1, 0, 1, 0)
	bg.BackgroundColor3 = Color3.fromRGB(20, 24, 34)
	bg.BackgroundTransparency = 0.15
	bg.BorderSizePixel = 0
	bg.Parent = bb

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = bg

	local title = Instance.new("TextLabel")
	title.Name = "TitleLabel"
	title.Position = UDim2.new(0, 6, 0, 4)
	title.Size = UDim2.new(1, -12, 0, 18)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBold
	title.TextColor3 = Color3.fromRGB(245, 247, 250)
	title.TextSize = 12
	title.Parent = bg

	local sub = Instance.new("TextLabel")
	sub.Name = "StatusLabel"
	sub.Position = UDim2.new(0, 6, 0, 22)
	sub.Size = UDim2.new(1, -12, 0, 16)
	sub.BackgroundTransparency = 1
	sub.Font = Enum.Font.GothamMedium
	sub.TextColor3 = Color3.fromRGB(255, 205, 115)
	sub.TextSize = 11
	sub.Parent = bg

	local barBg = Instance.new("Frame")
	barBg.Name = "BarBg"
	barBg.Position = UDim2.new(0, 8, 0, 40)
	barBg.Size = UDim2.new(1, -16, 0, 8)
	barBg.BackgroundColor3 = Color3.fromRGB(45, 52, 68)
	barBg.BorderSizePixel = 0
	barBg.Parent = bg

	local barFill = Instance.new("Frame")
	barFill.Name = "BarFill"
	barFill.Size = UDim2.new(1, 0, 1, 0)
	barFill.BackgroundColor3 = Color3.fromRGB(235, 82, 82)
	barFill.BorderSizePixel = 0
	barFill.Parent = barBg

	return bg, title, sub, barFill
end

local function resolvePrimaryPart(inst: Instance): BasePart?
	if inst:IsA("BasePart") then
		return inst
	elseif inst:IsA("Model") then
		if inst.PrimaryPart then
			return inst.PrimaryPart
		end
		return inst:FindFirstChildWhichIsA("BasePart")
	end
	return nil
end

local function decorateMobInstance(inst: Instance, callbacks: WorldCombatCallbacks)
	if boundPrompts[inst] then
		return
	end
	local part = resolvePrimaryPart(inst)
	if not part then
		return
	end
	boundPrompts[inst] = true

	local mobUid = tostring(inst:GetAttribute("MobUid") or inst.Name)
	local mobId = tostring(inst:GetAttribute("MobId") or inst:GetAttribute("MobType") or mobUid)
	local def = CombatConfig.SharedCombat.Mobs[mobId]
	local displayName = tostring(inst:GetAttribute("DisplayName") or (def and def.displayName) or mobId)
	local level = tonumber(inst:GetAttribute("Level")) or (def and def.level) or 1
	local maxHp = tonumber(inst:GetAttribute("MaxHealth")) or (def and def.maxHealth) or 100
	local curHp = tonumber(inst:GetAttribute("Health")) or maxHp

	mobVisuals[mobUid] = part
	mobVisuals[mobId] = part

	local _, title, sub, barFill = getOrCreateBillboard(part, "MobBillboard", Vector3.new(0, 4.2, 0))
	title.Text = string.format("👾 %s [Ур. %d]", displayName, level)
	sub.Text = string.format("HP: %d / %d", curHp, maxHp)
	if barFill then
		barFill.Size = UDim2.new(math.clamp(curHp / math.max(1, maxHp), 0, 1), 0, 1, 0)
	end

	local prompt = part:FindFirstChildOfClass("ProximityPrompt") or inst:FindFirstChildOfClass("ProximityPrompt")
	if not prompt then
		local newPrompt = Instance.new("ProximityPrompt")
		newPrompt.Name = "AttackPrompt"
		newPrompt.ActionText = "Атаковать"
		newPrompt.ObjectText = string.format("%s (Ур. %d)", displayName, level)
		newPrompt.HoldDuration = 0
		newPrompt.MaxActivationDistance = CombatConfig.MaxCombatLockRange
		newPrompt.RequiresLineOfSight = false
		newPrompt.Parent = part
		prompt = newPrompt
	end

	if prompt then
		prompt.Triggered:Connect(function()
			callbacks.OnMobAttackTriggered(mobUid)
		end)
	end
end

local function decorateChestInstance(inst: Instance, callbacks: WorldCombatCallbacks)
	if boundPrompts[inst] then
		return
	end
	local part = resolvePrimaryPart(inst)
	if not part then
		return
	end
	boundPrompts[inst] = true

	local chestId = tostring(inst:GetAttribute("ChestId") or inst.Name)
	local def = CombatConfig.SharedCombat.Chests[chestId]
	local displayName = tostring(inst:GetAttribute("DisplayName") or (def and def.displayName) or chestId)

	chestVisuals[chestId] = part

	local _, title, sub, barFill = getOrCreateBillboard(part, "ChestBillboard", Vector3.new(0, 3.6, 0))
	title.Text = "🧰 " .. displayName
	sub.Text = string.format("Ур. %d+ • Требуется побед: %d", def and def.minPlayerLevel or 1, def and def.requiredKillsSinceLastOpen or 2)
	if barFill and barFill.Parent then
		(barFill.Parent :: Frame).Visible = false
	end

	local prompt = part:FindFirstChildOfClass("ProximityPrompt") or inst:FindFirstChildOfClass("ProximityPrompt")
	if not prompt then
		local newPrompt = Instance.new("ProximityPrompt")
		newPrompt.Name = "OpenChestPrompt"
		newPrompt.ActionText = "Открыть сундук"
		newPrompt.ObjectText = displayName
		newPrompt.HoldDuration = 0.15
		newPrompt.MaxActivationDistance = (def and def.interactionRadius) or 18
		newPrompt.RequiresLineOfSight = false
		newPrompt.Parent = part
		prompt = newPrompt
	end

	if prompt then
		prompt.Triggered:Connect(function()
			callbacks.OnChestOpenTriggered(chestId)
		end)
	end
end

local function decorateArenaFolder(arenaFolder: Instance, callbacks: WorldCombatCallbacks)
	for _, child in ipairs(arenaFolder:GetDescendants()) do
		if child:IsA("ProximityPrompt") and not boundPrompts[child] then
			boundPrompts[child] = true
			child.Triggered:Connect(function()
				callbacks.OnArenaPortalTriggered()
			end)
		end
	end
end

function WorldMobChestManager.EnsureWorld(callbacks: WorldCombatCallbacks): ()
	task.spawn(function()
		local combatWorld = Workspace:WaitForChild("CombatWorld", 10)
		if not combatWorld then
			return
		end

		local mobsFolder = combatWorld:FindFirstChild("Mobs")
		if mobsFolder then
			for _, child in ipairs(mobsFolder:GetChildren()) do
				decorateMobInstance(child, callbacks)
			end
			mobsFolder.ChildAdded:Connect(function(child)
				task.defer(decorateMobInstance, child, callbacks)
			end)
		end

		local chestsFolder = combatWorld:FindFirstChild("Chests")
		if chestsFolder then
			for _, child in ipairs(chestsFolder:GetChildren()) do
				decorateChestInstance(child, callbacks)
			end
			chestsFolder.ChildAdded:Connect(function(child)
				task.defer(decorateChestInstance, child, callbacks)
			end)
		end

		local arenaFolder = combatWorld:FindFirstChild("Arena")
		if arenaFolder then
			decorateArenaFolder(arenaFolder, callbacks)
		end
	end)
end

function WorldMobChestManager.SyncMobs(mobs: { CombatTypes.MobTargetViewModel }): ()
	for _, mobVm in ipairs(mobs) do
		local part = mobVisuals[mobVm.mobUid] or mobVisuals[mobVm.mobId]
		if part then
			local bb = part:FindFirstChild("MobBillboard")
			local container = bb and bb:FindFirstChild("Container")
			if container then
				local statusLabel = container:FindFirstChild("StatusLabel")
				if statusLabel and statusLabel:IsA("TextLabel") then
					statusLabel.Text = if mobVm.defeated
						then "🏆 ПОВЕРЖЕН! Возрождение..."
						else string.format("HP: %d / %d", mobVm.currentHp, mobVm.maxHp)
				end
				local barBg = container:FindFirstChild("BarBg")
				local barFill = barBg and barBg:FindFirstChild("BarFill")
				if barFill and barFill:IsA("Frame") then
					barFill.Size = UDim2.new(math.clamp(mobVm.hpRatio, 0, 1), 0, 1, 0)
				end
			end
		end
	end
end

function WorldMobChestManager.PlayMobHitEffect(mobUid: string, _damageDealt: number, defeated: boolean): ()
	local part = mobVisuals[mobUid]
	if not part then
		return
	end
	local origColor = part.Color
	part.Color = if defeated then Color3.fromRGB(255, 215, 80) else Color3.fromRGB(255, 95, 95)
	local tween = TweenService:Create(part, TweenInfo.new(0.22), { Color = origColor })
	tween:Play()
end

function WorldMobChestManager.SyncChests(chests: { CombatTypes.ChestDefViewModel }): ()
	for _, chestVm in ipairs(chests) do
		local part = chestVisuals[chestVm.id]
		if part then
			local bb = part:FindFirstChild("ChestBillboard")
			local container = bb and bb:FindFirstChild("Container")
			if container then
				local statusLabel = container:FindFirstChild("StatusLabel")
				if statusLabel and statusLabel:IsA("TextLabel") then
					if chestVm.status == "Loading" then
						statusLabel.Text = "⏳ Запрос на сервере..."
						statusLabel.TextColor3 = Color3.fromRGB(255, 200, 90)
					elseif chestVm.status == "Success" and chestVm.lastRewardText then
						statusLabel.Text = chestVm.lastRewardText
						statusLabel.TextColor3 = Color3.fromRGB(100, 235, 140)
					elseif chestVm.status == "Error" then
						statusLabel.Text = chestVm.statusMessage or "Ошибка открытия"
						statusLabel.TextColor3 = Color3.fromRGB(255, 105, 105)
					else
						statusLabel.Text = chestVm.statusMessage
							or string.format("Побеждено мобов: %d/%d", chestVm.killsProgress, chestVm.requiredKills)
						statusLabel.TextColor3 = if chestVm.isReady
							then Color3.fromRGB(110, 235, 150)
							else Color3.fromRGB(200, 210, 225)
					end
				end
			end
		end
	end
end

function WorldMobChestManager.Cleanup(): ()
	table.clear(mobVisuals)
	table.clear(chestVisuals)
	table.clear(boundPrompts)
end

return WorldMobChestManager
