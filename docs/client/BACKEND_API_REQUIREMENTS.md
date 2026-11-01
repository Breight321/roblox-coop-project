# 🔗 BACKEND_API_REQUIREMENTS.md — Требования Client-части к Backend API (На согласование с Agent 1)

**Владелец:** Agent 2 (`anarugod`)  
**Адресат согласования:** Agent 1 (`Breight321`)  
**Статус:** Согласовано с `docs/backend/ECONOMY_INVENTORY_CONTRACTS.md`  
**Ветка:** `feature/agent2-client-design`

---

## 1. Назначение документа

Данный документ фиксирует требования клиентских систем (`UIController`, `WindowManager`, `InteractionController`, `WorldController` и представлений `ShopView`, `InventoryView`, `QuestsView`, `RebirthView`) к серверным сервисам **Agent 1 (`Breight321`)**.

Никакие серверные сервисы на стороне Agent 2 не дублируются и не переопределяются — всё взаимодействие строится строго через `src/shared/Core/Network.luau` и `src/shared/Core/Types.luau`.

---

## 2. Требования к входящим событиям на сервере (`Client -> Server`)

| Событие `Network.Events` | Отправитель на клиенте | Аргументы | Ожидаемая реакция Backend (Agent 1) |
|---|---|---|---|
| `RequestActionClick` | `InteractionController:TriggerPrimaryAction()` | `(equippedToolUid: string?)` | 1. Проверить серверный анти-спам кулдаун (`ClickCooldownSeconds` с допуском 15% на сетевой джиттер).<br>2. Рассчитать доход с учётом `Rebirths`, экипированных `Tool`/`Pet` и открытых зон.<br>3. Начислить `Coins` (`CurrencyUpdated`), `XP` (`ProgressionUpdated`) и обновить прогресс квестов (`QuestUpdated`). |
| `RequestShopPurchase` | `ShopView` / `InteractionController:RequestShopPurchase()` | `(shopItemId: string)` | 1. Проверить наличие товара в `ShopConfig`, требования `requiredZoneId`/`requiredRebirths` и баланс.<br>2. Атомарно списать валюту и выдать предмет через `InventoryService:GrantItem`.<br>3. Отправить `CurrencyUpdated`, `InventoryUpdated` и `Notification("Success", ...)`. При отказе — `Notification("Error", ...)`. |
| `RequestEquipItem` | `InventoryView` / `InteractionController:RequestEquipItem()` | `(itemUid: string, equip: boolean)` | 1. Проверить владение предметом.<br>2. Для `Tool` — автоматически снять предыдущий `Tool`. Для `Pet` — проверить лимит `MaxEquippedPets = 3`.<br>3. Отправить `InventoryUpdated`. При превышении лимита — `Notification("Warning", ...)`. |
| `RequestRebirth` | `RebirthView` / `InteractionController:RequestRebirth()` | `()` | 1. Проверить стоимость ребирта `BaseRebirthCostCoins * (RebirthCostMultiplier ^ rebirths)`.<br>2. Сбросить `Coins`, `level`, `xp`, увеличить `rebirths += 1`, начислить `RebirthGemsReward`.<br>3. Отправить `PlayerDataSync` (или пару `CurrencyUpdated` + `ProgressionUpdated`) и `Notification("Reward", ...)`. |
| `RequestUnlockZone` | `WorldController:RequestUnlockZone()` (через `ProximityPrompt`) | `(zoneId: string)` | 1. Проверить `ZonesConfig[zoneId]`, `requiredRebirths` и баланс `Coins`.<br>2. Списать стоимость, записать `unlockedZones[zoneId] = true`.<br>3. Отправить `CurrencyUpdated`, `ProgressionUpdated` и `Notification("Success", ...)`. |
| `RequestClaimQuest` | `QuestsView` / `InteractionController:RequestClaimQuest()` | `(questId: string)` | 1. Проверить `questState.completed == true` и `questState.claimed == false`.<br>2. Пометить `claimed = true`, начислить `rewardCurrency` и `rewardXP`.<br>3. Отправить `QuestUpdated`, `CurrencyUpdated`, `ProgressionUpdated` и `Notification("Reward", ...)`. |

---

## 3. Требования к исходящим событиям сервера (`Server -> Client`)

1. **Гарантия начальной синхронизации (`PlayerDataSync`):**
   - Сразу после загрузки профиля в `PlayerDataService` сервер обязан отправить полный снимок `Types.PlayerProfileData` через `Network.Events.PlayerDataSync`.
   - Кроме того, учитывая что клиентские контроллеры могут завершиться чуть позже `PlayerAdded` в Studio, рекомендуется либо повторно отправлять `PlayerDataSync` при первом действии, либо гарантировать, что `PlayerDataSync` содержит все обязательные поля (`currencies`, `rebirths`, `level`, `xp`, `unlockedZones`, `inventory`, `quests`, `stats`).
2. **Консистентность гранулярных обновлений:**
   - `CurrencyUpdated(currencyId, newBalance, delta)` всегда передаёт точный итоговый баланс `newBalance` и знаковое изменение `delta`.
   - `InventoryUpdated(inventory)` передаёт актуальную карту `{ [uid]: InventoryItem }`.
   - `ProgressionUpdated(level, xp, rebirths, unlockedZones)` передаёт все 4 параметра одновременно, чтобы `HUDComponent`, `RebirthView` и `WorldController` (`ZoneGateManager`) синхронизировались за один кадр.
   - `QuestUpdated(questState)` передаёт обновлённый `Types.QuestState` конкретного квеста.
3. **Человекочитаемые уведомления (`Notification`):**
   - При любой бизнес-ошибке (нехватка монет, закрытая зона, лимит питомцев, повторная покупка инструмента) сервер отправляет `Network.Events.Notification("Warning" | "Error", message)`, чтобы `UIController` отобразил тост через `NotificationComponent` и воспроизвёл соответствующий SFX.
