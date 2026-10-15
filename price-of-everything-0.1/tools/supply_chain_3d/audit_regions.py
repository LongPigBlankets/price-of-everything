#!/usr/bin/env python3
"""Review rendered 3D geometry; Shapely 2 required. No game data mutations.

Usage: python audit_regions.py <review-output-directory>
Reports candidate conflicts with actual height separation, excluding intended
access to a building, working level crossings and covered railway sections.
"""
import json
import math
import sys
from collections import Counter, defaultdict
from pathlib import Path
from shapely.geometry import Polygon, LineString, Point
from shapely.ops import unary_union, linemerge
from shapely import affinity
from shapely.strtree import STRtree


def asset_masses(path):
    """Project above-ground mesh triangles; ignore flat yard/base plates."""
    result = {}
    for key, mesh in json.loads(path.read_text()).items():
        faces, parts = mesh['faces'], []
        cutoff = mesh['height'] * .02
        for i in range(0, len(faces), 3):
            tri = faces[i:i+3]
            if max(p[1] for p in tri) < cutoff:
                continue
            poly = Polygon([(p[0], p[2]) for p in tri])
            if poly.area > 1e-9:
                parts.append(poly)
        result[key] = unary_union(parts).buffer(0)
    return result


def audit(folder, meshes=None):
    plan = json.loads((folder / 'plan.json').read_text())
    tiles = plan['tiles']
    buildings = [b for b in plan['buildings'] if not b['space'] and not b['harbour']]
    shapes = []
    for b in buildings:
        polys = [Polygon(p).buffer(0) for p in b['polygons'] if len(p) > 2]
        shape = unary_union(polys)
        if meshes and b['kind'] != 'house' and b['asset'] in meshes:
            if 'yaw' not in b:
                raise ValueError('Mesh audit needs a fresh plan containing building yaw')
            shape = affinity.scale(meshes[b['asset']], b['side'], b['side'], origin=(0, 0))
            shape = affinity.rotate(shape, -math.degrees(b['yaw']), origin=(0, 0))
            shape = affinity.translate(shape, *b['pos'])
        shapes.append(shape)
    tree = STRtree(shapes)
    roads = plan['roads']
    road_lines = [LineString([r['a'], r['b']]) for r in roads]
    road_tree = STRtree(road_lines)
    issues = []
    seen = set()

    def add(kind, tile, key, p, **extra):
        ident = (kind, key)
        if ident in seen:
            return
        seen.add(ident)
        issues.append(dict(kind=kind, tile=tile, region=tiles.get(tile, {}).get('region', ''),
                           key=key, point=list(p), **extra))

    def height(r, p):
        a, b = r['a'], r['b']
        dx, dy = b[0] - a[0], b[1] - a[1]
        t = max(0., min(1., ((p[0]-a[0])*dx+(p[1]-a[1])*dy)/max(.001, dx*dx+dy*dy)))
        return r.get('ha', 0) * (1-t) + r.get('hb', 0) * t

    for i, (b, shape) in enumerate(zip(buildings, shapes)):
        for j in tree.query(shape, predicate='intersects'):
            if j <= i:
                continue
            area = shape.intersection(shapes[j]).area
            if area > .15:
                add('building_building', b['tile'], '|'.join(sorted([b['iid'], buildings[j]['iid']])), b['pos'], area=area)
        for j in road_tree.query(shape.buffer(26), predicate='intersects'):
            r = roads[j]
            if r.get('tunnel') or r.get('source') == 'access:' + b['iid']:
                continue
            half = float(r.get('half', r.get('widths', [5])[0]))
            carriage = road_lines[j].buffer(half, cap_style=2)
            area = shape.intersection(carriage).area
            if area > .15:
                p = shape.intersection(carriage).centroid
                road_h = height(r, (p.x, p.y))
                if road_h < b['height']-2 or road_h > b.get('top', b['height']+max(20, b.get('side', 20)))+.5:
                    continue
                add('building_road', b['tile'], b['iid']+'|'+r['source'], (p.x, p.y), area=area,
                    building=b['iid'], road=r['source'], decorative=b['kind']=='house')

    rails = plan.get('visible_rails', plan['rails'])
    parallel = defaultdict(list)
    for t in rails:
        if t.get('hidden') or t.get('hidden_a') or t.get('hidden_b'):
            continue
        line = LineString([t['a'], t['b']])
        if line.length < .01:
            continue
        mid = line.interpolate(.5, normalized=True)
        p = (mid.x, mid.y)
        bed = height(t, p)
        for j in tree.query(line.buffer(7), predicate='intersects'):
            b = buildings[j]
            if bed + 1.25 < b['height'] - 2 or bed > b.get('top', b['height']+max(20, b.get('side', 20)))+2:
                continue
            if shapes[j].distance(line) < 6.6:
                add('building_rail', b['tile'], b['iid'], p, building=b['iid'], decorative=b['kind']=='house')
        dx = (t['b'][0]-t['a'][0])/line.length
        dy = (t['b'][1]-t['a'][1])/line.length
        for j in road_tree.query(line.buffer(30), predicate='intersects'):
            r, rl = roads[j], road_lines[j]
            if rl.length < .01:
                continue
            half = float(r.get('half', r.get('widths', [5])[0]))
            if line.distance(rl) >= half + 6.6:
                continue
            q = rl.interpolate(rl.project(mid))
            dh = height(r, (q.x, q.y)) - (bed+1.25)
            if dh > 6 or dh < -6:
                continue
            tangent = ((r['b'][0]-r['a'][0])/rl.length, (r['b'][1]-r['a'][1])/rl.length)
            dot = abs(dx*tangent[0]+dy*tangent[1])
            if dot > .95:
                part = line.intersection(rl.buffer(half+6.6, cap_style=2))
                parallel[(r['tile'], r['source'])].append(part)
            elif line.intersects(rl) and r.get('rail_crossing_mode') not in ('level', 'tunnel'):
                hit = line.intersection(rl)
                if hit.geom_type == 'Point':
                    add('road_rail_crossing', r['tile'], r['source']+'|'+str(tuple(round(v/10) for v in hit.coords[0])),
                        hit.coords[0], road=r['source'], separation=dh, mode=r.get('rail_crossing_mode', 'unclassified'))
    for (tile, road), parts in parallel.items():
        shape = unary_union(parts)
        if shape.geom_type == 'MultiLineString':
            shape = linemerge(shape)
        runs = list(shape.geoms) if hasattr(shape, 'geoms') else [shape]
        run = max(runs, key=lambda g: g.length)
        if run.length > 10:
            p = run.centroid
            add('parallel_road_rail', tile, road, (p.x, p.y), length=run.length)

    summary = {}
    for tid, tile in tiles.items():
        region = tile['region']
        r = summary.setdefault(region, dict(tiles=0, urban=0, decorative=0, gameplay=0, trees=0, issues=Counter()))
        r['tiles'] += 1
        r['urban'] += tile['type'] == 'urban'
        r['trees'] += tile['trees']
    for b in buildings:
        summary[tiles[b['tile']]['region']]['decorative' if b['kind']=='house' else 'gameplay'] += 1
    for issue in issues:
        summary[issue['region']]['issues'][issue['kind']] += 1
    result = dict(geometry='above-ground mesh projection' if meshes else 'rendered bounds',
                  counts=dict(Counter(i['kind'] for i in issues)), regions=summary, issues=issues)
    (folder/('audit-masses.json' if meshes else 'audit.json')).write_text(json.dumps(result, indent=2)+'\n')
    print(json.dumps(dict(buildings=len(buildings), roads=len(roads), rails=len(rails), counts=result['counts']), indent=2))
    return result

if __name__ == '__main__':
    audit(Path(sys.argv[1]), asset_masses(Path(sys.argv[2])) if len(sys.argv)>2 else None)
