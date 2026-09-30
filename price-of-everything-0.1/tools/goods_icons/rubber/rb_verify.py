"""Saved-scene checks for rubber: the fixed camera, closed hosts, nothing below ground, and which solids may touch.
    Blender --background --factory-startup --python rb_verify.py -- <revision_dir>
Intended contacts: each boot's upper with its rim and its midsole, the midsole with the outsole; the duck's neck
peg with its head and its body, the bill with the head, the lower mandible with the bill. Must not intersect: the duck with the
boots, the two boots with each other, the boots and the duck with the stack's sheets."""
import bpy, bmesh, json, math, sys
from pathlib import Path
from mathutils.bvhtree import BVHTree

root = Path(sys.argv[sys.argv.index('--') + 1]).resolve()
bpy.ops.wm.open_mainfile(filepath=str(root / 'rubber.blend'))
info = json.loads((root / 'rubber_metrics.json').read_text())
scene = bpy.context.scene
assert scene.camera.data.type == 'ORTHO'
assert all(abs(math.degrees(a) - b) < .01 for a, b in zip(scene.camera.rotation_euler, (54.7356, 0, 45)))
dg = bpy.context.evaluated_depsgraph_get(); trees = {}; records = {}
for n in info['structural_hosts']:
    o = bpy.data.objects[n]; ev = o.evaluated_get(dg); me = ev.to_mesh()
    bm = bmesh.new(); bm.from_mesh(o.data)
    ws = [o.matrix_world @ v.co for v in me.vertices]
    records[n] = {'faces': len(me.polygons), 'non_manifold': sum(not e.is_manifold for e in bm.edges),
                  'zero_area': sum(f.calc_area() < 1e-12 for f in bm.faces), 'min_z': round(min(v.z for v in ws), 4)}
    trees[n] = BVHTree.FromPolygons(ws, [tuple(p.vertices) for p in me.polygons])
    bm.free(); ev.to_mesh_clear()
sheets = [n for n in records if n.startswith('layer')]
boot = {i: [n for n in records if n.startswith('boot%d' % i)] for i in (0, 1)}
duck = [n for n in records if n.startswith('duck')]
intended = []
for i in (0, 1):
    intended += [('boot%d' % i, 'boot%d_rim' % i), ('boot%d' % i, 'boot%d_midsole' % i), ('boot%d_midsole' % i, 'boot%d_outsole' % i)]
intended += [('duck_neck', 'duck_head'), ('duck_neck', 'duck_body'), ('duck_beak', 'duck_head'), ('duck_beak_lower', 'duck_beak')]
must_clear = [(a, b) for a in duck for b in boot[0] + boot[1]] + [(a, b) for a in boot[0] for b in boot[1]]
must_clear += [(a, b) for a in boot[0] + boot[1] + duck for b in sheets]
pairs = {}
for a, b in must_clear + intended:
    hits = len(trees[a].overlap(trees[b])); pairs[a + '/' + b] = {'surface_intersections': hits, 'intended': (a, b) in intended}
failures = [k for k, v in pairs.items() if not v['intended'] and v['surface_intersections']]
failures += [k + ' does not touch' for k, v in pairs.items() if v['intended'] and not v['surface_intersections']]
failures += [n + ' open or degenerate' for n, r in records.items() if r['non_manifold'] or r['zero_area']]
failures += [n + ' below ground' for n, r in records.items() if r['min_z'] < -0.006]
out = {'camera_degrees': [math.degrees(x) for x in scene.camera.rotation_euler], 'meshes': records, 'pairs': pairs, 'failures': failures}
(root / 'saved_scene_verification.json').write_text(json.dumps(out, indent=2) + '\n')
print(json.dumps({'failures': failures}))
