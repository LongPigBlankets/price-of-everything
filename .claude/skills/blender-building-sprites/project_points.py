"""Project world points / object bounds through a builder's OWN camera into raw render px.
    blender --background --factory-startup --python project_points.py -- <builder.py> <build_fn> <level> <objects,comma> [x,y,z ...]
Prints, for each named object, its 8 world bbox corners as raw px (1024 canvas, y down), and
each explicit world point. Level 0 = level-less builder. The runtime bake step turns raw px
into sprite px with the export's crop box, factor and placement (see the bake log)."""
import os, sys, json
import bpy
from bpy_extras.object_utils import world_to_camera_view as w2c

B = os.path.dirname(os.path.abspath(__file__)).replace("\\", "/") + "/"
argv = sys.argv[sys.argv.index("--") + 1:]
builder_file, fn_name, level, objs = argv[0], argv[1], int(argv[2]), argv[3].split(",")
pts = [tuple(float(v) for v in a.split(",")) for a in argv[4:]]
for ob in list(bpy.data.objects):
    if ob.name not in ("Camera", "Light"):
        bpy.data.objects.remove(ob, do_unlink=True)
ns = {}
exec(open(B + "sprite_kit.py").read(), ns)
exec(open(os.path.join(B, builder_file)).read(), ns)
ns[fn_name]() if level == 0 else ns[fn_name](level)
bpy.context.view_layer.update()   # the rig's camera matrix is stale until the depsgraph runs
scene = bpy.context.scene
cam = scene.camera
res = scene.render.resolution_x
out = {"res": res, "objects": {}, "points": []}

def px(p):
    v = w2c(scene, cam, p)
    return [round(v.x * res, 2), round((1.0 - v.y) * res, 2)]

import mathutils
for name in objs:
    ob = bpy.data.objects.get(name)
    if ob is None:
        out["objects"][name] = None
        continue
    corners = [ob.matrix_world @ mathutils.Vector(c) for c in ob.bound_box]
    out["objects"][name] = {"world": [[round(c.x, 4), round(c.y, 4), round(c.z, 4)] for c in corners],
                            "px": [px(c) for c in corners]}
for p in pts:
    out["points"].append({"world": list(p), "px": px(mathutils.Vector(p))})
print("PROJECT_JSON " + json.dumps(out))
