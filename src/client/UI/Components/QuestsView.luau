--!strict
--[[
	@module QuestsView
	@owner Agent 2 (anarugod)
	@description Отрисовка списка квестов, прогресс-баров и кнопки получения награды (Claim Reward).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Core"):WaitForChild("Types"))
local QuestsConfig = require(Shared:WaitForChild("Config"):WaitForChild("QuestsConfig"))
local Theme = require(script.Parent.Parent:WaitForChild("Theme"))

local QuestsView = {}

function QuestsView.Render(
	contentFrame: ScrollingFrame,
	questsState: { [string]: Types.QuestState },
	onClaimQuest: (questId: string) -> ()
): ()
	for _, child in ipairs(contentFrame:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end

	local questIds: { string } = {}
	for qId in pairs(QuestsConfig) do
		table.insert(questIds, qId)
	end
	table.sort(questIds)

	for idx, qId in ipairs(questIds) do
		local def = QuestsConfig[qId]
		local state = questsState[qId]
		local progress = if state then state.progress else 0
		local target = if state then state.target else def.targetAmount
		local completed = if state then state.completed else false
		local claimed = if state then state.claimed else false

		local card = Instance.new("Frame")
		card.Name = "QuestCard_" .. qId
		card.Size = UDim2.new(1, -8, 0, 76)
		card.BackgroundColor3 = Theme.Colors.Surface
		card.BorderSizePixel = 0
		card.LayoutOrder = idx
		card.Parent = contentFrame

		local corner = Instance.new("UICorner")
		corner.CornerRadius = Theme.CornerRadius.Medium
		corner.Parent = card

		local title = Instance.new("TextLabel")
		title.Name = "Title"
		title.Position = UDim2.new(0, 12, 0, 8)
		title.Size = UDim2.new(1, -150, 0, 22)
		title.BackgroundTransparency = 1
		title.Font = Theme.Fonts.Heading
		title.TextColor3 = Theme.Colors.TextPrimary
		title.TextSize = 16
		title.TextXAlignment = Enum.TextXAlignment.Left
		title.Text = string.format("%s (%d/%d)", def.title, math.min(progress, target), target)
		title.Parent = card

		local desc = Instance.new("TextLabel")
		desc.Name = "Description"
		desc.Position = UDim2.new(0, 12, 0, 32)
		desc.Size = UDim2.new(1, -150, 0, 34)
		desc.BackgroundTransparency = 1
		desc.Font = Theme.Fonts.Body
		desc.TextColor3 = Theme.Colors.TextSecondary
		desc.TextSize = 13
		desc.TextWrapped = true
		desc.TextXAlignment = Enum.TextXAlignment.Left
		desc.Text = string.format("%s | Награда: %d %s, %d XP", def.description, def.rewardAmount, def.rewardCurrency, def.rewardXP)
		desc.Parent = card

		local claimBtn = Instance.new("TextButton")
		claimBtn.Name = "ClaimButton"
		claimBtn.AnchorPoint = Vector2.new(1, 0.5)
		claimBtn.Position = UDim2.new(1, -12, 0.5, 0)
		claimBtn.Size = UDim2.new(0, 120, 0, 40)
		claimBtn.BackgroundColor3 = if claimed
			then Theme.Colors.SurfaceLight
			elseif completed then Theme.Colors.Success
			else Theme.Colors.Primary
		claimBtn.Font = Theme.Fonts.Heading
		claimBtn.TextColor3 = Theme.Colors.TextPrimary
		claimBtn.TextSize = 14
		claimBtn.Text = if claimed then "CLAIMED" elseif completed then "CLAIM!" else "IN PROGRESS"
		claimBtn.Active = completed and not claimed
		claimBtn.Parent = card

		local btnCorner = Instance.new("UICorner")
		btnCorner.CornerRadius = Theme.CornerRadius.Small
		btnCorner.Parent = claimBtn

		claimBtn.Activated:Connect(function()
			if completed and not claimed then
				onClaimQuest(qId)
			end
		end)
	end
end

return QuestsView
