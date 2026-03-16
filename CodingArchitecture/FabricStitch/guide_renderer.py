"""
guide_renderer.py
ACMS Guide Renderer — Mind Over Metadata LLC
Peter Heller

Renders a saved step-04-guide-draft.md to Obsidian or Repo Markdown.
No LLM call — pure post-processing. Zero cost.

Usage:
    from guide_renderer import render_guide
    render_guide(draft_path, output_dir, file_base, format="repo", metadata={})
"""

import re
from pathlib import Path
from datetime import datetime


def _slug(text: str) -> str:
    s = re.sub(r'[^a-zA-Z0-9 ]', '', text)
    s = re.sub(r'  +', ' ', s).strip()
    return s.replace(' ', '-')


def _extract_title(content: str) -> str:
    """Extract H1 title from markdown."""
    for line in content.splitlines():
        if line.startswith('# '):
            return line[2:].strip()
    return "Guide"


def render_repo(content: str, metadata: dict) -> str:
    """
    Repo Markdown — clean, portable, renders on GitHub.
    No Obsidian syntax. Source URL as blockquote header.
    """
    title      = _extract_title(content)
    source_url = metadata.get("source_url", "")
    part_num   = metadata.get("part_num", "")
    course     = metadata.get("course_title", "")
    date       = metadata.get("date", datetime.now().strftime("%Y-%m-%d"))
    run_id     = metadata.get("run_id", "")

    header = []
    if source_url:
        header.append(f"> **Source**: {source_url}")
    if part_num and course:
        header.append(f"> Part {part_num} — {course}")
    header.append(f"> Synthesized: {date} — ACMS FabricStitch Pipeline — Mind Over Metadata LLC")
    if run_id:
        header.append(f"> Pipeline Run ID (ADR): `{run_id}`")

    header_block = "\n".join(header)
    separator    = "\n\n---\n\n"

    return header_block + separator + content


def render_obsidian(content: str, metadata: dict) -> str:
    """
    Obsidian Markdown — internal links, tags, frontmatter, backlinks.
    Designed for NavigatorDiary/06-Guides/ vault structure.
    """
    title      = _extract_title(content)
    source_url = metadata.get("source_url", "")
    part_num   = metadata.get("part_num", "")
    course     = metadata.get("course_title", "")
    course_slug = _slug(course) if course else ""
    date       = metadata.get("date", datetime.now().strftime("%Y-%m-%d"))
    run_id     = metadata.get("run_id", "")
    tags       = metadata.get("tags", [])

    # Build frontmatter
    tag_list = "\n".join(f"  - {t}" for t in tags) if tags else "  - guide"
    frontmatter = f"""---
title: "{title}"
date: {date}
course: "{course}"
part: {part_num if part_num else '""'}
source: "{source_url}"
pipeline_run_id: "{run_id}"
tags:
{tag_list}
---"""

    # Build Obsidian header with internal links
    obsidian_header = []
    if part_num and course:
        obsidian_header.append(
            f"**Course**: [[{course_slug}]] | Part {part_num}"
        )
    if source_url:
        obsidian_header.append(f"**Source**: {source_url}")
    obsidian_header.append(
        f"**Synthesized**: {date} — "
        f"[[ACMS-FabricStitch-Pipeline|ACMS FabricStitch]]"
    )
    if run_id:
        obsidian_header.append(
            f"**ADR Run ID**: `{run_id}` — "
            f"search in [[cost-audit-log|cost_audit.log]]"
        )

    header_block = "\n".join(f"> {line}" for line in obsidian_header)
    separator    = "\n\n---\n\n"

    return frontmatter + "\n\n" + header_block + separator + content


def render_guide(
    draft_path: Path,
    output_dir: Path,
    file_base: str,
    format: str = "repo",
    metadata: dict = None
) -> dict:
    """
    Render step-04-guide-draft.md to the requested format(s).
    Returns dict of {format: output_path}.

    Args:
        draft_path:  Path to step-04-guide-draft.md
        output_dir:  Folder where rendered files are written
        file_base:   Base filename (without extension or format suffix)
        format:      "repo" | "obsidian" | "both"
        metadata:    Dict with source_url, part_num, course_title, date, run_id, tags
    """
    if not draft_path.exists():
        raise FileNotFoundError(f"Draft not found: {draft_path}")

    metadata  = metadata or {}
    content   = draft_path.read_text()
    outputs   = {}
    formats   = ["repo", "obsidian"] if format == "both" else [format]

    for fmt in formats:
        if fmt == "repo":
            rendered = render_repo(content, metadata)
            suffix   = ".md"
        elif fmt == "obsidian":
            rendered = render_obsidian(content, metadata)
            suffix   = "-obsidian.md"
        else:
            raise ValueError(f"Unknown format: {fmt}. Use 'repo', 'obsidian', or 'both'.")

        out_path = output_dir / f"{file_base}{suffix}"
        out_path.write_text(rendered)
        outputs[fmt] = out_path
        print(f"  ✓ Rendered [{fmt}]: {out_path.name}")

    return outputs


def render_only(
    part_folder: Path,
    format: str = "repo",
    metadata: dict = None
) -> dict:
    """
    Re-render from an existing part folder without re-running the pipeline.
    Reads step-04-guide-draft.md, renders to requested format. Zero LLM cost.

    Args:
        part_folder: Path to existing Part-NN-Title/ folder
        format:      "repo" | "obsidian" | "both"
        metadata:    Optional metadata overrides
    """
    draft_path = part_folder / "step-04-guide-draft.md"
    if not draft_path.exists():
        # Fall back to step-04-narrative.md for backward compat
        draft_path = part_folder / "step-04-narrative.md"
    if not draft_path.exists():
        raise FileNotFoundError(
            f"No draft found in {part_folder}. "
            f"Run the pipeline first to generate step-04-guide-draft.md"
        )

    # Try to load metadata from existing manifest.json
    manifest_path = part_folder / "manifest.json"
    loaded_meta   = {}
    if manifest_path.exists():
        import json
        data = json.loads(manifest_path.read_text())
        loaded_meta = {
            "source_url": data.get("source_url", ""),
            "run_id":     data.get("pipeline_run_id", ""),
            "date":       data.get("created_date", ""),
        }

    merged_meta = {**loaded_meta, **(metadata or {})}

    # Derive file_base from folder name
    file_base = part_folder.name

    return render_guide(
        draft_path  = draft_path,
        output_dir  = part_folder,
        file_base   = file_base,
        format      = format,
        metadata    = merged_meta
    )


# ── CLI ───────────────────────────────────────────────────────
if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(
        description="ACMS Guide Renderer — render saved guide draft to Obsidian or Repo Markdown"
    )
    parser.add_argument("folder",
                        help="Path to Part-NN-Title/ folder containing step-04-guide-draft.md")
    parser.add_argument("--format", default="repo",
                        choices=["repo", "obsidian", "both"],
                        help="Output format (default: repo)")
    parser.add_argument("--source-url",    default="", help="Override source URL")
    parser.add_argument("--course",        default="", help="Course title")
    parser.add_argument("--part",          default="", help="Part number")
    parser.add_argument("--tags",          default="", help="Comma-separated tags")

    args    = parser.parse_args()
    folder  = Path(args.folder)

    metadata = {
        "source_url":    args.source_url,
        "course_title":  args.course,
        "part_num":      args.part,
        "tags":          [t.strip() for t in args.tags.split(",")] if args.tags else [],
    }

    print(f"\n  ACMS Guide Renderer")
    print(f"  Folder : {folder}")
    print(f"  Format : {args.format}")
    print()

    outputs = render_only(folder, format=args.format, metadata=metadata)

    print(f"\n  Done — {len(outputs)} file(s) written")
    for fmt, path in outputs.items():
        print(f"    [{fmt}] {path}")
