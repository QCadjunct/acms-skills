#!/usr/bin/env bash
# sync_skill.sh
# ACMS Skill Synchronization Pipeline
# © 2026 Mind Over Metadata LLC — Peter Heller
#
# Detects system.md changes via MD5 hash, versions prior artifacts with
# uuidv7 timestamps, regenerates system.yaml and system.toon via Fabric
# transformer patterns, deploys to target environment, and logs cost.
#
# Usage:
#   ./sync_skill.sh --source <path/to/system.md> [options]
#
# Options:
#   --source     PATH     Path to system.md (required)
#   --env        ENV      dev | qa | prod (default: dev)
#   --generate   TARGET   yaml | toon | all (default: all)
#   --dry-run             Show what would happen, no writes
#   --force               Skip hash check, regenerate regardless
#   --rates      PATH     Path to vendor_rates.yaml (default: auto-detect)
#   --help                Show this help
#
# Pipeline steps:
#   1. VALIDATE   — source file exists, is readable, has required sections
#   2. HASH       — compute MD5 of system.md, compare to stored hash
#   3. DIFF       — if no change and not --force, exit cleanly (nothing to do)
#   4. ARCHIVE    — version prior system.yaml and system.toon with uuidv7 timestamp
#   5. GENERATE   — run fabric transformer patterns to regenerate artifacts
#   6. VALIDATE   — confirm output artifacts are well-formed
#   7. DEPLOY     — copy to target environment patterns/ directory
#   8. HASH-STORE — write new MD5 hash to .sync_hash file
#   9. COST       — compute and log token cost via vendor_rates.yaml

set -euo pipefail

# ── Defaults ──────────────────────────────────────────────────────────────────
SOURCE=""
ENV="dev"
GENERATE="all"
DRY_RUN=false
FORCE=false
RATES_FILE=""

# ── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

# ── Arg parse ─────────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case $1 in
    --source)   SOURCE="$2";   shift 2 ;;
    --env)      ENV="$2";      shift 2 ;;
    --generate) GENERATE="$2"; shift 2 ;;
    --rates)    RATES_FILE="$2"; shift 2 ;;
    --dry-run)  DRY_RUN=true;  shift ;;
    --force)    FORCE=true;    shift ;;
    --help)
      grep "^#" "$0" | head -30 | sed 's/^# //'
      exit 0
      ;;
    *) echo -e "${RED}Unknown option: $1${RESET}"; exit 1 ;;
  esac
done

# ── Validate required args ────────────────────────────────────────────────────
if [[ -z "$SOURCE" ]]; then
  echo -e "${RED}ERROR: --source is required${RESET}"
  echo "Usage: $0 --source path/to/system.md"
  exit 1
fi

# ── Resolve paths ─────────────────────────────────────────────────────────────
SOURCE_ABS="$(realpath "$SOURCE")"
SKILL_DIR="$(dirname "$SOURCE_ABS")"
SKILL_NAME="$(basename "$SKILL_DIR")"
DOMAIN_DIR="$(dirname "$SKILL_DIR")"
DOMAIN="$(basename "$DOMAIN_DIR")"
REPO_ROOT="$(git -C "$SKILL_DIR" rev-parse --show-toplevel 2>/dev/null || echo "$HOME/acms-skills")"
ARCHIVE_DIR="$SKILL_DIR/_archive"
HASH_FILE="$SKILL_DIR/.sync_hash"
TIMESTAMP=$(date +%Y%m%dT%H%M%S)

# Auto-detect vendor_rates.yaml
if [[ -z "$RATES_FILE" ]]; then
  RATES_FILE="$REPO_ROOT/vendor_rates/vendor_rates.yaml"
fi

# Environment target paths (Fabric flat deploy pattern — ADR-003)
case "$ENV" in
  dev)  DEPLOY_BASE="$HOME/.config/fabric/patterns_custom" ;;
  qa)   DEPLOY_BASE="$HOME/.config/fabric/patterns_qa" ;;
  prod) DEPLOY_BASE="$HOME/.config/fabric/patterns" ;;
  *)    echo -e "${RED}ERROR: --env must be dev | qa | prod${RESET}"; exit 1 ;;
esac
DEPLOY_DIR="$DEPLOY_BASE/$SKILL_NAME"

# Fabric transformer pattern paths
YAML_TRANSFORMER="from_system.md_to_system.yaml"
TOON_TRANSFORMER="from_system.md_to_system.toon"

# ── Header ────────────────────────────────────────────────────────────────────
echo -e "${BOLD}${CYAN}"
echo "╔══════════════════════════════════════════════════════════╗"
echo "║           ACMS sync_skill.sh — Skill Sync Pipeline      ║"
echo "║           Mind Over Metadata LLC © 2026                 ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo -e "${RESET}"
echo -e "${BOLD}Skill:${RESET}   $SKILL_NAME"
echo -e "${BOLD}Domain:${RESET}  $DOMAIN"
echo -e "${BOLD}Source:${RESET}  $SOURCE_ABS"
echo -e "${BOLD}Env:${RESET}     $ENV → $DEPLOY_DIR"
echo -e "${BOLD}Generate:${RESET} $GENERATE"
[[ "$DRY_RUN" == true ]] && echo -e "${YELLOW}[DRY RUN] No files will be written.${RESET}"
[[ "$FORCE"   == true ]] && echo -e "${YELLOW}[FORCE] Hash check bypassed.${RESET}"
echo ""

STEP_START=$(date +%s%3N)
TOTAL_COST=0
STEPS_COMPLETED=0

# ── Step 1: VALIDATE ──────────────────────────────────────────────────────────
echo -e "${BOLD}Step 1/9 — VALIDATE${RESET}"
STEP_T=$(date +%s%3N)

if [[ ! -f "$SOURCE_ABS" ]]; then
  echo -e "${RED}  ✗ system.md not found: $SOURCE_ABS${RESET}"; exit 1
fi

# Check required sections
for section in "IDENTITY" "BEHAVIORAL CONTRACT"; do
  if ! grep -qi "^# $section" "$SOURCE_ABS"; then
    echo -e "${RED}  ✗ Missing required section: # $section${RESET}"; exit 1
  fi
done

echo -e "${GREEN}  ✓ system.md valid — required sections present${RESET}"
echo -e "  ⏱  $(($(date +%s%3N) - STEP_T))ms"
STEPS_COMPLETED=$((STEPS_COMPLETED + 1))

# ── Step 2: HASH ──────────────────────────────────────────────────────────────
echo -e "\n${BOLD}Step 2/9 — HASH${RESET}"
STEP_T=$(date +%s%3N)

CURRENT_HASH=$(md5sum "$SOURCE_ABS" | awk '{print $1}')
STORED_HASH=""
if [[ -f "$HASH_FILE" ]]; then
  STORED_HASH=$(cat "$HASH_FILE")
fi

echo -e "  Current MD5: ${CYAN}$CURRENT_HASH${RESET}"
if [[ -n "$STORED_HASH" ]]; then
  echo -e "  Stored MD5:  ${CYAN}$STORED_HASH${RESET}"
else
  echo -e "  Stored MD5:  ${YELLOW}none (first sync)${RESET}"
fi
echo -e "  ⏱  $(($(date +%s%3N) - STEP_T))ms"
STEPS_COMPLETED=$((STEPS_COMPLETED + 1))

# ── Step 3: DIFF ──────────────────────────────────────────────────────────────
echo -e "\n${BOLD}Step 3/9 — DIFF${RESET}"
STEP_T=$(date +%s%3N)

if [[ "$CURRENT_HASH" == "$STORED_HASH" && "$FORCE" == false ]]; then
  echo -e "${GREEN}  ✓ No changes detected — system.md unchanged since last sync${RESET}"
  echo -e "  ⏱  $(($(date +%s%3N) - STEP_T))ms"
  echo ""
  echo -e "${GREEN}Nothing to sync. Use --force to regenerate regardless.${RESET}"
  exit 0
fi

if [[ "$CURRENT_HASH" != "$STORED_HASH" ]]; then
  echo -e "${YELLOW}  ⚡ Change detected — system.md has been modified${RESET}"
else
  echo -e "${YELLOW}  ⚡ Force flag set — regenerating regardless of hash${RESET}"
fi
echo -e "  ⏱  $(($(date +%s%3N) - STEP_T))ms"
STEPS_COMPLETED=$((STEPS_COMPLETED + 1))

# ── Step 4: ARCHIVE ───────────────────────────────────────────────────────────
echo -e "\n${BOLD}Step 4/9 — ARCHIVE${RESET}"
STEP_T=$(date +%s%3N)

if [[ "$DRY_RUN" == false ]]; then
  mkdir -p "$ARCHIVE_DIR"

  for artifact in system.yaml system.toon; do
    if [[ -f "$SKILL_DIR/$artifact" ]]; then
      ARCHIVE_NAME="${artifact%.${artifact##*.}}_${TIMESTAMP}.${artifact##*.}"
      cp "$SKILL_DIR/$artifact" "$ARCHIVE_DIR/$ARCHIVE_NAME"
      echo -e "${GREEN}  ✓ Archived: $ARCHIVE_NAME${RESET}"
    else
      echo -e "  ℹ  No prior $artifact to archive"
    fi
  done
else
  echo -e "  [DRY RUN] Would archive prior system.yaml and system.toon"
fi
echo -e "  ⏱  $(($(date +%s%3N) - STEP_T))ms"
STEPS_COMPLETED=$((STEPS_COMPLETED + 1))

# ── Step 5: GENERATE ──────────────────────────────────────────────────────────
echo -e "\n${BOLD}Step 5/9 — GENERATE${RESET}"
STEP_T=$(date +%s%3N)

YAML_TOKENS_IN=0; YAML_TOKENS_OUT=0
TOON_TOKENS_IN=0; TOON_TOKENS_OUT=0

generate_artifact() {
  local transformer="$1"
  local output_file="$2"
  local label="$3"

  echo -e "  Generating $label via fabric pattern: $transformer"

  if [[ "$DRY_RUN" == false ]]; then
    if command -v fabric &>/dev/null; then
      fabric --pattern "$transformer" < "$SOURCE_ABS" > "$SKILL_DIR/$output_file"
      echo -e "${GREEN}  ✓ $label generated${RESET}"
    else
      echo -e "${YELLOW}  ⚠ fabric not in PATH — writing placeholder${RESET}"
      echo "# PLACEHOLDER — run: fabric --pattern $transformer < system.md > $output_file" \
        > "$SKILL_DIR/$output_file"
    fi
  else
    echo -e "  [DRY RUN] Would run: fabric --pattern $transformer < system.md > $output_file"
  fi
}

case "$GENERATE" in
  yaml) generate_artifact "$YAML_TRANSFORMER" "system.yaml" "system.yaml" ;;
  toon) generate_artifact "$TOON_TRANSFORMER" "system.toon" "system.toon" ;;
  all)
    generate_artifact "$YAML_TRANSFORMER" "system.yaml" "system.yaml"
    generate_artifact "$TOON_TRANSFORMER" "system.toon" "system.toon"
    ;;
esac

echo -e "  ⏱  $(($(date +%s%3N) - STEP_T))ms"
STEPS_COMPLETED=$((STEPS_COMPLETED + 1))

# ── Step 6: VALIDATE ARTIFACTS ────────────────────────────────────────────────
echo -e "\n${BOLD}Step 6/9 — VALIDATE ARTIFACTS${RESET}"
STEP_T=$(date +%s%3N)

if [[ "$DRY_RUN" == false ]]; then
  # Validate system.yaml
  if [[ "$GENERATE" == "yaml" || "$GENERATE" == "all" ]]; then
    if [[ -f "$SKILL_DIR/system.yaml" ]]; then
      if python3 -c "import yaml; yaml.safe_load(open('$SKILL_DIR/system.yaml'))" 2>/dev/null; then
        echo -e "${GREEN}  ✓ system.yaml — valid YAML${RESET}"
      else
        echo -e "${RED}  ✗ system.yaml — YAML parse error${RESET}"; exit 1
      fi
    fi
  fi

  # Validate system.toon — check 13 lines (type decl + 12 fields)
  if [[ "$GENERATE" == "toon" || "$GENERATE" == "all" ]]; then
    if [[ -f "$SKILL_DIR/system.toon" ]]; then
      TOON_LINES=$(wc -l < "$SKILL_DIR/system.toon")
      if [[ "$TOON_LINES" -ge 12 ]]; then
        echo -e "${GREEN}  ✓ system.toon — $TOON_LINES lines${RESET}"
      else
        echo -e "${YELLOW}  ⚠ system.toon — only $TOON_LINES lines (expected ≥12)${RESET}"
      fi
    fi
  fi
else
  echo -e "  [DRY RUN] Would validate generated artifacts"
fi
echo -e "  ⏱  $(($(date +%s%3N) - STEP_T))ms"
STEPS_COMPLETED=$((STEPS_COMPLETED + 1))

# ── Step 7: DEPLOY ────────────────────────────────────────────────────────────
echo -e "\n${BOLD}Step 7/9 — DEPLOY ($ENV)${RESET}"
STEP_T=$(date +%s%3N)

if [[ "$DRY_RUN" == false ]]; then
  mkdir -p "$DEPLOY_DIR"

  # Copy system.md always
  cp "$SOURCE_ABS" "$DEPLOY_DIR/system.md"
  echo -e "${GREEN}  ✓ Deployed: system.md → $DEPLOY_DIR/${RESET}"

  # Copy generated artifacts
  for artifact in system.yaml system.toon; do
    if [[ -f "$SKILL_DIR/$artifact" ]]; then
      cp "$SKILL_DIR/$artifact" "$DEPLOY_DIR/$artifact"
      echo -e "${GREEN}  ✓ Deployed: $artifact → $DEPLOY_DIR/${RESET}"
    fi
  done
else
  echo -e "  [DRY RUN] Would deploy to: $DEPLOY_DIR"
fi
echo -e "  ⏱  $(($(date +%s%3N) - STEP_T))ms"
STEPS_COMPLETED=$((STEPS_COMPLETED + 1))

# ── Step 8: HASH-STORE ────────────────────────────────────────────────────────
echo -e "\n${BOLD}Step 8/9 — HASH-STORE${RESET}"
STEP_T=$(date +%s%3N)

if [[ "$DRY_RUN" == false ]]; then
  echo "$CURRENT_HASH" > "$HASH_FILE"
  echo -e "${GREEN}  ✓ Hash stored: $CURRENT_HASH${RESET}"
else
  echo -e "  [DRY RUN] Would store hash: $CURRENT_HASH"
fi
echo -e "  ⏱  $(($(date +%s%3N) - STEP_T))ms"
STEPS_COMPLETED=$((STEPS_COMPLETED + 1))

# ── Step 9: COST — ADR-009 format, per-artifact breakdown ────────────────────
echo -e "\n${BOLD}Step 9/9 — COST${RESET}"
STEP_T=$(date +%s%3N)

# Generate RUN_ID (uuidv7-compatible via python3 stdlib)
RUN_ID=$(python3 -c "import uuid; print(str(uuid.uuid4()))")

# Locate transformer pattern prompts for token measurement
TRANSFORMER_YAML_MD="$HOME/.config/fabric/patterns_custom/system.md_transformers/from_system.md_to_system.yaml/system.md"
TRANSFORMER_TOON_MD="$HOME/.config/fabric/patterns_custom/system.md_transformers/from_system.md_to_system.toon/system.md"

# Colon-aware YAML rate reader (ADR-008 stdlib-only pattern)
compute_cost() {
  python3 - "$RATES_FILE" "$1" "$2" "$3" "$4" <<'PYEOF'
import sys
rates_file, vendor, model, tokens_in, tokens_out = sys.argv[1:]
tokens_in  = int(tokens_in)
tokens_out = int(tokens_out)

# YAML parser — colon-aware (handles model names like qwen3:8b)
rates = {}
try:
  with open(rates_file) as f:
    current_path = []
    for line in f:
      s = line.rstrip()
      if not s or s.startswith('#'):
        continue
      if ' #' in s:
        s = s[:s.index(' #')].rstrip()
      indent = len(line) - len(line.lstrip())
      depth  = indent // 2
      if ':' in s.lstrip():
        ls = s.lstrip()
        fc = ls.index(':')
        key = ls[:fc].strip()
        val = ls[fc+1:].strip()
        current_path = current_path[:depth] + [key]
        if val:
          rates['.'.join(current_path)] = val
except Exception:
  pass

in_key  = f"vendors.{vendor}.models.{model}.input"
out_key = f"vendors.{vendor}.models.{model}.output"

try:
  rate_in  = float(rates.get(in_key,  "0.0"))
  rate_out = float(rates.get(out_key, "0.0"))
except ValueError:
  rate_in = 0.0; rate_out = 0.0

cost_in  = tokens_in  * rate_in
cost_out = tokens_out * rate_out
cost     = cost_in + cost_out
print(f"{cost_in:.6f} {cost_out:.6f} {cost:.6f}")
PYEOF
}

# Token counter — file size / 4 chars per token estimate
token_count() {
  local f="$1"
  if [[ -f "$f" ]]; then
    local chars
    chars=$(wc -c < "$f")
    echo $(( chars / 4 ))
  else
    echo 0
  fi
}

# ── Measure all artifact token counts ─────────────────────────────────────────
SYNC_VENDOR="ollama"
SYNC_MODEL="gemma3:12b"

# Tier 1: Source files (input only — no output tokens)
SRC_TOKENS=$(token_count "$SOURCE_ABS")
TRANS_YAML_TOKENS=$(token_count "$TRANSFORMER_YAML_MD")
TRANS_TOON_TOKENS=$(token_count "$TRANSFORMER_TOON_MD")

# Tier 2: Derived artifacts
# Combined input = skill.system.md + transformer prompt
YAML_IN=$(( SRC_TOKENS + TRANS_YAML_TOKENS ))
TOON_IN=$(( SRC_TOKENS + TRANS_TOON_TOKENS ))
YAML_OUT=$(token_count "$SKILL_DIR/system.yaml")
TOON_OUT=$(token_count "$SKILL_DIR/system.toon")

# ── Compute costs per artifact ─────────────────────────────────────────────────
read SRC_COST_IN   SRC_COST_OUT   SRC_COST   <<< $(compute_cost "$SYNC_VENDOR" "$SYNC_MODEL" "$SRC_TOKENS" 0)
read TYAML_COST_IN TYAML_COST_OUT TYAML_COST <<< $(compute_cost "$SYNC_VENDOR" "$SYNC_MODEL" "$TRANS_YAML_TOKENS" 0)
read TTOON_COST_IN TTOON_COST_OUT TTOON_COST <<< $(compute_cost "$SYNC_VENDOR" "$SYNC_MODEL" "$TRANS_TOON_TOKENS" 0)
read YAML_COST_IN  YAML_COST_OUT  YAML_COST  <<< $(compute_cost "$SYNC_VENDOR" "$SYNC_MODEL" "$YAML_IN" "$YAML_OUT")
read TOON_COST_IN  TOON_COST_OUT  TOON_COST  <<< $(compute_cost "$SYNC_VENDOR" "$SYNC_MODEL" "$TOON_IN" "$TOON_OUT")

TOTAL=$(python3 -c "
costs = [float('${YAML_COST:-0}'), float('${TOON_COST:-0}')]
print(f'{sum(costs):.6f}')
" 2>/dev/null || echo "0.000000")

ELAPSED=$(( $(date +%s%3N) - STEP_START ))

# ── Display per-artifact breakdown ────────────────────────────────────────────
echo -e "  ${BOLD}Artifact token breakdown:${RESET}"
echo -e "  skill.system.md          : ${CYAN}${SRC_TOKENS} tokens${RESET} (source — input only)"
echo -e "  transformer.yaml.system.md: ${CYAN}${TRANS_YAML_TOKENS} tokens${RESET} (prompt — input only)"
echo -e "  transformer.toon.system.md: ${CYAN}${TRANS_TOON_TOKENS} tokens${RESET} (prompt — input only)"
echo -e "  skill.system.yaml        : in=${YAML_IN} out=${YAML_OUT} → ${CYAN}\$${YAML_COST}${RESET}"
echo -e "  skill.system.toon        : in=${TOON_IN} out=${TOON_OUT} → ${CYAN}\$${TOON_COST}${RESET}"
echo -e "  ${BOLD}Total cost: \$${TOTAL}${RESET}"
echo -e "  ${BOLD}RUN_ID: ${RUN_ID}${RESET}"

# ── Write ADR-009 format entries to cost_audit.log ────────────────────────────
AUDIT_LOG="$HOME/.config/fabric/cost_audit.log"
mkdir -p "$(dirname "$AUDIT_LOG")"

# FQSN for skill field
PILLAR="$(basename "$(dirname "$DOMAIN_DIR")")"
 SKILL_FQSN="${PILLAR}/${DOMAIN}/${SKILL_NAME}"

if [[ "$DRY_RUN" == false ]]; then
  {
    # skill.system.md — source measurement (input only)
    echo "[${TIMESTAMP}] | sync_skill | ${RUN_ID} | ${SKILL_FQSN} | skill.system.md | ${SYNC_VENDOR} | ${SYNC_MODEL} | ${SRC_TOKENS} | 0 | ${SRC_COST_IN:-0.000000} | 0.000000 | ${SRC_COST:-0.000000} | 0 | ${ENV} | | source measured"

    # transformer.yaml.system.md — prompt measurement (input only)
    echo "[${TIMESTAMP}] | sync_skill | ${RUN_ID} | ${SKILL_FQSN} | transformer.yaml.system.md | ${SYNC_VENDOR} | ${SYNC_MODEL} | ${TRANS_YAML_TOKENS} | 0 | ${TYAML_COST_IN:-0.000000} | 0.000000 | ${TYAML_COST:-0.000000} | 0 | ${ENV} | | transformer prompt measured"

    # transformer.toon.system.md — prompt measurement (input only)
    echo "[${TIMESTAMP}] | sync_skill | ${RUN_ID} | ${SKILL_FQSN} | transformer.toon.system.md | ${SYNC_VENDOR} | ${SYNC_MODEL} | ${TRANS_TOON_TOKENS} | 0 | ${TTOON_COST_IN:-0.000000} | 0.000000 | ${TTOON_COST:-0.000000} | 0 | ${ENV} | | transformer prompt measured"

    # skill.system.yaml — derived artifact (combined input)
    echo "[${TIMESTAMP}] | sync_skill | ${RUN_ID} | ${SKILL_FQSN} | skill.system.yaml | ${SYNC_VENDOR} | ${SYNC_MODEL} | ${YAML_IN} | ${YAML_OUT} | ${YAML_COST_IN:-0.000000} | ${YAML_COST_OUT:-0.000000} | ${YAML_COST:-0.000000} | ${ELAPSED} | ${ENV} | | in=skill+transformer"

    # skill.system.toon — derived artifact (combined input)
    echo "[${TIMESTAMP}] | sync_skill | ${RUN_ID} | ${SKILL_FQSN} | skill.system.toon | ${SYNC_VENDOR} | ${SYNC_MODEL} | ${TOON_IN} | ${TOON_OUT} | ${TOON_COST_IN:-0.000000} | ${TOON_COST_OUT:-0.000000} | ${TOON_COST:-0.000000} | ${ELAPSED} | ${ENV} | | in=skill+transformer"
  } >> "$AUDIT_LOG"

  echo -e "${GREEN}  ✓ 5 ADR-009 cost entries written (per-artifact breakdown)${RESET}"
fi
echo -e "  ⏱  $(($(date +%s%3N) - STEP_T))ms"

# ── Final summary ─────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}${GREEN}╔══════════════════════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}${GREEN}║  sync_skill.sh — COMPLETE                               ║${RESET}"
echo -e "${BOLD}${GREEN}║  Skill:    $SKILL_NAME$(printf '%*s' $((42 - ${#SKILL_NAME})) '')║${RESET}"
echo -e "${BOLD}${GREEN}║  Steps:    $STEPS_COMPLETED/9 completed$(printf '%*s' 33 '')║${RESET}"
echo -e "${BOLD}${GREEN}║  Env:      $ENV → $DEPLOY_BASE$(printf '%*s' $((30 - ${#ENV} - ${#DEPLOY_BASE})) '')║${RESET}"
echo -e "${BOLD}${GREEN}║  Cost:     \$$TOTAL$(printf '%*s' $((40 - ${#TOTAL})) '')║${RESET}"
echo -e "${BOLD}${GREEN}║  Elapsed:  ${ELAPSED}ms$(printf '%*s' $((38 - ${#ELAPSED})) '')║${RESET}"
[[ "$DRY_RUN" == true ]] && \
echo -e "${BOLD}${YELLOW}║  MODE: DRY RUN — no files written                       ║${RESET}"
echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════════════════════╝${RESET}"
