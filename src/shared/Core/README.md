# ⚙️ Core & Shared Modules (`src/shared/Core/`)

**Владелец:** Agent A (`Breight321`)  
**Версия:** `1.0.0`  
**Зависимости:** Нет (`0`)

## 1. Назначение
Пакет `src/shared/Core/` объединяет **Модуль 1 (`Core`)** и **Модуль 2 (`Shared`)** универсального фреймворка:
- `Registry.luau` — DI-контейнер и загрузчик модулей с топологической сортировкой графа зависимостей (DAG) и жизненным циклом `Init -> Start -> Shutdown`.
- `Signal.luau` — легковесная типизированная шина событий (`Connect`, `Once`, `Fire`, `Destroy`).
- `Logger.luau` — структурированное логирование с уровнями `DEBUG`, `INFO`, `WARN`, `ERROR`.
- `TestRunner.luau` — встроенная среда модульного и интеграционного тестирования.
- `Types.luau` — универсальные контракты типов данных и монада `Result<T, E>` (`Types.Ok`, `Types.Err`).
- `Network.luau` — типизированный сетевой транспорт поверх `Remotes.luau` с поддержкой динамической регистрации событий `Network.RegisterEvent`.

## 2. Пример использования в новой игре
```luau
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Core = ReplicatedStorage.Shared.Core

local Registry = require(Core.Registry)
local Signal = require(Core.Signal)
local Types = require(Core.Types)

local reg = Registry.new("Server")
reg:Register({
	Name = "MatchmakingService",
	Dependencies = {},
	OnMatchStarted = Signal.new(),
	Init = function(self) end,
	Start = function(self)
		self.OnMatchStarted:Fire("Arena_01")
	end,
	Shutdown = function(self)
		self.OnMatchStarted:Destroy()
	end,
})

local res = reg:StartAll()
assert(res.ok)
```
