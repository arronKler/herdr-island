#!/usr/bin/env python3
"""Build the two social share cards from the current site screenshots.

    Scripts/make-og-cards.py <site-directory>

Writes site/assets/og.png (Chinese) and site/assets/og-en.png (English) at
1200 x 630. The panel image is embedded at 2x so the card stays sharp.
"""

from __future__ import annotations

import base64
import subprocess
import sys
from pathlib import Path

WIDTH = 1200
HEIGHT = 630

CARDS = {
    "og.png": {
        "eyebrow": "HERDR 的 MACOS 图形前端",
        "title": ["屏幕凹口下，", "你的 agent 在值班。"],
        "lead": ["把每个 coding agent 的状态", "放进屏幕顶部的凹口两侧。", "拖动岛下那滴水，输入框就出现在落点上方。"],
        "meta": "macOS 14+ · Herdr 0.9.5+ · Apple Silicon & Intel",
        "shot": "running.webp",
        "shot_caption": "任务台 · 560 pt",
        "title_size": 62,
    },
    "og-en.png": {
        "eyebrow": "THE MACOS FRONT END FOR HERDR",
        "title": ["Your agents,", "under the notch."],
        "lead": ["Every coding agent's status on both", "sides of the notch. Drag the droplet to", "send a task, a window, or a file set."],
        "meta": "macOS 14+ · Herdr 0.9.5+ · Apple Silicon & Intel",
        "shot": "running.webp",
        "shot_caption": "Deck · 560 pt",
        "title_size": 66,
    },
}

FONT = "PingFang SC, Hiragino Sans GB, Noto Sans CJK SC, Helvetica Neue, sans-serif"
MONO = "SF Mono, Menlo, monospace"


def escape(text: str) -> str:
    return (
        text.replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")
        .replace('"', "&quot;")
    )


def card_svg(card: dict, shot_path: Path) -> str:
    from PIL import Image

    shot = Image.open(shot_path)
    shot_width = 520
    shot_height = round(shot_width * shot.height / shot.width)
    shot_x = WIDTH - shot_width - 64
    shot_y = 96
    encoded = base64.b64encode(shot_path.read_bytes()).decode("ascii")

    title_lines = "".join(
        f'<text x="72" y="{250 + index * 78}" font-family="{FONT}" font-size="{card["title_size"]}" '
        f'font-weight="700" letter-spacing="-2" fill="#F7FBFD">{escape(line)}</text>'
        for index, line in enumerate(card["title"])
    )
    lead_lines = "".join(
        f'<text x="72" y="{452 + index * 32}" font-family="{FONT}" font-size="20" '
        f'fill="#A3AEB5">{escape(line)}</text>'
        for index, line in enumerate(card["lead"])
    )

    return f'''<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="{WIDTH}" height="{HEIGHT}" viewBox="0 0 {WIDTH} {HEIGHT}">
<defs>
  <radialGradient id="glow" cx="50%" cy="0%" r="70%">
    <stop offset="0%" stop-color="#D7EFFC" stop-opacity="0.10"/>
    <stop offset="100%" stop-color="#D7EFFC" stop-opacity="0"/>
  </radialGradient>
  <radialGradient id="violet" cx="88%" cy="30%" r="60%">
    <stop offset="0%" stop-color="#4E3078" stop-opacity="0.30"/>
    <stop offset="100%" stop-color="#4E3078" stop-opacity="0"/>
  </radialGradient>
  <clipPath id="shot-clip">
    <rect x="{shot_x}" y="{shot_y}" width="{shot_width}" height="{shot_height}" rx="18"/>
  </clipPath>
</defs>
<rect width="{WIDTH}" height="{HEIGHT}" fill="#08090C"/>
<rect width="{WIDTH}" height="{HEIGHT}" fill="url(#glow)"/>
<rect width="{WIDTH}" height="{HEIGHT}" fill="url(#violet)"/>

<g transform="translate(72 64)">
  <rect width="44" height="44" rx="12" fill="#D7EFFC"/>
  <path d="M11 17h22a4 4 0 0 1 4 4v3a4 4 0 0 1-4 4H11a4 4 0 0 1-4-4v-3a4 4 0 0 1 4-4z" fill="#08090C"/>
  <circle cx="22" cy="22.5" r="3.4" fill="#D7EFFC"/>
  <text x="60" y="30" font-family="{FONT}" font-size="25" font-weight="650" fill="#F1F5F7">Herdr Island</text>
</g>

<circle cx="78" cy="152" r="4" fill="#D7EFFC"/>
<text x="94" y="159" font-family="{MONO}" font-size="14" letter-spacing="2.4" fill="#B7D9E8">{escape(card["eyebrow"])}</text>

{title_lines}
{lead_lines}

<rect x="72" y="556" width="46" height="3" rx="1.5" fill="#FFB224"/>
<text x="72" y="596" font-family="{MONO}" font-size="15" fill="#8B969D">{escape(card["meta"])}</text>

<rect x="{shot_x - 10}" y="{shot_y - 10}" width="{shot_width + 20}" height="{shot_height + 20}" rx="24" fill="#12151C" stroke="#D7EFFC" stroke-opacity="0.14"/>
<image x="{shot_x}" y="{shot_y}" width="{shot_width}" height="{shot_height}" clip-path="url(#shot-clip)" xlink:href="data:image/webp;base64,{encoded}"/>
<text x="{shot_x}" y="{shot_y + shot_height + 34}" font-family="{MONO}" font-size="13" fill="#8B969D">{escape(card["shot_caption"])}</text>
<text x="{shot_x + shot_width}" y="{shot_y + shot_height + 34}" text-anchor="end" font-family="{MONO}" font-size="13" fill="#FFB224">github.com/arronKler/herdr-island</text>
</svg>
'''


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: Scripts/make-og-cards.py <site-directory>", file=sys.stderr)
        return 2

    site_dir = Path(sys.argv[1]).resolve()
    assets = site_dir / "assets"

    for name, card in CARDS.items():
        shot_path = assets / "screens" / card["shot"]
        if not shot_path.exists():
            print(f"missing screenshot: {shot_path}", file=sys.stderr)
            return 1
        svg = assets / f"{name}.svg"
        svg.write_text(card_svg(card, shot_path), encoding="utf-8")
        output = assets / name
        subprocess.run(["rsvg-convert", "-o", str(output), str(svg)], check=True)
        svg.unlink()
        print(f"{output.relative_to(site_dir)} {WIDTH}x{HEIGHT}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
