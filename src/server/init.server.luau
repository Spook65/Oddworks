--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
-- Rojo maps src/server/init.server.luau to a Script named Server.
-- Service modules under src/server/Services therefore appear as children of this script.
local ServerRoot = script
local Services = ServerRoot:WaitForChild("Services")

type GameConstants = {
	PROJECT_NAME: string,
	VERTICAL_SLICE_VERSION: string,
}

local gameConstantsModule = Shared:WaitForChild("GameConstants")
if not gameConstantsModule:IsA("ModuleScript") then
	error("[ODDWORKS][Server] ReplicatedStorage.Shared.GameConstants must be a ModuleScript.")
end

local GameConstants = require(gameConstantsModule) :: GameConstants

local playerStateServiceModule = Services:WaitForChild("PlayerStateService")
if not playerStateServiceModule:IsA("ModuleScript") then
	error("[ODDWORKS][Server] Server.Services.PlayerStateService must be a ModuleScript.")
end

local PlayerStateService = require(playerStateServiceModule)

local workshopServiceModule = Services:WaitForChild("WorkshopService")
if not workshopServiceModule:IsA("ModuleScript") then
	error("[ODDWORKS][Server] Server.Services.WorkshopService must be a ModuleScript.")
end

local WorkshopService = require(workshopServiceModule)

-- The server verifies that the persistent world exists instead of creating it
-- here so Studio/Rojo remain the source of truth for this static bootstrap map.
local function requireChildOfClass(parent: Instance, childName: string, expectedClassName: string): Instance
	local child = parent:FindFirstChild(childName)
	if not child then
		error(string.format("[ODDWORKS][Server] Missing required bootstrap object: %s.%s", parent:GetFullName(), childName), 2)
	end

	if not child:IsA(expectedClassName) then
		error(
			string.format(
				"[ODDWORKS][Server] %s.%s must be a %s, but found %s.",
				parent:GetFullName(),
				childName,
				expectedClassName,
				child.ClassName
			),
			2
		)
	end

	return child
end

local world = requireChildOfClass(Workspace, "ODDWORKSWorld", "Folder")
local workshopPlots = requireChildOfClass(world, "WorkshopPlots", "Folder")

requireChildOfClass(world, "Spawn", "SpawnLocation")
requireChildOfClass(world, "SalvageField", "Part")
requireChildOfClass(workshopPlots, "Plot01", "Part")
requireChildOfClass(workshopPlots, "Plot02", "Part")

PlayerStateService.Start()
WorkshopService.Start()

print(string.format("[%s][Server] Production bootstrap ready (v%s)", GameConstants.PROJECT_NAME, GameConstants.VERTICAL_SLICE_VERSION))
