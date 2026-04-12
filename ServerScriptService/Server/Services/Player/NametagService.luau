--!strict
-- ServerScriptService/Server/Services/Player/NametagService.luau

--[[
	NametagService

	Manages the BillboardGui nametag above every player's head.

	─── Billboard setup ────────────────────────────────────────────────
	A template BillboardGui lives in ReplicatedStorage at the path defined
	in NametagConstants.TEMPLATE_PATH. On join, NametagService clones it,
	sets the Adornee to the player's Head, and parents it to the Head.
	This keeps all nametag instances in the character hierarchy so they
	stream with the character automatically.

	Expected template structure:
	  NametagTemplate (BillboardGui)
	    Frame (Frame)
	      BadgeIcon    (ImageLabel)  ← rank badge / star, hidden when no rank
	      NameLabel    (TextLabel)   ← display name
	      RankLabel    (TextLabel)   ← rank label e.g. "Admin", hidden if empty
	      CountryLabel (TextLabel)   ← country

	─── Data sources ───────────────────────────────────────────────────
	  - Display name / country : StateService (profile.Customisation)
	  - Rank info / badge      : AdminService
	  - VIP status             : AdminService mirrors VIP as rank 1

	─── First-join prompt ──────────────────────────────────────────────
	On first join (profile.Customisation.DisplayName == ""), the client
	is prompted to enter their name and country via a RemoteFunction.
	Staff and VIP can re-trigger this via settings later.
	Regular players can only change their country after first join.

	─── Updating a nametag ─────────────────────────────────────────────
	Call NametagService.refreshNametag(player) from any service after
	a relevant data change. AdminService.RankResolved is connected
	automatically so rank changes always refresh.
]]

local Players             = game:GetService("Players")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared  = ReplicatedStorage.Shared
local Server  = ServerScriptService.Server

local NametagConstants = require(Shared.Constants.Player.NametagConstants)
local NametagTypes     = require(Shared.Types.NametagTypes)
local AdminTypes       = require(Shared.Types.AdminTypes)
local Logger           = require(Shared.Util.Logger)
local StateService     = require(Server.Services.Core.DataStore.StateService)
local SessionService   = require(Server.Services.Core.DataStore.SessionService)
local AdminService     = require(Server.Services.Meta.AdminService)
local Packet = require(Shared.Packages.Packet)
local Fusion = require(Shared.Packages.Fusion)
local NametagBillboardComponent = require(Server.UI.MainUIs.NametagUI)
local UIConstants = NametagConstants.UIConstants

local fusionScope = Fusion.scoped

local scope = fusionScope(Fusion)

local NametagDataChanged = Packet("NametagDataChanged", {CountryName = Packet.String, DisplayName = Packet.String})

-- ─── Upvalues ────────────────────────────────────────────────────────────────
local taskSpawn = task.spawn
local taskDelay = task.delay

-- ─── Types ───────────────────────────────────────────────────────────────────
type NametagData    = NametagTypes.NametagData
type NametagProfile = NametagTypes.NametagProfile
type RankInfo       = AdminTypes.RankInfo

-- ─── Private path constants ───────────────────────────────────────────────────
local PATH_DISPLAY_NAME = {"Customisation", "DisplayName"}
local PATH_COUNTRY      = {"Customisation", "Country"}

-- ─── State ───────────────────────────────────────────────────────────────────
local log = Logger.new("NametagService")

-- Per-player BillboardGui references so we don't search the character each update.
local _playerNametagDataCache = {}

-- Cached template clone source. Resolved once in init().
local _template: BillboardGui

-- Remote used to prompt name/country input on the client.
-- TODO: wire to Remotes.luau once the network layer is set up.
-- local _promptRemote: RemoteFunction

-- ─── Private: Billboard construction ────────────────────────────────────────

local function _createBillboard(player: Player, character: Model)
	local displayNameValue = scope:Value("")
	local countryValue = scope:Value("")
	local rankValue = scope:Value("")
	local badgeImageId = scope:Value("")

	local NametagBillboard = NametagBillboardComponent(scope, {
		Text = {
			NameText = displayNameValue,
			CountryText = countryValue,
			RankText = rankValue
		},
		Image = {
			BadgeImageId = badgeImageId
		},
		Player = player,
		Parent = character:WaitForChild("Head"),
		UIConstants = UIConstants
	})
	
	return {
		Billboard = NametagBillboard :: BillboardGui,
		DisplayNameValue = displayNameValue,
		CountryValue = countryValue,
		RankValue = rankValue,
		BadgeImageId = badgeImageId
	}
end

-- ─── Private: Data resolution ────────────────────────────────────────────────

local function _resolveNametagData(player: Player): NametagData
	local displayName: string = StateService.Get(player, PATH_DISPLAY_NAME)
	local country: string     = StateService.Get(player, PATH_COUNTRY)

	if displayName == "" then
		displayName = player.Name
	end

	local rankInfo: RankInfo = AdminService.getRankInfo(player)
	local isStaff            = AdminService.isStaff(player)

	return {
		displayName  = displayName,
		country      = country,
		rankLabel    = rankInfo.label,
		badgeImageId = rankInfo.badgeImageId,
		badgeColor   = rankInfo.badgeColor,
		nameColor    = rankInfo.nameColor,
		isStaff      = isStaff,
	}
end

-- ─── Private: Applying data to the billboard ─────────────────────────────────

-- Finds a named descendant of the billboard safely.
local function _find(billboard: BillboardGui, name: string): Instance?
	return billboard:FindFirstChild(name, true)
end

local function _applyToBillboard(nametagData, data: NametagData)
	nametagData.DisplayNameValue:set(data.displayName)
	nametagData.CountryValue:set(data.country)
	nametagData.RankValue:set(data.rankLabel)
	nametagData.BadgeImageId:set(data.badgeImageId)
end

-- ─── Private: First-join prompt ──────────────────────────────────────────────

--[[
	_promptNameAndCountry(player)

	Fires the client-side UI to collect name + country on first join.
	Stubbed until the Remote and UI are wired up.

	The server expects the client to return:
	  { name: string, country: string }

	Validation happens here before writing to StateService.
]]
local function _promptNameAndCountry(player: Player)
	-- TODO: uncomment once _promptRemote is wired in Remotes.luau
	--[[
	local ok, result = pcall(function()
		return _promptRemote:InvokeClient(player)
	end)

	if not ok or type(result) ~= "table" then
		log:warn("Name prompt failed or timed out for {}", player.Name)
		return
	end

	local name    = tostring(result.name    or ""):sub(1, 32)
	local country = tostring(result.country or ""):sub(1, 64)

	-- Validate country against the allowed list
	local validCountry = false
	for _, c in NametagConstants.COUNTRIES do
		if c == country then
			validCountry = true
			break
		end
	end

	if name ~= "" then
		StateService.Set(player, PATH_DISPLAY_NAME, name)
	end

	if validCountry then
		StateService.Set(player, PATH_COUNTRY, country)
	end

	NametagService.refreshNametag(player)
	]]
	log:debug("_promptNameAndCountry stubbed for {} — wire Remote to activate", player.Name)
end

-- ─── Private: Lifecycle helpers ──────────────────────────────────────────────

local function _onCharacterAdded(player: Player, character: Model)
	-- Small delay so the character fully loads before we search for Head.
	taskDelay(0.1, function()
		if not player:IsDescendantOf(Players) then return end

		local nametagData = _createBillboard(player, character)
		if nametagData == nil then return end

		_playerNametagDataCache[player] = nametagData

		-- Apply current data immediately.
		local data = _resolveNametagData(player)
		_applyToBillboard(nametagData, data)

		log:debug("Billboard created for {}", player.Name)
	end)
end

local function _onPlayerReady(player: Player)
	-- Check if this is a first join (no display name saved yet).
	local savedName: string = StateService.Get(player, PATH_DISPLAY_NAME) or ""
	if savedName == "" then
		-- First join — prompt for name and country.
		-- Runs in its own thread so it doesn't block the ready pipeline.
		taskSpawn(_promptNameAndCountry, player)
	end

	-- Wire CharacterAdded for this player.
	player.CharacterAdded:Connect(function(character)
		_onCharacterAdded(player, character)
	end)

	-- Handle character already spawned (Studio / fast respawn edge case).
	if player.Character then
		taskSpawn(_onCharacterAdded, player, player.Character)
	end
end

-- ─── Module ──────────────────────────────────────────────────────────────────
local NametagService = {}

--[[
	refreshNametag(player)

	Re-resolves and re-applies nametag data for a player.
	Call this after any data change that affects the nametag:
	  - Display name or country updated
	  - AdminService.RankResolved fires (connected automatically in start())
	  - VIPStatusChanged fires (AdminService handles the cascade)
]]
function NametagService.refreshNametag(player: Player)
	local nametagData = _playerNametagDataCache[player]
	if nametagData == nil then
		log:debug("refreshNametag called for {} but no billboard found", player.Name)
		return
	end

	local data = _resolveNametagData(player)
	_applyToBillboard(nametagData, data)
end

--[[
	setDisplayName(player, name) → boolean

	Sets the player's custom display name if they have permission.
	Returns false if the player's rank does not allow name editing.

	Name is trimmed and capped at 32 characters.
	Pass "" to reset to the Roblox username.
]]
function NametagService.setDisplayName(player: Player, name: string): boolean
	if not AdminService.canEditName(player) then
		log:debug("{} attempted to set display name without permission", player.Name)
		return false
	end

	local trimmed = name:match("^%s*(.-)%s*$") or ""
	trimmed = trimmed:sub(1, 32)

	StateService.Set(player, PATH_DISPLAY_NAME, trimmed)
	NametagService.refreshNametag(player)
	log:debug("{} set display name to '{}'", player.Name, trimmed)
	return true
end

--[[
	setCountry(player, country) → boolean

	Sets the player's country. All rank levels can set their country.
	Country must be in NametagConstants.COUNTRIES — returns false if not.
]]
function NametagService.setCountry(player: Player, country: string): boolean
	local valid = false
	for _, c in NametagConstants.COUNTRIES do
		if c == country then
			valid = true
			break
		end
	end

	if not valid then
		log:debug("{} submitted invalid country '{}'", player.Name, country)
		return false
	end

	StateService.Set(player, PATH_COUNTRY, country)
	NametagService.refreshNametag(player)
	return true
end

--[[
	getNametagData(player) → NametagData?

	Returns the resolved nametag data for a player without touching the UI.
	Useful for admin tools or debugging.
	Returns nil if the player's profile is not loaded.
]]
function NametagService.getNametagData(player: Player): NametagData?
	if SessionService.GetData(player) == nil then return nil end
	return _resolveNametagData(player)
end

-- ─── Lifecycle ───────────────────────────────────────────────────────────────

function NametagService.init()
	-- Re-apply nametag whenever AdminService resolves or refreshes a rank.
	-- This covers: initial join, VIP purchase, staff status changes.
	AdminService.RankResolved:Connect(function(player)
		NametagService.refreshNametag(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		_playerNametagDataCache[player] = nil
	end)

	log:info("NametagService initialised")
end

function NametagService.start()
	SessionService.PlayerReady:Connect(function(player: Player)
		taskSpawn(_onPlayerReady, player)
	end)

	-- Handle players already past the ready gate.
	for _, player in Players:GetPlayers() do
		if SessionService.GetData(player) ~= nil then
			taskSpawn(_onPlayerReady, player)
		end
	end
	
	NametagDataChanged.OnServerEvent:Connect(function(player: Player, nametagData)
		NametagService.setDisplayName(player, nametagData.DisplayName)
		NametagService.setCountry(player, nametagData.CountryName)
	end)

	log:info("NametagService started")
end

return NametagService
