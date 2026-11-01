# 🖼️ Universal UI Framework (`src/client/UI`)

**Владелец:** Agent B (`anarugod`)  
**Модули фреймворка:** #15 UI & #8 Shop UI

## 1. Состав пакета `src/client/UI`
- `Theme.luau` — дизайн-токены (цветовая палитра, шрифты, скругления `UICorner`, цвета редкостей `RarityColors`).
- `WindowManager.luau` — универсальный менеджер модальных окон с политикой `Single Active Modal` (`RegisterWindow`, `Open`, `Close`, `CloseAll`, `Toggle`, `GetActiveWindow`, `IsAnyWindowOpen`, сигнал `OnWindowChanged`).
- `ShopUI/` — независимый модульный магазин с вкладками категорий, балансом, стейт-машиной `Idle / Loading / Success / Error` и модульными тестами `ShopUITests.luau`.
- `Components/` — переиспользуемые UI-компоненты:
  - `WindowComponent.luau` — каркас модального окна.
  - `NotificationComponent.luau` — всплывающие тост-уведомления.
  - `HUDComponent.luau` — компактный HUD с балансом, индикатором цели боя (`MobTargetPanel`), сводкой характеристик сборки, индикатором безопасной зоны / PvP-арены и быстрой навигацией.
  - `InventoryView.luau` — инвентарь деталей тела (`Head`, `Torso`, `Arms`, `Legs`) с фильтрами по слотам, сравнением бонусов относительно надетой детали и баннером изменений сборки после ответа сервера.
  - `ChestsView.luau` — экран сундуков локаций (показ награды строго после подтверждения сервером).
  - `SkillTreeView.luau` — компактное дерево навыков с ветками `Damage` (Урон), `Defense` (Защита) и `Mobility` (Мобильность).
  - `ArenaView.luau` — экран добровольной PvP-арены с правилами, входом/выходом и результатом боя.
  - `QuestsView.luau`, `RebirthView.luau`, `UpgradesView.luau`.
