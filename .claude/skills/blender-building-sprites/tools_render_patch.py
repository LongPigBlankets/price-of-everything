"""Re-render a REGION of a few film frames, to repair a fault without redoing the film.

    blender --background <file>.blend --python tools_render_patch.py -- I0 I1 [X0 X1 Y0 Y1]

X0..Y1 are Blender border fractions of the 2400-wide render (Y measured from the BOTTOM);
they default to the left-hand strip the construction site occupies in the opening frames.

WHY A REGION. A fault in one building costs one building's pixels, not the frame's. The
camera moves every frame, so the fix genuinely has to be re-rendered per frame — but only
where it lands. The rest of each frame is already correct in the shipped film and is far
better taken from there than re-rendered: identical by construction, and free.

`use_crop_to_border` stays FALSE on purpose. The output must keep full frame dimensions so
film_stitch's post lands on the same pixels it would have — its stipple lattice is positional
and its shading bands are fixed cuts, both per-pixel, so a partial frame shades exactly as the
whole one does INSIDE the border. Outside it the passes are empty and the post is meaningless;
that region is never read.

The scene build is the fixed cost (~16 min) and does not shrink with the border, so this is
worth doing for a handful of frames, not for one.
"""
import os
import sys

import bpy
import mathutils

_MAC_ROOT = "/Users/crisu/Price of Everything/blender-assets/"
B = os.environ.get("POE_BLENDER_ASSETS",
                   os.path.dirname(os.path.abspath(__file__)).replace("\\", "/") + "/")

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
parts = " ".join(argv).split()
if len(parts) < 2:
    raise SystemExit("tools_render_patch: need a frame range, e.g. `-- 0 18`")
i0, i1 = int(parts[0]), int(parts[1])
# Left strip, full height up to 0.72. Covers the construction site across frames 0-17: it
# starts at the left edge and slides further left as the camera passes it, so frame 0 bounds
# its rightmost extent, and the margin here is several times the frame-to-frame step.
X0, X1, Y0, Y1 = (0.09, 0.47, 0.0, 0.72)
if len(parts) >= 6:
    X0, X1, Y0, Y1 = [float(v) for v in parts[2:6]]
print("PATCH_RANGE", i0, i1, "border", X0, X1, Y0, Y1, flush=True)

ns = {}
exec(open(B + "loading_scene.py").read().replace(_MAC_ROOT, B), ns)

get_scene = ns["get_scene"]
build_film_scene = ns["build_film_scene"]
render_film_frame = ns["render_film_frame"]
_geo_mask_override = ns["_geo_mask_override"]
FILM_DIR = ns["FILM_DIR"]
FILM_START_X = ns["FILM_START_X"]
FILM_END_X = ns["FILM_END_X"]
FILM_STEP = ns["FILM_STEP"]

half = FILM_START_X + (FILM_END_X - FILM_START_X) * 0.5
if FILM_START_X + i1 * FILM_STEP >= half:
    raise SystemExit("tools_render_patch: range crosses the city LOD flip; use the chunk tool")

print("PATCH_BUILD_START", flush=True)
build_film_scene(detail=1)

sc = get_scene()
sc.render.use_border = True
sc.render.use_crop_to_border = False
sc.render.border_min_x, sc.render.border_max_x = X0, X1
sc.render.border_min_y, sc.render.border_max_y = Y0, Y1

to_sun = (bpy.data.objects["LoadSun"].matrix_world.to_3x3()
          @ mathutils.Vector((0, 0, 1))).normalized()
geo = _geo_mask_override(to_sun)

out_dir = os.path.join(FILM_DIR, "_patch")
os.makedirs(out_dir, exist_ok=True)
for idx in range(i0, i1):
    render_film_frame(out_dir, idx, FILM_START_X + idx * FILM_STEP, geo_mat=geo)
    print("PATCH_FRAME", idx, flush=True)
print("PATCH_DONE", i1 - i0, out_dir, flush=True)
