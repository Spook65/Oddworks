--!strict

local CommandUtil = require(script.Parent.Parent:WaitForChild("DevSupport"):WaitForChild("CommandUtil"))

-- Uses the executor when no player is supplied and returns only a formatted snapshot.
return function(context: any, targetPlayer: Player?): string
	return CommandUtil.DescribeState(targetPlayer or context.Executor)
end
