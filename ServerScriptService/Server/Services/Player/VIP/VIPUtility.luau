local function _buildStatus(tier: number): VIPStatus
	return {
		isVIP     = tier > VIPConstants.TIER_NONE,
		tier      = tier,
		tierLabel = VIPConstants.TIER_LABELS[tier] :: TierLabel,
		expiresAt = 0,       -- 0 = permanent (gamepass-based)
		grantedAt = osTime(),
	}
end