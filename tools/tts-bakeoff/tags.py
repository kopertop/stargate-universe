"""Neutral-tag -> per-engine emotion adapter for the TTS bake-off.

The bake-off authors each line ONCE with engine-agnostic tags (see lines.json:
`panic`, `shout`, `calm`, `sigh`, `gasp`, `laugh`). Each engine speaks a different
emotional dialect, so this module is the single place that translation lives.

Add/remove an engine here; the line data in lines.json never changes.

Returns per engine:
  chatterbox(tags)  -> {"exaggeration": float, "temperature": float, "cfg_weight": float}
  orpheus(text, t)  -> text with inline <tag> markup the model understands
  indextts2(tags)   -> a plain-English emotion instruction string
  zipvoice(text)    -> text with all tags stripped (baseline has no emotion control)
"""
from __future__ import annotations

import re

# ---- Chatterbox: single exaggeration knob (0=flat .. 2=theatrical) + sampling ----
# Resemble's exaggeration is the emotion intensity; temperature adds variation;
# cfg_weight (pace/guidance) lower = faster/looser delivery which reads as urgency.
_CHATTERBOX = {
	"panic": {"exaggeration": 1.6, "temperature": 0.9, "cfg_weight": 0.3},
	"shout": {"exaggeration": 1.7, "temperature": 0.9, "cfg_weight": 0.3},
	"calm":  {"exaggeration": 0.3, "temperature": 0.6, "cfg_weight": 0.5},
	"sigh":  {"exaggeration": 0.4, "temperature": 0.7, "cfg_weight": 0.5},
}
_CHATTERBOX_DEFAULT = {"exaggeration": 0.5, "temperature": 0.8, "cfg_weight": 0.5}

# ---- Orpheus: inline emotion tags the model renders as paralinguistics ----
# Orpheus understands a fixed tag set; map ours onto it. `panic`/`shout` have no
# 1:1 paralinguistic tag, so we lean on punctuation/caps in the text plus a leading
# breath. `sigh`/`gasp`/`laugh` map directly.
_ORPHEUS_INLINE = {
	"sigh":  "<sigh> ",
	"gasp":  "<gasp> ",
	"laugh": "<laugh> ",
}

# ---- IndexTTS-2: natural-language emotion instruction (soft Qwen3-guided control) ----
_INDEXTTS2 = {
	"panic": "shouting, panicked, breathless, high urgency",
	"shout": "shouting at full volume, commanding, urgent",
	"calm":  "calm, low energy, reflective, measured",
	"sigh":  "wistful, quiet, slightly tired, reflective",
}
_INDEXTTS2_DEFAULT = "neutral, natural delivery"


def _first_known(tags: list[str], table: dict) -> str | None:
	for t in tags:
		if t in table:
			return t
	return None


def chatterbox(tags: list[str]) -> dict:
	"""Strongest tag wins (panic/shout before calm)."""
	for key in ("shout", "panic", "sigh", "calm"):
		if key in tags:
			return dict(_CHATTERBOX[key])
	return dict(_CHATTERBOX_DEFAULT)


def orpheus(text: str, tags: list[str]) -> str:
	"""Prefix inline tags Orpheus understands; uppercase shouted lines for emphasis."""
	prefix = "".join(_ORPHEUS_INLINE[t] for t in tags if t in _ORPHEUS_INLINE)
	body = text
	if "shout" in tags or "panic" in tags:
		# Orpheus has no <shout> tag; ALL-CAPS + exclamation reliably raises intensity.
		body = text.upper()
	return f"{prefix}{body}"


def indextts2(tags: list[str]) -> str:
	for key in ("shout", "panic", "sigh", "calm"):
		if key in tags:
			return _INDEXTTS2[key]
	return _INDEXTTS2_DEFAULT


def qwen3_instruct(tags: list[str]) -> str:
	"""Qwen3-TTS CustomVoice `instruct` reuses the same plain-English directive."""
	return indextts2(tags)


_TAG_RE = re.compile(r"<[^>]+>|\[[^\]]+\]")


def zipvoice(text: str) -> str:
	"""Baseline has no emotion control: strip any tag markup, speak the words only."""
	return _TAG_RE.sub("", text).strip()
