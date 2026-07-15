#!/usr/bin/env python3
"""Unified bake-off review page -> out/index.html (+ out/index.md).

One page, four sections (each rendered only if its data exists):
  1. 5-engine emotion bake-off matrix (panic vs calm, same Scott lines)
  2. Chatterbox-Turbo paralinguistic-tag samples (Scott/Eli/TJ), grouped by character
  3. Panic / yelling A/B on TJ's triage line (which lever actually shouts)
  4. Base-Chatterbox PANIC render of every game voice

Stdlib only.
"""
from __future__ import annotations

import json
import re

import common

BAKE_ENGINES = ["zipvoice", "chatterbox", "indextts2", "orpheus", "qwen3"]
TAG_RE = re.compile(r"\[[^\]]+\]")

# Panic A/B variant descriptions (files: out/panic_test/tj-triage-<variant>.wav)
PANIC_AB = {
	"turbo_tags": "Turbo + directorial tags [panicked]/[loud]/[yelling]/[louder] — tags spoken literally (✗)",
	"turbo_caps": "Turbo + CAPS + [gasp] only",
	"base_e16": "base Chatterbox · exaggeration 1.6 · CAPS",
	"base_e20": "base Chatterbox · exaggeration 2.0 (max) · CAPS",
	"indextts2": "IndexTTS-2 · emo_text 'screaming/terrified/shouting'",
}


def _meta(engine: str) -> dict | None:
	p = common.OUT / engine / "meta.json"
	return json.loads(p.read_text()) if p.is_file() else None


def _entry(meta, lid, mood):
	for e in meta.get("entries", []):
		if e["id"] == lid and e["mood"] == mood:
			return e
	return None


# ----------------------------------------------------------------------------- HTML
def _matrix_html(lines, metas, engines):
	def cell(e, ln):
		ent = _entry(metas[e], ln["id"], ln["mood"])
		if ent and ent.get("ok"):
			return (f'<audio controls preload=none src="{e}/{ent["file"]}"></audio>'
			        f'<div class=t>{ent.get("gen_seconds","?")}s</div>')
		return '<span class=skip>–</span>' if not (ent and ent.get("error")) else '<span class=err>✗</span>'
	rows = ""
	for ln in lines:
		tds = "".join(f"<td>{cell(e, ln)}</td>" for e in engines)
		rows += (f'<tr><td class=id>{ln["id"]}</td>'
		         f'<td class="{"panic" if ln["mood"]=="panic" else "calm"}">{ln["mood"]}</td>'
		         f'<td class=txt>{ln["text"]}</td>{tds}</tr>')
	summ = "".join(
		f"<li><b>{e}</b> <span class=meta>[{metas[e].get('device','')}, "
		f"{sum(1 for x in metas[e]['entries'] if x.get('ok'))}/{len(metas[e]['entries'])} ok]</span> "
		f"— <span class=note>{metas[e].get('note','')}</span></li>" for e in engines)
	heads = "".join(f"<th>{e}</th>" for e in engines)
	return (f"<h2>1 · Emotion bake-off — same Scott lines, panic vs calm</h2>"
	        f"<p class=note>Compare panic vs calm <i>within</i> a column: emotion should change while the voice stays Scott.</p>"
	        f"<ul>{summ}</ul>"
	        f"<table><thead><tr><th>line</th><th>mood</th><th>text</th>{heads}</tr></thead><tbody>{rows}</tbody></table>")


def _turbo_html(meta):
	lines = {f"{l['char']}-{l['id']}": l for l in
	         json.loads((common.HERE / "lines_turbo.json").read_text())["lines"]}
	groups: dict[str, list] = {}
	for e in meta["entries"]:
		groups.setdefault(lines.get(e["id"], {}).get("char", "?"), []).append(e)
	secs = ""
	for char, es in groups.items():
		rows = ""
		for e in es:
			tags = " ".join(f"<code>{t}</code>" for t in TAG_RE.findall(e["text"])) or "—"
			player = (f'<audio controls preload=none src="chatterbox_turbo/{e["file"]}"></audio>'
			          if e.get("ok") else "<span class=err>✗</span>")
			rows += (f"<tr><td class=tags>{tags}</td><td class=txt>{e['text']}</td>"
			         f"<td>{player}</td><td class=t>{e.get('gen_seconds','?')}s</td></tr>")
		secs += (f"<h3>{char.upper()}</h3><table><thead><tr><th>tags</th><th>text</th>"
		         f"<th>audio</th><th>gen</th></tr></thead><tbody>{rows}</tbody></table>")
	return (f"<h2>2 · Chatterbox-Turbo — paralinguistic tags</h2>"
	        f"<p class=note>{meta['note']}</p>{secs}")


def _panic_ab_html():
	d = common.OUT / "panic_test"
	files = sorted(d.glob("tj-triage-*.wav")) if d.is_dir() else []
	if not files:
		return ""
	rows = ""
	for f in files:
		variant = f.stem.replace("tj-triage-", "")
		desc = PANIC_AB.get(variant, variant)
		cls = "err" if variant == "turbo_tags" else ("good" if variant.startswith(("base", "index")) else "")
		rows += (f"<tr><td class='{cls}'>{variant}</td><td class=txt>{desc}</td>"
		         f"<td><audio controls preload=none src='panic_test/{f.name}'></audio></td></tr>")
	return ("<h2>3 · Panic / yelling A/B — TJ \"Stay with me… NOW!\"</h2>"
	        "<p class=note>Which lever actually shouts. Turbo ignores intensity and SPEAKS directorial tags; "
	        "base Chatterbox <code>exaggeration</code> and IndexTTS-2 emotion are the real yelling levers.</p>"
	        f"<table><thead><tr><th>variant</th><th>what it is</th><th>audio</th></tr></thead><tbody>{rows}</tbody></table>")


def _panic_voices_html(meta):
	rows = ""
	for e in meta["entries"]:
		player = (f'<audio controls preload=none src="panic_voices/{e["file"]}"></audio>'
		          if e.get("ok") else "<span class=err>✗</span>")
		rows += (f"<tr><td class=id>{e['id']}</td><td>{player}</td>"
		         f"<td class=t>{e.get('gen_seconds','?')}s</td></tr>")
	return (f"<h2>4 · Base-Chatterbox PANIC — every voice</h2>"
	        f"<p class=note>{meta['note']}<br>Same yelling line per voice (\"{meta['entries'][0]['text']}\"). "
	        f"These double as <b>panic reference clips</b> — clone from <code>refs/&lt;voice&gt;.wav</code> calm or "
	        f"<code>panic_voices/&lt;voice&gt;.wav</code> panic in any engine.</p>"
	        f"<table><thead><tr><th>voice</th><th>audio</th><th>gen</th></tr></thead><tbody>{rows}</tbody></table>")


def _coldopen_html():
	# Reads the IndexTTS-2 baker's report; clips live in the game's prologue dir, so
	# reference them relative to out/ (../../../sounds/dialog/prologue/<id>.wav).
	rep = common.REPO / "tools" / "tts-bake" / "bake_report_cold_open.json"
	if not rep.is_file():
		return ""
	report = json.loads(rep.read_text())
	vo = "../../../sounds/dialog/prologue"
	rows = ""
	for r in report:  # report order == job order == scene order
		player = (f'<audio controls preload=none src="{vo}/{r["id"]}.wav"></audio>'
		          if r.get("ok") else "<span class=err>✗</span>")
		rows += (f"<tr><td class=id>{r['id']}</td><td>{r['voice']}</td>"
		         f"<td class=tags>{r.get('emotion','-')}</td><td class=txt>{r['text']}</td>"
		         f"<td>{player}</td><td class=t>{r.get('seconds','?')}s</td></tr>")
	return ("<h2>5 · E1 cold open — baked VO (IndexTTS-2)</h2>"
	        "<p class=note>The shipped cold-open dialog, in scene order (9 overlapping barks then "
	        "the 6-beat Rush hand-off). Emotion via named presets (tools/tts-bake/emotions.py). "
	        "Files: <code>sounds/dialog/prologue/&lt;id&gt;.wav</code>.</p>"
	        "<table><thead><tr><th>vo-id</th><th>voice</th><th>emotion</th><th>line</th>"
	        f"<th>audio</th><th>gen</th></tr></thead><tbody>{rows}</tbody></table>")


def build_html(lines, metas, engines) -> str:
	parts = [_matrix_html(lines, metas, engines)]
	if (m := _meta("chatterbox_turbo")):
		parts.append(_turbo_html(m))
	if (ab := _panic_ab_html()):
		parts.append(ab)
	if (pv := _meta("panic_voices")):
		parts.append(_panic_voices_html(pv))
	if (co := _coldopen_html()):
		parts.append(co)
	style = """
 body{font:14px/1.55 system-ui,sans-serif;margin:24px;color:#e8e8ea;background:#16161a}
 h1{font-size:21px} h2{margin-top:34px;color:#8ab4f8;border-bottom:1px solid #333;padding-bottom:5px}
 h3{color:#9ad;margin:18px 0 6px} a{color:#8ab4f8}
 table{border-collapse:collapse;width:100%;margin-top:8px}
 th,td{border:1px solid #2c2c34;padding:6px 9px;text-align:left;vertical-align:top}
 th{background:#23232a;position:sticky;top:0}
 td.id{font-family:ui-monospace,monospace;color:#9ad} td.txt{max-width:380px;color:#cfd}
 .panic{color:#ff7a7a;font-weight:700} .calm{color:#7ad19a;font-weight:700}
 .good{color:#7ad19a;font-weight:700} .err{color:#ff7a7a;font-weight:700}
 .t{font-size:12px;color:#888} .skip{color:#666} .meta{color:#888} .note{color:#9a9}
 .tags code,td code{background:#2a2a33;color:#ffd479;padding:1px 5px;border-radius:4px;margin-right:3px}
 audio{width:220px;height:30px}"""
	return (f"<!doctype html><meta charset=utf-8><title>SGU TTS bake-off</title><style>{style}</style>"
	        f"<h1>Stargate Universe — local TTS review</h1>{''.join(parts)}")


# ------------------------------------------------------------------------------- MD
def build_md(lines, metas, engines) -> str:
	out = ["# TTS bake-off review\n", "## 1 · Emotion bake-off (panic vs calm)\n",
	       "| Line | Mood | " + " | ".join(engines) + " |",
	       "|---|---|" + "|".join(["---"] * len(engines)) + "|"]
	for ln in lines:
		cells = []
		for e in engines:
			ent = _entry(metas[e], ln["id"], ln["mood"])
			cells.append(f"`{e}/{ent['file']}`" if ent and ent.get("ok") else "–")
		out.append(f"| {ln['id']} | {ln['mood']} | " + " | ".join(cells) + " |")
	if _meta("panic_voices"):
		out.append("\n## 4 · Base panic — every voice\n`out/panic_voices/<voice>.wav`")
	out.append("\nOpen `out/index.html` for all sections with inline players.\n")
	return "\n".join(out)


def main() -> int:
	lines = common.load_lines()["lines"]
	metas = {e: _meta(e) for e in BAKE_ENGINES}
	engines = [e for e in BAKE_ENGINES if metas.get(e)]
	if not engines:
		print("No bake-off engine outputs found.")
		return 1
	metas = {e: metas[e] for e in engines}
	(common.OUT / "index.html").write_text(build_html(lines, metas, engines))
	(common.OUT / "index.md").write_text(build_md(lines, metas, engines))
	extras = [s for s, ok in [("turbo", _meta("chatterbox_turbo")),
	                          ("panic-A/B", (common.OUT / "panic_test").is_dir()),
	                          ("panic-voices", _meta("panic_voices"))] if ok]
	print(f"Wrote out/index.html (+md): {len(engines)} engines + sections {extras}")
	return 0


if __name__ == "__main__":
	raise SystemExit(main())
