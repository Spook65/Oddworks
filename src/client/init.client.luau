--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
-- Rojo maps src/client/init.client.luau to a LocalScript named Client.
-- Client controllers live below this script and handle presentation-only systems.
local ClientRoot = script
local Controllers = ClientRoot:WaitForChild("Controllers")

type GameConstants = {
	PROJECT_NAME: string,
	VERTICAL_SLICE_VERSION: string,
}

local gameConstantsModule = Shared:WaitForChild("GameConstants")
if not gameConstantsModule:IsA("ModuleScript") then
	error("[ODDWORKS][Client] ReplicatedStorage.Shared.GameConstants must be a ModuleScript.")
end

local GameConstants = require(gameConstantsModule) :: GameConstants

local hudControllerModule = Controllers:WaitForChild("HudController")
if not hudControllerModule:IsA("ModuleScript") then
	error("[ODDWORKS][Client] Client.Controllers.HudController must be a ModuleScript.")
end

local HudController = require(hudControllerModule)

local craftingControllerModule = Controllers:WaitForChild("CraftingController")
if not craftingControllerModule:IsA("ModuleScript") then
	error("[ODDWORKS][Client] Client.Controllers.CraftingController must be a ModuleScript.")
end

local CraftingController = require(craftingControllerModule)

local devConsoleControllerModule = Controllers:WaitForChild("DevConsoleController")
if not devConsoleControllerModule:IsA("ModuleScript") then
	error("[ODDWORKS][Client] Client.Controllers.DevConsoleController must be a ModuleScript.")
end

local DevConsoleController = require(devConsoleControllerModule)

-- The client remains presentation-only: it starts a HUD that displays sanitized
-- server snapshots, but it does not own or mutate authoritative gameplay state.
HudController.Start()
CraftingController.Start()
-- The controller exits immediately outside Studio; the server remains the
-- actual authorization boundary even when the development UI is visible.
DevConsoleController.Start()

print(string.format("[%s][Client] Production bootstrap ready (v%s)", GameConstants.PROJECT_NAME, GameConstants.VERTICAL_SLICE_VERSION))
