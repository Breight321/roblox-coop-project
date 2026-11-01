# 🎮 INTERACTION_AND_WORLD_SPEC.md — Спецификация Interaction System и World & Zone API

**Владелец:** Agent 2 (`anarugod`)  
**Статус:** Готово к согласованию и интеграции  
**Ветка:** `feature/agent2-client-design`

---

## 1. Проектирование Interaction System (`InteractionController.luau`)

`InteractionController` отвечает за обработку всех видов пользовательского ввода, защиту от спама на стороне клиента, мгновенный аудио-визуальный отклик и отправку типизированных намерений на сервер.

### 1.1 Кроссплатформенная матрица ввода

| Действие | PC (Keyboard / Mouse) | Mobile / Touch | Console (Gamepad) |
|---|---|---|---|
| **Основной клик симулятора** | `MouseButton1` в мире или кнопка HUD `⚡ COLLECT POWER` | Тап по экрану или кнопка HUD `⚡ COLLECT POWER` | `Enum.KeyCode.ButtonR2` |
| **Открыть / Закрыть Магазин (`Shop`)** | Кнопка HUD `Shop` / Клавиша `F` | Кнопка HUD `Shop` | Навигация по HUD |
| **Открыть / Закрыть Инвентарь (`Inventory`)** | Кнопка HUD `Inventory` / Клавиша `B` | Кнопка HUD `Inventory` | Навигация по HUD |
| **Открыть / Закрыть Квесты (`Quests`)** | Кнопка HUD `Quests` / Клавиша `Q` | Кнопка HUD `Quests` | Навигация по HUD |
| **Открыть / Закрыть Ребирты (`Rebirth`)** | Кнопка HUD `Rebirth` / Клавиша `R` | Кнопка HUD `Rebirth` | Навигация по HUD |
| **Закрыть текущее модальное окно** | Клавиша `Escape` или кнопка `X` | Кнопка `X` в заголовке окна | `Enum.KeyCode.ButtonB` |
| **Открытие новой зоны в мире** | Клавиша `E` на `ProximityPrompt` у ворот зоны | Тап по `ProximityPrompt` | `Enum.KeyCode.ButtonX` |

### 1.2 Пайплайн обработки клика симулятора (`TriggerPrimaryAction`)

1. **Проверка доступности:**
   - Если `not interactionEnabled` -> возврат `Types.Err("INTERACTION_DISABLED")`.
2. **Проверка клиентского кулдауна (Rate Limiting):**
   - Сравнивается `os.clock() - lastClickClock < GameConfig.Simulator.ClickCooldownSeconds` (`0.15s`).
   - При превышении частоты кликов возвращается `Types.Err("CLICK_COOLDOWN")` без отправки сетевого пакета (экономия трафика `RemoteEvent`).
3. **Определение активного инструмента:**
   - Запрашивается `local equippedToolUid = WorldController:GetEquippedToolUid()`.
4. **Мгновенный клиентский отклик (Zero-Latency Feedback):**
   - `AudioController:PlaySFX("Click", 0.08)` (случайная вариация питча ±8% для естественного звучания).
   - `AnimationController:PlayActionAnimation("SimulatorSwing")`.
5. **Отправка намерения на сервер:**
   - `Network.FireServer(Network.Events.RequestActionClick, equippedToolUid)`.
   - Генерация локального сигнала `OnPrimaryActionTriggered:Fire(equippedToolUid)`.

### 1.3 Публичный API `InteractionController`

| Метод | Сигнатура | Описание |
|---|---|---|
| `TriggerPrimaryAction` | `(self) -> Result<boolean, string>` | Выполняет клик симулятора с проверкой кулдауна и отправкой `RequestActionClick`. |
| `SetInteractionEnabled` | `(self, enabled: boolean) -> ()` | Блокирует или разрешает игровые действия (например, во время катсцен/переходов). |
| `IsInteractionEnabled` | `(self) -> boolean` | Возвращает текущий статус активности ввода. |
| `RequestShopPurchase` | `(self, shopItemId: string) -> ()` | Валидирует непустой `shopItemId` и отправляет `RequestShopPurchase`. |
| `RequestEquipItem` | `(self, itemUid: string, equip: boolean) -> ()` | Валидирует `itemUid` и отправляет `RequestEquipItem`. |
| `RequestRebirth` | `(self) -> ()` | Отправляет `RequestRebirth` на сервер. |
| `RequestClaimQuest` | `(self, questId: string) -> ()` | Валидирует `questId` и отправляет `RequestClaimQuest`. |

---

## 2. Архитектура и API World & Zone System

Система мира разделена на оркестратор `WorldController` и два специализированных менеджера в `src/client/World/`:
1. **`ZoneGateManager` (`src/client/World/Zones/ZoneGateManager.luau`)** — отвечает за 3D-барьеры между локациями и `ProximityPrompt` для покупки доступа к зоне.
2. **`ItemDisplayManager` (`src/client/World/Items/ItemDisplayManager.luau`)** — отвечает за отслеживание и визуализацию экипированного оружия/инструмента (`Tool`) и активных питомцев (`Pet`).

### 2.1 Публичный API `WorldController` (`src/client/Controllers/WorldController.luau`)

| Метод | Сигнатура | Описание |
|---|---|---|
| `SyncUnlockedZones` | `(self, unlockedZones: { [string]: boolean }) -> ()` | Синхронизирует состояние открытых локаций с `ZoneGateManager` (отключает коллизию `CanCollide` и `ProximityPrompt` для открытых зон). |
| `RequestUnlockZone` | `(self, zoneId: string) -> ()` | Проверяет существование зоны в `ZonesConfig` и отправляет `Network.Events.RequestUnlockZone` на сервер. |
| `IsZoneUnlocked` | `(self, zoneId: string) -> boolean` | Возвращает `true`, если зона открыта у локального игрока. |
| `SetCurrentZone` | `(self, zoneId: string) -> ()` | Устанавливает текущую локацию игрока и генерирует сигнал `OnZoneEntered`. |
| `GetCurrentZone` | `(self) -> string` | Возвращает ID текущей зоны (по умолчанию `"spawn_meadow"`). |
| `GetZoneDef` | `(self, zoneId: string?) -> Types.ZoneDef?` | Возвращает конфигурацию указанной или текущей зоны из `ZonesConfig`. |
| `GetEquippedToolUid` | `(self) -> string?` | Возвращает `uid` текущего экипированного инструмента игрока. |
| `GetEquippedPetUids` | `(self) -> { string }` | Возвращает массив `uid` экипированных питомцев (до `MaxEquippedPets = 3`). |

### 2.2 Сигналы `WorldController`
- `OnZoneEntered: Signal<string>` — срабатывает при переходе игрока в новую зону.
- `OnZonesSynced: Signal<{ [string]: boolean }>` — срабатывает при обновлении списка разблокированных зон.

### 2.3 Механика `ZoneGateManager`
- Для каждой зоны из `ZonesConfig` (с `order > 1`) в папке `Workspace.SimulatorZones` создаётся или привязывается барьер `Gate_<zoneId>`.
- **Закрытая зона (`isUnlocked == false`):**
  - `CanCollide = true`, `Transparency = 0.25`, цвет барьера красный (`Color3.fromRGB(255, 92, 92)`).
  - Дочерний `ProximityPrompt` (`UnlockPrompt`) активен (`Enabled = true`), отображает название зоны (`ActionText = "Unlock " .. displayName`) и цену (`ObjectText = costAmount .. " " .. costCurrency`).
  - Срабатывание `ProximityPrompt.Triggered` вызывает `WorldController:RequestUnlockZone(zoneId)`.
- **Открытая зона (`isUnlocked == true`):**
  - `CanCollide = false`, `Transparency = 0.85`, цвет барьера зелёный (`Color3.fromRGB(88, 214, 122)`).
  - `ProximityPrompt.Enabled = false` (игрок свободно проходит сквозь ворота).
