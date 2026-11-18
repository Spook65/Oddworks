--!strict
-- Furnace-only, synchronous locomotion. Ownership and gameplay distances stay in the chase service.
local Navigator = {}
local RADIUS = 3.25
local CONTACT_TOLERANCE = 0.05
local INTERVAL = 0.5
local IMPROVEMENT = 6
local APPROACH_TOLERANCE = 0.05
local APPROACH_DIRECTIONS = 16
local SUPPORTED_MIN_X = -84
local SUPPORTED_MAX_X = 84
local SUPPORTED_MIN_Z = -14
local SUPPORTED_MAX_Z = 320
local IDS = {
	"B1_EF", "B1_EH", "B1_WF", "B1_WH",
	"B2_EF", "B2_EH", "B2_WF", "B2_WH",
	"B3_EF", "B3_EH", "B3_WF", "B3_WH",
	"F_C_REAR", "F_E_REAR", "F_E_SITE",
	"P_E_IN", "P_E_OUT", "P_W_IN", "P_W_OUT",
}
local EDGES = {
	{"B1_WF","B1_EF"}, {"B1_WH","B1_EH"}, {"B1_WF","B1_WH"}, {"B1_EF","B1_EH"},
	{"B2_WF","B2_EF"}, {"B2_WH","B2_EH"}, {"B2_WF","B2_WH"}, {"B2_EF","B2_EH"},
	{"B3_WF","B3_EF"}, {"B3_WH","B3_EH"}, {"B3_WF","B3_WH"}, {"B3_EF","B3_EH"},
	{"B3_WH","B2_WF"}, {"B3_EH","B2_EF"}, {"B2_WH","B1_WF"}, {"B2_EH","B1_EF"},
	{"B3_EF","F_E_SITE"}, {"F_E_SITE","F_E_REAR"}, {"F_E_REAR","F_C_REAR"},
	{"B1_WH","P_W_IN"}, {"B1_EH","P_E_IN"},
	{"P_W_IN","P_W_OUT"}, {"P_E_IN","P_E_OUT"}, {"P_W_IN","P_E_IN"},
}
local function flat(p: Vector3): Vector3
	return Vector3.new(p.X, 0, p.Z)
end
local function length(a: Vector3, b: Vector3): number
	return (flat(a) - flat(b)).Magnitude
end
-- Slab intersection against a yaw-oriented rectangle. Positive padding is a
-- locomotion envelope; slight negative padding avoids boundary-only contact
-- being treated as a solid separator.
local function intersects(a: Vector3, b: Vector3, part: BasePart, padding: number): boolean
	local p = part.CFrame:PointToObjectSpace(a)
	local q = part.CFrame:PointToObjectSpace(b)
	local lo, hi = 0, 1
	for _, axis in ipairs({"X", "Z"}) do
		local origin = if axis == "X" then p.X else p.Z
		local delta = if axis == "X" then q.X - p.X else q.Z - p.Z
		local extent = math.max(0, (if axis == "X" then part.Size.X else part.Size.Z) / 2 + padding)
		if math.abs(delta) < 0.000001 then
			if math.abs(origin) > extent then return false end
		else
			local x, y = (-extent - origin) / delta, (extent - origin) / delta
			lo = math.max(lo, math.min(x, y))
			hi = math.min(hi, math.max(x, y))
			if lo > hi then return false end
		end
	end
	return true
end

function Navigator.new(world: Instance)
	local self: any = {Nodes = {}, Neighbors = {}, Obstacles = {}, Plan = nil, MovementDestination = nil, NextDecision = 0,
		Generation = nil, Possession = nil, Phase = nil, Valid = false,
		Diagnostic = {MovementTarget = "NONE", CurrentWaypoint = "NONE", RouteReason = "INVALID_GRAPH",
			DirectSegment = "NOT_CHECKED", RouteCost = nil}}
	local foundation = world:FindFirstChild("Foundation")
	local route = world:FindFirstChild("FurnaceRoutePrototype")
	local markers = route and route:FindFirstChild("FurnaceNavigation")
	self.Foundation = foundation
	if not foundation or not foundation:IsA("BasePart") or not markers then return self end
	-- Explicit Furnace return rectangle, wholly supported by the accepted Foundation.
	-- Its east edge includes the rotated open route plus the Warden envelope while
	-- excluding the unrelated activity beginning beyond x=84.
	function self:Supported(p: Vector3): boolean
		local f = self.Foundation
		if not f.Parent or not f.CanCollide or f.CFrame.UpVector.Y < 0.999 then return false end
		local localPoint = f.CFrame:PointToObjectSpace(p)
		return p.X >= SUPPORTED_MIN_X + RADIUS and p.X <= SUPPORTED_MAX_X - RADIUS
			and p.Z >= SUPPORTED_MIN_Z + RADIUS and p.Z <= SUPPORTED_MAX_Z - RADIUS
			and math.abs(localPoint.X) + RADIUS <= f.Size.X / 2
			and math.abs(localPoint.Z) + RADIUS <= f.Size.Z / 2
			and math.abs(f.Position.Y + f.Size.Y / 2) < 0.01
	end
	-- Discover authored geometry once, not characters/runtime effects or per-tick Workspace scans.
	for _, part in ipairs(world:GetDescendants()) do
		if part:IsA("BasePart") and part.CanCollide
			and part.Position.Y + part.Size.Y / 2 > 0.5
			and part.Position.Y - part.Size.Y / 2 < 7.5 then
			if part.CFrame.UpVector.Y < 0.999 then return self end
			table.insert(self.Obstacles, part)
		end
	end
	function self:MovementSegmentLegal(a: Vector3, b: Vector3): boolean
		if not self:Supported(a) or not self:Supported(b) then return false end
		for _, part in ipairs(self.Obstacles) do
			if part.Parent and part.CanCollide and intersects(a, b, part, RADIUS) then return false end
		end
		return true
	end
	function self:ContactSegmentLegal(a: Vector3, b: Vector3): boolean
		for _, part in ipairs(self.Obstacles) do
			if part.Parent and part.CanCollide and intersects(a, b, part, -CONTACT_TOLERANCE) then return false end
		end
		return true
	end
	-- Compatibility for the existing movement-focused tests and route solver.
	self.Legal = self.MovementSegmentLegal
	for _, id in ipairs(IDS) do
		local marker = markers:FindFirstChild(id)
		if not marker or not marker:IsA("BasePart") or not marker.Anchored
			or marker.CanCollide or marker.CanTouch or marker.CanQuery then return self end
		self.Nodes[id] = flat(marker.Position)
		self.Neighbors[id] = {}
		if not self:MovementSegmentLegal(self.Nodes[id], self.Nodes[id]) then return self end
	end
	for _, edge in ipairs(EDGES) do
		local a, b = edge[1], edge[2]
		if not self:MovementSegmentLegal(self.Nodes[a], self.Nodes[b]) then return self end
		table.insert(self.Neighbors[a], b)
		table.insert(self.Neighbors[b], a)
	end
	for _, id in ipairs(IDS) do table.sort(self.Neighbors[id]) end
	self.Valid = true
	return self
end

function Navigator.Clear(self: any)
	self.Plan = nil
	self.MovementDestination = nil
	self.NextDecision = 0
	self.Generation, self.Possession, self.Phase = nil, nil, nil
	self.Diagnostic = {MovementTarget = "NONE", CurrentWaypoint = "NONE",
		RouteReason = if self.Valid then "UNREACHABLE" else "INVALID_GRAPH", DirectSegment = "NOT_CHECKED"}
end

local function cost(self: any, start: Vector3, target: Vector3, plan: {string}?): number
	if not plan then return math.huge end
	local total, previous = 0, start
	for _, id in ipairs(plan) do
		local p = self.Nodes[id]
		if not self:MovementSegmentLegal(previous, p) then return math.huge end
		total += length(previous, p)
		previous = p
	end
	if not self:MovementSegmentLegal(previous, target) then return math.huge end
	return total + length(previous, target)
end

local function solve(self: any, start: Vector3, target: Vector3): ({string}?, number)
	-- Multi-source Dijkstra includes every legal entry cost; exits include their full target leg.
	local distances, paths, visited = {}, {}, {}
	for _, id in ipairs(IDS) do
		distances[id] = if self:MovementSegmentLegal(start, self.Nodes[id]) then length(start, self.Nodes[id]) else math.huge
		paths[id] = {id}
	end
	local best, bestCost = nil, math.huge
	for _ = 1, #IDS do
		local current, minimum = nil, math.huge
		for _, id in ipairs(IDS) do
			if not visited[id] and distances[id] < minimum then current, minimum = id, distances[id] end
		end
		if not current then break end
		visited[current] = true
		if self:MovementSegmentLegal(self.Nodes[current], target) then
			local total = minimum + length(self.Nodes[current], target)
			if total < bestCost then best, bestCost = paths[current], total end
		end
		for _, neighbor in ipairs(self.Neighbors[current]) do
			if self:MovementSegmentLegal(self.Nodes[current], self.Nodes[neighbor]) then
				local nextCost = minimum + length(self.Nodes[current], self.Nodes[neighbor])
				if nextCost < distances[neighbor] then
					distances[neighbor] = nextCost
					paths[neighbor] = table.clone(paths[current])
					table.insert(paths[neighbor], neighbor)
				end
			end
		end
	end
	return best, bestCost
end

local function routeTo(self: any, start: Vector3, destination: Vector3): ({string}?, number)
	if self:MovementSegmentLegal(start, destination) then
		return {}, length(start, destination)
	end
	return solve(self, start, destination)
end

local function destinationStillValid(self: any, destination: Vector3?, target: Vector3, contactRadius: number): boolean
	return destination ~= nil
		and self:MovementSegmentLegal(destination :: Vector3, destination :: Vector3)
		and length(destination :: Vector3, target) <= contactRadius + 0.001
		and self:ContactSegmentLegal(destination :: Vector3, target)
end

local function solveWithContactApproach(
	self: any,
	start: Vector3,
	target: Vector3,
	contactRadius: number
): ({string}?, number, Vector3?)
	if self:MovementSegmentLegal(target, target) then
		local plan, routeCost = routeTo(self, start, target)
		return plan, routeCost, if plan then target else nil
	end

	-- Prefer the side nearest the Warden, then test alternating angular offsets.
	-- Every candidate remains a legal Warden position within the unchanged
	-- gameplay contact radius and must have unobstructed contact to the real target.
	local approachRadius = math.max(0, contactRadius - APPROACH_TOLERANCE)
	local towardStart = flat(start) - flat(target)
	local baseAngle = if towardStart.Magnitude > 0.00001
		then math.atan2(towardStart.Z, towardStart.X)
		else 0
	local bestPlan, bestCost, bestDestination = nil, math.huge, nil
	for index = 0, APPROACH_DIRECTIONS - 1 do
		local step = math.ceil(index / 2)
		local sign = if index == 0 or index % 2 == 1 then 1 else -1
		local angle = baseAngle + sign * step * (2 * math.pi / APPROACH_DIRECTIONS)
		local destination = Vector3.new(
			target.X + math.cos(angle) * approachRadius,
			start.Y,
			target.Z + math.sin(angle) * approachRadius
		)
		if destinationStillValid(self, destination, target, contactRadius) then
			local plan, routeCost = routeTo(self, start, destination)
			if plan and routeCost < bestCost then
				bestPlan, bestCost, bestDestination = plan, routeCost, destination
			end
		end
	end
	return bestPlan, bestCost, bestDestination
end

function Navigator.Step(self: any, pivot: CFrame, target: Vector3, budget: number,
	now: number, generation: number, possession: number, phase: string, contactRadius: number): (CFrame, boolean)
	if not self.Valid then return pivot, false end
	if self.Generation ~= generation or self.Possession ~= possession or self.Phase ~= phase then
		Navigator.Clear(self)
		self.Generation, self.Possession, self.Phase = generation, possession, phase
	end
	local p = pivot.Position
	local direct = self:MovementSegmentLegal(p, target)
	self.Diagnostic.DirectSegment = if direct then "CLEAR" else "BLOCKED"
	if direct then
		self.Plan = {}
		self.MovementDestination = target
	elseif not destinationStillValid(self, self.MovementDestination, target, contactRadius)
		or now >= self.NextDecision
		or (self.Plan ~= nil and self.MovementDestination ~= nil
			and cost(self, p, self.MovementDestination, self.Plan) == math.huge) then
		local replacement, replacementCost, replacementDestination = solveWithContactApproach(
			self, p, target, contactRadius
		)
		local remaining = if destinationStillValid(self, self.MovementDestination, target, contactRadius)
			then cost(self, p, self.MovementDestination, self.Plan)
			else math.huge
		if remaining == math.huge or replacementCost <= remaining - IMPROVEMENT then
			self.Plan = replacement
			self.MovementDestination = replacementDestination
		end
		self.NextDecision = now + INTERVAL
	end
	local movementDestination = self.MovementDestination
	local remaining = if movementDestination then cost(self, p, movementDestination, self.Plan) else math.huge
	self.Diagnostic.RouteCost = if remaining < math.huge then remaining else nil
	self.Diagnostic.RouteReason = if remaining == math.huge then "UNREACHABLE"
		elseif phase == "DROPPED_CONTESTED" then "DROP_ROUTE"
		elseif direct then "DIRECT_CLEAR" else "OBSTACLE_BYPASS"
	if remaining == math.huge then
		self.Plan = nil
		self.Diagnostic.MovementTarget, self.Diagnostic.CurrentWaypoint = "NONE", "NONE"
		return pivot, false
	end
	local result = pivot
	local committedStart = pivot.Position
	-- At most 16 node transitions plus one target segment; never exceed speed * dt.
	for _ = 1, #IDS + 1 do
		local id = self.Plan[1]
		local destination = if id then self.Nodes[id] else movementDestination :: Vector3
		if not self:MovementSegmentLegal(p, destination) then self.NextDecision = 0; return result, false end
		local delta = flat(destination) - flat(p)
		local distance = delta.Magnitude
		self.Diagnostic.MovementTarget = if id then "WAYPOINT"
			elseif direct then "DIRECT_TO_TARGET" else "FINAL_TARGET_LEG"
		self.Diagnostic.CurrentWaypoint = id or "NONE"
		if distance > 0.00001 then
			local direction = delta.Unit
			local nextPosition = p + direction * math.min(budget, distance)
			-- The service commits one PivotTo per tick. Do not collapse legal
			-- waypoint subsegments into an illegal start-to-end chord.
			if not self:MovementSegmentLegal(committedStart, nextPosition) then
				break
			end
			p = nextPosition
			result = CFrame.lookAt(p, p + direction)
			budget = math.max(0, budget - distance)
		end
		if id and length(p, destination) < 0.00001 then
			table.remove(self.Plan, 1)
			self.NextDecision = 0
		else break end
		if budget <= 0 then break end
	end
	return result, true
end

return Navigator
