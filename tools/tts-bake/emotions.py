"""Named emotion presets for the IndexTTS-2 baker.

A preset is a curated, reusable natural-language `emo_text` string. IndexTTS-2's
soft-instruction layer (fine-tuned Qwen3) parses it into an emotion vector applied over
the cloned timbre — so tagging a line `panic` is shorthand for the wording below.
Re-tune a feeling once here and every line tagged with it re-bakes consistently.

A line may override with its own free-text `emo_text` (see jobs/*.json). `emo_alpha`
scales emotion strength (0..1+); the default per preset is tuned for the cold open.
"""
from __future__ import annotations

# preset -> (emo_text, emo_alpha)
PRESETS: dict[str, tuple[str, float]] = {
	"neutral":  ("natural, even delivery", 0.7),
	# Chris-approved cold-open delivery: fast/clipped WITHOUT emotional drama. The
	# wording sets flat affect; the low alpha keeps it from drifting toward panic.
	# (Used for Scott's "Slow down the evac… too hot!" — "rushed, not emo".)
	"rushed":   ("fast, clipped, hurried, businesslike, matter-of-fact, flat affect, no drama", 0.45),
	"urgent":   ("commanding, loud, urgent, fast and clipped", 0.95),
	"panic":    ("shouting, panicked, breathless, high urgency", 1.0),
	"shout":    ("shouting at the top of his lungs, intense, furious urgency", 1.0),
	"calm":     ("calm, low energy, measured, reflective", 0.7),
	"reassure": ("calm, gentle, reassuring, warm and steady under pressure", 0.85),
	"confused": ("confused, frightened, disoriented", 0.9),
	"wonder":   ("awed, hushed, disbelief, breathless", 0.9),
	"pained":   ("weak, strained, wincing in pain", 0.9),
	"worried":  ("worried, anxious, searching, voice tightening", 0.9),
	"calling":  ("shouting a name into the chaos, searching, desperate", 1.0),
	"frantic":  ("flustered, scrambling, hurried and nervous", 0.95),
}


def resolve(emotion: str | None, emo_text: str | None, emo_alpha: float | None) -> tuple[str, float]:
	"""Per-line override beats preset. Returns (emo_text, emo_alpha)."""
	if emo_text:
		return emo_text, (emo_alpha if emo_alpha is not None else 0.9)
	key = (emotion or "neutral").strip().lower()
	if key not in PRESETS:
		raise KeyError(f"unknown emotion preset '{emotion}' (have: {sorted(PRESETS)})")
	text, alpha = PRESETS[key]
	return text, (emo_alpha if emo_alpha is not None else alpha)
