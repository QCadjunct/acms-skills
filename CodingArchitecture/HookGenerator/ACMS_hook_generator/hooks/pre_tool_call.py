#!/usr/bin/env python3
# pre_tool_call.py
# ACMS Lifecycle Hook — Pre Tool Call
# Skill:     ACMS_extract_wisdom
# Domain:    CodingArchitecture/FabricStitch
# Generated: 2026-03-14
# Generator: ACMS_hook_generator (CodingArchitecture/HookGenerator)
# Pattern:   stdlib-only — ADR-008 (alirezarezvani/claude-skills attribution)
# © 2026 Mind Over Metadata LLC — Peter Heller
# Zero pip dependencies — runs on any Python 3.8+

import os
import sys
import json
from datetime import datetime
from pathlib import Path

# ── Skill constants ────────────────────────────────────────────────────────────
SKILL_NAME      = "ACMS_extract_wisdom"
SKILL_DOMAIN    = "CodingArchitecture/FabricStitch"
SKILL_FQSN      = "CodingArchitecture/FabricStitch/ACMS_extract_wisdom"

# Authorized tools derived from system.md # Tools section
AUTHORIZED_TOOLS = {
    "fabric_pattern",
    "file_write",
    "file_read",
}

# ── Paths ──────────────────────────────────────────────────────────────────────
AUDIT_LOG    = Path.home() / ".config" / "fabric" / "hook_audit.log"
SCRATCH_FILE = Path("/tmp") / f"acms_{SKILL_NAME}_pre.json"

# ── Required environment variables ────────────────────────────────────────────
REQUIRED_ENV = [
    "ACMS_SKILL_NAME",   # must match SKILL_NAME
]

def log_audit(timestamp: str, tool: str, result: str, detail: str = "") -> None:
    AUDIT_LOG.parent.mkdir(parents=True, exist_ok=True)
    entry = (
        f"[{timestamp}] pre_tool_call.py | skill={SKILL_NAME} | "
        f"tool={tool} | result={result}"
    )
    if detail:
        entry += f" | detail={detail}"
    entry += "\n"
    with open(AUDIT_LOG, "a") as f:
        f.write(entry)

def main() -> int:
    timestamp = datetime.now().isoformat()
    tool_name = os.environ.get("ACMS_TOOL_NAME", "unknown")
    skill_env = os.environ.get("ACMS_SKILL_NAME", "")

    # Guard 1: skill name must match
    if skill_env and skill_env != SKILL_NAME:
        msg = f"ACMS_SKILL_NAME mismatch: expected {SKILL_NAME}, got {skill_env}"
        sys.stderr.write(f"[{timestamp}] pre_tool_call.py | {msg}\n")
        log_audit(timestamp, tool_name, "BLOCKED", msg)
        return 1

    # Guard 2: tool must be authorized
    if tool_name not in AUTHORIZED_TOOLS and tool_name != "unknown":
        msg = f"tool '{tool_name}' not in authorized list: {sorted(AUTHORIZED_TOOLS)}"
        sys.stderr.write(f"[{timestamp}] pre_tool_call.py | skill={SKILL_NAME} | {msg}\n")
        log_audit(timestamp, tool_name, "BLOCKED", msg)
        return 1

    # Check required env vars (warn only, not fatal)
    missing = [v for v in REQUIRED_ENV if not os.environ.get(v)]
    if missing:
        sys.stderr.write(
            f"[{timestamp}] pre_tool_call.py | skill={SKILL_NAME} | "
            f"WARNING — missing env vars: {missing}\n"
        )

    # Write scratch status
    status = {
        "skill":     SKILL_NAME,
        "fqsn":      SKILL_FQSN,
        "tool":      tool_name,
        "timestamp": timestamp,
        "result":    "approved",
        "authorized_tools": sorted(AUTHORIZED_TOOLS),
    }
    try:
        SCRATCH_FILE.write_text(json.dumps(status, indent=2))
    except OSError as e:
        sys.stderr.write(f"[{timestamp}] pre_tool_call.py | WARNING — could not write scratch: {e}\n")

    # Log success
    log_audit(timestamp, tool_name, "APPROVED")
    return 0

if __name__ == "__main__":
    sys.exit(main())
