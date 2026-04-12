

local Players = game:GetService("Players")

local Fusion = require(game.ReplicatedStorage.Shared.Packages.Fusion)
local scoped = Fusion.scoped
local Children = Fusion.Children
type UsedAs<T> = Fusion.UsedAs<T>

local function PlayerList(
	scope: Fusion.Scope,
	props: {
		Players: UsedAs<{Player}>
	}
): Fusion.Child
	return scope:New "Frame" {
		Name = "PlayerList",

		Position = UDim2.fromScale(1, 0),
		AnchorPoint = Vector2.new(1, 0),
		Size = UDim2.fromOffset(300, 0),
		AutomaticSize = "Y",

		BackgroundTransparency = 0.5,
		BackgroundColor3 = Color3.new(0, 0, 0),

		[Children] = {
			scope:New "UICorner" {
				CornerRadius = UDim.new(0, 8)
			},
			scope:New "UIListLayout" {
				SortOrder = "Name",
				FillDirection = "Vertical"
			},

			scope:ForValues(props.Players, function(use, scope, player)
				return scope:New "TextLabel" {
					Name = "PlayerListRow: " .. player.DisplayName,

					Size = UDim2.new(1, 0, 0, 25),
					BackgroundTransparency = 1,

					Text = player.DisplayName,
					TextColor3 = Color3.new(1, 1, 1),
					Font = Enum.Font.GothamMedium,
					TextSize = 16,
					TextXAlignment = "Right",
					TextTruncate = "AtEnd",

					[Children] = scope:New "UIPadding" {
						PaddingLeft = UDim.new(0, 10),
						PaddingRight = UDim.new(0, 10)
					}
				}
			end)
		}
	}
end

-- Don't forget to pass this to `doCleanup` if you disable the script.
local scope = scoped(Fusion, {
	PlayerList = PlayerList
})

local players = scope:Value(Players:GetPlayers())
local function updatePlayers()
	players:set(Players:GetPlayers())
end
table.insert(scope, {
	Players.PlayerAdded:Connect(updatePlayers),
	Players.PlayerRemoving:Connect(updatePlayers)
})

local gui = scope:New "ScreenGui" {
	Name = "PlayerListGui",
	Parent = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui"),

	[Children] = scope:PlayerList {
		Players = players
	}
}
