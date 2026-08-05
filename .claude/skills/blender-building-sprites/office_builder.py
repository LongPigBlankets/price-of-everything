"""Generic L-shaped office block — filler massing for the loading-scene street.

Four VARIANTS (not levels): floors, wing lengths and mirroring differ, so a street can
carry several without reading as copies. Deliberately quieter than the industrial
builders — pale walls, regular window grid, flat parapet roof, one brick accent at the
entrance — offices are the supporting cast, not the show.

Follows the builder contract: rebuilds BLDG_office from scratch each call, hides other
BLDG_* collections, all parameters per-variant in VARIANTS. Uses the sprite kit's
palette roles and window assembly (exec sprite_kit.py into this namespace first).
"""
import bpy

VARIANTS = {                     # owner 2026-08-05: two three-floor, two four-floor
    1: dict(floors=3, wa=3.2, wb=2.0, depth=1.15, mirror=False),
    2: dict(floors=3, wa=2.6, wb=2.4, depth=1.15, mirror=True),
    3: dict(floors=4, wa=4.0, wb=1.6, depth=1.25, mirror=False),
    4: dict(floors=4, wa=3.0, wb=2.0, depth=1.10, mirror=True),
}

FLOOR_H = 0.62
PARAPET = 0.10
EPS = 0.015


def build_office(variant: int = 1) -> dict:
    p = VARIANTS[variant]
    for other in bpy.data.collections:
        if other.name.startswith("BLDG_") and other.name != "BLDG_office":
            other.hide_render = True
            other.hide_viewport = True
    K = Kit(open_collection("BLDG_office"))

    floors, wa, wb, d = p["floors"], p["wa"], p["wb"], p["depth"]
    h = floors * FLOOR_H
    sgn = -1.0 if p["mirror"] else 1.0

    # Wing A: long bar along X, street face at y=0 (front). Wing B: runs back (+Y)
    # from one end — the L. Mirroring swaps which end carries wing B.
    ax0, ax1 = -wa / 2, wa / 2
    bx0 = (ax1 - d) if sgn > 0 else ax0
    bx1 = (ax1) if sgn > 0 else (ax0 + d)

    K.box("wing_a", (ax0 + ax1) / 2, d / 2, h / 2, wa, d, h, K.mat("chalk"))
    K.box("wing_b", (bx0 + bx1) / 2, d + wb / 2, h / 2, d, wb, h, K.mat("chalk"))
    # Junction seam: freestyle cannot ink face intersections (rule 3).
    K.seam("seam_ab", bx0 + (0.016 if sgn > 0 else d - 0.016), d, h / 2, h / 2, axis='Z')

    # Flat roof + parapet lip, proud by EPS so the edge takes ink.
    for name, cx, cy, sx, sy in (
            ("roof_a", (ax0 + ax1) / 2, d / 2, wa, d),
            ("roof_b", (bx0 + bx1) / 2, d + wb / 2, d, wb)):
        K.box(name, cx, cy, h + 0.02, sx - 0.10, sy - 0.10, 0.04, K.mat("deck"))
        K.box(name + "_lip", cx, cy, h + 0.05, sx + EPS, sy + EPS, 0.06, K.mat("chalk"))

    # Street-face window grid: one row per floor along wing A, plus wing B's west face.
    win_w, win_h = 0.34, 0.36
    for f in range(floors):
        zc = f * FLOOR_H + FLOOR_H * 0.55
        n = max(2, int(wa / 0.62))
        for i in range(n):
            xc = ax0 + (i + 0.5) * wa / n
            if f == 0 and abs(xc) < 0.45:      # ground floor entrance bay stays clear
                continue
            K.window("wa_f%d_%d" % (f, i), "-Y", (xc, 0.0, zc), win_w, win_h, 1, 1)
        for j in range(max(1, int(wb / 0.70))):
            yc = d + (j + 0.5) * wb / max(1, int(wb / 0.70))
            K.window("wb_f%d_%d" % (f, j), "-X" if sgn > 0 else "+X",
                     ((bx0 if sgn > 0 else bx1), yc, zc), win_w, win_h, 1, 1)

    # Entrance: the factory's personnel door verbatim (0.34 x 0.76 flat darkmetal
    # panel, factory_builder.py:291) — the Kit's ribbed door at 0.44 x 0.72 read
    # squat and misshapen at this scale. Brick surround stays the one warm accent.
    K.box("door_frame", 0.0, 0.012, 0.42, 0.50, 0.05, 0.84, K.mat("wall_brick"))
    K.box("door", 0.0, -EPS, 0.38, 0.34, 0.05, 0.76, K.mat("darkmetal"))

    print("bbox world %.2f x %.2f x %.2f" % (wa, d + wb, h + 0.08))
    return {"variant": variant, "objects": len(K.col.objects)}
