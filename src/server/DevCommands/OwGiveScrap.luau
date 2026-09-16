--!strict

return {
	Name = "ow-give-scrap",
	Aliases = {},
	Description = "Grant server-authoritative Scrap for Studio scenario setup.",
	Group = "ODDWORKSDev",
	Args = {
		{ Type = "player", Name = "player", Description = "Target player; use . for yourself." },
		{ Type = "positiveInteger", Name = "amount", Description = "Positive whole Scrap amount." },
	},
}
