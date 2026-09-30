"""Mark each pellet's centre on an 800 px render, coloured by course (red top, green 1, blue 2), and dump bag-local
coordinates.    Blender -b --python pellet_debug.py -- <revision_dir>"""
import bpy, json, math, sys
from pathlib import Path
from mathutils import Vector, Matrix
from bpy_extras.object_utils import world_to_camera_view
root = Path(sys.argv[sys.argv.index('--') + 1]).resolve()
bpy.ops.wm.open_mainfile(filepath=str(root / 'plastics.blend'))
sc = bpy.context.scene; res = sc.render.resolution_x * sc.render.resolution_percentage / 100
lw = json.loads((root / 'plastics_800_line_weights.json').read_text()); x0, y0, x1, y1 = lw['solid_frame']; k = lw['scale']
dims = (round((x1 - x0) * k), round((y1 - y0) * k)); pos = ((800 - dims[0]) // 2, (800 - dims[1]) // 2)
info = json.loads((root / 'plastics_metrics.json').read_text()); G = info['dimensions']['bag']
Rz = Matrix.Rotation(math.radians(G['yaw']), 3, 'Z').inverted(); O = Vector((G['bx'], G['by'], 0))
out = []
for ob in bpy.data.objects:
    if ob.name.startswith('pellet') and not ob.name.endswith('_rim') and ob.type == 'MESH':
        c = sum((ob.matrix_world @ v.co for v in ob.data.vertices), Vector()) / len(ob.data.vertices)
        uv = world_to_camera_view(sc, sc.camera, c); px = ((uv.x * res - x0) * k + pos[0], ((1 - uv.y) * res - y0) * k + pos[1])
        L = Rz @ (c - O); out.append(dict(name=ob.name, course=ob.get('course', -1), px=[round(px[0], 1), round(px[1], 1)], local=[round(L.x, 4), round(L.y, 4), round(L.z, 4)]))
(root / 'pellet_debug.json').write_text(json.dumps(out, indent=1))
print('pellets', len(out))
