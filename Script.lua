-- Auto GK for FSS
-- Tracks opponent ball carriers and loose footballs without chasing
-- the football outside the goalkeeper's useful positioning area.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Knit = require(game:GetService("ReplicatedStorage").Packages.Knit)

local LocalPlayer = Players.LocalPlayer

local Running = true
local MovementController
local Leap
local LastJumpAt = 0
local LastDiveAt = 0
local PendingDiveBall
local PendingDiveStartedAt = 0
local LastOpponentCarrier
local LOW_BALL_Y = -230

local BALL_GRAVITY = 196.2
local PREDICTION_MIN_TIME = 0.08
local PREDICTION_MAX_TIME = 0.8
local PREDICTION_STEP = 0.03

local OVERHEAD_MIN_HEIGHT = 1.5
local OVERHEAD_MAX_HEIGHT = 10
local OVERHEAD_RADIUS = 9

local GOAL_LATERAL_LIMIT = 13
local SAFE_LATERAL_LIMIT = 7
local GOAL_MIN_DEPTH = 6
local GOAL_MAX_DEPTH = 12
local CAMERA_TRACK_WEIGHT = 0.65
local THREAT_TRACK_WEIGHT = 0.35
local SHOT_PREDICTION_TIME = 0.18
local SLOW_BALL_SPEED = 35
local SLOW_BALL_RANGE = 55
local CONTESTED_BALL_RADIUS = 12
local MOVE_THRESHOLD = 1.0
local DEBUG = true
local DebugLast = {}
_G.AutoGKDebug = {}

local function debug(Name, Value)
	if not DEBUG then
		return
	end

	local Text = tostring(Value)
	if DebugLast[Name] == Text then
		return
	end

	DebugLast[Name] = Text
	print("[AutoGK][" .. Name .. "]", Text)
end

pcall(function()
	MovementController = Knit.GetController("MovementController")
end)

pcall(function()
	Leap = require(
		LocalPlayer.PlayerScripts.Client.Controllers.Actions.Managers.Leap
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

	if Goal:IsA("BasePart") then
		return Goal
	end

	return Goal:FindFirstChild("InterceptionHitbox")
		or Goal:FindFirstChild("Hitbox")
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

local function getOpponentCarrier()
	local MySide = getSide()

	if not MySide then
		return
	end

	for _, Player in Players:GetPlayers() do
		if Player ~= LocalPlayer
			and Player:GetAttribute("IsOnPitch") == true
			and Player:GetAttribute("IsHomeOrAway") ~= MySide
			and Player:GetAttribute("HasBall") == true then

			local Root = getRoot(Player)

			if Root then
				return Player, Root
			end
		end
	end
end

local function getNearestFreeBall(Root)
	local BestBall
	local BestDistance = math.huge

	for _, Ball in getActiveBalls() do
		if Ball:GetAttribute("State") ~= "Possessed" then
			local Distance = (Ball.Position - Root.Position).Magnitude

			if Distance < BestDistance then
				BestDistance = Distance
				BestBall = Ball
			end
		end
	end

	return BestBall, BestDistance
end

local function predictBallPosition(Ball, Time)
	local Position = Ball.Position
	local Velocity = Ball.AssemblyLinearVelocity

	return Position
		+ Velocity * Time
		+ Vector3.new(0, -BALL_GRAVITY * 0.5 * Time * Time, 0)
end

local function getNearestOpponentDistance(Position)
	local Best = math.huge

	for _, Player in Players:GetPlayers() do
		if Player ~= LocalPlayer
			and Player:GetAttribute("IsOnPitch") == true
			and Player:GetAttribute("IsHomeOrAway") ~= getSide() then
			local Root = getRoot(Player)
			if Root then
				Best = math.min(Best, (Root.Position - Position).Magnitude)
			end
		end
	end

	return Best
end

local function getCameraGoalLateral(Goal)
	local CameraObject = workspace.CurrentCamera
	if not CameraObject then
		return 0
	end

	local P = Goal.CFrame:PointToObjectSpace(CameraObject.CFrame.Position)
	local D = Goal.CFrame:VectorToObjectSpace(CameraObject.CFrame.LookVector)

	if math.abs(D.Z) < 0.05 then
		return math.clamp(P.X, -GOAL_LATERAL_LIMIT, GOAL_LATERAL_LIMIT)
	end

	local T = -P.Z / D.Z
	return math.clamp(P.X + D.X * T, -GOAL_LATERAL_LIMIT, GOAL_LATERAL_LIMIT)
end

local function getThreatLateral(Goal, Position)
	local LocalPosition = Goal.CFrame:PointToObjectSpace(Position)
	return math.clamp(LocalPosition.X, -GOAL_LATERAL_LIMIT, GOAL_LATERAL_LIMIT)
end

local function getDefensiveLateral(Goal, Position)
	-- During an actual attacking threat, never let the camera pull the GK
	-- away from the goal mouth. Camera tracking is only used when there is
	-- no identified attacker/ball threat.
	return math.clamp(
		getThreatLateral(Goal, Position) * THREAT_TRACK_WEIGHT,
		-SAFE_LATERAL_LIMIT,
		SAFE_LATERAL_LIMIT
	)
end

local function getGoalTarget(Goal, Root, Lateral, Depth)
	local LocalRoot = Goal.CFrame:PointToObjectSpace(Root.Position)
	local DepthSign = LocalRoot.Z >= 0 and 1 or -1

	return Goal.CFrame:PointToWorldSpace(Vector3.new(
		math.clamp(Lateral, -GOAL_LATERAL_LIMIT, GOAL_LATERAL_LIMIT),
		0,
		DepthSign * math.clamp(Depth, GOAL_MIN_DEPTH, GOAL_MAX_DEPTH)
	))
end

local function moveToGoalTarget(Humanoid, Root, Goal, Lateral, Depth)
	local Target = getGoalTarget(Goal, Root, Lateral, Depth)

	if (Target - Root.Position).Magnitude <= MOVE_THRESHOLD then
		return
	end

	if MovementController then
		MovementController:SetSprintingControlState(
			(Target - Root.Position).Magnitude > 1.5
		)
	end

	Humanoid:MoveTo(Target)
end

local function isDangerousBall(Goal, Ball)
	local GoalCFrame = Goal.CFrame
	local LocalPosition = GoalCFrame:PointToObjectSpace(Ball.Position)
	local LocalVelocity = GoalCFrame:VectorToObjectSpace(Ball.AssemblyLinearVelocity)

	local GoalDirection = LocalPosition.Z >= 0 and -1 or 1
	local TowardGoalSpeed = LocalVelocity.Z * GoalDirection

	if TowardGoalSpeed <= 5 then
		return false
	end

	local TimeToPlane = math.abs(LocalPosition.Z) / TowardGoalSpeed
	if TimeToPlane < 0 or TimeToPlane > PREDICTION_MAX_TIME then
		return false
	end

	local Predicted = predictBallPosition(Ball, TimeToPlane)
	local LocalPredicted = GoalCFrame:PointToObjectSpace(Predicted)

	if math.abs(LocalPredicted.X) > GOAL_LATERAL_LIMIT + 2 then
		return false
	end

	if math.abs(LocalPredicted.Z) > 3 then
		return false
	end

	return true
end


local function shouldRecoverSlowBall(Ball, Distance)
	if not Ball or Distance > SLOW_BALL_RANGE then
		return false
	end

	if Ball.AssemblyLinearVelocity.Magnitude > SLOW_BALL_SPEED then
		return false
	end

	return getNearestOpponentDistance(Ball.Position) > CONTESTED_BALL_RADIUS
end


local function getOverheadPrediction(Ball, Root)
	local Velocity = Ball.AssemblyLinearVelocity

	-- Do not require the ball to still be rising. A shot can already be
	-- descending by the time it enters the GK's interception range.
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

			-- Use a much wider interception radius so shots coming toward
			-- either side of the GK are detected before they pass.
			if Horizontal.Magnitude <= OVERHEAD_RADIUS then
				return Predicted, Time
			end
		end
	end

	-- Extra safety check for a ball that is already high and moving
	-- toward the GK. This catches fast cross-goal shots between samples.
	local CurrentHeight = Ball.Position.Y - Root.Position.Y
	local HorizontalVelocity = Vector3.new(Velocity.X, 0, Velocity.Z)
	local ToGK = Vector3.new(
		Root.Position.X - Ball.Position.X,
		0,
		Root.Position.Z - Ball.Position.Z
	)

	if CurrentHeight >= OVERHEAD_MIN_HEIGHT
		and CurrentHeight <= OVERHEAD_MAX_HEIGHT
		and HorizontalVelocity.Magnitude > 1
		and ToGK.Magnitude <= OVERHEAD_RADIUS * 1.5 then

		local TowardGK = HorizontalVelocity.Unit:Dot(ToGK.Unit)

		if TowardGK > 0.15 then
			return Ball.Position, 0
		end
	end
end

local function getPlayerTrackingTarget(Goal, Player, Root)
	local ThreatRoot = Player.Character and Player.Character:FindFirstChild("HumanoidRootPart")
	if not ThreatRoot then
		return
	end

	local GoalPosition = Goal.Position
	local ThreatPosition = ThreatRoot.Position
	local ToThreat = Vector3.new(
		ThreatPosition.X - GoalPosition.X,
		0,
		ThreatPosition.Z - GoalPosition.Z
	)

	local DistanceFromGoal = ToThreat.Magnitude
	if DistanceFromGoal < 0.1 then
		return GoalPosition
	end

	local LocalThreat = Goal.CFrame:PointToObjectSpace(ThreatPosition)
	local Lateral = getDefensiveLateral(Goal, ThreatPosition)

	local AngleWidth = math.clamp(
		math.abs(LocalThreat.X) / math.max(math.abs(LocalThreat.Z), 1),
		0,
		1.5
	)

	local Forward = math.clamp(10 + AngleWidth * 5, 10, 17)
	Forward = math.min(Forward, math.max(DistanceFromGoal - 3, 6))

	return getGoalTarget(Goal, Root, Lateral, Forward)
end

local function getBallTrackingTarget(Goal, Ball, Root)
	local Predicted = predictBallPosition(Ball, 0.12)
	local LocalBall = Goal.CFrame:PointToObjectSpace(Predicted)
	local Lateral = getDefensiveLateral(Goal, Predicted)
	local Depth = math.clamp(math.abs(LocalBall.Z) * 0.15, GOAL_MIN_DEPTH, GOAL_MAX_DEPTH)

	return getGoalTarget(Goal, Root, Lateral, Depth)
end

local function tryDive(Goal, Ball, Root, Now)
	if not Leap or not Ball then
		return false
	end

	if Now - LastDiveAt < 1.0 then
		return false
	end

	local GoalCFrame = Goal:GetPivot()
	local Predicted = predictBallPosition(Ball, 0.18)
	local LocalBall = GoalCFrame:PointToObjectSpace(Predicted)

	-- Only dive for a ball that is actually threatening the goal.
	-- This prevents the GK from diving for harmless balls far upfield.
	local GoalDepth = math.abs(LocalBall.Z)
	if GoalDepth > 13 then
		return false
	end

	if math.abs(LocalBall.X) < 4.5 then
		return false
	end

	local Velocity = Ball.AssemblyLinearVelocity
	local LocalVelocity = GoalCFrame:VectorToObjectSpace(Velocity)

	-- The ball must be moving toward the goal plane.
	local GoalDirection = LocalBall.Z >= 0 and -1 or 1
	if LocalVelocity.Z * GoalDirection <= 5 then
		return false
	end

	-- Leap's Left/Right directions are relative to the GK's
	-- character orientation, not the goal's orientation.
	local CharacterBall = Root.CFrame:PointToObjectSpace(Predicted)

	if CharacterBall.X < 0 then
		Leap.Activate("Left")
		_G.AutoGKDebug.Dive = "LEFT"
	else
		Leap.Activate("Right")
		_G.AutoGKDebug.Dive = "RIGHT"
	end

	LastDiveAt = Now
	_G.AutoGKDebug.DiveBall = Ball
	_G.AutoGKDebug.DivePrediction = Predicted

	return true
end

local function trackCamera(Position)
	-- Camera is a read-only defensive reference. Never overwrite CurrentCamera.CFrame.
	debug("Camera", string.format("tracking x=%.2f z=%.2f", Position.X, Position.Z))
end

local function tryOverheadJump(Ball, Root, Humanoid, Now)
	if not Ball then
		return false
	end

	local Predicted, PredictionTime = getOverheadPrediction(
		Ball,
		Root
	)

	if not Predicted then
		return false
	end

	if Now - LastJumpAt < 0.55 then
		return false
	end

	if Humanoid.FloorMaterial ~= Enum.Material.Air then
		Humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
		LastJumpAt = Now
		PendingDiveBall = Ball
		PendingDiveStartedAt = Now
	end

	_G.AutoGKDebug.Jump = true
	_G.AutoGKDebug.JumpBall = Ball
	_G.AutoGKDebug.JumpPrediction = Predicted
	_G.AutoGKDebug.JumpPredictionTime = PredictionTime

	return true
end

local function tryPendingDive(Goal, Root, Humanoid, Now)
	if not PendingDiveBall then
		return false
	end

	local Ball = PendingDiveBall

	if not Ball.Parent or Ball:GetAttribute("Enabled") ~= true then
		PendingDiveBall = nil
		return false
	end

	-- Wait until the GK has actually risen and is near the apex.
	local VerticalVelocity = Root.AssemblyLinearVelocity.Y
	local Elapsed = Now - PendingDiveStartedAt

	if Elapsed < 0.12 or VerticalVelocity > 1 then
		return false
	end

	PendingDiveBall = nil

	if Now - LastDiveAt < 1.0 then
		return false
	end

	local Predicted = predictBallPosition(Ball, 0.08)
	local LocalBall = Root.CFrame:PointToObjectSpace(Predicted)

	if math.abs(LocalBall.X) < 2 then
		return false
	end

	if LocalBall.X < 0 then
		Leap.Activate("Left")
		_G.AutoGKDebug.Dive = "LEFT"
	else
		Leap.Activate("Right")
		_G.AutoGKDebug.Dive = "RIGHT"
	end

	LastDiveAt = Now
	_G.AutoGKDebug.DiveBall = Ball
	_G.AutoGKDebug.DivePrediction = Predicted

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
		if MovementController then
			MovementController:SetSprintingControlState(false)
		end
		return
	end

	local Now = os.clock()
	local Opponent, OpponentRoot = getOpponentCarrier()

	if Opponent and OpponentRoot then
		LastOpponentCarrier = Opponent
	end

	local Goal = getGoal()
	if not Goal then
		debug("Goal", "not found")
		return
	end

	local FreeBall, FreeBallDistance = getNearestFreeBall(Root)

	-- A ball far below the playable area is not a defensive target.
	if FreeBall and FreeBall.Position.Y <= LOW_BALL_Y and LastOpponentCarrier then
		local LastRoot = getRoot(LastOpponentCarrier)
		if LastRoot
			and LastOpponentCarrier:GetAttribute("IsOnPitch") == true
			and LastOpponentCarrier:GetAttribute("IsHomeOrAway") ~= getSide() then
			Opponent = LastOpponentCarrier
			OpponentRoot = LastRoot
			FreeBall = nil
		end
	end

	-- Finish a previous overhead reaction before starting another one.
	if tryPendingDive(Goal, Root, Humanoid, Now) then
		debug("Action", "APEX DIVE")
		return
	end

	-- Immediate shot reaction has priority over positioning.
	if FreeBall and isDangerousBall(Goal, FreeBall) then
		if tryOverheadJump(FreeBall, Root, Humanoid, Now) then
			debug("Action", "OVERHEAD JUMP")
			return
		end

		if tryDive(Goal, FreeBall, Root, Now) then
			debug("Action", "GROUND DIVE")
			return
		end
	end

	-- Recover a slow, uncontested loose ball instead of ignoring a free save.
	if FreeBall and shouldRecoverSlowBall(FreeBall, FreeBallDistance) then
		if FreeBallDistance <= 8 and Leap and Now - LastDiveAt >= 1 then
			local LocalBall = Root.CFrame:PointToObjectSpace(FreeBall.Position)
			if math.abs(LocalBall.X) >= 2 then
				if LocalBall.X < 0 then
					Leap.Activate("Left")
					debug("Action", "RECOVERY LEFT")
				else
					Leap.Activate("Right")
					debug("Action", "RECOVERY RIGHT")
				end
				LastDiveAt = Now
				return
			end
		end

		local Target = Vector3.new(FreeBall.Position.X, Root.Position.Y, FreeBall.Position.Z)
		if MovementController then
			MovementController:SetSprintingControlState(true)
		end
		Humanoid:MoveTo(Target)
		debug("Action", "RECOVER SLOW BALL")
		return
	end

	local Target

	if Opponent and OpponentRoot then
		Target = getPlayerTrackingTarget(Goal, Opponent, Root)
		debug("Threat", "PLAYER " .. Opponent.Name)
	elseif FreeBall and FreeBallDistance <= 45 then
		Target = getBallTrackingTarget(Goal, FreeBall, Root)
		debug("Threat", "BALL")
	else
		-- No immediate threat: track the camera's view across the goal while
		-- remaining at a safe depth instead of snapping to center.
		local CameraLateral = math.clamp(
			getCameraGoalLateral(Goal),
			-SAFE_LATERAL_LIMIT,
			SAFE_LATERAL_LIMIT
		)
		Target = getGoalTarget(Goal, Root, CameraLateral, 7)
		debug("Threat", "NONE / CAMERA")
	end

	if not Target then
		return
	end

	Target = Vector3.new(Target.X, Root.Position.Y, Target.Z)

	if (Target - Root.Position).Magnitude > MOVE_THRESHOLD then
		if MovementController then
			MovementController:SetSprintingControlState(
				(Target - Root.Position).Magnitude > 1.5
			)
		end
		Humanoid:MoveTo(Target)
end

	_G.AutoGKDebug.ThreatPlayer = Opponent
	_G.AutoGKDebug.ThreatBall = FreeBall
	_G.AutoGKDebug.ThreatType = Opponent and "PLAYER" or (FreeBall and "BALL" or "CAMERA")
	_G.AutoGKDebug.Target = Target
	_G.AutoGKDebug.DistanceToTarget = (Target - Root.Position).Magnitude

	debug("Target", string.format("x=%.2f z=%.2f", Goal.CFrame:PointToObjectSpace(Target).X, Goal.CFrame:PointToObjectSpace(Target).Z))
end

debug("Loaded", LocalPlayer.Name)
debug("Team", tostring(LocalPlayer:GetAttribute("TeamPosition")))
debug("Side", tostring(LocalPlayer:GetAttribute("IsHomeOrAway")))

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
