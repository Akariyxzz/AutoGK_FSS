-- Auto GK for FSS
-- Phase 1: tracking only.
--
-- No saves, dives, prediction, or ball trajectory logic.
-- The goalkeeper continuously tracks the active football/attacker.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Knit = require(game:GetService("ReplicatedStorage").Packages.Knit)

local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera

local Running = true
local MovementController

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

local function getTrackingTarget(Goal, ThreatPosition, CurrentPosition)
	local GoalCFrame = Goal:GetPivot()
	local LocalThreat = GoalCFrame:PointToObjectSpace(ThreatPosition)

	-- Stay centered with the attacker's/ball's lateral position,
	-- but never leave the useful goalkeeper area.
	local Lateral = math.clamp(LocalThreat.X, -14, 14)

	-- A real GK does not stand glued to the goal line. Step forward
	-- toward the play, but become more conservative as the threat
	-- gets farther away.
	local DistanceFromGoal = math.abs(LocalThreat.Z)
	local Forward = math.clamp(
		18 - DistanceFromGoal * 0.10,
		3,
		10
	)

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

local function trackCamera(ThreatPosition)
	local CameraPosition = Camera.CFrame.Position
	local LookPosition = ThreatPosition + Vector3.new(0, 1.5, 0)

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

	local Threat = getThreat()

	if not Threat then
		return
	end

	local Goal = getGoal()

	if not Goal then
		return
	end

	local Target = getTrackingTarget(
		Goal,
		Threat.Position,
		Root.Position
	)

	local DistanceToTarget = (Target - Root.Position).Magnitude

	-- Use the game's actual MovementController sprint state so the
	-- goalkeeper can reposition quickly instead of slowly walking.
	if MovementController then
		MovementController:SetSprintingControlState(DistanceToTarget > 1.5)
	end

	Humanoid:MoveTo(Target)

	_G.AutoGKDebug = {
		ThreatPlayer = Threat.Player,
		ThreatBall = Threat.Ball,
		ThreatType = Threat.Type,
		ThreatPosition = Threat.Position,
		Target = Target,
		DistanceToTarget = DistanceToTarget,
	}

	-- Keep the camera following the current threat.
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
