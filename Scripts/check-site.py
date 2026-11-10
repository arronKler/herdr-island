#!/usr/bin/env python3
"""Fail when a local link or asset in the static site does not resolve."""

from __future__ import annotations

import sys
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import unquote, urlsplit


class LinkCollector(HTMLParser):
    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.links: list[str] = []
        self.ids: list[str] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        values = dict(attrs)
        element_id = values.get("id")
        if element_id:
            self.ids.append(element_id)
        for name in ("href", "src", "poster"):
            value = values.get(name)
            if value:
                self.links.append(value)
        srcset = values.get("srcset")
        if srcset:
            for candidate in srcset.split(","):
                url = candidate.strip().split(" ", 1)[0]
                if url:
                    self.links.append(url)


def local_target(page: Path, url: str) -> Path | None:
    split = urlsplit(url)
    if split.scheme or split.netloc or url.startswith("#") or url.startswith("data:"):
        return None
    path = unquote(split.path)
    if not path:
        return None
    if path.startswith("/"):
        return None
    from_root = (page.parent / path).resolve()
    return from_root


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: Scripts/check-site.py <site-directory>", file=sys.stderr)
        return 2

    root = Path(sys.argv[1]).resolve()
    pages = sorted(root.rglob("*.html"))
    if not pages:
        print(f"no HTML files under {root}", file=sys.stderr)
        return 1

    missing: list[str] = []
    checked = 0
    for page in pages:
        collector = LinkCollector()
        collector.feed(page.read_text(encoding="utf-8"))
        ids = set(collector.ids)
        for url in collector.links:
            if url.startswith("#"):
                anchor = unquote(url[1:])
                if anchor and anchor not in ids:
                    missing.append(
                        f"{page.relative_to(root)} -> missing anchor #{anchor}"
                    )
                continue
            target = local_target(page, url)
            if target is None:
                continue
            checked += 1
            if not target.exists():
                missing.append(f"{page.relative_to(root)} -> missing file {url}")

    for entry in missing:
        print(entry, file=sys.stderr)

    print(f"checked {checked} local references in {len(pages)} page(s)")
    return 1 if missing else 0


if __name__ == "__main__":
    raise SystemExit(main())
