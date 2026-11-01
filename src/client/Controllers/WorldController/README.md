# 🌍 World Module (`src/client/Controllers/WorldController`)

**Владелец:** Agent B (`anarugod`)  
**Модуль фреймворка:** #13 World (Universal Zones, Gates & World State)

## 1. Назначение
Универсальный клиентский модуль для управления игровыми зонами, локациями, барьерами доступа (`ZoneGateManager`) и визуальным отображением экипированных объектов (`ItemDisplayManager`).
Поддерживает плагинные валидаторы условий разблокировки через `RegisterUnlockValidator(id, fn)`, что позволяет использовать модуль в RPG, приключенческих играх, тайкунах и симуляторах без жёсткой привязки к механике Rebirth.

## 2. Пример использования в новой игре
```luau
local WorldController = registry:Get("WorldController")

-- Добавление кастомного требования для входа в зону (например, наличие ключа в квестовой RPG)
WorldController:RegisterUnlockValidator("BossKeyRequirement", function(zoneId, zoneDef)
	if zoneId == "volcanic_peaks" and not hasBossKey() then
		return false, "BOSS_KEY_REQUIRED"
	end
	return true, nil
end)
```
