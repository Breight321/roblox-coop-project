# 📋 TASKS.md — Распределение задач и статус разработки

## 👥 Роли агентов

| Агент | Роль | Зона ответственности |
|---|---|---|
| **Agent A (`Breight321`)** | Lead Architect / Backend | Core Framework, Module Lifecycle, Service Architecture, Player Data, Economy Backend, Shared Types & API Contracts, Server Validation, Backend Tests |
| **Agent B (`anarugod`)** | Gameplay / Client | UI Framework, Window Manager, Shop UI, Client Controllers, Interaction System, UI States & Notifications, Client Integration, UI Tests |

---

## ✅ PHASE 1 — Joint Architecture & Project Initialization (Завершено)
- [x] **T1.1–T1.4:** Первичный аудит, создание `develop`, базовая документация и общие типы (`Types.luau`, `Config/*`)
- [x] **T1.5–T1.8 (Agent A):** Core Framework (`Registry`, `Signal`, `Network`, `Logger`, `TestRunner`) и базовые сервисы сервера
- [x] **T1.9–T1.12 (Agent B):** Клиентские контроллеры (`UIController`, `InteractionController`, `WorldController`, `AudioController`, `AnimationController`), UI и World системы

---

## 🚀 PHASE 2 — Repository Hardening & First Integrated Systems (Economy + Shop UI)

### 1. Репозиторий, Git Workflow и Документация (Shared / Agent A)
- [x] **T2.1:** Обновить `AGENTS.md` — запретить прямой push в `main`, зафиксировать `feature/<module-name>` $\rightarrow$ PR $\rightarrow$ `develop`
- [x] **T2.2:** Создать/актуализировать `docs/ARCHITECTURE.md`, `docs/API_REGISTRY.md`, `docs/MODULE_STANDARD.md`, `docs/CONTRIBUTING.md`, `docs/INTEGRATION_GUIDE.md`
- [x] **T2.3:** Актуализировать `AGENT_SYNC.md` со всеми статусами, ветками, файлами и согласованными контрактами

### 2. Economy Backend & Player Data Hardening (Agent A — `Breight321`)
- [x] **T2.4:** Согласовать контракт `Economy Backend + Shop UI` с Agent B в Issue #1
- [x] **T2.5:** Перевести `EconomyService` на модульный стандарт `src/server/Services/EconomyService/` (`init.luau`, `Types.luau`, `Config.luau`, `README.md`, `tests/EconomyTests.luau`)
- [x] **T2.6:** Реализовать в `EconomyService` поддержку нескольких валют, настраиваемых лимитов, журнала транзакций, защиты от отрицательного баланса и серверной валидации
- [x] **T2.7:** Усилить `ShopService` (защита от параллельных/дублирующихся покупок, rate limiting, отправка `ShopPurchaseResult` и `Notification`, автоматический `Rollback`)
- [x] **T2.8:** Усилить `PlayerDataService` (Session Locking, `ReconcileAndSanitize`, `InMemoryStore` fallback для Studio, автосохранение по флагу `dirty`)

### 3. Shop UI & Window Manager Integration (Agent B — `anarugod`)
- [x] **T2.9:** Реализовать `WindowManager.luau` и модальные представления (`ShopView`, `InventoryView`, `QuestsView`, `RebirthView`)
- [x] **T2.10:** Интегрировать `Shop UI` с серверным `ShopService` / `EconomyService` (отправка `RequestShopPurchase`, реактивное обновление баланса и состояния кнопок)

---

## 🔜 PHASE 3 — Следующие шаги (Next Steps)
- [ ] **T3.1:** Интеграция системы питомцев (открытие яиц / Egg Hatching Backend + Pet Hatching UI)
- [ ] **T3.2:** Расширение системы локаций (визуальные эффекты телепортации и множители зон на карте)
- [ ] **T3.3:** Финальное интеграционное ревью `develop` и выпуск стабильного релиза `v0.2.0` в ветку `main`
