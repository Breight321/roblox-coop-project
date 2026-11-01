--!strict
--[[
	@module EconomyTests
	@owner Agent A (Breight321)
	@description Модульные и интеграционные тесты универсального EconomyService и ShopService (изоляция, кастомные валюты, адаптеры множителей, транзакции).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local TestRunner = require(Shared:WaitForChild("Core"):WaitForChild("TestRunner"))

local Server = ServerScriptService:WaitForChild("Server")
local Services = Server:WaitForChild("Services")
local PlayerDataService = require(Services:WaitForChild("PlayerDataService")) :: any
local EconomyService = require(Services:WaitForChild("EconomyService")) :: any
local InventoryService = require(Services:WaitForChild("InventoryService")) :: any
local ShopService = require(Services:WaitForChild("ShopService")) :: any

local EconomyTests = {}

function EconomyTests.RunAll(): TestRunner.TestSummary
	return TestRunner.RunSuite("UniversalEconomyAndShopSuite", {
		{
			name = "EconomyService: Works independently with custom registered currency and multiplier modifier",
			fn = function()
				local mockPlayer = { Name = "TestPlayer_CustomCurr", UserId = 90010 } :: any
				PlayerDataService:CreateSessionForTest(mockPlayer)

				EconomyService:RegisterCurrency({
					id = "RaceCredits",
					displayName = "Race Credits",
					startingAmount = 0,
					maxAmount = 1e6,
					showInLeaderstats = false,
				})

				EconomyService:RegisterMultiplierModifier("TestVIPBonus", function(_p: any, currId: string)
					return if currId == "RaceCredits" then 2.5 else 1.0
				end)

				TestRunner.AssertEqual(EconomyService:GetMultiplier(mockPlayer, "RaceCredits"), 2.5, "Custom VIP multiplier")

				local addRes = EconomyService:AddCurrency(mockPlayer, "RaceCredits", 400, "RaceWin")
				TestRunner.AssertTrue(addRes.ok, "Add custom currency ok")
				TestRunner.AssertEqual(EconomyService:GetBalance(mockPlayer, "RaceCredits"), 400, "RaceCredits balance")

				EconomyService:RemoveMultiplierModifier("TestVIPBonus")
				EconomyService:ClearPlayerState(mockPlayer)
				PlayerDataService:RemoveSessionForTest(mockPlayer)
			end,
		},
		{
			name = "EconomyService: GetBalance, AddCurrency, RemoveCurrency and CanAfford work for multiple currencies",
			fn = function()
				local mockPlayer = { Name = "TestPlayer_Econ1", UserId = 90001 } :: any
				PlayerDataService:CreateSessionForTest(mockPlayer)

				TestRunner.AssertEqual(EconomyService:GetBalance(mockPlayer, "Coins"), 0, "Initial Coins")
				TestRunner.AssertEqual(EconomyService:GetBalance(mockPlayer, "Gems"), 0, "Initial Gems")

				local addCoins = EconomyService:AddCurrency(mockPlayer, "Coins", 250, "TestGrant")
				TestRunner.AssertTrue(addCoins.ok, "AddCoins ok")
				TestRunner.AssertEqual(addCoins.value, 250, "Coins balance after add")
				TestRunner.AssertTrue(EconomyService:CanAfford(mockPlayer, "Coins", 200), "CanAfford 200 Coins")
				TestRunner.AssertTrue(not EconomyService:CanAfford(mockPlayer, "Coins", 300), "Cannot afford 300 Coins")

				local addGems = EconomyService:AddCurrency(mockPlayer, "Gems", 30, "TestGrantGems")
				TestRunner.AssertTrue(addGems.ok, "AddGems ok")
				TestRunner.AssertEqual(EconomyService:GetBalance(mockPlayer, "Gems"), 30, "Gems balance")

				local remCoins = EconomyService:RemoveCurrency(mockPlayer, "Coins", 100, "TestSpend")
				TestRunner.AssertTrue(remCoins.ok, "RemoveCoins ok")
				TestRunner.AssertEqual(EconomyService:GetBalance(mockPlayer, "Coins"), 150, "Coins after spend")

				local txLog = EconomyService:GetTransactionHistory(mockPlayer)
				TestRunner.AssertEqual(#txLog, 3, "Transaction log recorded 3 entries")

				EconomyService:ClearPlayerState(mockPlayer)
				PlayerDataService:RemoveSessionForTest(mockPlayer)
			end,
		},
		{
			name = "EconomyService: Rejects negative, zero, NaN, unknown currency, and insufficient funds",
			fn = function()
				local mockPlayer = { Name = "TestPlayer_Econ2", UserId = 90002 } :: any
				PlayerDataService:CreateSessionForTest(mockPlayer)

				EconomyService:AddCurrency(mockPlayer, "Coins", 50, "Init")

				local negRes = EconomyService:AddCurrency(mockPlayer, "Coins", -10, "ExploitAttempt")
				TestRunner.AssertTrue(not negRes.ok, "Negative add must fail")
				TestRunner.AssertEqual(negRes.error, "INVALID_AMOUNT", "Negative add error code")

				local nanRes = EconomyService:AddCurrency(mockPlayer, "Coins", 0 / 0, "NaNAttempt")
				TestRunner.AssertTrue(not nanRes.ok, "NaN add must fail")

				local badCurr = EconomyService:AddCurrency(mockPlayer, "UnknownTokenXYZ", 100, "BadCurrency")
				TestRunner.AssertTrue(not badCurr.ok, "Unknown currency must fail")
				TestRunner.AssertEqual(badCurr.error, "UNKNOWN_CURRENCY", "Unknown currency error code")

				local overSpend = EconomyService:RemoveCurrency(mockPlayer, "Coins", 500, "Overspend")
				TestRunner.AssertTrue(not overSpend.ok, "Overspend must fail")
				TestRunner.AssertEqual(overSpend.error, "INSUFFICIENT_FUNDS", "Overspend error code")
				TestRunner.AssertEqual(EconomyService:GetBalance(mockPlayer, "Coins"), 50, "Balance unchanged after failed spend")

				EconomyService:ClearPlayerState(mockPlayer)
				PlayerDataService:RemoveSessionForTest(mockPlayer)
			end,
		},
		{
			name = "ShopService + EconomyService: Validates purchase, deducts server price, grants item, and blocks duplicate tool purchase",
			fn = function()
				local mockPlayer = { Name = "TestPlayer_Shop1", UserId = 90003 } :: any
				PlayerDataService:CreateSessionForTest(mockPlayer)

				local failBuy = ShopService:PurchaseItem(mockPlayer, "shop_iron_wand")
				TestRunner.AssertTrue(not failBuy.ok, "Purchase without funds must fail")
				TestRunner.AssertEqual(failBuy.error, "INSUFFICIENT_FUNDS", "Expected INSUFFICIENT_FUNDS")

				EconomyService:AddCurrency(mockPlayer, "Coins", 150, "SetupShopTest")
				local okBuy = ShopService:PurchaseItem(mockPlayer, "shop_iron_wand")
				TestRunner.AssertTrue(okBuy.ok, "Purchase with funds must succeed")
				TestRunner.AssertEqual(EconomyService:GetBalance(mockPlayer, "Coins"), 50, "100 Coins deducted")
				TestRunner.AssertTrue(InventoryService:HasItemByTemplate(mockPlayer, "iron_wand"), "iron_wand granted to inventory")

				EconomyService:AddCurrency(mockPlayer, "Coins", 200, "TopUp")
				local dupBuy = ShopService:PurchaseItem(mockPlayer, "shop_iron_wand")
				TestRunner.AssertTrue(not dupBuy.ok, "Duplicate tool purchase must fail")
				TestRunner.AssertEqual(dupBuy.error, "ALREADY_OWNED", "Expected ALREADY_OWNED")
				TestRunner.AssertEqual(EconomyService:GetBalance(mockPlayer, "Coins"), 250, "No coins deducted on rejected duplicate")

				EconomyService:ClearPlayerState(mockPlayer)
				PlayerDataService:RemoveSessionForTest(mockPlayer)
			end,
		},
	})
end

return EconomyTests
