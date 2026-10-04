-- Auto GK - initial implementation
-- Phase 1: GK detection, goal positioning, and basic threat tracking.
-- Behavior rules: see Behavior.md
-- Verified mechanics: see Info.md

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalPlayer = Players.LocalPlayer
local Knit = require(ReplicatedStorage.Packages.Knit)
local MovementController = Knit.GetController("MovementController")

local Running = true
local LastOpponentCarrier = nil

local GOAL_FORWARD_OFFSET = 7
local GOAL_LATERAL_LIMIT = 12
local MOVE_THRESHOLD = 1.25

local function GetCharacter()
    local Character = LocalPlayer.Character
    if not Character then return end

    local Humanoid = Character:FindFirstChildOfClass("Humanoid")
    local Root = Character:FindFirstChild("HumanoidRootPart")

    if not Humanoid or not Root or Humanoid.Health <= 0 then return end
    return Character, Humanoid, Root
end

local function IsGoalkeeper()
    return LocalPlayer:GetAttribute("TeamPosition") == "GK"
end

local function GetOwnGoal()
    local Side = LocalPlayer:GetAttribute("IsHomeOrAway")
    if Side ~= "Home" and Side ~= "Away" then return end

    local Stadium = workspace:FindFirstChild("Stadium")
    local Teams = Stadium and Stadium:FindFirstChild("Teams")
    local Team = Teams and Teams:FindFirstChild(Side)

    return Team and Team:FindFirstChild("Goal")
end

local function IsOpponent(Player)
    if Player == LocalPlayer then return false end
    if Player:GetAttribute("IsOnPitch") ~= true then return false end

    return Player:GetAttribute("IsHomeOrAway")
        ~= LocalPlayer:GetAttribute("IsHomeOrAway")
end

local function GetOpponentCarrier()
    for _, Player in Players:GetPlayers() do
        if IsOpponent(Player) and Player:GetAttribute("HasBall") == true then
            return Player
        end
    end
end

local function GetThreatLateral(Goal, Player)
    local Character = Player.Character
    local Root = Character and Character:FindFirstChild("HumanoidRootPart")

    if not Root then return 0 end

    local LocalPosition = Goal.CFrame:PointToObjectSpace(Root.Position)
    return math.clamp(LocalPosition.X, -GOAL_LATERAL_LIMIT, GOAL_LATERAL_LIMIT)
end

local function MoveToGoalPosition(Humanoid, Root, Goal, Lateral)
    local TargetLateral = math.clamp(Lateral, -GOAL_LATERAL_LIMIT, GOAL_LATERAL_LIMIT)
    local Target = Goal.CFrame:PointToWorldSpace(
        Vector3.new(TargetLateral, 0, GOAL_FORWARD_OFFSET)
    )

    local Current = Goal.CFrame:PointToObjectSpace(Root.Position)

    if math.abs(Current.X - TargetLateral) <= MOVE_THRESHOLD
        and math.abs(Current.Z - GOAL_FORWARD_OFFSET) <= MOVE_THRESHOLD then
        return
    end

    Humanoid:MoveTo(Target)
end

local function StopMovement(Humanoid)
    local Root = Humanoid.RootPart
    if Root then
        Humanoid:MoveTo(Root.Position)
    end
end

RunService.Heartbeat:Connect(function()
    if not Running or not IsGoalkeeper() then return end

    local Character, Humanoid, Root = GetCharacter()
    if not Character then return end

    if LocalPlayer:GetAttribute("HasBall") == true then
        StopMovement(Humanoid)
        return
    end

    local Goal = GetOwnGoal()
    if not Goal or not Goal:IsA("BasePart") then return end

    local Carrier = GetOpponentCarrier()

    if Carrier then
        LastOpponentCarrier = Carrier
    elseif LastOpponentCarrier
        and IsOpponent(LastOpponentCarrier)
        and LastOpponentCarrier:GetAttribute("HasBall") == true then
        Carrier = LastOpponentCarrier
    else
        LastOpponentCarrier = nil
    end

    if Carrier then
        MoveToGoalPosition(
            Humanoid,
            Root,
            Goal,
            GetThreatLateral(Goal, Carrier)
        )
    else
        MoveToGoalPosition(Humanoid, Root, Goal, 0)
    end
end)
