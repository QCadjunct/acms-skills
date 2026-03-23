#!/usr/bin/env bash
# demo_run.sh — Master demo launcher
# ACMS POC Demo — Mind Over Metadata LLC © 2026 — Peter Heller
# Run from: ~/projects/aces-skills/demo/
# ─────────────────────────────────────────────────────────────────────────────

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

BOLD='\033[1m'; CYAN='\033[0;36m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; RESET='\033[0m'

echo -e "\n${BOLD}${CYAN}╔══════════════════════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}${CYAN}║  ACMS POC Demo — Master Launcher                        ║${RESET}"
echo -e "${BOLD}${CYAN}║  Mind Over Metadata LLC © 2026 — Peter Heller           ║${RESET}"
echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════════════════╝${RESET}\n"

echo -e "  ${BOLD}Sections:${RESET}"
echo -e "  [1] Architecture Overview         (~2 min)"
echo -e "  [2] Live Sync Pipeline            (~3 min, runs gemma3:12b)"
echo -e "  [3] D⁴ MDLC Cost Intelligence     (~2 min)"
echo -e "  [4] Marimo Monitor                (PowerShell — run separately)"
echo -e "  [5] PrincipalSystemArchitect      (~3 min, runs gemma3:12b)"
echo -e "  [6] Fabric Multi-Vendor Pipeline  (~3 min, runs gemma3:12b)"
echo -e "  [7] ADR-009 Provenance Chain      (~2 min)"
echo -e "  [A] Run all WSL2 sections (1,2,3,5,6,7)"
echo ""
echo -e "  ${YELLOW}Note: Section 4 (Marimo) runs in PowerShell on Windows.${RESET}"
echo -e "  ${YELLOW}      Run demo_04_monitor.ps1 in a separate terminal.${RESET}"
echo ""
read -p "Enter section number (1-7, A for all): " CHOICE

case "$CHOICE" in
  1) bash demo/demo_01_architecture.sh ;;
  2) bash demo/demo_02_sync.sh ;;
  3) bash demo/demo_03_cost.sh ;;
  4) echo -e "\n${YELLOW}Run in PowerShell:${RESET}"
     echo -e "  cd 'Z:\\VSCODE Projects\\PythonProjects\\aces-repo'"
     echo -e "  powershell -ExecutionPolicy Bypass -File demo\\demo_04_monitor.ps1" ;;
  5) bash demo/demo_05_psa.sh ;;
  6) bash demo/demo_06_fabric.sh ;;
  7) bash demo/demo_07_adr009.sh ;;
  [Aa])
     bash demo/demo_01_architecture.sh
     bash demo/demo_02_sync.sh
     bash demo/demo_03_cost.sh
     bash demo/demo_05_psa.sh
     bash demo/demo_06_fabric.sh
     bash demo/demo_07_adr009.sh
     ;;
  *) echo -e "${YELLOW}Invalid choice. Run individual scripts directly.${RESET}" ;;
esac
