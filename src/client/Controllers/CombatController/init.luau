--!strict
--[[
	@module CombatController
	@owner Agent B (anarugod)
	@description Клиентский контроллер боевого цикла (Combat Loop v1):
	1. Обратная связь боя: отправка RequestAttackMob(mobUid), обработка серверных ответов
	   CombatResult и MobDefeated, синхронизация здоровья мобов из Workspace.CombatWorld.Mobs,
	   уведомления о победе и награде без локального назначения урона или лута.
	2. Инвентарь деталей тела: просмотр слотов (Head, Arms, Torso, Legs), сравнение бонусов
	   с текущей экипировкой, отправка RequestEquipItem(itemUid, equip), расчёт дельты характеристик
	   и отображение 4/4 бонуса набора (BodySetsConfig) по серверным ответам InventoryUpdated и StatsUpdated.
	3. Сундуки: взаимодействие с сундуками в мире, отправка RequestOpenChest(chestId),
	   синхронизация прогресса мобов/кулдауна через ChestStateSync и показ выигрыша только после ChestResult.
	4. Дерево навыков: ветки Damage, Defense, Mobility (SkillTreeConfig), отправка RequestUnlockSkill(skillId),
	   синхронизация через SkillTreeSync и SkillUnlockResult с состояниями Loading / Success / Error.
	5. PvP-арена: добровольный вход (RequestArenaEnter) и выход (RequestArenaLeave), атака в арене (RequestPvPAttack),
	   индикатор PvP-зоны (ArenaStateChanged) и результат боя (PvPCombatResult).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Network = require(Shared:WaitForChild("Core"):WaitForChild("Network"))
local Signal = require(Shared:WaitForChild("Core"):WaitForChild("Signal"))
local SharedTypes = require(Shared:WaitForChild("Core"):WaitForChild("Types"))

local Config = require(script:WaitForChild("Config"))
local Types = require(script:WaitForChild("Types"))

local CombatController = {
	Name = "CombatController",
	Dependencies = { "AudioController", "AnimationController" },

	OnStateChanged = Signal.new(),
	OnCombatHitFeedback = Signal.new(),
	OnMobDefeated = Signal.new(),
	OnAssemblyUpdated = Signal.new(),
	OnChestResolved = Signal.new(),
	OnArenaMatchResolved = Signal.new(),

	_initialized = false,
	_started = false,

	-- Серверное состояние игрока (источник истины)
	_playerLevel = 1,
	_playerXp = 0,
	_coins = 0,
	_gems = 0,
	_inventory = {} :: { [string]: SharedTypes.InventoryItem },
	_serverStats = nil :: any,

	-- Локальное представление деталей тела и сборки
	_bodyParts = {} :: { Types.BodyPartViewModel },
	_assemblyStats = {
		level = 1,
		attackPower = Config.SharedCombat.BaseStats.attackPower,
		defense = Config.SharedCombat.BaseStats.defense,
		damageReductionPct = 0,
		maxHealth = Config.SharedCombat.BaseStats.maxHealth,
		moveSpeed = Config.SharedCombat.BaseStats.moveSpeed,
		critChancePct = math.floor(Config.SharedCombat.BaseStats.critChance * 100 + 0.5),
		critMultiplier = Config.SharedCombat.BaseStats.critMultiplier,
		attackCooldown = Config.SharedCombat.BaseStats.attackCooldown,
		equippedCount = 0,
		equippedBySlot = {},
		activeSetId = nil,
		activeSetName = nil,
		activeSetDescription = nil,
		setCounts = {},
		lastDeltaSummary = nil,
	} :: Types.AssemblyStatsSummary,
	_pendingEquipUid = nil :: string?,

	-- Мобы и активная цель боя
	_mobTargets = {} :: { [string]: Types.MobTargetViewModel },
	_activeTargetMobUid = nil :: string?,
	_lastAttackAt = 0,

	-- Сундуки
	_chestStates = {} :: { [string]: Types.ChestDefViewModel },

	-- Дерево навыков
	_unlockedSkills = {} :: { [string]: boolean },
	_skillNodes = {} :: { [string]: Types.SkillNodeViewModel },
	_skillSummary = {
		availablePoints = Config.SkillTree.StartingPoints or 1,
		spentPoints = 0,
		earnedPoints = Config.SkillTree.StartingPoints or 1,
		unlockedCount = 0,
	} :: Types.SkillTreeSummaryViewModel,

	-- Добровольная PvP-арена
	_arenaState = {
		zoneState = "SafeZone",
		isSafeZone = true,
		arenaId = Config.SharedCombat.Arena.ArenaId,
		arenaDisplayName = Config.SharedCombat.Arena.DisplayName,
		minPlayerLevel = Config.SharedCombat.Arena.MinPlayerLevel,
		combatTaggedSeconds = 0,
		statusText = "Безопасная зона (PvE)",
		rulesSummary = Config.ArenaRulesSummary,
		lastMatchOutcome = "None",
		lastMatchMessage = nil,
		pvpKills = 0,
		pvpDeaths = 0,
	} :: Types.ArenaStateViewModel,

	-- Наблюдатели UI / Мира
	_combatListeners = {} :: { (Types.MobTargetViewModel?, Types.CombatHitFeedback?) -> () },
	_inventoryListeners = {} :: { ({ Types.BodyPartViewModel }, Types.AssemblyStatsSummary) -> () },
	_chestListeners = {} :: { ({ Types.ChestDefViewModel }, string?) -> () },
	_skillListeners = {} :: { ({ Types.SkillNodeViewModel }, Types.SkillTreeSummaryViewModel) -> () },
	_arenaListeners = {} :: { (Types.ArenaStateViewModel) -> () },

	-- Ссылки на соседние клиентские контроллеры
	_audioController = nil :: any,
	_animationController = nil :: any,
	_uiController = nil :: any,
}

-- ============================================================================
-- ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ СБОРКИ И КОНФИГОВ
-- ============================================================================

local function mapCategoryToBodySlot(category: string?, metadataSlot: string?): Types.BodyPartSlot?
	if metadataSlot == "Head" or metadataSlot == "Arms" or metadataSlot == "Torso" or metadataSlot == "Legs" then
		return metadataSlot :: Types.BodyPartSlot
	end
	if category == "BodyHead" or category == "Head" then
		return "Head"
	elseif category == "BodyArms" or category == "Arms" then
		return "Arms"
	elseif category == "BodyTorso" or category == "Torso" then
		return "Torso"
	elseif category == "BodyLegs" or category == "Legs" then
		return "Legs"
	end
	return nil
end

local function extractBodyPartBonuses(itemId: string, itemData: SharedTypes.InventoryItem?): (Types.BodyPartSlot?, Types.BodyPartBonuses, string, string, string)
	local itemDef = Config.Items[itemId]
	local meta = (itemDef and itemDef.metadata) or (itemData and itemData.metadata) or {}
	local category = (itemData and itemData.category) or (itemDef and itemDef.category) or "Misc"
	local slot = mapCategoryToBodySlot(category, meta.bodySlot)

	local stats = meta.stats or meta
	local setId = tostring(meta.setId or "scrapper")
	local setDef = Config.BodySets[setId]
	local visual = meta.visual or (setDef and setDef.visualTheme) or {}

	local attackPower = tonumber(stats.attackPower or stats.damage) or 0
	local defense = tonumber(stats.defense) or 0
	local maxHealth = tonumber(stats.maxHealth) or 0
	local moveSpeed = tonumber(stats.moveSpeed) or 0
	local critChance = tonumber(stats.critChance) or 0
	local critMultiplier = tonumber(stats.critMultiplier) or 0
	local attackCooldownReduction = tonumber(stats.attackCooldownReduction or stats.attackSpeed) or 0

	local bonuses: Types.BodyPartBonuses = {
		attackPower = attackPower,
		defense = defense,
		maxHealth = maxHealth,
		moveSpeed = moveSpeed,
		critChance = critChance,
		critMultiplier = critMultiplier,
		attackCooldownReduction = attackCooldownReduction,
		setId = setId,
		setName = (setDef and setDef.displayName) or setId,
		visualStyle = tostring(visual.style or "ModularMech"),
		primaryColorHex = tostring(visual.primaryColor or "#7A6F64"),
		accentColorHex = tostring(visual.accentColor or "#E0A84A"),
	}

	local displayName = (itemDef and itemDef.displayName) or (meta.displayName and tostring(meta.displayName)) or itemId
	local rarity = tostring((itemData and itemData.rarity) or (itemDef and itemDef.rarity) or "Common")
	local description = (itemDef and itemDef.description) or "Модульная деталь экзо-корпуса."

	return slot, bonuses, displayName, rarity, description
end

local function formatDropPreview(lootTableId: string): string
	local tableDef = Config.SharedCombat.LootTables[lootTableId]
	if not tableDef or not tableDef.entries then
		return "Монеты, XP и детали тела"
	end
	local itemNames = {}
	for _, entry in ipairs(tableDef.entries) do
		if entry.kind == "Item" then
			local itemDef = Config.Items[entry.id]
			table.insert(itemNames, (itemDef and itemDef.displayName) or entry.id)
		end
	end
	if #itemNames > 0 then
		return "Дроп: монеты, XP, " .. table.concat(itemNames, ", ")
	end
	return "Дроп: монеты и опыт"
end

local function formatSkillBonusText(nodeDef: any): string
	local bonuses = nodeDef.bonuses or nodeDef.stats or {}
	local parts = {}
	if bonuses.attackPower then
		table.insert(parts, string.format("+%d к атаке", bonuses.attackPower))
	end
	if bonuses.attackPowerPct then
		table.insert(parts, string.format("+%d%% к атаке", math.floor(bonuses.attackPowerPct * 100 + 0.5)))
	end
	if bonuses.critChance then
		table.insert(parts, string.format("+%d%% крит. шанс", math.floor(bonuses.critChance * 100 + 0.5)))
	end
	if bonuses.critMultiplier then
		table.insert(parts, string.format("+%.2fx крит. урон", bonuses.critMultiplier))
	end
	if bonuses.maxHealth then
		table.insert(parts, string.format("+%d HP", bonuses.maxHealth))
	end
	if bonuses.maxHealthPct then
		table.insert(parts, string.format("+%d%% HP", math.floor(bonuses.maxHealthPct * 100 + 0.5)))
	end
	if bonuses.defense then
		table.insert(parts, string.format("+%d брони", bonuses.defense))
	end
	if bonuses.moveSpeed then
		table.insert(parts, string.format("+%d скорости", bonuses.moveSpeed))
	end
	if bonuses.attackCooldownReduction then
		table.insert(parts, string.format("-%.2fс перезарядки", bonuses.attackCooldownReduction))
	end
	if #parts == 0 then
		return nodeDef.description or "Пассивное усиление"
	end
	return table.concat(parts, " | ")
end

local function buildDeltaSummary(prev: Types.AssemblyStatsSummary, nextStats: Types.AssemblyStatsSummary): string?
	local diffs = {}
	local dAtk = nextStats.attackPower - prev.attackPower
	if math.abs(dAtk) >= 1 then
		table.insert(diffs, string.format("%s%d АТК", dAtk > 0 and "+" or "", math.floor(dAtk + 0.5)))
	end
	local dDef = nextStats.defense - prev.defense
	if math.abs(dDef) >= 1 then
		table.insert(diffs, string.format("%s%d Броня", dDef > 0 and "+" or "", math.floor(dDef + 0.5)))
	end
	local dHp = nextStats.maxHealth - prev.maxHealth
	if math.abs(dHp) >= 1 then
		table.insert(diffs, string.format("%s%d HP", dHp > 0 and "+" or "", math.floor(dHp + 0.5)))
	end
	local dSpd = nextStats.moveSpeed - prev.moveSpeed
	if math.abs(dSpd) >= 0.5 then
		table.insert(diffs, string.format("%s%.0f Скор.", dSpd > 0 and "+" or "", dSpd))
	end
	local dCrit = nextStats.critChancePct - prev.critChancePct
	if math.abs(dCrit) >= 1 then
		table.insert(diffs, string.format("%s%d%% Крит", dCrit > 0 and "+" or "", dCrit))
	end
	if prev.activeSetId ~= nextStats.activeSetId and nextStats.activeSetName then
		table.insert(diffs, string.format("Сет 4/4: %s!", nextStats.activeSetName))
	end
	if #diffs == 0 then
		return nil
	end
	return "Изменение сборки: " .. table.concat(diffs, ", ")
end

local function rebuildInventoryAndAssembly(self: any, recordDelta: boolean)
	local previousSummary = table.clone(self._assemblyStats)

	local equippedBySlot: { [string]: Types.BodyPartViewModel? } = {}
	local rawList: { Types.BodyPartViewModel } = {}
	local setCounts: { [string]: number } = {}
	local equippedCount = 0

	local sumAttack = 0
	local sumDefense = 0
	local sumMaxHp = 0
	local sumSpeed = 0
	local sumCritChance = 0
	local sumCritMult = 0
	local sumCdReduction = 0

	for uid, item in pairs(self._inventory) do
		local slot, bonuses, displayName, rarity, description = extractBodyPartBonuses(item.id, item)
		if slot then
			local vm: Types.BodyPartViewModel = {
				uid = item.uid or uid,
				itemId = item.id,
				displayName = displayName,
				slot = slot,
				category = item.category,
				rarity = rarity,
				level = item.level or 1,
				equipped = item.equipped == true,
				description = description,
				bonuses = bonuses,
				deltaAttackPower = 0,
				deltaDefense = 0,
				deltaMaxHealth = 0,
				deltaMoveSpeed = 0,
				deltaCritChance = 0,
				isPendingEquip = (self._pendingEquipUid == (item.uid or uid)),
			}
			table.insert(rawList, vm)

			if vm.equipped and not equippedBySlot[slot] then
				equippedBySlot[slot] = vm
				equippedCount += 1
				sumAttack += bonuses.attackPower
				sumDefense += bonuses.defense
				sumMaxHp += bonuses.maxHealth
				sumSpeed += bonuses.moveSpeed
				sumCritChance += bonuses.critChance
				sumCritMult += bonuses.critMultiplier
				sumCdReduction += bonuses.attackCooldownReduction
				setCounts[bonuses.setId] = (setCounts[bonuses.setId] or 0) + 1
			end
		end
	end

	-- Вычисляем дельту каждой детали относительно текущей экипированной детали в том же слоте
	for _, vm in ipairs(rawList) do
		local equippedInSlot = equippedBySlot[vm.slot]
		local eqBonuses = equippedInSlot and equippedInSlot.bonuses
		vm.deltaAttackPower = vm.bonuses.attackPower - (eqBonuses and eqBonuses.attackPower or 0)
		vm.deltaDefense = vm.bonuses.defense - (eqBonuses and eqBonuses.defense or 0)
		vm.deltaMaxHealth = vm.bonuses.maxHealth - (eqBonuses and eqBonuses.maxHealth or 0)
		vm.deltaMoveSpeed = vm.bonuses.moveSpeed - (eqBonuses and eqBonuses.moveSpeed or 0)
		vm.deltaCritChance = math.floor((vm.bonuses.critChance - (eqBonuses and eqBonuses.critChance or 0)) * 100 + 0.5)
	end

	table.sort(rawList, function(a, b)
		if a.slot ~= b.slot then
			return a.slot < b.slot
		end
		if a.equipped ~= b.equipped then
			return a.equipped
		end
		if a.bonuses.attackPower ~= b.bonuses.attackPower then
			return a.bonuses.attackPower > b.bonuses.attackPower
		end
		return a.displayName < b.displayName
	end)

	-- Проверяем активный бонус комплекта 4/4 (BodySetsConfig)
	local activeSetId: string? = nil
	local activeSetName: string? = nil
	local activeSetDescription: string? = nil
	local setAtkPct = 0
	local setHpPct = 0
	local setCritBonus = 0
	local setSpeedBonus = 0

	for setId, count in pairs(setCounts) do
		local setDef = Config.BodySets[setId]
		if setDef and count >= (setDef.requiredPieceCount or 4) then
			activeSetId = setId
			activeSetName = setDef.displayName
			activeSetDescription = setDef.description
			if setDef.fullSetBonus then
				setAtkPct = setDef.fullSetBonus.attackPowerPct or 0
				setHpPct = setDef.fullSetBonus.maxHealthPct or 0
				setCritBonus = setDef.fullSetBonus.critChance or 0
				setSpeedBonus = setDef.fullSetBonus.moveSpeed or 0
			end
			break
		end
	end

	-- Если сервер уже прислал StatsUpdated, используем серверные итоговые значения как авторитетные
	local base = Config.SharedCombat.BaseStats
	local perLevel = Config.SharedCombat.PerLevelStats
	local lvlOffset = math.max(0, self._playerLevel - 1)

	local calcAttack = math.floor(((base.attackPower + lvlOffset * perLevel.attackPower + sumAttack) * (1 + setAtkPct)) + 0.5)
	local calcDefense = base.defense + lvlOffset * perLevel.defense + sumDefense
	local calcMaxHp = math.floor(((base.maxHealth + lvlOffset * perLevel.maxHealth + sumMaxHp) * (1 + setHpPct)) + 0.5)
	local calcSpeed = base.moveSpeed + sumSpeed + setSpeedBonus
	local calcCritChance = math.min(Config.SharedCombat.MaxCritChance or 0.75, base.critChance + sumCritChance + setCritBonus)
	local calcCritMult = base.critMultiplier + sumCritMult
	local calcCooldown = math.max(Config.SharedCombat.MinAttackCooldown or 0.18, base.attackCooldown - sumCdReduction)

	local srv = self._serverStats
	if srv then
		-- Если сервер прислал StatsUpdated, берём максимум между серверным расчётом и расчётом по экипировке
		-- (на случай если сервер ещё считает старое поле damage вместо attackPower)
		local srvAtk = tonumber(srv.attackPower or srv.damage) or calcAttack
		local srvDef = tonumber(srv.defense) or calcDefense
		local srvHp = tonumber(srv.maxHealth) or calcMaxHp
		local srvSpd = tonumber(srv.moveSpeed) or calcSpeed
		local srvCrit = tonumber(srv.critChance) or calcCritChance
		local srvCritMult = tonumber(srv.critMultiplier) or calcCritMult
		local srvCd = tonumber(srv.attackCooldown) or calcCooldown

		calcAttack = math.max(srvAtk, calcAttack)
		calcDefense = math.max(srvDef, calcDefense)
		calcMaxHp = math.max(srvHp, calcMaxHp)
		calcSpeed = math.max(srvSpd, calcSpeed)
		calcCritChance = math.max(srvCrit, calcCritChance)
		calcCritMult = math.max(srvCritMult, calcCritMult)
		calcCooldown = math.min(srvCd, calcCooldown)
		if srv.activeSetId then
			activeSetId = srv.activeSetId
			local sDef = Config.BodySets[activeSetId]
			activeSetName = sDef and sDef.displayName or activeSetId
			activeSetDescription = sDef and sDef.description or activeSetDescription
		end
	end

	local defConst = Config.SharedCombat.DefenseConstant or 100
	local maxDr = Config.SharedCombat.MaxDamageReduction or 0.75
	local drRatio = math.min(maxDr, calcDefense / (calcDefense + defConst))

	local nextSummary: Types.AssemblyStatsSummary = {
		level = self._playerLevel,
		attackPower = calcAttack,
		defense = calcDefense,
		damageReductionPct = math.floor(drRatio * 100 + 0.5),
		maxHealth = calcMaxHp,
		moveSpeed = calcSpeed,
		critChancePct = math.floor(calcCritChance * 100 + 0.5),
		critMultiplier = calcCritMult,
		attackCooldown = calcCooldown,
		equippedCount = equippedCount,
		equippedBySlot = equippedBySlot,
		activeSetId = activeSetId,
		activeSetName = activeSetName,
		activeSetDescription = activeSetDescription,
		setCounts = setCounts,
		lastDeltaSummary = previousSummary.lastDeltaSummary,
	}

	if recordDelta then
		local deltaText = buildDeltaSummary(previousSummary, nextSummary)
		if deltaText then
			nextSummary.lastDeltaSummary = deltaText
		end
	end

	self._bodyParts = rawList
	self._assemblyStats = nextSummary
end

local function rebuildSkillViewModels(self: any)
	local spent = 0
	local unlockedCount = 0

	for skillId, isUnlocked in pairs(self._unlockedSkills) do
		if isUnlocked then
			local def = Config.SkillTree.Nodes[skillId]
			local cost = def and (def.cost or def.costPoints) or 1
			spent += cost
			unlockedCount += 1
		end
	end

	local earned = (Config.SkillTree.StartingPoints or 1)
		+ math.max(0, self._playerLevel - 1) * (Config.SkillTree.PointsPerLevel or 1)
	if self._skillSummary.earnedPoints > earned then
		earned = self._skillSummary.earnedPoints
	end
	local available = math.max(0, self._skillSummary.availablePoints)

	for skillId, def in pairs(Config.SkillTree.Nodes) do
		local existing = self._skillNodes[skillId]
		local isUnlocked = self._unlockedSkills[skillId] == true
		local costPoints = def.cost or (def :: any).costPoints or 1
		local requiredLevel = def.requiredLevel or 1
		local requires = def.requires or (def :: any).prerequisites or {}

		local meetsPrereqs = true
		for _, reqId in ipairs(requires) do
			if not self._unlockedSkills[reqId] then
				meetsPrereqs = false
				break
			end
		end

		local meetsLevel = self._playerLevel >= requiredLevel
		local hasEnoughPoints = available >= costPoints
		local canUnlock = (not isUnlocked) and meetsPrereqs and meetsLevel and hasEnoughPoints

		local status: Types.ActionAsyncStatus = (existing and existing.status == "Loading") and "Loading" or "Idle"
		local statusMsg: string? = existing and existing.statusMessage or nil

		if isUnlocked then
			status = "Success"
			statusMsg = "Изучено"
		elseif status ~= "Loading" then
			if not meetsPrereqs then
				statusMsg = "Требуется предыдущий навык ветки"
			elseif not meetsLevel then
				statusMsg = string.format("Требуется %d ур.", requiredLevel)
			elseif not hasEnoughPoints then
				statusMsg = string.format("Нужно очков: %d", costPoints)
			else
				statusMsg = "Доступно для изучения"
			end
		end

		self._skillNodes[skillId] = {
			id = skillId,
			branch = def.branch,
			tier = def.tier,
			displayName = def.displayName,
			description = def.description,
			bonusText = formatSkillBonusText(def),
			costPoints = costPoints,
			requiredLevel = requiredLevel,
			requires = requires,
			isUnlocked = isUnlocked,
			canUnlock = canUnlock,
			hasEnoughPoints = hasEnoughPoints,
			meetsLevel = meetsLevel,
			meetsPrereqs = meetsPrereqs,
			status = status,
			statusMessage = statusMsg,
		}
	end

	self._skillSummary = {
		availablePoints = available,
		spentPoints = spent,
		earnedPoints = math.max(earned, available + spent),
		unlockedCount = unlockedCount,
	}
end

-- ============================================================================
-- ОПОВЕЩЕНИЕ ПОДПИСЧИКОВ UI / МИРА
-- ============================================================================

local function notifyCombatListeners(self: any, feedback: Types.CombatHitFeedback?)
	local target = self._activeTargetMobUid and self._mobTargets[self._activeTargetMobUid] or nil
	for _, cb in ipairs(self._combatListeners) do
		task.spawn(cb, target, feedback)
	end
	if feedback then
		self.OnCombatHitFeedback:Fire(feedback)
		if feedback.defeated then
			self.OnMobDefeated:Fire(feedback)
		end
	end
	self.OnStateChanged:Fire()
end

local function notifyInventoryListeners(self: any)
	local parts = self:GetBodyPartsInventory()
	local summary = self:GetAssemblyStats()
	for _, cb in ipairs(self._inventoryListeners) do
		task.spawn(cb, parts, summary)
	end
	self.OnAssemblyUpdated:Fire(summary)
	self.OnStateChanged:Fire()
end

local function notifyChestListeners(self: any, changedChestId: string?)
	local list = self:GetChests()
	for _, cb in ipairs(self._chestListeners) do
		task.spawn(cb, list, changedChestId)
	end
	if changedChestId and self._chestStates[changedChestId] then
		self.OnChestResolved:Fire(self._chestStates[changedChestId])
	end
	self.OnStateChanged:Fire()
end

local function notifySkillListeners(self: any)
	local nodes = self:GetSkillTreeNodes()
	local summary = self:GetSkillTreeSummary()
	for _, cb in ipairs(self._skillListeners) do
		task.spawn(cb, nodes, summary)
	end
	self.OnStateChanged:Fire()
end

local function notifyArenaListeners(self: any)
	local state = self:GetArenaState()
	for _, cb in ipairs(self._arenaListeners) do
		task.spawn(cb, state)
	end
	self.OnArenaMatchResolved:Fire(state)
	self.OnStateChanged:Fire()
end

-- ============================================================================
-- ИНИЦИАЛИЗАЦИЯ ДАННЫХ ИЗ ОБЩИХ КОНФИГОВ И МИРА
-- ============================================================================

local function initStaticConfigs(self: any)
	-- Инициализируем витринные цели по каждому типу моба из CombatConfig.Mobs
	for mobId, def in pairs(Config.SharedCombat.Mobs) do
		self._mobTargets[mobId] = {
			mobUid = mobId,
			mobId = mobId,
			zoneId = def.zoneId,
			displayName = def.displayName,
			level = def.level,
			currentHp = def.maxHealth,
			maxHp = def.maxHealth,
			hpRatio = 1,
			defeated = false,
			lastHitDamage = nil,
			lastHitCrit = nil,
			lastRewardText = nil,
			lastErrorText = nil,
		}
		if not self._activeTargetMobUid and def.zoneId == "spawn_meadow" then
			self._activeTargetMobUid = mobId
		end
	end

	-- Инициализируем сундуки из CombatConfig.Chests
	for chestId, def in pairs(Config.SharedCombat.Chests) do
		local reqKills = def.requiredKillsSinceLastOpen or 0
		self._chestStates[chestId] = {
			id = chestId,
			zoneId = def.zoneId,
			displayName = def.displayName,
			minPlayerLevel = def.minPlayerLevel or 1,
			cooldownSeconds = def.cooldownSeconds or 60,
			requiredKills = reqKills,
			killsProgress = 0,
			readyAtUnix = 0,
			isReady = (reqKills == 0),
			description = string.format(
				"Требуется ур. %d и %d побед над мобами в зоне (%dс перезарядка).",
				def.minPlayerLevel or 1,
				reqKills,
				def.cooldownSeconds or 60
			),
			dropPreviewText = formatDropPreview(def.lootTableId),
			status = "Idle",
			statusMessage = reqKills > 0 and string.format("Побеждено мобов: 0/%d", reqKills) or "Готов к открытию",
			lastRewardText = nil,
			lastDropsCount = 0,
		}
	end

	rebuildSkillViewModels(self)
	rebuildInventoryAndAssembly(self, false)
end

-- Синхронизация живых инстансов мобов из Workspace.CombatWorld.Mobs
local function bindMobInstance(self: any, inst: Instance)
	local mobUid = inst:GetAttribute("MobUid") or inst.Name
	local mobId = inst:GetAttribute("MobId") or inst:GetAttribute("MobType") or mobUid
	local def = Config.SharedCombat.Mobs[tostring(mobId)]
	local displayName = tostring(inst:GetAttribute("DisplayName") or (def and def.displayName) or mobId)
	local zoneId = tostring(inst:GetAttribute("ZoneId") or (def and def.zoneId) or "spawn_meadow")
	local level = tonumber(inst:GetAttribute("Level")) or (def and def.level) or 1
	local maxHp = tonumber(inst:GetAttribute("MaxHealth")) or (def and def.maxHealth) or 100
	local curHp = tonumber(inst:GetAttribute("Health")) or maxHp
	local isAlive = inst:GetAttribute("Alive") ~= false and curHp > 0

	local vm: Types.MobTargetViewModel = self._mobTargets[tostring(mobUid)] or {
		mobUid = tostring(mobUid),
		mobId = tostring(mobId),
		zoneId = zoneId,
		displayName = displayName,
		level = level,
		currentHp = curHp,
		maxHp = maxHp,
		hpRatio = math.clamp(curHp / math.max(1, maxHp), 0, 1),
		defeated = not isAlive,
		lastHitDamage = nil,
		lastHitCrit = nil,
		lastRewardText = nil,
		lastErrorText = nil,
	}

	local function refreshFromAttributes()
		local mHp = tonumber(inst:GetAttribute("MaxHealth")) or vm.maxHp
		local cHp = tonumber(inst:GetAttribute("Health")) or vm.currentHp
		local aliveAttr = inst:GetAttribute("Alive")
		vm.maxHp = math.max(1, mHp)
		vm.currentHp = math.max(0, cHp)
		vm.hpRatio = math.clamp(vm.currentHp / vm.maxHp, 0, 1)
		vm.defeated = (aliveAttr == false) or (vm.currentHp <= 0)
		self._mobTargets[vm.mobUid] = vm
		-- Также обновляем запись по mobId для быстрого доступа
		self._mobTargets[vm.mobId] = vm
		if self._activeTargetMobUid == vm.mobUid or self._activeTargetMobUid == vm.mobId then
			notifyCombatListeners(self, nil)
		end
	end

	self._mobTargets[vm.mobUid] = vm
	self._mobTargets[vm.mobId] = vm
	if not self._activeTargetMobUid or self._activeTargetMobUid == vm.mobId then
		self._activeTargetMobUid = vm.mobUid
	end

	inst:GetAttributeChangedSignal("Health"):Connect(refreshFromAttributes)
	inst:GetAttributeChangedSignal("MaxHealth"):Connect(refreshFromAttributes)
	inst:GetAttributeChangedSignal("Alive"):Connect(refreshFromAttributes)
end

local function observeCombatWorldMobs(self: any)
	task.spawn(function()
		local combatWorld = Workspace:WaitForChild("CombatWorld", 10)
		if not combatWorld then
			return
		end
		local mobsFolder = combatWorld:WaitForChild("Mobs", 10)
		if not mobsFolder then
			return
		end
		for _, child in ipairs(mobsFolder:GetChildren()) do
			bindMobInstance(self, child)
		end
		mobsFolder.ChildAdded:Connect(function(child)
			bindMobInstance(self, child)
		end)
	end)
end

-- ============================================================================
-- ЖИЗНЕННЫЙ ЦИКЛ КОНТРОЛЛЕРА
-- ============================================================================

function CombatController:Init(registry: any?)
	if registry and type(registry) == "table" and type(registry.TryGet) == "function" then
		self._audioController = registry:TryGet("AudioController")
		self._animationController = registry:TryGet("AnimationController")
		self._uiController = registry:TryGet("UIController")
	end
	if self._initialized then
		return
	end
	self._initialized = true
	initStaticConfigs(self)
end

function CombatController:Shutdown()
	self._started = false
end

function CombatController:SetControllers(controllers: {
	audioController: any?,
	animationController: any?,
	uiController: any?,
})
	self._audioController = controllers.audioController
	self._animationController = controllers.animationController
	self._uiController = controllers.uiController
end

function CombatController:Start()
	if self._started then
		return
	end
	self._started = true

	observeCombatWorldMobs(self)

	-- 1. Загрузка профиля и базовых валют/уровня
	local profileLoadedEvent = Network.GetEvent("ProfileLoaded")
	if profileLoadedEvent then
		profileLoadedEvent.OnClientEvent:Connect(function(profile: any)
			if type(profile) ~= "table" then
				return
			end
			if profile.Progression and type(profile.Progression.Level) == "number" then
				self._playerLevel = profile.Progression.Level
				self._playerXp = profile.Progression.XP or 0
			end
			if profile.Currencies then
				self._coins = profile.Currencies.Coins or self._coins
				self._gems = profile.Currencies.Gems or self._gems
			end
			if type(profile.Inventory) == "table" then
				self._inventory = profile.Inventory
			end
			if type(profile.Skills) == "table" then
				if type(profile.Skills.Unlocked) == "table" then
					self._unlockedSkills = profile.Skills.Unlocked
				end
				if type(profile.Skills.AvailablePoints) == "number" then
					self._skillSummary.availablePoints = profile.Skills.AvailablePoints
				end
			end
			rebuildInventoryAndAssembly(self, false)
			rebuildSkillViewModels(self)
			notifyInventoryListeners(self)
			notifySkillListeners(self)
		end)
	end

	local currencyEvent = Network.GetEvent("CurrencyUpdated")
	if currencyEvent then
		currencyEvent.OnClientEvent:Connect(function(currencyType: string, newBalance: number)
			if currencyType == "Coins" then
				self._coins = newBalance
			elseif currencyType == "Gems" then
				self._gems = newBalance
			end
		end)
	end

	local levelUpEvent = Network.GetEvent("LevelUp")
	if levelUpEvent then
		levelUpEvent.OnClientEvent:Connect(function(newLevel: number, newXp: number)
			if type(newLevel) == "number" then
				self._playerLevel = newLevel
			end
			if type(newXp) == "number" then
				self._playerXp = newXp
			end
			rebuildInventoryAndAssembly(self, true)
			rebuildSkillViewModels(self)
			notifyInventoryListeners(self)
			notifySkillListeners(self)
		end)
	end

	-- 2. Инвентарь деталей тела и пересчёт характеристик (InventoryUpdated + StatsUpdated)
	local inventoryEvent = Network.GetEvent("InventoryUpdated")
	if inventoryEvent then
		inventoryEvent.OnClientEvent:Connect(function(inventory: { [string]: SharedTypes.InventoryItem })
			if type(inventory) ~= "table" then
				return
			end
			local hadPending = self._pendingEquipUid ~= nil
			self._pendingEquipUid = nil
			self._inventory = inventory
			rebuildInventoryAndAssembly(self, true)
			notifyInventoryListeners(self)

			if hadPending and self._assemblyStats.lastDeltaSummary and self._uiController then
				self._uiController:ShowNotification(self._assemblyStats.lastDeltaSummary, "Success")
			end
		end)
	end

	local statsUpdatedEvent = Network.GetEvent("StatsUpdated")
	if statsUpdatedEvent then
		statsUpdatedEvent.OnClientEvent:Connect(function(statsPayload: any)
			if type(statsPayload) ~= "table" then
				return
			end
			self._serverStats = statsPayload
			if type(statsPayload.level) == "number" then
				self._playerLevel = statsPayload.level
			end
			rebuildInventoryAndAssembly(self, true)
			notifyInventoryListeners(self)
		end)
	end

	-- 3. Обратная связь боя (CombatResult + MobDefeated)
	local combatResultEvent = Network.GetEvent("CombatResult")
	if combatResultEvent then
		combatResultEvent.OnClientEvent:Connect(function(payload: any)
			self:_handleCombatResult(payload)
		end)
	end

	local mobDefeatedEvent = Network.GetEvent("MobDefeated")
	if mobDefeatedEvent then
		mobDefeatedEvent.OnClientEvent:Connect(function(payload: any)
			self:_handleMobDefeated(payload)
		end)
	end

	-- 4. Сундуки (ChestStateSync + ChestResult)
	local chestSyncEvent = Network.GetEvent("ChestStateSync")
	if chestSyncEvent then
		chestSyncEvent.OnClientEvent:Connect(function(states: any)
			self:_handleChestStateSync(states)
		end)
	end

	local chestResultEvent = Network.GetEvent("ChestResult")
	if chestResultEvent then
		chestResultEvent.OnClientEvent:Connect(function(result: any)
			self:_handleChestResult(result)
		end)
	end

	-- 5. Дерево навыков (SkillTreeSync + SkillUnlockResult)
	local skillSyncEvent = Network.GetEvent("SkillTreeSync")
	if skillSyncEvent then
		skillSyncEvent.OnClientEvent:Connect(function(state: any)
			self:_handleSkillTreeSync(state)
		end)
	end

	local skillUnlockEvent = Network.GetEvent("SkillUnlockResult")
	if skillUnlockEvent then
		skillUnlockEvent.OnClientEvent:Connect(function(result: any)
			self:_handleSkillUnlockResult(result)
		end)
	end

	-- 6. Добровольная PvP-арена (ArenaStateChanged + PvPCombatResult)
	local arenaStateEvent = Network.GetEvent("ArenaStateChanged")
	if arenaStateEvent then
		arenaStateEvent.OnClientEvent:Connect(function(state: any)
			self:_handleArenaStateChanged(state)
		end)
	end

	local pvpCombatEvent = Network.GetEvent("PvPCombatResult")
	if pvpCombatEvent then
		pvpCombatEvent.OnClientEvent:Connect(function(result: any)
			self:_handlePvPCombatResult(result)
		end)
	end
end

-- ============================================================================
-- ОБРАБОТЧИКИ СЕРВЕРНЫХ ОТВЕТОВ (STRICTLY SERVER-AUTHORITATIVE)
-- ============================================================================

function CombatController:_handleStatsSyncForTest()
	rebuildInventoryAndAssembly(self, true)
	notifyInventoryListeners(self)
end

function CombatController:_handleCombatResult(payload: any)
	if type(payload) ~= "table" then
		return
	end
	local mobUid = tostring(payload.mobUid or self._activeTargetMobUid or "meadow_scrap_drone")
	local mobId = tostring(payload.mobId or mobUid)
	local target = self._mobTargets[mobUid] or self._mobTargets[mobId]
	if not target then
		local def = Config.SharedCombat.Mobs[mobId]
		target = {
			mobUid = mobUid,
			mobId = mobId,
			zoneId = def and def.zoneId or "spawn_meadow",
			displayName = def and def.displayName or mobId,
			level = def and def.level or 1,
			currentHp = def and def.maxHealth or 100,
			maxHp = def and def.maxHealth or 100,
			hpRatio = 1,
			defeated = false,
		}
	end

	local ok = payload.ok == true
	local dmg = tonumber(payload.damageDealt) or 0
	local isCrit = (payload.isCritical == true) or (payload.isCrit == true)
	local curHp = tonumber(payload.mobHealth or payload.mobRemainingHealth) or target.currentHp
	local maxHp = tonumber(payload.mobMaxHealth) or target.maxHp
	local defeated = (payload.killed == true) or (payload.defeated == true) or (ok and curHp <= 0)

	if ok then
		target.currentHp = math.max(0, curHp)
		target.maxHp = math.max(1, maxHp)
		target.hpRatio = math.clamp(target.currentHp / target.maxHp, 0, 1)
		target.defeated = defeated
		target.lastHitDamage = dmg
		target.lastHitCrit = isCrit
		target.lastErrorText = nil

		if self._audioController then
			self._audioController:PlaySound(isCrit and "UpgradeSuccess" or "CoinCollect")
		end
	else
		target.lastErrorText = tostring(payload.message or payload.errorCode or "Атака отклонена сервером")
		if self._uiController and payload.errorCode ~= "AttackCooldown" then
			self._uiController:ShowNotification(target.lastErrorText, "Warning")
		end
	end

	self._mobTargets[mobUid] = target
	self._mobTargets[mobId] = target
	self._activeTargetMobUid = mobUid

	local feedback: Types.CombatHitFeedback = {
		ok = ok,
		mobUid = mobUid,
		mobId = mobId,
		damageDealt = dmg,
		isCrit = isCrit,
		currentHp = target.currentHp,
		maxHp = target.maxHp,
		defeated = defeated,
		rewardText = target.lastRewardText,
		errorCode = payload.errorCode,
		message = payload.message,
	}

	notifyCombatListeners(self, feedback)
end

function CombatController:_handleMobDefeated(payload: any)
	if type(payload) ~= "table" then
		return
	end
	local mobUid = tostring(payload.mobUid or self._activeTargetMobUid or "")
	local mobId = tostring(payload.mobId or mobUid)
	local def = Config.SharedCombat.Mobs[mobId]
	local displayName = tostring(payload.displayName or (def and def.displayName) or mobId)

	local xp = tonumber(payload.xpGranted or payload.xpAwarded) or 0
	local coins = tonumber(payload.coinsGranted or payload.coinsAwarded) or 0
	local drops = payload.drops or payload.droppedItems or {}

	local dropNames = {}
	for _, drop in ipairs(drops) do
		if type(drop) == "string" then
			local itemDef = Config.Items[drop]
			table.insert(dropNames, (itemDef and itemDef.displayName) or drop)
		elseif type(drop) == "table" then
			if drop.kind == "Item" or drop.id then
				local itemDef = Config.Items[drop.id]
				table.insert(dropNames, tostring(drop.displayName or (itemDef and itemDef.displayName) or drop.id))
			end
		end
	end

	local rewardParts = {}
	if coins > 0 then
		table.insert(rewardParts, string.format("+%d монет", coins))
	end
	if xp > 0 then
		table.insert(rewardParts, string.format("+%d XP", xp))
	end
	if #dropNames > 0 then
		table.insert(rewardParts, "Деталь: " .. table.concat(dropNames, ", "))
	end
	local rewardText = #rewardParts > 0 and table.concat(rewardParts, " | ") or "Победа!"

	local target = self._mobTargets[mobUid] or self._mobTargets[mobId]
	if target then
		target.currentHp = 0
		target.hpRatio = 0
		target.defeated = true
		target.lastRewardText = rewardText
	end

	if self._audioController then
		self._audioController:PlaySound("StageUnlocked")
	end
	if self._uiController then
		self._uiController:ShowNotification(
			string.format("%s повержен! %s", displayName, rewardText),
			"Success"
		)
	end

	notifyCombatListeners(self, {
		ok = true,
		mobUid = mobUid,
		mobId = mobId,
		damageDealt = target and (target.lastHitDamage or 0) or 0,
		isCrit = target and (target.lastHitCrit == true) or false,
		currentHp = 0,
		maxHp = target and target.maxHp or 100,
		defeated = true,
		rewardText = rewardText,
	})
end

function CombatController:_handleChestStateSync(states: any)
	if type(states) ~= "table" then
		return
	end
	-- Поддерживаем и словарь { [chestId] = state }, и одиночный state
	local entries = states.chestId and { [states.chestId] = states } or states
	for chestId, st in pairs(entries) do
		local vm = self._chestStates[chestId]
		if vm and type(st) == "table" then
			local killsProgress = tonumber(st.killsSinceLastOpen or st.killsProgress) or vm.killsProgress
			local reqKills = tonumber(st.requiredKills or st.killsRequired) or vm.requiredKills
			local readyAtUnix = tonumber(st.readyAtUnix or st.nextAvailableAt) or 0
			local now = os.time()
			local isReady = st.isReady
			if isReady == nil then
				isReady = st.canOpen
			end
			if isReady == nil then
				isReady = (killsProgress >= reqKills) and (now >= readyAtUnix)
			end

			vm.killsProgress = killsProgress
			vm.requiredKills = reqKills
			vm.readyAtUnix = readyAtUnix
			vm.isReady = isReady == true
			if vm.status == "Loading" then
				vm.status = "Idle"
			end
			if vm.isReady then
				vm.statusMessage = "Готов к открытию!"
			elseif killsProgress < reqKills then
				vm.statusMessage = string.format("Побеждено мобов: %d/%d", killsProgress, reqKills)
			else
				local rem = math.max(0, readyAtUnix - now)
				vm.statusMessage = string.format("Перезарядка: %dс", rem)
			end
		end
	end
	notifyChestListeners(self, nil)
end

function CombatController:_handleChestResult(result: any)
	if type(result) ~= "table" then
		return
	end
	local chestId = tostring(result.chestId or "")
	local vm = self._chestStates[chestId]
	if not vm then
		return
	end

	if result.state then
		self:_handleChestStateSync({ [chestId] = result.state })
	end

	if result.ok then
		local drops = result.drops or {}
		local parts = {}
		local coins = tonumber(result.coinsAwarded) or 0
		local xp = tonumber(result.xpAwarded) or 0
		if coins > 0 then
			table.insert(parts, string.format("+%d монет", coins))
		end
		if xp > 0 then
			table.insert(parts, string.format("+%d XP", xp))
		end
		for _, drop in ipairs(drops) do
			if type(drop) == "table" then
				if drop.kind == "Currency" then
					table.insert(parts, string.format("+%d %s", drop.amount or 0, drop.displayName or drop.id))
				elseif drop.kind == "XP" then
					table.insert(parts, string.format("+%d XP", drop.amount or 0))
				else
					local itemDef = Config.Items[drop.id]
					table.insert(parts, tostring(drop.displayName or (itemDef and itemDef.displayName) or drop.id))
				end
			elseif type(drop) == "string" then
				local itemDef = Config.Items[drop]
				table.insert(parts, (itemDef and itemDef.displayName) or drop)
			end
		end

		local rewardSummary = #parts > 0 and table.concat(parts, ", ") or tostring(result.message or "Награда получена!")
		vm.status = "Success"
		vm.lastRewardText = rewardSummary
		vm.lastDropsCount = #drops
		vm.statusMessage = "Открыт! " .. rewardSummary

		if self._audioController then
			self._audioController:PlaySound("PurchaseSuccess")
		end
		if self._uiController then
			self._uiController:ShowNotification(
				string.format("%s: %s", vm.displayName, rewardSummary),
				"Success"
			)
		end
	else
		vm.status = "Error"
		vm.statusMessage = tostring(result.message or result.errorCode or "Не удалось открыть сундук")
		if self._audioController then
			self._audioController:PlaySound("Error")
		end
		if self._uiController then
			self._uiController:ShowNotification(vm.statusMessage, "Warning")
		end
	end

	notifyChestListeners(self, chestId)
end

function CombatController:_handleSkillTreeSync(state: any)
	if type(state) ~= "table" then
		return
	end
	local unlockedMap = state.unlocked or state.unlockedSkills
	if type(unlockedMap) == "table" then
		self._unlockedSkills = unlockedMap
	end
	if type(state.availablePoints) == "number" then
		self._skillSummary.availablePoints = state.availablePoints
	end
	if type(state.spentPoints) == "number" then
		self._skillSummary.spentPoints = state.spentPoints
	end
	if type(state.earnedPoints) == "number" then
		self._skillSummary.earnedPoints = state.earnedPoints
	end
	rebuildSkillViewModels(self)
	notifySkillListeners(self)
end

function CombatController:_handleSkillUnlockResult(result: any)
	if type(result) ~= "table" then
		return
	end
	local skillId = tostring(result.skillId or "")
	if result.state then
		self:_handleSkillTreeSync(result.state)
	end
	if type(result.availablePoints) == "number" then
		self._skillSummary.availablePoints = result.availablePoints
	end

	if result.ok and skillId ~= "" then
		self._unlockedSkills[skillId] = true
		rebuildSkillViewModels(self)
		local vm = self._skillNodes[skillId]
		if vm then
			vm.status = "Success"
			vm.statusMessage = "Изучено!"
		end
		if self._audioController then
			self._audioController:PlaySound("UpgradeSuccess")
		end
		if self._uiController then
			self._uiController:ShowNotification(
				string.format("Навык изучен: %s", vm and vm.displayName or skillId),
				"Success"
			)
		end
	else
		rebuildSkillViewModels(self)
		local vm = self._skillNodes[skillId]
		local errText = tostring(result.message or result.errorCode or "Не удалось изучить навык")
		if vm then
			vm.status = "Error"
			vm.statusMessage = errText
		end
		if self._audioController then
			self._audioController:PlaySound("Error")
		end
		if self._uiController then
			self._uiController:ShowNotification(errText, "Warning")
		end
	end

	notifySkillListeners(self)
end

function CombatController:_handleArenaStateChanged(state: any)
	if type(state) ~= "table" then
		return
	end
	local inArena = state.inArena == true
	local combatTagRemaining = tonumber(state.combatTagRemaining) or 0
	if state.combatTagExpiresAt and type(state.combatTagExpiresAt) == "number" then
		combatTagRemaining = math.max(combatTagRemaining, math.max(0, state.combatTagExpiresAt - os.time()))
	end

	self._arenaState.zoneState = inArena and "InArena" or "SafeZone"
	self._arenaState.isSafeZone = not inArena
	self._arenaState.combatTaggedSeconds = combatTagRemaining
	self._arenaState.pvpKills = tonumber(state.pvpKills) or self._arenaState.pvpKills
	self._arenaState.pvpDeaths = tonumber(state.pvpDeaths) or self._arenaState.pvpDeaths
	self._arenaState.statusText = tostring(
		state.message
			or (inArena and "ВЫ В ЗОНЕ PVP-АРЕНЫ (активен дуэльный баланс)" or "Безопасная зона (PvE)")
	)

	if self._uiController then
		self._uiController:ShowNotification(
			self._arenaState.statusText,
			inArena and "Warning" or "Info"
		)
	end

	notifyArenaListeners(self)
end

function CombatController:_handlePvPCombatResult(result: any)
	if type(result) ~= "table" then
		return
	end
	local localUserId = Players.LocalPlayer and Players.LocalPlayer.UserId or 0
	if result.ok then
		local dmg = tonumber(result.damageDealt) or 0
		local ko = (result.knockout == true) or (result.eliminated == true)
		local isAttacker = (result.attackerUserId == localUserId) or (result.attackerUserId == nil)

		if ko then
			self._arenaState.lastMatchOutcome = isAttacker and "Victory" or "Defeat"
			if isAttacker then
				self._arenaState.pvpKills += 1
			else
				self._arenaState.pvpDeaths += 1
			end
		else
			self._arenaState.lastMatchOutcome = "Hit"
		end

		self._arenaState.lastMatchMessage = tostring(
			result.message
				or string.format(
					"%s: %d урона (HP цели: %d/%d)",
					ko and "Нокаут на арене" or "Попадание в PvP",
					dmg,
					tonumber(result.targetHealth or result.targetRemainingHealth) or 0,
					tonumber(result.targetMaxHealth) or 100
				)
		)
	else
		self._arenaState.lastMatchMessage = tostring(result.message or result.errorCode or "PvP-действие отклонено")
	end

	notifyArenaListeners(self)
end

-- ============================================================================
-- ПУБЛИЧНЫЕ ДЕЙСТВИЯ КЛИЕНТА (CLIENT -> SERVER CONTRACT CALLS)
-- ============================================================================

function CombatController:SelectTargetMob(mobUid: string)
	if self._mobTargets[mobUid] then
		self._activeTargetMobUid = mobUid
		notifyCombatListeners(self, nil)
	end
end

function CombatController:RequestAttackMob(mobUid: string?): boolean
	local now = os.clock()
	if now - self._lastAttackAt < Config.AttackInputCooldownSec then
		return false
	end
	self._lastAttackAt = now

	local targetUid = mobUid or self._activeTargetMobUid or "meadow_scrap_drone"
	-- Если передан шаблонный id (например, "meadow_scrap_drone"), а в мире есть живой инстанс "meadow_scrap_drone_1",
	-- выбираем живой инстанс из Workspace.CombatWorld.Mobs
	local combatWorld = Workspace:FindFirstChild("CombatWorld")
	local mobsFolder = combatWorld and combatWorld:FindFirstChild("Mobs")
	if mobsFolder and not mobsFolder:FindFirstChild(targetUid) then
		for _, child in ipairs(mobsFolder:GetChildren()) do
			local childMobId = child:GetAttribute("MobId") or child:GetAttribute("MobType")
			local childAlive = child:GetAttribute("Alive") ~= false
			if tostring(childMobId) == targetUid and childAlive then
				targetUid = tostring(child:GetAttribute("MobUid") or child.Name)
				break
			end
		end
	end

	self._activeTargetMobUid = targetUid

	if self._animationController then
		self._animationController:PlayActionAnimation("SwingTool")
	end

	local ev = Network.GetEvent("RequestAttackMob")
	if ev then
		ev:FireServer(targetUid)
	end
	return true
end

function CombatController:RequestEquipBodyPart(itemUid: string, equip: boolean?): boolean
	if type(itemUid) ~= "string" or itemUid == "" then
		return false
	end
	local shouldEquip = if equip == nil then true else equip
	self._pendingEquipUid = itemUid

	for _, part in ipairs(self._bodyParts) do
		part.isPendingEquip = (part.uid == itemUid)
	end
	notifyInventoryListeners(self)

	local ev = Network.GetEvent("RequestEquipItem")
	if ev then
		ev:FireServer(itemUid, shouldEquip)
	end
	return true
end

function CombatController:RequestOpenChest(chestId: string): boolean
	local vm = self._chestStates[chestId]
	if not vm then
		return false
	end
	if vm.status == "Loading" then
		return false
	end

	vm.status = "Loading"
	vm.statusMessage = "Запрос открытия на сервере..."
	notifyChestListeners(self, chestId)

	local ev = Network.GetEvent("RequestOpenChest")
	if ev then
		ev:FireServer(chestId)
	end
	return true
end

function CombatController:RequestUnlockSkill(skillId: string): boolean
	local vm = self._skillNodes[skillId]
	if not vm then
		return false
	end
	if vm.isUnlocked or vm.status == "Loading" then
		return false
	end

	vm.status = "Loading"
	vm.statusMessage = "Отправка запроса серверу..."
	notifySkillListeners(self)

	local ev = Network.GetEvent("RequestUnlockSkill")
	if ev then
		ev:FireServer(skillId)
	end
	return true
end

function CombatController:RequestEnterArena(): boolean
	self._arenaState.zoneState = "Entering"
	self._arenaState.statusText = "Запрос входа на PvP-арену..."
	notifyArenaListeners(self)

	local ev = Network.GetEvent("RequestArenaEnter")
	if ev then
		ev:FireServer()
	end
	return true
end

function CombatController:RequestLeaveArena(): boolean
	self._arenaState.zoneState = "Leaving"
	self._arenaState.statusText = "Запрос выхода в безопасную зону..."
	notifyArenaListeners(self)

	local ev = Network.GetEvent("RequestArenaLeave")
	if ev then
		ev:FireServer()
	end
	return true
end

function CombatController:RequestPvPAttack(targetUserId: number): boolean
	local ev = Network.GetEvent("RequestPvPAttack")
	if ev then
		ev:FireServer(targetUserId)
		return true
	end
	return false
end

-- ============================================================================
-- ПУБЛИЧНЫЕ ГЕТТЕРЫ И ПОДПИСКИ ДЛЯ UI / WORLD
-- ============================================================================

function CombatController:GetActiveMobTarget(): Types.MobTargetViewModel?
	if self._activeTargetMobUid and self._mobTargets[self._activeTargetMobUid] then
		return table.clone(self._mobTargets[self._activeTargetMobUid])
	end
	return nil
end

function CombatController:GetAllMobTargets(): { Types.MobTargetViewModel }
	local seen = {}
	local list = {}
	for _, vm in pairs(self._mobTargets) do
		if not seen[vm.mobId] then
			seen[vm.mobId] = true
			table.insert(list, table.clone(vm))
		end
	end
	table.sort(list, function(a, b)
		return a.level < b.level
	end)
	return list
end

function CombatController:GetBodyPartsInventory(slotFilter: Types.BodyPartSlot?): { Types.BodyPartViewModel }
	local result = {}
	for _, vm in ipairs(self._bodyParts) do
		if not slotFilter or vm.slot == slotFilter then
			table.insert(result, table.clone(vm))
		end
	end
	return result
end

function CombatController:GetAssemblyStats(): Types.AssemblyStatsSummary
	return table.clone(self._assemblyStats)
end

function CombatController:GetChests(): { Types.ChestDefViewModel }
	local list = {}
	for _, vm in pairs(self._chestStates) do
		table.insert(list, table.clone(vm))
	end
	table.sort(list, function(a, b)
		return a.minPlayerLevel < b.minPlayerLevel
	end)
	return list
end

function CombatController:GetSkillTreeNodes(branchFilter: Types.SkillBranch?): { Types.SkillNodeViewModel }
	local list = {}
	for _, vm in pairs(self._skillNodes) do
		if not branchFilter or vm.branch == branchFilter then
			table.insert(list, table.clone(vm))
		end
	end
	table.sort(list, function(a, b)
		if a.branch ~= b.branch then
			return a.branch < b.branch
		end
		return a.tier < b.tier
	end)
	return list
end

function CombatController:GetSkillTreeSummary(): Types.SkillTreeSummaryViewModel
	return table.clone(self._skillSummary)
end

function CombatController:GetArenaState(): Types.ArenaStateViewModel
	return table.clone(self._arenaState)
end

function CombatController:OnCombatFeedback(callback: (Types.MobTargetViewModel?, Types.CombatHitFeedback?) -> ())
	table.insert(self._combatListeners, callback)
	task.spawn(callback, self:GetActiveMobTarget(), nil)
end

function CombatController:OnInventoryAssemblyChanged(callback: ({ Types.BodyPartViewModel }, Types.AssemblyStatsSummary) -> ())
	table.insert(self._inventoryListeners, callback)
	task.spawn(callback, self:GetBodyPartsInventory(), self:GetAssemblyStats())
end

function CombatController:OnChestsChanged(callback: ({ Types.ChestDefViewModel }, string?) -> ())
	table.insert(self._chestListeners, callback)
	task.spawn(callback, self:GetChests(), nil)
end

function CombatController:OnSkillTreeChanged(callback: ({ Types.SkillNodeViewModel }, Types.SkillTreeSummaryViewModel) -> ())
	table.insert(self._skillListeners, callback)
	task.spawn(callback, self:GetSkillTreeNodes(), self:GetSkillTreeSummary())
end

function CombatController:OnArenaStateChanged(callback: (Types.ArenaStateViewModel) -> ())
	table.insert(self._arenaListeners, callback)
	task.spawn(callback, self:GetArenaState())
end

-- Алиасы для совместимости с UIController / WorldController
function CombatController:GetAssemblySummary(): Types.AssemblyStatsSummary
	return self:GetAssemblyStats()
end

function CombatController:GetBodyPartsBySlot(slotFilter: string?): { Types.BodyPartViewModel }
	if not slotFilter or slotFilter == "All" then
		return self:GetBodyPartsInventory(nil)
	end
	return self:GetBodyPartsInventory(slotFilter :: Types.BodyPartSlot)
end

function CombatController:GetZoneMobs(): { Types.MobTargetViewModel }
	return self:GetAllMobTargets()
end

function CombatController:GetZoneChests(): { Types.ChestDefViewModel }
	return self:GetChests()
end

function CombatController:SelectMobTarget(mobUid: string)
	self:SelectTargetMob(mobUid)
end

return CombatController
