#!/usr/bin/env python3
"""
skill_chain_orchestrator.py — ACES FabricStitch Parallel Skill Chain Orchestrator
FQSN: CodingArchitecture/FabricStitch/ACES_fabric_analyze
VERSION: 1.0.0

CONCEPT
  Spawns one subagent per pattern, runs all in parallel via asyncio,
  synchronizes at a $AND barrier (asyncio.gather), assembles the complete
  acquired context, then passes to synthesize_eloquent_narrative_from_wisdom.

  Mirrors the VMS $AND event flag cluster: all N events must be set before
  the barrier releases and the next stage executes.

DCG STRUCTURE
  Source
    │
    ├──[async]──▶ SubAgent[extract_article_wisdom]  ──┐
    ├──[async]──▶ SubAgent[extract_wisdom]            │
    ├──[async]──▶ SubAgent[extract_ideas]             │  $AND barrier
    ├──[async]──▶ SubAgent[extract_questions]         │  asyncio.gather()
    ├──[async]──▶ SubAgent[analyze_claims]            │
    └──[async]──▶ SubAgent[summarize]              ──┘
                                                       │
                                              Context Assembler
                                                       │
                                          synthesize_eloquent_narrative_from_wisdom
                                                       │
                                                  pandoc → .docx

USAGE
  # From YAML skill_chain:
  uv run python skill_chain_orchestrator.py --chain=skill_chain.yaml

  # Single source, auto-derive chain from theme:
  uv run python skill_chain_orchestrator.py \\
    --url="https://next.redhat.com/2022/07/13/the-uor-framework/" \\
    --theme=vision-analysis

  # With all options:
  uv run python skill_chain_orchestrator.py \\
    --chain=skill_chain.yaml \\
    --vendor=Ollama \\
    --model=qwen3.5:397b-cloud \\
    --outdir=~/fabric-analysis/uor \\
    --obsidian=~/CSCI381-CourseVault/research

AUTHOR: Peter Heller / Mind Over Metadata LLC
REPO:   QCadjunct/aces-skills
"""

from __future__ import annotations

import asyncio
import argparse
import datetime
import json
import pathlib
import subprocess
import sys
import time
import yaml

from dataclasses import dataclass, field
from enum import Enum
from typing import Optional


# ═══════════════════════════════════════════════════════════════════════════════
# ACES DATACLASSES — runtime representation of the skill chain
# These mirror the YAML canonical form and are ACESBaseModel-compatible.
# ═══════════════════════════════════════════════════════════════════════════════

class OnFailure(str, Enum):
    FAIL_FAST = "fail_fast"   # cancel all, raise immediately
    PARTIAL   = "partial"     # release barrier with whatever completed
    RETRY     = "retry"       # retry failed once before barrier decision


class SubAgentStatus(str, Enum):
    PENDING   = "pending"
    RUNNING   = "running"
    COMPLETE  = "complete"
    FAILED    = "failed"
    CANCELLED = "cancelled"


@dataclass
class SubAgentDef:
    """One node in the parallel execution graph."""
    pattern:        str
    label:          str = ""
    vendor:         str = "Ollama"
    model:          str = "qwen3.5:397b-cloud"
    retry:          int = 1          # max retries before marking failed
    timeout:        int = 600        # seconds before subprocess kill
    spawn_delay_ms: int = 0          # stagger launch to prevent Ollama saturation
    enabled:        bool = True

    def __post_init__(self):
        if not self.label:
            self.label = self.pattern


@dataclass
class SyncBarrier:
    """The $AND barrier — releases when all required agents complete."""
    name:       str = "and_barrier"
    on_failure: OnFailure = OnFailure.RETRY
    required:   list[str] = field(default_factory=list)  # pattern names; empty=all


@dataclass
class SynthesisNode:
    """Post-barrier synthesis stage."""
    pattern:        str = "synthesize_analysis_brief_from_wisdom"
    vendor:         str = "Ollama"
    model:          str = "nemotron-3-super:cloud"
    word_minimum:   int = 5000
    word_target:    int = 6500
    word_limit:     int = 8000
    document_limit: int = 15000
    directive:      str = ""   # empty = use pattern's own behavioral contract


@dataclass
class SkillChain:
    """
    Complete DCG specification.
    YAML canonical → parsed into this dataclass at runtime.
    """
    title:      str
    source:     str                          # URL or file path
    vendor:     str = "Ollama"
    model:      str = "qwen3.5:397b-cloud"
    outdir:     str = "~/fabric-analysis"
    obsidian:   str = ""
    agents:     list[SubAgentDef] = field(default_factory=list)
    barrier:    SyncBarrier = field(default_factory=SyncBarrier)
    synthesis:  SynthesisNode = field(default_factory=SynthesisNode)
    skip_docx:  bool = False

    @classmethod
    def from_yaml(cls, path: pathlib.Path) -> "SkillChain":
        """Parse YAML canonical form into SkillChain dataclass."""
        data = yaml.safe_load(path.read_text())

        agents = [
            SubAgentDef(
                pattern        = a["pattern"],
                label          = a.get("label", a["pattern"]),
                vendor         = a.get("vendor", data.get("vendor", "Ollama")),
                model          = a.get("model",  data.get("model",  "qwen3.5:397b-cloud")),
                retry          = a.get("retry",  1),
                timeout        = a.get("timeout", 600),
                spawn_delay_ms = a.get("spawn_delay_ms", 0),
                enabled        = a.get("enabled", True),
            )
            for a in data.get("agents", [])
        ]

        barrier_data = data.get("barrier", {})
        barrier = SyncBarrier(
            name       = barrier_data.get("name", "and_barrier"),
            on_failure = OnFailure(barrier_data.get("on_failure", "retry")),
            required   = barrier_data.get("required", []),
        )

        syn_data = data.get("synthesis", {})
        synthesis = SynthesisNode(
            pattern        = syn_data.get("pattern",
                             "synthesize_analysis_brief_from_wisdom"),
            vendor         = syn_data.get("vendor", data.get("vendor", "Ollama")),
            model          = syn_data.get("model",  data.get("model",  "nemotron-3-super:cloud")),
            word_minimum   = syn_data.get("word_minimum",   5000),
            word_target    = syn_data.get("word_target",    6500),
            word_limit     = syn_data.get("word_limit",     8000),
            document_limit = syn_data.get("document_limit", 15000),
            directive      = syn_data.get("directive", ""),
        )

        return cls(
            title     = data.get("title", "Fabric Analysis"),
            source    = data.get("source", ""),
            vendor    = data.get("vendor", "Ollama"),
            model     = data.get("model",  "qwen3.5:397b-cloud"),
            outdir    = data.get("outdir", "~/fabric-analysis"),
            obsidian  = data.get("obsidian", ""),
            agents    = agents,
            barrier   = barrier,
            synthesis = synthesis,
            skip_docx = data.get("skip_docx", False),
        )

    @classmethod
    def from_theme(
        cls,
        source:     str,
        theme_path: pathlib.Path,
        vendor:     str = "Ollama",
        model:      str = "qwen3.5:397b-cloud",
        outdir:     str = "~/fabric-analysis",
        obsidian:   str = "",
    ) -> "SkillChain":
        """Auto-derive SkillChain from a theme YAML — chain builds itself."""
        theme = yaml.safe_load(theme_path.read_text())
        patterns = theme.get("patterns_required",
                   ["extract_article_wisdom", "summarize"])

        agents = [
            SubAgentDef(pattern=p, vendor=vendor, model=model)
            for p in patterns
        ]

        synthesis = SynthesisNode(
            word_limit = theme.get("word_limit", 4000),
            directive  = theme.get("synthesis_directive", ""),
        )

        return cls(
            title     = f"{source[:60]} — {theme.get('title_suffix','Analysis')}",
            source    = source,
            vendor    = vendor,
            model     = model,
            outdir    = outdir,
            obsidian  = obsidian,
            agents    = agents,
            barrier   = SyncBarrier(on_failure=OnFailure.RETRY),
            synthesis = synthesis,
        )

    def to_yaml(self) -> str:
        """Serialize back to YAML canonical form."""
        return yaml.dump({
            "title":  self.title,
            "source": self.source,
            "vendor": self.vendor,
            "model":  self.model,
            "outdir": self.outdir,
            "agents": [
                {
                    "pattern":        a.pattern,
                    "label":          a.label,
                    "vendor":         a.vendor,
                    "model":          a.model,
                    "spawn_delay_ms": a.spawn_delay_ms,
                    "retry":          a.retry,
                    "timeout":        a.timeout,
                    "enabled":        a.enabled,
                }
                for a in self.agents
            ],
            "barrier": {
                "name":       self.barrier.name,
                "on_failure": self.barrier.on_failure.value,
                "required":   self.barrier.required,
            },
            "synthesis": {
                "pattern":        self.synthesis.pattern,
                "vendor":         self.synthesis.vendor,
                "model":          self.synthesis.model,
                "word_minimum":   self.synthesis.word_minimum,
                "word_target":    self.synthesis.word_target,
                "word_limit":     self.synthesis.word_limit,
                "document_limit": self.synthesis.document_limit,
                "directive":      self.synthesis.directive,
            },
        }, default_flow_style=False, sort_keys=False)


# ═══════════════════════════════════════════════════════════════════════════════
# SUBAGENT RESULT
# ═══════════════════════════════════════════════════════════════════════════════

@dataclass
class SubAgentResult:
    pattern:    str
    status:     SubAgentStatus
    output:     str = ""
    elapsed_ms: int = 0
    attempts:   int = 0
    error:      str = ""


# ═══════════════════════════════════════════════════════════════════════════════
# SUBAGENT RUNNER — one coroutine per pattern
# ═══════════════════════════════════════════════════════════════════════════════

async def run_subagent(
    agent:  SubAgentDef,
    source: str,
    sem:    asyncio.Semaphore,
) -> SubAgentResult:
    """
    Async coroutine for one subagent.
    Staggered launch via spawn_delay_ms — prevents Ollama queue saturation.
    Acquires semaphore slot, runs fabric subprocess, releases slot.
    Retries up to agent.retry times before marking failed.
    """
    # Staggered launch — each agent waits its delay before acquiring semaphore
    if agent.spawn_delay_ms > 0:
        await asyncio.sleep(agent.spawn_delay_ms / 1000)

    async with sem:
        t_start = time.perf_counter()
        attempt = 0
        output  = ""

        # Detect source type
        is_youtube = any(x in source for x in
                         ["youtube.com/watch", "youtu.be/", "youtube.com/shorts/"])
        is_url     = source.startswith("http")

        while attempt <= agent.retry:
            attempt += 1
            try:
                # Build fabric command
                cmd = [
                    "fabric",
                    "-V", agent.vendor,
                    "-m", agent.model,
                    "-p", agent.pattern,
                ]

                if is_url:
                    if is_youtube:
                        cmd += ["-y", source]
                        stdin_data = None
                    else:
                        cmd += ["-u", source]
                        stdin_data = None
                else:
                    # File — convert to text via pandoc first
                    pandoc_proc = await asyncio.create_subprocess_exec(
                        "pandoc", source, "-t", "plain", "--wrap=none",
                        stdout=asyncio.subprocess.PIPE,
                        stderr=asyncio.subprocess.DEVNULL,
                    )
                    pandoc_out, _ = await asyncio.wait_for(
                        pandoc_proc.communicate(), timeout=60
                    )
                    stdin_data = pandoc_out

                proc = await asyncio.create_subprocess_exec(
                    *cmd,
                    stdin  = asyncio.subprocess.PIPE if stdin_data else None,
                    stdout = asyncio.subprocess.PIPE,
                    stderr = asyncio.subprocess.DEVNULL,
                )

                stdout, _ = await asyncio.wait_for(
                    proc.communicate(input=stdin_data),
                    timeout=agent.timeout,
                )
                output = stdout.decode("utf-8", errors="replace").strip()

                if output:
                    break  # success — exit retry loop

            except asyncio.TimeoutError:
                output = ""
                if attempt > agent.retry:
                    elapsed = int((time.perf_counter() - t_start) * 1000)
                    return SubAgentResult(
                        pattern    = agent.pattern,
                        status     = SubAgentStatus.FAILED,
                        elapsed_ms = elapsed,
                        attempts   = attempt,
                        error      = f"Timeout after {agent.timeout}s",
                    )
            except Exception as exc:
                output = ""
                if attempt > agent.retry:
                    elapsed = int((time.perf_counter() - t_start) * 1000)
                    return SubAgentResult(
                        pattern    = agent.pattern,
                        status     = SubAgentStatus.FAILED,
                        elapsed_ms = elapsed,
                        attempts   = attempt,
                        error      = str(exc),
                    )

        elapsed = int((time.perf_counter() - t_start) * 1000)

        if output:
            return SubAgentResult(
                pattern    = agent.pattern,
                status     = SubAgentStatus.COMPLETE,
                output     = output,
                elapsed_ms = elapsed,
                attempts   = attempt,
            )
        else:
            return SubAgentResult(
                pattern    = agent.pattern,
                status     = SubAgentStatus.FAILED,
                elapsed_ms = elapsed,
                attempts   = attempt,
                error      = "Empty output after all retries",
            )


# ═══════════════════════════════════════════════════════════════════════════════
# $AND BARRIER — asyncio.gather() over all subagent coroutines
# ═══════════════════════════════════════════════════════════════════════════════

async def and_barrier(
    chain: SkillChain,
) -> tuple[list[SubAgentResult], dict[str, str]]:
    """
    The $AND barrier.
    Launches all enabled subagents in parallel.
    asyncio.gather() blocks until ALL complete (or fail).
    Returns (results, context_map).

    context_map: pattern → output string for all completed agents.
    This is the complete acquired context passed to the synthesis node.
    """
    enabled = [a for a in chain.agents if a.enabled]
    n       = len(enabled)

    # Semaphore limits concurrent Fabric/Ollama calls.
    # Ollama handles concurrency well but cap at 6 to avoid OOM on RTX 5080.
    sem = asyncio.Semaphore(min(n, 6))

    print(f"\n{'═'*62}")
    print(f"  $AND BARRIER — {n} subagents launching in parallel")
    print(f"  on_failure: {chain.barrier.on_failure.value}")
    print(f"{'─'*62}")
    for a in enabled:
        print(f"  ▶  [{a.pattern:<35}] spawning...")
    print(f"{'─'*62}\n")

    t_barrier_start = time.perf_counter()

    # Spawn all coroutines — asyncio.gather IS the $AND
    coros   = [run_subagent(a, chain.source, sem) for a in enabled]
    results: list[SubAgentResult] = await asyncio.gather(*coros)

    t_barrier_end = time.perf_counter()
    wall_ms = int((t_barrier_end - t_barrier_start) * 1000)

    # Print results table
    print(f"\n{'─'*62}")
    print(f"  $AND BARRIER RELEASED — wall time: {wall_ms:,}ms")
    print(f"{'─'*62}")
    completed = [r for r in results if r.status == SubAgentStatus.COMPLETE]
    failed    = [r for r in results if r.status == SubAgentStatus.FAILED]

    for r in sorted(results, key=lambda x: x.elapsed_ms):
        icon = "✓" if r.status == SubAgentStatus.COMPLETE else "✗"
        print(f"  {icon}  [{r.pattern:<35}] "
              f"{r.elapsed_ms:>7,}ms  "
              f"attempt={r.attempts}  "
              f"{r.status.value}")
        if r.error:
            print(f"       ↳ {r.error}")

    print(f"{'─'*62}")
    print(f"  Completed : {len(completed)}/{n}")
    print(f"  Failed    : {len(failed)}/{n}")

    # Apply on_failure policy
    if failed:
        policy = chain.barrier.on_failure

        if policy == OnFailure.FAIL_FAST:
            names = [r.pattern for r in failed]
            raise RuntimeError(
                f"FAIL_FAST: {len(failed)} subagent(s) failed: {names}"
            )

        elif policy == OnFailure.PARTIAL:
            print(f"  PARTIAL: proceeding with {len(completed)} completed agents")

        elif policy == OnFailure.RETRY:
            # One additional retry for failed agents (sequential, after barrier)
            print(f"  RETRY: re-running {len(failed)} failed agent(s)...")
            retry_sem = asyncio.Semaphore(len(failed))
            retry_agents = [
                next(a for a in enabled if a.pattern == r.pattern)
                for r in failed
            ]
            retry_coros  = [run_subagent(a, chain.source, retry_sem)
                            for a in retry_agents]
            retry_results = await asyncio.gather(*retry_coros)

            # Merge retry results back
            result_map = {r.pattern: r for r in results}
            for rr in retry_results:
                result_map[rr.pattern] = rr
            results = list(result_map.values())

            still_failed = [r for r in results if r.status == SubAgentStatus.FAILED]
            if still_failed:
                print(f"  ⚠  Still failed after retry: "
                      f"{[r.pattern for r in still_failed]}")
                print(f"  Proceeding with partial context.")

    # Assemble context map — the complete acquired context
    context_map: dict[str, str] = {
        r.pattern: r.output
        for r in results
        if r.status == SubAgentStatus.COMPLETE and r.output
    }

    return results, context_map


# ═══════════════════════════════════════════════════════════════════════════════
# SYNTHESIS NODE — receives complete acquired context from barrier
# ═══════════════════════════════════════════════════════════════════════════════

async def synthesis_node(
    chain:       SkillChain,
    context_map: dict[str, str],
) -> str:
    """
    Post-barrier synthesis.
    Assembles the complete acquired context from all completed subagents
    and passes it to synthesize_eloquent_narrative_from_wisdom.
    """
    print(f"\n{'─'*62}")
    print(f"  SYNTHESIS NODE")
    print(f"  Pattern : {chain.synthesis.pattern}")
    print(f"  Context : {len(context_map)} pattern outputs")
    print(f"  Words   : {chain.synthesis.word_limit} target")
    print(f"{'─'*62}")

    # Build synthesis input in the three-step format the pattern expects:
    # STEP 1 — EXTRACTED WISDOM  (ideas, quotes, habits, facts, references)
    # STEP 2 — SUMMARY           (distilled key points)
    # STEP 3 — INSIGHTS          (deeper analysis and connections)

    # Map our six patterns into the three-step structure
    STEP1_PATTERNS = ["extract_article_wisdom", "extract_wisdom",
                      "extract_ideas", "extract_questions", "analyze_claims"]
    STEP2_PATTERNS = ["summarize"]
    STEP3_PATTERNS = ["extract_wisdom", "analyze_claims"]

    step1 = "\n\n".join(
        context_map[p] for p in STEP1_PATTERNS if p in context_map
    )
    step2 = "\n\n".join(
        context_map[p] for p in STEP2_PATTERNS if p in context_map
    )
    step3 = "\n\n".join(
        context_map[p] for p in STEP3_PATTERNS if p in context_map
    )

    # Pass explicit dates — model must never infer current date from training cutoff
    import datetime as _dt
    analysis_date = _dt.date.today().strftime("%Y-%m-%d")

    lines = [
        f"word_minimum={chain.synthesis.word_minimum}",
        f"word_target={chain.synthesis.word_target}",
        f"word_limit={chain.synthesis.word_limit}",
        f"document_limit={chain.synthesis.document_limit}",
        f"analysis_date={analysis_date}",
        f"source={chain.source}",
        "",
        "CRITICAL: analysis_date above is the ACTUAL current date.",
        "NEVER use your training cutoff date as the analysis date.",
        "The temporal gap must be calculated from analysis_date, not from",
        "any assumed current date in your training data.",
        "",
    ]

    if chain.synthesis.directive.strip():
        lines += [
            "SYNTHESIS DIRECTIVE:",
            chain.synthesis.directive.strip(),
            "",
        ]

    lines += [
        "# STEP 1 — EXTRACTED WISDOM",
        step1,
        "",
        "# STEP 2 — SUMMARY",
        step2,
        "",
        "# STEP 3 — INSIGHTS",
        step3,
        "",
    ]

    synthesis_input = "\n".join(lines)

    # Run synthesis (single call, not parallel)
    # Use synthesis-specific vendor/model (may differ from extraction agents)
    synth_vendor = chain.synthesis.vendor if chain.synthesis.vendor else chain.vendor
    synth_model  = chain.synthesis.model  if chain.synthesis.model  else chain.model

    cmd = [
        "fabric",
        "-V", synth_vendor,
        "-m", synth_model,
        "-p", chain.synthesis.pattern,
    ]

    t_s = time.perf_counter()
    proc = await asyncio.create_subprocess_exec(
        *cmd,
        stdin  = asyncio.subprocess.PIPE,
        stdout = asyncio.subprocess.PIPE,
        stderr = asyncio.subprocess.PIPE,
    )
    stdout, stderr_out = await asyncio.wait_for(
        proc.communicate(input=synthesis_input.encode()),
        timeout=600,
    )
    elapsed = int((time.perf_counter() - t_s) * 1000)

    output = stdout.decode("utf-8", errors="replace").strip()
    wc     = len(output.split())
    if not output and stderr_out:
        err = stderr_out.decode("utf-8", errors="replace").strip()
        print(f"  ✗  {elapsed:,}ms · stderr: {err[:200]}")
    else:
        print(f"  ✓  {elapsed:,}ms · {wc:,} words")

    return output


# ═══════════════════════════════════════════════════════════════════════════════
# OUTPUT WRITER
# ═══════════════════════════════════════════════════════════════════════════════

def write_output(
    chain:       SkillChain,
    narrative:   str,
    results:     list[SubAgentResult],
    context_map: dict[str, str],
    wall_ms:     int,
) -> tuple[pathlib.Path, pathlib.Path | None]:
    """Write .md and optionally .docx, return paths."""

    outdir = pathlib.Path(chain.outdir.replace("~", str(pathlib.Path.home())))
    outdir.mkdir(parents=True, exist_ok=True)

    slug = chain.source \
        .replace("https://", "").replace("http://", "") \
        .replace("/", "-").replace(".", "-")[:50]
    ts   = datetime.datetime.now().strftime("%Y-%m-%d-%H%M")

    md_path   = outdir / f"{slug}-parallel-{ts}.md"
    docx_path = outdir / f"{slug}-parallel-{ts}.docx"

    # Build timing table for appendix
    timing_rows = "\n".join(
        f"  {r.pattern:<40} {r.elapsed_ms:>8,}ms  "
        f"[{r.status.value}] attempts={r.attempts}"
        for r in sorted(results, key=lambda x: x.elapsed_ms)
    )

    md_content = f"""---
title: "{chain.title}"
subtitle: "Parallel Skill Chain · $AND Barrier · ACES FabricStitch v1.0.0"
author: "Peter Heller / Mind Over Metadata LLC"
date: "{datetime.datetime.now().strftime('%B %d, %Y')}"
source: "{chain.source}"
model: "{chain.vendor} / {chain.model}"
agents: "{len(results)}"
completed: "{len([r for r in results if r.status == SubAgentResult])}"
wall_time_ms: "{wall_ms}"
---

{narrative}

---

## Appendix — Parallel Execution Health

```
Skill Chain   : {chain.title}
Source        : {chain.source}
Model         : {chain.vendor} / {chain.model}
Agents        : {len(results)} spawned in parallel
Wall time     : {wall_ms:,}ms  (sequential would be ~{sum(r.elapsed_ms for r in results):,}ms)
Speedup       : {sum(r.elapsed_ms for r in results) / wall_ms:.1f}x

$AND BARRIER RESULTS
{timing_rows}

Synthesis     : {chain.synthesis.pattern}
Context keys  : {list(context_map.keys())}
```

*skill_chain_orchestrator.py v1.0.0 · CodingArchitecture/FabricStitch/ACES_fabric_analyze*
"""

    md_path.write_text(md_content)

    # pandoc conversion
    if not chain.skip_docx:
        try:
            subprocess.run(
                ["pandoc", str(md_path),
                 "--from", "markdown-yaml_metadata_block",
                 "--to", "docx", "--toc", "-o", str(docx_path)],
                check=True, capture_output=True,
            )
        except (subprocess.CalledProcessError, FileNotFoundError):
            docx_path = None

    # Obsidian copy
    if chain.obsidian:
        obs = pathlib.Path(chain.obsidian.replace("~", str(pathlib.Path.home())))
        obs.mkdir(parents=True, exist_ok=True)
        (obs / md_path.name).write_text(md_content)

    return md_path, docx_path


# ═══════════════════════════════════════════════════════════════════════════════
# ORCHESTRATOR — main async entry point
# ═══════════════════════════════════════════════════════════════════════════════

async def orchestrate(chain: SkillChain) -> None:
    """
    Full DCG execution:
      1. Print chain summary
      2. Run $AND barrier (all subagents in parallel)
      3. Pass complete acquired context to synthesis node
      4. Write output files
    """
    print(f"\n{'═'*62}")
    print(f"  ACES SKILL CHAIN ORCHESTRATOR v1.0.0")
    print(f"  {chain.title}")
    print(f"{'─'*62}")
    print(f"  Source  : {chain.source}")
    print(f"  Vendor  : {chain.vendor} / {chain.model}")
    print(f"  Agents  : {len([a for a in chain.agents if a.enabled])} parallel")
    print(f"  Barrier : {chain.barrier.on_failure.value}")
    print(f"  Synth   : {chain.synthesis.pattern}")
    print(f"  Words   : {chain.synthesis.word_limit}")
    print(f"{'═'*62}")

    t_total_start = time.perf_counter()

    # ── $AND BARRIER ──────────────────────────────────────────────────────────
    results, context_map = await and_barrier(chain)

    if not context_map:
        print("\n✗ No context acquired — all subagents failed. Aborting synthesis.")
        sys.exit(1)

    # ── SYNTHESIS NODE ────────────────────────────────────────────────────────
    narrative = await synthesis_node(chain, context_map)

    wall_ms = int((time.perf_counter() - t_total_start) * 1000)

    if not narrative:
        print("\n✗ Synthesis returned empty output.")
        sys.exit(1)

    # ── OUTPUT ────────────────────────────────────────────────────────────────
    md_path, docx_path = write_output(
        chain, narrative, results, context_map, wall_ms
    )

    sequential_est = sum(r.elapsed_ms for r in results)
    speedup        = sequential_est / wall_ms if wall_ms > 0 else 1.0

    print(f"\n{'═'*62}")
    print(f"  COMPLETE — {wall_ms:,}ms total wall time")
    print(f"  Sequential estimate : {sequential_est:,}ms")
    print(f"  Parallel speedup    : {speedup:.1f}x")
    print(f"  Markdown  : {md_path}")
    if docx_path:
        print(f"  Word doc  : {docx_path}")
    print(f"{'═'*62}\n")

    # Open Explorer (WSL2)
    try:
        subprocess.run(
            ["explorer.exe", str(pathlib.Path(chain.outdir
                .replace("~", str(pathlib.Path.home()))))],
            capture_output=True,
        )
    except FileNotFoundError:
        pass


# ═══════════════════════════════════════════════════════════════════════════════
# CLI ENTRY POINT
# ═══════════════════════════════════════════════════════════════════════════════

def main() -> None:
    parser = argparse.ArgumentParser(
        description="ACES Skill Chain Orchestrator — parallel Fabric subagents + $AND barrier",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("--chain",   help="YAML skill_chain definition file")
    parser.add_argument("--url",     help="Source URL (overrides chain.source)")
    parser.add_argument("--theme",   help="Theme YAML file to auto-derive chain")
    parser.add_argument("--vendor",  default="Ollama")
    parser.add_argument("--model",   default="qwen3.5:397b-cloud")
    parser.add_argument("--outdir",  default="~/fabric-analysis")
    parser.add_argument("--obsidian",default="")
    parser.add_argument("--word-limit", type=int, default=4000)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    script_dir = pathlib.Path(__file__).parent

    # ── Resolve SkillChain ────────────────────────────────────────────────────
    if args.chain:
        chain = SkillChain.from_yaml(pathlib.Path(args.chain))
        if args.url:
            chain.source = args.url
    elif args.theme and args.url:
        theme_path = pathlib.Path(args.theme)
        if not theme_path.is_absolute():
            # Look in themes/ directory next to this script
            theme_path = script_dir / "themes" / args.theme
            if not theme_path.suffix:
                theme_path = theme_path.with_suffix(".yaml")
        chain = SkillChain.from_theme(
            source   = args.url,
            theme_path = theme_path,
            vendor   = args.vendor,
            model    = args.model,
            outdir   = args.outdir,
            obsidian = args.obsidian,
        )
        chain.synthesis.word_limit = args.word_limit
    elif args.url:
        # Default full chain from URL
        chain = SkillChain(
            title  = f"Analysis: {args.url[:60]}",
            source = args.url,
            vendor = args.vendor,
            model  = args.model,
            outdir = args.outdir,
            agents = [
                SubAgentDef("extract_article_wisdom", vendor=args.vendor, model=args.model),
                SubAgentDef("extract_wisdom",         vendor=args.vendor, model=args.model),
                SubAgentDef("extract_ideas",          vendor=args.vendor, model=args.model),
                SubAgentDef("extract_questions",      vendor=args.vendor, model=args.model),
                SubAgentDef("analyze_claims",         vendor=args.vendor, model=args.model),
                SubAgentDef("summarize",              vendor=args.vendor, model=args.model),
            ],
            synthesis = SynthesisNode(word_limit=args.word_limit),
        )
    else:
        parser.print_help()
        sys.exit(1)

    if args.dry_run:
        print("═══ DRY RUN ═══")
        print(chain.to_yaml())
        sys.exit(0)

    asyncio.run(orchestrate(chain))


if __name__ == "__main__":
    main()
