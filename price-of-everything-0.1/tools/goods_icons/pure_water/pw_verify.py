"""Saved-scene checks for pure water: fixed camera, closed hosts, and which solids may touch.
    Blender --background --factory-startup --python pw_verify.py -- <revision_dir>
Pairs that must NOT intersect are the ones whose contact would be a modelling error: the
stream against the pipe (it must clear the bore), the post against the stream, puddle or crown.
The stream entering the puddle and the crown's buried base are intended contacts."""
import bpy, bmesh, json, math, sys, itertools
from pathlib import Path
from mathutils.bvhtree import BVHTree

root = Path(sys.argv[sys.argv.index('--') + 1]).resolve()
bpy.ops.wm.open_mainfile(filepath=str(root / 'pure_water.blend'))
info = json.loads((root / 'pure_water_metrics.json').read_text())
scene = bpy.context.scene
assert scene.camera.data.type == 'ORTHO'
assert all(abs(math.degrees(a) - b) < .01 for a, b in zip(scene.camera.rotation_euler, (54.7356, 0, 45)))
dg = bpy.context.evaluated_depsgraph_get(); trees = {}; records = {}
names = info['structural_hosts'] + ['crown', 'tongue_0', 'tongue_1']
for n in names:
    o = bpy.data.objects[n]; ev = o.evaluated_get(dg); me = ev.to_mesh()
    bm = bmesh.new(); bm.from_mesh(me)
    bad = sum(not e.is_manifold for e in bm.edges); zero = sum(f.calc_area() < 1e-12 for f in bm.faces)
    records[n] = {'faces': len(bm.faces), 'non_manifold': bad, 'zero_area': zero, 'volume': round(bm.calc_volume(signed=False), 4),
                  'min_z': round(min((o.matrix_world @ v.co).z for v in me.vertices), 4)}
    trees[n] = BVHTree.FromPolygons([o.matrix_world @ v.co for v in me.vertices], [tuple(p.vertices) for p in me.polygons])
    bm.free(); ev.to_mesh_clear()
must_clear = [('stream', 'pipe_shell'), ('stream', 'post_rod'), ('stream', 'post_collar'), ('stream', 'post_foot'),
              ('puddle', 'post_foot'), ('crown', 'post_foot'), ('crown', 'stream'),
              ('tongue_0', 'stream'), ('tongue_1', 'stream'), ('tongue_0', 'tongue_1')]
allowed = [('tongue_0', 'crown'), ('tongue_1', 'crown')]   # a tongue may grow out of the ribbon's end
intended = [('stream', 'puddle'), ('crown', 'puddle'), ('tongue_0', 'puddle'), ('tongue_1', 'puddle'),
            ('post_rod', 'post_foot'), ('post_rod', 'post_collar'), ('post_collar', 'pipe_shell')]
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
