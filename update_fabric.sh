#!/usr/bin/env bash
# update_fabric.sh
# Update Fabric to latest patterns then immediately restore ACMS customizations.
#
# Sequence:
#   1. fabric --updatepatterns  (pulls latest from danielmiessler/fabric)
#   2. ./sync_patterns.sh       (restores ACMS custom patterns to patterns/)
#   3. Report: new patterns added, customizations restored
#
# Usage:
#   ./update_fabric.sh              — full update + sync
#   ./update_fabric.sh --dry-run    — preview sync without writing
#   ./update_fabric.sh --skip-update — skip fabric update, just sync patterns
#
# Mind Over Metadata LLC © 2026 — Peter Heller
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PATTERNS_DIR="$HOME/.config/fabric/patterns"
CUSTOM_DIR="$HOME/.config/fabric/patterns_custom"
DRY_RUN=false
SKIP_UPDATE=false

BOLD='\033[1m'; CYAN='\033[0;36m'; GREEN='\033[0;32m'
YELLOW='\033[0;33m'; RESET='\033[0m'

for arg in "$@"; do
  case "$arg" in
    --dry-run)     DRY_RUN=true ;;
    --skip-update) SKIP_UPDATE=true ;;
  esac
done

echo -e "\n${BOLD}${CYAN}╔══════════════════════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}${CYAN}║  update_fabric.sh — Fabric Update + ACMS Sync           ║${RESET}"
echo -e "${BOLD}${CYAN}║  Mind Over Metadata LLC © 2026 — Peter Heller           ║${RESET}"
echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════════════════╝${RESET}"
echo ""

# ── Step 1: Count patterns before update ──────────────────────────────────────
BEFORE=$(find "$PATTERNS_DIR" -maxdepth 1 -type d | wc -l)
echo -e "  Patterns before update: ${CYAN}$BEFORE${RESET}"

# ── Step 2: fabric --updatepatterns ───────────────────────────────────────────
if [[ "$SKIP_UPDATE" == false ]]; then
  echo ""
  echo -e "  ${BOLD}Step 1/3 — fabric --updatepatterns${RESET}"
  if [[ "$DRY_RUN" == false ]]; then
    if command -v fabric &>/dev/null; then
      fabric --updatepatterns 2>&1 | tail -5
      echo -e "  ${GREEN}✓ Fabric patterns updated${RESET}"
    else
      echo -e "  ${YELLOW}⚠ fabric not found in PATH${RESET}"
    fi
  else
    echo -e "  [DRY RUN] Would run: fabric --updatepatterns"
  fi
else
  echo -e "  ${YELLOW}Step 1/3 — Skipping fabric --updatepatterns (--skip-update)${RESET}"
fi

# ── Step 3: Count patterns after update ───────────────────────────────────────
AFTER=$(find "$PATTERNS_DIR" -maxdepth 1 -type d | wc -l)
NEW_PATTERNS=$((AFTER - BEFORE))
echo ""
echo -e "  Patterns after update : ${CYAN}$AFTER${RESET}"
if [[ $NEW_PATTERNS -gt 0 ]]; then
  echo -e "  ${GREEN}✓ $NEW_PATTERNS new patterns added${RESET}"
else
  echo -e "  ─ No new patterns (already current)"
fi

# ── Step 4: Restore ACMS customizations ───────────────────────────────────────
echo ""
echo -e "  ${BOLD}Step 2/3 — Restore ACMS custom patterns${RESET}"

SYNC_SCRIPT="$SCRIPT_DIR/sync_patterns.sh"

# Try repo location if not in same dir
if [[ ! -f "$SYNC_SCRIPT" ]]; then
  SYNC_SCRIPT="$HOME/projects/aces-skills/sync_patterns.sh"
fi
if [[ ! -f "$SYNC_SCRIPT" ]]; then
  SYNC_SCRIPT="$(find "$HOME/projects" -name "sync_patterns.sh" 2>/dev/null | head -1)"
fi

if [[ -f "$SYNC_SCRIPT" ]]; then
  if [[ "$DRY_RUN" == false ]]; then
    bash "$SYNC_SCRIPT"
  else
    bash "$SYNC_SCRIPT" --dry-run
  fi
else
  echo -e "  ${YELLOW}⚠ sync_patterns.sh not found — manual sync required${RESET}"
  echo -e "  Copy sync_patterns.sh to the same directory as update_fabric.sh"
fi

# ── Step 5: Verify ACMS patterns are accessible ───────────────────────────────
echo -e "  ${BOLD}Step 3/3 — Verify ACMS patterns accessible${RESET}"
echo ""

ACMS_PATTERNS=(
  "ACMS_extract_wisdom"
  "synthesize_eloquent_narrative_from_wisdom"
  "from_cognitive_blueprint_to_system_md"
  "from_system.md_to_system.yaml"
  "from_system.md_to_system.toon"
  "ACMS_requirements_identity"
)

ALL_OK=true
for pattern in "${ACMS_PATTERNS[@]}"; do
  if fabric --listpatterns 2>/dev/null | grep -q "^${pattern}$"; then
    echo -e "  ${GREEN}✓${RESET} $pattern"
  else
    echo -e "  ${YELLOW}⚠${RESET} $pattern — not in fabric list (may still work with --pattern)"
    # Check if file exists even if not listed
    if [[ -f "$PATTERNS_DIR/$pattern/system.md" ]]; then
      echo -e "      File exists — chmod fix:"
      [[ "$DRY_RUN" == false ]] && chmod +x "$PATTERNS_DIR/$pattern/system.md"
      echo -e "      ${GREEN}✓ chmod +x applied${RESET}"
    else
      ALL_OK=false
    fi
  fi
done

echo ""
if [[ "$ALL_OK" == true ]]; then
  echo -e "  ${GREEN}${BOLD}✓ All ACMS patterns verified — Fabric is current${RESET}"
else
  echo -e "  ${YELLOW}⚠ Some patterns missing — run sync_patterns.sh manually${RESET}"
fi

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo -e "  ${BOLD}Next steps:${RESET}"
echo -e "  • New Fabric patterns available: ${CYAN}fabric --listpatterns${RESET}"
echo -e "  • Test ACMS pipeline: ${CYAN}./sync_skill.sh --source <path> --dry-run${RESET}"
echo -e "  • Update vendor_rates.yaml if new models were added"
echo ""
