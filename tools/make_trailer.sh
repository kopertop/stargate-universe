#!/usr/bin/env bash
# Automated gameplay-trailer generator for Stargate Universe (Godot 4.6).
#
# One command: records a scripted reel of ACTUAL gameplay via Godot's built-in
# Movie Maker, then post-processes it with ffmpeg into a branded 16:9 MP4 plus a
# draft social post.
#
#   tools/make_trailer.sh [config.json]    (default: tools/trailer/trailer.config.json)
#
# All trailer TEXT (captions, title card, end card) is rendered IN-ENGINE by the
# runner and baked into the recording — ffmpeg's `drawtext` is an optional
# compile-time feature missing from many builds, so we never depend on it. ffmpeg
# here only transcodes and (optionally) lays a music bed, which use universally
# available filters.
#
# Pipeline:
#   1. Godot --write-movie  → out/raw/trailer_raw.avi (+ beat sidecar JSON)
#   2. ffmpeg normalize     → out/work/capture.mp4 (clean h264 + audio track)
#   3. ffmpeg music bed     → out/trailer_<reel>_16x9.mp4 (or straight copy)
#   4. out/post_text.txt    (draft caption + hashtags)
#
# Local-only / opt-in: Movie Maker needs a GPU context (NOT --headless), so this
# never runs in CI. Mirrors the opt-in `visual`/`kino-map` captures in tests/run.sh.
#
# Env: SKIP_RECORD=1 reuses an existing out/raw/ capture (iterate on the music
# edit without re-rendering the gameplay).

set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$(pwd)"

CONFIG="${1:-tools/trailer/trailer.config.json}"

# --- dependencies --------------------------------------------------------
for bin in jq ffmpeg ffprobe; do
	if ! command -v "$bin" >/dev/null 2>&1; then
		echo "ERROR: '$bin' is required but not on PATH." >&2
		exit 2
	fi
done

GODOT_BIN="${GODOT_BIN:-/Applications/Godot.app/Contents/MacOS/Godot}"
if ! [[ -x "$GODOT_BIN" ]]; then
	if command -v godot >/dev/null 2>&1; then
		GODOT_BIN="$(command -v godot)"
	else
		echo "ERROR: cannot find Godot. Set GODOT_BIN or add 'godot' to PATH." >&2
		exit 2
	fi
fi

if [[ ! -f "$CONFIG" ]]; then
	echo "ERROR: config not found: $CONFIG" >&2
	exit 2
fi

# --- config --------------------------------------------------------------
cfg() { jq -r "$1 // empty" "$CONFIG"; }
REEL="$(cfg '.reel')";                  REEL="${REEL:-e1_highlight}"
FPS="$(cfg '.fps')";                    FPS="${FPS:-60}"
RES="$(cfg '.resolution')";             RES="${RES:-1280x720}"
MUSIC="$(cfg '.music')"
MUSIC_VOL="$(cfg '.music_volume')";     MUSIC_VOL="${MUSIC_VOL:-0.35}"
GAME_VOL="$(cfg '.game_audio_volume')"; GAME_VOL="${GAME_VOL:-1.0}"
GAME_NAME="$(cfg '.game_name')";        GAME_NAME="${GAME_NAME:-STARGATE UNIVERSE}"
TAGLINE="$(cfg '.tagline')"
CTA="$(cfg '.end_card_cta')";           CTA="${CTA:-Wishlist now}"
CAPTIONS="$(cfg '.captions')";          CAPTIONS="${CAPTIONS:-true}"
HASHTAGS="$(cfg '.hashtags')"
WIDTH="${RES%x*}"
HEIGHT="${RES#*x}"
CAP_ENV="1"; [[ "$CAPTIONS" == "false" ]] && CAP_ENV="0"

# Replay mode: if a captured playthrough exists, render THAT (real human play)
# instead of the scripted reel. Capture a run with tools/trailer/record.sh.
# Force scripted with FORCE_SCRIPTED=1; point at a specific capture with CAPTURE=.
CAPTURE="${CAPTURE:-$ROOT/out/capture/playthrough.json}"
REPLAY_SCENE="res://tools/trailer/replay.tscn"
SCRIPTED_SCENE="res://tools/trailer/trailer.tscn"
USE_REPLAY=0
if [[ "${FORCE_SCRIPTED:-0}" != "1" && -f "$CAPTURE" ]]; then
	USE_REPLAY=1
fi

# --- layout --------------------------------------------------------------
OUT="$ROOT/out"
RAW="$OUT/raw"
WORK="$OUT/work"
rm -rf "$WORK"; mkdir -p "$RAW" "$WORK"
RAW_AVI="$RAW/trailer_raw.avi"
BEATS="$RAW/trailer_beats.json"
FINAL="$OUT/trailer_${REEL}_16x9.mp4"
# Clear stale raw capture only when we're about to re-record (SKIP_RECORD reuses it).
if [[ "${SKIP_RECORD:-0}" != "1" ]]; then
	rm -f "$RAW_AVI" "$RAW/trailer_raw.wav" "$BEATS"
fi

# ========================================================================
# 1. RECORD — drive the scripted reel under Movie Maker.
# ========================================================================
if [[ "${SKIP_RECORD:-0}" == "1" ]]; then
	echo "=== [1/4] SKIP_RECORD=1 — reusing existing capture ==="
	[[ -f "$RAW_AVI" ]] || { echo "ERROR: SKIP_RECORD set but $RAW_AVI is missing." >&2; exit 1; }
else
	CAP_DATE="$(date '+%B %-d, %Y' 2>/dev/null || date '+%B %d, %Y')"
	TITLE_SUB="Real gameplay footage, captured ${CAP_DATE}"
	SCENE="$SCRIPTED_SCENE"
	SRC="scripted reel '$REEL'"
	if [[ "$USE_REPLAY" == "1" ]]; then
		SCENE="$REPLAY_SCENE"
		SRC="captured playthrough ($CAPTURE)"
	fi
	echo "=== [1/4] recording ${SRC} @ ${RES} ${FPS}fps via Godot Movie Maker ==="
	echo "    (a game window will open — do not close it; the runner quits itself)"
	TRAILER_REEL="$REEL" TRAILER_FPS="$FPS" TRAILER_BEATS="$BEATS" \
	TRAILER_CAPTIONS="$CAP_ENV" TRAILER_GAME_NAME="$GAME_NAME" \
	TRAILER_TAGLINE="$TAGLINE" TRAILER_TITLE_SUB="$TITLE_SUB" TRAILER_CTA="$CTA" \
	TRAILER_CAPTURE="$CAPTURE" \
		"$GODOT_BIN" \
			--rendering-driver metal \
			--resolution "$RES" \
			--fixed-fps "$FPS" \
			--write-movie "$RAW_AVI" \
			"$SCENE"
fi

[[ -f "$RAW_AVI" ]] || { echo "ERROR: Godot did not produce $RAW_AVI" >&2; exit 1; }

# ========================================================================
# 2. NORMALIZE — guarantee a clean h264 clip with an audio track.
# ========================================================================
echo "=== [2/4] normalizing capture ==="
VSCALE="scale=${WIDTH}:${HEIGHT}:force_original_aspect_ratio=decrease,pad=${WIDTH}:${HEIGHT}:(ow-iw)/2:(oh-ih)/2,setsar=1"
HAS_AUDIO="$(ffprobe -v error -select_streams a -show_entries stream=index -of csv=p=0 "$RAW_AVI" | head -n1 || true)"
WAV="$RAW/trailer_raw.wav"
if [[ -n "$HAS_AUDIO" ]]; then
	ffmpeg -y -loglevel error -i "$RAW_AVI" \
		-map 0:v:0 -map 0:a:0 -vf "$VSCALE" -r "$FPS" \
		-c:v libx264 -pix_fmt yuv420p -crf 18 -preset medium \
		-c:a aac -ar 48000 -ac 2 "$WORK/capture.mp4"
elif [[ -f "$WAV" ]]; then
	ffmpeg -y -loglevel error -i "$RAW_AVI" -i "$WAV" \
		-map 0:v:0 -map 1:a:0 -vf "$VSCALE" -r "$FPS" -shortest \
		-c:v libx264 -pix_fmt yuv420p -crf 18 -preset medium \
		-c:a aac -ar 48000 -ac 2 "$WORK/capture.mp4"
else
	echo "    no captured audio stream — adding silent track"
	ffmpeg -y -loglevel error -i "$RAW_AVI" -f lavfi -i "anullsrc=r=48000:cl=stereo" \
		-map 0:v:0 -map 1:a:0 -vf "$VSCALE" -r "$FPS" -shortest \
		-c:v libx264 -pix_fmt yuv420p -crf 18 -preset medium \
		-c:a aac -ar 48000 -ac 2 "$WORK/capture.mp4"
fi
DUR="$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$WORK/capture.mp4")"

# ========================================================================
# 3. MUSIC BED — mix a ducked, faded music track under the game audio.
# ========================================================================
echo "=== [3/4] music bed ==="
HAVE_MUSIC="false"
if [[ -n "$MUSIC" && -f "$ROOT/$MUSIC" ]]; then HAVE_MUSIC="true"; MUSIC_PATH="$ROOT/$MUSIC"; fi
if [[ -n "$MUSIC" && ! -f "$ROOT/$MUSIC" ]]; then echo "WARN: music '$MUSIC' not found — skipping bed." >&2; fi

if [[ "$HAVE_MUSIC" == "true" ]]; then
	FADE_OUT_START="$(awk "BEGIN{d=$DUR-2; if(d<0)d=0; print d}")"
	AFILTER="[1:a]volume=${MUSIC_VOL},afade=t=in:st=0:d=1,afade=t=out:st=${FADE_OUT_START}:d=2[mus];[0:a]volume=${GAME_VOL}[gme];[gme][mus]amix=inputs=2:duration=first:dropout_transition=0[a]"
	ffmpeg -y -loglevel error -i "$WORK/capture.mp4" -i "$MUSIC_PATH" \
		-filter_complex "${AFILTER}" -map 0:v -map "[a]" \
		-c:v copy -c:a aac -b:a 192k -shortest "$FINAL"
else
	echo "    no music — using captured audio as-is"
	cp "$WORK/capture.mp4" "$FINAL"
fi

# ========================================================================
# 4. DRAFT POST TEXT
# ========================================================================
echo "=== [4/4] draft post text ==="
POST="$OUT/post_text.txt"
{
	echo "$GAME_NAME"
	[[ -n "$TAGLINE" ]] && echo "$TAGLINE"
	echo
	if [[ -f "$BEATS" ]]; then
		jq -r '.beats[].caption' "$BEATS" | grep -vxF "$GAME_NAME" | sed 's/^/• /'
		echo
	fi
	echo "$CTA — built in Godot. 🛰️"
	[[ -n "$HASHTAGS" ]] && { echo; echo "$HASHTAGS"; }
} > "$POST"

echo
echo "=== done ==="
echo "  video : $FINAL"
echo "  post  : $POST"
echo "  beats : $BEATS"
echo "  length: ${DUR}s"
