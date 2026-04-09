local DataStoreConstants = {}

DataStoreConstants.KICK_MIGRATION_FAILED_MSG  =
	"Your save data could not be migrated safely. "
	.. "Please contact support and do not rejoin — your data is safe."
        local KEY_PREFIX  = "Player_"
DataStoreConstants.STORE_NAME  = "PlayerData"
DataStoreConstants.KICK_MSG    = "Your data failed to load. Please rejoin. If this persists, contact support."
DataStoreConstants.MAX_PATH_DEPTH = 5

return DataStoreConstants