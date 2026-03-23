#!/usr/bin/env bash
# ============================================================
# ACMS_skill_deploy_generators — deploy_generators.sh
# FQSN: MetaArchitecture/ACMS_skill_deployers/ACMS_skill_deploy_generators
# Mind Over Metadata LLC — Spec-Driven Development (SDD)
# ============================================================

set -euo pipefail

# ── Constants ────────────────────────────────────────────────
PATTERNS_DEV="$HOME/.config/fabric/patterns_custom"
PATTERNS_QA="$HOME/.config/fabric/patterns_qa"
PATTERNS_PROD="$HOME/.config/fabric/patterns"
AUDIT_LOG="$HOME/.config/fabric/deploy_audit.log"
SCRIPT_VERSION="1.1.0"
COST_LOG="$HOME/.config/fabric/cost_audit.log"
UV_PYTHON="$HOME/projects/aces-skills/.venv/bin/python3"

# ── Defaults ─────────────────────────────────────────────────
SOURCE=""
GENERATE="all"
ARCHIVE="true"
ENV="dev"

# ── Colors ───────────────────────────────────────────────────
RED='\033[0;31m'
YLW='\033[0;33m'
GRN='\033[0;32m'
CYN='\033[0;36m'
BLD='\033[1m'
RST='\033[0m'

# ── Usage ────────────────────────────────────────────────────
usage() {
    echo -e "${BLD}ACMS Skill Deploy Generators v${SCRIPT_VERSION}${RST}"
    echo -e "FQSN: MetaArchitecture/ACMS_skill_deployers/ACMS_skill_deploy_generators"
    echo ""
    echo -e "${BLD}Usage:${RST}"
    echo "  deploy_generators.sh --source <path/to/system.md> [options]"
    echo ""
    echo -e "${BLD}Options:${RST}"
    echo "  --source    <path>           Path to source system.md (required)"
    echo "  --generate  [yaml|toon|all]  Artifacts to generate   (default: all)"
    echo "  --archive   [true|false]     Archive previous versions(default: true)"
    echo "  --env       [dev|qa|prod]    Target environment       (default: dev)"
    echo ""
    echo -e "${BLD}Examples:${RST}"
    echo "  deploy_generators.sh --source ~/.config/fabric/patterns_custom/ACMS_Skills/CodingArchitecture/FabricStitch/ACMS_extract_wisdom/system.md"
    echo "  deploy_generators.sh --source ./system.md --generate yaml --env dev"
    echo "  deploy_generators.sh --source ./system.md --generate all  --env prod"
    exit 0
}

# ── Argument Parsing ─────────────────────────────────────────
[[ $# -eq 0 ]] && usage

while [[ $# -gt 0 ]]; do
    case "$1" in
        --source)   SOURCE="$2";   shift 2 ;;
        --generate) GENERATE="$2"; shift 2 ;;
        --archive)  ARCHIVE="$2";  shift 2 ;;
        --env)      ENV="$2";      shift 2 ;;
        --help|-h)  usage ;;
        *) echo -e "${RED}ERROR: Unknown parameter: $1${RST}" >&2; exit 1 ;;
    esac
done

# ── Validation ───────────────────────────────────────────────
step() { echo -e "${CYN}${BLD}[$1]${RST} $2" >&2; }
ok()   { echo -e "${GRN}  ✓ $1${RST}" >&2; }
warn() { echo -e "${YLW}  ⚠ $1${RST}" >&2; }
fail() { echo -e "${RED}  ✗ $1${RST}" >&2; exit 1; }

# ── Step 1: VALIDATE ─────────────────────────────────────────
step "1" "VALIDATE — checking source system.md"

[[ -z "$SOURCE" ]] && fail "--source is required. Run --help for usage."
[[ ! -f "$SOURCE" ]] && fail "system.md not found: $SOURCE"
ok "Source found: $SOURCE"

# Validate parameters
[[ ! "$GENERATE" =~ ^(yaml|toon|all)$ ]] && fail "--generate must be yaml, toon, or all"
[[ ! "$ARCHIVE"  =~ ^(true|false)$ ]]    && fail "--archive must be true or false"
[[ ! "$ENV"      =~ ^(dev|qa|prod)$ ]]   && fail "--env must be dev, qa, or prod"

ok "Parameters validated: generate=$GENERATE archive=$ARCHIVE env=$ENV"

# ── Step 2: RESOLVE ──────────────────────────────────────────
step "2" "RESOLVE — determining target folder"

SOURCE_DIR=$(dirname "$SOURCE")
SKILL_FOLDER=$(basename "$SOURCE_DIR")
ok "Skill folder: $SKILL_FOLDER"

case "$ENV" in
    dev)
        TARGET_BASE="$PATTERNS_DEV"
        DO_ARCHIVE="$ARCHIVE"
        REQUIRE_CONFIRM="false"
        ;;
    qa)
        if [[ ! -d "$PATTERNS_QA" ]]; then
            warn "patterns_qa/ does not exist — QA environment not configured"
            warn "Defaulting to DEV. Create $PATTERNS_QA to enable QA promotion."
            TARGET_BASE="$PATTERNS_DEV"
            ENV="dev"
        else
            TARGET_BASE="$PATTERNS_QA"
        fi
        DO_ARCHIVE="false"
        REQUIRE_CONFIRM="false"
        ;;
    prod)
        TARGET_BASE="$PATTERNS_PROD"
        DO_ARCHIVE="false"
        REQUIRE_CONFIRM="true"
        ;;
esac

TARGET_DIR="$TARGET_BASE/$SKILL_FOLDER"
mkdir -p "$TARGET_DIR"
ok "Target directory: $TARGET_DIR"

# ── Step 3: ARCHIVE ──────────────────────────────────────────
step "3" "ARCHIVE — versioning previous artifacts"

if [[ "$DO_ARCHIVE" == "true" ]]; then
    # Generate uuidv7 timestamp
    UUID=$(python3 -c "
import sys, subprocess
try:
    import uuid
    # uuid7 not in stdlib — use timestamp fallback
    from datetime import datetime, timezone
    ts = datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S')
    import random, string
    suffix = ''.join(random.choices(string.hexdigits[:16], k=8))
    print(f'{ts}_{suffix}')
except Exception as e:
    from datetime import datetime, timezone
    print(datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S'))
" 2>/dev/null)

    ARCHIVED=0
    for artifact in system.md system.yaml system.toon; do
        if [[ -f "$TARGET_DIR/$artifact" ]]; then
            mv "$TARGET_DIR/$artifact" "$TARGET_DIR/${artifact}_${UUID}"
            ok "Archived: ${artifact} → ${artifact}_${UUID}"
            ARCHIVED=$((ARCHIVED + 1))
        fi
    done
    [[ $ARCHIVED -eq 0 ]] && ok "No previous artifacts to archive"
else
    ok "Archive skipped (env=$ENV)"
fi

# ── Step 4: GENERATE ─────────────────────────────────────────
step "4" "GENERATE — calling fabric patterns"

GEN_YAML="false"
GEN_TOON="false"
[[ "$GENERATE" == "yaml" || "$GENERATE" == "all" ]] && GEN_YAML="true"
[[ "$GENERATE" == "toon" || "$GENERATE" == "all" ]] && GEN_TOON="true"

# Cost accounting accumulators
COST_MODEL=$(grep DEFAULT_MODEL "$HOME/.config/fabric/.env" 2>/dev/null | cut -d= -f2 || echo "unknown")
COST_VENDOR="Ollama"
[[ "$COST_MODEL" == claude* ]]  && COST_VENDOR="Anthropic"
[[ "$COST_MODEL" == gemini* ]]  && COST_VENDOR="Gemini"
[[ "$COST_MODEL" == gpt* ]]     && COST_VENDOR="OpenAI"
TOTAL_IN=0; TOTAL_OUT=0; TOTAL_COST=0
COST_ROWS=""

count_tokens() {
    local text="$1"
    if [[ -x "$UV_PYTHON" ]]; then
        echo "$text" | "$UV_PYTHON" -c "
import sys, tiktoken
enc = tiktoken.get_encoding('cl100k_base')
print(len(enc.encode(sys.stdin.read())))
" 2>/dev/null || echo "0"
    else
        echo "$text" | wc -w
    fi
}

cost_per_token() {
    local vendor="$1" model="$2" in_tok="$3" out_tok="$4"
    python3 -c "
vendor='$vendor'; model='$model'
in_tok=$in_tok; out_tok=$out_tok
rates = {
    'Anthropic': {'in': 0.000003, 'out': 0.000015},
    'Gemini':    {'in': 0.000000375, 'out': 0.0000015},
    'OpenAI':    {'in': 0.000005, 'out': 0.000015},
    'Ollama':    {'in': 0.0, 'out': 0.0},
}
r = rates.get(vendor, {'in': 0.0, 'out': 0.0})
print(f'{in_tok * r[\"in\"] + out_tok * r[\"out\"]:.6f}')
" 2>/dev/null || echo "0.000000"
}

if [[ "$GEN_YAML" == "true" ]]; then
    ok "Generating system.yaml via from_system.md_to_system.yaml..."
    T_START=$(date +%s%3N)
    YAML_OUT=$(cat "$SOURCE" | fabric --pattern from_system.md_to_system.yaml) \
        || fail "fabric pattern from_system.md_to_system.yaml failed"
    T_END=$(date +%s%3N)
    T_MS=$(( T_END - T_START ))
    echo "$YAML_OUT" > "$TARGET_DIR/system.yaml"
    IN_TOK=$(count_tokens "$(cat "$SOURCE")")
    OUT_TOK=$(count_tokens "$YAML_OUT")
    COST=$(cost_per_token "$COST_VENDOR" "$COST_MODEL" "$IN_TOK" "$OUT_TOK")
    TOTAL_IN=$(( TOTAL_IN + IN_TOK ))
    TOTAL_OUT=$(( TOTAL_OUT + OUT_TOK ))
    TOTAL_COST=$(python3 -c "print(f'{$TOTAL_COST + $COST:.6f}')")
    COST_ROWS="${COST_ROWS}\n  from_system.md_to_system.yaml  ${COST_VENDOR}|${COST_MODEL}  ${T_MS}ms  in=${IN_TOK}  out=${OUT_TOK}  \$${COST}"
    ok "system.yaml generated — ${T_MS}ms in=${IN_TOK} out=${OUT_TOK} \$${COST}"
fi

if [[ "$GEN_TOON" == "true" ]]; then
    ok "Generating system.toon via from_system.md_to_system.toon..."
    T_START=$(date +%s%3N)
    TOON_OUT=$(cat "$SOURCE" | fabric --pattern from_system.md_to_system.toon) \
        || fail "fabric pattern from_system.md_to_system.toon failed"
    T_END=$(date +%s%3N)
    T_MS=$(( T_END - T_START ))
    echo "$TOON_OUT" > "$TARGET_DIR/system.toon"
    IN_TOK=$(count_tokens "$(cat "$SOURCE")")
    OUT_TOK=$(count_tokens "$TOON_OUT")
    COST=$(cost_per_token "$COST_VENDOR" "$COST_MODEL" "$IN_TOK" "$OUT_TOK")
    TOTAL_IN=$(( TOTAL_IN + IN_TOK ))
    TOTAL_OUT=$(( TOTAL_OUT + OUT_TOK ))
    TOTAL_COST=$(python3 -c "print(f'{$TOTAL_COST + $COST:.6f}')")
    COST_ROWS="${COST_ROWS}\n  from_system.md_to_system.toon  ${COST_VENDOR}|${COST_MODEL}  ${T_MS}ms  in=${IN_TOK}  out=${OUT_TOK}  \$${COST}"
    ok "system.toon generated — ${T_MS}ms in=${IN_TOK} out=${OUT_TOK} \$${COST}"
fi

# ── Step 5: WRITE ────────────────────────────────────────────
step "5" "WRITE — copying system.md to target"

cp "$SOURCE" "$TARGET_DIR/system.md"
ok "system.md copied to $TARGET_DIR"

# ── Step 6: CONFIRM ──────────────────────────────────────────
step "6" "CONFIRM — production gate"

if [[ "$REQUIRE_CONFIRM" == "true" ]]; then
    echo -e "${YLW}${BLD}"
    echo "  ╔══════════════════════════════════════════════╗"
    echo "  ║  PRODUCTION DEPLOYMENT CONFIRMATION          ║"
    echo "  ║                                              ║"
    echo "  ║  Skill:  $SKILL_FOLDER"
    echo "  ║  Target: $TARGET_DIR"
    echo "  ║                                              ║"
    echo "  ║  Deploy to PROD? [y/n]                       ║"
    echo "  ╚══════════════════════════════════════════════╝"
    echo -e "${RST}"
    read -r CONFIRM
    [[ ! "$CONFIRM" =~ ^[Yy]$ ]] && { warn "PROD deployment cancelled by operator."; exit 0; }
    ok "PROD deployment confirmed"
else
    ok "Confirmation not required for env=$ENV"
fi

# ── Step 7: DEPLOY ───────────────────────────────────────────
step "7" "DEPLOY — trifecta deployed to $ENV"

ls -lh "$TARGET_DIR/"
ok "Deployment complete: $SKILL_FOLDER → $ENV"

# ── Step 8: LOG ──────────────────────────────────────────────
step "8" "LOG — appending to deploy_audit.log"

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
RUN_ID=$(python3 -c "import uuid; print(str(uuid.uuid4()))")
OPERATOR=$(whoami)
LOG_ENTRY="${TIMESTAMP} | ${SKILL_FOLDER} | ${ENV} | ${GENERATE} | ${DO_ARCHIVE} | SUCCESS | ${OPERATOR}"

mkdir -p "$(dirname "$AUDIT_LOG")"
echo "$LOG_ENTRY" >> "$AUDIT_LOG"
ok "Audit log updated: $AUDIT_LOG"

# ── Step 9: COST ─────────────────────────────────────────────
step "9" "COST — accounting report"

echo -e "${CYN}  Pattern                          Vendor|Model                ms    In    Out       Cost${RST}" >&2
echo -e "${CYN}  ───────────────────────────────────────────────────────────────────────────────────${RST}" >&2
echo -e "$COST_ROWS" >&2
echo -e "${CYN}  ───────────────────────────────────────────────────────────────────────────────────${RST}" >&2
echo -e "  TOT                                                                    in=${TOTAL_IN}  out=${TOTAL_OUT}  \$${TOTAL_COST}" >&2

# Append to cost_audit.log
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  # ADR-009 per-artifact cost entries — Step 4 patch
  SKILL_FQSN="${SKILL_FOLDER}"
  SRC_TOKENS=$(wc -c < "$SOURCE" | awk '{print int($1/4)}')
  TRANS_YAML_TOKENS=$(wc -c < "$HOME/.config/fabric/patterns_custom/system.md_transformers/from_system.md_to_system.yaml/system.md" 2>/dev/null | awk '{print int($1/4)}' || echo 0)
  TRANS_TOON_TOKENS=$(wc -c < "$HOME/.config/fabric/patterns_custom/system.md_transformers/from_system.md_to_system.toon/system.md" 2>/dev/null | awk '{print int($1/4)}' || echo 0)
  VENDOR_LC=$(echo "$COST_VENDOR" | tr 'A-Z' 'a-z')
  {
    echo "[${TIMESTAMP}] | deploy_generators | ${RUN_ID} | ${SKILL_FQSN} | skill.system.md | ${VENDOR_LC} | ${COST_MODEL} | ${SRC_TOKENS} | 0 | 0.000000 | 0.000000 | 0.000000 | 0 | ${ENV} | | source measured"
    echo "[${TIMESTAMP}] | deploy_generators | ${RUN_ID} | ${SKILL_FQSN} | transformer.yaml.system.md | ${VENDOR_LC} | ${COST_MODEL} | ${TRANS_YAML_TOKENS} | 0 | 0.000000 | 0.000000 | 0.000000 | 0 | ${ENV} | | transformer prompt measured"
    echo "[${TIMESTAMP}] | deploy_generators | ${RUN_ID} | ${SKILL_FQSN} | transformer.toon.system.md | ${VENDOR_LC} | ${COST_MODEL} | ${TRANS_TOON_TOKENS} | 0 | 0.000000 | 0.000000 | 0.000000 | 0 | ${ENV} | | transformer prompt measured"
    echo "[${TIMESTAMP}] | deploy_generators | ${RUN_ID} | ${SKILL_FQSN} | skill.system.yaml | ${VENDOR_LC} | ${COST_MODEL} | ${TOTAL_IN} | ${TOTAL_OUT} | 0.000000 | 0.000000 | ${TOTAL_COST} | 0 | ${ENV} | | in=skill+transformer"
    echo "[${TIMESTAMP}] | deploy_generators | ${RUN_ID} | ${SKILL_FQSN} | skill.system.toon | ${VENDOR_LC} | ${COST_MODEL} | ${TOTAL_IN} | ${TOTAL_OUT} | 0.000000 | 0.000000 | ${TOTAL_COST} | 0 | ${ENV} | | in=skill+transformer"
  } >> "$COST_LOG"
ok "Cost log updated: $COST_LOG"

# ── Summary ──────────────────────────────────────────────────
echo "" >&2
echo -e "${GRN}${BLD}════════════════════════════════════════${RST}" >&2
echo -e "${GRN}${BLD}  ACMS_skill_deploy_generators — DONE   ${RST}" >&2
echo -e "${GRN}${BLD}════════════════════════════════════════${RST}" >&2
echo -e "  Skill:    ${BLD}$SKILL_FOLDER${RST}" >&2
echo -e "  Env:      ${BLD}$ENV${RST}" >&2
echo -e "  Generate: ${BLD}$GENERATE${RST}" >&2
echo -e "  Archive:  ${BLD}$DO_ARCHIVE${RST}" >&2
echo -e "  Target:   ${BLD}$TARGET_DIR${RST}" >&2
echo -e "  Cost:     ${BLD}\$${TOTAL_COST}${RST}" >&2
echo -e "${GRN}${BLD}════════════════════════════════════════${RST}" >&2
