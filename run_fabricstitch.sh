#!/bin/bash
# ============================================================
# run_fabricstitch.sh
# Wrapper for ACMS FabricStitch Pipeline
# Mind Over Metadata LLC — Peter Heller
#
# Usage:
#   ./run_fabricstitch.sh <url> [word_limit]
#
# Arguments:
#   url         YouTube URL (required)
#   word_limit  Target word count for narrative (optional, default: 1000)
#               Range: 500 - 10000
#
# Examples:
#   ./run_fabricstitch.sh "https://www.youtube.com/watch?v=6I0z140c05o"
#   ./run_fabricstitch.sh "https://www.youtube.com/watch?v=6I0z140c05o" 3000
#   ./run_fabricstitch.sh "https://www.youtube.com/watch?v=FXwBWS4qDAA" 5000
#
# Word limit guide:
#   500  - 1000  : Executive summary — quick read, key points only
#   1000 - 2000  : Blog post — default, shareable one-pager
#   2000 - 4000  : Long-form article — detailed analysis
#   4000 - 7000  : White paper — comprehensive treatment
#   7000 - 10000 : Full essay — exhaustive coverage
# ============================================================

set -euo pipefail

SKILL_DIR="$HOME/projects/aces-skills/CodingArchitecture/FabricStitch/ACMS_extract_wisdom"

# ── Argument validation ───────────────────────────────────────
URL="${1:-}"
WORD_LIMIT="${2:-1000}"

if [[ -z "$URL" ]]; then
    echo ""
    echo "ERROR: YouTube URL is required"
    echo ""
    echo "Usage:   ./run_fabricstitch.sh <url> [word_limit]"
    echo ""
    echo "Examples:"
    echo "  ./run_fabricstitch.sh \"https://www.youtube.com/watch?v=6I0z140c05o\""
    echo "  ./run_fabricstitch.sh \"https://www.youtube.com/watch?v=6I0z140c05o\" 3000"
    echo "  ./run_fabricstitch.sh \"https://www.youtube.com/watch?v=FXwBWS4qDAA\" 5000"
    echo ""
    echo "Word limit guide:"
    echo "   500 - 1000  : Executive summary (default: 1000)"
    echo "  1000 - 2000  : Blog post"
    echo "  2000 - 4000  : Long-form article"
    echo "  4000 - 7000  : White paper"
    echo "  7000 - 10000 : Full essay"
    echo ""
    exit 1
fi

# Validate word limit range
if ! [[ "$WORD_LIMIT" =~ ^[0-9]+$ ]] || \
   [[ "$WORD_LIMIT" -lt 500 ]] || \
   [[ "$WORD_LIMIT" -gt 10000 ]]; then
    echo ""
    echo "ERROR: word_limit must be a number between 500 and 10000"
    echo "  Provided: $WORD_LIMIT"
    echo ""
    exit 1
fi

# ── Word limit label ──────────────────────────────────────────
if   [[ "$WORD_LIMIT" -le 1000 ]]; then LABEL="Executive summary"
elif [[ "$WORD_LIMIT" -le 2000 ]]; then LABEL="Blog post"
elif [[ "$WORD_LIMIT" -le 4000 ]]; then LABEL="Long-form article"
elif [[ "$WORD_LIMIT" -le 7000 ]]; then LABEL="White paper"
else                                     LABEL="Full essay"
fi

# ── Launch ────────────────────────────────────────────────────
echo ""
echo "  ACMS FabricStitch Pipeline"
echo "  URL        : $URL"
echo "  Word limit : $WORD_LIMIT ($LABEL)"
echo ""

cd "$SKILL_DIR"
./fabric_stitch.sh "$URL" --word-limit "$WORD_LIMIT"
