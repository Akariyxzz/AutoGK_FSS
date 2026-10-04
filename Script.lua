-- Auto GK - FSS
-- Phase 2: goal positioning, threat tracking, loose-ball prediction,
-- overhead jumps, lateral dives, and runtime diagnostics.
-- Behavior rules: see Behavior.md
-- Verified mechanics: see Info.md

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalPlayer = Players.LocalPlayer
local Knit = require(ReplicatedStorage.Packages.Knit)

local Running = true
local DEBUG = true

local MovementController
local Leap

local LastOpponentCarrier
local LastJumpAt = 0
local LastDiveAt = 0
local PendingDiveBall
local PendingDiveStartedAt = 0

local DebugLast = {}

local BALL_GRAVITY = 196.2
local PREDICTION_MIN_TIME = 0.08
local PREDICTION_MAX_TIME = 0.8
local PREDICTION_STEP = 0.03

local OVERHEAD_MIN_HEIGHT = 1.5
local OVERHEAD_MAX_HEIGHT = 10
local OVERHEAD_RADIUS = 9

local GOAL_LATERAL_LIMIT = 12
local SLOW_BALL_SPEED = 35
local SLOW_BALL_CHASE_RADIUS = 55
local SLOW_BALL_LEAP_DISTANCE = 8
local NEAR_BALL_PLAYER_RADIUS = 12
local GOAL_MIN_DEPTH = 6
local GOAL_MAX_DEPTH = 11
local MOVE_THRESHOLD = 1.25

local function Debug(Name, Value)
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

local function GetCharacter(Player)
    local Character = Player.Character

    if not Character then
        return
    end

    local Humanoid = Character:FindFirstChildOfClass("Humanoid")
    local Root = Character:FindFirstChild("HumanoidRootPart")

    if not Humanoid or not Root or Humanoid.Health <= 0 then
        return
    end

    return Character, Humanoid, Root
end

local function IsGoalkeeper()
    return LocalPlayer:GetAttribute("TeamPosition") == "GK"
end

local function GetSide()
    return LocalPlayer:GetAttribute("IsHomeOrAway")
end

local function GetOwnGoal()
    local Side = GetSide()

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

local function IsOpponent(Player)
    if Player == LocalPlayer then
        return false
    end

    if Player:GetAttribute("IsOnPitch") ~= true then
        return false
    end

    return Player:GetAttribute("IsHomeOrAway") ~= GetSide()
end

local function GetOpponentCarrier()
    for _, Player in Players:GetPlayers() do
        if IsOpponent(Player) and Player:GetAttribute("HasBall") == true then
            local _, _, Root = GetCharacter(Player)

            if Root then
                return Player, Root
            end
        end
    end
end

local function GetActiveBalls()
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

local function GetNearestFreeBall(Root)
    local BestBall
    local BestDistance = math.huge

    for _, Ball in GetActiveBalls() do
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

local function PredictBall(Ball, Time)
    return Ball.Position
        + Ball.AssemblyLinearVelocity * Time
        + Vector3.new(0, -0.5 * BALL_GRAVITY * Time * Time, 0)
end

local function GetThreatLateral(Goal, Player)
    local _, _, Root = GetCharacter(Player)

    if not Root then
        return 0
    end

    local LocalPosition = Goal.CFrame:PointToObjectSpace(Root.Position)

    return math.clamp(
        LocalPosition.X,
        -GOAL_LATERAL_LIMIT,
        GOAL_LATERAL_LIMIT
    )
end

local function GetCameraLateralBias(Goal, Root)
    local Camera = workspace.CurrentCamera

    if not Camera then
        return 0
    end

    local CameraLocal = Goal.CFrame:PointToObjectSpace(
        Camera.CFrame.Position
    )

    local CameraLook = Goal.CFrame:VectorToObjectSpace(
        Camera.CFrame.LookVector
    )

    if math.abs(CameraLook.Z) < 0.05 then
        return math.clamp(CameraLocal.X, -GOAL_LATERAL_LIMIT, GOAL_LATERAL_LIMIT)
    end

    local GoalPlaneX = CameraLocal.X - CameraLook.X
        * (CameraLocal.Z / CameraLook.Z)

    return math.clamp(
        GoalPlaneX,
        -GOAL_LATERAL_LIMIT,
        GOAL_LATERAL_LIMIT
    )
end

local function GetDefensiveLateral(Goal, Root, ThreatLateral)
    local CameraBias = GetCameraLateralBias(Goal, Root)

    -- Keep the camera as a secondary tracking signal. The actual threat
    -- remains dominant so looking toward the center does not pull the GK
    -- away from an attacker/ball on the opposite side.
    local Lateral = ThreatLateral * 0.75 + CameraBias * 0.25

    return math.clamp(
        Lateral,
        -GOAL_LATERAL_LIMIT,
        GOAL_LATERAL_LIMIT
    )
end

local function GetGoalDepthSign(Goal, Root)
    local LocalRoot = Goal.CFrame:PointToObjectSpace(Root.Position)

    if LocalRoot.Z >= 0 then
        return 1
    end

    return -1
end

local function GetGoalTarget(Goal, Root, Lateral, Depth)
    local DepthSign = GetGoalDepthSign(Goal, Root)

    return Goal.CFrame:PointToWorldSpace(Vector3.new(
        math.clamp(Lateral, -GOAL_LATERAL_LIMIT, GOAL_LATERAL_LIMIT),
        0,
        DepthSign * math.clamp(Depth, GOAL_MIN_DEPTH, GOAL_MAX_DEPTH)
    ))
end

local function MoveToGoalTarget(Humanoid, Root, Goal, Lateral, Depth)
    local Target = GetGoalTarget(Goal, Root, Lateral, Depth)
    local Current = Goal.CFrame:PointToObjectSpace(Root.Position)
    local TargetLocal = Goal.CFrame:PointToObjectSpace(Target)

    if math.abs(Current.X - TargetLocal.X) <= MOVE_THRESHOLD
        and math.abs(Current.Z - TargetLocal.Z) <= MOVE_THRESHOLD then
        return
    end

    Debug("Move", string.format(
        "target local X=%.2f Z=%.2f",
        TargetLocal.X,
        TargetLocal.Z
    ))

    if MovementController then
        MovementController:SetSprintingControlState(
            (Target - Root.Position).Magnitude > 1.5
        )
    end

    Humanoid:MoveTo(Target)
end

local function GetNearestOpponentDistance(Position)
    local BestDistance = math.huge

    for _, Player in Players:GetPlayers() do
        if IsOpponent(Player) then
            local _, _, Root = GetCharacter(Player)

            if Root then
                local Distance = (Root.Position - Position).Magnitude

                if Distance < BestDistance then
                    BestDistance = Distance
                end
            end
        end
    end

    return BestDistance
end

local function IsSlowUncontestedBall(Ball, BallDistance)
    if not Ball or BallDistance > SLOW_BALL_CHASE_RADIUS then
        return false
    end

    local Speed = Ball.AssemblyLinearVelocity.Magnitude

    if Speed > SLOW_BALL_SPEED then
        return false
    end

    local NearestOpponent = GetNearestOpponentDistance(Ball.Position)

    Debug("LooseBall", string.format(
        "speed=%.1f nearest opponent=%.1f",
        Speed,
        NearestOpponent
    ))

    return NearestOpponent > NEAR_BALL_PLAYER_RADIUS
end

local function ChaseSlowBall(Ball, BallDistance, Root, Humanoid)
    if not IsSlowUncontestedBall(Ball, BallDistance) then
        return false
    end

    local Target = Vector3.new(
        Ball.Position.X,
        Root.Position.Y,
        Ball.Position.Z
    )

    Debug("Chase", string.format(
        "slow uncontested ball distance=%.1f",
        BallDistance
    ))

    if BallDistance <= SLOW_BALL_LEAP_DISTANCE and Leap then
        local Camera = workspace.CurrentCamera

        if Camera then
            local CameraRight = Camera.CFrame.RightVector
            local ToBall = Ball.Position - Camera.CFrame.Position
            local ScreenSide = CameraRight:Dot(ToBall)

            if math.abs(ScreenSide) > 1 then
                if ScreenSide < 0 then
                    Leap.Activate("Left")
                    Debug("ChaseLeap", "LEFT based on camera")
                else
                    Leap.Activate("Right")
                    Debug("ChaseLeap", "RIGHT based on camera")
                end

                LastDiveAt = os.clock()
                return true
            end
        end

        Leap.Activate()
        Debug("ChaseLeap", "FORWARD")
        LastDiveAt = os.clock()
        return true
    end

    if MovementController then
        MovementController:SetSprintingControlState(true)
    end

    Humanoid:MoveTo(Target)
    return true
end

local function GetOverheadPrediction(Ball, Root)
    local Velocity = Ball.AssemblyLinearVelocity

    for Time = PREDICTION_MIN_TIME, PREDICTION_MAX_TIME, PREDICTION_STEP do
        local Predicted = PredictBall(Ball, Time)
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

    local CurrentHeight = Ball.Position.Y - Root.Position.Y
    local HorizontalVelocity = Vector3.new(
        Velocity.X,
        0,
        Velocity.Z
    )

    local ToGK = Vector3.new(
        Root.Position.X - Ball.Position.X,
        0,
        Root.Position.Z - Ball.Position.Z
    )

    if CurrentHeight >= OVERHEAD_MIN_HEIGHT
        and CurrentHeight <= OVERHEAD_MAX_HEIGHT
        and HorizontalVelocity.Magnitude > 1
        and ToGK.Magnitude <= OVERHEAD_RADIUS * 1.5 then

        if HorizontalVelocity.Unit:Dot(ToGK.Unit) > 0.15 then
            return Ball.Position, 0
        end
    end
end

local function TryOverheadJump(Ball, Root, Humanoid, Now)
    if not Ball then
        return false
    end

    local Predicted, PredictionTime = GetOverheadPrediction(Ball, Root)

    if not Predicted then
        return false
    end

    Debug("Overhead", string.format(
        "ball detected t=%.2f height=%.2f",
        PredictionTime,
        Predicted.Y - Root.Position.Y
    ))

    if Now - LastJumpAt < 0.55 then
        return true
    end

    if Humanoid.FloorMaterial ~= Enum.Material.Air then
        Humanoid:ChangeState(Enum.HumanoidStateType.Jumping)

        LastJumpAt = Now
        PendingDiveBall = Ball
        PendingDiveStartedAt = Now

        Debug("Jump", "Jumping for overhead ball")
    end

    return true
end

local function TryPendingDive(Root, Now)
    if not PendingDiveBall or not Leap then
        return false
    end

    local Ball = PendingDiveBall

    if not Ball.Parent or Ball:GetAttribute("Enabled") ~= true then
        PendingDiveBall = nil
        return false
    end

    if Now - PendingDiveStartedAt < 0.12 then
        return false
    end

    if Root.AssemblyLinearVelocity.Y > 1 then
        return false
    end

    PendingDiveBall = nil

    if Now - LastDiveAt < 1 then
        return false
    end

    local Predicted = PredictBall(Ball, 0.08)
    local LocalBall = Root.CFrame:PointToObjectSpace(Predicted)

    if math.abs(LocalBall.X) < 2 then
        return false
    end

    if LocalBall.X < 0 then
        Leap.Activate("Left")
        Debug("Dive", "LEFT")
    else
        Leap.Activate("Right")
        Debug("Dive", "RIGHT")
    end

    LastDiveAt = Now

    return true
end

local function TryGroundDive(Goal, Ball, Root, Now)
    if not Ball or not Leap then
        return false
    end

    if Now - LastDiveAt < 1 then
        return false
    end

    local Predicted = PredictBall(Ball, 0.18)
    local LocalBall = Goal.CFrame:PointToObjectSpace(Predicted)

    if math.abs(LocalBall.Z) > 13 then
        return false
    end

    if math.abs(LocalBall.X) < 4.5 then
        return false
    end

    local LocalVelocity = Goal.CFrame:VectorToObjectSpace(
        Ball.AssemblyLinearVelocity
    )

    local GoalDirection = LocalBall.Z >= 0 and -1 or 1

    if LocalVelocity.Z * GoalDirection <= 5 then
        return false
    end

    local CharacterBall = Root.CFrame:PointToObjectSpace(Predicted)

    if CharacterBall.X < 0 then
        Leap.Activate("Left")
        Debug("Dive", "GROUND LEFT")
    else
        Leap.Activate("Right")
        Debug("Dive", "GROUND RIGHT")
    end

    LastDiveAt = Now

    return true
end

local function Update()
    if not Running then
        return
    end

    if not IsGoalkeeper() then
        Debug("Status", "Not GK; TeamPosition=" .. tostring(
            LocalPlayer:GetAttribute("TeamPosition")
        ))
        return
    end

    local Character, Humanoid, Root = GetCharacter(LocalPlayer)

    if not Character then
        Debug("Character", "Missing character/humanoid/root")
        return
    end

    Debug("Status", "GK active")

    if LocalPlayer:GetAttribute("HasBall") == true then
        if MovementController then
            MovementController:SetSprintingControlState(false)
        end

        Humanoid:MoveTo(Root.Position)
        Debug("Status", "GK has ball")
        return
    end

    local Goal = GetOwnGoal()

    if not Goal then
        Debug("Goal", "Goal not found")
        return
    end

    Debug("Goal", Goal:GetFullName())

    local Carrier, CarrierRoot = GetOpponentCarrier()

    if Carrier then
        LastOpponentCarrier = Carrier
    end

    local FreeBall, BallDistance = GetNearestFreeBall(Root)

    if FreeBall then
        Debug("Ball", string.format(
            "%s distance=%.1f velocity=%.1f",
            FreeBall.Name,
            BallDistance,
            FreeBall.AssemblyLinearVelocity.Magnitude
        ))
    else
        Debug("Ball", "None")
    end

    -- A slow, uncontested loose ball is treated as a recoverable ball.
    -- Chase it directly instead of forcing the GK to stay on the goal line.
    if FreeBall and ChaseSlowBall(FreeBall, BallDistance, Root, Humanoid) then
        return
    end

    -- A distant/harmless loose ball must not drag the GK out of goal.
    if FreeBall and BallDistance <= 45 then
        if TryOverheadJump(FreeBall, Root, Humanoid, os.clock()) then
            return
        end

        if TryPendingDive(Root, os.clock()) then
            return
        end

        if TryGroundDive(Goal, FreeBall, Root, os.clock()) then
            return
        end
    end

    if Carrier and CarrierRoot then
        local ThreatLateral = GetThreatLateral(Goal, Carrier)
        local Lateral = GetDefensiveLateral(Goal, Root, ThreatLateral)
        local LocalCarrier = Goal.CFrame:PointToObjectSpace(CarrierRoot.Position)

        Debug("Threat", string.format(
            "PLAYER %s lateral=%.2f depth=%.2f",
            Carrier.Name,
            LocalCarrier.X,
            LocalCarrier.Z
        ))

        local Depth = math.clamp(
            10 + math.abs(LocalCarrier.X) / 2,
            10,
            15
        )

        MoveToGoalTarget(
            Humanoid,
            Root,
            Goal,
            Lateral,
            Depth
        )

        return
    end

    -- No carrier: follow a nearby loose ball only within a controlled
    -- defensive area.
    if FreeBall and BallDistance <= 45 then
        local Predicted = PredictBall(FreeBall, 0.12)
        local LocalBall = Goal.CFrame:PointToObjectSpace(Predicted)

        local Lateral = GetDefensiveLateral(
            Goal,
            Root,
            math.clamp(
                LocalBall.X,
                -GOAL_LATERAL_LIMIT,
                GOAL_LATERAL_LIMIT
            )
        )

        local Depth = math.clamp(
            math.abs(LocalBall.Z) * 0.15,
            GOAL_MIN_DEPTH,
            GOAL_MAX_DEPTH
        )

        Debug("Threat", string.format(
            "BALL lateral=%.2f depth=%.2f",
            LocalBall.X,
            LocalBall.Z
        ))

        MoveToGoalTarget(
            Humanoid,
            Root,
            Goal,
            Lateral,
            Depth
        )

        return
    end

    -- Do not immediately snap to the exact center. Use the camera's
    -- current viewing direction as a weak positional bias while there
    -- is no explicit carrier/ball threat.
    local IdleLateral = GetDefensiveLateral(Goal, Root, 0)

    Debug("Threat", string.format(
        "None; defensive lateral=%.2f",
        IdleLateral
    ))

    MoveToGoalTarget(Humanoid, Root, Goal, IdleLateral, 7)
end

UserInputService.InputBegan:Connect(function(Input, GameProcessed)
    if GameProcessed then
        return
    end

    if Input.KeyCode == Enum.KeyCode.L then
        Running = false

        if MovementController then
            MovementController:SetSprintingControlState(false)
        end

        Debug("Status", "Script stopped by L")
        print("[AutoGK] Script stopped.")
    end
end)

Debug("Loaded", "Script started for " .. LocalPlayer.Name)
Debug("TeamPosition", LocalPlayer:GetAttribute("TeamPosition"))
Debug("Side", LocalPlayer:GetAttribute("IsHomeOrAway"))

RunService.Heartbeat:Connect(Update)
