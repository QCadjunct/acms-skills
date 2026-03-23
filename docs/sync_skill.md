# sync_skill.sh — Skill Synchronization Pipeline

Detects `system.md` changes via MD5 hash, versions prior artifacts,
regenerates `system.yaml` and `system.toon`, deploys to target environment,
logs cost. Nine steps, always in order.

## Pipeline

```
VALIDATE → HASH → DIFF → ARCHIVE → GENERATE → VALIDATE → DEPLOY → HASH-STORE → COST
```

## Usage

```bash
# Standard dev sync
./sync_skill.sh \
  --source CodingArchitecture/FabricStitch/ACMS_extract_wisdom/system.md \
  --generate all \
  --env dev

# Dry run — no writes
./sync_skill.sh --source path/to/system.md --dry-run

# Force regeneration (skip hash check)
./sync_skill.sh --source path/to/system.md --force

# Generate yaml only
./sync_skill.sh --source path/to/system.md --generate yaml

# Promote to QA
./sync_skill.sh --source path/to/system.md --env qa

# Promote to PROD
./sync_skill.sh --source path/to/system.md --env prod
```

## Parameters

| Parameter | Values | Default |
|-----------|--------|---------|
| `--source` | path to system.md | required |
| `--env` | `dev` · `qa` · `prod` | `dev` |
| `--generate` | `yaml` · `toon` · `all` | `all` |
| `--rates` | path to vendor_rates.yaml | auto-detect |
| `--dry-run` | flag | false |
| `--force` | flag | false |

## Environment Deploy Targets (ADR-003 Flat Deploy Pattern)

```
dev  → ~/.config/fabric/patterns_custom/{skill_name}/
qa   → ~/.config/fabric/patterns_qa/{skill_name}/
prod → ~/.config/fabric/patterns/{skill_name}/
```

## Example Session Output

```
╔══════════════════════════════════════════════════════════╗
║           ACMS sync_skill.sh — Skill Sync Pipeline      ║
║           Mind Over Metadata LLC © 2026                 ║
╚══════════════════════════════════════════════════════════╝
Skill:    ACMS_extract_wisdom
Domain:   CodingArchitecture
Source:   /home/pheller/projects/aces-skills/CodingArchitecture/FabricStitch/ACMS_extract_wisdom/system.md
Env:      dev → /home/pheller/.config/fabric/patterns_custom
Generate: all

Step 1/9 — VALIDATE
  ✓ system.md valid — required sections present
  ⏱  12ms

Step 2/9 — HASH
  Current MD5: a3f8c9d1e2b4a5f6c7d8e9f0a1b2c3d4
  Stored MD5:  none (first sync)
  ⏱  3ms

Step 3/9 — DIFF
  ⚡ Change detected — system.md has been modified
  ⏱  1ms

Step 4/9 — ARCHIVE
  ℹ  No prior system.yaml to archive
  ℹ  No prior system.toon to archive
  ⏱  4ms

Step 5/9 — GENERATE
  Generating system.yaml via fabric pattern: from_system.md_to_system.yaml
  ✓ system.yaml generated
  Generating system.toon via fabric pattern: from_system.md_to_system.toon
  ✓ system.toon generated
  ⏱  3842ms

Step 6/9 — VALIDATE ARTIFACTS
  ✓ system.yaml — valid YAML
  ✓ system.toon — 13 lines
  ⏱  28ms

Step 7/9 — DEPLOY (dev)
  ✓ Deployed: system.md → /home/pheller/.config/fabric/patterns_custom/ACMS_extract_wisdom/
  ✓ Deployed: system.yaml → /home/pheller/.config/fabric/patterns_custom/ACMS_extract_wisdom/
  ✓ Deployed: system.toon → /home/pheller/.config/fabric/patterns_custom/ACMS_extract_wisdom/
  ⏱  8ms

Step 8/9 — HASH-STORE
  ✓ Hash stored: a3f8c9d1e2b4a5f6c7d8e9f0a1b2c3d4
  ⏱  2ms

Step 9/9 — COST
  yaml transformer: $0.000000 (in:280 out:195 tokens @ ollama/qwen3:8b)
  toon transformer: $0.000000 (in:280 out:52 tokens @ ollama/qwen3:8b)
  Total cost: $0.000000
  ✓ Cost written to audit log
  ⏱  18ms

╔══════════════════════════════════════════════════════════╗
║  sync_skill.sh — COMPLETE                               ║
║  Skill:    ACMS_extract_wisdom                          ║
║  Steps:    9/9 completed                                ║
║  Env:      dev                                          ║
║  Cost:     $0.000000                                    ║
║  Elapsed:  3918ms                                       ║
╚══════════════════════════════════════════════════════════╝
```

## Hash File

`.sync_hash` is created in the skill folder after the first sync:

```
a3f8c9d1e2b4a5f6c7d8e9f0a1b2c3d4
```

Commit this file to git. It prevents collaborators from triggering
unnecessary regeneration on first pull.

## Archive Structure

```
CodingArchitecture/FabricStitch/ACMS_extract_wisdom/
├── system.md
├── system.yaml
├── system.toon
├── .sync_hash
└── _archive/
    ├── system_20260314T103139.yaml   ← prior version, timestamped
    └── system_20260314T103139.toon
```
