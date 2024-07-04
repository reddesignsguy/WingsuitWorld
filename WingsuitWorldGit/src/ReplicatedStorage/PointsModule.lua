local PointsModule = {}

PointsModule.TierPopupMessages = {
	[1] = "COOL LOOP!",
	[2] = "RISKY LOOP!",
	[3] = "EPIC LOOP!",
	[4] = "LEGENDARY LOOP!",
	[5] = "POGGGG LOOOPPPPP!!11",
}

PointsModule.TierRewards = {
	[1] = 200,
	[2] = 400,
	[3] = 1000,
	[4] = 5000,
	[5] = 10000,
}

PointsModule.TierColors = {
	[1] = Color3.new(0.574716, 0.954879, 0.522713),
	[2] = Color3.new(0.366033, 0.707713, 0.963149),
	[3] = Color3.new(0.698589, 0.475975, 0.969818),
	[4] = Color3.new(0.969451, 0.832914, 0.342153),
	[5] = Color3.new(0.973053, 1, 0.975326),
}

function PointsModule.getTierColor(tier)
	return PointsModule.TierColors[tier]
end

function PointsModule.getTierPopupMessage(tier)
	return PointsModule.TierPopupMessages[tier]
end

function PointsModule.getTierReward(tier)
	return PointsModule.TierRewards[tier]
end

function PointsModule.getTier(dist)
	dist = math.floor(dist)

	if dist <= 6 then
		return 5
	elseif dist <= 7 then
		return 4
	elseif dist <= 12 then
		return 3
	elseif dist <= 20 then
		return 2
	else
		return 1
	end
end

function PointsModule.getPointsFromTier(tier)
	return PointsModule.TierRewards[tier]
end

return PointsModule
