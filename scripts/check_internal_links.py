#!/usr/bin/env python3
"""Check local href/src targets in Xylo's static HTML pages.

Run from repository root: python scripts/check_internal_links.py
External URLs, mailto/tel links, data URLs, JS URLs, and pure page fragments are
excluded from filesystem checks. Directory routes resolve to index.html.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path
from urllib.parse import unquote, urlsplit

ROOT = Path(__file__).resolve().parents[1]
ATTR_RE = re.compile(r'''\b(?:href|src)\s*=\s*(["'])(.*?)\1''', re.IGNORECASE)
ID_RE = re.compile(r'''\bid\s*=\s*(["'])(.*?)\1''', re.IGNORECASE)
HTML_FILES = sorted(p for p in ROOT.rglob("*.html") if ".git" not in p.parts and "node_modules" not in p.parts)
ERRORS: list[str] = []


def route_target(value: str, source: Path) -> Path | None:
    value = value.strip()
    if not value or value.startswith("#") or value.startswith("//"):
        return None
    parsed = urlsplit(value)
    if parsed.scheme.lower() in {"http", "https", "mailto", "tel", "data", "javascript"}:
        return None
    raw_path = unquote(parsed.path)
    if not raw_path:
        return source
    if raw_path.startswith("/"):
        candidate = ROOT / raw_path.lstrip("/")
    else:
        candidate = source.parent / raw_path
    candidate = candidate.resolve()
    try:
        candidate.relative_to(ROOT.resolve())
    except ValueError:
        return None
    if candidate.is_dir():
        candidate = candidate / "index.html"
    elif not candidate.exists() and not candidate.suffix:
        route_index = candidate / "index.html"
        if route_index.exists():
            candidate = route_index
    return candidate


def main() -> int:
    for source in HTML_FILES:
        text = source.read_text(encoding="utf-8", errors="replace")
        ids = {m.group(2) for m in ID_RE.finditer(text)}
        for match in ATTR_RE.finditer(text):
            value = match.group(2).strip()
            target = route_target(value, source)
            if target is None:
                continue
            if not target.exists() or not target.is_file():
                ERRORS.append(f"{source.relative_to(ROOT)}: missing target {value!r}")
                continue
            fragment = urlsplit(value).fragment
            if fragment and target.suffix.lower() == ".html":
                target_text = target.read_text(encoding="utf-8", errors="replace")
                target_ids = {m.group(2) for m in ID_RE.finditer(target_text)}
                if unquote(fragment) not in target_ids:
                    ERRORS.append(f"{source.relative_to(ROOT)}: missing fragment #{fragment} in {target.relative_to(ROOT)}")
    if ERRORS:
        print("\n".join(ERRORS))
        print(f"\nFAIL: {len(ERRORS)} broken local link(s) across {len(HTML_FILES)} HTML page(s).")
        return 1
    print(f"PASS: local href/src targets exist across {len(HTML_FILES)} HTML page(s).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
