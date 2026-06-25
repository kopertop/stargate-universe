#!/usr/bin/env python3
"""Audition page for the baked SGU music stems -> out/index.html.

Reads every bake_report_<job>.json next to this script, groups the stems by layer, and
renders inline <audio> players for each baked .ogg (sounds/music/loops/<id>.ogg). Includes a
reference section of the free CC0 Kenney Music Loops so the generated palette can be judged
against a known-quality baseline. Open out/index.html and listen before approving the full bake.

Stdlib only.
"""
from __future__ import annotations

import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parent.parent
OUT = HERE / "out"
# Baked stems live in the game tree; reference them relative to out/.
LOOPS_REL = "../../../sounds/music/loops"
KENNEY_LOOPS = Path.home() / "Downloads" / "Kenney Game Assets All-in-1 3.4.0" / "Audio" / "Music Loops" / "Loops"
LAYER_ORDER = ["bed", "pad", "melodic", "pulse", "accent"]
LAYER_BLURB = {
	"bed": "Location foundation — sustained drone under everything.",
	"pad": "Harmonic mood color, stacked over a bed.",
	"melodic": "Emotional spotlight — sparse phrases with rests.",
	"pulse": "Pace + intensity (rises with the air crisis).",
	"accent": "One-shot stings — fired, not looped.",
}


def _reports() -> list[dict]:
	recs: dict[str, dict] = {}
	for rep in sorted(HERE.glob("bake_report_*.json")):
		for r in json.loads(rep.read_text()):
			recs[r["id"]] = r  # later jobs win (full > sample)
	return list(recs.values())


def _player(rid: str, ok: bool) -> str:
	if ok:
		return f'<audio controls preload=none src="{LOOPS_REL}/{rid}.ogg"></audio>'
	return '<span class=err>✗ not baked</span>'


def _stems_html(recs: list[dict]) -> str:
	by_layer: dict[str, list[dict]] = {}
	for r in recs:
		by_layer.setdefault(r.get("layer", "?"), []).append(r)
	secs = ""
	for layer in LAYER_ORDER + [k for k in by_layer if k not in LAYER_ORDER]:
		rows_data = by_layer.get(layer)
		if not rows_data:
			continue
		rows = ""
		for r in rows_data:
			rows += (f'<tr><td class=id>{r["id"]}</td><td class=k>{r.get("kind","")}</td>'
			         f'<td class=t>{r.get("duration_s","?")}s</td>'
			         f'<td class=txt>{r.get("prompt","")}</td>'
			         f'<td>{_player(r["id"], r.get("ok"))}</td>'
			         f'<td class=t>{r.get("seconds","?")}s</td></tr>')
		secs += (f'<h2>{layer.title()} <span class=note>— {LAYER_BLURB.get(layer,"")}</span></h2>'
		         f'<table><thead><tr><th>stem</th><th>kind</th><th>dur</th><th>prompt</th>'
		         f'<th>audio</th><th>gen</th></tr></thead><tbody>{rows}</tbody></table>')
	return secs


def _kenney_html() -> str:
	if not KENNEY_LOOPS.is_dir():
		return ""
	loops = sorted(KENNEY_LOOPS.glob("*.ogg"))[:8]
	if not loops:
		return ""
	rows = ""
	for f in loops:
		rows += (f'<tr><td class=id>{f.stem}</td>'
		         f'<td><audio controls preload=none src="file://{f}"></audio></td></tr>')
	return ('<h2>Reference · Kenney Music Loops <span class=note>— free CC0 baseline to judge '
	        'fidelity/character against</span></h2>'
	        f'<table><thead><tr><th>loop</th><th>audio</th></tr></thead><tbody>{rows}</tbody></table>')


def main() -> int:
	recs = _reports()
	if not recs:
		print("No bake_report_*.json found — run bake.py first.")
		return 1
	OUT.mkdir(parents=True, exist_ok=True)
	style = """
 body{font:14px/1.55 system-ui,sans-serif;margin:24px;color:#e8e8ea;background:#16161a}
 h1{font-size:21px} h2{margin-top:32px;color:#8ab4f8;border-bottom:1px solid #333;padding-bottom:5px}
 table{border-collapse:collapse;width:100%;margin-top:8px}
 th,td{border:1px solid #2c2c34;padding:6px 9px;text-align:left;vertical-align:top}
 th{background:#23232a;position:sticky;top:0}
 td.id{font-family:ui-monospace,monospace;color:#9ad;white-space:nowrap}
 td.txt{max-width:460px;color:#cfd} td.k{color:#ffd479} .t{font-size:12px;color:#888}
 .err{color:#ff7a7a;font-weight:700} .note{color:#9a9;font-weight:400;font-size:13px}
 audio{width:240px;height:30px}"""
	ok = sum(1 for r in recs if r.get("ok"))
	html = (f"<!doctype html><meta charset=utf-8><title>SGU music stems</title><style>{style}</style>"
	        f"<h1>Stargate Universe — composable music stems</h1>"
	        f"<p class=note>{ok}/{len(recs)} stems baked. Listen per layer; each loop should hold up "
	        f"seamlessly on repeat and sit UNDER the others (it's a stem, not a finished track).</p>"
	        f"{_stems_html(recs)}{_kenney_html()}")
	(OUT / "index.html").write_text(html)
	print(f"Wrote {OUT / 'index.html'} ({ok}/{len(recs)} stems baked)")
	return 0


if __name__ == "__main__":
	raise SystemExit(main())
