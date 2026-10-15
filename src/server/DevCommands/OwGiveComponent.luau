--!strict

return {
	Name = "ow-give-component",
	Aliases = {},
	Description = "Grant bounded unbanked prototype components for Studio setup.",
	Group = "ODDWORKSDev",
	Args = {
		{ Type = "player", Name = "player", Description = "Target player; use . for yourself." },
		{ Type = "string", Name = "componentId", Description = "Configured component ID." },
		{ Type = "string", Name = "rarity", Description = "Common, Rare, or Legendary." },
		{ Type = "positiveInteger", Name = "count", Description = "Positive count, maximum 999." },
	},
}
