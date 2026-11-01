# 🤝 Правила совместной работы двух ИИ-агентов (Antigravity Multi-Agent Protocol)

Этот проект (**Roblox Simulator Framework**) разрабатывается двумя ИИ-агентами совместно через GitHub:

- **Agent A (`Breight321` — Lead Architect / Backend):**
  - Core Framework (`src/shared/Core/`)
  - Module initialization / lifecycle (`Registry.luau`)
  - Service architecture (`src/server/Services/`)
  - Player Data architecture (`PlayerDataService`)
  - Economy Backend (`EconomyService`)
  - Shared Types и API Contracts (`Types.luau`, `Network.luau`)
  - Server-side validation & Backend tests
- **Agent B (`anarugod` — Gameplay / Client):**
  - UI Framework & Window Manager (`src/client/UI/`)
  - Shop UI & Gameplay Views (`ShopView`, `InventoryView`, `QuestsView`, `RebirthView`)
  - Client Controllers (`src/client/Controllers/`)
  - Interaction System & World/Zone System (`src/client/World/`)
  - UI states, notifications, клиентская интеграция с Backend API & UI tests

---

## 1. Обязательный Git Workflow (Строгие правила)

Прямой push рабочих изменений в `main` **категорически запрещён**.

### Структура веток:
- **`main`** — стабильная релизная версия проекта (обновляется только из проверенного `develop`).
- **`develop`** — общая интеграционная ветка.
- **`feature/<module-name>`** — рабочие ветки отдельных задач и модулей (например, `feature/economy-backend-hardening`, `feature/shop-ui-states`).

### Обязательные правила для обоих агентов:
1. **Никогда не отправляй рабочие изменения напрямую в `main`.**
2. **Никогда не используй `git push --force` на общих ветках (`main`, `develop`).**
3. **Каждая задача выполняется в отдельной ветке `feature/<module-name>`, созданной от актуального `develop`.**
4. **Завершённая задача отправляется через Pull Request в ветку `develop` (`gh pr create --base develop`).**
5. **Перед началом работы всегда проверяй актуальное состояние репозитория:**
   ```powershell
   git fetch --all --prune
   git status
   git log -n 5 --oneline
   ```
6. **Не перезаписывай чужие изменения и не редактируй одновременно одни и те же файлы без согласования.**
7. **Не делай автоматический merge без проверки сборки (`rojo build default.project.json -o build.rbxlx`) и прогона тестов.**

---

## 2. Как агенты общаются и синхронизируются

1. **Через GitHub Issue #1 (`📡 Agent Sync Channel`):**
   - Прочитать последние сообщения:
     `gh issue view 1 --comments`
   - Отправить сообщение другому агенту:
     `gh issue comment 1 --body "🤖 [Agent A / Agent B]: <текст сообщения>"`
2. **Через доску синхронизации `AGENT_SYNC.md`:**
   - В `AGENT_SYNC.md` фиксируются текущие задачи, редактируемые файлы, активные `feature/*` ветки, согласованные API и статусы интеграции.
3. **Согласование API перед реализацией:**
   - Любое изменение публичного API или сетевых событий сначала согласуется в Issue #1 и фиксируется в `docs/API_REGISTRY.md` и `AGENT_SYNC.md`.
