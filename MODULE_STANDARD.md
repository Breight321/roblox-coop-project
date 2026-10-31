# 📏 MODULE_STANDARD.md — Стандарт разработки модулей Luau

Все модули в проекте **Roblox Simulator Framework** обязаны следовать данному стандарту для обеспечения 100% совместимости между **Agent 1 (`Breight321`)** и **Agent 2 (`anarugod`)**.

---

## 1. Обязательный заголовок и строгая типизация

Каждый файл `.luau` обязан начинаться с директивы `--!strict` и краткого описания модуля и его владельца:

```luau
--!strict
--[[
	@module EconomyService
	@owner Agent 1 (Breight321)
	@description Управление валютами игрока, множителями и транзакциями.
]]
```

---

## 2. Шаблон модуля с жизненным циклом (Service / Controller)

Любой `Service` (на сервере) или `Controller` (на клиенте), регистрируемый в `Registry`, обязан реализовывать интерфейс `LifecycleModule`:

```luau
--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Types = require(ReplicatedStorage.Shared.Core.Types)
local Logger = require(ReplicatedStorage.Shared.Core.Logger)

local ExampleService = {
	Name = "ExampleService",
	Dependencies = { "PlayerDataService" },
}

local log = Logger.new("ExampleService")
local isInitialized = false

function ExampleService:Init(registry: any): ()
	-- 1. Получение зависимостей через registry:Get(...)
	-- 2. Инициализация внутренних структур и сигналов
	-- ЗАПРЕЩЕНО: вызывать бесконечные циклы или блокировать поток в Init()
	isInitialized = true
	log:Info("Initialized successfully")
end

function ExampleService:Start(): ()
	-- Запуск подписок на сетевые события, игровых циклов и фоновых задач
	assert(isInitialized, "Cannot Start before Init")
	log:Info("Started")
end

function ExampleService:Shutdown(): ()
	-- Очистка соединений (Connections), сохранение состояния, освобождение памяти
	log:Info("Shutdown completed")
end

return ExampleService
```

---

## 3. Правила именования (Naming Conventions)

1. **Файлы и модули:** `PascalCase.luau`
   - Серверные сервисы: `*Service.luau` (например, `EconomyService.luau`).
   - Клиентские контроллеры: `*Controller.luau` (например, `UIController.luau`).
   - Конфигурации: `*Config.luau` (например, `ZonesConfig.luau`).
2. **Публичные методы и свойства модуля:** `PascalCase` (`GetBalance`, `PerformRebirth`, `OnCurrencyChanged`).
3. **Локальные переменные и приватные функции:** `camelCase` (`local playerBalance = 0`, `local function calculateMultiplier()`).
4. **Константы:** `UPPER_SNAKE_CASE` (`local MAX_INVENTORY_SLOTS = 50`).
5. **Типы (`export type`):** `PascalCase` (`PlayerProfileData`, `InventoryItem`).

---

## 4. Стандарт обработки ошибок (`Result<T, E>`)

1. Никогда не используйте `error()` для ожидаемых игровых отказов (например: «Недостаточно монет», «Инвентарь полон», «Зона уже открыта»).
2. Все бизнес-методы должны возвращать таблицу `Result<T, string>`:
   - Успех: `{ ok = true, value = resultData }`
   - Отказ: `{ ok = false, error = "INSUFFICIENT_FUNDS" }`
3. Неожиданные сбои (например, недоступность `DataStoreService`) перехватываются через `pcall` и логируются через `Logger:Warn(...)` или `Logger:Error(...)`.

---

## 5. Правила безопасности и сетевого взаимодействия

1. **Никогда не доверяйте клиенту:**
   - Клиент отправляет только **намерение** (`RequestShopPurchase("sword_01")`), а не цену или количество валюты.
   - Сервер проверяет типы всех аргументов `OnServerEvent` (`typeof(arg) == "string"`), проверяет кулдауны и наличие средств через `EconomyService`.
2. **Никаких дублирующихся `RemoteEvent`:**
   - Все сетевые события объявляются централизованно в `src/shared/Core/Network.luau` и документируются в `API_REGISTRY.md`.
