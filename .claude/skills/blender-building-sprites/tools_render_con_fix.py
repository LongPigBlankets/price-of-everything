"""Measure where con_a's part-built frame is on screen, then re-render exactly those frames.

    blender --background <file>.blend --python tools_render_con_fix.py -- [PAD_PX] [MAX_FRAME]

The first repair guessed the damaged span from eyeballed crops and got it wrong: the
construction site sits at x -6.1 with the camera starting at -13.0 and advancing 0.070 a
frame, so it is on screen for far longer than the dozen frames the crops suggested. The scene
knows the answer exactly — ask it instead of guessing.

Per frame this projects the world bounding boxes of the objects the fix touched (the second
storey: col2 / deck1 / deck2) through the film camera, and renders ONLY while they are in
shot, with a per-frame border around them. A border costs about what it covers, so a tight
one costs very little; the ~16 min scene build is the fixed cost either way.

Writes borders.json beside the frames so the compositor uses the SAME rectangle per frame.
"""
import json
import os
import sys

import bpy
import mathutils
from bpy_extras.object_utils import world_to_camera_view

_MAC_ROOT = "/Users/crisu/Price of Everything/blender-assets/"
B = os.environ.get("POE_BLENDER_ASSETS",
                   os.path.dirname(os.path.abspath(__file__)).replace("\\", "/") + "/")

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
parts = " ".join(argv).split()
PAD = int(parts[0]) if len(parts) > 0 else 90
MAXF = int(parts[1]) if len(parts) > 1 else 1350
# Below this on-screen height the fault is a few pixels of a slab edge and re-rendering the
# frame buys nothing. There are FOUR construction sites on this street — con_a at the opening
# and con_b/c/d at the far end — and the far ones are in shot for hundreds of frames while
# being far too small to read. Patch what can be SEEN, and say what was skipped.
MIN_PX = int(parts[2]) if len(parts) > 2 else 26
# The whole part-built frame, not just the pieces that moved: the repair has to sit inside a
# region that renders coherently, and the frame is one object as far as the eye is concerned.
# NOTE the name collision — storey-1 columns are col<i>_<j> (so the third line is "col2_0"),
# storey-2 columns are col2_<i>_<j>. Matching the prefix "col" takes both, which is what is
# wanted here; anything finer would split the structure in half.
TARGET = ("col", "deck", "panel", "slab", "scaf")

ns = {}
exec(open(B + "loading_scene.py").read().replace(_MAC_ROOT, B), ns)
get_scene = ns["get_scene"]; build_film_scene = ns["build_film_scene"]
render_film_frame = ns["render_film_frame"]; _geo_mask_override = ns["_geo_mask_override"]
FILM_DIR = ns["FILM_DIR"]; FILM_START_X = ns["FILM_START_X"]; FILM_STEP = ns["FILM_STEP"]
FILM_RES = ns["FILM_RES"]; FILM_SENSOR = ns["FILM_SENSOR"]; FILM_SHIFT_Y = ns["FILM_SHIFT_Y"]

print("CON_BUILD_START", flush=True)
build_film_scene(detail=1)

sc = get_scene()
sc.render.resolution_x, sc.render.resolution_y = FILM_RES
cam = bpy.data.objects["LoadCam"]
cam.data.sensor_width = FILM_SENSOR
cam.data.shift_y = FILM_SHIFT_Y

sites = {}
for c in bpy.data.collections:
    if not c.name.startswith("LOAD_bldg_con_"):
        continue
    objs = [ob for ob in c.objects
            if ob.type == 'MESH' and ob.name.split(".")[0].startswith(TARGET)]
    if not objs:
        continue
    pts = []
    for ob in objs:
        m = ob.matrix_world
        pts.extend([m @ mathutils.Vector(cc) for cc in ob.bound_box])
    sites[c.name] = pts
    print("CON_SITE %s  %d objects" % (c.name, len(objs)), flush=True)
if not sites:
    raise SystemExit("no LOAD_bldg_con_* collections")

W, H = FILM_RES


def bbox(pts):
    xs, ys = [], []
    for p in pts:
        c = world_to_camera_view(sc, cam, p)
        if c.z <= 0.0:
            continue
        xs.append(c.x * W); ys.append((1.0 - c.y) * H)
    if not xs:
        return None
    return min(xs), max(xs), min(ys), max(ys)


spans = {}
skipped = {}
for idx in range(MAXF):
    cam.location.x = FILM_START_X + idx * FILM_STEP
    bpy.context.view_layer.update()
    boxes = []
    for nm, pts in sites.items():
        b = bbox(pts)
        if b is None:
            continue
        x0, x1, y0, y1 = b
        if x1 <= 0 or x0 >= W or y1 <= 0 or y0 >= H:
            continue
        if (y1 - y0) < MIN_PX:
            skipped[nm] = skipped.get(nm, 0) + 1
            continue
        boxes.append(b)
    if not boxes:
        continue
    x0 = max(0.0, min(b[0] for b in boxes) - PAD)
    x1 = min(float(W), max(b[1] for b in boxes) + PAD)
    y0 = max(0.0, min(b[2] for b in boxes) - PAD)
    y1 = min(float(H), max(b[3] for b in boxes) + PAD)
    spans[idx] = (x0, x1, y0, y1)

ks = sorted(spans)
if not ks:
    raise SystemExit("nothing on screen above MIN_PX")
for nm, n in sorted(skipped.items()):
    print("CON_SKIPPED %s on screen but under %d px for %d frames" % (nm, MIN_PX, n), flush=True)
runs = []
for k in ks:
    if runs and k == runs[-1][1] + 1:
        runs[-1][1] = k
    else:
        runs.append([k, k])
print("CON_ONSCREEN %d frames in %d run(s): %s"
      % (len(ks), len(runs), ", ".join("%d-%d" % (a, b) for a, b in runs)), flush=True)
area = sum((spans[k][1] - spans[k][0]) * (spans[k][3] - spans[k][2]) for k in ks) / (W * H)
print("CON_COST %.1f full-frame equivalents (%d frames x avg %.1f%% of frame)"
      % (area, len(ks), 100.0 * area / len(ks)), flush=True)
for k in ks[::max(1, len(ks) // 12)]:
    x0, x1, y0, y1 = spans[k]
    print("   f%-5d px x %7.1f..%7.1f  y %7.1f..%7.1f" % (k, x0, x1, y0, y1), flush=True)

out_dir = os.path.join(FILM_DIR, "_patch2")
os.makedirs(out_dir, exist_ok=True)
json.dump({str(k): spans[k] for k in ks}, open(os.path.join(out_dir, "borders.json"), "w"))

to_sun = (bpy.data.objects["LoadSun"].matrix_world.to_3x3()
          @ mathutils.Vector((0, 0, 1))).normalized()
geo = _geo_mask_override(to_sun)
sc.render.use_border = True
sc.render.use_crop_to_border = False
for k in ks:
    x0, x1, y0, y1 = spans[k]
    sc.render.border_min_x, sc.render.border_max_x = x0 / W, x1 / W
    sc.render.border_min_y, sc.render.border_max_y = 1.0 - y1 / H, 1.0 - y0 / H
    render_film_frame(out_dir, k, FILM_START_X + k * FILM_STEP, geo_mat=geo)
    print("CON_FRAME", k, flush=True)
print("CON_DONE", len(ks), out_dir, flush=True)
