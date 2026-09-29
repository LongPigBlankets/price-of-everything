"""Saved-scene checks for nitrogen: fixed camera, closed hosts, which solids may touch, and the prints.
    Blender --background --factory-startup --python n2_verify.py -- <revision_dir>
Intended contacts: the collar on the shell's neck, the valve body on the collar, the outlet in the
valve body, the spindle on the valve body, and the handwheel's two spokes joining its ring to the spindle. The diamond, its white face and the
lettering must stand off the shell (every vertex outside its radius), none of them may touch each
other's surfaces, and nothing may sit below ground."""
import bpy, bmesh, json, math, sys
from pathlib import Path
from mathutils.bvhtree import BVHTree

root = Path(sys.argv[sys.argv.index('--') + 1]).resolve()
bpy.ops.wm.open_mainfile(filepath=str(root / 'nitrogen.blend'))
info = json.loads((root / 'nitrogen_metrics.json').read_text())
scene = bpy.context.scene
assert scene.camera.data.type == 'ORTHO'
assert all(abs(math.degrees(a) - b) < .01 for a, b in zip(scene.camera.rotation_euler, (54.7356, 0, 45)))
dg = bpy.context.evaluated_depsgraph_get(); trees = {}; records = {}; verts = {}
prints = ['n2_diamond', 'n2_diamond_face', 'n2_formula']
spokes = ['n2_spoke_0', 'n2_spoke_1']
for n in info['structural_hosts'] + prints + spokes:
    o = bpy.data.objects[n]; ev = o.evaluated_get(dg); me = ev.to_mesh()
    bm = bmesh.new(); bm.from_mesh(o.data)
    ws = [o.matrix_world @ v.co for v in me.vertices]; verts[n] = ws
    records[n] = {'faces': len(me.polygons), 'non_manifold': sum(not e.is_manifold for e in bm.edges),
                  'zero_area': sum(f.calc_area() < 1e-12 for f in bm.faces), 'min_z': round(min(v.z for v in ws), 4)}
    trees[n] = BVHTree.FromPolygons(ws, [tuple(p.vertices) for p in me.polygons])
    bm.free(); ev.to_mesh_clear()
intended = [('n2_collar', 'n2_shell'), ('n2_valve_body', 'n2_collar'), ('n2_outlet', 'n2_valve_body'), ('n2_spindle', 'n2_valve_body')]
# The handwheel is a ring joined to the spindle by its two spokes (the ring itself clears the spindle).
intended += [(sp, 'n2_handwheel') for sp in spokes] + [(sp, 'n2_spindle') for sp in spokes]
must_clear = [(p, 'n2_shell') for p in prints] + [('n2_diamond', 'n2_diamond_face'), ('n2_diamond_face', 'n2_formula'), ('n2_diamond', 'n2_formula')]
pairs = {}
for a, b in must_clear + intended:
    hits = len(trees[a].overlap(trees[b])); pairs[a + '/' + b] = {'surface_intersections': hits, 'intended': (a, b) in intended}
failures = [k for k, v in pairs.items() if not v['intended'] and v['surface_intersections']]
failures += [k + ' does not touch' for k, v in pairs.items() if v['intended'] and not v['surface_intersections']]
failures += [n + ' open or degenerate' for n, r in records.items() if n in info['structural_hosts'] and (r['non_manifold'] or r['zero_area'])]
failures += [n + ' below ground' for n, r in records.items() if r['min_z'] < -0.001]
R = info['dimensions']['body_radius']
standoff = {p: round(min(math.hypot(v.x, v.y) for v in verts[p]) - R, 5) for p in prints}
failures += [p + ' sinks into the shell' for p, d in standoff.items() if d <= 0]
out = {'camera_degrees': [math.degrees(x) for x in scene.camera.rotation_euler], 'meshes': records, 'pairs': pairs, 'print_standoff': standoff, 'failures': failures}
(root / 'saved_scene_verification.json').write_text(json.dumps(out, indent=2) + '\n')
print(json.dumps({'failures': failures, 'print_standoff': standoff}))
