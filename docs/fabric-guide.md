# Fabric CLI — Comprehensive Options Guide

> **Repository**: `aces-skills/docs/fabric-guide.md`  
> **Author**: Peter Heller, Mind Over Metadata LLC  
> **Fabric version**: 1.4.400+ (WSL2 Ubuntu 24.04 LTS)  
> **Last updated**: 2026-03-14  
> **ACMS Integration**: sync_skill.sh · fabric_stitch.sh · deploy_generators.sh

---

## 📑 Table of Contents

1. [What Fabric Is](#1-what-fabric-is)
2. [Flag Taxonomy](#2-flag-taxonomy)
3. [Core Flags — Pattern and Model](#3-core-flags--pattern-and-model)
4. [Input Flags](#4-input-flags)
5. [Output Flags](#5-output-flags)
6. [Session and Context Flags](#6-session-and-context-flags)
7. [Model Behavior Flags](#7-model-behavior-flags)
8. [YouTube and Media Flags](#8-youtube-and-media-flags)
9. [Search and Scraping Flags](#9-search-and-scraping-flags)
10. [Server Flags](#10-server-flags)
11. [Image Generation Flags](#11-image-generation-flags)
12. [Audio and Transcription Flags](#12-audio-and-transcription-flags)
13. [Extension and Strategy Flags](#13-extension-and-strategy-flags)
14. [Combinations Reference](#14-combinations-reference)
15. [Dangerous Combinations](#15-dangerous-combinations)
16. [Standalone Examples — No Stitching](#16-standalone-examples--no-stitching)
17. [FabricStitch Pipeline Examples](#17-fabricstitch-pipeline-examples)
18. [ACMS Integration Examples](#18-acms-integration-examples)
19. [Cost Accounting Integration](#19-cost-accounting-integration)

---

## 1. What Fabric Is

Fabric (Daniel Miessler, github.com/danielmiessler/fabric) is a modular
AI augmentation framework. At its core: pipe text into a pattern, get
augmented text out. Patterns are markdown system prompts stored in
`~/.config/fabric/patterns/`.

```
stdin → fabric --pattern PATTERN_NAME → stdout
```

In the ACMS architecture, Fabric is the **execution layer** for single-step
LLM invocations. FabricStitch chains multiple fabric calls into a pipeline.
The ACMS transformers (`from_system.md_to_system.yaml`, `from_system.md_to_system.toon`)
are Fabric patterns deployed to `patterns_custom/`.

---

## 2. Flag Taxonomy

Flags grouped by function — not alphabetical order:

| Group | Flags | Purpose |
|-------|-------|---------|
| **Core** | `-p`, `-m`, `-V`, `-C` | Pattern, model, vendor, context |
| **Input** | `-a`, `--input-has-vars`, `--no-variable-replacement` | Attachments, variable substitution |
| **Output** | `-o`, `-c`, `--output-session` | File output, clipboard, session |
| **Session** | `--session`, `-w`, `-W`, `-x`, `-X` | Session management |
| **Model behavior** | `-t`, `-T`, `-P`, `-F`, `-e`, `-r`, `--thinking` | Temperature, sampling, seed |
| **YouTube** | `-y`, `--transcript`, `--comments`, `--metadata`, `--playlist` | Video ingestion |
| **Search/scrape** | `-u`, `-q`, `--search`, `--search-location`, `--readability` | Web content |
| **Server** | `--serve`, `--serveOllama`, `--address`, `--api-key` | REST API mode |
| **Image gen** | `--image-file`, `--image-size`, `--image-quality` | Image output |
| **Audio** | `--transcribe-file`, `--transcribe-model`, `--voice` | Speech I/O |
| **Extensions** | `--addextension`, `--rmextension`, `--listextensions` | Plugin management |
| **Strategy** | `--strategy`, `--liststrategies` | Multi-step strategies |
| **Utility** | `-l`, `-L`, `-n`, `-d`, `--version`, `--dry-run` | Discovery, diagnostics |

---

## 3. Core Flags — Pattern and Model

### `-p` / `--pattern` *(required for most invocations)*

Selects the pattern to apply. Pattern files live in:
- `~/.config/fabric/patterns/` — official patterns (updated via `--updatepatterns`)
- `~/.config/fabric/patterns_custom/` — user patterns (survive updates)

```bash
fabric --pattern extract_wisdom < article.md
fabric --pattern from_system.md_to_system.yaml < system.md
```

Patterns are markdown files containing a system prompt. The pattern name
is the folder name, not the filename. Each pattern folder contains
`system.md` (required) and optionally `user.md`.

### `-m` / `--model`

Specifies the model. Format: `model_name` (Fabric resolves vendor from
the configured default) or use with `-V` for explicit vendor.

```bash
fabric --model gemma3:12b --pattern extract_wisdom
fabric --model claude-sonnet-4-6 --pattern summarize
fabric --model gemini-2.0-flash --pattern extract_insights
```

**ACMS models in use:**

| Model | Vendor | Cost | Speed | Use case |
|-------|--------|------|-------|---------|
| `gemma3:12b` | Ollama | $0 | 12s | Default sync transformer |
| `qwen3:8b` | Ollama | $0 | 23s | Fallback local |
| `qwen3:30b` | Ollama | $0 | ~45s | Higher quality local |
| `gemini-2.0-flash` | Google | $0.000000375/in | 3-5s | FabricStitch steps |
| `claude-sonnet-4-6` | Anthropic | $0.000003/in | 5-8s | Summarization steps |

### `-V` / `--vendor`

Explicit vendor selection. Used when model name is ambiguous across vendors.

```bash
fabric --vendor Ollama --model gemma3:12b --pattern extract_wisdom
fabric --vendor Anthropic --model claude-sonnet-4-6 --pattern summarize
fabric --vendor Google --model gemini-2.0-flash --pattern extract_insights
```

**Vendor strings** (case-sensitive in some versions):
`Ollama` · `Anthropic` · `Google` · `OpenAI` · `Perplexity` · `GitHub`

### `-C` / `--context`

Loads a saved context file from `~/.config/fabric/contexts/`. Contexts
prepend additional system-level information before the pattern.

```bash
fabric --context acms_project --pattern extract_wisdom < input.md
```

Use contexts for project-specific background that shouldn't live in the
pattern itself — domain glossaries, architectural constraints, rate cards.

### `-v` / `--variable`

Injects variables into pattern templates. Format: `-v=#variable:value`.

```bash
fabric --pattern summarize -v=#role:expert -v=#length:short < article.md
```

Variables in patterns use `{{variable}}` syntax. Multiple `-v` flags allowed.

---

## 4. Input Flags

### `-a` / `--attachment`

Attaches a file or URL for multimodal models (images, PDFs).

```bash
# Image input for vision models
fabric --pattern describe_image -a screenshot.png --model gpt-4o

# URL attachment
fabric --pattern analyze_page -a https://example.com/report.pdf
```

### `--input-has-vars`

Applies variable substitution to the user's stdin input (not just the pattern).
Used when the input itself contains `{{variable}}` placeholders.

```bash
echo "Summarize {{topic}} in {{length}} words" | \
  fabric --pattern passthrough \
    --input-has-vars \
    -v=#topic:"quantum computing" \
    -v=#length:100
```

### `--no-variable-replacement`

Disables all variable substitution. Use when input contains `{{` or `}}`
that should not be treated as variables (e.g., code templates, Jinja2).

```bash
cat jinja_template.html | fabric --pattern analyze_template --no-variable-replacement
```

---

## 5. Output Flags

### `-o` / `--output`

Writes output to a file instead of stdout. Does not suppress stdout.

```bash
fabric --pattern extract_wisdom < article.md -o wisdom.md
fabric --pattern from_system.md_to_system.yaml < system.md -o system.yaml
```

**ACMS usage**: sync_skill.sh uses `-o` for transformer output:
```bash
fabric --pattern from_system.md_to_system.yaml < system.md > system.yaml
# Note: ACMS uses shell redirect (>) not -o, for pipeline compatibility
```

### `-c` / `--copy`

Copies output to clipboard in addition to stdout. Useful for interactive use.

```bash
fabric --pattern summarize --copy < long_article.md
```

### `--output-session`

Writes the complete session (including system prompt, user input, and
response) to the output file. Use with `-o`.

```bash
fabric --pattern extract_wisdom --output-session -o full_session.md < article.md
```

Useful for debugging pattern behavior — you see exactly what was sent to
the model.

---

## 6. Session and Context Flags

### `--session`

Loads or creates a named session for multi-turn conversations.

```bash
# Start a session
fabric --session acms_design --pattern analyze < requirements.md

# Continue the session
echo "Now summarize the key decisions" | fabric --session acms_design
```

Sessions persist conversation history across invocations. Stored in
`~/.config/fabric/sessions/`.

### `-w` / `--wipecontext` and `-W` / `--wipesession`

Clear a specific context or session.

```bash
fabric --wipecontext acms_project
fabric --wipesession acms_design
```

### `-x` / `--listcontexts` and `-X` / `--listsessions`

List available contexts and sessions.

```bash
fabric --listcontexts
fabric --listsessions
```

### `--printcontext` and `--printsession`

Print the content of a specific context or session.

```bash
fabric --printcontext acms_project
fabric --printsession acms_design
```

---

## 7. Model Behavior Flags

### `-t` / `--temperature`

Controls randomness (0.0 = deterministic, 1.0 = creative). Default: 0.7.

```bash
# Deterministic — use for ACMS transformers
fabric --temperature 0 --pattern from_system.md_to_system.yaml < system.md

# Creative — use for brainstorming
fabric --temperature 0.9 --pattern brainstorm < topic.md
```

**ACMS standard**: all transformer patterns should use `temperature 0`
for deterministic, reproducible output. The MD5 hash-based change
detection in sync_skill.sh depends on this.

### `-T` / `--topp`

Top-P sampling threshold. Default: 0.9. Lower = more focused output.

```bash
fabric --topp 0.7 --pattern extract_wisdom < article.md
```

### `-P` / `--presencepenalty`

Penalizes tokens already present in the output. Default: 0.0.
Positive values reduce repetition.

```bash
fabric --presencepenalty 0.3 --pattern create_tags < content.md
```

### `-F` / `--frequencypenalty`

Penalizes tokens based on frequency in output. Default: 0.0.

```bash
fabric --frequencypenalty 0.2 --pattern summarize < article.md
```

### `-e` / `--seed`

Sets random seed for reproducible output (where supported by model).

```bash
fabric --seed 42 --pattern extract_wisdom < article.md
```

### `-r` / `--raw`

Uses model defaults without sending chat options (temperature, top_p, etc.).
Only affects OpenAI-compatible providers. Anthropic always uses smart
parameter selection.

```bash
fabric --raw --model claude-sonnet-4-6 --pattern summarize < article.md
```

### `--thinking`

Sets reasoning/thinking level for models that support it.
Values: `off` · `low` · `medium` · `high` · numeric tokens.

```bash
fabric --thinking high --model claude-sonnet-4-6 --pattern analyze < complex.md
fabric --thinking 10000 --model gemini-2.5-pro --pattern reason < problem.md
```

### `--suppress-think`

Suppresses text enclosed in thinking tags (`<think>...</think>`) from output.

```bash
fabric --thinking high --suppress-think --pattern analyze < article.md
```

### `--modelContextLength`

Sets model context length (Ollama only).

```bash
fabric --model qwen3:30b --modelContextLength 32768 --pattern analyze < long_doc.md
```

---

## 8. YouTube and Media Flags

### `-y` / `--youtube`

Fetches transcript and/or comments from a YouTube URL.

```bash
# Fetch transcript and pipe to pattern
fabric --youtube "https://youtu.be/VIDEO_ID" --pattern extract_wisdom

# With timestamps
fabric --youtube "https://youtu.be/VIDEO_ID" --transcript-with-timestamps --pattern summarize
```

### `--transcript` (default) / `--transcript-with-timestamps`

Controls transcript format. Timestamps useful for reference linking.

### `--comments`

Fetches video comments instead of transcript.

```bash
fabric --youtube "https://youtu.be/VIDEO_ID" --comments --pattern analyze_sentiment
```

### `--metadata`

Outputs video metadata (title, description, channel, date) to console.

```bash
fabric --youtube "https://youtu.be/VIDEO_ID" --metadata --pattern summarize
```

### `--playlist`

Prefers playlist processing when URL contains both video and playlist IDs.

### `--yt-dlp-args`

Passes additional arguments to yt-dlp for authenticated or restricted videos.

```bash
fabric --youtube "URL" --yt-dlp-args "--cookies-from-browser brave" --pattern extract_wisdom
```

### `--spotify`

Fetches metadata from a Spotify podcast or episode URL.

```bash
fabric --spotify "https://open.spotify.com/episode/..." --pattern summarize
```

---

## 9. Search and Scraping Flags

### `-u` / `--scrape_url`

Scrapes a URL to markdown using Jina AI, then pipes to pattern.

```bash
fabric --scrape_url "https://example.com/article" --pattern extract_wisdom
fabric --scrape_url "https://docs.anthropic.com/pricing" --pattern summarize
```

### `-q` / `--scrape_question`

Searches using Jina AI and pipes results to pattern.

```bash
fabric --scrape_question "ACMS architecture patterns" --pattern summarize
```

### `--search`

Enables web search tool for supported models (Anthropic, OpenAI, Gemini).

```bash
fabric --search --model gemini-2.0-flash --pattern research < query.md
```

### `--search-location`

Sets location for web search results.

```bash
fabric --search --search-location "America/New_York" --pattern research < query.md
```

### `--readability`

Converts HTML input into a clean, readable view before processing.

```bash
curl -s "https://example.com/article" | fabric --readability --pattern extract_wisdom
```

---

## 10. Server Flags

### `--serve`

Starts the Fabric REST API server.

```bash
fabric --serve --address :8080
fabric --serve --address :8080 --api-key your-secret-key
```

### `--serveOllama`

Serves Fabric REST API with Ollama-compatible endpoints.

```bash
fabric --serveOllama --address :8080
```

### `--address`

Binds the REST API to a specific address. Default: `:8080`.

### `--api-key`

Secures server routes with an API key.

---

## 11. Image Generation Flags

### `--image-file`

Saves generated image to a file path.

```bash
fabric --pattern create_image --image-file output.png < prompt.md
```

### `--image-size`

Sets image dimensions. Values: `1024x1024` · `1536x1024` · `1024x1536` · `auto`.

### `--image-quality`

Sets image quality. Values: `low` · `medium` · `high` · `auto`.

### `--image-compression`

Compression level 0-100 for JPEG/WebP formats.

### `--image-background`

Background type: `opaque` · `transparent` (PNG/WebP only).

---

## 12. Audio and Transcription Flags

### `--transcribe-file`

Transcribes an audio or video file.

```bash
fabric --transcribe-file lecture.mp4 --pattern summarize
fabric --transcribe-file meeting.wav --pattern extract_wisdom
```

### `--transcribe-model`

Specifies transcription model (separate from chat model).

```bash
fabric --transcribe-file audio.mp3 --transcribe-model whisper-1 --pattern summarize
```

### `--split-media-file`

Splits audio/video files larger than 25MB using ffmpeg before transcription.

### `--voice`

Sets TTS voice for supported models (e.g., Kore, Charon, Puck). Default: Kore.

```bash
fabric --voice Charon --pattern create_narration < script.md
```

### `--list-gemini-voices`

Lists available Gemini TTS voices.

### `--list-transcription-models`

Lists available transcription models.

---

## 13. Extension and Strategy Flags

### `--addextension` / `--rmextension` / `--listextensions`

Manage Fabric extensions (plugins) from config files.

```bash
fabric --addextension /path/to/extension.yaml
fabric --listextensions
fabric --rmextension extension-name
```

### `--strategy` / `--liststrategies`

Apply a multi-step strategy (chained pattern execution).

```bash
fabric --liststrategies
fabric --strategy research_and_summarize < topic.md
```

### `-S` / `--setup`

Interactive setup for all reconfigurable parts of Fabric (API keys, default model, etc.).

```bash
fabric --setup
```

---

## 14. Combinations Reference

### Natural combinations — flags that work well together

| Combination | Use case |
|-------------|---------|
| `--pattern P --model M --temperature 0` | Deterministic transformation — ACMS transformers |
| `--pattern P --model M --session S` | Multi-turn analysis session |
| `--youtube URL --pattern P` | Video content extraction |
| `--scrape_url URL --readability --pattern P` | Clean web article processing |
| `--pattern P --output FILE --copy` | Save + clipboard simultaneously |
| `--pattern P --thinking high --suppress-think` | Deep reasoning, clean output |
| `--pattern P --dry-run` | Preview what would be sent to model |
| `--pattern P --output-session -o FILE` | Debug pattern behavior |
| `--transcribe-file F --split-media-file --pattern P` | Large audio file processing |
| `--search --model gemini-2.0-flash --pattern P` | Web-augmented analysis |

### ACMS-specific combinations

```bash
# Standard transformer invocation (deterministic)
fabric --model gemma3:12b \
       --temperature 0 \
       --pattern from_system.md_to_system.yaml \
       < system.md > system.yaml

# FabricStitch step (cost-optimized)
fabric --model gemini-2.0-flash \
       --pattern extract_wisdom \
       --output step1_wisdom.md \
       < input.md

# High-quality summarization step
fabric --model claude-sonnet-4-6 \
       --pattern summarize \
       --temperature 0.3 \
       < step1_wisdom.md > step2_summary.md

# Local zero-cost tagging step
fabric --model qwen3:8b \
       --temperature 0 \
       --pattern create_tags \
       < step2_summary.md > step3_tags.md
```

---

## 15. Dangerous Combinations

### ⚠ Never combine these

| Combination | Why dangerous |
|-------------|--------------|
| `--temperature 0` + `--seed` + Anthropic | Anthropic ignores both; creates false confidence in reproducibility |
| `--serve` without `--api-key` | Exposes unauthenticated REST API to network |
| `--session S` + `--temperature 0` | Session history accumulates; determinism breaks on turn 2+ |
| `--search` + `--scrape_url` | Double web fetch — redundant, may hit rate limits |
| `--raw` + Anthropic model | Anthropic always overrides; `--raw` has no effect, misleading |
| `--output FILE` + shell redirect `>` | Double write — FILE and redirect may conflict |
| `--youtube URL` + `--comments` + large video | Comments can be enormous; pipe to pattern may exceed context |
| `--thinking high` without `--suppress-think` | Thinking tokens appear in output — noisy in pipelines |
| `--modelContextLength` with non-Ollama | Flag silently ignored; may cause unexpected truncation |

### ⚠ Use with caution

| Combination | Caution |
|-------------|---------|
| `--temperature 0` + creative patterns | Deterministic output may be low quality for brainstorming |
| `--session` in automated pipelines | Sessions accumulate state — stale context contaminates later runs |
| `--frequencypenalty` + `--presencepenalty` both non-zero | Compound penalty may produce stilted output |
| `--topp 0` | Fully greedy decoding — may produce repetitive output |
| `--wipecontext` / `--wipesession` | Permanent deletion, no confirmation prompt |

---

## 16. Standalone Examples — No Stitching

### Basic pattern invocation

```bash
# Extract wisdom from an article
fabric --pattern extract_wisdom < article.md

# Summarize with specific model
fabric --model gemma3:12b --pattern summarize < long_doc.md

# Save output to file
fabric --pattern extract_wisdom -o wisdom.md < article.md

# Copy to clipboard
fabric --pattern summarize --copy < article.md
```

### YouTube content extraction

```bash
# Extract wisdom from YouTube video
fabric --youtube "https://youtu.be/VIDEO_ID" --pattern extract_wisdom

# Summarize with timestamps
fabric --youtube "https://youtu.be/VIDEO_ID" \
       --transcript-with-timestamps \
       --pattern summarize \
       -o summary_with_timestamps.md
```

### Web scraping + pattern

```bash
# Analyze a web article
fabric --scrape_url "https://example.com/post" \
       --readability \
       --pattern extract_wisdom

# Research a topic
fabric --scrape_question "LangGraph agent patterns 2026" \
       --pattern summarize \
       -o research_notes.md
```

### Deterministic transformation

```bash
# ACMS transformer — always use temperature 0
fabric --model gemma3:12b \
       --temperature 0 \
       --pattern from_system.md_to_system.yaml \
       < CodingArchitecture/FabricStitch/ACMS_extract_wisdom/system.md \
       > /tmp/test_output.yaml

# Validate result
python3 -c "import yaml; yaml.safe_load(open('/tmp/test_output.yaml')); print('✓ valid')"
```

### Session-based analysis

```bash
# Turn 1 — initial analysis
fabric --session acms_review \
       --pattern analyze \
       < ADR-009-D4-MDLC-Governance.md

# Turn 2 — follow-up in same session
echo "What are the three most important architectural decisions?" | \
  fabric --session acms_review
```

### Debug a pattern

```bash
# See exactly what gets sent to the model
fabric --pattern extract_wisdom \
       --output-session \
       -o debug_session.md \
       --dry-run \
       < article.md
```

---

## 17. FabricStitch Pipeline Examples

FabricStitch chains multiple fabric invocations into a multi-vendor,
multi-step pipeline. Each step's output is the next step's input.

### ACMS_extract_wisdom — 5-step pipeline

```bash
#!/usr/bin/env bash
# ACMS_extract_wisdom FabricStitch pipeline
# Multi-vendor: Gemini → Claude → Gemini → Ollama → Pandoc

INPUT="$1"
OUTPUT_DIR="${2:-./output}"
mkdir -p "$OUTPUT_DIR"

# Step 1: Extract wisdom (Gemini Flash — cost-optimized)
echo "Step 1: extract_wisdom..."
fabric --model gemini-2.0-flash \
       --pattern extract_wisdom \
       < "$INPUT" \
       > "$OUTPUT_DIR/01_wisdom.md"

# Step 2: Summarize (Claude Sonnet — high quality)
echo "Step 2: summarize..."
fabric --model claude-sonnet-4-6 \
       --pattern summarize \
       < "$OUTPUT_DIR/01_wisdom.md" \
       > "$OUTPUT_DIR/02_summary.md"

# Step 3: Extract insights (Gemini Flash — cost-optimized)
echo "Step 3: extract_insights..."
fabric --model gemini-2.0-flash \
       --pattern extract_insights \
       < "$OUTPUT_DIR/01_wisdom.md" \
       > "$OUTPUT_DIR/03_insights.md"

# Step 4: Create tags (Ollama — zero cost)
echo "Step 4: create_tags..."
fabric --model qwen3:8b \
       --temperature 0 \
       --pattern create_tags \
       < "$OUTPUT_DIR/02_summary.md" \
       > "$OUTPUT_DIR/04_tags.md"

# Step 5: Multi-format output (Pandoc — no LLM)
echo "Step 5: pandoc conversion..."
cat "$OUTPUT_DIR/01_wisdom.md" "$OUTPUT_DIR/02_summary.md" \
    "$OUTPUT_DIR/03_insights.md" "$OUTPUT_DIR/04_tags.md" \
    > "$OUTPUT_DIR/00_full_report.md"
pandoc "$OUTPUT_DIR/00_full_report.md" -o "$OUTPUT_DIR/full_report.pdf"
pandoc "$OUTPUT_DIR/00_full_report.md" -o "$OUTPUT_DIR/full_report.docx"

echo "✓ Pipeline complete: $OUTPUT_DIR/"
```

### Simple two-step pipeline

```bash
#!/usr/bin/env bash
# Extract then summarize — minimal pipeline

INPUT="$1"

# Step 1
WISDOM=$(fabric --model gemini-2.0-flash --pattern extract_wisdom < "$INPUT")

# Step 2 — pipe step 1 output directly
echo "$WISDOM" | fabric --model claude-sonnet-4-6 --pattern summarize
```

### YouTube → wisdom pipeline

```bash
#!/usr/bin/env bash
# YouTube video → extracted wisdom → summary

VIDEO_URL="$1"

# Step 1: Get transcript and extract wisdom
WISDOM=$(fabric --youtube "$VIDEO_URL" --pattern extract_wisdom)

# Step 2: Summarize
echo "$WISDOM" | fabric --model claude-sonnet-4-6 --pattern summarize -o summary.md

echo "✓ Summary saved to summary.md"
```

---

## 18. ACMS Integration Examples

### sync_skill.sh — transformer invocation

```bash
# How sync_skill.sh calls fabric (Step 5)
fabric --pattern from_system.md_to_system.yaml \
  < "$SOURCE_ABS" \
  > "$SKILL_DIR/system.yaml"

fabric --pattern from_system.md_to_system.toon \
  < "$SOURCE_ABS" \
  > "$SKILL_DIR/system.toon"
```

### Custom pattern with ACMS model selection

```bash
# Using vendor_rates.yaml default for fabric_stitch
VENDOR="google"
MODEL="gemini-2.0-flash"

fabric --model "$MODEL" \
       --vendor "$VENDOR" \
       --pattern extract_wisdom \
       < input.md \
       > output.md
```

### Deploying a custom ACMS pattern

```bash
# Create a new ACMS transformer pattern
mkdir -p ~/.config/fabric/patterns_custom/my_pattern
cat > ~/.config/fabric/patterns_custom/my_pattern/system.md << 'EOF'
# IDENTITY
You are a specialized transformer.
# MISSION
Transform input according to ACMS Three-File Skill Standard.
EOF

# Use it immediately
fabric --pattern my_pattern < system.md
```

### PrincipalSystemArchitect dispatch simulation

```bash
# Simulate PSA dispatching to identity specialist
fabric --model gemma3:12b \
       --temperature 0 \
       --pattern ACMS_requirements_identity \
       << 'EOF'
Skill intent: Extract and analyze cost data from cost_audit.log
Target domain: TaskArchitecture
Target subdomain: CostAnalysis
EOF
```

---

## 19. Cost Accounting Integration

Every Fabric invocation in the ACMS pipeline is tracked in `cost_audit.log`
(ADR-009 format). The cost accounting wraps each fabric call:

```bash
# Standard cost-tracked fabric invocation pattern
_track_fabric_call() {
  local vendor="$1" model="$2" pattern="$3" artifact="$4" skill="$5"
  local run_id="$6" env="$7"
  local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  # Measure input tokens
  local input_content=$(cat)
  local tokens_in=$(echo "$input_content" | wc -c | awk '{print int($1/4)}')

  # Run fabric and capture output
  local output
  local t_start=$(date +%s%3N)
  output=$(echo "$input_content" | \
    fabric --model "$model" --temperature 0 --pattern "$pattern")
  local elapsed=$(( $(date +%s%3N) - t_start ))

  local tokens_out=$(echo "$output" | wc -c | awk '{print int($1/4)}')

  # Write ADR-009 cost entry
  echo "[${timestamp}] | fabric_stitch | ${run_id} | ${skill} | ${artifact} | ${vendor,,} | ${model} | ${tokens_in} | ${tokens_out} | 0.000000 | 0.000000 | 0.000000 | ${elapsed} | ${env} | | pattern=${pattern}" \
    >> ~/.config/fabric/cost_audit.log

  # Return output
  echo "$output"
}

# Usage
output=$(_track_fabric_call \
  "Google" "gemini-2.0-flash" "extract_wisdom" \
  "fabric_stitch.step_1" \
  "CodingArchitecture/FabricStitch/ACMS_extract_wisdom" \
  "$RUN_ID" "dev" \
  < input.md)
```

### Viewing cost breakdown after a pipeline run

```bash
# After running sync_skill.sh or fabric_stitch.sh
uv run python3 cost/cost_analyzer.py
uv run python3 cost/cost_analyzer.py --compare
uv run python3 cost/cost_analyzer.py --bloat
uv run python3 cost/cost_analyzer.py --projection 0.20
```

---

## Utility Flags Quick Reference

| Flag | Purpose | Example |
|------|---------|---------|
| `-l` / `--listpatterns` | List all patterns | `fabric --listpatterns` |
| `-L` / `--listmodels` | List all models | `fabric --listmodels` |
| `-n` / `--latest N` | List N latest patterns | `fabric --latest 10` |
| `-d` / `--changeDefaultModel` | Change default model | `fabric --changeDefaultModel` |
| `--updatepatterns` / `-U` | Pull latest patterns | `fabric --updatepatterns` |
| `--version` | Print version | `fabric --version` |
| `--dry-run` | Preview without sending | `fabric --dry-run --pattern P < f` |
| `--show-metadata` | Print metadata to stderr | `fabric --show-metadata --pattern P` |
| `--debug N` | Debug level 0-3 | `fabric --debug 2 --pattern P` |
| `--notification` | Desktop notification on complete | `fabric --notification --pattern P` |
| `-g` / `--language` | Set response language | `fabric -g zh --pattern summarize` |
| `--shell-complete-list` | Raw list for shell completion | `fabric --shell-complete-list` |

---

*© 2026 Mind Over Metadata LLC — Peter Heller*  
*Fabric by Daniel Miessler — github.com/danielmiessler/fabric*
