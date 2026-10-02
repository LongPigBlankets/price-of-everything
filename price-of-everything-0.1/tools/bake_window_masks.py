#!/usr/bin/env python3
"""Bake a mask of each building sprite's windows and other lit openings.

    python3 tools/bake_window_masks.py            (from the project directory)

The supply chain board lights a building's windows amber where the air is dirty. The sprites
have no such layer, so this finds the glass in each finished sprite: the sprite rig's glass
is the only large surface that is both dark and blue-dominant (the same test the print pass
uses to keep its dots off windows). Linework is that colour too, so anything thinner than a
window pane is removed by a morphological opening. Chimney mouths are dark and round and
would pass as well; they are not lights, so everything round a chimney anchor listed in
scripts/empire_fx.gd is cut out.

Writes assets/fx/windows/<sprite name>.png: white, with the mask as alpha, the same size and
layout as the sprite, so the game draws it straight over the sprite in whatever colour it likes.
"""
import os
import re

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

SPRITES = "assets/icons/buildings/sprites"
OUT = "assets/fx/windows"
OPENING = 9          # px: removes linework, which is at most 7 px wide
LUMA_MAX = 0.30
BLUE_OVER_RED = 1.45


def chimneys():
    """internal name -> level -> [(x, y, r)], read out of empire_fx.gd's anchor table."""
    out, name = {}, None
    for line in open("scripts/empire_fx.gd"):
        m = re.match(r'^\t"(\w+)": \{', line)
        if m:
            name = m.group(1)
            out[name] = {}
            continue
        m = re.match(r'^\t\t(\d): \{"stacks": \[(.*?)\]', line)
        if m and name:
            out[name][int(m.group(1))] = [(int(x), int(y), int(r)) for x, y, r in
                                          re.findall(r'"x": (\d+), "y": (\d+), "r": (\d+)', m.group(2))]
    return out


def main():
    stacks = chimneys()
    os.makedirs(OUT, exist_ok=True)
    done = 0
    for f in sorted(os.listdir(SPRITES)):
        m = re.match(r"(\w+)_lvl(\d)\.png$", f)
        if not m:
            continue
        name, level = m.group(1), int(m.group(2))
        im = Image.open(os.path.join(SPRITES, f)).convert("RGBA")
        a = np.asarray(im).astype(float) / 255.0
        r, g, b, alpha = a[..., 0], a[..., 1], a[..., 2], a[..., 3]
        luma = 0.2126 * r + 0.7152 * g + 0.0722 * b
        glass = (alpha > 0.8) & (b > BLUE_OVER_RED * r) & (luma < LUMA_MAX)
        mask = Image.fromarray((glass * 255).astype(np.uint8))
        mask = mask.filter(ImageFilter.MinFilter(OPENING)).filter(ImageFilter.MaxFilter(OPENING))
        # A level with no chimney entry of its own uses the nearest lower level's.
        levels = stacks.get(name, {})
        use = max([lv for lv in levels if lv <= level], default=None)
        draw = ImageDraw.Draw(mask)
        for x, y, rad in (levels.get(use, []) if use else []):
            k = im.size[0] / 800.0
            draw.ellipse([(x - rad * 1.7) * k, (y - rad * 1.3) * k, (x + rad * 1.7) * k, (y + rad * 1.3) * k], fill=0)
        mask = mask.filter(ImageFilter.GaussianBlur(0.7))
        out = Image.new("RGBA", im.size, (255, 255, 255, 0))
        out.putalpha(mask)
        out.save(os.path.join(OUT, f))
        done += 1
    print("baked %d window masks -> %s" % (done, OUT))


if __name__ == "__main__":
    main()
