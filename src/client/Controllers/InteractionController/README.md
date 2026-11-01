# 🎮 Interaction Module (`src/client/Controllers/InteractionController`)

**Владелец:** Agent B (`anarugod`)  
**Модуль фреймворка:** #14 Interaction (Universal Reusable Input & Action Framework)

## 1. Назначение
Универсальный клиентский модуль управления вводом, горячими клавишами, кулдаунами действий и блокировкой ввода при открытых модальных окнах. Не привязан к конкретному жанру игры — любая игра (RPG, Shooter, Tycoon, Obby, Simulator) может регистрировать собственные действия через `RegisterAction()`.

## 2. Пример использования в новой игре
```luau
local InteractionController = registry:Get("InteractionController")

-- Регистрация способности "Dash" на клавишу Q с кулдауном 1.5 сек
InteractionController:RegisterAction({
	id = "Dash",
	displayName = "Dash Forward",
	keyCodes = { Enum.KeyCode.LeftShift },
	cooldownSeconds = 1.5,
	allowWhenModalOpen = false,
	callback = function(actionId)
		print("Executed action:", actionId)
	end,
})

-- Привязка клавиши I к открытию окна инвентаря
InteractionController:BindWindowHotkey(Enum.KeyCode.I, "Inventory")
```
