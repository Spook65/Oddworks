--!strict

return {
	Name = "ow-state",
	Aliases = {},
	Description = "Inspect a player's authoritative ODDWORKS session snapshot.",
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
