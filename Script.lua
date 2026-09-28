-- Auto GK for FSS
-- Phase 1: tracking only.
--
-- No saves, dives, prediction, sprint control, or ball trajectory logic.
-- The goalkeeper first needs to continuously track the active attacker/ball.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera

local Running = true

local function getRoot(Player)
	local Character = Player.Character

	if not Character then
		return
	end

	return Character:FindFirstChild("HumanoidRootPart")
end

local function getSide()
	return LocalPlayer:GetAttribute("IsHomeOrAway")
end

local function getGoal()
	local Side = getSide()

	if Side ~= "Home" and Side ~= "Away" then
		return
	end

	local Stadium = workspace:FindFirstChild("Stadium")
	local Teams = Stadium and Stadium:FindFirstChild("Teams")
	local Team = Teams and Teams:FindFirstChild(Side)
	local Goal = Team and Team:FindFirstChild("Goal")

	if not Goal then
		return
	end

	return Goal
end

local function getThreat()
	local MySide = getSide()

	if not MySide then
		return
	end

	local BestPlayer
	local BestRoot
	local BestDistance = math.huge

	for _, Player in Players:GetPlayers() do
		if Player ~= LocalPlayer
			and Player:GetAttribute("IsOnPitch") == true
			and Player:GetAttribute("IsHomeOrAway") ~= MySide
			and Player:GetAttribute("HasBall") == true then

			local Root = getRoot(Player)

			if Root then
				local MyRoot = getRoot(LocalPlayer)

				if MyRoot then
					local Distance = (Root.Position - MyRoot.Position).Magnitude

					if Distance < BestDistance then
						BestDistance = Distance
						BestPlayer = Player
						BestRoot = Root
					end
				end
			end
		end
	end

	return BestPlayer, BestRoot
end

local function getTrackingTarget(Goal, ThreatPosition, CurrentPosition)
	local GoalCFrame = Goal:GetPivot()

	-- Convert the attacker into the goal's local space.
	-- X is the side-to-side position of the threat relative to the goal.
	local LocalThreat = GoalCFrame:PointToObjectSpace(ThreatPosition)

	-- Track the attacker's lateral position, but stay inside the goal area.
	local Lateral = math.clamp(
		LocalThreat.X,
		-14,
		14
	)

	-- Step forward a little as the attacker approaches.
	-- This is deliberately small; we are not trying to save the shot yet.
	local Depth = math.clamp(
		LocalThreat.Z * 0.12,
		-3,
		3
	)

	local LocalTarget = Vector3.new(
		Lateral,
		0,
		Depth
	)

	local WorldTarget = GoalCFrame:PointToWorldSpace(LocalTarget)

	return Vector3.new(
		WorldTarget.X,
		CurrentPosition.Y,
		WorldTarget.Z
	)
end

local function trackCamera(ThreatRoot)
	local CameraPosition = Camera.CFrame.Position
	local LookPosition = ThreatRoot.Position + Vector3.new(0, 1.5, 0)

	Camera.CFrame = CFrame.lookAt(
		CameraPosition,
		LookPosition
	)
end

local function update()
	if not Running then
		return
	end

	if LocalPlayer:GetAttribute("TeamPosition") ~= "GK" then
		return
	end

	local Character = LocalPlayer.Character
	local Humanoid = Character and Character:FindFirstChildOfClass("Humanoid")
	local Root = Character and Character:FindFirstChild("HumanoidRootPart")

	if not Humanoid or not Root or Humanoid.Health <= 0 then
		return
	end

	if LocalPlayer:GetAttribute("HasBall") == true then
		return
	end

	local Threat, ThreatRoot = getThreat()

	if not ThreatRoot then
		return
	end

	local Goal = getGoal()

	if not Goal then
		return
	end

	local Target = getTrackingTarget(
		Goal,
		ThreatRoot.Position,
		Root.Position
	)

	Humanoid:MoveTo(Target)

	_G.AutoGKDebug = {
		ThreatPlayer = Threat,
		ThreatPosition = ThreatRoot.Position,
		Target = Target,
	}

	trackCamera(ThreatRoot)
end

RunService.Heartbeat:Connect(update)

UserInputService.InputBegan:Connect(function(Input, GameProcessed)
	if GameProcessed then
		return
	end

	if Input.KeyCode ~= Enum.KeyCode.K then
		return
	end

	Running = false
	_G.AutoGKDebug = nil

	print("[AutoGK] stopped.")
end)
