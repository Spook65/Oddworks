--!strict
-- Explicit Studio-only invocation; never run by production bootstrap.
return function()
	assert(game:GetService("RunService"):IsStudio(), "Studio only")
	local Navigator = require(script.Parent.FurnaceObstacleNavigator)
	local world = workspace.ODDWORKSWorld:Clone()
	local function check()
		local nav = Navigator.new(world)
		assert(nav.Valid, "Authored graph validation failed")
		local function traverse(start: Vector3, target: Vector3, phase: string): number
			Navigator.Clear(nav)
			local pivot = CFrame.new(start)
			local travelled = 0
			for tick = 1, 500 do
				local nextPivot, reachable = Navigator.Step(nav, pivot, target, 1.8, tick * 0.1, 1, 1, phase, 4)
				assert(reachable, "Unexpected unreachable target")
				local step = (nextPivot.Position - pivot.Position).Magnitude
				assert(step <= 1.80001, "Movement budget exceeded")
				assert(nav:MovementSegmentLegal(pivot.Position, nextPivot.Position), "Illegal committed segment")
				travelled += step
				pivot = nextPivot
				if (Vector3.new(pivot.X, 0, pivot.Z) - Vector3.new(target.X, 0, target.Z)).Magnitude < 0.01 then
					return travelled
				end
			end
			error("Traversal did not complete")
		end

		assert(not nav:MovementSegmentLegal(Vector3.new(0,0.5,214), Vector3.new(2,0.5,214)),
			"Near-wall movement unexpectedly ignored Warden clearance")
		assert(nav:ContactSegmentLegal(Vector3.new(0,0.5,214), Vector3.new(2,0.5,214)),
			"Same-side near-wall contact rejected")
		assert(not nav:ContactSegmentLegal(Vector3.new(0,0.5,208.4), Vector3.new(0,0.5,211.6)),
			"Opposite barrier sides allowed contact")
		assert(nav:ContactSegmentLegal(Vector3.new(13,0.5,214), Vector3.new(15,0.5,214)),
			"Same-side barrier-corner contact rejected")
		assert(nav:ContactSegmentLegal(Vector3.new(-58,0.5,24), Vector3.new(-56,0.5,24)),
			"Same-side station contact rejected")
		assert(not nav:ContactSegmentLegal(Vector3.new(-58,0.5,15), Vector3.new(-58,0.5,21)),
			"Station-separated contact allowed")

		local nearWallTarget = Vector3.new(0,3,214)
		assert(not nav:MovementSegmentLegal(nearWallTarget, nearWallTarget),
			"Near-wall regression target unexpectedly fits Warden envelope")
		local nearWallPivot = CFrame.new(0,0.5,220)
		local nearWallStart = nearWallPivot.Position
		for tick = 1, 20 do
			local previous = nearWallPivot
			local reachable
			nearWallPivot, reachable = Navigator.Step(
				nav, nearWallPivot, nearWallTarget, 1.8, tick * 0.1, 2, 1, "CHASE_ACTIVE", 3.75
			)
			assert(reachable, "Near-wall legal contact approach was unreachable")
			assert(nav:MovementSegmentLegal(previous.Position, nearWallPivot.Position),
				"Near-wall approach committed an illegal segment")
			if (Vector3.new(nearWallPivot.X,0,nearWallPivot.Z) - Vector3.new(nearWallTarget.X,0,nearWallTarget.Z)).Magnitude <= 3.75 then
				break
			end
		end
		local nearWallDistance = (Vector3.new(nearWallPivot.X,0,nearWallPivot.Z)
			- Vector3.new(nearWallTarget.X,0,nearWallTarget.Z)).Magnitude
		assert((nearWallPivot.Position - nearWallStart).Magnitude > 0.1, "Near-wall approach made no progress")
		assert(nearWallDistance <= 3.75, "Near-wall approach did not reach catch radius")
		assert(nav:ContactSegmentLegal(nearWallPivot.Position, nearWallTarget),
			"Near-wall approach lost contact legality")
		Navigator.Clear(nav)
		local droppedApproach, droppedReachable = Navigator.Step(
			nav, CFrame.new(nearWallStart), nearWallTarget, 1.8, 2.5, 2, 1, "DROPPED_CONTESTED", 4
		)
		assert(droppedReachable and (droppedApproach.Position - nearWallStart).Magnitude > 0.1,
			"Dropped Pod did not use the same legal contact-approach path")
		assert(nav:MovementSegmentLegal(nearWallStart, droppedApproach.Position),
			"Dropped Pod approach committed an illegal segment")

		local crossWallWarden = Vector3.new(0,0.5,204)
		local crossWallTarget = Vector3.new(0,3,216)
		assert(not nav:ContactSegmentLegal(crossWallWarden, crossWallTarget),
			"Cross-wall regression setup did not block contact")
		assert(nav:MovementSegmentLegal(crossWallWarden, crossWallWarden)
			and nav:MovementSegmentLegal(crossWallTarget, crossWallTarget),
			"Cross-wall regression endpoints must both fit the Warden envelope")
		local crossWallNext, crossWallReachable = Navigator.Step(
			nav, CFrame.new(crossWallWarden), crossWallTarget, 1.8, 3, 3, 1, "CHASE_ACTIVE", 3.75
		)
		assert(crossWallReachable, "Cross-wall target should be routed around, not contacted through wall")
		assert(nav:MovementSegmentLegal(crossWallWarden, crossWallNext.Position),
			"Cross-wall route committed an illegal segment")
		assert(not (nav:ContactSegmentLegal(crossWallNext.Position, crossWallTarget)
			and (Vector3.new(crossWallNext.X,0,crossWallNext.Z) - Vector3.new(crossWallTarget.X,0,crossWallTarget.Z)).Magnitude <= 3.75),
			"Cross-wall route enabled contact through barrier")

		Navigator.Clear(nav)
		local crossingStart = CFrame.new(13.8,0.5,216)
		local crossingNext, crossingReachable = Navigator.Step(
			nav, crossingStart, Vector3.new(16,3,200), 4.5, 4, 4, 1, "CHASE_ACTIVE", 3.75
		)
		assert(crossingReachable, "Waypoint-crossing regression became unreachable")
		assert(nav:MovementSegmentLegal(crossingStart.Position, crossingNext.Position),
			"Waypoint-crossing regression returned an illegal committed segment")
		assert((crossingNext.Position - crossingStart.Position).Magnitude <= 4.50001,
			"Waypoint-crossing regression exceeded movement budget")

		assert(not nav:MovementSegmentLegal(Vector3.new(0,0.5,220), Vector3.new(0,0.5,200)),
			"Barrier must block locomotion")
		assert(traverse(Vector3.new(0,0.5,220), Vector3.new(0,0.5,200), "CHASE_ACTIVE") > 20)
		traverse(Vector3.new(0,0.5,230), Vector3.new(0,0.5,130), "CHASE_ACTIVE")
		traverse(Vector3.new(0,0.5,220), Vector3.new(0,0.5,200), "DROPPED_CONTESTED")

		local plots = world.WorkshopPlots
		local westSecure = plots.Plot01.FurnacePodSecureZone.Position
		local eastSecure = plots.Plot02.FurnacePodSecureZone.Position
		traverse(Vector3.new(0,0.5,100), westSecure, "CHASE_ACTIVE")
		traverse(Vector3.new(0,0.5,100), eastSecure, "CHASE_ACTIVE")
		assert(nav:MovementSegmentLegal(nav.Nodes.P_W_OUT, westSecure), "West final secure leg blocked")
		assert(nav:MovementSegmentLegal(nav.Nodes.P_E_OUT, eastSecure), "East final secure leg blocked")
		traverse(Vector3.new(12,0.5,300), Vector3.new(-16,0.5,314), "CHASE_ACTIVE")

		local openRoute = world.FurnaceRoutePrototype.SafeRouteLower
		local openEdge = openRoute.CFrame:PointToWorldSpace(Vector3.new(
			openRoute.Size.X / 2 - 3.25,
			0.33,
			openRoute.Size.Z / 2 - 3.25
		))
		assert(nav:Supported(openEdge), "Outermost intended open-route point unsupported")
		assert(not nav:Supported(Vector3.new(81,0.5,85)), "Point beyond experiment east edge supported")

		Navigator.Clear(nav)
		local start = CFrame.new(0,0.5,220)
		Navigator.Step(nav, start, Vector3.new(0,0.5,190), 0, 0, 1, 1, "CHASE_ACTIVE", 3.75)
		local original = table.concat(nav.Plan, ",")
		Navigator.Step(nav, start, Vector3.new(0.1,0.5,190), 0, 0.6, 1, 1, "CHASE_ACTIVE", 3.75)
		assert(table.concat(nav.Plan, ",") == original, "Equal-cost boundary changed route")
		Navigator.Step(nav, start, Vector3.new(-25,0.5,190), 0, 1.2, 1, 1, "CHASE_ACTIVE", 3.75)
		assert(table.concat(nav.Plan, ",") ~= original, "Meaningfully cheaper reversal did not reroute")

		local unchanged = Navigator.Step(nav, start, Vector3.new(100,0.5,200), 1.8, 2, 1, 1, "DROPPED_CONTESTED", 4)
		assert(unchanged == start and nav.Diagnostic.RouteReason == "UNREACHABLE")
		local _, ok = Navigator.Step(nav, start, Vector3.new(0,0.5,240), 0, 3, 1, 2, "CHASE_ACTIVE", 3.75)
		assert(ok and nav.Possession == 2 and #nav.Plan == 0, "Claim retained drop plan")
		Navigator.Clear(nav)
		assert(nav.Plan == nil and nav.Generation == nil)
		world.FurnaceRoutePrototype.FurnaceNavigation.B3_EF:Destroy()
		assert(not Navigator.new(world).Valid, "Missing graph must fail closed")
		return "PASS: contact approaches, cross-wall protection, committed segments, barriers, multi-barrier, drop, real workshops, bounds, hysteresis, reversal, unreachable, possession, cleanup, missing marker, budget"
	end
	local ok, result = pcall(check)
	world:Destroy()
	assert(ok, result)
	return result
end
