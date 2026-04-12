local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local Replica = require(ReplicatedStorage.Shared.Packages.ReplicaClient)
local NametagScreen = require(ReplicatedStorage.Shared.UI.MainUIs.NametagUI)
local Fusion = require(ReplicatedStorage.Shared.Packages.Fusion)
local Packet = require(ReplicatedStorage.Shared.Packages.Packet)

local peek = Fusion.peek

local DataChanged = Packet("NametagDataChanged", {Country = Packet.String, DisplayName = Packet.String})

local NametagConstants = require(ReplicatedStorage.Shared.Constants.Player.NametagConstants)
local Replica = require(ReplicatedStorage.Shared.Packages.ReplicaClient)
UIConstants = NametagConstants.UIConstants

local localPlayer = Players.LocalPlayer
local Character = localPlayer.CharacterAdded:Wait()

local Logger = require(ReplicatedStorage.Shared.Util.Logger)

local log = Logger.new("NametagController")

local scope = Fusion.scoped(Fusion)

local function OnChange(displayName: string)
	
	DataChanged:Fire({Country = "United Kingdom", DisplayName = displayName})
end

local NametagController = {}

function NametagController.Init()
	local UI = NametagScreen(scope, {
		Parent = localPlayer.PlayerGui,
		OnFocusEnd = OnChange
	})
	
	Replica.OnNew("PlayerData", function(replica)

		print(`Replica received client-side! Data:`, replica.Data)

		replica:OnSet({"Score"}, function(new_value, old_value)
			print(`Score has changed from {old_value} to {new_value}`)
		end)

	end)
	
	Replica.RequestData()
end

return NametagController
