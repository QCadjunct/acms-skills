#!/usr/bin/env bash
# launch_demo_preflight.sh
# ACMS Demo — Pre-flight health checks.
# Architecture Standard: Mind Over Metadata LLC — Peter Heller
#
# Run this 15 minutes before the co-chair joins.
# All five checks must pass before the demo starts.
#
# Usage:
#   ./launch_demo_preflight.sh

set -euo pipefail

NAVY='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
DIM='\033[2m'
RESET='\033[0m'
BOLD='\033[1m'

PASS=0
FAIL=0

print_header() {
  echo ""
  echo -e "${BOLD}${NAVY}╔══════════════════════════════════════════════════╗${RESET}"
  echo -e "${BOLD}${NAVY}║  ACMS Demo — Pre-Flight Checklist                ║${RESET}"
  echo -e "${BOLD}${NAVY}║  Mind Over Metadata LLC — Peter Heller           ║${RESET}"
  echo -e "${BOLD}${NAVY}╚══════════════════════════════════════════════════╝${RESET}"
  echo ""
}

check_pass() {
  echo -e "  ${GREEN}✓${RESET}  $1"
  PASS=$((PASS + 1))
}

check_fail() {
  echo -e "  ${RED}✗${RESET}  $1"
  echo -e "     ${DIM}→ $2${RESET}"
  FAIL=$((FAIL + 1))
}

check_warn() {
  echo -e "  ${YELLOW}⚠${RESET}  $1"
  echo -e "     ${DIM}→ $2${RESET}"
}

# ── Check 1: Ollama running ───────────────────────────────────────────────────
echo -e "${CYAN}[1/5]${RESET} Ollama — service and model"
if command -v ollama &>/dev/null; then
  if ollama list 2>/dev/null | grep -q "qwen3:8b"; then
    check_pass "Ollama running — qwen3:8b present"
  else
    check_fail "qwen3:8b not found" "Run: ollama pull qwen3:8b"
  fi
else
  check_fail "Ollama not found" "Install Ollama: https://ollama.com"
fi

# ── Check 2: Fabric DEFAULT_MODEL ────────────────────────────────────────────
echo -e "${CYAN}[2/5]${RESET} Fabric — DEFAULT_MODEL"
FABRIC_ENV="${HOME}/.config/fabric/.env"
if [[ -f "$FABRIC_ENV" ]] && grep -q "DEFAULT_MODEL=qwen3:8b" "$FABRIC_ENV"; then
  check_pass "Fabric DEFAULT_MODEL=qwen3:8b confirmed"
elif command -v fabric &>/dev/null; then
  check_warn "Fabric present but DEFAULT_MODEL not set to qwen3:8b" \
    "Run: echo 'DEFAULT_MODEL=qwen3:8b' >> ~/.config/fabric/.env"
else
  check_fail "Fabric not found" "Install: pip install fabric-ai"
fi

# ── Check 3: aces-skills repo clean ──────────────────────────────────────────
echo -e "${CYAN}[3/5]${RESET} aces-skills repo — git status"
SKILLS_REPO="${HOME}/projects/aces-skills"
if [[ -d "$SKILLS_REPO" ]]; then
  cd "$SKILLS_REPO"
  if git diff --quiet && git diff --cached --quiet; then
    BRANCH=$(git rev-parse --abbrev-ref HEAD)
    COMMIT=$(git log --oneline -1)
    check_pass "aces-skills clean on ${BRANCH} — ${COMMIT}"
  else
    check_warn "aces-skills has uncommitted changes" \
      "Run: git status  (changes visible during demo)"
  fi
  cd - > /dev/null
else
  check_fail "aces-skills not found at ${SKILLS_REPO}" \
    "Run: git clone https://github.com/QCadjunct/aces-skills ~/projects/aces-skills"
fi

# ── Check 4: deploy_generators.sh present ────────────────────────────────────
echo -e "${CYAN}[4/5]${RESET} deploy_generators.sh — present and executable"
DEPLOY_SCRIPT="${HOME}/projects/aces-skills/MetaArchitecture/ACMS_skill_deployers/ACMS_skill_deploy_generators/deploy_generators.sh"
if [[ -x "$DEPLOY_SCRIPT" ]]; then
  check_pass "deploy_generators.sh present and executable"
elif [[ -f "$DEPLOY_SCRIPT" ]]; then
  check_warn "deploy_generators.sh present but not executable" \
    "Run: chmod +x ${DEPLOY_SCRIPT}"
else
  check_fail "deploy_generators.sh not found" \
    "Expected: ${DEPLOY_SCRIPT}"
fi

# ── Check 5: ACMS Monitor reachable ──────────────────────────────────────────
echo -e "${CYAN}[5/5]${RESET} ACMS Monitor — http://127.0.0.1:2718"
if curl -s --max-time 2 http://127.0.0.1:2718 > /dev/null 2>&1; then
  check_pass "ACMS Monitor reachable at http://127.0.0.1:2718"
else
  check_warn "ACMS Monitor not yet running" \
    "Launch: .\\launch_monitor.ps1  (Windows PowerShell)"
fi

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo -e "${DIM}──────────────────────────────────────────────────${RESET}"
if [[ $FAIL -eq 0 ]]; then
  echo -e "  ${GREEN}${BOLD}All ${PASS} checks passed — ready for demo.${RESET}"
else
  echo -e "  ${GREEN}${PASS} passed${RESET}  ${RED}${FAIL} failed${RESET} — resolve failures before demo."
fi
echo ""
