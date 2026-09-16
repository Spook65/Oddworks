--!strict

return {
	Name = "ow-advance-workshop",
	Aliases = {},
	Description = "Advance to the next configured workshop level as a Studio-only setup bypass.",
	Group = "ODDWORKSDev",
	Args = {
		{
			Type = "player",
			Name = "player",
			Description = "Target player; omit to target yourself.",
			Optional = true,
		},
	},
}
