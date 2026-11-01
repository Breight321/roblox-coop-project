--!strict
--[[
	@module ShopUITests
	@owner Agent B (anarugod)
	@description Модульные тесты для проверки ShopUI: фильтрация категорий, проверка недостатка средств, состояния Loading/Success/Error и неизменность баланса на клиенте.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local TestRunner = require(Shared:WaitForChild("Core"):WaitForChild("TestRunner"))
local ShopUI = require(script.Parent.Parent)

local ShopUITests = {}

function ShopUITests.GetTestCases(): { TestRunner.TestCase }
	return {
		{
			name = "ShopUI evaluates InsufficientFunds and prevents unauthorized balance mutation",
			fn = function()
				local shop = ShopUI.new()
				shop:UpdatePlayerContext({
					currencies = { Coins = 25, Gems = 0 },
					rebirths = 0,
					unlockedZones = { spawn_meadow = true },
				})

				local evalRes = shop:EvaluateOffer("shop_iron_wand")
				TestRunner.AssertTrue(evalRes.ok, "EvaluateOffer succeeded")
				TestRunner.AssertEqual(
					(evalRes.value :: any).buttonState,
					"InsufficientFunds",
					"Button state should be InsufficientFunds when Coins < 100"
				)

				local reqRes = shop:RequestPurchase("shop_iron_wand")
				TestRunner.AssertTrue(not reqRes.ok, "Purchase request must fail on InsufficientFunds")
				TestRunner.AssertEqual(reqRes.error, "INSUFFICIENT_FUNDS", "Expected INSUFFICIENT_FUNDS error")
				TestRunner.AssertEqual(shop:GetPlayerBalance("Coins"), 25, "Client balance must remain untouched (25)")
				shop:Destroy()
			end,
		},
		{
			name = "ShopUI transitions Idle -> Loading -> Success and prevents duplicate requests while Loading",
			fn = function()
				local shop = ShopUI.new()
				shop:UpdatePlayerContext({
					currencies = { Coins = 500, Gems = 50 },
					rebirths = 0,
					unlockedZones = { spawn_meadow = true },
				})

				local firedItemId: string? = nil
				shop.OnPurchaseRequested:Connect(function(shopItemId: string)
					firedItemId = shopItemId
				end)

				local req1 = shop:RequestPurchase("shop_iron_wand")
				TestRunner.AssertTrue(req1.ok, "First purchase request should succeed")
				TestRunner.AssertEqual(shop:GetStatus(), "Loading", "ShopUI status must be Loading")
				task.wait()
				TestRunner.AssertEqual(firedItemId, "shop_iron_wand", "OnPurchaseRequested fired shop_iron_wand")

				-- Duplicate click while Loading must be rejected
				local req2 = shop:RequestPurchase("shop_iron_wand")
				TestRunner.AssertTrue(not req2.ok, "Duplicate purchase during Loading must be rejected")
				TestRunner.AssertEqual(req2.error, "PURCHASE_IN_PROGRESS", "Error must be PURCHASE_IN_PROGRESS")

				-- Server confirms purchase
				shop:ResolvePurchase("shop_iron_wand", true, "Purchased Iron Collector")
				TestRunner.AssertEqual(shop:GetStatus(), "Success", "Status must transition to Success")
				shop:Destroy()
			end,
		},
		{
			name = "ShopUI supports extensible categories and filters offers accurately",
			fn = function()
				local shop = ShopUI.new()
				local allOffers = shop:GetVisibleOffers()
				TestRunner.AssertTrue(#allOffers >= 3, "All category shows all offers")

				shop:SelectCategory("Pet")
				local petOffers = shop:GetVisibleOffers()
				TestRunner.AssertEqual(#petOffers, 1, "Pet category shows exactly 1 pet offer")
				TestRunner.AssertEqual(petOffers[1].shopItemId, "shop_ember_fox_pet", "Pet offer is shop_ember_fox_pet")

				local addRes = shop:AddCategory({ id = "Special", displayName = "Special Offers", order = 99 })
				TestRunner.AssertTrue(addRes.ok, "Custom category added")
				local selRes = shop:SelectCategory("Special")
				TestRunner.AssertTrue(selRes.ok, "Custom category selected")
				TestRunner.AssertEqual(#shop:GetVisibleOffers(), 0, "Empty custom category returns 0 offers")
				shop:Destroy()
			end,
		},
	}
end

return ShopUITests
