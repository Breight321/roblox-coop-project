--!strict
--[[
	@module CombatService
	@owner Agent A (Breight321)
	@description Серверно-авторитетный сервис PvE-боя с мобами:
	спавн и респавн мобов в Workspace.CombatWorld.Mobs, проверка цели/дистанции/зоны/уровня/кулдауна,
	расчёт урона и критов через StatsService, учёт вклада игроков, выдача XP (ProgressionService),
	монет (EconomyService) и деталей тела (LootService -> InventoryService).
]]

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Core"):WaitForChild("Types"))
local Logger = require(Shared:WaitForChild("Core"):WaitForChild("Logger"))
local Signal = require(Shared:WaitForChild("Core"):WaitForChild("Signal"))
local Network = require(Shared:WaitForChild("Core"):WaitForChild("Network"))
local CombatConfig = require(Shared:WaitForChild("Config"):WaitForChild("CombatConfig"))

export type ActiveMobInstance = {
	mobUid: string,
	mobId: string,
	def: Types.MobDef,
	position: Vector3,
	health: number,
	maxHealth: number,
	isAlive: boolean,
	damageByPlayer: { [any]: number },
	lastMobAttackAt: number,
	part: BasePart?,
	isTestMob: boolean?,
}

local CombatService = {
	Name = "CombatService",
	Dependencies = { "PlayerDataService", "ProgressionService", "EconomyService", "StatsService", "LootService" },
	OnMobDamaged = Signal.new(),
	OnMobDefeated = Signal.new(),
}

local log = Logger.new("CombatService")
local serviceRegistry: any = nil
local playerDataService: any = nil
local progressionService: any = nil
local economyService: any = nil
local statsService: any = nil
local lootService: any = nil

local activeMobs: { [string]: ActiveMobInstance } = {}
local lastAttackTime: { [any]: number } = {}
local connections: { RBXScriptConnection } = {}
local aiLoopThread: thread? = nil
local customRng: Random? = nil
local defaultRng = Random.new()

local function isValidPlayerKey(player: any): boolean
	return player ~= nil and (typeof(player) == "Instance" or type(player) == "table")
end

local function isRealPlayer(player: any): boolean
	return typeof(player) == "Instance" and player:IsA("Player")
end

local function unwrapProfile(player: any): Types.PlayerProfileData?
	if not playerDataService then
		return nil
	end
	local res = playerDataService:GetProfile(player)
	if type(res) == "table" and res.ok ~= nil then
		if res.ok and res.value then
			return res.value
		end
		return nil
	end
	return res
end

local function createDefaultCombatSection(): {
	totalMobKills: number,
	mobKillsById: { [string]: number },
	pvpKills: number,
	pvpDeaths: number,
}
	return {
		totalMobKills = 0,
		mobKillsById = {},
		pvpKills = 0,
		pvpDeaths = 0,
	}
end

local function ensureCombatSection(profile: Types.PlayerProfileData): {
	totalMobKills: number,
	mobKillsById: { [string]: number },
	pvpKills: number,
	pvpDeaths: number,
}
	if type(profile.customData) ~= "table" then
		profile.customData = {}
	end
	local raw = profile.customData.combat
	if type(raw) ~= "table" then
		local def = createDefaultCombatSection()
		profile.customData.combat = def
		raw = def
	end
	if type(raw.totalMobKills) ~= "number" or raw.totalMobKills < 0 then
		raw.totalMobKills = 0
	end
	if type(raw.mobKillsById) ~= "table" then
		raw.mobKillsById = {}
	end
	if type(raw.pvpKills) ~= "number" or raw.pvpKills < 0 then
		raw.pvpKills = 0
	end
	if type(raw.pvpDeaths) ~= "number" or raw.pvpDeaths < 0 then
		raw.pvpDeaths = 0
	end
	return raw
end

local function getPlayerCombatState(player: any, fallbackPos: Vector3): (boolean, boolean, Vector3?)
	if isRealPlayer(player) then
		local character = (player :: Player).Character
		if not character then
			return false, false, nil
		end
		local rootPart = character:FindFirstChild("HumanoidRootPart")
		if not rootPart or not rootPart:IsA("BasePart") then
			return false, false, nil
		end
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.Health <= 0 then
			return true, true, rootPart.Position
		end
		return true, false, rootPart.Position
	elseif type(player) == "table" then
		if player.CharacterMissing == true then
			return false, false, nil
		end
		if player.IsDead == true then
			return true, true, if typeof(player.Position) == "Vector3" then player.Position else fallbackPos
		end
		local pos = if typeof(player.Position) == "Vector3" then player.Position else fallbackPos
		return true, false, pos
	end
	return false, false, nil
end

local function ensureMobsFolder(): Folder
	local worldFolder = Workspace:FindFirstChild("CombatWorld") :: Folder?
	if not worldFolder then
		local newWorld = Instance.new("Folder")
		newWorld.Name = "CombatWorld"
		newWorld.Parent = Workspace
		worldFolder = newWorld
	end
	local validWorld = worldFolder :: Folder
	local mobsFolder = validWorld:FindFirstChild("Mobs") :: Folder?
	if not mobsFolder then
		local newMobs = Instance.new("Folder")
		newMobs.Name = "Mobs"
		newMobs.Parent = validWorld
		mobsFolder = newMobs
	end
	return mobsFolder :: Folder
end

local function syncMobInstanceAttributes(mob: ActiveMobInstance): ()
	local part = mob.part
	if not part then
		return
	end
	part:SetAttribute("MobUid", mob.mobUid)
	part:SetAttribute("MobId", mob.mobId)
	part:SetAttribute("ZoneId", mob.def.zoneId)
	part:SetAttribute("DisplayName", mob.def.displayName)
	part:SetAttribute("Level", mob.def.level)
	part:SetAttribute("Health", mob.health)
	part:SetAttribute("MaxHealth", mob.maxHealth)
	part:SetAttribute("IsAlive", mob.isAlive)
	part.Transparency = if mob.isAlive then 0.05 else 0.8
	part.CanCollide = mob.isAlive
end

local function createMobWorldPart(mob: ActiveMobInstance): BasePart
	local folder = ensureMobsFolder()
	local part = Instance.new("Part")
	part.Name = mob.mobUid
	part.Anchored = true
	part.CanCollide = true
	part.Material = Enum.Material.SmoothPlastic
	part.Color = if mob.def.zoneId == "spawn_meadow"
		then Color3.fromRGB(165, 142, 115)
		elseif mob.def.zoneId == "ember_woods" then Color3.fromRGB(235, 98, 48)
		else Color3.fromRGB(92, 195, 255)
	part.Size = if mob.def.level >= 5 then Vector3.new(6, 7, 6) else Vector3.new(4, 5, 4)
	part.Position = mob.position + Vector3.new(0, part.Size.Y * 0.5, 0)
	part.Parent = folder
	mob.part = part
	syncMobInstanceAttributes(mob)
	return part
end

local function spawnConfiguredMobs(): ()
	ensureMobsFolder()
	for mobId, def in pairs(CombatConfig.Mobs) do
		for index, spawnPos in ipairs(def.spawnPositions) do
			local mobUid = string.format("%s_%d", mobId, index)
			if not activeMobs[mobUid] then
				local inst: ActiveMobInstance = {
					mobUid = mobUid,
					mobId = mobId,
					def = def,
					position = spawnPos,
					health = def.maxHealth,
					maxHealth = def.maxHealth,
					isAlive = true,
					damageByPlayer = {},
					lastMobAttackAt = 0,
					part = nil,
					isTestMob = false,
				}
				activeMobs[mobUid] = inst
				createMobWorldPart(inst)
			end
		end
	end
end

local function grantMobKillRewardsToPlayer(
	contributor: any,
	mob: ActiveMobInstance
): Types.MobDefeatedPayload?
	local profile = unwrapProfile(contributor)
	if not profile then
		return nil
	end

	local totalKills = 0
	playerDataService:UpdateProfile(contributor, function(p: Types.PlayerProfileData)
		local combatSec = ensureCombatSection(p)
		combatSec.totalMobKills += 1
		combatSec.mobKillsById[mob.mobId] = (combatSec.mobKillsById[mob.mobId] or 0) + 1
		totalKills = combatSec.totalMobKills
		return true
	end)

	local def = mob.def
	local xpAwarded = def.xpReward
	local coinsAwarded = def.coinReward

	if xpAwarded > 0 then
		progressionService:AddXP(contributor, xpAwarded)
	end
	if coinsAwarded > 0 then
		economyService:AddCurrency(contributor, "Coins", coinsAwarded, "MobKill:" .. mob.mobId)
	end

	local rng = customRng or defaultRng
	local rolledDrops = lootService:RollLootTable(def.lootTableId, rng)
	local grantedDrops = lootService:GrantDrops(contributor, rolledDrops, "MobLoot:" .. mob.mobId)

	local refreshedProfile = unwrapProfile(contributor)
	local payload: Types.MobDefeatedPayload = {
		mobUid = mob.mobUid,
		mobId = mob.mobId,
		xpAwarded = xpAwarded,
		coinsAwarded = coinsAwarded,
		drops = grantedDrops,
		newLevel = if refreshedProfile then refreshedProfile.level else profile.level,
		newXP = if refreshedProfile then refreshedProfile.xp else profile.xp,
		totalMobKills = totalKills,
	}

	if isRealPlayer(contributor) then
		Network.FireClient(contributor, Network.Events.MobDefeated, payload)
	end
	CombatService.OnMobDefeated:Fire(contributor, mob, payload)

	return payload
end

function CombatService:Init(registry: any): ()
	serviceRegistry = registry
	playerDataService = registry:Get("PlayerDataService")
	progressionService = registry:Get("ProgressionService")
	economyService = registry:Get("EconomyService")
	statsService = registry:Get("StatsService")
	lootService = registry:Get("LootService")

	playerDataService:RegisterSchemaSection("combat", createDefaultCombatSection())
	log:Info("Initialized.")
end

function CombatService:Start(): ()
	spawnConfiguredMobs()

	table.insert(
		connections,
		playerDataService.OnProfileReleasing:Connect(function(player: any)
			lastAttackTime[player] = nil
		end)
	)

	table.insert(
		connections,
		Network.OnServerEvent(Network.Events.RequestAttackMob, function(player: Player, rawMobUid: any)
			local mobUid = if type(rawMobUid) == "string" and #rawMobUid <= 80 then rawMobUid else ""
			local res = self:AttackMob(player, mobUid)
			Network.FireClient(player, Network.Events.CombatResult, res)
		end)
	)

	-- Фоновый цикл ответных атак живых мобов по игрокам в радиусе
	aiLoopThread = task.spawn(function()
		while true do
			task.wait(0.5)
			local now = os.clock()
			local Players = game:GetService("Players")
			local onlinePlayers = Players:GetPlayers()
			if #onlinePlayers > 0 then
				for _, mob in pairs(activeMobs) do
					if mob.isAlive and not mob.isTestMob and (now - mob.lastMobAttackAt) >= mob.def.attackIntervalSeconds then
						for _, plr in ipairs(onlinePlayers) do
							local hasChar, isDead, plrPos = getPlayerCombatState(plr, mob.position)
							if hasChar and not isDead and plrPos then
								local dist = (plrPos - mob.position).Magnitude
								if dist <= mob.def.attackRange then
									local character = plr.Character
									local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
									if humanoid and humanoid.Health > 0 then
										mob.lastMobAttackAt = now
										local pStats = statsService:GetStats(plr)
										local dmg = statsService:ComputeMitigatedDamage(mob.def.damage, pStats.defense)
										humanoid:TakeDamage(dmg)
										break
									end
								end
							end
						end
					end
				end
			end
		end
	end)

	log:Info("Started.")
end

function CombatService:Shutdown(): ()
	if aiLoopThread then
		task.cancel(aiLoopThread)
		aiLoopThread = nil
	end
	for _, conn in ipairs(connections) do
		conn:Disconnect()
	end
	table.clear(connections)
end

function CombatService:GetActiveMobs(): { [string]: ActiveMobInstance }
	return activeMobs
end

function CombatService:GetPlayerCombatRecord(player: any): { totalMobKills: number, mobKillsById: { [string]: number } }
	local profile = unwrapProfile(player)
	if not profile then
		return {
			totalMobKills = 0,
			mobKillsById = {},
		}
	end
	local sec = ensureCombatSection(profile)
	local copyMap: { [string]: number } = {}
	for k, v in pairs(sec.mobKillsById) do
		copyMap[k] = v
	end
	return {
		totalMobKills = sec.totalMobKills,
		mobKillsById = copyMap,
	}
end

function CombatService:AttackMob(player: any, mobUid: string): Types.CombatResultPayload
	local function fail(code: Types.CombatErrorCode, mobInst: ActiveMobInstance?): Types.CombatResultPayload
		return {
			ok = false,
			errorCode = code,
			mobUid = if mobInst then mobInst.mobUid else tostring(mobUid or ""),
			mobId = if mobInst then mobInst.mobId else "",
			damageDealt = 0,
			isCrit = false,
			mobRemainingHealth = if mobInst then mobInst.health else 0,
			mobMaxHealth = if mobInst then mobInst.maxHealth else 0,
			defeated = false,
		}
	end

	if not isValidPlayerKey(player) then
		return fail("INVALID_PLAYER", nil)
	end

	local profile = unwrapProfile(player)
	if not profile then
		return fail("PROFILE_NOT_LOADED", nil)
	end

	local arenaService = if serviceRegistry then serviceRegistry:TryGet("ArenaService") else nil
	if arenaService and arenaService:IsInArena(player) then
		return fail("IN_ARENA", nil)
	end

	if type(mobUid) ~= "string" or activeMobs[mobUid] == nil then
		return fail("INVALID_TARGET", nil)
	end

	local mob = activeMobs[mobUid]
	if not mob.isAlive or mob.health <= 0 then
		return fail("TARGET_DEAD", mob)
	end

	local hasChar, isDead, playerPos = getPlayerCombatState(player, mob.position)
	if not hasChar or not playerPos then
		return fail("CHARACTER_NOT_READY", mob)
	end
	if isDead then
		return fail("PLAYER_DEAD", mob)
	end

	local zoneRule = CombatConfig.ZoneRules[mob.def.zoneId]
	if zoneRule then
		if zoneRule.requireUnlockedZone and not profile.unlockedZones[mob.def.zoneId] then
			return fail("ZONE_LOCKED", mob)
		end
		if profile.level < zoneRule.minPlayerLevel then
			return fail("LEVEL_TOO_LOW", mob)
		end
	end

	local maxAllowedRange = math.max(mob.def.attackRange, CombatConfig.DefaultMeleeRange)
	local dist = (playerPos - mob.position).Magnitude
	if dist > maxAllowedRange then
		return fail("OUT_OF_RANGE", mob)
	end

	local pStats = statsService:GetStats(player)
	local now = os.clock()
	local prevAttack = lastAttackTime[player] or 0
	if (now - prevAttack) < pStats.attackCooldown then
		return fail("ATTACK_COOLDOWN", mob)
	end
	lastAttackTime[player] = now

	local rng = customRng or defaultRng
	local isCrit = rng:NextNumber() < pStats.critChance
	local rawDamage = pStats.damage
	if isCrit then
		rawDamage = math.floor(rawDamage * pStats.critMultiplier + 0.5)
	end
	local finalDamage = statsService:ComputeMitigatedDamage(rawDamage, mob.def.defense)

	mob.health = math.max(0, mob.health - finalDamage)
	mob.damageByPlayer[player] = (mob.damageByPlayer[player] or 0) + finalDamage

	local defeated = mob.health <= 0
	if defeated then
		mob.isAlive = false
	end

	syncMobInstanceAttributes(mob)
	self.OnMobDamaged:Fire(player, mob, finalDamage, isCrit)

	if defeated then
		local minContrib = mob.maxHealth * CombatConfig.MinContributionRatioForRewards
		local rewardedPlayers: { [any]: boolean } = {}

		-- Всегда вознаграждаем игрока, нанёсшего добивающий удар
		rewardedPlayers[player] = true
		grantMobKillRewardsToPlayer(player, mob)

		-- А также всех помощников, нанёсших >= 15% здоровья моба
		for contributor, dmgDone in pairs(mob.damageByPlayer) do
			if not rewardedPlayers[contributor] and dmgDone >= minContrib then
				rewardedPlayers[contributor] = true
				grantMobKillRewardsToPlayer(contributor, mob)
			end
		end

		table.clear(mob.damageByPlayer)

		if not mob.isTestMob then
			local respawnDelay = math.max(1, mob.def.respawnSeconds)
			task.delay(respawnDelay, function()
				if activeMobs[mob.mobUid] == mob then
					mob.health = mob.maxHealth
					mob.isAlive = true
					table.clear(mob.damageByPlayer)
					syncMobInstanceAttributes(mob)
				end
			end)
		end
	end

	return {
		ok = true,
		errorCode = nil,
		mobUid = mob.mobUid,
		mobId = mob.mobId,
		damageDealt = finalDamage,
		isCrit = isCrit,
		mobRemainingHealth = mob.health,
		mobMaxHealth = mob.maxHealth,
		defeated = defeated,
	}
end

function CombatService:SpawnMobForTest(mobId: string, customPos: Vector3?): string?
	local def = CombatConfig.Mobs[mobId]
	if not def then
		return nil
	end
	local mobUid = "test_" .. mobId .. "_" .. HttpService:GenerateGUID(false)
	local pos = customPos or def.spawnPositions[1] or Vector3.new(0, 0, 0)
	local inst: ActiveMobInstance = {
		mobUid = mobUid,
		mobId = mobId,
		def = def,
		position = pos,
		health = def.maxHealth,
		maxHealth = def.maxHealth,
		isAlive = true,
		damageByPlayer = {},
		lastMobAttackAt = 0,
		part = nil,
		isTestMob = true,
	}
	activeMobs[mobUid] = inst
	createMobWorldPart(inst)
	return mobUid
end

function CombatService:DespawnMobForTest(mobUid: string): ()
	local inst = activeMobs[mobUid]
	if inst then
		if inst.part then
			inst.part:Destroy()
		end
		activeMobs[mobUid] = nil
	end
end

function CombatService:ClearCooldownForTest(player: any): ()
	lastAttackTime[player] = nil
end

function CombatService:SetRngForTests(rng: Random?): ()
	customRng = rng
end

return CombatService
