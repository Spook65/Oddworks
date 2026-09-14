--!strict

return {
	Name = "ow-displays",
	Aliases = {},
	Description = "Inspect copied physical display counts and configured capacity.",
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
