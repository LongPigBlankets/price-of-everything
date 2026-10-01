"""Saved-scene checks for plastics: fixed camera, closed hosts, and which solids may touch.
    Blender --background --factory-startup --python pl_verify.py -- <revision_dir>
Must not intersect: the bottle with the chair; the bag (and its handles) with the chair; the seat with
the back legs' feet... Intended contacts: the seat in the shell, the back legs under the seat, the front
fins on the shell's legs, the cap on the bottle. Pellets may touch each other and the bag's film."""
import bpy, bmesh, json, math, sys
from pathlib import Path
from mathutils.bvhtree import BVHTree

root = Path(sys.argv[sys.argv.index('--') + 1]).resolve()
bpy.ops.wm.open_mainfile(filepath=str(root / 'plastics.blend'))
info = json.loads((root / 'plastics_metrics.json').read_text())
scene = bpy.context.scene
assert scene.camera.data.type == 'ORTHO'
assert all(abs(math.degrees(a) - b) < .01 for a, b in zip(scene.camera.rotation_euler, (54.7356, 0, 45)))
dg = bpy.context.evaluated_depsgraph_get(); trees = {}; records = {}
extra = [n for n in ('front_fin_left', 'front_fin_right', 'front_foot_left', 'front_foot_right', 'front_band_left', 'front_band_right') if n in bpy.data.objects]
rims = [n for n in bpy.data.objects.keys() if n.startswith('chair_rim') and bpy.data.objects[n].type == 'MESH']
extra = [n for n in extra if n not in info['structural_hosts']]
for n in list(dict.fromkeys(info['structural_hosts'] + extra + rims)):
    o = bpy.data.objects[n]; ev = o.evaluated_get(dg); me = ev.to_mesh()
    bm = bmesh.new(); bm.from_mesh(o.data)
    ws = [o.matrix_world @ v.co for v in me.vertices]
    records[n] = {'faces': len(me.polygons), 'non_manifold': sum(not e.is_manifold for e in bm.edges),
                  'zero_area': sum(f.calc_area() < 1e-12 for f in bm.faces), 'min_z': round(min(v.z for v in ws), 4)}
    trees[n] = BVHTree.FromPolygons(ws, [tuple(p.vertices) for p in me.polygons])
    bm.free(); ev.to_mesh_clear()
fins = [n for n in ('front_fin_left', 'front_fin_right') if n in records]
legs = [n for n in ('back_leg_left', 'back_leg_right', 'front_leg_left', 'front_leg_right') if n in records]
fronts = [n for n in records if n.startswith('front_foot') or n.startswith('front_band')]   # v27: the owner's front legs
chair = [n for n in ('chair_shell', 'chair_seat', 'chair_mesh') if n in records] + legs + fins + rims + fronts   # v28: the downloaded mesh is one solid
bag = [n for n in records if n.startswith('bag')]
must_clear = [(a, b) for a in ('bottle', 'bottle_cap') for b in chair] + [(a, b) for a in bag for b in chair]
intended = [('bottle_cap', 'bottle')] + ([('chair_seat', 'chair_shell')] if 'chair_seat' in records else []) + [(f, 'chair_shell') for f in fins] + [(r, 'chair_shell') for r in rims]
if 'front_leg_left' in legs:                  # v23: four identical posts, each rising into the shell (arm bend or arm underside)
    intended += [(l, 'chair_shell') for l in legs]
    for f in fronts:                          # v27: each foot pad and band on its leg, the bands up to the seat's underside
        intended.append((f, 'front_leg_' + f.split('_')[-1]))
        if f.startswith('front_band'):
            intended.append((f, 'chair_seat'))
else:
    intended += [(l, 'chair_seat') for l in legs if l != 'back_leg_left'] + [('back_leg_left', 'chair_shell')] * ('back_leg_left' in legs)
pairs = {}
for a, b in must_clear + intended:
    hits = len(trees[a].overlap(trees[b])); pairs[a + '/' + b] = {'surface_intersections': hits, 'intended': (a, b) in intended}
failures = [k for k, v in pairs.items() if not v['intended'] and v['surface_intersections']]
failures += [k + ' does not touch' for k, v in pairs.items() if v['intended'] and not v['surface_intersections']]
failures += [n + ' open or degenerate' for n, r in records.items() if n in info['structural_hosts'] and (r['non_manifold'] or r['zero_area'])]
failures += [n + ' below ground' for n, r in records.items() if r['min_z'] < -0.006]
out = {'camera_degrees': [math.degrees(x) for x in scene.camera.rotation_euler], 'meshes': records, 'pairs': pairs, 'failures': failures}
(root / 'saved_scene_verification.json').write_text(json.dumps(out, indent=2) + '\n')
print(json.dumps({'failures': failures}))
