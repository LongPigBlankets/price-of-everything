"""Saved-scene checks for the EV car: the fixed camera, nothing below ground, and which solids may touch.
    Blender --background --factory-startup --python ev_verify.py -- <revision_dir>
Intended contacts: the port housing with the body, the pistol with the port, the cable with the pistol and with the
holster, the holster with the post, the post with its plinth. Must not intersect: the charger (post, plinth, holster,
cable) with any part of the car. The car itself is the downloaded model's open surfaces, so it is not checked for
closure."""
import bpy, json, math, sys
from pathlib import Path
from mathutils.bvhtree import BVHTree

root = Path(sys.argv[sys.argv.index('--') + 1]).resolve()
bpy.ops.wm.open_mainfile(filepath=str(root / 'ev_car.blend'))
scene = bpy.context.scene
assert scene.camera.data.type == 'ORTHO'
assert all(abs(math.degrees(a) - b) < .01 for a, b in zip(scene.camera.rotation_euler, (54.7356, 0, 45)))
dg = bpy.context.evaluated_depsgraph_get(); trees = {}; min_z = {}
for o in scene.objects:
    if o.type != 'MESH' or o.get('edge_ink') or not o.name.startswith('ev_') or '_line' in o.name:
        continue
    ev = o.evaluated_get(dg); me = ev.to_mesh(); ws = [o.matrix_world @ v.co for v in me.vertices]
    trees[o.name] = BVHTree.FromPolygons(ws, [tuple(p.vertices) for p in me.polygons]); min_z[o.name] = round(min(v.z for v in ws), 4)
    ev.to_mesh_clear()
charger = [n for n in ('ev_post', 'ev_plinth', 'ev_holster', 'ev_cable') if n in trees]
car = [n for n in trees if n not in charger + ['ev_port', 'ev_pistol', 'ev_screen', 'ev_bolt']]
intended = [('ev_port', 'ev_body'), ('ev_pistol', 'ev_port'), ('ev_cable', 'ev_pistol'), ('ev_cable', 'ev_holster'),
            ('ev_holster', 'ev_post'), ('ev_post', 'ev_plinth')]
must_clear = [(a, b) for a in charger for b in car]
pairs = {}
for a, b in must_clear + intended:
    pairs[a + '/' + b] = {'surface_intersections': len(trees[a].overlap(trees[b])), 'intended': (a, b) in intended}
failures = [k for k, v in pairs.items() if not v['intended'] and v['surface_intersections']]
failures += [k + ' does not touch' for k, v in pairs.items() if v['intended'] and not v['surface_intersections']]
failures += [n + ' below ground' for n, z in min_z.items() if z < -0.006]
out = {'camera_degrees': [math.degrees(x) for x in scene.camera.rotation_euler], 'min_z': min_z, 'pairs': pairs, 'failures': failures}
(root / 'saved_scene_verification.json').write_text(json.dumps(out, indent=2) + '\n')
print(json.dumps({'failures': failures}))
