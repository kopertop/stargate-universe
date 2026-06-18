#!/usr/bin/env python3
"""BASELINE engine: the project's existing ZipVoice/LuxTTS sidecar (:8765).

ZipVoice has NO emotion control — the panic and calm variants come out identically
(same `scott` voice embedding, tags stripped). That's the point: this is the gap the
bake-off is trying to close. Requires the sidecar to be running:

    tools/tts-onnx-poc/run_server.sh   # or however it's normally started

Stdlib only — no `uv run` deps needed.
"""
from __future__ import annotations

import sys
import urllib.error
import urllib.parse
import urllib.request

import common
import tags

SERVER = "http://127.0.0.1:8765"


def main() -> int:
	data = common.load_lines()
	voice = data["voice"]
	out = common.engine_dir("zipvoice")
	entries: list[dict] = []

	# Probe health so a down sidecar fails fast & clearly (skipped, not fatal).
	try:
		with urllib.request.urlopen(f"{SERVER}/health", timeout=5) as r:
			import json
			voices = json.loads(r.read()).get("voices", [])
		if voice not in voices:
			print(f"[zipvoice] voice '{voice}' not enrolled (have: {voices})", file=sys.stderr)
	except Exception as e:  # noqa: BLE001
		print(f"[zipvoice] sidecar not reachable at {SERVER}: {e}", file=sys.stderr)
		common.write_meta("zipvoice", device="n/a", model="ZipVoice/LuxTTS (sidecar)",
		                  entries=[], note="sidecar offline — skipped")
		return 0  # non-fatal: orchestrator continues

	for line in data["lines"]:
		text = tags.zipvoice(line["text"])  # tags stripped — no emotion
		url = f"{SERVER}/synthesize?voice={urllib.parse.quote(voice)}&text={urllib.parse.quote(text)}&seed=7"
		fname = common.out_name(line)
		e = {"id": line["id"], "mood": line["mood"], "file": fname, "text": text, "ok": False}
		try:
			with common.Timer() as t:
				with urllib.request.urlopen(url, timeout=60) as r:
					wav = r.read()
			(out / fname).write_bytes(wav)
			e["ok"] = True
			e["gen_seconds"] = round(t.seconds, 2)
		except Exception as ex:  # noqa: BLE001
			e["error"] = str(ex)
		entries.append(e)

	common.write_meta("zipvoice", device="sidecar", model="ZipVoice/LuxTTS",
	                  entries=entries, note="No emotion control — panic==calm by design.")
	return 0


if __name__ == "__main__":
	raise SystemExit(main())
