-- Auto GK for FSS
-- Controls the existing LocalPlayer goalkeeper.
--
-- Main design:
--   1. Find opponent players with HasBall first.
--   2. Associate the active football with the closest possessor.
--   3. Predict the football's trajectory from AssemblyLinearVelocity.
--   4. Move toward the predicted interception point.
--   5. Use the game's actual Leap manager for left/right dives.
--
-- Known game physics:
--   Gravity = 55
--   Sprint speed ~= 27
--
-- The script intentionally does not depend on NetworkOwner for primary
-- possession detection.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalPlayer = Players.LocalPlayer
local PlayerScripts = LocalPlayer:WaitForChild("PlayerScripts")

local ClientControllers = PlayerScripts:WaitForChild("Client"):WaitForChild("Controllers")
local Actions = ClientControllers:WaitForChild("Actions")
local Leap = require(Actions:WaitForChild("Managers"):WaitForChild("Leap"))

local Knit = require(ReplicatedStorage.Packages.Knit)

local MovementController
pcall(function()
    MovementController = Knit.GetController("MovementController")
end)

local GRAVITY = 55
local PREDICTION_TIME = 2
local PREDICTION_STEP = 1 / 30

local MOVE_UPDATE_INTERVAL = 0.08
local DIVE_COOLDOWN = 0.35
local DIVE_DISTANCE = 11
local REPOSITION_DISTANCE = 2.5

local lastMove = 0
local lastDive = 0

local function getCharacter()
    local Character = LocalPlayer.Character
    if not Character then
        return
    end

    local Humanoid = Character:FindFirstChildOfClass("Humanoid")
    local Root = Character:FindFirstChild("HumanoidRootPart")

    if not Humanoid or not Root then
        return
    end

    return Character, Humanoid, Root
end

local function getSide()
    local side = LocalPlayer:GetAttribute("IsHomeOrAway")

    if side == "Home" or side == "Away" then
        return side
    end

    return
end

local function getOwnGoal()
    local side = getSide()
    if not side then
        return
    end

    local Stadium = workspace:FindFirstChild("Stadium")
    local Teams = Stadium and Stadium:FindFirstChild("Teams")
    local Team = Teams and Teams:FindFirstChild(side)
    local Goal = Team and Team:FindFirstChild("Goal")

    if not Goal then
        return
    end

    local InterceptionHitbox = Goal:FindFirstChild("InterceptionHitbox")

    if not InterceptionHitbox or not InterceptionHitbox:IsA("BasePart") then
        return
    end

    return InterceptionHitbox
end

local function isOnPitch(Player)
    return Player:GetAttribute("IsOnPitch") == true
end

local function isOpponent(Player)
    if Player == LocalPlayer then
        return false
    end

    local mySide = getSide()
    if not mySide then
        return true
    end

    -- The game uses IsHomeOrAway to identify the player's side.
    local side = Player:GetAttribute("IsHomeOrAway")

    if side == nil then
        -- Do not reject the player if the side attribute is temporarily absent.
        return true
    end

    return side ~= mySide
end

local function getRoot(Player)
    local Character = Player.Character
    return Character and Character:FindFirstChild("HumanoidRootPart")
end

local function getActiveFootballs()
    local Misc = workspace:FindFirstChild("Misc")
    if not Misc then
        return {}
    end

    local result = {}

    for _, Object in Misc:GetChildren() do
        if Object:IsA("BasePart")
            and Object.Name:sub(1, 9) == "Football "
            and Object:GetAttribute("Enabled") == true then
            result[#result + 1] = Object
        end
    end

    return result
end

local function getClosestBallToPosition(Balls, Position)
    local Closest
    local ClosestDistance = math.huge

    for _, Ball in Balls do
        local Distance = (Ball.Position - Position).Magnitude

        if Distance < ClosestDistance then
            ClosestDistance = Distance
            Closest = Ball
        end
    end

    return Closest, ClosestDistance
end

local function getPossessingOpponent()
    local Character, Humanoid, Root = getCharacter()
    if not Character or Humanoid.Health <= 0 then
        return
    end

    local ClosestPlayer
    local ClosestDistance = math.huge

    for _, Player in Players:GetPlayers() do
        if isOpponent(Player)
            and isOnPitch(Player)
            and Player:GetAttribute("HasBall") == true then

            local PlayerRoot = getRoot(Player)

            if PlayerRoot then
                local Distance = (PlayerRoot.Position - Root.Position).Magnitude

                if Distance < ClosestDistance then
                    ClosestDistance = Distance
                    ClosestPlayer = Player
                end
            end
        end
    end

    return ClosestPlayer
end

local function getRelevantBall()
    local Balls = getActiveFootballs()
    if #Balls == 0 then
        return
    end

    -- Possession is the primary source of truth.
    local Possessor = getPossessingOpponent()

    if Possessor then
        local PossessorRoot = getRoot(Possessor)

        if PossessorRoot then
            local Ball, Distance = getClosestBallToPosition(Balls, PossessorRoot.Position)

            -- A possessed ball should normally be close to its possessor.
            if Ball and Distance <= 12 then
                return Ball, Possessor
            end
        end
    end

    -- Fallback: nobody currently reports HasBall.
    -- Look for the active football moving toward our goal.
    local Goal = getOwnGoal()
    if not Goal then
        return
    end

    local BestBall
    local BestScore = math.huge

    for _, Ball in Balls do
        local Velocity = Ball.AssemblyLinearVelocity
        local Speed = Velocity.Magnitude

        if Speed > 1 then
            local ToGoal = Goal.Position - Ball.Position
            local DirectionToGoal = ToGoal.Magnitude > 0 and ToGoal.Unit

            if DirectionToGoal then
                local TowardGoal = Velocity.Unit:Dot(DirectionToGoal)

                if TowardGoal > 0.15 then
                    local Distance = ToGoal.Magnitude
                    local Score = Distance / math.max(Speed, 1)

                    if Score < BestScore then
                        BestScore = Score
                        BestBall = Ball
                    end
                end
            end
        end
    end

    return BestBall
end

local function pointInsidePart(Part, WorldPoint)
    local LocalPoint = Part.CFrame:PointToObjectSpace(WorldPoint)
    local HalfSize = Part.Size * 0.5

    return math.abs(LocalPoint.X) <= HalfSize.X
        and math.abs(LocalPoint.Y) <= HalfSize.Y
        and math.abs(LocalPoint.Z) <= HalfSize.Z
end

local function predictGoalInterception(Ball, Goal)
    local Position = Ball.Position
    local Velocity = Ball.AssemblyLinearVelocity

    if Velocity.Magnitude < 1 then
        return
    end

    -- Reject balls whose current velocity is clearly moving away from goal.
    local ToGoal = Goal.Position - Position

    if ToGoal.Magnitude > 0 then
        local TowardGoal = Velocity.Unit:Dot(ToGoal.Unit)

        if TowardGoal < 0.05 then
            return
        end
    end

    local time = 0

    while time <= PREDICTION_TIME do
        local Predicted = Position
            + Velocity * time
            + Vector3.new(0, -0.5 * GRAVITY * time * time, 0)

        if pointInsidePart(Goal, Predicted) then
            return Predicted, time
        end

        time += PREDICTION_STEP
    end
end

local function getGoalkeeperTarget(Goal, PredictedPosition, Root)
    -- Keep the GK inside the goal/interception region horizontally.
    local LocalGoalPoint = Goal.CFrame:PointToObjectSpace(PredictedPosition)

    local HalfSize = Goal.Size * 0.5

    LocalGoalPoint = Vector3.new(
        math.clamp(LocalGoalPoint.X, -HalfSize.X, HalfSize.X),
        0,
        0
    )

    local Target = Goal.CFrame:PointToWorldSpace(LocalGoalPoint)

    -- Keep the goalkeeper around its current Y level.
    Target = Vector3.new(Target.X, Root.Position.Y, Target.Z)

    return Target
end

local function faceTarget(Root, Target)
    local FlatTarget = Vector3.new(Target.X, Root.Position.Y, Target.Z)
    local Direction = FlatTarget - Root.Position

    if Direction.Magnitude > 0.05 then
        Root.CFrame = CFrame.lookAt(Root.Position, FlatTarget)
    end
end

local function tryLeap(Root, Target)
    local now = os.clock()

    if now - lastDive < DIVE_COOLDOWN then
        return
    end

    local Offset = Target - Root.Position
    local FlatOffset = Vector3.new(Offset.X, 0, Offset.Z)

    if FlatOffset.Magnitude > DIVE_DISTANCE then
        return
    end

    if FlatOffset.Magnitude < 2 then
        return
    end

    -- Leap uses the character's current orientation to determine left/right.
    faceTarget(Root, Target)

    local Right = Root.CFrame.RightVector
    local Side = FlatOffset:Dot(Right)

    if math.abs(Side) < 1 then
        return
    end

    lastDive = now

    if Side > 0 then
        Leap.Activate("Right")
    else
        Leap.Activate("Left")
    end
end

local function reposition(Root, Goal)
    local LocalRoot = Goal.CFrame:PointToObjectSpace(Root.Position)
    local HalfSize = Goal.Size * 0.5

    -- Center the goalkeeper on the goal when there is no immediate threat.
    local Center = Goal.CFrame:PointToWorldSpace(Vector3.new(
        0,
        0,
        math.clamp(LocalRoot.Z, -HalfSize.Z, HalfSize.Z)
    ))

    local Target = Vector3.new(Center.X, Root.Position.Y, Center.Z)

    if (Root.Position - Target).Magnitude > REPOSITION_DISTANCE then
        HumanoidMoveTo(Target)
    end
end

function HumanoidMoveTo(Target)
    local Character, Humanoid, Root = getCharacter()
    if not Character then
        return
    end

    local now = os.clock()

    if now - lastMove < MOVE_UPDATE_INTERVAL then
        return
    end

    lastMove = now
    Humanoid:MoveTo(Target)
end

local function startSprint()
    if MovementController and MovementController.SetSprintingControlState then
        pcall(function()
            MovementController:SetSprintingControlState(true)
        end)
    end
end

local function stopSprint()
    if MovementController and MovementController.SetSprintingControlState then
        pcall(function()
            MovementController:SetSprintingControlState(false)
        end)
    end
end

local function isGoalkeeper()
    local Position = LocalPlayer:GetAttribute("TeamPosition")

    if Position == "GK" then
        return true
    end

    -- Some game systems use an IsGoalie/IsGoalkeeper-style state.
    -- Do not require it because TeamPosition == GK is already known.
    return false
end

local function update()
    local Character, Humanoid, Root = getCharacter()

    if not Character or Humanoid.Health <= 0 then
        return
    end

    if not isGoalkeeper() then
        stopSprint()
        return
    end

    startSprint()

    local Goal = getOwnGoal()
    if not Goal then
        return
    end

    -- If the GK has the ball, do not try to intercept it.
    if LocalPlayer:GetAttribute("HasBall") == true then
        return
    end

    local Ball = getRelevantBall()

    if not Ball then
        reposition(Root, Goal)
        return
    end

    local PredictedPosition, TimeToGoal = predictGoalInterception(Ball, Goal)

    if not PredictedPosition then
        reposition(Root, Goal)
        return
    end

    local Target = getGoalkeeperTarget(Goal, PredictedPosition, Root)

    -- Start moving toward the predicted interception point.
    Humanoid:MoveTo(Target)

    -- Dive when the interception point is close enough to be useful.
    tryLeap(Root, Target)

    -- Keep these values available while debugging from the executor.
    _G.AutoGKDebug = {
        Ball = Ball,
        Goal = Goal,
        PredictedPosition = PredictedPosition,
        TimeToGoal = TimeToGoal,
        Target = Target,
    }
end

RunService.Heartbeat:Connect(update)
