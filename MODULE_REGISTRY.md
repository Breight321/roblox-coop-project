# 📦 MODULE_REGISTRY.md — Universal Roblox Framework Module Catalog

Этот реестр описывает все **18 модулей** универсального фреймворка, их границы ответственности, зависимости, владельцев и статус готовности. Любая игра в Roblox может установить только те модули, которые ей необходимы.

---

## 1. Сводная таблица 18 модулей фреймворка

| № | Модуль | Путь в репозитории | Владелец | Зависимости (`Dependencies`) | Версия | Статус |
|---|---|---|---|---|---|---|
| 1 | **Core** | `src/shared/Core/` (`Registry`, `Signal`, `Logger`, `TestRunner`) | Agent A | Нет (`0`) | `1.0.0` | ✅ Ready |
| 2 | **Shared** | `src/shared/Core/` (`Types`, `Network`) + `src/shared/Remotes.luau` | Shared | `Core` | `1.0.0` | ✅ Ready |
| 3 | **Data** | `src/server/Services/PlayerDataService/` | Agent A | `Core`, `Shared` | `1.0.0` | ✅ Ready |
| 4 | **Economy** | `src/server/Services/EconomyService/` | Agent A | `Core`, `Shared`, `Data` | `1.0.0` | ✅ Ready |
| 5 | **Inventory** | `src/server/Services/InventoryService/` | Agent A | `Core`, `Shared`, `Data`, `Items` | `1.0.0` | ✅ Ready |
| 6 | **Items** | `src/shared/Config/ItemsConfig.luau` | Shared | `Shared` | `1.0.0` | ✅ Ready |
| 7 | **Progression** | `src/server/Services/ProgressionService.luau` | Agent A | `Core`, `Shared`, `Data`, `Economy` | `1.0.0` | ✅ Ready |
| 8 | **Shop** | `src/server/Services/ShopService.luau` + `src/client/UI/ShopUI/` | Agent A & B | `Economy`, (`Inventory` опционально через адаптер) | `1.0.0` | ✅ Ready |
| 9 | **Quests** | `src/server/Services/QuestService.luau` | Agent A | `Core`, `Shared`, `Data`, `Economy` | `1.0.0` | ✅ Ready |
| 10 | **Achievements** | `src/server/Services/AchievementService.luau` *(Planned)* | Agent A | `Core`, `Shared`, `Data`, `Economy` | `0.1.0` | 📋 Planned |
| 11 | **Pets** | `src/client/World/Items/` *(Optional Adapter)* | Agent A & B | `Inventory`, `Items`, `Effects` | `0.2.0` | 🔄 Optional |
| 12 | **Trading** | `src/server/Services/TradingService.luau` *(Planned)* | Agent A | `Data`, `Economy`, `Inventory` | `0.1.0` | 📋 Planned |
| 13 | **World** | `src/client/Controllers/WorldController.luau` + `src/client/World/Zones/` | Agent B | `Core`, `Shared`, `UI` | `1.0.0` | ✅ Ready |
| 14 | **Interaction** | `src/client/Controllers/InteractionController.luau` | Agent B | `Core`, `Shared` | `1.0.0` | ✅ Ready |
| 15 | **UI** | `src/client/Controllers/UIController.luau` + `src/client/UI/` | Agent B | `Core`, `Shared` | `1.0.0` | ✅ Ready |
| 16 | **Monetization** | `src/server/Services/MonetizationService.luau` *(Planned)* | Agent A | `Core`, `Shared`, `Data`, `Economy` | `0.1.0` | 📋 Planned |
| 17 | **Audio** | `src/client/Controllers/AudioController.luau` | Agent B | `Core`, `Shared` | `1.0.0` | ✅ Ready |
| 18 | **Effects** | `src/client/Controllers/AnimationController.luau` | Agent B | `Core`, `Shared` | `1.0.0` | ✅ Ready |

---

## 2. Матрица независимости модулей (Module Independence Guarantees)

1. **`Core` + `Shared`** работают автономно в любом проекте без единого игрового сервиса.
2. **`Data` (`PlayerDataService`)** работает с любой пользовательской схемой профиля (`RegisterSchemaSection`) и не требует ни `Economy`, ни `Inventory`, ни `Progression`.
3. **`Economy` (`EconomyService`)** работает **без** `Inventory`, `Items`, `Pets`, `World` и `Shop`. Внешние системы подключают свои бонусы/множители через публичный контракт `EconomyService:RegisterMultiplierModifier(id, callback)`.
4. **`Inventory` (`InventoryService`)** работает **без** `Pets`, `Economy` и `Shop`. Слоты экипировки и стекирование задаются в `InventoryService/Config.luau`.
5. **`UI` (`WindowManager`, `NotificationComponent`, `ShopUI`)** не содержит серверной логики экономики или сохранения и общается с бэкендом исключительно через публичные сетевые контракты.
