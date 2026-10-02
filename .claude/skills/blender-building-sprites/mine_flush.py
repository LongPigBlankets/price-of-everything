#!/usr/bin/env python3
"""Bake the mine as it stands on the supply chain board: level with the ground.

    BLENDER_EXE=... python3 mine_flush.py --game <price-of-everything-0.1 dir> [--raw DIR] [--no-render]

The shipped mine is a block of earth with the pit cut into it. On the board the ground is the
board's own, so the block goes: what is left is the pit, looked down into, and the headframe
and winding house at its rim. The block cannot simply be hidden for the render, because it is
what hides the outsides of the pit's walls; so it is rendered, flat magenta in a pass of its
own, and cut out of the picture afterwards.

Each level keeps the frame of the shipped mine_lvl<n>.png, so the game places it exactly as it
places that sprite and then lowers it by the block's height, which is written beside it:

    <game>/assets/iso/mine/mine_flush_lvl<n>.png
    <game>/assets/iso/mine/mine_flush.json   {"drop": {"1": px, ...}, "frame": 800}
"""
import argparse
import json
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import bake_sprite                                     # noqa: E402
from sprite_export import outer_contour                # noqa: E402
from stylize_shade import stylize                      # noqa: E402

SIZE, PAD, LEVELS = 800, 6, (1, 2, 3)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--game", required=True)
    ap.add_argument("--raw", default="/tmp/bake_mine_flush")
    ap.add_argument("--no-render", action="store_true")
    k = ap.parse_args()
    raw = os.path.abspath(k.raw)
    os.makedirs(raw, exist_ok=True)
    if not k.no_render:
        bake_sprite.render("mine_flush", raw, LEVELS)

    # The same crop and scale sprite_export gives the shipped set: one scale for all levels.
    src, box = {}, {}
    for L in LEVELS:
        src[L] = outer_contour(Image.open(os.path.join(raw, "mine_flush_L%d.png" % L)).convert("RGBA"))
        box[L] = src[L].split()[3].getbbox()
    factor = (SIZE - 2 * PAD) / float(max(max(b[2] - b[0], b[3] - b[1]) for b in box.values()))

    def frame(im, L):
        c = im.crop(box[L])
        nw, nh = max(1, round(c.size[0] * factor)), max(1, round(c.size[1] * factor))
        out = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
        out.alpha_composite(c.resize((nw, nh), Image.LANCZOS), ((SIZE - nw) // 2, (SIZE - nh) // 2))
        return out

    out_dir = os.path.join(os.path.abspath(k.game), "assets", "iso", "mine")
    os.makedirs(out_dir, exist_ok=True)
    drop = {}
    for L in LEVELS:
        base = os.path.join(raw, "flush_lvl%d" % L)
        frame(src[L], L).save(base + ".png")
        frame(Image.open(os.path.join(raw, "mine_flush_L%d_mask.png" % L)).convert("RGBA"), L).save(base + "_mask.png")
        stylize(base + ".png", base + "_mask.png", base + ".png", **bake_sprite.STYLIZE)
        full = np.asarray(Image.open(base + ".png").convert("RGBA")).copy()
        cut = np.asarray(frame(Image.open(os.path.join(raw, "mine_flush_L%d_cut.png" % L)).convert("RGBA"), L))
        solid = cut[..., 3] > 128
        block = solid & (cut[..., 0] > 180) & (cut[..., 1] < 90) & (cut[..., 2] > 180)
        # The block, and a little way in from it: the ink along its edges sits half on what is
        # kept. Everything outside the render's own silhouette goes too, the old outer line with it.
        wide = np.asarray(Image.fromarray((block * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(5))) > 128
        keep = solid & ~wide
        # The block's own wall inside the pit, where the pit's first step down is cut into it,
        # is ringed by what is kept: that stays, or the grass would show through the pit's side.
        sea = Image.fromarray((keep * 255).astype(np.uint8)).copy()
        ImageDraw.floodfill(sea, (0, 0), 128)
        keep = keep | (solid & (np.asarray(sea) == 0))
        full[..., 3] = np.where(keep, full[..., 3], 0)
        # A wide closing, so the headframe is outlined as one thing and not strut by strut.
        out = outer_contour(Image.fromarray(full), r_out=3, rc=30)
        out.save(os.path.join(out_dir, "mine_flush_lvl%d.png" % L))
        # The block's silhouette is its top face's diamond with its height below it.
        ys, xs = np.nonzero(block)
        drop[str(L)] = round(float((ys.max() - ys.min()) - (xs.max() - xs.min()) * math.tan(math.radians(30))), 1)
        print("L%d: kept %.0f%% of the sprite, block stands %s px tall" % (
            L, 100.0 * keep.sum() / max(1, solid.sum()), drop[str(L)]))
    json.dump({"frame": SIZE, "drop": drop}, open(os.path.join(out_dir, "mine_flush.json"), "w"), indent=1)
    print("->", out_dir)


if __name__ == "__main__":
    main()
