#!/usr/bin/env bash
# demo_preflight.sh — Pre-demo verification checklist
# ACMS POC Demo — Mind Over Metadata LLC © 2026 — Peter Heller
# Run the night before / morning of the demo to verify all systems green.
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

BOLD='\033[1m'; CYAN='\033[0;36m'; GREEN='\033[0;32m'
YELLOW='\033[0;33m'; RED='\033[0;31m'; RESET='\033[0m'

PASS=0; FAIL=0; WARN=0

pass() { echo -e "  ${GREEN}✓${RESET} $1"; PASS=$((PASS+1)); }
fail() { echo -e "  ${RED}✗${RESET} $1"; FAIL=$((FAIL+1)); }
warn() { echo -e "  ${YELLOW}⚠${RESET} $1"; WARN=$((WARN+1)); }
section() { echo -e "\n${BOLD}${CYAN}━━━ $1 ━━━${RESET}"; }

echo -e "\n${BOLD}${CYAN}╔══════════════════════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}${CYAN}║  ACMS POC — Pre-Demo Preflight Checklist                ║${RESET}"
echo -e "${BOLD}${CYAN}║  Mind Over Metadata LLC © 2026 — Peter Heller           ║${RESET}"
echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════════════════╝${RESET}"

# ── 1. Repository state ───────────────────────────────────────────────────────
section "1. Repository State"

# Git status
if git diff --quiet && git diff --cached --quiet; then
  pass "Git working tree clean"
else
  warn "Uncommitted changes present — consider committing before demo"
fi

# Remote sync
LOCAL=$(git rev-parse HEAD)
REMOTE=$(git rev-parse origin/master 2>/dev/null || echo "unknown")
if [[ "$LOCAL" == "$REMOTE" ]]; then
  pass "Local master in sync with origin/master ($LOCAL)"
else
  warn "Local ahead of or behind remote — run git push/pull"
fi

# ── 2. Required files ─────────────────────────────────────────────────────────
section "2. Required Files"

check_file() {
  local f="$1" label="$2"
  if [[ -f "$f" ]]; then pass "$label"; else fail "$label — MISSING: $f"; fi
}

check_file "sync_skill.sh" "sync_skill.sh"
check_file "cost/cost_analyzer.py" "cost_analyzer.py"
check_file "vendor_rates/vendor_rates.yaml" "vendor_rates.yaml"
check_file "docs/fabric-guide.md" "fabric-guide.md"
check_file "docs/ADR-009-D4-MDLC-Governance.md" "ADR-009 spec"
check_file "MetaArchitecture/PrincipalSystemArchitect/ACMS_principal_system_architect/system.md" \
  "PrincipalSystemArchitect system.md"
check_file "CodingArchitecture/FabricStitch/ACMS_extract_wisdom/system.md" \
  "ACMS_extract_wisdom system.md"
check_file "CodingArchitecture/FabricStitch/ACMS_extract_wisdom/system.yaml" \
  "ACMS_extract_wisdom system.yaml"
check_file "CodingArchitecture/FabricStitch/ACMS_extract_wisdom/system.toon" \
  "ACMS_extract_wisdom system.toon"

# RequirementsGathering specialists
for specialist in identity mission authorities lifecycle cost_model data; do
  check_file "CodingArchitecture/RequirementsGathering/ACMS_requirements_${specialist}/system.md" \
    "ACMS_requirements_${specialist} system.md"
done

# Demo scripts
for n in 01 02 03 05 06 07; do
  _found=$(ls demo/demo_${n}_*.sh 2>/dev/null | head -1)
  if [[ -n "$_found" ]]; then pass "demo_${n} script: $_found"
  else fail "demo_${n} script — MISSING"; fi
done

# ── 3. Tools ──────────────────────────────────────────────────────────────────
section "3. Required Tools"

check_cmd() {
  local cmd="$1" label="${2:-$1}"
  if command -v "$cmd" &>/dev/null; then
    pass "$label ($(command -v $cmd))"
  else
    fail "$label — not found in PATH"
  fi
}

check_cmd "fabric" "fabric"
check_cmd "ollama" "ollama"
check_cmd "python3" "python3"
check_cmd "uv" "uv"
check_cmd "git" "git"

# Fabric version
if command -v fabric &>/dev/null; then
  FABRIC_VER=$(fabric --version 2>/dev/null || echo "unknown")
  pass "fabric version: $FABRIC_VER"
fi

# ── 4. Models ─────────────────────────────────────────────────────────────────
section "4. Ollama Models"

check_model() {
  local model="$1"
  if ollama list 2>/dev/null | awk '{print $1}' | grep -qF "$model"; then
    pass "ollama model: $model"
  else
    fail "ollama model: $model — not pulled"
  fi
}

check_model "gemma3:12b"
check_model "qwen3:8b"

# Ollama running
if curl -s http://localhost:11434/api/tags &>/dev/null; then
  pass "Ollama server running (localhost:11434)"
else
  fail "Ollama server not responding — run: ollama serve"
fi

# ── 5. Fabric patterns ────────────────────────────────────────────────────────
section "5. Fabric Patterns"

PATTERNS_DIR="$HOME/.config/fabric/patterns_custom"
check_pattern() {
  local name="$1"
  if [[ -f "$PATTERNS_DIR/$name/system.md" ]]; then
    pass "pattern: $name"
  else
    fail "pattern: $name — not deployed to patterns_custom/"
  fi
}

check_pattern "system.md_transformers/from_system.md_to_system.yaml"
check_pattern "system.md_transformers/from_system.md_to_system.toon"
check_pattern "ACMS_extract_wisdom"
check_pattern "ACMS_requirements_identity"

# ── 6. Cost audit log ─────────────────────────────────────────────────────────
section "6. Cost Audit Log"

AUDIT_LOG="$HOME/.config/fabric/cost_audit.log"
if [[ -f "$AUDIT_LOG" ]]; then
  ENTRY_COUNT=$(wc -l < "$AUDIT_LOG")
  if [[ $ENTRY_COUNT -gt 0 ]]; then
    pass "cost_audit.log exists with $ENTRY_COUNT entries"
  else
    warn "cost_audit.log exists but is empty — run sync to populate"
  fi
else
  warn "cost_audit.log not found — will be created on first sync run"
fi

# ── 7. Syntax checks ──────────────────────────────────────────────────────────
section "7. Syntax Checks"

# YAML validation
for yaml_file in $(find . -name "system.yaml" | grep -v ".git\|_archive"); do
  if python3 -c "import yaml; yaml.safe_load(open('$yaml_file'))" 2>/dev/null; then
    pass "YAML valid: $yaml_file"
  else
    fail "YAML invalid: $yaml_file"
  fi
done

# Python syntax
if python3 -m py_compile cost/cost_analyzer.py 2>/dev/null; then
  pass "cost_analyzer.py syntax clean"
else
  fail "cost_analyzer.py syntax error"
fi

# Bash syntax
for script in sync_skill.sh; do
  if bash -n "$script" 2>/dev/null; then
    pass "$script syntax clean"
  else
    fail "$script syntax error"
  fi
done

# ── 8. Quick functional test ──────────────────────────────────────────────────
section "8. Functional Tests"

# Dry run sync
echo -e "  Running sync dry-run..."
if ./sync_skill.sh \
    --source CodingArchitecture/FabricStitch/ACMS_extract_wisdom/system.md \
    --dry-run --force \
    > /tmp/sync_dryrun.log 2>&1; then
  pass "sync_skill.sh dry-run passed"
else
  fail "sync_skill.sh dry-run failed — check /tmp/sync_dryrun.log"
fi

# cost_analyzer
if uv run python3 cost/cost_analyzer.py > /tmp/cost_check.log 2>&1; then
  pass "cost_analyzer.py runs without error"
else
  warn "cost_analyzer.py returned non-zero — may need log data"
fi

# Fabric smoke test (no LLM call)
if fabric --listpatterns | grep -q "ACMS_extract_wisdom" 2>/dev/null; then
  pass "fabric --listpatterns finds ACMS_extract_wisdom"
else
  warn "ACMS_extract_wisdom not in fabric pattern list"
fi

# ── Summary ───────────────────────────────────────────────────────────────────
echo -e "\n${BOLD}${CYAN}━━━ Preflight Summary ━━━${RESET}"
echo ""
TOTAL=$((PASS + FAIL + WARN))
echo -e "  ${GREEN}✓ PASS: $PASS${RESET}"
echo -e "  ${YELLOW}⚠ WARN: $WARN${RESET}"
echo -e "  ${RED}✗ FAIL: $FAIL${RESET}"
echo -e "  Total checks: $TOTAL"
echo ""

if [[ $FAIL -eq 0 ]]; then
  echo -e "${GREEN}${BOLD}  ✓ ALL CHECKS PASSED — Demo is GO${RESET}"
  echo ""
  echo -e "  ${BOLD}Demo run order:${RESET}"
  echo -e "  WSL2:  bash demo/demo_run.sh  (sections 1,2,3,5,6,7)"
  echo -e "  Win:   demo_04_monitor.ps1    (section 4 — Marimo)"
  echo ""
  echo -e "  ${CYAN}Estimated total time: 15-20 minutes${RESET}"
else
  echo -e "${RED}${BOLD}  ✗ $FAIL CHECK(S) FAILED — Fix before demo${RESET}"
  echo ""
  echo -e "  Review failed items above and resolve before March 16."
fi

echo ""
echo -e "${BOLD}  Repo: github.com/QCadjunct/aces-skills${RESET}"
echo -e "${BOLD}  Monitor: http://127.0.0.1:2718${RESET}"
echo ""
