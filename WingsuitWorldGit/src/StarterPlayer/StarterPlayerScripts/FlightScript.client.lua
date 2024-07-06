-- =-=-=-=-=-=-=-=-=-= Imports -=-=-=-=-=-=-=-=-=-=-=-
local uis = game:GetService("UserInputService")
local runService = game:GetService("RunService")
local replicatedStorage = game:GetService("ReplicatedStorage")
local serverScriptService = game:GetService("ServerScriptService")
local players = game:GetService("Players")
local constants = require(replicatedStorage.Constants)
local pointsModule = require(replicatedStorage:WaitForChild("PointsModule"))

-- Events
local exitedFlightModeEvent = replicatedStorage.Events.ExitedFlightMode
local enteredFlightModeEvent = replicatedStorage.Events.EnteredFlightMode

-- References
local targetVelocityUnit = nil -- Used to check stalling
local plr: Player = players.LocalPlayer
local playerGui = plr:FindFirstChild("PlayerGui")
local character = plr.Character or plr.CharacterAdded:Wait()
local humanoid: Humanoid = character:WaitForChild("Humanoid")
local hrp = humanoid.RootPart
local parts = {}
local vectorVisuals = {} -- TODO: Remove in prod

--=-=-=-=-=-==-=-= Development and Parameters -=-=-=-=-=-=-=-=-=-=-=
-- Debugging
local showVectorVisuals = false
local lateralMobility = nil

-- States
local flightMode = false
local heartbeatLoop = nil

-- Physics references
local alignOrientation: AlignOrientation = nil
local maintainFlight: Vector3 = nil
local verticalWeight = 0
local breakPercentage = 0

-- local POINTS_HITBOX_RADIUS = 60 -- TODO: Testing the hitbox radius for earning points, Remove in prod
local lastBodyVelocity = nil -- for calculating acceleration; used for detecting stall

-- Physics parameters
local MAX_SPEED = constants.MAX_SPEED
local GRAVITY = 70 -- 160 gravity, 0.001 air density
local AoA = 12.5 -- degrees
local liftCoefficient = 0.5
local LIFT_BOOST = 4.5 ^ 2 -- Higher = the more maneuvarabilty, but slows down horizontal speed faster -> less transfer to vertical height momentum
local LIFT_BASE_BOOST_NEW = 3.0
local ALIGN_ORIENTATION_MAX_TORQUE = 100000
local ALIGN_ORIENTATION_RESPONSIVENESS = 50
local TURN_FORCE_MAGNITUDE = 2200
local BASE_TURN_FORCE_MAGNITUDE = 3000
local DOWN_BOOST = 500
local BASE_DOWN_BOOST = 500
local PITCH_DEGREES_OF_FREEDOM = 80 -- Controls the maximuim degrees of freedom on one side of the axis of pitch []

local keysActive = {
	[Enum.KeyCode.W] = false,
	[Enum.KeyCode.S] = false,
	[Enum.KeyCode.A] = false,
	[Enum.KeyCode.D] = false,
	[Enum.KeyCode.Space] = false,
}

-- Starts the loop
function start()
	-- Reset references
	character = plr.Character or plr.CharacterAdded:Wait()
	humanoid = character:WaitForChild("Humanoid")
	hrp = humanoid.RootPart

	-- Teleport character to the sky
	flightMode = true
	workspace.Gravity = GRAVITY
	setupForces()

	playerGui.Gui.Enabled = true -- Set up gui

	heartbeatLoop = runService.Heartbeat:Connect(loop)

	-- TODO: =-=-=-=-=-=-=-=-=- Remove in prod (DEBUGGING) -=-=-=-=-=-=-=-=-=-=-=-=
	-- if showVectorVisuals then
	-- 	setupVectorVisuals()
	-- end

	-- Visualize the player's points hitbox
	-- local pointsHitBox = Instance.new("Part")
	-- pointsHitBox.Shape = Enum.PartType.Ball
	-- pointsHitBox.Parent = hrp
	-- pointsHitBox.Name = "PointsHitBox"
	-- pointsHitBox.Transparency = 0.9
	-- pointsHitBox.Color = Color3.new(1, 0.881743, 0.0887922)
	-- pointsHitBox.Size = Vector3.new(POINTS_HITBOX_RADIUS * 2, POINTS_HITBOX_RADIUS * 2, POINTS_HITBOX_RADIUS * 2)
	-- pointsHitBox.Massless = true
	-- pointsHitBox.CastShadow = false
	-- pointsHitBox.CanCollide = false
	-- pointsHitBox.Material = Enum.Material.SmoothPlastic
end
enteredFlightModeEvent.OnClientEvent:Connect(start)

-- Stops the loop
function stop(crashed)
	resetState()

	-- instances
	destroyForces()
	destroyVectorVisuals()

	-- turn off gui
	playerGui.Gui.Enabled = false
end
exitedFlightModeEvent.OnClientEvent:Connect(stop)

function resetState()
	flightMode = false

	-- Reset physics
	workspace.Gravity = 196.2

	-- Disconnect connections
	if heartbeatLoop then
		heartbeatLoop:Disconnect()
	end
	heartbeatLoop = nil
end

function loop(dt: number)
	if flightMode then
		-- TODO: Testing optimal lateral mobility, Remove in prod
		if lateralMobility == nil then
			-- lateralMobility = plr.PlayerGui.DevGui.DevGuiFrame.LateralMobility.Value
			lateralMobility = Instance.new("IntValue")
			lateralMobility.Value = 400
		end

		-- -=-=-=-=-=-=-=- Vector/Angle references -=-=-=-=-=-=-=-
		local bodyMovement = hrp.AssemblyLinearVelocity
		local speed = bodyMovement.Magnitude
		local movementDirection = bodyMovement.Unit -- unit vector of player's velocity direction
		local headingVector = hrp.CFrame.UpVector.Unit
		local velocityToHeadingAngle = math.deg(math.acos(movementDirection:Dot(headingVector))) -- angle between

		local movementY = Vector3.new(movementDirection.X, movementDirection.Y, 0).Unit
		local headingY = Vector3.new(headingVector.X, headingVector.Y, 0).Unit
		local yAng = math.deg(math.acos(movementY:Dot(headingY)))

		local velocityToHeadingCross = movementY:Cross(headingY)
		--local headingIsAboveVelocity = velocityToHeadingCross.Z > 0 -- direction relative to heading
		local headingIsAboveVelocity = headingY.Y > movementY.Y

		---=-=-=-=-=-=-=-= Handle keyboard state -=-=-=-=-=-=-=-=-=-=

		--[[
			Note: Player heading vector and alignOrientation up vector are the same. Use commands below to see.
			
			print("heading: " .. tostring(headingVector))
			print("orientation: " .. tostring(alignOrientation.CFrame.UpVector))
		]]
		--

		--
		local bufferAngle = math.rad(1.0)

		local movementDirectionCFrame = CFrame.new(Vector3.new(), movementDirection)
			* CFrame.Angles(-math.rad(90), 0, 0)

		alignOrientation.CFrame = movementDirectionCFrame
		local breakingOrientationAngle = 45
		if isBreaking() then
			alignOrientation.CFrame *= CFrame.Angles(math.rad(breakingOrientationAngle), 0, 0)
		end

		-- TODO: Testing: A weight variable that determines the percentage of the lift force that should be applied
		local minimum = 0.5
		local decay = 0.5 -- per sec
		local growth = 2.0 -- per sec
		if keysActive[Enum.KeyCode.S] and verticalWeight < 1 then
			verticalWeight += growth * dt -- full flight is achiveved in 2 secs
		elseif verticalWeight > minimum then
			verticalWeight -= decay * dt

			if verticalWeight < minimum then
				verticalWeight = minimum
			end
		end

		--=-=-=-=-=-=-= Handle rotations -=-=-=-=-=-=-=-=-=-=-
		if keysActive[Enum.KeyCode.W] and not playerPitchTooLow() then
			alignOrientation.CFrame *= CFrame.Angles(-math.rad(AoA + bufferAngle), 0, 0)
		elseif keysActive[Enum.KeyCode.S] and not playerPitchTooHigh() then
			alignOrientation.CFrame *= CFrame.Angles(math.rad(AoA - bufferAngle), 0, 0)
		end

		if keysActive[Enum.KeyCode.A] then
			alignOrientation.CFrame *= CFrame.Angles(0, 0, math.rad(AoA - bufferAngle))
		elseif keysActive[Enum.KeyCode.D] then
			alignOrientation.CFrame *= CFrame.Angles(0, 0, -math.rad(AoA - bufferAngle))
		end

		-- -=--=-=-=-=-=-=-=-= Apply aerodynamic forces -=-=-=-=-=-=-=-=-=-=-=-
		local breakMin = 0.5
		local breakDecay = 0.5 -- per sec
		local breakGrowth = 2.0 -- per sec
		if isBreaking() and breakPercentage < 1 then
			breakPercentage += breakGrowth * dt -- full flight is achiveved in 2 secs
		elseif breakPercentage > minimum then
			breakPercentage -= breakDecay * dt

			if breakPercentage < breakMin then
				breakPercentage = breakMin
			end
		end

		local density = 0.32
		for _, data in parts do
			data.NetForce.Force = Vector3.new(0, 0, 0) -- Reset force for each part

			-- Turning up and down settings for breaking and gliding
			if isBreaking() then
				--  Break magnitude
				local area = 0.05
				local breakMag = liftCoefficient * (0.5 * density * math.pow(bodyMovement.Magnitude, 2) * area)
				data.NetForce.Force += -hrp.CFrame.LookVector * breakMag * breakPercentage -- keybinds affect orientation
			else
				--  Lift magnitude
				local area = 0.1
				local liftMag = liftCoefficient * (0.5 * density * math.pow(bodyMovement.Magnitude, 2) * area)

				-- Turn down
				if keysActive[Enum.KeyCode.W] and not playerPitchTooLow() then
					data.NetForce.Force += alignOrientation.CFrame.LookVector * liftMag
					maintainFlight = bodyMovement

				-- Turn up
				elseif keysActive[Enum.KeyCode.S] and not playerPitchTooHigh() then
					data.NetForce.Force += -hrp.CFrame.LookVector * liftMag * LIFT_BASE_BOOST_NEW * verticalWeight -- keybinds affect orientation
					maintainFlight = bodyMovement

				-- Maintain altitude
				elseif maintainFlight ~= nil and bodyMovement.Y < maintainFlight.Y then
					data.NetForce.Force += -hrp.CFrame.LookVector * liftMag
				end
			end

			-- Turn left and right
			if keysActive[Enum.KeyCode.A] then
				data.NetForce.Force += -hrp.CFrame.RightVector * lateralMobility.Value
			elseif keysActive[Enum.KeyCode.D] then
				data.NetForce.Force += hrp.CFrame.RightVector * lateralMobility.Value
			end
		end

		-- -=-=-=-=-=-=-=-=-= Check max speed -=-=-=-=-=-=-=-=-=-=
		if speed > MAX_SPEED then
			local reducer = MAX_SPEED / speed
			hrp.AssemblyLinearVelocity = hrp.AssemblyLinearVelocity * reducer
		end

		-- Check for stall (can happen whether or not the player is pressing anything)
		if isStalling(bodyMovement, dt) then
			local downwardsMovementDirectionCFrame = movementDirectionCFrame
			downwardsMovementDirectionCFrame *= CFrame.Angles(-math.rad(70), 0, 0)
			targetVelocityUnit = downwardsMovementDirectionCFrame.UpVector
		end
		-- TODO: -=-=-=-=-=-=-=-=-= Debugging -=-=-=-=-=-=-=-=-=-=
		-- if showVectorVisuals then
		-- 	updateVisuals()
		-- end

		--drawPoints()
		--drawMultiplier()
	end
end

function isTurning()
	return keysActive[Enum.KeyCode.A] or keysActive[Enum.KeyCode.D]
end

function isPitching()
	return keysActive[Enum.KeyCode.W] or keysActive[Enum.KeyCode.S]
end

function isBreaking()
	return keysActive[Enum.KeyCode.Space]
end

function getAngleBetween(vector1, vector2)
	return math.deg(math.acos(vector1:Dot(vector2)))
end

function playerPitchTooHigh()
	-- check if it's within the max degrees of freedom
	local velocityUnit = hrp.CFrame.UpVector
	local groundVector = velocityUnit * Vector3.new(1, 0, 1)
	local pitchAngle = getAngleBetween(velocityUnit, groundVector)
	if pitchAngle < PITCH_DEGREES_OF_FREEDOM then
		return false
	end

	-- at this point, the pitch angle exceeds the max degrees of freedom
	-- so check if it's because the player is too high or too low
	local direction = velocityUnit:Cross(groundVector).Z -- a negative value means the player is too high
	return direction < 0
end

function playerPitchTooLow()
	-- check if it's within the max degrees of freedom
	local velocityUnit = hrp.CFrame.UpVector
	local groundVector = velocityUnit * Vector3.new(1, 0, 1)
	local pitchAngle = getAngleBetween(velocityUnit, groundVector)

	if pitchAngle < PITCH_DEGREES_OF_FREEDOM then
		return false
	end

	-- at this point, the pitch angle exceeds the max degrees of freedom
	-- so check if it's because the player is too high or too low
	local direction = velocityUnit:Cross(groundVector).Z -- a negative value means the player is too high
	return direction > 0
end

function adjustedDownBoost(speed)
	local newDownBoost = BASE_DOWN_BOOST + (1 - speed / MAX_SPEED) * DOWN_BOOST
	return newDownBoost
end

-- Turning force adjusted to the player's speed
function adjustedTurningForce(speed)
	--local newTurnForce = BASE_TURN_FORCE_MAGNITUDE + TURN_FORCE_MAGNITUDE / math.log(speed, 6) -- works
	local newTurnForce = BASE_TURN_FORCE_MAGNITUDE + TURN_FORCE_MAGNITUDE / math.pow(speed, 0.3) -- new

	return newTurnForce
end

-- Lift boost adjusted to the player's speed
function adjustedLiftBoost(speed)
	local newLiftBoost = LIFT_BOOST / math.pow(speed, 0.3) -- works
	--print(newLiftBoost)
	return newLiftBoost
end

function isStalling(bodyVelocity: Vector3, dt: number)
	if lastBodyVelocity == nil then -- initial bodyVelocity
		lastBodyVelocity = bodyVelocity
		return
	end

	local acceleration = (bodyVelocity.Y - lastBodyVelocity.Y) * dt

	lastBodyVelocity = bodyVelocity -- update change w/ respects to dt

	if -1 < bodyVelocity.Y and bodyVelocity.Y < 1 and acceleration < 0 then -- Player is stalling if the velocity hits 0 and acceleration is negative
		return true
	end

	return false
end

-- Apply forces to all parts of model
function setupForces()
	for i, v in pairs(character:GetChildren()) do
		if v.ClassName == "Part" then
			-- TODO: Adjust in prod
			--local animationPart : Part = v:Clone() -- make a clone of the character's limbs which will be used for animation
			--animationPart.Parent = character
			--animationPart.Name = "Animation" .. tostring(v.Name)
			--v.Transparency = 1

			-- Make attachment for gravity to apply to
			local attachment = Instance.new("Attachment")
			local attachment1 = Instance.new("Attachment", v)
			attachment.Parent = v
			attachment.Position = Vector3.new(0, 0, 0)
			attachment.Name = "ForceAttachment"
			attachment1.Name = "Attachment1"

			-- Make gravity
			local netForce = Instance.new("VectorForce")
			netForce.Name = "NetForce"
			netForce.Force = Vector3.new(0, 0, 0)
			netForce.RelativeTo = "World"

			netForce.Parent = v
			netForce.Attachment0 = attachment
			netForce.Enabled = true

			-- Visualize this force
			local beam = Instance.new("Beam")
			beam.Name = "VectorVisual"
			beam.FaceCamera = true
			beam.Segments = 1
			beam.Width0 = 0.2
			beam.Width1 = 0.2
			beam.Color = ColorSequence.new(Color3.new(1, 0, 0))
			beam.Attachment0 = attachment
			beam.Attachment1 = attachment1
			beam.Parent = v

			-- Make the part aerdynamic
			v.EnableFluidForces = true

			-- Save a reference to this part
			table.insert(parts, {
				Part = v,
				ForceAttachment = attachment,
				Attachment1 = attachment1,
				NetForce = netForce,
				Beam = beam,
			})
		end
	end

	-- Use alignOrientation to control pitch of player
	alignOrientation = Instance.new("AlignOrientation")
	alignOrientation.CFrame = hrp.CFrame
	alignOrientation.Mode = Enum.OrientationAlignmentMode.OneAttachment
	alignOrientation.Attachment0 = hrp.ForceAttachment
	alignOrientation.Parent = hrp
	alignOrientation.MaxTorque = ALIGN_ORIENTATION_MAX_TORQUE
	alignOrientation.Responsiveness = ALIGN_ORIENTATION_RESPONSIVENESS
	alignOrientation.AlignType = Enum.AlignType.AllAxes
end

function destroyForces()
	for _, data in pairs(parts) do
		data.ForceAttachment:Destroy()
		data.Attachment1:Destroy()
		data.Beam:Destroy()
		data.NetForce:Destroy()
	end
	table.clear(parts)

	local alignOrientation = hrp:FindFirstChild("AlignOrientation")
	alignOrientation:Destroy()
end

function destroyVectorVisuals()
	for _, data in pairs(vectorVisuals) do
		data.beam:Destroy()
		data.Attachment0:Destroy()
		data.Attachment1:Destroy()
	end
	table.clear(vectorVisuals)
end

-- Debugging
function setupVectorVisuals()
	local tempVectorVisuals = {}
	-- Initialize visuals
	local velocityVisual = Instance.new("Beam")
	velocityVisual.Name = "VelocityVisual"
	velocityVisual.Color = ColorSequence.new(Color3.new(1, 1, 0))
	table.insert(tempVectorVisuals, velocityVisual)

	local HeadingVisual = Instance.new("Beam")
	HeadingVisual.Name = "HeadingVisual"
	HeadingVisual.Color = ColorSequence.new(Color3.new(0.179583, 0.675776, 0.996979))
	table.insert(tempVectorVisuals, HeadingVisual)

	local alignOrientationVisual = Instance.new("Beam")
	alignOrientationVisual.Name = "alignOrientationVisual"
	alignOrientationVisual.Color = ColorSequence.new(Color3.new(0.675334, 0.97528, 0.336172))
	table.insert(tempVectorVisuals, alignOrientationVisual)

	local TargetVelocityVisual = Instance.new("Beam")
	TargetVelocityVisual.Name = "TargetVelocityVisual"
	TargetVelocityVisual.Color = ColorSequence.new(Color3.new(0.917281, 1, 0.926604))
	table.insert(tempVectorVisuals, TargetVelocityVisual)

	-- Set up visuals
	for i, beam in ipairs(tempVectorVisuals) do
		local attachment = Instance.new("Attachment")
		local attachment1 = Instance.new("Attachment", humanoid.RootPart)
		attachment.Parent = humanoid.RootPart
		attachment.Position = Vector3.new(0, 0, 0)

		beam.FaceCamera = true
		beam.Segments = 1
		beam.Width0 = 0.2
		beam.Width1 = 0.2
		beam.Attachment0 = attachment
		beam.Attachment1 = attachment1
		beam.Parent = humanoid.RootPart

		local beamName = beam.Name
		table.insert(vectorVisuals, {
			beam = beam,
			Attachment0 = attachment,
			Attachment1 = attachment1,
		})
	end
end

-- Checks if at least one key is being perssed
function atLeastOneKeyPressed()
	for key, value in pairs(keysActive) do
		if value == true then
			return true
		end
	end

	return false
end

-- Checks if at least one key is being perssed
function atLeastOnePitchKeyPressed()
	if keysActive[Enum.KeyCode.W] or keysActive[Enum.KeyCode.S] then
		return true
	end

	return false
end

uis.InputBegan:Connect(function(input, gameProcessedEvent)
	if input.KeyCode == Enum.KeyCode.W then
		keysActive[Enum.KeyCode.W] = true
	elseif input.KeyCode == Enum.KeyCode.S then
		keysActive[Enum.KeyCode.S] = true
	elseif input.KeyCode == Enum.KeyCode.D then
		keysActive[Enum.KeyCode.D] = true
	elseif input.KeyCode == Enum.KeyCode.A then
		keysActive[Enum.KeyCode.A] = true
	elseif input.KeyCode == Enum.KeyCode.Space then
		keysActive[Enum.KeyCode.Space] = true
	end
end)

uis.InputEnded:Connect(function(input, gameProcessedEvent)
	if input.KeyCode == Enum.KeyCode.W then
		keysActive[Enum.KeyCode.W] = false
	elseif input.KeyCode == Enum.KeyCode.S then
		keysActive[Enum.KeyCode.S] = false
	elseif input.KeyCode == Enum.KeyCode.D then
		keysActive[Enum.KeyCode.D] = false
	elseif input.KeyCode == Enum.KeyCode.A then
		keysActive[Enum.KeyCode.A] = false
	elseif input.KeyCode == Enum.KeyCode.Space then
		keysActive[Enum.KeyCode.Space] = false
	end
end)

plr.CharacterAdded:Connect(function()
	resetState()

	-- instances
	destroyForces()
	destroyVectorVisuals()

	start()
end)
----------------------- DEBUGGING -----------------------
-- Debugging
function updateVisuals()
	-- Visualize the force vectors in 3D spacing using a rectangular cube
	if flightMode then
		-- Update vector sizes
		for i, part in parts do
			assert(part.Attachment1 and part.ForceAttachment and part.NetForce)
			part.Attachment1.WorldPosition = part.ForceAttachment.WorldPosition + part.NetForce.Force / 40
		end

		-- Visualize vectors
		local velocityVis = humanoid.RootPart.VelocityVisual
		local headingVis = humanoid.RootPart.HeadingVisual
		local alignOrientationVis = humanoid.RootPart.alignOrientationVisual
		local targetVelocityVis = humanoid.RootPart.TargetVelocityVisual

		if velocityVis and headingVis and alignOrientationVis then
			velocityVis.Attachment1.WorldPosition = velocityVis.Attachment0.WorldPosition
				+ hrp.AssemblyLinearVelocity.Unit * 5
			--headingVis.Attachment1.WorldPosition = headingVis.Attachment0.WorldPosition + hrp.CFrame.UpVector.Unit * 5
			alignOrientationVis.Attachment1.WorldPosition = alignOrientationVis.Attachment0.WorldPosition
				+ alignOrientation.CFrame.UpVector.Unit * 5
		end

		if targetVelocityVis and maintainFlight then
			targetVelocityVis.Attachment1.WorldPosition = targetVelocityVis.Attachment0.WorldPosition
				+ maintainFlight.Unit * 5
		end

		-- Visualize points hitbox
		assert(hrp.PointsHitBox)
		hrp.PointsHitBox.CFrame = hrp.CFrame
	end
end

--function drawMultiplier()
--	-- Init
--	if not playerGui then
--		playerGui = plr:FindFirstChild("PlayerGui")
--		return
--	end

--	if not multiplierLabel or not multiplierBarFrame or not multiplierHealthFrame then
--		multiplierBarFrame = playerGui.Gui.MultiplierBar
--		multiplierHealthFrame = playerGui.Gui.MultiplierHealth
--		multiplierLabel = playerGui.Gui.Multiplier
--		return
--	end

--	multiplierLabel.Text = tostring(multipliers[multiplierIndex]) .. "x" -- Draw current multiplier

--	-- Draw health bar
--	local percentage = pointsForNextMultiplier / pointsForNextMultiplierRequirement
--	local xSize = percentage * multiplierBarFrame.Size.X.Offset
--	local ySize = multiplierBarFrame.Size.Y.Offset
--	multiplierHealthFrame.Size = UDim2.new(0, xSize, 0, ySize)
--end
