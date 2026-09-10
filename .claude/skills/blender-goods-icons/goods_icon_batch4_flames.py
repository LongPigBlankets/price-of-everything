"""FX sprites, batch 4 (2026-09-10): FLAME LICKS for the supply-chain view - furnace mouths and
the refinery flare. Owner: 'replace the orange teardrop with actual fire in the style we've
been using'. A lick is a cluster of three to five tapered tongues at different heights and
leans, orange bodies with a yellow core tongue and a deep-orange root, lathed under subsurf so
the silhouettes are smooth, inked by Freestyle on every tongue, outer contour from the export.
Four seeds; the runtime cycles them per anchor with jitter so no two fires flicker alike.

Run AFTER sprite_kit.py, goods_icon_kit.py, goods_icon_batch2.py (P/toon5, setup_batch_rig,
lathe come from those).
"""
import bpy, math, random
from mathutils import Vector

FLAME_BODY = (0.95, 0.42, 0.06)
FLAME_CORE = (1.00, 0.86, 0.30)
FLAME_ROOT = (0.62, 0.14, 0.03)


def _tongue(K, name, base, h, w, lean, mat, seed):
    """One tongue of flame: a revolved teardrop that tapers to a point, then tilted."""
    rng = random.Random(seed)
    # profile (z, r): fat low, tapering to the tip with a slight waist so it licks
    prof = [(0.00, w * 0.55), (h * 0.12, w), (h * 0.35, w * 0.92), (h * 0.55, w * 0.62),
            (h * 0.75, w * 0.36), (h * 0.90, w * 0.16), (h, 0.0)]
    ob = lathe(K, name, (0, 0, 0), prof, mat, segments=24, levels=2, cap_bottom=True, cap_top=False)
    ob.rotation_euler = (math.radians(lean[1]), math.radians(lean[0]), 0.0)
    ob.location = Vector(base)
    return ob


def _flame(seed: int):
    setup_batch_rig()
    col = open_collection("ICON_flame_%d" % seed)
    K = Kit(col)
    body = P("flame_body", FLAME_BODY); core = P("flame_core", FLAME_CORE); root = P("flame_root", FLAME_ROOT)
    rng = random.Random(500 + seed)
    # root: a squat dark-orange bulb the tongues rise from
    lathe(K, "root", (0, 0, 0), [(0.0, 0.42), (0.10, 0.50), (0.28, 0.42), (0.40, 0.22), (0.46, 0.0)], root, segments=24, levels=2)
    n = rng.randint(3, 5)
    for i in range(n):
        ang = 2 * math.pi * i / n + rng.uniform(-0.4, 0.4)
        rr = rng.uniform(0.10, 0.30)
        base = (rr * math.cos(ang), rr * math.sin(ang), 0.08)
        h = rng.uniform(1.0, 1.9)
        w = rng.uniform(0.20, 0.34)
        lean = (rng.uniform(-22, 22), rng.uniform(-14, 14))
        _tongue(K, "tongue%d" % i, base, h, w, lean, body, seed * 10 + i)
    # the core: one tall yellow tongue in the middle, slightly inside the bodies
    _tongue(K, "core", (0.0, 0.0, 0.12), rng.uniform(1.2, 1.6), 0.17, (rng.uniform(-8, 8), rng.uniform(-6, 6)), core, seed * 10 + 9)
    return {"objects": len(col.objects)}


for _seed in range(4):
    exec("def build_flame_%d():\n    return _flame(%d)\n" % (_seed, _seed))
