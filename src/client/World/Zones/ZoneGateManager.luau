--!strict
--[[
	@module ZoneGateManager
	@owner Agent 2 (anarugod)
	@description Управление визуальными барьерами локаций и ProximityPrompt-триггерами открытия зон на клиенте.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ZonesConfig = require(Shared:WaitForChild("Config"):WaitForChild("ZonesConfig"))

local ZoneGateManager = {}

local gateInstances: { [string]: BasePart } = {}

function ZoneGateManager.EnsureGatesFolder(): Folder
	local existing = Workspace:FindFirstChild("SimulatorZones")
	if existing and existing:IsA("Folder") then
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = "SimulatorZones"
	folder.Parent = Workspace
	return folder
end

function ZoneGateManager.SyncGates(unlockedZones: { [string]: boolean }, onUnlockRequested: (zoneId: string) -> ()): ()
	local folder = ZoneGateManager.EnsureGatesFolder()

	for zoneId, zoneDef in pairs(ZonesConfig) do
		local isUnlocked = unlockedZones[zoneId] == true or zoneDef.costAmount == 0
		local gatePart = gateInstances[zoneId]

		if not gatePart then
			local existing = folder:FindFirstChild("Gate_" .. zoneId)
			if existing and existing:IsA("BasePart") then
				gatePart = existing
				gateInstances[zoneId] = existing
			elseif zoneDef.order > 1 then
				local newGate = Instance.new("Part")
				newGate.Name = "Gate_" .. zoneId
				newGate.Anchored = true
				newGate.Size = Vector3.new(24, 14, 2)
				newGate.Position = Vector3.new(0, 7, -45 * (zoneDef.order - 1))
				newGate.Material = Enum.Material.ForceField
				newGate.Color = Color3.fromRGB(255, 92, 92)
				newGate.Parent = folder

				local prompt = Instance.new("ProximityPrompt")
				prompt.Name = "UnlockPrompt"
				prompt.ActionText = "Unlock " .. zoneDef.displayName
				prompt.ObjectText = string.format("%d %s", zoneDef.costAmount, zoneDef.costCurrency)
				prompt.HoldDuration = 0.25
				prompt.MaxActivationDistance = 14
				prompt.Parent = newGate

				prompt.Triggered:Connect(function()
					onUnlockRequested(zoneId)
				end)

				gatePart = newGate
				gateInstances[zoneId] = newGate
			end
		end

		if gatePart then
			gatePart.CanCollide = not isUnlocked
			gatePart.Transparency = if isUnlocked then 0.85 else 0.25
			gatePart.Color = if isUnlocked then Color3.fromRGB(88, 214, 122) else Color3.fromRGB(255, 92, 92)
			local prompt = gatePart:FindFirstChild("UnlockPrompt")
			if prompt and prompt:IsA("ProximityPrompt") then
				prompt.Enabled = not isUnlocked
			end
		end
	end
end

function ZoneGateManager.Cleanup(): ()
	table.clear(gateInstances)
end

return ZoneGateManager
