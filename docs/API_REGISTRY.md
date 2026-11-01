# 📘 docs/API_REGISTRY.md — Единый реестр публичных API и сетевых контрактов

> **Статус:** Согласовано между **Agent A (`Breight321`)** и **Agent B (`anarugod`)**.

---

## 1. Общие типы (`src/shared/Core/Types.luau`)

```luau
export type Result<T, E = string> = {
	ok: boolean,
	value: T?,
	error: E?,
}

export type CurrencyId = "Coins" | "Gems"
export type ShopCategory = "Tools" | "Pets" | "Boosts"

export type ShopPurchaseResponse = {
	ok: boolean,
	shopItemId: string,
	itemId: string?,
	itemUid: string?,
	currencyId: CurrencyId?,
	pricePaid: number?,
	newBalance: number?,
	errorCode: string?,
	message: string,
}

export type EconomyTransactionRecord = {
	id: string,
	timestamp: number,
	userId: number,
	currencyId: CurrencyId,
	delta: number,
	balanceBefore: number,
	balanceAfter: number,
	reason: string,
}
```

---

## 2. Сетевые события (`src/shared/Core/Network.luau`)

| Событие (`Network.Events`) | Направление | Аргументы (Payload) | Назначение |
|---|---|---|---|
| `PlayerDataSync` | Server $\rightarrow$ Client | `(profileData: PlayerProfileData)` | Начальная и полная синхронизация чистого профиля игрока |
| `CurrencyUpdated` | Server $\rightarrow$ Client | `(currencyId: CurrencyId, newBalance: number, delta: number)` | Обновление баланса валюты после любой серверной транзакции |
| `InventoryUpdated` | Server $\rightarrow$ Client | `(inventory: { [string]: InventoryItem })` | Полное обновление словаря предметов игрока |
| `ProgressionUpdated` | Server $\rightarrow$ Client | `(level: number, xp: number, rebirths: number, unlockedZones: { [string]: boolean })` | Синхронизация уровня, опыта, ребиртов и открытых зон |
| `QuestUpdated` | Server $\rightarrow$ Client | `(questState: QuestState)` | Обновление прогресса и статуса квеста |
| `ShopPurchaseResult` | Server $\rightarrow$ Client | `(response: ShopPurchaseResponse)` | Подтверждение или отказ покупки для состояний `Loading / Success / Error` в `Shop UI` |
| `Notification` | Server $\rightarrow$ Client | `(notifType: "Success" \| "Warning" \| "Error" \| "Reward", message: string)` | Отображение тост-уведомления на клиенте |
| `RequestActionClick` | Client $\rightarrow$ Server | `(equippedToolUid: string?)` | Запрос на клик симулятора |
| `RequestShopPurchase` | Client $\rightarrow$ Server | `(shopItemId: string)` | Запрос на покупку товара из `ShopConfig` |
| `RequestEquipItem` | Client $\rightarrow$ Server | `(itemUid: string, equip: boolean)` | Запрос на экипировку/снятие предмета |
| `RequestRebirth` | Client $\rightarrow$ Server | `()` | Запрос на выполнение перерождения |
| `RequestUnlockZone` | Client $\rightarrow$ Server | `(zoneId: string)` | Запрос на разблокировку локации |
| `RequestClaimQuest` | Client $\rightarrow$ Server | `(questId: string)` | Запрос на получение награды за квест |

---

## 3. Economy Backend API (`src/server/Services/EconomyService/`) — *Agent A (`Breight321`)*

- **Dependencies:** `{ "PlayerDataService" }`
- **Configuration:** `src/server/Services/EconomyService/Config.luau`, `src/shared/Config/CurrenciesConfig.luau`
- **Types:** `src/server/Services/EconomyService/Types.luau`
- **Public Methods:**
  - `GetBalance(player: Player, currencyId: CurrencyId): number`
  - `CanAfford(player: Player, currencyId: CurrencyId, amount: number): boolean`
  - `ValidateAmount(amount: any): Result<number, EconomyErrorCode>`
  - `AddCurrency(player: Player, currencyId: CurrencyId, amount: number, reason: string?): Result<number, EconomyErrorCode>`
  - `RemoveCurrency(player: Player, currencyId: CurrencyId, amount: number, reason: string?): Result<number, EconomyErrorCode>`
  - `GetMultiplier(player: Player, currencyId: CurrencyId): number`
  - `GetMultiplierBreakdown(player: Player, currencyId: CurrencyId): MultiplierBreakdown`
  - `ProcessSimulatorClick(player: Player, clientToolUid: string?): Result<number, EconomyErrorCode>`
  - `GetTransactionHistory(player: Player): { EconomyTransactionRecord }`
- **Signals:**
  - `OnCurrencyChanged: Signal<Player, CurrencyId, number, number, string?>`
  - `OnSimulatorClickProcessed: Signal<Player, number, string?>`
- **Error Codes (`EconomyErrorCode`):**
  - `"INVALID_PLAYER"` | `"PROFILE_NOT_LOADED"` | `"UNKNOWN_CURRENCY"` | `"INVALID_AMOUNT"` | `"AMOUNT_EXCEEDS_MAX_TRANSACTION"` | `"NEGATIVE_BALANCE_FORBIDDEN"` | `"INSUFFICIENT_FUNDS"` | `"CLICK_COOLDOWN"` | `"RATE_LIMITED"` | `"UPDATE_FAILED"`

---

## 4. Shop Service API (`src/server/Services/ShopService.luau`) — *Agent A (`Breight321`)*

- **Dependencies:** `{ "PlayerDataService", "EconomyService", "InventoryService" }`
- **Public Methods:**
  - `GetCatalog(): { [string]: ShopItemDef }`
  - `GetCatalogByCategory(category: ShopCategory): { ShopItemDef }`
  - `PurchaseItem(player: Player, shopItemId: string): Result<InventoryItem, string>`
- **Signals:**
  - `OnPurchaseCompleted: Signal<Player, string, InventoryItem>`
  - `OnPurchaseFailed: Signal<Player, string, string>`

---

## 5. Client Controllers & Shop UI API (`src/client/`) — *Agent B (`anarugod`)*

- **`UIController`:** `OpenScreen`, `CloseScreen`, `ToggleScreen`, `GetActiveScreen`, `ShowNotification`, `GetClientState`, `OnShopPurchaseResult: Signal<ShopPurchaseResponse>`
- **`WindowManager`:** `Register`, `Open`, `Close`, `Toggle`, `CloseAll`, `GetActiveWindow`
- **`ShopView`:** Отображение категорий, цен, текущего баланса, состояния кнопки `Loading / Success / Error`, отправка `RequestShopPurchase(shopItemId)`.
