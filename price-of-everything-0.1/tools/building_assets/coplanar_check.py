"""List pairs of objects whose axis-aligned faces overlap in one plane, facing the same way.

These pairs z-fight: in the Blender sprite they can be invisible, but the 3D view's depth
buffer shows them as flicker. Corners of one material are harmless; a coloured part laid
flush on a differently coloured face is not. Largest overlaps print first.

blender --background <file.blend> --python coplanar_check.py -- <BLDG_ collection> [tolerance]"""
import bpy, sys
from collections import defaultdict
args = sys.argv[sys.argv.index('--')+1:]
col = bpy.data.collections[args[0]]; tol = float(args[1]) if len(args) > 1 else .004
faces = []   # (axis, plane, object, rect in the other two axes, normal sign)
for ob in col.objects:
    if ob.type != 'MESH': continue
    mw = ob.matrix_world
    for p in ob.data.polygons:
        n = (mw.to_3x3() @ p.normal).normalized()
        axis = max(range(3), key=lambda i: abs(n[i]))
        if abs(n[axis]) < .999: continue
        vs = [mw @ ob.data.vertices[i].co for i in p.vertices]
        o = [i for i in range(3) if i != axis]
        rect = (min(v[o[0]] for v in vs), max(v[o[0]] for v in vs), min(v[o[1]] for v in vs), max(v[o[1]] for v in vs))
        if (rect[1]-rect[0]) * (rect[3]-rect[2]) < 1e-5: continue
        plane = sum(v[axis] for v in vs)/len(vs)
        if axis == 2 and n[2] < 0 and plane < .01: continue   # undersides on the ground are never seen
        faces.append((axis, plane, ob.name, rect, 1 if n[axis] > 0 else -1))
buckets = defaultdict(list)
for f in faces: buckets[(f[0], round(f[1]/tol))].append(f)
hits = defaultdict(float)
for (axis, b), group in buckets.items():
    near = group + buckets.get((axis, b+1), [])
    for i, a in enumerate(group):
        for c in near:
            if c is a or c[2] == a[2] or abs(c[1]-a[1]) > tol or c[4] != a[4]: continue
            r1, r2 = a[3], c[3]
            ox = min(r1[1], r2[1])-max(r1[0], r2[0]); oy = min(r1[3], r2[3])-max(r1[2], r2[2])
            if ox > .01 and oy > .01:
                key = tuple(sorted((a[2], c[2]))) + ('xyz'[axis],)
                hits[key] = max(hits[key], ox*oy)
for (a, b, ax), area in sorted(hits.items(), key=lambda kv: -kv[1])[:40]:
    print(f'COPLANAR {ax}  {area:7.3f}  {a}  |  {b}')
print('COPLANAR PAIRS', len(hits))
