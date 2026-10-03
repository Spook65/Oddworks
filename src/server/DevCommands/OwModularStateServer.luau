--!strict

local CommandUtil = require(script.Parent.Parent:WaitForChild("DevSupport"):WaitForChild("CommandUtil"))

return function(context: any, targetPlayer: Player?): string
	return CommandUtil.DescribeModularState(targetPlayer or context.Executor)
end
