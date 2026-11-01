# ⚡ QUICK_START.md — Быстрый старт и установка модулей в новую игру Roblox

**Universal Roblox Framework** спроектирован так, чтобы вы могли подключить либо весь фреймворк целиком, либо выбрать только нужные модули (например, только `Core + Data + Economy` для RPG или Tycoon).

---

## 1. Требования
- **Rojo:** `>= 7.4.0` (рекомендуется `7.7.1`)
- **Roblox Studio** с установленным плагином Rojo

---

## 2. Вариант А: Установка всего фреймворка за 2 минуты

```powershell
# 1. Клонируйте репозиторий
git clone https://github.com/Breight321/roblox-coop-project.git my-new-roblox-game
cd my-new-roblox-game

# 2. Проверьте сборку проекта
rojo build default.project.json -o build.rbxlx

# 3. Запустите live-синхронизацию с Roblox Studio
rojo serve
```

---

## 3. Вариант Б: Выборочная установка отдельных модулей (Modular Pick & Choose)

Допустим, вы создаёте **гоночную игру (Racing Game)** и вам нужны только **`Core`**, **`Data`** и **`Economy`** (без инвентаря, питомцев и квестов):

1. Скопируйте в ваш проект:
   - `src/shared/Remotes.luau`
   - `src/shared/Core/` (`Types.luau`, `Logger.luau`, `Signal.luau`, `Network.luau`, `Registry.luau`, `TestRunner.luau`)
   - `src/shared/Config/GameConfig.luau` и `CurrenciesConfig.luau`
   - `src/server/Services/PlayerDataService/`
   - `src/server/Services/EconomyService/`

2. Зарегистрируйте свои валюты и секции данных в вашем серверном скрипте:
   ```luau
   --!strict
   local ReplicatedStorage = game:GetService("ReplicatedStorage")
   local ServerScriptService = game:GetService("ServerScriptService")

   local Registry = require(ReplicatedStorage.Shared.Core.Registry)
   local PlayerDataService = require(ServerScriptService.Server.Services.PlayerDataService)
   local EconomyService = require(ServerScriptService.Server.Services.EconomyService)

   -- 1. Добавьте свою секцию профиля (например, гараж машин)
   PlayerDataService:RegisterSchemaSection("cars", { starter_sedan = true })

   -- 2. Зарегистрируйте валюту вашей игры
   EconomyService:RegisterCurrency({
       id = "RaceCredits",
       displayName = "Credits",
       startingAmount = 500,
       maxAmount = 1e9,
       showInLeaderstats = true,
   })

   -- 3. Запустите только выбранные сервисы через Registry
   local reg = Registry.new("Server")
   reg:Register(PlayerDataService)
   reg:Register(EconomyService)
   reg:InitAll()
   reg:StartAll()
   ```

---

## 4. Как подключить бонус от вашей игровой механики к `EconomyService` (Адаптер)

Вместо того чтобы редактировать код `EconomyService`, зарегистрируйте модификатор множителя:

```luau
-- Например, VIP-игроки получают x2 валюты:
EconomyService:RegisterMultiplierModifier("VIPPassBonus", function(player: Player, _currencyId: string)
	if player:GetAttribute("IsVIP") == true then
		return 2.0
	end
	return 1.0
end)
```
