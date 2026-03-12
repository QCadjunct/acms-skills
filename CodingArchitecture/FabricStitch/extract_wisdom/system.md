# CodingArchitecture/FabricStitch/extract_wisdom

## Identity
FQSN    : CodingArchitecture/FabricStitch/extract_wisdom
Version : 1.0.0
Agent   : BASH
Status  : active
Author  : Peter Heller
Org     : Mind Over Metadata LLC
Created : 2026-03-12

## Behavioral Contract
This skill orchestrates a multi-vendor Fabric pattern stitching
pipeline that extracts wisdom from any text source.

Input source is a parameter — YouTube URL, text file, or stdin.
Each pipeline step binds to an independently configured LLM vendor.
Vendor assignments live in system.yaml — not in this file.
Token counts and cost estimates are calculated per step.
All executions are recorded in audit.log.

## Pipeline Steps
1. extract_wisdom   — primary insight extraction       (Gemini Flash)
2. summarize        — condensed summary from wisdom    (Claude Sonnet)
3. extract_insights — distilled key insights           (Gemini Flash)
4. create_tags      — categorization tags              (Ollama local)
5. pandoc           — multi-format output              (no LLM)

## Inputs
- Text source: YouTube URL, file path, or stdin (required)
- Output directory (optional, defaults to ./output)

## Outputs
- 01_wisdom.md
- 02_summary.md
- 03_insights.md
- 04_tags.md
- 00_full_report.md
- full_report.pdf
- full_report.docx
- full_report.html

## Metrics Captured Per Step
- Duration (ms)
- Input token count
- Output token count
- Estimated cost (USD)

## Audit
Appends to audit.log on every execution.
Records: session ID, source, per-step timing,
token counts, cost estimates, vendor assignments.

## Runtime Requirements
- fabric >= 1.4.400 (WSL2)
- pandoc >= 3.1.3 + xelatex
- uv + tiktoken (token counting)
- ANTHROPIC_API_KEY
- GEMINI_API_KEY
- YouTube API key in ~/.config/fabric/.env

## ACMS Framework Mapping
AgentType    : BASH
TaskGroup    : DataExtract
WorkspaceKey : session_id (TIMESTAMP)
AuditLog     : audit.log
TOON format  : system.toon
