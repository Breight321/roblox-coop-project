# 📘 API_REFERENCE.md — Справочник публичных API Universal Roblox Framework

Данный документ описывает стабильные публичные интерфейсы (v1.0.0) базовых переиспользуемых модулей фреймворка.

---

## 1. Модуль `1. Core` (`src/shared/Core/`)

### 1.1 `Registry.luau` — Управление жизненным циклом и зависимостями (DAG)
```luau
local Registry = require(ReplicatedStorage.Shared.Core.Registry)
local serverRegistry = Registry.new("Server")

-- Регистрация модуля
serverRegistry:Register({
	Name = "MyCustomService",
	Dependencies = { "PlayerDataService" },
	Init = function(self, reg)
		self.dataService = reg:Get("PlayerDataService")
	end,
	Start = function(self) end,
	Shutdown = function(self) end,
})

serverRegistry:InitAll()     -- -> Result<{ string }, string>
serverRegistry:StartAll()    -- -> Result<{ string }, string>
serverRegistry:ShutdownAll() -- -> ()
```

### 1.2 `Signal.luau` — Внутрипроцессная шина событий
```luau
local Signal = require(ReplicatedStorage.Shared.Core.Signal)
local onScored = Signal.new()

local conn = onScored:Connect(function(player: Player, points: number)
	print(player.Name, points)
end)
onScored:Fire(player, 10)
conn:Disconnect()
onScored:Destroy()
```

### 1.3 `Logger.luau` и `TestRunner.luau`
- `Logger.new(scope: string)` $\rightarrow$ `:Debug(...)`, `:Info(...)`, `:Warn(...)`, `:Error(...)`
- `TestRunner.RunSuite(suiteName: string, tests: { TestCase }): TestSummary`

---

## 2. Модуль `2. Shared` (`src/shared/Core/Types.luau`, `Network.luau`)

### 2.1 Универсальный тип результата `Result<T, E>`
```luau
local Types = require(ReplicatedStorage.Shared.Core.Types)
local okResult = Types.Ok({ balance = 100 })
local errResult = Types.Err("INSUFFICIENT_FUNDS")
```

### 2.2 `Network.luau` — Сетевой транспорт
- `Network.RegisterEvent(eventName: string): string` — динамическая регистрация пользовательского события для новой игры.
- `Network.BootstrapServer(): ()`
- `Network.FireClient(player: Player, eventName: string, ...: any): ()`
- `Network.FireAllClients(eventName: string, ...: any): ()`
- `Network.FireServer(eventName: string, ...: any): ()`
- `Network.OnServerEvent(eventName: string, handler: (player: Player, ...any) -> ()): RBXScriptConnection`
- `Network.OnClientEvent(eventName: string, handler: (...any) -> ()): RBXScriptConnection`

---

## 3. Модуль `3. Data` (`src/server/Services/PlayerDataService/`)

Универсальный сервис профилей игроков с Session Locking, миграциями и автоматическим `InMemoryStore` fallback для Roblox Studio.

- `RegisterSchemaSection(sectionKey: string, defaultValue: any): ()` — позволяет любой игре или модулю добавить свою секцию данных в профиль игрока без редактирования кода `PlayerDataService`.
- `RegisterMigration(fromVersion: number, migrateFn: (rawProfile: any) -> any): ()` — регистрация функции миграции схемы.
- `GetProfile(player: Player): Result<PlayerProfileData, string>`
- `UpdateProfile(player: Player, mutator: (PlayerProfileData) -> boolean): Result<PlayerProfileData, string>`
- `SaveProfile(player: Player, releaseLock: boolean?): Result<boolean, string>`
- **Signals:** `OnProfileLoaded`, `OnProfileReleasing`

---

## 4. Модуль `4. Economy` (`src/server/Services/EconomyService/`)

Универсальный сервис валют и транзакций. Работает **полностью независимо** от `Inventory`, `Items`, `Pets` и `World`.

- `RegisterCurrency(currencyDef: CurrencyDef, limitRule: CurrencyLimitRule?): ()` — динамическая регистрация новой валюты (например, `"Gold"`, `"Credits"`, `"Mana"`).
- `RegisterMultiplierModifier(modifierId: string, callback: (player: Player, currencyId: CurrencyId) -> number): ()` — подключение внешних бонусов (например, от экипировки или VIP-статуса) без жёсткой зависимости.
- `RemoveMultiplierModifier(modifierId: string): ()`
- `GetBalance(player: Player, currencyId: CurrencyId): number`
- `CanAfford(player: Player, currencyId: CurrencyId, amount: number): boolean`
- `ValidateAmount(currencyId: CurrencyId, amount: any): Result<number, EconomyErrorCode>`
- `AddCurrency(player: Player, currencyId: CurrencyId, amount: number, reason: string?): Result<number, EconomyErrorCode>`
- `RemoveCurrency(player: Player, currencyId: CurrencyId, amount: number, reason: string?): Result<number, EconomyErrorCode>`
- `GetMultiplier(player: Player, currencyId: CurrencyId): number`
- `GetMultiplierBreakdown(player: Player, currencyId: CurrencyId): MultiplierBreakdown`
- `GetTransactionHistory(player: Player): { EconomyTransactionRecord }`
- **Signals:** `OnCurrencyChanged(player, currencyId, newBalance, delta, reason)`

---

## 5. Модуль `5. Inventory` (`src/server/Services/InventoryService/`)

Универсальная система хранения предметов, стекирования (`quantity`) и слотов экипировки. Не зависит от модуля `Pets`.

- `GetInventory(player: Player): { [string]: InventoryItem }`
- `GetItem(player: Player, itemUid: string): InventoryItem?`
- `HasItemByTemplate(player: Player, itemId: string, minQuantity: number?): boolean`
- `GetCapacityInfo(player: Player): InventoryCapacityInfo`
- `GrantItem(player: Player, itemId: string, quantity: number?): Result<InventoryItem, string>`
- `RemoveItem(player: Player, itemUid: string, quantity: number?): Result<boolean, string>`
- `EquipItem(player: Player, itemUid: string, equipped: boolean): Result<InventoryItem, string>`
- `GetEquippedItems(player: Player, category: string?): { InventoryItem }`
- `SetCategoryEquipLimit(category: string, maxEquipped: number): ()`
- **Signals:** `OnItemGranted`, `OnItemRemoved`, `OnEquipmentChanged`

---

## 6. Модули `8. Shop`, `14. Interaction`, `15. UI`, `17. Audio`, `18. Effects`

- **`ShopService` (Server):** `RegisterGrantHandler(category: string, handlerFn)`, `GetCatalog()`, `GetCatalogByCategory(category)`, `PurchaseItem(player, shopItemId)`.
- **`WindowManager` (Client):** `RegisterWindow(name, handle)`, `Open(name)`, `Close(name)`, `Toggle(name)`, `CloseAll()`, `GetActiveWindow()`.
- **`ShopUI` (Client):** `Mount(parent)`, `AddCategory(def)`, `SetActiveCategory(id)`, `UpdatePlayerContext(ctx)`, `ResolvePurchase(shopItemId, ok, msg)`.
- **`AudioController` (Client):** `PlaySFX(name, pitchVariance?)`, `PlayMusic(name)`, `SetMuted(muted)`.
- **`AnimationController` (Client):** `PlayUIEffect(effectName, guiObject)`, `PlayActionAnimation(actionName)`.
