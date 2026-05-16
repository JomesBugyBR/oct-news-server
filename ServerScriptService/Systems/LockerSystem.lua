-- LockerSystem.lua (REFATORADO - Data-Driven)
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local GameData = require(ServerStorage:WaitForChild("GameData"))

local remoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")

local lockerEnterEvent = remoteEvents:WaitForChild("LockerEnter")
local lockerExitEvent = remoteEvents:WaitForChild("LockerExit")
local lockerRequestEvent = remoteEvents:WaitForChild("LockerRequest")

local hiddenPlayers = {}

local LockerSystem = {}
LockerSystem.HiddenPlayers = hiddenPlayers

function LockerSystem:IsHidden(player)
	return hiddenPlayers[player.UserId] ~= nil
end

---------------------------------------------------------------------------
-- SETUP DOS ARMÁRIOS (Data-Driven)
---------------------------------------------------------------------------
local lockersFolder = GameData.config.Folders.Lockers

if not lockersFolder then
	warn("LockerSystem: pasta 'Armarios' não encontrada no Workspace")
	return LockerSystem
end

local function getHidingSpot(locker)
	-- Usar GameData para nome do HidingSpot
	return locker:FindFirstChild(GameData.config.Locker.HidingSpotName, true)
end

local function getExitPosition(locker)
	-- Usar GameData para nome do ExitSpot
	local exitSpot = locker:FindFirstChild(GameData.config.Locker.ExitSpotName, true)
	if exitSpot then
		return exitSpot.CFrame
	end

	-- Fallback: usar GameData para nome da porta
	local door = locker:FindFirstChild(GameData.config.Locker.DoorPartName) or locker:FindFirstChildWhichIsA("BasePart")
	if door then
		-- Usar GameData para offset padrão
		return door.CFrame * CFrame.new(0, 0, GameData.config.Locker.DefaultExitOffset)
	end

	local cf, size = locker:GetBoundingBox()
	return cf * CFrame.new(0, 0, size.Z / 2 + 2)
end

local function hidePlayer(player, locker)
	local character = player.Character
	if not character then return end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root then return end
	if humanoid.Health <= 0 then return end
	if hiddenPlayers[player.UserId] then return end

	local hidingSpot = getHidingSpot(locker)
	if not hidingSpot then
		warn("Armário sem HidingSpot: " .. locker.Name)
		return
	end

	local savedCollision = {}
	for _, part in ipairs(character:GetDescendants()) do
		if part:IsA("BasePart") then
			savedCollision[part] = part.CanCollide
			part.CanCollide = false
			if part.Name ~= "HumanoidRootPart" then
				part.Transparency = 1
			end
		end
	end

	hiddenPlayers[player.UserId] = {
		Locker = locker,
		SavedCollision = savedCollision,
		WalkSpeed = humanoid.WalkSpeed,
		JumpPower = humanoid.JumpPower,
	}

	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0

	root.CFrame = hidingSpot.CFrame
	locker:SetAttribute("Occupied", true)
	locker:SetAttribute("OccupiedBy", player.UserId)
	lockerEnterEvent:FireClient(player, hidingSpot.CFrame, locker)

	print(string.format("🚪 %s entrou no armário %s", player.Name, locker.Name))
end

local function revealPlayer(player)
	local character = player.Character
	if not character then
		hiddenPlayers[player.UserId] = nil
		return
	end

	local data = hiddenPlayers[player.UserId]
	if not data then return end

	local locker = data.Locker
	local savedCollision = data.SavedCollision

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root then return end

	local exitCF = getExitPosition(locker)
	root.CFrame = exitCF * CFrame.new(0, 3, 0)
	task.wait()

	for _, part in ipairs(character:GetDescendants()) do
		if part:IsA("BasePart") then
			local original = savedCollision[part]
			part.CanCollide = (original == true)
			if part.Name ~= "HumanoidRootPart" then
				part.Transparency = 0
			end
		end
	end

	humanoid.WalkSpeed = data.WalkSpeed
	humanoid.JumpPower = data.JumpPower

	if locker and locker.Parent then
		locker:SetAttribute("Occupied", false)
		locker:SetAttribute("OccupiedBy", 0)
	end

	hiddenPlayers[player.UserId] = nil
	lockerExitEvent:FireClient(player, locker)

	print(string.format("🚪 %s saiu do armário", player.Name))
end

---------------------------------------------------------------------------
-- RECEBE PEDIDO DO CLIENTE
---------------------------------------------------------------------------
lockerRequestEvent.OnServerEvent:Connect(function(player, locker)
	if not locker or not locker:IsA("Model") then return end
	if not locker:IsDescendantOf(lockersFolder) then return end

	if hiddenPlayers[player.UserId] then
		revealPlayer(player)
	else
		if locker:GetAttribute("Occupied") then return end

		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		local hidingSpot = getHidingSpot(locker)
		if not root or not hidingSpot then return end
		
		-- Usar GameData para distância máxima
		if (root.Position - hidingSpot.Position).Magnitude > GameData.config.Locker.MaxDistance then return end

		hidePlayer(player, locker)
	end
end)

---------------------------------------------------------------------------
-- LIMPA AO SAIR / MORRER
---------------------------------------------------------------------------
Players.PlayerRemoving:Connect(function(player)
	if hiddenPlayers[player.UserId] then
		revealPlayer(player)
	end
end)

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(character)
		if hiddenPlayers[player.UserId] then
			local data = hiddenPlayers[player.UserId]
			if data.Locker and data.Locker.Parent then
				data.Locker:SetAttribute("Occupied", false)
				data.Locker:SetAttribute("OccupiedBy", 0)
			end
			hiddenPlayers[player.UserId] = nil
		end

		local humanoid = character:WaitForChild("Humanoid")
		humanoid.Died:Connect(function()
			if hiddenPlayers[player.UserId] then
				revealPlayer(player)
			end
		end)
	end)
end)

---------------------------------------------------------------------------
-- SETUP DOS PROMPTS (Data-Driven)
---------------------------------------------------------------------------
for _, locker in ipairs(lockersFolder:GetChildren()) do
	if not locker:IsA("Model") then continue end

	locker:SetAttribute("Occupied", false)
	locker:SetAttribute("OccupiedBy", 0)

	-- Usar GameData para nome da parte da porta
	local door = locker:FindFirstChild(GameData.config.Locker.DoorPartName) or locker:FindFirstChildWhichIsA("BasePart")
	if not door then continue end

	local prompt = door:FindFirstChildWhichIsA("ProximityPrompt")
	if not prompt then
		prompt = Instance.new("ProximityPrompt")
		-- Usar GameData para textos e configurações do prompt
		prompt.ActionText = GameData.config.Locker.ActionText
		prompt.ObjectText = GameData.config.Locker.ObjectText
		prompt.HoldDuration = GameData.config.Locker.HoldDuration
		prompt.MaxActivationDistance = GameData.config.Locker.MaxActivationDistance
		prompt.Parent = door
	end

	prompt.Triggered:Connect(function(player)
		if hiddenPlayers[player.UserId] then
			revealPlayer(player)
		else
			if not locker:GetAttribute("Occupied") then
				hidePlayer(player, locker)
			end
		end
	end)
end

return LockerSystem
