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


---

## 7. Combat Loop v1 — Мобы, Детали тела, Сундуки, Дерево навыков, PvP-арена — *Agent A (`Breight321`)*

> **Статус:** контракт v1 опубликован Agent A. Цикл: победа над мобами → XP (`ProgressionService`), `Coins` (`EconomyService`) и детали тела (`InventoryService`) → сборка персонажа с бонусами (`StatsService` + `SkillTreeService`) → новые зоны (`ProgressionService:UnlockZone`) и более сильные мобы.
> **Правило безопасности:** клиент отправляет только идентификаторы (`mobUid`, `chestId`, `skillId`, `targetUserId`, `itemUid`). Урон, крит, XP, валюта, выпавшие предметы, очки навыков и результат PvP рассчитываются **только на сервере**. Новых валют и уровней сложности не добавляется.

### 7.1. Новые сервисы и зависимости (DAG без циклов)

| Сервис | Dependencies | Назначение |
|---|---|---|
| `SkillTreeService` | `PlayerDataService`, `ProgressionService` | Очки навыков, покупка пассивных навыков, сохранение в профиле |
| `StatsService` | `PlayerDataService`, `InventoryService`, `SkillTreeService` | Итоговые статы персонажа (база + уровень + детали тела + сет-бонус + навыки), применение `MaxHealth`/`WalkSpeed` к `Humanoid` |
| `LootService` | `PlayerDataService`, `EconomyService`, `InventoryService`, `ProgressionService` | Серверный бросок таблиц добычи и выдача наград |
| `CombatService` | `PlayerDataService`, `ProgressionService`, `EconomyService`, `StatsService`, `LootService` | Спавн мобов, проверка атаки, урон, победа, награды, атаки мобов по игрокам |
| `ChestService` | `PlayerDataService`, `ProgressionService`, `LootService`, `CombatService` | Сундуки в зонах, условия открытия, кулдауны, защита от повторных запросов |
| `ArenaService` | `PlayerDataService`, `StatsService` | Добровольная PvP-арена, отдельный PvP-баланс |

### 7.2. RemoteEvents (`Network.Events`)

| Событие | Направление | Кто вызывает | Payload |
|---|---|---|---|
| `RequestAttackMob` | Client → Server | `CombatController` / клик по мобу (Agent B) | `(mobUid: string)` |
| `CombatResult` | Server → Client (атакующему) | `CombatService` | `(result: CombatResultPayload)` |
| `MobDefeated` | Server → Client (каждому награждённому) | `CombatService` | `(payload: MobDefeatedPayload)` |
| `RequestOpenChest` | Client → Server | `InteractionController` / ProximityPrompt (Agent B) | `(chestId: string)` |
| `ChestResult` | Server → Client | `ChestService` | `(result: ChestOpenResultPayload)` |
| `ChestStateSync` | Server → Client | `ChestService` (при загрузке профиля и после открытия) | `(states: { [string]: ChestStatePayload })` |
| `RequestUnlockSkill` | Client → Server | `SkillTreeView` (Agent B) | `(skillId: string)` |
| `SkillTreeSync` | Server → Client | `SkillTreeService` (загрузка профиля, level-up, покупка) | `(state: SkillTreeStatePayload)` |
| `SkillUnlockResult` | Server → Client | `SkillTreeService` | `(result: SkillUnlockResultPayload)` |
| `StatsUpdated` | Server → Client | `StatsService` (загрузка, экипировка, навык, level-up) | `(stats: CharacterStatsPayload)` |
| `RequestArenaEnter` | Client → Server | Кнопка/Prompt у входа в арену (Agent B) | `()` |
| `RequestArenaLeave` | Client → Server | Кнопка «Покинуть арену» (Agent B) | `()` |
| `ArenaStateChanged` | Server → Client | `ArenaService` | `(state: ArenaStatePayload)` |
| `RequestPvPAttack` | Client → Server | `CombatController` в арене (Agent B) | `(targetUserId: number)` |
| `PvPCombatResult` | Server → Client (атакующему и цели) | `ArenaService` | `(result: PvPCombatResultPayload)` |

**Экипировка деталей тела использует существующий** `RequestEquipItem(itemUid: string, equip: boolean)` → `InventoryUpdated(inventory)` + `StatsUpdated(stats)`. Нового события экипировки нет.

### 7.3. Мобы в мире (реплицируемые Instance, без отдельного события здоровья)

`Workspace.CombatWorld.Mobs.<mobUid>` — `Model` c `PrimaryPart` `Body` и атрибутами:
`MobUid: string`, `MobId: string`, `ZoneId: string`, `DisplayName: string`, `Level: number`, `Health: number`, `MaxHealth: number`, `IsAlive: boolean`.
Клиент читает атрибуты (`GetAttributeChangedSignal("Health")`) для полоски HP и стилизует модель сам. Сундуки: `Workspace.CombatWorld.Chests.<chestId>` (атрибуты `ChestId`, `ZoneId`, `DisplayName`). Арена: `Workspace.CombatWorld.Arena.Entrance` (атрибут `ArenaId`).

### 7.4. Детали тела (Body Parts) — поля предмета

- Хранятся как обычные `InventoryItem` в `profile.inventory`, выдаются через `InventoryService:GrantItem` (совместимо с магазином и инвентарём).
- **Слот = категория предмета**, лимит экипировки 1 на категорию (стандартное правило `InventoryService`):

| Слот (`metadata.bodySlot`) | `category` | Основной бонус |
|---|---|---|
| `"Head"` | `"BodyHead"` | `critChance` |
| `"Arms"` | `"BodyArms"` | `attackPower` |
| `"Torso"` | `"BodyTorso"` | `maxHealth` + `defense` |
| `"Legs"` | `"BodyLegs"` | `moveSpeed` (+ немного `defense`) |

```luau
-- ItemsConfig[itemId] для детали тела (ItemDef + metadata)
{
	id = "scrap_head",
	displayName = "Scrapper Visor",
	category = "BodyHead",            -- "BodyHead" | "BodyArms" | "BodyTorso" | "BodyLegs"
	rarity = "Common",                -- Common (Scrapper) | Rare (Ember) | Epic (Frostforged)
	stackable = false,
	powerMultiplier = 1.0,            -- не используется боем (совместимость ItemDef)
	coinMultiplier = 1.0,             -- детали тела не меняют доход Coins
	description = "...",
	metadata = {
		bodySlot = "Head",            -- BodySlot
		setId = "scrapper",           -- "scrapper" | "ember" | "frostforged"
		stats = { critChance = 0.03 },-- BodyStatBlock (любые поля из CharacterStats ниже)
		visual = {                    -- общий визуальный язык: все наборы — модульный «ретро-мех» с одинаковыми точками крепления
			style = "ModularMech",
			primaryColor = "#7A6F64",
			accentColor = "#E0A84A",
			material = "Metal",       -- Enum.Material name
			glow = false,
		},
	},
}
```

- **Сет-бонус:** 4 детали одного `setId` → `BodySetsConfig[setId].fullSetBonus` (`BodyStatBlock`).
- Детали разных наборов совместимы: общий `style = "ModularMech"`, одинаковые точки крепления, палитры подобраны с общим акцентным тоном.

### 7.5. Типы (`src/shared/Core/Types.luau`)

```luau
export type BodySlot = "Head" | "Arms" | "Torso" | "Legs"
export type SkillBranch = "Damage" | "Defense" | "Mobility"

export type BodyStatBlock = {
	attackPower: number?, critChance: number?, critMultiplier: number?,
	maxHealth: number?, defense: number?, moveSpeed: number?,
	attackCooldownReduction: number?, attackPowerPct: number?, maxHealthPct: number?,
}

export type CharacterStatsPayload = {
	level: number,
	attackPower: number,          -- итоговый урон до крита
	critChance: number,           -- 0..CombatConfig.MaxCritChance
	critMultiplier: number,
	maxHealth: number,
	defense: number,              -- снижение урона = defense / (defense + CombatConfig.DefenseConstant)
	damageReduction: number,      -- 0..CombatConfig.MaxDamageReduction (уже рассчитано)
	moveSpeed: number,
	attackCooldown: number,       -- секунды между атаками по мобам
	equippedBodyParts: { [BodySlot]: string }, -- slot -> itemId
	activeSetBonus: string?,      -- setId при полном комплекте
}

export type CombatErrorCode = "INVALID_PLAYER" | "PROFILE_NOT_LOADED" | "CHARACTER_NOT_READY" | "PLAYER_DEAD"
	| "INVALID_TARGET" | "TARGET_DEAD" | "OUT_OF_RANGE" | "ATTACK_COOLDOWN" | "ZONE_LOCKED" | "LEVEL_TOO_LOW" | "IN_ARENA"

export type LootDrop = { kind: "Currency" | "XP" | "Item", id: string, amount: number, itemUid: string? }

export type CombatResultPayload = {
	ok: boolean, mobUid: string, damageDealt: number, isCritical: boolean,
	mobHealth: number, mobMaxHealth: number, killed: boolean,
	errorCode: CombatErrorCode?, message: string,
}

export type MobDefeatedPayload = {
	mobUid: string, mobId: string, zoneId: string,
	xpGained: number, coinsGained: number, drops: { LootDrop },
	totalMobKills: number,
}

export type ChestErrorCode = "INVALID_PLAYER" | "PROFILE_NOT_LOADED" | "CHARACTER_NOT_READY" | "UNKNOWN_CHEST"
	| "ZONE_LOCKED" | "LEVEL_TOO_LOW" | "OUT_OF_RANGE" | "CHEST_COOLDOWN" | "NOT_ENOUGH_KILLS" | "REQUEST_IN_PROGRESS"

export type ChestStatePayload = {
	chestId: string, readyAtUnix: number, requiredKills: number, killsSinceLastOpen: number, isReady: boolean,
}

export type ChestOpenResultPayload = {
	ok: boolean, chestId: string, drops: { LootDrop }, state: ChestStatePayload?,
	errorCode: ChestErrorCode?, message: string,
}

export type SkillErrorCode = "INVALID_PLAYER" | "PROFILE_NOT_LOADED" | "UNKNOWN_SKILL" | "ALREADY_UNLOCKED"
	| "PREREQUISITE_MISSING" | "LEVEL_TOO_LOW" | "NOT_ENOUGH_POINTS" | "RATE_LIMITED"

export type SkillTreeStatePayload = {
	unlocked: { [string]: boolean }, earnedPoints: number, spentPoints: number, availablePoints: number,
}

export type SkillUnlockResultPayload = {
	ok: boolean, skillId: string, state: SkillTreeStatePayload, errorCode: SkillErrorCode?, message: string,
}

export type ArenaErrorCode = "INVALID_PLAYER" | "PROFILE_NOT_LOADED" | "CHARACTER_NOT_READY" | "PLAYER_DEAD"
	| "NOT_AT_ARENA_ENTRANCE" | "ALREADY_IN_ARENA" | "NOT_IN_ARENA" | "COMBAT_TAGGED" | "LEVEL_TOO_LOW"
	| "INVALID_TARGET" | "SELF_TARGET" | "TARGET_NOT_IN_ARENA" | "OUT_OF_RANGE" | "ATTACK_COOLDOWN" | "RATE_LIMITED"

export type ArenaStatePayload = {
	inArena: boolean, arenaId: string, combatTaggedUntil: number, -- os.clock() сервера не передаётся; это секунды до снятия тега
	reason: string?, errorCode: ArenaErrorCode?, message: string,
}

export type PvPCombatResultPayload = {
	ok: boolean, attackerUserId: number, targetUserId: number, damageDealt: number, isCritical: boolean,
	targetHealth: number, targetMaxHealth: number, killed: boolean, errorCode: ArenaErrorCode?, message: string,
}
```

> `ArenaStatePayload.combatTaggedUntil` — **оставшиеся секунды** combat-тега (0 = можно выйти).

### 7.6. Поля профиля (`profile.customData`, сохраняются через `PlayerDataService`)

```luau
customData.combat    = { totalMobKills: number, mobKillsById: { [mobId]: number }, pvpKills: number, pvpDeaths: number }
customData.chests    = { [chestId]: { lastOpenedAt: number, killsAtLastOpen: number } }
customData.skillTree = { unlocked: { [skillId]: boolean }, earnedPoints: number }
customData.harvestState = PlayerHarvestState -- (исправление: раньше хранилось вне customData и терялось при перезаходе; profile.harvestState остаётся алиасом для клиента)
```

### 7.7. Публичные методы сервисов

- **`StatsService`:** `GetStats(player): CharacterStatsPayload`, `RecalculateAndApply(player): CharacterStatsPayload`, `GetEquippedBodyParts(player): { [BodySlot]: InventoryItem }`, `ComputeMitigatedDamage(rawDamage, defense): number`. Signal `OnStatsChanged(player, stats)`.
- **`SkillTreeService`:** `GetState(player): Result<SkillTreeStatePayload>`, `UnlockSkill(player, skillId): Result<SkillTreeStatePayload, SkillErrorCode>`, `GetSkillBonuses(player): BodyStatBlock`. Signal `OnSkillUnlocked(player, skillId)`.
- **`LootService`:** `RollLootTable(lootTableId, rng?): { LootDrop }`, `GrantDrops(player, drops, reason): { LootDrop }` (возвращает фактически выданное, с `itemUid`).
- **`CombatService`:** `AttackMob(player, mobUid): Result<CombatResultPayload, CombatErrorCode>`, `GetMob(mobUid)`, `GetKillStats(player)`, `IsPlayerInCombatZone`, тестовые `SpawnMobForTest`, `DespawnMobForTest`, `ClearCooldownForTest`, `SetRngForTests`. Signals `OnMobDamaged(player, mobUid, dmg)`, `OnMobDefeated(mobUid, mobId, rewardedPlayers)`.
- **`ChestService`:** `GetChestStates(player): { [chestId]: ChestStatePayload }`, `OpenChest(player, chestId): Result<ChestOpenResultPayload, ChestErrorCode>`. Signal `OnChestOpened(player, chestId, drops)`.
- **`ArenaService`:** `EnterArena(player)`, `LeaveArena(player, reason?)`, `IsInArena(player): boolean`, `AttackPlayer(attacker, targetUserId)`. Signals `OnArenaEntered`, `OnArenaLeft`, `OnPvPKill(killer, victim)`.
- **`ProgressionService`** (расширение без поломки API): новый Signal `OnLevelUp(player, newLevel, oldLevel)`.

### 7.8. Правила серверной валидации

- **Атака моба:** профиль загружен, персонаж жив, игрок не в арене, моб существует и жив, `distance <= CombatConfig.MeleeRange`, кулдаун `stats.attackCooldown`, зона моба открыта (`profile.unlockedZones[zoneId]`) и `level >= CombatConfig.ZoneRules[zoneId].minPlayerLevel`. Урон = `attackPower × (крит ? critMultiplier : 1)`.
- **Награды моба:** получают все игроки, нанёсшие ≥ `CombatConfig.RewardContributionThreshold` (15%) от MaxHealth. XP → `ProgressionService:AddXP`, Coins → `EconomyService:AddCurrency` (с `EconomyService:GetMultiplier`), дроп → `LootService`.
- **Сундук:** зона открыта, уровень, `distance <= interactionRadius`, кулдаун на игрока (сохраняется в профиле — перезаход не сбрасывает), не менее `requiredKillsSinceLastOpen` убийств мобов с прошлого открытия, блокировка параллельных запросов (`REQUEST_IN_PROGRESS`).
- **Навык:** существует, не куплен, все `requires` куплены, `level >= requiredLevel`, `availablePoints >= cost`; очки: +`SkillTreeConfig.PointsPerLevel` за каждый новый уровень (переживают ребирт).
- **PvP:** вход только у `ArenaConfig.EntrancePosition` (радиус) и с `minPlayerLevel`; урон только если **оба** игрока в арене; отдельная формула `ArenaConfig.Balance` (масштаб урона, кап крита, кап урона за удар от MaxHealth); выход запрещён во время combat-тега; смерть или выход за границы арены автоматически выводят из арены. В обычных зонах путь урона «игрок → игрок» отсутствует.
