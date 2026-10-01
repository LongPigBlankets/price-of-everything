#!/usr/bin/env python3
"""Check a capsule layout for clashes and draw it as a plan.

    python3 tools/steam_capsule/check_layout.py tools/steam_capsule/renders/plate.png

Reads the render's .layout.json (footprints the render script exports), rasterises it
in plan view turned like the camera (the view's far side up), and reports every clash:
- a building standing in water, or off the plate, unless it belongs in the water;
- a building closer than CLEARANCE to a road, the railway, the river or a bridge;
- two buildings closer than GAP;
- a road or the railway running into water anywhere but on a bridge or the pier.
Writes <render>_plan.png with the clashes in red, and exits 1 if there are any.
"""
import json
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont

RES = 0.025                  # world units per plan pixel
CLEARANCE = 0.20             # building to railway, river or bridge
ROAD_CLEARANCE = 0.10        # building to road: houses front their roads (buildings.SETBACK 0.16)
GAP = 0.08                   # building to building
# Pieces of one works may touch each other. A game building (CAP_*) is already one works.
WORKS = [("BO_Harbour_warehouse", "BO_Harbour_warehouse_2", "BO_Harbour_crane")]
IN_WATER = {"BO_Ship", "CAP_Cargo_ship", "CAP_Offshore_wind"}   # must stand in the sea
SHORE = {"BO_Harbour_crane", "CAP_Harbour"}   # may stand over the water: the pier and its crane
RAILSIDE = {"BO_Coal_heap", "BO_Coal_heap_2"}   # the railway's own stock: tipped from the track
END_RADIUS = 0.35                             # a road or rail may END this close to a building
FONT = "/System/Library/Fonts/Supplemental/Arial.ttf"


def main(render):
    stem = os.path.splitext(render)[0]
    L = json.load(open(stem + ".layout.json"))
    polys = [p for _, p in L["plate"]]
    allp = [pt for p in polys for pt in p]
    U = [(x + y) / math.sqrt(2) for x, y in allp]
    V = [(y - x) / math.sqrt(2) for x, y in allp]
    u0, v1 = min(U) - 1, max(V) + 1
    W = int((max(U) + 1 - u0) / RES)
    H = int((v1 - (min(V) - 1)) / RES)

    def to_px(pt):
        x, y = pt
        return ((x + y) / math.sqrt(2) - u0) / RES, (v1 - (y - x) / math.sqrt(2)) / RES

    def mask(shapes):
        m = Image.new("L", (W, H))
        d = ImageDraw.Draw(m)
        for s in shapes:
            if len(s) >= 3:
                d.polygon([to_px(p) for p in s], fill=255)
        return np.asarray(m) > 0

    def grow(m, dist):
        r = max(1, int(round(dist / RES)))
        img = Image.fromarray((m * 255).astype(np.uint8))
        from PIL import ImageFilter
        return np.asarray(img.filter(ImageFilter.MaxFilter(2 * r + 1))) > 0

    by_mat = {}
    for mat, p in L["plate"]:
        by_mat.setdefault(mat, []).append(p)
    # A pit is cut into the land, so it counts as land.
    land = mask(by_mat.get("map_ground", []) + by_mat.get("map_sand", []) + L.get("pits", []))
    sea = mask(by_mat.get("map_sea", []) + by_mat.get("map_shelf", []))
    river = mask(by_mat.get("map_river", []))
    plate = land | sea | river
    kinds = {"road": [], "rail": [], "bridge": [], "pier": []}
    for name, faces in L["infra"].items():
        if name.startswith("BO_Pipeline"):
            continue                        # the chemical plant's own pipework, not a road
        k = "bridge" if ("_bridge_" in name or "_truss_" in name) else \
            "pier" if name == "BO_Pier" else "rail" if "railway" in name else "road"
        kinds[k] += faces
    inf = {k: mask(v) for k, v in kinds.items()}
    # Where a road or the railway ends it serves a building, so it may reach it there.
    ends = np.zeros((H, W), bool)
    if L.get("ends"):
        e_img = Image.new("L", (W, H))
        ed = ImageDraw.Draw(e_img)
        rr = END_RADIUS / RES
        for p in L["ends"]:
            cx, cy = to_px(p)
            ed.ellipse([cx - rr, cy - rr, cx + rr, cy + rr], fill=255)
        ends = np.asarray(e_img) > 0
    blds = {n: mask(hulls) for n, hulls in L["buildings"].items()}

    clashes = []

    def area(m):
        return m.sum() * RES * RES

    def pretty(n):
        return n.replace("CAP_", "").replace("BO_", "").replace("_", " ")

    for n, m in blds.items():
        if n not in IN_WATER and n not in SHORE:
            wet = m & (sea | river)
            if area(wet) > 0.01:
                clashes.append((wet, "%s stands in water (%.2f sq units)" % (pretty(n), area(wet))))
        if n in IN_WATER:
            dry = m & ~sea
            if area(dry) > 0.01:
                clashes.append((dry, "%s is not in the bay (%.2f sq units dry)" % (pretty(n), area(dry))))
        off = m & ~plate
        if area(off) > 0.01:
            clashes.append((off, "%s hangs off the plate (%.2f sq units)" % (pretty(n), area(off))))
        near = grow(m, CLEARANCE)
        for k in ("road", "rail", "bridge"):
            if k == "road" and n in SHORE:
                continue                                   # the roads lead onto the pier
            if k == "rail" and n in RAILSIDE:
                continue
            gap = ROAD_CLEARANCE if k == "road" else CLEARANCE
            hit = (grow(m, gap) if k == "road" else near) & inf[k] & ~ends
            if area(hit) > 0.005:
                clashes.append((hit, "%s is within %.2f of the %s" % (pretty(n), gap, {"road": "road", "rail": "railway", "bridge": "bridge"}[k])))
        if n not in IN_WATER and n not in SHORE:
            hit = near & river
            if area(hit) > 0.005:
                clashes.append((hit, "%s is within %.2f of the river" % (pretty(n), CLEARANCE)))
    names = list(blds)
    for i, a in enumerate(names):
        ga = grow(blds[a], GAP)
        for b in names[i + 1:]:
            if a.startswith(b) or b.startswith(a) or any(a in g and b in g for g in WORKS):
                continue                                   # one works, or a turbine and its nacelle
            hit = ga & blds[b]
            if area(hit) > 0.005:
                clashes.append((hit, "%s and %s are within %.2f" % (pretty(a), pretty(b), GAP)))
    for k in ("road", "rail"):
        piers = inf["bridge"] | inf["pier"]
        for n in SHORE:
            if n in blds:
                piers = piers | blds[n]
        wet = inf[k] & (sea | river) & ~grow(piers, 0.05)
        if area(wet) > 0.01:
            clashes.append((wet, "the %s runs into water (%.2f sq units)" % ({"road": "road", "rail": "railway"}[k], area(wet))))

    # The road network must be one piece: roads, their bridges and the pier together. The
    # railway is left out, so a level crossing cannot join two roads that do not meet.
    from scipy import ndimage
    net = inf["road"] | mask([f for n, faces in L["infra"].items() if n.startswith("BO_Road") and "_bridge_" in n
                               for f in faces])
    for n in SHORE:
        if n in blds:
            net = net | blds[n]
    labels, count = ndimage.label(grow(net, 0.03), structure=np.ones((3, 3)))
    if count > 1:
        sizes = ndimage.sum(np.ones_like(labels), labels, range(1, count + 1))
        main = 1 + int(np.argmax(sizes))
        clashes.append(((labels > 0) & (labels != main),
                        "the roads form %d separate networks (red: cut off from the main one)" % count))

    img = np.zeros((H, W, 3), np.uint8) + np.array([20, 28, 38], np.uint8)
    for m, col in ((land, (154, 164, 101)), (mask(by_mat.get("map_sand", [])), (221, 208, 166)),
                   (sea, (79, 111, 153)), (river, (91, 134, 181)), (inf["road"], (234, 223, 190)),
                   (inf["rail"], (60, 70, 90)), (inf["pier"], (150, 150, 150)), (inf["bridge"], (120, 125, 135))):
        img[m] = col
    for m in blds.values():
        img[m] = (210, 205, 195)
        edge = m & ~np.asarray(Image.fromarray((m * 255).astype(np.uint8)).filter(__import__("PIL.ImageFilter", fromlist=["MinFilter"]).MinFilter(3))) > 0
        img[edge] = (30, 30, 30)
    for m, _ in clashes:
        img[m] = (230, 40, 40)
    out = Image.fromarray(img)
    d = ImageDraw.Draw(out)
    f = ImageFont.truetype(FONT, 18)
    for n, m in blds.items():
        ys, xs = np.nonzero(m)
        if len(xs) and "nacelle" not in n:
            d.text((xs.mean() + 6, ys.mean() - 9), pretty(n), fill=(255, 255, 255), font=f)
    out.save(stem + "_plan.png")
    for _, msg in clashes:
        print("CLASH", msg)
    print("%d clash(es); plan written to %s" % (len(clashes), stem + "_plan.png"))
    return 1 if clashes else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
