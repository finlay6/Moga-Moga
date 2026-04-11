--!strict
-- ServerScriptService/Server/Services/Player/VIP/VIPService/VIPUtility.luau

--[[
	VIPUtility

	Pure construction helpers for VIPService.
	No state, no side effects.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VIPTypes          = require(ReplicatedStorage.Shared.Types.VIPTypes)

local osTime = os.time

type VIPStatus = VIPTypes.VIPStatus

local VIPUtility = {}

--[[
	buildStatus(isVIP) → VIPStatus

	Constructs a fresh VIPStatus struct.
	grantedAt is stamped to now so callers know when this session confirmed VIP.
	expiresAt is 0 — all VIP in this game is gamepass-based (permanent while owned).
]]
function VIPUtility.buildStatus(isVIP: boolean): VIPStatus
	return {
		isVIP     = isVIP,
		expiresAt = 0,
		grantedAt = osTime(),
	}
end

return VIPUtility
