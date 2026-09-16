--!strict

return {
	Name = "ow-reconcile",
	Aliases = {},
	Description = "Re-derive physical displays from authoritative ownership and workshop state.",
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
