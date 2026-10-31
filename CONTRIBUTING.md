# 🤝 CONTRIBUTING.md — Правила совместной работы и Git Workflow

Проект разрабатывается двумя ИИ-агентами (**Agent 1: `Breight321`** и **Agent 2: `anarugod`**). Соблюдение этих правил гарантирует отсутствие Git-конфликтов и стабильность кодовой базы.

---

## 1. Модель ветвления (Git Branching Strategy)

- **`main`** — стабильная релизная ветка. Код в `main` всегда должен собираться через `rojo build` без ошибок и проходить все тесты `TestRunner`.
- **`develop`** — общая интеграционная ветка. Все новые фичи сливаются в `develop` через Pull Request.
- **`feature/*`** — рабочие ветки агентов для конкретных задач:
  - Примеры для Agent 1: `feature/agent1-core-framework`, `feature/agent1-economy-system`
  - Примеры для Agent 2: `feature/agent2-client-framework`, `feature/agent2-ui-hud`

### Запрещено:
- Делать `git push --force` в `main` или `develop`.
- Редактировать файлы из чужой зоны ответственности без предварительного согласования в **GitHub Issue #1** (`📡 Agent Sync Channel`).
- Удалять существующие файлы без обоюдного согласия.

---

## 2. Стандарт коммитов (Conventional Commits)

Используйте понятные префиксы коммитов:
- `feat(scope): ...` — новая функциональность (`feat(economy): add rebirth multiplier calculation`)
- `fix(scope): ...` — исправление ошибки (`fix(ui): prevent double click on shop button`)
- `docs(scope): ...` — обновление документации (`docs(api): register QuestService events`)
- `refactor(scope): ...` — рефакторинг без изменения внешнего API
- `test(scope): ...` — добавление или обновление тестов
- `chore(sync): ...` — обновление `AGENT_SYNC.md` или `TASKS.md`

---

## 3. Протокол кооперации перед разработкой общей фичи

Перед реализацией любой системы, затрагивающей оба слоя (Server + Client):
1. Проверьте `API_REGISTRY.md`.
2. Если нужен новый метод или сетевой ивент — опишите предложение в **Issue #1** (`gh issue comment 1 --body "..."`).
3. Добавьте типы в `src/shared/Core/Types.luau` и событие в `src/shared/Core/Network.luau`.
4. Проверьте сборку проекта командой:
   ```powershell
   rojo build default.project.json -o build.rbxlx
   ```
   *(Файл `build.rbxlx` добавлен в `.gitignore` и используется для проверки валидности дерева Rojo).*
5. Запустите или обновите модульные тесты в `src/shared/Tests/FrameworkTests.luau`.
6. Создайте Pull Request в ветку `develop` (`gh pr create --base develop`).
