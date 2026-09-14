--!strict

return {
	Name = "ow-give-oddling",
	Aliases = {},
	Description = "Grant configured Oddling ownership for Studio scenario setup.",
	Group = "ODDWORKSDev",
	Args = {
		{ Type = "player", Name = "player", Description = "Target player; use . for yourself." },
		{ Type = "string", Name = "speciesId", Description = "Configured Oddling species ID." },
		{ Type = "positiveInteger", Name = "count", Description = "Positive whole ownership count." },
	},
}
