#!/usr/bin/env bash
# launch_demo5_github.sh
# ACMS Demo Step 05 — open GitHub repos in browser.
# Architecture Standard: Mind Over Metadata LLC — Peter Heller
#
# Opens both repos in sequence — aces-skills first, then acms-langgraph-poc.
#
# Usage:
#   ./launch_demo5_github.sh

set -euo pipefail

NAVY='\033[0;34m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
DIM='\033[2m'
RESET='\033[0m'
BOLD='\033[1m'

SKILLS_URL="https://github.com/QCadjunct/aces-skills"
POC_URL="https://github.com/QCadjunct/acms-langgraph-poc"

echo ""
echo -e "${BOLD}${NAVY}╔══════════════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}${NAVY}║  Demo Step 05 — GitHub Repos                     ║${RESET}"
echo -e "${BOLD}${NAVY}║  Public · Documented · Committed                 ║${RESET}"
echo -e "${BOLD}${NAVY}╚══════════════════════════════════════════════════╝${RESET}"
echo ""
echo -e "  ${CYAN}Repo 1 :${RESET} ${SKILLS_URL}"
echo -e "  ${CYAN}Repo 2 :${RESET} ${POC_URL}"
echo ""
echo -e "  ${DIM}Talking point: 'Everything is public, documented, and committed."
echo -e "  This is a proof of concept with receipts at every level."
echo -e "  Not a demo. Not a slide deck.'${RESET}"
echo ""
echo -e "  ${DIM}What to show: README → MetaArchitecture/ → CodingArchitecture/FabricStitch/${RESET}"
echo -e "  ${DIM}             → system.md / system.yaml / system.toon trifecta${RESET}"
echo -e "  ${DIM}             → Commit history (two commits from today visible)${RESET}"
echo ""
echo -e "  ${DIM}──────────────────────────────────────────────────${RESET}"
echo ""

echo -e "  ${GREEN}→${RESET}  Opening aces-skills..."
explorer.exe "$SKILLS_URL"
sleep 1
echo -e "  ${GREEN}→${RESET}  Opening acms-langgraph-poc..."
explorer.exe "$POC_URL"
