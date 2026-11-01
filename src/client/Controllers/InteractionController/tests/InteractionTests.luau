--!strict
--[[
	@module InteractionTests
	@owner Agent B (anarugod)
	@description Изолированные модульные тесты для универсального InteractionController.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local TestRunner = require(Shared:WaitForChild("Core"):WaitForChild("TestRunner"))
local InteractionController = require(script.Parent.Parent)

local InteractionTests = {}

function InteractionTests.GetTestCases(): { TestRunner.TestCase }
	return {
		{
			name = "InteractionController registers custom actions, enforces cooldown, and unregisters cleanly",
			fn = function()
				InteractionController:ResetStateForTests()
				local triggerCount = 0

				local regRes = InteractionController:RegisterAction({
					id = "TestDash",
					cooldownSeconds = 0.5,
					allowWhenModalOpen = true,
					callback = function()
						triggerCount += 1
					end,
				})
				TestRunner.AssertTrue(regRes.ok, "RegisterAction succeeded")

				local dupRes = InteractionController:RegisterAction({
					id = "TestDash",
					cooldownSeconds = 0.5,
				})
				TestRunner.AssertTrue(not dupRes.ok, "Duplicate action registration must fail")
				TestRunner.AssertEqual(dupRes.error, "ACTION_ALREADY_REGISTERED", "Expected ACTION_ALREADY_REGISTERED")

				local trig1 = InteractionController:TriggerAction("TestDash")
				TestRunner.AssertTrue(trig1.ok, "First TriggerAction succeeded")
				TestRunner.AssertEqual(triggerCount, 1, "Callback executed once")

				local trig2 = InteractionController:TriggerAction("TestDash")
				TestRunner.AssertTrue(not trig2.ok, "Immediate second TriggerAction must be rate-limited")
				TestRunner.AssertEqual(trig2.error, "ACTION_COOLDOWN", "Expected ACTION_COOLDOWN")

				local removed = InteractionController:UnregisterAction("TestDash")
				TestRunner.AssertTrue(removed, "UnregisterAction returned true")
				InteractionController:ResetStateForTests()
			end,
		},
		{
			name = "InteractionController blocks actions when SetInteractionEnabled(false)",
			fn = function()
				InteractionController:ResetStateForTests()
				InteractionController:RegisterAction({
					id = "Attack",
					cooldownSeconds = 0,
					allowWhenModalOpen = true,
				})

				InteractionController:SetInteractionEnabled(false)
				local res = InteractionController:TriggerAction("Attack")
				TestRunner.AssertTrue(not res.ok, "Action must fail when disabled")
				TestRunner.AssertEqual(res.error, "INTERACTION_DISABLED", "Expected INTERACTION_DISABLED")

				InteractionController:SetInteractionEnabled(true)
				local res2 = InteractionController:TriggerAction("Attack")
				TestRunner.AssertTrue(res2.ok, "Action succeeds after re-enabling")
				InteractionController:ResetStateForTests()
			end,
		},
	}
end

return InteractionTests
