#!/usr/bin/env python3
"""Render the cars the supply chain board runs along its streets.

    blender --background --factory-startup --python car_pieces.py -- <out_dir>

One small frame per car per heading, seen by the sprite rig's own camera; bake_pipes.py packs
them into an atlas (its --kind cars). The board's streets run along twelve headings, every 30
degrees, so a car is baked at each: heading index k is the Blender angle 30*k degrees, as for
the pipes and roads. The car is the vehicle kit's sedan, brought down to the board's scale.

Pieces: car_<colour>_<k>, colour 0..3, k 0..11. The anchor (the frame's centre) is the middle
of the car at road level.
"""
import json
import math
import os
import sys

import bpy
import mathutils

B = os.path.dirname(os.path.abspath(__file__)).replace("\\", "/") + "/"
argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
if not argv:
    raise SystemExit("need: <out_dir>")
OUT = argv[0]
os.makedirs(OUT, exist_ok=True)

UNIT = 27.0
FRAME = 96
ORTHO = 0.9            # 96 px across 0.9 Blender units: the same 3.95 px per map unit as the roads
LENGTH = 11.0          # a car's length on the board, in map units
COLOURS = ("car_red", "car_blue", "car_cream", "car_grey")

for ob in list(bpy.data.objects):
    if ob.name not in ("Camera", "Light"):
        bpy.data.objects.remove(ob, do_unlink=True)
ns = {}
exec(open(B + "sprite_kit.py").read(), ns)
exec(open(B + "vehicles_kit.py").read(), ns)
ns["setup_rig"](ortho_scale=ORTHO, target=(0.0, 0.0, 0.0), res=FRAME)
scene = bpy.context.scene
fs = scene.view_layers[0].freestyle_settings
for ls in list(fs.linesets):
    if ls.name not in ("ink", "ink_fine"):
        fs.linesets.active_index = list(fs.linesets).index(ls)
        bpy.ops.scene.freestyle_lineset_remove()
# At this size the full ink line is most of the car: draw it fine.
for ls in fs.linesets:
    ls.linestyle.thickness = 1.0
scene.render.image_settings.file_format = 'PNG'
scene.render.image_settings.color_mode = 'RGBA'
scene.render.film_transparent = True
K = ns["Kit"](ns["open_collection"]("BLDG_cars"))
cam = scene.camera
cam.location = mathutils.Vector((1, -1, 1)).normalized() * 26.0

for ci, colour in enumerate(COLOURS):
    for k in range(12):
        for ob in list(K.col.objects):
            bpy.data.objects.remove(ob, do_unlink=True)
        ns["_car"](K, "car", 0.0, 0.0, 1.0, colour, seed=ci)
        bpy.context.view_layer.update()
        lo = mathutils.Vector((1e9, 1e9, 1e9))
        hi = mathutils.Vector((-1e9, -1e9, -1e9))
        for ob in K.col.objects:
            for corner in ob.bound_box:
                w = ob.matrix_world @ mathutils.Vector(corner)
                lo = mathutils.Vector((min(lo.x, w.x), min(lo.y, w.y), min(lo.z, w.z)))
                hi = mathutils.Vector((max(hi.x, w.x), max(hi.y, w.y), max(hi.z, w.z)))
        centre = mathutils.Vector(((lo.x + hi.x) / 2, (lo.y + hi.y) / 2, lo.z))
        scale = (LENGTH / UNIT) / max(1e-6, hi.x - lo.x)
        fit = (mathutils.Matrix.Rotation(math.radians(30.0 * k), 4, 'Z') @ mathutils.Matrix.Scale(scale, 4)
               @ mathutils.Matrix.Translation(-centre))
        for ob in K.col.objects:
            if ob.parent is None:
                ob.matrix_world = fit @ ob.matrix_world
        scene.render.filepath = os.path.join(OUT, "car_%d_%d.png" % (ci, k))
        bpy.ops.render.render(write_still=True)
        print("PIECE_OK", ci, k, flush=True)

json.dump({"unit": UNIT, "frame": FRAME, "ortho": ORTHO, "dims": {"length": LENGTH, "colours": len(COLOURS)}},
          open(os.path.join(OUT, "pieces.json"), "w"), indent=1)
print("ALL_OK", flush=True)
