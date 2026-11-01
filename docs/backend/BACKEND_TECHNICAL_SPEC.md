# 📋 BACKEND_TECHNICAL_SPEC.md — Техническое задание на реализацию Backend-модулей

**Владелец:** Agent 1 (`Breight321`)  
**Статус:** Готово к разработке после подтверждения контрактов  
**Ветка:** `feature/agent1-backend-design`

---

## 1. Цель технического задания

Данное ТЗ определяет точные требования к реализации, обработке краевых случаев, безопасности и тестированию серверных модулей **Roblox Simulator Framework** (зона ответственности **Agent 1**) для бесшовной работы с уже созданным UI и клиентскими контроллерами **Agent 2 (`anarugod`)**.

---

## 2. Декомпозиция задач по модулям (Backend Modules Spec)

### Модуль Б1: `PlayerDataService` (`src/server/Services/PlayerDataService.luau`)
- **Приоритет:** Критический (Blocker для остальных сервисов)
- **Требования к реализации:**
  1. Реализовать обёртку хранилища с автоматическим переключением между `DataStoreService:GetDataStore(GameConfig.DataStoreName)` и `InMemoryStore` (для неопубликованных плейсов в Roblox Studio).
  2. Внедрить конверт хранения `PlayerProfileEnvelope` с блокировкой сессии (`sessionJobId`, `sessionLockTimestamp`, таймаут 300 сек).
  3. Реализовать функции `ReconcileProfile(rawData)` и `MigrateProfile(rawData)` для безопасного обновления структуры профиля.
  4. Реализовать фоновый цикл автосохранения каждые `GameConfig.AutoSaveIntervalSeconds` (60 сек) только для изменённых (`dirty`) профилей.
  5. В `Shutdown()` реализовать параллельное сохранение всех онлайн-игроков с снятием `sessionJobId`.
- **Критерии приёмки (DoD):**
  - При входе игрока создаётся папка `leaderstats` (`Coins`, `Gems`, `Rebirths`) и клиенту уходит `PlayerDataSync`.
  - Повторный вызов `UpdateProfile` с ошибкой внутри мутатора не повреждает профиль и возвращает `Err("MUTATOR_ERROR")`.

---

### Модуль Б2: `EconomyService` (`src/server/Services/EconomyService.luau`)
- **Приоритет:** Высокий (Реализация после согласования `ECONOMY_INVENTORY_CONTRACTS.md`)
- **Требования к реализации:**
  1. Реализовать `GetMultiplierBreakdown(player, currencyId)` с учётом:
     - бонуса ребиртов (`1 + rebirths * RebirthBonusMultiplierPerRebirth`);
     - бонуса экипированных предметов (`Tool` и `Pet` из `ItemsConfig`);
     - бонуса максимальной открытой зоны из `ZonesConfig`.
  2. В `ProcessSimulatorClick(player, clientToolUid)` добавить допуск на сетевой джиттер (`ClickCooldownSeconds * 0.85`), чтобы легитимные клики от `InteractionController` не отбрасывались из-за колебаний пинга.
  3. Генерировать серверный сигнал `OnSimulatorClickProcessed:Fire(player, gain, clientToolUid)`, на который подпишутся `ProgressionService` (начисление `BaseXPPerClick`) и `QuestService` (прогресс квестов `"Clicks"` и `"EarnCoins"`).
- **Критерии приёмки (DoD):**
  - Клиент при клике получает `CurrencyUpdated`, `QuestUpdated` и `ProgressionUpdated`.
  - Попытка списать больше текущего баланса возвращает `Err("INSUFFICIENT_FUNDS")` без изменения баланса.

---

### Модуль Б3: `InventoryService` (`src/server/Services/InventoryService.luau`)
- **Приоритет:** Высокий (Реализация после согласования `ECONOMY_INVENTORY_CONTRACTS.md`)
- **Требования к реализации:**
  1. Реализовать методы `GetInventory`, `GetItem`, `HasItemByTemplate`, `GetCapacityInfo`, `GrantItem`, `RemoveItem`, `EquipItem`, `GetEquippedItems`.
  2. Защитить стартовый предмет `starter_wand_default` от удаления через `RemoveItem`.
  3. При попытке экипировать больше `MaxEquippedPets` (3) возвращать `Err("MAX_PETS_EQUIPPED")` и отправлять клиенту `Network.Events.Notification("Warning", "Максимум питомцев уже экипировано!")`.
- **Критерии приёмки (DoD):**
  - В `InventoryView` (Agent 2) нажатие `EQUIP / UNEQUIP` мгновенно переключает рамку и статус предмета, а `WorldController` получает обновлённый `equippedToolUid`.

---

### Модуль Б4: `ProgressionService`, `ShopService`, `QuestService`
- **Приоритет:** Средний (Слой геймплейных правил)
- **Требования к реализации:**
  1. **`ProgressionService`:**
     - Подписаться на `EconomyService.OnSimulatorClickProcessed` для автоматического начисления `GameConfig.Simulator.BaseXPPerClick`.
     - При успешном `PerformRebirth` и `UnlockZone` отправлять клиенту `Notification("Reward", ...)` и вызывать прогресс квестов.
  2. **`ShopService`:**
     - При обработке `RequestShopPurchase` проверять `requiredRebirths`, `requiredZoneId` и не позволять покупать дубликат уже имеющегося `Tool` (возвращать `Err("ALREADY_OWNED")` + уведомление клиенту).
  3. **`QuestService`:**
     - Автоматически подписываться в `Start()` на сигналы:
       - `EconomyService.OnSimulatorClickProcessed` -> цели `"Clicks"` (+1) и `"EarnCoins"` (+gain)
       - `ProgressionService.OnRebirth` -> цель `"Rebirths"` (+1)
       - `ProgressionService.OnZoneUnlocked` -> цель `"UnlockZones"` (+1)
     - При выполнении квеста отправлять `Notification("Reward", "Квест выполнен!")`.

---

## 3. План модульного и интеграционного тестирования (`src/shared/Tests/FrameworkTests.luau`)

В тестовый набор добавляются проверки Backend-контрактов (без необходимости реального игрока в игре — через mock-профиль):
1. **Тест миграции и сверки профиля (`PlayerDataService`):** проверка восстановления отсутствующих полей и валидации схемы.
2. **Тест формулы множителей (`EconomyService`):** проверка расчёта дохода при комбинации ребиртов + экипированного `Tool` + `Pet`.
3. **Тест ограничений экипировки (`InventoryService`):** проверка, что экипировка второго `Tool` автоматически снимает первый, а 4-й `Pet` отклоняется с кодом `MAX_PETS_EQUIPPED`.
4. **Тест транзакционности магазина (`ShopService`):** проверка отката списанных монет (`Rollback`), если выдача предмета вернула `INVENTORY_FULL`.
