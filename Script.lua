-- Auto GK for FSS
-- Tracks opponent ball carriers without chasing loose footballs.
-- Loose footballs are only considered for overhead jump detection.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Knit = require(game:GetService("ReplicatedStorage").Packages.Knit)

local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera

local Running = true
local MovementController
local LastJumpAt = 0

local BALL_GRAVITY = 196.2
local PREDICTION_MIN_TIME = 0.08
local PREDICTION_MAX_TIME = 0.55
local PREDICTION_STEP = 0.05

local OVERHEAD_MIN_HEIGHT = 1.5
local OVERHEAD_MAX_HEIGHT = 7
local OVERHEAD_RADIUS = 5

pcall(function()
	MovementController = Knit.GetController("MovementController")
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

local function getTrackingTarget(Goal, Player, Root)
	local GoalCFrame = Goal:GetPivot()
	local LocalThreat = GoalCFrame:PointToObjectSpace(
		Player.Character.HumanoidRootPart.Position
	)

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

	if Now - LastJumpAt < 0.75 then
		return true
	end

	if Humanoid.FloorMaterial ~= Enum.Material.Air then
		Humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
		LastJumpAt = Now
	end

	_G.AutoGKDebug.Jump = true
	_G.AutoGKDebug.JumpBall = Ball
	_G.AutoGKDebug.JumpPrediction = Predicted
	_G.AutoGKDebug.JumpPredictionTime = PredictionTime

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
	local FreeBall = getNearestFreeBall(Root)

	_G.AutoGKDebug = {
		ThreatPlayer = Opponent,
		ThreatBall = FreeBall,
		ThreatType = Opponent and "PLAYER" or nil,
		Jump = false,
	}

	-- A loose ball can trigger a jump, but it can NEVER become the
	-- goalkeeper's movement target.
	if tryOverheadJump(FreeBall, Root, Humanoid, Now) then
		if FreeBall then
			trackCamera(FreeBall.Position)
		end

		return
	end

	if not Opponent or not OpponentRoot then
		return
	end

	local Goal = getGoal()

	if not Goal then
		return
	end

	local Target = getTrackingTarget(Goal, Opponent, Root)

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

	trackCamera(OpponentRoot.Position)
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
