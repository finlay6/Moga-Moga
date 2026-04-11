local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Replica = require(ReplicatedStorage.Shared.Packages.ReplicaClient)
local RunService = game:GetService("RunService")

local Fusion = require(game.ReplicatedStorage.Shared.Packages.Fusion) -- initialise Fusion here however you please!
local scoped = Fusion.scoped
local Children = Fusion.Children
type UsedAs<T> = Fusion.UsedAs<T>
local localPlayer = game.Players.LocalPlayer
local Character = localPlayer.CharacterAdded:Wait()

local Logger = require(ReplicatedStorage.Shared.Util.Logger)

local log = Logger.new("NametagController")

local NametagController = {}

local SPIN_DEGREES_PER_SECOND = 180
local SPIN_SIZE = 1

local function Spinner(
	scope: Fusion.Scope,
	props: {
		Layout: {
			LayoutOrder: UsedAs<number>?,
			Position: UsedAs<UDim2>?,
			AnchorPoint: UsedAs<Vector2>?,
			ZIndex: UsedAs<number>?,
			Text: UsedAs<string>?,
			TextScaled: UsedAs<boolean>?
		},
		CurrentTime: UsedAs<number>,
	}
): Fusion.Child
	return scope:New "TextLabel" {
		Name = "Spinner",

		LayoutOrder = props.Layout.LayoutOrder,
		Position = props.Layout.Position,
		AnchorPoint = props.Layout.AnchorPoint,
		ZIndex = props.Layout.ZIndex,
		Text = props.Name,
		TextScaled = true,
		Parent = Character:WaitForChild("Head"):WaitForChild("NametagTemplate"):WaitForChild("Frame"),

		Size = UDim2.fromScale(SPIN_SIZE, SPIN_SIZE),

		Rotation = scope:Computed(function(use)
			return (use(props.CurrentTime) * SPIN_DEGREES_PER_SECOND) % 360
		end)
	}
end

-- Don't forget to pass this to `doCleanup` if you disable the script.
local scope = scoped(Fusion, {
	Spinner = Spinner,
})

local NAME_THING = scope:Value("")
local currentTime = scope:Value(os.clock())
table.insert(scope,
	RunService.RenderStepped:Connect(function()
		currentTime:set(os.clock())
	end)
)

local spinner = scope:Spinner {
	Layout = {
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(50, 50),
		
	},
	Name = NAME_THING,
	CurrentTime = currentTime
}

function NametagController.Init()
	Replica.OnNew("PlayerData", function(replica)
		replica:OnSet({"Customisation", "DisplayName"}, function(new_value, old_value)
			log:debug("DisplayName changed for {}. New name: {}", localPlayer, new_value)
			NAME_THING:set(new_value)
			print(NAME_THING)
		end)
	end)

	Replica.RequestData()
end

return NametagController
