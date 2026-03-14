#!/usr/bin/env python3
# cost_analyzer.py
# ACMS Cost Intelligence Analyzer — D⁴ MDLC Governance Layer
# © 2026 Mind Over Metadata LLC — Peter Heller
#
# Reads ~/.config/fabric/cost_audit.log and presents cost intelligence
# broken down by artifact, vendor, model, component, skill, and run.
#
# Supports both legacy format (pre-ADR-009) and ADR-009 16-field format.
# Backward compatible — legacy entries are normalized on read.
#
# Usage:
#   python3 cost_analyzer.py                    # full report
#   python3 cost_analyzer.py --skill FQSN       # filter by skill
#   python3 cost_analyzer.py --run RUN_ID        # filter by run
#   python3 cost_analyzer.py --artifact yaml     # filter by artifact type
#   python3 cost_analyzer.py --component sync    # filter by component
#   python3 cost_analyzer.py --env dev           # filter by environment
#   python3 cost_analyzer.py --bloat             # bloat detection report
#   python3 cost_analyzer.py --ripple RUN_ID     # full provenance chain
#   python3 cost_analyzer.py --compare           # artifact comparison table
#   python3 cost_analyzer.py --projection 0.20   # cost savings projection
#   python3 cost_analyzer.py --log PATH          # custom log path
#   python3 cost_analyzer.py --seed              # write sample log entries
#
# Dependencies: polars (uv add polars)
# stdlib used: sys, os, argparse, datetime, pathlib, re, uuid

import sys
import os
import re
import argparse
from datetime import datetime
from pathlib import Path

try:
    import polars as pl
except ImportError:
    print("ERROR: polars not installed. Run: uv add polars")
    sys.exit(1)

# ── Constants ──────────────────────────────────────────────────────────────────
DEFAULT_LOG = Path.home() / ".config" / "fabric" / "cost_audit.log"
VERSION     = "1.0.0"

# ADR-009 16-field schema
FIELDS = [
    "timestamp",       # 0  ISO 8601
    "component",       # 1  which script/node
    "run_id",          # 2  uuidv7 correlation key
    "skill",           # 3  FQSN
    "artifact",        # 4  artifact taxonomy
    "vendor",          # 5  anthropic | google | ollama
    "model",           # 6  model name
    "tokens_in",       # 7  int
    "tokens_out",      # 8  int
    "cost_in",         # 9  float
    "cost_out",        # 10 float
    "cost_total",      # 11 float
    "elapsed_ms",      # 12 int
    "env",             # 13 dev | qa | prod
    "upstream_id",     # 14 uuidv7 or empty
    "notes",           # 15 optional
]

# Artifact tier classification for grouping
ARTIFACT_TIERS = {
    "principal_system_architect.system.md": "tier_0_elicitation",
    "requirements_identity.system.md":      "tier_0_elicitation",
    "requirements_mission.system.md":       "tier_0_elicitation",
    "requirements_authorities.system.md":   "tier_0_elicitation",
    "requirements_lifecycle.system.md":     "tier_0_elicitation",
    "requirements_cost_model.system.md":    "tier_0_elicitation",
    "requirements_data.system.md":          "tier_0_elicitation",
    "skill.system.md":                      "tier_1_source",
    "transformer.yaml.system.md":           "tier_1_source",
    "transformer.toon.system.md":           "tier_1_source",
    "skill.system.yaml":                    "tier_2_derived",
    "skill.system.toon":                    "tier_2_derived",
    "session.total":                        "tier_4_session",
}

def classify_artifact(artifact: str) -> str:
    """Classify artifact into tier for grouping."""
    if artifact in ARTIFACT_TIERS:
        return ARTIFACT_TIERS[artifact]
    if artifact.startswith("fabric_stitch."):
        return "tier_3_execution"
    if artifact.startswith("langgraph."):
        return "tier_3_execution"
    if artifact.startswith("hook."):
        return "tier_3_execution"
    return "tier_unknown"

# ── Log Parser ─────────────────────────────────────────────────────────────────
def parse_timestamp(ts_raw: str) -> str:
    """Extract timestamp from bracketed format [2026-03-14T10:46:17.123]."""
    return ts_raw.strip("[]")

def normalize_legacy_entry(parts: list[str]) -> dict:
    """
    Normalize a legacy (pre-ADR-009) log entry to the 16-field schema.
    Legacy format: [TIMESTAMP] | component | skill=X | ... | cost=$Y | elapsed=Zms
    """
    raw = " | ".join(parts)

    def extract(pattern: str, default: str = "") -> str:
        m = re.search(pattern, raw)
        return m.group(1) if m else default

    timestamp  = parse_timestamp(parts[0]) if parts else ""
    component  = parts[1].strip() if len(parts) > 1 else "unknown"
    skill      = extract(r"skill=([^\s|]+)")
    vendor     = extract(r"vendor=([^\s|]+)")
    model      = extract(r"model=([^\s|]+)")
    tokens_in  = extract(r"tokens_in=(\d+)", "0")
    tokens_out = extract(r"tokens_out=(\d+)", "0")
    cost_raw   = extract(r"cost=\$?([0-9.]+)", "0.0")
    elapsed    = extract(r"elapsed=(\d+)ms", "0")
    env        = extract(r"env=([^\s|]+)", "dev")

    return {
        "timestamp":   timestamp,
        "component":   component,
        "run_id":      "legacy",
        "skill":       skill,
        "artifact":    "session.total",
        "vendor":      vendor,
        "model":       model,
        "tokens_in":   int(tokens_in),
        "tokens_out":  int(tokens_out),
        "cost_in":     0.0,
        "cost_out":    0.0,
        "cost_total":  float(cost_raw),
        "elapsed_ms":  int(elapsed),
        "env":         env,
        "upstream_id": "",
        "notes":       "legacy_format",
    }

def parse_adr009_entry(parts: list[str]) -> dict:
    """Parse an ADR-009 16-field log entry."""
    def safe_int(v: str) -> int:
        try: return int(v.strip())
        except: return 0

    def safe_float(v: str) -> float:
        try: return float(v.strip())
        except: return 0.0

    def safe_str(v: str) -> str:
        return v.strip() if v else ""

    # Pad to 16 fields
    while len(parts) < 16:
        parts.append("")

    return {
        "timestamp":   parse_timestamp(parts[0]),
        "component":   safe_str(parts[1]),
        "run_id":      safe_str(parts[2]),
        "skill":       safe_str(parts[3]),
        "artifact":    safe_str(parts[4]),
        "vendor":      safe_str(parts[5]),
        "model":       safe_str(parts[6]),
        "tokens_in":   safe_int(parts[7]),
        "tokens_out":  safe_int(parts[8]),
        "cost_in":     safe_float(parts[9]),
        "cost_out":    safe_float(parts[10]),
        "cost_total":  safe_float(parts[11]),
        "elapsed_ms":  safe_int(parts[12]),
        "env":         safe_str(parts[13]),
        "upstream_id": safe_str(parts[14]),
        "notes":       safe_str(parts[15]),
    }

def is_adr009_format(parts: list[str]) -> bool:
    """Detect ADR-009 format: field 2 looks like a uuid or 'legacy', field 4 matches artifact taxonomy."""
    if len(parts) < 6:
        return False
    # Field 2 should be a RUN_ID (uuid-like) or 'legacy'
    field2 = parts[2].strip()
    uuid_pattern = re.compile(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
        re.IGNORECASE
    )
    return uuid_pattern.match(field2) is not None

def load_log(log_path: Path) -> pl.DataFrame:
    """Load and parse cost_audit.log into a Polars DataFrame."""
    if not log_path.exists():
        print(f"  No log found at: {log_path}")
        print("  Run with --seed to create sample entries.")
        return pl.DataFrame(schema={f: pl.Utf8 for f in FIELDS})

    rows = []
    skipped = 0

    with open(log_path) as f:
        for line_num, line in enumerate(f, 1):
            line = line.strip()
            if not line or line.startswith("#"):
                continue

            parts = line.split(" | ")
            if len(parts) < 2:
                skipped += 1
                continue

            try:
                if is_adr009_format(parts):
                    row = parse_adr009_entry(parts)
                else:
                    row = normalize_legacy_entry(parts)
                row["artifact_tier"] = classify_artifact(row["artifact"])
                rows.append(row)
            except Exception as e:
                skipped += 1
                continue

    if not rows:
        print(f"  No parseable entries found. Skipped {skipped} lines.")
        return pl.DataFrame()

    # Build DataFrame with correct types
    df = pl.DataFrame(rows).with_columns([
        pl.col("tokens_in").cast(pl.Int64),
        pl.col("tokens_out").cast(pl.Int64),
        pl.col("cost_in").cast(pl.Float64),
        pl.col("cost_out").cast(pl.Float64),
        pl.col("cost_total").cast(pl.Float64),
        pl.col("elapsed_ms").cast(pl.Int64),
    ])

    if skipped:
        print(f"  Note: {skipped} malformed lines skipped")

    return df

# ── Display Helpers ────────────────────────────────────────────────────────────
CYAN  = "\033[0;36m"
GREEN = "\033[0;32m"
YELLOW= "\033[1;33m"
RED   = "\033[0;31m"
BOLD  = "\033[1m"
RESET = "\033[0m"

def header(title: str) -> None:
    width = 70
    print(f"\n{BOLD}{CYAN}{'═' * width}{RESET}")
    print(f"{BOLD}{CYAN}  {title}{RESET}")
    print(f"{BOLD}{CYAN}{'═' * width}{RESET}")

def subheader(title: str) -> None:
    print(f"\n{BOLD}── {title} ──{RESET}")

def fmt_cost(cost: float) -> str:
    if cost == 0.0:
        return f"{GREEN}$0.000000{RESET}"
    elif cost < 0.01:
        return f"{YELLOW}${cost:.6f}{RESET}"
    else:
        return f"{RED}${cost:.6f}{RESET}"

def fmt_tokens(n: int) -> str:
    return f"{n:,}"

def print_df(df: pl.DataFrame, max_rows: int = 50) -> None:
    """Print a Polars DataFrame with formatting."""
    if df.is_empty():
        print("  (no data)")
        return
    with pl.Config(tbl_rows=max_rows, tbl_width_chars=120):
        print(df)

# ── Reports ────────────────────────────────────────────────────────────────────
def report_summary(df: pl.DataFrame) -> None:
    """Overall summary statistics."""
    header("ACMS Cost Intelligence — Summary Report")
    print(f"  Log entries:    {len(df):,}")
    print(f"  Skills:         {df['skill'].n_unique()}")
    print(f"  Components:     {df['component'].n_unique()}")
    print(f"  Run IDs:        {df['run_id'].n_unique()}")
    print(f"  Vendors:        {', '.join(df['vendor'].unique().to_list())}")
    print(f"  Environments:   {', '.join(df['env'].unique().to_list())}")

    total_cost    = df["cost_total"].sum()
    total_in      = df["tokens_in"].sum()
    total_out     = df["tokens_out"].sum()
    total_elapsed = df["elapsed_ms"].sum()

    print(f"\n  Total cost:     {fmt_cost(total_cost)}")
    print(f"  Total tokens:   {fmt_tokens(total_in + total_out)} "
          f"(in: {fmt_tokens(total_in)} / out: {fmt_tokens(total_out)})")
    print(f"  Total elapsed:  {total_elapsed/1000:.1f}s")

def report_by_artifact(df: pl.DataFrame) -> None:
    """Cost breakdown by artifact type — the core D⁴ MDLC differentiator."""
    header("Cost by Artifact Type")
    print("  Shows token consumption and cost at each layer of the D⁴ MDLC chain\n")

    result = (
        df.group_by(["artifact", "artifact_tier"])
        .agg([
            pl.len().alias("entries"),
            pl.col("tokens_in").sum().alias("total_tokens_in"),
            pl.col("tokens_out").sum().alias("total_tokens_out"),
            pl.col("cost_total").sum().alias("total_cost"),
            pl.col("elapsed_ms").sum().alias("total_elapsed_ms"),
        ])
        .sort("artifact_tier")
    )

    print_df(result)

    # Highlight system.md vs derived artifacts
    subheader("Three-File Standard — Token Comparison")
    three_file = df.filter(
        pl.col("artifact").is_in([
            "skill.system.md",
            "skill.system.yaml",
            "skill.system.toon",
            "transformer.yaml.system.md",
            "transformer.toon.system.md",
        ])
    ).group_by("artifact").agg([
        pl.col("tokens_in").sum().alias("tokens_in"),
        pl.col("tokens_out").sum().alias("tokens_out"),
        pl.col("cost_total").sum().alias("cost_total"),
    ]).sort("artifact")

    if not three_file.is_empty():
        print_df(three_file)
    else:
        print("  No three-file standard entries yet — run sync_skill.sh to populate")

def report_by_component(df: pl.DataFrame) -> None:
    """Cost breakdown by ACMS component."""
    header("Cost by Component")
    print("  Shows which layer of the architecture is consuming tokens\n")

    result = (
        df.group_by("component")
        .agg([
            pl.len().alias("entries"),
            pl.col("tokens_in").sum().alias("tokens_in"),
            pl.col("tokens_out").sum().alias("tokens_out"),
            pl.col("cost_total").sum().alias("cost_total"),
            pl.col("elapsed_ms").mean().alias("avg_elapsed_ms"),
        ])
        .sort("cost_total", descending=True)
    )
    print_df(result)

def report_by_vendor(df: pl.DataFrame) -> None:
    """Cost breakdown by vendor and model."""
    header("Cost by Vendor / Model")

    result = (
        df.group_by(["vendor", "model"])
        .agg([
            pl.len().alias("entries"),
            pl.col("tokens_in").sum().alias("tokens_in"),
            pl.col("tokens_out").sum().alias("tokens_out"),
            pl.col("cost_in").sum().alias("cost_in"),
            pl.col("cost_out").sum().alias("cost_out"),
            pl.col("cost_total").sum().alias("cost_total"),
        ])
        .sort("cost_total", descending=True)
    )
    print_df(result)

def report_by_skill(df: pl.DataFrame) -> None:
    """Cost breakdown by skill FQSN."""
    header("Cost by Skill (FQSN)")

    result = (
        df.group_by("skill")
        .agg([
            pl.len().alias("entries"),
            pl.col("tokens_in").sum().alias("tokens_in"),
            pl.col("tokens_out").sum().alias("tokens_out"),
            pl.col("cost_total").sum().alias("cost_total"),
            pl.col("run_id").n_unique().alias("unique_runs"),
        ])
        .sort("cost_total", descending=True)
    )
    print_df(result)

def report_bloat_detection(df: pl.DataFrame) -> None:
    """Detect bloated skill.system.md files and project ripple cost."""
    header("Bloat Detection — skill.system.md Analysis")
    print("  A bloated system.md inflates every downstream consumer's token count")
    print("  Threshold: > 800 tokens = review recommended\n")

    source_entries = df.filter(pl.col("artifact") == "skill.system.md")

    if source_entries.is_empty():
        print("  No skill.system.md entries found in log.")
        print("  Patch sync_skill.sh Step 9 to measure source tokens (Step 3 of build)")
        return

    bloat_report = (
        source_entries
        .group_by("skill")
        .agg([
            pl.col("tokens_in").max().alias("max_source_tokens"),
            pl.col("tokens_in").mean().alias("avg_source_tokens"),
            pl.col("run_id").n_unique().alias("sync_runs"),
        ])
        .with_columns([
            pl.when(pl.col("max_source_tokens") > 800)
              .then(pl.lit("⚠ REVIEW"))
              .when(pl.col("max_source_tokens") > 500)
              .then(pl.lit("🔶 WATCH"))
              .otherwise(pl.lit("✅ OK"))
              .alias("status"),
            # Estimate downstream amplification
            (pl.col("max_source_tokens") * 3).alias("estimated_downstream_tokens"),
        ])
        .sort("max_source_tokens", descending=True)
    )

    print_df(bloat_report)

    # Cross-reference with derived artifacts
    subheader("Ripple Effect — Source vs Derived Token Counts")
    combined = df.filter(
        pl.col("artifact").is_in([
            "skill.system.md",
            "skill.system.yaml",
            "skill.system.toon",
        ])
    ).group_by(["skill", "artifact"]).agg([
        pl.col("tokens_in").sum().alias("tokens_in"),
        pl.col("tokens_out").sum().alias("tokens_out"),
    ]).sort(["skill", "artifact"])

    if not combined.is_empty():
        print_df(combined)
    else:
        print("  No derived artifact entries yet")

def report_ripple_chain(df: pl.DataFrame, run_id: str) -> None:
    """Trace full provenance chain for a given RUN_ID."""
    header(f"Provenance Chain — RUN_ID: {run_id}")
    print("  Shows complete cost ancestry from source to execution\n")

    # Find all entries in this run
    direct = df.filter(pl.col("run_id") == run_id)

    # Find all entries that have this run as upstream
    downstream = df.filter(pl.col("upstream_id") == run_id)

    # Find all entries that have downstream runs as upstream (2nd generation)
    downstream_run_ids = downstream["run_id"].unique().to_list()
    gen2 = df.filter(pl.col("upstream_id").is_in(downstream_run_ids))

    print(f"  Generation 0 (this run):    {len(direct)} entries")
    print(f"  Generation 1 (downstream):  {len(downstream)} entries")
    print(f"  Generation 2 (2nd order):   {len(gen2)} entries")

    all_related = pl.concat([direct, downstream, gen2]).unique()
    total_cost = all_related["cost_total"].sum()
    total_tokens = all_related["tokens_in"].sum() + all_related["tokens_out"].sum()

    print(f"\n  Total cost of ownership: {fmt_cost(total_cost)}")
    print(f"  Total tokens:            {fmt_tokens(total_tokens)}")

    subheader("Full Chain Detail")
    chain = (
        all_related
        .select(["timestamp", "component", "run_id", "artifact",
                 "vendor", "model", "tokens_in", "tokens_out",
                 "cost_total", "upstream_id"])
        .sort("timestamp")
    )
    print_df(chain)

def report_artifact_comparison(df: pl.DataFrame) -> None:
    """Compare system.yaml vs system.toon token efficiency."""
    header("Artifact Comparison — system.yaml vs system.toon")
    print("  Validates TOON token reduction vs YAML for same skill\n")

    yaml_entries = df.filter(pl.col("artifact") == "skill.system.yaml")
    toon_entries = df.filter(pl.col("artifact") == "skill.system.toon")

    if yaml_entries.is_empty() or toon_entries.is_empty():
        print("  Need both skill.system.yaml and skill.system.toon entries to compare.")
        print("  Run sync_skill.sh --generate all to populate both.")
        return

    yaml_stats = yaml_entries.group_by("skill").agg([
        pl.col("tokens_out").mean().alias("yaml_tokens_out"),
        pl.col("cost_total").mean().alias("yaml_cost"),
    ])

    toon_stats = toon_entries.group_by("skill").agg([
        pl.col("tokens_out").mean().alias("toon_tokens_out"),
        pl.col("cost_total").mean().alias("toon_cost"),
    ])

    comparison = yaml_stats.join(toon_stats, on="skill", how="inner").with_columns([
        (
            (pl.col("yaml_tokens_out") - pl.col("toon_tokens_out"))
            / pl.col("yaml_tokens_out") * 100
        ).round(1).alias("token_reduction_pct"),
        (pl.col("yaml_tokens_out") - pl.col("toon_tokens_out"))
          .alias("tokens_saved"),
    ]).sort("token_reduction_pct", descending=True)

    print_df(comparison)

    # Summary
    if not comparison.is_empty():
        avg_reduction = comparison["token_reduction_pct"].mean()
        print(f"\n  Average TOON reduction: {avg_reduction:.1f}%")
        if avg_reduction >= 15:
            print(f"  {GREEN}✓ TOON efficiency validated — target ≥15%{RESET}")
        else:
            print(f"  {YELLOW}⚠ TOON reduction below 15% target — review transformer{RESET}")

def report_cost_projection(df: pl.DataFrame, reduction_pct: float) -> None:
    """Project cost savings from reducing skill.system.md token count."""
    header(f"Cost Savings Projection — {reduction_pct*100:.0f}% Token Reduction")
    print(f"  What happens if skill.system.md is {reduction_pct*100:.0f}% smaller?\n")

    # Current costs by artifact
    current = df.group_by("artifact").agg([
        pl.col("tokens_in").sum().alias("current_tokens_in"),
        pl.col("tokens_out").sum().alias("current_tokens_out"),
        pl.col("cost_total").sum().alias("current_cost"),
    ])

    total_current = df["cost_total"].sum()
    total_tokens  = df["tokens_in"].sum() + df["tokens_out"].sum()

    # Source tokens are in skill.system.md — these reduce directly
    source = df.filter(pl.col("artifact") == "skill.system.md")
    source_tokens = source["tokens_in"].sum() if not source.is_empty() else 0

    # Downstream tokens also reduce (they consume the source)
    derived = df.filter(pl.col("artifact").is_in([
        "skill.system.yaml", "skill.system.toon"
    ]))
    derived_input_tokens = derived["tokens_in"].sum()

    # Execution tier consumes toon — also reduces
    execution = df.filter(pl.col("artifact_tier") == "tier_3_execution")
    execution_input_tokens = execution["tokens_in"].sum()

    # Conservative estimate: only direct source reduction
    tokens_saved_conservative = int(source_tokens * reduction_pct)

    # Full ripple estimate: source + derived inputs + execution inputs
    tokens_saved_ripple = int(
        (source_tokens + derived_input_tokens + execution_input_tokens)
        * reduction_pct
    )

    print(f"  Current total tokens:          {fmt_tokens(total_tokens)}")
    print(f"  Current source tokens:         {fmt_tokens(source_tokens)}")
    print(f"  Current total cost:            {fmt_cost(total_current)}")
    print()
    print(f"  Conservative savings (source only):")
    print(f"    Tokens saved:                {fmt_tokens(tokens_saved_conservative)}")
    print()
    print(f"  Ripple savings (source + downstream):")
    print(f"    Tokens saved:                {fmt_tokens(tokens_saved_ripple)}")
    print()
    print(f"  {BOLD}Boris Cherney principle:{RESET} A {reduction_pct*100:.0f}% trim in skill.system.md")
    print(f"  saves {tokens_saved_ripple:,} tokens across the full D⁴ MDLC chain.")

def write_seed_entries(log_path: Path) -> None:
    """Write sample ADR-009 format entries to cost_audit.log for testing."""
    import uuid

    log_path.parent.mkdir(parents=True, exist_ok=True)

    run_001 = str(uuid.uuid4())  # synthesis run
    run_002 = str(uuid.uuid4())  # sync run
    run_003 = str(uuid.uuid4())  # execution run
    ts      = datetime.now().isoformat()

    entries = [
        # Sync run — source measurement
        f"[{ts}] | sync_skill | {run_002} | CodingArchitecture/FabricStitch/ACMS_extract_wisdom | skill.system.md | ollama | qwen3:8b | 478 | 0 | 0.000000 | 0.000000 | 0.000000 | 0 | dev | {run_001} | source measured",
        f"[{ts}] | sync_skill | {run_002} | CodingArchitecture/FabricStitch/ACMS_extract_wisdom | transformer.yaml.system.md | ollama | qwen3:8b | 312 | 0 | 0.000000 | 0.000000 | 0.000000 | 0 | dev | {run_001} | transformer prompt measured",
        f"[{ts}] | sync_skill | {run_002} | CodingArchitecture/FabricStitch/ACMS_extract_wisdom | transformer.toon.system.md | ollama | qwen3:8b | 287 | 0 | 0.000000 | 0.000000 | 0.000000 | 0 | dev | {run_001} | transformer prompt measured",
        f"[{ts}] | sync_skill | {run_002} | CodingArchitecture/FabricStitch/ACMS_extract_wisdom | skill.system.yaml | ollama | qwen3:8b | 790 | 421 | 0.000000 | 0.000000 | 0.000000 | 23452 | dev | {run_001} | in=skill+transformer",
        f"[{ts}] | sync_skill | {run_002} | CodingArchitecture/FabricStitch/ACMS_extract_wisdom | skill.system.toon | ollama | qwen3:8b | 765 | 333 | 0.000000 | 0.000000 | 0.000000 | 23452 | dev | {run_001} | in=skill+transformer",
        # Fabric stitch execution
        f"[{ts}] | fabric_stitch | {run_003} | CodingArchitecture/FabricStitch/ACMS_extract_wisdom | fabric_stitch.step_1 | google | gemini-2.0-flash | 1240 | 892 | 0.000465 | 0.001338 | 0.001803 | 4821 | dev | {run_002} | extract_wisdom",
        f"[{ts}] | fabric_stitch | {run_003} | CodingArchitecture/FabricStitch/ACMS_extract_wisdom | fabric_stitch.step_2 | anthropic | claude-sonnet-4-6 | 2180 | 445 | 0.006540 | 0.006675 | 0.013215 | 8234 | dev | {run_002} | summarize",
        f"[{ts}] | fabric_stitch | {run_003} | CodingArchitecture/FabricStitch/ACMS_extract_wisdom | fabric_stitch.step_3 | google | gemini-2.0-flash | 1890 | 312 | 0.000709 | 0.000468 | 0.001177 | 3912 | dev | {run_002} | extract_insights",
        f"[{ts}] | fabric_stitch | {run_003} | CodingArchitecture/FabricStitch/ACMS_extract_wisdom | fabric_stitch.step_4 | ollama | qwen3:8b | 1340 | 89 | 0.000000 | 0.000000 | 0.000000 | 12341 | dev | {run_002} | create_tags",
        # Hook entries
        f"[{ts}] | post_tool_call | {run_003} | CodingArchitecture/FabricStitch/ACMS_extract_wisdom | hook.post_tool_call | ollama | qwen3:8b | 512 | 280 | 0.000000 | 0.000000 | 0.000000 | 342 | dev | {run_002} |",
        f"[{ts}] | task_complete | {run_003} | CodingArchitecture/FabricStitch/ACMS_extract_wisdom | session.total | ollama | qwen3:8b | 1468 | 1034 | 0.000000 | 0.000000 | 0.016195 | 47891 | dev | {run_002} | 4 cost entries summed",
    ]

    with open(log_path, "a") as f:
        for entry in entries:
            f.write(entry + "\n")

    print(f"✓ Wrote {len(entries)} sample ADR-009 entries to: {log_path}")
    print(f"  RUN_002 (sync):      {run_002}")
    print(f"  RUN_003 (execution): {run_003}")
    print(f"  UPSTREAM (synthesis): {run_001}")

# ── Main ───────────────────────────────────────────────────────────────────────
def main() -> int:
    parser = argparse.ArgumentParser(
        description="ACMS Cost Intelligence Analyzer — D⁴ MDLC Governance Layer",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  python3 cost_analyzer.py                          # full report
  python3 cost_analyzer.py --bloat                  # bloat detection
  python3 cost_analyzer.py --compare                # yaml vs toon comparison
  python3 cost_analyzer.py --ripple <RUN_ID>        # provenance chain
  python3 cost_analyzer.py --projection 0.20        # 20% trim projection
  python3 cost_analyzer.py --skill CodingArchitecture/FabricStitch/ACMS_extract_wisdom
  python3 cost_analyzer.py --seed                   # populate sample data
        """
    )
    parser.add_argument("--log",        default=str(DEFAULT_LOG), help="Path to cost_audit.log")
    parser.add_argument("--skill",      help="Filter by skill FQSN")
    parser.add_argument("--run",        help="Filter by RUN_ID")
    parser.add_argument("--artifact",   help="Filter by artifact (partial match)")
    parser.add_argument("--component",  help="Filter by component")
    parser.add_argument("--env",        help="Filter by environment (dev/qa/prod)")
    parser.add_argument("--bloat",      action="store_true", help="Bloat detection report")
    parser.add_argument("--ripple",     help="Full provenance chain for RUN_ID")
    parser.add_argument("--compare",    action="store_true", help="yaml vs toon comparison")
    parser.add_argument("--projection", type=float, help="Cost savings projection (0.0-1.0)")
    parser.add_argument("--seed",       action="store_true", help="Write sample log entries")
    parser.add_argument("--version",    action="store_true", help="Show version")

    args = parser.parse_args()

    if args.version:
        print(f"cost_analyzer.py v{VERSION} — ACMS D⁴ MDLC Governance Layer")
        print(f"© 2026 Mind Over Metadata LLC — Peter Heller")
        return 0

    log_path = Path(args.log)

    # Seed mode
    if args.seed:
        write_seed_entries(log_path)
        print("\nRun without --seed to analyze the entries.")
        return 0

    # Load log
    print(f"\n{BOLD}ACMS Cost Intelligence Analyzer{RESET} v{VERSION}")
    print(f"© 2026 Mind Over Metadata LLC — Peter Heller")
    print(f"\nLog: {log_path}")

    df = load_log(log_path)

    if df.is_empty():
        return 0

    # Apply filters
    if args.skill:
        df = df.filter(pl.col("skill").str.contains(args.skill))
        print(f"Filter: skill contains '{args.skill}' → {len(df)} entries")

    if args.run:
        df = df.filter(pl.col("run_id") == args.run)
        print(f"Filter: run_id = '{args.run}' → {len(df)} entries")

    if args.artifact:
        df = df.filter(pl.col("artifact").str.contains(args.artifact))
        print(f"Filter: artifact contains '{args.artifact}' → {len(df)} entries")

    if args.component:
        df = df.filter(pl.col("component").str.contains(args.component))
        print(f"Filter: component contains '{args.component}' → {len(df)} entries")

    if args.env:
        df = df.filter(pl.col("env") == args.env)
        print(f"Filter: env = '{args.env}' → {len(df)} entries")

    if df.is_empty():
        print("\n  No entries match the specified filters.")
        return 0

    # Route to specific report
    if args.bloat:
        report_bloat_detection(df)
    elif args.ripple:
        report_ripple_chain(df, args.ripple)
    elif args.compare:
        report_artifact_comparison(df)
    elif args.projection is not None:
        report_cost_projection(df, args.projection)
    else:
        # Full report
        report_summary(df)
        report_by_artifact(df)
        report_by_component(df)
        report_by_vendor(df)
        report_by_skill(df)
        report_bloat_detection(df)
        report_artifact_comparison(df)

    print(f"\n{BOLD}{CYAN}{'═' * 70}{RESET}")
    print(f"{BOLD}  D⁴ MDLC — Metadata-Driven Lifecycle Governance{RESET}")
    print(f"{BOLD}  © 2026 Mind Over Metadata LLC — Peter Heller{RESET}")
    print(f"{BOLD}{CYAN}{'═' * 70}{RESET}\n")

    return 0

if __name__ == "__main__":
    sys.exit(main())
