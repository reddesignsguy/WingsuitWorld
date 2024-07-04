local replicatedStorage = game:GetService("ReplicatedStorage")

-- Events
local enteredServerFlightMode = replicatedStorage.ClientEvents.EnteredFlightMode

-- References
local collisionConnections = {} -- "Touched" connections of player

-- Updates a player's character to be in flight mode
function setupFlight(plr)
	local character = plr.Character or plr.CharacterAdded:Wait()
	local humanoid = character:WaitForChild("Humanoid")
	local hrp = character.HumanoidRootPart

	hrp.CFrame = hrp.CFrame + Vector3.new(0, 100, 0) -- TODO: Remove in prod
	humanoid:ChangeState(Enum.HumanoidStateType.Physics)
	humanoid.RootPart.CFrame *= CFrame.Angles(math.rad(-50), 0, 0)
end
enteredServerFlightMode.Event:Connect(setupFlight)
