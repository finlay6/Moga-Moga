local OnyxUI = require(game.ReplicatedStorage.Shared.Packages.OnyxUI)
local Fusion = require(game.ReplicatedStorage.Shared.Packages.Fusion)
local TextComponent = require(game.ReplicatedStorage.Shared.UI.Components.TextComponent)

local Scoped = Fusion.scoped
local Children = Fusion.Children

local scope = Scoped()

export type TextButtonProps = OnyxUI.ButtonProps & {
	Text: Fusion.UsedAs<string>?,
}

local function Frame(Scope: Fusion.Scope<any>, Props: TextButtonProps)
	local PlayerName
	
	local function _onFocusEnd()
		local text = PlayerName.Text
		
		Props.OnFocusEnd(text)
	end
	
	PlayerName = TextComponent(Scope, {
		Position = UDim2.fromScale(0.5, 0.5),
		OnFocusEnd = _onFocusEnd,
	})
	
	return Scope:New "Frame" {
		Name = "MainFrame",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		[Children] = {
			PlayerName
		},
	}
end

return function(scope: Fusion.Scope<any>, Props)
	local Scope = Fusion.innerScope(scope, Fusion, OnyxUI.Util, OnyxUI.Components)
	local Theme = OnyxUI.Themer.Theme:now()
	
	local Frame = Frame(scope, {
		OnFocusEnd = Props.OnFocusEnd,
	})
	
	return Scope:New "ScreenGui" {
		Name = "NametagChanger",
		Parent = Props.Parent,

		[Children] = {
			Frame
		},
	}
end