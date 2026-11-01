--!strict
--[[
	@module CombatLoopTests
	@owner Agent A (Breight321)
	@description Серверные модульные и интеграционные тесты Combat Loop v1:
	1. Бой с мобами и награды (CombatService + LootService + ProgressionService + EconomyService).
	2. Детали тела (4 слота: Head, Arms, Torso, Legs) и бонус полного комплекта (StatsService + InventoryService).
	3. Сундуки и таблицы добычи с защитой от пропуска фарма (ChestService).
	4. Дерево пассивных навыков (SkillTreeService).
	5. Добровольная PvP-арена и защита мирных зон (ArenaService).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local TestRunner = require(Shared:WaitForChild("Core"):WaitForChild("TestRunner"))
local CombatConfig = require(Shared:WaitForChild("Config"):WaitForChild("CombatConfig"))

local Services = ServerScriptService:WaitForChild("Server"):WaitForChild("Services")
local PlayerDataService = require(Services:WaitForChild("PlayerDataService"))
local EconomyService = require(Services:WaitForChild("EconomyService"))
local InventoryService = require(Services:WaitForChild("InventoryService"))
local ProgressionService = require(Services:WaitForChild("ProgressionService"))
local SkillTreeService = require(Services:WaitForChild("SkillTreeService"))
local StatsService = require(Services:WaitForChild("StatsService"))
local CombatService = require(Services:WaitForChild("CombatService"))
local ChestService = require(Services:WaitForChild("ChestService"))
local ArenaService = require(Services:WaitForChild("ArenaService"))

local CombatLoopTests = {}

function CombatLoopTests.RunAll(): TestRunner.SuiteSummary
	local cases: { TestRunner.TestCase } = {
		{
			name = "CombatService: validates range, zone lock, cooldown, mob kill, XP and Coins rewards",
			fn = function()
				CombatService:SetRngForTests(Random.new(12345))
				local mobPos = Vector3.new(-28, 3, -10)
				local testMobUid = CombatService:SpawnMobForTest("meadow_scrap_drone", mobPos)
				TestRunner.Assert(testMobUid ~= nil, "Should spawn test meadow_scrap_drone")
				local mobUid = testMobUid :: string

				local lockedMobPos = Vector3.new(28, 3, -12)
				local lockedMobUid = CombatService:SpawnMobForTest("cavern_ember_golem", lockedMobPos) :: string

				local mockPlayer: any = {
					UserId = 992001,
					Name = "CombatTester1",
					Position = mobPos + Vector3.new(100, 0, 0),
				}
				PlayerDataService:CreateSessionForTest(mockPlayer)

				-- 1. Вне радиуса атаки -> OUT_OF_RANGE
				local farRes = CombatService:AttackMob(mockPlayer, mobUid)
				TestRunner.Assert(not farRes.ok, "Attack from 100 studs should fail")
				TestRunner.AssertEqual(farRes.errorCode, "OUT_OF_RANGE", "Expected OUT_OF_RANGE")

				-- 2. Попытка атаковать моба в закрытой зоне (crystal_cavern) -> ZONE_LOCKED
				mockPlayer.Position = lockedMobPos
				local zoneRes = CombatService:AttackMob(mockPlayer, lockedMobUid)
				TestRunner.Assert(not zoneRes.ok, "Attack in locked zone should fail")
				TestRunner.AssertEqual(zoneRes.errorCode, "ZONE_LOCKED", "Expected ZONE_LOCKED")

				-- 3. Подходим к meadow_scrap_drone и наносим первый удар
				mockPlayer.Position = mobPos + Vector3.new(4, 0, 0)
				local hit1 = CombatService:AttackMob(mockPlayer, mobUid)
				TestRunner.Assert(hit1.ok, "Valid attack in range should succeed")
				TestRunner.Assert(hit1.damageDealt > 0, "Damage dealt must be > 0")

				-- 4. Мгновенный повторный удар без ожидания кулдауна -> ATTACK_COOLDOWN
				local cdHit = CombatService:AttackMob(mockPlayer, mobUid)
				TestRunner.Assert(not cdHit.ok, "Immediate second attack must hit cooldown")
				TestRunner.AssertEqual(cdHit.errorCode, "ATTACK_COOLDOWN", "Expected ATTACK_COOLDOWN")

				-- 5. Добиваем моба и проверяем начисление XP, Coins и счётчика побед
				local startCoins = EconomyService:GetBalance(mockPlayer, "Coins")
				local killed = hit1.killed
				local safety = 0
				while not killed and safety < 20 do
					safety += 1
					CombatService:ClearCooldownForTest(mockPlayer)
					local step = CombatService:AttackMob(mockPlayer, mobUid)
					TestRunner.Assert(step.ok, "Subsequent attack after cooldown clear should succeed")
					killed = step.killed
				end
				TestRunner.Assert(killed, "Mob must be defeated within expected hits")

				-- 6. Попытка ударить уже побеждённого моба -> TARGET_DEAD
				CombatService:ClearCooldownForTest(mockPlayer)
				local deadRes = CombatService:AttackMob(mockPlayer, mobUid)
				TestRunner.Assert(not deadRes.ok, "Attacking dead mob should fail")
				TestRunner.AssertEqual(deadRes.errorCode, "TARGET_DEAD", "Expected TARGET_DEAD")

				local endCoins = EconomyService:GetBalance(mockPlayer, "Coins")
				TestRunner.Assert(endCoins > startCoins, "Player should receive Coins for defeating mob")

				local record = CombatService:GetPlayerCombatRecord(mockPlayer)
				TestRunner.AssertEqual(record.totalMobKills, 1, "totalMobKills should increment to 1")
				TestRunner.AssertEqual(record.mobKillsById.meadow_scrap_drone, 1, "meadow_scrap_drone kill count should be 1")

				CombatService:DespawnMobForTest(mobUid)
				CombatService:DespawnMobForTest(lockedMobUid)
				CombatService:SetRngForTests(nil)
				PlayerDataService:RemoveSessionForTest(mockPlayer)
			end,
		},
		{
			name = "StatsService & InventoryService: body part slots (Head, Arms, Torso, Legs), cross-set mixing, and 4-piece set bonus",
			fn = function()
				local mockPlayer: any = {
					UserId = 992002,
					Name = "BodyPartTester",
				}
				PlayerDataService:CreateSessionForTest(mockPlayer)

				local baseStats = StatsService:GetStats(mockPlayer)
				local baseAttackPower = baseStats.attackPower
				local baseMaxHealth = baseStats.maxHealth

				-- Выдаём 4 детали комплекта Scrapper и 1 шлем комплекта Ember
				local headRes = InventoryService:GrantItem(mockPlayer, "scrap_head", 1)
				local armsRes = InventoryService:GrantItem(mockPlayer, "scrap_arms", 1)
				local torsoRes = InventoryService:GrantItem(mockPlayer, "scrap_torso", 1)
				local legsRes = InventoryService:GrantItem(mockPlayer, "scrap_legs", 1)
				local emberHeadRes = InventoryService:GrantItem(mockPlayer, "ember_head", 1)

				TestRunner.Assert(headRes.ok and armsRes.ok and torsoRes.ok and legsRes.ok and emberHeadRes.ok, "All body parts should be granted")

				local headUid = (headRes.value :: any).uid
				local armsUid = (armsRes.value :: any).uid
				local torsoUid = (torsoRes.value :: any).uid
				local legsUid = (legsRes.value :: any).uid
				local emberHeadUid = (emberHeadRes.value :: any).uid

				-- Экипируем все 4 слота комплекта Scrapper
				TestRunner.Assert(InventoryService:EquipItem(mockPlayer, headUid, true).ok, "Should equip Head")
				TestRunner.Assert(InventoryService:EquipItem(mockPlayer, armsUid, true).ok, "Should equip Arms")
				TestRunner.Assert(InventoryService:EquipItem(mockPlayer, torsoUid, true).ok, "Should equip Torso")
				TestRunner.Assert(InventoryService:EquipItem(mockPlayer, legsUid, true).ok, "Should equip Legs")

				local fullSetStats = StatsService:GetStats(mockPlayer)
				TestRunner.AssertEqual(fullSetStats.activeSetBonus, "scrapper", "4 pieces of scrapper must activate 'scrapper' set bonus")
				TestRunner.Assert(fullSetStats.attackPower > baseAttackPower, "AttackPower should increase with equipped body parts + set bonus")
				TestRunner.Assert(fullSetStats.maxHealth > baseMaxHealth, "MaxHealth should increase with equipped body parts + set bonus")

				-- Проверяем ограничение 1 предмета на слот BodyHead: попытка надеть второй шлем поверх первого без снятия -> CATEGORY_EQUIP_LIMIT_REACHED
				local secondHeadAttempt = InventoryService:EquipItem(mockPlayer, emberHeadUid, true)
				TestRunner.Assert(not secondHeadAttempt.ok, "Equipping a second Head without unequipping the first must fail")
				TestRunner.AssertEqual(secondHeadAttempt.error, "CATEGORY_EQUIP_LIMIT_REACHED", "Expected CATEGORY_EQUIP_LIMIT_REACHED")

				-- Снимаем шлем Scrapper и надеваем шлем Ember (комбинация разных наборов)
				TestRunner.Assert(InventoryService:EquipItem(mockPlayer, headUid, false).ok, "Should unequip Scrapper Head")
				TestRunner.Assert(InventoryService:EquipItem(mockPlayer, emberHeadUid, true).ok, "Should equip Ember Head")

				local mixedStats = StatsService:GetStats(mockPlayer)
				TestRunner.AssertEqual(mixedStats.activeSetBonus, nil, "3/4 scrapper + 1/4 ember must not have fullSetBonus")
				TestRunner.AssertEqual(mixedStats.equippedBodyParts.Head, "ember_head", "Head slot should now report ember_head")
				TestRunner.AssertEqual(mixedStats.equippedBodyParts.Arms, "scrap_arms", "Arms slot should keep scrap_arms")

				PlayerDataService:RemoveSessionForTest(mockPlayer)
			end,
		},
		{
			name = "ChestService: enforces mob kill requirement (complementing farm), range, and cooldown",
			fn = function()
				local fakeNow = 10000
				ChestService:SetClockForTests(function()
					return fakeNow
				end)

				local chestDef = CombatConfig.Chests.meadow_supply_cache
				local mobPos = Vector3.new(-28, 3, -10)
				local mockPlayer: any = {
					UserId = 992003,
					Name = "ChestTester",
					Position = chestDef.position,
				}
				PlayerDataService:CreateSessionForTest(mockPlayer)

				-- 1. Попытка открыть сундук сразу без убийства мобов -> NOT_ENOUGH_KILLS
				local noKillsRes = ChestService:OpenChest(mockPlayer, "meadow_supply_cache")
				TestRunner.Assert(not noKillsRes.ok, "Opening chest with 0 kills must fail")
				TestRunner.AssertEqual(noKillsRes.errorCode, "NOT_ENOUGH_KILLS", "Expected NOT_ENOUGH_KILLS")

				-- 2. Побеждаем 2 мобов (requiredKillsSinceLastOpen = 2 для meadow_supply_cache)
				for _ = 1, chestDef.requiredKillsSinceLastOpen do
					local mUid = CombatService:SpawnMobForTest("meadow_scrap_drone", mobPos) :: string
					mockPlayer.Position = mobPos
					local safety = 0
					while safety < 20 do
						safety += 1
						CombatService:ClearCooldownForTest(mockPlayer)
						local r = CombatService:AttackMob(mockPlayer, mUid)
						if r.killed then
							break
						end
					end
					CombatService:DespawnMobForTest(mUid)
				end

				-- 3. Слишком далеко от сундука -> OUT_OF_RANGE
				mockPlayer.Position = chestDef.position + Vector3.new(80, 0, 0)
				local farRes = ChestService:OpenChest(mockPlayer, "meadow_supply_cache")
				TestRunner.Assert(not farRes.ok, "Opening chest from afar must fail")
				TestRunner.AssertEqual(farRes.errorCode, "OUT_OF_RANGE", "Expected OUT_OF_RANGE")

				-- 4. Подходим к сундуку и успешно открываем
				mockPlayer.Position = chestDef.position
				local openRes = ChestService:OpenChest(mockPlayer, "meadow_supply_cache")
				TestRunner.Assert(openRes.ok, "Opening chest after required kills and in range should succeed")
				TestRunner.Assert(#openRes.drops > 0, "Chest must grant loot drops")

				-- 5. Повторное открытие сразу -> CHEST_COOLDOWN
				local cdRes = ChestService:OpenChest(mockPlayer, "meadow_supply_cache")
				TestRunner.Assert(not cdRes.ok, "Immediate second open must fail with CHEST_COOLDOWN")
				TestRunner.AssertEqual(cdRes.errorCode, "CHEST_COOLDOWN", "Expected CHEST_COOLDOWN")

				-- 6. Даже после истечения времени кулдауна сундук снова требует убить 2 мобов -> NOT_ENOUGH_KILLS
				fakeNow += chestDef.cooldownSeconds + 5
				local afterCdNoKills = ChestService:OpenChest(mockPlayer, "meadow_supply_cache")
				TestRunner.Assert(not afterCdNoKills.ok, "After cooldown expires, chest still requires new mob kills")
				TestRunner.AssertEqual(afterCdNoKills.errorCode, "NOT_ENOUGH_KILLS", "Expected NOT_ENOUGH_KILLS")

				ChestService:SetClockForTests(nil)
				PlayerDataService:RemoveSessionForTest(mockPlayer)
			end,
		},
		{
			name = "SkillTreeService: validates prerequisites, skill points, level requirements, and stat bonuses",
			fn = function()
				local mockPlayer: any = {
					UserId = 992004,
					Name = "SkillTester",
				}
				PlayerDataService:CreateSessionForTest(mockPlayer)

				local initStats = StatsService:GetStats(mockPlayer)

				-- 1. Попытка открыть узел 2-го тира (dmg_2) без открытого dmg_1 -> PREREQUISITE_MISSING
				local prereqRes = SkillTreeService:UnlockSkill(mockPlayer, "dmg_2")
				TestRunner.Assert(not prereqRes.ok, "Unlocking tier 2 without tier 1 must fail")
				TestRunner.AssertEqual(prereqRes.errorCode, "PREREQUISITE_MISSING", "Expected PREREQUISITE_MISSING")

				-- 2. Открываем базовый навык урона dmg_1 за стартовое очко навыков
				local unlock1 = SkillTreeService:UnlockSkill(mockPlayer, "dmg_1")
				TestRunner.Assert(unlock1.ok, "Unlocking dmg_1 at level 1 with 1 starting point should succeed")
				TestRunner.AssertEqual(unlock1.state.availablePoints, 0, "Should have 0 available points left")

				local afterDmg1Stats = StatsService:GetStats(mockPlayer)
				TestRunner.AssertEqual(afterDmg1Stats.attackPower, initStats.attackPower + 4, "dmg_1 should add +4 attackPower")

				-- 3. Попытка открыть def_1 без очков навыков -> NOT_ENOUGH_POINTS
				local noPtsRes = SkillTreeService:UnlockSkill(mockPlayer, "def_1")
				TestRunner.Assert(not noPtsRes.ok, "Unlocking without points must fail")
				TestRunner.AssertEqual(noPtsRes.errorCode, "NOT_ENOUGH_POINTS", "Expected NOT_ENOUGH_POINTS")

				-- 4. Попытка открыть dmg_2 на 1-м уровне (даже если выдать очки) -> LEVEL_TOO_LOW
				SkillTreeService:GrantPointsForTest(mockPlayer, 2)
				local lowLvlRes = SkillTreeService:UnlockSkill(mockPlayer, "dmg_2")
				TestRunner.Assert(not lowLvlRes.ok, "Unlocking dmg_2 below level 2 must fail")
				TestRunner.AssertEqual(lowLvlRes.errorCode, "LEVEL_TOO_LOW", "Expected LEVEL_TOO_LOW")

				-- 5. Повышаем уровень до 2 через ProgressionService:AddXP и открываем dmg_2
				ProgressionService:AddXP(mockPlayer, 200)
				local unlock2 = SkillTreeService:UnlockSkill(mockPlayer, "dmg_2")
				TestRunner.Assert(unlock2.ok, "Unlocking dmg_2 at level >= 2 should succeed")

				PlayerDataService:RemoveSessionForTest(mockPlayer)
			end,
		},
		{
			name = "ArenaService: voluntary opt-in PvP, safe zone protection, PvE isolation, and separate PvP balance",
			fn = function()
				local entrancePos = CombatConfig.Arena.EntrancePosition
				local p1: any = {
					UserId = 992005,
					Name = "ArenaFighter1",
					Position = entrancePos,
				}
				local p2: any = {
					UserId = 992006,
					Name = "ArenaFighter2",
					Position = entrancePos,
				}
				PlayerDataService:CreateSessionForTest(p1)
				PlayerDataService:CreateSessionForTest(p2)
				ArenaService:RegisterTestPlayer(p1)
				ArenaService:RegisterTestPlayer(p2)

				-- Повышаем уровень обоих игроков до 2 (MinPlayerLevel для арены = 2)
				ProgressionService:AddXP(p1, 150)
				ProgressionService:AddXP(p2, 150)

				-- 1. В обычной зоне (вне арены) атака игрока невозможна -> NOT_IN_ARENA
				local outsideHit = ArenaService:AttackPlayer(p1, p2.UserId)
				TestRunner.Assert(not outsideHit.ok, "PvP attack outside arena must be blocked")
				TestRunner.AssertEqual(outsideHit.errorCode, "NOT_IN_ARENA", "Expected NOT_IN_ARENA")

				-- 2. Игрок 1 входит в арену, но Игрок 2 ещё в мирной зоне -> TARGET_NOT_IN_ARENA
				local enter1 = ArenaService:EnterArena(p1)
				TestRunner.Assert(enter1.inArena and enter1.errorCode == nil, "Player 1 should enter arena")

				local hitOutsideTarget = ArenaService:AttackPlayer(p1, p2.UserId)
				TestRunner.Assert(not hitOutsideTarget.ok, "Attacking player outside arena must fail")
				TestRunner.AssertEqual(hitOutsideTarget.errorCode, "TARGET_NOT_IN_ARENA", "Expected TARGET_NOT_IN_ARENA")

				-- 3. Находясь в арене, нельзя бить PvE-мобов -> IN_ARENA
				local mobUid = CombatService:SpawnMobForTest("meadow_scrap_drone", p1.Position) :: string
				local pveAttempt = CombatService:AttackMob(p1, mobUid)
				TestRunner.Assert(not pveAttempt.ok, "Attacking PvE mob while in PvP arena must fail")
				TestRunner.AssertEqual(pveAttempt.errorCode, "IN_ARENA", "Expected IN_ARENA")
				CombatService:DespawnMobForTest(mobUid)

				-- 4. Игрок 2 также добровольно входит в арену; сближаем их и проверяем PvP-удар
				local enter2 = ArenaService:EnterArena(p2)
				TestRunner.Assert(enter2.inArena and enter2.errorCode == nil, "Player 2 should enter arena")
				p2.Position = p1.Position + Vector3.new(4, 0, 0)

				local pvpHit = ArenaService:AttackPlayer(p1, p2.UserId)
				TestRunner.Assert(pvpHit.ok, "PvP attack when both players are in arena and in range should succeed")
				TestRunner.Assert(pvpHit.damageDealt > 0, "PvP damage dealt must be > 0")
				TestRunner.Assert(
					pvpHit.damageDealt <= math.ceil(pvpHit.targetMaxHealth * CombatConfig.Arena.Balance.MaxSingleHitHealthFraction),
					"PvP single hit must respect MaxSingleHitHealthFraction cap"
				)

				-- 5. Попытка немедленно покинуть арену во время боя -> COMBAT_TAGGED
				local fleeAttempt = ArenaService:LeaveArena(p1)
				TestRunner.Assert(fleeAttempt.inArena and fleeAttempt.errorCode == "COMBAT_TAGGED", "Leaving arena while combat-tagged must fail")

				-- 6. После сброса боевой метки выход из арены разрешён
				ArenaService:ClearCooldownsForTest(p1)
				ArenaService:ClearCooldownsForTest(p2)
				local leave1 = ArenaService:LeaveArena(p1)
				local leave2 = ArenaService:LeaveArena(p2)
				TestRunner.Assert(not leave1.inArena and leave1.errorCode == nil, "Player 1 should leave arena after combat tag expires")
				TestRunner.Assert(not leave2.inArena and leave2.errorCode == nil, "Player 2 should leave arena after combat tag expires")

				PlayerDataService:RemoveSessionForTest(p1)
				PlayerDataService:RemoveSessionForTest(p2)
			end,
		},
	}

	return TestRunner.RunSuite("CombatLoopBackendSuite", cases)
end

return CombatLoopTests
