--!strict
--[[
	@module ShopUI
	@owner Agent B (anarugod)
	@description Независимый модульный Shop UI: категории товаров, отображение баланса, состояния Loading/Success/Error, проверка средств и безопасная отправка запросов на сервер.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local SharedTypes = require(Shared:WaitForChild("Core"):WaitForChild("Types"))
local Signal = require(Shared:WaitForChild("Core"):WaitForChild("Signal"))
local ShopConfig = require(Shared:WaitForChild("Config"):WaitForChild("ShopConfig"))
local ItemsConfig = require(Shared:WaitForChild("Config"):WaitForChild("ItemsConfig"))

local Theme = require(script.Parent:WaitForChild("Theme"))
local ShopUITypes = require(script:WaitForChild("Types"))
local ShopUIConfig = require(script:WaitForChild("Config"))

export type ShopUIInstance = {
	OnPurchaseRequested: Signal.SignalInstance<string>,
	OnStatusChanged: Signal.SignalInstance<ShopUITypes.ShopUIStatus, string?>,
	OnCategoryChanged: Signal.SignalInstance<ShopUITypes.ShopCategoryId>,
	GetStatus: (self: ShopUIInstance) -> ShopUITypes.ShopUIStatus,
	GetSelectedCategory: (self: ShopUIInstance) -> ShopUITypes.ShopCategoryId,
	GetCategories: (self: ShopUIInstance) -> { ShopUITypes.ShopCategoryDef },
	AddCategory: (self: ShopUIInstance, categoryDef: ShopUITypes.ShopCategoryDef) -> SharedTypes.Result<boolean, string>,
	SelectCategory: (self: ShopUIInstance, categoryId: ShopUITypes.ShopCategoryId) -> SharedTypes.Result<boolean, string>,
	UpdatePlayerContext: (self: ShopUIInstance, context: ShopUITypes.ShopPlayerContext) -> (),
	GetPlayerBalance: (self: ShopUIInstance, currencyId: SharedTypes.CurrencyId) -> number,
	EvaluateOffer: (self: ShopUIInstance, shopItemId: string) -> SharedTypes.Result<ShopUITypes.ShopOfferViewModel, string>,
	GetVisibleOffers: (self: ShopUIInstance) -> { ShopUITypes.ShopOfferViewModel },
	RequestPurchase: (self: ShopUIInstance, shopItemId: string) -> SharedTypes.Result<boolean, string>,
	ResolvePurchase: (self: ShopUIInstance, shopItemId: string?, success: boolean, message: string?) -> (),
	Mount: (self: ShopUIInstance, contentFrame: ScrollingFrame) -> (),
	RefreshView: (self: ShopUIInstance) -> (),
	Destroy: (self: ShopUIInstance) -> (),
}

local CATEGORY_ALIASES: { [string]: string } = {
	Tool = "Tools",
	Tools = "Tools",
	Pet = "Pets",
	Pets = "Pets",
	Consumable = "Boosts",
	Boosts = "Boosts",
}

local function normalizeCategory(rawCategory: string): string
	return CATEGORY_ALIASES[rawCategory] or rawCategory
end

local ShopUI = {}
ShopUI.__index = ShopUI

function ShopUI.new(): ShopUIInstance
	local categories: { ShopUITypes.ShopCategoryDef } = {}
	for _, cat in ipairs(ShopUIConfig.DefaultCategories) do
		table.insert(categories, table.clone(cat))
	end

	local self = setmetatable({
		OnPurchaseRequested = Signal.new(),
		OnStatusChanged = Signal.new(),
		OnCategoryChanged = Signal.new(),
		_status = "Idle" :: ShopUITypes.ShopUIStatus,
		_statusMessage = "Select an item to purchase" :: string,
		_selectedCategory = "All" :: ShopUITypes.ShopCategoryId,
		_categories = categories,
		_pendingShopItemId = nil :: string?,
		_lastRequestClock = 0,
		_itemTransientStates = {} :: { [string]: ShopUITypes.OfferButtonState },
		_context = {
			currencies = { Coins = 0, Gems = 0 },
			rebirths = 0,
			unlockedZones = { spawn_meadow = true },
		} :: ShopUITypes.ShopPlayerContext,
		_contentFrame = nil :: ScrollingFrame?,
	}, ShopUI)

	return (self :: any) :: ShopUIInstance
end

function ShopUI:GetStatus(): ShopUITypes.ShopUIStatus
	return self._status
end

function ShopUI:GetSelectedCategory(): ShopUITypes.ShopCategoryId
	return self._selectedCategory
end

function ShopUI:GetCategories(): { ShopUITypes.ShopCategoryDef }
	local copy = table.clone(self._categories)
	table.sort(copy, function(a, b)
		return a.order < b.order
	end)
	return copy
end

function ShopUI:AddCategory(categoryDef: ShopUITypes.ShopCategoryDef): SharedTypes.Result<boolean, string>
	if type(categoryDef) ~= "table" or type(categoryDef.id) ~= "string" or #categoryDef.id == 0 then
		return SharedTypes.Err("INVALID_CATEGORY_ID")
	end
	local normId = normalizeCategory(categoryDef.id)
	for _, existing in ipairs(self._categories) do
		if existing.id == normId or existing.id == categoryDef.id then
			return SharedTypes.Err("CATEGORY_ALREADY_EXISTS")
		end
	end
	table.insert(self._categories, {
		id = categoryDef.id,
		displayName = categoryDef.displayName or categoryDef.id,
		order = categoryDef.order or (#self._categories + 1),
	})
	self:RefreshView()
	return SharedTypes.Ok(true)
end

function ShopUI:SelectCategory(categoryId: ShopUITypes.ShopCategoryId): SharedTypes.Result<boolean, string>
	local normTarget = if categoryId == "All" then "All" else normalizeCategory(categoryId)
	local matchedId: string? = nil
	for _, cat in ipairs(self._categories) do
		if cat.id == categoryId or cat.id == normTarget then
			matchedId = cat.id
			break
		end
	end
	if not matchedId then
		return SharedTypes.Err("UNKNOWN_CATEGORY")
	end
	self._selectedCategory = matchedId
	self.OnCategoryChanged:Fire(matchedId)
	self:RefreshView()
	return SharedTypes.Ok(true)
end

function ShopUI:UpdatePlayerContext(context: ShopUITypes.ShopPlayerContext): ()
	self._context = {
		currencies = {
			Coins = context.currencies.Coins or 0,
			Gems = context.currencies.Gems or 0,
		},
		rebirths = context.rebirths or 0,
		unlockedZones = table.clone(context.unlockedZones or { spawn_meadow = true }),
	}
	self:RefreshView()
end

function ShopUI:GetPlayerBalance(currencyId: SharedTypes.CurrencyId): number
	return self._context.currencies[currencyId] or 0
end

function ShopUI:EvaluateOffer(shopItemId: string): SharedTypes.Result<ShopUITypes.ShopOfferViewModel, string>
	local shopDef = ShopConfig[shopItemId]
	if not shopDef then
		return SharedTypes.Err("UNKNOWN_SHOP_OFFER")
	end

	local itemDef = ItemsConfig[shopDef.itemId]
	if not itemDef then
		return SharedTypes.Err("UNKNOWN_ITEM_DEF")
	end

	local transient = self._itemTransientStates[shopItemId]
	local buttonState: ShopUITypes.OfferButtonState = "Available"
	local statusText = string.format("%d %s", shopDef.price, shopDef.currencyId)
	local canPurchase = true

	if transient then
		buttonState = transient
		canPurchase = false
		if transient == "Loading" then
			statusText = "BUYING..."
		elseif transient == "Success" then
			statusText = "✓ BOUGHT!"
		elseif transient == "Error" then
			statusText = "✗ ERROR"
		end
	elseif self._status == "Loading" then
		canPurchase = false
	else
		local reqRebirths = shopDef.requiredRebirths or 0
		local reqZone = shopDef.requiredZoneId
		local balance = self:GetPlayerBalance(shopDef.currencyId)

		if self._context.rebirths < reqRebirths then
			buttonState = "LockedRebirth"
			statusText = string.format("REQ %d REBIRTHS", reqRebirths)
			canPurchase = false
		elseif reqZone and not self._context.unlockedZones[reqZone] then
			buttonState = "LockedZone"
			statusText = "ZONE LOCKED"
			canPurchase = false
		elseif balance < shopDef.price then
			buttonState = "InsufficientFunds"
			statusText = string.format("NEED %d %s", shopDef.price, shopDef.currencyId)
			canPurchase = false
		end
	end

	local vm: ShopUITypes.ShopOfferViewModel = {
		shopItemId = shopItemId,
		itemId = shopDef.itemId,
		displayName = itemDef.displayName,
		description = itemDef.description,
		category = itemDef.category,
		rarity = itemDef.rarity,
		currencyId = shopDef.currencyId,
		price = shopDef.price,
		powerMultiplier = itemDef.powerMultiplier,
		coinMultiplier = itemDef.coinMultiplier,
		buttonState = buttonState,
		statusText = statusText,
		canPurchase = canPurchase,
	}

	return SharedTypes.Ok(vm)
end

function ShopUI:GetVisibleOffers(): { ShopUITypes.ShopOfferViewModel }
	local offers: { ShopUITypes.ShopOfferViewModel } = {}
	local sortedIds: { string } = {}
	for shopId in pairs(ShopConfig) do
		table.insert(sortedIds, shopId)
	end
	table.sort(sortedIds)

	local selectedNorm = if self._selectedCategory == "All" then "All" else normalizeCategory(self._selectedCategory)

	for _, shopId in ipairs(sortedIds) do
		local shopDef = ShopConfig[shopId] :: any
		local evalRes = self:EvaluateOffer(shopId)
		if evalRes.ok and evalRes.value then
			local vm = evalRes.value
			local offerCategory = normalizeCategory(tostring(shopDef.category or vm.category))
			if selectedNorm == "All" or offerCategory == selectedNorm or vm.category == self._selectedCategory then
				table.insert(offers, vm)
			end
		end
	end

	return offers
end

function ShopUI:RequestPurchase(shopItemId: string): SharedTypes.Result<boolean, string>
	if type(shopItemId) ~= "string" or #shopItemId == 0 then
		self:_setStatus("Error", "INVALID_SHOP_ITEM_ID")
		return SharedTypes.Err("INVALID_SHOP_ITEM_ID")
	end

	if self._status == "Loading" or self._pendingShopItemId ~= nil then
		return SharedTypes.Err("PURCHASE_IN_PROGRESS")
	end

	local now = os.clock()
	if (now - self._lastRequestClock) < ShopUIConfig.RequestCooldownSeconds then
		return SharedTypes.Err("RATE_LIMITED")
	end

	local evalRes = self:EvaluateOffer(shopItemId)
	if not evalRes.ok or not evalRes.value then
		self:_setStatus("Error", evalRes.error or "UNKNOWN_SHOP_OFFER")
		return SharedTypes.Err(evalRes.error or "UNKNOWN_SHOP_OFFER")
	end

	local vm = evalRes.value
	if vm.buttonState == "LockedRebirth" then
		self:_setStatus("Error", "INSUFFICIENT_REBIRTHS")
		return SharedTypes.Err("INSUFFICIENT_REBIRTHS")
	elseif vm.buttonState == "LockedZone" then
		self:_setStatus("Error", "ZONE_LOCKED")
		return SharedTypes.Err("ZONE_LOCKED")
	elseif vm.buttonState == "InsufficientFunds" then
		self._itemTransientStates[shopItemId] = "Error"
		self:_setStatus("Error", "INSUFFICIENT_FUNDS")
		self:RefreshView()
		task.delay(ShopUIConfig.FeedbackResetSeconds, function()
			if self._itemTransientStates[shopItemId] == "Error" then
				self._itemTransientStates[shopItemId] = nil
				if self._status == "Error" then
					self:_setStatus("Idle", "Ready")
				end
				self:RefreshView()
			end
		end)
		return SharedTypes.Err("INSUFFICIENT_FUNDS")
	end

	self._lastRequestClock = now
	self._pendingShopItemId = shopItemId
	self._itemTransientStates[shopItemId] = "Loading"
	self:_setStatus("Loading", "Sending purchase request to server...")
	self:RefreshView()

	self.OnPurchaseRequested:Fire(shopItemId)
	return SharedTypes.Ok(true)
end

function ShopUI:ResolvePurchase(shopItemId: string?, success: boolean, message: string?): ()
	local targetId = shopItemId or self._pendingShopItemId
	self._pendingShopItemId = nil

	if success then
		if targetId then
			self._itemTransientStates[targetId] = "Success"
		end
		self:_setStatus("Success", message or "Purchase confirmed!")
	else
		if targetId then
			self._itemTransientStates[targetId] = "Error"
		end
		self:_setStatus("Error", message or "Purchase failed")
	end

	self:RefreshView()

	if targetId then
		task.delay(ShopUIConfig.FeedbackResetSeconds, function()
			self._itemTransientStates[targetId] = nil
			if self._status ~= "Loading" then
				self:_setStatus("Idle", "Ready")
			end
			self:RefreshView()
		end)
	end
end

function ShopUI:_setStatus(status: ShopUITypes.ShopUIStatus, message: string?): ()
	self._status = status
	self._statusMessage = message or ""
	self.OnStatusChanged:Fire(status, message)
end

function ShopUI:Mount(contentFrame: ScrollingFrame): ()
	self._contentFrame = contentFrame
	self:RefreshView()
end

function ShopUI:RefreshView(): ()
	local contentFrame = self._contentFrame
	if not contentFrame then
		return
	end

	for _, child in ipairs(contentFrame:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end

	-- 1. Balance & Status Banner
	local headerBar = Instance.new("Frame")
	headerBar.Name = "ShopBalanceBanner"
	headerBar.Size = UDim2.new(1, -8, 0, 38)
	headerBar.BackgroundColor3 = Theme.Colors.Surface
	headerBar.BorderSizePixel = 0
	headerBar.LayoutOrder = 1
	headerBar.Parent = contentFrame

	local headerCorner = Instance.new("UICorner")
	headerCorner.CornerRadius = Theme.CornerRadius.Small
	headerCorner.Parent = headerBar

	local balanceLabel = Instance.new("TextLabel")
	balanceLabel.Name = "BalanceText"
	balanceLabel.Position = UDim2.new(0, 12, 0, 0)
	balanceLabel.Size = UDim2.new(0.55, -12, 1, 0)
	balanceLabel.BackgroundTransparency = 1
	balanceLabel.Font = Theme.Fonts.Heading
	balanceLabel.TextColor3 = Theme.Colors.Coins
	balanceLabel.TextSize = 14
	balanceLabel.TextXAlignment = Enum.TextXAlignment.Left
	balanceLabel.Text = string.format(
		"💰 Coins: %d   |   💎 Gems: %d",
		math.floor(self:GetPlayerBalance("Coins")),
		math.floor(self:GetPlayerBalance("Gems"))
	)
	balanceLabel.Parent = headerBar

	local statusLabel = Instance.new("TextLabel")
	statusLabel.Name = "StatusText"
	statusLabel.Position = UDim2.new(0.55, 0, 0, 0)
	statusLabel.Size = UDim2.new(0.45, -12, 1, 0)
	statusLabel.BackgroundTransparency = 1
	statusLabel.Font = Theme.Fonts.Body
	statusLabel.TextSize = 13
	statusLabel.TextXAlignment = Enum.TextXAlignment.Right
	statusLabel.TextColor3 = if self._status == "Error"
		then Theme.Colors.Error
		elseif self._status == "Success" then Theme.Colors.Success
		elseif self._status == "Loading" then Theme.Colors.Warning
		else Theme.Colors.TextSecondary
	statusLabel.Text = string.format("[%s] %s", self._status:upper(), self._statusMessage)
	statusLabel.Parent = headerBar

	-- 2. Category Tabs Bar
	local tabsBar = Instance.new("Frame")
	tabsBar.Name = "CategoryTabs"
	tabsBar.Size = UDim2.new(1, -8, 0, 34)
	tabsBar.BackgroundTransparency = 1
	tabsBar.LayoutOrder = 2
	tabsBar.Parent = contentFrame

	local tabsLayout = Instance.new("UIListLayout")
	tabsLayout.FillDirection = Enum.FillDirection.Horizontal
	tabsLayout.Padding = UDim.new(0, 8)
	tabsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	tabsLayout.Parent = tabsBar

	for idx, cat in ipairs(self:GetCategories()) do
		local tabBtn = Instance.new("TextButton")
		tabBtn.Name = "Tab_" .. cat.id
		tabBtn.Size = UDim2.new(0, 105, 1, 0)
		tabBtn.BackgroundColor3 = if self._selectedCategory == cat.id
			then Theme.Colors.Primary
			else Theme.Colors.SurfaceLight
		tabBtn.Font = Theme.Fonts.Heading
		tabBtn.TextColor3 = Theme.Colors.TextPrimary
		tabBtn.TextSize = 13
		tabBtn.Text = cat.displayName
		tabBtn.LayoutOrder = idx
		tabBtn.Parent = tabsBar

		local tabCorner = Instance.new("UICorner")
		tabCorner.CornerRadius = Theme.CornerRadius.Small
		tabCorner.Parent = tabBtn

		tabBtn.Activated:Connect(function()
			self:SelectCategory(cat.id)
		end)
	end

	-- 3. Offer Cards
	local offers = self:GetVisibleOffers()
	for idx, vm in ipairs(offers) do
		local rarityColor = Theme.RarityColors[vm.rarity] or Theme.Colors.Primary

		local card = Instance.new("Frame")
		card.Name = "ShopCard_" .. vm.shopItemId
		card.Size = UDim2.new(1, -8, 0, 76)
		card.BackgroundColor3 = Theme.Colors.Surface
		card.BorderSizePixel = 0
		card.LayoutOrder = idx + 10
		card.Parent = contentFrame

		local corner = Instance.new("UICorner")
		corner.CornerRadius = Theme.CornerRadius.Medium
		corner.Parent = card

		local stroke = Instance.new("UIStroke")
		stroke.Color = rarityColor
		stroke.Thickness = 1.5
		stroke.Parent = card

		local title = Instance.new("TextLabel")
		title.Name = "Title"
		title.Position = UDim2.new(0, 12, 0, 8)
		title.Size = UDim2.new(1, -160, 0, 22)
		title.BackgroundTransparency = 1
		title.Font = Theme.Fonts.Heading
		title.TextColor3 = Theme.Colors.TextPrimary
		title.TextSize = 16
		title.TextXAlignment = Enum.TextXAlignment.Left
		title.Text = string.format("%s [%s • %s]", vm.displayName, vm.category, vm.rarity)
		title.Parent = card

		local desc = Instance.new("TextLabel")
		desc.Name = "Description"
		desc.Position = UDim2.new(0, 12, 0, 32)
		desc.Size = UDim2.new(1, -160, 0, 36)
		desc.BackgroundTransparency = 1
		desc.Font = Theme.Fonts.Body
		desc.TextColor3 = Theme.Colors.TextSecondary
		desc.TextSize = 13
		desc.TextWrapped = true
		desc.TextXAlignment = Enum.TextXAlignment.Left
		desc.Text = string.format("%s (Coin x%.2f | Power x%.2f)", vm.description, vm.coinMultiplier, vm.powerMultiplier)
		desc.Parent = card

		local buyBtn = Instance.new("TextButton")
		buyBtn.Name = "BuyButton"
		buyBtn.AnchorPoint = Vector2.new(1, 0.5)
		buyBtn.Position = UDim2.new(1, -12, 0.5, 0)
		buyBtn.Size = UDim2.new(0, 132, 0, 42)
		buyBtn.Font = Theme.Fonts.Heading
		buyBtn.TextColor3 = Theme.Colors.TextPrimary
		buyBtn.TextSize = 13
		buyBtn.Text = vm.statusText

		if vm.buttonState == "Available" then
			buyBtn.BackgroundColor3 = Theme.Colors.Success
		elseif vm.buttonState == "Loading" then
			buyBtn.BackgroundColor3 = Theme.Colors.Warning
		elseif vm.buttonState == "Success" then
			buyBtn.BackgroundColor3 = Theme.Colors.Primary
		elseif vm.buttonState == "Error" or vm.buttonState == "InsufficientFunds" then
			buyBtn.BackgroundColor3 = Theme.Colors.Error
		else
			buyBtn.BackgroundColor3 = Theme.Colors.SurfaceLight
		end

		buyBtn.Parent = card

		local btnCorner = Instance.new("UICorner")
		btnCorner.CornerRadius = Theme.CornerRadius.Small
		btnCorner.Parent = buyBtn

		buyBtn.Activated:Connect(function()
			self:RequestPurchase(vm.shopItemId)
		end)
	end
end

function ShopUI:Destroy(): ()
	self._contentFrame = nil
	self.OnPurchaseRequested:Destroy()
	self.OnStatusChanged:Destroy()
	self.OnCategoryChanged:Destroy()
end

return ShopUI
