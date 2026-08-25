"""Shared stdlib-only helpers for bake-off generators. Safe to import under any
engine's `uv run` env (no third-party deps here)."""
from __future__ import annotations

import json
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parent.parent  # tools/tts-bakeoff -> tools -> repo root
OUT = HERE / "out"


def load_lines() -> dict:
	return json.loads((HERE / "lines.json").read_text())


def ref_wav() -> Path:
	return REPO / load_lines()["reference_wav"]


def engine_dir(engine: str) -> Path:
	d = OUT / engine
	d.mkdir(parents=True, exist_ok=True)
	return d


def out_name(line: dict) -> str:
	"""Stable per-line filename, e.g. scott-cover-panic.wav"""
	return f"{line['id']}-{line['mood']}.wav"


class Timer:
	def __enter__(self):
		self._t = time.time()
		return self

	def __exit__(self, *a):
		self.seconds = time.time() - self._t


def write_meta(engine: str, *, device: str, model: str, entries: list[dict], note: str = "") -> None:
	"""entries: [{id, mood, file, text, gen_seconds, ok, error?}]"""
	meta = {"engine": engine, "device": device, "model": model, "note": note, "entries": entries}
	(engine_dir(engine) / "meta.json").write_text(json.dumps(meta, indent=2))
	ok = sum(1 for e in entries if e.get("ok"))
	print(f"[{engine}] {ok}/{len(entries)} lines, device={device}")
