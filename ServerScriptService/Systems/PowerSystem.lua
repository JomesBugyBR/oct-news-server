-- PowerSystem.lua (REFATORADO - Data-Driven)
local ServerStorage = game:GetService("ServerStorage")
local GameData = require(ServerStorage:WaitForChild("GameData"))

local PowerSystem = {}
PowerSystem.__index = PowerSystem

function PowerSystem.new(remoteEvents)
	local self = setmetatable({}, PowerSystem)
	self.RemoteEvents = remoteEvents
	self.GeneratorOn = false
	self._flickerActive = false
	return self
end

---------------------------------------------------------------------------
-- UTILS
---------------------------------------------------------------------------

local function setLights(folder, enabled)
	if not folder then return end
	for _, light in ipairs(folder:GetDescendants()) do
		if light:IsA("Light") then
			light.Enabled = enabled
		end
	end
end

local function setNeonMaterials(mainLightsFolder, lightsOn)
	if not mainLightsFolder then return end
	for _, part in ipairs(mainLightsFolder:GetDescendants()) do
		if part:IsA("BasePart") and part:GetAttribute("Neon") == true then
			part.Material = lightsOn and Enum.Material.Neon or Enum.Material.SmoothPlastic
		end
	end
end

---------------------------------------------------------------------------
-- FLICKER (Data-Driven)
---------------------------------------------------------------------------

function PowerSystem:_startFlicker(mainLights)
	self._flickerActive = true
	local cfg = GameData.config.Flicker

	task.spawn(function()
		while self._flickerActive and self.GeneratorOn do
			-- Intervalo aleatório do GameData
			local interval = cfg.intervalMin + math.random() * (cfg.intervalMax - cfg.intervalMin)
			task.wait(interval)

			if not self._flickerActive or not self.GeneratorOn then break end

			-- Pisca N vezes
			for _ = 1, cfg.blinkCount do
				setLights(mainLights, false)
				setNeonMaterials(mainLights, false)
				self.RemoteEvents.PowerUpdate:FireAllClients(false)
				task.wait(cfg.blinkOffTime)

				if not self._flickerActive or not self.GeneratorOn then return end

				setLights(mainLights, true)
				setNeonMaterials(mainLights, true)
				self.RemoteEvents.PowerUpdate:FireAllClients(true)
				task.wait(cfg.blinkOnTime)
			end

			-- Chance de apagão prolongado
			if math.random() < cfg.blackoutChance then
				local dur = cfg.blackoutMin + math.random() * (cfg.blackoutMax - cfg.blackoutMin)

				setLights(mainLights, false)
				setNeonMaterials(mainLights, false)
				self.RemoteEvents.PowerUpdate:FireAllClients(false)

				task.wait(dur)

				if not self._flickerActive or not self.GeneratorOn then return end

				setLights(mainLights, true)
				setNeonMaterials(mainLights, true)
				self.RemoteEvents.PowerUpdate:FireAllClients(true)
			end
		end
	end)
end

---------------------------------------------------------------------------
-- API PÚBLICA
---------------------------------------------------------------------------

function PowerSystem:SetGeneratorOn(state)
	if self.GeneratorOn == state then return end
	self.GeneratorOn = state

	-- Usar GameData para nomes de folders
	local lightsFolder = GameData.config.Folders.Lights
	if lightsFolder then
		local mainLights = lightsFolder:FindFirstChild(GameData.config.Names.MainLights)
		local emergencyLights = lightsFolder:FindFirstChild(GameData.config.Names.EmergencyLights)

		setLights(emergencyLights, not state)
		setLights(mainLights, state)
		setNeonMaterials(mainLights, state)

		if state then
			self:_startFlicker(mainLights)
		else
			self._flickerActive = false
		end
	end

	self.RemoteEvents.PowerUpdate:FireAllClients(state)
end

return PowerSystem
