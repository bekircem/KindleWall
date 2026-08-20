#!/usr/bin/env python3
"""Builds one release's notes, in the two shapes the pipeline needs.

`markdown` goes into the GitHub release body; `html` goes into the appcast item's
`<description>`, which is what Sparkle shows a user before they agree to update. Before
this existed the body was a bare compare link and the description was absent entirely, so
the update prompt could not say what it was offering.

Source of truth, in order:
  1. `docs/release-notes/<version>.md` — hand-written, used verbatim when present.
  2. The feat/fix/perf commit subjects since the previous tag.

Housekeeping commits (docs, test, chore, refactor, style, ci, release) are not news and are
dropped. If that leaves nothing, the notes say so plainly rather than inventing a highlight.
"""
from __future__ import annotations

import os
import re
import subprocess
import sys

# Conventional-commit types worth telling a user about, in the order they should appear.
NEWSWORTHY = ("feat", "fix", "perf")
HEADING = {"feat": "New", "fix": "Fixed", "perf": "Faster"}

SUBJECT = re.compile(r"^(?P<type>[a-z]+)(?:\([^)]*\))?!?:\s*(?P<text>.+)$")


def commit_subjects(rev_range: str) -> list[str]:
    out = subprocess.run(
        ["git", "log", "--no-merges", "--pretty=%s", rev_range],
        capture_output=True, text=True, check=True,
    )
    return [line.strip() for line in out.stdout.splitlines() if line.strip()]


def group(subjects: list[str]) -> dict[str, list[str]]:
    grouped: dict[str, list[str]] = {kind: [] for kind in NEWSWORTHY}
    for subject in subjects:
        match = SUBJECT.match(subject)
        if not match or match["type"] not in grouped:
            continue
        text = match["text"]
        grouped[match["type"]].append(text[0].upper() + text[1:])
    return {kind: items for kind, items in grouped.items() if items}


def from_file(path: str) -> str | None:
    if not os.path.isfile(path):
        return None
    body = open(path, encoding="utf-8").read().strip()
    return body or None


def as_markdown(grouped: dict[str, list[str]]) -> str:
    blocks = []
    for kind, items in grouped.items():
        lines = "\n".join(f"- {item}" for item in items)
        blocks.append(f"### {HEADING[kind]}\n{lines}")
    return "\n\n".join(blocks)


def escape(text: str) -> str:
    return text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def as_html(grouped: dict[str, list[str]]) -> str:
    blocks = []
    for kind, items in grouped.items():
        entries = "".join(f"<li>{escape(item)}</li>" for item in items)
        blocks.append(f"<h3>{HEADING[kind]}</h3><ul>{entries}</ul>")
    return "".join(blocks)


def markdown_to_html(markdown: str) -> str:
    """Enough of a converter for hand-written notes: headings and bullets, nothing else."""
    html, in_list = [], False
    for line in markdown.splitlines():
        stripped = line.strip()
        if stripped.startswith("- "):
            if not in_list:
                html.append("<ul>")
                in_list = True
            html.append(f"<li>{escape(stripped[2:])}</li>")
            continue
        if in_list:
            html.append("</ul>")
            in_list = False
        if stripped.startswith("#"):
            level = min(len(stripped) - len(stripped.lstrip("#")), 6)
            html.append(f"<h{level}>{escape(stripped.lstrip('# '))}</h{level}>")
        elif stripped:
            html.append(f"<p>{escape(stripped)}</p>")
    if in_list:
        html.append("</ul>")
    return "".join(html)


def main() -> int:
    shape = sys.argv[1] if len(sys.argv) > 1 else "markdown"
    if shape not in ("markdown", "html"):
        print(f"usage: {sys.argv[0]} markdown|html", file=sys.stderr)
        return 2

    version = os.environ.get("KW_VERSION", "")
    handwritten = from_file(os.environ.get("KW_NOTES_FILE", ""))
    if handwritten is not None:
        print(handwritten if shape == "markdown" else markdown_to_html(handwritten))
        return 0

    grouped = group(commit_subjects(os.environ.get("KW_RANGE", "HEAD")))
    if not grouped:
        fallback = f"Maintenance release. Nothing user-visible changed in {version}."
        print(fallback if shape == "markdown" else f"<p>{escape(fallback)}</p>")
        return 0

    print(as_markdown(grouped) if shape == "markdown" else as_html(grouped))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
