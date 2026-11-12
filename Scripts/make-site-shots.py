#!/usr/bin/env python3
"""Crop the 2x fixture renders down to the island and encode the site images.

Run after `HerdrIsland --render <directory>`:

    Scripts/make-site-shots.py <render-directory> <site-directory>

The renderer writes each scene's panel frame into manifest.json, so the crop
is exact instead of guessed. Inputs are rasterized at 2x, which keeps text
sharp when the site shows a panel at its logical size on a Retina display.
"""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

# fixture -> page image. The composer shots use the fixtures that carry
# attachments, because the page copy promises them.
SHOTS = {
    "collapsed": "collapsed",
    "completed": "completed",
    "deckCrowded": "deck",
    "deckReplying": "running",
    "detail": "terminal",
    "mainAgentFiles": "drop",
    "mainAgentLock": "window",
}

# Breathing room around the panel, in logical points. The collapsed island is
# only 64 pt tall, so it gets more desktop below to read as hanging from the
# menu bar.
PAD_X = 28
PAD_BOTTOM = 28
PAD_BOTTOM_BY_SHOT = {"collapsed": 120}

# The status card shows only the top of the deck: header, filters, and a few
# full rows. Chips the crop at a row boundary so nothing is cut in half. The
# drop canvas and the window-lock panel are much taller than their content, so
# they trim to the composer instead of leaving a block of empty desktop.
HEIGHT_BY_SHOT = {"deckCrowded": 380, "mainAgentFiles": 280, "mainAgentLock": 280}


def main() -> int:
    if len(sys.argv) != 3:
        print(
            "usage: Scripts/make-site-shots.py <render-directory> <site-directory>",
            file=sys.stderr,
        )
        return 2

    render_dir = Path(sys.argv[1]).resolve()
    site_dir = Path(sys.argv[2]).resolve()
    target_dir = site_dir / "assets" / "screens"
    target_dir.mkdir(parents=True, exist_ok=True)

    from PIL import Image

    manifest = json.loads((render_dir / "manifest.json").read_text(encoding="utf-8"))
    scenes = {scene["name"]: scene for scene in manifest["scenes"]}

    for fixture, name in SHOTS.items():
        scene = scenes.get(fixture)
        if scene is None:
            print(f"missing scene in manifest: {fixture}", file=sys.stderr)
            return 1

        source = render_dir / scene["file"]
        image = Image.open(source).convert("RGB")
        scale = image.width / 1200
        panel = scene["panel"]
        pad_bottom = PAD_BOTTOM_BY_SHOT.get(fixture, PAD_BOTTOM)
        height = HEIGHT_BY_SHOT.get(fixture, panel["height"] + pad_bottom)

        box = (
            max(0, round((panel["x"] - PAD_X) * scale)),
            0,
            min(image.width, round((panel["x"] + panel["width"] + PAD_X) * scale)),
            min(image.height, round(height * scale)),
        )

        cropped = image.crop(box)
        png = source.with_suffix(".crop.png")
        cropped.save(png)
        output = target_dir / f"{name}.webp"
        subprocess.run(
            ["cwebp", "-quiet", "-q", "90", str(png), "-o", str(output)],
            check=True,
        )
        png.unlink()
        print(f"{output.relative_to(site_dir)} {cropped.width}x{cropped.height}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
