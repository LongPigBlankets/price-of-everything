#!/usr/bin/env python3
"""Key the game's building icons to one colour and trace them, for the nameplate's embossed
icons (owner: use the game's own factory and solar panel icons).

    python3 tools/steam_capsule/icon_key.py

For each icon in ICONS (the game's own pictograms, cream on a transparent ground in
assets/icons/buildings/cleaned/), it keeps only the icon itself: opaque and pale, since a few
opaque edge pixels still carry the navy ground the icon was cut from. Specks go, and so do
pinholes, but not the icon's own openings (the factory's windows). It writes the icon in a
single colour (icons/<name>_keyed.png), then traces its outline, holes included, into
icons/<name>.json: closed polygons in the icon's own units, y up, its height 1 and its middle
at the origin. nameplate.py extrudes them into brass relief.

The tracing is marching squares on the mask, smoothed at three times the icon's size so the
curves (the smoke, the sun) come out round rather than stepped, then thinned (Douglas-Peucker).
"""
import json
import math
import os

import numpy as np
from PIL import Image, ImageFilter
from scipy import ndimage

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.normpath(os.path.join(HERE, "..", "..", "price-of-everything-0.1", "assets", "icons",
                                    "buildings", "cleaned"))
OUT = os.path.join(HERE, "icons")
ICONS = {"factory": "b_007.png",          # b_007 industrial factory: chimney, smoke, sawtooth shed
         "solar": "b_024.png",            # b_024 solar farm: the panel on its post, and the sun
         "windmills": "b_025.png"}        # b_025 onshore wind farm, made a pair (windmills_mask)
# The windmills (owner, the three-hex logo): the onshore wind farm's turbine twice, a smaller
# one at its right as on the offshore icon (b_026), each on its own plinth and both on one
# ground line. The icon's turbine and plinth are the rows above PLINTH_FOOT; its ground bar,
# GROUND_BAR rows deep, is drawn again under both.
SMALL, APART, PLINTH_FOOT, GROUND_BAR, GROUND_OVER = 0.66, 196, 314, 10, 22
KEY_RGB = (236, 226, 202)                 # the icons' own cream
PALE = 150                                # luminance: an opaque pixel darker than this is ground
SPECK = 40                                # px: islands and holes smaller than this are noise
UP = 3                                    # trace at this multiple of the icon's size
SMOOTH = 1.1                              # px (at UP): the blur that rounds the traced curves
THIN = 0.55                               # px (at UP): Douglas-Peucker tolerance


def key(path):
    """The icon as a boolean mask of just itself."""
    a = np.asarray(Image.open(path).convert("RGBA")).astype(np.float32)
    lum = 0.2126 * a[..., 0] + 0.7152 * a[..., 1] + 0.0722 * a[..., 2]
    m = (a[..., 3] > 128) & (lum > PALE)
    lab, n = ndimage.label(m)
    sizes = ndimage.sum(m, lab, range(1, n + 1))
    m = np.isin(lab, [i + 1 for i, s in enumerate(sizes) if s >= SPECK])
    holes, n = ndimage.label(~m)
    sizes = ndimage.sum(~m, holes, range(1, n + 1))
    m |= np.isin(holes, [i + 1 for i, s in enumerate(sizes) if s < SPECK])
    return m


def windmills_mask(path):
    """Two of the turbine on one ground bar, unioned as a mask so the outline traces as one."""
    m = key(path)
    turbine = m[:PLINTH_FOOT]
    cols = np.nonzero(turbine.any(axis=0))[0]
    turbine = turbine[:, cols[0]:cols[-1] + 1]
    h, w = turbine.shape
    sh, sw = round(h * SMALL), round(w * SMALL)
    small = np.asarray(Image.fromarray(turbine.astype(np.uint8) * 255).resize((sw, sh), Image.BILINEAR)) > 127
    hub = w // 2                                      # the turbine's mast is its middle
    x_small = hub + APART - sw // 2
    W = max(w, x_small + sw) + 2 * GROUND_OVER
    out = np.zeros((h + GROUND_BAR + 4, W), bool)
    out[2:2 + h, GROUND_OVER:GROUND_OVER + w] |= turbine
    out[2 + h - sh:2 + h, GROUND_OVER + x_small:GROUND_OVER + x_small + sw] |= small
    out[2 + h:2 + h + GROUND_BAR, :] = True
    return out


def march(f, level=0.5):
    """Closed contours of f at `level` (marching squares), as lists of (x, y) in pixels."""
    f = np.pad(f, 1)
    h, w = f.shape
    b = f >= level
    case = (b[:-1, :-1] * 1 + b[:-1, 1:] * 2 + b[1:, 1:] * 4 + b[1:, :-1] * 8)
    ii, jj = np.nonzero((case != 0) & (case != 15))

    def cross(i0, j0, i1, j1):
        v0, v1 = f[i0, j0], f[i1, j1]
        t = (level - v0) / (v1 - v0) if v1 != v0 else 0.5
        return (j0 + (j1 - j0) * t - 1, i0 + (i1 - i0) * t - 1)

    # edges of cell (i, j): top (i,j)-(i,j+1), right (i,j+1)-(i+1,j+1), bottom (i+1,j)-(i+1,j+1),
    # left (i,j)-(i+1,j); each keyed so neighbouring cells share it
    def edge(i, j, e):
        return {"t": ("h", i, j), "b": ("h", i + 1, j), "l": ("v", i, j), "r": ("v", i, j + 1)}[e]

    def point(key_):
        kind, i, j = key_
        return cross(i, j, i, j + 1) if kind == "h" else cross(i, j, i + 1, j)

    table = {1: [("l", "t")], 2: [("t", "r")], 3: [("l", "r")], 4: [("r", "b")], 6: [("t", "b")],
             7: [("l", "b")], 8: [("b", "l")], 9: [("b", "t")], 11: [("b", "r")], 12: [("r", "l")],
             13: [("r", "t")], 14: [("t", "l")]}
    nxt = {}
    for i, j in zip(ii, jj):
        c = int(case[i, j])
        if c in (5, 10):                                   # saddles: decide by the cell's middle
            mid = (f[i, j] + f[i, j + 1] + f[i + 1, j] + f[i + 1, j + 1]) / 4.0 >= level
            segs = {5: [("l", "b"), ("r", "t")] if mid else [("l", "t"), ("r", "b")],
                    10: [("t", "l"), ("b", "r")] if mid else [("t", "r"), ("b", "l")]}[c]
        else:
            segs = table[c]
        for e0, e1 in segs:
            nxt[edge(i, j, e0)] = edge(i, j, e1)
    loops, seen = [], set()
    for start in nxt:
        if start in seen:
            continue
        loop, k = [], start
        while k not in seen and k in nxt:
            seen.add(k)
            loop.append(point(k))
            k = nxt[k]
        if len(loop) >= 3:
            loops.append(loop)
    return loops


def thin(pts, eps):
    """Douglas-Peucker on a closed loop."""
    def dp(seq):
        if len(seq) < 3:
            return seq
        (x0, y0), (x1, y1) = seq[0], seq[-1]
        L = math.hypot(x1 - x0, y1 - y0) or 1e-9
        d = [abs((y1 - y0) * x - (x1 - x0) * y + x1 * y0 - y1 * x0) / L for x, y in seq]
        k = int(np.argmax(d))
        if d[k] > eps:
            return dp(seq[:k + 1])[:-1] + dp(seq[k:])
        return [seq[0], seq[-1]]
    far = max(range(len(pts)), key=lambda k: (pts[k][0] - pts[0][0]) ** 2 + (pts[k][1] - pts[0][1]) ** 2)
    return dp(pts[:far + 1])[:-1] + dp(pts[far:] + [pts[0]])[:-1]


def main():
    os.makedirs(OUT, exist_ok=True)
    for name, file in ICONS.items():
        m = (windmills_mask if name == "windmills" else key)(os.path.join(SRC, file))
        keyed = np.zeros(m.shape + (4,), np.uint8)
        keyed[m] = (*KEY_RGB, 255)
        Image.fromarray(keyed).save(os.path.join(OUT, name + "_keyed.png"))
        big = Image.fromarray((m * 255).astype(np.uint8)).resize((m.shape[1] * UP, m.shape[0] * UP), Image.BILINEAR)
        f = np.asarray(big.filter(ImageFilter.GaussianBlur(SMOOTH))).astype(np.float32) / 255.0
        loops = [thin(lp, THIN) for lp in march(f)]
        loops = [lp for lp in loops if len(lp) >= 3]
        xs = [x for lp in loops for x, _ in lp]
        ys = [y for lp in loops for _, y in lp]
        cx, cy, hgt = (min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2, max(ys) - min(ys)
        polys = [[[round((x - cx) / hgt, 5), round(-(y - cy) / hgt, 5)] for x, y in lp] for lp in loops]
        width = (max(xs) - min(xs)) / hgt
        with open(os.path.join(OUT, name + ".json"), "w") as fh:
            json.dump({"source": "price-of-everything-0.1/assets/icons/buildings/cleaned/" + file,
                       "width": round(width, 4), "height": 1.0, "polygons": polys}, fh)
        print("%-8s %s: %d outlines, %d points, %.2f wide per 1 high" % (
            name, file, len(polys), sum(len(p) for p in polys), width))


if __name__ == "__main__":
    main()
