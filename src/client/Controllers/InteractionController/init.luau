--!strict
--[[
	@module InteractionController
	@owner Agent B (anarugod)
	@description Универсальный переиспользуемый контроллер интеракций и ввода: регистрация произвольных игровых действий, кулдауны, хоткеи окон и сетевые намерения.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Core"):WaitForChild("Types"))
local Logger = require(Shared:WaitForChild("Core"):WaitForChild("Logger"))
local Signal = require(Shared:WaitForChild("Core"):WaitForChild("Signal"))
local Network = require(Shared:WaitForChild("Core"):WaitForChild("Network"))
local GameConfig = require(Shared:WaitForChild("Config"):WaitForChild("GameConfig"))

local InteractionTypes = require(script:WaitForChild("Types"))
local InteractionConfig = require(script:WaitForChild("Config"))

local InteractionController = {
	Name = "InteractionController",
	Dependencies = { "UIController", "WorldController", "AudioController", "AnimationController" },
	OnPrimaryActionTriggered = Signal.new(),
	OnActionTriggered = Signal.new(),
}

local log = Logger.new("InteractionController")
local uiController: any = nil
local worldController: any = nil
local audioController: any = nil
local animationController: any = nil

local interactionEnabled = true
local lastClickClock = 0
local registeredActions: { [string]: InteractionTypes.ActionDefinition } = {}
local actionLastClock: { [string]: number } = {}
local windowHotkeys: { [Enum.KeyCode]: string } = table.clone(InteractionConfig.DefaultWindowHotkeys)

local rbxConnections: { RBXScriptConnection } = {}
local signalConnections: { Signal.SignalConnection } = {}

function InteractionController:Init(registry: any): ()
	uiController = registry:TryGet("UIController")
	worldController = registry:TryGet("WorldController")
	audioController = registry:TryGet("AudioController")
	animationController = registry:TryGet("AnimationController")
	log:Info("Initialized InteractionController")
end

function InteractionController:Start(): ()
	if uiController and uiController.OnPrimaryClickRequested then
		table.insert(
			signalConnections,
			uiController.OnPrimaryClickRequested:Connect(function()
				self:TriggerPrimaryAction()
			end)
		)
	end

	table.insert(
		rbxConnections,
		UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
			if gameProcessed then
				return
			end

			for _, closeKey in ipairs(InteractionConfig.CloseModalKeyCodes) do
				if input.KeyCode == closeKey then
					if uiController and uiController:IsAnyWindowOpen() then
						uiController:CloseAllScreens()
					end
					return
				end
			end

			local hotkeyScreen = windowHotkeys[input.KeyCode]
			if hotkeyScreen and uiController then
				uiController:ToggleScreen(hotkeyScreen)
				return
			end

			-- Check custom registered actions
			for actionId, actionDef in pairs(registeredActions) do
				local matched = false
				if actionDef.keyCodes then
					for _, kc in ipairs(actionDef.keyCodes) do
						if input.KeyCode == kc then
							matched = true
							break
						end
					end
				end
				if not matched and actionDef.userInputTypes then
					for _, uit in ipairs(actionDef.userInputTypes) do
						if input.UserInputType == uit then
							matched = true
							break
						end
					end
				end
				if matched then
					self:TriggerAction(actionId)
					return
				end
			end

			if
				input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch
				or input.KeyCode == Enum.KeyCode.ButtonR2
			then
				local anyModalOpen = if uiController then uiController:IsAnyWindowOpen() else false
				if not anyModalOpen then
					self:TriggerPrimaryAction()
				end
			end
		end)
	)

	log:Info("Started InteractionController")
end

function InteractionController:RegisterAction(
	actionDef: InteractionTypes.ActionDefinition
): Types.Result<boolean, InteractionTypes.InteractionErrorCode>
	if type(actionDef) ~= "table" or type(actionDef.id) ~= "string" or #actionDef.id == 0 then
		return Types.Err("INVALID_ACTION_DEF")
	end
	if registeredActions[actionDef.id] ~= nil then
		return Types.Err("ACTION_ALREADY_REGISTERED")
	end
	registeredActions[actionDef.id] = table.clone(actionDef)
	return Types.Ok(true)
end

function InteractionController:UnregisterAction(actionId: string): boolean
	if registeredActions[actionId] == nil then
		return false
	end
	registeredActions[actionId] = nil
	actionLastClock[actionId] = nil
	return true
end

function InteractionController:TriggerAction(
	actionId: string,
	...: any
): Types.Result<boolean, InteractionTypes.InteractionErrorCode>
	if not interactionEnabled then
		return Types.Err("INTERACTION_DISABLED")
	end

	local actionDef = registeredActions[actionId]
	if not actionDef then
		return Types.Err("UNKNOWN_ACTION")
	end

	if not actionDef.allowWhenModalOpen and uiController and uiController:IsAnyWindowOpen() then
		return Types.Err("MODAL_BLOCKED")
	end

	local cooldown = actionDef.cooldownSeconds or InteractionConfig.DefaultActionCooldownSeconds
	local now = os.clock()
	local last = actionLastClock[actionId] or 0
	if cooldown > 0 and (now - last) < cooldown then
		return Types.Err("ACTION_COOLDOWN")
	end
	actionLastClock[actionId] = now

	if actionDef.callback then
		actionDef.callback(actionId, ...)
	end
	self.OnActionTriggered:Fire(actionId, ...)
	return Types.Ok(true)
end

function InteractionController:BindWindowHotkey(keyCode: Enum.KeyCode, windowName: string): ()
	windowHotkeys[keyCode] = windowName
end

function InteractionController:UnbindWindowHotkey(keyCode: Enum.KeyCode): ()
	windowHotkeys[keyCode] = nil
end

function InteractionController:TriggerPrimaryAction(): Types.Result<boolean, string>
	if not interactionEnabled then
		return Types.Err("INTERACTION_DISABLED")
	end

	local cooldown = if GameConfig.Simulator
		then GameConfig.Simulator.ClickCooldownSeconds
		else InteractionConfig.DefaultActionCooldownSeconds
	local now = os.clock()
	if (now - lastClickClock) < cooldown then
		return Types.Err("CLICK_COOLDOWN")
	end
	lastClickClock = now

	local equippedToolUid = if worldController then worldController:GetEquippedToolUid() else nil
	if audioController then
		audioController:PlaySFX("Click", 0.08)
	end
	if animationController then
		animationController:PlayActionAnimation("SimulatorSwing")
	end
	Network.FireServer(Network.Events.RequestActionClick, equippedToolUid)
	self.OnPrimaryActionTriggered:Fire(equippedToolUid)
	self.OnActionTriggered:Fire("PrimaryAction", equippedToolUid)

	return Types.Ok(true)
end

function InteractionController:SetInteractionEnabled(enabled: boolean): ()
	interactionEnabled = enabled
end

function InteractionController:IsInteractionEnabled(): boolean
	return interactionEnabled
end

function InteractionController:RequestShopPurchase(shopItemId: string): ()
	if type(shopItemId) ~= "string" or #shopItemId == 0 then
		return
	end
	Network.FireServer(Network.Events.RequestShopPurchase, shopItemId)
end

function InteractionController:RequestEquipItem(itemUid: string, equip: boolean): ()
	if type(itemUid) ~= "string" or #itemUid == 0 then
		return
	end
	Network.FireServer(Network.Events.RequestEquipItem, itemUid, equip)
end

function InteractionController:RequestRebirth(): ()
	Network.FireServer(Network.Events.RequestRebirth)
end

function InteractionController:RequestClaimQuest(questId: string): ()
	if type(questId) ~= "string" or #questId == 0 then
		return
	end
	Network.FireServer(Network.Events.RequestClaimQuest, questId)
end

function InteractionController:ResetStateForTests(): ()
	interactionEnabled = true
	lastClickClock = 0
	table.clear(registeredActions)
	table.clear(actionLastClock)
	windowHotkeys = table.clone(InteractionConfig.DefaultWindowHotkeys)
end

function InteractionController:Shutdown(): ()
	for _, conn in ipairs(rbxConnections) do
		conn:Disconnect()
	end
	table.clear(rbxConnections)

	for _, conn in ipairs(signalConnections) do
		conn:Disconnect()
	end
	table.clear(signalConnections)
	log:Info("Shutdown InteractionController")
end

return InteractionController
