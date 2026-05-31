#!/usr/bin/env python3
"""Regenerate the circular bottom-menu UI icons at 100/200/400 px.

Source art (1254px squares on black) lives in assets/icons/ui_icons/source/.
For each icon we detect the metal rim, keep everything INSIDE the rim fully
opaque (so detail stays crisp), and ramp alpha to 0 over a gentle band just
OUTSIDE the rim so the icon feathers into the UI background instead of showing
a hard black cut. Outputs go to assets/icons/ui_icons/{100,200,400}/<key>.png.

Pure Pillow (no numpy). Run from anywhere:
    python scripts/regenerate_ui_icons.py
"""
import os
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
SRC_DIR = os.path.join(ROOT, "assets", "icons", "ui_icons", "source")
OUT_DIR = os.path.join(ROOT, "assets", "icons", "ui_icons")

KEYS = ["resources", "buildings", "map_overlays", "markets", "politics", "construct", "tech"]
SIZES = [400, 200, 100]
LUM_T = 40            # brightness threshold for rim detection (0..255)
R_PAD = 0            # grow(+)/shrink(-) detected radius, in source px
FEATHER_AT_SRC = 12  # feather band width in source px (gentle soft rim edge)
CROP_MARGIN = 2      # transparent px beyond the feather; the feathered rim then reaches
                     # the icon edge so the icon fills the round button (like construct)


def detect_circle(im):
    g = im.convert("L")
    px = g.load()
    W, H = g.size
    minx, miny, maxx, maxy = W, H, 0, 0
    for y in range(0, H, 2):
        for x in range(0, W, 2):
            if px[x, y] > LUM_T:
                if x < minx: minx = x
                if x > maxx: maxx = x
                if y < miny: miny = y
                if y > maxy: maxy = y
    return (minx + maxx) / 2.0, (miny + maxy) / 2.0, ((maxx - minx) + (maxy - miny)) / 4.0 + R_PAD


def build_mask(W, H, cx, cy, R, feather):
    """255 inside R, linear ramp 255->0 across R..R+feather, 0 beyond."""
    mask = Image.new("L", (W, H), 0)
    d = ImageDraw.Draw(mask)
    for k in range(int(feather), -1, -1):          # large->small so inner radii overwrite
        rad = R + k
        a = 255 if k == 0 else int(round(255 * (1 - k / float(feather))))
        d.ellipse([cx - rad, cy - rad, cx + rad, cy + rad], fill=a)
    return mask


def main():
    for s in SIZES:
        os.makedirs(os.path.join(OUT_DIR, str(s)), exist_ok=True)
    for key in KEYS:
        src = os.path.join(SRC_DIR, key + ".png")
        if not os.path.exists(src):
            print("SKIP (no source):", key)
            continue
        im = Image.open(src).convert("RGBA")
        W, H = im.size
        cx, cy, R = detect_circle(im)
        print("%-13s %dx%d  center=(%d,%d)  R=%d" % (key, W, H, cx, cy, R))
        im.putalpha(build_mask(W, H, cx, cy, R, FEATHER_AT_SRC))
        half = R + FEATHER_AT_SRC + CROP_MARGIN   # feathered rim reaches the icon edge
        im = im.crop((int(round(cx - half)), int(round(cy - half)),
                      int(round(cx + half)), int(round(cy + half))))
        for s in SIZES:
            im.resize((s, s), Image.LANCZOS).save(os.path.join(OUT_DIR, str(s), key + ".png"))
    print("done")


if __name__ == "__main__":
    main()
