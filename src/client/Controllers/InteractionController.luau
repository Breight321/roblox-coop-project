--!strict
--[[
	@module InteractionController
	@owner Agent 2 (anarugod)
	@description Контроллер ввода игрока и клиентских намерений: клики симулятора, покупки, экипировка, ребирты и квесты.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Core"):WaitForChild("Types"))
local Logger = require(Shared:WaitForChild("Core"):WaitForChild("Logger"))
local Signal = require(Shared:WaitForChild("Core"):WaitForChild("Signal"))
local Network = require(Shared:WaitForChild("Core"):WaitForChild("Network"))
local GameConfig = require(Shared:WaitForChild("Config"):WaitForChild("GameConfig"))

local InteractionController = {
	Name = "InteractionController",
	Dependencies = { "UIController", "WorldController", "AudioController", "AnimationController" },
	OnPrimaryActionTriggered = Signal.new(),
}

local log = Logger.new("InteractionController")
local uiController: any = nil
local worldController: any = nil
local audioController: any = nil
local animationController: any = nil

local interactionEnabled = true
local lastClickClock = 0
local rbxConnections: { RBXScriptConnection } = {}
local signalConnections: { Signal.SignalConnection } = {}

function InteractionController:Init(registry: any): ()
	uiController = registry:Get("UIController")
	worldController = registry:Get("WorldController")
	audioController = registry:Get("AudioController")
	animationController = registry:Get("AnimationController")
	log:Info("Initialized InteractionController")
end

function InteractionController:Start(): ()
	table.insert(
		signalConnections,
		uiController.OnPrimaryClickRequested:Connect(function()
			self:TriggerPrimaryAction()
		end)
	)

	table.insert(
		rbxConnections,
		UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
			if gameProcessed then
				return
			end
			if
				input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch
				or input.KeyCode == Enum.KeyCode.ButtonR2
			then
				if uiController:GetActiveScreen() == nil then
					self:TriggerPrimaryAction()
				end
			end
		end)
	)

	log:Info("Started InteractionController")
end

function InteractionController:TriggerPrimaryAction(): Types.Result<boolean, string>
	if not interactionEnabled then
		return Types.Err("INTERACTION_DISABLED")
	end

	local now = os.clock()
	if (now - lastClickClock) < GameConfig.Simulator.ClickCooldownSeconds then
		return Types.Err("CLICK_COOLDOWN")
	end
	lastClickClock = now

	local equippedToolUid = worldController:GetEquippedToolUid()
	audioController:PlaySFX("Click", 0.08)
	animationController:PlayActionAnimation("SimulatorSwing")
	Network.FireServer(Network.Events.RequestActionClick, equippedToolUid)
	self.OnPrimaryActionTriggered:Fire(equippedToolUid)

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
