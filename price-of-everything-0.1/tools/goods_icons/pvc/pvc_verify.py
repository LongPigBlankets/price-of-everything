"""Saved-scene checks for PVC: fixed camera, closed hosts, and which solids may touch.
    Blender --background --factory-startup --python pvc_verify.py -- <revision_dir>
Must not intersect: the frame or the glass with any pipe or strap. Intended contacts: the straps
hugging the pipes, the two frame members at the mitre, the panes' edges seated in the grooves.
Nothing below ground."""
import bpy, bmesh, json, math, sys
from pathlib import Path
from mathutils.bvhtree import BVHTree

root = Path(sys.argv[sys.argv.index('--') + 1]).resolve()
bpy.ops.wm.open_mainfile(filepath=str(root / 'pvc.blend'))
info = json.loads((root / 'pvc_metrics.json').read_text())
scene = bpy.context.scene
assert scene.camera.data.type == 'ORTHO'
assert all(abs(math.degrees(a) - b) < .01 for a, b in zip(scene.camera.rotation_euler, (54.7356, 0, 45)))
dg = bpy.context.evaluated_depsgraph_get(); trees = {}; records = {}
names = info['structural_hosts'] + ['pane_0', 'pane_1']
for n in names:
    o = bpy.data.objects[n]; ev = o.evaluated_get(dg); me = ev.to_mesh()
    bm = bmesh.new(); bm.from_mesh(me)
    bad = sum(not e.is_manifold for e in bm.edges); zero = sum(f.calc_area() < 1e-12 for f in bm.faces)
    ws = [o.matrix_world @ v.co for v in me.vertices]
    records[n] = {'faces': len(bm.faces), 'non_manifold': bad, 'zero_area': zero, 'min_z': round(min(v.z for v in ws), 4),
                  'bbox': [[round(min(getattr(v, a) for v in ws), 4), round(max(getattr(v, a) for v in ws), 4)] for a in 'xyz']}
    trees[n] = BVHTree.FromPolygons(ws, [tuple(p.vertices) for p in me.polygons])
    bm.free(); ev.to_mesh_clear()
pipes = sorted(n for n in names if n.startswith('pipe_')); straps = sorted(n for n in names if n.startswith('strap_'))
frame = ['frame_bottom', 'frame_upright']; panes = ['pane_0', 'pane_1']
must_clear = [(a, b) for a in frame + panes for b in pipes + straps]
intended = [(s, p) for s in straps for p in pipes if p != 'pipe_c'] + [('frame_bottom', 'frame_upright')] + [(p, f) for p in panes for f in frame]
pairs = {}
for a, b in must_clear + intended:
    hits = len(trees[a].overlap(trees[b])); pairs[a + '/' + b] = {'surface_intersections': hits, 'intended': (a, b) in intended}
failures = [k for k, v in pairs.items() if not v['intended'] and v['surface_intersections']]
failures += [k + ' does not touch' for k, v in pairs.items() if v['intended'] and not v['surface_intersections'] and not k.startswith('frame_bottom/frame_upright')]
failures += [n + ' open or degenerate' for n, r in records.items() if n in info['structural_hosts'] and (r['non_manifold'] or r['zero_area'])]
failures += [n + ' below ground' for n, r in records.items() if r['min_z'] < -0.001]
gap = min(records[f]['bbox'][0][0] for f in frame) - max(records[s]['bbox'][0][1] for s in straps + pipes)
out = {'camera_degrees': [math.degrees(x) for x in scene.camera.rotation_euler], 'frame_to_bundle_gap_x': round(gap, 4),
       'meshes': records, 'pairs': pairs, 'failures': failures}
(root / 'saved_scene_verification.json').write_text(json.dumps(out, indent=2) + '\n')
print(json.dumps({'failures': failures, 'frame_to_bundle_gap_x': round(gap, 4)}))
