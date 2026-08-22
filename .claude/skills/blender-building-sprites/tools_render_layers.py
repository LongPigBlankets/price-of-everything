"""Render the film's FIRST FRAME as separate, stackable layers.

    blender --background --factory-startup --python tools_render_layers.py

The loading screen opens on the film's opening composition assembling itself — sky, then
the far city, then the street, then the props — and only starts the video once the build
is done. Those plates were being faked from the finished frame; this renders them properly.

WHAT "IN LAYERS" HAS TO MEAN. Each layer is rendered with ONLY its own collection visible to
the camera, on a transparent background, so it is a cutout: the pixels its objects cover, and
alpha everywhere else. Stack them back to front and you have the frame; stop early and you
have the frame partly built. That is the whole trick, and it is why the layers cannot be made
by masking the finished picture — a cutout of the trees does not tell you what is behind them.

Excluded objects also stop CASTING for the pass, which is the difference between a build-up
and a lighting error: a building that has not arrived yet must not already be laying its
shadow across the road. (loading_scene._show_only_load keeps excluded objects as shadow
casters on purpose — right for its own three-pass isolation, wrong here.)

Passes and framing are the film's, not new ones: the same three renders per layer
(colour / geometric wall mask / ground mask), the same wide 2400x1080 sensor-45 camera at
FILM_START_X, so a stitched layer lands pixel-on-pixel with the shipped film's first frame.
film_layers_stitch.py then applies the film's own stipple and shading and writes RGBA.

Costs a scene build (~16 min) plus three renders a layer. Output goes to
renders/loading/layers_frame0/.
"""
import os
import sys

import bpy
import mathutils

B = "C:/Users/urigi/price-of-everything/.claude/skills/blender-building-sprites/"
OUT = B + "renders/loading/layers_frame0/"

# Back to front, as PREDICATES over collection names — the buildings are one collection each
# (LOAD_bldg_off_a, LOAD_bldg_fac_a, ... 21 of them) rather than a single group, which is only
# visible once the scene is standing.
#
# Two plates are not rendered here. The SKY, because the film's colour pass hides the sky plane
# and the vivid sky is composited in post (AgX crushes the emission bands), so it comes from
# that same post step. And the LAST plate, which is the film's own first frame: a per-layer
# render cannot carry the shadows the buildings cast on a road that is in a different layer, so
# the sequence resolves onto the truth rather than onto an approximation of it. That also makes
# the props their own step, arriving with the shading, which is what "trees, cars and
# decoration" should look like landing.
LAYERS = [
    ("02_city", lambda n: n == "LOAD_city"),
    ("03_street", lambda n: n == "LOAD_street"),
    ("04_buildings", lambda n: n.startswith("LOAD_bldg")),
]

# loading_scene.py hardcodes the author's Mac asset root and pulls sprite_kit.py and the
# builders from it. On this machine the kit lives in the skill directory itself, so the root
# is rewritten in the SOURCE before it runs — patching the namespace afterwards is too late,
# the sub-execs have already fired.
_MAC_ROOT = "/Users/crisu/Price of Everything/blender-assets/"
ns = {}
exec(open(B + "loading_scene.py").read().replace(_MAC_ROOT, B), ns)

get_scene = ns["get_scene"]
build_film_scene = ns["build_film_scene"]
_show_only_load = ns["_show_only_load"]
_geo_mask_override = ns["_geo_mask_override"]
_light_mask_material = ns["_light_mask_material"]
place_vehicles = ns["place_vehicles"]
FILM_RES = ns["FILM_RES"]
FILM_SENSOR = ns["FILM_SENSOR"]
FILM_SHIFT_Y = ns["FILM_SHIFT_Y"]
FILM_START_X = ns["FILM_START_X"]
CAM_X = ns["CAM_X"]


def _isolate(pred):
    """Only the matching collections draw AND only they cast. See the module docstring."""
    _show_only_load(pred)
    for c in bpy.data.collections:
        if not c.name.startswith("LOAD_"):
            continue
        included = bool(pred(c.name))
        for ob in c.objects:
            ob.visible_shadow = included


def render_layer(tag, pred, geo_mat):
    sc = get_scene()
    cam = bpy.data.objects["LoadCam"]
    sun = bpy.data.objects["LoadSun"]
    wbg = sc.world.node_tree.nodes.get("Background")
    vl = sc.view_layers[0]
    ov = _light_mask_material()
    sky_objs = list(bpy.data.collections["LOAD_sky"].objects)

    # colour: flat (sun off, warm ambient), sky plane hidden — exactly the film's pass.
    _isolate(pred)
    for ob in sky_objs:
        ob.hide_render = True
    sun.data.energy = 0.0
    wbg.inputs[0].default_value = (1.0, 0.972, 0.918, 1.0)
    wbg.inputs[1].default_value = 1.216
    sc.render.filepath = os.path.join(OUT, tag)
    bpy.ops.render.render(write_still=True)
    sun.data.energy = 3.6
    wbg.inputs[0].default_value = (1.0, 1.0, 1.0, 1.0)
    wbg.inputs[1].default_value = 0.45

    # geo: orientation bands for the walls.
    sc.render.use_freestyle = False
    prev_vt = sc.view_settings.view_transform
    vl.material_override = geo_mat
    sc.view_settings.view_transform = 'Standard'
    sc.render.filepath = os.path.join(OUT, tag + "_geo")
    bpy.ops.render.render(write_still=True)
    sc.view_settings.view_transform = prev_vt

    # ground: only meaningful for the layer that owns the street, but rendered for every
    # layer so the stitch reads the same three files each time and never special-cases.
    street = bpy.data.collections["LOAD_street"]
    if pred("LOAD_street"):
        for ob in street.objects:
            ob.visible_camera = True
            ob.is_holdout = False
        for c in bpy.data.collections:
            if c.name.startswith("LOAD_") and c is not street and pred(c.name):
                for ob in c.objects:
                    ob.visible_camera = True
                    ob.is_holdout = True   # occlude + cut alpha, keep casting
    vl.material_override = ov
    sc.render.filepath = os.path.join(OUT, tag + "_gnd")
    bpy.ops.render.render(write_still=True)
    vl.material_override = None
    sc.render.use_freestyle = True

    for ob in sky_objs:
        ob.hide_render = False
    print("LAYER_DONE %s" % tag, flush=True)


def main():
    os.makedirs(OUT, exist_ok=True)
    print("LAYERS_BUILD_START", flush=True)
    build_film_scene(detail=1)
    sc = get_scene()
    cam = bpy.data.objects["LoadCam"]
    sc.render.resolution_x, sc.render.resolution_y = FILM_RES
    cam.data.sensor_width = FILM_SENSOR
    cam.data.shift_y = FILM_SHIFT_Y
    fs = sc.view_layers[0].freestyle_settings
    k = FILM_RES[1] / 1080.0
    fs.linesets["ink"].linestyle.thickness = 2.4 * k
    fs.linesets["contour"].linestyle.thickness = 7.0 * k
    if "ink_fine" in fs.linesets:
        fs.linesets["ink_fine"].linestyle.thickness = 1.05 * k
    cam.location.x = FILM_START_X
    place_vehicles(advance=FILM_START_X - CAM_X, cam_x=FILM_START_X)

    for c in bpy.data.collections:
        if c.name.startswith("LOAD_"):
            print("LAYER_COLLECTION %s %d objects" % (c.name, len(c.objects)), flush=True)

    sun = bpy.data.objects["LoadSun"]
    to_sun = (sun.matrix_world.to_3x3() @ mathutils.Vector((0, 0, 1))).normalized()
    geo = _geo_mask_override(to_sun)
    for tag, pred in LAYERS:
        render_layer(tag, pred, geo)
    print("LAYERS_ALL_DONE", flush=True)


main()
