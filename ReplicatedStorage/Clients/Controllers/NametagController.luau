local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local localPlayer = Players.LocalPlayer
local Character = localPlayer.CharacterAdded:Wait()

local Replica = require(ReplicatedStorage.Shared.Packages.ReplicaClient)
local NametagScreen = require(ReplicatedStorage.Shared.UI.MainUIs.NametagChangeUI)
local Fusion = require(ReplicatedStorage.Shared.Packages.Fusion)
local Packet = require(ReplicatedStorage.Shared.Packages.Packet)
local NametagConstants = require(ReplicatedStorage.Shared.Constants.Player.NametagConstants)

local DataChanged = Packet("NametagDataChanged", {Country = Packet.String, DisplayName = Packet.String})

local Logger = require(ReplicatedStorage.Shared.Util.Logger)

local log = Logger.new("NametagController")

local scope = Fusion.scoped(Fusion)

UIConstants = NametagConstants.UIConstants

local function OnSubmit(displayName: string, Country)
	DataChanged:Fire({DisplayName = displayName, Country = Country})
end

local NametagController = {}

function NametagController.Init()
	local UI = NametagScreen(scope, {
		Parent = localPlayer.PlayerGui,
		OnSubmit = OnSubmit
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
