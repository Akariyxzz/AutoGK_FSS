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

The current implementation uses continuous threat tracking with two movement sources:

1. An opponent ball carrier.
2. A loose active football when nobody on the opposing team currently has possession.

The important distinction is that **loose-ball tracking is allowed, but loose-ball chasing is not**.

## Opponent has the ball

When an opponent has:

\`\`\`lua
Player:GetAttribute("HasBall") == true
\`\`\`

the GK tracks that player.

The target uses:

- limited lateral movement toward the attacker;
- limited depth adjustment;
- a goalkeeper set position several studs in front of the goal.

This prevents the attacker from dragging the GK too far out of position.

## Ball is loose

When there is no opponent ball carrier, the nearest active non-possessed football can become the tracking source.

The GK uses a short predicted ball position based on the football's live velocity and the documented gravity approximation.

The ball's local position relative to the own goal is then converted into a goalkeeper movement target.

Loose-ball tracking is constrained:

- lateral target is clamped to approximately `-12` to `12` studs in goal-local X;
- depth is clamped to approximately `6` to `11` studs in front of the goal;
- therefore a ball far upfield cannot make the GK run toward the ball;
- the GK can still move laterally across the goal mouth to follow the ball.

## Overhead ball

A nearby rising loose ball can trigger the existing overhead jump detector.

The ball used for jump detection does not bypass the goalkeeper positioning constraints and does not directly become the `Humanoid:MoveTo()` target.

## Main flow

\`\`\`
LocalPlayer
  |
  +-- TeamPosition == GK?
  |
  +-- LocalPlayer HasBall?
  |     |
  |     +-- yes -> stop interception movement
  |
  +-- own Goal
  |
  +-- opponent HasBall?
  |     |
  |     +-- yes -> track opponent
  |
  +-- loose active football
        |
        +-- nearby overhead trajectory?
        |     |
        |     +-- jump
        |
        +-- otherwise -> track loose ball laterally
                         while clamping goalkeeper depth
\`\`\`

The current script therefore does **not** use the football only for jump detection. A loose football is also a movement threat when there is no opponent carrier.

This is an implementation heuristic, not confirmed game AI behavior.

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

The previous prediction-first implementation was replaced with continuous threat tracking.

The tracking system:

1. Finds an opponent with `HasBall`.
2. If an opponent has the ball, tracks the opponent.
3. If nobody has the ball, finds a nearby active loose football.
4. Uses a short predicted ball position for loose-ball tracking.
5. Tracks loose balls laterally across the goal mouth.
6. Clamps loose-ball tracking depth so the GK does not chase a distant football upfield.
7. Keeps overhead jump detection as a separate vertical reaction.
8. Uses the existing goalkeeper character and `Humanoid:MoveTo()` for movement.

The tracking system is an Auto GK heuristic, not confirmed game AI behavior.

## Loose-ball tracking restoration

The loose-ball movement source was temporarily removed too aggressively.

The current implementation restores it with a goalkeeper-area constraint:

- Opponent carrier takes priority when possession is known.
- A free football is used as the movement source only when there is no opponent carrier.
- Ball-local lateral movement is clamped.
- Ball-local depth is clamped to the goalkeeper's useful positioning range.
- The GK can therefore follow a loose ball without running directly toward it from far upfield.


---

# 45. Current Script.lua — exact implementation reference

This section describes the implementation that is actually in `Script.lua` now. It is intentionally more specific than the general design above.

## Services and state

The script currently gets:

```lua
Players
RunService
UserInputService
ReplicatedStorage.Packages.Knit
```

It stores:

- `LocalPlayer`
- `workspace.CurrentCamera`
- `Running`
- `MovementController`
- `Leap`
- `LastJumpAt`
- `LastDiveAt`
- `PendingDiveBall`
- `PendingDiveStartedAt`
- `LastOpponentCarrier`

Current low-ball threshold:

```lua
LOW_BALL_Y = -230
```

Current football prediction constants:

```lua
BALL_GRAVITY = 196.2
PREDICTION_MIN_TIME = 0.08
PREDICTION_MAX_TIME = 0.8
PREDICTION_STEP = 0.03
```

Current overhead constants:

```lua
OVERHEAD_MIN_HEIGHT = 1.5
OVERHEAD_MAX_HEIGHT = 10
OVERHEAD_RADIUS = 9
```

These are Auto GK heuristics. They are not claimed to be values from the game's own AI.

---

# 46. Exact threat-selection behavior

Every Heartbeat, the script first verifies:

```lua
LocalPlayer:GetAttribute("TeamPosition") == "GK"
```

It then gets:

- Character
- Humanoid
- HumanoidRootPart

If the character is missing, dead, or the player has the ball, the update exits.

The opponent carrier is found by checking every player for:

```lua
Player ~= LocalPlayer
Player:GetAttribute("IsOnPitch") == true
Player:GetAttribute("IsHomeOrAway") ~= getSide()
Player:GetAttribute("HasBall") == true
```

The first valid player is used.

If a valid opponent carrier exists, it is saved as:

```lua
LastOpponentCarrier
```

This matters for the low-ball fallback.

---

# 47. Low-ball fallback

When the nearest active free football has:

```lua
Ball.Position.Y <= -230
```

the script does not chase that football.

Instead, if `LastOpponentCarrier` is still a valid opponent on the pitch, the script changes the threat back to that player.

This prevents a football that has fallen far below the playable pitch from dragging the GK away from the goal.

The fallback is currently evaluated from the nearest free ball each Heartbeat. It is not a permanent state machine/latch.

---

# 48. Exact overhead detection

The current overhead detector intentionally does NOT require:

```lua
Ball.AssemblyLinearVelocity.Y > 8
```

The old rising-only restriction was removed.

Reason:

A shot can already be descending when it enters the goalkeeper's useful interception range. Requiring positive vertical velocity could therefore miss a valid overhead save.

The detector samples:

```lua
0.08s -> 0.8s
```

in increments of:

```lua
0.03s
```

For every sample it calculates:

```lua
Position + Velocity * t
+ Vector3.new(0, -196.2 * 0.5 * t^2, 0)
```

It accepts the sample when:

- predicted height is at least 1.5 studs above the GK;
- predicted height is no more than 10 studs above the GK;
- predicted horizontal distance from the GK is at most 9 studs.

This intentionally gives the GK an early warning window.

There is also a secondary safety test for a football that is already high and moving toward the GK.

The safety test checks:

- current height is between 1.5 and 10 studs above the GK;
- horizontal velocity is nonzero;
- the ball is within 1.5 × the overhead radius;
- horizontal velocity points toward the GK.

---

# 49. Exact overhead reaction

When an overhead prediction succeeds:

1. If the jump cooldown has not expired, the detector continues treating the overhead threat as active.
2. Otherwise, if the Humanoid is grounded, it executes:
   
```lua
Humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
```

3. It stores the ball in `PendingDiveBall`.
4. It stores the jump start time.
5. It returns before normal movement processing.

The current jump cooldown is:

```lua
0.55 seconds
```

The purpose of the pending-ball state is to make an overhead save a two-stage action:

```
detect high ball
    ->
jump
    ->
reach apex
    ->
lateral Leap
```

---

# 50. Exact apex-dive behavior

While `PendingDiveBall` exists, the script waits until:

- the ball still exists;
- `Enabled == true`;
- at least 0.12 seconds have elapsed since the jump;
- the GK's vertical velocity is no longer greater than 1.

Once the apex condition is reached, the script:

1. Clears `PendingDiveBall`.
2. Checks the dive cooldown.
3. Predicts the ball 0.08 seconds ahead.
4. Converts that prediction into the GK's local space.
5. Requires at least 2 studs of lateral displacement.
6. Calls:
   
```lua
Leap.Activate("Left")
```

or:

```lua
Leap.Activate("Right")
```

The side is selected from the ball's local X coordinate relative to the GK.

Current dive cooldown:

```lua
1.0 second
```

---

# 51. Exact ground-dive behavior

Ground dives use a prediction of:

```lua
0.18 seconds
```

The ball must satisfy all of these:

- goal-local depth <= 13 studs;
- goal-local lateral distance >= 4.5 studs;
- local ball velocity points toward the goal plane strongly enough;
- dive cooldown has expired.

The GK then uses the ball's position relative to the character to choose Left or Right Leap.

The script does not call a fictional save API.

The actual Leap manager moves the physical GK.

---

# 52. Exact opponent positioning — current implementation

This is an important distinction from the older implementation.

The current target is NOT based on an arbitrary fixed Z coordinate from `Goal:GetPivot()`.

The script first attempts to use:

```
Goal.InterceptionHitbox.CFrame
```

as the physical goal reference.

Only if `InterceptionHitbox` is unavailable does it fall back to:

```lua
Goal:GetPivot()
```

This matters because a Model pivot is not guaranteed to represent the center of the physical scoring/interception region.

The target calculation is:

1. Get the physical center of the interception box.
2. Get the attacker's HumanoidRootPart.
3. Flatten both positions to X/Z.
4. Calculate the normalized direction from the goal toward the attacker.
5. Calculate the attacker's local shooting angle.
6. Select a forward distance.
7. Put the GK on the goal-to-attacker line at that distance.
8. Preserve the attacker's Y coordinate only as the movement target Y.

The current forward distance is:

```lua
Forward = clamp(10 + AngleWidth * 5, 10, 17)
```

Then it is limited so the GK cannot be placed beyond the attacker:

```lua
Forward = min(
    Forward,
    max(DistanceFromGoal - 3, 6)
)
```

Therefore the intended behavior is:

```
                ATTACKER
                   X
                  /
                 /
                /   GK target
               /       X
              /
        GOAL X
```

The GK is deliberately moved out from the goal along the line toward the attacker.

This is specifically intended to address wide shooting angles.

---

# 53. Why forward movement matters

A goalkeeper sitting too close to the goal line has to cover a large angular area.

For an attacker positioned far to one side, a shot toward the opposite post can travel across a large portion of the goal before reaching the keeper.

Moving the GK forward reduces the effective shooting angle.

Conceptually:

```
DEEP GK

Attacker
   X
    \
     \
      \       large angle
       \
        X GK
       /   \
    post   post
```

versus:

```
FORWARD GK

Attacker
   X
    \
     X GK
    / \
 post   post
```

The second position gives the GK less lateral distance to cover.

The forward movement is therefore not intended to make the GK chase the attacker.

It is intended to make the goal physically smaller from the attacker's shooting position.

---

# 54. Video test reference — 2026-09-28

A gameplay recording was supplied showing the exact failure being discussed.

Observed sequence:

1. The attacking player is positioned outside the goal area and prepares a shot.
2. The goalkeeper remains relatively deep.
3. The shot travels toward the opposite side of the goal.
4. The goalkeeper reacts laterally but does not establish enough forward angle-closing position.
5. The shot reaches the goal before the goalkeeper can compensate.

The important lesson from this test is:

**The failure is not solved simply by increasing the lateral clamp or making overhead detection more sensitive.**

The goalkeeper needs to establish a meaningful forward set position relative to the physical goal and the attacker's current shooting angle.

The current implementation therefore uses `InterceptionHitbox.CFrame` as the reference and explicitly moves along the goal-to-attacker direction.

The video is a behavioral test reference, not a source of exact world coordinates.

---

# 55. Current loose-ball positioning

When there is no opponent carrier, the script can track the nearest active non-possessed football.

It predicts the football 0.12 seconds ahead.

Then it converts that prediction to goal-local coordinates.

Current lateral limit:

```
-12 to +12 studs
```

Current forward/depth range:

```
6 to 11 studs
```

This is intentionally different from opponent positioning.

The GK should not sprint all the way to a random loose football upfield.

The GK instead moves within a controlled goalkeeper positioning envelope.

---

# 56. Movement execution

The final target Y is replaced with the GK's current Y for normal ground movement.

Then:

```lua
DistanceToTarget = (Target - Root.Position).Magnitude
```

If the target is more than 1.5 studs away:

```lua
MovementController:SetSprintingControlState(true)
```

Otherwise sprinting is disabled.

Movement itself uses:

```lua
Humanoid:MoveTo(Target)
```

The script therefore does not directly set:

- WalkSpeed;
- AssemblyLinearVelocity;
- HumanoidRootPart CFrame;

for normal GK movement.

It uses the game's movement controller plus Humanoid movement.

---

# 57. Camera behavior

The current script also calls `trackCamera()` every Heartbeat.

It keeps the camera's current position and changes its orientation to look at the current threat.

The look position is:

```lua
ThreatPosition + Vector3.new(0, 1.5, 0)
```

This means the Auto GK currently takes control of camera orientation.

If later testing shows that camera control interferes with movement, camera tracking should be separated from the goalkeeper AI rather than silently changing movement logic.

---

# 58. Current update priority

The actual decision order is:

```
1. Is Auto GK running?
2. Is LocalPlayer a GK?
3. Is Character/Humanoid/Root valid?
4. Is GK alive?
5. Does GK already have the ball?
6. Find opponent carrier.
7. Save LastOpponentCarrier.
8. Find nearest free football.
9. Apply low-ball fallback.
10. Create debug state.
11. Find own goal.
12. Try overhead jump.
13. Try pending apex dive.
14. Try ground dive.
15. Track opponent carrier if available.
16. Otherwise track loose football.
17. Move with Humanoid:MoveTo().
18. Update sprint state.
19. Update camera.
```

This ordering is important.

In particular:

**Overhead jump is intentionally checked before ground dive.**

This prevents a high shot from being interpreted only as a ground-level lateral dive.

---

# 59. Current debug information

The script creates:

```lua
_G.AutoGKDebug
```

Current useful fields include:

- `ThreatPlayer`
- `ThreatBall`
- `ThreatType`
- `Jump`
- `Dive`
- `JumpBall`
- `JumpPrediction`
- `JumpPredictionTime`
- `DiveBall`
- `DivePrediction`
- `Target`
- `DistanceToTarget`

During future debugging, these fields should be inspected before changing constants.

For example:

```lua
print(_G.AutoGKDebug.Target)
print(_G.AutoGKDebug.Jump)
print(_G.AutoGKDebug.Dive)
```

can distinguish:

- bad threat detection;
- bad positioning;
- bad prediction;
- bad jump timing;
- bad Leap direction.

---

# 60. Important implementation mistakes to avoid

## Do not use Goal:GetPivot() as the only physical goal reference

The Model pivot is not guaranteed to be the center of the scoring/interception region.

Prefer:

```lua
Goal.InterceptionHitbox.CFrame
```

when calculating defensive positioning.

## Do not solve every problem with a larger lateral clamp

A large lateral clamp helps coverage, but it does not fix a goalkeeper who is positioned too deep.

Forward angle-closing and lateral coverage are separate controls.

## Do not require positive ball Y velocity for every overhead save

A valid high shot can already be descending when it becomes dangerous.

## Do not use `Leap.Activate("Forward")`

The confirmed forward form is:

```lua
Leap.Activate()
```

## Do not recreate Leap physics

The game already owns:

- LeapPosition;
- LeapOrientation;
- Leap animation;
- Leap cooldown;
- Leap action handling.

Use the existing manager.

## Do not hard-code Home/Away goal directions

Use goal CFrame/local space.

## Do not assume `NetworkOwner` means possession

Use player `HasBall` as the primary possession indicator.

---

# 61. Recent Auto GK commits

## `d57ea2a`

Made overhead detection more reliable:

- larger overhead radius;
- longer prediction horizon;
- smaller prediction sampling interval;
- descending-ball detection;
- additional high-ball safety test;
- shorter jump cooldown.

## `fa97194`

Increased forward positioning based on shooter angle.

This was later superseded conceptually by the physical goal-line positioning update.

## `945c7a4`

Changed opponent positioning to move along the goal-to-shooter direction.

This exposed the need to use the actual interception geometry rather than relying on the Goal model pivot.

## `64e13ff`

Current opponent-positioning implementation.

Changes:

- uses `InterceptionHitbox.CFrame` when available;
- calculates the real goal-to-shooter direction;
- places the GK along that direction;
- uses a 10–17 stud forward positioning range;
- prevents the target from going beyond the attacker.

---

# 62. Current tuning philosophy

There are three separate defensive dimensions:

## Lateral coverage

How far left/right the GK can move.

Current player-position lateral clamp from the earlier implementation:

```
-13 to +13
```

## Forward angle-closing

How far the GK steps toward the shooter.

Current opponent target:

```
10 to 17 studs from the interception center
```

with attacker-distance protection.

## Vertical reaction

How early the GK detects a high football and jumps.

Current overhead detection:

- 1.5–10 studs above GK;
- up to 9 studs horizontal distance;
- prediction horizon up to 0.8 seconds.

These should be tuned independently.

Changing one should not be assumed to fix failures belonging to another.

---

# 63. Future improvements

The current system is still heuristic.

The next major improvement should be **actual goal-plane shot prediction**.

Instead of asking only:

> Where is the attacker?

the bot should calculate:

> Where will the football cross the own goal's interception plane?

The ideal future flow is:

```
attacker possession
      |
      v
estimate likely shot direction
      |
      v
predict football trajectory
      |
      v
calculate intersection with InterceptionHitbox
      |
      v
calculate GK travel time
      |
      +--> reachable on ground?
      |        |
      |        +--> MoveTo interception point
      |
      +--> reachable vertically?
               |
               +--> Jump + Leap
```

This would be more reliable than purely angle-based positioning.

The exact shot direction should preferably come from the game's actual released football velocity when the ball has already been kicked.

For a player still charging a shot, attacker position and goal geometry remain useful predictive signals.

---

# 64. Rule for future edits

Before modifying Auto GK behavior:

1. Fetch the current `Script.lua`.
2. Fetch the current `Info.md` if the change introduces new game knowledge.
3. Identify whether the problem is:
   - threat selection;
   - positioning;
   - trajectory prediction;
   - jump timing;
   - dive timing;
   - Leap direction;
   - movement execution;
   - camera behavior.
4. Change only the relevant subsystem.
5. Update `Info.md` with the new confirmed behavior.
6. Commit both changes to GitHub.
7. Record the commit in this change log.
8. Never overwrite confirmed game facts with guesses.

The repository itself is the persistent source of project knowledge so future sessions do not need to reconstruct the entire investigation.
