"""Saved-scene checks for the building frame: the fixed camera, closed hosts, nothing below ground; each pipe passes
through its cutouts without touching the beams; no cable passes into the frame, the pane or a pipe.
    Blender --background --factory-startup --python bf_verify.py -- <revision_dir>"""
import bpy, bmesh, json, math, sys
from pathlib import Path
from mathutils.bvhtree import BVHTree
root = Path(sys.argv[sys.argv.index('--') + 1]).resolve()
bpy.ops.wm.open_mainfile(filepath=str(root / 'building_frame.blend'))
info = json.loads((root / 'building_frame_metrics.json').read_text()); scene = bpy.context.scene
assert scene.camera.data.type == 'ORTHO'
assert all(abs(math.degrees(a) - b) < .01 for a, b in zip(scene.camera.rotation_euler, (54.7356, 0, 45)))
trees, rec = {}, {}
for n in info['structural_hosts']:
    o = bpy.data.objects[n]; bm = bmesh.new(); bm.from_mesh(o.data); ws = [o.matrix_world @ v.co for v in o.data.vertices]
    rec[n] = {'non_manifold': sum(not e.is_manifold for e in bm.edges), 'min_z': round(min(v.z for v in ws), 4)}
    trees[n] = BVHTree.FromPolygons(ws, [tuple(p.vertices) for p in o.data.polygons]); bm.free()
steel = [n for n in trees if n.startswith(('post', 'beam'))]
pipes = [n for n in trees if n.startswith('pipe')]
cables = [n for n in trees if n.startswith('cable')]
pairs = {}
for a in pipes:
    for b in steel:
        pairs[a + '/' + b] = len(trees[a].overlap(trees[b]))
for a in cables:
    for b in steel + ['pane'] + pipes:
        pairs[a + '/' + b] = len(trees[a].overlap(trees[b]))
failures = [k for k, v in pairs.items() if v]
failures += [n + ' open' for n, r in rec.items() if r['non_manifold']] + [n + ' below ground' for n, r in rec.items() if r['min_z'] < -0.006]
out = {'meshes': rec, 'pairs': pairs, 'failures': failures}
(root / 'saved_scene_verification.json').write_text(json.dumps(out, indent=2) + '\n'); print(json.dumps({'failures': failures}))
