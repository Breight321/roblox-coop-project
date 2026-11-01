--!strict
--[[
	@module WindowManager
	@owner Agent 2 (anarugod)
	@description Менеджер модальных окон: эксклюзивное открытие (Single Active Modal), переключение, закрытие и события фокуса.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Signal = require(Shared:WaitForChild("Core"):WaitForChild("Signal"))
local WindowComponent = require(script.Parent:WaitForChild("Components"):WaitForChild("WindowComponent"))

export type WindowManagerCallbacks = {
	OnWindowOpened: ((name: string, handle: WindowComponent.WindowHandle) -> ())?,
	OnWindowClosed: ((name: string, handle: WindowComponent.WindowHandle) -> ())?,
}

export type WindowManagerInstance = {
	OnWindowChanged: Signal.SignalInstance<string, boolean>,
	RegisterWindow: (self: WindowManagerInstance, name: string, handle: WindowComponent.WindowHandle) -> (),
	GetWindow: (self: WindowManagerInstance, name: string) -> WindowComponent.WindowHandle?,
	Open: (self: WindowManagerInstance, name: string) -> boolean,
	Close: (self: WindowManagerInstance, name: string) -> boolean,
	CloseAll: (self: WindowManagerInstance) -> (),
	Toggle: (self: WindowManagerInstance, name: string) -> boolean,
	GetActiveWindow: (self: WindowManagerInstance) -> string?,
	IsAnyWindowOpen: (self: WindowManagerInstance) -> boolean,
	Destroy: (self: WindowManagerInstance) -> (),
}

local WindowManager = {}
WindowManager.__index = WindowManager

function WindowManager.new(callbacks: WindowManagerCallbacks?): WindowManagerInstance
	local self = setmetatable({
		OnWindowChanged = Signal.new(),
		_windows = {} :: { [string]: WindowComponent.WindowHandle },
		_activeWindow = nil :: string?,
		_callbacks = callbacks or {},
	}, WindowManager)
	return (self :: any) :: WindowManagerInstance
end

function WindowManager:RegisterWindow(name: string, handle: WindowComponent.WindowHandle): ()
	self._windows[name] = handle
	handle:SetVisible(false)
end

function WindowManager:GetWindow(name: string): WindowComponent.WindowHandle?
	return self._windows[name]
end

function WindowManager:Open(name: string): boolean
	local target = self._windows[name]
	if not target then
		return false
	end

	if self._activeWindow and self._activeWindow ~= name then
		self:Close(self._activeWindow)
	end

	target:SetVisible(true)
	self._activeWindow = name

	if self._callbacks.OnWindowOpened then
		self._callbacks.OnWindowOpened(name, target)
	end

	self.OnWindowChanged:Fire(name, true)
	return true
end

function WindowManager:Close(name: string): boolean
	local target = self._windows[name]
	if not target then
		return false
	end

	target:SetVisible(false)
	if self._activeWindow == name then
		self._activeWindow = nil
	end

	if self._callbacks.OnWindowClosed then
		self._callbacks.OnWindowClosed(name, target)
	end

	self.OnWindowChanged:Fire(name, false)
	return true
end

function WindowManager:CloseAll(): ()
	if self._activeWindow then
		self:Close(self._activeWindow)
	end
	for _, handle in pairs(self._windows) do
		handle:SetVisible(false)
	end
end

function WindowManager:Toggle(name: string): boolean
	if self._activeWindow == name then
		return self:Close(name)
	else
		return self:Open(name)
	end
end

function WindowManager:GetActiveWindow(): string?
	return self._activeWindow
end

function WindowManager:IsAnyWindowOpen(): boolean
	return self._activeWindow ~= nil
end

function WindowManager:Destroy(): ()
	self:CloseAll()
	table.clear(self._windows)
	self.OnWindowChanged:Destroy()
end

return WindowManager
