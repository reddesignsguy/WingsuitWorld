local Player = game:GetService("Players").LocalPlayer
local UIS = game:GetService("UserInputService")
local Runservice = game:GetService("RunService")
local Frame = script.Parent
local step = 0.01
local percentage = 0

function snap(number, factor)
	if factor == 0 then
		return number
	else
		return math.floor(number / factor + 0.5) * factor
	end
end

function insertSlider(sliders, name, val, min, max)
	local padding = 5
	local sizeX = 40
	local sizeY = 20

	local Button = Instance.new("TextButton")
	Button.Parent = Frame
	Button.Name = name
	Button.Text = name
	Button.Position = UDim2.new(0, 0, #sliders * sizeY + padding, 0)
	Button.Size = UDim2.new(0, 40, 0, 20)

	local currentVal = Instance.new("IntValue")
	currentVal.Parent = Button
	currentVal.Value = val

	local db = false

	Button.MouseButton1Down:Connect(function()
		db = true
	end)

	Button.MouseButton1Up:Connect(function()
		db = false
	end)

	Runservice.RenderStepped:Connect(function()
		if db then
			local MousePos = UIS:GetMouseLocation().X
			local BtnPos = Button.Position
			local FrameSize = Frame.AbsoluteSize.X
			local FramePos = Frame.AbsolutePosition.X
			local pos = snap((MousePos - FramePos) / FrameSize, step)
			percentage = math.clamp(pos, 0, 1)
			Button.Position = UDim2.new(percentage, 0, BtnPos.Y.Scale, BtnPos.Y.Offset)

			currentVal.Value = min + percentage * (max - min)
			print(currentVal.Value)
		end
	end)

	table.insert(sliders, Button)
end

---=-=-=-=-=-=-=-=-=-=-=-=-
-- Set up code

local sliders = {}

insertSlider(sliders, "LateralMobility", 500, 300, 2000)

--insertSlider(sliders, "UpMobility", 5, 0, 500)

--local Button = Instance.new("TextButton")
--Button.Parent = Frame
--Button.Name = "Button"
--Button.Size = UDim2.new(0, 40, 0, 20)

--local Button = Instance.new("TextButton")
--Button.Parent = Frame
--Button.Name = "Button"
--Button.Position = UDim2.new(0, 0, 0, 0)
--Button.Size = UDim2.new(0, 40, 0, 20)

--local Button = Instance.new("TextButton")
--Button.Parent = Frame
--Button.Name = "Button"
--Button.Position = UDim2.new(0, 0, 0, 0)
--Button.Size = UDim2.new(0, 40, 0, 20)

---=-=-=-=-=-=-=-=-=-=-=-=-
