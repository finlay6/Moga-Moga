local OnyxUI = require(game.ReplicatedStorage.Shared.Packages.OnyxUI)
local Fusion = require(game.ReplicatedStorage.Shared.Packages.Fusion)
local peek = Fusion.peek
local OnEvent = Fusion.OnEvent

local Children = Fusion.Children

export type TextButtonProps = OnyxUI.ButtonProps & {
	Text: Fusion.UsedAs<string>?,
}

return function(Scope: Fusion.Scope<any>, Props: TextButtonProps)
	local Scope = Fusion.innerScope(Scope, Fusion, OnyxUI.Util, OnyxUI.Components)
	local Theme = OnyxUI.Themer.Theme:now()

	return Scope:TextInput(OnyxUI.Util.CombineProps(Props, {
		Name = Props.Name,
		TextTransparency = 0,
		TextColor3 = Color3.fromRGB(255, 255, 255),
		TextXAlignment = "Center",
		TextYAlignment = "Center",
		Text = Props.Text,
		FontFace = Font.fromName("Nunito"),
		Size = UDim2.fromScale(0.5, 0.2),
		Position = Props.Position,
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = Theme.Colors.Primary.Main,
		TextScaled = true,
		Corner = {
			Radius = UDim.new(0.15)
		},
	}))
end