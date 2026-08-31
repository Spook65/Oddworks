--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")

type GameConstants = {
	PROJECT_NAME: string,
	VERTICAL_SLICE_VERSION: string,
}

local gameConstantsModule = Shared:WaitForChild("GameConstants")
if not gameConstantsModule:IsA("ModuleScript") then
	error("[ODDWORKS][Client] ReplicatedStorage.Shared.GameConstants must be a ModuleScript.")
end

local GameConstants = require(gameConstantsModule) :: GameConstants

-- This LocalScript is intentionally presentation-only for the bootstrap pass.
-- It proves client startup and shared ModuleScript loading without owning gameplay state.
print(string.format("[%s][Client] Production bootstrap ready (v%s)", GameConstants.PROJECT_NAME, GameConstants.VERTICAL_SLICE_VERSION))
