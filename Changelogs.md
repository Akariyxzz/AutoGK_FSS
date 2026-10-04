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

- Recreated `Script.lua` as an exact baseline copy of `Old.lua`; future implementation work will be built from this baseline.

- Rebuilt `Script.lua` from the `Old.lua` baseline with goalkeeper behavior: goal-local positioning, camera-view tracking, threat/ball prioritization, live trajectory checks, slow uncontested-ball recovery, controlled depth, and debug state. Camera tracking is read-only and no longer overwrites `CurrentCamera.CFrame`.

- Fixed the Old.lua-based rebuild: corrected the predictBallPosition local-scope bug, made dangerous-shot detection use actual goal-plane crossing time, fixed overhead-jump cooldown logic, prioritized pending apex dives correctly, removed unused threat-ball selection code, and initialized persistent debug state before action handlers use it.

- Added initial AI telemetry to `Script.lua`: player/ball/self state snapshots, controlled-ball substitution when a player owns the ball, camera/goal context, current action labels, and resilient `DisplayPointsGain` reward capture across `__GamemodeComm` recreation.
- Added `Script.py` as the first training-side baseline: JSONL loading, observation discretization, action/reward statistics, and a tabular policy export. This is intentionally a data/validation stage before a full RL algorithm.
