# 📘 API_REGISTRY.md — Единый реестр публичных интерфейсов

> **ВАЖНО:** Этот документ является **единым источником истины (Single Source of Truth)** для всех публичных API, сетевых событий и общих типов между **Agent 1 (`Breight321`)** и **Agent 2 (`anarugod`)**. Любое изменение сигнатуры метода или сетевого контракта требует предварительного согласования и обновления этого файла.

---

## 1. Общие типы данных (`src/shared/Core/Types.luau`)

Все публичные функции возвращают стандартизированный тип `Result<T, E>` для операций, которые могут завершиться ошибкой:

```luau
export type Result<T, E = string> = {
	ok: boolean,
	value: T?,
	error: E?,
}

export type CurrencyId = "Coins" | "Gems"

export type InventoryItem = {
	uid: string,          -- Уникальный ID экземпляра предмета
	itemId: string,       -- ID шаблона из ItemsConfig
	category: "Tool" | "Pet" | "Consumable",
	equipped: boolean,
	level: number,
	acquiredAt: number,
}

export type QuestState = {
	questId: string,
	progress: number,
	target: number,
	completed: boolean,
	claimed: boolean,
}

export type PlayerProfileData = {
	schemaVersion: number,
	currencies: { [CurrencyId]: number },
	rebirths: number,
	level: number,
	xp: number,
	unlockedZones: { [string]: boolean },
	inventory: { [string]: InventoryItem },
	quests: { [string]: QuestState },
	stats: {
		totalClicks: number,
		totalCoinsEarned: number,
		playTimeSeconds: number,
	},
}
```

---

## 2. Core Framework API (`src/shared/Core/`) — *Владелец: Agent 1 (Shared)*

### 2.1 `Registry.luau`
Отвечает за регистрацию, топологическую сортировку зависимостей и жизненный цикл модулей.

- **Public API:**
  - `Registry.new(scope: "Server" | "Client"): RegistryInstance`
  - `registry:Register(moduleDef: LifecycleModule): ()`
  - `registry:Get<T>(name: string): T` — безопасное получение зарегистрированного сервиса/контроллера.
  - `registry:InitAll(): Result<boolean, string>` — вызывает `:Init(registry)` в топологическом порядке.
  - `registry:StartAll(): Result<boolean, string>` — вызывает `:Start()` для всех инициализированных модулей.
  - `registry:ShutdownAll(): ()` — вызывает `:Shutdown()` в обратном порядке.

### 2.2 `Signal.luau`
Типизированный синхронный/асинхронный внутрипроцессный сигнал.

- **Public API:**
  - `Signal.new<T...>(): Signal<T...>`
  - `signal:Connect(callback: (T...) -> ()): SignalConnection`
  - `signal:Once(callback: (T...) -> ()): SignalConnection`
  - `signal:Fire(T...): ()`
  - `signal:Destroy(): ()`

### 2.3 `Network.luau`
Типизированный сетевой слой для общения между Server Services (Agent 1) и Client Controllers (Agent 2).

- **Сетевые события (`Network.Events`):**
  | Имя события | Направление | Payload (Аргументы) | Описание |
  |---|---|---|---|
  | `PlayerDataSync` | Server -> Client | `(data: PlayerProfileData)` | Полная или начальная синхронизация профиля |
  | `CurrencyUpdated` | Server -> Client | `(currencyId: CurrencyId, newBalance: number, delta: number)` | Изменение баланса валюты |
  | `InventoryUpdated` | Server -> Client | `(inventory: { [string]: InventoryItem })` | Обновление инвентаря игрока |
  | `ProgressionUpdated` | Server -> Client | `(level: number, xp: number, rebirths: number, unlockedZones: { [string]: boolean })` | Обновление уровня/ребиртов/зон |
  | `QuestUpdated` | Server -> Client | `(questState: QuestState)` | Обновление прогресса квеста |
  | `Notification` | Server -> Client | `(notifType: "Success" | "Warning" | "Error" | "Reward", message: string)` | Системное уведомление для UI |
  | `RequestActionClick` | Client -> Server | `(toolUid: string?)` | Игрок совершил клик/действие симулятора |
  | `RequestShopPurchase` | Client -> Server | `(shopItemId: string)` | Запрос на покупку предмета/улучшения |
  | `RequestEquipItem` | Client -> Server | `(itemUid: string, equip: boolean)` | Запрос на экипировку/снятие предмета |
  | `RequestRebirth` | Client -> Server | `()` | Запрос на выполнение Ребирта |
  | `RequestUnlockZone` | Client -> Server | `(zoneId: string)` | Запрос на открытие новой локации/зоны |
  | `RequestClaimQuest` | Client -> Server | `(questId: string)` | Запрос на получение награды за выполненный квест |

---

## 3. Server Services API (`src/server/Services/`) — *Владелец: Agent 1 (`Breight321`)*

### 3.1 `PlayerDataService`
- **Dependencies:** `{}`
- **Configuration:** `src/shared/Config/GameConfig.luau`
- **Public API:**
  - `GetProfile(player: Player): Result<PlayerProfileData, string>`
  - `UpdateProfile(player: Player, mutator: (PlayerProfileData) -> boolean): Result<PlayerProfileData, string>`
  - `SaveProfile(player: Player): Result<boolean, string>`
- **Events:**
  - `OnProfileLoaded: Signal<Player, PlayerProfileData>`
  - `OnProfileReleasing: Signal<Player, PlayerProfileData>`
- **Initialization / Shutdown:** Подписывается на `Players.PlayerAdded`/`PlayerRemoving`, при `Shutdown()` сохраняет все активные сессии.

### 3.2 `EconomyService`
- **Dependencies:** `{ "PlayerDataService" }`
- **Configuration:** `src/shared/Config/CurrenciesConfig.luau`
- **Public API:**
  - `GetBalance(player: Player, currencyId: CurrencyId): number`
  - `AddCurrency(player: Player, currencyId: CurrencyId, amount: number, reason: string?): Result<number, string>`
  - `RemoveCurrency(player: Player, currencyId: CurrencyId, amount: number, reason: string?): Result<number, string>`
  - `CanAfford(player: Player, currencyId: CurrencyId, amount: number): boolean`
  - `GetMultiplier(player: Player, currencyId: CurrencyId): number`
  - `ProcessSimulatorClick(player: Player): Result<number, string>`
- **Events:**
  - `OnCurrencyChanged: Signal<Player, CurrencyId, number, number>` (player, currencyId, newBalance, delta)

### 3.3 `InventoryService`
- **Dependencies:** `{ "PlayerDataService" }`
- **Configuration:** `src/shared/Config/ItemsConfig.luau`
- **Public API:**
  - `GetInventory(player: Player): { [string]: InventoryItem }`
  - `GrantItem(player: Player, itemId: string): Result<InventoryItem, string>`
  - `RemoveItem(player: Player, itemUid: string): Result<boolean, string>`
  - `EquipItem(player: Player, itemUid: string, equipped: boolean): Result<InventoryItem, string>`
  - `GetEquippedItems(player: Player, category: ("Tool" | "Pet" | "Consumable")?): { InventoryItem }`
- **Events:**
  - `OnItemGranted: Signal<Player, InventoryItem>`
  - `OnEquipmentChanged: Signal<Player, InventoryItem>`

### 3.4 `ProgressionService`
- **Dependencies:** `{ "PlayerDataService", "EconomyService" }`
- **Configuration:** `src/shared/Config/GameConfig.luau`, `src/shared/Config/ZonesConfig.luau`
- **Public API:**
  - `AddXP(player: Player, amount: number): Result<{ level: number, xp: number }, string>`
  - `CanRebirth(player: Player): Result<boolean, string>`
  - `PerformRebirth(player: Player): Result<number, string>`
  - `UnlockZone(player: Player, zoneId: string): Result<boolean, string>`
  - `IsZoneUnlocked(player: Player, zoneId: string): boolean`
- **Events:**
  - `OnRebirth: Signal<Player, number>`
  - `OnZoneUnlocked: Signal<Player, string>`

### 3.5 `ShopService`
- **Dependencies:** `{ "PlayerDataService", "EconomyService", "InventoryService" }`
- **Configuration:** `src/shared/Config/ShopConfig.luau`
- **Public API:**
  - `PurchaseItem(player: Player, shopItemId: string): Result<InventoryItem, string>`
  - `GetCatalog(): { [string]: any }`
- **Events:**
  - `OnPurchaseCompleted: Signal<Player, string, InventoryItem>`

### 3.6 `QuestService`
- **Dependencies:** `{ "PlayerDataService", "EconomyService", "InventoryService" }`
- **Configuration:** `src/shared/Config/QuestsConfig.luau`
- **Public API:**
  - `IncrementProgress(player: Player, objectiveType: string, amount: number): ()`
  - `ClaimReward(player: Player, questId: string): Result<boolean, string>`
  - `GetPlayerQuests(player: Player): { [string]: QuestState }`
- **Events:**
  - `OnQuestCompleted: Signal<Player, string>`
  - `OnQuestClaimed: Signal<Player, string>`

---

## 4. Client Controllers API (`src/client/`) — *Владелец: Agent 2 (`anarugod`)*

> Реализовано и поддерживается **Agent 2 (`anarugod`)**.

### 4.1 `UIController` (`src/client/Controllers/UIController.luau`)
- **Dependencies:** `{ "AudioController", "AnimationController" }`
- **UI Modules:** `src/client/UI/Theme.luau`, `HUDComponent.luau`, `WindowComponent.luau`, `NotificationComponent.luau`
- **Public API:**
  - `OpenScreen(screenName: string): ()`
  - `CloseScreen(screenName: string): ()`
  - `ToggleScreen(screenName: string): ()`
  - `GetActiveScreen(): string?`
  - `ShowNotification(notifType: string, message: string): ()`
  - `GetClientState(): PlayerProfileData?`
- **Events:**
  - `OnScreenChanged: Signal<string, boolean>`
  - `OnStateUpdated: Signal<PlayerProfileData>`
  - `OnCurrencyUpdated: Signal<CurrencyId, number, number>`
  - `OnInventoryUpdated: Signal<{ [string]: InventoryItem }>`
  - `OnProgressionUpdated: Signal<number, number, number, { [string]: boolean }>`
  - `OnQuestUpdated: Signal<QuestState>`
  - `OnPrimaryClickRequested: Signal<>`

### 4.2 `InteractionController` (`src/client/Controllers/InteractionController.luau`)
- **Dependencies:** `{ "UIController", "WorldController", "AudioController", "AnimationController" }`
- **Public API:**
  - `TriggerPrimaryAction(): Result<boolean, string>` — отправка `RequestActionClick` с проверкой кулдауна и запуском клиентских эффектов.
  - `SetInteractionEnabled(enabled: boolean): ()`
  - `IsInteractionEnabled(): boolean`
  - `RequestShopPurchase(shopItemId: string): ()`
  - `RequestEquipItem(itemUid: string, equip: boolean): ()`
  - `RequestRebirth(): ()`
  - `RequestClaimQuest(questId: string): ()`
- **Events:**
  - `OnPrimaryActionTriggered: Signal<string?>`

### 4.3 `WorldController` (`src/client/Controllers/WorldController.luau`)
- **Dependencies:** `{ "UIController", "AudioController" }`
- **World Modules:** `src/client/World/Zones/ZoneGateManager.luau`, `src/client/World/Items/ItemDisplayManager.luau`
- **Public API:**
  - `SyncUnlockedZones(unlockedZones: { [string]: boolean }): ()`
  - `RequestUnlockZone(zoneId: string): ()`
  - `IsZoneUnlocked(zoneId: string): boolean`
  - `SetCurrentZone(zoneId: string): ()`
  - `GetCurrentZone(): string`
  - `GetEquippedToolUid(): string?`
- **Events:**
  - `OnZoneEntered: Signal<string>`
  - `OnZonesSynced: Signal<{ [string]: boolean }>`

### 4.4 `AudioController` (`src/client/Controllers/AudioController.luau`)
- **Dependencies:** `{}`
- **Public API:**
  - `PlaySFX(soundName: string, pitchVariance: number?): ()`
  - `PlayMusic(trackName: string): ()`
  - `SetMuted(muted: boolean): ()`
  - `IsMuted(): boolean`
  - `GetActiveMusicTrack(): string?`
- **Events:**
  - `OnMuteChanged: Signal<boolean>`

### 4.5 `AnimationController` (`src/client/Controllers/AnimationController.luau`)
- **Dependencies:** `{}`
- **Public API:**
  - `PlayActionAnimation(actionName: string): ()`
  - `PlayUIEffect(effectName: string, targetGui: GuiObject): ()`
  - `GetLastActionAnimation(): string?`
