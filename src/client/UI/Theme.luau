--!strict
--[[
	@module Theme
	@owner Agent 2 (anarugod)
	@description Единая дизайн-система и цветовая палитра для клиентского UI симулятора.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Types = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Core"):WaitForChild("Types"))

local Theme = {
	Colors = {
		Background = Color3.fromRGB(22, 24, 34),
		Surface = Color3.fromRGB(32, 36, 50),
		SurfaceLight = Color3.fromRGB(45, 50, 70),
		Primary = Color3.fromRGB(72, 138, 255),
		Accent = Color3.fromRGB(255, 196, 46),
		Coins = Color3.fromRGB(255, 208, 64),
		Gems = Color3.fromRGB(88, 214, 255),
		Rebirth = Color3.fromRGB(235, 84, 255),
		Success = Color3.fromRGB(68, 214, 116),
		Warning = Color3.fromRGB(255, 180, 54),
		Error = Color3.fromRGB(255, 82, 82),
		TextPrimary = Color3.fromRGB(245, 247, 255),
		TextSecondary = Color3.fromRGB(168, 176, 204),
	},

	RarityColors = {
		Common = Color3.fromRGB(180, 186, 198),
		Uncommon = Color3.fromRGB(88, 214, 122),
		Rare = Color3.fromRGB(72, 156, 255),
		Epic = Color3.fromRGB(186, 92, 255),
		Legendary = Color3.fromRGB(255, 192, 48),
		Mythic = Color3.fromRGB(255, 68, 112),
	} :: { [Types.Rarity]: Color3 },

	Fonts = {
		Heading = Enum.Font.GothamBold,
		Body = Enum.Font.GothamMedium,
		Mono = Enum.Font.RobotoMono,
	},

	CornerRadius = {
		Small = UDim.new(0, 6),
		Medium = UDim.new(0, 10),
		Large = UDim.new(0, 14),
		Pill = UDim.new(1, 0),
	},
}

return table.freeze(Theme)
