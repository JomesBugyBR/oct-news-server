-- ServerStorage > GameData (COMPLETE DATA-DRIVEN VERSION)
local GameData = {}

GameData.config = {
	-- ==================== ESTRUTURA DE PASTAS ====================
	Folders = {
		Monsters = game.ReplicatedStorage.Monsters,
		Objectives = workspace.Objectives,
		Sounds = workspace.SoundEmitters,
		Waypoints = workspace.Waypoints,
		EndpointSpawns = workspace.EndpointSpawns,
		BifurcParts = workspace.BifurcParts,
		Lights = workspace.Lights,
		SafeZones = workspace.SafeZones,
		Lockers = workspace.Armarios, -- Sistema de locker
	},

	-- ==================== REMOTE EVENTS (Lista centralizada) ====================
	RemoteEvents = {
		-- Objetivos
		ObjectiveUpdate = "ObjectiveUpdate",
		-- Player State
		Jumpscare = "Jumpscare",
		RevivedEvent = "RevivedEvent",
		GameState = "GameState",
		-- Camera
		CameraInterpolate = "cameraInterpolateEvent",
		CameraToPlayer = "cameraToPlayerEvent",
		-- Locker System
		LockerEnter = "LockerEnter",
		LockerExit = "LockerExit",
		LockerRequest = "LockerRequest",
		-- Power System
		PowerUpdate = "PowerUpdate",
		-- Rematch
		RematchVote = "RematchVote",
		RematchState = "RematchState",
		-- Monster Investigation
		MonsterToInvestigate = "MonsterToInvestigate",
		-- Exit Door / Chase
		ExitDoorCutscene = "ExitDoorCutscene",
		ExitDoorPhase = "ExitDoorPhase",
		ExitDoorCutsceneStart = "ExitDoorCutsceneStart",
		-- Drone
		DroneEnter = "DroneEnter",
		DroneExit = "DroneExit",
		DroneControl = "DroneControl",
		DroneRecall = "DroneRecall",
		DroneForceExit = "DroneForceExit",
		DroneCutsceneEnd = "DroneCutsceneEnd",
		-- Monster Ambient
		MonsterStepShake = "MonsterStepShake",
		-- Cutscenes
		Cutscene1 = "Cutscene1",
		TeleportRequest = "TeleportRequest",
	},

	-- ==================== BINDABLE EVENTS ====================
	BindableEvents = {
		PowerStateEvent = "PowerStateEvent",
		SpawnMonsterEvent = "SpawnMonsterEvent",
		MonsterSpawnEvent = "MonsterSpawnEvent",
	},

	-- ==================== CONFIGURAÇÃO DE MONSTROS ====================
	Monsters = {
		{
			Name = "Monster",
			IsMainMonster = true,
			-- Velocidades
			PatrolSpeed = 16,
			InvestigateSpeed = 24,
			ChaseSpeed = 36,
			-- Visão e Dano
			SightDistance = 100,
			VisionRadius = 100,
			DamageAmount = 0,
			DamageDelay = 1.5,
			-- Jumpscare
			CanJumpscare = true,
			JumpscareCameraHeight = 1.10,
			JumpscareCameraZoomOut = 6,
			ExtraBangJumpscare = true,
			JumpscareEndTime = 1.3,
			-- Camera Shake
			CameraShakes = true,
			ShakeMagNear = 50,
			ShakeMagFar = 80,
			ShakeMagFarthest = 130,
			-- Comportamento
			HasEvents = true,
			IgnoreEventsDuration = 8, -- segundos para ignorar jogadores que já foram vistos
		},
		{
			Name = "Monster2",
			IsMainMonster = false,
			PatrolSpeed = 16,
			InvestigateSpeed = 16,
			ChaseSpeed = 20,
			SightDistance = 50,
			VisionRadius = 50,
			DamageAmount = 0,
			DamageDelay = 1.5,
			CanJumpscare = false,
			CameraShakes = true,
			ShakeMagNear = 30,
			ShakeMagFar = 60,
			ShakeMagFarthest = 100,
			HasEvents = false,
		},
	},

	-- ==================== CONFIGURAÇÃO DO PLAYER ====================
	Player = {
		WalkSpeed = 24,
		RunSpeed = 32,
		DroneSpeed = 26,
		JumpPower = 13,
	},

	-- ==================== LOCKER SYSTEM ====================
	Locker = {
		MaxDistance = 12, -- distância máxima para entrar no armário
		HidingSpotName = "HidingSpot",
		ExitSpotName = "ExitSpot",
		DoorPartName = "Door",
		DefaultExitOffset = 4, -- studs para fora da porta
		ActionText = "Esconder",
		ObjectText = "Armário",
		HoldDuration = 0.3,
		MaxActivationDistance = 5,
	},

	-- ==================== TIMINGS (Delays e Waits) ====================
	Timings = {
		-- Player Revival
		DeathCheckDelay = 10,
		RevivalCheckWait = 1,
		-- Cutscene
		CutsceneCompleteWait = 0.5,
		ExitDoorWaitTimeout = 10,
		-- Sounds
		AmbientStartWait = { Min = 1, Max = 5 },
		-- MonsterAI
		PositionCheckInterval = 0.5,
		StuckThreshold = 3.5,
		PathRecalcInterval = 0.2,
		ChaseTickRate = 0.07,
		PatrolTickRate = 0.15,
		-- Monster sounds
		PatrolSoundInterval = { Min = 15, Max = 35 },
		ChaseSoundCooldown = 8,
		ChaseMemoryDuration = 6,
	},

	-- ==================== CUTSCENES ====================
	Cutscenes = {
		Exit = {
			Module = "ExitCutscene",
			RemoteEvent = "ExitDoorCutscene",
			Setup = true,
		},
	},

	-- ==================== SONS AMBIENTES ====================
	AmbientSounds = {
		{
			Name = "AmbientHospital",
			Id = "rbxassetid://9112740464",
			Volume = 0.2,
			MinDelay = 5,
			MaxDelay = 10,
		},
		{
			Name = "DistantScreams",
			Id = "rbxassetid://86829351328919",
			Volume = 0.25,
			MinDelay = 40,
			MaxDelay = 120,
		},
		{
			Name = "ElectricalBuzz",
			Id = "rbxassetid://78958348163129",
			Volume = 0.3,
			MinDelay = 0,
			MaxDelay = 30,
		},
	},

	-- ==================== CONFIGURAÇÕES DE INVESTIGAÇÃO ====================
	Investigation = {
		CanInvestigateMultipleSounds = false,
		IgnoreNoiseWhileChasing = true,
	},

	-- ==================== NOMES E IDENTIFICADORES ====================
	Names = {
		MainMonsterTemplate = "Monster",
		ExitDoor = "ExitDoor",
		MonsterSpawn = "MonsterSpawn",
		MonstersFolder = "Monsters",
		MainLights = "MainLights",
		EmergencyLights = "EmergencyLights",
	},

	-- ==================== FLICKER (Power System) ====================
	Flicker = {
		intervalMin = 30,
		intervalMax = 90,
		blinkCount = 3,
		blinkOnTime = 0.08,
		blinkOffTime = 0.10,
		blackoutChance = 0.25,
		blackoutMin = 10,
		blackoutMax = 30,
	},

	-- ==================== REMATCH SYSTEM ====================
	Rematch = {
		PlaceId = 108541974835727,
		TimerDefault = 15, -- segundos para primeiro voto
		TimerAll = 3, -- segundos quando todos votam
	},

	-- ==================== MONSTER SOUNDS ====================
	MonsterSounds = {
		ScreamDurations = {
			Scream = { Min = 0.2, Max = 1.5 },
			Scream1 = { Min = 0.2, Max = 1.5 },
		},
		PatrolVolumeMultiplier = { Min = 0.7, Max = 0.9 },
		PlaybackSpeedRange = { Min = 0.1, Max = 5.0 },
	},

	-- ==================== PATHFINDING ====================
	Pathfinding = {
		MaxConsecutiveFails = 3,
		Configs = {
			{ radius = 3.5, height = 10 },
			{ radius = 2.0, height = 6 },
			{ radius = 1.2, height = 5 },
		},
		WaypointSpacing = 8,
		GlobalStuckThreshold = 4, -- segundos
	},

	-- ==================== FASES (será preenchido pelo ObjectiveSystem) ====================
	Phases = {
		-- Exemplo:
		-- [1] = { Phase = 1, Trigger = { Type = "immediate" }, Main = { ... } }
	},
}

return GameData
