#!/usr/bin/env python3
"""Lay the key art's map and the nameplate together under one light (a mock-up).

    python3 tools/steam_capsule/compose_capsule.py MAP_PRINT NAMEPLATE OUT [--mirror]

MAP_PRINT is finish_render.py's transparent _print.png; NAMEPLATE is nameplate.py's
transparent render. With --mirror the map is flipped left to right, so its golden light,
which comes off the sea on the right, comes from the left, as the nameplate's does when it
is rendered with --light topleft (owner).

One light, off the top left of the frame, spans everything: the navy backdrop is lit warm in
its top-left corner and falls to dark at the bottom right; the map and the nameplate each
cast a soft shadow down and to the right onto it; and the map carries a gentle wash of the
same light, brighter toward its top left.

With --map-width the map is scaled to that share of the frame's width (owner: two thirds of
the composition) and set in the bottom-right corner, leaving the top left to the nameplate.

The nameplate stands where --plate-at puts it: the top-left corner (tl), the middle of the
left side (l) or the bottom-right corner (br). Unless --plate-h fixes its size, it is made
as large as it can be there (up to PLATE_MAX) without coming within MAP_CLEAR of the map.
"""
import argparse
import os
import sys

import numpy as np
from PIL import Image, ImageFilter, ImageOps

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from nameplate_finish import bloom, glow_of, light_of  # noqa: E402

NAVY = np.array((20, 28, 38), np.float32) / 255.0
LIGHT_AT = (-0.10, -0.18)            # the light's centre, as shares of the width and height
LIGHT_REACH = 1.25                   # how far it reaches, as a share of the width
LIT = np.array((0.25, 0.225, 0.195), np.float32)    # the backdrop where the light is strongest
DARK = 0.72                          # the backdrop beyond its reach, as a share of the navy
MAP_WASH = (1.10, 0.86)              # the map's brightness at the light's side and the far side
PLATE_MAX = 0.46                     # the largest the nameplate may be, as a share of the frame's height
MAP_CLEAR = 0.012                    # how near the map it may come, as a share of the width
EDGE = 0.03                          # its margin from the frame's edges, as a share of the width


def backdrop(w, h):
    """Navy lit warm from off the top-left corner, falling to a little below navy at the far
    corner."""
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    d = np.hypot(xx - LIGHT_AT[0] * w, yy - LIGHT_AT[1] * h) / (LIGHT_REACH * w)
    fall = (np.clip(1.0 - d, 0.0, 1.0) ** 1.6)[..., None]
    return NAVY[None, None, :] * DARK * (1.0 - fall) + LIT[None, None, :] * fall


def wash(img, w, h):
    """The same light over the map: brighter toward the frame's top left, dimmer at its far
    corner."""
    a = np.asarray(img).astype(np.float32) / 255.0
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    t = np.clip((xx / w + yy / h) / 2.0, 0.0, 1.0)
    g = MAP_WASH[0] + (MAP_WASH[1] - MAP_WASH[0]) * t
    a[..., :3] = np.clip(a[..., :3] * g[..., None], 0.0, 1.0)
    return Image.fromarray((a * 255 + 0.5).astype(np.uint8))


def shadowed(canvas, layer, at, offset, blur, opacity):
    """Composite a transparent layer at `at` with its soft shadow cast by `offset`."""
    sh = Image.new("RGBA", layer.size, (3, 5, 8, 0))
    sh.putalpha(layer.split()[3].point(lambda v: int(v * opacity)))
    sh = sh.filter(ImageFilter.GaussianBlur(blur))
    canvas.alpha_composite(sh, (at[0] + offset[0], at[1] + offset[1]))
    canvas.alpha_composite(layer, at)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("map_print")
    ap.add_argument("nameplate")
    ap.add_argument("out")
    ap.add_argument("--mirror", action="store_true")
    ap.add_argument("--plate-at", choices=("tl", "l", "br"), default="tl")
    ap.add_argument("--map-width", type=float, default=None, help="the map's width, share of the frame's")
    ap.add_argument("--plate-h", type=float, default=None, help="the nameplate's height, share of the frame's")
    args = ap.parse_args()
    m = Image.open(args.map_print).convert("RGBA")
    if args.mirror:
        m = ImageOps.mirror(m)
    w, h = m.size
    if args.map_width:
        crop = m.crop(m.getbbox())
        margin = int(0.02 * w)
        k = min(args.map_width * w / crop.size[0], (h - 2 * margin) / crop.size[1])
        crop = crop.resize((int(crop.size[0] * k), int(crop.size[1] * k)), Image.LANCZOS)
        m = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        m.alpha_composite(crop, (w - margin - crop.size[0], h - margin - crop.size[1]))
        print("map at %.2f of the frame's width" % (crop.size[0] / w))
    canvas = Image.fromarray((backdrop(w, h) * 255 + 0.5).astype(np.uint8)).convert("RGBA")
    shadowed(canvas, wash(m, w, h), (0, 0), (int(0.014 * w), int(0.024 * h)), 0.012 * w, 0.62)
    plate = bloom(Image.open(args.nameplate).convert("RGBA"), glow_of(args.nameplate))
    from scipy import ndimage
    near_map = ndimage.binary_dilation(np.asarray(m)[..., 3] > 16, iterations=int(MAP_CLEAR * w))
    edge = int(EDGE * w)

    def fitted(share):
        ph = int(share * h)
        p = plate.resize((int(plate.size[0] * ph / plate.size[1]), ph), Image.LANCZOS)
        a = np.asarray(p)[..., 3] > 16                      # where the plate itself is
        ys, xs = np.nonzero(a)
        x0, x1, y0, y1 = xs.min(), xs.max(), ys.min(), ys.max()
        if args.plate_at == "tl":
            at = (edge - x0, edge - y0)
        elif args.plate_at == "l":
            at = (edge - x0, (h - (y1 - y0)) // 2 - y0)
        else:
            at = (w - edge - x1, h - edge - y1)
        # the frame's part under the plate, and the plate's part inside the frame
        fx0, fy0 = max(0, at[0]), max(0, at[1])
        fx1, fy1 = min(w, at[0] + p.size[0]), min(h, at[1] + p.size[1])
        sub = near_map[fy0:fy1, fx0:fx1]
        mine = a[fy0 - at[1]:fy1 - at[1], fx0 - at[0]:fx1 - at[0]]
        return p, at, bool((mine & sub).any())

    share = args.plate_h or PLATE_MAX
    p, at, clash = fitted(share)
    while clash and args.plate_h is None and share > 0.12:
        share -= 0.01
        p, at, clash = fitted(share)
    high = light_of(args.nameplate).endswith("-high")          # a high sun casts a shorter shadow
    off = (0.006, 0.010) if high else (0.010, 0.016)
    shadowed(canvas, p, at, (int(off[0] * w), int(off[1] * h)), 0.006 * w, 0.60)
    print("nameplate at %s, %.2f of the frame's height%s" % (args.plate_at, share, " (touches the map)" if clash else ""))
    canvas.convert("RGB").save(args.out)
    print("wrote", args.out)


if __name__ == "__main__":
    main()
