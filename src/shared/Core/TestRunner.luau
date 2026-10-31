--!strict
--[[
	@module TestRunner
	@owner Agent 1 (Breight321) & Agent 2 (anarugod)
	@description Легковесная тестовая среда для проверки модулей и контрактов фреймворка.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Logger = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Core"):WaitForChild("Logger"))

export type TestCase = {
	name: string,
	fn: () -> (),
}

export type TestSummary = {
	total: number,
	passed: number,
	failed: number,
	failures: { string },
}

local TestRunner = {}
local log = Logger.new("TestRunner")

function TestRunner.AssertEqual(actual: any, expected: any, label: string?): ()
	if actual ~= expected then
		error(
			string.format(
				"%s: expected '%s', got '%s'",
				label or "Assertion failed",
				tostring(expected),
				tostring(actual)
			),
			2
		)
	end
end

function TestRunner.AssertTrue(condition: boolean, label: string?): ()
	if not condition then
		error(string.format("%s: expected true, got false", label or "Assertion failed"), 2)
	end
end

function TestRunner.RunSuite(suiteName: string, tests: { TestCase }): TestSummary
	local summary: TestSummary = {
		total = #tests,
		passed = 0,
		failed = 0,
		failures = {},
	}

	log:Info("Running suite '%s' (%d tests)...", suiteName, #tests)
	for _, test in ipairs(tests) do
		local ok, err = pcall(test.fn)
		if ok then
			summary.passed += 1
		else
			summary.failed += 1
			local failMsg = string.format("[%s] %s -> %s", suiteName, test.name, tostring(err))
			table.insert(summary.failures, failMsg)
			log:Error("FAIL: %s", failMsg)
		end
	end

	log:Info(
		"Suite '%s' finished: %d/%d passed (%d failed)",
		suiteName,
		summary.passed,
		summary.total,
		summary.failed
	)
	return summary
end

return TestRunner
