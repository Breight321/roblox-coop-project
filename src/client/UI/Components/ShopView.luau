--!strict
--[[
	@module ShopView
	@owner Agent B (anarugod)
	@description Адаптер обратной совместимости поверх модульного src/client/UI/ShopUI.
]]

local ShopUI = require(script.Parent.Parent:WaitForChild("ShopUI"))

local ShopView = {}

function ShopView.CreateInstance(): ShopUI.ShopUIInstance
	return ShopUI.new()
end

function ShopView.Populate(contentFrame: ScrollingFrame, onPurchaseClicked: (shopItemId: string) -> ()): ShopUI.ShopUIInstance
	local instance = ShopUI.new()
	instance.OnPurchaseRequested:Connect(function(shopItemId: string)
		onPurchaseClicked(shopItemId)
	end)
	instance:Mount(contentFrame)
	return instance
end

return ShopView
