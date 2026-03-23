#!/usr/bin/env bash
# launch_demo3_monitor.sh
# ACMS Demo Step 03 — open ACMS Monitor in browser.
# Architecture Standard: Mind Over Metadata LLC — Peter Heller
#
# The monitor is pre-warmed during pre-flight (launch_monitor.ps1 already running).
# This script opens the browser to the live monitor URL.
#
# Usage:
#   ./launch_demo3_monitor.sh

set -euo pipefail

NAVY='\033[0;34m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
DIM='\033[2m'
RESET='\033[0m'
BOLD='\033[1m'

MONITOR_URL="http://127.0.0.1:2718"

echo ""
echo -e "${BOLD}${NAVY}╔══════════════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}${NAVY}║  Demo Step 03 — ACMS Monitor                     ║${RESET}"
echo -e "${BOLD}${NAVY}║  Marimo — Reactive Dashboard                     ║${RESET}"
echo -e "${BOLD}${NAVY}╚══════════════════════════════════════════════════╝${RESET}"
echo ""
echo -e "  ${CYAN}URL  :${RESET} ${MONITOR_URL}"
echo -e "  ${CYAN}Tabs :${RESET} Audit Trail · Registry · Pipeline · Cost · Cost Detail · About"
echo ""
echo -e "  ${DIM}Talking point: 'Marimo — the modern DECforms. Reactive, not sequential."
echo -e "  Six tabs. Cost tab shows every dollar. Cost Detail drills to every row."
echo -e "  About tab has the full architecture and Task Groups roadmap.'${RESET}"
echo ""
echo -e "  ${DIM}What to show first: Cost tab → By vendor table → filter Cost Detail to Anthropic${RESET}"
echo ""
echo -e "  ${DIM}──────────────────────────────────────────────────${RESET}"
echo ""

# Check monitor is reachable before opening
if curl -s --max-time 2 "$MONITOR_URL" > /dev/null 2>&1; then
  echo -e "  ${GREEN}✓${RESET}  Monitor is running — opening browser..."
  explorer.exe "$MONITOR_URL"
else
  echo -e "  ${YELLOW}⚠${RESET}  Monitor not reachable at ${MONITOR_URL}"
  echo ""
  echo -e "  Start it now from Windows PowerShell:"
  echo -e "  ${CYAN}  cd \"Z:\\VSCODE Projects\\PythonProjects\\aces-repo\"${RESET}"
  echo -e "  ${CYAN}  .\\launch_monitor.ps1${RESET}"
  echo ""
  echo -e "  Then re-run this script."
  exit 1
fi
