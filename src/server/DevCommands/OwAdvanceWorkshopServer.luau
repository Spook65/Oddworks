--!strict

local CommandUtil = require(script.Parent.Parent:WaitForChild("DevSupport"):WaitForChild("CommandUtil"))

-- Advances only one configured step and clearly labels the economy bypass.
return function(context: any, targetPlayer: Player?): string
	return CommandUtil.AdvanceWorkshop(context, targetPlayer or context.Executor)
end
