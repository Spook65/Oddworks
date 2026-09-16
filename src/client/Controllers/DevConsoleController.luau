--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local DevConsoleController = {}

local started = false

-- Enables Cmdr's presentation only in Studio. This is a convenience gate; the
-- server-side BeforeRun hook is still responsible for privileged authorization.
function DevConsoleController.Start()
	if started then
		return
	end

	started = true
	if not RunService:IsStudio() then
		return
	end

	-- Cmdr's server entry point inserts CmdrClient into ReplicatedStorage after
	-- installing its own networking, so the client waits only during Studio boot.
	local cmdrClientModule = ReplicatedStorage:WaitForChild("CmdrClient", 10)
	if not cmdrClientModule or not cmdrClientModule:IsA("ModuleScript") then
		warn("[ODDWORKS][DEV] CmdrClient was not created; the developer console is unavailable.")
		return
	end

	local didRequire, result = pcall(require, cmdrClientModule)
	if not didRequire then
		warn(string.format("[ODDWORKS][DEV] CmdrClient failed to load: %s", tostring(result)))
		return
	end

	local CmdrClient = result :: any
	CmdrClient:SetActivationKeys({ Enum.KeyCode.F2 })
	CmdrClient:SetPlaceName("ODDWORKS Studio Dev")
end

return DevConsoleController
