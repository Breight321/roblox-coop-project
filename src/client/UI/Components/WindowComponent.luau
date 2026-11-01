--!strict
--[[
	@module WindowComponent
	@owner Agent 2 (anarugod)
	@description Универсальный модульный контейнер для модальных окон (Shop, Inventory, Quests, Rebirth).
]]

local Theme = require(script.Parent.Parent:WaitForChild("Theme"))

export type WindowHandle = {
	Name: string,
	Root: Frame,
	Content: ScrollingFrame,
	SetVisible: (self: WindowHandle, visible: boolean) -> (),
}

local WindowComponent = {}

function WindowComponent.Create(parent: ScreenGui, screenName: string, titleText: string, onClose: () -> ()): WindowHandle
	local root = Instance.new("Frame")
	root.Name = screenName .. "Window"
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Position = UDim2.new(0.5, 0, 0.5, 0)
	root.Size = UDim2.new(0, 520, 0, 380)
	root.BackgroundColor3 = Theme.Colors.Background
	root.BorderSizePixel = 0
	root.Visible = false
	root.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = Theme.CornerRadius.Large
	corner.Parent = root

	local stroke = Instance.new("UIStroke")
	stroke.Color = Theme.Colors.SurfaceLight
	stroke.Thickness = 2
	stroke.Parent = root

	local header = Instance.new("Frame")
	header.Name = "Header"
	header.Size = UDim2.new(1, 0, 0, 48)
	header.BackgroundColor3 = Theme.Colors.Surface
	header.BorderSizePixel = 0
	header.Parent = root

	local headerCorner = Instance.new("UICorner")
	headerCorner.CornerRadius = Theme.CornerRadius.Large
	headerCorner.Parent = header

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, -60, 1, 0)
	title.Position = UDim2.new(0, 18, 0, 0)
	title.BackgroundTransparency = 1
	title.Font = Theme.Fonts.Heading
	title.TextColor3 = Theme.Colors.TextPrimary
	title.TextSize = 20
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = titleText
	title.Parent = header

	local closeButton = Instance.new("TextButton")
	closeButton.Name = "CloseButton"
	closeButton.AnchorPoint = Vector2.new(1, 0.5)
	closeButton.Position = UDim2.new(1, -12, 0.5, 0)
	closeButton.Size = UDim2.new(0, 32, 0, 32)
	closeButton.BackgroundColor3 = Theme.Colors.Error
	closeButton.Font = Theme.Fonts.Heading
	closeButton.TextColor3 = Theme.Colors.TextPrimary
	closeButton.TextSize = 16
	closeButton.Text = "X"
	closeButton.Parent = header

	local closeCorner = Instance.new("UICorner")
	closeCorner.CornerRadius = Theme.CornerRadius.Small
	closeCorner.Parent = closeButton

	closeButton.Activated:Connect(function()
		onClose()
	end)

	local content = Instance.new("ScrollingFrame")
	content.Name = "Content"
	content.Position = UDim2.new(0, 16, 0, 60)
	content.Size = UDim2.new(1, -32, 1, -76)
	content.BackgroundTransparency = 1
	content.BorderSizePixel = 0
	content.ScrollBarThickness = 6
	content.AutomaticCanvasSize = Enum.AutomaticSize.Y
	content.CanvasSize = UDim2.new(0, 0, 0, 0)
	content.Parent = root

	local listLayout = Instance.new("UIListLayout")
	listLayout.Padding = UDim.new(0, 8)
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Parent = content

	local handle: WindowHandle = {
		Name = screenName,
		Root = root,
		Content = content,
		SetVisible = function(_self: WindowHandle, visible: boolean)
			root.Visible = visible
		end,
	}

	return handle
end

return WindowComponent
