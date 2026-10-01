"""Saved-scene checks for REE ore: the fixed camera, closed hosts, nothing below ground, and the crystal and magnet clear
of each other and of the rocks. The brown and mottled rocks interpenetrate behind the mottled one (hidden); that pair is
reported, not failed.    Blender --background --factory-startup --python ree_verify.py -- <revision_dir>"""
import bpy, bmesh, json, math, sys
from pathlib import Path
from mathutils.bvhtree import BVHTree
root = Path(sys.argv[sys.argv.index('--') + 1]).resolve()
bpy.ops.wm.open_mainfile(filepath=str(root / 'ree_ore.blend'))
info = json.loads((root / 'ree_ore_metrics.json').read_text()); scene = bpy.context.scene
assert scene.camera.data.type == 'ORTHO'
assert all(abs(math.degrees(a) - b) < .01 for a, b in zip(scene.camera.rotation_euler, (54.7356, 0, 45)))
trees, rec = {}, {}
for n in info['structural_hosts']:
    o = bpy.data.objects[n]; bm = bmesh.new(); bm.from_mesh(o.data); ws = [o.matrix_world @ v.co for v in o.data.vertices]
    rec[n] = {'non_manifold': sum(not e.is_manifold for e in bm.edges), 'min_z': round(min(v.z for v in ws), 4)}
    trees[n] = BVHTree.FromPolygons(ws, [tuple(p.vertices) for p in o.data.polygons]); bm.free()
pairs = {}
for a in ('crystal', 'magnet', 'magnet_pole_-1', 'magnet_pole_1'):
    for b in ('crystal', 'rock_brown', 'rock_mottled'):
        if a != b and a in trees and b in trees:
            pairs[a + '/' + b] = len(trees[a].overlap(trees[b]))
hidden = len(trees['rock_brown'].overlap(trees['rock_mottled']))
failures = [k for k, v in pairs.items() if v]
failures += [n + ' open' for n, r in rec.items() if r['non_manifold']] + [n + ' below ground' for n, r in rec.items() if r['min_z'] < -0.006]
out = {'meshes': rec, 'pairs': pairs, 'rock_brown/rock_mottled_hidden_overlap': hidden, 'failures': failures}
(root / 'saved_scene_verification.json').write_text(json.dumps(out, indent=2) + '\n'); print(json.dumps({'failures': failures}))
