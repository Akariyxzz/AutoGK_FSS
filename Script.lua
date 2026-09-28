-- Auto GK for FSS
-- Tracking + loose-ball recovery + basic trajectory prediction.
--
-- The goalkeeper tracks the opponent when they have possession, predicts
-- free-ball movement using the live football velocity, and can jump when a
-- predicted shot enters a small overhead interception zone.

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
local LastJumpAt = 0

local BALL_GRAVITY = 196.2
local PREDICTION_MIN_TIME = 0.08
local PREDICTION_MAX_TIME = 0.55
local PREDICTION_STEP = 0.05

local OVERHEAD_MIN_HEIGHT = 1.5
local OVERHEAD_MAX_HEIGHT = 7
local OVERHEAD_RADIUS = 5

local GK_LOOSE_BALL_PLAYER_RADIUS = 15
local GK_LOOSE_BALL_DIVE_DISTANCE = 12
local GK_RECOVERY_MAX_LATERAL = 12
local GK_RECOVERY_TIME_MARGIN = 0.4
local PLAYER_RUN_SPEED = 27

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

local function predictBallPosition(Ball, Time)
	local Position = Ball.Position
	local Velocity = Ball.AssemblyLinearVelocity

	return Position
		+ Velocity * Time
		+ Vector3.new(0, -BALL_GRAVITY * 0.5 * Time * Time, 0)
end

local function getPredictedBallPosition(Ball, Root)
	local Velocity = Ball.AssemblyLinearVelocity
	local Speed = Velocity.Magnitude

	if Speed < 1 then
		return Ball.Position, 0
	end

	local Horizon = math.clamp(
		20 / Speed,
		PREDICTION_MIN_TIME,
		PREDICTION_MAX_TIME
	)

	return predictBallPosition(Ball, Horizon), Horizon
end

local function getOverheadPrediction(Ball, Root)
	local Velocity = Ball.AssemblyLinearVelocity

	if Velocity.Y <= 8 then
		return
	end

	for Time = PREDICTION_MIN_TIME, PREDICTION_MAX_TIME, PREDICTION_STEP do
		local Predicted = predictBallPosition(Ball, Time)
		local Height = Predicted.Y - Root.Position.Y

		if Height >= OVERHEAD_MIN_HEIGHT
			and Height <= OVERHEAD_MAX_HEIGHT then

			local Horizontal = Vector3.new(
				Predicted.X - Root.Position.X,
				0,
				Predicted.Z - Root.Position.Z
			)

			if Horizontal.Magnitude <= OVERHEAD_RADIUS then
				return Predicted, Time
			end
		end
	end
end

local function getTrackingTarget(Goal, Threat, Root)
	local GoalCFrame = Goal:GetPivot()

	if Threat.Type == "BALL" then
		local Predicted, PredictionTime = getPredictedBallPosition(
			Threat.Ball,
			Root
		)

		_G.AutoGKDebug.PredictedBall = Predicted
		_G.AutoGKDebug.PredictionTime = PredictionTime

		return Vector3.new(
			Predicted.X,
			Root.Position.Y,
			Predicted.Z
		)
	end

	local LocalThreat = GoalCFrame:PointToObjectSpace(Threat.Position)

	local Lateral = math.clamp(
		LocalThreat.X * 0.15,
		-4,
		4
	)

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

local function tryOverheadJump(Threat, Root, Humanoid, Now)
	if Threat.Type ~= "BALL" or not Threat.Ball then
		return false
	end

	local Ball = Threat.Ball
	local Predicted, PredictionTime = getOverheadPrediction(Ball, Root)

	if not Predicted then
		return false
	end

	if Now - LastJumpAt < 0.75 then
		return true
	end

	if Humanoid.FloorMaterial ~= Enum.Material.Air then
		Humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
		LastJumpAt = Now
	end

	_G.AutoGKDebug.Jump = true
	_G.AutoGKDebug.JumpPrediction = Predicted
	_G.AutoGKDebug.JumpPredictionTime = PredictionTime

	return true
end

local function getNearestOpponentToBall(Ball)
	local BallPosition = Ball.Position
	local MySide = getSide()

	local NearestPlayer
	local NearestDistance = math.huge

	for _, Player in Players:GetPlayers() do
		if Player ~= LocalPlayer
			and Player:GetAttribute("IsOnPitch") == true
			and Player:GetAttribute("IsHomeOrAway") ~= MySide then

			local Root = getRoot(Player)

			if Root then
				local Distance = (
					Vector3.new(Root.Position.X, 0, Root.Position.Z)
					- Vector3.new(BallPosition.X, 0, BallPosition.Z)
				).Magnitude

				if Distance < NearestDistance then
					NearestDistance = Distance
					NearestPlayer = Player
				end
			end
		end
	end

	return NearestPlayer, NearestDistance
end

local function tryLooseBallRecovery(Threat, Root, Humanoid, Now)
	if Threat.Type ~= "BALL" or not Threat.Ball then
		return false
	end

	local Ball = Threat.Ball
	local Goal = getGoal()

	if not Goal or not isBallInGoalkeeperArea(Ball) then
		return false
	end

	local GoalCFrame = Goal:GetPivot()
	local LocalBall = GoalCFrame:PointToObjectSpace(Ball.Position)

	-- Never chase a ball all the way to the side of the area. Keep enough
	-- central coverage that an opponent cannot simply take it and shoot
	-- into the now-open goal.
	if math.abs(LocalBall.X) > GK_RECOVERY_MAX_LATERAL then
		return false
	end

	local Opponent, OpponentDistance = getNearestOpponentToBall(Ball)

	if Opponent and OpponentDistance <= GK_LOOSE_BALL_PLAYER_RADIUS then
		return false
	end

	-- Estimate who reaches the ball first. If an opponent can get there
	-- before the GK (with a safety margin), stay home instead of gambling.
	local GKDistance = (
		Vector3.new(Root.Position.X, 0, Root.Position.Z)
		- Vector3.new(Ball.Position.X, 0, Ball.Position.Z)
	).Magnitude

	local GKTime = GKDistance / PLAYER_RUN_SPEED
	local OpponentTime = math.huge

	if Opponent then
		OpponentTime = OpponentDistance / PLAYER_RUN_SPEED
	end

	if OpponentTime <= GKTime + GK_RECOVERY_TIME_MARGIN then
		return false
	end

	local BallPosition = Ball.Position

	Humanoid:MoveTo(Vector3.new(
		BallPosition.X,
		Root.Position.Y,
		BallPosition.Z
	))

	if GKDistance <= GK_LOOSE_BALL_DIVE_DISTANCE
		and Now - LastDiveAt >= 1.25
		and Leap then
		Leap.Activate()
		LastDiveAt = Now
	end

	_G.AutoGKDebug.Recovery = true
	_G.AutoGKDebug.RecoveryBall = Ball
	_G.AutoGKDebug.RecoveryDistance = GKDistance
	_G.AutoGKDebug.RecoveryOpponentDistance = OpponentDistance
	_G.AutoGKDebug.RecoveryGKTime = GKTime
	_G.AutoGKDebug.RecoveryOpponentTime = OpponentTime

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
		Jump = false,
	}

	if tryOverheadJump(Threat, Root, Humanoid, Now) then
		trackCamera(Threat.Position)
		return
	end

	if tryLooseBallRecovery(Threat, Root, Humanoid, Now) then
		trackCamera(Threat.Position)
		return
	end

	local Target = getTrackingTarget(Goal, Threat, Root)

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
