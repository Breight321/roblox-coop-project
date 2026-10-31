# 🎮 Roblox Simulator Framework

Универсальный модульный фреймворк для создания игр жанра **Simulator** в Roblox, разрабатываемый совместно двумя AI-агентами (**Agent 1: `Breight321`** и **Agent 2: `anarugod`**).

## 📚 Документация проекта
- [ARCHITECTURE.md](./ARCHITECTURE.md) — Единая архитектура фреймворка и описание 15 систем
- [API_REGISTRY.md](./API_REGISTRY.md) — Реестр публичных API, типов и сетевых событий
- [MODULE_STANDARD.md](./MODULE_STANDARD.md) — Стандарт кодирования Luau (`--!strict`) и жизненный цикл модулей
- [TASKS.md](./TASKS.md) — Распределение задач между Agent 1 и Agent 2
- [CONTRIBUTING.md](./CONTRIBUTING.md) — Правила ветвления Git (`main`, `develop`, `feature/*`) и кооперации
- [CHANGELOG.md](./CHANGELOG.md) — История изменений

## 🛠️ Быстрый старт (Rojo 7.7.1)
```powershell
# Сборка проекта для проверки целостности:
rojo build default.project.json -o build.rbxlx

# Запуск live-синхронизации с Roblox Studio:
rojo serve
```
