--!strict
--[[
	@module ExpeditionTests
	@owner Agent B (anarugod)
	@description Модульные клиентские тесты первого вертикального среза «Sunforge Expedition» через TestRunner:
	1. Сбор Solar Shards в сумку (RequestHarvest -> HarvestResult / HarvestStateSync) и запрет локальной мутации.
	2. Заполнение сумки (isNearlyFull / isFull) и блокировка сбора при полной сумке (BAG_FULL).
	3. Сдача добычи на станции (RequestDeposit -> DepositResult): состояния BAG_EMPTY -> Loading -> Error + Retry -> Success.
	4. Улучшения инструмента (Tool) и сумки (Bag) через RequestHarvestUpgrade -> HarvestUpgradeResult:
	   проверка InsufficientFunds, Loading, Error + Retry и Success по ценам из HarvestConfig.
	5. Общий прогресс сервера (ServerProgressUpdated) и открытие следующего этапа.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local TestRunner = require(Shared:WaitForChild("Core"):WaitForChild("TestRunner"))
local HarvestConfig = require(Shared:WaitForChild("Config"):WaitForChild("HarvestConfig"))
local ExpeditionController = require(script.Parent.Parent)

local ExpeditionTests = {}

function ExpeditionTests.GetTestCases(): { TestRunner.TestCase }
	return {
		{
			name = "ExpeditionController: RequestHarvest never mutates bag/balance locally and enforces BAG_FULL when full",
			fn = function()
				ExpeditionController:ResetStateForTests()

				local baseCap = HarvestConfig.BagUpgrades[1].capacity -- 20
				local initialBag = ExpeditionController:GetBagState()
				TestRunner.AssertEqual(initialBag.current, 0, "Initial bag current is 0")
				TestRunner.AssertEqual(initialBag.capacity, baseCap, "Initial bag capacity matches HarvestConfig (20)")
				TestRunner.AssertEqual(ExpeditionController:GetBankedBalance(), 0, "Initial banked balance is 0")

				-- Отправляем запрос на добычу: локальные значения НЕ должны измениться до ответа сервера
				local collectRes = ExpeditionController:RequestCollect("sunforge_crater")
				TestRunner.AssertTrue(collectRes.ok, "RequestCollect succeeded")
				local pendingBag = ExpeditionController:GetBagState()
				TestRunner.AssertEqual(
					pendingBag.collectStatus,
					"Loading",
					"Collect status is Loading while waiting for server"
				)
				TestRunner.AssertEqual(pendingBag.current, 0, "Bag current must remain 0 until server confirms")
				TestRunner.AssertEqual(ExpeditionController:GetBankedBalance(), 0, "Banked balance must remain 0")

				-- Сервер подтверждает частичное заполнение сумки (16 / 20 -> 80% isNearlyFull)
				ExpeditionController:ApplyServerHarvestResult({
					ok = true,
					nodeId = "sunforge_crater",
					addedAmount = 16,
					bagStored = 16,
					bagCapacity = baseCap,
					isBagFull = false,
					message = "Harvested 16 Solar Shards",
				})
				local nearlyFullBag = ExpeditionController:GetBagState()
				TestRunner.AssertEqual(nearlyFullBag.current, 16, "Server updated bag to 16")
				TestRunner.AssertTrue(nearlyFullBag.isNearlyFull, "Bag is marked isNearlyFull at 80%")
				TestRunner.AssertTrue(not nearlyFullBag.isFull, "Bag is not yet 100% full")

				-- Сервер подтверждает полное заполнение сумки (20 / 20 -> 100% isFull)
				ExpeditionController:ApplyServerHarvestResult({
					ok = true,
					nodeId = "sunforge_crater",
					addedAmount = 4,
					bagStored = baseCap,
					bagCapacity = baseCap,
					isBagFull = true,
					message = "Bag is full!",
				})
				local fullBag = ExpeditionController:GetBagState()
				TestRunner.AssertEqual(fullBag.current, baseCap, "Server updated bag to 20")
				TestRunner.AssertTrue(fullBag.isFull, "Bag is marked isFull at 20/20")

				-- Попытка сбора при полной сумке должна отклоняться на клиенте с BAG_FULL
				local blockedRes = ExpeditionController:RequestCollect("sunforge_crater")
				TestRunner.AssertTrue(not blockedRes.ok, "Collect must be blocked when bag is full")
				TestRunner.AssertEqual(blockedRes.error, "BAG_FULL", "Expected BAG_FULL error")
				ExpeditionController:ResetStateForTests()
			end,
		},
		{
			name = "ExpeditionController: Deposit Station state machine (BAG_EMPTY -> Loading -> Error + Retry -> Success)",
			fn = function()
				ExpeditionController:ResetStateForTests()
				local baseCap = HarvestConfig.BagUpgrades[1].capacity -- 20

				-- Пустая сумка не может быть сдана
				local emptyDep = ExpeditionController:RequestDeposit("central_refinery")
				TestRunner.AssertTrue(not emptyDep.ok, "Deposit with empty bag must fail")
				TestRunner.AssertEqual(emptyDep.error, "BAG_EMPTY", "Expected BAG_EMPTY")

				-- Сервер начисляет 20 Solar Shards в сумку
				ExpeditionController:ApplyServerHarvestStateSync({
					bagStored = baseCap,
					bagCapacity = baseCap,
					toolLevel = 1,
					toolId = "copper_extractor",
					toolName = "Copper Resonance Pick",
					harvestPower = 2,
					cooldownSeconds = 0.25,
					bagLevel = 1,
					bagId = "canvas_pouch",
					bagName = "Canvas Shard Pouch",
					nextToolPrice = 25,
					nextBagPrice = 20,
					totalHarvested = 20,
					totalDeposited = 0,
				})

				-- Игрок отправляет запрос на сдачу добычи
				local req1 = ExpeditionController:RequestDeposit("central_refinery")
				TestRunner.AssertTrue(req1.ok, "Deposit request sent")
				local loadingBag = ExpeditionController:GetBagState()
				TestRunner.AssertEqual(loadingBag.depositStatus, "Loading", "Deposit status is Loading")
				TestRunner.AssertEqual(loadingBag.current, baseCap, "Bag still holds 20 until server confirms")
				TestRunner.AssertEqual(
					ExpeditionController:GetBankedBalance(),
					0,
					"Banked balance still 0 until server confirms"
				)

				-- Дублирующий клик во время Loading блокируется
				local dupReq = ExpeditionController:RequestDeposit("central_refinery")
				TestRunner.AssertTrue(not dupReq.ok, "Duplicate deposit blocked while Loading")
				TestRunner.AssertEqual(dupReq.error, "DEPOSIT_IN_PROGRESS", "Expected DEPOSIT_IN_PROGRESS")

				-- Сервер возвращает отказ (например, TOO_FAR_FROM_STATION)
				ExpeditionController:ApplyServerDepositResult({
					ok = false,
					stationId = "central_refinery",
					depositedAmount = 0,
					coinsEarned = 0,
					newCoinsBalance = 0,
					bagStored = baseCap,
					bagCapacity = baseCap,
					serverTotalDeposited = 0,
					serverStage = 1,
					errorCode = "TOO_FAR_FROM_STATION",
					message = "Подойдите ближе к Central Sunforge Refinery!",
				})
				local errBag = ExpeditionController:GetBagState()
				TestRunner.AssertEqual(errBag.depositStatus, "Error", "Deposit status is Error after server rejection")
				TestRunner.AssertTrue(errBag.canRetryDeposit, "RetryDeposit is available after error")
				TestRunner.AssertEqual(errBag.current, baseCap, "Bag shards preserved on deposit rejection")

				-- Повторный запрос (RetryDeposit) и подтверждение от сервера
				local retryRes = ExpeditionController:RetryDeposit()
				TestRunner.AssertTrue(retryRes.ok, "RetryDeposit succeeded")
				TestRunner.AssertEqual(ExpeditionController:GetBagState().depositStatus, "Loading", "Status back to Loading")

				ExpeditionController:ApplyServerDepositResult({
					ok = true,
					stationId = "central_refinery",
					depositedAmount = baseCap,
					coinsEarned = 20,
					newCoinsBalance = 120,
					bagStored = 0,
					bagCapacity = baseCap,
					serverTotalDeposited = 60,
					serverStage = 1,
					message = "Deposited 20 Solar Shards for 20 Coins!",
				})

				local finalBag = ExpeditionController:GetBagState()
				TestRunner.AssertEqual(finalBag.depositStatus, "Success", "Deposit status is Success")
				TestRunner.AssertEqual(finalBag.current, 0, "Bag emptied after confirmed deposit")
				TestRunner.AssertEqual(ExpeditionController:GetBankedBalance(), 120, "Banked balance updated to 120")
				TestRunner.AssertEqual(
					ExpeditionController:GetTeamProgress().currentAmount,
					60,
					"Team progress updated to 60"
				)
				ExpeditionController:ResetStateForTests()
			end,
		},
		{
			name = "ExpeditionController: Tool & Bag Upgrades enforce InsufficientFunds and transition Loading -> Error/Retry -> Success",
			fn = function()
				ExpeditionController:ResetStateForTests()

				-- При балансе 10 Монет улучшение инструмента (цена 25 в HarvestConfig.ToolUpgrades[2]) недоступно
				ExpeditionController:ApplyServerCurrencyUpdate("Coins", 10, 10)
				local toolVmLocked = ExpeditionController:GetUpgradeTrack("Tool")
				TestRunner.AssertEqual(
					toolVmLocked.buttonState,
					"InsufficientFunds",
					"Tool buttonState is InsufficientFunds"
				)
				TestRunner.AssertEqual(toolVmLocked.shortageAmount, 15, "Shortage is 15 Coins")

				local failUp = ExpeditionController:RequestUpgrade("Tool")
				TestRunner.AssertTrue(not failUp.ok, "Upgrade blocked on InsufficientFunds")
				TestRunner.AssertEqual(failUp.error, "INSUFFICIENT_FUNDS", "Expected INSUFFICIENT_FUNDS")
				TestRunner.AssertEqual(ExpeditionController:GetBankedBalance(), 10, "Balance untouched at 10")
				TestRunner.AssertEqual(ExpeditionController:GetUpgradeTrack("Tool").level, 1, "Tool level untouched at 1")

				-- Сервер обновляет баланс до 100 Монет
				ExpeditionController:ApplyServerCurrencyUpdate("Coins", 100, 90)
				local toolVmReady = ExpeditionController:GetUpgradeTrack("Tool")
				TestRunner.AssertEqual(toolVmReady.buttonState, "Available", "Tool upgrade is now Available")

				local reqUp = ExpeditionController:RequestUpgrade("Tool")
				TestRunner.AssertTrue(reqUp.ok, "Upgrade request sent")
				TestRunner.AssertEqual(
					ExpeditionController:GetUpgradeTrack("Tool").buttonState,
					"Loading",
					"Tool state is Loading"
				)
				TestRunner.AssertEqual(
					ExpeditionController:GetBankedBalance(),
					100,
					"Balance remains 100 until server confirms"
				)

				-- Сервер возвращает временную ошибку -> проверяем доступность Retry
				ExpeditionController:ApplyServerUpgradeResult({
					ok = false,
					upgradeType = "Tool",
					newLevel = 1,
					pricePaid = 0,
					newCoinsBalance = 100,
					errorCode = "UPDATE_FAILED",
					message = "Temporary error, retry",
				})
				local errVm = ExpeditionController:GetUpgradeTrack("Tool")
				TestRunner.AssertEqual(errVm.buttonState, "Error", "Tool state is Error")
				TestRunner.AssertTrue(errVm.canRetry, "Tool upgrade can be retried")

				-- Повторный запрос и успешный ответ сервера
				local retryUp = ExpeditionController:RetryUpgrade("Tool")
				TestRunner.AssertTrue(retryUp.ok, "RetryUpgrade sent")

				ExpeditionController:ApplyServerUpgradeResult({
					ok = true,
					upgradeType = "Tool",
					newLevel = 2,
					pricePaid = 25,
					newCoinsBalance = 75,
					message = "Upgraded to Sunbronze Drill (Lv. 2)!",
				})
				local upgradedTool = ExpeditionController:GetUpgradeTrack("Tool")
				TestRunner.AssertEqual(upgradedTool.level, 2, "Tool level is now 2")
				TestRunner.AssertEqual(upgradedTool.currentValue, 5, "Tool harvestPower is now 5")
				TestRunner.AssertEqual(ExpeditionController:GetBankedBalance(), 75, "Banked balance is now 75")

				-- Улучшение сумки (Bag): уровень 2 стоит 20 монет и даёт вместимость 50
				local reqBag = ExpeditionController:RequestUpgrade("Bag")
				TestRunner.AssertTrue(reqBag.ok, "Bag upgrade request sent")
				ExpeditionController:ApplyServerUpgradeResult({
					ok = true,
					upgradeType = "Bag",
					newLevel = 2,
					pricePaid = 20,
					newCoinsBalance = 55,
					message = "Upgraded to Reinforced Sun-Satchel (Lv. 2)!",
				})
				TestRunner.AssertEqual(ExpeditionController:GetBagState().capacity, 50, "Bag capacity updated to 50")
				ExpeditionController:ResetStateForTests()
			end,
		},
		{
			name = "ExpeditionController: ServerProgressUpdated tracks team deposits and fires OnStageUnlocked on Stage advance",
			fn = function()
				ExpeditionController:ResetStateForTests()
				local unlockedFired = false
				local conn = ExpeditionController.OnStageUnlocked:Connect(function()
					unlockedFired = true
				end)

				ExpeditionController:ApplyServerProgressUpdated({
					totalDeposited = 60,
					currentStage = 1,
					stageTitle = "Stage I: Awakening the Forge",
					stageDescription = "Deposit 100 to unlock Stage II",
					currentStageTarget = 100,
					previousStageThreshold = 0,
					progressRatio = 0.6,
					stageBonusMultiplier = 1.0,
					unlockedExtractionZones = { sunforge_crater = true },
					isMaxStage = false,
				})
				local prog1 = ExpeditionController:GetTeamProgress()
				TestRunner.AssertEqual(prog1.currentAmount, 60, "Team progress is 60")
				TestRunner.AssertEqual(prog1.targetAmount, 100, "Stage I target is 100")
				TestRunner.AssertTrue(not prog1.isUnlocked, "Stage II not yet unlocked")

				ExpeditionController:ApplyServerProgressUpdated({
					totalDeposited = 110,
					currentStage = 2,
					stageTitle = "Stage II: Amber Canyon Breach",
					stageDescription = "Deposit 500 to unlock Stage III",
					currentStageTarget = 500,
					previousStageThreshold = 100,
					progressRatio = 0.025,
					stageBonusMultiplier = 1.25,
					unlockedExtractionZones = { sunforge_crater = true, amber_canyon = true },
					isMaxStage = false,
				})
				task.wait()
				local prog2 = ExpeditionController:GetTeamProgress()
				TestRunner.AssertEqual(prog2.stageNumber, 2, "Server advanced to Stage 2")
				TestRunner.AssertTrue(prog2.isUnlocked, "Stage progression unlocked")
				TestRunner.AssertTrue(unlockedFired, "OnStageUnlocked signal fired")
				TestRunner.AssertTrue(
					ExpeditionController:IsExtractionZoneUnlocked("amber_canyon"),
					"amber_canyon is now unlocked"
				)

				conn:Disconnect()
				ExpeditionController:ResetStateForTests()
			end,
		},
	}
end

return ExpeditionTests
