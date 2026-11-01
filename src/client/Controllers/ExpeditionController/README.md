# 🧭 ExpeditionController (`src/client/Controllers/ExpeditionController/`)

**Владелец:** Agent B (`anarugod`)  
**Назначение:** Клиентский контроллер первого вертикального среза кооперативной игры **«Aetherfall: Expedition Core»**.

## Ключевые обязанности
1. **Сбор Эфирных Монет (`RequestCollect`):** Отправка намерения сбора без локальной мутации сумки или баланса.
2. **Станция Сдачи (`RequestDeposit` / `RetryDeposit`):** Полная машина состояний `Idle -> Loading -> Success / Error` с поддержкой повторного запроса при отказе.
3. **Улучшения инструмента и сумки (`RequestUpgrade` / `RetryUpgrade`):** Оценка доступности по подтверждённому балансу банка (`Available`, `InsufficientFunds`, `MaxLevel`, `Loading`, `Success`, `Error`).
4. **Командный прогресс (`GetTeamProgress` / `RequestTeamSync`):** Отображение вклада всех игроков и разблокировки следующего этапа.
