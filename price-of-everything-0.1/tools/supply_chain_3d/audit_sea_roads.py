#!/usr/bin/env python3
"""Find roads beyond the 3D coast; river/lake bridges remain valid."""
import json
import sys
from collections import defaultdict
from pathlib import Path
from shapely.geometry import Polygon, LineString, box
from shapely.ops import unary_union, linemerge
from shapely.prepared import prep
from shapely.strtree import STRtree

folder = Path(sys.argv[1])
water = Path(__file__).resolve().parents[2] / "data/supply_chain_water.json"
data = json.loads(water.read_text())
land = unary_union([Polygon(list(zip(v[::2], v[1::2]))) for v in data["coast"]]).buffer(.1)
prepared = prep(land)
# Split the complicated continent outline into small clip boxes once, rather
# than repeating a whole-continent difference for every six-unit road sample.
local = {}
def local_land(line):
    x, y = line.centroid.coords[0]
    key = (int(x//256), int(y//256))
    if key not in local:
        local[key] = land.intersection(box(key[0]*256-30,key[1]*256-30,(key[0]+1)*256+30,(key[1]+1)*256+30))
    return local[key]

plan = json.loads((folder / "plan.json").read_text())
parts = defaultdict(list)
tiles = defaultdict(set)
for r in plan["roads"]:
    line = LineString([r["a"], r["b"]])
    if prepared.covers(line):
        continue
    sea = line.difference(local_land(line))
    if sea.length > .2:
        parts[r["source"]].append(sea)
        tiles[r["source"]].add(r["tile"])
result = []
for source, pieces in parts.items():
    shape = unary_union(pieces)
    if shape.length <= 1:
        continue
    result.append(dict(source=source, sea_length=shape.length, point=list(shape.centroid.coords[0]), tiles=sorted(tiles[source])))
result.sort(key=lambda r: r["sea_length"], reverse=True)
(folder / "sea-roads.json").write_text(json.dumps(result,indent=2)+"\n")
print(json.dumps(result,indent=2))
