--!strict
--[[
	@module Logger
	@owner Agent 1 (Breight321)
	@description Единая система логирования и стандартизированного вывода ошибок.
]]

export type LogLevel = "DEBUG" | "INFO" | "WARN" | "ERROR"

export type LoggerInstance = {
	Scope: string,
	Debug: (self: LoggerInstance, message: string, ...any) -> (),
	Info: (self: LoggerInstance, message: string, ...any) -> (),
	Warn: (self: LoggerInstance, message: string, ...any) -> (),
	Error: (self: LoggerInstance, message: string, ...any) -> (),
}

local Logger = {}
Logger.__index = Logger
Logger.EnableDebug = true

local function formatMessage(level: LogLevel, scope: string, message: string, ...: any): string
	local formatted = message
	if select("#", ...) > 0 then
		local ok, res = pcall(string.format, message, ...)
		if ok then
			formatted = res
		end
	end
	return string.format("[%s][%s] %s", level, scope, formatted)
end

function Logger.new(scope: string): LoggerInstance
	local self = setmetatable({
		Scope = scope,
	}, Logger)
	return (self :: any) :: LoggerInstance
end

function Logger:Debug(message: string, ...: any): ()
	if not Logger.EnableDebug then
		return
	end
	print(formatMessage("DEBUG", self.Scope, message, ...))
end

function Logger:Info(message: string, ...: any): ()
	print(formatMessage("INFO", self.Scope, message, ...))
end

function Logger:Warn(message: string, ...: any): ()
	warn(formatMessage("WARN", self.Scope, message, ...))
end

function Logger:Error(message: string, ...: any): ()
	warn(formatMessage("ERROR", self.Scope, message, ...))
end

return Logger
