local uis = game:GetService("UserInputService")
local replicatedStorage = game:GetService("ReplicatedStorage")
local plr = game.Players.LocalPlayer

local enteredRace = replicatedStorage.Events.EnteredRace

uis.InputBegan:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.G then -- Enter race
		enteredRace:FireServer(plr)
	elseif input.KeyCode == Enum.KeyCode.X then
		local char = plr.Character or plr.CharacterAdded:Wait()
		char.PrimaryPart.CFrame = CFrame.new(Vector3.new(-1347.691, 2000.482, 1998.224))
	end
end)
