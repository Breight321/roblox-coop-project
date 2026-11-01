--!strict
--[[
	@module AnimationController
	@owner Agent B (anarugod)
	@description Универсальный модуль управления анимациями действий и процедурными UI-эффектами (Effects & Animation Framework).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Logger = require(Shared:WaitForChild("Core"):WaitForChild("Logger"))

export type UIEffectHandler = (targetGui: GuiObject) -> ()

local AnimationController = {
	Name = "AnimationController",
	Dependencies = {} :: { string },
}

local log = Logger.new("AnimationController")
local lastActionExecuted: string? = nil
local customEffects: { [string]: UIEffectHandler } = {}

function AnimationController:Init(_registry: any): ()
	log:Info("Initialized AnimationController")
end

function AnimationController:Start(): ()
	log:Info("Started AnimationController")
end

function AnimationController:RegisterUIEffect(effectName: string, handler: UIEffectHandler): ()
	if type(effectName) == "string" and #effectName > 0 and type(handler) == "function" then
		customEffects[effectName] = handler
	end
end

function AnimationController:PlayActionAnimation(actionName: string): ()
	lastActionExecuted = actionName
	log:Debug("Triggered action animation: %s", actionName)
end

function AnimationController:PlayUIEffect(effectName: string, targetGui: GuiObject): ()
	if not targetGui or not targetGui.Parent then
		return
	end

	local customHandler = customEffects[effectName]
	if customHandler then
		customHandler(targetGui)
		return
	end

	local uiScale = targetGui:FindFirstChildOfClass("UIScale")
	if not uiScale then
		uiScale = Instance.new("UIScale")
		uiScale.Parent = targetGui
	end

	if effectName == "Bounce" or effectName == "Pulse" then
		local shrink = TweenService:Create(
			uiScale,
			TweenInfo.new(0.06, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Scale = 0.92 }
		)
		local expand = TweenService:Create(
			uiScale,
			TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Scale = 1.0 }
		)
		shrink:Play()
		shrink.Completed:Once(function()
			expand:Play()
		end)
	elseif effectName == "PopIn" then
		uiScale.Scale = 0.85
		local pop = TweenService:Create(
			uiScale,
			TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Scale = 1.0 }
		)
		pop:Play()
	end
end

function AnimationController:GetLastActionAnimation(): string?
	return lastActionExecuted
end

function AnimationController:Shutdown(): ()
	lastActionExecuted = nil
	table.clear(customEffects)
	log:Info("Shutdown AnimationController")
end

return AnimationController
