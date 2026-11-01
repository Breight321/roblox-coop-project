# 📋 TASKS.md — Распределение задач и дорожная карта проекта

## 👥 Зоны ответственности агентов

| Направление | Ответственный агент | Папки в репозитории |
|---|---|---|
| **Core Framework, Player Data, Economy, Inventory, Progression, Shop Backend, Quest Backend** | **AGENT 1 (`Breight321`)** | `src/shared/Core/`, `src/server/Services/` |
| **UI Framework, UI Components, Interaction System, World & Zone System, Item Components, Audio, Animation, Client Controllers** | **AGENT 2 (`anarugod`)** | `src/client/Controllers/`, `src/client/UI/`, `src/client/World/` |
| **Архитектура, API Contracts, Shared Types, Configs, Интеграция, Тестирование, Документация** | **SHARED (`Breight321` & `anarugod`)** | `src/shared/Config/`, `src/shared/Tests/`, `/*.md` |

---

## 🚀 PHASE 1 — Joint Architecture & Project Initialization (Завершён)

### Общие задачи (Shared)
- [x] **T1.1:** Первичный аудит GitHub-репозитория и веток
- [x] **T1.2:** Создание интеграционной ветки `develop`
- [x] **T1.3:** Разработка и фиксация `ARCHITECTURE.md`, `API_REGISTRY.md`, `MODULE_STANDARD.md`, `CONTRIBUTING.md`, `TASKS.md`, `CHANGELOG.md`
- [x] **T1.4:** Согласование общих Luau Types (`src/shared/Core/Types.luau`) и конфигураций (`src/shared/Config/*`)

### Задачи AGENT 1 (`Breight321`)
- [x] **T1.5:** Реализация `Registry.luau` (Module Loader с проверкой DAG-зависимостей и жизненным циклом `Init -> Start -> Shutdown`)
- [x] **T1.6:** Реализация `Signal.luau`, `Logger.luau`, `Network.luau` (поверх `Remotes.luau`) и `TestRunner.luau`
- [x] **T1.7:** Создание базовых модулей-сервисов сервера (`PlayerDataService`, `EconomyService`, `InventoryService`, `ProgressionService`, `ShopService`, `QuestService`) по стандарту `API_REGISTRY.md`
- [x] **T1.8:** Обновление серверного Bootstrap (`src/server/init.server.luau`) и модульных тестов (`src/shared/Tests/FrameworkTests.luau`)

### Задачи AGENT 2 (`anarugod`)
- [x] **T1.9:** Аудит предложенной архитектуры и подтверждение клиентских контрактов в `API_REGISTRY.md`
- [x] **T1.10:** Подготовка структуры клиентских контроллеров (`UIController`, `InteractionController`, `WorldController`, `AudioController`, `AnimationController`) в `src/client/Controllers/`
- [x] **T1.11:** Подготовка базовой структуры `src/client/UI/Components/` и `src/client/World/` (`Zones`, `Items`)
- [x] **T1.12:** Проверка независимого запуска клиентского Bootstrap (`src/client/init.client.luau`) с использованием `Registry.luau`

---

## 🔜 PHASE 2 — Core Gameplay Loop & Client-Server Integration (Следующий этап)
- [ ] **T2.1 (Agent 1):** Полная реализация сохранения в `DataStoreService` с автосохранением и миграциями схем
- [ ] **T2.2 (Agent 2):** Реализация главного HUD (отображение валют, кнопки Магазина, Инвентаря, Ребиртов, Квестов)
- [ ] **T2.3 (Agent 1 & 2):** Сквозная интеграция клика симулятора (`InteractionController` -> `EconomyService` -> `UIController` + `AudioController` + `AnimationController`)
- [ ] **T2.4 (Agent 1 & 2):** Сквозная интеграция открытия зон (`WorldController` <-> `ProgressionService`)
