--!strict
--[[
	@module ArenaService
	@owner Agent A (Breight321)
	@description Серверно-авторитетная добровольная PvP-арена.
	PvP включается ТОЛЬКО при явном входе игрока в арену (EnterArena / RequestArenaEnter).
	В обычных зонах игроки не могут наносить друг другу урон.
	Использует отдельный от PvE баланс урона, критов и брони (CombatConfig.Arena.Balance).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Core"):WaitForChild("Types"))
local Logger = require(Shared:WaitForChild("Core"):WaitForChild("Logger"))
local Signal = require(Shared:WaitForChild("Core"):WaitForChild("Signal"))
local Network = require(Shared:WaitForChild("Core"):WaitForChild("Network"))
local CombatConfig = require(Shared:WaitForChild("Config"):WaitForChild("CombatConfig"))

type ArenaParticipant = {
	player: any,
	userId: number,
	enteredAt: number,
	combatTagUntil: number,
	lastAttackAt: number,
	health: number,
	maxHealth: number,
}

local ArenaService = {
	Name = "ArenaService",
	Dependencies = { "PlayerDataService", "StatsService" },
	OnPlayerEnteredArena = Signal.new(),
	OnPlayerLeftArena = Signal.new(),
	OnPvPHit = Signal.new(),
}

local log = Logger.new("ArenaService")
local playerDataService: any = nil
local statsService: any = nil

local participants: { [any]: ArenaParticipant } = {}
local participantsByUserId: { [number]: ArenaParticipant } = {}
local testPlayersByUserId: { [number]: any } = {}
local connections: { RBXScriptConnection } = {}
local defaultRng = Random.new()

local function isValidPlayerKey(player: any): boolean
	return player ~= nil and (typeof(player) == "Instance" or type(player) == "table")
end

local function isRealPlayer(player: any): boolean
	return typeof(player) == "Instance" and player:IsA("Player")
end

local function getPlayerUserId(player: any): number
	if isRealPlayer(player) then
		return (player :: Player).UserId
	elseif type(player) == "table" and type(player.UserId) == "number" then
		return player.UserId
	end
	return 0
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

local function teleportPlayerCharacter(player: any, targetPos: Vector3): ()
	if isRealPlayer(player) then
		local character = (player :: Player).Character
		local rootPart = if character then character:FindFirstChild("HumanoidRootPart") else nil
		if rootPart and rootPart:IsA("BasePart") then
			rootPart.CFrame = CFrame.new(targetPos + Vector3.new(0, 3, 0))
		end
	elseif type(player) == "table" then
		player.Position = targetPos
	end
end

local function getParticipantCount(): number
	local count = 0
	for _ in pairs(participants) do
		count += 1
	end
	return count
end

local function ensureArenaWorldMarkers(): ()
	local worldFolder = Workspace:FindFirstChild("CombatWorld") :: Folder?
	if not worldFolder then
		local newWorld = Instance.new("Folder")
		newWorld.Name = "CombatWorld"
		newWorld.Parent = Workspace
		worldFolder = newWorld
	end
	local validWorld = worldFolder :: Folder
	local arenaFolder = validWorld:FindFirstChild("Arena") :: Folder?
	if not arenaFolder then
		local newArena = Instance.new("Folder")
		newArena.Name = "Arena"
		newArena.Parent = validWorld
		arenaFolder = newArena
	end
	local validArena = arenaFolder :: Folder

	local arenaCfg = CombatConfig.Arena
	if not validArena:FindFirstChild("EntrancePad") then
		local entrance = Instance.new("Part")
		entrance.Name = "EntrancePad"
		entrance.Anchored = true
		entrance.CanCollide = false
		entrance.Transparency = 0.3
		entrance.Material = Enum.Material.Neon
		entrance.Color = Color3.fromRGB(255, 75, 95)
		entrance.Size = Vector3.new(10, 0.8, 10)
		entrance.Position = arenaCfg.EntrancePosition + Vector3.new(0, 0.4, 0)
		entrance:SetAttribute("ArenaId", arenaCfg.Id)
		entrance:SetAttribute("MinPlayerLevel", arenaCfg.MinPlayerLevel)
		entrance.Parent = validArena
	end

	if not validArena:FindFirstChild("ArenaFloor") then
		local floor = Instance.new("Part")
		floor.Name = "ArenaFloor"
		floor.Anchored = true
		floor.CanCollide = true
		floor.Material = Enum.Material.Cobblestone
		floor.Color = Color3.fromRGB(68, 56, 74)
		floor.Size = Vector3.new(arenaCfg.Radius * 2, 2, arenaCfg.Radius * 2)
		floor.Position = arenaCfg.CenterPosition - Vector3.new(0, 1, 0)
		floor:SetAttribute("ArenaId", arenaCfg.Id)
		floor.Parent = validArena
	end
end

local function setPlayerPvPAttribute(player: any, inArena: boolean): ()
	if not isRealPlayer(player) then
		return
	end
	local plr = player :: Player
	plr:SetAttribute("PvPEnabled", inArena)
	if plr.Character then
		plr.Character:SetAttribute("PvPEnabled", inArena)
	end
end

local function sendArenaState(player: any, payload: Types.ArenaStatePayload): ()
	if not isRealPlayer(player) then
		return
	end
	Network.FireClient(player, Network.Events.ArenaStateChanged, payload)
end

function ArenaService:Init(registry: any): ()
	playerDataService = registry:Get("PlayerDataService")
	statsService = registry:Get("StatsService")
	log:Info("Initialized.")
end

function ArenaService:Start(): ()
	ensureArenaWorldMarkers()

	table.insert(
		connections,
		playerDataService.OnProfileReleasing:Connect(function(player: any)
			local p = participants[player]
			if p then
				participants[player] = nil
				participantsByUserId[p.userId] = nil
			end
		end)
	)

	table.insert(
		connections,
		Network.OnServerEvent(Network.Events.RequestArenaEnter, function(player: Player)
			local res = self:EnterArena(player)
			sendArenaState(player, res)
		end)
	)

	table.insert(
		connections,
		Network.OnServerEvent(Network.Events.RequestArenaLeave, function(player: Player)
			local res = self:LeaveArena(player)
			sendArenaState(player, res)
		end)
	)

	table.insert(
		connections,
		Network.OnServerEvent(Network.Events.RequestPvPAttack, function(player: Player, rawTargetUserId: any)
			local targetId = if type(rawTargetUserId) == "number" then math.floor(rawTargetUserId) else 0
			local res = self:AttackPlayer(player, targetId)
			Network.FireClient(player, Network.Events.PvPCombatResult, res)
		end)
	)

	log:Info("Started.")
end

function ArenaService:Shutdown(): ()
	for _, conn in ipairs(connections) do
		conn:Disconnect()
	end
	table.clear(connections)
	table.clear(participants)
	table.clear(participantsByUserId)
	table.clear(testPlayersByUserId)
end

function ArenaService:RegisterTestPlayer(mockPlayer: any): ()
	if type(mockPlayer) == "table" and type(mockPlayer.UserId) == "number" then
		testPlayersByUserId[mockPlayer.UserId] = mockPlayer
	end
end

function ArenaService:ClearCooldownsForTest(player: any): ()
	local part = participants[player]
	if part then
		part.lastAttackAt = 0
		part.combatTagUntil = 0
	end
end

function ArenaService:IsInArena(player: any): boolean
	return participants[player] ~= nil
end

function ArenaService:EnterArena(player: any): Types.ArenaStatePayload
	local function fail(code: Types.ArenaErrorCode, inArena: boolean): Types.ArenaStatePayload
		local part = participants[player]
		return {
			ok = false,
			errorCode = code,
			inArena = inArena,
			pvpEnabled = inArena,
			combatTagExpiresAt = if part then part.combatTagUntil else 0,
			participantsCount = getParticipantCount(),
		}
	end

	if not isValidPlayerKey(player) then
		return fail("INVALID_PLAYER", false)
	end

	local profile = unwrapProfile(player)
	if not profile then
		return fail("PROFILE_NOT_LOADED", false)
	end

	if participants[player] ~= nil then
		return fail("ALREADY_IN_ARENA", true)
	end

	local arenaCfg = CombatConfig.Arena
	if profile.level < arenaCfg.MinPlayerLevel then
		return fail("LEVEL_TOO_LOW", false)
	end

	local hasChar, isDead, playerPos = getPlayerCombatState(player, arenaCfg.EntrancePosition)
	if not hasChar or not playerPos then
		return fail("CHARACTER_NOT_READY", false)
	end
	if isDead then
		return fail("PLAYER_DEAD", false)
	end

	local distToEntrance = (playerPos - arenaCfg.EntrancePosition).Magnitude
	if distToEntrance > arenaCfg.EntranceRadius then
		return fail("OUT_OF_RANGE", false)
	end

	local pStats = statsService:GetStats(player)
	local userId = getPlayerUserId(player)
	local spawnList = arenaCfg.SpawnPoints
	local spawnIdx = (getParticipantCount() % #spawnList) + 1
	local spawnPos = spawnList[spawnIdx] or arenaCfg.CenterPosition

	local newPart: ArenaParticipant = {
		player = player,
		userId = userId,
		enteredAt = os.clock(),
		combatTagUntil = 0,
		lastAttackAt = 0,
		health = pStats.maxHealth,
		maxHealth = pStats.maxHealth,
	}

	participants[player] = newPart
	if userId ~= 0 then
		participantsByUserId[userId] = newPart
	end

	teleportPlayerCharacter(player, spawnPos)
	setPlayerPvPAttribute(player, true)

	if isRealPlayer(player) then
		local char = (player :: Player).Character
		local hum = if char then char:FindFirstChildOfClass("Humanoid") else nil
		if hum then
			hum.MaxHealth = pStats.maxHealth
			hum.Health = pStats.maxHealth
		end
	end

	local payload: Types.ArenaStatePayload = {
		ok = true,
		errorCode = nil,
		inArena = true,
		pvpEnabled = true,
		combatTagExpiresAt = 0,
		participantsCount = getParticipantCount(),
	}

	self.OnPlayerEnteredArena:Fire(player, payload)
	return payload
end

function ArenaService:LeaveArena(player: any): Types.ArenaStatePayload
	local function fail(code: Types.ArenaErrorCode, inArena: boolean, tagUntil: number): Types.ArenaStatePayload
		return {
			ok = false,
			errorCode = code,
			inArena = inArena,
			pvpEnabled = inArena,
			combatTagExpiresAt = tagUntil,
			participantsCount = getParticipantCount(),
		}
	end

	if not isValidPlayerKey(player) then
		return fail("INVALID_PLAYER", false, 0)
	end

	local part = participants[player]
	if not part then
		return fail("NOT_IN_ARENA", false, 0)
	end

	local now = os.clock()
	if now < part.combatTagUntil then
		return fail("COMBAT_TAGGED", true, part.combatTagUntil)
	end

	participants[player] = nil
	if part.userId ~= 0 then
		participantsByUserId[part.userId] = nil
	end

	setPlayerPvPAttribute(player, false)
	teleportPlayerCharacter(player, CombatConfig.Arena.EntrancePosition)

	if isRealPlayer(player) then
		local char = (player :: Player).Character
		local hum = if char then char:FindFirstChildOfClass("Humanoid") else nil
		local pStats = statsService:GetStats(player)
		if hum and hum.Health > 0 then
			hum.MaxHealth = pStats.maxHealth
			hum.Health = pStats.maxHealth
		end
	end

	local payload: Types.ArenaStatePayload = {
		ok = true,
		errorCode = nil,
		inArena = false,
		pvpEnabled = false,
		combatTagExpiresAt = 0,
		participantsCount = getParticipantCount(),
	}

	self.OnPlayerLeftArena:Fire(player, payload)
	return payload
end

function ArenaService:AttackPlayer(attacker: any, targetUserId: number): Types.PvPCombatResultPayload
	local attackerId = getPlayerUserId(attacker)
	local function fail(code: Types.ArenaErrorCode, targetPart: ArenaParticipant?): Types.PvPCombatResultPayload
		return {
			ok = false,
			errorCode = code,
			attackerUserId = attackerId,
			targetUserId = targetUserId,
			damageDealt = 0,
			isCrit = false,
			targetRemainingHealth = if targetPart then targetPart.health else 0,
			targetMaxHealth = if targetPart then targetPart.maxHealth else 0,
			targetDefeated = false,
		}
	end

	if not isValidPlayerKey(attacker) then
		return fail("INVALID_PLAYER", nil)
	end

	local attackerProfile = unwrapProfile(attacker)
	if not attackerProfile then
		return fail("PROFILE_NOT_LOADED", nil)
	end

	-- Защита мирных зон: атакующий обязан находиться в добровольной PvP-арене
	local attackerPart = participants[attacker]
	if not attackerPart then
		return fail("NOT_IN_ARENA", nil)
	end

	if type(targetUserId) ~= "number" or targetUserId == 0 or targetUserId == attackerId then
		return fail("INVALID_TARGET", nil)
	end

	-- Ищем цель: только участники арены могут получать PvP-урон
	local targetPart = participantsByUserId[targetUserId]
	if not targetPart then
		-- Проверим, существует ли вообще такой игрок вне арены, чтобы вернуть точный код TARGET_NOT_IN_ARENA
		local outsideReal = Players:GetPlayerByUserId(targetUserId)
		local outsideTest = testPlayersByUserId[targetUserId]
		if outsideReal or outsideTest then
			return fail("TARGET_NOT_IN_ARENA", nil)
		end
		return fail("INVALID_TARGET", nil)
	end

	local targetPlayer = targetPart.player
	local arenaCfg = CombatConfig.Arena

	local attHasChar, attDead, attPos = getPlayerCombatState(attacker, arenaCfg.CenterPosition)
	if not attHasChar or not attPos then
		return fail("CHARACTER_NOT_READY", targetPart)
	end
	if attDead or attackerPart.health <= 0 then
		return fail("PLAYER_DEAD", targetPart)
	end

	local tgtHasChar, tgtDead, tgtPos = getPlayerCombatState(targetPlayer, arenaCfg.CenterPosition)
	if not tgtHasChar or not tgtPos then
		return fail("INVALID_TARGET", targetPart)
	end
	if tgtDead or targetPart.health <= 0 then
		return fail("TARGET_DEAD", targetPart)
	end

	local dist = (attPos - tgtPos).Magnitude
	if dist > arenaCfg.Balance.MaxAttackRange then
		return fail("OUT_OF_RANGE", targetPart)
	end

	local now = os.clock()
	local attStats = statsService:GetStats(attacker)
	local effectiveCooldown = math.max(arenaCfg.Balance.AttackCooldownFloor, attStats.attackCooldown)
	if (now - attackerPart.lastAttackAt) < effectiveCooldown then
		return fail("ATTACK_COOLDOWN", targetPart)
	end
	attackerPart.lastAttackAt = now

	-- Отдельный от PvE баланс PvP-урона (CombatConfig.Arena.Balance)
	local tgtStats = statsService:GetStats(targetPlayer)
	targetPart.maxHealth = tgtStats.maxHealth
	if targetPart.health > targetPart.maxHealth then
		targetPart.health = targetPart.maxHealth
	end

	local isCrit = defaultRng:NextNumber() < attStats.critChance
	local critMult = if isCrit then math.min(attStats.critMultiplier, arenaCfg.Balance.CritMultiplierCap) else 1.0
	local scaledRaw = attStats.damage * arenaCfg.Balance.DamageScale * critMult
	local effectiveDefense = tgtStats.defense * arenaCfg.Balance.DefenseEffectivenessMultiplier
	local mitigated = statsService:ComputeMitigatedDamage(scaledRaw, effectiveDefense)
	local maxCap = math.max(1, math.floor(targetPart.maxHealth * arenaCfg.Balance.MaxSingleHitHealthFraction + 0.5))
	local finalDamage = math.clamp(mitigated, 1, maxCap)

	targetPart.health = math.max(0, targetPart.health - finalDamage)

	local tagUntil = now + arenaCfg.CombatTagDurationSeconds
	attackerPart.combatTagUntil = tagUntil
	targetPart.combatTagUntil = tagUntil

	if isRealPlayer(targetPlayer) then
		local char = (targetPlayer :: Player).Character
		local hum = if char then char:FindFirstChildOfClass("Humanoid") else nil
		if hum and hum.Health > 0 then
			hum:TakeDamage(finalDamage)
		end
	end

	local targetDefeated = targetPart.health <= 0
	if targetDefeated then
		-- Записываем статистику PvP-победы/поражения в профиль и восстанавливаем здоровье побеждённого на точке возрождения арены
		playerDataService:UpdateProfile(attacker, function(p: Types.PlayerProfileData)
			if type(p.customData) == "table" and type(p.customData.combat) == "table" then
				p.customData.combat.pvpKills = (p.customData.combat.pvpKills or 0) + 1
			end
			return true
		end)
		playerDataService:UpdateProfile(targetPlayer, function(p: Types.PlayerProfileData)
			if type(p.customData) == "table" and type(p.customData.combat) == "table" then
				p.customData.combat.pvpDeaths = (p.customData.combat.pvpDeaths or 0) + 1
			end
			return true
		end)

		-- Сбрасываем боевую метку у побеждённого и восстанавливаем здоровье для следующего раунда
		targetPart.combatTagUntil = 0
		targetPart.health = targetPart.maxHealth
		local respawnPos = arenaCfg.SpawnPoints[1] or arenaCfg.CenterPosition
		teleportPlayerCharacter(targetPlayer, respawnPos)
	end

	local resPayload: Types.PvPCombatResultPayload = {
		ok = true,
		errorCode = nil,
		attackerUserId = attackerId,
		targetUserId = targetUserId,
		damageDealt = finalDamage,
		isCrit = isCrit,
		targetRemainingHealth = if targetDefeated then 0 else targetPart.health,
		targetMaxHealth = targetPart.maxHealth,
		targetDefeated = targetDefeated,
	}

	if isRealPlayer(targetPlayer) then
		Network.FireClient(targetPlayer, Network.Events.PvPCombatResult, resPayload)
	end
	self.OnPvPHit:Fire(attacker, targetPlayer, resPayload)

	return resPayload
end

return ArenaService
