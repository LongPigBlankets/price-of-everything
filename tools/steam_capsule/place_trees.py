#!/usr/bin/env python3
"""Choose where the capsule's trees stand, from a layout the render script wrote.

    python3 tools/steam_capsule/place_trees.py tools/steam_capsule/renders/plate.png

Reads <render>.layout.json and writes trees.json beside this script: one [x, y, h, r, seed]
per tree, in world units, for render_earth_plate.py to build with the game's own tree prop
(props_kit.py). Run it again whenever the layout changes.

Trees go on open ground only: grass, not sand or a pit, clear of every building, road, rail
line, bridge and the water, and back from the plate's edge. They are spaced by Poisson-disc
sampling and thinned by a smooth noise field, so they gather in copses with open ground
between rather than spreading evenly. They are 0.4 of the prop's own size, a little above the
homes beside them.

Some are planted on purpose first (owner): an avenue down both sides of the spine road from
the docks to the EV plant (AVENUES: its line is read from blockout.py's ROADS, so it follows
the road), standing nearer the road than the scattered trees may; and a copse between the
factory and the high tech manufactory (COPSES).
"""
import ast
import json
import math
import os
import random
import sys

import numpy as np
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
RES = 0.025                                  # world units per raster pixel
CLEAR_BUILDING, CLEAR_INFRA, CLEAR_WATER, CLEAR_EDGE = 0.30, 0.28, 0.32, 0.45
SPACING = 0.46                               # between trunks
H, R = 0.76, 0.18                            # the prop's 1.9 / 0.45 at 0.4, beside half-size homes
MAX_TREES = 80
SEED = 7
# (road index in blockout.ROADS, spacing along it, offset each side of its centre), world units
AVENUES = [(0, 0.66, 0.43)]
AVENUE_CLEAR_ROAD = 0.10                     # an avenue tree may stand this near the road's edge
# (map centre in units of R, radius in R, how many), for copses planted on purpose
COPSES = [((-2.36, -1.96), 0.30, 9)]
PLATE_R, PLATE_YAW = 5.0, 57.0               # blockout's map frame: units of R, E' at this bearing


def map_to_world(x, y):
    e, n = math.radians(PLATE_YAW), math.radians(PLATE_YAW + 90.0)
    return (PLATE_R * (x * math.cos(e) + y * math.cos(n)), PLATE_R * (x * math.sin(e) + y * math.sin(n)))


def catmull(pts, per_seg=16):
    P = [pts[0]] + list(pts) + [pts[-1]]
    out = []
    for i in range(1, len(P) - 2):
        p0, p1, p2, p3 = P[i - 1], P[i], P[i + 1], P[i + 2]
        for j in range(per_seg):
            t = j / per_seg
            out.append(tuple(0.5 * (2 * p1[k] + (p2[k] - p0[k]) * t + (2 * p0[k] - 5 * p1[k] + 4 * p2[k] - p3[k]) * t * t
                                    + (3 * p1[k] - p0[k] - 3 * p2[k] + p3[k]) * t * t * t) for k in range(2)))
    out.append(tuple(pts[-1]))
    return out


def roads():
    """blockout.ROADS, read from its source (blockout.py needs Blender to run)."""
    src = open(os.path.join(HERE, "blockout.py")).read()
    start = src.index("ROADS = [") + len("ROADS = ")
    depth = 0
    for i in range(start, len(src)):
        depth += {"[": 1, "]": -1}.get(src[i], 0)
        if depth == 0:
            return ast.literal_eval(src[start:i + 1])


def main(render):
    L = json.load(open(os.path.splitext(render)[0] + ".layout.json"))
    pts = [p for _, poly in L["plate"] for p in poly]
    x0, x1 = min(p[0] for p in pts) - 1, max(p[0] for p in pts) + 1
    y0, y1 = min(p[1] for p in pts) - 1, max(p[1] for p in pts) + 1
    W, Hh = int((x1 - x0) / RES), int((y1 - y0) / RES)

    def px(p):
        return ((p[0] - x0) / RES, (y1 - p[1]) / RES)

    def mask(polys):
        m = Image.new("L", (W, Hh))
        d = ImageDraw.Draw(m)
        for poly in polys:
            if len(poly) >= 3:
                d.polygon([px(p) for p in poly], fill=255)
        return np.asarray(m) > 0

    from scipy import ndimage

    def near(m, dist):
        return ndimage.distance_transform_edt(~m) * RES <= dist

    by_mat = {}
    for mat, poly in L["plate"]:
        by_mat.setdefault(mat, []).append(poly)
    grass = mask(by_mat.get("map_ground", []))
    plate = grass | mask(by_mat.get("map_sand", [])) | mask(L.get("pits", []))
    water = mask(by_mat.get("map_sea", []) + by_mat.get("map_shelf", []) + by_mat.get("map_river", []))
    plate |= water
    blds = mask([h for hulls in L["buildings"].values() for h in hulls] + L.get("pits", []))
    infra = mask([f for faces in L["infra"].values() for f in faces])
    edge = ndimage.distance_transform_edt(plate) * RES <= CLEAR_EDGE
    open_ground = grass & ~near(blds, CLEAR_BUILDING) & ~near(water, CLEAR_WATER) & ~edge
    free = open_ground & ~near(infra, CLEAR_INFRA)
    by_road = open_ground & ~near(infra, AVENUE_CLEAR_ROAD)

    def ok(m, x, y):
        i, j = int((y1 - y) / RES), int((x - x0) / RES)
        return 0 <= i < m.shape[0] and 0 <= j < m.shape[1] and m[i, j]

    rng = random.Random(SEED)
    trees = []

    def plant(x, y):
        s = rng.uniform(0.85, 1.15)
        trees.append([round(x, 3), round(y, 3), round(H * s, 3), round(R * rng.uniform(0.9, 1.15) * s, 3),
                      len(trees) + 1])

    # The avenue: both sides of the road, at even steps, wherever the ground is free there.
    all_roads = roads()
    for road, step, off in AVENUES:
        path = catmull([map_to_world(*p) for p in all_roads[road]])
        seg = [math.dist(path[i], path[i + 1]) for i in range(len(path) - 1)]
        at, i, done = step / 2.0, 0, 0.0
        while i < len(seg):
            if done + seg[i] < at:
                done += seg[i]
                i += 1
                continue
            t = (at - done) / seg[i]
            (ax, ay), (bx, by) = path[i], path[i + 1]
            px_, py_ = ax + (bx - ax) * t, ay + (by - ay) * t
            nx, ny = -(by - ay) / seg[i], (bx - ax) / seg[i]
            for side in (-1, 1):
                x, y = px_ + nx * off * side, py_ + ny * off * side
                if ok(by_road, x, y) and all((x - q[0]) ** 2 + (y - q[1]) ** 2 >= (SPACING * 0.9) ** 2 for q in trees):
                    plant(x, y)
            at += step
    avenue = len(trees)
    # Copses planted on purpose.
    for (cx, cy), rad, count in COPSES:
        wx, wy = map_to_world(cx, cy)
        made = tries = 0
        while made < count and tries < 4000:
            tries += 1
            a, r = rng.uniform(0, 2 * math.pi), rad * PLATE_R * math.sqrt(rng.random())
            x, y = wx + r * math.cos(a), wy + r * math.sin(a)
            if ok(free, x, y) and all((x - q[0]) ** 2 + (y - q[1]) ** 2 >= SPACING ** 2 for q in trees):
                plant(x, y)
                made += 1
    planted = len(trees)
    # A smooth field for copses: a few long sine waves with random phases.
    waves = [(rng.uniform(0.25, 0.6), rng.uniform(0, 2 * math.pi), rng.uniform(0, 2 * math.pi),
              rng.uniform(0, 2 * math.pi)) for _ in range(4)]

    def copse(x, y):
        v = sum(math.sin(k * (x * math.cos(a) + y * math.sin(a)) + ph) for k, a, ph, _ in waves)
        return v / len(waves)

    ys, xs = np.nonzero(free)
    order = list(range(len(xs)))
    rng.shuffle(order)
    for i in order:
        x, y = x0 + xs[i] * RES, y1 - ys[i] * RES
        if copse(x, y) < 0.05:
            continue
        if any((x - t[0]) ** 2 + (y - t[1]) ** 2 < SPACING ** 2 for t in trees):
            continue
        plant(x, y)
        if len(trees) - planted >= MAX_TREES:
            break
    out = os.path.join(HERE, "trees.json")
    json.dump(trees, open(out, "w"), indent=0)
    print("%d trees written to %s (%d along the avenue, %d in planted copses)" % (
        len(trees), out, avenue, planted - avenue))


if __name__ == "__main__":
    main(sys.argv[1])
