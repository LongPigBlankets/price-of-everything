"""FX sprites, batch 3 (2026-09-10): SMOKE and STEAM puff variations for the supply-chain
view's chimney plumes. The runtime (`scripts/empire_fx.gd`) keeps the motion (drift, growth,
fade, spin, three staggered puffs per stack); Blender supplies the LOOK - a cloud of overlapping
spheres in the house toon style, Freestyle ink on every sphere's silhouette so the cloud
scallops, the 2D outer contour and the shadow-step halftone from the export.

Two colourways (owner): smoke = medium grey with darker patches; steam = light grey with white
tinges. Five seeds each. Rendered at 1024, exported at 256 (they are drawn 20-60 px tall).

Run AFTER sprite_kit.py, goods_icon_kit.py and goods_icon_batch2.py (uses P/toon5 + setup_batch_rig).
"""
import bpy, math, random
from mathutils import Vector

PUFF_SMOKE = ((0.20, 0.195, 0.19), (0.10, 0.095, 0.095))
PUFF_STEAM = ((0.90, 0.92, 0.93), (1.0, 1.0, 1.0))


def _puff(kind: str, seed: int):
    setup_batch_rig()
    col = open_collection("ICON_puff_%s_%d" % (kind, seed))
    K = Kit(col)
    base_rgb, patch_rgb = PUFF_SMOKE if kind == "smoke" else PUFF_STEAM
    base = P("puff_%s_base" % kind, base_rgb)
    patch = P("puff_%s_patch" % kind, patch_rgb)
    rng = random.Random(1000 + seed)
    # a cloud: one big sphere, a ring of medium ones around its upper half, small ones in
    # the gaps - flattened a little so it reads as a puff rising, not a ball
    spheres = [(Vector((0, 0, 0)), 1.00)]
    n = rng.randint(5, 7)
    for i in range(n):
        ang = 2 * math.pi * i / n + rng.uniform(-0.3, 0.3)
        rr = rng.uniform(0.85, 1.05)
        z = rng.uniform(-0.15, 0.45)
        spheres.append((Vector((rr * math.cos(ang), rr * math.sin(ang), z)), rng.uniform(0.48, 0.70)))
    for i in range(rng.randint(2, 4)):
        ang = rng.uniform(0, 2 * math.pi)
        rr = rng.uniform(1.1, 1.35)
        spheres.append((Vector((rr * math.cos(ang), rr * math.sin(ang), rng.uniform(-0.1, 0.3))), rng.uniform(0.28, 0.42)))
    # two or three PATCH spheres, tucked into the body so they read as tone, not as bumps
    patch_ids = set(rng.sample(range(1, len(spheres)), min(3, len(spheres) - 1)))
    for i, (c, r) in enumerate(spheres):
        m = patch if i in patch_ids else base
        if i in patch_ids:
            c = c * 0.75
            r = r * 0.9
        K.sphere("s%d" % i, c.x, c.y, c.z * 0.85, r, m)
    return {"objects": len(col.objects)}


for _kind in ("smoke", "steam"):
    for _seed in range(5):
        exec("def build_puff_%s_%d():\n    return _puff('%s', %d)\n" % (_kind, _seed, _kind, _seed))
