"""Measure sustained near-parallel road/rail footprint overlap, separating elevations."""
import json
import math
from pathlib import Path
import numpy as np
from shapely import STRtree
from shapely.geometry import LineString, box

def audit(data):
    roads = data['roads']
    shapes = [LineString([r['a'], r['b']]) for r in roads]
    index = STRtree(shapes)
    rail_half = data.get('rail_half', 4.725)
    half = max(r['half'] for r in roads) + rail_half
    runs = []
    for corridor, samples in enumerate(data['rails']):
        current = None
        for a, b in zip(samples, samples[1:]):
            pa, pb = np.array(a['p']), np.array(b['p'])
            delta = pb-pa
            length = np.linalg.norm(delta)
            matches = []
            if length > .01 and not a['hidden'] and not b['hidden']:
                mid = (pa+pb)/2
                for idx in index.query(box(*(np.minimum(pa,pb)-half), *(np.maximum(pa,pb)+half))):
                    r = roads[idx]
                    if r['tunnel']: continue
                    ra, rb = np.array(r['a']), np.array(r['b'])
                    rd = rb-ra; rr = np.dot(rd,rd)
                    if rr < .01 or abs(np.dot(delta,rd))/math.sqrt(rr)/length < math.cos(math.radians(30)): continue
                    t = np.clip(np.dot(mid-ra,rd)/rr, 0, 1)
                    if np.linalg.norm(mid-ra-rd*t) >= r['half']+rail_half: continue
                    dh = abs((a['h']+b['h'])/2 - (r['ha']+(r['hb']-r['ha'])*t))
                    matches.append((dh, int(idx)))
            kind = 'same_height' if any(v[0] < 5 for v in matches) else 'grade_separated' if matches else ''
            if current and (not kind or current['kind'] != kind):
                if current['length'] > 10: runs.append(current)
                current = None
            if kind:
                if current is None: current = {'corridor':corridor,'kind':kind,'length':0.,'points':[a['p']],'road_segments':set(),'min_height_gap':999.}
                current['length'] += length
                current['points'].append(b['p'])
                current['road_segments'].update(m[1] for m in matches)
                current['min_height_gap'] = min(current['min_height_gap'], min(m[0] for m in matches))
        if current and current['length'] > 10: runs.append(current)
    runs.sort(key=lambda r:-r['length'])
    for run in runs:
        middle = run['points'][len(run['points'])//2]
        tile = min(data['tiles'],key=lambda t:math.dist(t['center'],middle))
        run.update(tile=tile['id'],label=tile['label'],length=round(run['length'],2),min_height_gap=round(run['min_height_gap'],2))
        run['road_segments'] = sorted(run['road_segments'])
    return {'transport_key':data.get('transport_key',''),
            'method':'Exposed corridors; angle difference <=30 degrees; overlapping track/road footprints for >10u; height separation >=5u classified separately.',
            'counts':{k:sum(r['kind']==k for r in runs) for k in ['same_height','grade_separated']},'runs':runs}

if __name__ == '__main__':
    output = Path(__file__).resolve().parents[3]/'outputs/supply-chain-3d/water-greenery/validation/transport-overlap.json'
    result = audit(json.load(open('/private/tmp/transport-overlap-inputs.json')))
    output.write_text(json.dumps(result,indent=2)+'\n')
    print(result['counts'])
    print([{k:r[k] for k in ['kind','length','label','min_height_gap']} for r in result['runs'][:12]])
