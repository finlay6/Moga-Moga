local Fusion = require(game.ReplicatedStorage.Shared.Packages.Fusion)
local OnyxUI = require(game.ReplicatedStorage.Shared.Packages.OnyxUI)
local Children = Fusion.Children
local Out = Fusion.Out
local OnEvent = Fusion.OnEvent
local peek = Fusion.peek

type UsedAs<T> = Fusion.UsedAs<T>

export type NametagFormProps = {
	OnSubmit: (displayName: string, country: string) -> (),
}

local function getFrame(Scope: Fusion.Scope<any>, Props: NametagFormProps)
	local Scope = Fusion.innerScope(Scope, Fusion, OnyxUI.Util, OnyxUI.Components)

	-- These are the source of truth for the input values.
	-- Nothing reads .Text off an instance — everything reads these.
	local displayName = Scope:Value("")
	local country     = Scope:Value("")

	return Scope:New "Frame" {
		Name              = "NametagForm",
		AnchorPoint       = Vector2.new(0.5, 0.5),
		Position          = UDim2.fromScale(0.5, 0.5),
		Size              = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,

		[Children] = {
			Scope:New "TextBox" {
				PlaceholderText = "Enter display name",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position        = UDim2.fromScale(0.4, 0.8),
				Size     = UDim2.fromOffset(150, 60),
				TextScaled = true,
				Text = displayName,
				[Out "Text"] = displayName,
			},

			Scope:New "TextBox" {
				PlaceholderText = "Enter country",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position        = UDim2.fromScale(0.5, 0.8),
				Size     = UDim2.fromOffset(150, 60),
				TextScaled = true,
				Text            = country,
				[Out "Text"] = country,
			},

			Scope:New "TextButton" {
				Text     = "Save",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.6, 0.8),
				Size     = UDim2.fromOffset(150, 60),
				TextScaled = true,

				[OnEvent "Activated"] = function()
					Props.OnSubmit(peek(displayName), peek(country))
				end,
			},
		},
	}
end

return function(Scope: Fusion.Scope<any>, Props)
	local Theme = OnyxUI.Themer.Theme:now()
	
	local Frame = getFrame(Scope, {
		OnSubmit = Props.OnSubmit,
	})
	
	return Scope:New "ScreenGui" {
		Name = "NametagChanger",
		Parent = Props.Parent,

		[Children] = {
			Frame
		},
	}
end