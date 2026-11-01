# ⚔️ CombatController (`src/client/Controllers/CombatController`)

**Владелец:** Agent B (`anarugod`)  
**Назначение:** Клиентский контроллер боевого цикла (`Combat Loop v1`), инвентаря и сборки деталей тела (`Head`, `Arms`, `Torso`, `Legs`), открытия сундуков в мире, дерева навыков (`Damage`, `Defense`, `Mobility`) и добровольной PvP-арены.

---

## 1. Ключевые принципы и используемые контракты Agent A (`Network.Events`)

1. **Обратная связь боя (`RequestAttackMob` -> `CombatResult`, `MobDefeated`):**
   - При вызове `RequestAttackMob(mobUid)` проигрывается только визуально-звуковой отклик замаха (`AnimationController`, `AudioController`) и отправляется `Network.Events.RequestAttackMob` на сервер.
   - Здоровье моба (`Health / MaxHealth` из атрибутов `Workspace.CombatWorld.Mobs` и `CombatResult`), критический удар, поражение и полученная награда (`MobDefeated`) отображаются строго после подтверждения сервером.
2. **Инвентарь деталей тела и сравнение сборки (`RequestEquipItem` -> `InventoryUpdated`, `StatsUpdated`):**
   - Поддерживает 4 слота тела: `Head` (`BodyHead`), `Arms` (`BodyArms`), `Torso` (`BodyTorso`), `Legs` (`BodyLegs`) и комплекты 4/4 из `BodySetsConfig` (`scrapper`, `ember`, `frostforged`, единый стиль `ModularMech`).
   - Вычисляет разницу бонусов (`deltaAttackPower`, `deltaDefense`, `deltaMaxHealth`, `deltaMoveSpeed`, `deltaCritChance`) относительно надетой детали в том же слоте и формирует сводку изменений сборки (`lastDeltaSummary`).
3. **Сундуки (`RequestOpenChest` -> `ChestStateSync`, `ChestResult`):**
   - `RequestOpenChest(chestId)` переводит сундук в состояние `"Loading"` и **не показывает выигрыш** до получения серверного ответа `ChestResult`.
4. **Дерево навыков (`RequestUnlockSkill` -> `SkillTreeSync`, `SkillUnlockResult`):**
   - Три ветки из `SkillTreeConfig`: `Damage` (Урон), `Defense` (Защита), `Mobility` (Мобильность) с состояниями `Idle`, `Loading`, `Success`, `Error`.
5. **Добровольная PvP-арена (`RequestArenaEnter`, `RequestArenaLeave`, `RequestPvPAttack` -> `ArenaStateChanged`, `PvPCombatResult`):**
   - Обычные зоны безопасны (`isSafeZone = true`, `zoneState = "SafeZone"`).
   - Вход и выход добровольны; правила и отдельный PvP-баланс берутся из `CombatConfig.Arena`.
