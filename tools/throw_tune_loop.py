#!/usr/bin/env python3
"""Karpathy-style overnight tuner for the gate-throw projectile arc.

Loop: perturb one THROW_* constant in scripts/gate_room.gd -> render the
tests/shots/ragdoll_tune.gd harness -> read its `score=` -> if the score is
strictly better, COMMIT the change; otherwise REVERT it (git checkout). Hill-climb
across all params for many passes, decaying the step, with occasional random-ish
restarts (deterministic, seeded by pass index) so it keeps exploring overnight.

The harness is deterministic (kinematic projectile, no RNG), so a given constant
vector always yields the same score — the climb is stable and reproducible.

Run (from repo root), backgrounded:
    python3 tools/throw_tune_loop.py >> screenshots/loop/throw_tune.log 2>&1 &
"""
import os
import re
import subprocess
import sys
import time
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
GD = "/Applications/Godot.app/Contents/MacOS/Godot"
GATE = REPO / "scripts" / "gate_room.gd"
HARNESS = "res://tests/shots/ragdoll_tune.gd"
USERDATA = Path.home() / "Library/Application Support/Godot/app_userdata/Stargate Universe"
LOOPDIR = REPO / "screenshots" / "loop"
LOOPDIR.mkdir(parents=True, exist_ok=True)

# name -> [min, max, initial_step]. Only the crew-throw arc params (the harness
# throws a crew body); crate params don't affect its score so they're left alone.
PARAMS = {
    "THROW_FLIGHT_TIME": [0.90, 2.10, 0.10],
    "THROW_TUMBLE_BASE": [2.0, 9.0, 0.5],
    "THROW_TUMBLE_DIST": [0.0, 1.0, 0.10],
}
MAX_EVALS = int(os.environ.get("TUNE_MAX_EVALS", "600"))


def log(msg: str) -> None:
    print(f"[{time.strftime('%H:%M:%S')}] {msg}", flush=True)


def read_param(name: str) -> float:
    txt = GATE.read_text()
    m = re.search(rf"const {name}: float = ([0-9.]+)", txt)
    if not m:
        raise SystemExit(f"param {name} not found in {GATE}")
    return float(m.group(1))


def write_param(name: str, value: float) -> None:
    txt = GATE.read_text()
    new = re.sub(rf"(const {name}: float = )[0-9.]+", rf"\g<1>{value:.3f}", txt, count=1)
    GATE.write_text(new)


def revert() -> None:
    subprocess.run(["git", "-C", str(REPO), "checkout", "--", "scripts/gate_room.gd"], check=False)


def commit(msg: str) -> None:
    subprocess.run(["git", "-C", str(REPO), "add", "scripts/gate_room.gd"], check=False)
    subprocess.run(["git", "-C", str(REPO), "commit", "-q", "-m", msg], check=False)


def run_score(save_shot: bool = False) -> float:
    args = [GD, "--quit-after", "400", "-s", HARNESS, "++", "out=user://ragdoll",
            "shot=1" if save_shot else "shot=0"]
    try:
        out = subprocess.run(args, cwd=str(REPO), capture_output=True, text=True, timeout=120).stdout
    except subprocess.TimeoutExpired:
        return -999.0
    m = re.search(r"score=(-?[0-9.]+)", out)
    score = float(m.group(1)) if m else -999.0
    # surface the full metrics line for the log
    ml = re.search(r"METRICS .*", out)
    if ml:
        log("   " + ml.group(0))
    return score


def save_best_shot(tag: str) -> None:
    run_score(save_shot=True)
    for fn in ("ragdoll_flight.png", "ragdoll_settled.png"):
        src = USERDATA / fn
        if src.exists():
            (LOOPDIR / f"best_{tag}_{fn}").write_bytes(src.read_bytes())


def main() -> int:
    if not Path(GD).exists():
        raise SystemExit(f"Godot not found at {GD}")
    log(f"=== throw tuner start (max {MAX_EVALS} evals) ===")
    best = run_score()
    log(f"baseline score={best:.3f}  params=" +
        ", ".join(f"{k}={read_param(k):.3f}" for k in PARAMS))
    evals = 1
    steps = {k: v[2] for k, v in PARAMS.items()}
    passes = 0
    while evals < MAX_EVALS:
        improved_this_pass = False
        for name, (lo, hi, _) in PARAMS.items():
            if evals >= MAX_EVALS:
                break
            cur = read_param(name)
            step = steps[name]
            for delta in (step, -step):
                cand = round(min(hi, max(lo, cur + delta)), 3)
                if abs(cand - cur) < 1e-6:
                    continue
                write_param(name, cand)
                s = run_score()
                evals += 1
                if s > best + 1e-3:
                    best = s
                    cur = cand
                    improved_this_pass = True
                    commit(f"tune(throw): {name}={cand:.3f} score={s:.2f} (auto Karpathy loop)")
                    log(f"  ✔ COMMIT {name}={cand:.3f} score={s:.3f}  (eval {evals})")
                    save_best_shot("latest")
                    break  # take the improving direction, move to next param
                else:
                    revert()
                    log(f"  ✗ revert {name}={cand:.3f} score={s:.3f} (best {best:.3f})")
        passes += 1
        if not improved_this_pass:
            # Converged at this resolution — halve every step and keep refining.
            new_steps = {k: round(v / 2.0, 4) for k, v in steps.items()}
            if all(v < 0.02 for v in new_steps.values()):
                log(f"=== converged after {evals} evals, pass {passes}; best={best:.3f} ===")
                # Random-ish restart to keep exploring overnight (seeded by pass).
                steps = {k: v[2] for k, v in PARAMS.items()}
                seed = passes
                for k in PARAMS:
                    lo, hi, _ = PARAMS[k]
                    seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF
                    jitter = (seed / 0x7FFFFFFF) * (hi - lo) * 0.25 - (hi - lo) * 0.125
                    write_param(k, round(min(hi, max(lo, read_param(k) + jitter)), 3))
                s = run_score(); evals += 1
                if s > best + 1e-3:
                    best = s; commit(f"tune(throw): restart improved score={s:.2f}")
                    log(f"  ✔ restart COMMIT score={s:.3f}")
                else:
                    revert()
                    log(f"  restart probe score={s:.3f} (kept best {best:.3f})")
            else:
                steps = new_steps
                log(f"  -- step decay -> {steps}")
    log(f"=== tuner done: {evals} evals, best score={best:.3f} ===")
    log("final params: " + ", ".join(f"{k}={read_param(k):.3f}" for k in PARAMS))
    return 0


if __name__ == "__main__":
    sys.exit(main())
