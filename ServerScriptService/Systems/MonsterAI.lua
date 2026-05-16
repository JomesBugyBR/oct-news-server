-- MonsterAI.lua (REFATORADO - Data-Driven Completo)
local PathfindingService = game:GetService("PathfindingService")
local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")

local GameData = require(ServerStorage:WaitForChild("GameData"))

local MonsterAI = {}
MonsterAI.__index = MonsterAI

local STATE_PATROL = "PATROL"
local STATE_INVESTIGATE = "INVESTIGATE"
local STATE_CHASE = "CHASE"

local LockerSystem = nil
pcall(function()
	LockerSystem = require(script.Parent:WaitForChild("LockerSystem"))
end)

-- Lê um atributo do modelo ou retorna do GameData
local function attr(model, name, fallback)
	local v = model:GetAttribute(name)
	if v ~= nil then return v end
	return fallback
end

function MonsterAI.new(remoteEvents)
	local self = setmetatable({}, MonsterAI)

	self.RemoteEvents = remoteEvents
	self.State = STATE_PATROL
	self.Monster = nil
	self.Humanoid = nil
	self.Root = nil
	self.Hitbox = nil
	self.Waypoints = {}
	self.CurrentWaypointIndex = 1
	self.LastNoisePos = nil
	self.TargetPlayer = nil

	self.PatrolSpeed = 16
	self.ChaseSpeed = 36
	self.SightDistance = 100
	self.MonsterSize = nil

	self.PlayerCooldowns = {}
	self.IgnoreUntil = {}
	self.IgnoreDuration = GameData.config.Monsters[1].IgnoreEventsDuration

	self.CurrentPathWaypoints = nil
	self.CurrentPathNode = 1
	self.LastPathDestination = nil
	self.PathRecalcInterval = GameData.config.Timings.PathRecalcInterval
	self.LastPathCompute = -999
	self.ConsecutivePathFails = 0
	self.MaxConsecutiveFails = GameData.config.Pathfinding.MaxConsecutiveFails

	self.StuckTimer = 0
	self.StuckThreshold = GameData.config.Timings.StuckThreshold
	self.LastValidPosition = nil
	self.LastPositionCheckTime = 0
	self.PositionCheckInterval = GameData.config.Timings.PositionCheckInterval

	self.WalkTrack = nil
	self.RunTrack = nil
	self.AnimState = "IDLE"

	self.PlayerRemovingConn = nil
	self.JumpscareActive = false
	self.LastChaseSoundTime = 0
	self.ChaseSoundCooldown = GameData.config.Timings.ChaseSoundCooldown

	self.LastKnownPlayerPos = nil
	self.LastSeenTime = 0
	self.ChaseMemoryDuration = GameData.config.Timings.ChaseMemoryDuration

	return self
end

function MonsterAI:Init(monsterModel, waypointsFolder)
	self.Monster = monsterModel
	self.Humanoid = monsterModel:WaitForChild("Humanoid")

	self.PatrolSpeed = attr(monsterModel, "PatrolSpeed") or GameData.config.Monsters[1].PatrolSpeed
	self.ChaseSpeed = attr(monsterModel, "ChaseSpeed") or GameData.config.Monsters[1].ChaseSpeed
	self.SightDistance = attr(monsterModel, "SightDistance") or GameData.config.Monsters[1].SightDistance
	self.DamageAmount = attr(monsterModel, "DamageAmount") or GameData.config.Monsters[1].DamageAmount
	self.DamageDelay = attr(monsterModel, "DamageDelay") or GameData.config.Monsters[1].DamageDelay
	self.CanJumpscare = attr(monsterModel, "CanJumpscare") or GameData.config.Monsters[1].CanJumpscare
	self.JumpscareCameraHeight = attr(monsterModel, "JumpscareCameraHeight") or GameData.config.Monsters[1].JumpscareCameraHeight
	self.JumpscareCameraZoomOut = attr(monsterModel, "JumpscareCameraZoomOut") or GameData.config.Monsters[1].JumpscareCameraZoomOut
	self.ExtraBangJumpscare = attr(monsterModel, "ExtraBangJumpscare") or GameData.config.Monsters[1].ExtraBangJumpscare
	self.JumpscareEndTime = attr(monsterModel, "JumpscareEndTime") or GameData.config.Monsters[1].JumpscareEndTime
	self.CameraShakes = attr(monsterModel, "CameraShakes") or GameData.config.Monsters[1].CameraShakes
	self.ShakeMagNear = attr(monsterModel, "ShakeMagNear") or GameData.config.Monsters[1].ShakeMagNear
	self.ShakeMagFar = attr(monsterModel, "ShakeMagFar") or GameData.config.Monsters[1].ShakeMagFar
	self.ShakeMagFarthest = attr(monsterModel, "ShakeMagFarthest") or GameData.config.Monsters[1].ShakeMagFarthest

	self.MonsterSize = self.Monster:GetExtentsSize()
	self.Root = monsterModel:WaitForChild("HumanoidRootPart")

	for _, part in ipairs(self.Monster:GetDescendants()) do
		if part:IsA("BasePart") and part:CanSetNetworkOwnership() then
			part:SetNetworkOwner(nil)
		end
	end

	if waypointsFolder then
		for _, wp in ipairs(waypointsFolder:GetChildren()) do
			if wp:IsA("BasePart") then
				table.insert(self.Waypoints, wp)
			end
		end
	end

	if self.Root.Position.Y < 0 and #self.Waypoints > 0 then
		local firstWaypoint = self.Waypoints[1]
		if firstWaypoint then
			self.Root.CFrame = CFrame.new(firstWaypoint.Position + Vector3.new(0, 5, 0))
		end
	end

	self.SafeZonesFolder = GameData.config.Folders.SafeZones
	self:CacheSafeZones()

	self:CreateHitbox()
	self:SetupCollisions()
	self:SetupAnimations()
	self:SetupFootsteps()
	self:SetupStateSounds()
	self:BindAttack()
	self:StartLoop(self.StartDelay or 0)

	self.PlayerRemovingConn = Players.PlayerRemoving:Connect(function(player)
		self.PlayerCooldowns[player.UserId] = nil
		self.IgnoreUntil[player.UserId] = nil
	end)

	monsterModel.AncestryChanged:Connect(function()
		if not monsterModel.Parent then
			self:Destroy()
		end
	end)
end

function MonsterAI:CacheSafeZones()
	self.SafeZones = {}
	if self.SafeZonesFolder then
		for _, zone in ipairs(self.SafeZonesFolder:GetDescendants()) do
			if zone:IsA("BasePart") then
				table.insert(self.SafeZones, zone)
			end
		end
	end
end

function MonsterAI:CreateHitbox()
	local hitbox = self.Monster:FindFirstChild("Hitbox")
	if not hitbox then
		hitbox = Instance.new("Part")
		hitbox.Name = "Hitbox"
		hitbox.Transparency = 1
		hitbox.CanCollide = false
		hitbox.CanQuery = false
		hitbox.CanTouch = true
		hitbox.Massless = true

		local bboxCFrame, bboxSize = self.Monster:GetBoundingBox()
		hitbox.Size = Vector3.new(
			math.max(4, bboxSize.X * 0.85),
			math.max(8, bboxSize.Y * 0.95),
			math.max(4, bboxSize.Z * 0.85)
		)
		hitbox.CFrame = bboxCFrame
		hitbox.Parent = self.Monster

		local weld = Instance.new("WeldConstraint")
		weld.Part0 = hitbox
		weld.Part1 = self.Root
		weld.Parent = hitbox
	end

	self.Hitbox = hitbox
end

function MonsterAI:SetupAnimations() end
function MonsterAI:PlayAnimation(animType) end
function MonsterAI:SetupFootsteps() end

function MonsterAI:GetGroundPoint(worldPos, ignoreList)
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude

	local filter = { self.Monster }

	if ignoreList then
		if typeof(ignoreList) == "Instance" then
			table.insert(filter, ignoreList)
		elseif typeof(ignoreList) == "table" then
			for _, obj in ipairs(ignoreList) do
				if typeof(obj) == "Instance" then
					table.insert(filter, obj)
				end
			end
		end
	end

	rayParams.FilterDescendantsInstances = filter

	local origin = worldPos + Vector3.new(0, 10, 0)
	local direction = Vector3.new(0, -80, 0)

	local result = workspace:Raycast(origin, direction, rayParams)
	if result then
		return result.Position + Vector3.new(0, 0.15, 0)
	end

	return worldPos
end

function MonsterAI:BindAttack() end

function MonsterAI:FindVisiblePlayer()
	local nearest = nil
	local nearestDist = self.SightDistance

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = { self.Monster }

	for _, player in ipairs(Players:GetPlayers()) do

		if LockerSystem and LockerSystem:IsHidden(player) then
			continue
		end

		local character = player.Character
		if character then
			local root = character:FindFirstChild("HumanoidRootPart")
			local humanoid = character:FindFirstChildOfClass("Humanoid")

			if root and humanoid and humanoid.Health > 0 then
				local now = os.clock()
				local skipTarget = false

				local ignoreUntil = self.IgnoreUntil[player.UserId]
				if ignoreUntil and ignoreUntil > now then
					skipTarget = true
				elseif self.SafeZonesFolder and self:IsInSafeZone(root.Position) then
					self.IgnoreUntil[player.UserId] = now + 1.5
					skipTarget = true
				end

				if not skipTarget then
					local direction = root.Position - self.Root.Position
					local dist = direction.Magnitude

					if dist > 0 and dist < nearestDist then
						local monsterLook = self.Root.CFrame.LookVector
						local toPlayer = direction.Unit
						local dot = monsterLook:Dot(toPlayer)
						if dot < -0.2 then continue end

						local origins = {
							self.Root.Position,
							self.Root.Position - Vector3.new(0, 4, 0),
							self.Root.Position - Vector3.new(0, self.MonsterSize.Y * 0.45, 0),
						}

						local seen = false
						for _, origin in ipairs(origins) do
							local dir = (root.Position - origin).Unit * math.min(dist, self.SightDistance)
							local result = workspace:Raycast(origin, dir, rayParams)
							if result and result.Instance and result.Instance:IsDescendantOf(character) then
								seen = true
								break
							end
						end

						if seen then
							nearest = player
							nearestDist = dist
						end
					end
				end
			end
		end
	end

	return nearest
end

function MonsterAI:IsInSafeZone(position)
	if not self.SafeZones then return false end

	for _, zone in ipairs(self.SafeZones) do
		local localPos = zone.CFrame:PointToObjectSpace(position)
		local half = zone.Size * 0.5
		if math.abs(localPos.X) <= half.X and math.abs(localPos.Y) <= half.Y and math.abs(localPos.Z) <= half.Z then
			return true
		end
	end

	return false
end

function MonsterAI:SetupCollisions()
	local bodyParts = { "HumanoidRootPart", "LeftFoot", "RightFoot" }
	local bodyPartSet = {}
	for _, name in ipairs(bodyParts) do
		bodyPartSet[name] = true
	end

	for _, part in ipairs(self.Monster:GetDescendants()) do
		if part:IsA("BasePart") then
			if part.Name == "Hitbox" then
				part.CanCollide = false
			elseif bodyPartSet[part.Name] then
				part.CanCollide = true
			else
				part.CanCollide = false
			end
		end
	end
end

function MonsterAI:ResetPathfinding()
	self.CurrentPathWaypoints = nil
	self.CurrentPathNode = 1
	self.LastPathDestination = nil
	self.LastMoveTo = nil
	self.LastPathCompute = -999
	if self.PathBlockedConn then
		self.PathBlockedConn:Disconnect()
		self.PathBlockedConn = nil
	end
end

function MonsterAI:ComputePath(startPos, endPos, ignoreList)
	local startGround = self:GetGroundPoint(startPos, ignoreList)
	local endGround = self:GetGroundPoint(endPos, ignoreList)

	-- Usar GameData para configs de pathfinding
	local configs = GameData.config.Pathfinding.Configs

	for _, cfg in ipairs(configs) do
		local path = PathfindingService:CreatePath({
			AgentRadius = cfg.radius,
			AgentHeight = cfg.height,
			AgentCanJump = true,
			WaypointSpacing = GameData.config.Pathfinding.WaypointSpacing,
		})

		local success = pcall(function()
			path:ComputeAsync(startGround, endGround)
		end)

		if success and path.Status == Enum.PathStatus.Success then
			return path
		end
	end

	return nil
end

function MonsterAI:MoveTo(targetPosition, isChasing, ignoreList)
	local now = os.clock()
	local currentPos = self.Root.Position
	local targetGround = self:GetGroundPoint(targetPosition, ignoreList)

	local destinationChanged = not self.LastPathDestination
		or (self.LastPathDestination - targetGround).Magnitude > (isChasing and 8 or 10)

	local pathFinished = not self.CurrentPathWaypoints or self.CurrentPathNode > #self.CurrentPathWaypoints
	local shouldRepath = destinationChanged or pathFinished

	local repathCooldown = isChasing and 0.25 or 0.35

	if shouldRepath and (now - self.LastPathCompute >= repathCooldown) then
		self.LastPathCompute = now
		self.LastPathDestination = targetGround

		if self.PathBlockedConn then
			self.PathBlockedConn:Disconnect()
			self.PathBlockedConn = nil
		end

		local path = self:ComputePath(currentPos, targetGround, ignoreList)
		if path then
			local waypoints = path:GetWaypoints()

			if #waypoints >= 2 then
				table.remove(waypoints, 1)
				self.CurrentPathWaypoints = waypoints
				self.CurrentPathNode = 1
				self.ConsecutivePathFails = 0

				self.PathBlockedConn = path.Blocked:Connect(function(blockedIndex)
					if blockedIndex >= self.CurrentPathNode then
						self.CurrentPathWaypoints = nil
						self.CurrentPathNode = 1
						self.LastPathDestination = nil
						self.ConsecutivePathFails += 1
					end
				end)
			else
				self.CurrentPathWaypoints = nil
				self.CurrentPathNode = 1
				self.ConsecutivePathFails += 1
			end
		else
			self.CurrentPathWaypoints = nil
			self.CurrentPathNode = 1
			self.ConsecutivePathFails += 1
		end
	end

	if self.ConsecutivePathFails >= self.MaxConsecutiveFails then
		self:ResetPathfinding()
		self.Humanoid:MoveTo(currentPos)
		return
	end

	local waypoint = self.CurrentPathWaypoints and self.CurrentPathWaypoints[self.CurrentPathNode]
	if waypoint then
		local wpPos = waypoint.Position
		local flatDist = (Vector3.new(currentPos.X, 0, currentPos.Z) - Vector3.new(wpPos.X, 0, wpPos.Z)).Magnitude

		if waypoint.Action == Enum.PathWaypointAction.Jump then
			self.Humanoid.Jump = true
		end

		if flatDist < 8 then
			self.CurrentPathNode += 1
			waypoint = self.CurrentPathWaypoints[self.CurrentPathNode]

			if waypoint then
				if waypoint.Action == Enum.PathWaypointAction.Jump then
					self.Humanoid.Jump = true
				end
				local nextPos = waypoint.Position

				if not self.LastMoveTo or (self.LastMoveTo - nextPos).Magnitude > 1 then
					self.LastMoveTo = nextPos
					self.Humanoid:MoveTo(nextPos)
				end
			else
				self.CurrentPathWaypoints = nil
			end
		else
			if isChasing then
				self.LastMoveTo = wpPos
				self.Humanoid:MoveTo(wpPos)
			else
				if not self.LastMoveTo or (self.LastMoveTo - wpPos).Magnitude > 1 then
					self.LastMoveTo = wpPos
					self.Humanoid:MoveTo(wpPos)
				end
			end
		end
	else
		if not self.LastMoveTo or (self.LastMoveTo - targetGround).Magnitude > 1 then
			self.LastMoveTo = targetGround
			self.Humanoid:MoveTo(targetGround)
		end
	end
end

function MonsterAI:Patrol()
	if #self.Waypoints == 0 then return end

	if self.ConsecutivePathFails >= self.MaxConsecutiveFails then
		self.ConsecutivePathFails = 0
		local tried = 0
		local found = false
		local original = self.CurrentWaypointIndex

		while tried < math.min(2, #self.Waypoints - 1) do
			local newIndex
			repeat
				newIndex = math.random(1, #self.Waypoints)
			until newIndex ~= self.CurrentWaypointIndex
			self.CurrentWaypointIndex = newIndex
			tried += 1

			local testPath = self:ComputePath(self.Root.Position, self.Waypoints[newIndex].Position, nil)
			if testPath then
				found = true
				break
			end
		end

		if not found then
			self.CurrentWaypointIndex = original
		end

		self:ResetPathfinding()
		return
	end

	self.Humanoid.WalkSpeed = self.PatrolSpeed
	self:PlayAnimation("WALK")

	local targetWaypoint = self.Waypoints[self.CurrentWaypointIndex]
	self:MoveTo(targetWaypoint.Position, false)

	local flatRootPos = Vector3.new(self.Root.Position.X, 0, self.Root.Position.Z)
	local flatTargetPos = Vector3.new(targetWaypoint.Position.X, 0, targetWaypoint.Position.Z)

	if (flatRootPos - flatTargetPos).Magnitude < 10 then
		self.ConsecutivePathFails = 0
		if #self.Waypoints > 1 then
			local nearby = {}
			for i, wp in ipairs(self.Waypoints) do
				if i ~= self.CurrentWaypointIndex then
					local d = (self.Root.Position - wp.Position).Magnitude
					if d < 120 then
						table.insert(nearby, i)
					end
				end
			end

			local pool = #nearby > 0 and nearby or nil
			if not pool then
				pool = {}
				for i = 1, #self.Waypoints do
					if i ~= self.CurrentWaypointIndex then
						table.insert(pool, i)
					end
				end
			end

			self.CurrentWaypointIndex = pool[math.random(1, #pool)]
		end
		self:ResetPathfinding()
	end
end

function MonsterAI:Investigate()
	if not self.Root or not self.Root.Parent then return end
	if not self.LastNoisePos then
		self.State = STATE_PATROL
		self:ResetPathfinding()
		return
	end

	if self.ConsecutivePathFails >= self.MaxConsecutiveFails then
		print("⚠️ Ponto de investigação inacessível, voltando a patrulhar")
		self.LastNoisePos = nil
		self.ConsecutivePathFails = 0
		self.State = STATE_PATROL
		self:ResetPathfinding()
		return
	end

	self.Humanoid.WalkSpeed = self.PatrolSpeed
	self:PlayAnimation("WALK")
	self:MoveTo(self.LastNoisePos, false)

	local flatRootPos = Vector3.new(self.Root.Position.X, 0, self.Root.Position.Z)
	if not self.LastNoisePos then return end
	local flatNoisePos = Vector3.new(self.LastNoisePos.X, 0, self.LastNoisePos.Z)

	if (flatRootPos - flatNoisePos).Magnitude < 10 then
		self.LastNoisePos = nil
		self.State = STATE_PATROL
		self:ResetPathfinding()
	end
end

function MonsterAI:Chase(player)
	self.TargetPlayer = player

	local character = player.Character
	if not character then self:ResetToPatrol(); return end

	local root = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChildOfClass("Humanoid")

	if not root or not humanoid or humanoid.Health <= 0 then
		self:ResetToPatrol()
		return
	end

	local distance = (root.Position - self.Root.Position).Magnitude

	if self.SafeZonesFolder and self:IsInSafeZone(root.Position) then
		self.IgnoreUntil[player.UserId] = os.clock() + self.IgnoreDuration
		self:ResetToPatrol()
		return
	end

	if self.ConsecutivePathFails >= self.MaxConsecutiveFails then
		self.ConsecutivePathFails = 0
		self:ResetPathfinding()
	end

	local now = os.clock()
	if now - self.LastPositionCheckTime >= self.PositionCheckInterval then
		local currentPos = self.Root.Position
		local posDelta = self.LastValidPosition and (currentPos - self.LastValidPosition).Magnitude or 10

		if distance > 5 and posDelta < 1.2 then
			self.StuckTimer += self.PositionCheckInterval
		else
			self.StuckTimer = math.max(0, self.StuckTimer - self.PositionCheckInterval)
		end

		self.LastValidPosition = currentPos
		self.LastPositionCheckTime = now
	end

	if self.StuckTimer > self.StuckThreshold then
		self.StuckTimer = 0
		self:ResetPathfinding()

		if #self.Waypoints > 0 then
			local candidates = {}
			for _, wp in ipairs(self.Waypoints) do
				if (self.Root.Position - wp.Position).Magnitude < 80 then
					table.insert(candidates, wp)
				end
			end
			if #candidates == 0 then candidates = self.Waypoints end

			local escapeWaypoint = candidates[math.random(1, #candidates)]
			self.State = STATE_INVESTIGATE
			self.LastNoisePos = escapeWaypoint.Position
			self.TargetPlayer = nil
		end

		self.TargetPlayer = nil
		return
	end

	self.Humanoid.WalkSpeed = self.ChaseSpeed
	self:PlayAnimation("RUN")

	self:MoveTo(root.Position, true, character)
end

function MonsterAI:ResetToPatrol()
	self.State = STATE_PATROL
	self.TargetPlayer = nil
	self.LastNoisePos = nil
	self.StuckTimer = 0
	self:ResetPathfinding()
	self.Humanoid:Move(Vector3.new(0, 0, 0))
end

function MonsterAI:Destroy()
	self._dead = true
	if self.PlayerRemovingConn then
		self.PlayerRemovingConn:Disconnect()
		self.PlayerRemovingConn = nil
	end

	if self.Monster then
		self.Monster:Destroy()
	end
end

function MonsterAI:GlobalStuckCheck()
	if not self.Root or not self.Root.Parent then return end
	if self.State == STATE_CHASE then
		self.GlobalStuckTimer = 0
		return
	end

	local now = os.clock()
	if now - self.LastPositionCheckTime < self.PositionCheckInterval then return end

	local currentPos = self.Root.Position
	local posDelta = self.LastValidPosition and (currentPos - self.LastValidPosition).Magnitude or 10

	local shouldBeMoving = self.State == STATE_PATROL
		or self.State == STATE_INVESTIGATE
		or self.State == STATE_CHASE

	if shouldBeMoving and posDelta < 1.2 then
		self.GlobalStuckTimer = (self.GlobalStuckTimer or 0) + self.PositionCheckInterval
	else
		self.GlobalStuckTimer = math.max(0, (self.GlobalStuckTimer or 0) - self.PositionCheckInterval)
	end

	self.LastValidPosition = currentPos
	self.LastPositionCheckTime = now

	-- Usar GameData para limiar global de travamento
	if (self.GlobalStuckTimer or 0) > GameData.config.Pathfinding.GlobalStuckThreshold then
		self.GlobalStuckTimer = 0
		self:TeleportToNearestWaypoint()
	end
end

function MonsterAI:TeleportToNearestWaypoint()
	if #self.Waypoints == 0 then return end

	print("🔧 GlobalStuck detectado em estado: " .. self.State .. " — indo para waypoint mais próximo")

	local sorted = {}
	for _, wp in ipairs(self.Waypoints) do
		table.insert(sorted, {
			Waypoint = wp,
			Distance = (self.Root.Position - wp.Position).Magnitude
		})
	end
	table.sort(sorted, function(a, b) return a.Distance < b.Distance end)

	for i = 1, math.min(3, #sorted) do
		local wp = sorted[i].Waypoint
		local path = self:ComputePath(self.Root.Position, wp.Position, nil)

		if path then
			print("✅ Waypoint acessível encontrado: " .. wp.Name)
			self.ConsecutivePathFails = 0
			self.StuckTimer = 0
			self:ResetPathfinding()

			self.LastNoisePos = wp.Position
			self.State = STATE_INVESTIGATE
			self.TargetPlayer = nil
			return
		end
	end

	local nearest = sorted[1].Waypoint
	warn("⚠️ Nenhum path encontrado, teleportando para: " .. nearest.Name)
	self.Root.CFrame = CFrame.new(nearest.Position + Vector3.new(0, 5, 0))
	self.ConsecutivePathFails = 0
	self.StuckTimer = 0
	self:ResetPathfinding()
	self.State = STATE_PATROL
end

function MonsterAI:SetupStateSounds()
	local head = self.Monster:FindFirstChild("Head")
	if not head then return end

	self.SoundScream = head:FindFirstChild("Scream")
	self.SoundScream1 = head:FindFirstChild("Scream1")
	self.SoundPlaying = false
	self.LastPatrolSound = os.clock()

	-- Usar GameData para intervalo de som
	local interval = GameData.config.Timings.PatrolSoundInterval
	self.NextPatrolInterval = math.random(interval.Min, interval.Max)
end

function MonsterAI:PlayStateSound(volumeOverride)
	if self.SoundPlaying then return end
	if not self.SoundScream and not self.SoundScream1 then return end

	local sounds = {}
	if self.SoundScream then table.insert(sounds, { Sound = self.SoundScream, Name = "Scream" }) end
	if self.SoundScream1 then table.insert(sounds, { Sound = self.SoundScream1, Name = "Scream1" }) end

	local chosen = sounds[math.random(1, #sounds)]
	local sound = chosen.Sound
	local cfg = GameData.config.MonsterSounds.ScreamDurations[chosen.Name]

	local originalVolume = sound.Volume
	if volumeOverride then
		local mult = GameData.config.MonsterSounds.PatrolVolumeMultiplier
		local multiplier = math.random(mult.Min * 100, mult.Max * 100) / 100
		sound.Volume = originalVolume * multiplier
	end

	local playDuration = cfg.Min + math.random() * (cfg.Max - cfg.Min)

	self.SoundPlaying = true
	sound:Play()

	task.delay(playDuration, function()
		sound:Stop()
		sound.Volume = originalVolume
		self.SoundPlaying = false
	end)
end

function MonsterAI:StartLoop(delaySeconds)
	task.spawn(function()
		if delaySeconds and delaySeconds > 0 then
			self.Humanoid.WalkSpeed = 0
			task.wait(delaySeconds)
			self.Humanoid.WalkSpeed = self.PatrolSpeed
		end

		while self.Monster and self.Monster.Parent
			and self.Humanoid and self.Humanoid.Parent
			and self.Humanoid.Health > 0
			and not self._dead do

			self:GlobalStuckCheck()

			local visiblePlayer = self:FindVisiblePlayer()
			local now = os.clock()

			if visiblePlayer then
				self.LastKnownPlayerPos = visiblePlayer.Character.HumanoidRootPart.Position
				self.LastSeenTime = now

				if self.State ~= STATE_CHASE then
					self.State = STATE_CHASE
					self:ResetPathfinding()
					self.LastPathCompute = -999

					if now - self.LastChaseSoundTime >= self.ChaseSoundCooldown then
						self.LastChaseSoundTime = now
						self:PlayStateSound()
					end
				end
				self.TargetPlayer = visiblePlayer

			elseif self.State == STATE_CHASE then
				if now - self.LastSeenTime < self.ChaseMemoryDuration then
					if self.LastKnownPlayerPos then
						self.State = STATE_INVESTIGATE
						self.LastNoisePos = self.LastKnownPlayerPos
						self.TargetPlayer = nil
						self:ResetPathfinding()
						self:PlayStateSound()
					else
						self:ResetToPatrol()
					end
				else
					self:ResetToPatrol()
				end
			end

			if self.State == STATE_CHASE and self.TargetPlayer then
				self:Chase(self.TargetPlayer)
			elseif self.State == STATE_INVESTIGATE then
				self:Investigate()
			else
				self.State = STATE_PATROL
				self:Patrol()

				local now2 = os.clock()
				if now2 - self.LastPatrolSound >= self.NextPatrolInterval then
					self.LastPatrolSound = now2
					local interval = GameData.config.Timings.PatrolSoundInterval
					self.NextPatrolInterval = math.random(interval.Min, interval.Max)
					self:PlayStateSound(true)
				end
			end

			-- Usar GameData para tick rate
			local tickRate = (self.State == STATE_CHASE) 
				and GameData.config.Timings.ChaseTickRate 
				or GameData.config.Timings.PatrolTickRate
			task.wait(tickRate)
		end
	end)
end

return MonsterAI
