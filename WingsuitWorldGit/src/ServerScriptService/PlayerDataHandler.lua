local PlayerDataHandler = {}
local ReplicaService = require(game.ServerScriptService.ReplicaService)
local rand = Random.new()

local dataTemplate = {
	Coins = 0,
	FlightPoints = 0,
	HighestStreak = 0,
	Maps = {},
	ProfileCode = rand.NextInteger(Random.new(), 0, 1000000),
}

local ProfileService = require(game.ServerScriptService.ProfileService)
local Players = game:GetService("Players")

local ProfileStore = ProfileService.GetProfileStore("PlayerProfile", dataTemplate)

-- Profiles of every player in game right now
local Profiles = {}

-- Load profile
local function playerAdded(player)
	local profile = ProfileStore:LoadProfileAsync("Player_" .. player.UserId)
	-- Profile found for newly joined player
	if profile then
		profile:AddUserId(player.UserId)
		profile:Reconcile()

		-- Listen for if profile is released
		profile:ListenToRelease(function()
			Profiles[player] = nil
			player:Kick()
		end)

		-- Release player's profile if player leaves
		if not player:IsDescendantOf(Players) then
			profile:Release()
		else
			Profiles[player] = profile

			local leaderstats = Instance.new("Folder")
			leaderstats.Name = "leaderstats"
			leaderstats.Parent = player

			local Coins = Instance.new("IntValue")
			Coins.Name = "Coins"
			Coins.Value = profile.Data["Coins"]
			Coins.Parent = leaderstats

			local profileCodeReplica = ReplicaService.NewReplica({
				ClassToken = ReplicaService.NewClassToken("ProfileCodeReplica"),
				Data = { Value = profile.Data["ProfileCode"] },
				Replication = "All",
			})
		end
	else
		player:Kick()
	end
end

-- Invoke load profile function
function PlayerDataHandler:Init()
	for _, player in game.Players:GetPlayers() do
		task.spawn(playerAdded, player)
	end

	game.Players.PlayerAdded:Connect(playerAdded)

	game.Players.PlayerRemoving:Connect(function(player)
		if Profiles[player] then
			Profiles[player]:Release()
		end
	end)
end

local function getProfile(player)
	print(player)
	assert(Profiles[player], string.format("Profile doesn't exist for" .. tostring(player.UserId)))

	return Profiles[player]
end

-- getter/setter methods for values from player
function PlayerDataHandler:Get(player, key)
	local profile = getProfile(player)
	assert(profile.Data[key], string.format("Data doesn't exist for key: %s", key))

	return profile.Data[key]
end

function PlayerDataHandler:Set(player, key, value)
	local profile = getProfile(player)
	assert(profile.Data[key], string.format("Data doesn't exist for key: %s", key))

	assert(type(profile.Data[key]) == type(value))

	profile.Data[key] = value
end

function PlayerDataHandler:Increment(player, key, value)
	local profile = getProfile(player)
	assert(profile.Data[key], string.format("Data doesn't exist for key: %s", key))

	assert(type(profile.Data[key]) == type(value))

	profile.Data[key] += value
end

function PlayerDataHandler:Update(player, key, callback)
	local profile = getProfile(player)

	local oldData = self:Get(player, key)
	local newData = callback(oldData)

	self:Set(player, key, newData)
end

return PlayerDataHandler
