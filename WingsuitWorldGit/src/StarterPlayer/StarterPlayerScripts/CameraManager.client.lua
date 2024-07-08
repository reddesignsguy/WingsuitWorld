local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local replicatedStorage = game:GetService("ReplicatedStorage")

local physicsCalculator = require(replicatedStorage.PhysicsCalculator)
local constants = require(replicatedStorage.Constants)
local cameraShaker = require(replicatedStorage.CameraShaker)

-- Events
local exitedFlightModeClientEvent = replicatedStorage.ClientEvents.ExitedFlightMode
local enteredFlightModeClientEvent = replicatedStorage.ClientEvents.EnteredFlightMode
local enteredFlightMode = replicatedStorage.Events.EnteredFlightMode
local exitedFlightModeEvent = replicatedStorage.Events.ExitedFlightMode

-- TODO: Globalize activeKeys in another script -=-=-=
local uis = game:GetService("UserInputService")
local keysActive = {
	[Enum.KeyCode.W] = false,
	[Enum.KeyCode.S] = false,
	[Enum.KeyCode.A] = false,
	[Enum.KeyCode.D] = false,
}
-- TODO: -=-=-=-=-=-=-=-=-=-=-=

local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local camera = workspace.CurrentCamera
camera.FieldOfView = 100

local MAX_SPEED = constants.MAX_SPEED
local MAX_OBSERVED_LIFT = 400 -- changing this does not affect the max lift player can gain
local MIN_CAMERA_DEPTH = 7
local MAX_CAMERA_DEPTH_ADDITION = 30
local MIN_CAMERA_FOV = 65
local MAX_CAMERA_FOV_ADDITION = 65 -- best 45
local HEIGHT_OFFSET = 3
local MIN_SHAKE_MAGNITUDE = 0.11
local MAX_SHAKE_MAGNITUDE_ADDITION = 0.15
local MIN_SHAKE_ROUGHNESS = 2
local MAX_SHAKE_ROUGHNESS_ADDITION = 30

local windSound = Instance.new("Sound")
windSound.SoundId = "rbxassetid://17619012144"
windSound.Looped = true
windSound.PlaybackRegion = NumberRange.new(3, 68)
windSound.Parent = camera

local cameraShake = cameraShaker.new(Enum.RenderPriority.Camera.Value + 2, function(shakeCf)
	camera.CFrame *= shakeCf
end)

function setupCamera()
	disassembleCamera()
	character = player.Character or player.CharacterAdded:Wait()

	cameraShake:Start()
	windSound:Play()
	RunService:BindToRenderStep("UpdateCamera", Enum.RenderPriority.Camera.Value + 1, updateCamera)
end
enteredFlightMode.OnClientEvent:Connect(setupCamera)

function disassembleCamera()
	character = nil
	cameraShake:Stop()
	windSound:Stop()

	RunService:UnbindFromRenderStep("UpdateCamera")
end
exitedFlightModeEvent.OnClientEvent:Connect(disassembleCamera)

function updateCamera(dt)
	if character then
		local humanoid: Humanoid = character:WaitForChild("Humanoid")

		local hrp: Part = character:FindFirstChild("HumanoidRootPart")
		local headingVector = hrp.CFrame.UpVector.Unit

		if hrp then
			local speed = 1
			if speed then
				speed = hrp.AssemblyLinearVelocity.Magnitude
			end

			-- Sounds
			windSound.PlaybackSpeed = 0 + speed / MAX_SPEED * 2.8

			-- Camera position
			local lateralAxis = 0
			if keysActive[Enum.KeyCode.D] then
				lateralAxis = 1
			elseif keysActive[Enum.KeyCode.A] then
				lateralAxis = -1
			end
			local lateralPosGol = 0.1
			local lateralLookAtGol = 100

			local avgLift = physicsCalculator.getLiftMagnitude(hrp.AssemblyLinearVelocity)
			local posGoal = (
				hrp.CFrame
				+ (
						-hrp.CFrame.RightVector:Cross(hrp.AssemblyLinearVelocity.Unit).Unit -- down
						- hrp.AssemblyLinearVelocity.Unit -- back
					)
					* getCameraDepth(avgLift, speed, headingVector)
			)
			posGoal = posGoal.Position

			local lookAtGoal = (
				hrp.CFrame.Position + (hrp.AssemblyLinearVelocity.Unit * 1000) -- forward
			)
			local newCFrame = CFrame.new(posGoal, lookAtGoal)

			local goal = {}
			goal.CFrame = newCFrame
			local tweenInfo = TweenInfo.new(1)

			local tween = TweenService:Create(camera, tweenInfo, goal)
			tween:Play()

			-- Shake
			cameraShake:ShakeOnce(getShakeMagnitude(avgLift), getShakeRoughness(avgLift), 0.1, 0.75, 0, 0)

			-- FOV
			camera.FieldOfView = getCameraFOV(avgLift, speed, headingVector)
		end
	end
end

function getShakeMagnitude(lift)
	return MIN_SHAKE_MAGNITUDE + (lift / MAX_OBSERVED_LIFT) ^ 3.75 * MAX_SHAKE_MAGNITUDE_ADDITION
end

function getShakeRoughness(lift)
	return MIN_SHAKE_ROUGHNESS + (lift / MAX_OBSERVED_LIFT) ^ 3.75 * MAX_SHAKE_ROUGHNESS_ADDITION
end

-- Orientation must be normalized normalized
function getCameraDepth(lift, speed, orientation)
	return MIN_CAMERA_DEPTH + (lift / MAX_OBSERVED_LIFT) * MAX_CAMERA_DEPTH_ADDITION
end

function getCameraFOV(lift, speed, orientation)
	return MIN_CAMERA_FOV + (lift / MAX_OBSERVED_LIFT) * MAX_CAMERA_FOV_ADDITION
end

-- Allows references to be refreshed whenever character dies
function resetReferences()
	character = nil
end

player.CharacterAdded:Connect(function()
	resetReferences()
	setupCamera()
end)

player.CharacterRemoving:Connect(disassembleCamera)

-- TODO: Globalize activeKeys in another script -=-=-=
uis.InputEnded:Connect(function(input, gameProcessedEvent)
	if input.KeyCode == Enum.KeyCode.W then
		keysActive[Enum.KeyCode.W] = false
	elseif input.KeyCode == Enum.KeyCode.S then
		keysActive[Enum.KeyCode.S] = false
	elseif input.KeyCode == Enum.KeyCode.D then
		keysActive[Enum.KeyCode.D] = false
	elseif input.KeyCode == Enum.KeyCode.A then
		keysActive[Enum.KeyCode.A] = false
	end
end)

uis.InputBegan:Connect(function(input, gameProcessedEvent)
	if input.KeyCode == Enum.KeyCode.W then
		keysActive[Enum.KeyCode.W] = true
	elseif input.KeyCode == Enum.KeyCode.S then
		keysActive[Enum.KeyCode.S] = true
	elseif input.KeyCode == Enum.KeyCode.D then
		keysActive[Enum.KeyCode.D] = true
	elseif input.KeyCode == Enum.KeyCode.A then
		keysActive[Enum.KeyCode.A] = true
	end
end)
