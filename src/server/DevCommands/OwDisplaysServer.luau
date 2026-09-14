--!strict

local CommandUtil = require(script.Parent.Parent:WaitForChild("DevSupport"):WaitForChild("CommandUtil"))

-- Reads only the display service's defensive count copy and server configuration.
return function(context: any, targetPlayer: Player?): string
	return CommandUtil.DescribeDisplays(targetPlayer or context.Executor)
end
