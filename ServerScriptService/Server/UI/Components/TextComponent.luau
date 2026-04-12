local OnyxUI = require(game.ReplicatedStorage.Shared.Packages.OnyxUI)
local Fusion = require(game.ReplicatedStorage.Shared.Packages.Fusion)

local Children = Fusion.Children

export type TextButtonProps = OnyxUI.ButtonProps & {
	Text: Fusion.UsedAs<string>?,
}

return function(Scope: Fusion.Scope<any>, Props: TextButtonProps)
	local Scope = Fusion.innerScope(Scope, Fusion, OnyxUI.Util, OnyxUI.Components)
	local Theme = OnyxUI.Themer.Theme:now()

	return Scope:Text(OnyxUI.Util.CombineProps(Props, {
		Name = Props.Name,
		TextScaled = true,
		TextColor3 = Color3.fromRGB(255, 255, 255),
		TextXAlignment = "Center",
		TextYAlignment = "Center",
		AutomaticSize = Enum.AutomaticSize.None,
		FontFace = Font.fromName("Nunito"),
		Size = UDim2.fromScale(0.5, 0.2),
		Position = Props.Position,
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 0.7,
		BackgroundColor3 = Theme.Colors.Primary.Main,
		Corner = {
			Radius = UDim.new(0.15)
		}
	}))
end