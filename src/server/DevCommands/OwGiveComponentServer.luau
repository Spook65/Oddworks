--!strict

local CommandUtil = require(script.Parent.Parent:WaitForChild("DevSupport"):WaitForChild("CommandUtil"))

return function(context: any, targetPlayer: Player, componentId: string, rarity: string, count: number): string
	return CommandUtil.GiveComponent(context, targetPlayer, componentId, rarity, count)
end
