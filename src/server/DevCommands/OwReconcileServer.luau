--!strict

local CommandUtil = require(script.Parent.Parent:WaitForChild("DevSupport"):WaitForChild("CommandUtil"))

-- Requests the existing reconciliation path without editing ownership or clones directly.
return function(context: any, targetPlayer: Player?): string
	return CommandUtil.ReconcileDisplays(context, targetPlayer or context.Executor)
end
