local OnyxUI = require(game.ReplicatedStorage.Shared.Packages.OnyxUI)
local Fusion = require(game.ReplicatedStorage.Shared.Packages.Fusion)

local Children = Fusion.Children

export type TextButtonProps = OnyxUI.ButtonProps & {
	Text: Fusion.UsedAs<string>?,
}

return function(Scope: Fusion.Scope<any>, Props: TextButtonProps)
	local Scope = Fusion.innerScope(Scope, Fusion, OnyxUI.Util, OnyxUI.Components)
	local Theme = OnyxUI.Themer.Theme:now()

	return Scope:Image(OnyxUI.Util.CombineProps(Props, {
		Name = Props.Name,
		AutomaticSize = Enum.AutomaticSize.None,
		Size = UDim2.fromScale(0.3, 0.7),
		Position = Props.Position,
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Image = Props.ImageId
	}))
end