#!/usr/bin/env python3
"""Build the bake-off comparison matrix from each engine's out/<engine>/meta.json.

Emits:
  out/index.md   — afplay-friendly table (rows = lines x mood, cols = engines)
  out/index.html — same matrix with inline <audio> players (click to compare)

Stdlib only.
"""
from __future__ import annotations

import json
from pathlib import Path

import common

ENGINE_ORDER = ["zipvoice", "chatterbox", "indextts2", "orpheus", "qwen3"]


def _load_meta() -> dict[str, dict]:
	metas: dict[str, dict] = {}
	for d in sorted(common.OUT.glob("*")):
		mj = d / "meta.json"
		if mj.is_file():
			metas[d.name] = json.loads(mj.read_text())
	return metas


def _engines(metas: dict) -> list[str]:
	known = [e for e in ENGINE_ORDER if e in metas]
	extra = [e for e in metas if e not in ENGINE_ORDER]
	return known + extra


def _entry(meta: dict, line_id: str, mood: str) -> dict | None:
	for e in meta.get("entries", []):
		if e["id"] == line_id and e["mood"] == mood:
			return e
	return None


def build_md(lines: list[dict], metas: dict, engines: list[str]) -> str:
	out = ["# TTS Emotion Bake-off — Scott\n",
	       "Same lines, same reference voice (`sounds/dialog/prologue/scott_clear.wav`). "
	       "The only variable is each engine's emotional rendering. "
	       "Play `panic` vs `calm` for one engine: emotion should differ while the voice stays Scott.\n"]

	out.append("## Engines\n")
	out.append("| Engine | Model | Device | Lines OK | Avg s/line | Note |")
	out.append("|---|---|---|---|---|---|")
	for e in engines:
		m = metas[e]
		ents = m.get("entries", [])
		ok = [x for x in ents if x.get("ok")]
		avg = (sum(x.get("gen_seconds", 0) for x in ok) / len(ok)) if ok else 0
		out.append(f"| {e} | {m.get('model','')} | {m.get('device','')} | "
		           f"{len(ok)}/{len(ents)} | {avg:.1f} | {m.get('note','')} |")
	out.append("")

	out.append("## Samples\n")
	header = "| Line | Mood | Text | " + " | ".join(engines) + " |"
	sep = "|---|---|---|" + "|".join(["---"] * len(engines)) + "|"
	out += [header, sep]
	for ln in lines:
		cells = []
		for e in engines:
			ent = _entry(metas[e], ln["id"], ln["mood"])
			if ent and ent.get("ok"):
				cells.append(f"`out/{e}/{ent['file']}` ({ent.get('gen_seconds','?')}s)")
			elif ent and ent.get("error"):
				cells.append("✗ err")
			else:
				cells.append("–")
		txt = ln["text"].replace("|", "\\|")
		out.append(f"| {ln['id']} | **{ln['mood']}** | {txt} | " + " | ".join(cells) + " |")
	out.append("\nPlay a cell: `afplay tools/tts-bakeoff/out/<engine>/<file>`\n")
	return "\n".join(out)


def build_html(lines: list[dict], metas: dict, engines: list[str]) -> str:
	def cell(e, ln):
		ent = _entry(metas[e], ln["id"], ln["mood"])
		if ent and ent.get("ok"):
			return (f'<audio controls preload="none" src="{e}/{ent["file"]}"></audio>'
			        f'<div class="t">{ent.get("gen_seconds","?")}s</div>')
		if ent and ent.get("error"):
			return f'<span class="err" title="{ent["error"][:160]}">✗ error</span>'
		return '<span class="skip">–</span>'

	rows = []
	for ln in lines:
		tds = "".join(f"<td>{cell(e, ln)}</td>" for e in engines)
		mood_cls = "panic" if ln["mood"] == "panic" else "calm"
		rows.append(f'<tr><td class="id">{ln["id"]}</td>'
		            f'<td class="{mood_cls}">{ln["mood"]}</td>'
		            f'<td class="txt">{ln["text"]}</td>{tds}</tr>')

	eng_summary = []
	for e in engines:
		m = metas[e]
		ents = m.get("entries", [])
		ok = sum(1 for x in ents if x.get("ok"))
		eng_summary.append(f"<li><b>{e}</b> — {m.get('model','')} "
		                   f"<span class=meta>[{m.get('device','')}, {ok}/{len(ents)} ok]</span><br>"
		                   f"<span class=note>{m.get('note','')}</span></li>")

	headers = "".join(f"<th>{e}</th>" for e in engines)
	return f"""<!doctype html><meta charset=utf-8>
<title>TTS Emotion Bake-off — Scott</title>
<style>
 body{{font:14px/1.5 system-ui,sans-serif;margin:24px;color:#e8e8ea;background:#16161a}}
 h1{{font-size:20px}} a{{color:#8ab4f8}}
 table{{border-collapse:collapse;width:100%;margin-top:12px}}
 th,td{{border:1px solid #333;padding:6px 8px;vertical-align:top;text-align:left}}
 th{{background:#23232a;position:sticky;top:0}}
 td.id{{font-family:ui-monospace,monospace;color:#9ad}} td.txt{{max-width:240px;color:#bbb}}
 .panic{{color:#ff7a7a;font-weight:700}} .calm{{color:#7ad19a;font-weight:700}}
 .t{{font-size:11px;color:#888}} .err{{color:#ff7a7a}} .skip{{color:#666}}
 audio{{width:200px;height:30px}} ul{{line-height:1.7}} .meta{{color:#888}} .note{{color:#9a9}}
</style>
<h1>TTS Emotion Bake-off — Scott</h1>
<p>Same lines, same reference voice (<code>scott_clear.wav</code>). Compare <b class=panic>panic</b>
vs <b class=calm>calm</b> within one engine column: emotion should change while the voice stays Scott.</p>
<ul>{''.join(eng_summary)}</ul>
<table><thead><tr><th>line</th><th>mood</th><th>text</th>{headers}</tr></thead>
<tbody>{''.join(rows)}</tbody></table>
"""


def main() -> int:
	lines = common.load_lines()["lines"]
	metas = _load_meta()
	if not metas:
		print("No engine outputs found in out/. Run run_bakeoff.sh first.")
		return 1
	engines = _engines(metas)
	(common.OUT / "index.md").write_text(build_md(lines, metas, engines))
	(common.OUT / "index.html").write_text(build_html(lines, metas, engines))
	print(f"Wrote out/index.md and out/index.html ({len(engines)} engines, {len(lines)} lines)")
	return 0


if __name__ == "__main__":
	raise SystemExit(main())
