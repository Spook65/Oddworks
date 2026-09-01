--!strict

export type RecipeDefinition = {
	RecipeId: string,
	ScrapCost: number,
	OutputSpeciesId: string,
}

local Recipes = {}

-- Crafting costs stay server-only because clients are allowed to request a recipe,
-- but they are never allowed to decide what that recipe costs or produces.
local recipeDefinitions: { [string]: RecipeDefinition } = {
	Toastmarshal = {
		RecipeId = "Toastmarshal",
		ScrapCost = 5,
		OutputSpeciesId = "Toastmarshal",
	},
}

-- Returns a copy of the recipe so callers cannot accidentally edit the server's
-- authoritative balance table after looking up a definition.
function Recipes.GetRecipe(recipeId: string): RecipeDefinition?
	local recipe = recipeDefinitions[recipeId]
	if not recipe then
		return nil
	end

	return {
		RecipeId = recipe.RecipeId,
		ScrapCost = recipe.ScrapCost,
		OutputSpeciesId = recipe.OutputSpeciesId,
	}
end

return Recipes
