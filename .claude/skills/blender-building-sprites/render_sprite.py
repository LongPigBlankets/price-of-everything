#!/usr/bin/env python3
"""Headless render of ONE building sprite, plus its shading mask.

    blender --background --factory-startup --python render_sprite.py -- \
        <builder.py> <build_fn> <level> <out.png> <BLDG_collection>

Writes <out.png> and <out>_mask.png. Feed both to sprite_export.py, then stylize_shade.py.

Runs from --factory-startup rather than the .blend: setup_rig() asserts engine, film, camera,
sun and linesets, so nothing needs saved state, and a 1024 sprite takes about four seconds.
Two things about a fresh Blender have to be handled here, and both fail SILENTLY:

  * the default CUBE renders. It lives in the Scene Collection, so the BLDG_*/SHOWCASE_*/
    STACK_* isolation sweep never touches it, and it sat INSIDE a building as a pale box
    nobody had modelled.
  * enabling Freestyle leaves Blender's own default "LineSet" in place. setup_rig only ever
    ADDS its three, so the default draws a second, thicker pass over everything.
"""
import os
import sys

import bpy

B = os.path.dirname(os.path.abspath(__file__)).replace("\\", "/") + "/"

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
if len(argv) < 5:
    raise SystemExit("need: <builder.py> <build_fn> <level> <out.png> <BLDG_collection>")
builder_file, fn_name, level, out_png, col_name = (
    argv[0], argv[1], int(argv[2]), argv[3], argv[4])

for ob in list(bpy.data.objects):
    if ob.name not in ("Camera", "Light"):
        print("PURGE startup object", ob.name, flush=True)
        bpy.data.objects.remove(ob, do_unlink=True)

ns = {}
exec(open(B + "sprite_kit.py").read(), ns)
exec(open(os.path.join(B, builder_file)).read(), ns)
# level 0 means the builder takes NO level argument. The docks and the construction site
# each build one fixed scene — the port ships that single image under all three level names
# and the construction site only has an L1 at all.
print("BUILD", ns[fn_name]() if level == 0 else ns[fn_name](level), flush=True)

scene = bpy.context.scene

# --- linesets -----------------------------------------------------------------------------
# "contour" is dropped DELIBERATELY along with any stray default. Freestyle's external contour
# is view-map based, so it draws the 7 px line around every patch of background, including the
# gaps between a component's own pipes and the holes inside a pylon's lattice. The heavy line
# is synthesized per-component in sprite_export.py, where 2D morphology can tell an interior
# pocket from true outside.
fs = scene.view_layers[0].freestyle_settings
for ls in list(fs.linesets):
    if ls.name not in ("ink", "ink_fine"):
        print("DROP lineset", ls.name, flush=True)
        fs.linesets.active_index = list(fs.linesets).index(ls)
        bpy.ops.scene.freestyle_lineset_remove()

# --- isolation ------------------------------------------------------------------------------
mine_col = bpy.data.collections.get(col_name)
if mine_col is None or not mine_col.objects:
    raise SystemExit("no objects in %r (have: %s)" % (
        col_name, [c.name for c in bpy.data.collections if c.name.startswith("BLDG_")]))
print("COLLECTION", mine_col.name, len(mine_col.objects), "objects", flush=True)

for c in bpy.data.collections:
    if c.name.startswith(("BLDG_", "SHOWCASE_", "STACK_")):
        off = c.name != mine_col.name
        c.hide_render = c.hide_viewport = off
mine_col.hide_render = mine_col.hide_viewport = False
for ob in mine_col.objects:
    ob.hide_render = ob.hide_viewport = False

# Hiding BLDG_* is NOT enough: fine-ink assemblies DUAL-LINK into FINE_INK, which stays
# visible so ink_fine can draw, so another building's pylon keeps rendering. Hide per OBJECT.
mine = {o.name for o in mine_col.objects}
fine = bpy.data.collections.get("FINE_INK")
if fine:
    stale = 0
    for ob in fine.objects:
        ob.hide_render = ob.hide_viewport = ob.name not in mine
        stale += ob.name not in mine
    print("FINE_INK", len(fine.objects), "objects,", stale, "hidden as stale", flush=True)

# --- colour pass ------------------------------------------------------------------------------
scene.render.image_settings.file_format = 'PNG'
scene.render.image_settings.color_mode = 'RGBA'
scene.render.film_transparent = True
os.makedirs(os.path.dirname(out_png) or ".", exist_ok=True)
scene.render.filepath = out_png
bpy.ops.render.render(write_still=True)
print("RENDER_OK", out_png, flush=True)

# --- shading mask ------------------------------------------------------------------------------
# From the face NORMAL, not from a lighting render. This rig has no directional light worth
# speaking of: a single cube in a single material renders its three visible faces at lumas
# 129/130/132, because the world is white at strength 0.75 against a 2.6 sun. All the tonal
# structure in these sprites comes from MATERIALS, so a lighting-based mask is flat by
# construction — measured at override base 0.8 and 0.30, giving 0.687-0.710 and 0.502-0.529.
#
# So the mask MAKES the shading the print pass needs: emission = dot(N, L), mapped to 0..1,
# rendered with the Standard view transform so AgX cannot compress the range straight back out.
# LIGHT points upper-left-front: -Y faces and tops lit, +X faces shaded.
mask_png = out_png.rsplit(".", 1)[0] + "_mask.png"
LIGHT = (-0.30, -0.62, 0.72)
mat = bpy.data.materials.get("_shade_mask")
if mat is None:
    # A render pass must CREATE what it depends on: bpy.data.materials.get() is None in a
    # fresh Blender, and assigning None to material_override means NO override, which renders
    # an ordinary colour frame and looks exactly like a mask that silently did nothing.
    mat = bpy.data.materials.new("_shade_mask")
    mat.use_nodes = True
    nt = mat.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    geo = nt.nodes.new("ShaderNodeNewGeometry")
    dot = nt.nodes.new("ShaderNodeVectorMath")
    dot.operation = 'DOT_PRODUCT'
    dot.inputs[1].default_value = LIGHT
    rng = nt.nodes.new("ShaderNodeMapRange")
    rng.inputs["From Min"].default_value = -1.0
    rng.inputs["From Max"].default_value = 1.0
    rng.inputs["To Min"].default_value = 0.04
    rng.inputs["To Max"].default_value = 1.0
    rng.clamp = True
    emi = nt.nodes.new("ShaderNodeEmission")
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    nt.links.new(geo.outputs["Normal"], dot.inputs[0])
    nt.links.new(dot.outputs["Value"], rng.inputs["Value"])
    nt.links.new(rng.outputs["Result"], emi.inputs["Color"])
    nt.links.new(emi.outputs["Emission"], out.inputs["Surface"])

vl = scene.view_layers[0]
prev_vt = scene.view_settings.view_transform
scene.view_settings.view_transform = 'Standard'
vl.material_override = mat
vl.use_freestyle = False
scene.render.use_freestyle = False
scene.render.filepath = mask_png
bpy.ops.render.render(write_still=True)
vl.material_override = None
vl.use_freestyle = True
scene.render.use_freestyle = True
scene.view_settings.view_transform = prev_vt
print("MASK_OK", mask_png, flush=True)
