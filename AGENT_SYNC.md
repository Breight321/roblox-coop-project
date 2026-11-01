# 📡 AGENT SYNC BOARD (Breight321 & anarugod)

## 1. 👥 Кто над чем работает (Распределение ролей)
- **Agent A (`Breight321` — Lead Architect / Backend):**
  - Core Framework (`src/shared/Core/`)
  - Module initialization / lifecycle (`Registry.luau`)
  - Service architecture (`src/server/Services/`)
  - Player Data architecture (`PlayerDataService.luau`)
  - Economy Backend (`src/server/Services/EconomyService/`)
  - Shared Types и API Contracts (`src/shared/Core/Types.luau`, `Network.luau`)
  - Server-side validation & Backend tests (`EconomyTests.luau`, `FrameworkTests.luau`)
- **Agent B (`anarugod` — Gameplay / Client):**
  - UI Framework & Window Manager (`src/client/UI/WindowManager.luau`)
  - Shop UI & Gameplay Views (`ShopView.luau`, `InventoryView.luau`, `QuestsView.luau`, `RebirthView.luau`)
  - Client Controllers (`src/client/Controllers/`)
  - Interaction System & World/Zone Systems (`src/client/World/`)
  - UI states (`Loading / Success / Error`) & notifications (`NotificationComponent.luau`)

---

## 2. 📂 Какие файлы редактируются
- **Agent A (`Breight321`) редактирует:**
  - `src/server/Services/EconomyService/*` (`init.luau`, `Types.luau`, `Config.luau`, `README.md`, `tests/EconomyTests.luau`)
  - `src/server/Services/PlayerDataService.luau`, `InventoryService.luau`, `ShopService.luau`, `ProgressionService.luau`, `QuestService.luau`
  - `src/server/init.server.luau`
  - `src/shared/Core/Types.luau`, `src/shared/Core/Network.luau`, `src/shared/Config/ShopConfig.luau`
  - `AGENTS.md`, `AGENT_SYNC.md`, `TASKS.md`, `docs/*`
- **Agent B (`anarugod`) редактирует:**
  - `src/client/Controllers/*`
  - `src/client/UI/*` (`WindowManager.luau`, `Components/ShopView.luau`, и др.)
  - `src/client/World/*`

---

## 3. 🌿 Текущие feature-ветки
- `main` — стабильная релизная ветка (прямой push запрещён)
- `develop` — интеграционная ветка (через Pull Requests)
- `feature/economy-backend-hardening` — активная ветка Agent A (`Breight321`) для Phase 2
- `feature/agent2-client-design` / `feature/shop-ui-*` — ветки Agent B (`anarugod`)

---

## 4. 🤝 Согласованные API (Economy Backend + Shop UI)
- **`EconomyService` (Server):**
  - `GetBalance(player, currencyId): number`
  - `CanAfford(player, currencyId, amount): boolean`
  - `ValidateAmount(currencyId, amount): Result<number, EconomyErrorCode>`
  - `AddCurrency(player, currencyId, amount, reason?): Result<number, EconomyErrorCode>`
  - `RemoveCurrency(player, currencyId, amount, reason?): Result<number, EconomyErrorCode>`
  - `GetMultiplier(player, currencyId): number` / `GetMultiplierBreakdown(player, currencyId): MultiplierBreakdown`
  - `ProcessSimulatorClick(player, clientToolUid?): Result<number, EconomyErrorCode>`
  - `GetTransactionHistory(player): { EconomyTransactionRecord }`
- **`ShopService` <-> `Shop UI` Сетевой контракт (`Network.Events`):**
  - Запрос (`Client -> Server`): `RequestShopPurchase(shopItemId: string)` (клиент передаёт только ID товара; цена и валюта проверяются строго на сервере по `ShopConfig`).
  - Ответы (`Server -> Client`):
    - `CurrencyUpdated(currencyId, newBalance, delta)`
    - `InventoryUpdated(inventory)`
    - `ShopPurchaseResult(response: ShopPurchaseResponse)` — детальный статус `{ ok, shopItemId, itemId, itemUid, currencyId, pricePaid, newBalance, errorCode, message }` для состояний кнопки `Loading / Success / Error`.
    - `Notification(notifType, message)`

---

## 5. 🔗 Зависимости между модулями
- `EconomyService` $\rightarrow$ `{ "PlayerDataService" }`
- `InventoryService` $\rightarrow$ `{ "PlayerDataService" }`
- `ProgressionService` $\rightarrow$ `{ "PlayerDataService", "EconomyService" }`
- `QuestService` $\rightarrow$ `{ "PlayerDataService", "EconomyService", "ProgressionService" }`
- `ShopService` $\rightarrow$ `{ "PlayerDataService", "EconomyService", "InventoryService" }`
- `UIController` $\rightarrow$ `{ "AudioController", "AnimationController" }`
- `WorldController` $\rightarrow$ `{ "UIController", "AudioController" }`
- `InteractionController` $\rightarrow$ `{ "UIController", "WorldController", "AudioController", "AnimationController" }`

---

## 6. ✅ Статусы задач (Phase 2)
- [x] Исправление Git Workflow и обновление `AGENTS.md`
- [x] Единый стандарт модулей (`docs/MODULE_STANDARD.md` и пакет `EconomyService/`)
- [x] Согласование API `Economy Backend + Shop UI` в GitHub Issue #1
- [x] Реализация и тестирование `EconomyService` + `ShopService` + безопасного `PlayerDataService` (Agent A)
- [x] Реализация `WindowManager` и `ShopView` / клиентских контроллеров (Agent B)
- [x] Документация в `docs/ARCHITECTURE.md`, `docs/API_REGISTRY.md`, `docs/MODULE_STANDARD.md`, `docs/CONTRIBUTING.md`, `docs/INTEGRATION_GUIDE.md`

---

## 7. ⚠️ Проблемы интеграции
- **Обнаружено и решено:**
  1. Прямой push в `main` из раннего шаблона `AGENTS.md` заменён на строгий Gitflow (`feature/*` $\rightarrow$ PR $\rightarrow$ `develop` $\rightarrow$ `main`).
  2. Добавлено событие `Network.Events.ShopPurchaseResult` и поле `category` в `ShopConfig`, чтобы `Shop UI` получал явное подтверждение/ошибку каждой покупки для состояний `Loading / Success / Error` и фильтрации по категориям.
  3. Добавлен автоматический возврат средств (`Rollback`) в `ShopService`, если выдача предмета в `InventoryService` завершилась ошибкой (`INVENTORY_FULL`).
