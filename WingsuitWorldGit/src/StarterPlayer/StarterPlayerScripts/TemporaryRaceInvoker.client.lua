local uis = game:GetService("UserInputService")
local replicatedStorage = game:GetService("ReplicatedStorage")
local plr = game.Players.LocalPlayer

local enteredRace = replicatedStorage.Events.EnteredRace

uis.InputBegan:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.G  then -- Enter race
		enteredRace:FireServer(plr)
	end
end)