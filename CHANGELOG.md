# 📝 CHANGELOG.md

Все значимые изменения в проекте **Roblox Simulator Framework** документируются в этом файле.

## [0.1.0] — 2026-11-01 (Phase 1: Joint Architecture & Project Initialization)

### Added
- **Документация проекта:**
  - `ARCHITECTURE.md` — полное описание 15 систем фреймворка, графа зависимостей и структуры папок.
  - `API_REGISTRY.md` — единый реестр публичных интерфейсов, типов и сетевых событий.
  - `MODULE_STANDARD.md` — стандарт написания модулей Luau (`--!strict`, `Result<T, E>`, жизненный цикл).
  - `CONTRIBUTING.md` — правила работы с ветками (`main`, `develop`, `feature/*`) и кооперации двух агентов.
  - `TASKS.md` и `CHANGELOG.md` — план работ и журнал изменений.
- **Core Framework (`src/shared/Core/`):**
  - `Types.luau` — строгие Luau-типы для всех систем фреймворка.
  - `Logger.luau` — структурированное логирование.
  - `Signal.luau` — типизированная шина событий с методом `Destroy()`.
  - `Network.luau` — типизированный сетевой слой поверх `Remotes.luau`.
  - `Registry.luau` — контейнер модулей с топологической сортировкой зависимостей, защитой от циклов и жизненным циклом `Init -> Start -> Shutdown`.
  - `TestRunner.luau` — встроенная среда тестирования модулей.
- **Configuration System (`src/shared/Config/`):**
  - Добавлены базовые конфигурации: `GameConfig.luau`, `CurrenciesConfig.luau`, `ItemsConfig.luau`, `ZonesConfig.luau`, `ShopConfig.luau`, `QuestsConfig.luau`.
- **Server Services (`src/server/Services/` — Agent 1):**
  - Созданы базовые сервисы с согласованным API: `PlayerDataService`, `EconomyService`, `InventoryService`, `ProgressionService`, `ShopService`, `QuestService`.
- **Client Controllers & UI/World Systems (`src/client/` — Agent 2):**
  - Созданы клиентские контроллеры с DAG-зависимостями: `AudioController`, `AnimationController`, `UIController`, `WorldController`, `InteractionController`.
  - Реализована модульная система интерфейса (`Theme.luau`, `HUDComponent.luau`, `WindowComponent.luau`, `NotificationComponent.luau`).
  - Реализованы клиентские системы мира и зон (`ZoneGateManager.luau`, `ItemDisplayManager.luau`).
- **Bootstrap & Tests:**
  - Обновлены `src/server/init.server.luau` и `src/client/init.client.luau` для работы через `Registry`.
  - Добавлен тестовый набор `src/shared/Tests/FrameworkTests.luau`.
