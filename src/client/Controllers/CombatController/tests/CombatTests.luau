--!strict
--[[
	@module CombatTests
	@owner Agent B (anarugod)
	@description Модульные клиентские тесты CombatController (Combat Loop v1) через TestRunner:
	проверяет обработку серверных событий боя (CombatResult, MobDefeated), сборки деталей тела
	(Head, Arms, Torso, Legs + 4/4 BodySetsConfig), сундуков (ChestStateSync, ChestResult),
	дерева навыков (SkillTreeSync, SkillUnlockResult) и добровольной PvP-арены (ArenaStateChanged, PvPCombatResult).
]]

local CombatController = require(script.Parent.Parent)

return function(TestRunner: any)
	TestRunner.describe("CombatController (Combat Loop v1 Client Contracts)", function()
		CombatController:Init()

		TestRunner.it("должен инициализировать цели мобов, сундуки и 9 узлов дерева навыков из общих конфигов", function()
			local mobs = CombatController:GetAllMobTargets()
			TestRunner.expect(#mobs > 0).toBe(true)

			local chests = CombatController:GetChests()
			TestRunner.expect(#chests).toBe(3)

			local skills = CombatController:GetSkillTreeNodes()
			TestRunner.expect(#skills).toBe(9)

			local arena = CombatController:GetArenaState()
			TestRunner.expect(arena.isSafeZone).toBe(true)
			TestRunner.expect(arena.zoneState).toBe("SafeZone")
		end)

		TestRunner.it("не должен начислять урон или награду за сундук локально до ответа сервера", function()
			local targetBefore = CombatController:GetActiveMobTarget()
			TestRunner.expect(targetBefore ~= nil).toBe(true)
			local hpBefore = targetBefore and targetBefore.currentHp or 40

			-- Локальный запрос открытия сундука переводит статус в Loading без выдачи награды
			local ok = CombatController:RequestOpenChest("meadow_supply_cache")
			TestRunner.expect(ok).toBe(true)

			local chests = CombatController:GetChests()
			local meadowChest = nil
			for _, c in ipairs(chests) do
				if c.id == "meadow_supply_cache" then
					meadowChest = c
					break
				end
			end
			TestRunner.expect(meadowChest ~= nil).toBe(true)
			TestRunner.expect(meadowChest.status).toBe("Loading")
			TestRunner.expect(meadowChest.lastRewardText).toBe(nil)

			-- Сервер подтверждает открытие сундука (ChestResult)
			CombatController:_handleChestResult({
				ok = true,
				chestId = "meadow_supply_cache",
				drops = {
					{ kind = "Currency", id = "Coins", amount = 35, displayName = "Coins" },
					{ kind = "Item", id = "scrap_head", amount = 1, displayName = "Scrapper Optic Visor" },
				},
			})

			local chestsAfter = CombatController:GetChests()
			for _, c in ipairs(chestsAfter) do
				if c.id == "meadow_supply_cache" then
					TestRunner.expect(c.status).toBe("Success")
					TestRunner.expect(c.lastRewardText ~= nil).toBe(true)
				end
			end

			-- Урон мобу применяется только после серверного CombatResult
			CombatController:_handleCombatResult({
				ok = true,
				mobUid = "meadow_scrap_drone",
				mobId = "meadow_scrap_drone",
				damageDealt = 14,
				isCritical = true,
				mobHealth = math.max(0, hpBefore - 14),
				mobMaxHealth = hpBefore,
				killed = false,
			})
			local targetAfter = CombatController:GetActiveMobTarget()
			TestRunner.expect(targetAfter and targetAfter.lastHitDamage).toBe(14)
			TestRunner.expect(targetAfter and targetAfter.lastHitCrit).toBe(true)
		end)

		TestRunner.it("должен пересчитывать бонусы сборки и 4/4 бонус комплекта Scrapper Rig", function()
			CombatController._inventory = {
				uid_1 = {
					uid = "uid_1",
					id = "scrap_head",
					category = "BodyHead",
					rarity = "Common",
					level = 1,
					equipped = true,
				},
				uid_2 = {
					uid = "uid_2",
					id = "scrap_arms",
					category = "BodyArms",
					rarity = "Common",
					level = 1,
					equipped = true,
				},
				uid_3 = {
					uid = "uid_3",
					id = "scrap_torso",
					category = "BodyTorso",
					rarity = "Common",
					level = 1,
					equipped = true,
				},
				uid_4 = {
					uid = "uid_4",
					id = "scrap_legs",
					category = "BodyLegs",
					rarity = "Common",
					level = 1,
					equipped = true,
				},
				uid_5 = {
					uid = "uid_5",
					id = "ember_arms",
					category = "BodyArms",
					rarity = "Rare",
					level = 1,
					equipped = false,
				},
			}
			-- Вызываем обновление через StatsUpdated / пересчёт
			CombatController:_handleSkillTreeSync({
				unlocked = { dmg_1 = true },
				availablePoints = 2,
				spentPoints = 1,
				earnedPoints = 3,
			})
			CombatController:_handleStatsSyncForTest()

			local summary = CombatController:GetAssemblyStats()
			TestRunner.expect(summary.equippedCount).toBe(4)
			TestRunner.expect(summary.activeSetId).toBe("scrapper")

			-- Проверяем сравнение бонусов неэкипированной детали ember_arms (+15 ATK против +6 ATK у scrap_arms => дельта +9)
			local armParts = CombatController:GetBodyPartsInventory("Arms")
			TestRunner.expect(#armParts).toBe(2)
			for _, part in ipairs(armParts) do
				if part.itemId == "ember_arms" then
					TestRunner.expect(part.deltaAttackPower).toBe(9)
				end
			end
		end)

		TestRunner.it("должен корректно обновлять состояние дерева навыков и добровольной PvP-арены", function()
			local reqOk = CombatController:RequestUnlockSkill("def_1")
			TestRunner.expect(reqOk).toBe(true)

			CombatController:_handleSkillUnlockResult({
				ok = true,
				skillId = "def_1",
				availablePoints = 1,
			})

			local defNodes = CombatController:GetSkillTreeNodes("Defense")
			local def1 = nil
			for _, n in ipairs(defNodes) do
				if n.id == "def_1" then
					def1 = n
					break
				end
			end
			TestRunner.expect(def1 ~= nil and def1.isUnlocked).toBe(true)

			-- Вход и выход из добровольной PvP-арены
			CombatController:RequestEnterArena()
			CombatController:_handleArenaStateChanged({
				inArena = true,
				arenaId = "sunforge_duel_ring",
				combatTagRemaining = 0,
				message = "Вы вошли на добровольную PvP-арену!",
			})
			local arenaIn = CombatController:GetArenaState()
			TestRunner.expect(arenaIn.isSafeZone).toBe(false)
			TestRunner.expect(arenaIn.zoneState).toBe("InArena")

			CombatController:RequestLeaveArena()
			CombatController:_handleArenaStateChanged({
				inArena = false,
				arenaId = "sunforge_duel_ring",
				combatTagRemaining = 0,
				message = "Вы вернулись в безопасную зону.",
			})
			local arenaOut = CombatController:GetArenaState()
			TestRunner.expect(arenaOut.isSafeZone).toBe(true)
			TestRunner.expect(arenaOut.zoneState).toBe("SafeZone")
		end)
	end)
end
