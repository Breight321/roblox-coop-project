# 📝 CHANGELOG.md

Все значимые изменения в проекте **Universal Reusable Roblox Framework** документируются в этом файле.

## [1.0.0] — 2026-11-01 (Universal Reusable Roblox Framework Migration)

### Added
- **Полный пакет документации универсального фреймворка:**
  - `MODULE_REGISTRY.md` — реестр 18 модулей с версиями, зависимостями и границами ответственности.
  - `API_REFERENCE.md` — справочник публичных API универсальных модулей.
  - `QUICK_START.md` — руководство по быстрой установке всего фреймворка или отдельных модулей в любую новую игру Roblox.
  - `VERSIONING.md` — политика семантического версионирования (`SemVer`).
  - `INTEGRATION_GUIDE.md` — паттерны слабосвязанной интеграции через адаптеры (`RegisterMultiplierModifier`, `RegisterSchemaSection`).
  - `src/shared/Core/README.md` — документация ядра (`Core` & `Shared`).
- **Декуплинг и универсализация модулей:**
  - В `EconomyService` добавлены `RegisterCurrency` и `RegisterMultiplierModifier` / `RemoveMultiplierModifier`, полностью удалены прямые импорты `ItemsConfig` и `ZonesConfig`.
  - В `PlayerDataService` добавлены `RegisterSchemaSection` и `RegisterMigration` для расширяемых пользовательских профилей.
  - В `InventoryService` добавлены `SetCategoryEquipLimit`, поддержка стекирования (`quantity`) и опциональный адаптер множителей для `EconomyService`.
  - В `Network.luau` добавлен метод `Network.RegisterEvent(eventName)`.

## [0.2.0] — 2026-11-01 (Phase 2: Repository Hardening & Economy + Shop UI Integration)
- Модульные пакеты `src/server/Services/EconomyService/` и `src/client/UI/ShopUI/` со встроенными тестами (`EconomyTests.luau`, `ShopUITests.luau`).
- Контракт `ShopPurchaseResult` и состояния `Loading / Success / Error` в `ShopUI`.
- Защита от дублирования транзакций, rate limiting и двухфазный Rollback в `ShopService`.

## [0.1.0] — 2026-11-01 (Phase 1: Joint Architecture & Project Initialization)
- Базовая архитектура `Core Framework`, `Registry` (DAG), `Signal`, `Network`, `Logger`, `TestRunner`.
