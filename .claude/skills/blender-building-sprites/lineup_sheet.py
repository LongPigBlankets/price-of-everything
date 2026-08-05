#!/usr/bin/env python3
"""Composite an exported level set into one showcase sheet.

The per-level PNGs from sprite_export.py are already on a SHARED SCALE (the --ref level
hits the padding margin, smaller levels are deliberately inset). So placing the canvases
edge to edge preserves relative size for free — do NOT re-crop them tight, that inset is
the whole size signal.

Only the vertical dead space is trimmed, using the UNION of the levels' alpha boxes, so
every level is cropped by the same amount and they stay on a common baseline.

    python3 lineup_sheet.py exports factory 1 2 3 --out renders/factory_sheet.png
"""
import argparse
import os
from PIL import Image


def build_sheet(folder, name, levels, out, gap=0, bg=None):
    ims = [Image.open(os.path.join(folder, "%s_lvl%d_800.png" % (name, lv))).convert("RGBA")
           for lv in levels]
    w, h = ims[0].size
    for im in ims:
        if im.size != (w, h):
            raise SystemExit("level canvases differ in size: %s vs %s" % (im.size, (w, h)))

    # Union of alpha boxes -> one vertical crop applied to ALL levels, so the trim cannot
    # shift any level relative to the others.
    tops, bots = [], []
    for im in ims:
        bb = im.split()[-1].getbbox()
        if bb:
            tops.append(bb[1])
            bots.append(bb[3])
    top, bot = min(tops), max(bots)

    tile_h = bot - top
    sheet_w = w * len(ims) + gap * (len(ims) - 1)
    sheet = Image.new("RGBA", (sheet_w, tile_h), bg or (0, 0, 0, 0))
    for i, im in enumerate(ims):
        sheet.paste(im.crop((0, top, w, bot)), (i * (w + gap), 0))

    os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
    sheet.save(out)
    return {"out": out, "size": sheet.size, "levels": levels,
            "crop_rows": [top, bot], "tile": (w, tile_h)}


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("folder")
    ap.add_argument("name")
    ap.add_argument("levels", nargs="+", type=int)
    ap.add_argument("--out", required=True)
    ap.add_argument("--gap", type=int, default=0)
    args = ap.parse_args()
    print(build_sheet(args.folder, args.name, args.levels, args.out, args.gap))
