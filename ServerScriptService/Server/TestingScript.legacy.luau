task.wait(5)
local logger = require(game.ReplicatedStorage.Shared.Util.Logger)
local log = logger.new("Testing Log")

local EconomyService = require(game.ServerScriptService.Server.Services.Economy.EconomyService)
local EconomyConstants = require(game.ReplicatedStorage.Shared.Constants.Economy.EconomyConstants)
local Sources = EconomyConstants.Source
--[[
for i = 1,1000 do
	task.wait(0.01)
	EconomyService.spendCash(game.Players.SilentFish20, 1, {source = Sources.ROBUX_EXCHANGE})
end
]]
