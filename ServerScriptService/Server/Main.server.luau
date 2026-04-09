local ServerScriptService = game:GetService("ServerScriptService")
local Server = ServerScriptService.Server
local ServicesFolder = Server.Services
local Core = ServicesFolder.Core
local DataStore = Core.DataStore
local Economy = ServicesFolder.Economy
local VIP = ServicesFolder.Player.VIP

local Services = {
	require(DataStore.PersistanceService),
	require(DataStore.SessionService),
	require(DataStore.StateService),
	require(Economy.EconomyService),
	require(VIP.VIPService)
}

for _, service in Services do
	if service.init then service:init() end
end

for _, service in Services do
	if service.start then service:start() end
end