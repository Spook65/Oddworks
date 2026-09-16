--!strict

local CommandUtil = require(script.Parent.Parent:WaitForChild("DevSupport"):WaitForChild("CommandUtil"))

-- Delegates the mutation to PlayerStateService through the shared dev adapter.
return function(context: any, targetPlayer: Player, amount: number): string
	return CommandUtil.GiveScrap(context, targetPlayer, amount)
end
