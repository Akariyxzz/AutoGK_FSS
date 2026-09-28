-- Auto GK for FSS
-- Phase 1: continuous goalkeeper positioning and threat tracking.
--
-- The important rule here is simple:
--   ALWAYS TRACK THE BALL OR THE ATTACKER FIRST.
--
-- Saving/prediction should be layered on top of this behavior later.
-- The GK should visibly move when the threat moves instead of standing still.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalPlayer = Players.LocalPlayer

local PlayerScripts = LocalPlayer:WaitForChild("PlayerScripts")
local Controllers = PlayerScripts:WaitForChild("Client"):WaitForChild("Controllers")
local Actions = Controllers:WaitForChild("Actions")

local Leap = require(
    Actions:WaitForChild("Managers"):WaitForChild("Leap")
)

local Knit = require(ReplicatedStorage.Packages.Knit)

local MovementController
pcall(function()
    MovementController = Knit.GetController("MovementController")
end)

-- =========================
-- Configuration
-- =========================

local TRACK_UPDATE = 0.05
local TRACK_DISTANCE = 3.5
local MAX_LATERAL_OFFSET = 13
local MAX_DEPTH_OFFSET = 9

local DIVE_COOLDOWN = 0.45
local DIVE_DISTANCE = 9
local DIVE_MIN_DISTANCE = 3

local DEBUG_INTERVAL = 0.5

-- =========================
-- Runtime
-- =========================

local running = true
local HeartbeatConnection

local LastMove = 0
local LastDive = 0
local LastDebug = 0

local GKState = "IDLE"
local CurrentThreat
local CurrentBall
local CurrentTarget

-- =========================
-- Character / team
-- =========================

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
    local Side = LocalPlayer:GetAttribute("IsHomeOrAway")

    if Side == "Home" or Side == "Away" then
        return Side
    end
end

local function isGoalkeeper()
    return LocalPlayer:GetAttribute("TeamPosition") == "GK"
end

local function getPlayerRoot(Player)
    local Character = Player.Character

    if not Character then
        return
    end

    return Character:FindFirstChild("HumanoidRootPart")
end

local function isOpponent(Player)
    if Player == LocalPlayer then
        return false
    end

    if Player:GetAttribute("IsOnPitch") ~= true then
        return false
    end

    local MySide = getSide()
    local PlayerSide = Player:GetAttribute("IsHomeOrAway")

    if not MySide or not PlayerSide then
        return false
    end

    return PlayerSide ~= MySide
end

-- =========================
-- Goal
-- =========================

local function getOwnGoal()
    local Side = getSide()

    if not Side then
        return
    end

    local Stadium = workspace:FindFirstChild("Stadium")
    local Teams = Stadium and Stadium:FindFirstChild("Teams")
    local Team = Teams and Teams:FindFirstChild(Side)
    local Goal = Team and Team:FindFirstChild("Goal")

    if not Goal then
        return
    end

    local InterceptionHitbox = Goal:FindFirstChild("InterceptionHitbox")

    if not InterceptionHitbox
        or not InterceptionHitbox:IsA("BasePart") then
        return
    end

    return InterceptionHitbox
end

-- =========================
-- Football
-- =========================

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

local function getClosestBall(Balls, Position)
    local BestBall
    local BestDistance = math.huge

    for _, Ball in Balls do
        local Distance = (Ball.Position - Position).Magnitude

        if Distance < BestDistance then
            BestDistance = Distance
            BestBall = Ball
        end
    end

    return BestBall, BestDistance
end

-- =========================
-- Threat selection
-- =========================
--
-- Priority:
--
-- 1. Opponent with HasBall.
-- 2. A nearby moving football.
--
-- This means the GK has something to follow even when there is no
-- immediately dangerous shot.

local function getThreat(Goal, Root)
    local Balls = getActiveBalls()

    local Possessor
    local PossessorDistance = math.huge

    for _, Player in Players:GetPlayers() do
        if isOpponent(Player)
            and Player:GetAttribute("HasBall") == true then

            local PlayerRoot = getPlayerRoot(Player)

            if PlayerRoot then
                local Distance = (PlayerRoot.Position - Root.Position).Magnitude

                if Distance < PossessorDistance then
                    PossessorDistance = Distance
                    Possessor = Player
                end
            end
        end
    end

    if Possessor then
        local PlayerRoot = getPlayerRoot(Possessor)
        local Ball, BallDistance

        if PlayerRoot then
            Ball, BallDistance = getClosestBall(Balls, PlayerRoot.Position)

            if Ball and BallDistance <= 14 then
                return {
                    Player = Possessor,
                    Ball = Ball,
                    Position = Ball.Position,
                    Type = "POSSESSION",
                }
            end

            -- Even if the ball lookup is imperfect, the player itself
            -- is still a valid threat to track.
            return {
                Player = Possessor,
                Ball = Ball,
                Position = PlayerRoot.Position,
                Type = "PLAYER",
            }
        end
    end

    -- Nobody has HasBall. Find the football that is closest to the GK
    -- and moving with meaningful speed.
    local BestBall
    local BestScore = math.huge

    for _, Ball in Balls do
        local Velocity = Ball.AssemblyLinearVelocity
        local Speed = Velocity.Magnitude

        if Speed > 2 then
            local Distance = (Ball.Position - Root.Position).Magnitude

            -- Favor balls that are both close and moving.
            local Score = Distance / math.max(Speed, 8)

            if Score < BestScore then
                BestScore = Score
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

    return
end

-- =========================
-- Goalkeeper target
-- =========================
--
-- The target is deliberately NOT "the predicted goal intersection".
--
-- First we make the GK follow the threat:
--
--   attacker/ball
--          |
--          v
--     [   GK   ]
--          |
--        GOAL
--
-- The GK follows the threat laterally and shifts a little in depth.
-- Both offsets are clamped so the GK does not chase the attacker out
-- of the goal area.

local function getTrackingTarget(Goal, Threat, Root)
    local ThreatPosition = Threat.Position

    local LocalThreat = Goal.CFrame:PointToObjectSpace(ThreatPosition)
    local HalfSize = Goal.Size * 0.5

    -- Lateral tracking.
    --
    -- Use most of the threat's lateral position rather than a tiny
    -- fraction. This makes movement visibly responsive.
    local Lateral = math.clamp(
        LocalThreat.X * 0.75,
        -MAX_LATERAL_OFFSET,
        MAX_LATERAL_OFFSET
    )

    -- Keep the GK close to the goal.
    --
    -- We take a small amount of the threat's depth, but clamp it.
    -- This lets the GK step forward toward a nearby attacker/ball
    -- without running all the way out.
    local ThreatDepth = math.clamp(
        LocalThreat.Z,
        -MAX_DEPTH_OFFSET,
        MAX_DEPTH_OFFSET
    )

    local Depth = ThreatDepth * 0.35

    -- The exact center depth is based on the current goal hitbox.
    -- Adding a small offset toward the threat makes the GK stand
    -- slightly in front of the goal instead of directly on its line.
    local LocalTarget = Vector3.new(
        Lateral,
        0,
        Depth + math.sign(ThreatDepth) * 2
    )

    local WorldTarget = Goal.CFrame:PointToWorldSpace(LocalTarget)

    return Vector3.new(
        WorldTarget.X,
        Root.Position.Y,
        WorldTarget.Z
    )
end

-- =========================
-- Movement
-- =========================

local function startSprint()
    if not MovementController then
        return
    end

    pcall(function()
        MovementController:SetSprintingControlState(true)
    end)
end

local function stopSprint()
    if not MovementController then
        return
    end

    pcall(function()
        MovementController:SetSprintingControlState(false)
    end)
end

local function moveTo(Target)
    local Character, Humanoid = getCharacter()

    if not Character or not Humanoid then
        return
    end

    local Now = os.clock()

    if Now - LastMove < TRACK_UPDATE then
        return
    end

    LastMove = Now

    Humanoid:MoveTo(Target)
end

-- =========================
-- Dive
-- =========================

local function faceGoal(Goal, Root)
    local Forward = Goal.CFrame.LookVector
    local FlatForward = Vector3.new(
        Forward.X,
        0,
        Forward.Z
    )

    if FlatForward.Magnitude < 0.01 then
        return
    end

    FlatForward = FlatForward.Unit

    Root.CFrame = CFrame.lookAt(
        Root.Position,
        Root.Position + FlatForward
    )
end

local function tryDive(Goal, Root, Target)
    local Now = os.clock()

    if Now - LastDive < DIVE_COOLDOWN then
        return
    end

    local Offset = Target - Root.Position
    local FlatOffset = Vector3.new(
        Offset.X,
        0,
        Offset.Z
    )

    local Distance = FlatOffset.Magnitude

    if Distance < DIVE_MIN_DISTANCE
        or Distance > DIVE_DISTANCE then
        return
    end

    faceGoal(Goal, Root)

    local Side = FlatOffset:Dot(Root.CFrame.RightVector)

    if math.abs(Side) < 2 then
        return
    end

    LastDive = Now

    if Side > 0 then
        Leap.Activate("Right")
    else
        Leap.Activate("Left")
    end
end

-- =========================
-- Main
-- =========================

local function update()
    if not running then
        return
    end

    local Character, Humanoid, Root = getCharacter()

    if not Character
        or not Humanoid
        or Humanoid.Health <= 0 then
        return
    end

    if not isGoalkeeper() then
        GKState = "IDLE"
        CurrentThreat = nil
        CurrentBall = nil
        CurrentTarget = nil
        stopSprint()
        return
    end

    local Goal = getOwnGoal()

    if not Goal then
        GKState = "IDLE"
        return
    end

    if LocalPlayer:GetAttribute("HasBall") == true then
        GKState = "POSSESSION"
        CurrentThreat = nil
        CurrentBall = nil
        CurrentTarget = nil
        return
    end

    startSprint()

    local Threat = getThreat(Goal, Root)

    if not Threat then
        GKState = "IDLE"
        CurrentThreat = nil
        CurrentBall = nil
        CurrentTarget = nil
        return
    end

    CurrentThreat = Threat.Player
    CurrentBall = Threat.Ball

    -- THIS IS THE CORE BEHAVIOR:
    -- every update, find where the ball/player is NOW and move toward
    -- the corresponding goalkeeper tracking position.
    local Target = getTrackingTarget(
        Goal,
        Threat,
        Root
    )

    CurrentTarget = Target
    GKState = "TRACK"

    moveTo(Target)

    -- Diving is deliberately secondary. We only attempt it when the
    -- tracking target is already close enough to the GK.
    if Threat.Ball then
        tryDive(Goal, Root, Target)
    end

    _G.AutoGKDebug = {
        State = GKState,
        ThreatPlayer = Threat.Player,
        ThreatType = Threat.Type,
        Ball = Threat.Ball,
        Target = Target,
        BallPosition = Threat.Ball and Threat.Ball.Position,
        BallVelocity = Threat.Ball and Threat.Ball.AssemblyLinearVelocity,
        BallState = Threat.Ball and Threat.Ball:GetAttribute("State"),
    }

    local Now = os.clock()

    if Now - LastDebug >= DEBUG_INTERVAL then
        LastDebug = Now

        print(("[AutoGK] state=%s threat=%s type=%s target=%s"):format(
            GKState,
            Threat.Player and Threat.Player.Name or "none",
            Threat.Type,
            tostring(Target)
        ))
    end
end

HeartbeatConnection = RunService.Heartbeat:Connect(update)

-- =========================
-- Kill switch
-- =========================

UserInputService.InputBegan:Connect(function(Input, GameProcessed)
    if GameProcessed then
        return
    end

    if Input.KeyCode ~= Enum.KeyCode.K then
        return
    end

    if not running then
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
