--!strict

-- Shared constants are safe here because they describe project identity only.
-- Economy, rewards, crafting costs, unlocks, and ownership rules must stay server-owned.
local GameConstants = {
	PROJECT_NAME = "ODDWORKS",
	VERTICAL_SLICE_VERSION = "0.1",
}

return GameConstants
