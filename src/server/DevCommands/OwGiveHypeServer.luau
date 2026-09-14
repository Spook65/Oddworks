--!strict

local CommandUtil = require(script.Parent.Parent:WaitForChild("DevSupport"):WaitForChild("CommandUtil"))

-- Delegates the mutation to PlayerStateService so normal replication still fires.
return function(context: any, targetPlayer: Player, amount: number): string
	return CommandUtil.GiveHype(context, targetPlayer, amount)
end
