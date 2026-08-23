#!/usr/bin/env python3
"""Render ONE building from all four sides, for inspection.

    blender --background --factory-startup --python render_rotations.py -- \
        <builder.py> <build_fn> <level> <out_prefix> <BLDG_collection>

Writes <out_prefix>_000.png, _090.png, _180.png, _270.png. Colour pass only — this is for
LOOKING at a model, not for baking a sprite, so it skips the shading mask and the print pass.

The camera never moves; the building turns under it. That is the point — the rig's view angle
IS the style contract, so every side has to be judged from the angle the game will show, and
a moved camera would answer a question nobody asked.
"""
import math
import os
import sys

import bpy
import mathutils

B = os.path.dirname(os.path.abspath(__file__)).replace("\\", "/") + "/"
argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
if len(argv) < 5:
    raise SystemExit("need: <builder.py> <build_fn> <level> <out_prefix> <BLDG_collection>")
builder_file, fn_name, level, out_prefix, col_name = (
    argv[0], argv[1], int(argv[2]), argv[3], argv[4])

for ob in list(bpy.data.objects):
    if ob.name not in ("Camera", "Light"):
        bpy.data.objects.remove(ob, do_unlink=True)

ns = {}
exec(open(B + "sprite_kit.py").read(), ns)
exec(open(os.path.join(B, builder_file)).read(), ns)
print("BUILD", ns[fn_name]() if level == 0 else ns[fn_name](level), flush=True)

scene = bpy.context.scene
fs = scene.view_layers[0].freestyle_settings
for ls in list(fs.linesets):
    if ls.name not in ("ink", "ink_fine"):
        fs.linesets.active_index = list(fs.linesets).index(ls)
        bpy.ops.scene.freestyle_lineset_remove()

mine_col = bpy.data.collections.get(col_name)
if mine_col is None or not mine_col.objects:
    raise SystemExit("no objects in %r" % col_name)
for c in bpy.data.collections:
    if c.name.startswith(("BLDG_", "SHOWCASE_", "STACK_")):
        off = c.name != mine_col.name
        c.hide_render = c.hide_viewport = off
mine_col.hide_render = mine_col.hide_viewport = False
for ob in mine_col.objects:
    ob.hide_render = ob.hide_viewport = False
mine = {o.name for o in mine_col.objects}
fine = bpy.data.collections.get("FINE_INK")
if fine:
    for ob in fine.objects:
        ob.hide_render = ob.hide_viewport = ob.name not in mine

scene.render.image_settings.file_format = 'PNG'
scene.render.image_settings.color_mode = 'RGBA'
scene.render.film_transparent = True
os.makedirs(os.path.dirname(out_prefix) or ".", exist_ok=True)

# Turn about the model's own plan CENTRE, not the world origin: a building built off-centre
# would otherwise swing across the frame and leave the shot on two of the four sides.
xs, ys = [], []
for ob in mine_col.objects:
    if ob.type != 'MESH':
        continue
    for c in ob.bound_box:
        w = ob.matrix_world @ mathutils.Vector(c)
        xs.append(w.x); ys.append(w.y)
pivot = mathutils.Vector(((min(xs) + max(xs)) * 0.5, (min(ys) + max(ys)) * 0.5, 0.0))
print("PIVOT %.3f %.3f" % (pivot.x, pivot.y), flush=True)

step = mathutils.Matrix.Translation(pivot) @ mathutils.Matrix.Rotation(
    math.radians(90.0), 4, 'Z') @ mathutils.Matrix.Translation(-pivot)

for i, ang in enumerate((0, 90, 180, 270)):
    if i:
        for ob in mine_col.objects:
            ob.matrix_world = step @ ob.matrix_world
        bpy.context.view_layer.update()
    scene.render.filepath = "%s_%03d.png" % (out_prefix, ang)
    bpy.ops.render.render(write_still=True)
    print("ROT_OK", ang, scene.render.filepath, flush=True)
print("ROT_DONE", flush=True)
