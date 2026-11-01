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

export type CurrencyId = "Coins" | "Gems" | string
export type ShopCategory = "Tools" | "Pets" | "Boosts" | string

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

-- Типы вертикального среза "Sunforge Expedition" (добыча -> сумка -> сдача -> апгрейды -> прогресс сервера)
export type HarvestUpgradeType = "Tool" | "Bag"

export type HarvestErrorCode =
	"INVALID_PLAYER"
	| "PROFILE_NOT_LOADED"
	| "CHARACTER_NOT_READY"
	| "UNKNOWN_EXTRACTION_ZONE"
	| "STAGE_LOCKED"
	| "OUT_OF_ZONE_RANGE"
	| "HARVEST_COOLDOWN"
	| "BAG_FULL"
	| "INVALID_STATION"
	| "STATION_INACTIVE"
	| "TOO_FAR_FROM_STATION"
	| "BAG_EMPTY"
	| "INVALID_UPGRADE_TYPE"
	| "MAX_LEVEL_REACHED"
	| "INSUFFICIENT_FUNDS"
	| "UPDATE_FAILED"

export type PlayerHarvestState = {
	bagStored: number,
	toolLevel: number,
	bagLevel: number,
	totalHarvested: number,
	totalDeposited: number,
}

export type HarvestStatePayload = {
	bagStored: number,
	bagCapacity: number,
	toolLevel: number,
	toolId: string,
	toolName: string,
	harvestPower: number,
	cooldownSeconds: number,
	bagLevel: number,
	bagId: string,
	bagName: string,
	nextToolPrice: number?,
	nextBagPrice: number?,
	totalHarvested: number,
	totalDeposited: number,
}

export type HarvestResultPayload = {
	ok: boolean,
	nodeId: string,
	addedAmount: number,
	bagStored: number,
	bagCapacity: number,
	isBagFull: boolean,
	errorCode: HarvestErrorCode?,
	message: string,
}

export type DepositResultPayload = {
	ok: boolean,
	stationId: string,
	depositedAmount: number,
	coinsEarned: number,
	newCoinsBalance: number,
	bagStored: number,
	bagCapacity: number,
	serverTotalDeposited: number,
	serverStage: number,
	errorCode: HarvestErrorCode?,
	message: string,
}

export type UpgradeResultPayload = {
	ok: boolean,
	upgradeType: HarvestUpgradeType,
	newLevel: number,
	pricePaid: number,
	newCoinsBalance: number,
	harvestState: HarvestStatePayload?,
	errorCode: HarvestErrorCode?,
	message: string,
}

export type ServerProgressPayload = {
	totalDeposited: number,
	currentStage: number,
	stageTitle: string,
	stageDescription: string,
	currentStageTarget: number,
	previousStageThreshold: number,
	progressRatio: number,
	stageBonusMultiplier: number,
	unlockedExtractionZones: { [string]: boolean },
	isMaxStage: boolean,
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
| `HarvestStateSync` | Server $\rightarrow$ Client | `(state: HarvestStatePayload)` | Полная синхронизация состояния сумки, уровня инструмента/сумки и цен следующих апгрейдов |
| `HarvestResult` | Server $\rightarrow$ Client | `(result: HarvestResultPayload)` | Результат попытки добычи в зоне (числовой прирост в сумку, заполненность или код ошибки) |
| `DepositResult` | Server $\rightarrow$ Client | `(result: DepositResultPayload)` | Результат сдачи добычи на станции (сколько сдано, сколько начислено монет, новый прогресс сервера) |
| `HarvestUpgradeResult` | Server $\rightarrow$ Client | `(result: UpgradeResultPayload)` | Результат покупки улучшения инструмента (`"Tool"`) или сумки (`"Bag"`) |
| `ServerProgressUpdated` | Server $\rightarrow$ Client | `(progress: ServerProgressPayload)` | Широковещательное обновление общей цели сервера и открытых этапов/зон |
| `RequestActionClick` | Client $\rightarrow$ Server | `(equippedToolUid: string?)` | Запрос на клик симулятора |
| `RequestShopPurchase` | Client $\rightarrow$ Server | `(shopItemId: string)` | Запрос на покупку товара из `ShopConfig` |
| `RequestEquipItem` | Client $\rightarrow$ Server | `(itemUid: string, equip: boolean)` | Запрос на экипировку/снятие предмета |
| `RequestRebirth` | Client $\rightarrow$ Server | `()` | Запрос на выполнение перерождения |
| `RequestUnlockZone` | Client $\rightarrow$ Server | `(zoneId: string)` | Запрос на разблокировку локации |
| `RequestClaimQuest` | Client $\rightarrow$ Server | `(questId: string)` | Запрос на получение награды за квест |
| `RequestHarvest` | Client $\rightarrow$ Server | `(nodeId: string?)` | Запрос на добычу из общей зоны (расстояние, инструмент, cooldown и место в сумке проверяются на сервере) |
| `RequestDeposit` | Client $\rightarrow$ Server | `(stationId: string?)` | Запрос на сдачу добычи из сумки на станции приёма (сумма рассчитывается строго на сервере) |
| `RequestHarvestUpgrade` | Client $\rightarrow$ Server | `(upgradeType: "Tool" \| "Bag")` | Запрос на покупку следующего уровня инструмента или сумки (цена и баланс проверяются на сервере) |

---

## 3. Economy Backend API (`src/server/Services/EconomyService/`) — *Agent A (`Breight321`)*

- **Dependencies:** `{ "PlayerDataService" }`
- **Configuration:** `src/server/Services/EconomyService/Config.luau`, `src/shared/Config/CurrenciesConfig.luau`
- **Types:** `src/server/Services/EconomyService/Types.luau`
- **Public Methods:**
  - `GetBalance(player: Player, currencyId: CurrencyId): number`
  - `CanAfford(player: Player, currencyId: CurrencyId, amount: number): boolean`
  - `ValidateAmount(currencyId: CurrencyId, amount: any): Result<number, EconomyErrorCode>`
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

## 4. Harvest & Co-op Goal Service API (`src/server/Services/HarvestService/`) — *Agent A (`Breight321`)*

- **Title & World Concept:** **"Sunforge Expedition" (Экспедиция Солнечного Горна)** — кооперативная добыча солнечных осколков из кратеров в переносные ранцы-контейнеры, переплавка на станциях Горна в монеты и совместная зарядка Ядра Сервера для открытия новых зон.
- **Dependencies:** `{ "PlayerDataService", "EconomyService" }`
- **Configuration:** `src/shared/Config/HarvestConfig.luau`
- **Public Methods:**
  - `GetHarvestState(player: Player): Result<HarvestStatePayload, HarvestErrorCode>`
  - `HarvestFromNode(player: Player, nodeId: string?): Result<HarvestResultPayload, HarvestErrorCode>`
  - `DepositAtStation(player: Player, stationId: string?): Result<DepositResultPayload, HarvestErrorCode>`
  - `PurchaseUpgrade(player: Player, upgradeType: HarvestUpgradeType): Result<UpgradeResultPayload, HarvestErrorCode>`
  - `GetServerProgress(): ServerProgressPayload`
  - `ResetServerProgressForTests(): ()`
- **Signals:**
  - `OnResourceHarvested: Signal<Player, HarvestResultPayload>`
  - `OnLootDeposited: Signal<Player, DepositResultPayload>`
  - `OnUpgradePurchased: Signal<Player, UpgradeResultPayload>`
  - `OnServerStageAdvanced: Signal<number, ServerProgressPayload>`

---

## 5. Shop Service API (`src/server/Services/ShopService.luau`) — *Agent A (`Breight321`)*

- **Dependencies:** `{ "PlayerDataService", "EconomyService", "InventoryService" }`
- **Public Methods:**
  - `GetCatalog(): { [string]: ShopItemDef }`
  - `GetCatalogByCategory(category: ShopCategory): { ShopItemDef }`
  - `PurchaseItem(player: Player, shopItemId: string): Result<InventoryItem, string>`
- **Signals:**
  - `OnPurchaseCompleted: Signal<Player, string, InventoryItem>`
  - `OnPurchaseFailed: Signal<Player, string, string>`

---

## 6. Client Controllers & Shop UI API (`src/client/`) — *Agent B (`anarugod`)*

- **`UIController`:** `OpenScreen`, `CloseScreen`, `ToggleScreen`, `GetActiveScreen`, `ShowNotification`, `GetClientState`, `OnShopPurchaseResult: Signal<ShopPurchaseResponse>`
- **`WindowManager`:** `Register`, `Open`, `Close`, `Toggle`, `CloseAll`, `GetActiveWindow`
- **`ShopView`:** Отображение категорий, цен, текущего баланса, состояния кнопки `Loading / Success / Error`, отправка `RequestShopPurchase(shopItemId)`.
