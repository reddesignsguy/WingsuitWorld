local PhysicsCalculator = {}

local liftCoefficient = 0.5
local density = 0.32
local area = 0.1

function PhysicsCalculator.getLiftMagnitude(bodyMovement)
	local liftMag = liftCoefficient * (0.5 * density * math.pow(bodyMovement.Magnitude, 2) * area)
	return liftMag
end

return PhysicsCalculator
