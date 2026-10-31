--!strict
--[[
	@module FrameworkTests
	@owner Shared (Agent 1 & Agent 2)
	@description Автоматические модульные тесты для проверки Core Framework, DAG зависимостей, Signal и Конфигов.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Core"):WaitForChild("Types"))
local Signal = require(Shared:WaitForChild("Core"):WaitForChild("Signal"))
local Registry = require(Shared:WaitForChild("Core"):WaitForChild("Registry"))
local TestRunner = require(Shared:WaitForChild("Core"):WaitForChild("TestRunner"))

local GameConfig = require(Shared:WaitForChild("Config"):WaitForChild("GameConfig"))
local CurrenciesConfig = require(Shared:WaitForChild("Config"):WaitForChild("CurrenciesConfig"))
local ItemsConfig = require(Shared:WaitForChild("Config"):WaitForChild("ItemsConfig"))
local ZonesConfig = require(Shared:WaitForChild("Config"):WaitForChild("ZonesConfig"))

local FrameworkTests = {}

function FrameworkTests.RunAll(): TestRunner.TestSummary
	return TestRunner.RunSuite("CoreFrameworkSuite", {
		{
			name = "Types.Ok and Types.Err construct valid Result objects",
			fn = function()
				local okRes = Types.Ok(42)
				TestRunner.AssertTrue(okRes.ok, "okRes.ok should be true")
				TestRunner.AssertEqual(okRes.value, 42, "okRes.value")

				local errRes = Types.Err("ERR_CODE")
				TestRunner.AssertTrue(not errRes.ok, "errRes.ok should be false")
				TestRunner.AssertEqual(errRes.error, "ERR_CODE", "errRes.error")
			end,
		},
		{
			name = "Signal Connect, Fire, Disconnect work deterministically",
			fn = function()
				local sig = Signal.new()
				local count = 0
				local conn = sig:Connect(function(delta: number)
					count += delta
				end)
				sig:Fire(5)
				task.wait()
				TestRunner.AssertEqual(count, 5, "Signal fired once")
				conn:Disconnect()
				sig:Fire(10)
				task.wait()
				TestRunner.AssertEqual(count, 5, "Signal should not fire after disconnect")
				sig:Destroy()
			end,
		},
		{
			name = "Registry resolves topological dependency order (Init -> Start -> Shutdown)",
			fn = function()
				local reg = Registry.new("Server")
				local events: { string } = {}

				reg:Register({
					Name = "ServiceB",
					Dependencies = { "ServiceA" },
					Init = function()
						table.insert(events, "Init:B")
					end,
					Start = function()
						table.insert(events, "Start:B")
					end,
					Shutdown = function()
						table.insert(events, "Shutdown:B")
					end,
				})

				reg:Register({
					Name = "ServiceA",
					Dependencies = {},
					Init = function()
						table.insert(events, "Init:A")
					end,
					Start = function()
						table.insert(events, "Start:A")
					end,
					Shutdown = function()
						table.insert(events, "Shutdown:A")
					end,
				})

				local initRes = reg:InitAll()
				TestRunner.AssertTrue(initRes.ok, "InitAll succeeded")
				local startRes = reg:StartAll()
				TestRunner.AssertTrue(startRes.ok, "StartAll succeeded")
				reg:ShutdownAll()

				TestRunner.AssertEqual(table.concat(events, ","), "Init:A,Init:B,Start:A,Start:B,Shutdown:B,Shutdown:A")
			end,
		},
		{
			name = "Registry detects circular dependencies and returns Err",
			fn = function()
				local reg = Registry.new("Server")
				reg:Register({
					Name = "CycleA",
					Dependencies = { "CycleB" },
				})
				reg:Register({
					Name = "CycleB",
					Dependencies = { "CycleA" },
				})

				local initRes = reg:InitAll()
				TestRunner.AssertTrue(not initRes.ok, "Circular dependency must fail InitAll")
			end,
		},
		{
			name = "Configs are frozen and contain valid baseline definitions",
			fn = function()
				TestRunner.AssertTrue(table.isfrozen(GameConfig), "GameConfig must be frozen")
				TestRunner.AssertTrue(CurrenciesConfig.Coins ~= nil, "Coins config exists")
				TestRunner.AssertTrue(ItemsConfig.starter_wand ~= nil, "starter_wand exists")
				TestRunner.AssertTrue(ZonesConfig.spawn_meadow ~= nil, "spawn_meadow exists")
			end,
		},
	})
end

return FrameworkTests
