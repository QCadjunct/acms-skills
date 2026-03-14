#!/usr/bin/env python3
# task_complete.py
# ACMS Lifecycle Hook — Task Complete
# Skill:     ACMS_extract_wisdom
# Domain:    CodingArchitecture/FabricStitch
# Generated: 2026-03-14
# Generator: ACMS_hook_generator (CodingArchitecture/HookGenerator)
# Pattern:   stdlib-only — ADR-008 (alirezarezvani/claude-skills attribution)
# © 2026 Mind Over Metadata LLC — Peter Heller
# Zero pip dependencies — runs on any Python 3.8+
#
# Invoked when the agent signals task completion via task_complete tool.
# Validates output, computes total session cost, writes audit summary,
# cleans up scratch files. Exit 1 if output validation fails.

import os
import sys
import json
import re
import shutil
from datetime import datetime
from pathlib import Path

# ── Skill constants ────────────────────────────────────────────────────────────
SKILL_NAME = "ACMS_extract_wisdom"
SKILL_FQSN = "CodingArchitecture/FabricStitch/ACMS_extract_wisdom"

# Expected output files — derived from system.md mission
# ACMS_extract_wisdom writes extracted wisdom to stdout or a named output file
EXPECTED_OUTPUTS: list[str] = []   # stdout-based skill — no file outputs required

# ── Paths ──────────────────────────────────────────────────────────────────────
AUDIT_LOG   = Path.home() / ".config" / "fabric" / "hook_audit.log"
COST_LOG    = Path.home() / ".config" / "fabric" / "cost_audit.log"
DEPLOY_LOG  = Path.home() / ".config" / "fabric" / "deploy_audit.log"
SCRATCH_DIR = Path("/tmp")
SCRATCH_GLOB = f"acms_{SKILL_NAME}_*.json"

def log_audit(timestamp: str, result: str, total_cost: float,
              duration_ms: int, detail: str = "") -> None:
    AUDIT_LOG.parent.mkdir(parents=True, exist_ok=True)
    entry = (
        f"[{timestamp}] task_complete.py | skill={SKILL_NAME} | "
        f"result={result} | total_cost=${total_cost:.6f} | "
        f"duration={duration_ms}ms"
    )
    if detail:
        entry += f" | detail={detail}"
    entry += "\n"
    with open(AUDIT_LOG, "a") as f:
        f.write(entry)

def compute_session_cost() -> tuple[float, int]:
    """Sum all cost entries for this skill from cost_audit.log."""
    total_cost   = 0.0
    entry_count  = 0
    pattern      = re.compile(rf"skill={re.escape(SKILL_NAME)}.*cost=\$([0-9.]+)")

    if not COST_LOG.exists():
        return 0.0, 0

    with open(COST_LOG) as f:
        for line in f:
            m = pattern.search(line)
            if m:
                try:
                    total_cost += float(m.group(1))
                    entry_count += 1
                except ValueError:
                    pass

    return total_cost, entry_count

def validate_outputs() -> list[str]:
    """Validate expected output files exist. Returns list of missing files."""
    missing = []
    for path_str in EXPECTED_OUTPUTS:
        p = Path(path_str).expanduser()
        if not p.exists():
            missing.append(str(p))
    return missing

def cleanup_scratch() -> int:
    """Remove /tmp/acms_{SKILL_NAME}_*.json scratch files."""
    removed = 0
    for f in SCRATCH_DIR.glob(SCRATCH_GLOB):
        try:
            f.unlink()
            removed += 1
        except OSError:
            pass
    return removed

def write_deploy_summary(timestamp: str, total_cost: float,
                         entry_count: int, duration_ms: int,
                         missing_outputs: list[str]) -> None:
    DEPLOY_LOG.parent.mkdir(parents=True, exist_ok=True)
    summary = {
        "timestamp":      timestamp,
        "skill":          SKILL_NAME,
        "fqsn":           SKILL_FQSN,
        "result":         "PASS" if not missing_outputs else "FAIL",
        "total_cost":     f"${total_cost:.6f}",
        "cost_entries":   entry_count,
        "duration_ms":    duration_ms,
        "missing_outputs": missing_outputs,
    }
    with open(DEPLOY_LOG, "a") as f:
        f.write(json.dumps(summary) + "\n")

def main() -> int:
    timestamp  = datetime.now().isoformat()
    start_time = datetime.now()

    # Step 1: Validate expected outputs
    missing = validate_outputs()

    # Step 2: Compute total session cost
    total_cost, entry_count = compute_session_cost()

    # Step 3: Cleanup scratch files
    removed = cleanup_scratch()

    duration_ms = int((datetime.now() - start_time).total_seconds() * 1000)

    # Step 4: Write deploy audit summary
    write_deploy_summary(timestamp, total_cost, entry_count, duration_ms, missing)

    # Step 5: Print completion receipt (mirrors deploy_generators.sh Step 9)
    result = "PASS" if not missing else "FAIL"
    print(f"╔══════════════════════════════════════════════════════════╗")
    print(f"║  ACMS task_complete — {SKILL_NAME:<35} ║")
    print(f"║  Result:      {result:<43} ║")
    print(f"║  Total cost:  ${total_cost:.6f} ({entry_count} cost entries){'':<17} ║")
    print(f"║  Duration:    {duration_ms}ms{'':<42} ║")
    print(f"║  Scratch:     {removed} file(s) cleaned up{'':<31} ║")
    if missing:
        for m in missing:
            print(f"║  MISSING:     {m:<43} ║")
    print(f"╚══════════════════════════════════════════════════════════╝")

    # Log to audit
    detail = f"cost_entries={entry_count} | scratch_removed={removed}"
    if missing:
        detail += f" | missing={missing}"
    log_audit(timestamp, result, total_cost, duration_ms, detail)

    # Exit 1 if output validation failed
    if missing:
        sys.stderr.write(
            f"[{timestamp}] task_complete.py | skill={SKILL_NAME} | "
            f"FAIL — missing expected outputs: {missing}\n"
        )
        return 1

    return 0

if __name__ == "__main__":
    sys.exit(main())
