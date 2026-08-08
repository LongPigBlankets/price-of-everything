#!/usr/bin/env python3
"""Plan a road-density experiment as a REGION overlay.

    python3 tools/plan_region_overlay.py tile_5_10 3 dense_city [--write]

Road density is a property of a REGION (road_region_jobs builds a region's whole
web from its identity), so "denser roads within N tiles of X" has to be expressed
as a set of regions, not a disc. This prints which regions the disc covers and
how completely, so you can see the spill before committing to it — a region that
is only half inside the radius will get denser roads across all of it.

--write emits data/road_region_overlays.json for the WHOLLY-covered regions plus
any partial region you name with --include. Revert by deleting that file; the
authored road_regions.json is never touched.
"""
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def rc(tile_id):
    p = tile_id.split("_")
    return int(p[1]), int(p[2])


def cube(col, row):
    x = col
    z = row - (col - (col & 1)) // 2
    return x, -x - z, z


def hex_dist(a, b):
    ax, ay, az = cube(*a)
    bx, by, bz = cube(*b)
    return max(abs(ax - bx), abs(ay - by), abs(az - bz))


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return 1
    centre, radius = sys.argv[1], int(sys.argv[2])
    identity = sys.argv[3] if len(sys.argv) > 3 else "dense_city"
    write = "--write" in sys.argv
    include = [a.split("=", 1)[1] for a in sys.argv if a.startswith("--include=")]

    import csv
    with open(os.path.join(ROOT, "data", "tile_properties.csv")) as f:
        rows = [r for r in csv.DictReader(f) if r["id"].startswith("tile_")]
    land = {r["id"] for r in rows if r["type"] not in ("sea", "deep_sea")}
    inside = {t for t in land if hex_dist(rc(centre), rc(t)) <= radius}

    with open(os.path.join(ROOT, "data", "road_regions.json")) as f:
        regions = json.load(f)["regions"]

    print("centre %s  radius %d  -> %d land tiles\n" % (centre, radius, len(inside)))
    whole, partial = [], []
    for rid, reg in regions.items():
        tiles = [t for t in reg["tiles"] if t in land]
        if not tiles:
            continue
        hit = [t for t in tiles if t in inside]
        if not hit:
            continue
        (whole if len(hit) == len(tiles) else partial).append(
            (rid, reg["identity"], len(hit), len(tiles)))

    print("WHOLLY inside the radius (safe to raise):")
    for rid, ident, hit, tot in sorted(whole):
        print("  %-22s %-13s %d/%d tiles" % (rid, ident, hit, tot))
    print("\nPARTIALLY inside (raising these spills outside the radius):")
    for rid, ident, hit, tot in sorted(partial):
        print("  %-22s %-13s %d/%d tiles  (+%d outside)" % (rid, ident, hit, tot, tot - hit))
    orphans = inside - {t for r in regions.values() for t in r["tiles"]}
    if orphans:
        print("\nIn radius but in NO region (identity stays default): %s" % sorted(orphans))

    chosen = [r for r, _, _, _ in whole] + include
    chosen = [r for r in chosen if regions.get(r, {}).get("identity") != identity]
    print("\noverlay would raise -> %s: %s" % (identity, chosen))
    if write:
        path = os.path.join(ROOT, "data", "road_region_overlays.json")
        with open(path, "w") as f:
            json.dump({"version": 1,
                       "note": "experiment: %s r=%d" % (centre, radius),
                       "identity_overrides": {r: identity for r in chosen}}, f, indent=1)
        print("wrote %s  (delete it to revert; re-bake to apply)" % path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
