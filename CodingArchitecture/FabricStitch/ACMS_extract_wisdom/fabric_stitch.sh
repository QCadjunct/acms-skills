#!/bin/bash
# ============================================================
# ACMS BASH Agent — Fabric Stitching Pipeline v3
# Mind Over Metadata LLC — Peter Heller
# skill: CodingArchitecture/FabricStitch/ACMS_extract_wisdom
#
# Usage:
#   ./fabric_stitch.sh --url   <youtube_url>      [--word-limit N] [--output-dir DIR]
#   ./fabric_stitch.sh --file  <path/to/file>     [--word-limit N] [--output-dir DIR]
#   ./fabric_stitch.sh --web   <article_url>      [--word-limit N] [--output-dir DIR]
#   ./fabric_stitch.sh --video <path/to/video>    [--word-limit N] [--output-dir DIR]
#
# Input sources:
#   --url   YouTube URL    — uses fabric --youtube for transcript
#   --file  Local file     — .md .txt .pdf .docx .html
#   --web   Web article    — any URL (fetches via fabric --url or curl)
#   --video Local video    — uses yt-dlp for transcript
#
# Examples:
#   ./fabric_stitch.sh --url  "https://youtube.com/watch?v=xxx"
#   ./fabric_stitch.sh --url  "https://youtube.com/watch?v=xxx" --word-limit 5000
#   ./fabric_stitch.sh --file ~/Documents/article.md
#   ./fabric_stitch.sh --file ~/Downloads/paper.pdf --word-limit 3000
#   ./fabric_stitch.sh --web  "https://www.dailydoseofds.com/ai-agents-crash-course-part-1/"
#   ./fabric_stitch.sh --web  "https://martinfowler.com/articles/hexagonal.html" --word-limit 5000
#   ./fabric_stitch.sh --video ~/Videos/lecture.mp4 --word-limit 2000
#
# Output structure:
#   output/YYYY/MM/YYYYMMDD-Title-Slug/
#     step-01-extracted-wisdom.md
#     step-02-summary.md
#     step-03-insights.md
#     step-04-narrative.md
#     step-05-combined-for-synthesis.md
#     Title-YYYYMMDD-[uuidv7].md
#     Title-YYYYMMDD-[uuidv7].docx
#     Title-YYYYMMDD-[uuidv7].pdf
#     Title-YYYYMMDD-[uuidv7].html
#     manifest.json
# ============================================================

set -euo pipefail

# ── Argument Parsing ──────────────────────────────────────────
SOURCE_URL=""      # YouTube URL
SOURCE_FILE=""     # Local file path (.md .txt .pdf .docx .html)
SOURCE_WEB=""      # Web article URL (any site)
SOURCE_VIDEO=""    # Local video file
SOURCE_TYPE=""     # youtube | file | web | video
WORD_LIMIT=3000
OUTPUT_BASE="$HOME/projects/acms-skills/FabricStitch/output"
WIN_OUTPUT_DIR="/mnt/c/Users/pheller/Documents/ACMS-Output"
UV_PYTHON="$HOME/projects/acms-skills/.venv/bin/python3"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --url)         SOURCE_URL="$2";   SOURCE_TYPE="youtube"; shift 2 ;;
    --file)        SOURCE_FILE="$2";  SOURCE_TYPE="file";    shift 2 ;;
    --web)         SOURCE_WEB="$2";   SOURCE_TYPE="web";     shift 2 ;;
    --video)       SOURCE_VIDEO="$2"; SOURCE_TYPE="video";   shift 2 ;;
    --word-limit)  WORD_LIMIT="$2";   shift 2 ;;
    --output-dir)  OUTPUT_BASE="$2";  shift 2 ;;
    --*)           echo "Unknown flag: $1" >&2; exit 1 ;;
    # Legacy: bare YouTube URL as positional arg
    *)
      if [[ "$1" == http* ]]; then
        SOURCE_URL="$1"; SOURCE_TYPE="youtube"
      fi
      shift ;;
  esac
done

# Validate — one source required
if [[ -z "$SOURCE_TYPE" ]]; then
  echo ""
  echo "ERROR: Input source required"
  echo ""
  echo "  --url   <youtube_url>    YouTube video"
  echo "  --file  <path>           Local file (.md .txt .pdf .docx .html)"
  echo "  --web   <article_url>    Web article (any URL)"
  echo "  --video <path>           Local video file"
  echo ""
  exit 1
fi

[[ "$SOURCE_TYPE" == "file"  && ! -f "$SOURCE_FILE"  ]] && { echo "ERROR: File not found: $SOURCE_FILE" >&2;  exit 1; }
[[ "$SOURCE_TYPE" == "video" && ! -f "$SOURCE_VIDEO" ]] && { echo "ERROR: Video not found: $SOURCE_VIDEO" >&2; exit 1; }

# Unified source label for display and manifest
case "$SOURCE_TYPE" in
  youtube) SOURCE_LABEL="$SOURCE_URL"          ;;
  file)    SOURCE_LABEL="file://$SOURCE_FILE"  ;;
  web)     SOURCE_LABEL="$SOURCE_WEB"          ;;
  video)   SOURCE_LABEL="file://$SOURCE_VIDEO" ;;
esac

# ── UUIDv7 Generator ──────────────────────────────────────────
# UUIDv7 encodes millisecond timestamp — time-sortable and globally unique
# This ID is the Architectural Decision Record (ADR) pipeline run identifier
# It links every file in this folder to the cost audit trail in cost_audit.log
generate_uuidv7() {
  "$UV_PYTHON" -c "
import time, random
ms = int(time.time() * 1000)
ts_hex = format(ms, '012x')
rand_a = format(random.getrandbits(12), '03x')
rand_b = format(random.getrandbits(62), '015x')
raw = ts_hex + rand_a + rand_b
u = f'{raw[0:8]}-{raw[8:12]}-7{raw[12:15]}-{format(random.randint(0x80,0xbf),\"02x\")}{raw[17:19]}-{raw[19:31]}'
print(u)
" 2>/dev/null || python3 -c "import uuid; print(uuid.uuid4())"
}

# ── Date helpers ──────────────────────────────────────────────
TODAY=$(date +%Y%m%d)
YEAR=$(date +%Y)
MONTH=$(date +%m)
DAY=$(date +%d)
PIPELINE_START_TIME=$(date '+%Y-%m-%d %H:%M:%S')

# ── Run ID — Architectural Decision Record (ADR) identifier ───
# ADR-009 governs the ACMS cost audit format
# This UUID ties all pipeline artifacts to their cost audit entries
RUN_ID=$(generate_uuidv7)

# ── Temp staging dir (renamed after title extraction) ─────────
STAGING="${OUTPUT_BASE}/.staging_${RUN_ID}"
mkdir -p "$STAGING"

# ── Multi-Model Configuration ─────────────────────────────────
STEP1_MODEL="gemini-2.5-flash";    STEP1_VENDOR="Gemini"
STEP2_MODEL="claude-sonnet-4-5";   STEP2_VENDOR="Anthropic"
STEP3_MODEL="gemini-2.5-flash";    STEP3_VENDOR="Gemini"
STEP4_MODEL="claude-sonnet-4-5";   STEP4_VENDOR="Anthropic"

# ── Vendor Cost Rates per 1M tokens ──────────────────────────
declare -A INPUT_RATE=(
    ["Gemini"]="0.075"
    ["Anthropic"]="3.00"
    ["Ollama"]="0.00"
    ["OpenAI"]="2.50"
    ["GitHub"]="0.00"
)
declare -A OUTPUT_RATE=(
    ["Gemini"]="0.30"
    ["Anthropic"]="15.00"
    ["Ollama"]="0.00"
    ["OpenAI"]="10.00"
    ["GitHub"]="0.00"
)

# ── Token Counter ─────────────────────────────────────────────
count_tokens() {
    local file=$1
    if [ ! -f "$file" ]; then echo "0"; return; fi
    "$UV_PYTHON" -c "
import tiktoken
enc = tiktoken.get_encoding('cl100k_base')
text = open('$file', 'r', errors='replace').read()
print(len(enc.encode(text)))
" 2>/dev/null || echo "0"
}

# ── Cost Calculator ───────────────────────────────────────────
calc_cost() {
    local vendor=$1 input_tokens=$2 output_tokens=$3
    local in_rate=${INPUT_RATE[$vendor]:-"0.00"}
    local out_rate=${OUTPUT_RATE[$vendor]:-"0.00"}
    "$UV_PYTHON" -c "
in_cost  = ($input_tokens  / 1_000_000) * $in_rate
out_cost = ($output_tokens / 1_000_000) * $out_rate
print(f'{in_cost + out_cost:.6f}')
" 2>/dev/null || echo "0.000000"
}

# ── Source title extraction ──────────────────────────────────
# YouTube/video: yt-dlp for accurate title
# File: filename without extension
# Web: yt-dlp (many sites) or HTML <title> tag via curl
get_source_title() {
    local source_type=$1
    local source=$2
    local title=""
    case "$source_type" in
      youtube|video)
        if command -v yt-dlp &>/dev/null; then
          title=$(yt-dlp --get-title "$source" 2>/dev/null | head -1)
        fi
        if [[ -z "$title" && "$source_type" == "video" ]]; then
          title=$(basename "$source" | sed "s/\.[^.]*$//")
        fi
        ;;
      file)
        title=$(basename "$source" | sed "s/\.[^.]*$//" | tr "-_" " ")
        ;;
      web)
        if command -v yt-dlp &>/dev/null; then
          title=$(yt-dlp --get-title "$source" 2>/dev/null | head -1)
        fi
        if [[ -z "$title" ]]; then
          title=$(curl -sL --max-time 10 "$source" 2>/dev/null |             grep -o '<title>[^<]*</title>' |             sed "s/<[^>]*>//g" | head -1 |             sed "s/ *[-|].*$//")  # strip site name suffix after - or |
        fi
        ;;
    esac
    echo "$title"
}

# ── Title extraction from narrative ──────────────────────────
extract_title() {
    local file=$1
    grep -m1 '^# ' "$file" 2>/dev/null | sed 's/^# //' | head -1
}

# ── Title to filesystem-safe slug ───────────────────────────
# No length cap on folder or file — full title preserved
# UUIDv7 provides uniqueness — title provides readability
# Rules:
#   - Strip channel/venue suffix after | 
#   - Replace & with "and" (preserves technical terms like Ports & Adapters)
#   - Remove remaining special chars
#   - Collapse spaces, convert to slug
title_to_slug() {
    local raw="$1"
    local max="${2:-0}"   # 0 = no cap (folder), N = cap at N chars (file)
    # Strip everything after | (channel names, venue names)
    local stripped
    stripped=$(echo "$raw" | sed 's/ *|.*$//')
    [[ -z "$stripped" ]] && stripped="$raw"
    # Replace & with "and" — preserves technical meaning
    stripped=$(echo "$stripped" | sed 's/ & / and /g; s/&/ and /g')
    # Remove remaining special chars, collapse spaces, convert to slug
    local slug
    slug=$(echo "$stripped" | sed 's/[^a-zA-Z0-9 ]//g' | \
                              sed 's/  */ /g' | \
                              sed 's/^ //;s/ $//' | \
                              tr ' ' '-')
    # Apply length cap if specified
    if [[ "$max" -gt 0 ]]; then
        slug=$(echo "$slug" | cut -c1-$max)
        # Trim trailing dash if cut mid-word
        slug=$(echo "$slug" | sed 's/-$//')
    fi
    echo "$slug"
}

# ── Timing Helpers ────────────────────────────────────────────
pipeline_start_ms=$(date +%s%3N)

step_start() {
    local label=$1 name=$2 vendor=$3 model=$4
    echo "" >&2
    echo "------------------------------------------------------------" >&2
    echo "[${label}] ${name}" >&2
    echo "  Model   : ${vendor}|${model}" >&2
    echo "  Started : $(date '+%Y-%m-%d %H:%M:%S')" >&2
    date +%s%3N
}

step_end() {
    local start_ms=$1 input_file=$2 output_file=$3 vendor=$4
    local end_ms duration_ms duration_s input_tokens output_tokens cost
    end_ms=$(date +%s%3N)
    duration_ms=$(( end_ms - start_ms ))
    duration_s=$(echo "scale=2; $duration_ms / 1000" | bc)
    input_tokens=$(count_tokens "$input_file")
    output_tokens=$(count_tokens "$output_file")
    cost=$(calc_cost "$vendor" "$input_tokens" "$output_tokens")
    echo "  Ended   : $(date '+%Y-%m-%d %H:%M:%S')" >&2
    echo "  Duration: ${duration_s}s (${duration_ms}ms)" >&2
    echo "  Tokens  : ${input_tokens} in -> ${output_tokens} out" >&2
    echo "  Cost    : \$${cost}" >&2
    echo "  Output  : ${output_file}" >&2
    echo "${duration_ms}|${input_tokens}|${output_tokens}|${cost}"
}

get_dur()  { echo "$1" | cut -d'|' -f1; }
get_in()   { echo "$1" | cut -d'|' -f2; }
get_out()  { echo "$1" | cut -d'|' -f3; }
get_cost() { echo "$1" | cut -d'|' -f4; }

# ── Pipeline Header ───────────────────────────────────────────
echo "============================================================"
echo "ACMS Fabric Stitching Pipeline v3"
echo "Mind Over Metadata LLC — Peter Heller"
echo "============================================================"
echo "Source      : $SOURCE_LABEL"
echo "Type        : $SOURCE_TYPE"
echo "Word limit  : $WORD_LIMIT"
echo "Run ID (ADR): $RUN_ID"
echo "Started     : $PIPELINE_START_TIME"
echo ""
echo "Model assignments:"
echo "  Step 1 extract_wisdom   : $STEP1_VENDOR|$STEP1_MODEL"
echo "  Step 2 summarize        : $STEP2_VENDOR|$STEP2_MODEL"
echo "  Step 3 extract_insights : $STEP3_VENDOR|$STEP3_MODEL"
echo "  Step 4 synthesize       : $STEP4_VENDOR|$STEP4_MODEL (word_limit=$WORD_LIMIT)"
echo "  Step 5 pandoc           : no LLM"
echo "============================================================"

# ── Step 1 — Extract Wisdom (source-aware) ───────────────────
t=$(step_start "Step 1/5" "extract_wisdom ($SOURCE_TYPE)" "$STEP1_VENDOR" "$STEP1_MODEL")

case "$SOURCE_TYPE" in
  youtube)
    fabric --youtube="$SOURCE_URL" \
           --transcript \
           --pattern ACMS_extract_wisdom \
           --model "$STEP1_MODEL" \
           --vendor "$STEP1_VENDOR" \
           --output "${STAGING}/step-01-extracted-wisdom.md"
    ;;
  file)
    cat "$SOURCE_FILE" | \
      fabric --pattern ACMS_extract_wisdom \
             --model "$STEP1_MODEL" \
             --vendor "$STEP1_VENDOR" \
             --output "${STAGING}/step-01-extracted-wisdom.md"
    ;;
  web)
    fabric --url="$SOURCE_WEB" \
           --pattern ACMS_extract_wisdom \
           --model "$STEP1_MODEL" \
           --vendor "$STEP1_VENDOR" \
           --output "${STAGING}/step-01-extracted-wisdom.md"
    ;;
  video)
    if command -v yt-dlp &>/dev/null; then
      yt-dlp --write-auto-sub --skip-download \
             --sub-format vtt \
             -o "${STAGING}/video_sub" \
             "$SOURCE_VIDEO" 2>/dev/null
      SUB_FILE=$(ls "${STAGING}/video_sub"*.vtt 2>/dev/null | head -1)
      if [[ -f "$SUB_FILE" ]]; then
        cat "$SUB_FILE" | sed "/^[0-9]*$/d;/^-->/d;/^WEBVTT/d;/^$/d" | \
          fabric --pattern ACMS_extract_wisdom \
                 --model "$STEP1_MODEL" \
                 --vendor "$STEP1_VENDOR" \
                 --output "${STAGING}/step-01-extracted-wisdom.md"
      fi
    fi
    ;;
esac
R1=$(step_end "$t" "${STAGING}/step-01-extracted-wisdom.md" \
              "${STAGING}/step-01-extracted-wisdom.md" "$STEP1_VENDOR")
DUR1=$(get_dur "$R1"); IN1=$(get_in "$R1"); OUT1=$(get_out "$R1"); COST1=$(get_cost "$R1")

# ── Step 2 — Summarize ────────────────────────────────────────
t=$(step_start "Step 2/5" "summarize" "$STEP2_VENDOR" "$STEP2_MODEL")
cat "${STAGING}/step-01-extracted-wisdom.md" | \
    fabric --pattern summarize \
           --model "$STEP2_MODEL" \
           --vendor "$STEP2_VENDOR" \
           --output "${STAGING}/step-02-summary.md"
R2=$(step_end "$t" "${STAGING}/step-01-extracted-wisdom.md" \
              "${STAGING}/step-02-summary.md" "$STEP2_VENDOR")
DUR2=$(get_dur "$R2"); IN2=$(get_in "$R2"); OUT2=$(get_out "$R2"); COST2=$(get_cost "$R2")

# ── Step 3 — Extract Insights ─────────────────────────────────
t=$(step_start "Step 3/5" "extract_insights" "$STEP3_VENDOR" "$STEP3_MODEL")
cat "${STAGING}/step-01-extracted-wisdom.md" | \
    fabric --pattern extract_insights \
           --model "$STEP3_MODEL" \
           --vendor "$STEP3_VENDOR" \
           --output "${STAGING}/step-03-insights.md"
R3=$(step_end "$t" "${STAGING}/step-01-extracted-wisdom.md" \
              "${STAGING}/step-03-insights.md" "$STEP3_VENDOR")
DUR3=$(get_dur "$R3"); IN3=$(get_in "$R3"); OUT3=$(get_out "$R3"); COST3=$(get_cost "$R3")

# ── Step 4 — Synthesize Narrative ────────────────────────────
t=$(step_start "Step 4/5" "synthesize_eloquent_narrative" "$STEP4_VENDOR" "$STEP4_MODEL")

# Combine all prior outputs — wisdom + summary + insights
{
  echo "word_limit=${WORD_LIMIT}"
  echo ""
  echo "## Extracted Wisdom"
  cat "${STAGING}/step-01-extracted-wisdom.md"
  echo ""
  echo "## Summary"
  cat "${STAGING}/step-02-summary.md"
  echo ""
  echo "## Insights"
  cat "${STAGING}/step-03-insights.md"
} > "${STAGING}/step-05-combined-for-synthesis.md"

fabric --pattern synthesize_eloquent_narrative_from_wisdom \
       --model "$STEP4_MODEL" \
       --vendor "$STEP4_VENDOR" \
       < "${STAGING}/step-05-combined-for-synthesis.md" \
       --output "${STAGING}/step-04-narrative.md"
R4=$(step_end "$t" "${STAGING}/step-05-combined-for-synthesis.md" \
              "${STAGING}/step-04-narrative.md" "$STEP4_VENDOR")
DUR4=$(get_dur "$R4"); IN4=$(get_in "$R4"); OUT4=$(get_out "$R4"); COST4=$(get_cost "$R4")

# ── Extract title — prefer YouTube title over narrative H1 ────
RAW_TITLE=$(get_source_title "$SOURCE_TYPE" "${SOURCE_URL}${SOURCE_FILE}${SOURCE_WEB}${SOURCE_VIDEO}")
if [[ -z "$RAW_TITLE" ]]; then
    RAW_TITLE=$(extract_title "${STAGING}/step-04-narrative.md")
fi
[[ -z "$RAW_TITLE" ]] && RAW_TITLE="Untitled-$(date +%H%M%S)"
# Folder slug — no cap, preserves full title meaning
FOLDER_SLUG=$(title_to_slug "$RAW_TITLE" 0)
FOLDER_NAME="${TODAY}-${FOLDER_SLUG}"
FINAL_DIR="${OUTPUT_BASE}/${YEAR}/${MONTH}/${DAY}/${FOLDER_NAME}"
mkdir -p "$FINAL_DIR"

echo ""
echo "  Title   : $RAW_TITLE"
echo "  Folder  : $FINAL_DIR"

# Move step files to final directory
mv "${STAGING}/step-01-extracted-wisdom.md"       "${FINAL_DIR}/step-01-extracted-wisdom.md"
mv "${STAGING}/step-02-summary.md"                "${FINAL_DIR}/step-02-summary.md"
mv "${STAGING}/step-03-insights.md"               "${FINAL_DIR}/step-03-insights.md"
mv "${STAGING}/step-04-narrative.md"              "${FINAL_DIR}/step-04-narrative.md"
mv "${STAGING}/step-05-combined-for-synthesis.md" "${FINAL_DIR}/step-05-combined-for-synthesis.md"
rmdir "$STAGING" 2>/dev/null || true

# File slug — no cap, full title preserved
FILE_SLUG=$(title_to_slug "$RAW_TITLE" 0)
# Named base for output files: Title-YYYYMMDD-[uuidv7]
FILE_BASE="${FILE_SLUG}-${TODAY}-${RUN_ID}"

# Build full report: narrative + appendix
REPORT_MD="${FINAL_DIR}/${FILE_BASE}.md"
{
  cat "${FINAL_DIR}/step-04-narrative.md"
  echo ""
  echo "---"
  echo ""
  echo "## Appendix: Raw Extractions"
  echo ""
  echo "### Step 1 — Extracted Wisdom"
  cat "${FINAL_DIR}/step-01-extracted-wisdom.md"
  echo ""
  echo "### Step 2 — Summary"
  cat "${FINAL_DIR}/step-02-summary.md"
  echo ""
  echo "### Step 3 — Insights"
  cat "${FINAL_DIR}/step-03-insights.md"
} > "$REPORT_MD"

# ── Step 5 — Pandoc Output Generation ─────────────────────────
t=$(step_start "Step 5/5" "pandoc conversion" "none" "no LLM")

pandoc "$REPORT_MD" \
       -o "${FINAL_DIR}/${FILE_BASE}.pdf" \
       --pdf-engine=xelatex \
       -V geometry:margin=1in \
       --metadata title="$RAW_TITLE" \
       && echo "  Done: ${FILE_BASE}.pdf" || echo "  Failed: ${FILE_BASE}.pdf"

pandoc "$REPORT_MD" \
       -o "${FINAL_DIR}/${FILE_BASE}.docx" \
       --metadata title="$RAW_TITLE" \
       && echo "  Done: ${FILE_BASE}.docx"

# Copy docx to Windows and launch Word
mkdir -p "$WIN_OUTPUT_DIR"
WIN_FILE="${WIN_OUTPUT_DIR}/${FILE_BASE}.docx"
cp "${FINAL_DIR}/${FILE_BASE}.docx" "$WIN_FILE" 2>/dev/null && {
    WIN_PATH=$(wslpath -w "$WIN_FILE" 2>/dev/null || echo "$WIN_FILE")
    echo "  ✓ Windows copy: $WIN_PATH"
    cmd.exe /c start winword.exe "$WIN_PATH" 2>/dev/null && \
        echo "  ✓ Word launched" || \
        echo "  ⚠ Word launch failed — open manually: $WIN_PATH"
}

pandoc "$REPORT_MD" \
       -o "${FINAL_DIR}/${FILE_BASE}.html" \
       --standalone \
       --metadata title="$RAW_TITLE" \
       && echo "  Done: ${FILE_BASE}.html"

R5=$(step_end "$t" "$REPORT_MD" "$REPORT_MD" "none")
DUR5=$(get_dur "$R5")

# ── Grand Total ───────────────────────────────────────────────
pipeline_end_ms=$(date +%s%3N)
pipeline_ms=$(( pipeline_end_ms - pipeline_start_ms ))
pipeline_s=$(echo "scale=2; $pipeline_ms / 1000" | bc)
total_in=$(( IN1 + IN2 + IN3 + IN4 ))
total_out=$(( OUT1 + OUT2 + OUT3 + OUT4 ))
total_cost=$("$UV_PYTHON" -c "
costs = ['${COST1}','${COST2}','${COST3}','${COST4}']
total = sum(float(c) for c in costs)
print(f'{total:.6f}')
" 2>/dev/null || echo "0.000000")

WORD_COUNT=$("$UV_PYTHON" -c "
text = open('${FINAL_DIR}/step-04-narrative.md').read()
print(len(text.split()))
" 2>/dev/null || echo "0")

# ── manifest.json — plain English self-documenting record ─────
cat > "${FINAL_DIR}/manifest.json" << MANIFEST
{
  "title": "${RAW_TITLE}",
  "source_url": "${SOURCE_LABEL}",
  "created_date": "$(date '+%Y-%m-%d')",
  "created_time": "$(date '+%H:%M:%S')",

  "pipeline_run_id": "${RUN_ID}",
  "pipeline_run_id_explanation": "Architectural Decision Record (ADR) identifier — this ID links every file in this folder to the cost audit trail in cost_audit.log. Search for this ID to trace every token spent, every model used, and every decision made during this pipeline run.",
  "governance_standard": "ADR-009 — ACMS Cost Audit Format (16-field pipe-delimited log)",

  "word_limit_requested": ${WORD_LIMIT},
  "word_count_produced": ${WORD_COUNT},
  "total_cost_usd": ${total_cost},
  "duration_seconds": $(echo "scale=1; $pipeline_ms / 1000" | bc),

  "pipeline_steps": {
    "step_01_extract_wisdom": {
      "description": "Extract structured wisdom, ideas, quotes, habits, and recommendations from source",
      "model": "${STEP1_VENDOR} ${STEP1_MODEL}",
      "input_tokens": ${IN1},
      "output_tokens": ${OUT1},
      "cost_usd": ${COST1},
      "duration_ms": ${DUR1},
      "output_file": "step-01-extracted-wisdom.md"
    },
    "step_02_summarize": {
      "description": "Distill key points into a concise structured summary",
      "model": "${STEP2_VENDOR} ${STEP2_MODEL}",
      "input_tokens": ${IN2},
      "output_tokens": ${OUT2},
      "cost_usd": ${COST2},
      "duration_ms": ${DUR2},
      "output_file": "step-02-summary.md"
    },
    "step_03_extract_insights": {
      "description": "Pull deeper analytical insights and connections from the wisdom",
      "model": "${STEP3_VENDOR} ${STEP3_MODEL}",
      "input_tokens": ${IN3},
      "output_tokens": ${OUT3},
      "cost_usd": ${COST3},
      "duration_ms": ${DUR3},
      "output_file": "step-03-insights.md"
    },
    "step_04_synthesize_narrative": {
      "description": "Synthesize all prior steps into a polished long-form narrative article",
      "model": "${STEP4_VENDOR} ${STEP4_MODEL}",
      "input_tokens": ${IN4},
      "output_tokens": ${OUT4},
      "cost_usd": ${COST4},
      "duration_ms": ${DUR4},
      "output_file": "step-04-narrative.md",
      "word_limit": ${WORD_LIMIT},
      "word_count": ${WORD_COUNT}
    },
    "step_05_document_generation": {
      "description": "Convert narrative to Word, PDF, and HTML via pandoc (no AI used)",
      "model": "pandoc (no AI)",
      "cost_usd": 0.000000,
      "duration_ms": ${DUR5},
      "output_files": [
        "step-05-combined-for-synthesis.md",
        "${FILE_BASE}.md",
        "${FILE_BASE}.docx",
        "${FILE_BASE}.pdf",
        "${FILE_BASE}.html"
      ]
    }
  },

  "output_folder": "${FINAL_DIR}",
  "windows_copy": "${WIN_FILE}"
}
MANIFEST

echo ""
echo "============================================================"
echo "ACMS PIPELINE COMPLETION REPORT"
echo "============================================================"
printf "  %-5s %-24s %-30s %8s %8s %8s %12s\n" \
    "Step" "Pattern" "Vendor|Model" "ms" "In" "Out" "Cost"
echo "  -------------------------------------------------------------------------------"
printf "  %-5s %-24s %-30s %8s %8s %8s %12s\n" \
    "1" "extract_wisdom" "${STEP1_VENDOR}|${STEP1_MODEL}" \
    "$DUR1" "$IN1" "$OUT1" "\$${COST1}"
printf "  %-5s %-24s %-30s %8s %8s %8s %12s\n" \
    "2" "summarize" "${STEP2_VENDOR}|${STEP2_MODEL}" \
    "$DUR2" "$IN2" "$OUT2" "\$${COST2}"
printf "  %-5s %-24s %-30s %8s %8s %8s %12s\n" \
    "3" "extract_insights" "${STEP3_VENDOR}|${STEP3_MODEL}" \
    "$DUR3" "$IN3" "$OUT3" "\$${COST3}"
printf "  %-5s %-24s %-30s %8s %8s %8s %12s\n" \
    "4" "synthesize" "${STEP4_VENDOR}|${STEP4_MODEL}" \
    "$DUR4" "$IN4" "$OUT4" "\$${COST4}"
printf "  %-5s %-24s %-30s %8s %8s %8s %12s\n" \
    "5" "pandoc" "no LLM" \
    "$DUR5" "-" "-" "-"
echo "  -------------------------------------------------------------------------------"
printf "  %-5s %-24s %-30s %8s %8s %8s %12s\n" \
    "TOT" "" "" \
    "$pipeline_ms" "$total_in" "$total_out" "\$${total_cost}"
echo ""
echo "  Title              : $RAW_TITLE"
echo "  Word count         : $WORD_COUNT (requested: $WORD_LIMIT)"
echo "  Pipeline wall time : ${pipeline_s}s (${pipeline_ms}ms)"
echo "  Completed          : $(date '+%Y-%m-%d %H:%M:%S')"
echo "  Output folder      : $FINAL_DIR"
echo "  Run ID (ADR)       : $RUN_ID"
echo "============================================================"
ls -lh "$FINAL_DIR"

# ── Write to cost_audit.log (ADR-009 format) ─────────────────
COST_LOG="$HOME/.config/fabric/cost_audit.log"
TIMESTAMP_NOW=$(date '+%Y-%m-%dT%H:%M:%S')
for entry in \
  "${TIMESTAMP_NOW}|fabric_stitch|${RUN_ID}|CodingArchitecture/FabricStitch/ACMS_extract_wisdom|fabric_stitch.step_1|${STEP1_VENDOR}|${STEP1_MODEL}|${IN1}|${OUT1}|0|0|${COST1}|${DUR1}|dev|${RUN_ID}|extract_wisdom" \
  "${TIMESTAMP_NOW}|fabric_stitch|${RUN_ID}|CodingArchitecture/FabricStitch/ACMS_extract_wisdom|fabric_stitch.step_2|${STEP2_VENDOR}|${STEP2_MODEL}|${IN2}|${OUT2}|0|0|${COST2}|${DUR2}|dev|${RUN_ID}|summarize" \
  "${TIMESTAMP_NOW}|fabric_stitch|${RUN_ID}|CodingArchitecture/FabricStitch/ACMS_extract_wisdom|fabric_stitch.step_3|${STEP3_VENDOR}|${STEP3_MODEL}|${IN3}|${OUT3}|0|0|${COST3}|${DUR3}|dev|${RUN_ID}|extract_insights" \
  "${TIMESTAMP_NOW}|fabric_stitch|${RUN_ID}|CodingArchitecture/FabricStitch/ACMS_extract_wisdom|fabric_stitch.step_4|${STEP4_VENDOR}|${STEP4_MODEL}|${IN4}|${OUT4}|0|0|${COST4}|${DUR4}|dev|${RUN_ID}|synthesize_narrative" \
  "${TIMESTAMP_NOW}|fabric_stitch|${RUN_ID}|CodingArchitecture/FabricStitch/ACMS_extract_wisdom|session.total|all|all|${total_in}|${total_out}|0|0|${total_cost}|${pipeline_ms}|dev|${RUN_ID}|pipeline_complete"
do
  echo "$entry" >> "$COST_LOG"
done
echo ""
echo "  Architectural Decision Record (ADR) cost entries written to: $COST_LOG"
echo "  Search Run ID: $RUN_ID"
