#!/usr/bin/env python3
"""Build a per-character listening page for the Chatterbox-Turbo tag samples
(out/chatterbox_turbo/). Separate from the 5-engine matrix in build_index.py because
these are grouped by character + tagged lines, not the panic/calm bake-off lines.

Emits out/index_turbo.md and out/index_turbo.html.
"""
from __future__ import annotations

import json
import re

import common

TAG_RE = re.compile(r"\[[^\]]+\]")


def main() -> int:
	meta = json.loads((common.OUT / "chatterbox_turbo" / "meta.json").read_text())
	lines = json.loads((common.HERE / "lines_turbo.json").read_text())["lines"]
	by_id = {f"{l['char']}-{l['id']}": l for l in lines}
	ents = meta["entries"]

	# Markdown
	md = ["# Chatterbox-Turbo — paralinguistic tag samples\n",
	      f"Model: **{meta['model']}** · device **{meta['device']}** · "
	      f"~{round(sum(e.get('gen_seconds',0) for e in ents)/len(ents),1)}s/line\n",
	      f"> {meta['note']}\n",
	      "| Character | Line | Tags | Text | File |", "|---|---|---|---|---|"]
	for e in ents:
		l = by_id.get(e["id"], {})
		tags = " ".join(TAG_RE.findall(e["text"])) or "—"
		ok = f"`out/chatterbox_turbo/{e['file']}` ({e.get('gen_seconds','?')}s)" if e.get("ok") else "✗"
		md.append(f"| {l.get('char','')} | {e['id'].split('-',1)[-1]} | {tags} | "
		          f"{e['text'].replace('|','\\|')} | {ok} |")
	md.append("\nPlay: `afplay tools/tts-bakeoff/out/chatterbox_turbo/<file>`\n")
	(common.OUT / "index_turbo.md").write_text("\n".join(md))

	# HTML, grouped by character
	groups: dict[str, list] = {}
	for e in ents:
		groups.setdefault(by_id.get(e["id"], {}).get("char", "?"), []).append(e)

	def row(e):
		tags = " ".join(f'<code>{t}</code>' for t in TAG_RE.findall(e["text"])) or "—"
		player = (f'<audio controls preload="none" src="chatterbox_turbo/{e["file"]}"></audio>'
		          if e.get("ok") else '<span class=err>✗</span>')
		return (f'<tr><td class=tags>{tags}</td><td class=txt>{e["text"]}</td>'
		        f'<td>{player}</td><td class=t>{e.get("gen_seconds","?")}s</td></tr>')

	sections = []
	for char, es in groups.items():
		rows = "".join(row(e) for e in es)
		sections.append(f"<h2>{char.upper()}</h2><table><thead><tr><th>tags</th><th>text</th>"
		                f"<th>audio</th><th>gen</th></tr></thead><tbody>{rows}</tbody></table>")

	html = f"""<!doctype html><meta charset=utf-8>
<title>Chatterbox-Turbo tag samples</title>
<style>
 body{{font:14px/1.55 system-ui,sans-serif;margin:24px;color:#e8e8ea;background:#16161a}}
 h1{{font-size:20px}} h2{{margin-top:26px;color:#9ad;border-bottom:1px solid #333;padding-bottom:4px}}
 table{{border-collapse:collapse;width:100%}} th,td{{border:1px solid #2c2c34;padding:6px 9px;text-align:left;vertical-align:top}}
 th{{background:#23232a}} .tags code{{background:#2a2a33;color:#ffd479;padding:1px 5px;border-radius:4px;margin-right:3px}}
 .txt{{max-width:420px;color:#cfd}} .t{{color:#888;font-size:12px}} .err{{color:#ff7a7a}} audio{{width:230px;height:30px}}
 .note{{color:#9a9;margin:6px 0 14px}}
</style>
<h1>Chatterbox-Turbo — paralinguistic tag samples (Scott · Eli · TJ)</h1>
<p class=note>{meta['note']}<br>Model {meta['model']} · {meta['device']}.</p>
{''.join(sections)}
"""
	(common.OUT / "index_turbo.html").write_text(html)
	print(f"Wrote out/index_turbo.md and out/index_turbo.html ({len(ents)} samples, {len(groups)} characters)")
	return 0


if __name__ == "__main__":
	raise SystemExit(main())
