# 🛒 ShopUI Module (`src/client/UI/ShopUI`)

**Владелец:** Agent B (`anarugod`)  
**Слой:** Client UI Framework (`StarterPlayerScripts.Client.UI.ShopUI`)

## 1. Назначение
`ShopUI` — независимый переиспользуемый клиентский модуль магазина для **Roblox Simulator Framework**. Отвечает за:
- отображение витрины товаров из `ShopConfig` и `ItemsConfig`;
- фильтрацию товаров по категориям (`All`, `Tool`, `Pet`, `Consumable`) с возможностью динамического добавления новых категорий через `AddCategory()`;
- отображение актуального баланса игрока (`Coins`, `Gems`);
- управление состояниями покупки (`Idle`, `Loading`, `Success`, `Error`) и доступности (`Available`, `InsufficientFunds`, `LockedZone`, `LockedRebirth`);
- защиту от дублирующих кликов (rate-limiting & loading lock).

## 2. Правила безопасности (Single Source of Truth)
- `ShopUI` **никогда** самостоятельно не списывает валюту и не добавляет предметы в инвентарь.
- При нажатии кнопки покупки `ShopUI` проверяет предварительные условия и генерирует сигнал `OnPurchaseRequested(shopItemId)`, который передаёт в `Network.FireServer(Network.Events.RequestShopPurchase, shopItemId)` только `shopItemId`.
- Переход в состояние `Success` и обновление баланса происходят исключительно после подтверждения от сервера (`InventoryUpdated`, `CurrencyUpdated`, `Notification`).

## 3. Структура модуля
```text
ShopUI/
├── init.luau            # Основная реализация и стейт-машина ShopUI
├── Types.luau           # Типы состояний, категорий и ViewModel карточек
├── Config.luau          # Тайминги, кулдауны и базовые категории
├── README.md            # Документация модуля
└── tests/
    └── ShopUITests.luau # Автоматические модульные тесты ShopUI
```
