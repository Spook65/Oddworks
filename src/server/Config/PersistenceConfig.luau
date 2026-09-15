--!strict

local PersistenceConfig = {
	SCHEMA_VERSION = 1,
	PROFILE_KEY_PREFIX = "Player_",
	STUDIO_MOCK_STORE_NAME = "ODDWORKS_STUDIO_MOCK_PlayerData_v1",
	INTERNAL_TEST_STORE_NAME = "ODDWORKS_TEST_PlayerData_v1",
	PRODUCTION_STORE_NAME = "ODDWORKS_PlayerData_v1",
	-- Verified against the separate ODDWORKS - INTERNAL TEST experience.
	INTERNAL_TEST_UNIVERSE_ID = 10_766_404_161,
}

-- Production persistence is intentionally unreachable in Pass 11. A future
-- release pass must explicitly add and review that environment selection.
return table.freeze(PersistenceConfig)
