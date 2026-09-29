"""Saved-scene checks for fertilisers: fixed camera, closed hosts, and which solids may touch.
    Blender --background --factory-startup --python fz_verify.py -- <revision_dir>
Must not intersect: the sack with the bed or the soil; any tomato with the bed, the soil or the sack;
the leaves with the sack. Intended contacts: the stem in the soil, the soil against the bed's walls
(it fills the bed), the calyx on its tomato. Tomatoes in a truss may touch each other."""
import bpy, bmesh, json, math, sys, itertools
from pathlib import Path
from mathutils.bvhtree import BVHTree

root = Path(sys.argv[sys.argv.index('--') + 1]).resolve()
bpy.ops.wm.open_mainfile(filepath=str(root / 'fertilisers.blend'))
info = json.loads((root / 'fertilisers_metrics.json').read_text())
scene = bpy.context.scene
assert scene.camera.data.type == 'ORTHO'
assert all(abs(math.degrees(a) - b) < .01 for a, b in zip(scene.camera.rotation_euler, (54.7356, 0, 45)))
dg = bpy.context.evaluated_depsgraph_get(); trees = {}; records = {}
leaves = sorted(o.name for o in bpy.data.objects if '_leaflet' in o.name and o.type == 'MESH')
names = info['structural_hosts'] + ['stem'] + leaves
names = list(dict.fromkeys(n for n in names if n in bpy.data.objects))
for n in names:
    o = bpy.data.objects[n]; ev = o.evaluated_get(dg); me = ev.to_mesh()
    bm = bmesh.new(); bm.from_mesh(o.data)
    ws = [o.matrix_world @ v.co for v in me.vertices]
    records[n] = {'faces': len(me.polygons), 'non_manifold': sum(not e.is_manifold for e in bm.edges),
                  'zero_area': sum(f.calc_area() < 1e-12 for f in bm.faces), 'min_z': round(min(v.z for v in ws), 4)}
    trees[n] = BVHTree.FromPolygons(ws, [tuple(p.vertices) for p in me.polygons])
    bm.free(); ev.to_mesh_clear()
bed = [n for n in names if n.startswith('bed_')]
tomatoes = [n for n in names if n.startswith('tomato') and n[6:].isdigit()]
must_clear = [('fert_bag', b) for b in bed] + [('fert_bag', 'soil')] + [(t, b) for t in tomatoes for b in bed] + [(t, 'soil') for t in tomatoes]
must_clear += [(t, 'fert_bag') for t in tomatoes] + [(l, 'fert_bag') for l in leaves]
intended = [('stem', 'soil')] + [('soil', b) for b in bed]
allowed = list(itertools.combinations(tomatoes, 2))
pairs = {}
for a, b in must_clear + intended + allowed:
    hits = len(trees[a].overlap(trees[b])); pairs[a + '/' + b] = {'surface_intersections': hits, 'intended': (a, b) in intended, 'allowed': (a, b) in allowed}
failures = [k for k, v in pairs.items() if not v['intended'] and not v['allowed'] and v['surface_intersections']]
failures += [k + ' does not touch' for k, v in pairs.items() if v['intended'] and not v['surface_intersections'] and not k.startswith('soil/')]
failures += [n + ' open or degenerate' for n, r in records.items() if n in info['structural_hosts'] and (r['non_manifold'] or r['zero_area'])]
failures += [n + ' below ground' for n, r in records.items() if r['min_z'] < -0.001]
out = {'camera_degrees': [math.degrees(x) for x in scene.camera.rotation_euler], 'meshes': records, 'pairs': pairs, 'failures': failures}
(root / 'saved_scene_verification.json').write_text(json.dumps(out, indent=2) + '\n')
print(json.dumps({'failures': failures, 'touching_tomatoes': [k for k, v in pairs.items() if v['allowed'] and v['surface_intersections']]}))
