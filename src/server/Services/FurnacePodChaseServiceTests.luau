--!strict
-- Explicit Studio-only invocation; never run by production bootstrap.
return function()
	assert(game:GetService("RunService"):IsStudio(), "Studio only")
	local service = require(script.Parent.FurnacePodChaseService)
	local world = workspace.ODDWORKSWorld:Clone()
	local ok, result = pcall(function()
		return service.RunObstacleNavigationIntegrationTests(world)
	end)
	world:Destroy()
	assert(ok, result)
	return result
end
