# 🛠️ CLIENT_TECHNICAL_SPEC.md — Техническое задание на реализацию Client-модулей

**Владелец:** Agent 2 (`anarugod`)  
**Статус:** Реализовано и интегрировано с Core Framework  
**Ветка:** `feature/agent2-client-design`

---

## 1. Общие технические требования к клиентским модулям

1. **Строгая типизация:** Каждый файл в `src/client/` начинается с `--!strict` и заголовка `@module`, `@owner Agent 2 (anarugod)`, `@description`.
2. **Единый жизненный цикл (`LifecycleModule`):**
   - Все контроллеры в `src/client/Controllers/` экспортируют `Name: string`, `Dependencies: { string }`, `:Init(registry)`, `:Start()` и `:Shutdown()`.
   - В `Init(registry)` разрешено только разрешение зависимостей через `registry:Get(...)` и подготовка локальных структур данных без блокировки потока.
   - В `Start()` выполняется монтирование `ScreenGui`, создание 3D-объектов в `Workspace` и подписка на `Network.OnClientEvent` / `UserInputService`.
   - В `Shutdown()` все `RBXScriptConnection` и `SignalConnection` отключаются, а созданные GUI/3D-инстансы очищаются.

---

## 2. Декомпозиция клиентских модулей (Модули К1–К5)

### Модуль К1: Презентационное ядро (`AudioController` & `AnimationController`)
- **Расположение:**
  - `src/client/Controllers/AudioController.luau`
  - `src/client/Controllers/AnimationController.luau`
- **Зависимости:** `{}` (Уровень 1 DAG)
- **Задачи:**
  1. Реализовать таблицу звуковых пресетов (`Click`, `UIButton`, `Purchase`, `Error`, `LevelUp`, `ZoneUnlock`) с поддержкой случайного отклонения питча (`pitchVariance`) и глобального флага `isMuted`.
  2. Реализовать неблокирующие Tween-эффекты интерфейса (`Bounce`, `Pulse`, `PopIn`) через `UIScale` и `TweenService`, а также триггер анимаций действий (`PlayActionAnimation`).
- **Критерии готовности (DoD):**
  - Вызов `PlaySFX` при `IsMuted() == true` не создаёт `Sound` инстансов.
  - Вызов `PlayUIEffect("PopIn", frame)` плавно анимирует масштаб окна при открытии.

---

### Модуль К2: UI Framework, `WindowManager` и `UIController`
- **Расположение:**
  - `src/client/UI/Theme.luau`
  - `src/client/UI/WindowManager.luau`
  - `src/client/UI/Components/HUDComponent.luau`
  - `src/client/UI/Components/WindowComponent.luau`
  - `src/client/UI/Components/NotificationComponent.luau`
  - `src/client/UI/Components/ShopView.luau`
  - `src/client/UI/Components/InventoryView.luau`
  - `src/client/UI/Components/QuestsView.luau`
  - `src/client/UI/Components/RebirthView.luau`
  - `src/client/Controllers/UIController.luau`
- **Зависимости `UIController`:** `{ "AudioController", "AnimationController" }` (Уровень 2 DAG)
- **Задачи:**
  1. Реализовать `WindowManager` с поддержкой регистрации окон, эксклюзивного открытия (`Open` автоматически закрывает предыдущее активное окно), `Close`, `CloseAll`, `Toggle`, `IsAnyWindowOpen` и сигнала `OnWindowChanged`.
  2. В `UIController` монтировать `ScreenGui` (`SimulatorUI`), инициализировать `HUDComponent`, `NotificationComponent` и регистрировать 4 модальных экрана (`Shop`, `Inventory`, `Quests`, `Rebirth`) в `WindowManager`.
  3. Подписаться на все 6 событий `Server -> Client` (`PlayerDataSync`, `CurrencyUpdated`, `InventoryUpdated`, `ProgressionUpdated`, `QuestUpdated`, `Notification`) и реактивно обновлять HUD и открытые представления.
- **Критерии готовности (DoD):**
  - Одновременно может быть открыто только одно модальное окно.
  - Любое изменение баланса, инвентаря, квестов или ребиртов мгновенно отражается в открытом окне без необходимости его переоткрывать.

---

### Модуль К3: Игровой мир и зоны (`WorldController`, `ZoneGateManager`, `ItemDisplayManager`)
- **Расположение:**
  - `src/client/Controllers/WorldController.luau`
  - `src/client/World/Zones/ZoneGateManager.luau`
  - `src/client/World/Items/ItemDisplayManager.luau`
- **Зависимости `WorldController`:** `{ "UIController", "AudioController" }` (Уровень 3 DAG)
- **Задачи:**
  1. В `ZoneGateManager` создавать и обновлять силовые барьеры `Gate_<zoneId>` в `Workspace.SimulatorZones` на основе `ZonesConfig` и таблицы `unlockedZones`.
  2. Подключить `ProximityPrompt` на закрытых барьерах к методу `WorldController:RequestUnlockZone(zoneId)`.
  3. В `ItemDisplayManager` синхронизировать активный `equippedToolUid` и список `equippedPetUids` при каждом обновлении инвентаря.
- **Критерии готовности (DoD):**
  - При получении `ProgressionUpdated` с новой открытой зоной барьер зоны становится полупрозрачным, отключает коллизию (`CanCollide = false`) и скрывает `ProximityPrompt`.

---

### Модуль К4: Система интеракций и ввода (`InteractionController`)
- **Расположение:** `src/client/Controllers/InteractionController.luau`
- **Зависимости:** `{ "UIController", "WorldController", "AudioController", "AnimationController" }` (Уровень 4 DAG)
- **Задачи:**
  1. Реализовать `TriggerPrimaryAction()` с проверкой `interactionEnabled` и кулдауна `GameConfig.Simulator.ClickCooldownSeconds`.
  2. Подключить `UserInputService.InputBegan` для:
     - кликов в мире (`MouseButton1`, `Touch`, `ButtonR2`), если не открыто модальное окно (`not UIController:IsAnyWindowOpen()`);
     - горячих клавиш окон (`F` — `Shop`, `B` — `Inventory`, `Q` — `Quests`, `R` — `Rebirth`, `Escape` — закрытие текущего окна).
  3. Предоставить типизированные методы отправки клиентских намерений (`RequestShopPurchase`, `RequestEquipItem`, `RequestRebirth`, `RequestClaimQuest`).
- **Критерии готовности (DoD):**
  - Клики при открытом модальном окне не вызывают `TriggerPrimaryAction()`.
  - Горячие клавиши `F`, `B`, `Q`, `R` и `Escape` корректно переключают и закрывают модальные окна через `UIController`.

---

### Модуль К5: Модульное тестирование клиентской архитектуры (`FrameworkTests.luau`)
- **Расположение:** `src/shared/Tests/FrameworkTests.luau`
- **Задачи:**
  1. Проверить топологическую сортировку 5 клиентских контроллеров в `Registry`.
  2. Проверить работу `WindowManager` (эксклюзивное открытие окон, `Toggle`, `CloseAll`, `IsAnyWindowOpen`).
