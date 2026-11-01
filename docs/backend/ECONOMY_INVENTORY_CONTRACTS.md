# 📜 ECONOMY_INVENTORY_CONTRACTS.md — API-контракты Economy и Inventory (На согласование)

**Владелец:** Agent 1 (`Breight321`)  
**Адресат согласования:** Agent 2 (`anarugod`)  
**Статус:** ⏳ Ожидает подтверждения API перед финальной реализацией  
**Ветка:** `feature/agent1-backend-design`

> **ВАЖНО:** В соответствии с регламентом разработки реализация расширенной бизнес-логики `EconomyService` и `InventoryService` заморожена до согласования данных контрактов между Agent 1 и Agent 2.

---

## 1. Контракт `EconomyService` (`src/server/Services/EconomyService.luau`)

### 1.1 Зависимости и конфигурация
- **Dependencies:** `{ "PlayerDataService" }`
- **Configs:** `GameConfig.luau`, `CurrenciesConfig.luau`, `ItemsConfig.luau`, `ZonesConfig.luau`

### 1.2 Типы и коды ошибок (`EconomyErrorCode`)

```luau
export type EconomyErrorCode =
	"PROFILE_NOT_LOADED"
	| "UNKNOWN_CURRENCY"
	| "INVALID_AMOUNT"
	| "INSUFFICIENT_FUNDS"
	| "CLICK_COOLDOWN"
	| "UPDATE_FAILED"

export type MultiplierBreakdown = {
	base: number,          -- 1.0
	rebirthBonus: number,  -- 1.0 + rebirths * RebirthBonusMultiplierPerRebirth
	equippedItemsBonus: number, -- Произведение или сумма множителей экипированных Tool + Pets
	zoneBonus: number,     -- Множитель текущей открытой зоны
	total: number,         -- Итоговый множитель
}
```

### 1.3 Публичный серверный API (`EconomyService`)

| Метод | Сигнатура | Описание и гарантии |
|---|---|---|
| `GetBalance` | `(self, player: Player, currencyId: CurrencyId) -> number` | Возвращает текущий баланс валюты (`0`, если профиль ещё не загружен). Не выбрасывает исключений. |
| `CanAfford` | `(self, player: Player, currencyId: CurrencyId, amount: number) -> boolean` | Проверяет `amount >= 0`, `amount == amount` (не NaN) и `GetBalance >= amount`. |
| `GetMultiplier` | `(self, player: Player, currencyId: CurrencyId) -> number` | Возвращает итоговый множитель для указанной валюты. |
| `GetMultiplierBreakdown` | `(self, player: Player, currencyId: CurrencyId) -> MultiplierBreakdown` | Детализация множителей (базовый, ребирты, предметы, зоны) для отладки и UI. |
| `AddCurrency` | `(self, player: Player, currencyId: CurrencyId, amount: number, reason: string?) -> Result<number, EconomyErrorCode>` | Начисляет валюту с ограничением `CurrenciesConfig[currencyId].maxAmount`, обновляет `leaderstats` и `stats.totalCoinsEarned`, отправляет `CurrencyUpdated` клиенту. |
| `RemoveCurrency` | `(self, player: Player, currencyId: CurrencyId, amount: number, reason: string?) -> Result<number, EconomyErrorCode>` | Атомарно проверяет `CanAfford` и списывает валюту. При нехватке средств возвращает `Err("INSUFFICIENT_FUNDS")`. |
| `ProcessSimulatorClick` | `(self, player: Player, clientToolUid: string?) -> Result<number, EconomyErrorCode>` | Проверяет серверный кулдаун (`ClickCooldownSeconds` с допуском 15% на сетевой джиттер), валидирует `clientToolUid` по серверному инвентарю, начисляет монеты и генерирует событие клика. |

### 1.4 Серверные сигналы (`Signal`)
- `OnCurrencyChanged: Signal<Player, CurrencyId, number, number, string?>` — `(player, currencyId, newBalance, delta, reason)`
- `OnSimulatorClickProcessed: Signal<Player, number, string?>` — `(player, coinsEarned, equippedToolUid)` (используется `QuestService` и `ProgressionService` для начисления XP и прогресса квестов без циклической зависимости `EconomyService -> QuestService`!).

### 1.5 Сетевой контракт с клиентом (Agent 2)
- **Входящее событие (`Client -> Server`):**
  - `Network.Events.RequestActionClick (toolUid: string?)` — вызывается из `InteractionController:TriggerPrimaryAction()`.
- **Исходящее событие (`Server -> Client`):**
  - `Network.Events.CurrencyUpdated (currencyId: CurrencyId, newBalance: number, delta: number)` — принимается в `UIController` для обновления `HUDComponent` и активных окон (`RebirthView`, `ShopView`).

---

## 2. Контракт `InventoryService` (`src/server/Services/InventoryService.luau`)

### 2.1 Зависимости и конфигурация
- **Dependencies:** `{ "PlayerDataService" }`
- **Configs:** `GameConfig.luau`, `ItemsConfig.luau`

### 2.2 Типы и коды ошибок (`InventoryErrorCode`)

```luau
export type InventoryErrorCode =
	"PROFILE_NOT_LOADED"
	| "UNKNOWN_ITEM_ID"
	| "INVENTORY_FULL"
	| "ITEM_NOT_FOUND"
	| "MAX_PETS_EQUIPPED"
	| "EQUIP_FAILED"
	| "GRANT_FAILED"

export type InventoryCapacityInfo = {
	usedSlots: number,
	maxSlots: number,
	equippedPetsCount: number,
	maxEquippedPets: number,
}
```

### 2.3 Публичный серверный API (`InventoryService`)

| Метод | Сигнатура | Описание и гарантии |
|---|---|---|
| `GetInventory` | `(self, player: Player) -> { [string]: InventoryItem }` | Возвращает таблицу всех предметов игрока (`uid -> InventoryItem`). |
| `GetItem` | `(self, player: Player, itemUid: string) -> InventoryItem?` | Возвращает конкретный экземпляр предмета по `uid`. |
| `HasItemByTemplate` | `(self, player: Player, itemId: string) -> boolean` | Проверяет, есть ли у игрока хотя бы один предмет с заданным шаблоном `itemId`. |
| `GetCapacityInfo` | `(self, player: Player) -> InventoryCapacityInfo` | Возвращает текущую заполненность инвентаря и слотов экипировки. |
| `GrantItem` | `(self, player: Player, itemId: string) -> Result<InventoryItem, InventoryErrorCode>` | Проверяет `ItemsConfig[itemId]` и лимит `MaxInventorySlots` (50), создаёт `InventoryItem` с GUID и отправляет `InventoryUpdated` клиенту. |
| `RemoveItem` | `(self, player: Player, itemUid: string) -> Result<boolean, InventoryErrorCode>` | Удаляет предмет по `uid` (запрещено удалять последний базовый `starter_wand_default`) и синхронизирует клиента. |
| `EquipItem` | `(self, player: Player, itemUid: string, equipped: boolean) -> Result<InventoryItem, InventoryErrorCode>` | Для `Tool`: автоматически снимает предыдущий `Tool` (только 1 активный инструмент). Для `Pet`: проверяет лимит `MaxEquippedPets` (3). Отправляет `InventoryUpdated` клиенту. |
| `GetEquippedItems` | `(self, player: Player, category: ItemCategory?) -> { InventoryItem }` | Возвращает список экипированных предметов (всех или по категории `"Tool" \| "Pet"`). |

### 2.4 Серверные сигналы (`Signal`)
- `OnItemGranted: Signal<Player, InventoryItem>`
- `OnItemRemoved: Signal<Player, string>`
- `OnEquipmentChanged: Signal<Player, InventoryItem>`

### 2.5 Сетевой контракт с клиентом (Agent 2)
- **Входящее событие (`Client -> Server`):**
  - `Network.Events.RequestEquipItem (itemUid: string, equip: boolean)` — отправляется из `InventoryView` через `InteractionController:RequestEquipItem()`.
- **Исходящие события (`Server -> Client`):**
  - `Network.Events.InventoryUpdated (inventory: { [string]: InventoryItem })` — принимается в `UIController` (перерисовывает `InventoryView`) и `WorldController` (обновляет `ItemDisplayManager`).
  - `Network.Events.Notification (notifType: "Warning" | "Error", message: string)` — отправляется при отказе экипировки (например, `"Maximum 3 pets can be equipped!"`), чтобы `NotificationComponent` показал тост игроку.
