# Changelog

## 2026-10-04 — Clean WebSocket foundation

- Completely reset `Script.lua` and `Script.py`.
- Added a localhost WebSocket connection from Roblox to Python.
- Added a Windows Python WebSocket server on `127.0.0.1:8765`.
- Added raw JSONL storage in `data/transitions.jsonl`.
- Added a minimal JSON state/action protocol.
- The Roblox state collector and learned policy are intentionally not implemented yet.
