--!strict

local CommandUtil = require(script.Parent.Parent:WaitForChild("DevSupport"):WaitForChild("CommandUtil"))

-- Validates species through server config before using the production ownership API.
return function(context: any, targetPlayer: Player, speciesId: string, count: number): string
	return CommandUtil.GiveOddling(context, targetPlayer, speciesId, count)
end
