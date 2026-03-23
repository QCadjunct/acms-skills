# ADR-009 — D⁴ MDLC Governance for Agentic AI Systems

> **Vault**: Agentic-ACMS-Proof-of-Concept / ADRs  
> **Cross-ref**: Mind-Over-Metadata / 10-AI-Agent-Orchestration  
> **Type**: Architectural Decision Record (ADR)  
> **Status**: Accepted  
> **Date**: 2026-03-14  
> **Author**: Peter Heller, Mind Over Metadata LLC  
> **Significance**: Foundation ADR — establishes D⁴ MDLC as the governance  
> framework for the entire ACMS agentic architecture

---

## 📑 Table of Contents

1. [The Thesis](#1-the-thesis)
2. [Context — What Led Here](#2-context--what-led-here)
3. [The Bloat Ripple Problem](#3-the-bloat-ripple-problem)
4. [Decision 1 — Unified Cost Audit Log](#4-decision-1--unified-cost-audit-log)
5. [Decision 2 — PrincipalSystemArchitect](#5-decision-2--principalsystemarchitect)
6. [Decision 3 — RequirementsGathering Specialists](#6-decision-3--requirementsgathering-specialists)
7. [Decision 4 — Self-Documenting Naming as BGD Governance](#7-decision-4--self-documenting-naming-as-bgd-governance)
8. [Decision 5 — POC V1.0 Scope and Refinement Gate](#8-decision-5--poc-v10-scope-and-refinement-gate)
9. [The Full Architecture Under D⁴ MDLC](#9-the-full-architecture-under-d4-mdlc)
10. [Updated Taxonomy](#10-updated-taxonomy)
11. [Consequences](#11-consequences)
12. [Publication Path](#12-publication-path)
13. [Links](#13-links)

---

## 1. The Thesis

**D⁴ MDLC (Domain-Driven Database Design — Metadata-Driven Lifecycle)
is the governance framework for agentic AI systems.**

D⁴ was born in 2003 from a NYC DCAS EC3 energy billing system. This ADR
establishes that D⁴ governance principles apply equally to AI agent
behavioral contracts as they do to database schemas. The methodology
generalizes — metadata-driven governance is not domain-specific, it is
a universal architectural principle.

The ACMS POC is the proof of concept for this thesis:

| D⁴ Database Principle | ACMS Agentic Equivalent |
|----------------------|------------------------|
| Physical Data Model first | system.md behavioral contract first |
| Business Glossary Domains (BGDs) | FQSN taxonomy domain classifiers |
| Fully Qualified Domain Names (FQDNs) | Fully Qualified Skill Names (FQSNs) |
| Two-value predicate logic (no NULLs) | No abbreviations — self-documenting names |
| Allen Interval temporal referential integrity | RUN_ID → UPSTREAM_ID provenance chain |
| Governance embedded in DDL | Governance embedded in system.md |
| B-tree navigation paths | FQSN as B-tree navigation path |
| Metadata-Driven Lifecycle (MDLC) | Cost audit log as governance audit trail |

The claim this POC will prove: **what D⁴ did for database governance,
ACMS does for agentic AI governance.** Same principles. Different payload.

---

## 2. Context — What Led Here

During the session of 2026-03-14, several architectural insights
converged simultaneously:

**Insight 1**: The ambiguity of "system.md" — all three files in the
Three-File Skill Standard have a file named system.md. Without
qualification, "system.md" is ambiguous across:
- `skill.system.md` — the primary behavioral contract
- `transformer.yaml.system.md` — the yaml transformer pattern prompt
- `transformer.toon.system.md` — the toon transformer pattern prompt

**Insight 2**: Token cost is not flat — it compounds downstream. A
bloated `skill.system.md` inflates every downstream consumer's input
token count. Boris Cherney's sample.md demonstrated this: verbosity in
the source propagates as cost amplification through every derived
artifact and every execution that consumes those artifacts.

**Insight 3**: The PSA (Principal System Architect) was identified as
the missing orchestration layer — the Navigator at the system level
that dispatches to specialist elicitation skills before any `system.md`
is authored. Without the PSA, authors compensate for incomplete
elicitation by writing verbose system.md files — which is the root
cause of the bloat problem.

**Insight 4**: "PSA" is an abbreviation that requires institutional
memory to decode. Institutional memory is exactly what governance
systems exist to eliminate. The correct name is
`PrincipalSystemArchitect` — a Business Glossary Domain name that
declares its role unambiguously, consistent with D⁴ BGD naming
conventions.

**Insight 5**: These four insights are not independent — they are all
expressions of the same underlying principle: **D⁴ MDLC applied to
agentic AI governance.**

---

## 3. The Bloat Ripple Problem

A bloated `skill.system.md` creates a cost amplification cascade:

```
skill.system.md (N tokens)
        │
        ├── + transformer.yaml.system.md (M tokens)
        │         = tokens_in for yaml generation
        │         → system.yaml (P tokens output)
        │                 │
        │                 └── tokens_in for LangGraph EXC node
        │
        └── + transformer.toon.system.md (Q tokens)
                  = tokens_in for toon generation
                  → system.toon (R tokens output)
                          │
                          └── tokens_in for RabbitMQ consumer
                                      │
                                      └── tokens_in for every
                                          LangGraph node that
                                          loads the skill contract
```

The precise cost formula:

```
cost_yaml_gen = (skill.system.md + transformer.yaml.system.md) × rate_in
              + system.yaml × rate_out

cost_toon_gen = (skill.system.md + transformer.toon.system.md) × rate_in
              + system.toon × rate_out

cost_per_langgraph_node = system.toon × rate_in (loaded as context)
                        + node_output × rate_out

total_cost_of_ownership = cost_yaml_gen
                        + cost_toon_gen
                        + (cost_per_langgraph_node × node_count)
                        + (psa_elicitation_cost if tracked)
```

A 20% reduction in `skill.system.md` token count does not produce 20%
cost savings — it produces compounding savings at every downstream
consumption point. The Polars analyzer will quantify this projection.

**Root cause of bloat**: incomplete elicitation. When the
PrincipalSystemArchitect does not dispatch to all required
RequirementsGathering specialists, the author compensates by writing
verbose prose in `system.md`. The cost audit trail exposes this gap.

---

## 4. Decision 1 — Unified Cost Audit Log

**Decision**: All ACMS components that touch tokens write to a single
unified audit log using a 16-field pipe-delimited format.

**Log location**: `~/.config/fabric/cost_audit.log`

**Format** (pipe-delimited, one entry per line):

```
[TIMESTAMP] | COMPONENT | RUN_ID | SKILL | ARTIFACT | VENDOR | MODEL | TOKENS_IN | TOKENS_OUT | COST_IN | COST_OUT | COST_TOTAL | ELAPSED_MS | ENV | UPSTREAM_ID | NOTES
```

**Field definitions**:

| # | Field | Type | Values / Example |
|---|-------|------|-----------------|
| 0 | TIMESTAMP | ISO 8601 | `2026-03-14T10:46:17.123` |
| 1 | COMPONENT | string | `sync_skill` · `deploy_generators` · `fabric_stitch` · `pre_tool_call` · `post_tool_call` · `task_complete` · `langgraph_exc` · `marimo_monitor` · `principal_system_architect` · `requirements_gathering` |
| 2 | RUN_ID | uuidv7 | `019541c2-a1b3-7e4d-9f2a-3b8c7d6e5f4a` |
| 3 | SKILL | FQSN | `CodingArchitecture/FabricStitch/ACMS_extract_wisdom` |
| 4 | ARTIFACT | string | see Artifact Taxonomy below |
| 5 | VENDOR | string | `anthropic` · `google` · `ollama` |
| 6 | MODEL | string | `gemini-2.0-flash` · `qwen3:8b` · `claude-sonnet-4-6` |
| 7 | TOKENS_IN | int | `478` |
| 8 | TOKENS_OUT | int | `421` |
| 9 | COST_IN | float | `0.000465` |
| 10 | COST_OUT | float | `0.001338` |
| 11 | COST_TOTAL | float | `0.001803` |
| 12 | ELAPSED_MS | int | `4821` |
| 13 | ENV | string | `dev` · `qa` · `prod` |
| 14 | UPSTREAM_ID | uuidv7 or empty | RUN_ID of originating sync |
| 15 | NOTES | string | optional free text |

**Artifact Taxonomy** (ARTIFACT field — eliminates system.md ambiguity):

```
# PrincipalSystemArchitect tier
principal_system_architect.system.md
requirements_identity.system.md
requirements_mission.system.md
requirements_authorities.system.md
requirements_lifecycle.system.md
requirements_cost_model.system.md
requirements_data.system.md

# Skill tier
skill.system.md              ← primary behavioral contract (source of truth)
transformer.yaml.system.md   ← yaml transformer pattern prompt
transformer.toon.system.md   ← toon transformer pattern prompt

# Derived artifact tier
skill.system.yaml            ← derived yaml artifact
skill.system.toon            ← derived toon artifact

# Execution tier (Fabric pipeline)
fabric_stitch.step_N         ← step N of FabricStitch pipeline

# Execution tier (LangGraph pipeline)
langgraph.node_NAME          ← named LangGraph node

# Hook tier
hook.pre_tool_call           ← pre-tool lifecycle hook
hook.post_tool_call          ← post-tool lifecycle hook
hook.task_complete           ← task completion hook

# Session tier
session.total                ← aggregated session summary
```

**Provenance chain** — RUN_ID and UPSTREAM_ID enable full ancestry:

```
RUN-000  PrincipalSystemArchitect elicitation
    └── RUN-001  skill.system.md synthesis
            └── RUN-002  sync (yaml + toon generation)
                    └── RUN-003  fabric_stitch / langgraph execution
```

Polars query `group_by(UPSTREAM_ID).sum(COST_TOTAL)` gives total cost
of ownership for everything that flowed from a single system.md sync.

**Example entries showing full chain**:

```
[2026-03-14T10:46:17.000] | sync_skill | RUN-002 | CodingArchitecture/FabricStitch/ACMS_extract_wisdom | skill.system.md | ollama | qwen3:8b | 478 | 0 | 0.000000 | 0.000000 | 0.000000 | 0 | dev | RUN-001 | source measured
[2026-03-14T10:46:17.001] | sync_skill | RUN-002 | CodingArchitecture/FabricStitch/ACMS_extract_wisdom | transformer.yaml.system.md | ollama | qwen3:8b | 312 | 0 | 0.000000 | 0.000000 | 0.000000 | 0 | dev | RUN-001 | transformer prompt measured
[2026-03-14T10:46:17.002] | sync_skill | RUN-002 | CodingArchitecture/FabricStitch/ACMS_extract_wisdom | transformer.toon.system.md | ollama | qwen3:8b | 287 | 0 | 0.000000 | 0.000000 | 0.000000 | 0 | dev | RUN-001 | transformer prompt measured
[2026-03-14T10:46:17.123] | sync_skill | RUN-002 | CodingArchitecture/FabricStitch/ACMS_extract_wisdom | skill.system.yaml | ollama | qwen3:8b | 790 | 421 | 0.000000 | 0.000000 | 0.000000 | 23452 | dev | RUN-001 | in=skill+transformer combined
[2026-03-14T10:46:17.124] | sync_skill | RUN-002 | CodingArchitecture/FabricStitch/ACMS_extract_wisdom | skill.system.toon | ollama | qwen3:8b | 765 | 333 | 0.000000 | 0.000000 | 0.000000 | 23452 | dev | RUN-001 | in=skill+transformer combined
[2026-03-14T11:02:44.000] | langgraph_exc | RUN-003 | CodingArchitecture/FabricStitch/ACMS_extract_wisdom | langgraph.node_validate | google | gemini-2.0-flash | 333 | 180 | 0.000125 | 0.000270 | 0.000395 | 1240 | dev | RUN-002 | consumed skill.system.toon
[2026-03-14T11:02:48.000] | langgraph_exc | RUN-003 | CodingArchitecture/FabricStitch/ACMS_extract_wisdom | langgraph.node_execute | anthropic | claude-sonnet-4-6 | 892 | 445 | 0.002676 | 0.006675 | 0.009351 | 8234 | dev | RUN-002 | ripple from skill.system.md
```

**Components that write to cost_audit.log**:

```
sync_skill.sh              ← Step 9 (patched — per-artifact breakdown)
deploy_generators.sh       ← Step 9 (patched — per-artifact breakdown)
fabric_stitch.sh           ← per step (patched — artifact-aware)
pre_tool_call.py           ← hook entry (token env vars)
post_tool_call.py          ← hook entry (cost per tool call)
task_complete.py           ← session summary (all artifacts)
langgraph_exc nodes        ← per node (future)
marimo_monitor             ← read-only consumer (future)
principal_system_architect ← elicitation cost (future)
requirements_gathering/*   ← specialist cost (future)
```

---

## 5. Decision 2 — PrincipalSystemArchitect

**Decision**: The orchestrating meta-skill that governs elicitation is
named `PrincipalSystemArchitect` — not PSA, not dispatcher, not
orchestrator.

**Rationale**: `PrincipalSystemArchitect` is a Business Glossary Domain
name. It declares its role unambiguously without institutional memory.
Any practitioner reading the FQSN immediately understands the role
hierarchy. This is D⁴ BGD naming applied to skill taxonomy.

**FQSN**:
`MetaArchitecture/PrincipalSystemArchitect/ACMS_principal_system_architect`

**Role**:
- Dispatches to RequirementsGathering specialists in sequence
- Collects specialist responses
- Synthesizes responses into `skill.system.md`
- Scores elicitation completeness against refinement criteria
- Writes cost audit entries for the full elicitation run

**POC V1.0 dispatch sequence**:
```
1. ACMS_requirements_identity     → who is this agent?
2. ACMS_requirements_mission      → what does it do?
3. ACMS_requirements_authorities  → what can it touch?
4. ACMS_requirements_lifecycle    → how does it start and end?
5. ACMS_requirements_cost_model   → what does it cost to run?
6. ACMS_requirements_data         → what flows in and out?
7. PrincipalSystemArchitect synthesizes → skill.system.md
```

**Future expansion** (post-POC):
```
MetaArchitecture/PrincipalSystemArchitect/
├── ACMS_principal_system_architect/  ← dispatcher (POC V1.0)
├── ACMS_psa_synthesizer/             ← synthesis specialist
└── ACMS_psa_quality_gate/            ← elicitation completeness scorer
```

---

## 6. Decision 3 — RequirementsGathering Specialists

**Decision**: Six specialist elicitation skills for POC V1.0, each
responsible for one topical domain of requirements gathering.

**Location**: `CodingArchitecture/RequirementsGathering/`

**Rationale**: RequirementsGathering belongs in CodingArchitecture
because the elicitation patterns are reusable HOW patterns — the same
identity elicitation works for a diary skill or an extract_wisdom skill.
Domain does not change the elicitation pattern.

**POC V1.0 specialists**:

| FQSN | Elicits | Every skill? |
|------|---------|-------------|
| `CodingArchitecture/RequirementsGathering/ACMS_requirements_identity` | Persona, role, tone, name | ✅ Yes |
| `CodingArchitecture/RequirementsGathering/ACMS_requirements_mission` | Purpose, termination condition | ✅ Yes |
| `CodingArchitecture/RequirementsGathering/ACMS_requirements_authorities` | Tools, constraints, permissions | ✅ Yes |
| `CodingArchitecture/RequirementsGathering/ACMS_requirements_lifecycle` | Hooks, pre/post, task_complete | ✅ Yes |
| `CodingArchitecture/RequirementsGathering/ACMS_requirements_cost_model` | Vendor, token budget, thresholds | ACMS-specific |
| `CodingArchitecture/RequirementsGathering/ACMS_requirements_data` | Inputs, outputs, formats, schemas | Pipeline-specific |

**Deferred to post-POC**:
- `ACMS_requirements_security` — not blocking March 16
- `ACMS_requirements_compliance` — institutional concerns
- `ACMS_requirements_performance` — latency budgets
- `ACMS_requirements_ux` — Marimo monitor concerns

**POC V1.0 status marker** (in every specialist system.md frontmatter):
```yaml
status: POC-V1.0
refinement_gate: After first 3 live elicitation runs
refinement_criteria:
  - Elicitation completeness score > 80%
  - skill.system.md token count < 800 tokens
  - No manual additions required post-synthesis
```

---

## 7. Decision 4 — Self-Documenting Naming as BGD Governance

**Decision**: All skill names, domain names, and artifact names follow
D⁴ BGD naming conventions — full English names, no abbreviations, no
acronyms that require institutional memory to decode.

**Rationale**:

In D⁴, Business Glossary Domains are named for what they govern, not
abbreviated for convenience. Institutional memory is exactly what
governance systems exist to eliminate. A new contributor reading a FQSN
must understand the role hierarchy without asking anyone.

**Applied consistently**:

| Abbreviated (rejected) | Self-documenting (accepted) |
|----------------------|---------------------------|
| `PSA` | `PrincipalSystemArchitect` |
| `ACMS_psa` | `ACMS_principal_system_architect` |
| `ACMS_req_identity` | `ACMS_requirements_identity` |
| `psa.system.md` | `principal_system_architect.system.md` |
| `skill.sys.md` | `skill.system.md` |

**The deeper principle**: self-documenting names are the architectural
antidote to the Celibacy Problem. When Navigator knowledge is embedded
in the names themselves, the system carries its own institutional memory.
New practitioners can onboard from the taxonomy alone.

---

## 8. Decision 5 — POC V1.0 Scope and Refinement Gate

**Decision**: Structure is permanent, content is provisional.

The FQSN taxonomy, PSA dispatch sequence, elicitation call order, and
cost audit log format are architectural decisions — locked in now.

The actual questions each specialist asks, the synthesis rules the PSA
applies, and the completeness scoring algorithm are POC-grade
implementations — explicitly marked for refinement after live runs.

**Refinement gate**: After 3 live elicitation runs on real skills,
review all six RequirementsGathering specialists and the PSA synthesizer
against the refinement criteria. Document findings as ADR-010.

**What this means for March 16 demo**: The PrincipalSystemArchitect and
RequirementsGathering skills are demonstrated as working POC
implementations — not production-grade elicitation. The architecture
is the demonstration, not the content quality.

---

## 9. The Full Architecture Under D⁴ MDLC

```
D⁴ MDLC Governance Layer
════════════════════════════════════════════════════════════

PrincipalSystemArchitect (MetaArchitecture)
    │  dispatches to RequirementsGathering specialists
    │  synthesizes → skill.system.md
    │  writes → cost_audit.log (RUN-000)
    ▼
skill.system.md  (BGD-governed behavioral contract)
    │  FQSN = B-tree navigation path
    │  No NULLs = no abbreviations
    │  Governance embedded in contract
    ▼
sync_skill.sh  (9-step pipeline)
    │  measures skill.system.md tokens
    │  measures transformer.yaml.system.md tokens
    │  measures transformer.toon.system.md tokens
    │  generates skill.system.yaml
    │  generates skill.system.toon
    │  writes → cost_audit.log (RUN-002, UPSTREAM_ID=RUN-001)
    ▼
fabric_stitch.sh / langgraph_exc  (execution pipelines)
    │  consumes skill.system.toon as input context
    │  writes → cost_audit.log (RUN-003, UPSTREAM_ID=RUN-002)
    ▼
cost_audit.log  (MDLC audit trail)
    │  16-field pipe-delimited format
    │  RUN_ID + UPSTREAM_ID = full provenance chain
    │  artifact taxonomy eliminates ambiguity
    ▼
cost_analyzer.py (Polars)  (metadata-driven reporting)
    │  group_by(ARTIFACT) → cost per artifact type
    │  group_by(UPSTREAM_ID) → total cost of ownership
    │  filter(skill.system.md) → bloat detection
    │  project(token_reduction) → cost savings projection
    ▼
cost_monitor.py (Marimo)  (MDLC dashboard)
    │  reactive UI fed by cost_analyzer.py
    │  live cost visibility per skill per run
    │  bloat alerts when skill.system.md > threshold
    ▼
vendor_rates.yaml  (single source of truth)
    all rate lookups → one file
    no hardcoded rates anywhere
```

---

## 10. Updated Taxonomy

```
aces-skills/
├── MetaArchitecture/
│   ├── ACMS_skill_deployers/                    ← existing
│   ├── ACMS_skill_generators/                   ← existing (transformers)
│   └── PrincipalSystemArchitect/                ← NEW (ADR-009)
│       └── ACMS_principal_system_architect/
│           ├── system.md
│           ├── system.yaml
│           └── system.toon
│
├── CodingArchitecture/
│   ├── FabricStitch/                            ← existing
│   ├── HookGenerator/                           ← existing
│   └── RequirementsGathering/                   ← NEW (ADR-009)
│       ├── ACMS_requirements_identity/
│       ├── ACMS_requirements_mission/
│       ├── ACMS_requirements_authorities/
│       ├── ACMS_requirements_lifecycle/
│       ├── ACMS_requirements_cost_model/
│       └── ACMS_requirements_data/
│
└── TaskArchitecture/
    └── DiaryWriter/                             ← existing
        └── ACMS_daily_diary/
```

---

## 11. Consequences

**Positive**:
- Full cost provenance from PSA elicitation through execution output
- Bloat detection at source — before it compounds downstream
- Self-documenting taxonomy eliminates institutional memory dependency
- D⁴ MDLC principles validated in a live agentic system
- March 16 demo shows governance AND cost intelligence simultaneously
- Foundation for post-POC PSA synthesizer and quality gate

**Constraints**:
- sync_skill.sh Step 9 requires patching (Step 3 of build sequence)
- deploy_generators.sh Step 9 requires patching (Step 4)
- post_tool_call.py and task_complete.py require patching (Step 5)
- RUN_ID generation requires uuidv7 — stdlib `uuid` module sufficient
  (`uuid.uuid7()` available Python 3.12+ or manual implementation)
- PrincipalSystemArchitect and RequirementsGathering skills to be built
  (next build sequence after cost infrastructure complete)

**Open questions** (flagged for ADR-010):
- Should the PSA dispatch sequence be configurable per domain, or fixed?
- Should elicitation completeness scoring be a separate LangGraph node?
- Should cost_audit.log rotate daily or by size threshold?
- Should UPSTREAM_ID support multi-parent (diamond dependency graphs)?

---

## 12. Publication Path

This ADR documents the first live proof that D⁴ MDLC generalizes
beyond database design to agentic AI governance. The publication path:

**Medium article**: "D⁴ MDLC — From Energy Billing to Agentic AI:
A Universal Governance Framework" — connects the 2003 NYC DCAS origin
to the 2026 ACMS POC. Target: Mind Over Metadata publication.

**Conference submission**: Position paper for a database/AI governance
conference — D⁴ as universal metadata governance framework.

**CUNY grant proposal**: D⁴ MDLC as curriculum framework for teaching
AI governance alongside database design. Positions CSCI 331 and 381
as foundational governance courses, not just technical courses.

**Copyright registration**: D⁴ MDLC as a methodology — US Copyright
Office eCO, Mind Over Metadata LLC as claimant.

---

## 13. Links

| | |
|--|--|
| ⬆️ Parent ADRs | [[ACMS-Architecture-Decisions-20260313]] |
| 🔄 ADR-008 | [[ADR-008-stdlib-hook-pattern]] |
| 🔄 VS Code 1.111 | [[VSCode-1110-Agent-Architecture]] |
| 🔄 Transformers | [[Transformer-Patterns-Component]] |
| 🔄 vendor_rates | [[vendor_rates-Component]] |
| 🔄 sync_skill | [[sync_skill-Component]] |
| 🔄 D⁴ Methodology | [[02-D4-MOC]] |
| 🔄 TOON | [[TOON-Serialization]] |
| 🌐 aces-skills repo | https://github.com/QCadjunct/aces-skills |

---

## Tags

`#ADR` `#ADR-009` `#D4-MDLC` `#governance` `#cost-accounting`
`#PrincipalSystemArchitect` `#RequirementsGathering` `#provenance`
`#RUN_ID` `#UPSTREAM_ID` `#bloat-ripple` `#self-documenting`
`#BGD` `#FQSN` `#ACMS` `#POC-V1.0` `#publication-path`
