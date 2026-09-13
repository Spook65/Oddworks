--!strict

export type RecipeDefinition = {
	RecipeId: string,
	ScrapCost: number,
	OutputSpeciesId: string,
	RequiredWorkshopLevel: number,
	IsCraftingEnabled: boolean,
}

local Recipes = {}

-- Crafting costs stay server-only because clients are allowed to request a recipe,
-- but they are never allowed to decide what that recipe costs or produces.
local recipeDefinitions: { [string]: RecipeDefinition } = {
	Toastmarshal = {
		RecipeId = "Toastmarshal",
		ScrapCost = 5,
		OutputSpeciesId = "Toastmarshal",
		RequiredWorkshopLevel = 1,
		IsCraftingEnabled = true,
	},
	Conejurer = {
		RecipeId = "Conejurer",
		ScrapCost = 8,
		OutputSpeciesId = "Conejurer",
		RequiredWorkshopLevel = 2,
		-- Progression can reveal Conejurer before its runtime model is ready.
		-- Server crafting remains disabled independently from that unlock.
		IsCraftingEnabled = false,
	},
}

-- Copies one definition so no caller can mutate authoritative recipe rules.
local function copyRecipe(recipe: RecipeDefinition): RecipeDefinition
	return {
		RecipeId = recipe.RecipeId,
		ScrapCost = recipe.ScrapCost,
		OutputSpeciesId = recipe.OutputSpeciesId,
		RequiredWorkshopLevel = recipe.RequiredWorkshopLevel,
		IsCraftingEnabled = recipe.IsCraftingEnabled,
	}
end

-- Returns a copy of the recipe so callers cannot accidentally edit the server's
-- authoritative balance table after looking up a definition.
function Recipes.GetRecipe(recipeId: string): RecipeDefinition?
	local recipe = recipeDefinitions[recipeId]
	if not recipe then
		return nil
	end

	return copyRecipe(recipe)
end

-- Returns all recipes in deterministic ID order for server-side progression reconciliation.
-- The returned array and definitions are copies, not mutable access to recipe authority.
function Recipes.GetAllRecipes(): { RecipeDefinition }
	local recipes: { RecipeDefinition } = {}

	for _, recipe in pairs(recipeDefinitions) do
		table.insert(recipes, copyRecipe(recipe))
	end

	table.sort(recipes, function(left: RecipeDefinition, right: RecipeDefinition): boolean
		return left.RecipeId < right.RecipeId
	end)

	return recipes
end

return Recipes
