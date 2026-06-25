"""Transcribe the isolated SGU-opening vocals stem with segment+word timestamps.
Dev tool: extracts WHEN each line is spoken so the cold-open beats can be synced to
the source recording. Writes asr/transcript.json (timestamps + text segments)."""
import json
import sys
import mlx_whisper

AUDIO = sys.argv[1] if len(sys.argv) > 1 else "vocals_16k.wav"
OUT = "asr/transcript.json"

res = mlx_whisper.transcribe(
    AUDIO,
    path_or_hf_repo="mlx-community/whisper-large-v3-mlx",
    word_timestamps=True,
    condition_on_previous_text=False,
)

segs = []
for s in res.get("segments", []):
    segs.append({
        "start": round(float(s["start"]), 2),
        "end": round(float(s["end"]), 2),
        "text": s["text"].strip(),
    })

import os
os.makedirs("asr", exist_ok=True)
with open(OUT, "w") as f:
    json.dump({"language": res.get("language"), "segments": segs}, f, indent=2)
print("wrote", OUT, "segments:", len(segs))
