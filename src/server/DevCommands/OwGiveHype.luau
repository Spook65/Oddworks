--!strict

return {
	Name = "ow-give-hype",
	Aliases = {},
	Description = "Grant server-authoritative Hype for Studio scenario setup.",
	Group = "ODDWORKSDev",
	Args = {
		{ Type = "player", Name = "player", Description = "Target player; use . for yourself." },
		{ Type = "positiveInteger", Name = "amount", Description = "Positive whole Hype amount." },
	},
}
