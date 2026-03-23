# Credits and Acknowledgments

## aces-skills
**Author**: Peter Heller, Mind Over Metadata LLC  
**GitHub**: github.com/QCadjunct/aces-skills  
**© 2026 Mind Over Metadata LLC. All rights reserved.**

---

## Original Work in This Repository

The following are original contributions of Peter Heller / Mind Over Metadata LLC:

- **ACMS Architectural Framework** — the reincarnation of DEC's Application Control
  and Management System as a modern agentic orchestration model, using LangGraph
  as the Execution Controller, Marimo as DECforms, and system.md as the Task
  Definition Language
- **Three-File Skill Standard** — system.md / system.yaml / system.toon; system.md
  is the single source of truth; system.yaml and system.toon are derived artifacts
- **FQSN (Fully Qualified Skill Name) Taxonomy** — the three-pillar hierarchy:
  MetaArchitecture (abstract), CodingArchitecture (HOW), TaskArchitecture (WHAT)
- **TOON (Token-Optimized Object Notation)** — the wire format delivering ~19%
  token reduction vs YAML on validated skill data; `model_dump_tool()` is the
  canonical serialization method
- **Nine-Step Deployment Pipeline** — VALIDATE → RESOLVE → ARCHIVE → GENERATE →
  WRITE → CONFIRM → DEPLOY → LOG → COST; implemented in `deploy_generators.sh`
- **Cost Accounting Standard** — cost accounting as Step N in every bash utility,
  not an afterthought; per-token rate card across Anthropic, Google, and Ollama
- **Flat Deploy Pattern (ADR-003)** — taxonomy-to-runtime bridge via
  `deploy_generators.sh` across DEV → QA → PROD environments
- **D⁴ (Domain-Driven Database Design) Methodology** — the underlying governance
  philosophy informing skill taxonomy and naming conventions

---

## Third-Party Patterns and Attributions

### ADR-008 — stdlib-only Python Hook Scripts

The pattern of implementing deterministic pre/post processing logic as Python
scripts using only the standard library (zero external dependencies, zero pip
installs) is adapted from:

> **Reza Rezvani** — `claude-skills` repository  
> github.com/alirezarezvani/claude-skills  
> Used under open source license per repository terms.  
> Article: "AI Agent Skills at Scale" — alirezarezvani.medium.com (2026-03-14)

**What was adapted**: The design principle of stdlib-only Python scripts as
portable, dependency-free deterministic tools that ship alongside skill
definitions.

**What is original here**: The application of that pattern to agent-scoped
lifecycle hooks (pre_tool_call / post_tool_call / task_complete) within the
ACMS Execution Controller model, governed by the FQSN taxonomy, serialized
via system.toon, and orchestrated by LangGraph. The hook lifecycle itself
derives from VS Code 1.111's agent-scoped hooks formalization (2026-03-09).

Rezvani's pattern solves portability and dependency at the tool layer.
The ACMS framework provides the orchestration, governance, and serialization
layer above it. These are complementary contributions at different layers
of the stack.

**Direct outreach**: Peter Heller notified Reza Rezvani via LinkedIn on
2026-03-14, prior to this attribution being committed to the repository.

---

## How to Read This Credits File

If a pattern, algorithm, or design principle appears in this repository
without attribution, it is original work of Mind Over Metadata LLC.

If it is attributed above, the boundary between borrowed and original is
stated explicitly. Vague attribution is how practitioners obscure what
they built vs. what they borrowed. Precise attribution is how the
ecosystem builds trust.

---

*Last updated: 2026-03-14*
