"""Saved-scene checks for diesel fuel: fixed camera, closed hosts, and which solids may touch.
    Blender --background --factory-startup --python ds_verify.py -- <revision_dir>
Must not intersect: the hoses with the can, the plinth or each other; the nozzle with the can or its
handle; the open cap with the can, the spout or the nozzle; the can with the pump or the plinth.
Intended contacts: the pump on its plinth, the hoses entering the pump (the left one through the
holster's hole), the spout in the can's neck and in the nozzle's head, the nozzle's parts with each
other, the neck on the can. The open cap may touch its neck at the hinge."""
import bpy, bmesh, json, math, sys
from pathlib import Path
from mathutils.bvhtree import BVHTree

root = Path(sys.argv[sys.argv.index('--') + 1]).resolve()
bpy.ops.wm.open_mainfile(filepath=str(root / 'fuels.blend'))
info = json.loads((root / 'fuels_metrics.json').read_text())
scene = bpy.context.scene
assert scene.camera.data.type == 'ORTHO'
assert all(abs(math.degrees(a) - b) < .01 for a, b in zip(scene.camera.rotation_euler, (54.7356, 0, 45)))
dg = bpy.context.evaluated_depsgraph_get(); trees = {}; records = {}
names = info['structural_hosts'] + [n for n in ('diesel_can_handle_bridge_0', 'diesel_can_handle_bridge_1') if n in bpy.data.objects]
for n in names:
    o = bpy.data.objects[n]; ev = o.evaluated_get(dg); me = ev.to_mesh()
    bm = bmesh.new(); bm.from_mesh(o.data)
    ws = [o.matrix_world @ v.co for v in me.vertices]
    records[n] = {'faces': len(me.polygons), 'non_manifold': sum(not e.is_manifold for e in bm.edges),
                  'zero_area': sum(f.calc_area() < 1e-12 for f in bm.faces), 'min_z': round(min(v.z for v in ws), 4)}
    trees[n] = BVHTree.FromPolygons(ws, [tuple(p.vertices) for p in me.polygons])
    bm.free(); ev.to_mesh_clear()
can, neck, cap = 'diesel_can_body', 'diesel_can_neck', 'diesel_can_cap'
handles = [n for n in names if n.startswith('diesel_can_handle_bridge')]
nozzle = ['nozzle_body', 'nozzle_guard', 'nozzle_lever', 'nozzle_collar', 'spout_collar']
must_clear = [('hose_left', can), ('hose_left', 'plinth'), ('hose_right', can), ('hose_right', 'plinth'), ('hose_left', 'hose_right'),
              ('hose_right', cap), ('hose_right', neck), (can, 'pump_body'), (can, 'plinth'), ('nozzle_spout', can),
              (cap, can), (cap, 'nozzle_spout')] + [(n, can) for n in nozzle] + [(n, h) for n in nozzle for h in handles] + [(cap, n) for n in nozzle]
must_clear += [('hose_right', h) for h in handles]
intended = [('pump_body', 'plinth'), ('hose_left', 'pump_body'), ('hose_right', 'pump_body'), ('nozzle_spout', neck), (neck, can),
            ('nozzle_guard', 'nozzle_body'), ('nozzle_lever', 'nozzle_body'), ('nozzle_collar', 'nozzle_body'), ('hose_right', 'nozzle_collar'),
            ('nozzle_spout', 'spout_collar'), ('spout_collar', 'nozzle_body'), ('nozzle_spout', 'nozzle_body')]
allowed = [(cap, neck)]
pairs = {}
for a, b in must_clear + intended + allowed:
    hits = len(trees[a].overlap(trees[b])); pairs[a + '/' + b] = {'surface_intersections': hits, 'intended': (a, b) in intended, 'allowed': (a, b) in allowed}
failures = [k for k, v in pairs.items() if not v['intended'] and not v['allowed'] and v['surface_intersections']]
failures += [k + ' does not touch' for k, v in pairs.items() if v['intended'] and not v['surface_intersections']]
failures += [n + ' open or degenerate' for n, r in records.items() if n in info['structural_hosts'] and (r['non_manifold'] or r['zero_area'])]
failures += [n + ' below ground' for n, r in records.items() if r['min_z'] < -0.001]
out = {'camera_degrees': [math.degrees(x) for x in scene.camera.rotation_euler], 'meshes': records, 'pairs': pairs, 'failures': failures}
(root / 'saved_scene_verification.json').write_text(json.dumps(out, indent=2) + '\n')
print(json.dumps({'failures': failures, 'pairs': {k: v['surface_intersections'] for k, v in pairs.items()}}))
