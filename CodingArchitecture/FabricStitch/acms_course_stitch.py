#!/usr/bin/env python3
"""
acms_course_stitch.py
ACMS Course FabricStitch Pipeline
Mind Over Metadata LLC — Peter Heller

Processes a multi-part course — one article at a time or fully automated.
Each part runs through fabric_stitch.sh --web and lands in a course folder.

Usage:
    python3 acms_course_stitch.py --course ai-agents --mode auto --word-limit 2000
    python3 acms_course_stitch.py --course ai-agents --mode interactive
    python3 acms_course_stitch.py --course ai-agents --mode auto --start 3 --end 6
    python3 acms_course_stitch.py --course ai-agents --mode auto --part 5
    python3 acms_course_stitch.py --course ai-agents --part 10 --format obsidian
    python3 acms_course_stitch.py --course ai-agents --part 10 --render-only --format repo
    python3 acms_course_stitch.py --course ai-agents --part 10 --render-only --format both

Built-in courses:
    ai-agents   — AI Agents Crash Course (Daily Dose of Data Science, 17 parts)

Flags:
    --course NAME       Course name (required)
    --mode MODE         auto | interactive (default: interactive)
    --word-limit N      Words per article (default: 2000)
    --start N           Start at part N (default: 1)
    --end N             End at part N (default: last)
    --part N            Run only part N
    --dry-run           Show plan without running
    --output-dir DIR    Base output directory
    --format FORMAT     repo | obsidian | both (default: repo)
    --render-only       Re-render from existing step-04 — no LLM cost

Output formats:
    repo      Clean portable markdown, renders on GitHub
    obsidian  Frontmatter + internal links for NavigatorDiary/06-Guides/
    both      Write both formats from same synthesis (zero extra LLM cost)

Re-render (--render-only):
    Skips Steps 1-4, reads existing step-04-guide-draft.md,
    renders to requested format. Use to switch format without re-running.
"""

import argparse
import json
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path

# Guide renderer — zero LLM cost post-processing
sys.path.insert(0, str(Path(__file__).parent))
try:
    from guide_renderer import render_guide, render_only
    HAS_RENDERER = True
except ImportError:
    HAS_RENDERER = False

# ── Course Registry ───────────────────────────────────────────
COURSES = {
    "ai-agents": {
        "title": "AI Agents Crash Course",
        "author": "Avi Chawla",
        "publisher": "Daily Dose of Data Science",
        "url": "https://www.dailydoseofds.com/tag/ai-agents-crash-course/",
        "parts": [
            ("01", "Agentic Systems 101 — Fundamentals Building Blocks and How to Build Them Part A",
             "https://www.dailydoseofds.com/ai-agents-crash-course-part-1-with-implementation/"),
            ("02", "Agentic Systems 101 — Fundamentals Building Blocks and How to Build Them Part B",
             "https://www.dailydoseofds.com/ai-agents-crash-course-part-2-with-implementation/"),
            ("03", "Building Flows in Agentic Systems Part A",
             "https://www.dailydoseofds.com/ai-agents-crash-course-part-3-with-implementation/"),
            ("04", "Building Flows in Agentic Systems Part B",
             "https://www.dailydoseofds.com/ai-agents-crash-course-part-4-with-implementation/"),
            ("05", "Advanced Techniques to Build Robust Agentic Systems Part A",
             "https://www.dailydoseofds.com/ai-agents-crash-course-part-5-with-implementation/"),
            ("06", "Advanced Techniques to Build Robust Agentic Systems Part B",
             "https://www.dailydoseofds.com/ai-agents-crash-course-part-6-with-implementation/"),
            ("07", "A Practical Deep Dive Into Knowledge for Agentic Systems",
             "https://www.dailydoseofds.com/ai-agents-crash-course-part-7-with-implementation/"),
            ("08", "A Practical Deep Dive Into Memory for Agentic Systems Part A",
             "https://www.dailydoseofds.com/ai-agents-crash-course-part-8-with-implementation/"),
            ("09", "A Practical Deep Dive Into Memory for Agentic Systems Part B",
             "https://www.dailydoseofds.com/ai-agents-crash-course-part-9-with-implementation/"),
            ("10", "Implementing ReAct Agentic Pattern From Scratch",
             "https://www.dailydoseofds.com/ai-agents-crash-course-part-10-with-implementation/"),
            ("11", "Implementing Planning Agentic Pattern From Scratch",
             "https://www.dailydoseofds.com/ai-agents-crash-course-part-11-with-implementation/"),
            ("12", "Implementing Multi-agent Agentic Pattern From Scratch",
             "https://www.dailydoseofds.com/ai-agents-crash-course-part-12-with-implementation/"),
            ("13", "10 Practical Steps to Improve Agentic Systems Part A",
             "https://www.dailydoseofds.com/ai-agents-crash-course-part-13-with-implementation/"),
            ("14", "10 Practical Steps to Improve Agentic Systems Part B",
             "https://www.dailydoseofds.com/ai-agents-crash-course-part-14-with-implementation/"),
            ("15", "A Practical Deep Dive Into Memory Optimization for Agentic Systems Part A",
             "https://www.dailydoseofds.com/ai-agents-crash-course-part-15-with-implementation/"),
            ("16", "A Practical Deep Dive Into Memory Optimization for Agentic Systems Part B",
             "https://www.dailydoseofds.com/ai-agents-crash-course-part-16-with-implementation/"),
            ("17", "A Practical Deep Dive Into Memory Optimization for Agentic Systems Part C",
             "https://www.dailydoseofds.com/ai-agents-crash-course-part-17-with-implementation/"),
        ]
    }
}

# ── Config ────────────────────────────────────────────────────
FABRIC_STITCH = Path.home() / "projects/acms-skills/CodingArchitecture/FabricStitch/ACMS_extract_wisdom/fabric_stitch.sh"
OUTPUT_BASE   = Path.home() / "projects/acms-skills/FabricStitch/output"

# ── Helpers ───────────────────────────────────────────────────
def banner(text: str, width: int = 60):
    print("\n" + "=" * width)
    print(f"  {text}")
    print("=" * width)

def slug(text: str) -> str:
    import re
    s = re.sub(r'[^a-zA-Z0-9 ]', '', text)
    s = re.sub(r'  +', ' ', s).strip()
    return s.replace(' ', '-')

def run_part(part_num: str, title: str, url: str,
             word_limit: int, output_dir: Path,
             fmt: str = "repo",
             render_only_mode: bool = False,
             course_meta: dict = None,
             dry_run: bool = False) -> dict:
    """Run fabric_stitch.sh for one course part, then render guide."""

    part_slug  = f"Part-{part_num}-{slug(title)}"
    start_time = time.time()
    course_meta = course_meta or {}

    print(f"\n  Part {part_num}/17 — {title}")
    print(f"  URL   : {url}")
    print(f"  Slug  : {part_slug}")
    print(f"  Format: {fmt}")

    # ── Render-only mode — skip pipeline, re-render from saved draft ──
    if render_only_mode:
        if not HAS_RENDERER:
            print("  ✗ guide_renderer.py not found — cannot render")
            return {"part": part_num, "title": title, "url": url,
                    "status": "error: renderer missing", "duration_s": 0, "cost_usd": 0}

        # Find the existing part folder
        today = datetime.now()
        search = output_dir / today.strftime("%Y") / today.strftime("%m") / today.strftime("%d")
        matches = list(search.glob(f"*{part_slug[:30]}*")) if search.exists() else []
        if not matches:
            print(f"  ✗ No existing folder found for Part {part_num} — run pipeline first")
            return {"part": part_num, "title": title, "url": url,
                    "status": "error: no draft found", "duration_s": 0, "cost_usd": 0}

        part_folder = matches[0]
        meta = {
            "source_url":   url,
            "course_title": course_meta.get("title", ""),
            "part_num":     part_num,
            "tags":         course_meta.get("tags", ["guide", "agentic"]),
        }
        outputs = render_only(part_folder, format=fmt, metadata=meta)
        duration = round(time.time() - start_time, 1)
        return {
            "part": part_num, "title": title, "url": url,
            "status": "rendered", "duration_s": duration, "cost_usd": 0.0,
            "rendered_files": {k: str(v) for k, v in outputs.items()}
        }

    if dry_run:
        print("  [DRY RUN] Would run fabric_stitch.sh --web")
        return {
            "part": part_num,
            "title": title,
            "url": url,
            "status": "dry_run",
            "duration_s": 0,
            "cost_usd": 0,
        }

    # Guide format uses the practical guide pattern — article uses narrative
    synthesis_pattern = (
        "synthesize_practical_guide_from_wisdom"
        if fmt in ("repo", "obsidian", "both")
        else "synthesize_eloquent_narrative_from_wisdom"
    )

    cmd = [
        "bash", str(FABRIC_STITCH),
        "--web", url,
        "--word-limit", str(word_limit),
        "--output-dir", str(output_dir),
        "--synthesis-pattern", synthesis_pattern,
    ]

    try:
        result = subprocess.run(
            cmd,
            capture_output=False,   # stream output to terminal
            text=True,
            timeout=600             # 10 min max per part
        )
        status   = "completed" if result.returncode == 0 else "failed"
        duration = round(time.time() - start_time, 1)

        # Try to extract cost from output folder manifest
        cost = _extract_cost(output_dir, part_slug)

        # ── Render guide from saved draft ─────────────────────────
        if status == "completed" and HAS_RENDERER and fmt:
            try:
                today = datetime.now()
                search = output_dir / today.strftime("%Y") / today.strftime("%m") / today.strftime("%d")
                matches = list(search.glob(f"*{slug(title)[:30]}*")) if search.exists() else []
                if matches:
                    part_folder = matches[0]
                    draft = part_folder / "step-04-narrative.md"
                    meta = {
                        "source_url":   url,
                        "course_title": course_meta.get("title", ""),
                        "part_num":     part_num,
                        "tags":         course_meta.get("tags", ["guide", "agentic"]),
                    }
                    render_guide(
                        draft_path = draft,
                        output_dir = part_folder,
                        file_base  = part_folder.name,
                        format     = fmt,
                        metadata   = meta
                    )
            except Exception as e:
                print(f"  ⚠ Render step failed: {e}")

        return {
            "part": part_num,
            "title": title,
            "url": url,
            "status": status,
            "duration_s": duration,
            "cost_usd": cost,
            "output_folder": str(output_dir),
            "format": fmt,
        }
    except subprocess.TimeoutExpired:
        return {
            "part": part_num,
            "title": title,
            "url": url,
            "status": "timeout",
            "duration_s": 600,
            "cost_usd": 0,
        }
    except Exception as e:
        return {
            "part": part_num,
            "title": title,
            "url": url,
            "status": f"error: {e}",
            "duration_s": 0,
            "cost_usd": 0,
        }

def _extract_cost(output_dir: Path, part_slug: str) -> float:
    """Extract cost from the most recent manifest.json in output_dir."""
    try:
        today = datetime.now().strftime("%Y%m%d")
        year  = datetime.now().strftime("%Y")
        month = datetime.now().strftime("%m")
        day   = datetime.now().strftime("%d")
        search_dir = output_dir / year / month / day
        if search_dir.exists():
            for folder in sorted(search_dir.iterdir(), reverse=True):
                manifest = folder / "manifest.json"
                if manifest.exists():
                    data = json.loads(manifest.read_text())
                    return float(data.get("total_cost_usd", 0))
    except Exception:
        pass
    return 0.0

def write_course_manifest(course: dict, results: list,
                          output_dir: Path, word_limit: int):
    """Write a course-level manifest linking all parts."""

    today     = datetime.now().strftime("%Y-%m-%d")
    year      = datetime.now().strftime("%Y")
    month     = datetime.now().strftime("%m")
    day       = datetime.now().strftime("%d")
    course_dir = output_dir / year / month / day / slug(course["title"])
    course_dir.mkdir(parents=True, exist_ok=True)

    total_cost     = sum(r.get("cost_usd", 0) for r in results)
    completed      = [r for r in results if r["status"] == "completed"]
    failed         = [r for r in results if r["status"] not in ("completed", "dry_run")]
    total_duration = sum(r.get("duration_s", 0) for r in results)

    manifest = {
        "course_title": course["title"],
        "author": course["author"],
        "publisher": course["publisher"],
        "course_url": course["url"],
        "processed_date": today,
        "word_limit_per_part": word_limit,
        "total_parts": len(course["parts"]),
        "parts_processed": len(results),
        "parts_completed": len(completed),
        "parts_failed": len(failed),
        "total_cost_usd": round(total_cost, 6),
        "total_duration_seconds": round(total_duration, 1),
        "pipeline": "ACMS FabricStitch — Mind Over Metadata LLC",
        "pipeline_run_id_explanation": (
            "Architectural Decision Record (ADR) course-level manifest. "
            "Each part has its own manifest.json with individual run IDs. "
            "Search cost_audit.log for any part's run_id to trace its full cost breakdown."
        ),
        "parts": results,
    }

    manifest_path = course_dir / "course-manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2))
    print(f"\n  Course manifest written: {manifest_path}")
    return manifest_path

def print_summary(course: dict, results: list):
    """Print course completion summary table."""
    banner(f"COURSE COMPLETE — {course['title']}")
    total_cost = sum(r.get("cost_usd", 0) for r in results)
    print(f"\n  {'Part':<6} {'Status':<12} {'Duration':<10} {'Cost':<12} Title")
    print(f"  {'-'*70}")
    for r in results:
        status   = r.get("status", "unknown")
        duration = f"{r.get('duration_s', 0)}s"
        cost     = f"${r.get('cost_usd', 0):.4f}"
        title    = r.get("title", "")[:45]
        mark     = "✓" if status == "completed" else "✗"
        print(f"  {mark} {r['part']:<5} {status:<12} {duration:<10} {cost:<12} {title}")
    print(f"  {'-'*70}")
    print(f"  {'TOTAL':<18} {'':<10} ${total_cost:.4f}")

# ── Main ──────────────────────────────────────────────────────
def main():
    parser = argparse.ArgumentParser(
        description="ACMS Course FabricStitch Pipeline",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__
    )
    parser.add_argument("--course",      required=True, choices=list(COURSES.keys()),
                        help="Course name")
    parser.add_argument("--mode",        default="interactive",
                        choices=["auto", "interactive"],
                        help="auto = unattended loop, interactive = confirm each part")
    parser.add_argument("--word-limit",  type=int, default=2000,
                        help="Target word count per article (default: 2000)")
    parser.add_argument("--start",       type=int, default=1,
                        help="Start at part N (default: 1)")
    parser.add_argument("--end",         type=int, default=None,
                        help="End at part N (default: last)")
    parser.add_argument("--part",        type=int, default=None,
                        help="Run only part N")
    parser.add_argument("--dry-run",     action="store_true",
                        help="Show plan without running")
    parser.add_argument("--output-dir",  type=Path, default=OUTPUT_BASE,
                        help="Base output directory")
    parser.add_argument("--format",      default="repo",
                        choices=["repo", "obsidian", "both"],
                        help="Output format (default: repo)")
    parser.add_argument("--render-only", action="store_true",
                        help="Re-render from existing draft — no LLM cost")
    args = parser.parse_args()

    course = COURSES[args.course]
    parts  = course["parts"]

    # Filter parts
    if args.part:
        parts = [p for p in parts if int(p[0]) == args.part]
    else:
        start = args.start - 1
        end   = args.end if args.end else len(parts)
        parts = parts[start:end]

    if not parts:
        print("ERROR: No parts matched the specified range.")
        sys.exit(1)

    # Print plan
    banner(f"ACMS Course FabricStitch — {course['title']}")
    print(f"\n  Author      : {course['author']}")
    print(f"  Publisher   : {course['publisher']}")
    print(f"  Parts       : {len(parts)} of {len(course['parts'])} total")
    print(f"  Word limit  : {args.word_limit} per part")
    print(f"  Mode        : {args.mode}")
    print(f"  Format      : {args.format}")
    if args.render_only:
        print(f"  Render only : yes — skipping pipeline, re-rendering from saved draft")
    print(f"  Output      : {args.output_dir}")
    if args.dry_run:
        print(f"  DRY RUN     : no files will be written")
    print(f"\n  Parts to process:")
    for num, title, url in parts:
        print(f"    {num}. {title}")

    if not args.dry_run and args.mode == "interactive":
        print("\n  Press Enter to begin, Ctrl+C to cancel...")
        try:
            input()
        except KeyboardInterrupt:
            print("\n  Cancelled.")
            sys.exit(0)

    # Run pipeline
    results = []
    for i, (num, title, url) in enumerate(parts, 1):
        banner(f"Part {num} of {len(course['parts'])} — {i}/{len(parts)} in this run")

        if args.mode == "interactive" and i > 1:
            print(f"\n  Next: Part {num} — {title}")
            print(f"  Press Enter to continue, 's' to skip, 'q' to quit...")
            try:
                choice = input("  > ").strip().lower()
                if choice == 'q':
                    print("  Stopping — writing partial manifest.")
                    break
                elif choice == 's':
                    print(f"  Skipping Part {num}.")
                    results.append({
                        "part": num, "title": title, "url": url,
                        "status": "skipped", "duration_s": 0, "cost_usd": 0
                    })
                    continue
            except KeyboardInterrupt:
                print("\n  Interrupted — writing partial manifest.")
                break

        result = run_part(
            num, title, url, args.word_limit,
            args.output_dir,
            fmt              = args.format,
            render_only_mode = args.render_only,
            course_meta      = course,
            dry_run          = args.dry_run
        )
        results.append(result)

        # Show running cost
        running_cost = sum(r.get("cost_usd", 0) for r in results)
        print(f"\n  Running total: ${running_cost:.4f}  |  "
              f"{len([r for r in results if r['status']=='completed'])} completed")

    # Write course manifest and summary
    if not args.dry_run:
        write_course_manifest(course, results, args.output_dir, args.word_limit)

    print_summary(course, results)

if __name__ == "__main__":
    main()
