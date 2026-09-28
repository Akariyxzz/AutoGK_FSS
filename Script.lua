-- Auto GK for FSS
-- Tracking + loose-ball recovery.
--
-- The goalkeeper tracks the opponent when they have possession, tracks free
-- footballs directly, and can leave the line to recover a loose ball that
-- has remained unpossessed for 3 seconds.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Knit = require(game:GetService("ReplicatedStorage").Packages.Knit)

local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera

local Running = true
local MovementController
local Leap
local LastDiveAt = 0

local FreeBallSince = {}

pcall(function()
	MovementController = Knit.GetController("MovementController")
end)

pcall(function()
	Leap = require(
		Players.LocalPlayer.PlayerScripts.Client.Controllers.Actions.Managers.Leap
	)
end)

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

local function getGoalkeeperArea()
	local Side = getSide()

	if Side ~= "Home" and Side ~= "Away" then
		return
	end

	local Stadium = workspace:FindFirstChild("Stadium")
	local Teams = Stadium and Stadium:FindFirstChild("Teams")
	local Team = Teams and Teams:FindFirstChild(Side)
	local Barriers = Team and Team:FindFirstChild("Barriers")
	local Goalkeeper = Barriers and Barriers:FindFirstChild("Goalkeeper")

	if not Goalkeeper then
		return
	end

	return Goalkeeper
end

local function isPointInPart(Point, Part)
	local LocalPoint = Part.CFrame:PointToObjectSpace(Point)
	local HalfSize = Part.Size * 0.5

	return math.abs(LocalPoint.X) <= HalfSize.X
		and math.abs(LocalPoint.Y) <= HalfSize.Y
		and math.abs(LocalPoint.Z) <= HalfSize.Z
end

local function isBallInGoalkeeperArea(Ball)
	local Area = getGoalkeeperArea()

	if not Area then
		return false
	end

	for _, Object in Area:GetDescendants() do
		if Object:IsA("BasePart") and Object.Name == "NoCharacter" then
			if isPointInPart(Ball.Position, Object) then
				return true
			end
		end
	end

	return false
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

local function getThreat()
	local MySide = getSide()

	if not MySide then
		return
	end

	local MyRoot = getRoot(LocalPlayer)

	if not MyRoot then
		return
	end

	-- A possessed football is hidden underground, so its Position is
	-- deliberately not used as the threat position. In that state,
	-- track the opponent who actually possesses it.
	local PossessingPlayer

	for _, Player in Players:GetPlayers() do
		if Player ~= LocalPlayer
			and Player:GetAttribute("IsOnPitch") == true
			and Player:GetAttribute("IsHomeOrAway") ~= MySide
			and Player:GetAttribute("HasBall") == true then

			local Root = getRoot(Player)

			if Root then
				PossessingPlayer = Player
				break
			end
		end
	end

	-- Prefer a genuinely free football. Possessed footballs are ignored.
	local BestBall
	local BestDistance = math.huge

	for _, Ball in getActiveBalls() do
		if Ball:GetAttribute("State") ~= "Possessed" then
			local Distance = (Ball.Position - MyRoot.Position).Magnitude

			if Distance < BestDistance then
				BestDistance = Distance
				BestBall = Ball
			end
		end
	end

	if BestBall then
		return {
			Ball = BestBall,
			Position = BestBall.Position,
			Type = "BALL",
		}
	end

	-- No free football: if somebody possesses it, use their position.
	if PossessingPlayer then
		local Root = getRoot(PossessingPlayer)

		if Root then
			return {
				Player = PossessingPlayer,
				Position = Root.Position,
				Type = "PLAYER",
			}
		end
	end
end

local function getTrackingTarget(Goal, Threat)
	local GoalCFrame = Goal:GetPivot()
	local LocalThreat = GoalCFrame:PointToObjectSpace(Threat.Position)

	-- A free ball is the actual target. Do not reduce or offset its lateral
	-- position: the GK should move directly to the ball.
	if Threat.Type == "BALL" then
		local WorldTarget = GoalCFrame:PointToWorldSpace(Vector3.new(
			LocalThreat.X,
			0,
			LocalThreat.Z
		))

		return WorldTarget
	end

	-- When an opponent has the ball, only follow a small amount of their
	-- lateral movement so they cannot drag the GK across most of the goal.
	local Lateral = math.clamp(
		LocalThreat.X * 0.15,
		-4,
		4
	)

	-- Stay somewhat off the line and toward the attacker.
	local DistanceFromGoal = math.abs(LocalThreat.Z)
	local Forward = math.clamp(
		DistanceFromGoal * 0.30,
		6,
		11
	)

	local DepthSign = LocalThreat.Z >= 0 and 1 or -1

	local LocalTarget = Vector3.new(
		Lateral,
		0,
		DepthSign * Forward
	)

	return GoalCFrame:PointToWorldSpace(LocalTarget)
end

local function trackCamera(ThreatPosition)
	local CameraPosition = Camera.CFrame.Position
	local LookPosition = ThreatPosition + Vector3.new(0, 1.5, 0)

	Camera.CFrame = CFrame.lookAt(
		CameraPosition,
		LookPosition
	)
end

local function updateFreeBallTimers(Balls, Now)
	local CurrentBalls = {}

	for _, Ball in Balls do
		CurrentBalls[Ball] = true

		if Ball:GetAttribute("State") == "Possessed" then
			FreeBallSince[Ball] = nil
		elseif not FreeBallSince[Ball] then
			FreeBallSince[Ball] = Now
		end
	end

	for Ball in pairs(FreeBallSince) do
		if not CurrentBalls[Ball] then
			FreeBallSince[Ball] = nil
		end
	end
end

local function tryLooseBallRecovery(Threat, Root, Humanoid, Now)
	if Threat.Type ~= "BALL" or not Threat.Ball then
		return false
	end

	local Ball = Threat.Ball
	local FreeSince = FreeBallSince[Ball]

	if not FreeSince or Now - FreeSince < 3 then
		return false
	end

	if not isBallInGoalkeeperArea(Ball) then
		return false
	end

	-- Run directly to the loose ball.
	local BallPosition = Ball.Position
	Humanoid:MoveTo(Vector3.new(
		BallPosition.X,
		Root.Position.Y,
		BallPosition.Z
	))

	-- Once close enough, use the game's actual forward Leap action to dive
	-- toward the ball. The Leap manager handles its own action cooldown.
	local Distance = (BallPosition - Root.Position).Magnitude

	if Distance <= 12
		and Now - LastDiveAt >= 1.25
		and Leap then
		Leap.Activate()
		LastDiveAt = Now
	end

	-- Also allow a normal jump when the ball is above the GK's body. This
	-- gives the goalkeeper a way to reach elevated loose balls.
	if BallPosition.Y - Root.Position.Y > 1.5
		and Distance <= 10
		and Humanoid.FloorMaterial ~= Enum.Material.Air then
		Humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
	end

	_G.AutoGKDebug.Recovery = true
	_G.AutoGKDebug.FreeFor = Now - FreeSince

	return true
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

	local Now = os.clock()
	local Balls = getActiveBalls()

	updateFreeBallTimers(Balls, Now)

	local Threat = getThreat()

	if not Threat then
		return
	end

	local Goal = getGoal()

	if not Goal then
		return
	end

	_G.AutoGKDebug = {
		ThreatPlayer = Threat.Player,
		ThreatBall = Threat.Ball,
		ThreatType = Threat.Type,
		ThreatPosition = Threat.Position,
		Recovery = false,
	}

	if tryLooseBallRecovery(Threat, Root, Humanoid, Now) then
		trackCamera(Threat.Position)
		return
	end

	local Target = getTrackingTarget(Goal, Threat)

	Target = Vector3.new(
		Target.X,
		Root.Position.Y,
		Target.Z
	)

	local DistanceToTarget = (Target - Root.Position).Magnitude

	if MovementController then
		MovementController:SetSprintingControlState(DistanceToTarget > 1.5)
	end

	Humanoid:MoveTo(Target)

	_G.AutoGKDebug.Target = Target
	_G.AutoGKDebug.DistanceToTarget = DistanceToTarget

	trackCamera(Threat.Position)
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

	if MovementController then
		MovementController:SetSprintingControlState(false)
	end

	_G.AutoGKDebug = nil

	print("[AutoGK] stopped.")
end)
