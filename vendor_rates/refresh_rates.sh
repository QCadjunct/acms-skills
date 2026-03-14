#!/usr/bin/env bash
# refresh_rates.sh
# ACMS vendor_rates.yaml on-demand rate refresher
# © 2026 Mind Over Metadata LLC — Peter Heller
#
# Usage:
#   ./refresh_rates.sh              # interactive review + update
#   ./refresh_rates.sh --dry-run    # show current vs. known rates, no write
#   ./refresh_rates.sh --force      # update timestamp only, skip prompts
#
# This script does NOT auto-pull rates from an API (by design — ADR-008).
# It opens the pricing pages, shows current rates in vendor_rates.yaml,
# and walks you through confirming or updating each vendor's rates.
# Full automation via Perplexity is a post-POC enhancement.

set -euo pipefail

# ── Config ────────────────────────────────────────────────────────────────────
RATES_FILE="$(dirname "$0")/vendor_rates.yaml"
ARCHIVE_DIR="$(dirname "$0")/_archive"
TIMESTAMP=$(date +%Y%m%dT%H%M%S)
DRY_RUN=false
FORCE=false

# ── Arg parse ─────────────────────────────────────────────────────────────────
for arg in "$@"; do
  case $arg in
    --dry-run) DRY_RUN=true ;;
    --force)   FORCE=true ;;
    --help)
      echo "Usage: $0 [--dry-run] [--force] [--help]"
      exit 0
      ;;
  esac
done

# ── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

# ── Header ────────────────────────────────────────────────────────────────────
echo -e "${BOLD}${CYAN}"
echo "╔══════════════════════════════════════════════════════╗"
echo "║        ACMS vendor_rates.yaml Refresh Tool          ║"
echo "║        Mind Over Metadata LLC © 2026                ║"
echo "╚══════════════════════════════════════════════════════╝"
echo -e "${RESET}"

if [[ "$DRY_RUN" == true ]]; then
  echo -e "${YELLOW}[DRY RUN] No files will be written.${RESET}\n"
fi

# ── Validate rates file exists ────────────────────────────────────────────────
if [[ ! -f "$RATES_FILE" ]]; then
  echo -e "${RED}ERROR: vendor_rates.yaml not found at: $RATES_FILE${RESET}"
  exit 1
fi

# ── Show current validated date ───────────────────────────────────────────────
CURRENT_DATE=$(grep "validated_date" "$RATES_FILE" | awk -F'"' '{print $2}')
DAYS_SINCE=$(( ( $(date +%s) - $(date -d "$CURRENT_DATE" +%s 2>/dev/null || date -j -f "%Y-%m-%d" "$CURRENT_DATE" +%s) ) / 86400 ))

echo -e "${BOLD}Current rates validated:${RESET} $CURRENT_DATE (${DAYS_SINCE} days ago)"
echo ""

# ── Show current rates summary ────────────────────────────────────────────────
echo -e "${BOLD}Current rates in vendor_rates.yaml:${RESET}"
echo ""
echo -e "${CYAN}Anthropic:${RESET}"
echo "  claude-sonnet-4-6  in: \$0.000003   out: \$0.000015"
echo "  claude-haiku-4-5   in: \$0.0000008  out: \$0.000004"
echo "  claude-opus-4-6    in: \$0.000015   out: \$0.000075"
echo ""
echo -e "${CYAN}Google:${RESET}"
echo "  gemini-2.0-flash       in: \$0.000000375  out: \$0.0000015"
echo "  gemini-2.0-flash-lite  in: \$0.000000075  out: \$0.000000300"
echo "  gemini-2.5-pro         in: \$0.00000125   out: \$0.000010"
echo ""
echo -e "${CYAN}Ollama (local):${RESET}"
echo "  all models             in: \$0.000000000  out: \$0.000000000"
echo ""

# ── Open pricing pages ────────────────────────────────────────────────────────
if [[ "$FORCE" == false && "$DRY_RUN" == false ]]; then
  echo -e "${BOLD}Pricing pages to verify:${RESET}"
  echo "  Anthropic: https://www.anthropic.com/pricing"
  echo "  Google:    https://ai.google.dev/pricing"
  echo ""

  # Try to open browser (WSL2-aware)
  if command -v explorer.exe &>/dev/null; then
    explorer.exe "https://www.anthropic.com/pricing" 2>/dev/null || true
    sleep 1
    explorer.exe "https://ai.google.dev/pricing" 2>/dev/null || true
  elif command -v xdg-open &>/dev/null; then
    xdg-open "https://www.anthropic.com/pricing" 2>/dev/null || true
    xdg-open "https://ai.google.dev/pricing" 2>/dev/null || true
  fi

  echo -e "${YELLOW}Review the pricing pages, then press ENTER to continue...${RESET}"
  read -r

  echo ""
  echo "Have rates changed since $CURRENT_DATE? [y/N]"
  read -r RATES_CHANGED

  if [[ "$RATES_CHANGED" =~ ^[Yy]$ ]]; then
    echo ""
    echo -e "${YELLOW}Open vendor_rates.yaml in your editor, update the rates,"
    echo -e "then run this script again with --force to update the timestamp.${RESET}"
    echo ""
    echo "  code vendor_rates.yaml    # VS Code"
    echo "  nano vendor_rates.yaml    # nano"
    echo ""
    echo "After editing: ./refresh_rates.sh --force"
    exit 0
  fi
fi

# ── Archive current file ───────────────────────────────────────────────────────
if [[ "$DRY_RUN" == false ]]; then
  mkdir -p "$ARCHIVE_DIR"
  cp "$RATES_FILE" "$ARCHIVE_DIR/vendor_rates_${TIMESTAMP}.yaml"
  echo -e "${GREEN}✓ Archived: vendor_rates_${TIMESTAMP}.yaml${RESET}"
fi

# ── Update validated_date and updated_by ──────────────────────────────────────
TODAY=$(date +%Y-%m-%d)

if [[ "$DRY_RUN" == false ]]; then
  sed -i "s/validated_date: \".*\"/validated_date: \"$TODAY\"/" "$RATES_FILE"
  sed -i "s/Last updated: .*/Last updated: $TODAY/" "$RATES_FILE"
  echo -e "${GREEN}✓ Updated validated_date to $TODAY${RESET}"
fi

# ── Cost audit log entry ──────────────────────────────────────────────────────
AUDIT_LOG="$HOME/.config/fabric/cost_audit.log"
mkdir -p "$(dirname "$AUDIT_LOG")"

if [[ "$DRY_RUN" == false ]]; then
  echo "[${TIMESTAMP}] refresh_rates.sh | validated_date=${TODAY} | rates_changed=false | cost=\$0.000000" >> "$AUDIT_LOG"
  echo -e "${GREEN}✓ Audit log entry written${RESET}"
fi

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}${GREEN}╔══════════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}${GREEN}║  vendor_rates.yaml — refresh complete        ║${RESET}"
echo -e "${BOLD}${GREEN}║  validated_date: $TODAY                ║${RESET}"
echo -e "${BOLD}${GREEN}║  rates_changed:  false                       ║${RESET}"
if [[ "$DRY_RUN" == true ]]; then
echo -e "${BOLD}${GREEN}║  mode: DRY RUN — no files written            ║${RESET}"
fi
echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════════╝${RESET}"
