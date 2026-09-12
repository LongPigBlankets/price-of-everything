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
    """Owner 2026-09-10 (v2): 'more lobes at the base and taller in the middle'. A wide
    skirt of five to seven short splayed lobes around a squat root, then ONE tall central
    tongue (orange body with a yellow core tongue in front) reaching about two and a half
    times the skirt's height."""
    setup_batch_rig()
    col = open_collection("ICON_flame_%d" % seed)
    K = Kit(col)
    body = P("flame_body", FLAME_BODY); core = P("flame_core", FLAME_CORE); root = P("flame_root", FLAME_ROOT)
    rng = random.Random(500 + seed)
    # root: a wide squat dark-orange bulb the skirt rises from
    lathe(K, "root", (0, 0, 0), [(0.0, 0.55), (0.10, 0.62), (0.26, 0.52), (0.38, 0.28), (0.44, 0.0)], root, segments=28, levels=2)
    # the skirt: short fat lobes splayed OUTWARD from the axis
    n = rng.randint(5, 7)
    for i in range(n):
        ang = 2 * math.pi * i / n + rng.uniform(-0.3, 0.3)
        rr = rng.uniform(0.28, 0.42)
        base = (rr * math.cos(ang), rr * math.sin(ang), 0.06)
        h = rng.uniform(0.5, 1.1)
        w = rng.uniform(0.24, 0.34)
        splay = rng.uniform(14, 30)
        lean = (splay * math.cos(ang), -splay * math.sin(ang))
        _tongue(K, "lobe%d" % i, base, h, w, lean, body, seed * 10 + i)
    # the middle: one tall orange tongue, a yellow core tongue just in front of it (-y = camera side)
    mid_lean = (rng.uniform(-6, 6), rng.uniform(-4, 4))
    hm = rng.uniform(2.0, 2.5)
    _tongue(K, "mid", (0.0, 0.0, 0.10), hm, 0.34, mid_lean, body, seed * 10 + 8)
    # the camera sits at (+1,-1,+1): the core is pushed that way so it shows on the body
    _tongue(K, "core", (0.17, -0.17, 0.16), hm * rng.uniform(0.62, 0.72), 0.21,
            (mid_lean[0] * 0.8, mid_lean[1] * 0.8), core, seed * 10 + 9)
    return {"objects": len(col.objects)}


for _seed in range(4):
    exec("def build_flame_%d():\n    return _flame(%d)\n" % (_seed, _seed))
