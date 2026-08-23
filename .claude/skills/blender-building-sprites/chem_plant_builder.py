# Parametric builder for the Chemical Plant (b_012, `chem_plant`).
# Run AFTER sprite_kit.py:
#   exec(open(".../sprite_kit.py").read())
#   exec(open(".../chem_plant_builder.py").read()); build_chem_plant(2)
#
# BUILDING class on z=0. Built to the owner's reference (2026-08-22): a stepped two-storey
# BACK BUILDING with a clerestory window strip and a roof vent, squat PROCESS TANKS in a grid
# in front of it with an accent band round their lower third, tall thin REACTION COLUMNS with
# loop pipes at the right, pipework tying the three together, all on a stepped slab. The
# accent is LIME — the game's CAT_ELECTRO (#A6E22E) — not the electrolyser's forest green and
# not the power family's mustard.
#
# THE BACK BUILDING GROWS WITH THE TANKS, AND BOTH GROW TO THE LEFT. Levels add a column to
# the tank grid (2 -> 4 -> 6 tanks) and a reaction column (1 -> 2 -> 3); the reaction columns,
# the building's pipe wall and its door are anchored on the right and the plant extends away
# from them, so the services never move and the door keeps its distance from the pipe wall.
# The building is a single storey painted lime below and white above, with a parapet rim and
# fan units along its front roof edge; L3 adds the upper floor (penthouse with a navy
# clerestory strip, its own parapet and vent) and a standalone stack at the building's left.
# This is the owner's explicit instruction for this building and it is the opposite of the
# assembly hall's rule; the difference is that nothing here is built against the building's
# ends, so extending it is physically possible.
#
# ---------------------------------------------------------------------------------------
# 1. THE TANKS ARE SQUAT (h/r 1.8) AND THE COLUMNS ARE SLENDER (h/r 11): the contrast between
#    the two is the silhouette. Tank-to-tank links are SHORT horizontal stubs at mid-height —
#    the reference's grammar — and each row's last tank runs on to its column.
# 2. EVERY COLUMN CARRIES AN INVERTED-U LOOP from its crown back down to the row header: a
#    recycle line, and the one curve in an otherwise rectilinear drawing.
# 3. THE CLERESTORY PANES ARE THE ACCENT ON THE BUILDING — flat lime, not emissive (one
#    emissive per sprite, and this plant has none). Five pipes climb the building's visible
#    +X wall and turn in at the top, as in the reference.
# 4. FRAME FROM PROJECTED EXTREMES (SKILL.md rule 20); the plant fills ~930 px at L3 so its ink
#    weight matches the rest of the set after the shared-scale export.

import math

# Lime, measured on the rendered tank bands against CAT_ELECTRO (#A6E22E = 166,226,46):
#   (0.30, 0.62, 0.045) -> 132,163,61        (0.42, 0.92, 0.03) -> 149,180,76  "too neon"
#   (0.26, 0.52, 0.075) -> 125,154,70 s.55    (0.30, 0.52, 0.12) -> grey mixed in, s<.50
# AgX compresses saturation: pushing green lifts EVERY channel, so the target hue is
# unreachable. Dimming alone kept the chroma (saturation 0.55 vs 0.58) and still read neon;
# what calms it is GREY mixed in — red and blue raised relative to green. Clearly lime beside
# the electrolyser's forest green (68,116,73 as installed) and the power mustard (123,96,27).
PALETTE["lime"] = (0.300, 0.520, 0.120)
PALETTE["lime_lo"] = (0.170, 0.380, 0.025)
ROLES["chem_accent"] = "lime"
ROLES["chem_accent_lo"] = "lime_lo"

CP_LEVELS = {
    1: dict(cols=1, columns=1, upper=False, stack=False),
    2: dict(cols=2, columns=2, upper=False, stack=False),
    3: dict(cols=3, columns=3, upper=True, stack=True),
}

# Process tanks: a grid, `cols` along X by two rows in Y. THE GRID IS ANCHORED ON ITS RIGHT:
# the last tank column, the reaction columns and the building's pipe wall never move, and
# growth adds tank columns on the LEFT. The first version grew to the right, which dragged
# the pipe wall along and left the door stranded at the far end — a building cannot extend
# through the wall its services are on.
TANK_R, TANK_H = 0.72, 1.30
TX_LAST, TPITCH = 0.40, 1.80
ROW_YS = (-1.95, -0.35)
BAND_H = 0.46                      # lime band, lower third
LINK_Z = 0.78                      # tank-to-tank and tank-to-column links

# Reaction columns, one per row and a third behind at L3.
COL_R, COL_H = 0.30, 3.40
COL_GAP = 1.85                     # from the last tank's centre to the column's centre
COL_YS = (-1.95, -0.35, 1.25)

# Back building: x follows the grid; y fixed, set back from the tanks. SINGLE storey, painted
# lime below the split and white above it; the upper floor (penthouse) is L3 only. The door
# and the window beside it are placed from the RIGHT wall, so they stay put as the building
# grows left; new windows and fan units appear on the left.
BY0, BY1 = 1.35, 3.95
BX_PAD_L, BX_PAD_R = 0.95, 1.05
DOOR_FROM_R = 1.50                 # door centre, from the right wall
LOWER_H = 1.90
SPLIT = 1.00                       # lime/white split, above the plinth
PENT_IN_X, PENT_IN_F, PENT_IN_B, PENT_H = 0.45, 0.55, 0.30, 1.30
PARAPET_H, PARAPET_W = 0.16, 0.11
FAN_Y = 0.34                       # fan units along the front roof edge, behind the parapet
FAN_R = 0.20
SLAB_OVER = 1.55                   # slab beyond the outermost tank / column (covers the stack)
PLINTH_H = 0.14                    # the building's raised step
STACK_DX, STACK_DY = -0.36, 1.10   # standalone stack off the building's left wall
STACK_TOP = 5.30


def _extents(p):
    xs = [TX_LAST - (p["cols"] - 1 - i) * TPITCH for i in range(p["cols"])]
    cx = TX_LAST + COL_GAP
    bx0, bx1 = xs[0] - BX_PAD_L, TX_LAST + BX_PAD_R
    sx0, sx1 = xs[0] - SLAB_OVER, cx + 0.75
    sy0, sy1 = ROW_YS[0] - TANK_R - 0.40, BY1 + 0.30
    return xs, cx, (bx0, bx1), (sx0, sx1, sy0, sy1)


def _tank(K, tag, cx, cy):
    shell = K.cyl("t%s" % tag, cx, cy, TANK_H / 2, TANK_R, TANK_H, K.mat("wall_bright"),
                  segments=32)
    K.gloss(shell)
    K.cyl("t%s_band" % tag, cx, cy, BAND_H / 2, TANK_R + 0.012, BAND_H, K.mat("chem_accent"),
          segments=32)
    K.seam("t%s_bs" % tag, cx, cy, BAND_H, TANK_R + 0.02)
    K.seam("t%s_ts" % tag, cx, cy, TANK_H - 0.06, TANK_R + 0.01)
    K.cyl("t%s_lid" % tag, cx, cy, TANK_H + 0.03, TANK_R + 0.025, 0.06, K.mat("gear"), segments=32)
    K.cyl("t%s_noz" % tag, cx, cy, TANK_H + 0.12, 0.10, 0.14, K.mat("pipe"), segments=12)
    K.cyl("t%s_nozcap" % tag, cx, cy, TANK_H + 0.205, 0.12, 0.04, K.mat("gear"), segments=12)


def _column(K, tag, cx, cy, loop_to_x):
    """Slender reaction column: skirt, glossed shell, lime band near the crown, dome cap,
    ladder, and an inverted-U loop from the crown back down to the row header."""
    K.cyl("c%s_skirt" % tag, cx, cy, 0.11, COL_R + 0.035, 0.22, K.mat("scaffold"), segments=24)
    shell = K.cyl("c%s" % tag, cx, cy, 0.22 + (COL_H - 0.22) / 2, COL_R, COL_H - 0.22,
                  K.mat("wall_bright"), segments=24)
    K.gloss(shell)
    for z in (1.10, 2.05):
        K.seam("c%s_s%d" % (tag, int(z * 10)), cx, cy, z, COL_R + 0.01)
    K.cyl("c%s_band" % tag, cx, cy, COL_H - 0.55, COL_R + 0.012, 0.26, K.mat("chem_accent"),
          segments=24)
    K.dome_cap("c%s_cap" % tag, cx, cy, COL_H, COL_R, 0.22, K.mat("wall_bright"), seg=24)
    K.ladder("c%s_lad" % tag, cx + COL_R + 0.02, cy, 0.35, COL_H - 0.15, face="+X", w=0.16,
             mat=K.mat("handrail"))
    K.pipe_run("c%s_loop" % tag,
               [(cx, cy, COL_H + 0.18), (cx, cy, COL_H + 0.55), (loop_to_x, cy, COL_H + 0.55),
                (loop_to_x, cy, LINK_Z + 0.10)], 0.07, K.mat("pipe"))
    K.pipe_run("c%s_side" % tag, [(cx - COL_R - 0.30, cy + 0.18, 0.45),
                                  (cx - COL_R - 0.30, cy + 0.18, 2.30),
                                  (cx - COL_R + 0.02, cy + 0.18, 2.30)], 0.045, K.mat("pipe"))


def _parapet(K, tag, x0, x1, y0, y1, z):
    """Raised rim with a coping course round a flat roof — the assembly head block's."""
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    for t, (bx, by, sx, sy) in {
        "f": (cx, y0 + PARAPET_W / 2, x1 - x0, PARAPET_W), "b": (cx, y1 - PARAPET_W / 2, x1 - x0, PARAPET_W),
        "l": (x0 + PARAPET_W / 2, cy, PARAPET_W, y1 - y0), "r": (x1 - PARAPET_W / 2, cy, PARAPET_W, y1 - y0),
    }.items():
        K.box("par_%s_%s" % (tag, t), bx, by, z + PARAPET_H / 2, sx, sy, PARAPET_H, K.mat("wall_bright"))
        K.box("cop_%s_%s" % (tag, t), bx, by, z + PARAPET_H + 0.02, sx + 0.03, sy + 0.03, 0.04,
              K.mat("slab_cream"))


def _fan_unit(K, tag, cx, cy, z):
    K.cyl("fan%s" % tag, cx, cy, z + 0.09, FAN_R, 0.18, K.mat("gear"), segments=20)
    K.washer("fan%s_ring" % tag, (cx, cy, z + 0.22), (0, 0, 1), FAN_R - 0.06, FAN_R, 0.08,
             K.mat("wall_steel"), seg=20)
    K.cyl("fan%s_hub" % tag, cx, cy, z + 0.21, 0.04, 0.06, K.mat("wall_steel"), segments=10)
    fm = K._fine_mode
    K._fine_mode = True
    for ang in (15.0, 75.0, 135.0):
        K.rotbox("fan%s_b%d" % (tag, int(ang)), cx, cy, z + 0.215, FAN_R * 1.4, 0.035, 0.012,
                 K.mat("wall_steel"), 'Z', ang)
    K._fine_mode = fm


def _building(K, bx0, bx1, upper, stack):
    cx, cy = (bx0 + bx1) / 2, (BY0 + BY1) / 2
    K.box("plinth", cx, cy, PLINTH_H / 2, bx1 - bx0 + 0.50, BY1 - BY0 + 0.50, PLINTH_H,
          K.mat("slab_kerb"))
    # Single storey, painted: lime below the split, white above. Two stacked boxes — their
    # faces share planes but never overlap in z, so they cannot z-fight; Freestyle draws the
    # joint as a line, which reads as the paint line.
    K.box("lower_lime", cx, cy, PLINTH_H + SPLIT / 2, bx1 - bx0, BY1 - BY0, SPLIT,
          K.mat("chem_accent"))
    K.box("lower_white", cx, cy, PLINTH_H + SPLIT + (LOWER_H - SPLIT) / 2, bx1 - bx0, BY1 - BY0,
          LOWER_H - SPLIT, K.mat("wall_bright"))
    rz = PLINTH_H + LOWER_H
    K.box("lower_roof", cx, cy, rz + 0.03, bx1 - bx0 - 0.02, BY1 - BY0 - 0.02, 0.06, K.mat("roof_deck"))
    _parapet(K, "lo", bx0, bx1, BY0, BY1, rz)
    # Door placed from the RIGHT wall, one window between it and that wall, and a series of
    # windows marching LEFT from the door on a 0.85 pitch as far as the building reaches.
    # Window heads sit level with the door head (the facade rule).
    door_h = 0.92
    dx = bx1 - DOOR_FROM_R
    K.door("bdoor", "-Y", (dx, BY0, PLINTH_H + door_h / 2), 0.36, door_h)
    head = PLINTH_H + door_h
    K.window("bw_r", "-Y", (dx + 0.78, BY0, head - 0.25), 0.40, 0.50)
    k, x = 0, dx - 0.85
    while x > bx0 + 0.42:
        K.window("bw%d" % k, "-Y", (x, BY0, head - 0.25), 0.40, 0.50)
        x -= 0.85
        k += 1
    # Fan units along the FRONT roof edge, behind the parapet and clear of the penthouse
    # footprint, placed from the right so growth adds them on the left.
    k, x = 0, bx1 - 0.55
    while x > bx0 + 0.45:
        _fan_unit(K, str(k), x, BY0 + FAN_Y, rz + 0.06)
        x -= 0.90
        k += 1
    # Five pipes up the +X wall, turning into the building at the top; a header at the
    # bottom collects them and runs on to the columns (closed in build()).
    fm = K._fine_mode
    K._fine_mode = True
    ys = [BY0 + 0.45 + i * 0.48 for i in range(5)]
    for i, y in enumerate(ys):
        K.pipe_run("wallpipe%d" % i, [(bx1 + 0.13, y, 0.32), (bx1 + 0.13, y, rz - 0.25),
                                      (bx1 - 0.04, y, rz - 0.25)], 0.045, K.mat("pipe"))
    K._fine_mode = fm
    K.pipe_run("wallhdr", [(bx1 + 0.13, ys[-1] + 0.05, 0.32), (bx1 + 0.13, ys[0] - 0.45, 0.32)],
               0.06, K.mat("pipe"))
    if upper:
        px0, px1 = bx0 + PENT_IN_X, bx1 - PENT_IN_X
        py0, py1 = BY0 + PENT_IN_F, BY1 - PENT_IN_B
        pz0 = rz + 0.06
        K.box("pent", (px0 + px1) / 2, (py0 + py1) / 2, pz0 + PENT_H / 2, px1 - px0, py1 - py0,
              PENT_H, K.mat("wall_bright"))
        K.box("pent_roof", (px0 + px1) / 2, (py0 + py1) / 2, pz0 + PENT_H + 0.03, px1 - px0 - 0.02,
              py1 - py0 - 0.02, 0.06, K.mat("roof_deck"))
        _parapet(K, "up", px0, px1, py0, py1, pz0 + PENT_H)
        K.cyl("vent", px0 + 0.55, (py0 + py1) / 2 + 0.25, pz0 + PENT_H + 0.06 + 0.22, 0.17, 0.44,
              K.mat("gear"), segments=16)
        K.cyl("vent_cap", px0 + 0.55, (py0 + py1) / 2 + 0.25, pz0 + PENT_H + 0.06 + 0.47, 0.20, 0.05,
              K.mat("wall_steel"), segments=16)
        # Clerestory: a strip of NAVY panes along the penthouse front, mullions between.
        n = max(2, int((px1 - px0 - 0.30) / 0.50))
        w = (px1 - px0 - 0.30) / n
        zc = pz0 + PENT_H * 0.55
        K.box("clere_frame", (px0 + px1) / 2, py0 - 0.02, zc, px1 - px0 - 0.22, 0.035, 0.46,
              K.mat("window_frame"))
        for i in range(n):
            K.box("clere%d" % i, px0 + 0.15 + (i + 0.5) * w, py0 - 0.045, zc, w - 0.07, 0.02, 0.36,
                  K.mat("window_glass"))
    if stack:
        # Standalone on the LEFT of the building at ground level: firebox base, stack, collar,
        # and a duct into the building's wall so it is fed by something.
        sx, sy = bx0 + STACK_DX, BY0 + STACK_DY
        K.box("stack_base", sx, sy, 0.30, 0.62, 0.62, 0.60, K.mat("gear"))
        K.box("stack_base_band", sx, sy, 0.16, 0.64, 0.64, 0.12, K.mat("wall_steel"))
        K.cyl("stack", sx, sy, 0.60 + (STACK_TOP - 0.60) / 2, 0.16, STACK_TOP - 0.60, K.mat("stack"),
              segments=20)
        K.washer("stack_collar", (sx, sy, STACK_TOP - 0.12), (0, 0, 1), 0.16, 0.22, 0.16,
                 K.mat("gear"), seg=20)
        K.cyl("stack_mouth", sx, sy, STACK_TOP - 0.01, 0.13, 0.03, K.mat("opening"), segments=20)
        K.pipe_run("stack_duct", [(sx + 0.30, sy, 0.95), (bx0 + 0.05, sy, 0.95)], 0.09, K.mat("pipe"))
    return ys[0] - 0.45


def _frame(p):
    xs, cxc, (bx0, bx1), (sx0, sx1, sy0, sy1) = _extents(p)
    # Highest points: the penthouse parapet (L3) or the lower parapet, and the standalone
    # stack at the building's left, which is the extreme at L3.
    lo_top = PLINTH_H + LOWER_H + PARAPET_H + 0.06
    pts = [(sx0, sy0, -0.1), (sx1, sy0, -0.1), (sx1, sy1, -0.1), (sx0, sy1, -0.1),
           (bx0, BY1, lo_top), (bx1, BY1, lo_top), (bx0, BY0, lo_top),
           (cxc, COL_YS[0], COL_H + 0.7)]
    if p["upper"]:
        top = lo_top + 0.06 + PENT_H + 0.58
        px0, px1, py1 = bx0 + PENT_IN_X, bx1 - PENT_IN_X, BY1 - PENT_IN_B
        pts += [(px0, py1, top), (px1, py1, top), (px0, BY0 + PENT_IN_F, top)]
    if p["stack"]:
        pts.append((bx0 + STACK_DX, BY0 + STACK_DY, STACK_TOP + 0.2))
    cs = [x + y for x, y, z in pts]
    hs = [z - (x - y) / 2.0 for x, y, z in pts]
    c, h = (min(cs) + max(cs)) / 2.0, (min(hs) + max(hs) + 0.10) / 2.0
    return (c / 2.0, c / 2.0, h)


def build_chem_plant(level: int = 2) -> dict:
    p = CP_LEVELS[level]
    xs, cxc, (bx0, bx1), (sx0, sx1, sy0, sy1) = _extents(p)
    setup_rig(target=_frame(p))
    K = Kit(open_collection("BLDG_chem"))

    # Stepped slab: the yard plate, with the building's plinth stepping up off it.
    K.box("slab", (sx0 + sx1) / 2, (sy0 + sy1) / 2, -0.05, sx1 - sx0, sy1 - sy0, 0.10,
          K.mat("yard_pad"))
    K.box("slab_step", (sx0 + cxc + 0.75) / 2, sy0 - 0.20, -0.05, cxc + 0.75 - sx0 - 0.60, 0.40,
          0.10, K.mat("yard_pad")) if False else None

    # Tanks, linked along each row, the last one on to its column.
    for r, ry in enumerate(ROW_YS):
        for i, x in enumerate(xs):
            _tank(K, "%d%d" % (r, i), x, ry)
            if i + 1 < len(xs):
                K.pipe_run("link%d%d" % (r, i), [(x + TANK_R - 0.02, ry, LINK_Z),
                                                 (xs[i + 1] - TANK_R + 0.02, ry, LINK_Z)], 0.06,
                           K.mat("pipe"))
        if r < p["columns"]:
            K.pipe_run("tocol%d" % r, [(xs[-1] + TANK_R - 0.02, ry, LINK_Z),
                                       (cxc - COL_R + 0.02, ry, LINK_Z)], 0.06, K.mat("pipe"))

    # Columns: one per row, the third behind at L3, each looping back to its header.
    for j in range(p["columns"]):
        _column(K, str(j), cxc, COL_YS[j], cxc - COL_R - 0.62)
    if p["columns"] > 2:
        # The third column has no tank row: it is fed from the second's header.
        K.pipe_run("tocol2", [(cxc - COL_R - 0.62, COL_YS[1], LINK_Z + 0.10),
                              (cxc - COL_R - 0.62, COL_YS[2] - 0.05, LINK_Z + 0.10),
                              (cxc - COL_R + 0.02, COL_YS[2] - 0.05, LINK_Z + 0.10)], 0.06,
                   K.mat("pipe"))

    # Back building, and its wall header on to the nearest column.
    hdr_y = _building(K, bx0, bx1, p["upper"], p["stack"])
    near = COL_YS[min(p["columns"], 2) - 1] if p["columns"] < 3 else COL_YS[2]
    K.pipe_run("bld_to_col", [(bx1 + 0.13, hdr_y, 0.32), (cxc - 0.02, hdr_y, 0.32),
                              (cxc - 0.02, near + COL_R + 0.06, 0.32)], 0.06, K.mat("pipe"))

    print("\n".join(K.validate(ground=-0.12)))
    return {"building": "chem_plant", "level": level, "tanks": 2 * p["cols"],
            "columns": p["columns"], "objects": len(K.col.objects)}
