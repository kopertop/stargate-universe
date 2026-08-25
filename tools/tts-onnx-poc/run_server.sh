#!/usr/bin/env bash
# Launch the resident LuxTTS sidecar for in-engine dynamic dialogue.
# Uses the committed repo voice embeddings by default.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV="${LUXTTS_HOME:-$HOME/.cache/luxtts}/.venv"
VOICES="${LUXTTS_VOICES:-$HERE/voices}"
DEVICE="${TTS_DEVICE:-mps}"   # mps on Apple Silicon; auto-falls back

if [[ ! -x "$VENV/bin/python" ]]; then
	echo "ERROR: LuxTTS venv missing. Run the /tts skill's setup.sh first." >&2
	exit 1
fi

exec "$VENV/bin/python" "$HERE/tts_server.py" --voices-dir "$VOICES" --device "$DEVICE" "$@"
