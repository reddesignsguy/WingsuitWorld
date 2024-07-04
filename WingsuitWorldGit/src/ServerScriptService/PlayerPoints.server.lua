local playerService = game:GetService("Players")
local runService = game:GetService("RunService")
local replicatedStorage = game:GetService("ReplicatedStorage")
local collectionService = game:GetService("CollectionService")
local playerDataHandler = require(game.ServerScriptService:WaitForChild("PlayerDataHandler"))
local pointsModule = require(replicatedStorage:WaitForChild("PointsModule"))

-- Events
local exitedFlightMode = replicatedStorage.Events.ExitedFlightMode
local enteredFlightMode = replicatedStorage.Events.EnteredFlightMode
local enteredServerFlightMode = replicatedStorage.ClientEvents.EnteredFlightMode
local enteredRace = replicatedStorage.Events.EnteredRace
local rewardedPlayer = replicatedStorage.Events.RewardedPlayer
local updatedMultiplier = replicatedStorage.Events.UpdatedMultiplier
local flewThruLoop = replicatedStorage.Events.FlewThruLoop
local flewNearObstacle = replicatedStorage.Events.FlewNearObstacle
local flewThruCheckpoint = replicatedStorage.Events.FlewThruCheckpoint

local flyingPlayers = {} -- Holds data that persists within a flight run
-- Key: Player
-- Value:  Data

-- States:
local multipliers = { 1, 2, 4, 6, 8 } -- TODO: Move to a module script

-- References
local POINTS_HITBOX_RADIUS = 60

function loop(dt)
	for plr, data in pairs(flyingPlayers) do
		-- Update points/multipliers for player
		local pointsEarned = updatePoints(plr, dt)
		data.PointsInProgress += pointsEarned
		updateMultiplier(pointsEarned, data, dt)

		local mult = data.multiplier

		-- Update racetrack
		local racetrackData = data.racetrackData
		local index = racetrackData.nextRingIndex
		local ring = racetrackData.Rings[index]
		local beacon = ring.NextBeacon -- Beacon of the next checkpoint

		local dist = (plr.Character.PrimaryPart.Position - ring.Collider.Position).Magnitude

		local function updateTransparency(beacon, transparency)
			local cylinder = beacon.Cylinder
			for _, decal in pairs(cylinder:GetChildren()) do
				decal.Transparency = transparency
			end
		end

		local falloff = 200 -- Defines when checkpt starts to disappear(TODO: Globalize)
		local range = 250 -- Defines how long it takes after the falloff pt the checkpt completely disappears
		if dist > falloff then
			local opacity = (dist - falloff) / range
			if opacity > 1 then
				opacity = 1
			end

			local transparency = 1 - opacity + 0.15

			updateTransparency(beacon, transparency)
		else
			updateTransparency(beacon, 1)
		end

		-- Collect coins
		local char = plr.Character
		local hrp = char.HumanoidRootPart
		local hitboxRadius = 15 -- TODO: Globalize
		for _, coin: Part in pairs(collectionService:GetTagged("Coin")) do
			local dist = (coin.Position - hrp.Position).Magnitude
			if dist < hitboxRadius then
				-- Update datastore
				playerDataHandler:Increment(plr, "Coins", 1)

				-- Update leaderboards
				local leaderstatsCoins = plr.leaderstats["Coins"]
				leaderstatsCoins.Value += 1

				-- Disassemble
				collectionService:RemoveTag(coin, "Coin")
				coin:Destroy()
			end
		end
	end
end
runService.Heartbeat:Connect(loop)

-- Updates points and returns the amount of points earned from this call
function updatePoints(player, dt)
	local character = player.Character or player.CharacterAdded:Wait()
	local hrp = character.HumanoidRootPart
	local speed = hrp.AssemblyLinearVelocity.Magnitude

	-- Shoot 8 raycasts around the up axis of the player
	local raycastParams = RaycastParams.new()

	-- Ignore parts of the character
	local filterInstances = {}
	for _, part in character:GetChildren() do
		table.insert(filterInstances, part)
	end

	raycastParams.FilterDescendantsInstances = filterInstances
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude

	local baseCFrame = CFrame.new(hrp.CFrame.Position) * CFrame.fromEulerAnglesXYZ(hrp.CFrame:ToEulerAnglesXYZ())
	local numHits = 0

	local distances = {}
	for i = 0, 8, 1 do
		local octalCFrame = baseCFrame * CFrame.Angles(0, math.rad(45 * i), 0)

		local proximityCheck =
			workspace:Raycast(octalCFrame.Position, octalCFrame.RightVector * POINTS_HITBOX_RADIUS, raycastParams)

		if proximityCheck and proximityCheck.Instance.Name ~= "Collider" then
			numHits += 1
			table.insert(distances, proximityCheck.Distance)
		end
	end

	local pointsDt = 0

	if numHits > 0 then
		pointsDt += applyPointsEquation(speed, dt)
		flewNearObstacle:FireClient(player, pointsDt)
	end

	-- Flew through loop
	if numHits >= 8 then
		-- TODO: Comment
		local avg = 0
		for _, distance in pairs(distances) do
			avg += distance
		end
		avg /= 8

		-- TODO: Comment
		local tier = pointsModule.getTier(avg)
		flewThruLoop:FireClient(player, tier)
		local pointsReward = pointsModule.getPointsFromTier(tier)

		pointsDt += pointsReward
	end

	pointsDt = math.round(pointsDt)

	return pointsDt
end

function getMultiplierRequirement(multiplier: number)
	return multiplierPointRequirements[multiplier]
end

function updateMultiplier(pointsEarned, data, dt)
	-- Increase multiplier points based on points earned
	if pointsEarned ~= 0 then
		data.pointsForNextMultiplier += pointsEarned

		local multReq = getMultiplierRequirement(data.multiplier)
		if data.pointsForNextMultiplier > multReq then
			data.pointsForNextMultiplier = multReq
		end

		-- Check if we can upgrade to the next multiplier
		if data.pointsForNextMultiplier >= multReq and data.multiplier ~= 5 then
			data.multiplier += 1
			data.pointsForNextMultiplier = 0
		end

		-- Decrease multiplier points based on time not earning points
	else
		-- Check if we must go down a multiplier
		if data.pointsForNextMultiplier == 0 and data.multiplier ~= 1 then
			data.multiplier -= 1
			local requirement = getMultiplierRequirement(data.multiplier)
			data.pointsForNextMultiplier = requirement - 1 -- If we didn't do this, we risk having the player's multiplier go up  when it should go down
		end

		data.pointsForNextMultiplier -= calculateMultiplierReduction(data.pointsForNextMultiplier) * dt

		if data.pointsForNextMultiplier < 0 then
			data.pointsForNextMultiplier = 0
		end
	end
end

function calculateMultiplierReduction(points)
	-- base it off ..
	local multiplierReduction = points ^ 0.83

	-- players will be more inclined to stick to the surface (harder gameplay)
	return multiplierReduction
end

-- -=-=-=-=-=-=-=-=
function applyPointsEquation(speed, dt)
	-- TODO: Refactor to pull in actual data
	local MAX_SPEED = 300
	local multipliers = { 1 }
	local multiplierIndex = 1
	return (speed / MAX_SPEED * 100) * dt * multipliers[multiplierIndex]
end

function handleEnteredRace(plr: Player) -- TODO: Replace with "Entered Race Track Event"
	-- Init points logic
	local data = {}
	data.points = 0
	data.PointsInProgress = 0
	data.multiplier = 1
	data.pointsForNextMultiplier = 1
	data.connections = {}

	-- Init racetrack logic
	local racetrackData = {}
	racetrackData.nextRingIndex = 1
	local char = plr.Character
	local humanoid = char.Humanoid
	local hrp = char.HumanoidRootPart

	-- CONNECTIONS
	-- 1. Handle entering checkpoints
	local enteredCheckpointConnection = humanoid.Touched:Connect(function(otherPart)
		handleEnteredCheckpoint(plr, otherPart)
	end)
	table.insert(data.connections, enteredCheckpointConnection)

	-- 2. Handle collision detection
	local partCollisionConnections = setupCollisionDetection(char)
	for _, connectionOfPart in pairs(partCollisionConnections) do
		table.insert(data.connections, connectionOfPart)
	end

	-- Init the racetrack for player -- TODO: This ain't actually client-sided
	local racetrack = replicatedStorage.Racetrack
	racetrack = racetrack:Clone()
	racetrack.Parent = workspace

	racetrackData.Rings = {} -- Store refernces to client-sided racetrack
	for _, ring in racetrack.Rings:GetChildren() do
		local index = tonumber(ring.Name)
		racetrackData.Rings[index] = ring
	end

	data.racetrackData = racetrackData -- Add racetrack data
	flyingPlayers[plr] = data -- Add racetrack data for player

	-- Add coins to a collection for coin detection
	for _, coin in racetrack.Coins:GetChildren() do
		collectionService:AddTag(coin, "Coin")
	end

	-- Disconnect connections
	local function handleDeath(plr)
		local plrData = flyingPlayers[plr]
		if plrData then
			local connections = plrData.connections
			for _, connection: RBXScriptConnection in pairs(connections) do
				connection:Disconnect()
			end
			table.clear(connections)

			exitedFlightMode:FireClient(plr)
		end
	end
	plr.CharacterRemoving:Connect(function() -- TODO: Disconnect
		handleDeath(plr)
	end)

	-- Handle player respawning after dying
	local function handleRespawn(plr, char)
		local humanoid = char.Humanoid
		humanoid.Touched:Connect(function(otherPart)
			handleEnteredCheckpoint(plr, otherPart)
		end) -- Reconnect entering checkpoint detection

		local partCollisionConnections = setupCollisionDetection(char) -- Reconnect collision connection to parts
		local connections = flyingPlayers[plr].connections
		for _, connectionOfPart in pairs(partCollisionConnections) do
			table.insert(connections, connectionOfPart)
		end

		-- Move player to the last checkpoint
		local hrp = char.HumanoidRootPart
		local lastRingIndex = racetrackData.nextRingIndex - 1
		local ring = racetrackData.Rings[lastRingIndex]
		local collider = ring.Collider
		local spawnLocation = collider.CFrame.Position

		hrp.CFrame = CFrame.new(spawnLocation)

		-- Enable flight mode
		enteredFlightMode:FireClient(plr) -- client
		enteredServerFlightMode:Fire(plr) -- server
	end
	plr.CharacterAdded:Connect(function(char)
		handleRespawn(plr, char)
	end) -- TODO: Disconnect

	-- Enable flight mode
	enteredFlightMode:FireClient(plr) -- client
	enteredServerFlightMode:Fire(plr) -- server
end
enteredRace.OnServerEvent:Connect(handleEnteredRace)

--function handleExitedFlightMode(plr, crashed)
--	-- Save to datastore + leaderstats
--	if not crashed then
--		-- TODO: Replace with updating flight streak + coins

--		--local leaderstatsPoints = plr.leaderstats["Flight Points"]
--		--local points = flyingPlayers[plr].points

--		--leaderstatsPoints.Value += points
--		--playerDataHandler:Increment(plr, "FlightPoints", points)
--	end

--	-- Remove from plr from flying players
--	local index = table.find(flyingPlayers, plr)
--	if index  then
--		table.remove(flyingPlayers, index)
--	end
--end
--exitedFlightMode.OnServerEvent:Connect(handleExitedFlightMode)

function clearPointsInProgress(data)
	local temp = data["PointsInProgress"]
	data["PointsInProgress"] = 0 -- clear

	return temp
end

-- Transfers points in progress to points
function transferPIPtoPoints(data)
	data.points += clearPointsInProgress(data)
end

-- Handle player going through checkpoints
function handleEnteredCheckpoint(plr, otherPart)
	if otherPart.Name == "Collider" then
		local data = flyingPlayers[plr]
		local racetrackData = data.racetrackData

		local ring = otherPart.parent
		local num = tonumber(ring.Name)

		-- Player went thru correct ring
		-- TODO: Handle player going the wrong way
		if num == racetrackData.nextRingIndex then
			print("Went thru correct ring!")

			-- Edge: No more checkpoints left
			if racetrackData.nextRingIndex == #racetrackData.Rings then
				print("Last ring!")
				return
			end

			-- Give player the points earned from the last checkpoint up until this checkpoint
			local data = flyingPlayers[plr]
			transferPIPtoPoints(data)
			flewThruCheckpoint:FireClient(plr, data["points"])

			-- Make the next checkpoint glow yellow
			racetrackData.nextRingIndex += 1
			local index = racetrackData.nextRingIndex
			local ring = racetrackData.Rings[index]
			local beacon = ring.Beacon
			beacon:Destroy()

			local nextBeacon = replicatedStorage.Checkpoints.NextBeacon
			nextBeacon = nextBeacon:Clone()
			nextBeacon.Parent = ring
			--print(nextBeacon.Parent.Collider.Position)
			nextBeacon.Cylinder.Position = nextBeacon.Parent.Collider.Position + Vector3.new(0, 500, 0)

			-- Destroy the ring we just went thru
			local lastRing = racetrackData.Rings[index - 1]
			local lastBeacon = lastRing.NextBeacon
			lastBeacon:Destroy()
		else -- Player skipped a ring
		end
	end
end

-- Player collisions with terrain
function setupCollisionDetection(character)
	local connections = {}

	local humanoid = character:WaitForChild("Humanoid")
	for _, part in pairs(character:GetChildren()) do
		if part.ClassName == "Part" then
			local connection = part.Touched:Connect(function(part)
				handleCollision(part, humanoid)
			end)
			table.insert(connections, connection)
		end
	end

	return connections
end

function handleCollision(part, humanoid)
	if part.Name == "Terrain" and humanoid:GetState() ~= Enum.HumanoidStateType.Dead then
		humanoid.Health = 0
	end
end
