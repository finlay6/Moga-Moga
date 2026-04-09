local ReplicatedStorage   = game:GetService("ReplicatedStorage")

local Shared   = ReplicatedStorage.Shared

local VIPTypes           = require(Shared.Types.VIPTypes)

local osTime = os.time

type VIPStatus        = VIPTypes.VIPStatus

local VIPUtil = {}

function VIPUtil._buildStatus(isVIP: boolean): VIPStatus
	return {
		isVIP     = isVIP,
		expiresAt = 0,       -- 0 = permanent (gamepass-based)
		grantedAt = osTime(),
	}
end

return VIPUtil