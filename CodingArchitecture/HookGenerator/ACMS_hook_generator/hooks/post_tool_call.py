#!/usr/bin/env python3
# post_tool_call.py
# ACMS Lifecycle Hook — Post Tool Call
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
import time
from datetime import datetime
from pathlib import Path

# ── Skill constants ────────────────────────────────────────────────────────────
SKILL_NAME  = "ACMS_extract_wisdom"
SKILL_FQSN  = "CodingArchitecture/FabricStitch/ACMS_extract_wisdom"

# Constraints derived from system.md # Constraints section
CONSTRAINTS = [
    "Never fabricate insights not present in source text",
    "Never truncate output to fit token limits",
]

# ── Paths ──────────────────────────────────────────────────────────────────────
AUDIT_LOG    = Path.home() / ".config" / "fabric" / "hook_audit.log"
COST_LOG     = Path.home() / ".config" / "fabric" / "cost_audit.log"
PRE_SCRATCH  = Path("/tmp") / f"acms_{SKILL_NAME}_pre.json"
POST_SCRATCH = Path("/tmp") / f"acms_{SKILL_NAME}_post.json"

# ── Rate constants (from vendor_rates.yaml defaults for sync_skill) ────────────
RATE_IN  = 0.000000000   # ollama/qwen3:8b — local, zero cost
RATE_OUT = 0.000000000

def log_audit(timestamp: str, tool: str, result: str,
              elapsed_ms: int = 0, detail: str = "") -> None:
    AUDIT_LOG.parent.mkdir(parents=True, exist_ok=True)
    entry = (
        f"[{timestamp}] post_tool_call.py | skill={SKILL_NAME} | "
        f"tool={tool} | result={result} | elapsed={elapsed_ms}ms"
    )
    if detail:
        entry += f" | detail={detail}"
    entry += "\n"
    with open(AUDIT_LOG, "a") as f:
        f.write(entry)

def estimate_cost(tokens_in: int, tokens_out: int) -> float:
    return (tokens_in * RATE_IN) + (tokens_out * RATE_OUT)

def main() -> int:
    timestamp  = datetime.now().isoformat()
    tool_name  = os.environ.get("ACMS_TOOL_NAME", "unknown")
    exit_code  = int(os.environ.get("ACMS_TOOL_EXIT_CODE", "0"))
    tokens_in  = int(os.environ.get("ACMS_TOKENS_IN", "0"))
    tokens_out = int(os.environ.get("ACMS_TOKENS_OUT", "0"))

    # Compute elapsed from pre-scratch if available
    elapsed_ms = 0
    if PRE_SCRATCH.exists():
        try:
            pre_data   = json.loads(PRE_SCRATCH.read_text())
            pre_ts     = datetime.fromisoformat(pre_data.get("timestamp", timestamp))
            elapsed_ms = int((datetime.now() - pre_ts).total_seconds() * 1000)
        except (json.JSONDecodeError, KeyError, ValueError):
            pass

    # Compute cost
    cost = estimate_cost(tokens_in, tokens_out)

    # Constraint validation — log warnings, never block (post-hook is advisory)
    constraint_warnings = []
    output_text = os.environ.get("ACMS_TOOL_OUTPUT", "")
    if len(output_text) < 10 and tokens_out > 50:
        constraint_warnings.append("Output suspiciously short relative to token count")

    # Write ADR-009 format cost entry to cost_audit.log
    COST_LOG.parent.mkdir(parents=True, exist_ok=True)

    # Read RUN_ID from pre-scratch if available
    run_id = "unknown"
    upstream_id = ""
    try:
        pre_data = json.loads(PRE_SCRATCH.read_text())
        run_id = pre_data.get("run_id", "unknown")
        upstream_id = pre_data.get("upstream_id", "")
    except Exception:
        pass

    vendor = os.environ.get("ACMS_VENDOR", "ollama").lower()
    model  = os.environ.get("ACMS_MODEL", "qwen3:8b")
    env    = os.environ.get("ACMS_ENV", "dev")

    cost_in  = tokens_in  * RATE_IN
    cost_out = tokens_out * RATE_OUT
    cost     = cost_in + cost_out

    adr009_entry = (
        f"[{timestamp}] | post_tool_call | {run_id} | {SKILL_FQSN} | "
        f"hook.post_tool_call | {vendor} | {model} | "
        f"{tokens_in} | {tokens_out} | "
        f"{cost_in:.6f} | {cost_out:.6f} | {cost:.6f} | "
        f"{elapsed_ms} | {env} | {upstream_id} | "
        f"tool={tool_name} exit={exit_code}\n"
    )
    with open(COST_LOG, "a") as f:
        f.write(adr009_entry)

    # Write post scratch status
    status = {
        "skill":      SKILL_NAME,
        "fqsn":       SKILL_FQSN,
        "tool":       tool_name,
        "timestamp":  timestamp,
        "exit_code":  exit_code,
        "elapsed_ms": elapsed_ms,
        "tokens_in":  tokens_in,
        "tokens_out": tokens_out,
        "cost":       f"${cost:.6f}",
        "constraints_checked": len(CONSTRAINTS),
        "warnings":   constraint_warnings,
        "result":     "ok" if exit_code == 0 else "tool_error",
    }
    try:
        POST_SCRATCH.write_text(json.dumps(status, indent=2))
    except OSError as e:
        sys.stderr.write(f"[{timestamp}] post_tool_call.py | WARNING — scratch write failed: {e}\n")

    result = "ok" if exit_code == 0 else f"tool_exit_{exit_code}"
    detail = f"cost=${cost:.6f}"
    if constraint_warnings:
        detail += f" | warnings={constraint_warnings}"

    log_audit(timestamp, tool_name, result, elapsed_ms, detail)

    # Post-hook always exits 0 — failures are logged, not fatal
    return 0

if __name__ == "__main__":
    sys.exit(main())
