- Added camera tracking as the primary lateral positioning signal for the goalkeeper, projecting the camera's center view onto the goal plane.
# Changelogs

## Unreleased

### Added
- Improved defensive lateral positioning so the GK shades toward the attacking threat instead of staying fixed at the exact center; camera direction is used as a secondary tracking bias.
- Added camera-aware side selection for close recovery leaps.
- Added slow-ball recovery: when a loose ball is slow, within chase range, and no opponent is nearby, the GK sprints directly toward it and can leap when close.
- Added nearby-opponent protection so the GK does not blindly chase a contested loose ball.
- Expanded `Script.lua` beyond basic positioning with active football discovery, live-velocity ballistic prediction, controlled loose-ball tracking, overhead jump detection, apex lateral dives, and dangerous ground-ball dives.
- Added MovementController sprint support when repositioning.
- Kept the `L` runtime kill switch and debug diagnostics.
- Added `L` as a runtime kill switch that stops the Auto GK heartbeat logic.
- Added detailed runtime debug output for GK detection, character state, goal resolution, carrier detection, target selection, and movement.
- Fixed goal resolution to use the goal's `InterceptionHitbox`/`Hitbox` when `Goal` is a Model rather than a BasePart.
- Added the first working `Script.lua` implementation for Phase 1.
- Added goalkeeper-role detection, own-goal resolution, centered goal positioning, carrier-based lateral tracking, possession protection, and reduced redundant movement calls.
- Added `Behavior.md` as the behavioral specification for Auto GK.
- Documented goal-centered positioning, attacker analysis, controlled rushing, shot detection, trajectory prediction, lateral/vertical interception, dive timing, loose-ball handling, and post-save behavior.
- Documented the distinction between verified game mechanics in `Info.md` and behavioral heuristics in `Behavior.md`.

### Notes
- The behavioral rules are intended as implementation guidance and are not claims that every described goalkeeper technique is a hard game mechanic.
- Significant future changes to `Script.lua` should be reflected here.

- Removed the previous `Script.lua` implementation; future Auto GK development will restart from `Old.lua` as the codebase baseline.
