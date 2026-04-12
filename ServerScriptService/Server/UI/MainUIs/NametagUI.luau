local OnyxUI = require(game.ReplicatedStorage.Shared.Packages.OnyxUI)
local Fusion = require(game.ReplicatedStorage.Shared.Packages.Fusion)
local TextComponent = require(game.ServerScriptService.Server.UI.Components.TextComponent)
local ImageComponent = require(game.ServerScriptService.Server.UI.Components.ImageComponent)

local Scoped = Fusion.scoped
local Children = Fusion.Children

local scope = Scoped()

export type TextButtonProps = OnyxUI.ButtonProps & {
	Text: Fusion.UsedAs<string>?,
}

local function Frame(Scope: Fusion.Scope<any>, Props: TextButtonProps)
	return Scope:New "Frame" {
		Name = "MainFrame",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		[Children] = {
			CountryLabel = TextComponent(Scope, {
				Position = UDim2.fromScale(0.7, 0.2),
				Text = Props.Text.CountryText
			}),
			NameLabel = TextComponent(Scope, {
				Position = UDim2.fromScale(0.7, 0.5),
				Text = Props.Text.NameText
			}),
			RankLabel = TextComponent(Scope, {
				Position = UDim2.fromScale(0.7, 0.8),
				Text = Props.Text.RankText
			}),
			BadgeImage = ImageComponent(Scope, {
				Position = UDim2.fromScale(0.25, 0.5),
				ImageId = Props.Image.BadgeImageId
			})
		},
	}
end

return function(scope: Fusion.Scope<any>, Props)
	local Scope = Fusion.innerScope(scope, Fusion, OnyxUI.Util, OnyxUI.Components)
	local Theme = OnyxUI.Themer.Theme:now()
	
	local Frame = Frame(scope, {
		Text = Props.Text,
		Image = Props.Image
	})
	
	return Scope:New "BillboardGui" {
		Name = "NametagTemplate",
		Parent = Props.Parent,
		Adornee = Props.Parent,
		Size = Props.UIConstants.BILLBOARD_SIZE,
		StudsOffset = Props.UIConstants.BILLBOARD_STUD_OFFSET,
		MaxDistance = Props.UIConstants.BILLBOARD_MAX_DISTANCE,

		[Children] = {
			Frame
		},
	}
end