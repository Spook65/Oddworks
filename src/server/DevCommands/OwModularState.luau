--!strict

return {
	Name = "ow-modular-state",
	Aliases = {},
	Description = "Inspect a player's sanitized temporary modular state.",
	Group = "ODDWORKSDev",
	Args = {
		{
			Type = "player",
			Name = "player",
			Description = "Target player; omit to inspect yourself.",
			Optional = true,
		},
	},
}
