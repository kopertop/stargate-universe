#!/usr/bin/env python3
"""ElevenLabs music-stem baker. Generates the composable SGU loop library — isolated,
seamlessly-looping textures (drones, pads, solo strings/piano, pulses) plus short one-shot
stings — that the runtime MusicDirector (scripts/music_director.gd) layers into moods.

Why the SFX API for stems: text_to_sound_effects.convert(loop=True) makes a SINGLE seamless
looping texture you can stack — exactly one stem. music.compose() makes a fully-mixed track
you can't pull stems back out of, so it's reserved for `kind: bed` standalone pieces.

Reads a job (tools/music-bake/jobs/<name>.json): { out_dir, stems: [<id> | {id, ...overrides}] }.
Stem definitions live in palette.py; jobs just SELECT ids. For each stem: call the right API,
write a temp mp3, ffmpeg-transcode to <out_dir>/<id>.ogg (project loop convention), record a
bake_report. Loop POINTS aren't baked in — the .ogg loops because MusicDirector sets
stream.loop = true at load (robust across Godot OGG-import defaults).

Run via tools/music-bake/run.sh (handles uv env + ffmpeg + godot --import). Direct:
  ELEVENLABS_API_KEY=... uv run --python-preference only-managed --with elevenlabs \\
    python bake.py [job_name]      # default job: sgu_sample
"""
from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
import time
from pathlib import Path

import palette

HERE = Path(__file__).resolve().parent
REPO = HERE.parent.parent  # tools/music-bake -> tools -> repo
# Request a high-bitrate mp3 from the API, then transcode to ogg for the game.
API_OUTPUT_FORMAT = "mp3_44100_128"
SFX_MODEL = "eleven_text_to_sound_v2"  # loop=True requires the v2 model


def _resolve_stems(job: dict) -> list[dict]:
	"""Expand a job's stem-selection list into full palette definitions (+ overrides)."""
	out: list[dict] = []
	for entry in job["stems"]:
		if isinstance(entry, str):
			out.append(palette.resolve(entry))
		else:
			stem_id = entry["id"]
			overrides = {k: v for k, v in entry.items() if k != "id"}
			out.append(palette.resolve(stem_id, overrides))
	return out


def _transcode_to_ogg(raw_mp3: Path, dst_ogg: Path) -> bool:
	"""mp3 -> Ogg Vorbis. Returns True on success.

	Prefers libvorbis (best quality) but falls back to ffmpeg's built-in `vorbis`
	encoder (needs `-strict -2`, it's marked experimental) so the tool works on a
	minimal Homebrew ffmpeg that wasn't built with libvorbis. Godot 4 imports either
	as AudioStreamOggVorbis. Quality ~q6 VBR — fine for ambient music beds.
	"""
	dst_ogg.parent.mkdir(parents=True, exist_ok=True)
	attempts = (
		["-c:a", "libvorbis", "-q:a", "5"],
		["-c:a", "vorbis", "-strict", "-2", "-q:a", "6"],
	)
	last_err = ""
	for codec_args in attempts:
		proc = subprocess.run(
			["ffmpeg", "-y", "-loglevel", "error", "-i", str(raw_mp3), *codec_args, str(dst_ogg)],
			capture_output=True, text=True,
		)
		if proc.returncode == 0 and dst_ogg.is_file():
			return True
		last_err = proc.stderr.strip()
	print(f"[bake] ffmpeg FAIL: {last_err}", file=sys.stderr)
	return False


def _generate(client, stem: dict, raw_mp3: Path) -> None:
	"""Call the right ElevenLabs API for this stem's kind and stream bytes to raw_mp3."""
	kind = stem["kind"]
	if kind == "bed":
		# Fully-mixed standalone piece (not a layerable stem).
		audio = client.music.compose(
			prompt=stem["prompt"],
			music_length_ms=int(stem["duration_s"] * 1000),
		)
	else:
		# loop -> seamless texture; oneshot -> short non-looping accent.
		audio = client.text_to_sound_effects.convert(
			text=stem["prompt"],
			model_id=SFX_MODEL,
			duration_seconds=float(stem["duration_s"]),
			prompt_influence=float(stem["prompt_influence"]),
			loop=(kind == "loop"),
			output_format=API_OUTPUT_FORMAT,
		)
	with open(raw_mp3, "wb") as f:
		for chunk in audio:
			f.write(chunk)


def main() -> int:
	job_name = sys.argv[1] if len(sys.argv) > 1 else "sgu_sample"
	job_path = HERE / "jobs" / f"{job_name}.json"
	if not job_path.is_file():
		print(f"ERROR: no job file {job_path}", file=sys.stderr)
		return 1
	job = json.loads(job_path.read_text())

	# Validate every stem id up front so a typo fails before any API spend.
	try:
		stems = _resolve_stems(job)
	except KeyError as e:
		print(f"ERROR: {e}", file=sys.stderr)
		return 1

	out_dir = REPO / job.get("out_dir", "sounds/music/loops")
	out_dir.mkdir(parents=True, exist_ok=True)
	print(f"[bake] job '{job_name}': {len(stems)} stems -> {out_dir.relative_to(REPO)}")

	if not os.environ.get("ELEVENLABS_API_KEY"):
		print("ERROR: ELEVENLABS_API_KEY not set — required for ElevenLabs generation.",
		      file=sys.stderr)
		return 1

	from elevenlabs import ElevenLabs
	client = ElevenLabs()

	report = []
	tmp = Path(tempfile.mkdtemp(prefix="music-bake-"))
	for stem in stems:
		dst = out_dir / f"{stem['id']}.ogg"
		rec = {"id": stem["id"], "layer": stem["layer"], "kind": stem["kind"],
		       "duration_s": stem["duration_s"], "prompt": stem["prompt"], "ok": False}
		try:
			t0 = time.time()
			raw = tmp / f"{stem['id']}.mp3"
			_generate(client, stem, raw)
			rec["ok"] = _transcode_to_ogg(raw, dst)
			rec["seconds"] = round(time.time() - t0, 1)
			status = "ok" if rec["ok"] else "TRANSCODE-FAIL"
			print(f"[bake] {stem['id']:<20} {stem['layer']:<8} {stem['kind']:<8} "
			      f"{rec.get('seconds')}s  {status}")
		except Exception as e:  # noqa: BLE001
			rec["error"] = str(e)
			print(f"[bake] FAIL {stem['id']}: {e}", file=sys.stderr)
		report.append(rec)

	(HERE / f"bake_report_{job_name}.json").write_text(json.dumps(report, indent=2))
	ok = sum(1 for r in report if r["ok"])
	print(f"[bake] done: {ok}/{len(report)} ok -> {out_dir.relative_to(REPO)}")
	print("[bake] NEXT: run `godot --headless --import` so the OGGs get .import sidecars "
	      "(else AudioStream load() returns null in-game), then `python build_index.py` to audition.")
	return 0 if ok == len(report) else 2


if __name__ == "__main__":
	raise SystemExit(main())
