"""What does the camera see at these 800 px pixels?   Blender -b --python pick.py -- <revision_dir> x,y x,y ..."""
import bpy, json, math, sys
from pathlib import Path
from mathutils import Vector, Matrix
args = sys.argv[sys.argv.index('--') + 1:]; root = Path(args[0]).resolve()
bpy.ops.wm.open_mainfile(filepath=str(root / 'plastics.blend'))
sc = bpy.context.scene; cam = sc.camera; res = sc.render.resolution_x * sc.render.resolution_percentage / 100
lw = json.loads((root / 'plastics_800_line_weights.json').read_text()); x0, y0, x1, y1 = lw['solid_frame']; k = lw['scale']
dims = (round((x1 - x0) * k), round((y1 - y0) * k)); pos = ((800 - dims[0]) // 2, (800 - dims[1]) // 2)
info = json.loads((root / 'plastics_metrics.json').read_text()); G = info['dimensions']['bag']
Rzi = Matrix.Rotation(math.radians(G['yaw']), 3, 'Z').inverted(); O = Vector((G['bx'], G['by'], 0))
dg = bpy.context.evaluated_depsgraph_get(); M = cam.matrix_world; S = cam.data.ortho_scale
fwd = -(M.to_3x3() @ Vector((0, 0, 1))); rx = M.to_3x3() @ Vector((1, 0, 0)); uy = M.to_3x3() @ Vector((0, 1, 0))
for a in args[1:]:
    px, py = map(float, a.split(','))
    rxp = (px - pos[0]) / k + x0; ryp = (py - pos[1]) / k + y0          # raw px
    u, v = rxp / res - 0.5, 0.5 - ryp / res
    o = M.translation + rx * (u * S) + uy * (v * S)
    hit, loc, nrm, idx, ob, _ = sc.ray_cast(dg, o, fwd)
    L = Rzi @ (loc - O) if hit else None
    print('px (%s) -> %s  bag-local %s  normal %s' % (a, ob.name if hit else None, tuple(round(c, 3) for c in L) if L else None, tuple(round(c, 2) for c in nrm) if hit else None))
