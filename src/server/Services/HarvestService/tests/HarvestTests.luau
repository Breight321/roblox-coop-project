--!strict
--[[
	@module HarvestTests
	@owner Agent A (Breight321)
	@description Серверные модульные и интеграционные тесты вертикального среза "Sunforge Expedition" (HarvestService) через штатный TestRunner.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local TestRunner = require(Shared:WaitForChild("Core"):WaitForChild("TestRunner"))
local HarvestConfig = require(Shared:WaitForChild("Config"):WaitForChild("HarvestConfig"))

local Services = ServerScriptService:WaitForChild("Server"):WaitForChild("Services")
local PlayerDataService = require(Services:WaitForChild("PlayerDataService"))
local EconomyService = require(Services:WaitForChild("EconomyService"))
local HarvestService = require(Services:WaitForChild("HarvestService"))

local HarvestTests = {}

function HarvestTests.RunAll(): TestRunner.SuiteSummary
	local cases: { TestRunner.TestCase } = {
		{
			name = "HarvestService: enforces distance, cooldown, and bag capacity limits",
			fn = function()
				HarvestService:ResetServerProgressForTests()
				local craterPos = HarvestConfig.ExtractionZones.sunforge_crater.centerPosition
				local mockPlayer: any = {
					UserId = 991001,
					Name = "HarvestTester1",
					Position = craterPos + Vector3.new(200, 0, 0), -- далеко за пределами радиуса (45)
				}
				PlayerDataService:CreateSessionForTest(mockPlayer)

				-- 1. Слишком далеко от зоны -> OUT_OF_ZONE_RANGE
				local farRes = HarvestService:HarvestFromNode(mockPlayer, "sunforge_crater")
				TestRunner.Assert(not farRes.ok, "Harvest outside zone radius must fail")
				TestRunner.AssertEqual(farRes.error, "OUT_OF_ZONE_RANGE", "Expected OUT_OF_ZONE_RANGE")

				-- 2. Входим в зону -> успешная добыча (+2 при Tool Level 1)
				mockPlayer.Position = craterPos + Vector3.new(5, 0, 0)
				local okRes = HarvestService:HarvestFromNode(mockPlayer, "sunforge_crater")
				TestRunner.Assert(okRes.ok and okRes.value ~= nil, "Harvest inside zone should succeed")
				local payload = okRes.value :: any
				TestRunner.AssertEqual(payload.addedAmount, 2, "Level 1 tool should harvest 2 shards")
				TestRunner.AssertEqual(payload.bagStored, 2, "Bag should hold 2 shards")

				-- 3. Мгновенный повтор без ожидания cooldown -> HARVEST_COOLDOWN
				local cdRes = HarvestService:HarvestFromNode(mockPlayer, "sunforge_crater")
				TestRunner.Assert(not cdRes.ok, "Immediate harvest must hit cooldown")
				TestRunner.AssertEqual(cdRes.error, "HARVEST_COOLDOWN", "Expected HARVEST_COOLDOWN")

				-- 4. Заполняем сумку до лимита (20) и проверяем BAG_FULL
				for _ = 1, 9 do
					HarvestService:ClearCooldownForTest(mockPlayer)
					local stepRes = HarvestService:HarvestFromNode(mockPlayer, "sunforge_crater")
					TestRunner.Assert(stepRes.ok, "Harvest step should succeed until bag is full")
				end

				HarvestService:ClearCooldownForTest(mockPlayer)
				local fullRes = HarvestService:HarvestFromNode(mockPlayer, "sunforge_crater")
				TestRunner.Assert(not fullRes.ok, "Harvest with full bag must fail")
				TestRunner.AssertEqual(fullRes.error, "BAG_FULL", "Expected BAG_FULL")

				PlayerDataService:RemoveSessionForTest(mockPlayer)
			end,
		},
		{
			name = "HarvestService: validates active deposit station, range, and server coin payout",
			fn = function()
				HarvestService:ResetServerProgressForTests()
				local craterPos = HarvestConfig.ExtractionZones.sunforge_crater.centerPosition
				local stationPos = HarvestConfig.DepositStations.central_refinery.position
				local mockPlayer: any = {
					UserId = 991002,
					Name = "DepositTester",
					Position = stationPos,
				}
				PlayerDataService:CreateSessionForTest(mockPlayer)

				-- 1. Пустая сумка -> BAG_EMPTY
				local emptyRes = HarvestService:DepositAtStation(mockPlayer, "central_refinery")
				TestRunner.Assert(not emptyRes.ok, "Deposit with empty bag must fail")
				TestRunner.AssertEqual(emptyRes.error, "BAG_EMPTY", "Expected BAG_EMPTY")

				-- 2. Добываем 4 единицы ресурса
				mockPlayer.Position = craterPos
				HarvestService:HarvestFromNode(mockPlayer, "sunforge_crater")
				HarvestService:ClearCooldownForTest(mockPlayer)
				HarvestService:HarvestFromNode(mockPlayer, "sunforge_crater")

				-- 3. Попытка сдать на отключённой станции -> STATION_INACTIVE
				mockPlayer.Position = HarvestConfig.DepositStations.dormant_relay.position
				local inactiveRes = HarvestService:DepositAtStation(mockPlayer, "dormant_relay")
				TestRunner.Assert(not inactiveRes.ok, "Inactive station must reject deposit")
				TestRunner.AssertEqual(inactiveRes.error, "STATION_INACTIVE", "Expected STATION_INACTIVE")

				-- 4. Попытка сдать слишком далеко от активной станции -> TOO_FAR_FROM_STATION
				mockPlayer.Position = stationPos + Vector3.new(100, 0, 0)
				local farDeposit = HarvestService:DepositAtStation(mockPlayer, "central_refinery")
				TestRunner.Assert(not farDeposit.ok, "Deposit far from station must fail")
				TestRunner.AssertEqual(farDeposit.error, "TOO_FAR_FROM_STATION", "Expected TOO_FAR_FROM_STATION")

				-- 5. Успешная сдача рядом со станцией -> сумка очищается, начисляются Coins и растёт прогресс сервера
				mockPlayer.Position = stationPos
				local depRes = HarvestService:DepositAtStation(mockPlayer, "central_refinery")
				TestRunner.Assert(depRes.ok and depRes.value ~= nil, "Valid deposit should succeed")
				local depPayload = depRes.value :: any
				TestRunner.AssertEqual(depPayload.depositedAmount, 4, "Should deposit 4 shards")
				TestRunner.AssertEqual(depPayload.coinsEarned, 4, "Should earn 4 Coins at 1.0x rate")
				TestRunner.AssertEqual(depPayload.bagStored, 0, "Bag must be emptied after deposit")
				TestRunner.AssertEqual(EconomyService:GetBalance(mockPlayer, "Coins"), 4, "Player Coins balance should be 4")

				PlayerDataService:RemoveSessionForTest(mockPlayer)
			end,
		},
		{
			name = "HarvestService: validates Tool and Bag upgrades on server and updates stats",
			fn = function()
				HarvestService:ResetServerProgressForTests()
				local mockPlayer: any = {
					UserId = 991003,
					Name = "UpgradeTester",
					Position = HarvestConfig.ExtractionZones.sunforge_crater.centerPosition,
				}
				PlayerDataService:CreateSessionForTest(mockPlayer)

				-- 1. Без монет покупка улучшения должна отклоняться -> INSUFFICIENT_FUNDS
				local noFundsRes = HarvestService:PurchaseUpgrade(mockPlayer, "Tool")
				TestRunner.Assert(not noFundsRes.ok, "Upgrade without coins must fail")
				TestRunner.AssertEqual(noFundsRes.error, "INSUFFICIENT_FUNDS", "Expected INSUFFICIENT_FUNDS")

				-- 2. Начисляем 50 монет и покупаем улучшение сумки (L2 стоит 20) и инструмента (L2 стоит 25)
				EconomyService:AddCurrency(mockPlayer, "Coins", 50, "TestGrant")

				local bagUpRes = HarvestService:PurchaseUpgrade(mockPlayer, "Bag")
				TestRunner.Assert(bagUpRes.ok and bagUpRes.value ~= nil, "Bag upgrade to L2 should succeed")
				TestRunner.AssertEqual((bagUpRes.value :: any).newLevel, 2, "Bag level should be 2")
				TestRunner.AssertEqual(EconomyService:GetBalance(mockPlayer, "Coins"), 30, "Coins after bag upgrade should be 30")

				local toolUpRes = HarvestService:PurchaseUpgrade(mockPlayer, "Tool")
				TestRunner.Assert(toolUpRes.ok and toolUpRes.value ~= nil, "Tool upgrade to L2 should succeed")
				TestRunner.AssertEqual((toolUpRes.value :: any).newLevel, 2, "Tool level should be 2")
				TestRunner.AssertEqual(EconomyService:GetBalance(mockPlayer, "Coins"), 5, "Coins after tool upgrade should be 5")

				-- 3. Проверяем, что новый инструмент добывает 5 ед., а вместимость сумки стала 50
				local harvestRes = HarvestService:HarvestFromNode(mockPlayer, "sunforge_crater")
				TestRunner.Assert(harvestRes.ok and harvestRes.value ~= nil, "Harvest with L2 tool should succeed")
				local hPayload = harvestRes.value :: any
				TestRunner.AssertEqual(hPayload.addedAmount, 5, "L2 tool should harvest 5 shards")
				TestRunner.AssertEqual(hPayload.bagCapacity, 50, "L2 bag capacity should be 50")

				PlayerDataService:RemoveSessionForTest(mockPlayer)
			end,
		},
		{
			name = "HarvestService: advances shared server stage and unlocks Stage 2 extraction zone",
			fn = function()
				HarvestService:ResetServerProgressForTests()
				local amberPos = HarvestConfig.ExtractionZones.amber_canyon.centerPosition
				local mockPlayer: any = {
					UserId = 991004,
					Name = "CoopStageTester",
					Position = amberPos,
				}
				PlayerDataService:CreateSessionForTest(mockPlayer)

				-- 1. На этапе 1 зона amber_canyon (требует Stage 2) заблокирована -> STAGE_LOCKED
				local lockedRes = HarvestService:HarvestFromNode(mockPlayer, "amber_canyon")
				TestRunner.Assert(not lockedRes.ok, "Stage 2 zone must be locked on Stage 1")
				TestRunner.AssertEqual(lockedRes.error, "STAGE_LOCKED", "Expected STAGE_LOCKED")

				-- 2. Повышаем сумку и инструмент и сдаём >= 100 ед., чтобы открыть Stage 2
				EconomyService:AddCurrency(mockPlayer, "Coins", 500, "StageTestSetup")
				HarvestService:PurchaseUpgrade(mockPlayer, "Bag") -- L2 (cap 50)
				HarvestService:PurchaseUpgrade(mockPlayer, "Bag") -- L3 (cap 125)
				HarvestService:PurchaseUpgrade(mockPlayer, "Tool") -- L2 (power 5)
				HarvestService:PurchaseUpgrade(mockPlayer, "Tool") -- L3 (power 12)
				HarvestService:PurchaseUpgrade(mockPlayer, "Tool") -- L4 (power 30)

				mockPlayer.Position = HarvestConfig.ExtractionZones.sunforge_crater.centerPosition
				for _ = 1, 4 do
					HarvestService:ClearCooldownForTest(mockPlayer)
					HarvestService:HarvestFromNode(mockPlayer, "sunforge_crater")
				end

				mockPlayer.Position = HarvestConfig.DepositStations.central_refinery.position
				local depRes = HarvestService:DepositAtStation(mockPlayer, "central_refinery")
				TestRunner.Assert(depRes.ok, "Deposit of 120 shards should succeed")

				local serverProg = HarvestService:GetServerProgress()
				TestRunner.AssertEqual(serverProg.currentStage, 2, "Server should advance to Stage 2 after 120 deposited")
				TestRunner.Assert(
					serverProg.unlockedExtractionZones["amber_canyon"] == true,
					"amber_canyon must be unlocked in Stage 2"
				)

				-- 3. Теперь добыча в amber_canyon должна работать!
				mockPlayer.Position = amberPos
				HarvestService:ClearCooldownForTest(mockPlayer)
				local unlockedHarvest = HarvestService:HarvestFromNode(mockPlayer, "amber_canyon")
				TestRunner.Assert(unlockedHarvest.ok, "Harvest in amber_canyon should succeed once Stage 2 is reached")

				PlayerDataService:RemoveSessionForTest(mockPlayer)
				HarvestService:ResetServerProgressForTests()
			end,
		},
	}

	return TestRunner.RunSuite("SunforgeHarvestBackendSuite", cases)
end

return HarvestTests
