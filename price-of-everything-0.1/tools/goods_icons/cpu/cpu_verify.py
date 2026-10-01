"""Saved-scene checks for the CPU: the fixed camera, closed hosts, nothing below ground; the seated CPU's parts stack
(board on the pocket floor, flange on the board, plateau on the flange), the leaning CPU rests on the tray without
passing into it.    Blender --background --factory-startup --python cpu_verify.py -- <revision_dir>"""
import bpy, bmesh, json, math, sys
from pathlib import Path
from mathutils.bvhtree import BVHTree
root = Path(sys.argv[sys.argv.index('--') + 1]).resolve()
bpy.ops.wm.open_mainfile(filepath=str(root / 'cpu.blend'))
info = json.loads((root / 'cpu_metrics.json').read_text()); scene = bpy.context.scene
assert scene.camera.data.type == 'ORTHO'
assert all(abs(math.degrees(a) - b) < .01 for a, b in zip(scene.camera.rotation_euler, (54.7356, 0, 45)))
trees, rec = {}, {}
for n in info['structural_hosts']:
    o = bpy.data.objects[n]; bm = bmesh.new(); bm.from_mesh(o.data); ws = [o.matrix_world @ v.co for v in o.data.vertices]
    rec[n] = {'non_manifold': sum(not e.is_manifold for e in bm.edges), 'min_z': round(min(v.z for v in ws), 4)}
    trees[n] = BVHTree.FromPolygons(ws, [tuple(p.vertices) for p in o.data.polygons]); bm.free()
tray = [n for n in trees if n.startswith('tray')]
intended = [('seated_board', 'tray_upper'), ('seated_flange', 'seated_board'), ('seated_plateau', 'seated_flange')]
lean = [('chip_board', n) for n in tray]
pairs = {a + '/' + b: len(trees[a].overlap(trees[b])) for a, b in intended + lean}
failures = [a + '/' + b + ' does not touch' for a, b in intended if not pairs[a + '/' + b]]
touch = sum(pairs['chip_board/' + n] for n in tray)
failures += [] if touch else ['chip_board does not rest on the tray']
# resting, not passing through: the chip's back face must not have tray points on its far side
chip = bpy.data.objects['chip_board']; c = sum((chip.matrix_world @ v.co for v in chip.data.vertices), chip.matrix_world.translation * 0) / len(chip.data.vertices)
lean_rad = math.radians(info['dimensions']['chip']['lean']); nrm = (math.cos(lean_rad), 0.0, math.sin(lean_rad))
back = min((chip.matrix_world @ v.co)[0] * nrm[0] + (chip.matrix_world @ v.co)[2] * nrm[2] for v in chip.data.vertices)
worst = max(((bpy.data.objects[n].matrix_world @ v.co)[0] * nrm[0] + (bpy.data.objects[n].matrix_world @ v.co)[2] * nrm[2]) - back
            for n in tray for v in bpy.data.objects[n].data.vertices)
failures += ['the tray passes %.3f into the leaning chip' % worst] if worst > 0.002 else []
failures += [n + ' open' for n, r in rec.items() if r['non_manifold']] + [n + ' below ground' for n, r in rec.items() if r['min_z'] < -0.006]
out = {'meshes': rec, 'pairs': pairs, 'tray_past_chip_back': round(worst, 4), 'failures': failures}
(root / 'saved_scene_verification.json').write_text(json.dumps(out, indent=2) + '\n'); print(json.dumps({'failures': failures, 'pairs': pairs}))
