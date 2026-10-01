#!/usr/bin/env python3
"""Write each blockout label beside its shape, for reviewing a layout render.

    python3 tools/steam_capsule/label_render.py renders/plate.png renders/plate_print.png out.png

Reads the labels from the render's .probe.json (first argument), draws them over the
image to annotate (second argument) on a navy ground, and saves the result. Repeated
labels (turbines, battery rows) are written once.
"""
import json
import os
import sys

from PIL import Image, ImageDraw, ImageFont

FONT = "/System/Library/Fonts/Supplemental/Arial Bold.ttf"


def main(render, image, out):
    probe = json.load(open(os.path.splitext(render)[0] + ".probe.json"))
    im = Image.open(image).convert("RGBA")
    bg = Image.new("RGBA", im.size, (20, 28, 38, 255))
    bg.alpha_composite(im)
    d = ImageDraw.Draw(bg)
    size = max(14, im.width // 90)
    f = ImageFont.truetype(FONT, size)
    seen, placed = set(), []
    for item in probe.get("labels", []):
        base = item["label"].rstrip(" 0123456789")
        if base in seen:
            continue
        seen.add(base)
        x, y = item["px"]
        tx, ty = x + size * 0.8, y - size * 2.2
        while any(abs(ty - py) < size * 1.3 and abs(tx - px) < size * 9 for px, py in placed):
            ty -= size * 1.4
        placed.append((tx, ty))
        d.line([(x, y), (tx, ty + size * 0.6)], fill=(255, 225, 90, 255), width=2)
        d.ellipse([x - 3, y - 3, x + 3, y + 3], fill=(255, 225, 90, 255))
        tw = d.textlength(base, font=f)
        d.rectangle([tx - 4, ty - 2, tx + tw + 4, ty + size + 4], fill=(10, 16, 24, 210))
        d.text((tx, ty), base, fill=(255, 240, 200, 255), font=f)
    bg.convert("RGB").save(out)


if __name__ == "__main__":
    main(*sys.argv[1:4])
