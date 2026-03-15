#!/bin/bash
# ============================================================
# ACMS BASH Agent — Fabric Stitching Pipeline v2
# Mind Over Metadata LLC — Peter Heller
# skill: CodingArchitecture/FabricStitch/bash.cli/
#
# Usage: ./fabric_stitch.sh <youtube_url> [output_dir]
# Examples:
#   ./fabric_stitch.sh "https://youtube.com/watch?v=xxx"
#   ./fabric_stitch.sh "https://youtube.com/watch?v=xxx" ~/my_output
# ============================================================

URL=${1:?"ERROR: YouTube URL required as first argument"}
OUTPUT_DIR=${2:-"$HOME/projects/acms-skills/FabricStitch/output"}
WIN_OUTPUT_DIR="/mnt/c/Users/pheller/Documents/ACMS-Output"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BASE="${OUTPUT_DIR}/${TIMESTAMP}"
AUDIT_LOG="$HOME/projects/acms-skills/FabricStitch/audit.log"
UV_PYTHON="$HOME/projects/acms-skills/.venv/bin/python3"

mkdir -p "$BASE"

# ── Multi-Model Configuration ─────────────────────────────────
STEP1_MODEL="gemini-2.0-flash";         STEP1_VENDOR="Gemini"
STEP2_MODEL="claude-sonnet-4-6";        STEP2_VENDOR="Anthropic"
STEP3_MODEL="gemini-2.0-flash";         STEP3_VENDOR="Gemini"
STEP4_MODEL="gemma3:12b";               STEP4_VENDOR="Ollama"

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
    local vendor=$1
    local input_tokens=$2
    local output_tokens=$3
    local in_rate=${INPUT_RATE[$vendor]:-"0.00"}
    local out_rate=${OUTPUT_RATE[$vendor]:-"0.00"}
    "$UV_PYTHON" -c "
in_cost  = ($input_tokens  / 1_000_000) * $in_rate
out_cost = ($output_tokens / 1_000_000) * $out_rate
print(f'{in_cost + out_cost:.6f}')
" 2>/dev/null || echo "0.000000"
}

# ── Timing Helpers ────────────────────────────────────────────
pipeline_start=$(date +%s%3N)

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
    local start_ms=$1
    local input_file=$2
    local output_file=$3
    local vendor=$4
    local end_ms duration_ms duration_s
    local input_tokens output_tokens cost

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

# ── Parse step_end result ─────────────────────────────────────
get_dur()  { echo "$1" | cut -d'|' -f1; }
get_in()   { echo "$1" | cut -d'|' -f2; }
get_out()  { echo "$1" | cut -d'|' -f3; }
get_cost() { echo "$1" | cut -d'|' -f4; }

# ── Pipeline Header ───────────────────────────────────────────
echo "============================================================"
echo "ACMS Fabric Stitching Pipeline v2"
echo "Mind Over Metadata LLC — Peter Heller"
echo "============================================================"
echo "URL        : $URL"
echo "Output     : $BASE"
echo "Started    : $(date '+%Y-%m-%d %H:%M:%S')"
echo ""
echo "Model assignments:"
echo "  Step 1 extract_wisdom   : $STEP1_VENDOR|$STEP1_MODEL"
echo "  Step 2 summarize        : $STEP2_VENDOR|$STEP2_MODEL"
echo "  Step 3 extract_insights : $STEP3_VENDOR|$STEP3_MODEL"
echo "  Step 4 synthesize       : $STEP4_VENDOR|$STEP4_MODEL (word_limit=3000)"
echo "  Step 5 pandoc           : no LLM"
echo "============================================================"

# ── Step 1 — Extract Wisdom ───────────────────────────────────
t=$(step_start "Step 1/5" "extract_wisdom" "$STEP1_VENDOR" "$STEP1_MODEL")
fabric --youtube="$URL" \
       --transcript \
       --pattern extract_wisdom \
       --model "$STEP1_MODEL" \
       --vendor "$STEP1_VENDOR" \
       --output "${BASE}/01_wisdom.md"
R1=$(step_end "$t" "${BASE}/01_wisdom.md" "${BASE}/01_wisdom.md" "$STEP1_VENDOR")
DUR1=$(get_dur "$R1"); IN1=$(get_in "$R1"); OUT1=$(get_out "$R1"); COST1=$(get_cost "$R1")

# ── Step 2 — Summarize ────────────────────────────────────────
t=$(step_start "Step 2/5" "summarize" "$STEP2_VENDOR" "$STEP2_MODEL")
cat "${BASE}/01_wisdom.md" | \
    fabric --pattern summarize \
           --model "$STEP2_MODEL" \
           --vendor "$STEP2_VENDOR" \
           --output "${BASE}/02_summary.md"
R2=$(step_end "$t" "${BASE}/01_wisdom.md" "${BASE}/02_summary.md" "$STEP2_VENDOR")
DUR2=$(get_dur "$R2"); IN2=$(get_in "$R2"); OUT2=$(get_out "$R2"); COST2=$(get_cost "$R2")

# ── Step 3 — Extract Insights ─────────────────────────────────
t=$(step_start "Step 3/5" "extract_insights" "$STEP3_VENDOR" "$STEP3_MODEL")
cat "${BASE}/01_wisdom.md" | \
    fabric --pattern extract_insights \
           --model "$STEP3_MODEL" \
           --vendor "$STEP3_VENDOR" \
           --output "${BASE}/03_insights.md"
R3=$(step_end "$t" "${BASE}/01_wisdom.md" "${BASE}/03_insights.md" "$STEP3_VENDOR")
DUR3=$(get_dur "$R3"); IN3=$(get_in "$R3"); OUT3=$(get_out "$R3"); COST3=$(get_cost "$R3")

# ── Step 4 — Create Tags ──────────────────────────────────────
t=$(step_start "Step 4/5" "synthesize_eloquent_narrative" "$STEP4_VENDOR" "$STEP4_MODEL")
# Combine all prior outputs for synthesis — wisdom + summary + insights
COMBINED="${BASE}/03_combined_for_synthesis.md"
{
  echo "word_limit=3000"
  echo ""
  echo "## Extracted Wisdom"
  cat "${BASE}/01_wisdom.md"
  echo ""
  echo "## Summary"
  cat "${BASE}/02_summary.md"
  echo ""
  echo "## Insights"
  cat "${BASE}/03_insights.md"
} > "$COMBINED"

fabric --pattern synthesize_eloquent_narrative_from_wisdom \
       --model "$STEP4_MODEL" \
       --vendor "$STEP4_VENDOR" \
       < "$COMBINED" \
       --output "${BASE}/04_narrative.md"
R4=$(step_end "$t" "$COMBINED" "${BASE}/04_narrative.md" "$STEP4_VENDOR")
DUR4=$(get_dur "$R4"); IN4=$(get_in "$R4"); OUT4=$(get_out "$R4"); COST4=$(get_cost "$R4")

# ── Step 5 — Pandoc Output Generation ─────────────────────────
t=$(step_start "Step 5/5" "pandoc conversion" "none" "no LLM")

# Use narrative as primary content — the synthesized document IS the report
cat "${BASE}/04_narrative.md" > "${BASE}/00_full_report.md"
# Append appendix with raw extractions
{
  echo ""
  echo "---"
  echo ""
  echo "## Appendix: Raw Extractions"
  echo ""
  echo "### Extracted Wisdom"
  cat "${BASE}/01_wisdom.md"
  echo ""
  echo "### Summary"
  cat "${BASE}/02_summary.md"
  echo ""
  echo "### Insights"
  cat "${BASE}/03_insights.md"
} >> "${BASE}/00_full_report.md"

pandoc "${BASE}/00_full_report.md" \
       -o "${BASE}/full_report.pdf" \
       --pdf-engine=xelatex \
       -V geometry:margin=1in \
       --metadata title="ACMS Fabric Stitch Report" \
       && echo "  Done: full_report.pdf" || echo "  Failed: full_report.pdf"

pandoc "${BASE}/00_full_report.md" \
       -o "${BASE}/full_report.docx" \
       --metadata title="ACMS Fabric Stitch Report" \
       && echo "  Done: full_report.docx"

# Copy docx to Windows via WSL2 interop and launch Word
mkdir -p "$WIN_OUTPUT_DIR"
WIN_FILE="${WIN_OUTPUT_DIR}/ACMS_$(basename $BASE)_report.docx"
cp "${BASE}/full_report.docx" "$WIN_FILE" 2>/dev/null && {
  WIN_PATH=$(wslpath -w "$WIN_FILE" 2>/dev/null || echo "$WIN_FILE")
  echo "  ✓ Windows copy: $WIN_PATH"
  cmd.exe /c start winword.exe "$WIN_PATH" 2>/dev/null &&
    echo "  ✓ Word launched" ||
    echo "  ⚠ Word launch failed — open manually: $WIN_PATH"
}

pandoc "${BASE}/00_full_report.md" \
       -o "${BASE}/full_report.html" \
       --standalone \
       --metadata title="ACMS Fabric Stitch Report" \
       && echo "  Done: full_report.html"

R5=$(step_end "$t" "${BASE}/00_full_report.md" "${BASE}/00_full_report.md" "none")
DUR5=$(get_dur "$R5")

# ── Grand Total ───────────────────────────────────────────────
pipeline_end=$(date +%s%3N)
pipeline_ms=$(( pipeline_end - pipeline_start ))
pipeline_s=$(echo "scale=2; $pipeline_ms / 1000" | bc)
total_step_ms=$(( DUR1 + DUR2 + DUR3 + DUR4 + DUR5 ))
total_step_s=$(echo "scale=2; $total_step_ms / 1000" | bc)
total_in=$(( IN1 + IN2 + IN3 + IN4 ))
total_out=$(( OUT1 + OUT2 + OUT3 + OUT4 ))
total_cost=$("$UV_PYTHON" -c "
costs = ['${COST1}','${COST2}','${COST3}','${COST4}']
total = sum(float(c) for c in costs)
print(f'{total:.6f}')
" 2>/dev/null || echo "0.000000")

echo ""
echo "============================================================"
echo "ACMS PIPELINE COMPLETION REPORT"
echo "============================================================"
printf "  %-5s %-20s %-35s %8s %8s %8s %12s\n" \
    "Step" "Pattern" "Vendor|Model" "ms" "In" "Out" "Cost"
echo "  -------------------------------------------------------------------------------"
printf "  %-5s %-20s %-35s %8s %8s %8s %12s\n" \
    "1" "extract_wisdom" "${STEP1_VENDOR}|${STEP1_MODEL}" \
    "$DUR1" "$IN1" "$OUT1" "\$${COST1}"
printf "  %-5s %-20s %-35s %8s %8s %8s %12s\n" \
    "2" "summarize" "${STEP2_VENDOR}|${STEP2_MODEL}" \
    "$DUR2" "$IN2" "$OUT2" "\$${COST2}"
printf "  %-5s %-20s %-35s %8s %8s %8s %12s\n" \
    "3" "extract_insights" "${STEP3_VENDOR}|${STEP3_MODEL}" \
    "$DUR3" "$IN3" "$OUT3" "\$${COST3}"
printf "  %-5s %-20s %-35s %8s %8s %8s %12s\n" \
    "4" "synthesize" "${STEP4_VENDOR}|${STEP4_MODEL}" \
    "$DUR4" "$IN4" "$OUT4" "\$${COST4}"
printf "  %-5s %-20s %-35s %8s %8s %8s %12s\n" \
    "5" "pandoc" "no LLM" \
    "$DUR5" "-" "-" "-"
echo "  -------------------------------------------------------------------------------"
printf "  %-5s %-20s %-35s %8s %8s %8s %12s\n" \
    "TOT" "" "" \
    "$total_step_ms" "$total_in" "$total_out" "\$${total_cost}"
echo ""
echo "  Pipeline wall time : ${pipeline_s}s (${pipeline_ms}ms)"
echo "  Completed          : $(date '+%Y-%m-%d %H:%M:%S')"
echo "  Output dir         : $BASE"
echo "============================================================"
ls -lh "$BASE"

# ── Audit Log ─────────────────────────────────────────────────
cat >> "$AUDIT_LOG" << AUDIT
============================================================
ACMS AUDIT ENTRY
Timestamp   : $(date '+%Y-%m-%d %H:%M:%S')
Session     : ${TIMESTAMP}
URL         : ${URL}
Output dir  : ${BASE}
------------------------------------------------------------
Step  Pattern           Vendor|Model                        ms      In      Out     Cost
1     extract_wisdom    ${STEP1_VENDOR}|${STEP1_MODEL}      ${DUR1}  ${IN1}  ${OUT1}  ${COST1}
2     summarize         ${STEP2_VENDOR}|${STEP2_MODEL}      ${DUR2}  ${IN2}  ${OUT2}  ${COST2}
3     extract_insights  ${STEP3_VENDOR}|${STEP3_MODEL}      ${DUR3}  ${IN3}  ${OUT3}  ${COST3}
4     synthesize        ${STEP4_VENDOR}|${STEP4_MODEL}      ${DUR4}  ${IN4}  ${OUT4}  ${COST4}
5     pandoc            no LLM                              ${DUR5}  -       -       -
------------------------------------------------------------
Total input tokens  : ${total_in}
Total output tokens : ${total_out}
Total cost          : \$${total_cost}
Pipeline ms         : ${pipeline_ms}
Status              : COMPLETED
============================================================
AUDIT

echo ""
echo "  Audit log: $AUDIT_LOG"
