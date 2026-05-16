-- GameManager.lua (REFATORADO - Data-Driven Completo)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local MonsterAI = require(script.Parent:WaitForChild("MonsterAI"))
local ObjectiveSystem = require(script.Parent:WaitForChild("ObjectiveSystem"))
local PowerSystem = require(script.Parent:WaitForChild("PowerSystem"))
local ExitCutsceneController = require(script.Parent:WaitForChild("ExitCutsceneController"))
local GameData = require(ServerStorage:WaitForChild("GameData"))

local GameManager = {}
GameManager.__index = GameManager

-- ==================== HELPER: Criar RemoteEvents a partir do GameData ====================
local function getRemoteEvents()
	local folder = ReplicatedStorage:FindFirstChild("RemoteEvents")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "RemoteEvents"
		folder.Parent = ReplicatedStorage
	end

	local function ensure(name)
		local ev = folder:FindFirstChild(name)
		if not ev then
			ev = Instance.new("RemoteEvent")
			ev.Name = name
			ev.Parent = folder
		end
		return ev
	end

	local result = {}
	local eventList = GameData.config.RemoteEvents

	-- Itera sobre a tabela de eventos do GameData
	for key, eventName in pairs(eventList) do
		result[key] = ensure(eventName)
	end

	-- Eventos dinâmicos do OnGameInit (se existirem)
	for _, ev in ipairs(GameData.config.OnGameInit or {}) do
		if ev.type == "remote" then
			result[ev.Name] = ensure(ev.Name)
		end
	end

	return result, folder
end

-- ==================== HELPER: Obter BindableEvents ====================
local function getBindableEvents()
	local result = {}
	local eventList = GameData.config.BindableEvents

	for key, eventName in pairs(eventList) do
		local ev = ServerScriptService:FindFirstChild(eventName)
		if not ev then
			ev = Instance.new("BindableEvent")
			ev.Name = eventName
			ev.Parent = ServerScriptService
		end
		result[key] = ev
	end

	return result
end

-- ==================== CONSTRUTOR ====================
function GameManager.new()
	local self = setmetatable({}, GameManager)

	local RematchSystem = require(script.Parent:WaitForChild("RematchSystem"))
	local LockerSystem = require(script.Parent:WaitForChild("LockerSystem"))

	self.RematchSystem = RematchSystem
	self.LockerSystem = LockerSystem
	self.GameData = GameData

	-- Carregar eventos
	self.RemoteEvents, self.RemoteEventsFolder = getRemoteEvents()
	self.BindableEvents = getBindableEvents()

	-- Sistemas
	self.Objectives = ObjectiveSystem.new(self.RemoteEvents)
	self.Power = PowerSystem.new(self.RemoteEvents)
	self.ExitCutscene = ExitCutsceneController.new(self)

	-- Monstro principal
	self.Monster = MonsterAI.new(self.RemoteEvents)
	self.ActiveMonsters = {}

	-- Estado
	self.GameOver = false
	self.AlivePlayers = {}

	return self
end

-- ==================== INICIALIZAÇÃO ====================
function GameManager:Init()
	self.Objectives:Init()
	self.Objectives:BindPlayerJoin()

	-- Usar GameData.config.Folders em vez de hardcodes
	local objectivesFolder = self.GameData.config.Folders.Objectives
	self.Objectives:BindPrompts(objectivesFolder)

	self:BindObjectiveUpdates()
	self:BindPlayerLifecycle()
	self:BindNoisePrompts(objectivesFolder)
	self:SetupAmbientSounds()
	self:SetupPowerSystem()
	self:SetupGenericMonsterSpawn()
end

-- ==================== POWER SYSTEM ====================
function GameManager:SetupPowerSystem()
	local powerEvent = self.BindableEvents.PowerStateEvent
	if powerEvent then
		powerEvent.Event:Connect(function(state)
			self.Power:SetGeneratorOn(state)
		end)
	else
		warn("⚠️ PowerStateEvent não encontrado")
	end
end

-- ==================== SPAWN GENÉRICO DE MONSTROS ====================
function GameManager:SetupGenericMonsterSpawn()
	local spawnEvent = self.BindableEvents.SpawnMonsterEvent
	local objectiveTrigger = self.BindableEvents.MonsterSpawnEvent

	if not spawnEvent then
		warn("❌ SpawnMonsterEvent não encontrado")
		return
	end

	spawnEvent.Event:Connect(function(templateModel, spawnPart, startDelay)
		if not templateModel then
			warn("❌ SpawnMonsterEvent: templateModel não fornecido")
			return
		end

		local ai = self:SpawnMonster(templateModel, spawnPart, startDelay)
		print("👾 Monstro spawnado: " .. templateModel.Name)

		-- Se for o monstro principal, marca e ativa objetivo
		local mainMonsterName = self.GameData.config.Names.MainMonsterTemplate
		if templateModel.Name == mainMonsterName then
			self.Monster = ai
			if objectiveTrigger then
				objectiveTrigger:Fire()
			end
		end
	end)
end

-- ==================== SPAWN DE MONSTRO ====================
function GameManager:SpawnMonster(templateModel, spawnPart, startDelay)
	local monsterModel = templateModel:Clone()

	-- Usar GameData para pasta e nome do spawn
	local sp = spawnPart or self.GameData.config.Folders.Waypoints
		and self.GameData.config.Folders.Waypoints.Parent:FindFirstChild(
			self.GameData.config.Names.MonsterSpawn
		)

	if sp then
		monsterModel:PivotTo(sp.CFrame)
	end

	local monstersFolder = self.GameData.config.Folders.Monsters or workspace:FindFirstChild(
		self.GameData.config.Names.MonstersFolder
	)
	monsterModel.Parent = monstersFolder or workspace

	local ai = MonsterAI.new(self.RemoteEvents)
	ai.StartDelay = startDelay or 0
	ai:Init(monsterModel, self.GameData.config.Folders.Waypoints)

	table.insert(self.ActiveMonsters, ai)
	return ai
end

-- ==================== INVESTIGAÇÃO DE RUÍDO ====================
function GameManager:BindNoisePrompts(objectivesFolder)
	if not objectivesFolder then
		return
	end

	for _, instance in ipairs(objectivesFolder:GetDescendants()) do
		if instance:IsA("ProximityPrompt") then
			-- Usar GameData para nome da porta de saída
			local isExitDoor = instance.Parent and instance.Parent.Name == self.GameData.config.Names.ExitDoor
			if isExitDoor then continue end

			instance.Triggered:Connect(function(player)
				local parentPart = instance.Parent
				if parentPart and parentPart:IsA("BasePart") then
					-- Usar configs do GameData para investigação
					if self.Monster.LastNoisePos ~= nil and not self.GameData.config.Investigation.CanInvestigateMultipleSounds then
						return
					end

					if self.Monster.State == "CHASE" and self.GameData.config.Investigation.IgnoreNoiseWhileChasing then
						return
					end

					self.Monster.LastNoisePos = parentPart.Position
					self.Monster.State = "INVESTIGATE"
				end
			end)
		end
	end
end

-- ==================== SONS AMBIENTES (Data-Driven) ====================
function GameManager:SetupAmbientSounds()
	-- Usar GameData.config.Folders.Sounds
	local soundsFolder = self.GameData.config.Folders.Sounds or Instance.new("Folder", workspace)
	soundsFolder.Name = "SoundEmitters"

	local function ensureEmitter(name)
		local part = soundsFolder:FindFirstChild(name)
		if not part then
			part = Instance.new("Part")
			part.Name = name
			part.Anchored = true
			part.CanCollide = false
			part.Transparency = 1
			part.Parent = soundsFolder
		end
		return part
	end

	local function playWithRandomDelay(sound, minDelay, maxDelay)
		local rng = Random.new()
		task.spawn(function()
			-- Usar GameData para wait inicial
			task.wait(rng:NextNumber(
				self.GameData.config.Timings.AmbientStartWait.Min,
				self.GameData.config.Timings.AmbientStartWait.Max
			))

			while sound and sound.Parent do
				sound.PlaybackSpeed = rng:NextNumber(0.1, 5)
				sound:Play()
				sound.Ended:Wait()

				local tempoSorteado = rng:NextNumber(minDelay, maxDelay)
				task.wait(tempoSorteado)
			end
		end)
	end

	local function ensureSound(parent, soundName, soundId, volume, minDelay, maxDelay)
		local sound = parent:FindFirstChild(soundName)
		if not sound then
			sound = Instance.new("Sound")
			sound.Name = soundName
			sound.SoundId = soundId
			sound.Looped = false
			sound.Volume = volume
			sound.RollOffMaxDistance = 120
			sound.Parent = parent
			sound.PlaybackSpeed = math.random(1, 50) / 10

			playWithRandomDelay(sound, minDelay, maxDelay)
		end
		return sound
	end

	local ambientEmitter = ensureEmitter("AmbientEmitter")

	-- Carrega TODOS os sons do GameData
	for _, s in ipairs(self.GameData.config.AmbientSounds or {}) do
		ensureSound(ambientEmitter, s.Name, s.Id, s.Volume, s.MinDelay, s.MaxDelay)
	end
end

-- ==================== OBJETIVOS E FASES ====================
function GameManager:BindObjectiveUpdates()
	self.Objectives.PhaseChanged.Event:Connect(function(order, phase, signal)
		if signal == "cutscene_start" or signal == "cutscene_complete" then
			self:OnCutscenePhase(phase, signal)
		end
	end)

	self.Objectives.Updated.Event:Connect(function(id, obj)
		if id == "__PHASE_COMPLETE__" then
			self:OnPhaseComplete(obj)
		elseif id == "__VICTORY__" then
			self:OnVictoryPhaseComplete(obj.Phase)
		end
	end)
end

function GameManager:OnPhaseComplete(obj)
	local completedPhase = self.Objectives.Phases[obj.Phase]

	if completedPhase
		and completedPhase.Main.HasCutscene
		and completedPhase.Main.CutsceneTrigger
		and completedPhase.Main.CutsceneTrigger.Type == "complete"
		and not completedPhase.Main.IsVictory then
		task.spawn(function()
			self:DestroyAllMonsters()

			self:OnCutscenePhase(completedPhase, "cutscene_complete")
			if self.ExitCutscene then
				self.ExitCutscene.Finished.Event:Wait()
				-- Usar GameData para timing
				task.wait(self.GameData.config.Timings.CutsceneCompleteWait)
			end

			local nextOrder = obj.Phase + 1
			local nextPhase = self.Objectives.Phases[nextOrder]
			if nextPhase and nextPhase.Trigger.Type == "immediate" then
				self.Objectives:ActivatePhase(nextOrder)
			end
		end)
		return
	end

	local nextOrder = obj.Phase + 1
	local nextPhase = self.Objectives.Phases[nextOrder]
	if nextPhase and nextPhase.Trigger.Type == "immediate" then
		self.Objectives:ActivatePhase(nextOrder)
	end
end

function GameManager:OnVictoryPhaseComplete(phaseOrder)
	if self.GameOver then return end

	self:DestroyAllMonsters()

	local phase = self.Objectives.Phases[phaseOrder]
	local hasCutsceneComplete = phase
		and phase.Main.HasCutscene
		and phase.Main.CutsceneTrigger
		and phase.Main.CutsceneTrigger.Type == "complete"

	if hasCutsceneComplete then
		self:OnCutscenePhase(phase, "cutscene_complete")

		if self.ExitCutscene then
			self.ExitCutscene.Finished.Event:Wait()
			-- Usar GameData para timing
			task.wait(self.GameData.config.Timings.CutsceneCompleteWait)
		end

		print("GameManager: cutscene concluida, aguardando EndPoint...")
	else
		self.GameOver = true
		self.RemoteEvents.GameState:FireAllClients("VICTORY")
	end
end

function GameManager:DestroyAllMonsters()
	for _, ai in ipairs(self.ActiveMonsters) do
		if ai and ai.Root then ai:Destroy() end
	end
	self.ActiveMonsters = {}
	if self.Monster and self.Monster.Root then
		self.Monster:Destroy()
	end
end

-- ==================== CUTSCENE ====================
function GameManager:OnCutscenePhase(phase, signal)
	if self.GameOver then return end

	-- Usar GameData para folder e nomes
	local objectivesFolder = self.GameData.config.Folders.Objectives
	local cutsceneConfig = self.GameData.config.Cutscenes.Exit
	local exitDoorName = self.GameData.config.Names.ExitDoor
	local timeoutDuration = self.GameData.config.Timings.ExitDoorWaitTimeout

	if signal == "cutscene_start" then
		task.spawn(function()
			local exitDoor = objectivesFolder:FindFirstChild(exitDoorName)
				or objectivesFolder:WaitForChild(exitDoorName, timeoutDuration)

			if exitDoor then
				self.RemoteEvents.ExitDoorPhase:FireAllClients(exitDoor)
			else
				warn("⚠️ OnCutscenePhase: " .. exitDoorName .. " não encontrado após timeout")
			end
		end)

	elseif signal == "cutscene_complete" then
		local exitDoor = objectivesFolder and objectivesFolder:FindFirstChild(exitDoorName)
		if not exitDoor then
			warn("⚠️ OnCutscenePhase: " .. exitDoorName .. " não encontrado")
			if self.ExitCutscene then self.ExitCutscene.Finished:Fire() end
			return
		end

		task.spawn(function()
			local CutscenePlayer = require(ServerStorage.CutscenesConfig.CutscenePlayer)
			local ExitCutscene = require(ServerStorage.CutscenesConfig.Cutscenes[cutsceneConfig.Module])

			if ExitCutscene.Setup then
				ExitCutscene.Setup({ exitDoorModel = exitDoor, GM = self })
			end

			CutscenePlayer.PlayCutscene(ExitCutscene, {
				RemoteEvent = self.RemoteEvents[cutsceneConfig.RemoteEvent],
				Context = { exitDoorModel = exitDoor, GM = self },
			})

			if self.ExitCutscene then self.ExitCutscene.Finished:Fire() end
		end)
	end
end

-- ==================== LIFECYCLE DOS PLAYERS ====================
function GameManager:BindPlayerLifecycle()
	local function trackCharacter(player, character)
		local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid")

		self.AlivePlayers[player] = true

		humanoid.Died:Connect(function()
			self.AlivePlayers[player] = nil
			self.RematchSystem:MarkDead(player)

			-- Usar GameData para delay
			task.delay(self.GameData.config.Timings.DeathCheckDelay, function()
				if not self.GameOver then
					self:CheckDefeat()
				end
			end)
		end)
	end

	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function(character)
			trackCharacter(player, character)
		end)
	end)

	for _, player in ipairs(Players:GetPlayers()) do
		if player.Character then
			trackCharacter(player, player.Character)
		else
			player.CharacterAdded:Connect(function(character)
				trackCharacter(player, character)
			end)
		end
	end

	Players.PlayerRemoving:Connect(function(player)
		self.AlivePlayers[player] = nil
		self:CheckDefeat()
	end)
end

function GameManager:OnPlayerRevived(player)
	self.AlivePlayers[player] = true
	self.RematchSystem:MarkAlive(player)
	if self.GameOver then self.GameOver = false end
	self.RemoteEvents.GameState:FireAllClients("RESUME")
end

function GameManager:CheckDefeat()
	if self.GameOver then return end

	-- Usar GameData para timing
	task.wait(self.GameData.config.Timings.RevivalCheckWait)

	local totalAlive = 0
	for _ in pairs(self.AlivePlayers) do
		totalAlive += 1
	end

	local totalPlayers = #Players:GetPlayers()

	if totalAlive == 0 and totalPlayers > 0 then
		self.GameOver = true
		self.RemoteEvents.GameState:FireAllClients("DEFEAT")
	end
end

function GameManager:CheckVictory()
	if self.GameOver then return end
	self.GameOver = true
	self.RemoteEvents.GameState:FireAllClients("VICTORY")
end

return GameManager
