--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Effects = require(script.Parent.RecoveryFeelEffects)

local Controller = {}
local started = false
local generation = -1
local revision = 0
local destination: Part? = nil
local clue: Highlight? = nil
local trace: BillboardGui? = nil
local observing = false
local message: TextLabel

local function clearWorld()
	if destination then destination:Destroy(); destination = nil end
	if clue then clue:Destroy(); clue = nil end
	if trace then trace:Destroy(); trace = nil end
	observing = false
end

local function destinationMarker(position: Vector3)
	local anchor = Instance.new("Part")
	anchor.Name = "SignalCacheHomeCue"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanTouch = false
	anchor.CanQuery = false
	anchor.Transparency = 1
	anchor.Position = position + Vector3.new(0, 5, 0)
	anchor.Parent = Workspace
	destination = anchor
	local marker = Instance.new("BillboardGui")
	marker.Size = UDim2.fromOffset(150, 36)
	marker.AlwaysOnTop = true
	marker.Adornee = anchor
	marker.Parent = anchor
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = Color3.fromRGB(26, 40, 32)
	label.BackgroundTransparency = 0.15
	label.Text = "YOUR WORKSHOP"
	label.Font = Enum.Font.GothamBold
	label.TextSize = 15
	label.TextColor3 = Color3.fromRGB(135, 255, 180)
	label.Parent = marker
end

function Controller.Start()
	if started then return end
	started = true
	local player = Players.LocalPlayer
	local remote = ReplicatedStorage:WaitForChild("ODDWORKSNetwork"):WaitForChild("SignalCacheState") :: RemoteEvent
	local area = Workspace:WaitForChild("ODDWORKSWorld"):WaitForChild("SignalCacheArea")
	local gui = Instance.new("ScreenGui")
	gui.Name = "ODDWORKSSignalCacheGui"
	gui.ResetOnSpawn = false
	gui.Parent = player:WaitForChild("PlayerGui")
	message = Instance.new("TextLabel")
	message.Name = "Objective"
	message.AnchorPoint = Vector2.new(0.5, 1)
	message.Position = UDim2.new(0.5, 0, 1, -110)
	message.Size = UDim2.new(0.85, 0, 0, 60)
	local constraint = Instance.new("UISizeConstraint")
	constraint.MaxSize = Vector2.new(480, 60)
	constraint.Parent = message
	message.BackgroundColor3 = Color3.fromRGB(24, 35, 31)
	message.BackgroundTransparency = 0.15
	message.TextColor3 = Color3.fromRGB(185, 247, 207)
	message.Font = Enum.Font.GothamBold
	message.TextSize = 17
	message.TextWrapped = true
	message.Visible = false
	message.Parent = gui
	local function show(text: string)
		message.Text = text
		message.Visible = true
	end
	local function stopObservation()
		if not observing then return end
		revision += 1
		clearWorld()
		message.Visible = false
	end
	area:GetAttributeChangedSignal("RecoveryGeneration"):Connect(stopObservation)
	area:GetAttributeChangedSignal("SignalsActive"):Connect(function()
		if area:GetAttribute("SignalsActive") ~= true then stopObservation() end
	end)
	remote.OnClientEvent:Connect(function(payload)
		if typeof(payload) ~= "table" or typeof(payload.Generation) ~= "number"
			or payload.Generation < generation or typeof(payload.Kind) ~= "string"
			or typeof(payload.Message) ~= "string" then return end
		generation = payload.Generation
		revision += 1
		local token = revision
		clearWorld()
		show(payload.Message)
		if payload.Kind == "CHASE" and typeof(payload.Destination) == "Vector3" then
			destinationMarker(payload.Destination)
			Effects.Theft(Color3.fromRGB(160, 240, 180))
			return
		end
		if payload.Kind == "OBSERVE" and typeof(payload.CacheId) == "string" then
			if area:GetAttribute("RecoveryGeneration") ~= generation or area:GetAttribute("SignalsActive") ~= true then
				message.Visible = false
				return
			end
			local cache = area:FindFirstChild("Cache" .. payload.CacheId)
			if cache and cache:IsA("BasePart") then
				observing = true
				local highlight = Instance.new("Highlight")
				highlight.Adornee = cache
				highlight.FillTransparency = 1
				highlight.OutlineColor = Color3.fromRGB(170, 220, 205)
				highlight.FillColor = highlight.OutlineColor
				highlight.DepthMode = Enum.HighlightDepthMode.Occluded
				highlight.Parent = gui
				clue = highlight
				local strip: Frame? = nil
				if payload.Scanner == true then
					local board = Instance.new("BillboardGui")
					board.Name = "SignalRhythmTrace"
					board.Adornee = cache
					board.Size = UDim2.fromOffset(220, 54)
					board.StudsOffset = Vector3.new(0, 5, 0)
					board.MaxDistance = payload.Range
					board.AlwaysOnTop = false
					board.Parent = gui
					trace = board
					local title = Instance.new("TextLabel")
					title.Size = UDim2.new(1, 0, 0, 24)
					title.Text = "SCANNER - LIVE RHYTHM"
					title.TextSize = 13
					title.Font = Enum.Font.GothamBold
					title.TextColor3 = Color3.fromRGB(130, 245, 245)
					title.BackgroundColor3 = Color3.fromRGB(22, 40, 43)
					title.Parent = board
					local track = Instance.new("Frame")
					track.Position = UDim2.fromOffset(0, 26)
					track.Size = UDim2.new(1, 0, 0, 22)
					track.BackgroundColor3 = Color3.fromRGB(22, 40, 43)
					track.Parent = board
					strip = track
				end
				-- One bounded observation, same timing source as the world lens. No answer label.
				task.spawn(function()
					local began = Workspace:GetServerTimeNow()
					local previous = began
					while revision == token and observing do
						local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
						local now = Workspace:GetServerTimeNow()
						if not root or not root:IsA("BasePart") or (root.Position - cache.Position).Magnitude > payload.Range
							or now - began >= payload.Duration then stopObservation(); return end
						if strip then
							local elapsed = now - payload.SignalEpoch
							local cycle = math.floor(elapsed / payload.CycleSeconds)
							local on = false
							for _, onset in ipairs(payload.PulseOffsets) do
								local pulseAt = payload.SignalEpoch + cycle * payload.CycleSeconds + onset
								if now >= pulseAt and now < pulseAt + payload.PulseSeconds then on = true end
								if pulseAt > previous and pulseAt <= now then
									local tick = Instance.new("Frame")
									tick.Size = UDim2.fromOffset(3, 18)
									tick.Position = UDim2.new(math.clamp((pulseAt - began) / payload.Duration, 0, 1), 0, 0, 2)
									tick.BackgroundColor3 = Color3.fromRGB(130, 245, 245)
									tick.BorderSizePixel = 0
									tick.Parent = strip
								end
							end
							highlight.FillTransparency = if on then 0.65 else 1
							highlight.OutlineTransparency = if on then 0 else 0.65
						end
						previous = now
						task.wait(0.1)
					end
				end)
			end
			return
		elseif payload.Kind == "SECURED" then
			Effects.Secured()
			task.delay(1.2, function()
				if revision ~= token then return end
				show("CONEJURER RECOVERED")
				Effects.Revealed(Color3.fromRGB(154, 216, 169), false)
			end)
		end
		task.delay(5, function()
			if revision ~= token then return end
			clearWorld()
			message.Visible = false
		end)
	end)
	player.CharacterRemoving:Connect(function()
		revision += 1
		clearWorld()
		message.Visible = false
	end)
end

return Controller
