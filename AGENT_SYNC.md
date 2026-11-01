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
