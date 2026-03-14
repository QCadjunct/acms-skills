# vendor_rates — LLM Cost Rate Registry

Single source of truth for LLM cost rates across the ACMS pipeline.

## Files

| File | Purpose |
|------|---------|
| `vendor_rates/vendor_rates.yaml` | Rate definitions, pipeline defaults, thresholds |
| `vendor_rates/refresh_rates.sh` | On-demand rate validation and timestamp update |

## Quick Reference — Current Rates

| Vendor | Model | Input /token | Output /token |
|--------|-------|-------------|--------------|
| Anthropic | claude-sonnet-4-6 | $0.000003 | $0.000015 |
| Anthropic | claude-haiku-4-5 | $0.0000008 | $0.000004 |
| Google | gemini-2.0-flash | $0.000000375 | $0.0000015 |
| Ollama | qwen3:8b (local) | $0.000000 | $0.000000 |

*Last validated: 2026-03-14. Run `./vendor_rates/refresh_rates.sh --dry-run` to check.*

## Usage

```bash
# Validate current rates (no writes)
./vendor_rates/refresh_rates.sh --dry-run

# Update timestamp after confirming rates are current
./vendor_rates/refresh_rates.sh --force

# Interactive review (opens pricing pages)
./vendor_rates/refresh_rates.sh
```

## Reading Rates in Scripts — stdlib-only Pattern

```python
#!/usr/bin/env python3
# Read a rate from vendor_rates.yaml without PyYAML (stdlib only — ADR-008)

def read_rate(rates_file: str, vendor: str, model: str, direction: str) -> float:
    from pathlib import Path
    
    target = f"vendors.{vendor}.models.{model}.{direction}"
    rates = {}
    path = []
    
    for line in Path(rates_file).read_text().splitlines():
        s = line.rstrip()
        if not s or s.startswith('#'):
            continue
        depth = (len(line) - len(line.lstrip())) // 2
        if ':' in s:
            k, _, v = s.lstrip().partition(':')
            k = k.strip(); v = v.strip()
            path = path[:depth] + [k]
            if v:
                rates['.'.join(path)] = v
    
    try:
        return float(rates.get(target, "0.0"))
    except ValueError:
        return 0.0

# Examples
rate_in  = read_rate("vendor_rates/vendor_rates.yaml", "google", "gemini-2.0-flash", "input")
rate_out = read_rate("vendor_rates/vendor_rates.yaml", "google", "gemini-2.0-flash", "output")

tokens_in  = 420
tokens_out = 195
cost = (tokens_in * rate_in) + (tokens_out * rate_out)
print(f"Cost: ${cost:.6f}")   # → Cost: $0.000450
```

## Cost Audit Log Format

Every ACMS component writes to `~/.config/fabric/cost_audit.log`:

```
[2026-03-14T10:31:39] deploy_generators.sh | skill=ACMS_extract_wisdom | vendor=ollama | model=qwen3:8b | tokens_in=420 | tokens_out=195 | cost=$0.000000 | elapsed=1247ms
[2026-03-14T10:32:11] sync_skill.sh | skill=ACMS_extract_wisdom | env=dev | vendor=ollama | model=qwen3:8b | tokens_in=384 | tokens_out=180 | cost=$0.000000 | elapsed=847ms
[2026-03-14T10:33:05] post_tool_call.py | skill=ACMS_extract_wisdom | tool=fabric_pattern | tokens_in=512 | tokens_out=280 | cost=$0.000000 | exit_code=0
```

## Thresholds

```yaml
thresholds:
  warn:  0.05    # $0.05  → log warning
  alert: 0.25   # $0.25  → log alert + notify
  hard:  1.00   # $1.00  → abort run, requires --override flag
```
