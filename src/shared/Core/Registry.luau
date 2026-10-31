--!strict
--[[
	@module Registry
	@owner Agent 1 (Breight321)
	@description Загрузчик модулей (Service / Controller) с проверкой циклических зависимостей (DAG) и управлением жизненным циклом.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Types = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Core"):WaitForChild("Types"))
local Logger = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Core"):WaitForChild("Logger"))

export type RegistryInstance = {
	Scope: "Server" | "Client",
	Register: (self: RegistryInstance, moduleDef: Types.LifecycleModule) -> Types.Result<boolean, string>,
	Get: <T>(self: RegistryInstance, name: string) -> T,
	TryGet: <T>(self: RegistryInstance, name: string) -> T?,
	InitAll: (self: RegistryInstance) -> Types.Result<{ string }, string>,
	StartAll: (self: RegistryInstance) -> Types.Result<{ string }, string>,
	ShutdownAll: (self: RegistryInstance) -> (),
}

local Registry = {}
Registry.__index = Registry

function Registry.new(scope: "Server" | "Client"): RegistryInstance
	local self = setmetatable({
		Scope = scope,
		_modules = {} :: { [string]: Types.LifecycleModule },
		_sortedOrder = {} :: { string },
		_initialized = false,
		_started = false,
		_log = Logger.new("Registry:" .. scope),
	}, Registry)
	return (self :: any) :: RegistryInstance
end

function Registry:Register(moduleDef: Types.LifecycleModule): Types.Result<boolean, string>
	if self._initialized then
		return Types.Err("Cannot register modules after InitAll() has run")
	end
	if type(moduleDef) ~= "table" or type(moduleDef.Name) ~= "string" or #moduleDef.Name == 0 then
		return Types.Err("Invalid module definition: missing 'Name'")
	end
	if self._modules[moduleDef.Name] ~= nil then
		return Types.Err(string.format("Duplicate module registration: '%s'", moduleDef.Name))
	end
	self._modules[moduleDef.Name] = moduleDef
	return Types.Ok(true)
end

function Registry:TryGet<T>(name: string): T?
	return (self._modules[name] :: any) :: T?
end

function Registry:Get<T>(name: string): T
	local mod = self._modules[name]
	assert(mod ~= nil, string.format("[Registry:%s] Module '%s' is not registered", self.Scope, name))
	return (mod :: any) :: T
end

function Registry:_resolveOrder(): Types.Result<{ string }, string>
	local inDegree: { [string]: number } = {}
	local dependents: { [string]: { string } } = {}
	local totalCount = 0

	for name in pairs(self._modules) do
		inDegree[name] = 0
		dependents[name] = {}
		totalCount += 1
	end

	for name, mod in pairs(self._modules) do
		local deps = mod.Dependencies or {}
		for _, depName in ipairs(deps) do
			if self._modules[depName] == nil then
				return Types.Err(
					string.format("Module '%s' depends on unregistered module '%s'", name, depName)
				)
			end
			if depName == name then
				return Types.Err(string.format("Module '%s' cannot depend on itself", name))
			end
			inDegree[name] += 1
			table.insert(dependents[depName], name)
		end
	end

	local queue: { string } = {}
	for name, degree in pairs(inDegree) do
		if degree == 0 then
			table.insert(queue, name)
		end
	end
	table.sort(queue)

	local sorted: { string } = {}
	while #queue > 0 do
		local current = table.remove(queue, 1) :: string
		table.insert(sorted, current)

		local nextList = dependents[current]
		table.sort(nextList)
		for _, depUser in ipairs(nextList) do
			inDegree[depUser] -= 1
			if inDegree[depUser] == 0 then
				table.insert(queue, depUser)
			end
		end
	end

	if #sorted ~= totalCount then
		return Types.Err("Circular dependency detected among registered modules!")
	end

	return Types.Ok(sorted)
end

function Registry:InitAll(): Types.Result<{ string }, string>
	if self._initialized then
		return Types.Ok(self._sortedOrder)
	end

	local orderRes = self:_resolveOrder()
	if not orderRes.ok or not orderRes.value then
		self._log:Error("Dependency resolution failed: %s", tostring(orderRes.error))
		return orderRes
	end

	self._sortedOrder = orderRes.value

	for _, name in ipairs(self._sortedOrder) do
		local mod = self._modules[name]
		if type(mod.Init) == "function" then
			local ok, err = pcall(function()
				(mod.Init :: any)(mod, self)
			end)
			if not ok then
				local errMsg = string.format("Failed to Init module '%s': %s", name, tostring(err))
				self._log:Error(errMsg)
				return Types.Err(errMsg)
			end
		end
	end

	self._initialized = true
	self._log:Info("Initialized %d modules in topological order", #self._sortedOrder)
	return Types.Ok(self._sortedOrder)
end

function Registry:StartAll(): Types.Result<{ string }, string>
	if not self._initialized then
		local initRes = self:InitAll()
		if not initRes.ok then
			return initRes
		end
	end

	if self._started then
		return Types.Ok(self._sortedOrder)
	end

	for _, name in ipairs(self._sortedOrder) do
		local mod = self._modules[name]
		if type(mod.Start) == "function" then
			local ok, err = pcall(function()
				(mod.Start :: any)(mod)
			end)
			if not ok then
				local errMsg = string.format("Failed to Start module '%s': %s", name, tostring(err))
				self._log:Error(errMsg)
				return Types.Err(errMsg)
			end
		end
	end

	self._started = true
	self._log:Info("Started %d modules", #self._sortedOrder)
	return Types.Ok(self._sortedOrder)
end

function Registry:ShutdownAll(): ()
	if not self._initialized then
		return
	end
	for i = #self._sortedOrder, 1, -1 do
		local name = self._sortedOrder[i]
		local mod = self._modules[name]
		if mod and type(mod.Shutdown) == "function" then
			local ok, err = pcall(function()
				(mod.Shutdown :: any)(mod)
			end)
			if not ok then
				self._log:Warn("Error shutting down '%s': %s", name, tostring(err))
			end
		end
	end
	self._started = false
	self._initialized = false
	self._log:Info("All modules shut down cleanly")
end

return Registry
