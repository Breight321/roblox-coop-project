--!strict
--[[
	@module Signal
	@owner Agent 1 (Breight321)
	@description Легковесная типизированная шина событий для межмодульного взаимодействия.
]]

export type SignalConnection = {
	Connected: boolean,
	Disconnect: (self: SignalConnection) -> (),
}

export type SignalInstance<T...> = {
	Connect: (self: SignalInstance<T...>, callback: (T...) -> ()) -> SignalConnection,
	Once: (self: SignalInstance<T...>, callback: (T...) -> ()) -> SignalConnection,
	Fire: (self: SignalInstance<T...>, T...) -> (),
	Destroy: (self: SignalInstance<T...>) -> (),
}

local Signal = {}
Signal.__index = Signal

function Signal.new<T...>(): SignalInstance<T...>
	local self = setmetatable({
		_listeners = {} :: { [SignalConnection]: (...any) -> () },
		_destroyed = false,
	}, Signal)
	return (self :: any) :: SignalInstance<T...>
end

function Signal:Connect(callback: (...any) -> ()): SignalConnection
	assert(not self._destroyed, "Cannot connect to a destroyed Signal")
	local listeners = self._listeners
	local connection: SignalConnection
	connection = {
		Connected = true,
		Disconnect = function(conn: SignalConnection)
			if conn.Connected then
				conn.Connected = false
				listeners[conn] = nil
			end
		end,
	}
	listeners[connection] = callback
	return connection
end

function Signal:Once(callback: (...any) -> ()): SignalConnection
	local connection: SignalConnection
	connection = self:Connect(function(...: any)
		if connection.Connected then
			connection:Disconnect()
		end
		callback(...)
	end)
	return connection
end

function Signal:Fire(...: any): ()
	if self._destroyed then
		return
	end
	local snapshot = {}
	for conn, fn in pairs(self._listeners) do
		if conn.Connected then
			table.insert(snapshot, fn)
		end
	end
	for _, fn in ipairs(snapshot) do
		task.spawn(fn, ...)
	end
end

function Signal:Destroy(): ()
	self._destroyed = true
	for conn in pairs(self._listeners) do
		conn.Connected = false
	end
	table.clear(self._listeners)
end

return Signal
