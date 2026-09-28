# AutoGK_FSS — Game Knowledge Wiki

This document is the persistent technical reference for the Auto GK project.

The purpose of this file is to record exact game paths, attribute names, values, controller APIs, decompiled behavior, confirmed facts, and unconfirmed behavior so future work does not have to rely on memory or assumptions.

---

# 1. Project purpose

AutoGK controls the existing `Players.LocalPlayer` character as a goalkeeper.

It does not create a second character.

The bot is intended to behave like a normal goalkeeper using the game's existing movement, possession, shooting/throwing, animation, and Leap systems.

The core goalkeeper loop is:

1. Determine whether the LocalPlayer is the goalkeeper.
2. Determine which team/side the LocalPlayer is on.
3. Find the LocalPlayer's own goal and goalkeeper region.
4. Find opponent players who are on the pitch.
5. Prefer opponent players whose `HasBall` attribute is `true`.
6. Find the football associated with the relevant player.
7. Read the football's live `AssemblyLinearVelocity`.
8. Predict whether the football can enter the own goal's `InterceptionHitbox`.
9. Move the existing goalkeeper toward the interception point.
10. Use the actual game's Leap manager when a dive is useful.
11. Let physical contact with the football produce possession.
12. When the goalkeeper has the ball, stop interception behavior and let the game's normal goalkeeper possession/throw mechanics handle it.

---

# 2. Important terminology

## Attribute

An Attribute is Roblox instance metadata accessed with:

```lua
Instance:GetAttribute("AttributeName")
```

or changed with:

```lua
Instance:SetAttribute("AttributeName", value)
```

When this wiki says something like:

`HasBall` attribute

it specifically means:

```lua
Player:GetAttribute("HasBall")
```

It does NOT mean a child Instance named `HasBall`.

## BasePart

A football is a Roblox `BasePart`.

This means properties such as:

- `Position`
- `CFrame`
- `Size`
- `AssemblyLinearVelocity`

are available.

## LocalPlayer

The controlled player is:

```lua
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
```

The bot operates this player's existing character.

---

# 3. LocalPlayer attributes

The LocalPlayer has several important attributes.

## IsHomeOrAway

Attribute name:

`IsHomeOrAway`

Access:

```lua
LocalPlayer:GetAttribute("IsHomeOrAway")
```

Known values:

- `"Home"`
- `"Away"`

This tells which side/team the player belongs to.

Example:

```lua
local Side = LocalPlayer:GetAttribute("IsHomeOrAway")

if Side == "Home" then
    -- LocalPlayer is on Home
elseif Side == "Away" then
    -- LocalPlayer is on Away
end
```

This attribute should be used to select the corresponding team model under:

`workspace.Stadium.Teams`

For example:

```lua
workspace.Stadium.Teams[Side]
```

Do not hard-code Home or Away as the own side.

---

## TeamPosition

Attribute name:

`TeamPosition`

Access:

```lua
LocalPlayer:GetAttribute("TeamPosition")
```

Known values include:

- `"CF"`
- `"LF"`
- `"RF"`
- `"CM"`
- `"LB"`
- `"RB"`
- `"GK"`

For Auto GK, the LocalPlayer is considered a goalkeeper when:

```lua
LocalPlayer:GetAttribute("TeamPosition") == "GK"
```

---

## HasBall

Attribute name:

`HasBall`

Access:

```lua
Player:GetAttribute("HasBall")
```

Known behavior:

- `true` means the player currently has possession of the football.
- A goalkeeper touching the football can obtain possession.
- The bot should check opponent players for this attribute before selecting a free football based only on physics.

Example:

```lua
if Player:GetAttribute("HasBall") == true then
    -- Player is the current possessor.
end
```

The LocalPlayer can also have:

```lua
LocalPlayer:GetAttribute("HasBall") == true
```

When the GK has the ball, interception logic should stop.

---

## IsOnPitch

Attribute name:

`IsOnPitch`

Access:

```lua
Player:GetAttribute("IsOnPitch")
```

Known behavior:

- `true` means the player is currently on the pitch.
- Auto GK should generally only consider opponent players with `IsOnPitch == true`.

---

## Evading

Attribute name:

`Evading`

This attribute can exist on players and is related to evading/dribbling behavior.

Its exact values and complete semantics have not been fully documented yet.

Do not assume a particular value means a particular animation/state until confirmed.

---

# 4. Player-side selection

Players can be inspected with:

```lua
for _, Player in Players:GetPlayers() do
    -- inspect Player attributes
end
```

The recommended order for finding the relevant attacking threat is:

1. Ignore `LocalPlayer`.
2. Require `IsOnPitch == true`.
3. Require the player's side to be different from LocalPlayer's `IsHomeOrAway`.
4. Check `HasBall == true`.
5. Find the football closest to that player.

The opponent's `HasBall` attribute is currently the preferred possession indicator.

`NetworkOwner` is NOT the primary possession test.

---

# 5. Character

The controlled character is:

```lua
local Character = LocalPlayer.Character
```

Important children:

- `Humanoid`
- `HumanoidRootPart`

Get them with:

```lua
local Humanoid = Character:FindFirstChildOfClass("Humanoid")
local Root = Character:FindFirstChild("HumanoidRootPart")
```

The bot must use the existing character.

---

# 6. Normal movement

The character can be moved using:

```lua
Humanoid:MoveTo(Position)
```

The game also has a MovementController.

Obtain it with Knit:

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Knit = require(ReplicatedStorage.Packages.Knit)

local MovementController = Knit.GetController("MovementController")
```

Sprint control:

```lua
MovementController:SetSprintingControlState(true)
```

Stop sprint:

```lua
MovementController:SetSprintingControlState(false)
```

Known sprinting WalkSpeed:

`27`

This is useful because the bot has to estimate how quickly the GK can reach a predicted interception point.

The GK can freely move around the goalkeeper area. There is no known artificial requirement to stay at one fixed goalkeeper position.

---

# 7. Jump

Known jump method:

```lua
Character.Humanoid:ChangeState(
    Enum.HumanoidStateType.Jumping
)
```

Jump is available to the character.

The Auto GK should not jump constantly. It should only be used when future goalkeeper logic determines that vertical reach is useful.

---

# 8. Leap / GK dive

The Leap manager is located at:

```
Players.LocalPlayer.PlayerScripts.Client.Controllers.Actions.Managers.Leap
```

Exact require:

```lua
local Leap = require(
    game:GetService("Players").LocalPlayer
        .PlayerScripts.Client.Controllers.Actions.Managers.Leap
)
```

## Left dive

Use:

```lua
Leap.Activate("Left")
```

Exact direct form:

```lua
require(
    game:GetService("Players").LocalPlayer
        .PlayerScripts.Client.Controllers.Actions.Managers.Leap
).Activate("Left")
```

## Right dive

Use:

```lua
Leap.Activate("Right")
```

Exact direct form:

```lua
require(
    game:GetService("Players").LocalPlayer
        .PlayerScripts.Client.Controllers.Actions.Managers.Leap
).Activate("Right")
```

## Forward dive

The Leap manager can be called without an argument:

```lua
Leap.Activate()
```

Important:

```lua
Leap.Activate("Forward")
```

does NOT work.

Do not use the string `"Forward"` as a Leap argument.

Forward Leap is optional experimental behavior. Left/right Leap is the reliable goalkeeper dive interface currently confirmed.

## What Leap actually does

The Leap manager:

1. Gets LocalPlayer's Character.
2. Gets `HumanoidRootPart`.
3. Gets `HumanoidRootPart.LeapPosition`.
4. Gets `HumanoidRootPart.LeapOrientation`.
5. Checks the Leap cooldown through ActionController.
6. Calls the game's ActionController internally.
7. Enables `LeapOrientation`.
8. Enables `LeapPosition`.
9. Calculates a lateral direction.
10. Sets the movement target.
11. Plays the corresponding animation.
12. Disables the movers after the configured Leap lifetime.

Therefore Auto GK should NOT manually reproduce Leap physics.

The bot should call the game's Leap manager.

## Leap direction

The manager determines left/right using the character's orientation and movement direction.

Therefore Auto GK must be careful about the goalkeeper's facing direction before deciding whether to call:

```lua
Leap.Activate("Left")
```

or:

```lua
Leap.Activate("Right")
```

---

# 9. ActionController

The ActionController is NOT the Actions ModuleScript itself.

Correct controller acquisition:

```lua
local Knit = require(
    game:GetService("ReplicatedStorage").Packages.Knit
)

local ActionController = Knit.GetController("ActionController")
```

The ActionController exposes:

- `RequestAction`
- `PerformAction`
- `StopAction`
- `IsOnCooldown`
- `GetBindings`
- `GetKeybind`
- `GetConfiguration`

Important implementation detail:

The Leap manager itself internally calls:

```lua
ActionController:RequestAction("Leap")
```

Auto GK should therefore directly call the Leap manager instead of manually duplicating this chain.

---

# 10. Football discovery

Football objects are found in:

```
workspace.Misc
```

The known football identification rules are:

1. Object is a `BasePart`.
2. Object name begins with `"Football "`.
3. Object has an `Enabled` attribute.
4. The football is active when `Enabled == true`.

Example:

```lua
for _, Object in workspace.Misc:GetChildren() do
    if Object:IsA("BasePart")
        and Object.Name:sub(1, 9) == "Football "
        and Object:GetAttribute("Enabled") == true then

        -- active football
    end
end
```

---

# 11. Football attributes

Known football attributes include:

## Enabled

Attribute:

`Enabled`

Access:

```lua
Ball:GetAttribute("Enabled")
```

Known active value:

`true`

---

## State

Attribute:

`State`

Access:

```lua
Ball:GetAttribute("State")
```

Confirmed observed values:

- `"Possessed"`
- `"Released"`

There may be more states. They have not been fully enumerated.

Do not assume that these are the only possible values.

---

## NetworkOwner

Attribute:

`NetworkOwner`

Access:

```lua
Ball:GetAttribute("NetworkOwner")
```

An observed value looked like a player name, for example:

`"tumbleScripts0002"`

This can provide ownership information, but it should NOT be used as the primary Auto GK possession test.

Prefer player `HasBall`.

---

## ReleasePosition

Attribute:

`ReleasePosition`

This records the football's release position.

Example observed value:

```
136.5000457763672, -6.563745975494385, -390.21844482421875
```

---

## ReleaseVelocity

Attribute:

`ReleaseVelocity`

This records the football's release velocity.

Example observed value:

```
-14.114134788513184,
84.31346118164062,
108.96917724609375
```

The live physics property should still be preferred for current prediction:

```lua
Ball.AssemblyLinearVelocity
```

---

## ReleaseId

Attribute:

`ReleaseId`

Observed as a UUID-like value.

Example:

```
{fc3dcf4d-1dd0-4cb3-a41c-811e65ece4f1}
```

---

## BlockBallPickUpTill

Attribute:

`BlockBallPickUpTill`

This can temporarily prevent pickup/possession.

Example observed numeric value:

`8079.064212894009`

The exact timing/reference system has not been fully documented.

---

# 12. Live football velocity

The football is a `BasePart`.

The actual current velocity is:

```lua
Ball.AssemblyLinearVelocity
```

This has been explicitly confirmed to represent the live football velocity.

Auto GK trajectory prediction should therefore start from:

```lua
local Position = Ball.Position
local Velocity = Ball.AssemblyLinearVelocity
```

Do not assume `ReleaseVelocity` remains the current velocity after physics changes.

---

# 13. Football physics defaults

Module:

```
ReplicatedStorage.Shared.Defaults.Football
```

Confirmed values:

## Gravity

The actual game/world gravity relevant to the football is:

`196.1999969482422`

This is the value that Auto GK trajectory prediction should currently use.

Do NOT use `55` as football gravity.

The previous Auto GK implementation incorrectly treated the Football defaults value `Gravity = 55` as the actual physics gravity. That was incorrect.

---

## VelocityDampening

Football default:

`0.755`

The exact way this value is applied over time has not yet been confirmed.

Do not invent a dampening equation.

If implementing prediction before the exact application is known, use the live `AssemblyLinearVelocity` plus confirmed gravity and clearly mark the model as approximate.

---

## MaximumFootballs

`30`

---

## HighShotPowerThreshold

`67.5`

---

## HighShotPowerThresholdExtension

`53`

---

# 14. Football velocity ranges

From `ReplicatedStorage.Shared.Defaults.Football.Velocity`:

| Action | Velocity |
|---|---:|
| Kick | 32.5–138.5 |
| Pass | 34–120 |
| Throw | 32.5–110 |
| Header | 85–130 |
| LowVolley | 40–133 |
| BicycleKick | 110 |

These are game defaults, not necessarily the exact velocity of every individual football event.

---

# 15. Football charge times

From `ReplicatedStorage.Shared.Defaults.Football.ChargeTimes`:

| Action | Charge time |
|---|---:|
| PowerShot | 0.4 |
| Pass | 0.6 |
| Header | 0.5 |
| LowVolley | 0.45 |

---

# 16. Football timing defaults

From `ReplicatedStorage.Shared.Defaults.Football.Timings`:

- `GeneralPossessionCooldown = 0.25`
- `HighShotPowerGhostingThreshold = 1`
- `HighWallSelfPassExpiration = 6`
- `RapidPossessionCooldown = 0.35`
- `PreparedShotProcessExtension = 0.6`

---

# 17. Football directions

From `ReplicatedStorage.Shared.Defaults.Football.Directions`:

- Kick:
  `Vector3.new(0, 0.6087614297866821, 0.7933533191688232)`
- LowVolley:
  `Vector3.new(0, 0.2672383785247803, 1)`
- Pass:
  `Vector3.new(0, 0, 1)`
- Throw:
  `Vector3.new(0, 0.4226182699203491, 0.9063078165054321)`
- BicycleKick:
  `Vector3.new(0, 0.27000001072883606, 1).Unit`
- Header:
  `Vector3.new(0, 0.400000005728..., 1).Unit`

These defaults are useful when understanding the game's shot system, but Auto GK should prefer live football velocity for defending.

---

# 18. Goal structure

Stadium:

```
workspace.Stadium
```

Teams:

```
workspace.Stadium.Teams
```

Known team models:

```
workspace.Stadium.Teams.Home
workspace.Stadium.Teams.Away
```

Each team has:

```
Team.Goal
Team.Barriers.Goalkeeper
Team.Bounds.Goal
```

The own team is determined by LocalPlayer's `IsHomeOrAway` attribute.

---

# 19. Own goalkeeper area

Path:

```
workspace.Stadium.Teams[Side].Barriers.Goalkeeper
```

where:

```lua
local Side = LocalPlayer:GetAttribute("IsHomeOrAway")
```

The goalkeeper barrier contains parts named `NoCharacter`.

The GK can freely move in the goalkeeper area.

This area can be used as a movement constraint if later needed.

---

# 20. Own goal

Path:

```
workspace.Stadium.Teams[Side].Goal
```

The goal is a Model.

Known children:

- `Hitbox`
- `InterceptionHitbox`
- `Collision`

---

# 21. Goal Hitbox

The `Hitbox` is a Part.

Its dimensions represent the actual goal scoring region.

The Auto GK should generally use `InterceptionHitbox` for defensive prediction because it is slightly larger.

---

# 22. Goal InterceptionHitbox

The `InterceptionHitbox` is a Part.

It is larger than the normal goal `Hitbox`.

It is intended to be useful as the region in which the goalkeeper should attempt an interception.

Prediction should test a future football position against this Part using its CFrame and Size rather than hard-coded world coordinates.

Example point-in-box calculation:

```lua
local LocalPoint = Goal.CFrame:PointToObjectSpace(WorldPoint)
local HalfSize = Goal.Size * 0.5

local Inside =
    math.abs(LocalPoint.X) <= HalfSize.X
    and math.abs(LocalPoint.Y) <= HalfSize.Y
    and math.abs(LocalPoint.Z) <= HalfSize.Z
```

---

# 23. Home goal measurements

## Home Hitbox

Size:

```
31.327247619628906,
11.277809143066406,
8.33917236328125
```

CFrame position:

```
86.4280701,
-1.80362248,
-420.158569
```

Rotation:

identity orientation.

## Home InterceptionHitbox

Size:

```
33.192832946777344,
11.70659351348877,
10.094496726989746
```

CFrame position:

```
86.3431778,
-1.58926702,
-419.280945
```

Rotation:

identity orientation.

---

# 24. Away goal measurements

## Away Hitbox

Size:

```
31.327247619628906,
11.277809143066406,
8.289474487304688
```

CFrame position:

```
86.2023621,
-1.70572662,
-47.753933
```

Rotation:

approximately:

```
-1,0,0,
 0,1,0,
 0,0,-1
```

## Away InterceptionHitbox

Size:

```
33.19300079345703,
11.70699977874756,
10.093999862670898
```

CFrame position:

```
86.3023605,
-1.70572662,
-48.3733177
```

Rotation:

approximately:

```
-1,0,0,
 0,1,0,
 0,0,-1
```

Home and Away goals face opposite directions.

Therefore:

- Never assume the own goal is always at positive Z or negative Z.
- Use the goal's CFrame to derive its orientation.
- Use local-space coordinates when determining lateral/depth relationships.

---

# 25. Goal Collision model

The goal also contains:

```
Goal.Collision
```

This is a Model.

Known children:

- `Center`
- `Front`
- `Left`
- `Right`
- `Top`

The Collision model is known but is NOT currently required for the first Auto GK implementation.

Do not substitute Collision geometry for the InterceptionHitbox unless testing proves it is necessary.

---

# 26. Player/GK hitbox dimensions

Approximate normal player hitbox:

```
4.520999908447266,
5.730000019073486,
2.3980000019073486
```

Approximate goalkeeper hitbox:

```
4.520999908447266,
5.730000019073486,
2.6480000019073486
```

The GK is therefore slightly wider than a normal player in the documented dimension.

---

# 27. GK ball interaction

There is no separately confirmed "Save" action.

The goalkeeper gets the football by physically touching it.

Therefore:

- Moving the GK into the football can produce possession.
- A Leap is primarily a movement/boost/dive mechanism.
- The bot should not invent a separate save API.
- A successful dive is useful because it moves the GK's physical character toward the ball.

This is important: Leap itself is not documented as a magical "catch ball" function.

---

# 28. GK possession duration

Once the goalkeeper has the ball:

- The game allows the GK to hold it for roughly 7 seconds.
- After that, the game forces the ball out.

The exact timer implementation has not been reverse-engineered yet.

Auto GK should not implement its own fake 7-second timer unless necessary.

---

# 29. Primary action

The game's ActionPrimary manager uses `PrepareShot`.

Its start behavior is effectively:

```lua
PrepareShot.Activate("Kick", ...)
```

and release:

```lua
PrepareShot.Activate("Release", id)
```

Primary is the kick/shoot/cross action.

For the goalkeeper, primary does NOT become the throw action.

---

# 30. Secondary action

The game's ActionSecondary manager normally prepares a Pass.

However, when:

1. The player is a goalkeeper, and
2. The goalkeeper has the ball,

the secondary action changes from:

`"Pass"`

to:

`"Throw"`

Therefore GK secondary is the game's normal throw mechanic.

The GK must have the ball for this goalkeeper-specific secondary behavior.

---

# 31. PrepareShot

PrepareShot is located under the Actions managers.

It exposes:

- `GetPayload()`
- `Activate("Kick", ...)`
- `Activate("Release", id)`
- `GetPreviousReleaseVelocity()`
- `GetPreviousReleaseEndPoint()`

Payload structure observed:

```lua
{
    Id = "",
    Active = false,
    MaximumChargeTime = 0,
    Shot = "",
    Specialty = "",
    Charge = 0,
}
```

PrepareShot eventually changes the possessed football's `State` attribute to:

`"Released"`

and calls the football component's shoot behavior.

---

# 32. PrepareShot camera direction

PrepareShot obtains camera direction from:

```lua
workspace.CurrentCamera.CFrame.LookVector
```

It flattens the direction to X/Z:

```lua
Vector3.new(LookVector.X, 0, LookVector.Z).Unit
```

Therefore camera orientation is relevant to normal shooting/throwing behavior.

---

# 33. Ball selection strategy

The recommended Auto GK ball-selection order is:

## Stage 1 — Find attacking players

Loop through Players.

For each player:

- Not LocalPlayer.
- `IsOnPitch == true`.
- `IsHomeOrAway` differs from LocalPlayer's `IsHomeOrAway`.
- `HasBall == true`.

These players are active attacking possessors.

## Stage 2 — Associate the football

Loop active footballs in `workspace.Misc`.

Find the football closest to the possessor's HumanoidRootPart.

A possessed football should normally be physically near its possessor.

## Stage 3 — If nobody has the ball

Look through active footballs and inspect:

```lua
Ball.AssemblyLinearVelocity
```

Prioritize balls whose current velocity is directed toward the own goal.

## Stage 4 — Predict danger

Use current position + current velocity + actual gravity.

Do not assume a released ball travels forever using a constant velocity because the game's `VelocityDampening = 0.755` behavior is not yet fully understood.

---

# 34. Trajectory prediction

Confirmed values:

- Current position: Ball.Position
- Current velocity: Ball.AssemblyLinearVelocity
- Gravity: 196.1999969482422

The GK should NOT wait for the predicted football position to enter the goal hitbox before reacting.

The current Auto GK predictor estimates when the ball crosses the goal's local Z=0 plane:

1. Convert the football position into the goal's local space.
2. Convert the live velocity into the goal's local space.
3. Solve the time required for local Z to reach 0.
4. Reject negative or excessively distant interception times.
5. Apply the confirmed gravity to the predicted world position.
6. Use the predicted local X position as the goalkeeper's lateral target.
7. Keep the goalkeeper several studs in front of the goal rather than directly on the goal line.

This makes the goalkeeper react while the shot is still approaching the goal.

Basic ballistic approximation:

Position + Velocity * Time + Vector3.new(0, -0.5 * 196.1999969482422 * Time * Time, 0)

This is only the no-dampening approximation.

The actual game also has VelocityDampening = 0.755, but the exact implementation of that damping has not yet been confirmed.

Do not claim the simple equation is the exact game physics.

# 35. Diving strategy

Left/right Leap should be selected from the predicted lateral displacement.

The bot should not simply face directly toward the interception point and then ask Leap for Left/Right.

Why:

Leap's Left/Right directions are relative to the character's orientation.

Therefore the bot needs a stable goalkeeper-facing orientation first, then determine whether the interception point is on the character's left or right.

Confirmed calls:

```lua
Leap.Activate("Left")
Leap.Activate("Right")
```

Optional forward call:

```lua
Leap.Activate()
```

Invalid forward string:

```lua
Leap.Activate("Forward")
```

---

# 36. Tackle behavior

The goalkeeper's tackle behavior is effectively associated with Leap/dive behavior.

Known:

- Normal players can tackle.
- Goalkeepers can tackle.
- Players cannot tackle the GK in the same way.
- GK Leap can function as the goalkeeper's dive/boost/tackle-like movement.

No separate goalkeeper "Save" API has been confirmed.

---

# 37. Controllers and services

Known relevant client controllers include:

- ActionController
- MovementController
- AnimationController
- InputController
- MatchController
- SkillsController
- SoundController
- Stamina
- FootballLocators
- AgentLocators
- Player
- Camera

The exact list observed also included:

- Data
- Movement
- Sound
- Packs
- Lobby
- Lighting
- Skills
- Match
- Particle
- Player
- Animation
- Trade
- Competitive
- Chat
- Camera
- Admin
- Weather
- Actions
- Input
- GlobalConfig
- FootballLocators
- Mannequins
- InfluencerStudioTools
- Freecam
- ItemInteractions
- MarketplaceController
- PacksScene
- Party
- Purchase
- RAPMilestones
- CardDisplay
- FinalMinute
- AgentLocators

Only use a controller when its API has actually been confirmed.

---

# 38. Important exact paths

## LocalPlayer

```
Players.LocalPlayer
```

## PlayerScripts

```
Players.LocalPlayer.PlayerScripts
```

## Client Controllers

```
Players.LocalPlayer.PlayerScripts.Client.Controllers
```

## Actions

```
Players.LocalPlayer.PlayerScripts.Client.Controllers.Actions
```

## Leap manager

```
Players.LocalPlayer.PlayerScripts.Client.Controllers.Actions.Managers.Leap
```

## Football defaults

```
ReplicatedStorage.Shared.Defaults.Football
```

## Stadium

```
workspace.Stadium
```

## Teams

```
workspace.Stadium.Teams
```

## Home team

```
workspace.Stadium.Teams.Home
```

## Away team

```
workspace.Stadium.Teams.Away
```

## Own goal

```
workspace.Stadium.Teams[
    LocalPlayer:GetAttribute("IsHomeOrAway")
].Goal
```

## Own goalkeeper barrier

```
workspace.Stadium.Teams[
    LocalPlayer:GetAttribute("IsHomeOrAway")
].Barriers.Goalkeeper
```

## Football container

```
workspace.Misc
```

---

# 39. Confirmed vs unknown information

## Confirmed

- LocalPlayer is the controlled GK character.
- `IsHomeOrAway` is an attribute.
- `TeamPosition` is an attribute.
- `HasBall` is an attribute.
- `IsOnPitch` is an attribute.
- Active footballs are BaseParts in `workspace.Misc`.
- Football names begin with `"Football "`.
- Footballs have an `Enabled` attribute.
- `AssemblyLinearVelocity` is the live football velocity.
- Actual gravity for prediction is `196.1999969482422`.
- Football default `VelocityDampening` is `0.755`.
- GK gets possession by touching the football.
- GK can move freely in its goalkeeper region.
- Sprint control uses MovementController.
- Sprinting speed is approximately 27.
- Left Leap is `Leap.Activate("Left")`.
- Right Leap is `Leap.Activate("Right")`.
- Forward Leap, if attempted, is `Leap.Activate()`, not `Leap.Activate("Forward")`.
- Own goal is selected from `IsHomeOrAway`.
- Own goal contains `Hitbox` and `InterceptionHitbox`.
- Home and Away goals face opposite directions.
- GK secondary becomes Throw when the GK has the ball.
- GK ball possession lasts roughly 7 seconds before forced release.
- There is no separately confirmed save API.

## Unknown / not fully reverse-engineered

- Complete football `State` enumeration.
- Exact mathematical implementation of `VelocityDampening = 0.755`.
- Exact implementation of the forced GK ball release timer.
- Exact conditions under which a football can be picked up after `BlockBallPickUpTill`.
- Exact collision/possession internals for every type of football contact.
- Exact best threshold for deciding when a GK should Leap.
- Exact best prediction horizon.
- Exact relationship between Leap lifetime and physical interception range.
- Whether forward Leap should be used routinely.
- Exact vertical jump/dive behavior required for different shot types.

Do not turn unknown items into assumptions without testing or a new decompile.

---

# 40. Auto GK implementation rules

When modifying `Script.lua`:

1. Use the existing LocalPlayer character.
2. Use actual game controllers where their APIs are known.
3. Prefer player `HasBall` over football `NetworkOwner`.
4. Use `AssemblyLinearVelocity` for live velocity.
5. Use gravity `196.1999969482422`.
6. Do not use gravity `55` for football trajectory prediction.
7. Do not invent the damping equation for `VelocityDampening = 0.755`.
8. Use the own team's `InterceptionHitbox`.
9. Derive goal direction from CFrame instead of hard-coding Home/Away Z direction.
10. Use `Leap.Activate("Left")` or `Leap.Activate("Right")` for lateral dives.
11. If testing forward Leap, call `Leap.Activate()` with no argument.
12. Never use `Leap.Activate("Forward")`.
13. Do not manually recreate LeapPosition/LeapOrientation physics.
14. Do not invent a separate save action.
15. Treat physical contact with the ball as the mechanism for obtaining GK possession.
16. Keep confirmed facts separate from experimental heuristics.

---

# 41. Current Auto GK design

The current implementation uses explicit goalkeeper behavior states rather than treating the GK as a simple "move to the predicted goal point" bot.

States currently used:

- IDLE: LocalPlayer is not currently acting as GK or required GK data is unavailable.
- POSITION: No immediate scoring trajectory is detected; maintain a sensible central/set position.
- TRACK: Track an attacker or approaching football and shade laterally toward the threat.
- READY: A scoring trajectory exists with roughly 0.45–1.0 seconds until the goal plane.
- COMMIT: A scoring trajectory is close, with roughly 0–0.45 seconds until the goal plane; move aggressively and allow a dive.
- POSSESSION: LocalPlayer has HasBall == true; interception behavior stops.

Positioning behavior:

- The GK's set position is several studs in front of the goal line.
- When tracking, the GK moves only a fraction of the ball/attacker's lateral displacement.
- This prevents a distant attacker from dragging the GK all the way sideways.
- The GK can begin moving before a shot reaches the goal.
- Fast shots are evaluated using their time to the goal plane rather than waiting for a hitbox intersection.
- If there is no ball, the GK returns toward the set position instead of using the old goal-center depth behavior.

Main flow:

LocalPlayer
  |
  +-- TeamPosition == GK?
  |
  +-- own Goal -> InterceptionHitbox
  |
  +-- LocalPlayer HasBall?
  |     |
  |     +-- yes -> POSSESSION
  |
  +-- opponent HasBall / active football
        |
        +-- direct goal-plane trajectory?
        |     |
        |     +-- yes -> TRACK / READY / COMMIT
        |            |
        |            +-- MoveTo predicted lateral position
        |            |
        |            +-- Leap when close enough
        |
        +-- no -> TRACK / POSITION
               |
               +-- shade toward ball/possessor
               |
               +-- remain centered and in front of goal

Fallback when nobody has HasBall == true:

workspace.Misc
  |
  +-- active Football BaseParts
        |
        +-- AssemblyLinearVelocity
              |
              +-- moving toward own goal?
                    |
                    +-- goal-plane prediction

# 42. Debugging

The current script exposes:

_G.AutoGKDebug

Useful fields:

- State
- StateSince
- Ball
- Goal
- Possessor
- PredictedPosition
- TimeToGoal
- Target
- BallVelocity
- BallState
- BallLocalPosition when there is no direct goal-plane prediction

The script also prints a throttled one-line status approximately once per second.

This is intended for testing and tuning the goalkeeper state machine and prediction system.

If the bot behaves incorrectly, inspect these values before changing physics assumptions.

# 43. Source/decompile references

Important decompiled modules that supplied the above behavior:

- `Players.tumbleScripts0002.PlayerScripts.Client.Controllers.Actions`
- `Players.tumbleScripts0002.PlayerScripts.Client.Controllers.Actions.Managers.Leap`
- `StarterPlayer.StarterPlayerScripts.Client.Controllers.Actions.Managers.Sprint`
- `ReplicatedStorage.Shared.Defaults.Football`
- `ActionPrimary`
- `ActionSecondary`
- `PrepareShot`

The ActionController decompile confirmed that its module is a Knit controller and that its `RequestAction` / `PerformAction` methods are controller methods.

The Leap manager decompile confirmed that Leap itself calls the ActionController and controls `LeapPosition` / `LeapOrientation`.

---

# 44. Change log

## Initial project knowledge

Recorded:

- Character movement
- Sprinting
- Jumping
- Leap
- ActionController
- Football discovery
- Football attributes
- Ball possession
- Football physics
- Goal geometry
- GK hitbox
- GK possession
- Shooting
- Throwing
- Goalkeeper region
- Player positions
- Current Auto GK strategy

## Physics correction

The first Auto GK implementation incorrectly recorded football gravity as 55.

Correct value:

196.1999969482422

The value 55 must NOT be used as the football trajectory gravity.

## Reactive tracking rebuild

The previous prediction-first implementation was replaced.

The current implementation deliberately starts with continuous threat tracking:

1. Find an opponent with HasBall.
2. Associate the nearest active football with that player when possible.
3. If nobody has HasBall, select a nearby moving active football.
4. Recalculate the threat position every update.
5. Move the GK toward a goal-relative tracking position based on that threat.
6. Track the threat laterally strongly enough to produce visible movement.
7. Apply only a limited depth adjustment so the GK does not chase the attacker out of position.
8. Keep diving as a secondary behavior rather than making prediction the primary movement system.

The current script intentionally does not depend on goal-plane prediction for basic movement. Prediction/save logic should be added only after continuous ball/player tracking is behaving correctly.

The tracking system is an Auto GK heuristic, not confirmed game AI behavior.
