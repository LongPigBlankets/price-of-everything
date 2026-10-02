#!/usr/bin/env python3
"""Bake the supply chain board's pipe or road pieces: render, outline, pack into one atlas,
install.

    python3 bake_pipes.py --game <price-of-everything-0.1 dir> [--kind pipes|roads] [--raw DIR] [--no-render]

pipe_pieces.py (or road_pieces.py) renders one frame per piece. Each gets the sprite set's
heavy outer line (sprite_export.outer_contour), then all are packed into
<game>/assets/iso/<kind>/<kind>.png, a grid of FRAME-sized cells, with <kind>.json beside it:

    {"frame": px, "px_per_unit": px per map unit, "cols": n, "dims": {...map units...},
     "cells": {piece name: [column, row]}}

A piece's anchor is its cell's centre. The print pass is left out on purpose: its dot pitch
is as wide as a pipe, so on these it is noise.

The renderer is called by the name in BLENDER_EXE (default `blender`, which the agent shim
runs in the background).
"""
import argparse
import json
import os
import subprocess
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from sprite_export import outer_contour   # noqa: E402

RENDERER = os.environ.get("BLENDER_EXE", "blender")
COLS = 16
BORDER = 12
# The heavy outer line's width in pixels. The building sprites carry 4; these pieces are drawn
# far smaller than a building, so they take a thinner one.
OUTLINE = 2


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--game", required=True)
    ap.add_argument("--kind", default="pipes", choices=["pipes", "roads", "cars"])
    ap.add_argument("--raw", default="")
    ap.add_argument("--no-render", action="store_true")
    args = ap.parse_args()
    kind = args.kind
    raw = os.path.abspath(args.raw or "/tmp/bake_%s_raw" % kind)
    if not args.no_render:
        r = subprocess.run([RENDERER, "--background", "--factory-startup", "--python",
                            os.path.join(HERE, "%s_pieces.py" % kind[:-1]), "--", raw],
                           capture_output=True, text=True)
        if "ALL_OK" not in r.stdout:
            print((r.stdout + r.stderr)[-3000:])
            return 1
    meta = json.load(open(os.path.join(raw, "pieces.json")))
    frame = int(meta["frame"])
    names = sorted(f[:-4] for f in os.listdir(raw) if f.endswith(".png"))
    rows = (len(names) + COLS - 1) // COLS
    atlas = Image.new("RGBA", (COLS * frame, rows * frame), (0, 0, 0, 0))
    cells = {}
    for i, name in enumerate(names):
        im = Image.open(os.path.join(raw, name + ".png")).convert("RGBA")
        if kind != "cars":
            # A car is too small to carry the heavy outer line; its own fine ink is enough.
            im = outer_contour(im, r_out=OUTLINE, rc=9)
        if im.size != (frame, frame):
            raise SystemExit("%s is %s, not %d square" % (name, im.size, frame))
        # Clear a border in every cell. Straights run to the edge of their frame, and at a small
        # scale that edge would bleed into the cell beside it; the game never draws this far out.
        border = BORDER if frame > 128 else 3
        edge = Image.new("RGBA", im.size, (0, 0, 0, 0))
        edge.paste(im.crop((border, border, frame - border, frame - border)), (border, border))
        atlas.paste(edge, ((i % COLS) * frame, (i // COLS) * frame))
        cells[name] = [i % COLS, i // COLS]
    out_dir = os.path.join(os.path.abspath(args.game), "assets", "iso", kind)
    os.makedirs(out_dir, exist_ok=True)
    atlas.save(os.path.join(out_dir, kind + ".png"))
    index = {"frame": frame, "cols": COLS,
             "px_per_unit": frame / (float(meta["ortho"]) * float(meta["unit"])),
             "dims": meta["dims"], "cells": cells}
    json.dump(index, open(os.path.join(out_dir, kind + ".json"), "w"), indent=1, sort_keys=True)
    print("-> %s  %d pieces, %dx%d" % (out_dir, len(names), atlas.size[0], atlas.size[1]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
