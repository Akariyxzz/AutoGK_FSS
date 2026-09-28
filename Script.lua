-- Auto GK for FSS
-- Tracks opponent ball carriers and loose footballs without chasing
-- the football outside the goalkeeper's useful positioning area.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Knit = require(game:GetService("ReplicatedStorage").Packages.Knit)

local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera

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

	return BestBall
end

local function predictBallPosition(Ball, Time)
	local Position = Ball.Position
	local Velocity = Ball.AssemblyLinearVelocity

	return Position
		+ Velocity * Time
		+ Vector3.new(0, -BALL_GRAVITY * 0.5 * Time * Time, 0)
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

local function getPlayerTrackingTarget(Goal, Player)
	local GoalCFrame = Goal:GetPivot()
	local LocalThreat = GoalCFrame:PointToObjectSpace(
		Player.Character.HumanoidRootPart.Position
	)

	-- Position the GK to cover the shooter's available goal angles.
	-- A very wide angle makes the far post harder to reach, so move
	-- slightly forward to reduce the shot angle. A central shooter can
	-- stay deeper because both sides of the goal are already covered.
	local DistanceFromGoal = math.abs(LocalThreat.Z)
	local DepthSign = LocalThreat.Z >= 0 and 1 or -1

	local BaseDepth = 7
	local AngleWidth = math.clamp(
		math.abs(LocalThreat.X) / math.max(DistanceFromGoal, 1),
		0,
		1.2
	)

	-- Forward movement closes the shooting angle. Keep it conservative
	-- so the GK does not abandon the goal line.
	local Forward = math.clamp(
		BaseDepth + AngleWidth * 6,
		6,
		13
	)

	-- Match the GK laterally to the shooter's angle, but leave enough
	-- room on the opposite side for a far-post shot.
	local Lateral = LocalThreat.X * math.clamp(
		Forward / math.max(DistanceFromGoal, 1),
		0,
		0.9
	)

	Lateral = math.clamp(Lateral, -13, 13)

	return GoalCFrame:PointToWorldSpace(Vector3.new(
		Lateral,
		0,
		DepthSign * Forward
	))
end

local function getBallTrackingTarget(Goal, Ball)
	local GoalCFrame = Goal:GetPivot()
	local Predicted = predictBallPosition(Ball, 0.12)
	local LocalBall = GoalCFrame:PointToObjectSpace(Predicted)

	-- Follow the ball laterally across the goal mouth, but clamp depth
	-- so a distant loose ball cannot pull the GK out of position.
	local Lateral = math.clamp(LocalBall.X, -12, 12)
	local DepthSign = LocalBall.Z >= 0 and 1 or -1
	local Forward = math.clamp(math.abs(LocalBall.Z) * 0.15, 6, 11)

	return GoalCFrame:PointToWorldSpace(Vector3.new(
		Lateral,
		0,
		DepthSign * Forward
	))
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
	local CameraPosition = Camera.CFrame.Position
	local LookPosition = Position + Vector3.new(0, 1.5, 0)

	Camera.CFrame = CFrame.lookAt(
		CameraPosition,
		LookPosition
	)
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
		return true
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
		return
	end

	local Now = os.clock()
	local Opponent, OpponentRoot = getOpponentCarrier()

	if Opponent and OpponentRoot then
		LastOpponentCarrier = Opponent
	end

	local FreeBall = getNearestFreeBall(Root)
	local LowBall = FreeBall and FreeBall.Position.Y <= LOW_BALL_Y

	-- When the ball falls far below the pitch, keep the GK on the
	-- opponent who last had possession instead of chasing the ball.
	if LowBall and LastOpponentCarrier then
		local LastRoot = getRoot(LastOpponentCarrier)

		if LastRoot
			and LastOpponentCarrier:GetAttribute("IsOnPitch") == true
			and LastOpponentCarrier:GetAttribute("IsHomeOrAway") ~= getSide() then
			Opponent = LastOpponentCarrier
			OpponentRoot = LastRoot
			FreeBall = nil
		end
	end

	_G.AutoGKDebug = {
		ThreatPlayer = Opponent,
		ThreatBall = FreeBall,
		ThreatType = Opponent and "PLAYER" or nil,
		Jump = false,
	}

	local Goal = getGoal()

	if not Goal then
		return
	end

	_G.AutoGKDebug.Dive = false

	-- If the ball is elevated and approaching the GK, jump first.
	-- The apex dive is handled separately once the GK has risen.
	if FreeBall and tryOverheadJump(FreeBall, Root, Humanoid, Now) then
		trackCamera(FreeBall.Position)
		return
	end

	-- Finish an overhead save by diving at the apex of the jump.
	if tryPendingDive(Goal, Root, Humanoid, Now) then
		trackCamera(PendingDiveBall and PendingDiveBall.Position or Root.Position)
		return
	end

	-- Dive for a dangerous ground-level ball.
	if FreeBall and tryDive(Goal, FreeBall, Root, Now) then
		trackCamera(FreeBall.Position)
		return
	end

	-- A loose ball can trigger a jump. Jumping does not make the ball
	-- the movement target by itself.
	if false then
		if FreeBall then
			trackCamera(FreeBall.Position)
		end

		return
	end

	local Target
	local CameraTarget

	if Opponent and OpponentRoot then
		Target = getPlayerTrackingTarget(Goal, Opponent)
		CameraTarget = OpponentRoot.Position
	elseif FreeBall then
		Target = getBallTrackingTarget(Goal, FreeBall)
		CameraTarget = FreeBall.Position
	else
		return
	end

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
	_G.AutoGKDebug.ThreatType = Opponent and "PLAYER" or "BALL"

	trackCamera(CameraTarget)
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
