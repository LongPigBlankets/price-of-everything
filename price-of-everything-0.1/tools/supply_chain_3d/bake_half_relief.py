#!/usr/bin/env python3
"""Derive 3D-only half contours from the shipped authored hill grid.

Requires numpy/scipy. Never regenerates or writes the regular map. Intermediate
contours lie midway (by distance) between adjacent authored elevation regions.
Disconnected summits without a higher contour retain their original height.
"""
from __future__ import annotations
import argparse
import base64
import hashlib
import json
from pathlib import Path

import numpy as np
from scipy import ndimage

PROJECT = Path(__file__).resolve().parents[2]
SOURCE = PROJECT / 'data/hills_baked.json'
OUTPUT = PROJECT / 'data/supply_chain_half_relief.json'
VERSION = 1
PAIRS = {1: [(3, 0)], 2: [(0, 1)], 3: [(3, 1)], 4: [(1, 2)],
         5: [(0, 1), (2, 3)], 6: [(0, 2)], 7: [(3, 2)], 8: [(2, 3)],
         9: [(0, 2)], 10: [(0, 3), (1, 2)], 11: [(1, 2)],
         12: [(1, 3)], 13: [(0, 1)], 14: [(0, 3)]}


def contours(field):
    """Marching squares with interpolated edge positions, returning exterior rings."""
    positive = field > 0
    cases = (positive[:-1, :-1].astype(np.uint8)
             + positive[:-1, 1:] * 2 + positive[1:, 1:] * 4 + positive[1:, :-1] * 8)
    ys, xs = np.nonzero((cases != 0) & (cases != 15))
    adjacency, points = {}, {}
    for y, x in zip(ys.tolist(), xs.tolist()):
        keys = [(x, y, 0), (x + 1, y, 1), (x, y + 1, 0), (x, y, 1)]
        for ea, eb in PAIRS[int(cases[y, x])]:
            a, b = keys[ea], keys[eb]
            adjacency.setdefault(a, []).append(b)
            adjacency.setdefault(b, []).append(a)
            for key in (a, b):
                if key in points:
                    continue
                kx, ky, vertical = key
                dx, dy = 1 - vertical, vertical
                va, vb = field[ky, kx], field[ky + dy, kx + dx]
                t = float(va / (va - vb))
                points[key] = (kx + t * dx, ky + t * dy)
    seen = set()
    rings = []
    for start in adjacency:
        if start in seen:
            continue
        current, previous, ring = start, None, []
        while current not in seen:
            seen.add(current)
            ring.append(points[current])
            neighbours = adjacency[current]
            following = next((v for v in neighbours if v != previous), None)
            previous, current = current, following
            if current is None:
                break
        if current != start or len(ring) < 3:
            continue
        p = np.asarray(ring)
        area = np.sum(p[:, 0] * np.roll(p[:, 1], -1) - p[:, 1] * np.roll(p[:, 0], -1)) / 2
        if area < 0:
            p = p[::-1]
        direction = p[1] - p[0]
        sample = (p[0] + p[1]) / 2 + np.array([-direction[1], direction[0]]) / np.linalg.norm(direction) * .2
        # Interior is left of a positive-area ring. Negative interiors are holes;
        # the original paint-ordered lower polygons restore these depressions.
        if ndimage.map_coordinates(field, sample[::-1, None], order=1)[0] <= 0:
            continue
        if abs(area) >= 1600 / 144:
            rings.append(p)
    return rings


def half_field(bands, band):
    lower, upper = bands >= band, bands >= band + 1
    components, _ = ndimage.label(lower)
    valid = np.unique(components[upper])
    valid = valid[valid > 0]
    eligible = np.isin(components, valid)
    field = ndimage.distance_transform_edt(lower) - ndimage.distance_transform_edt(~upper)
    field = ndimage.gaussian_filter(field, .65)
    field[~eligible] = np.minimum(field[~eligible], -1)
    return field


def generate():
    raw = SOURCE.read_bytes()
    doc = json.loads(raw)
    grid = doc['navgrid']
    bands = np.frombuffer(base64.b64decode(grid['cells_b64']), dtype=np.uint8).reshape(grid['gh'], grid['gw']) & 15
    origin = np.asarray(grid['origin'])
    output = []
    for band in range(2, 11):
        rings = contours(half_field(bands, band))
        for p in rings:
            world = np.round(p * grid['step'] + origin, 3)
            output.append({'b': band + .5, 'p': world.ravel().tolist()})
        print(f'Level {band - .5:g}: {len(rings)} intermediate contours', flush=True)
    return {'version': VERSION, 'source_sha256': hashlib.sha256(raw).hexdigest(),
            'method': 'distance midpoint between authored bands; no new summit heights', 'polys': output}


def self_test():
    bands = np.full((80, 100), 2, dtype=np.uint8)
    bands[10:70, 10:90] = 4
    bands[30:50, 30:70] = 5
    bands[2:7, 2:7] = 4  # isolated hill must not gain a summit
    field = half_field(bands, 4)
    assert np.all(field[2:7, 2:7] < 0)
    assert field[40, 18] < 0 < field[40, 22]
    rings = contours(field)
    assert len(rings) == 1 and abs(rings[0][:, 0].min() - 19.5) < 1
    print('Half-contour interpolation/self-test passed')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true', help='Compare regenerated output without writing it')
    args = parser.parse_args()
    self_test()
    result = generate()
    if args.check:
        assert json.loads(OUTPUT.read_text()) == result, '3D half-contour bake is stale'
    else:
        OUTPUT.write_text(json.dumps(result, separators=(',', ':')) + '\n')
    print(f'{len(result["polys"])} contours; {OUTPUT.stat().st_size:,} bytes')
