#!/usr/bin/env python3
"""Copy pages/ into _site/ and generate _site/index.html listing every HTML file."""
import html
import json
import re
import shutil
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "pages"
OUT = ROOT / "_site"
TEMPLATE = ROOT / "scripts" / "index_template.html"

TITLE_RE = re.compile(r"<title[^>]*>(.*?)</title>", re.I | re.S)
DESC_RE = re.compile(
    r'<meta\s+[^>]*name=["\']description["\'][^>]*content=["\'](.*?)["\']', re.I | re.S
)


def git_date(path: Path) -> str:
    """Last commit date of the file, falling back to its modification time."""
    try:
        out = subprocess.run(
            ["git", "log", "-1", "--format=%cI", "--", str(path)],
            cwd=ROOT, capture_output=True, text=True, check=True,
        ).stdout.strip()
        if out:
            return out
    except (subprocess.CalledProcessError, FileNotFoundError):
        pass
    return datetime.fromtimestamp(path.stat().st_mtime, timezone.utc).isoformat()


def describe(path: Path) -> dict:
    text = path.read_text(encoding="utf-8", errors="replace")[:20000]
    title = TITLE_RE.search(text)
    desc = DESC_RE.search(text)
    rel = path.relative_to(SRC).as_posix()
    category = rel.split("/")[0] if "/" in rel else "misc"
    return {
        "path": rel,
        "title": html.unescape(" ".join(title.group(1).split())) if title else path.stem,
        "description": html.unescape(" ".join(desc.group(1).split())) if desc else "",
        "category": category,
        "date": git_date(path),
    }


def main() -> None:
    if OUT.exists():
        shutil.rmtree(OUT)
    shutil.copytree(SRC, OUT, ignore=shutil.ignore_patterns(".gitkeep", ".DS_Store"))

    items = [
        describe(p) for p in SRC.rglob("*.html")
        if p.relative_to(SRC).as_posix() != "index.html"
    ]
    items.sort(key=lambda i: i["date"], reverse=True)

    data = json.dumps(items, ensure_ascii=False).replace("</", "<\\/")
    page = TEMPLATE.read_text(encoding="utf-8").replace("/*__ITEMS__*/[]", data)
    (OUT / "index.html").write_text(page, encoding="utf-8")
    print(f"Built {OUT / 'index.html'} with {len(items)} page(s)", file=sys.stderr)


if __name__ == "__main__":
    main()
