#!/usr/bin/env python3
"""
AutoGK_FSS trainer.

Consumes the JSONL telemetry written by Script.lua.
This first version deliberately focuses on validating/normalizing the
observation stream. It also builds a simple action/reward table that can be
used as the first policy baseline without requiring external ML packages.

Input:
    AutoGK_FSS/episodes.jsonl

Output:
    AutoGK_FSS/model.json
"""

from __future__ import annotations

import json
import math
from collections import defaultdict
from pathlib import Path

DATASET = Path("AutoGK_FSS/episodes.jsonl")
MODEL = Path("AutoGK_FSS/model.json")


def vec(value):
    if not isinstance(value, dict):
        return (0.0, 0.0, 0.0)
    return (
        float(value.get("x", 0.0)),
        float(value.get("y", 0.0)),
        float(value.get("z", 0.0)),
    )


def speed(value):
    x, y, z = vec(value)
    return math.sqrt(x * x + y * y + z * z)


def discretize(snapshot):
    """Turn the large observation into a compact state key.

    This is intentionally coarse for the first trainer. We can replace this
    with a neural policy later without changing Script.lua's observation
    format.
    """
    me = snapshot.get("self") or {}
    balls = snapshot.get("balls") or []
    players = snapshot.get("players") or []

    my_pos = vec(me.get("position"))
    my_vel = vec(me.get("velocity"))

    best_ball = None
    best_distance = float("inf")

    for ball in balls:
        pos = vec(ball.get("position"))
        distance = math.dist(my_pos, pos)
        if distance < best_distance:
            best_distance = distance
            best_ball = ball

    if best_ball:
        ball_pos = vec(best_ball.get("position"))
        ball_vel = vec(best_ball.get("velocity"))
        dx = ball_pos[0] - my_pos[0]
        dz = ball_pos[2] - my_pos[2]
        ball_speed = speed(best_ball.get("velocity"))
    else:
        dx = dz = ball_speed = 0.0
        best_distance = 999.0

    opponents = [
        p for p in players
        if p.get("team") and p.get("team") != me.get("team")
        and p.get("isOnPitch")
    ]

    nearest_opponent = min(
        (
            math.dist(my_pos, vec(p.get("position")))
            for p in opponents
        ),
        default=999.0,
    )

    def bucket(value, size):
        return int(value / size)

    return (
        me.get("team", "Unknown"),
        bucket(dx, 4.0),
        bucket(dz, 4.0),
        bucket(ball_speed, 15.0),
        bucket(best_distance, 5.0),
        bucket(nearest_opponent, 5.0),
        bucket(my_vel[0], 5.0),
        bucket(my_vel[2], 5.0),
    )


def load():
    if not DATASET.exists():
        print(f"No dataset found: {DATASET}")
        print("Run Script.lua in-game first so it can collect telemetry.")
        return []

    rows = []

    with DATASET.open("r", encoding="utf-8") as file:
        for line_number, line in enumerate(file, 1):
            try:
                row = json.loads(line)
                if isinstance(row, dict):
                    rows.append(row)
            except json.JSONDecodeError:
                print(f"Skipping invalid JSON on line {line_number}")

    return rows


def build_baseline(rows):
    """Estimate reward by state/action.

    This is not the final RL algorithm. It gives us a usable baseline and,
    more importantly, tells us whether the collected observations contain
    enough variation to train from.
    """
    totals = defaultdict(float)
    counts = defaultdict(int)

    for row in rows:
        state = discretize(row)
        action = row.get("action", "NONE")
        reward = float(row.get("reward", 0.0) or 0.0)

        key = (state, action)
        totals[key] += reward
        counts[key] += 1

    policy = {}

    states = {key[0] for key in totals}

    for state in states:
        candidates = [
            (totals[(state, action)] / counts[(state, action)], action)
            for (candidate_state, action) in totals
            if candidate_state == state
        ]
        if candidates:
            policy[repr(state)] = max(candidates)[1]

    return policy


def main():
    rows = load()

    if not rows:
        return

    reward_rows = [
        row for row in rows
        if row.get("reward")
    ]

    actions = defaultdict(int)
    rewards = defaultdict(float)

    for row in rows:
        action = row.get("action", "NONE")
        actions[action] += 1
        rewards[action] += float(row.get("reward", 0.0) or 0.0)

    policy = build_baseline(rows)

    MODEL.parent.mkdir(parents=True, exist_ok=True)
    MODEL.write_text(
        json.dumps(
            {
                "version": 1,
                "type": "tabular_baseline",
                "samples": len(rows),
                "reward_samples": len(reward_rows),
                "actions": dict(actions),
                "reward_totals": dict(rewards),
                "policy": policy,
            },
            indent=2,
        ),
        encoding="utf-8",
    )

    print(f"Loaded {len(rows):,} observations.")
    print(f"Reward observations: {len(reward_rows):,}")
    print("Actions:")
    for action, count in sorted(actions.items()):
        print(f"  {action:16} {count:,}  reward={rewards[action]:.1f}")
    print(f"Wrote baseline model: {MODEL}")


if __name__ == "__main__":
    main()
