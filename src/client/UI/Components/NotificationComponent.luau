--!strict
--[[
	@module NotificationComponent
	@owner Agent 2 (anarugod)
	@description Компонент всплывающих уведомлений (Toasts) для отображения событий сервера и клиента.
]]

local TweenService = game:GetService("TweenService")
local Theme = require(script.Parent.Parent:WaitForChild("Theme"))

export type NotificationType = "Success" | "Warning" | "Error" | "Reward"

local NotificationComponent = {}

local TYPE_COLORS: { [string]: Color3 } = {
	Success = Theme.Colors.Success,
	Warning = Theme.Colors.Warning,
	Error = Theme.Colors.Error,
	Reward = Theme.Colors.Accent,
}

function NotificationComponent.CreateContainer(parent: ScreenGui): Frame
	local container = Instance.new("Frame")
	container.Name = "NotificationContainer"
	container.AnchorPoint = Vector2.new(0.5, 0)
	container.Position = UDim2.new(0.5, 0, 0, 16)
	container.Size = UDim2.new(0, 380, 0, 220)
	container.BackgroundTransparency = 1
	container.Parent = parent

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 8)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Top
	layout.Parent = container

	return container
end

function NotificationComponent.ShowToast(container: Frame, notifType: string, message: string, duration: number?): ()
	local toast = Instance.new("Frame")
	toast.Name = "Toast_" .. notifType
	toast.Size = UDim2.new(1, 0, 0, 42)
	toast.BackgroundColor3 = Theme.Colors.Surface
	toast.BackgroundTransparency = 0.08
	toast.BorderSizePixel = 0
	toast.Parent = container

	local corner = Instance.new("UICorner")
	corner.CornerRadius = Theme.CornerRadius.Medium
	corner.Parent = toast

	local stroke = Instance.new("UIStroke")
	stroke.Color = TYPE_COLORS[notifType] or Theme.Colors.Primary
	stroke.Thickness = 2
	stroke.Parent = toast

	local label = Instance.new("TextLabel")
	label.Name = "Message"
	label.Size = UDim2.new(1, -24, 1, 0)
	label.Position = UDim2.new(0, 12, 0, 0)
	label.BackgroundTransparency = 1
	label.Font = Theme.Fonts.Body
	label.TextColor3 = Theme.Colors.TextPrimary
	label.TextSize = 15
	label.TextWrapped = true
	label.Text = string.format("[%s] %s", notifType:upper(), message)
	label.Parent = toast

	local lifeTime = duration or 3.0
	task.delay(lifeTime, function()
		if toast.Parent then
			local fadeOut = TweenService:Create(
				toast,
				TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0) }
			)
			fadeOut:Play()
			fadeOut.Completed:Wait()
			toast:Destroy()
		end
	end)
end

return NotificationComponent
