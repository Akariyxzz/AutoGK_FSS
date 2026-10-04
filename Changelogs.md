# Changelog

## 2026-10-04 — Clean WebSocket foundation

- Completely reset `Script.lua` and `Script.py`.
- Added a localhost WebSocket connection from Roblox to Python.
- Added a Windows Python WebSocket server on `127.0.0.1:8765`.
- Added raw JSONL storage in `data/transitions.jsonl`.
- Added a minimal JSON state/action protocol.
- The Roblox state collector and learned policy are intentionally not implemented yet.

## 2026-10-04 — Local player telemetry

- Added local player position, velocity, and team observation to `Script.lua`.
- Roblox now sends state snapshots every 0.1 seconds.
- Python prints and stores the received player observations.
