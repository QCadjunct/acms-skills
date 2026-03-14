#!/usr/bin/env python3
# pre_tool_call.py
# ACMS Lifecycle Hook — Pre Tool Call
# Skill:     ACMS_daily_diary
# Domain:    TaskArchitecture/DiaryWriter
# Generated: 2026-03-14
# Generator: ACMS_hook_generator
# Pattern:   stdlib-only — ADR-008
# © 2026 Mind Over Metadata LLC — Peter Heller

import os
import sys
import json
from datetime import datetime
from pathlib import Path

SKILL_NAME       = "ACMS_daily_diary"
SKILL_FQSN       = "TaskArchitecture/DiaryWriter/ACMS_daily_diary"
AUTHORIZED_TOOLS = {"file_write", "file_read", "datetime_now"}
VAULT_ROOTS      = [
    Path.home() / "Documents" / "Obsidian Vault",
    Path("/mnt/c/Users/pheller/Documents/Obsidian Vault"),
]

AUDIT_LOG    = Path.home() / ".config" / "fabric" / "hook_audit.log"
SCRATCH_FILE = Path("/tmp") / f"acms_{SKILL_NAME}_pre.json"

def log_audit(timestamp: str, tool: str, result: str, detail: str = "") -> None:
    AUDIT_LOG.parent.mkdir(parents=True, exist_ok=True)
    entry = (
        f"[{timestamp}] pre_tool_call.py | skill={SKILL_NAME} | "
        f"tool={tool} | result={result}"
    )
    if detail:
        entry += f" | {detail}"
    with open(AUDIT_LOG, "a") as f:
        f.write(entry + "\n")

def validate_vault_path(output_path: str) -> bool:
    """Confirm output path is inside an Obsidian vault root."""
    if not output_path:
        return True   # path not set yet — allow through
    p = Path(output_path).expanduser().resolve()
    return any(str(p).startswith(str(root)) for root in VAULT_ROOTS)

def main() -> int:
    timestamp   = datetime.now().isoformat()
    tool_name   = os.environ.get("ACMS_TOOL_NAME", "unknown")
    output_path = os.environ.get("ACMS_OUTPUT_PATH", "")

    # Guard 1: tool authorization
    if tool_name not in AUTHORIZED_TOOLS and tool_name != "unknown":
        msg = f"tool '{tool_name}' not authorized"
        sys.stderr.write(f"[{timestamp}] pre_tool_call | skill={SKILL_NAME} | BLOCKED — {msg}\n")
        log_audit(timestamp, tool_name, "BLOCKED", msg)
        return 1

    # Guard 2: file_write must target vault (diary constraint)
    if tool_name == "file_write" and not validate_vault_path(output_path):
        msg = f"output_path '{output_path}' is outside Obsidian vault"
        sys.stderr.write(f"[{timestamp}] pre_tool_call | skill={SKILL_NAME} | BLOCKED — {msg}\n")
        log_audit(timestamp, tool_name, "BLOCKED", msg)
        return 1

    status = {
        "skill": SKILL_NAME, "fqsn": SKILL_FQSN,
        "tool": tool_name, "timestamp": timestamp,
        "output_path": output_path, "result": "approved"
    }
    try:
        SCRATCH_FILE.write_text(json.dumps(status, indent=2))
    except OSError:
        pass

    log_audit(timestamp, tool_name, "APPROVED")
    return 0

if __name__ == "__main__":
    sys.exit(main())
