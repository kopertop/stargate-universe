#!/bin/bash
# ─── Visual Similarity Report ───────────────────────────────────────────────
#
# Karpathy-style iterative improvement loop:
#   1. Capture game screenshots from predefined camera angles
#   2. Compare against reference images
#   3. Output composite similarity scores
#
# Usage:
#   ./scripts/similarity-report.sh              # full capture + compare
#   ./scripts/similarity-report.sh --skip-capture  # compare only (reuse existing screenshots)
#   ./scripts/similarity-report.sh --validate    # run tool self-validation

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SCREENSHOTS_DIR="$SCRIPT_DIR/screenshots"
CATALOG="$SCRIPT_DIR/reference-catalog.json"
REPORT_DIR="$SCRIPT_DIR/reports"

# ─── Parse args ──────────────────────────────────────────────────────────────

SKIP_CAPTURE=false
VALIDATE_ONLY=false

for arg in "$@"; do
  case "$arg" in
    --skip-capture) SKIP_CAPTURE=true ;;
    --validate)     VALIDATE_ONLY=true ;;
    *)              echo "Unknown arg: $arg"; exit 1 ;;
  esac
done

# ─── Validate mode ──────────────────────────────────────────────────────────

if [ "$VALIDATE_ONLY" = true ]; then
  echo "Running tool self-validation..."
  python3 "$SCRIPT_DIR/visual_similarity.py" validate
  exit $?
fi

# ─── Capture screenshots ────────────────────────────────────────────────────

if [ "$SKIP_CAPTURE" = false ]; then
  echo "═══════════════════════════════════════════════════"
  echo " Step 1: Capturing game screenshots"
  echo "═══════════════════════════════════════════════════"

  mkdir -p "$SCREENSHOTS_DIR"
  cd "$PROJECT_DIR"
  bun run scripts/capture-screenshots.ts
fi

# ─── Run similarity comparison ──────────────────────────────────────────────

echo ""
echo "═══════════════════════════════════════════════════"
echo " Step 2: Comparing against reference images"
echo "═══════════════════════════════════════════════════"

mkdir -p "$REPORT_DIR"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
REPORT_FILE="$REPORT_DIR/similarity-$TIMESTAMP.json"

python3 "$SCRIPT_DIR/visual_similarity.py" report "$CATALOG" "$SCREENSHOTS_DIR" -o "$REPORT_FILE"

echo ""
echo "═══════════════════════════════════════════════════"
echo " Report saved: $REPORT_FILE"
echo "═══════════════════════════════════════════════════"

# ─── Print summary ──────────────────────────────────────────────────────────

python3 - "$REPORT_FILE" <<'PYEOF'
import json, sys

report_file = sys.argv[1]
with open(report_file) as f:
    report = json.load(f)

if 'error' in report:
    print(f'ERROR: {report["error"]}')
    sys.exit(1)

print(f'Overall similarity: {report["average_composite_score"]:.1f}%')
print(f'Comparisons: {report["num_comparisons"]}')
print()

for r in sorted(report['results'], key=lambda x: x['composite_score']):
    score = r['composite_score']
    bar = '\u2588' * int(score / 2) + '\u2591' * (50 - int(score / 2))
    print(f'  {r["name"]:<25} {bar} {score:.1f}%')
PYEOF
