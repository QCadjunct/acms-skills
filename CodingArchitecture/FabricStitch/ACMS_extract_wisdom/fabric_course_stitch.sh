#!/bin/bash
# ============================================================
# ACMS BASH Agent — Course FabricStitch Pipeline v1
# Mind Over Metadata LLC — Peter Heller
# skill: CodingArchitecture/FabricStitch/ACMS_extract_wisdom
#
# Purpose:
#   Process web articles into step-by-step guides.
#   Outputs repo markdown and Obsidian markdown only.
#   No pandoc. No docx. No PDF. No Windows copy.
#   Pandoc rendering is handled by a separate stitch.
#
# Usage:
#   ./fabric_course_stitch.sh --web <article_url> [--word-limit N] [--output-dir DIR]
#   ./fabric_course_stitch.sh --file <path/to/file> [--word-limit N]
#
# Examples:
#   ./fabric_course_stitch.sh --web "https://www.dailydoseofds.com/ai-agents-crash-course-part-1/"
#   ./fabric_course_stitch.sh --web "https://..." --word-limit 3000
#   ./fabric_course_stitch.sh --file ~/Documents/article.md --word-limit 2000
#
# Output structure:
#   output/YYYY/MM/DD/YYYYMMDD-Title-Slug/
#     step-01-extracted-wisdom.md
#     step-02-summary.md
#     step-03-insights.md
#     step-04-guide-draft.md
#     step-05-combined-for-synthesis.md
#     Title-YYYYMMDD-[uuidv7].md              ← repo markdown
#     Title-YYYYMMDD-[uuidv7]-obsidian.md     ← obsidian markdown
#     manifest.json
# ============================================================

set -euo pipefail

# ── Argument Parsing ──────────────────────────────────────────
SOURCE_WEB=""
SOURCE_FILE=""
SOURCE_TYPE=""
WORD_LIMIT=2000
OUTPUT_BASE="$HOME/projects/aces-skills/FabricStitch/output"
UV_PYTHON="$HOME/projects/aces-skills/.venv/bin/python3"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --web)         SOURCE_WEB="$2";   SOURCE_TYPE="web";  shift 2 ;;
    --file)        SOURCE_FILE="$2";  SOURCE_TYPE="file"; shift 2 ;;
    --word-limit)  WORD_LIMIT="$2";   shift 2 ;;
    --output-dir)  OUTPUT_BASE="$2";  shift 2 ;;
    *)             echo "Unknown flag: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$SOURCE_TYPE" ]]; then
  echo ""
  echo "ERROR: Input source required"
  echo ""
  echo "  --web   <article_url>   Web article"
  echo "  --file  <path>          Local file (.md .txt .html)"
  echo ""
  echo "Optional:"
  echo "  --word-limit N          Target word count (default: 2000)"
  echo "  --output-dir DIR        Output base directory"
  echo ""
  exit 1
fi

[[ "$SOURCE_TYPE" == "file" && ! -f "$SOURCE_FILE" ]] && {
  echo "ERROR: File not found: $SOURCE_FILE" >&2; exit 1
}

SOURCE_LABEL="${SOURCE_WEB}${SOURCE_FILE}"

# ── UUIDv7 Generator ──────────────────────────────────────────
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

# ── Title helpers ─────────────────────────────────────────────
get_web_title() {
  local url=$1
  local title=""
  if command -v yt-dlp &>/dev/null; then
    title=$(yt-dlp --get-title "$url" 2>/dev/null | head -1)
  fi
  if [[ -z "$title" ]]; then
    title=$(curl -sL --max-time 10 "$url" 2>/dev/null | \
      grep -o '<title>[^<]*</title>' | \
      sed "s/<[^>]*>//g" | head -1 | \
      sed "s/ *[-|].*$//")
  fi
  echo "$title"
}

title_to_slug() {
  local raw="$1"
  local max="${2:-0}"
  local stripped
  stripped=$(echo "$raw" | sed 's/ *|.*$//')
  [[ -z "$stripped" ]] && stripped="$raw"
  stripped=$(echo "$stripped" | sed 's/ & / and /g; s/&/ and /g')
  local slug
  slug=$(echo "$stripped" | sed 's/[^a-zA-Z0-9 ]//g' | \
                            sed 's/  */ /g' | \
                            sed 's/^ //;s/ $//' | \
                            tr ' ' '-')
  if [[ "$max" -gt 0 ]]; then
    slug=$(echo "$slug" | cut -c1-$max | sed 's/-$//')
  fi
  echo "$slug"
}

# ── Token Counter ─────────────────────────────────────────────
count_tokens() {
  local file=$1
  [[ ! -f "$file" ]] && echo "0" && return
  "$UV_PYTHON" -c "
import tiktoken
enc = tiktoken.get_encoding('cl100k_base')
text = open('$file', 'r', errors='replace').read()
print(len(enc.encode(text)))
" 2>/dev/null || echo "0"
}

# ── Cost Calculator ───────────────────────────────────────────
declare -A INPUT_RATE=(["Gemini"]="0.075" ["Anthropic"]="3.00" ["Ollama"]="0.00")
declare -A OUTPUT_RATE=(["Gemini"]="0.30" ["Anthropic"]="15.00" ["Ollama"]="0.00")

calc_cost() {
  local vendor=$1 in_tok=$2 out_tok=$3
  local in_rate=${INPUT_RATE[$vendor]:-"0.00"}
  local out_rate=${OUTPUT_RATE[$vendor]:-"0.00"}
  "$UV_PYTHON" -c "
print(f'{($in_tok/1_000_000)*$in_rate + ($out_tok/1_000_000)*$out_rate:.6f}')
" 2>/dev/null || echo "0.000000"
}

# ── Timing ────────────────────────────────────────────────────
pipeline_start_ms=$(date +%s%3N)

step_start() {
  echo "" >&2
  echo "------------------------------------------------------------" >&2
  echo "[$1] $2" >&2
  echo "  Model   : $3|$4" >&2
  echo "  Started : $(date '+%Y-%m-%d %H:%M:%S')" >&2
  date +%s%3N
}

step_end() {
  local start_ms=$1 in_file=$2 out_file=$3 vendor=$4
  local end_ms dur_ms in_tok out_tok cost
  end_ms=$(date +%s%3N)
  dur_ms=$(( end_ms - start_ms ))
  in_tok=$(count_tokens "$in_file")
  out_tok=$(count_tokens "$out_file")
  cost=$(calc_cost "$vendor" "$in_tok" "$out_tok")
  echo "  Ended   : $(date '+%Y-%m-%d %H:%M:%S')" >&2
  echo "  Duration: $(echo "scale=2; $dur_ms/1000" | bc)s" >&2
  echo "  Tokens  : $in_tok in → $out_tok out" >&2
  echo "  Cost    : \$$cost" >&2
  echo "${dur_ms}|${in_tok}|${out_tok}|${cost}"
}

get_dur()  { echo "$1" | cut -d'|' -f1; }
get_in()   { echo "$1" | cut -d'|' -f2; }
get_out()  { echo "$1" | cut -d'|' -f3; }
get_cost() { echo "$1" | cut -d'|' -f4; }

# ── Model Config ──────────────────────────────────────────────
STEP1_MODEL="gemini-2.5-flash"; STEP1_VENDOR="Gemini"
STEP2_MODEL="claude-sonnet-4-5"; STEP2_VENDOR="Anthropic"
STEP3_MODEL="gemini-2.5-flash"; STEP3_VENDOR="Gemini"
STEP4_MODEL="claude-sonnet-4-5"; STEP4_VENDOR="Anthropic"
SYNTHESIS_PATTERN="synthesize_stepbystep_guide_from_wisdom"

# ── Setup ─────────────────────────────────────────────────────
TODAY=$(date +%Y%m%d)
YEAR=$(date +%Y)
MONTH=$(date +%m)
DAY=$(date +%d)
RUN_ID=$(generate_uuidv7)
STAGING="${OUTPUT_BASE}/.staging_${RUN_ID}"
mkdir -p "$STAGING"

# ── Header ────────────────────────────────────────────────────
echo "============================================================"
echo "ACMS Course FabricStitch Pipeline v1"
echo "Mind Over Metadata LLC — Peter Heller"
echo "============================================================"
echo "Source      : $SOURCE_LABEL"
echo "Type        : $SOURCE_TYPE"
echo "Word limit  : $WORD_LIMIT"
echo "Pattern     : $SYNTHESIS_PATTERN"
echo "Run ID (ADR): $RUN_ID"
echo "Started     : $(date '+%Y-%m-%d %H:%M:%S')"
echo ""
echo "Model assignments:"
echo "  Step 1 extract_wisdom : $STEP1_VENDOR|$STEP1_MODEL"
echo "  Step 2 summarize      : $STEP2_VENDOR|$STEP2_MODEL"
echo "  Step 3 insights       : $STEP3_VENDOR|$STEP3_MODEL"
echo "  Step 4 guide          : $STEP4_VENDOR|$STEP4_MODEL (word_limit=$WORD_LIMIT)"
echo "  Step 5 render         : markdown only (no LLM)"
echo "============================================================"

# ── Step 1 — Extract Wisdom ───────────────────────────────────
t=$(step_start "Step 1/5" "ACMS_extract_wisdom" "$STEP1_VENDOR" "$STEP1_MODEL")

case "$SOURCE_TYPE" in
  web)
    curl -sL --max-time 30 "$SOURCE_WEB" 2>/dev/null | \
      fabric --pattern ACMS_extract_wisdom \
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

# ── Step 4 — Synthesize Guide ─────────────────────────────────
t=$(step_start "Step 4/5" "$SYNTHESIS_PATTERN" "$STEP4_VENDOR" "$STEP4_MODEL")
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

fabric --pattern "$SYNTHESIS_PATTERN" \
       --model "$STEP4_MODEL" \
       --vendor "$STEP4_VENDOR" \
       < "${STAGING}/step-05-combined-for-synthesis.md" \
       --output "${STAGING}/step-04-guide-draft.md"
R4=$(step_end "$t" "${STAGING}/step-05-combined-for-synthesis.md" \
              "${STAGING}/step-04-guide-draft.md" "$STEP4_VENDOR")
DUR4=$(get_dur "$R4"); IN4=$(get_in "$R4"); OUT4=$(get_out "$R4"); COST4=$(get_cost "$R4")

# ── Extract title — build final output directory ──────────────
if [[ "$SOURCE_TYPE" == "web" ]]; then
  RAW_TITLE=$(get_web_title "$SOURCE_WEB")
fi
if [[ -z "${RAW_TITLE:-}" ]]; then
  RAW_TITLE=$(grep -m1 '^# ' "${STAGING}/step-04-guide-draft.md" 2>/dev/null | sed 's/^# //' || echo "Untitled")
fi
[[ -z "$RAW_TITLE" ]] && RAW_TITLE="Untitled-$(date +%H%M%S)"

FOLDER_SLUG=$(title_to_slug "$RAW_TITLE" 0)
FILE_SLUG=$(title_to_slug "$RAW_TITLE" 0)
FOLDER_NAME="${TODAY}-${FOLDER_SLUG}"
FINAL_DIR="${OUTPUT_BASE}/${YEAR}/${MONTH}/${DAY}/${FOLDER_NAME}"
FILE_BASE="${FILE_SLUG}-${TODAY}-${RUN_ID}"
mkdir -p "$FINAL_DIR"

echo ""
echo "  Title  : $RAW_TITLE"
echo "  Folder : $FINAL_DIR"

# Move step files
mv "${STAGING}/step-01-extracted-wisdom.md"       "${FINAL_DIR}/step-01-extracted-wisdom.md"
mv "${STAGING}/step-02-summary.md"                "${FINAL_DIR}/step-02-summary.md"
mv "${STAGING}/step-03-insights.md"               "${FINAL_DIR}/step-03-insights.md"
mv "${STAGING}/step-04-guide-draft.md"            "${FINAL_DIR}/step-04-guide-draft.md"
mv "${STAGING}/step-05-combined-for-synthesis.md" "${FINAL_DIR}/step-05-combined-for-synthesis.md"
rmdir "$STAGING" 2>/dev/null || true

# ── Step 5 — Render Markdown (no LLM) ────────────────────────
t=$(step_start "Step 5/5" "render markdown" "none" "no LLM")

REPO_FILE="${FINAL_DIR}/${FILE_BASE}.md"
OBS_FILE="${FINAL_DIR}/${FILE_BASE}-obsidian.md"

# Repo markdown — clean, GitHub-ready
{
  echo "> **Source**: ${SOURCE_LABEL}"
  echo "> *Synthesized: $(date '+%Y-%m-%d') — ACMS FabricStitch — Mind Over Metadata LLC*"
  echo "> *Pipeline Run ID (ADR): \`${RUN_ID}\`*"
  echo ""
  echo "---"
  echo ""
  cat "${FINAL_DIR}/step-04-guide-draft.md"
} > "$REPO_FILE"
echo "  ✓ Repo     : ${FILE_BASE}.md"

# Obsidian markdown — frontmatter + wikilinks
{
  echo "---"
  echo "title: \"${RAW_TITLE}\""
  echo "date: $(date '+%Y-%m-%d')"
  echo "source: \"${SOURCE_LABEL}\""
  echo "pipeline_run_id: \"${RUN_ID}\""
  echo "tags:"
  echo "  - guide"
  echo "  - agentic"
  echo "---"
  echo ""
  echo "> **Source**: ${SOURCE_LABEL}"
  echo "> **Synthesized**: $(date '+%Y-%m-%d') — [[ACMS-FabricStitch-Pipeline|ACMS FabricStitch]]"
  echo "> **ADR Run ID**: \`${RUN_ID}\` — search in [[cost-audit-log|cost_audit.log]]"
  echo ""
  echo "---"
  echo ""
  cat "${FINAL_DIR}/step-04-guide-draft.md"
} > "$OBS_FILE"
echo "  ✓ Obsidian : ${FILE_BASE}-obsidian.md"

R5=$(step_end "$t" "$REPO_FILE" "$REPO_FILE" "none")
DUR5=$(get_dur "$R5")

# ── Grand Total ───────────────────────────────────────────────
pipeline_end_ms=$(date +%s%3N)
pipeline_ms=$(( pipeline_end_ms - pipeline_start_ms ))
pipeline_s=$(echo "scale=2; $pipeline_ms/1000" | bc)
total_in=$(( IN1 + IN2 + IN3 + IN4 ))
total_out=$(( OUT1 + OUT2 + OUT3 + OUT4 ))
total_cost=$("$UV_PYTHON" -c "
costs=['${COST1}','${COST2}','${COST3}','${COST4}']
print(f'{sum(float(c) for c in costs):.6f}')
" 2>/dev/null || echo "0.000000")

WORD_COUNT=$("$UV_PYTHON" -c "
print(len(open('${FINAL_DIR}/step-04-guide-draft.md').read().split()))
" 2>/dev/null || echo "0")

# ── manifest.json ─────────────────────────────────────────────
cat > "${FINAL_DIR}/manifest.json" << MANIFEST
{
  "title": "${RAW_TITLE}",
  "source_url": "${SOURCE_LABEL}",
  "created_date": "$(date '+%Y-%m-%d')",
  "created_time": "$(date '+%H:%M:%S')",
  "pipeline_run_id": "${RUN_ID}",
  "pipeline_run_id_explanation": "Architectural Decision Record (ADR) identifier — search this ID in cost_audit.log to trace every token spent and every decision made during this pipeline run.",
  "governance_standard": "ADR-009 — ACMS Cost Audit Format",
  "word_limit_requested": ${WORD_LIMIT},
  "word_count_produced": ${WORD_COUNT},
  "total_cost_usd": ${total_cost},
  "duration_seconds": $(echo "scale=1; $pipeline_ms/1000" | bc),
  "output_files": [
    "${FILE_BASE}.md",
    "${FILE_BASE}-obsidian.md"
  ],
  "pipeline_steps": {
    "step_01_extract_wisdom": { "model": "${STEP1_VENDOR} ${STEP1_MODEL}", "tokens_in": ${IN1}, "tokens_out": ${OUT1}, "cost_usd": ${COST1}, "duration_ms": ${DUR1} },
    "step_02_summarize":      { "model": "${STEP2_VENDOR} ${STEP2_MODEL}", "tokens_in": ${IN2}, "tokens_out": ${OUT2}, "cost_usd": ${COST2}, "duration_ms": ${DUR2} },
    "step_03_insights":       { "model": "${STEP3_VENDOR} ${STEP3_MODEL}", "tokens_in": ${IN3}, "tokens_out": ${OUT3}, "cost_usd": ${COST3}, "duration_ms": ${DUR3} },
    "step_04_guide":          { "model": "${STEP4_VENDOR} ${STEP4_MODEL}", "tokens_in": ${IN4}, "tokens_out": ${OUT4}, "cost_usd": ${COST4}, "duration_ms": ${DUR4}, "pattern": "${SYNTHESIS_PATTERN}", "word_limit": ${WORD_LIMIT} },
    "step_05_render":         { "model": "no LLM", "cost_usd": 0, "duration_ms": ${DUR5}, "outputs": ["repo.md", "obsidian.md"] }
  }
}
MANIFEST

# ── Completion Report ─────────────────────────────────────────
echo ""
echo "============================================================"
echo "ACMS COURSE PIPELINE — COMPLETE"
echo "============================================================"
printf "  %-5s %-24s %-28s %8s %8s %8s %12s\n" \
    "Step" "Pattern" "Vendor|Model" "ms" "In" "Out" "Cost"
echo "  -----------------------------------------------------------------------"
printf "  %-5s %-24s %-28s %8s %8s %8s %12s\n" \
    "1" "extract_wisdom" "${STEP1_VENDOR}|${STEP1_MODEL}" "$DUR1" "$IN1" "$OUT1" "\$${COST1}"
printf "  %-5s %-24s %-28s %8s %8s %8s %12s\n" \
    "2" "summarize" "${STEP2_VENDOR}|${STEP2_MODEL}" "$DUR2" "$IN2" "$OUT2" "\$${COST2}"
printf "  %-5s %-24s %-28s %8s %8s %8s %12s\n" \
    "3" "extract_insights" "${STEP3_VENDOR}|${STEP3_MODEL}" "$DUR3" "$IN3" "$OUT3" "\$${COST3}"
printf "  %-5s %-24s %-28s %8s %8s %8s %12s\n" \
    "4" "guide" "${STEP4_VENDOR}|${STEP4_MODEL}" "$DUR4" "$IN4" "$OUT4" "\$${COST4}"
printf "  %-5s %-24s %-28s %8s %8s %8s %12s\n" \
    "5" "render" "no LLM" "$DUR5" "-" "-" "-"
echo "  -----------------------------------------------------------------------"
printf "  %-5s %-24s %-28s %8s %8s %8s %12s\n" \
    "TOT" "" "" "$pipeline_ms" "$total_in" "$total_out" "\$${total_cost}"
echo ""
echo "  Title      : $RAW_TITLE"
echo "  Words      : $WORD_COUNT (requested: $WORD_LIMIT)"
echo "  Wall time  : ${pipeline_s}s"
echo "  Completed  : $(date '+%Y-%m-%d %H:%M:%S')"
echo "  Output     : $FINAL_DIR"
echo "  Run ID     : $RUN_ID"
echo "============================================================"
ls -lh "$FINAL_DIR"

# ── ADR-009 cost audit entries ────────────────────────────────
COST_LOG="$HOME/.config/fabric/cost_audit.log"
TS=$(date '+%Y-%m-%dT%H:%M:%S')
for entry in \
  "${TS}|fabric_course_stitch|${RUN_ID}|CodingArchitecture/FabricStitch/ACMS_extract_wisdom|step_1|${STEP1_VENDOR}|${STEP1_MODEL}|${IN1}|${OUT1}|0|0|${COST1}|${DUR1}|dev|${RUN_ID}|extract_wisdom" \
  "${TS}|fabric_course_stitch|${RUN_ID}|CodingArchitecture/FabricStitch/ACMS_extract_wisdom|step_2|${STEP2_VENDOR}|${STEP2_MODEL}|${IN2}|${OUT2}|0|0|${COST2}|${DUR2}|dev|${RUN_ID}|summarize" \
  "${TS}|fabric_course_stitch|${RUN_ID}|CodingArchitecture/FabricStitch/ACMS_extract_wisdom|step_3|${STEP3_VENDOR}|${STEP3_MODEL}|${IN3}|${OUT3}|0|0|${COST3}|${DUR3}|dev|${RUN_ID}|extract_insights" \
  "${TS}|fabric_course_stitch|${RUN_ID}|CodingArchitecture/FabricStitch/ACMS_extract_wisdom|step_4|${STEP4_VENDOR}|${STEP4_MODEL}|${IN4}|${OUT4}|0|0|${COST4}|${DUR4}|dev|${RUN_ID}|${SYNTHESIS_PATTERN}" \
  "${TS}|fabric_course_stitch|${RUN_ID}|CodingArchitecture/FabricStitch/ACMS_extract_wisdom|session.total|all|all|${total_in}|${total_out}|0|0|${total_cost}|${pipeline_ms}|dev|${RUN_ID}|pipeline_complete"
do
  echo "$entry" >> "$COST_LOG"
done
echo ""
echo "  Architectural Decision Record (ADR) entries → $COST_LOG"
echo "  Search Run ID: $RUN_ID"
