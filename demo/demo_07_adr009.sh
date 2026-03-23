#!/usr/bin/env bash
# demo_07_adr009.sh
# ACMS POC Demo — Section 7: ADR-009 Provenance Chain
# Mind Over Metadata LLC © 2026 — Peter Heller
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

BOLD='\033[1m'; CYAN='\033[0;36m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; RESET='\033[0m'

banner() {
  echo -e "\n${BOLD}${CYAN}╔══════════════════════════════════════════════════════════╗${RESET}"
  echo -e "${BOLD}${CYAN}║  $1$(printf '%*s' $((54 - ${#1})) '')║${RESET}"
  echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════════════════╝${RESET}\n"
}

section() { echo -e "\n${BOLD}${YELLOW}━━━ $1 ━━━${RESET}\n"; }

banner "ACMS POC — Section 7: ADR-009 Provenance Chain"

# ── ADR-009 overview ──────────────────────────────────────────────────────────
section "7.1 — ADR-009: Why Provenance Matters"
echo -e "The D⁴ MDLC principle: ${BOLD}every token has a cost, every cost has a source${RESET}.\n"
echo -e "ADR-009 establishes the governance framework for agentic AI cost accounting."
echo -e "Every pipeline component — sync, deploy, hook, fabric_stitch — writes"
echo -e "a standardized 16-field cost entry. The RUN_ID chains all entries from"
echo -e "a single run. The UPSTREAM_ID chains execution back to the sync that"
echo -e "produced the artifacts.\n"
echo -e "  ${BOLD}16 fields:${RESET}"
echo -e "  [1]  timestamp       — ISO 8601"
echo -e "  [2]  component       — sync_skill | deploy_generators | post_tool_call | task_complete"
echo -e "  [3]  RUN_ID          — uuidv4 per run"
echo -e "  [4]  skill_fqsn      — CodingArchitecture/FabricStitch/ACMS_extract_wisdom"
echo -e "  [5]  artifact        — skill.system.md | skill.system.yaml | skill.system.toon"
echo -e "  [6]  vendor          — ollama | anthropic | google"
echo -e "  [7]  model           — gemma3:12b | claude-sonnet-4-6 | gemini-2.0-flash"
echo -e "  [8]  tokens_in       — input token count"
echo -e "  [9]  tokens_out      — output token count"
echo -e "  [10] cost_in         — input cost USD"
echo -e "  [11] cost_out        — output cost USD"
echo -e "  [12] cost_total      — total cost USD"
echo -e "  [13] elapsed_ms      — wall clock time"
echo -e "  [14] env             — dev | staging | prod"
echo -e "  [15] upstream_id     — RUN_ID of prior sync (provenance chain)"
echo -e "  [16] notes           — free text"

read -p "Press Enter to view live cost_audit.log →"

# ── Live log ──────────────────────────────────────────────────────────────────
section "7.2 — Live cost_audit.log"
AUDIT_LOG="$HOME/.config/fabric/cost_audit.log"

if [[ -f "$AUDIT_LOG" ]] && [[ -s "$AUDIT_LOG" ]]; then
  ENTRY_COUNT=$(wc -l < "$AUDIT_LOG")
  echo -e "  Log: ${CYAN}$AUDIT_LOG${RESET}"
  echo -e "  Entries: ${GREEN}$ENTRY_COUNT${RESET}\n"

  # Show entries formatted
  echo -e "${BOLD}Entries by artifact (formatted):${RESET}\n"
  while IFS='|' read -r ts comp run_id skill artifact vendor model \
      tok_in tok_out cost_in cost_out cost_total elapsed env upstream notes; do
    ts=$(echo "$ts" | tr -d '[]' | xargs)
    artifact=$(echo "$artifact" | xargs)
    tok_in=$(echo "$tok_in" | xargs)
    tok_out=$(echo "$tok_out" | xargs)
    cost_total=$(echo "$cost_total" | xargs)
    elapsed=$(echo "$elapsed" | xargs)
    echo -e "  ${CYAN}${artifact}${RESET}"
    echo -e "    tokens: in=${tok_in} out=${tok_out}  cost=\$${cost_total}  elapsed=${elapsed}ms"
  done < "$AUDIT_LOG"

  # Extract and display RUN_IDs
  echo ""
  echo -e "${BOLD}RUN_IDs in this log:${RESET}"
  awk -F'|' '{print $3}' "$AUDIT_LOG" | sort -u | while read run_id; do
    run_id=$(echo "$run_id" | xargs)
    count=$(grep -c "$run_id" "$AUDIT_LOG" 2>/dev/null || echo 0)
    echo -e "  ${GREEN}$run_id${RESET} ($count entries)"
  done
else
  echo -e "${YELLOW}No log entries found.${RESET}"
  echo "Run Section 2 (demo_02_sync.sh) to populate the log."
fi

read -p "Press Enter for full projection analysis →"

# ── Projection ────────────────────────────────────────────────────────────────
section "7.3 — Cost Projection: 100 Skills Scenario"
echo -e "If this skill set scales to 100 skills:\n"
uv run python3 cost/cost_analyzer.py --projection 0.20 2>/dev/null || \
  echo -e "${YELLOW}Run with: uv run python3 cost/cost_analyzer.py --projection 0.20${RESET}"

# ── Components that write ADR-009 ─────────────────────────────────────────────
section "7.4 — All Components Writing ADR-009 Entries"
echo -e "  ${GREEN}✓${RESET} sync_skill.sh         — 5 entries per sync (Step 9)"
echo -e "  ${GREEN}✓${RESET} deploy_generators.sh  — 5 entries per deploy (Step 9)"
echo -e "  ${GREEN}✓${RESET} post_tool_call.py     — 1 entry per tool call"
echo -e "  ${GREEN}✓${RESET} task_complete.py      — 1 session.total entry per task"
echo ""
echo -e "  ${YELLOW}Planned:${RESET}"
echo -e "  ○ fabric_stitch.sh    — 1 entry per pipeline step"
echo -e "  ○ langgraph nodes     — 1 entry per node execution"
echo -e "  ○ PSA elicitation     — 1 entry per specialist dispatch"

# ── Marimo D⁴ MDLC tab ───────────────────────────────────────────────────────
section "7.5 — Marimo Monitor: D⁴ MDLC Tab"
echo -e "The Marimo monitor reads cost_audit.log live via WSL2 UNC path."
echo -e "Every sync run updates the D⁴ MDLC tab automatically on refresh.\n"
echo -e "  WSL2 path: ${CYAN}\\\\wsl\$\\Ubuntu\\home\\pheller\\.config\\fabric\\cost_audit.log${RESET}"
echo -e "  Monitor:   ${CYAN}http://127.0.0.1:2718${RESET} → Tab 6: 🧬 D⁴ MDLC"

# ── Final summary ─────────────────────────────────────────────────────────────
section "7.6 — ACMS POC: What We Built Today"
echo -e "  ${GREEN}✓${RESET} ADR-009 governance spec — D⁴ MDLC cost accounting standard"
echo -e "  ${GREEN}✓${RESET} sync_skill.sh — 9-step pipeline, ADR-009, gemma3:12b"
echo -e "  ${GREEN}✓${RESET} deploy_generators.sh — ADR-009 cost tracking"
echo -e "  ${GREEN}✓${RESET} Hook scripts — post_tool_call + task_complete ADR-009"
echo -e "  ${GREEN}✓${RESET} cost_analyzer.py — bloat detection, TOON comparison, projection"
echo -e "  ${GREEN}✓${RESET} Marimo monitor — 7 tabs, D⁴ MDLC tab live"
echo -e "  ${GREEN}✓${RESET} PrincipalSystemArchitect — meta-contract, 6-step elicitation"
echo -e "  ${GREEN}✓${RESET} RequirementsGathering — 6 specialist skills"
echo -e "  ${GREEN}✓${RESET} fabric-guide.md — comprehensive CLI reference"
echo ""
echo -e "  ${BOLD}Repo:${RESET} github.com/QCadjunct/aces-skills"
echo -e "  ${BOLD}Repo:${RESET} github.com/QCadjunct/aces-repo"
echo ""
echo -e "${BOLD}${GREEN}╔══════════════════════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}${GREEN}║  ACMS POC Demo Complete                                 ║${RESET}"
echo -e "${BOLD}${GREEN}║  Mind Over Metadata LLC © 2026 — Peter Heller           ║${RESET}"
echo -e "${BOLD}${GREEN}║  D⁴ MDLC — Domain-Driven Database Design               ║${RESET}"
echo -e "${BOLD}${GREEN}║           Metadata-Driven Lifecycle                     ║${RESET}"
echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════════════════════╝${RESET}"
