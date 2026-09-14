--!strict

local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Services = script.Parent
local ServerRoot = assert(Services.Parent, "[ODDWORKS][DEV] Services folder must have a parent.")
local DevCommands = ServerRoot:WaitForChild("DevCommands")

local DevHarnessService = {}

local COMMAND_GROUP = "ODDWORKSDev"
local started = false

-- This check is deliberately repeated by the server hook. Hiding the console on
-- a client is presentation only; the server environment decides authorization.
local function getAuthorizationFailure(): string?
	if not RunService:IsStudio() then
		return "ODDWORKS developer commands are disabled outside Roblox Studio."
	end

	return nil
end

-- Starts Cmdr only in Studio and registers the authorization hook before any
-- state-changing commands. A missing dev dependency cannot block gameplay boot.
function DevHarnessService.Start()
	if started then
		return
	end

	started = true
	if getAuthorizationFailure() then
		return
	end

	local packages = ServerScriptService:FindFirstChild("ServerPackages")
	local cmdrModule = packages and packages:FindFirstChild("Cmdr")
	if not cmdrModule or not cmdrModule:IsA("ModuleScript") then
		warn("[ODDWORKS][DEV] Cmdr is unavailable. Run `wally install` before Studio testing.")
		return
	end

	local didRequire, result = pcall(require, cmdrModule)
	if not didRequire then
		warn(string.format("[ODDWORKS][DEV] Cmdr failed to load: %s", tostring(result)))
		return
	end

	local Cmdr = result :: any
	-- This hook executes on the server immediately before an implementation.
	-- It remains the security boundary even if an exploiter invokes Cmdr networking directly.
	Cmdr.Registry:RegisterHook("BeforeRun", function(context: any): string?
		local environmentFailure = getAuthorizationFailure()
		if environmentFailure then
			return environmentFailure
		end

		if context.Group ~= COMMAND_GROUP then
			return "This command group is not authorized by the ODDWORKS developer harness."
		end

		return nil
	end)

	-- Default Cmdr commands are intentionally omitted; only the narrowly scoped
	-- ODDWORKS setup and inspection commands are replicated to Studio clients.
	Cmdr.Registry:RegisterCommandsIn(DevCommands)
	print("[ODDWORKS][DEV] Studio-only Cmdr harness ready (F2).")
end

return DevHarnessService
