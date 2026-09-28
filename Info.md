# AutoGK_FSS — Knowledge

This file contains the known game mechanics and reverse-engineered APIs used by the Auto GK.

## Character / movement

- The bot controls the existing LocalPlayer character. It does not create a new character.
- Normal movement can use:
  `Humanoid:MoveTo(position)`.
- Sprinting is handled by the game's MovementController:
  `Knit.GetController("MovementController"):SetSprintingControlState(true)`.
- Sprint movement speed is approximately 27.
- The goalkeeper can move freely inside the goalkeeper area.
- Jump:
  `Character.Humanoid:ChangeState(Enum.HumanoidStateType.Jumping)`.

## Leap / goalkeeper dive

Manager:
`Players.LocalPlayer.PlayerScripts.Client.Controllers.Actions.Managers.Leap`

Use the existing manager directly:

```lua
local Leap = require(
    Players.LocalPlayer.PlayerScripts.Client.Controllers.Actions.Managers.Leap
)

Leap.Activate("Left")
Leap.Activate("Right")
```

Important:
- Left/right leap are the primary goalkeeper dive actions.
- The Leap manager itself handles `LeapPosition` and `LeapOrientation`.
- The bot should not manually recreate the leap physics.
- Forward leap can be attempted with `Leap.Activate()`.
- Passing a `"Forward"` argument does not work.
- The game considers Leap a goalkeeper action when the player is a goalie and does not have the ball.
- Leap has its own cooldown.
- The user describes GK tackling as effectively the leap/dive mechanic.

## ActionController

The game's ActionController is:

```lua
local Knit = require(ReplicatedStorage.Packages.Knit)
local ActionController = Knit.GetController("ActionController")
```

It exposes:
- `RequestAction`
- `PerformAction`
- `StopAction`
- `IsOnCooldown`
- `GetBindings`
- `GetKeybind`
- `GetConfiguration`

For this project, use the Leap manager directly rather than routing the dive through ActionController.

## Football discovery

Active footballs are found in:

`workspace.Misc`

A football:
- is a BasePart
- has a name beginning with `"Football "`
- has an `Enabled` attribute
- active footballs have `Enabled == true`

Useful football attributes observed:
- `Enabled`
- `State`
- `NetworkOwner`
- `ReleasePosition`
- `ReleaseVelocity`
- `ReleaseId`
- `BlockBallPickUpTill`

Known football states:
- `Possessed`
- `Released`

There may be additional states, but they have not been confirmed.

Football velocity:
- `AssemblyLinearVelocity` reflects the actual ball velocity and should be used for live trajectory prediction.
- The game also exposes `ReleaseVelocity` on released footballs.

## Ball ownership / possession

For deciding which ball matters, check players before checking football physics.

Players can expose:
- `HasBall`
- `IsOnPitch`
- `TeamPosition`
- `IsHomeOrAway`

The important positions include:
- `CF`
- `LF`
- `RF`
- `CM`
- `LB`
- `RB`
- `GK`

Preferred selection logic:
1. Find on-pitch players.
2. Find opponents with `HasBall == true`.
3. Associate the active football closest to the possessing player.
4. Use the football's live velocity for threat prediction.
5. If nobody possesses a ball, fall back to active released footballs.

Do not use NetworkOwner as the primary possession test.

## Football physics defaults

From `ReplicatedStorage.Shared.Defaults.Football`:

- Gravity: `55`
- VelocityDampening: `0.755`
- MaximumFootballs: `30`
- HighShotPowerThreshold: `67.5`
- HighShotPowerThresholdExtension: `53`

Velocity ranges:
- Kick: `32.5–138.5`
- Pass: `34–120`
- Throw: `32.5–110`
- Header: `85–130`
- LowVolley: `40–133`
- BicycleKick: `110`

Charge times:
- PowerShot: `0.4`
- Pass: `0.6`
- Header: `0.5`
- LowVolley: `0.45`

The exact application of velocity dampening to a long-term trajectory has not been confirmed, so the first bot implementation predicts from the live `AssemblyLinearVelocity` and game gravity.

## Shooting / throwing

Primary action uses PrepareShot and is used for kick/cross.

Secondary action:
- Normal player: Pass
- Goalkeeper with ball: Throw

The goalkeeper therefore uses the game's normal possession/throw mechanics instead of a custom throw implementation.

PrepareShot exposes:
- `PrepareShot.GetPayload()`
- `PrepareShot.Activate("Kick", ...)`
- `PrepareShot.Activate("Release", id)`
- `PrepareShot.GetPreviousReleaseVelocity()`
- `PrepareShot.GetPreviousReleaseEndPoint()`

Camera direction is used by PrepareShot and is flattened to the X/Z plane.

## Goal / goalkeeper regions

The LocalPlayer has:

`IsHomeOrAway == "Home"` or `"Away"`

Own goalkeeper region:
`workspace.Stadium.Teams[side].Barriers.Goalkeeper`

Own goal:
`workspace.Stadium.Teams[side].Goal`

Goal contains:
- `Hitbox`
- `InterceptionHitbox`
- `Collision`

The bot should use `InterceptionHitbox` for interception prediction rather than the smaller actual goal hitbox.

### Home goal

Hitbox:
- Size: `31.3272476, 11.2778091, 8.3391724`
- Position: approximately `86.4281, -1.8036, -420.1586`

InterceptionHitbox:
- Size: `33.1928329, 11.7065935, 10.0944967`
- Position: approximately `86.3432, -1.5893, -419.2809`

### Away goal

Hitbox:
- Size: `31.3272476, 11.2778091, 8.2894745`
- Position: approximately `86.2024, -1.7057, -47.7539`

InterceptionHitbox:
- Size: `33.1930008, 11.7070007, 10.0939999`
- Position: approximately `86.3024, -1.7057, -48.3733`

The goals face opposite directions, so the bot should derive direction from the goal CFrame rather than hard-code a Z direction.

## Character hitbox

Normal player approximate hitbox:
`4.521, 5.73, 2.398`

Goalkeeper approximate hitbox:
`4.521, 5.73, 2.648`

A GK gets the ball by physically touching it. There is no separate confirmed "save" action.

Leaping is primarily a movement/boost mechanism that lets the GK reach balls more like an actual goalkeeper.

## GK possession

- Touching the football gives the GK possession.
- A goalkeeper can hold the ball for roughly 7 seconds before the game forces the ball out.

## Tackling / evading

- Players have tackling.
- Goalkeepers can tackle/dive.
- A normal player cannot tackle the GK in the same way.
- Other players may expose an `Evading` attribute.

## Known architecture

Relevant controllers include:
- Movement
- ActionController
- Match
- Input
- Animation
- FootballLocators
- AgentLocators
- Player
- Camera
- Skills
- Stamina

Relevant paths:
- `Players.LocalPlayer.PlayerScripts.Client.Controllers.Actions`
- `Players.LocalPlayer.PlayerScripts.Client.Controllers.Actions.Managers.Leap`
- `ReplicatedStorage.Shared.Defaults.Football`
- `workspace.Stadium.Teams.Home.Goal`
- `workspace.Stadium.Teams.Away.Goal`

## Bot strategy

The intended first implementation is:

1. Confirm the local player is a goalkeeper.
2. Find the own goal and interception box.
3. Find opponent players on the pitch.
4. Prioritize opponents with `HasBall == true`.
5. Find the active football associated with the possessor.
6. Predict whether the live football trajectory enters the own goal's interception box.
7. Move the GK toward the predicted interception point.
8. If the ball is close enough and the interception is lateral, use:
   - `Leap.Activate("Left")`
   - `Leap.Activate("Right")`
9. If the ball is already reachable without diving, allow physical contact to produce possession.
10. If nobody possesses the ball, inspect active released footballs as a fallback.
11. Once the GK gets the ball, the game's normal possession and throw systems remain responsible for the ball.

Unconfirmed behavior should not be treated as fact until another decompile/test confirms it.
