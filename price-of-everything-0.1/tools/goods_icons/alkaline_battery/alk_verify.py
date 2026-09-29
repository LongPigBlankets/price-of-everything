"""Saved-scene checks for the alkaline battery: fixed camera, closed hosts, and which solids may touch.
    Blender --background --factory-startup --python alk_verify.py -- <revision_dir>
Pairs that must NOT intersect are the ones whose contact would be a modelling error: a terminal
against the raised panel, the printed + against a collar, a label print against the lid. Embedded
contacts (panel, collars and label frame sunk into what they stand on) are intended."""
import bpy, bmesh, json, math, sys
from pathlib import Path
from mathutils.bvhtree import BVHTree

root = Path(sys.argv[sys.argv.index('--') + 1]).resolve()
bpy.ops.wm.open_mainfile(filepath=str(root / 'alkaline_battery.blend'))
info = json.loads((root / 'alkaline_battery_metrics.json').read_text())
scene = bpy.context.scene
assert scene.camera.data.type == 'ORTHO'
assert all(abs(math.degrees(a) - b) < .01 for a, b in zip(scene.camera.rotation_euler, (54.7356, 0, 45)))
dg = bpy.context.evaluated_depsgraph_get(); trees = {}; records = {}
names = info['structural_hosts'] + ['label_frame', 'label_band', 'label_tab_top', 'label_tab_bottom', 'disc_plus', 'disc_minus',
                                     'lid_plus_0', 'lid_plus_1', 'lid_minus']
for n in names:
    o = bpy.data.objects[n]; ev = o.evaluated_get(dg); me = ev.to_mesh()
    bm = bmesh.new(); bm.from_mesh(me)
    bad = sum(not e.is_manifold for e in bm.edges); zero = sum(f.calc_area() < 1e-12 for f in bm.faces)
    ws = [o.matrix_world @ v.co for v in me.vertices]
    records[n] = {'faces': len(bm.faces), 'non_manifold': bad, 'zero_area': zero, 'volume': round(bm.calc_volume(signed=False), 5),
                  'min_z': round(min(v.z for v in ws), 4), 'bbox': [[round(min(getattr(v, a) for v in ws), 4), round(max(getattr(v, a) for v in ws), 4)] for a in 'xyz']}
    trees[n] = BVHTree.FromPolygons(ws, [tuple(p.vertices) for p in me.polygons])
    bm.free(); ev.to_mesh_clear()
must_clear = [('post_plus', 'panel'), ('post_minus', 'panel'), ('collar_plus', 'panel'), ('collar_minus', 'panel'),
              ('lid_plus_0', 'collar_plus'), ('lid_plus_1', 'collar_plus'), ('lid_plus_0', 'panel'), ('lid_plus_1', 'panel'), ('lid_minus', 'collar_minus'), ('lid_minus', 'panel'),
              ('label_frame', 'lid'), ('label_band', 'lid'), ('label_tab_top', 'lid'), ('label_band', 'disc_plus'), ('label_band', 'disc_minus'),
              ('label_tab_bottom', 'disc_plus'), ('label_tab_bottom', 'disc_minus')]
intended = [('panel', 'lid'), ('collar_plus', 'lid'), ('collar_minus', 'lid'), ('post_plus', 'collar_plus'), ('post_minus', 'collar_minus'),
            ('label_frame', 'case'), ('label_band', 'label_frame'), ('label_tab_top', 'label_frame'), ('label_tab_bottom', 'label_frame'),
            ('disc_plus', 'label_frame'), ('disc_minus', 'label_frame')]
pairs = {}
for a, b in must_clear + intended:
    hits = len(trees[a].overlap(trees[b])); pairs[a + '/' + b] = {'surface_intersections': hits, 'intended': (a, b) in intended}
failures = [k for k, v in pairs.items() if not v['intended'] and v['surface_intersections']]
failures += [k + ' does not touch' for k, v in pairs.items() if v['intended'] and not v['surface_intersections']]
failures += [n + ' open or degenerate' for n, r in records.items() if n in info['structural_hosts'] and (r['non_manifold'] or r['zero_area'])]
failures += [n + ' below ground' for n, r in records.items() if r['min_z'] < -0.001]
# The case must meet the lid flush: the case top and the lid bottom share z = CZ.
cz = info['dimensions']['case'][2]
if abs(records['case']['bbox'][2][1] - cz) > 1e-6 or abs(records['lid']['bbox'][2][0] - cz) > 1e-6:
    failures.append('case and lid do not meet at z=%.3f' % cz)
out = {'camera_degrees': [math.degrees(x) for x in scene.camera.rotation_euler], 'meshes': records, 'pairs': pairs, 'failures': failures}
(root / 'saved_scene_verification.json').write_text(json.dumps(out, indent=2) + '\n')
print(json.dumps({'failures': failures, 'pairs': {k: v['surface_intersections'] for k, v in pairs.items()}}))
