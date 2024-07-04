local runService = game:GetService("RunService")
local replicatedStorage = game:GetService("ReplicatedStorage")
local collectionService = game:GetService("CollectionService")
local playerDataHandler = require(game.ServerScriptService:WaitForChild("PlayerDataHandler"))
local pointsModule = require(replicatedStorage:WaitForChild("PointsModule"))
local Constants = require(replicatedStorage.Constants)

-- Events
local exitedFlightMode = replicatedStorage.Events.ExitedFlightMode
local enteredFlightMode = replicatedStorage.Events.EnteredFlightMode
local enteredServerFlightMode = replicatedStorage.ClientEvents.EnteredFlightMode
local enteredRace = replicatedStorage.Events.EnteredRace
local flewThruLoopEvent = replicatedStorage.Events.FlewThruLoop
local flewNearObstacle = replicatedStorage.Events.FlewNearObstacle
local flewThruCheckpoint = replicatedStorage.Events.FlewThruCheckpoint

-- Imports
local MAX_SPEED = Constants.MAX_SPEED

-- Constants
local POINTS_HITBOX_RADIUS = 60
local COINS_HITBOX_RADIUS = 15

-- Contains data for players who are currently racing.. Used for the racing game loop
type flyingPlayer = {
	points: number,
	PointsInProgress: number,
	multiplier: number,
	connections: { connection: RBXScriptConnection },
	racetrackData: {
		nextRingIndex: number,
		Rings: { index: number },
	},
}
local flyingPlayers: { flyingPlayer } = {}

--[[ 
	Loops through each player in the race and updates important data like:
        - Points earned
		- Coins collected
		- Visuals of the racetrack

	@param dt  float  loop will be called every heartbeat
--]]
function loop(dt)
	for plr, racingData in pairs(flyingPlayers) do
		-- Update points for player
		local obsData = getNearbyObstacleData(plr)
		local pointsEarned = updatePoints(plr, obsData, dt)
		racingData.PointsInProgress += pointsEarned

		collectNearbyCoins(plr)

		-- Update racetrack
		local racetrackData = racingData.racetrackData
		local index = racetrackData.nextRingIndex
		local ring = racetrackData.Rings[index]
		updateRacetrack(plr, ring)
	end
end
runService.Heartbeat:Connect(loop)

--[[ 
	Sets up gameplay logic for a player entering a race like:
	- Flying
	- Collision detection
	- Earning points

	@param dt  float  loop will be called every heartbeat
--]]
function handleEnteredRace(plr: Player)
	-- Init points logic
	local data: flyingPlayer = {}
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

	-- Init the racetrack for player -- TODO: This ain't actually client-sided, move to client
	local racetrack = replicatedStorage.Racetrack
	racetrack = racetrack:Clone()
	racetrack.Parent = workspace

	racetrackData.Rings = {} -- Store refernces to client-sided racetrack
	for _, ring in racetrack.Rings:GetChildren() do
		local index = tonumber(ring.Name)
		racetrackData.Rings[index] = ring
	end
	data.racetrackData = racetrackData
	flyingPlayers[plr] = data -- Add racetrack data for player

	-- Handle character being removed right before dying
	plr.CharacterRemoving:Connect(function()
		handleDeath(plr) -- TODO: Disconnect
	end)

	-- Handle character respawning after dying
	plr.CharacterAdded:Connect(function(char)
		handleRespawn(plr, char)
	end) -- TODO: Disconnect

	-- Enable flight mode
	enteredFlightMode:FireClient(plr) -- client
	enteredServerFlightMode:Fire(plr) -- server

	-- Allows coins in race to be collected
	for _, coin in racetrack.Coins:GetChildren() do
		collectionService:AddTag(coin, "Coin")
	end
end
enteredRace.OnServerEvent:Connect(handleEnteredRace)

function handleRespawn(plr, char)
	local humanoid = char.Humanoid
	humanoid.Touched:Connect(function(otherPart)
		handleEnteredCheckpoint(plr, otherPart)
	end) -- Reconnect entering checkpoint detection

	-- Reconnect collision detections to parts
	local partCollisionConnections = setupCollisionDetection(char)
	local connections = flyingPlayers[plr].connections
	for _, connectionOfPart in pairs(partCollisionConnections) do
		table.insert(connections, connectionOfPart)
	end

	-- Move player to the last checkpoint
	local racetrackData = flyingPlayers[plr].racetrackData
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

function handleDeath(plr)
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

function collectNearbyCoins(plr)
	local char = plr.Character
	local hrp = char.HumanoidRootPart

	for _, coin: Part in pairs(collectionService:GetTagged("Coin")) do
		local dist = (coin.Position - hrp.Position).Magnitude
		if dist < COINS_HITBOX_RADIUS then
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

function updateRacetrack(plr, checkpoint)
	local beacon = checkpoint.NextBeacon

	local dist = (plr.Character.PrimaryPart.Position - checkpoint.Collider.Position).Magnitude
	local falloff = 200 -- Defines when checkpt starts to disappear(TODO: Globalize)
	local range = 250 -- Defines how long it takes after the falloff pt the checkpt completely disappears
	local playerIsFarAway = dist > falloff

	if playerIsFarAway then
		local opacity = (dist - falloff) / range
		if opacity > 1 then
			opacity = 1
		end

		local transparency = 1 - opacity + 0.15

		updateTransparency(beacon, transparency)
	else
		updateTransparency(beacon, 1)
	end
end

function updateTransparency(beacon, transparency)
	local cylinder = beacon.Cylinder
	for _, decal in pairs(cylinder:GetChildren()) do
		decal.Transparency = transparency
	end
end

--[[
	Returns data from any nearby obstacles/terrain to a player including:
	- Distance to the terrain

	@param plr  Player  Function checks the surrounding area of the plr
--]]
function getNearbyObstacleData(plr)
	local character = plr.Character or plr.CharacterAdded:Wait()
	local hrp = character.HumanoidRootPart

	-- Prepare raycasting
	local raycastParams = RaycastParams.new()

	-- EDGE-CASE: Raycasts ignore the parts of the character
	local filterInstances = {}
	for _, part in character:GetChildren() do
		table.insert(filterInstances, part)
	end
	raycastParams.FilterDescendantsInstances = filterInstances
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude

	-- Shoot 8 raycasts around the up axis of the player
	local baseCFrame = CFrame.new(hrp.CFrame.Position) * CFrame.fromEulerAnglesXYZ(hrp.CFrame:ToEulerAnglesXYZ())

	local distances = {}
	for i = 0, 8, 1 do
		local octalCFrame = baseCFrame * CFrame.Angles(0, math.rad(45 * i), 0)

		local proximityCheck =
			workspace:Raycast(octalCFrame.Position, octalCFrame.RightVector * POINTS_HITBOX_RADIUS, raycastParams)

		if proximityCheck and proximityCheck.Instance.Name ~= "Collider" then
			table.insert(distances, proximityCheck.Distance)
		end
	end

	return distances
end

-- Updates points and returns the amount of points earned from this call
function updatePoints(plr, nearbyObstacleData, dt)
	local pointsDt = 0

	local numHits = #nearbyObstacleData

	-- Reward player for flying near obstacles
	local isNearAnObstacle = numHits > 0
	if isNearAnObstacle then
		local character = plr.Character or plr.CharacterAdded:Wait()
		local hrp = character.HumanoidRootPart
		local speed = hrp.AssemblyLinearVelocity.Magnitude

		pointsDt += applyPointsEquation(speed, dt)
		flewNearObstacle:FireClient(plr, pointsDt)
	end

	-- Reward player for flying through loops or tight spaces
	local flewThruLoop = numHits >= 8
	if flewThruLoop then
		local score = 0 -- The lower the score, the better
		for _, distance in pairs(nearbyObstacleData) do
			score += distance
		end
		score /= 8

		local tier = pointsModule.getTier(score)
		flewThruLoopEvent:FireClient(plr, tier)
		local pointsReward = pointsModule.getPointsFromTier(tier)

		pointsDt += pointsReward
	end

	pointsDt = math.round(pointsDt)
	return pointsDt
end

function applyPointsEquation(speed: number, dt: number)
	return (speed / MAX_SPEED * 100) * dt
end

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
		local ringNum = tonumber(ring.Name)

		local wentThruCorrectCheckpt = ringNum == racetrackData.nextRingIndex
		if wentThruCorrectCheckpt then
			-- EDGE-CASE: No more checkpoints left
			if racetrackData.nextRingIndex == #racetrackData.Rings then
				print("Last ring!")
				return
			end

			-- Give player the points earned from the last checkpoint up until this checkpoint
			local data = flyingPlayers[plr]
			transferPIPtoPoints(data)
			flewThruCheckpoint:FireClient(plr, data["points"])

			-- Destroy the checkpoint the player has passed
			racetrackData.nextRingIndex += 1
			local index = racetrackData.nextRingIndex
			local ring = racetrackData.Rings[index]
			local beacon = ring.Beacon
			beacon:Destroy()

			-- Replace the next checkpoint's beacon with one that is yellow
			local yellowBeacon = replicatedStorage.Checkpoints.NextBeacon
			yellowBeacon = yellowBeacon:Clone()
			yellowBeacon.Parent = ring
			yellowBeacon.Cylinder.Position = yellowBeacon.Parent.Collider.Position + Vector3.new(0, 500, 0)

			-- Destroy the ring we just went thru
			local lastRing = racetrackData.Rings[index - 1]
			local lastBeacon = lastRing.NextBeacon
			lastBeacon:Destroy()
		end
	end
end

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

function handleCollision(collidingPart, humanoid)
	if collidingPart.Name == "Terrain" and humanoid:GetState() ~= Enum.HumanoidStateType.Dead then
		humanoid.Health = 0
	end
end

-- local multipliers = { 1, 2, 4, 6, 8 } -- TODO: Move to a module script

--[[
function handleExitedFlightMode(plr, crashed)
	-- Save to datastore + leaderstats
	if not crashed then
		-- TODO: Replace with updating flight streak + coins

		--local leaderstatsPoints = plr.leaderstats["Flight Points"]
		--local points = flyingPlayers[plr].points

		--leaderstatsPoints.Value += points
		--playerDataHandler:Increment(plr, "FlightPoints", points)
	end

	-- Remove from plr from flying players
	local index = table.find(flyingPlayers, plr)
	if index  then
		table.remove(flyingPlayers, index)
	end
end
exitedFlightMode.OnServerEvent:Connect(handleExitedFlightMode)
--]]

--[[
function getMultiplierRequirement(multiplier: number)
	return multiplierPointRequirements[multiplier]
end
--]]

--[[
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
--]]

--[[
function calculateMultiplierReduction(points)
	-- base it off ..
	local multiplierReduction = points ^ 0.83

	-- players will be more inclined to stick to the surface (harder gameplay)
	return multiplierReduction
end
--]]
