# Changelogs

## Unreleased

### Added
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
