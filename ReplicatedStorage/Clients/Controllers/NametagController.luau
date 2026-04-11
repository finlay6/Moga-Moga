local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Replica = require(ReplicatedStorage.Shared.Packages.ReplicaClient)
local Fusion = require(ReplicatedStorage.Shared.Packages.Fusion)
local New = Fusion.New
local localPlayer = game.Players.LocalPlayer
local Character = localPlayer.CharacterAdded:Wait()

local Logger = require(ReplicatedStorage.Shared.Util.Logger)

local log = Logger.new("NametagController")

local NametagController = {}

local function Test()
	local ui = New "BillboardGui" {
		Name = "Greeting",
		Parent = Character.Head,
	}
end

function NametagController.Init()
	Replica.OnNew("PlayerData", function(replica)
		replica:OnSet({"Customisation", "DisplayName"}, function(new_value, old_value)
			log:debug("DisplayName changed for {}. New name: {}", new_value)
		end)

	end)

	Replica.RequestData()
end

return NametagController
