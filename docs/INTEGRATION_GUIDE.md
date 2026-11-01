# 🔗 docs/INTEGRATION_GUIDE.md — Руководство по интеграции модулей (Economy Backend + Shop UI)

## 1. Обзор первой интеграционной связки

Первая сквозная интеграция фреймворка объединяет:
- **Backend (Agent A — `Breight321`):** `PlayerDataService` $\rightarrow$ `EconomyService` $\rightarrow$ `InventoryService` $\rightarrow$ `ShopService`
- **Client (Agent B — `anarugod`):** `InteractionController` $\leftrightarrow$ `UIController` $\leftrightarrow$ `WindowManager` $\leftrightarrow$ `ShopView` / `HUDComponent`

---

## 2. Пошаговый сценарий работы связки Economy + Shop UI

### Шаг 1. Инициализация и синхронизация баланса
1. При входе игрока `PlayerDataService` создаёт или загружает профиль и отправляет `Network.Events.PlayerDataSync(profile)`.
2. Клиентский `UIController` принимает `PlayerDataSync`, кэширует состояние профиля и обновляет `HUDComponent` (баланс `Coins`, `Gems`, `Rebirths`) и `ShopView`.

### Шаг 2. Запрос на покупку товара из `Shop UI`
1. Игрок открывает магазин (`WindowManager:Open("Shop")`) и нажимает кнопку покупки товара `shopItemId` (например, `"shop_iron_wand"`).
2. `ShopView` переводит кнопку в состояние **`Loading`** (блокировка повторного нажатия) и вызывает `InteractionController:RequestShopPurchase(shopItemId)`.
3. `InteractionController` отправляет на сервер событие:
   ```luau
   Network.FireServer(Network.Events.RequestShopPurchase, shopItemId)
   ```
   *(Клиент передаёт **только ID оффера** `shopItemId`. Цена и валюта берутся сервером из `ShopConfig`!).*

### Шаг 3. Серверная валидация и проведение транзакции (`ShopService` + `EconomyService`)
1. `ShopService` проверяет:
   - тип аргумента (`type(shopItemId) == "string"` и длину `<= 64`);
   - анти-спам / защиту от дублирования транзакций (lock на параллельную покупку одного игрока + rate limit);
   - существование товара в `ShopConfig[shopItemId]`;
   - условия `requiredRebirths` и `requiredZoneId`;
   - отсутствие дубликата для уникальных инструментов (`category == "Tool"`);
   - достаточность баланса через `EconomyService:CanAfford(player, offer.currencyId, offer.price)`.
2. Если проверка не пройдена:
   - Сервер отправляет `Network.Events.ShopPurchaseResult(player, { ok = false, shopItemId = shopItemId, errorCode = code, message = msg })` и `Network.Events.Notification(player, "Error", msg)`.
3. Если проверка пройдена:
   - `EconomyService:RemoveCurrency(player, offer.currencyId, offer.price, "ShopPurchase:" .. shopItemId)` списывает средства, записывает транзакцию в журнал и отправляет клиенту `CurrencyUpdated(currencyId, newBalance, -offer.price)`.
   - `InventoryService:GrantItem(player, offer.itemId)` добавляет предмет в инвентарь и отправляет клиенту `InventoryUpdated(inventory)`.
   - Если `GrantItem` вернул ошибку (например, `INVENTORY_FULL`), `ShopService` автоматически возвращает списанную валюту через `EconomyService:AddCurrency` (Rollback!).
   - При успехе сервер отправляет клиенту `ShopPurchaseResult({ ok = true, shopItemId = shopItemId, itemId = offer.itemId, itemUid = item.uid, currencyId = offer.currencyId, pricePaid = offer.price, newBalance = newBalance, message = "..." })` и `Notification("Success", ...)`.

### Шаг 4. Реакция `Shop UI` на ответ сервера
1. При получении `CurrencyUpdated` баланс в `HUDComponent` и `ShopView` мгновенно обновляется.
2. При получении `ShopPurchaseResult` (или `InventoryUpdated` / `Notification`) кнопка в `ShopView` переходит в состояние **`Success`** (например, `"OWNED"` или `"PURCHASED!"`) либо **`Error`** (например, `"NO FUNDS"`), а затем возвращается в исходное состояние.

---

## 3. Как подключить новый сервис или контроллер

1. Создайте модуль в `src/server/Services/` (для сервера) или `src/client/Controllers/` (для клиента), реализующий интерфейс `Types.LifecycleModule` (`Name`, `Dependencies`, `Init`, `Start`, `Shutdown`).
2. Укажите зависимости в массиве `Dependencies`.
3. `init.server.luau` / `init.client.luau` автоматически обнаружит модуль и запустит его в правильном топологическом порядке через `Registry`.
