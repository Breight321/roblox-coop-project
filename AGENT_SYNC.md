# 📡 AGENT SYNC BOARD (Breight321 & anarugod)

## 1. 👥 Кто над чем работает (Распределение ролей)
- **Agent A (`Breight321` — Lead Architect / Backend):**
  - Core Framework (`src/shared/Core/`)
  - Module initialization / lifecycle (`Registry.luau`)
  - Service architecture (`src/server/Services/`)
  - Player Data architecture (`PlayerDataService.luau`)
  - Economy Backend (`src/server/Services/EconomyService/`)
  - **Вертикальный срез «Sunforge Expedition» (Backend & Shared Contracts):**
    - Конфиг цикла добычи, станций сдачи, апгрейдов инструмента/сумки и этапов сервера (`src/shared/Config/HarvestConfig.luau`)
    - Сервис `src/server/Services/HarvestService/` (`init.luau`, `tests/HarvestTests.luau`)
  - Shared Types и API Contracts (`src/shared/Core/Types.luau`, `Network.luau`)
  - Server-side validation & Backend tests (`EconomyTests.luau`, `HarvestTests.luau`, `FrameworkTests.luau`)
- **Agent B (`anarugod` — Gameplay / Client):**
  - UI Framework & Window Manager (`src/client/UI/WindowManager.luau`)
  - Shop UI & Gameplay Views (`ShopView.luau`, `InventoryView.luau`, `QuestsView.luau`, `RebirthView.luau`)
  - Client Controllers (`src/client/Controllers/`)
  - Interaction System & World/Zone Systems (`src/client/World/`)
  - UI states (`Loading / Success / Error`), индикатор сумки, прогресс-бар общей цели сервера & notifications (`NotificationComponent.luau`)

---

## 2. 📂 Какие файлы редактируются
- **Agent A (`Breight321`) редактирует:**
  - `src/shared/Config/HarvestConfig.luau` *(новый конфиг вертикального среза)*
  - `src/server/Services/HarvestService/init.luau` *(новый серверный сервис добычи, сумки, сдачи, апгрейдов и общей цели сервера)*
  - `src/server/Services/HarvestService/tests/HarvestTests.luau` *(серверные модульные и интеграционные тесты цикла)*
  - `src/server/init.server.luau` *(подключение `HarvestTests` при старте)*
  - `src/shared/Core/Types.luau`, `src/shared/Core/Network.luau` *(типы и сетевые события вертикального среза)*
  - `AGENT_SYNC.md`, `docs/API_REGISTRY.md`
- **Agent B (`anarugod`) редактирует (без пересечений с Agent A):**
  - `src/client/Controllers/*`
  - `src/client/UI/*`
  - `src/client/World/*`

---

## 3. 🌿 Текущие feature-ветки
- `main` — стабильная релизная ветка (прямой push запрещён)
- `develop` — интеграционная ветка (через Pull Requests)
- `feature/sunforge-harvest-backend` — активная ветка Agent A (`Breight321`) для вертикального среза «добыча → сумка → сдача → апгрейды → прогресс сервера»
- `feature/universal-client-modules` / клиентские ветки — ветки Agent B (`anarugod`)

---

## 4. 🤝 Согласованные API (Sunforge Expedition + Economy Backend + Shop UI)

### 4.1. Контракт цикла «Добыча → Сумка → Сдача → Улучшения → Цель Сервера» (`HarvestService`)

Клиент **никогда** не передаёт сумму добычи, баланс, цену или уровень улучшения — только ID зоны/станции или тип улучшения (`"Tool"` | `"Bag"`). Все проверки (дистанция, открытый этап сервера, cooldown, вместимость сумки, расчёт выплаты и списание валюты) выполняются строго на сервере.

#### Запросы (`Client -> Server` через `Network.FireServer`):
1. **`Network.Events.RequestHarvest` (`"RequestHarvest"`)**
   - Аргументы: `(nodeId: string?)` — ID зоны добычи из `HarvestConfig.ExtractionZones` (по умолчанию `"sunforge_crater"`).
   - Сервер проверяет: профиль загружен, этап сервера `>= requiredServerStage`, расстояние до `zone.centerPosition <= zone.radius`, прошёл `cooldownSeconds` текущего инструмента, в сумке `bagStored < bagCapacity`.
   - Ответ клиенту: `Network.Events.HarvestResult` (`HarvestResultPayload`) и `Network.Events.HarvestStateSync` (`HarvestStatePayload`).
2. **`Network.Events.RequestDeposit` (`"RequestDeposit"`)**
   - Аргументы: `(stationId: string?)` — ID станции сдачи из `HarvestConfig.DepositStations` (по умолчанию `"central_refinery"`).
   - Сервер проверяет: станция существует и `active == true`, этап сервера `>= requiredServerStage`, расстояние до `station.position <= station.interactionRadius`, `bagStored > 0`.
   - Сервер рассчитывает выплату в `"Coins"`, очищает сумку (`bagStored = 0`), начисляет валюту через `EconomyService:AddCurrency`, увеличивает общий прогресс сервера `serverTotalDeposited` и проверяет открытие нового этапа.
   - Ответ клиенту: `Network.Events.DepositResult` (`DepositResultPayload`), `Network.Events.HarvestStateSync` (`HarvestStatePayload`), и всем игрокам `Network.Events.ServerProgressUpdated` (`ServerProgressPayload`).
3. **`Network.Events.RequestHarvestUpgrade` (`"RequestHarvestUpgrade"`)**
   - Аргументы: `(upgradeType: "Tool" | "Bag")` — что улучшаем (инструмент или ранец/сумку).
   - Сервер проверяет: существует следующий уровень в `HarvestConfig.ToolUpgrades` / `HarvestConfig.BagUpgrades`, хватает `"Coins"` в `EconomyService`, списывает цену и повышает `toolLevel` или `bagLevel` в `PlayerDataService`.
   - Ответ клиенту: `Network.Events.HarvestUpgradeResult` (`UpgradeResultPayload`) и `Network.Events.HarvestStateSync` (`HarvestStatePayload`).

#### Ответы и синхронизация (`Server -> Client` через `Network.OnClientEvent`):
- **`HarvestStateSync(state: HarvestStatePayload)`**:
  ```luau
  {
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
      nextToolPrice: number?, -- nil если достигнут макс. уровень
      nextBagPrice: number?,  -- nil если достигнут макс. уровень
      totalHarvested: number,
      totalDeposited: number,
  }
  ```
- **`HarvestResult(result: HarvestResultPayload)`**:
  ```luau
  {
      ok: boolean,
      nodeId: string,
      addedAmount: number,
      bagStored: number,
      bagCapacity: number,
      isBagFull: boolean,
      errorCode: HarvestErrorCode?,
      message: string,
  }
  ```
- **`DepositResult(result: DepositResultPayload)`**:
  ```luau
  {
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
  ```
- **`HarvestUpgradeResult(result: UpgradeResultPayload)`**:
  ```luau
  {
      ok: boolean,
      upgradeType: "Tool" | "Bag",
      newLevel: number,
      pricePaid: number,
      newCoinsBalance: number,
      harvestState: HarvestStatePayload?,
      errorCode: HarvestErrorCode?,
      message: string,
  }
  ```
- **`ServerProgressUpdated(progress: ServerProgressPayload)`**:
  ```luau
  {
      totalDeposited: number,
      currentStage: number,
      stageTitle: string,
      stageDescription: string,
      currentStageTarget: number,
      previousStageThreshold: number,
      progressRatio: number, -- 0..1 для прогресс-бара этапа
      stageBonusMultiplier: number,
      unlockedExtractionZones: { [string]: boolean },
      isMaxStage: boolean,
  }
  ```

### 4.2. Контракт `EconomyService` и `ShopService`
- **`EconomyService` (Server):** `GetBalance`, `CanAfford`, `ValidateAmount`, `AddCurrency`, `RemoveCurrency`, `GetMultiplier`, `GetMultiplierBreakdown`, `ProcessSimulatorClick`, `GetTransactionHistory`.
- **`ShopService` <-> `Shop UI`:** `RequestShopPurchase(shopItemId)` $\rightarrow$ `ShopPurchaseResult(response: ShopPurchaseResponse)`.

---

## 5. 🔗 Зависимости между модулями
- `EconomyService` $\rightarrow$ `{ "PlayerDataService" }`
- `HarvestService` $\rightarrow$ `{ "PlayerDataService", "EconomyService" }`
- `InventoryService` $\rightarrow$ `{ "PlayerDataService" }`
- `ProgressionService` $\rightarrow$ `{ "PlayerDataService", "EconomyService" }`
- `QuestService` $\rightarrow$ `{ "PlayerDataService", "EconomyService", "ProgressionService" }`
- `ShopService` $\rightarrow$ `{ "PlayerDataService", "EconomyService", "InventoryService" }`
- `UIController` $\rightarrow$ `{ "AudioController", "AnimationController" }`
- `WorldController` $\rightarrow$ `{ "UIController", "AudioController" }`
- `InteractionController` $\rightarrow$ `{ "UIController", "WorldController", "AudioController", "AnimationController" }`


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
