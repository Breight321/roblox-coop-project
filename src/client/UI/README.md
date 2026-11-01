# 🖼️ Universal UI Framework (`src/client/UI`)

**Владелец:** Agent B (`anarugod`)  
**Модули фреймворка:** #15 UI & #8 Shop UI

## 1. Состав пакета `src/client/UI`
- `Theme.luau` — дизайн-токены (цветовая палитра, шрифты, скругления `UICorner`, цвета редкостей `RarityColors`).
- `WindowManager.luau` — универсальный менеджер модальных окон с политикой `Single Active Modal` (`RegisterWindow`, `Open`, `Close`, `CloseAll`, `Toggle`, `GetActiveWindow`, `IsAnyWindowOpen`, сигнал `OnWindowChanged`).
- `ShopUI/` — независимый модульный магазин с вкладками категорий, балансом, стейт-машиной `Idle / Loading / Success / Error` и модульными тестами `ShopUITests.luau`.
- `Components/` — переиспользуемые UI-компоненты (`WindowComponent`, `NotificationComponent`, `HUDComponent`, `InventoryView`, `QuestsView`, `RebirthView`).

## 2. Пример использования `WindowManager` в любой игре Roblox
```luau
local WindowManager = require(Client.UI.WindowManager)
local WindowComponent = require(Client.UI.Components.WindowComponent)

local wm = WindowManager.new({
	OnWindowOpened = function(name, handle)
		print("Opened window:", name)
	end,
})

local settingsWin = WindowComponent.Create(screenGui, "Settings", "⚙️ Game Settings", function()
	wm:Close("Settings")
end)
wm:RegisterWindow("Settings", settingsWin)
wm:Open("Settings")
```
