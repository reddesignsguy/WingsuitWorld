local runService = game:GetService("RunService")
local replicatedStorage = game:GetService("ReplicatedStorage")
local tweenService = game:GetService("TweenService")
local pointsModule = require(replicatedStorage:WaitForChild("PointsModule"))

-- References
local gui = script.Parent
local pointsLabel: TextLabel = gui.Points
local multiplierLabel: TextLabel = gui.Multiplier
local multiplierBarFrame: Frame = gui.MultiplierBar
local multiplierHealthFrame: Frame = gui.MultiplierHealth
local vignette = gui.Vignette
local rewardFrame = gui.RewardFrame

-- Events
local rewardedPlayer = replicatedStorage.ClientEvents.RewardedPlayer
local updatedPoints = replicatedStorage.Events.UpdatedPoints
local updatedMultiplier = replicatedStorage.Events.UpdatedMultiplier
local flewThruLoop = replicatedStorage.Events.FlewThruLoop
local flewNearObstacle = replicatedStorage.Events.FlewNearObstacle
local flewThruCheckpoint = replicatedStorage.Events.FlewThruCheckpoint
local plrPointsChanged = replicatedStorage.Events.PlrPointsChanged

-- Vignette
local age = 3
local lifetime = 2

-- Draw state
local points = 0
local multiplier = 1
local pointsForNextMultiplier = 1
local multiplierPointRequirement = 1000

-- States
local rewardLabels = {}

function init()
	rewardLabels["Loop"] = {}
	rewardLabels["Proximity"] = {}
end
init()

function drawRewards()
	-- TODO: Put this in wider scope
	local nextYPosition = 200

	for categoryName, category in pairs(rewardLabels) do
		-- TODO: Refactor handling between categories w/ multiple tiers and those with just one
		if categoryName == "Loop" then
			for _, tier in pairs(category) do
				local frame: Frame = tier.Frame
				frame.Position = UDim2.new(0, 200, 0, nextYPosition)

				local pointsLabel: TextLabel = frame.Points
				if pointsLabel then
					pointsLabel.Text = tostring(tier.Points)
				end

				nextYPosition += 20
			end

		-- Might be a reward for proximity flying (only 1 tier)
		elseif categoryName == "Proximity" and category.Points then
			local frame: Frame = category.Frame
			frame.Position = UDim2.new(0, 200, 0, nextYPosition)

			local pointsLabel: TextLabel = frame.Points
			if pointsLabel then
				pointsLabel.Text = tostring(category.Points)
			end

			nextYPosition += 20
		end
	end
end
runService.Heartbeat:Connect(drawRewards)

function drawMultiplier()
	multiplierLabel.Text = tostring(multiplier) .. "x" -- Draw current multiplier

	-- Draw health bar
	local percentage = pointsForNextMultiplier / multiplierPointRequirement
	local xSize = percentage * multiplierBarFrame.Size.X.Offset
	local ySize = multiplierBarFrame.Size.Y.Offset
	multiplierHealthFrame.Size = UDim2.new(0, xSize, 0, ySize)
end
runService.Heartbeat:Connect(drawMultiplier)

function drawPoints()
	pointsLabel.Text = points
end
runService.Heartbeat:Connect(drawPoints)

--=-=-=-=-=-=-=-=-=-=-=-= Remotes  -=-=-=-=-=-=-=-=-=-=-=-=-=-=
function setPoints(newPoints)
	print("Setting points")
	points = newPoints
end
flewThruCheckpoint.OnClientEvent:Connect(setPoints)
plrPointsChanged.OnClientEvent:Connect(setPoints)

function updateVignette(dt)
	if age <= lifetime then
		vignette.Size = UDim2.new(0, gui.AbsoluteSize.X, 0, gui.AbsoluteSize.Y)

		age += dt
	else
		vignette.Visible = false
	end
end
runService.PreRender:Connect(updateVignette)

function resetVignette(color: Color3)
	-- Reset only if the tier is higher
	-- Reset state
	vignette.BackgroundTransparency = 0.85
	vignette.ImageTransparency = 0
	vignette.ImageColor3 = color
	vignette.Visible = true
	age = 0

	-- Animate vignette
	local goal = {}

	goal.BackgroundTransparency = 1
	goal.ImageTransparency = 1
	local tweenInfo = TweenInfo.new(1, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out)

	local tween = tweenService:Create(vignette, tweenInfo, goal)
	tween:Play()
end
rewardedPlayer.Event:Connect(resetVignette)

function updateMultiplier(mult, pointsForNextMult, multPointReq)
	multiplier = mult
	pointsForNextMultiplier = pointsForNextMult
	multiplierPointRequirement = multPointReq
end
updatedMultiplier.OnClientEvent:Connect(updateMultiplier)

function addLoopReward(tier)
	-- Update existing frame
	if rewardLabels["Loop"][tier] then
		rewardLabels["Loop"][tier]["Points"] += pointsModule.getTierReward(tier)
	-- Create new frame
	else
		local newFrame = rewardFrame:Clone()
		newFrame.Parent = gui

		local points = pointsModule.getTierReward(tier)
		newFrame.Points.Text = points

		local title = pointsModule.getTierPopupMessage(tier)
		newFrame.Title.Text = title

		newFrame.Visible = true

		local data = { Frame = newFrame, Points = points }
		rewardLabels["Loop"][tier] = data
	end
end
flewThruLoop.OnClientEvent:Connect(addLoopReward)

function addProximityReward(proximityReward)
	-- Update existing frame
	if rewardLabels["Proximity"]["Points"] then
		rewardLabels["Proximity"]["Points"] += proximityReward
		-- Create new frame
	else
		local newFrame = rewardFrame:Clone()
		newFrame.Parent = gui

		local points = proximityReward
		newFrame.Points.Text = points

		local title = "Proximity"
		newFrame.Title.Text = title

		newFrame.Visible = true

		local data = { Frame = newFrame, Points = points }
		rewardLabels["Proximity"] = data
	end
end
flewNearObstacle.OnClientEvent:Connect(addProximityReward)

function clearRewards()
	for categoryName, category in pairs(rewardLabels) do
		if categoryName == "Loop" then
			for _, tier in pairs(category) do
				tier.Frame:ClearAllChildren()
				table.clear(tier)
			end
		else
			category.Frame:ClearAllChildren()
		end

		table.clear(category)
	end
end
flewThruCheckpoint.OnClientEvent:Connect(clearRewards)
