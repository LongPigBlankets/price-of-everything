"""Build the capsule scene and render it through the sprite rig, headless.

    ~/.agent-shims/blender --factory-startup --python-exit-code 1 \
        --python tools/steam_capsule/render_earth_plate.py -- \
        --out tools/steam_capsule/renders/earth_plate.png

The game's buildings come first (buildings.py): each builder resets the render rig, so the
capsule's rig is stated after them, then the plate (with the mine's pit cut into it) and the
remaining blockout. Writes the PNG (transparent film) and beside it:
  .probe.json   pixel positions of the ground, each strata band on the two camera-facing
                walls (for measure_render.py) and the labels;
  .layout.json  every footprint, for check_layout.py;
  .water.png    an unlit pass in which only water is white;
  .plate.png    the plate on its own, whose outline carries the heavy line (finish_render.py).
With --save, also the scene as a .blend. --no-render builds and writes .layout.json only.
"""
import argparse
import json
import math
import os
import sys

import bpy
import mathutils
from bpy_extras.object_utils import world_to_camera_view

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_KIT = "/Users/crisu/Price of Everything/blender-assets/sprite_kit.py"

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
ap = argparse.ArgumentParser()
ap.add_argument("--kit", default=DEFAULT_KIT, help="the shared sprite_kit.py")
ap.add_argument("--out", required=True)
ap.add_argument("--res", default="1920x1080")
ap.add_argument("--radius", type=float, default=5.0)
# Camera height above the ground plane, in degrees. True isometric is 35.264. The AI
# concept is not one camera: its buildings are drawn near 21 (cooling-tower ellipse,
# rectangular roofs) but its slab reads from higher, with a top ~0.61 as deep as it is
# wide and walls ~0.20 of that depth. One 3D scene can only have one angle; 30 is where
# a plate of real hexes reproduces the slab, which is what reads as the view.
ap.add_argument("--elevation", type=float, default=30.0)
ap.add_argument("--albedo", action="append", default=[],
                help="name=r,g,b linear override for calibration, e.g. map_sand=0.7,0.6,0.35")
ap.add_argument("--save", default=None, help="also save the scene to this .blend")
ap.add_argument("--no-blockout", action="store_true",
                help="the plate alone, without buildings or massing")
ap.add_argument("--no-render", action="store_true", help="build and write .layout.json only")
ap.add_argument("--no-trees", action="store_true", help="leave out trees.json's trees")
ap.add_argument("--look", default="day", choices=("day", "golden", "dusk"),
                help="lighting: the calibrated daylight, or a warmer one with lit windows (lighting.py)")
args = ap.parse_args(argv)

exec(open(args.kit).read())
exec(open(os.path.join(HERE, "earth_plate.py")).read())
exec(open(os.path.join(HERE, "blockout.py")).read())
exec(open(os.path.join(HERE, "housing.py")).read())
exec(open(os.path.join(HERE, "capsule_parts.py")).read())
exec(open(os.path.join(HERE, "lighting.py")).read())
exec(open(os.path.join(HERE, "smoke.py")).read())
exec(open(os.path.join(HERE, "buildings.py")).read())
# The game's prop kit (trees) patches Kit, so it goes into this namespace, before any Kit().
exec(open(os.path.join(SKILL_DIR, "props_kit.py")).read())
for spec in args.albedo:
    mat, rgb = spec.split("=")
    PALETTE[mat] = tuple(float(v) for v in rgb.split(","))

scene = bpy.context.scene
for ob in list(bpy.data.objects):
    if ob.type == 'MESH':
        bpy.data.objects.remove(ob, do_unlink=True)


def xy_hull(points):
    pts = sorted(set((round(x, 4), round(y, 4)) for x, y in points))
    if len(pts) < 3:
        return pts
    def cross(o, a, b):
        return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])
    lower, upper = [], []
    for p in pts:
        while len(lower) >= 2 and cross(lower[-2], lower[-1], p) <= 0:
            lower.pop()
        lower.append(p)
    for p in reversed(pts):
        while len(upper) >= 2 and cross(upper[-2], upper[-1], p) <= 0:
            upper.pop()
        upper.append(p)
    return lower[:-1] + upper[:-1]


placed = [] if args.no_blockout else build_buildings(args.radius, PLATE_YAW)

res_x, res_y = (int(v) for v in args.res.lower().split("x"))
setup_rig(res=res_x)
scene.render.resolution_y = res_y
# The master sprite .blend's colour pipeline, read from it and restated so a factory
# startup cannot drift from the rig every kit tone was measured on.
scene.view_settings.view_transform = 'AgX'
scene.view_settings.look = 'None'
scene.view_settings.exposure = 0.0
scene.view_settings.gamma = 1.0
scene.display_settings.display_device = 'sRGB'
scene.eevee.taa_render_samples = 32
scene.render.filter_size = 1.5
# Factory startup's "Light" is a POINT lamp; setup_rig only sets its energy and angle,
# which on a point lamp lights nothing and leaves every face at ambient. The rig's is a sun.
sun = bpy.data.objects["Light"]
sun.data.type = 'SUN'
sun.data.angle = 0.0
sun.data.use_shadow = False
# The sun stands over the sea, off the right of the frame (owner), high enough that flat tops
# stay clean in the stipple (they need a dot with the sun of 0.72 or more). The sprite rig's
# light comes from the camera's side, so every face is front-lit and a cube's three faces
# render within 8 luma of each other. At this strength against a dimmer white world, the faces
# separate into three tones while every map colour holds its calibrated value (measured).
SUN_AZ, SUN_EL, SUN_ENERGY, WORLD_STRENGTH = 45.0, 48.0, 2.45, 0.62
SUN_DIR = mathutils.Vector((math.cos(math.radians(SUN_EL)) * math.cos(math.radians(SUN_AZ)),
                            math.cos(math.radians(SUN_EL)) * math.sin(math.radians(SUN_AZ)),
                            math.sin(math.radians(SUN_EL))))          # toward the sun
sun.data.energy = SUN_ENERGY
sun.rotation_euler = SUN_DIR.to_track_quat('Z', 'Y').to_euler()
world_bg = scene.world.node_tree.nodes.get("Background") if scene.world else None
if world_bg:
    world_bg.inputs[1].default_value = WORLD_STRENGTH
# Factory startup also carries Blender's default Freestyle lineset (pure black, 3 px,
# silhouette/border/crease), which the master file does not have: it drew black lines
# over the rig's navy ink wherever its crease test fired. The rig's own `contour` goes too:
# Freestyle draws it wherever background shows, up round every building that rises past the
# plate's edge and into the gaps between stacks. The heavy line belongs to the plate alone,
# so finish_render.py draws it from the .plate.png pass, as the sprites draw theirs in 2D.
fs = scene.view_layers[0].freestyle_settings
for ls in list(fs.linesets):
    if ls.name not in ("ink", "ink_fine"):
        fs.linesets.remove(ls)
# Faces marked no-ink (painted windows, sleepers, rails) are left out of every line.
for ls in fs.linesets:
    ls.select_by_face_marks = True
    ls.face_mark_negation = 'EXCLUSIVE'
    ls.face_mark_condition = 'ONE'

col = open_collection("CAPSULE_plate")
K = Kit(col)
plate, info = build_earth_plate(K, R=args.radius, pits=pits_of(placed))
items = []
if not args.no_blockout:
    items = build_blockout(Kit(open_collection("CAPSULE_buildings")), Kit(open_collection("CAPSULE_infra")), info)
    items += label_points(placed)
finish_buildings(placed)                 # after every open_collection(): they unlink FINE_INK
if not args.no_blockout:
    road_cars(ROAD_RUNS, ROAD_TOP[0])    # the lot's car on the roads, lit in the warm looks
    pit_works(placed)                    # haul trucks and floodlight masts in the mine's pit
# Trees from trees.json (place_trees.py), with the game's tree prop. Their collection is made
# directly: open_collection() would unlink the fine ink again.
trees_path = os.path.join(HERE, "trees.json")
if not args.no_blockout and not args.no_trees and os.path.exists(trees_path):
    tcol = bpy.data.collections.new("CAP_Trees")
    scene.collection.children.link(tcol)
    Kt = Kit(tcol)
    for x, y, h, r, seed in json.load(open(trees_path)):
        Kt.tree("tree%03d" % seed, x, y, h=h, r=r, seed=seed)

# The sprite rig's 45-degree yaw, lowered from true iso to the requested elevation.
# Then frame the plate by fitting its screen-space bounds with a margin.
cam = bpy.data.objects["Camera"]
elev = math.radians(args.elevation)
cam.rotation_euler = (math.pi / 2 - elev, 0.0, math.radians(45.0))
right = mathutils.Vector((1, 1, 0)).normalized()
up = mathutils.Vector((-math.sin(elev) / math.sqrt(2), math.sin(elev) / math.sqrt(2), math.cos(elev)))
toward_cam = mathutils.Vector((math.cos(elev) / math.sqrt(2), -math.cos(elev) / math.sqrt(2), math.sin(elev)))
pts = [ob.matrix_world @ mathutils.Vector(c) for ob in bpy.data.objects if ob.type == 'MESH'
       for c in ob.bound_box]
sx = [p.dot(right) for p in pts]
sy = [p.dot(up) for p in pts]
centre = right * ((min(sx) + max(sx)) / 2) + up * ((min(sy) + max(sy)) / 2)
w, h = max(sx) - min(sx), max(sy) - min(sy)
cam.data.ortho_scale = max(w, h * res_x / res_y) * 1.18
cam.location = centre + toward_cam * 40.0
cam.data.clip_end = 200.0

def pit_glow(cam):
    """The mine's pit on screen, in pixels: its centre and half-width, for the light rising out
    of it (finish_render.py)."""
    if not PIT:
        return None
    z = PIT["top"]
    pts = [world_to_camera_view(scene, cam, mathutils.Vector((x, y, z))) for x, y in PIT["rim"]]
    xs = [p.x * res_x for p in pts]
    ys = [(1.0 - p.y) * res_y for p in pts]
    return [(min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2, (max(xs) - min(xs)) / 2]


# Smoke and the look's lamps come after the framing, so neither moves the camera.
if not args.no_blockout:
    build_smoke()
look = None if args.no_blockout else apply_look(args.look, placed, sun, world_bg)
stem = os.path.splitext(os.path.abspath(args.out))[0]
with open(stem + ".look.json", "w") as f:
    json.dump({"look": args.look, "glow": look["glow"] if look else 0.0,
               "falloff": look["falloff"] if look else None,
               "sides": {side: list(look[side][2]) for side in ("nw", "se") if look and look.get(side)},
               "haze": list(look["haze"]) if look and look.get("haze") else None,
               "pit_glow": pit_glow(cam) if look and look.get("pit") else None}, f)

scene.render.filepath = os.path.abspath(args.out)
if not args.no_render:
    bpy.ops.render.render(write_still=True)
    # The look's sides: the same frame under the light it leans toward at the plate's
    # north-west end and at its sea end.
    look_sun = (tuple(sun.data.color), sun.data.energy,
                tuple(world_bg.inputs[0].default_value) if world_bg else None,
                world_bg.inputs[1].default_value if world_bg else None)
    for side in ("nw", "se"):
        if side_lighting(args.look, side, sun, world_bg, SUN_ENERGY):
            scene.render.filepath = stem + ".%s.png" % side
            bpy.ops.render.render(write_still=True)
            sun.data.color, sun.data.energy = look_sun[0], look_sun[1]
            if world_bg:
                world_bg.inputs[0].default_value, world_bg.inputs[1].default_value = look_sun[2], look_sun[3]
        elif os.path.exists(stem + ".%s.png" % side):
            os.remove(stem + ".%s.png" % side)
    scene.render.filepath = os.path.abspath(args.out)          # the layout and probe take its name


def px(p):
    v = world_to_camera_view(scene, cam, mathutils.Vector(p))
    return [round(v.x * res_x, 1), round((1.0 - v.y) * res_y, 1)]


probe = {"res": [res_x, res_y], "tops": [], "walls": []}
for mat, pts in info["top_probes"].items():
    if pts:
        probe["tops"].append({"mat": mat, "target": "#" + TOP_HEX[mat], "albedo": list(PALETTE[mat]),
                              "px": [px((x, y, info["z_top"])) for x, y in pts]})
for group in (info["land"], info["sea"]):
    if not group:
        continue
    front = max(group, key=lambda c: (c[1], -abs(c[0])))
    for label, (x, y), levels in front_wall_columns(info, front):
        for i, (mat, kind) in enumerate(info["bands"]):
            if levels[i] - levels[i + 1] < 0.02:
                continue                      # empty here
            z = (levels[i] + levels[i + 1]) / 2.0
            probe["walls"].append({"cell": list(front), "wall": label, "band": i, "mat": mat,
                                   "px": px((x, y, z))})
probe["labels"] = [{"label": label, "px": px(p)} for label, p in items]
with open(os.path.splitext(scene.render.filepath)[0] + ".probe.json", "w") as fh:
    json.dump(probe, fh, indent=1)


# Footprints for check_layout.py: the plate's top faces by material, the pits cut into it,
# each building's outline (a list of convex hulls: one per blockout shape, one per grounded
# part of a game building) and every upward face of the roads, railway, bridges and pier
# (ribbons curve, so they are not convex).
layout = {"plate": [], "pits": info["pits"], "buildings": footprints(placed, info["z_top"]), "infra": {},
          "ends": [list(p) for p in ENDS]}
me = plate.data
for poly in me.polygons:
    vs = [plate.matrix_world @ me.vertices[i].co for i in poly.vertices]
    if all(abs(v.z - info["z_top"]) < 1e-4 for v in vs):
        layout["plate"].append([plate.material_slots[poly.material_index].name, [[v.x, v.y] for v in vs]])
for col_name, key in (("CAPSULE_buildings", "buildings"), ("CAPSULE_infra", "infra")):
    col = bpy.data.collections.get(col_name)
    for ob in (col.objects if col else []):
        mw = ob.matrix_world
        if key == "buildings":
            layout[key][ob.name] = [xy_hull([((mw @ v.co).x, (mw @ v.co).y) for v in ob.data.vertices])]
        else:
            layout[key][ob.name] = [[[(mw @ ob.data.vertices[i].co).x, (mw @ ob.data.vertices[i].co).y]
                                     for i in poly.vertices] for poly in ob.data.polygons if poly.normal.z > 0.5]
with open(os.path.splitext(scene.render.filepath)[0] + ".layout.json", "w") as fh:
    json.dump(layout, fh)

if args.save:
    bpy.ops.wm.save_as_mainfile(filepath=os.path.abspath(args.save))
if args.no_render:
    print("LAYOUT ONLY", os.path.abspath(args.out))
    raise SystemExit(0)


def override_pass(suffix, material):
    """Render the frame again with every material replaced, no ink, under the Standard view
    (AgX would compress the range the print pass reads)."""
    vl = scene.view_layers[0]
    vt = scene.view_settings.view_transform
    scene.view_settings.view_transform = 'Standard'
    vl.material_override = material
    scene.render.use_freestyle = False
    scene.render.filepath = os.path.splitext(os.path.abspath(args.out))[0] + suffix
    bpy.ops.render.render(write_still=True)
    vl.material_override = None
    scene.render.use_freestyle = True
    scene.view_settings.view_transform = vt


def shade_material():
    """Emission = the face's dot product with the sun, mapped from -1..1 to 0.04..1: the
    game's shading mask (render_sprite.py), aimed at the capsule's sun."""
    mat = bpy.data.materials.new("_capsule_shade")
    mat.use_nodes = True
    nt = mat.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    geo = nt.nodes.new("ShaderNodeNewGeometry")
    dot = nt.nodes.new("ShaderNodeVectorMath")
    dot.operation = 'DOT_PRODUCT'
    dot.inputs[1].default_value = tuple(SUN_DIR)
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
    return mat


def lit_material():
    """Plain white diffuse, for the sun-only pass that finds cast shadows."""
    mat = bpy.data.materials.new("_capsule_lit")
    mat.use_nodes = True
    b = mat.node_tree.nodes.get("Principled BSDF")
    b.inputs["Base Color"].default_value = (1, 1, 1, 1)
    b.inputs["Roughness"].default_value = 1.0
    if "Specular IOR Level" in b.inputs:
        b.inputs["Specular IOR Level"].default_value = 0.0
    return mat


# Shading mask: how far each face turns from the sun. The print pass stipples by it.
override_pass(".shade.png", shade_material())
# Shadow pass: the sun alone, with shadows, on white. Black where the sun cannot reach, so
# the print can band cast shadows with dots too (finish_render.py --shadows).
bg = scene.world.node_tree.nodes.get("Background") if scene.world else None
if bg:
    bg.inputs[1].default_value = 0.0
pools_off()
sun.data.color = (1.0, 1.0, 1.0)
sun.data.energy = math.pi                    # a face square to the sun renders 1.0
sun.data.use_shadow = True
sun.data.angle = math.radians(0.3)
if hasattr(scene.eevee, "use_shadows"):
    scene.eevee.use_shadows = True
override_pass(".shadow.png", lit_material())
sun.data.use_shadow = False
sun.data.energy = SUN_ENERGY

# Glow pass: the look's light sources alone, for the print's bloom. It blacks every material,
# which the water pass below rewrites anyway.
if look and look["glow"] > 0:
    glow_pass(stem + ".glow.png", sun, bg)
elif os.path.exists(stem + ".glow.png"):
    os.remove(stem + ".glow.png")

# Water mask: a second, unlit pass with every water material white and everything else
# black, so the print pass can keep water free of stipple. Run after saving: it rewrites
# the materials and turns the lights and ink off.
water = {"map_sea", "map_shelf", "map_river"}
scene.render.use_freestyle = False
scene.view_settings.view_transform = 'Standard'
sun.data.energy = 0.0
bg = scene.world.node_tree.nodes.get("Background") if scene.world else None
if bg:
    bg.inputs[1].default_value = 0.0
for mt in bpy.data.materials:
    # Emission-built materials (the icon car's toon shading) glow on their own: dark them too.
    for n in (mt.node_tree.nodes if mt.use_nodes else []):
        if n.type == 'EMISSION':
            n.inputs["Strength"].default_value = 0.0
    b = mt.node_tree.nodes.get("Principled BSDF") if mt.use_nodes else None
    if b is None:
        continue
    b.inputs["Base Color"].default_value = (0, 0, 0, 1)
    b.inputs["Emission Color"].default_value = (1, 1, 1, 1)
    b.inputs["Emission Strength"].default_value = 1.0 if mt.name in water else 0.0
scene.render.filepath = os.path.splitext(os.path.abspath(args.out))[0] + ".water.png"
bpy.ops.render.render(write_still=True)

# Plate pass: the plate alone, for its alpha. Its outline is where the heavy line goes.
for col in bpy.data.collections:
    if col.name.startswith("CAP_") or col.name in ("CAPSULE_buildings", "CAPSULE_infra"):
        col.hide_render = True
        for ob in col.objects:
            ob.hide_render = True
scene.render.filepath = os.path.splitext(os.path.abspath(args.out))[0] + ".plate.png"
bpy.ops.render.render(write_still=True)
print("RENDERED", os.path.abspath(args.out))
