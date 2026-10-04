# Auto GK Behavior

This document defines the intended goalkeeper behavior for Auto GK. It describes decision-making and priorities rather than the game's low-level APIs or exact physics. Verified game mechanics belong in `Info.md`.

## 1. Core principle

The goalkeeper should protect the goal first, not continuously chase the ball or attacker.

Default priorities:

1. Maintain useful goal positioning.
2. Read the attacker's position and available shooting options.
3. Detect an actual threatening shot/trajectory.
4. Predict where the ball will reach the goal.
5. Intercept with the smallest necessary movement.
6. Avoid unnecessary dives and rushes.
7. After gaining possession, transition into a clearance/counterattack behavior.

## 2. Goal positioning

The default goalkeeper position is around the center of the goal and slightly forward of the goal line.

The goalkeeper should be able to cover both corners without being dragged too far toward the attacker.

Positioning should use the goal's CFrame/local space rather than assuming Home and Away goals face the same direction.

The goalkeeper may move laterally in response to a threat, but normal ball tracking must not continuously pull the goalkeeper away from the goal.

## 3. Attacker behavior

When an opponent has possession, consider:

- distance from the goal;
- lateral position relative to the goal;
- movement direction;
- current ball possession;
- whether the attacker is approaching a dangerous shooting area;
- whether the attacker appears to have limited shooting options.

Do not assume the attacker's current facing direction is the shot direction. Once the ball is released, live ball velocity is the stronger signal.

## 4. Dribbling and baiting

A nearby attacker does not automatically justify a tackle, rush, or dive.

The goalkeeper should generally hold a safe position while the attacker is dribbling and avoid being baited into leaving the goal.

A controlled forward movement may be used as a fake rush, followed by a retreat toward the goal when the attacker has not committed.

Fake rushing is secondary behavior. It must never compromise basic goal coverage.

## 5. Rushing / one-on-one situations

Rushing is appropriate when:

- the attacker is sufficiently close to the goal;
- the goalkeeper can reach a useful interception position quickly;
- the attacker has limited safe shooting options;
- rushing does not expose an obvious open side of the goal.

Rushing is not appropriate merely because the attacker is nearby.

If the attacker is still far enough away to shoot over or around the goalkeeper, prefer positioning and prediction.

## 6. Shot detection

Once a shot is released, defensive behavior should transition away from following the attacker and toward the football.

The goalkeeper should briefly avoid unnecessary repositioning immediately after release while determining whether the trajectory threatens the goal.

A threatening shot should be evaluated using:

- live position;
- live velocity;
- predicted intersection with the goal/interception area;
- predicted lateral location;
- predicted height;
- time to interception.

## 7. Trajectory prediction

Prediction is preferred over pure reaction.

The bot should estimate where the football will be when it reaches the goal plane/interception area.

A predicted trajectory that does not threaten the goal should not cause a dive.

The current ball velocity should be preferred over stored release velocity when available.

Prediction should remain conservative because the exact game's damping/collision behavior is not completely reverse engineered.

## 8. Lateral interception

For a dangerous trajectory:

- predicted left-side interception -> prepare for left;
- predicted right-side interception -> prepare for right;
- predicted center interception -> remain centered unless another action is necessary.

The goalkeeper should move early enough to improve interception odds, but should not instantly commit to a side based only on the attacker's position.

Leap direction is relative to the goalkeeper's orientation, so the goalkeeper should have a stable/appropriate facing before selecting left/right.

## 9. Vertical interception

Height matters.

Use different reactions for:

- low trajectory -> ground positioning/interception;
- medium trajectory -> jump and potentially early leap;
- high trajectory -> jump with timing adjusted to the predicted height.

Do not always wait for the exact apex. An earlier leap can be necessary for a ball that would otherwise pass over or beside the goalkeeper.

## 10. Dive timing

A jump followed by a lateral leap is a timing problem.

The bot should consider:

- predicted ball height;
- horizontal distance;
- goalkeeper vertical velocity;
- elapsed time since jump;
- whether the ball is still moving toward the interception area.

A fixed "always leap at apex" rule is undesirable.

The existing Leap manager should be used rather than manually reproducing leap physics.

## 11. Unnecessary-dive prevention

Do not dive when:

- the ball is predicted to miss the goal/interception area;
- the goalkeeper is already positioned to intercept without a leap;
- the attacker has not actually released a dangerous ball;
- the ball is moving away from the goal;
- a teammate or existing positioning already provides adequate coverage.

A missed dive can be worse than holding position.

## 12. Loose balls

When nobody has possession:

- inspect active footballs;
- prioritize balls that can actually threaten the own goal;
- use trajectory and distance rather than simply choosing the closest ball;
- do not chase distant harmless balls;
- do not let a dead/fallen football pull the goalkeeper far from the goal.

Nearby overhead balls may justify a jump if their predicted path enters the goalkeeper's reachable area.

## 13. Overhead balls

For a ball passing above the goalkeeper:

1. Predict its near-future height and horizontal position.
2. Determine whether it is within a reachable overhead region.
3. Jump if appropriate.
4. Select lateral leap direction from the predicted local position.
5. Adjust leap timing based on the ball's height instead of always waiting for the jump apex.

## 14. Goal coverage

Goal coverage has priority over attacker tracking.

The goalkeeper should remain within a controlled depth range in front of the goal.

Lateral movement can cover the goal mouth, but depth should be clamped so an attacker cannot drag the goalkeeper unnecessarily far forward.

## 15. Possession / post-save behavior

When the goalkeeper has the ball:

- stop defensive interception movement;
- do not continue chasing the previous threat;
- prepare a clearance/counterattack;
- prefer useful forward distribution, generally toward the central field when that is the intended behavior.

The exact action/API used for throwing, passing, or shooting belongs in `Info.md` and the implementation.

## 16. Team coverage

A teammate may cover part of the goal.

If reliable teammate-position information is available, future versions may use it to identify covered and uncovered areas.

This is optional and should not be required for the basic Auto GK.

## 17. Decision priority

When multiple behaviors are possible, use this priority:

1. Player validity / GK role
2. Own-ball safety
3. Immediate dangerous trajectory
4. Reachable interception
5. Goal coverage
6. Controlled one-on-one rush
7. Attacker tracking
8. Loose-ball positioning
9. Optional fakes / advanced behaviors

Defensive safety should win when behaviors conflict.

## 18. Known uncertainty

The following are behavioral observations rather than guaranteed game rules:

- attackers frequently target corners;
- attackers may fake or change shooting direction;
- human goalkeepers use fake rushing;
- leap timing can affect save height;
- goalkeeper touch may beat an attacker's subsequent touch in some situations;
- ping and collision timing can affect saves.

These should be treated as heuristics and tested in-game, not as hardcoded facts.

## 19. Implementation philosophy

The Auto GK should favor:

- prediction over reaction;
- positioning over chasing;
- minimal necessary movement;
- actual ball velocity over assumptions;
- goal-local coordinates over hardcoded Home/Away directions;
- game-provided movement/action controllers over recreated physics;
- measurable/debuggable decisions over opaque heuristics.

Every significant behavioral change should also be recorded in `Changelogs.md`.
