# 🤝 docs/CONTRIBUTING.md — Руководство по совместной разработке и Git Workflow

## 1. Роли в команде

- **Agent A (`Breight321` — Lead Architect / Backend):** Core Framework, жизненный цикл модулей, архитектура сервисов, `PlayerDataService`, `EconomyService`, серверная валидация и Backend-тесты.
- **Agent B (`anarugod` — Gameplay / Client):** UI Framework, `WindowManager`, `Shop UI`, клиентские контроллеры, `InteractionController`, состояния UI и клиентские тесты.

---

## 2. Схема работы с Git

1. **`main`** — стабильная ветка. Прямые коммиты и пуши в `main` запрещены.
2. **`develop`** — основная интеграционная ветка.
3. **`feature/<module-name>`** — ветка для конкретной задачи.

### Жизненный цикл задачи:
```powershell
# 1. Синхронизация с удалённым репозиторием
git fetch --all --prune
git checkout develop
git pull origin develop

# 2. Создание feature-ветки
git checkout -b feature/<module-name>

# 3. Проверка сборки Rojo после внесения изменений
rojo build default.project.json -o build.rbxlx
Remove-Item build.rbxlx -Force

# 4. Коммит и отправка ветки
git add .
git commit -m "feat(<scope>): <краткое описание>"
git push -u origin feature/<module-name>

# 5. Создание Pull Request в develop
gh pr create --base develop --head feature/<module-name> --title "..." --body "..."
```

---

## 3. Правила согласования API и предотвращения конфликтов

1. Перед изменением любого контракта в `src/shared/` опишите предложение в **GitHub Issue #1** (`gh issue comment 1 --body "..."`).
2. Дождитесь подтверждения второго агента или проверьте совместимость с его текущей веткой.
3. Зафиксируйте изменения в `docs/API_REGISTRY.md` и `AGENT_SYNC.md`.
4. Не редактируйте файлы в чужой зоне ответственности (`src/server/` для Agent A, `src/client/` для Agent B) без явного запроса.
