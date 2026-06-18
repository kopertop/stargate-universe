#!/usr/bin/env bash
# TTS emotion bake-off orchestrator. Runs each engine (skip-on-fail), normalizes
# outputs to 48kHz mono, then builds the comparison matrix.
#
#   ./run_bakeoff.sh                       # all engines
#   ./run_bakeoff.sh zipvoice chatterbox   # a subset
#
# ZipVoice needs the sidecar running first:
#   tools/tts-onnx-poc/run_server.sh
#
# First runs download multi-GB models (chatterbox ~2GB, qwen3 ~3GB, orpheus ~6GB,
# indextts2 several GB). Voxtral is excluded (gated, needs HF_TOKEN).
set -uo pipefail
cd "$(dirname "$0")"

ESPEAK_PREFIX="$(brew --prefix espeak 2>/dev/null)"
export PHONEMIZER_ESPEAK_LIBRARY="${ESPEAK_PREFIX}/lib/libespeak.dylib"

ENGINES=("$@")
[ ${#ENGINES[@]} -eq 0 ] && ENGINES=(zipvoice chatterbox qwen3 indextts2 orpheus)

# Force uv to a clean, managed interpreter. An ACTIVE Anaconda base env
# (CONDA_PREFIX set) otherwise leaks its site-packages into uv's "isolated" env —
# e.g. a broken global torchvision shadows the pinned one and crashes transformers 5.x
# imports ("Could not import module 'LlamaModel'"). only-managed sidesteps it entirely.
UV="uv run --python-preference only-managed --python 3.12"

run_engine() {
	case "$1" in
		zipvoice)   python3 gen_zipvoice.py ;;
		chatterbox) $UV --with chatterbox-tts --with torchaudio --with torchvision python gen_chatterbox.py ;;
		qwen3)      $UV --with mlx-audio --with soundfile --with phonemizer --prerelease=allow python gen_qwen3.py ;;
		orpheus)    $UV --with mlx-audio --with soundfile --with phonemizer --prerelease=allow python gen_orpheus.py ;;
		indextts2)  # indextts pins numba==0.58.1 -> llvmlite 0.41.1, which has no 3.12 wheel
		            # and fails to build from source; 3.11 has a prebuilt wheel.
		            uv run --python-preference only-managed --python 3.11 \
		                --with "git+https://github.com/index-tts/index-tts" \
		                --with huggingface_hub --with soundfile python gen_indextts2.py ;;
		*) echo "unknown engine: $1" >&2; return 1 ;;
	esac
}

for e in "${ENGINES[@]}"; do
	echo "=== $e ==="
	run_engine "$e" || echo "[$e] generator exited non-zero (continuing)"
done

echo "=== normalize -> 48kHz mono ==="
while IFS= read -r -d '' f; do
	tmp="${f%.wav}.tmp"
	if ffmpeg -y -loglevel error -i "$f" -ar 48000 -ac 1 -f wav "$tmp" 2>/dev/null; then
		mv "$tmp" "$f"
	else
		rm -f "$tmp"
	fi
done < <(find out -name '*.wav' -print0 2>/dev/null)

python3 build_index.py
echo
echo "Done. Listen:  open tools/tts-bakeoff/out/index.html"
echo "         or:  afplay tools/tts-bakeoff/out/chatterbox/scott-cover-panic.wav"
