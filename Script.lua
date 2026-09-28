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
--   Gravity = 196.1999969482422 (actual trajectory gravity)
--   Sprint speed ~= 27
--
-- The script intentionally does not depend on NetworkOwner for primary
-- possession detection.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalPlayer = Players.LocalPlayer
local PlayerScripts = LocalPlayer:WaitForChild("PlayerScripts")
local ClientControllers = PlayerScripts:WaitForChild("Client"):WaitForChild("Controllers")
local Actions = ClientControllers:WaitForChild("Actions")

local Leap = require(
    Actions:WaitForChild("Managers"):WaitForChild("Leap")
)

local Knit = require(ReplicatedStorage.Packages.Knit)

local MovementController
pcall(function()
    MovementController = Knit.GetController("MovementController")
end)

local GRAVITY = 196.1999969482422
local PREDICTION_TIME = 2.5
local PREDICTION_STEP = 1 / 30

local MOVE_UPDATE_INTERVAL = 0.08
local DIVE_COOLDOWN = 0.35
local DIVE_DISTANCE = 11
local REPOSITION_DISTANCE = 2.5

local lastMove = 0
local lastDive = 0
local debugLast = 0
local running = true
local HeartbeatConnection

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

    local side = Player:GetAttribute("IsHomeOrAway")

    if side == nil then
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
            local Ball, Distance = getClosestBallToPosition(
                Balls,
                PossessorRoot.Position
            )

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

local function predictGoalInterception(Ball, Goal)
    local Position = Ball.Position
    local Velocity = Ball.AssemblyLinearVelocity
    local LocalPosition = Goal.CFrame:PointToObjectSpace(Position)
    local LocalVelocity = Goal.CFrame:VectorToObjectSpace(Velocity)

    if Velocity.Magnitude < 1 then
        return
    end

    -- The GK should react to where the ball is going to cross the
    -- goal plane, not wait until the ball is already inside the goal.
    if math.abs(LocalVelocity.Z) < 0.5 then
        return
    end

    local TimeToPlane = -LocalPosition.Z / LocalVelocity.Z

    if TimeToPlane < 0 or TimeToPlane > PREDICTION_TIME then
        return
    end

    local Predicted = Position
        + Velocity * TimeToPlane
        + Vector3.new(0, -0.5 * GRAVITY * TimeToPlane * TimeToPlane, 0)

    local LocalPredicted = Goal.CFrame:PointToObjectSpace(Predicted)
    local HalfSize = Goal.Size * 0.5

    -- If the trajectory is completely outside the goal mouth, don't
    -- commit to a save. The positioning system can still track the shot.
    if math.abs(LocalPredicted.X) > HalfSize.X + 5
        or LocalPredicted.Y < -HalfSize.Y - 5
        or LocalPredicted.Y > HalfSize.Y + 5 then
        return
    end

    return Predicted, TimeToPlane
end

local function moveTo(Target)
    local Character, Humanoid = getCharacter()
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

local function faceGoal(Root, Goal)
    -- Leap's Left/Right direction is relative to the character orientation.
    -- Face along the goal's depth axis, not toward the interception point.
    local Forward = Goal.CFrame.LookVector
    local FlatForward = Vector3.new(Forward.X, 0, Forward.Z)

    if FlatForward.Magnitude < 0.01 then
        return
    end

    FlatForward = FlatForward.Unit

    Root.CFrame = CFrame.lookAt(
        Root.Position,
        Root.Position + FlatForward
    )
end

local function tryLeap(Root, Goal, Target)
    local now = os.clock()

    if now - lastDive < DIVE_COOLDOWN then
        return
    end

    local Offset = Target - Root.Position
    local FlatOffset = Vector3.new(Offset.X, 0, Offset.Z)

    if FlatOffset.Magnitude > DIVE_DISTANCE
        or FlatOffset.Magnitude < 2 then
        return
    end

    -- Establish a stable GK-facing orientation first.
    -- Do NOT face Target itself, because that would make Target "Forward"
    -- and destroy the left/right decision.
    faceGoal(Root, Goal)

    local Side = FlatOffset:Dot(Root.CFrame.RightVector)

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

local function reposition(Root, Goal, Ball, Possessor, PredictedPosition)
    local Target = getPositioningTarget(
        Goal,
        Ball,
        Possessor,
        Root,
        PredictedPosition
    )

    if (Root.Position - Target).Magnitude > REPOSITION_DISTANCE then
        moveTo(Target)
    end
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
    return LocalPlayer:GetAttribute("TeamPosition") == "GK"
end

local GKState = "IDLE"
local stateSince = os.clock()

local function setState(NewState)
    if GKState == NewState then
        return
    end

    GKState = NewState
    stateSince = os.clock()
end

local function update()
    if not running then
        return
    end

    local Character, Humanoid, Root = getCharacter()

    if not Character or Humanoid.Health <= 0 then
        return
    end

    if not isGoalkeeper() then
        setState("IDLE")
        stopSprint()
        return
    end

    startSprint()

    local Goal = getOwnGoal()
    if not Goal then
        setState("IDLE")
        return
    end

    -- A GK with the ball is no longer an interceptor.
    if LocalPlayer:GetAttribute("HasBall") == true then
        setState("POSSESSION")
        return
    end

    local Ball, Possessor = getRelevantBall()

    if not Ball then
        setState("POSITION")
        reposition(Root, Goal, nil, nil, nil)
        return
    end

    local PredictedPosition, TimeToGoal =
        predictGoalInterception(Ball, Goal)

    local BallSpeed = Ball.AssemblyLinearVelocity.Magnitude
    local LocalBall = Goal.CFrame:PointToObjectSpace(Ball.Position)

    -- The GK reacts to the ball even before a shot has a valid goal-plane
    -- intersection. This prevents the old "stand still until the line"
    -- behavior.
    if PredictedPosition then
        if TimeToGoal <= 0.45 then
            setState("COMMIT")
        elseif TimeToGoal <= 1.0 then
            setState("READY")
        else
            setState("TRACK")
        end

        local Target = getGoalkeeperTarget(
            Goal,
            PredictedPosition,
            Root
        )

        moveTo(Target)

        if TimeToGoal <= 0.75 then
            tryLeap(Root, Goal, Target)
        end

        _G.AutoGKDebug = {
            State = GKState,
            StateSince = stateSince,
            Ball = Ball,
            Goal = Goal,
            Possessor = Possessor,
            PredictedPosition = PredictedPosition,
            TimeToGoal = TimeToGoal,
            Target = Target,
            BallVelocity = Ball.AssemblyLinearVelocity,
            BallState = Ball:GetAttribute("State"),
        }
    else
        -- Ball is not currently on a direct scoring trajectory.
        -- Track its lateral movement and the attacker, but keep the GK
        -- inside a sensible set position.
        local DistanceToGoal = (Ball.Position - Goal.Position).Magnitude

        if Possessor then
            setState("TRACK")
        elseif DistanceToGoal < 45 or BallSpeed > 15 then
            setState("TRACK")
        else
            setState("POSITION")
        end

        local Target = getPositioningTarget(
            Goal,
            Ball,
            Possessor,
            Root,
            nil
        )

        moveTo(Target)

        _G.AutoGKDebug = {
            State = GKState,
            StateSince = stateSince,
            Ball = Ball,
            Goal = Goal,
            Possessor = Possessor,
            PredictedPosition = nil,
            TimeToGoal = nil,
            Target = Target,
            BallVelocity = Ball.AssemblyLinearVelocity,
            BallState = Ball:GetAttribute("State"),
            BallLocalPosition = LocalBall,
        }
    end

    -- Lightweight internal debugging. Throttled so Heartbeat does not spam output.
    local now = os.clock()
    if now - debugLast >= 1 then
        debugLast = now
        print(("[AutoGK] state=%s ball=%s speed=%.1f t=%s target=%s"):format(
            GKState,
            Ball.Name,
            BallSpeed,
            TimeToGoal and string.format("%.2f", TimeToGoal) or "nil",
            tostring(_G.AutoGKDebug.Target)
        ))
    end
end

HeartbeatConnection = RunService.Heartbeat:Connect(update)

UserInputService.InputBegan:Connect(function(Input, GameProcessed)
    if GameProcessed or Input.KeyCode ~= Enum.KeyCode.K or not running then
        return
    end

    running = false

    if HeartbeatConnection then
        HeartbeatConnection:Disconnect()
        HeartbeatConnection = nil
    end

    stopSprint()
    _G.AutoGKDebug = nil

    print("[AutoGK] stopped.")
end)local function getGoalkeeperTarget(Goal, PredictedPosition, Root)
    local LocalGoalPoint = Goal.CFrame:PointToObjectSpace(PredictedPosition)
    local HalfSize = Goal.Size * 0.5

    LocalGoalPoint = Vector3.new(
        math.clamp(LocalGoalPoint.X, -HalfSize.X, HalfSize.X),
        0,
        HalfSize.Z + 3
    )

    local Target = Goal.CFrame:PointToWorldSpace(LocalGoalPoint)

    return Vector3.new(Target.X, Root.Position.Y, Target.Z)
end

local function getPositioningTarget(Goal, Ball, Possessor, Root, PredictedPosition)
    local HalfSize = Goal.Size * 0.5

    -- Start from the normal GK set position: centered and slightly
    -- in front of the goal line.
    local lateral = 0

    if PredictedPosition then
        local LocalPredicted = Goal.CFrame:PointToObjectSpace(PredictedPosition)
        lateral = LocalPredicted.X
    elseif Ball then
        -- While an attacker is carrying the ball, shade toward them.
        -- This is deliberately conservative so the GK does not get dragged
        -- out of the center by a distant player.
        lateral = Goal.CFrame:PointToObjectSpace(Ball.Position).X

        if Possessor then
            local PossessorRoot = getRoot(Possessor)
            if PossessorRoot then
                lateral = Goal.CFrame:PointToObjectSpace(
                    PossessorRoot.Position
                ).X
            end
        end
    end

    lateral = math.clamp(lateral * 0.35, -HalfSize.X * 0.65, HalfSize.X * 0.65)

    -- Stay in front of the goal instead of walking along its depth.
    local LocalTarget = Vector3.new(
        lateral,
        0,
        HalfSize.Z + 3
    )

    local WorldTarget = Goal.CFrame:PointToWorldSpace(LocalTarget)

    return Vector3.new(
        WorldTarget.X,
        Root.Position.Y,
        WorldTarget.Z
    )
end

local function moveTo(Target)
    local Character, Humanoid = getCharacter()
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

local function faceGoal(Root, Goal)
    -- Leap's Left/Right direction is relative to the character orientation.
    -- Face along the goal's depth axis, not toward the interception point.
    local Forward = Goal.CFrame.LookVector
    local FlatForward = Vector3.new(Forward.X, 0, Forward.Z)

    if FlatForward.Magnitude < 0.01 then
        return
    end

    FlatForward = FlatForward.Unit

    Root.CFrame = CFrame.lookAt(
        Root.Position,
        Root.Position + FlatForward
    )
end

local function tryLeap(Root, Goal, Target)
    local now = os.clock()

    if now - lastDive < DIVE_COOLDOWN then
        return
    end

    local Offset = Target - Root.Position
    local FlatOffset = Vector3.new(Offset.X, 0, Offset.Z)

    if FlatOffset.Magnitude > DIVE_DISTANCE
        or FlatOffset.Magnitude < 2 then
        return
    end

    -- Establish a stable GK-facing orientation first.
    -- Do NOT face Target itself, because that would make Target "Forward"
    -- and destroy the left/right decision.
    faceGoal(Root, Goal)

    local Side = FlatOffset:Dot(Root.CFrame.RightVector)

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

    local Center = Goal.CFrame:PointToWorldSpace(Vector3.new(
        0,
        0,
        math.clamp(LocalRoot.Z, -HalfSize.Z, HalfSize.Z)
    ))

    local Target = Vector3.new(
        Center.X,
        Root.Position.Y,
        Center.Z
    )

    if (Root.Position - Target).Magnitude > REPOSITION_DISTANCE then
        moveTo(Target)
    end
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
    return LocalPlayer:GetAttribute("TeamPosition") == "GK"
end

local function update()
    if not running then
        return
    end

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

    -- If the GK has the ball, don't try to intercept it.
    if LocalPlayer:GetAttribute("HasBall") == true then
        return
    end

    local Ball = getRelevantBall()

    if not Ball then
        reposition(Root, Goal)
        return
    end

    local PredictedPosition, TimeToGoal =
        predictGoalInterception(Ball, Goal)

    if not PredictedPosition then
        reposition(Root, Goal)
        return
    end

    local Target = getGoalkeeperTarget(
        Goal,
        PredictedPosition,
        Root
    )

    -- Move toward the predicted interception point.
    moveTo(Target)

    -- Dive when the lateral interception point is close enough.
    tryLeap(Root, Goal, Target)

    _G.AutoGKDebug = {
        Ball = Ball,
        Goal = Goal,
        PredictedPosition = PredictedPosition,
        TimeToGoal = TimeToGoal,
        Target = Target,
        BallVelocity = Ball.AssemblyLinearVelocity,
        BallState = Ball:GetAttribute("State"),
    }

    -- Lightweight internal debugging. Throttled so Heartbeat does not spam output.
    local now = os.clock()
    if now - debugLast >= 1 then
        debugLast = now
        print(("[AutoGK] ball=%s state=%s t=%.2f target=%s"):format(
            Ball.Name,
            tostring(Ball:GetAttribute("State")),
            TimeToGoal,
            tostring(Target)
        ))
    end
end

HeartbeatConnection = RunService.Heartbeat:Connect(update)

UserInputService.InputBegan:Connect(function(Input, GameProcessed)
    if GameProcessed or Input.KeyCode ~= Enum.KeyCode.K or not running then
        return
    end

    running = false

    if HeartbeatConnection then
        HeartbeatConnection:Disconnect()
        HeartbeatConnection = nil
    end

    stopSprint()
    _G.AutoGKDebug = nil

    print("[AutoGK] stopped.")
end)
