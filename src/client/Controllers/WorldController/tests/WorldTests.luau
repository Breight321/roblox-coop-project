--!strict
--[[
	@module WorldTests
	@owner Agent B (anarugod)
	@description Изолированные модульные тесты для универсального WorldController.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local TestRunner = require(Shared:WaitForChild("Core"):WaitForChild("TestRunner"))
local WorldController = require(script.Parent.Parent)

local WorldTests = {}

function WorldTests.GetTestCases(): { TestRunner.TestCase }
	return {
		{
			name = "WorldController tracks unlocked zones and emits OnZoneEntered on zone transition",
			fn = function()
				WorldController:ResetStateForTests()
				TestRunner.AssertTrue(WorldController:IsZoneUnlocked("spawn_meadow"), "spawn_meadow unlocked by default")
				TestRunner.AssertTrue(not WorldController:IsZoneUnlocked("crystal_cavern"), "crystal_cavern locked initially")

				WorldController:SyncUnlockedZones({
					spawn_meadow = true,
					crystal_cavern = true,
				})
				TestRunner.AssertTrue(WorldController:IsZoneUnlocked("crystal_cavern"), "crystal_cavern unlocked after sync")

				local enteredZone: string? = nil
				local conn = WorldController.OnZoneEntered:Connect(function(zoneId: string)
					enteredZone = zoneId
				end)

				local changed = WorldController:SetCurrentZone("crystal_cavern")
				task.wait()
				TestRunner.AssertTrue(changed, "SetCurrentZone returned true")
				TestRunner.AssertEqual(enteredZone, "crystal_cavern", "OnZoneEntered fired crystal_cavern")
				conn:Disconnect()
				WorldController:ResetStateForTests()
			end,
		},
		{
			name = "WorldController enforces custom RegisterUnlockValidator predicates cleanly",
			fn = function()
				WorldController:ResetStateForTests()
				WorldController:RegisterUnlockValidator("RequiresQuestComplete", function(zoneId: string)
					if zoneId == "volcanic_peaks" then
						return false, "QUEST_NOT_COMPLETED"
					end
					return true, nil
				end)

				local canCrystal = WorldController:CanRequestUnlockZone("crystal_cavern")
				TestRunner.AssertTrue(canCrystal.ok, "crystal_cavern passes custom validator")

				local canVolcano = WorldController:CanRequestUnlockZone("volcanic_peaks")
				TestRunner.AssertTrue(not canVolcano.ok, "volcanic_peaks blocked by custom validator")
				TestRunner.AssertEqual(canVolcano.error, "QUEST_NOT_COMPLETED", "Expected QUEST_NOT_COMPLETED")

				WorldController:UnregisterUnlockValidator("RequiresQuestComplete")
				WorldController:ResetStateForTests()
			end,
		},
	}
end

return WorldTests
