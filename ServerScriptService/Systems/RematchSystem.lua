-- RematchSystem.lua (REFATORADO - Data-Driven)
local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local GameData = require(ServerStorage:WaitForChild("GameData"))

local remoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")

local rematchVoteEvent = remoteEvents:WaitForChild("RematchVote")
local rematchStateEvent = remoteEvents:WaitForChild("RematchState")

-- ==================== Usar GameData para configurações ====================
local PLACE_MATCH = GameData.config.Rematch.PlaceId
local TIMER_DEFAULT = GameData.config.Rematch.TimerDefault
local TIMER_ALL = GameData.config.Rematch.TimerAll

local votes = {}
local deadPlayers = {}
local timerActive = false
local timerEnd = 0

local function getDeadCount()
	local n = 0
	for _ in pairs(deadPlayers) do n += 1 end
	return n
end

local function getVoteCount()
	local n = 0
	for _ in pairs(votes) do n += 1 end
	return n
end

local function broadcastState()
	local timeLeft = math.max(0, math.ceil(timerEnd - os.clock()))
	local dead = getDeadCount()
	local voted = getVoteCount()
	rematchStateEvent:FireAllClients(voted, dead, timeLeft)
end

local function startRematch()
	local playerList = {}

	for _, p in ipairs(Players:GetPlayers()) do
		if votes[p.UserId] then
			table.insert(playerList, p)
		end
	end

	if #playerList == 0 then return end

	local ok, err = pcall(function()
		local code = TeleportService:ReserveServer(PLACE_MATCH)
		TeleportService:TeleportToPrivateServer(PLACE_MATCH, code, playerList)
	end)

	if not ok then
		warn("Erro no rematch teleport:", err)
	end
end

local function startTimer(duration)
	timerActive = true
	timerEnd = os.clock() + duration

	task.spawn(function()
		while timerActive do
			local timeLeft = timerEnd - os.clock()

			broadcastState()

			if timeLeft <= 0 then
				timerActive = false
				broadcastState()
				task.wait(0.5)
				startRematch()
				-- reset
				votes = {}
				deadPlayers = {}
				return
			end

			task.wait(1)
		end
	end)
end

local RematchSystem = {}

function RematchSystem:MarkDead(player)
	deadPlayers[player.UserId] = true
	broadcastState()
end

function RematchSystem:MarkAlive(player)
	deadPlayers[player.UserId] = nil
	votes[player.UserId] = nil
end

-- Recebe voto do cliente
rematchVoteEvent.OnServerEvent:Connect(function(player)
	if not deadPlayers[player.UserId] then return end
	if votes[player.UserId] then return end

	votes[player.UserId] = true

	local dead = getDeadCount()
	local voted = getVoteCount()

	if not timerActive then
		-- Primeiro voto: inicia timer com valor do GameData
		startTimer(TIMER_DEFAULT)
	elseif voted >= dead then
		-- Todos votaram: acelera com valor do GameData
		timerEnd = os.clock() + TIMER_ALL
	end

	broadcastState()
end)

-- Limpa ao sair
Players.PlayerRemoving:Connect(function(player)
	votes[player.UserId] = nil
	deadPlayers[player.UserId] = nil
end)

return RematchSystem
