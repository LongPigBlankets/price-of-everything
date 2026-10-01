"""Pellets and the core against the bag's film and handles (BVH overlaps).   Blender -b --python pellet_clear.py -- <dir>"""
import bpy, sys
from pathlib import Path
from mathutils.bvhtree import BVHTree
root = Path(sys.argv[sys.argv.index('--') + 1]).resolve()
bpy.ops.wm.open_mainfile(filepath=str(root / 'plastics.blend'))
def tree(o):
    return BVHTree.FromPolygons([o.matrix_world @ v.co for v in o.data.vertices], [tuple(p.vertices) for p in o.data.polygons])
film = {n: tree(bpy.data.objects[n]) for n in ('bag', 'bag_handle_left', 'bag_handle_right') if n in bpy.data.objects}
beads = [o for o in bpy.data.objects if o.name.startswith('pellet') and o.type == 'MESH' and not o.name.endswith('_rim') and o.get('edge_ink') is None]
hits = {}
for o in beads:
    t = tree(o)
    for n, ft in film.items():
        if t.overlap(ft):
            hits.setdefault(n, []).append(o.name)
print('beads', len(beads), {n: len(v) for n, v in hits.items()}, {n: v[:6] for n, v in hits.items()})
