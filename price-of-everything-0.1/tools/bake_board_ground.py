#!/usr/bin/env python3
"""Bake the ground texture of the supply chain board.

    python3 tools/bake_board_ground.py            (from the project directory)

strata.png   the cut-away under the tiles, in the key art plate's manner: soil, rock, a
             coal seam and a copper-stained band, each boundary wavy and inked. It is one tile
             edge wide and repeats exactly, so the strata run on round a tile's corners and
             from one tile to the next. From top to bottom it spans the whole height of the
             board's slab, mountain top to the slab's foot.
"""
import math
import os

from PIL import Image, ImageDraw

OUT = "assets/iso/ground"
W, H = 540, 480
INK = (47, 59, 89)
# (where the band ENDS, as a share of the height; colour; how much its lower edge waves;
#  waves across the strip; phase). The first band starts at the top.
BANDS = [
    (0.36, (124, 104, 80), 5.0, 2, 0.4),      # soil
    (0.47, (96, 82, 68), 7.0, 3, 1.9),        # subsoil
    (0.60, (88, 86, 92), 9.0, 2, 3.1),        # grey rock
    (0.665, (30, 30, 36), 6.0, 4, 0.9),       # the coal seam
    (0.78, (138, 80, 52), 10.0, 3, 2.3),      # copper-stained rock
    (1.01, (76, 72, 66), 0.0, 1, 0.0),        # deep rock
]


def edge(band, x):
    end, _, amp, waves, phase = band
    t = 2.0 * math.pi * x / W
    return end * H + amp * math.sin(t * waves + phase) + amp * 0.4 * math.sin(t * (waves + 2) + phase * 1.7)


def strata():
    im = Image.new("RGB", (W, H))
    px = im.load()
    for x in range(W):
        edges = [edge(b, x) for b in BANDS]
        for y in range(H):
            for i, e in enumerate(edges):
                if y < e:
                    px[x, y] = BANDS[i][1]
                    break
    draw = ImageDraw.Draw(im)
    # Printed shading: a dot screen on every other band, so neighbours differ in texture too.
    for i, band in enumerate(BANDS):
        if i % 2 == 0:
            continue
        dark = tuple(int(c * 0.72) for c in band[1])
        for gy in range(0, H, 6):
            for gx in range((gy // 6 % 2) * 3, W, 6):
                top = edge(BANDS[i - 1], gx) if i else 0.0
                if top + 2 < gy < edge(band, gx) - 2:
                    draw.ellipse([gx - 1, gy - 1, gx + 1, gy + 1], fill=dark)
    # Ink on every boundary.
    for band in BANDS[:-1]:
        pts = [(x, edge(band, x)) for x in range(-2, W + 3)]
        draw.line(pts, fill=INK, width=2)
    return im


os.makedirs(OUT, exist_ok=True)
strata().save(os.path.join(OUT, "strata.png"))
print("baked", OUT)
