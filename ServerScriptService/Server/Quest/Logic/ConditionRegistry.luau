-- ConditionRegistry.lua
local ConditionRegistry = {}

-- Each entry: signal to listen to, function to evaluate progress
ConditionRegistry["FishCaught"] = {
	signal = QuestSignals.FishCaught,
	getProgress = function(profile: ProfileData, required: number)
		return profile.FishingData.FishCaught, required
	end,
	isThreshold = true,
}

ConditionRegistry["TalkTo"] = {
	signal = QuestSignals.NPCTalked,
	getProgress = function(profile: ProfileData, npc: string)
		local npcData = profile.NPCData[npc]
		return if npcData then npcData.IsTalkingTo else false
	end,
	isThreshold = false,
}

ConditionRegistry["ZoneReached"] = {
	signal = QuestSignals.ZoneEntered,
	getProgress = function(profile: ProfileData, zone: string)
		return profile.ZoneData[zone] and profile.ZoneData[zone].HasVisited or false
	end,
	isThreshold = false,
}

return ConditionRegistry