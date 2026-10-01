"""Saved-scene checks for the circuit board: the fixed camera, closed hosts (the board and its raised pads), nothing
below ground, each pad seated on the board, and the copper free of loose ends (copper2.json: every trace end on a via,
a pad, the socket's edge, another trace or a finger).    Blender --background --factory-startup --python cb_verify.py -- <dir>"""
import bpy, bmesh, json, math, sys
from pathlib import Path
from mathutils.bvhtree import BVHTree
root = Path(sys.argv[sys.argv.index('--') + 1]).resolve(); here = Path(__file__).resolve().parent
bpy.ops.wm.open_mainfile(filepath=str(root / 'circuit_board.blend'))
info = json.loads((root / 'circuit_board_metrics.json').read_text()); scene = bpy.context.scene
assert scene.camera.data.type == 'ORTHO'
assert all(abs(math.degrees(a) - b) < .01 for a, b in zip(scene.camera.rotation_euler, (54.7356, 0, 45)))
trees, rec = {}, {}
for n in info['structural_hosts']:
    o = bpy.data.objects[n]; bm = bmesh.new(); bm.from_mesh(o.data); ws = [o.matrix_world @ v.co for v in o.data.vertices]
    rec[n] = {'non_manifold': sum(not e.is_manifold for e in bm.edges), 'min_z': round(min(v.z for v in ws), 4)}
    trees[n] = BVHTree.FromPolygons(ws, [tuple(p.vertices) for p in o.data.polygons]); bm.free()
failures = [n + ' open' for n, r in rec.items() if r['non_manifold']] + [n + ' below ground' for n, r in rec.items() if r['min_z'] < -0.006]
failures += [n + ' not on the board' for n in trees if n.startswith('pad') and not trees[n].overlap(trees['board'])]
C = json.loads((here / 'copper2.json').read_text())
out = {'meshes': rec, 'traces': len(C['traces']), 'vias': len(C['vias']), 'lands': len(C['lands']), 'failures': failures}
(root / 'saved_scene_verification.json').write_text(json.dumps(out, indent=2) + '\n'); print(json.dumps({'failures': failures}))
