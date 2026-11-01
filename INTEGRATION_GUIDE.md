# 🔗 INTEGRATION_GUIDE.md — Руководство по интеграции и адаптерам модулей

Этот документ описывает, как модули **Universal Roblox Framework** взаимодействуют друг с другом через публичные контракты и опциональные адаптеры без жёсткой связности (tight coupling).

---

## 1. Золотое правило независимости модулей

Ни один универсальный модуль не должен содержать жёстких зависимостей от необязательных соседних систем:
- **`Economy`** не импортирует `Inventory`, `Items`, `Pets` или `World`.
- **`Inventory`** не импортирует `Pets` или `Shop`.
- **`Data`** не содержит зашитых в код игровых предметов.
- **`Shop`** общается с `Economy` и `Inventory` через публичные интерфейсы и делегаты выдачи товаров.

---

## 2. Паттерн 1: Интеграция `Economy` + `Inventory` / `World` через Multiplier Modifiers

Вместо того чтобы `EconomyService` сам читал инвентарь или зоны игрока, игра (или интеграционный сервис) регистрирует адаптеры множителей при старте:

```luau
-- Интеграция бонусов экипировки с экономикой:
economyService:RegisterMultiplierModifier("EquippedItemsBonus", function(player: Player, currencyId: string)
	if currencyId ~= "Coins" then
		return 1.0
	end
	local multiplier = 1.0
	for _, item in ipairs(inventoryService:GetEquippedItems(player)) do
		local itemDef = ItemsConfig[item.itemId]
		if itemDef and itemDef.coinMultiplier and itemDef.coinMultiplier > 0 then
			multiplier *= itemDef.coinMultiplier
		end
	end
	return multiplier
end)
```
Если в новой игре нет модуля `Inventory`, этот адаптер просто не регистрируется — а `EconomyService` продолжает работать без единого изменения кода!

---

## 3. Паттерн 2: Интеграция `Data` с новыми модулями через `RegisterSchemaSection`

Любой новый модуль (например, `Achievements` или `Pets`) может добавить своё поле в сохраняемый профиль игрока при инициализации (`Init`):

```luau
function AchievementService:Init(registry: any)
	local dataService = registry:Get("PlayerDataService")
	dataService:RegisterSchemaSection("achievements", {})
end
```
При загрузке профиля `PlayerDataService:ReconcileAndSanitize` автоматически гарантирует наличие таблицы `profile.achievements` у каждого игрока.

---

## 4. Паттерн 3: Интеграция `ShopService` + `EconomyService` + `ShopUI`

1. Клиентский модуль `ShopUI` отображает каталог и отправляет на сервер только идентификатор товара:
   `Network.FireServer(Network.Events.RequestShopPurchase, shopItemId)`
2. Серверный `ShopService` проверяет цену и валюту в `ShopConfig`, вызывает `EconomyService:RemoveCurrency(player, currencyId, price, reason)` и выдаёт товар через зарегистрированный обработчик выдачи (`InventoryService:GrantItem` по умолчанию или кастомный `RegisterGrantHandler`).
3. Сервер отправляет клиенту `ShopPurchaseResult(response)`, `CurrencyUpdated` и `Notification`, а `ShopUI` переключает состояние кнопки (`Loading -> Success / Error`).
