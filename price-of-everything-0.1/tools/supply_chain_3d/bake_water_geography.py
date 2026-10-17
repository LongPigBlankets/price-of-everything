"""Bake continuous 3D-only water geography. Requires numpy and shapely.

First run export_water_inputs.tscn to obtain actual 3D plateau/rise boundaries.
Regular-map hill/sea/lake data is read only. The output is shared by ground,
clearance and all terrain LODs; no procedural shoreline work runs at startup.
"""
import hashlib
import json
import math
from pathlib import Path
import numpy as np
from shapely import make_valid
from shapely.geometry import Polygon, LineString, box
from shapely.geometry.polygon import orient
from shapely.ops import unary_union, split

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT/'data/hills_baked.json'
OUTPUT = ROOT/'data/supply_chain_water.json'

def polygons(g):
    if g.is_empty: return []
    if g.geom_type == 'Polygon': return [g]
    return [p for c in getattr(g,'geoms',[]) for p in polygons(c)]

def poly(flat):
    return make_valid(Polygon(np.asarray(flat).reshape(-1,2)))

def simple(g):
    """Split holes into simple polygons for Godot's polygon painter."""
    result = []
    for p in polygons(g):
        if p.area < .01: continue
        if p.interiors:
            x = Polygon(p.interiors[0]).representative_point().x
            parts = split(p, LineString([(x,p.bounds[1]-1),(x,p.bounds[3]+1)]))
            for part in parts.geoms: result.extend(simple(part))
        else: result.append(p)
    return result

def flat(p):
    return np.round(np.asarray(orient(p,1).exterior.coords)[:-1],4).ravel().tolist()

def wiggle(p, outward, inward, seed):
    ring = orient(p,1).exterior.segmentize(4)
    q = np.asarray(ring.coords)[:-1]
    tangent = np.roll(q,-2,axis=0)-np.roll(q,2,axis=0)
    normal = np.column_stack([tangent[:,1],-tangent[:,0]])
    normal /= np.maximum(np.linalg.norm(normal,axis=1)[:,None],1e-6)
    # World-space phase is continuous at the closing point of the ring.
    wave = .65*np.sin(q[:,0]/61+q[:,1]/83+seed)+.35*np.sin(q[:,0]/23-q[:,1]/39+seed*2)
    distance = (outward-inward)/2 + (outward+inward)/2*wave
    candidate = make_valid(Polygon(q+normal*distance[:,None]))
    return candidate.intersection(p.buffer(outward)).union(p.buffer(-inward))

def bake(inputs):
    original = json.loads(SOURCE.read_text())
    old_coast = unary_union([poly(r['p']) for r in original['sea'] if r['b']==5] + [poly(r['p']) for r in original['polys']] + [poly(r['p']) for r in original['lakes']])
    coast = unary_union([wiggle(p,20,5,i*.71) for i,p in enumerate(polygons(old_coast))])
    islands = []
    for i,p in enumerate(polygons(old_coast)):
        line = orient(p,1).exterior
        for station in np.arange(180+i*17,line.length,720):
            at = np.array(line.interpolate(station).coords[0])
            tangent = np.array(line.interpolate(min(station+3,line.length)).coords[0])-np.array(line.interpolate(max(0,station-3)).coords[0])
            normal = np.array([tangent[1],-tangent[0]])/max(np.linalg.norm(tangent),.001)
            center = at+normal*15
            theta = np.arange(20)*math.tau/20
            radius = 3.3+.6*np.sin(theta*3+station)
            island = Polygon(center+np.column_stack([np.cos(theta)*radius,np.sin(theta)*radius*.8]))
            if island.distance(coast)>2 and old_coast.buffer(20).covers(island): islands.append(island)
    coast = unary_union([coast]+islands).intersection(old_coast.buffer(20)).union(old_coast.buffer(-5))
    assert coast.difference(old_coast.buffer(20.001)).area < .01
    assert old_coast.buffer(-5.001).difference(coast).area < .01
    print('Coast:',len(polygons(coast)),'parts,',len(islands),'islets',flush=True)

    levels = {}
    for r in inputs['regions']:
        remaining = poly(r['p'])
        for rise in sorted(r['rises'],key=lambda a:-a['level']):
            part = remaining.intersection(poly(rise['p']))
            levels.setdefault(rise['level'],[]).append(part)
            remaining = remaining.difference(part)
        levels.setdefault(r['level'],[]).append(remaining)
    lake_beds = unary_union(levels.get(25,[]))
    levels = {h:unary_union(parts).intersection(old_coast) for h,parts in levels.items() if h>25}
    lakes = []
    lake_groups = []
    checks = []
    for i,source in enumerate(inputs['lakes']):
        old = poly(source['p'])
        rim = old.buffer(35).difference(old)
        h = max(levels,key=lambda h:levels[h].intersection(rim).area)
        # Nominal water tiles are basin floor, not a lower land terrace. Give
        # each connected basin the surrounding plateau's level before expansion.
        bed = unary_union([p for p in polygons(lake_beds) if p.intersects(old)])
        plateau = unary_union(polygons(levels[h].union(bed).intersection(old_coast)))
        # A constrained shore should still meander inward, rather than trace
        # a straight plateau/outer-world edge like a reservoir wall.
        allowed = unary_union([wiggle(p,0,18,i*.57) for p in polygons(plateau)]).buffer(-1.1).intersection(plateau.buffer(-1.1))
        shape = unary_union([wiggle(p,30,6,i*.93) for p in polygons(old)]).intersection(allowed)
        # Retain only the connected bodies touching the authored lake.
        shape = unary_union([p for p in polygons(shape) if p.area>200 and p.intersects(old)]).simplify(.03, preserve_topology=True)
        # Remove sub-centimetre clipper slivers before float32 conversion in
        # Godot. The extra 0.1u inset leaves room for this simplification.
        assert shape.difference(plateau.buffer(-1.01)).area < .001
        lip = shape.distance(plateau.boundary)
        assert math.isfinite(lip) and lip>=1, (i,lip)
        checks.append({'source':i,'plate':h,'area_before':old.area,'area_after':shape.area,'minimum_lip':lip})
        for body in polygons(shape):
            shores = [np.asarray(r.coords)[:-1].round(4).ravel().tolist() for r in [body.exterior]+list(body.interiors)]
            banks = plateau.intersection(body.buffer(24))
            lake_groups.append((body,banks))
            # Keep a 3u visible bank even where the display relief exaggerates
            # mountain heights; a fixed source-space drop becomes a tall wall.
            display_slope = 1 if h<=77 else min(5,math.floor((h-77-.001)/11))+2
            for p in simple(body): lakes.append({'p':flat(p),'level':max(25,h-3/display_slope),'plate':h,'shores':shores,
                                                 'bank_mask':[flat(q) for q in simple(banks)]})
    print('Lakes:',len(lakes),'bodies; minimum terrain lip:',min(c['minimum_lip'] for c in checks),flush=True)

    lake_shapes = [poly(r['p']) for r in lakes]
    # All ribbons are polygon differences of the complete shapes. Tile edges
    # never become shorelines, and adjacent tiny bars cannot protrude at bends.
    ink = []
    for outer,inner,tone in [(28,0,'shallows_outer'),(15,0,'shallows_inner'),(0,-15,'sand'),(2.3,-1.1,'shore'),(3.15,2.05,'foam')]:
        ink.append((coast.buffer(outer).difference(coast.buffer(inner)),tone))
    for p,limit in lake_groups:
        ink.append((p.buffer(2).difference(p.buffer(-2)).intersection(limit),'lake_sand'))
        ink.append((p.buffer(.8).difference(p.buffer(-.8)).intersection(limit),'lake_foam'))
    ink_boxes = [g.bounds for g,tone in ink]
    tile_data = {}
    coast_boundary = coast.boundary
    for tile in inputs['tiles']:
        cx,cy = tile['center']
        hexagon = Polygon([(cx+270,cy),(cx+135,cy+240),(cx-135,cy+240),(cx-270,cy),(cx-135,cy-240),(cx+135,cy-240)])
        gutter = box(cx-278,cy-248,cx+278,cy+248)
        local_coast = coast.intersection(hexagon)
        data = {'land':[flat(p) for p in simple(local_coast)],'lakes':[],'ink':[],'shore':[]}
        for lake in lake_shapes: data['lakes'].extend(flat(p) for p in simple(lake.intersection(hexagon)))
        for (g,tone),bounds in zip(ink,ink_boxes):
            if gutter.intersects(box(*bounds)):
                data['ink'].extend({'tone':tone,'p':flat(p)} for p in simple(g.intersection(gutter)))
        # True coastline segments, also used by river mouths. The normal points
        # from land to water even for an island within a nominal sea tile.
        for p in polygons(coast):
            if not gutter.intersects(p): continue
            q = np.asarray(orient(p,1).exterior.coords)
            for a,b in zip(q,q[1:]):
                if not gutter.intersects(LineString([a,b])): continue
                d=b-a; n=np.array([d[1],-d[0]])/max(np.linalg.norm(d),.001)
                data['shore'].append(np.round(np.r_[a,b,n],4).tolist())
        tile_data[tile['id']] = data
    return {'version':1,'source_sha256':hashlib.sha256(SOURCE.read_bytes()).hexdigest(),
            'limits':{'coast_out':20,'coast_in':5,'lake_lip':1},'lake_checks':checks,'islets':len(islands),
            'coast':[flat(p) for p in simple(coast)],'lakes':lakes,'tiles':tile_data}

if __name__ == '__main__':
    inputs = json.load(open('/private/tmp/water-inputs.json'))
    result = bake(inputs)
    OUTPUT.write_text(json.dumps(result,separators=(',',':'))+'\n')
    print('Wrote',OUTPUT.stat().st_size,'bytes',flush=True)
