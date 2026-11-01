--!strict
--[[
	@module AudioController
	@owner Agent 2 (anarugod)
	@description Управление звуковыми эффектами (SFX) и фоновой музыкой (BGM) на клиенте.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Logger = require(Shared:WaitForChild("Core"):WaitForChild("Logger"))
local Signal = require(Shared:WaitForChild("Core"):WaitForChild("Signal"))

local AudioController = {
	Name = "AudioController",
	Dependencies = {} :: { string },
	OnMuteChanged = Signal.new(),
}

local log = Logger.new("AudioController")
local isMuted = false
local activeMusicTrack: string? = nil

local SOUND_PRESETS: { [string]: { SoundId: string, Volume: number } } = {
	Click = { SoundId = "rbxassetid://9119713951", Volume = 0.45 },
	UIButton = { SoundId = "rbxassetid://6895079853", Volume = 0.35 },
	Purchase = { SoundId = "rbxassetid://9118823108", Volume = 0.6 },
	Error = { SoundId = "rbxassetid://9114221580", Volume = 0.5 },
	LevelUp = { SoundId = "rbxassetid://9118828562", Volume = 0.65 },
	ZoneUnlock = { SoundId = "rbxassetid://9118828562", Volume = 0.7 },
}

function AudioController:Init(_registry: any): ()
	log:Info("Initialized AudioController")
end

function AudioController:Start(): ()
	log:Info("Started AudioController")
end

function AudioController:PlaySFX(soundName: string, pitchVariance: number?): ()
	if isMuted then
		return
	end

	local preset = SOUND_PRESETS[soundName]
	local sound = Instance.new("Sound")
	sound.Name = "SFX_" .. soundName
	sound.SoundId = if preset then preset.SoundId else "rbxassetid://6895079853"
	sound.Volume = if preset then preset.Volume else 0.4

	if pitchVariance and pitchVariance > 0 then
		local offset = (math.random() * 2 - 1) * pitchVariance
		sound.PlaybackSpeed = math.clamp(1 + offset, 0.5, 2.0)
	end

	sound.Parent = SoundService
	sound:Play()
	sound.Ended:Once(function()
		sound:Destroy()
	end)
end

function AudioController:PlayMusic(trackName: string): ()
	activeMusicTrack = trackName
	if isMuted then
		return
	end
	log:Debug("Playing music track: %s", trackName)
end

function AudioController:SetMuted(muted: boolean): ()
	if isMuted == muted then
		return
	end
	isMuted = muted
	self.OnMuteChanged:Fire(isMuted)
	log:Info("Audio muted state set to: %s", tostring(isMuted))
end

function AudioController:IsMuted(): boolean
	return isMuted
end

function AudioController:GetActiveMusicTrack(): string?
	return activeMusicTrack
end

function AudioController:Shutdown(): ()
	activeMusicTrack = nil
	log:Info("Shutdown AudioController")
end

return AudioController
