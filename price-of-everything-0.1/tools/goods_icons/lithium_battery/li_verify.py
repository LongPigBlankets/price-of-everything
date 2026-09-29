"""Saved-scene checks for the lithium-ion battery: fixed camera, closed hosts, and which solids may touch.
    Blender --background --factory-startup --python li_verify.py -- <revision_dir>
Must not intersect: cells with each other, terminals with the cover, the cover or its print with the
crate. Intended contacts: cells standing on the crate floor (and nowhere near its walls: checked by
clearance), panels and terminals sunk into their cells, the cover resting on the panels. Nothing but
the terminal posts may rise above the rim."""
import bpy, bmesh, json, math, sys
from pathlib import Path
from mathutils.bvhtree import BVHTree

root = Path(sys.argv[sys.argv.index('--') + 1]).resolve()
bpy.ops.wm.open_mainfile(filepath=str(root / 'lithium_battery.blend'))
info = json.loads((root / 'lithium_battery_metrics.json').read_text())
scene = bpy.context.scene
assert scene.camera.data.type == 'ORTHO'
assert all(abs(math.degrees(a) - b) < .01 for a, b in zip(scene.camera.rotation_euler, (54.7356, 0, 45)))
dg = bpy.context.evaluated_depsgraph_get(); trees = {}; records = {}
names = info['structural_hosts'] + ['cover_print']
for n in names:
    o = bpy.data.objects[n]; ev = o.evaluated_get(dg); me = ev.to_mesh()
    bm = bmesh.new(); bm.from_mesh(me)
    bad = sum(not e.is_manifold for e in bm.edges); zero = sum(f.calc_area() < 1e-12 for f in bm.faces)
    ws = [o.matrix_world @ v.co for v in me.vertices]
    records[n] = {'faces': len(bm.faces), 'non_manifold': bad, 'zero_area': zero, 'volume': round(bm.calc_volume(signed=False), 5),
                  'min_z': round(min(v.z for v in ws), 4), 'bbox': [[round(min(getattr(v, a) for v in ws), 4), round(max(getattr(v, a) for v in ws), 4)] for a in 'xyz']}
    trees[n] = BVHTree.FromPolygons(ws, [tuple(p.vertices) for p in me.polygons])
    bm.free(); ev.to_mesh_clear()
cells = sorted(n for n in names if n.startswith('cell_') and n.count('_') == 1)
panels = [c + '_plate' for c in cells if c + '_plate' in records]
terms = sorted(n for n in names if '_terminal_' in n)
must_clear = [(t, 'cover') for t in terms] + [('cover', 'crate'), ('cover_print', 'crate')]
must_clear += [(pn, t) for pn in panels for t in terms if t.startswith(pn[:-len('_plate')] + '_')]
washers = sorted(n for n in names if n.endswith('_plus_washer'))
must_clear += [(w, 'cover') for w in washers] + [(w, pn) for w in washers for pn in panels]
# Cells meet face to face (touching is allowed); they must not overlap: checked by bounding boxes.
cell_overlaps = []
for i, a in enumerate(cells):
    for b in cells[i + 1:]:
        ov = [min(records[a]['bbox'][k][1], records[b]['bbox'][k][1]) - max(records[a]['bbox'][k][0], records[b]['bbox'][k][0]) for k in range(2)]
        if min(ov) > 1e-6:
            cell_overlaps.append(a + '/' + b + ' overlap')
intended = [(pn, pn[:-len('_plate')]) for pn in panels] + [(t, t.split('_terminal_')[0]) for t in terms]
intended += [(w, w.replace('_plus_washer', '_terminal_a')) for w in washers] + [(w, w.replace('_plus_washer', '')) for w in washers]
# Cells standing on the floor are coplanar contacts, which the BVH overlap test reports unreliably;
# the floor and lip clearances are checked from the bounding boxes below instead.
intended += [('cover', pn) for pn in panels if records[pn]['bbox'][1][1] > records['cover']['bbox'][1][0]]
pairs = {}
for a, b in must_clear + intended:
    hits = len(trees[a].overlap(trees[b])); pairs[a + '/' + b] = {'surface_intersections': hits, 'intended': (a, b) in intended}
failures = cell_overlaps + [k for k, v in pairs.items() if not v['intended'] and v['surface_intersections']]
failures += [k + ' does not touch' for k, v in pairs.items() if v['intended'] and not v['surface_intersections']]
failures += [n + ' open or degenerate' for n, r in records.items() if n in info['structural_hosts'] and (r['non_manifold'] or r['zero_area'])]
failures += [n + ' below ground' for n, r in records.items() if r['min_z'] < -0.001]
# Cells touch the crate only at the floor: keep them clear of the walls' inner faces.
tw = info['dimensions']['walls'][0]; cr = info['dimensions']['crate']
for c in cells:
    (x0, x1), (y0, y1), (z0, _) = records[c]['bbox']
    if min(x0 - tw, cr[0] - tw - x1, y0 - tw, cr[1] - tw - y1) < 0.005 or abs(z0 - info['dimensions']['walls'][1]) > 1e-6:
        failures.append(c + ' not clear of the walls or not on the floor')
    lip = info['dimensions'].get('lip')
    if lip and records[c]['bbox'][2][1] > cr[2] - lip[1] - 0.001:
        failures.append(c + ' reaches the rim lip')
# Nothing may rise above the crate rim except the terminal posts (as shipped).
rim = info['dimensions']['crate'][2]
failures += [n + ' above the rim' for n, r in records.items() if r['bbox'][2][1] > rim + 1e-6 and '_terminal_' not in n]
out = {'camera_degrees': [math.degrees(x) for x in scene.camera.rotation_euler], 'meshes': records, 'pairs': pairs, 'failures': failures}
(root / 'saved_scene_verification.json').write_text(json.dumps(out, indent=2) + '\n')
print(json.dumps({'failures': failures, 'pairs': {k: v['surface_intersections'] for k, v in pairs.items()}}))
