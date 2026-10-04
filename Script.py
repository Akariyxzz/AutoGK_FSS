import json
import time
from pathlib import Path

from websocket_server import WebsocketServer

HOST = "127.0.0.1"
PORT = 8765

DATA_DIR = Path(__file__).resolve().parent / "data"
DATA_DIR.mkdir(exist_ok=True)
DATA_FILE = DATA_DIR / "transitions.jsonl"

server = None


def send_json(client, value):
    server.send_message(client, json.dumps(value, separators=(",", ":")))


def on_connect(client, _server):
    print(f"[WS] connected: {client['id']}")
    send_json(client, {"type": "hello", "protocol": 1})


def on_disconnect(client, _server):
    print(f"[WS] disconnected: {client['id']}")


def on_message(client, _server, message):
    try:
        packet = json.loads(message)
    except json.JSONDecodeError:
        print("[WS] invalid JSON")
        return

    if packet.get("type") == "hello":
        print(f"[WS] protocol hello from client {client['id']}")
        return

    if packet.get("type") != "state":
        return

    record = {
        "timestamp": packet.get("timestamp", time.time()),
        "self": packet.get("self"),
        "players": packet.get("players", []),
    }

    with DATA_FILE.open("a", encoding="utf-8") as file:
        file.write(json.dumps(record, separators=(",", ":")) + "\n")

    print(
        f"[STATE] players={len(record['players'])} "
        f"self={record['self']}"
    )

    send_json(client, {
        "type": "action",
        "action": "HOLD",
    })


server = WebsocketServer(host=HOST, port=PORT, loglevel=0)
server.set_fn_new_client(on_connect)
server.set_fn_client_left(on_disconnect)
server.set_fn_message_received(on_message)

print(f"AutoGK_FSS listening on ws://{HOST}:{PORT}")
print(f"Data: {DATA_FILE}")
print("Press Ctrl+C to stop.")

try:
    server.run_forever()
except KeyboardInterrupt:
    print("\nStopped.")
