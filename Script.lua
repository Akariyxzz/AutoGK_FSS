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

local function getActiveBalls()
	local Misc = workspace:FindFirstChild("Misc")

	if not Misc then
		return {}
	end

	local Balls = {}

	for _, Object in Misc:GetChildren() do
		if Object:IsA("BasePart")
			and Object.Name:sub(1, 9) == "Football "
			and Object:GetAttribute("Enabled") == true then
			Balls[#Balls + 1] = Object
		end
	end

	return Balls
end

local function getNearestBall(Position)
	local BestBall
	local BestDistance = math.huge

	for _, Ball in getActiveBalls() do
		local Distance = (Ball.Position - Position).Magnitude

		if Distance < BestDistance then
			BestDistance = Distance
			BestBall = Ball
		end
	end

	return BestBall
end

-- Threat priority:
-- 1. Opponent currently possessing the ball.
-- 2. Nearest active football.
--
-- We do not permanently follow the opponent. The selected threat itself
-- becomes the point the GK positions against.

local function getThreat()
	local MySide = getSide()

	if not MySide then
		return
	end

	local MyRoot = getRoot(LocalPlayer)

	if not MyRoot then
		return
	end

	-- Player comes first because we know exactly who is controlling the play.
	for _, Player in Players:GetPlayers() do
		if Player ~= LocalPlayer
			and Player:GetAttribute("IsOnPitch") == true
			and Player:GetAttribute("IsHomeOrAway") ~= MySide
			and Player:GetAttribute("HasBall") == true then

			local Root = getRoot(Player)

			if Root then
				return {
					Player = Player,
					Position = Root.Position,
					Type = "PLAYER",
				}
			end
		end
	end

	-- Nobody possesses it, so track the nearest active football instead.
	local Ball = getNearestBall(MyRoot.Position)

	if Ball then
		return {
			Ball = Ball,
			Position = Ball.Position,
			Type = "BALL",
		}
	end
end

local function getTrackingTarget(Goal, ThreatPosition, CurrentPosition)
	local GoalCFrame = Goal:GetPivot()
	local LocalThreat = GoalCFrame:PointToObjectSpace(ThreatPosition)

	-- The GK follows the threat's side-to-side position.
	-- Do not clamp this to the goal line; the GK is allowed to move
	-- slightly out and toward the play.

	local Lateral = math.clamp(
		LocalThreat.X,
		-14,
		14
	)

	-- Move forward when the threat is in front of the goal.
	-- The further the threat is from the goal line, the more the GK
	-- can step out, while still keeping a hard limit.
	local Forward = math.clamp(
		math.abs(LocalThreat.Z) * 0.22,
		0,
		5
	)

	-- Point toward the threat along the goal's local depth axis.
	local DepthSign = LocalThreat.Z >= 0 and 1 or -1

	local LocalTarget = Vector3.new(
		Lateral,
		0,
		DepthSign * Forward
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
