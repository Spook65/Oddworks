--!strict

local Players = game:GetService("Players")

local RecoveryCarrierRegistry = {}

local activeActivities: { [Player]: string } = {}
local started = false

function RecoveryCarrierRegistry.Start()
	if started then
		return
	end
	started = true
	Players.PlayerRemoving:Connect(function(player: Player)
		activeActivities[player] = nil
	end)
end

-- This registry coordinates only the one-player/one-carried-target invariant.
-- Each recovery service continues to own its own target, guardian, and rewards.
function RecoveryCarrierRegistry.TryAcquire(player: Player, activityId: string): boolean
	if player.Parent ~= Players or #activityId == 0 or activeActivities[player] ~= nil then
		return false
	end
	activeActivities[player] = activityId
	return true
end

function RecoveryCarrierRegistry.Release(player: Player, expectedActivityId: string): boolean
	if activeActivities[player] ~= expectedActivityId then
		return false
	end
	activeActivities[player] = nil
	return true
end

function RecoveryCarrierRegistry.GetActiveActivity(player: Player): string?
	return activeActivities[player]
end

return RecoveryCarrierRegistry
