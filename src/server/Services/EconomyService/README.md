# 💰 EconomyService Module (`src/server/Services/EconomyService/`)

**Владелец:** Agent A (`Breight321`)  
**Слой:** Server Domain Service (`ServerScriptService.Server.Services.EconomyService`)

## 1. Назначение
`EconomyService` — единственный авторитетный источник истины для баланса валют игрока (`Coins`, `Gems`), расчёта множителей дохода, валидации транзакций, логирования операций и обработки кликов симулятора.

## 2. Структура модуля
- `init.luau` — основная реализация и публичный API сервиса.
- `Types.luau` — типы `EconomyErrorCode`, `CurrencyLimitRule`, `EconomyConfigSchema`.
- `Config.luau` — настраиваемые лимиты баланса, максимальной разовой транзакции и анти-спам кулдаунов.
- `tests/EconomyTests.luau` — модульные тесты API экономики и защиты от некорректных запросов.

## 3. Зависимости (`Dependencies`)
- `PlayerDataService` — хранение и атомарное обновление профиля игрока.

## 4. Публичный API
- `GetBalance(player, currencyId): number`
- `CanAfford(player, currencyId, amount): boolean`
- `ValidateAmount(currencyId, amount): Result<number, EconomyErrorCode>`
- `AddCurrency(player, currencyId, amount, reason?): Result<number, EconomyErrorCode>`
- `RemoveCurrency(player, currencyId, amount, reason?): Result<number, EconomyErrorCode>`
- `GetMultiplier(player, currencyId): number`
- `GetMultiplierBreakdown(player, currencyId): MultiplierBreakdown`
- `ProcessSimulatorClick(player, clientToolUid?): Result<number, EconomyErrorCode>`
- `GetTransactionHistory(player): { EconomyTransactionRecord }`

## 5. События (`Signals`)
- `OnCurrencyChanged(player, currencyId, newBalance, delta, reason)`
- `OnSimulatorClickProcessed(player, coinsEarned, verifiedToolUid)`
