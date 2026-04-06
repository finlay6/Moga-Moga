local ServerScriptService = game:GetService("ServerScriptService")
local Server = ServerScriptService.Server
local ServicesFolder = Server.Services
local Core = ServicesFolder.Core

local Services = {
	require(Core.DataService),
}

for _, service in Services do
	if service.init then service:init() end
end

for _, service in Services do
	if service.start then service:start() end
end