# Parametric builder for the Polymerisation Refinery (b_013, internal_name `poly_plant`).
# Run AFTER sprite_kit.py:
#   exec(open(".../sprite_kit.py").read())
#   exec(open(".../poly_plant_builder.py").read()); build_poly_plant(1)
#
# REWRITE (2026-07-31) to the owner's brief. It shares the petro refinery's vocabulary — white
# flat-roofed masses, cream apron, silver pipework, purple as the only chroma, gloss banding —
# and differs where it matters:
#   * MIXING VATS: external floating-roof tanks. The deck sits down inside the shell and the
#     rim stands proud of it. Nothing on the fuels plant is open-topped.
#   * a WAREHOUSE with its double doors slid open on rolls of white and black mesh — the one
#     thing in either building that reads as FINISHED GOODS rather than plant.
#   * PUMPS scattered at ground level: this plant moves fluid, it does not just store it.
#   * TALL PROCESS TANKS feeding out through overhead pipe.
# It has NO flare, NO bund and NO bullets — those are the petro plant's.
#
# The warehouse doorway is REAL GEOMETRY, not a dark panel: piers + lintel + a back wall,
# leaving an alcove. A painted-on opening cannot show anything standing inside it, and the
# rolls are the point of the building.

import math

POLY_LEVELS = {
    1: dict(vats=2, tanks=2, pumps=3, ext=False, back_tanks=False, bullet=False,
            apron_front=0.0, dado=False, tower=False, bay=False, rank3=False, skid=False,
            flues=((3.05, 3.40, 0.24, 4.20, 0.14, 0.0),)),
    2: dict(vats=2, tanks=2, pumps=0, ext=True, back_tanks=True, bullet=True,
            apron_front=1.00, dado=True, tower=True, bay=False, rank3=False, skid=True,
            # FAR RIGHT, on the ground. Different heights on purpose: a matched pair reads as
            # one object duplicated. Never flamed — a flare belongs to the fuels plant.
            flues=((3.05, 3.20, 0.24, 3.90, 0.14, 0.42),
                   (3.05, 4.70, 0.22, 4.70, 0.13, 0.42))),
    3: dict(vats=2, tanks=2, pumps=0, ext=True, back_tanks=True, bullet=True,
            apron_front=1.00, dado=True, tower=True, bay=True, rank3=True, skid=True,
            flues=((3.05, 3.20, 0.24, 3.90, 0.14, 0.42),
                   (3.05, 4.70, 0.22, 4.70, 0.13, 0.42))),
}

WH_BAY_Y1 = 5.75                            # L3: open-topped bay beyond the flat extension.
WH_BAY_H = 1.75
# Third rank, further back and taller again. Ranks must clear each other in PLAN as well as on
# screen: 0.95 apart with r=0.50 each was an OVERLAP, and two intersecting tanks read as one
# lumpy mass however good the tone separation is.
RANK3 = ((0.95, 5.55, 0.50, 3.30), (5.15, 5.55, 0.44, 2.95))

# The shed is deliberately SMALLER relative to the plant than it was: at 3.60 x 2.10 it was
# the subject and the process equipment was scenery, and it also pushed the sprite past the
# 1024 render frame once the far-right flues were added.
WH = (-2.05, 0.75, 2.90, 1.75, 1.30)        # cx, cy, width(+X), depth(+Y), EAVE height
WH_RISE = 0.55                              # mono-pitch: how much the roof climbs to the back
WH_DOOR_W, WH_DOOR_H, WH_ALCOVE = 1.45, 1.05, 0.90
WH_EXT_Y1 = 3.60                            # L2: shed extended back to here, roof FLAT at the
                                            # pitch's high edge so the two roofs run on as one
# --- mixing vats: floating roof, the plant's signature -------------------------------------
VATS = ((0.95, 1.30, 0.72, 1.05), (3.05, 1.30, 0.62, 0.92))   # cx, cy, r, shell height
# --- tall process tanks: each sits DIRECTLY BEHIND the vat it feeds -------------------------
# The RANKS share x with each other (straight cascades), but the right-hand column no longer
# sits over its vat: at double the spacing that feed becomes an L, which is fine because it
# turns OUTSIDE the other feed's column and so still cannot cross it. What must never drift is
# rank-to-rank alignment — that is what the checks guard.
TANKS = ((0.95, 3.30, 0.50, 2.05), (5.15, 3.30, 0.44, 1.70))   # cx, cy, r, shell top
# L2 back rank: same x as the front rank (a straight cascade, no crossing) and TALLER, because
# 0.95 of extra y buys only 0.39 of screen height on its own.
BACK_TANKS = ((0.95, 4.40, 0.50, 2.68), (5.15, 4.40, 0.44, 2.33))
PUMPS = ((0.30, -0.50), (1.20, -0.50), (2.10, -0.50))
BULLET = (1.50, 3.40, -0.75, 0.38)          # x0, x1, cy, r — laid LEFT-TO-RIGHT, out front
# The corridor the flue lines run down: clear of the vats in front (they reach y 2.02) and the
# process tanks behind (they start at 2.80). Two pipes, stacked, so they read as a pair.
FLUE_LANE_Y = 2.40
FLUE_LANE_Z = (0.94, 0.70)
# LONG front-to-back unit that the flues rise out of. Their bases are sunk into it, which is
# why they carry a z0: at z0=0 the accent skirt would be entirely buried inside the skid and
# the plant would lose the band. L2/L3 only.
SKID = (3.05, 4.10, 0.95, 2.40, 0.50)       # cx, cy, w(+X), d(+Y), h
SKID_TIE_Y = (3.30, 4.40)                   # east tie / west tie, on the tank rows


def build_poly_plant(level: int = 1) -> dict:
    p = POLY_LEVELS[level]
    # WIDER FIELD than the default rig. Three ranks of process tanks put the sprite past 11
    # world units across, and resolution alone does not help — ortho_scale is what sets the
    # field, res only samples it. 14.0 / 1304 keeps px-per-unit at the default 93.1, so the
    # ABSOLUTE-pixel Freestyle ink stays the same weight as every other building once
    # sprite_export normalises this plant's own L3 to 788.
    # Target moved off the shared default too: with the tank ranks spread the composition's
    # centre sits well right of the world origin, and a centred camera is what buys the margin
    # that lets it fit at all. tx+ty is the only part that matters horizontally.
    setup_rig(ortho_scale=14.0, res=1304, target=(0.8, 2.55, 1.9))
    K = Kit(open_collection("BLDG_poly"))

    # ---------------- warehouse: the anchoring mass, with an open doorway ----------------
    wx, wy, ww, wd, wh = WH
    rise = WH_RISE
    x0, x1 = wx - ww / 2, wx + ww / 2
    y0, y1 = wy - wd / 2, wy + wd / 2
    dx0, dx1 = wx - WH_DOOR_W / 2, wx + WH_DOOR_W / 2
    yb = y0 + WH_ALCOVE                                # alcove back wall
    for tag, (bx, by, bw, bd) in {
        "L": ((x0 + dx0) / 2, wy, dx0 - x0, wd),       # left pier, full depth
        "R": ((dx1 + x1) / 2, wy, x1 - dx1, wd),       # right pier, full depth
    }.items():
        K.box("wh_%s" % tag, bx, by, wh / 2, bw, bd, wh, K.mat("wall_bright"))
    # The alcove's back block is DARK. Only its -Y face is ever seen (the piers cover its
    # sides, the roof its top), so one dark box buys a shaded interior for the rolls to read
    # against — white in there and they vanish into the wall behind them.
    K.box("wh_B", wx, (yb + y1) / 2, wh / 2, WH_DOOR_W, y1 - yb, wh, K.mat("wall_grey"))
    K.box("wh_floor", wx, (y0 + yb) / 2, 0.03, WH_DOOR_W, WH_ALCOVE, 0.06, K.mat("yard"))
    K.box("wh_ceil", wx, (y0 + yb) / 2, WH_DOOR_H - 0.03, WH_DOOR_W, WH_ALCOVE, 0.06,
          K.mat("wall_grey"))
    K.box("wh_lintel", wx, (y0 + yb) / 2, (WH_DOOR_H + wh) / 2, WH_DOOR_W, WH_ALCOVE,
          wh - WH_DOOR_H, K.mat("wall_bright"))
    # MONO-PITCH roof, climbing to the back. The gable wedge is solid and in the WALL tone so
    # the wall simply gets taller at the back; the deck is a separate constant-thickness slab
    # laid on its slope, oversized for an eaves overhang and sunk 0.02 in so the two are not
    # coplanar. A parapet ring is deliberately gone — that belongs to a flat roof.
    K.prism("wh_gable", (wx, y0, wh), (0, 1, 0), [(0, 0), (wd, 0), (wd, rise)], ww,
            K.mat("wall_bright"))
    K.prism("wh_roof", (wx, y0 - 0.09, wh - 0.02), (0, 1, 0),
            [(0, 0), (wd + 0.18, rise), (wd + 0.18, rise + 0.10), (0, 0.10)], ww + 0.18,
            K.mat("roof_deck"))
    K.box("wh_fascia", wx, y0 - 0.09, wh + 0.03, ww + 0.18, 0.06, 0.12, K.mat("roof"))
    if p["ext"]:
        # Straight on at the HIGH level: the pitch tops out at wh+rise and the extension's
        # flat roof starts there, so the two read as one roof that stops climbing.
        eh = wh + rise
        ey0, ey1 = y1, WH_EXT_Y1
        K.box("wh2", wx, (ey0 + ey1) / 2, eh / 2, ww, ey1 - ey0, eh, K.mat("wall_bright"))
        K.box("wh2_deck", wx, (ey0 + ey1) / 2, eh + 0.012, ww - 0.02, ey1 - ey0 - 0.02, 0.05,
              K.mat("roof_deck"))
        for tag, (px, py, sx, sy) in {
            "b": (wx, ey1, ww + 0.10, 0.10), "l": (x0, (ey0 + ey1) / 2, 0.10, ey1 - ey0),
            "r": (x1, (ey0 + ey1) / 2, 0.10, ey1 - ey0),
        }.items():
            K.box("wh2_par_%s" % tag, px, py, eh + 0.055, sx, sy, 0.11, K.mat("roof"))
        K.window("wh2_w", "-Y", (x1 - 0.55, ey0, eh - 0.50), 0.30, 0.40, cols=2, rows=2)
    if p["dado"]:
        # Painted stretch along the BOTTOM of the walls. One proud box per mass, because a
        # single band across the whole footprint would paint straight over the doorway.
        dh = 0.26
        dados = [((x0 + dx0) / 2, wy, dx0 - x0, wd), ((dx1 + x1) / 2, wy, x1 - dx1, wd)]
        if p["ext"]:
            dados.append((wx, (y1 + WH_EXT_Y1) / 2, ww, WH_EXT_Y1 - y1))
        if p["bay"]:
            dados.append((wx, (WH_EXT_Y1 + WH_BAY_Y1) / 2, ww, WH_BAY_Y1 - WH_EXT_Y1))
        for di, (bx, by, bw, bd) in enumerate(dados):
            K.box("wh_dado%d" % di, bx, by, dh / 2, bw + 0.03, bd + 0.03, dh, K.mat("accent"))
    if p["bay"]:
        # OPEN TOP: walls only, no deck. What is visible of it is set by the extension's
        # roofline in front — the floor is always hidden, so the rolls go up on a stillage and
        # the crane rides high, which is the part that clears.
        by0, by1, bh = WH_EXT_Y1, WH_BAY_Y1, WH_BAY_H
        for tag, (bx, byc, bsx, bsy) in {
            "l": (x0 + 0.09, (by0 + by1) / 2, 0.18, by1 - by0),
            "r": (x1 - 0.09, (by0 + by1) / 2, 0.18, by1 - by0),
            "b": (wx, by1 - 0.09, ww, 0.18),
        }.items():
            K.box("bay_%s" % tag, bx, byc, bh / 2, bsx, bsy, bh, K.mat("wall_bright"))
            K.box("bay_cope_%s" % tag, bx, byc, bh + 0.04, bsx + 0.05, bsy + 0.05, 0.08,
                  K.mat("roof"))
        K.box("bay_floor", wx, (by0 + by1) / 2, 0.03, ww - 0.30, by1 - by0 - 0.20, 0.06,
              K.mat("yard"))
        # The stillage is HIGH for a reason. Solved from the extension's roofline: at the
        # bay's y, anything below z ~0.79 is behind that roof and invisible, so rolls sitting
        # on the bay floor simply are not there. 0.86 puts both rows in view.
        K.box("bay_stillage", wx + 0.10, (by0 + by1) / 2 + 0.10, 0.43, 1.75, 1.15, 0.86,
              K.mat("wall_grey"))
        K.roll_stack("bayrolls", wx + 0.10, (by0 + by1) / 2 + 0.10,
                     (by0 + by1) / 2 - 0.42, (by0 + by1) / 2 + 0.62, r=0.20, cols=3, rows=2,
                     z0=0.86)
        K.gantry_crane("crane", x0 + 0.42, x1 - 0.42, (by0 + by1) / 2 - 0.25, bh + 0.72)
        # Visibility over the extension roof, solved rather than eyeballed. At a shared screen
        # column the roof's silhouette is its back-top edge, so a point in the bay clears when
        #   0.4082*(bay_y - ext_y) > 0.8165*ext_top - 0.8165*z
        ry = (by0 + by1) / 2 + 0.10
        need_z = (0.8165 * (wh + rise + 0.11) - 0.4082 * (ry - WH_EXT_Y1) * 2.0) / 0.8165
        if 0.86 + 0.20 < need_z:
            print("BAY ROLLS SIT BELOW THE ROOFLINE (need z>%.2f)" % need_z)
    K.box("wh_soffit", wx, y0 + 0.02, WH_DOOR_H, WH_DOOR_W, 0.04, 0.05, K.mat("opening"))
    # The leaves, SLID OPEN across the piers rather than swung: everything in this kit is
    # axis-aligned, and a rotated leaf is the one thing that would break that.
    for si, lx in ((0, dx0 - 0.34), (1, dx1 + 0.34)):
        K.box("wh_leaf%d" % si, lx, y0 - 0.05, WH_DOOR_H / 2, 0.64, 0.07, WH_DOOR_H - 0.06,
              K.mat("door_leaf"))
        for k in range(2):
            K.box("wh_leafrib%d_%d" % (si, k), lx + (k - 0.5) * 0.30, y0 - 0.09,
                  WH_DOOR_H / 2 - 0.03, 0.05, 0.03, WH_DOOR_H - 0.24, K.mat("handrail"))
    K.roll_stack("rolls", wx, wy, y0 + 0.20, yb - 0.05, r=0.18, cols=3, rows=2)
    for b, bxw in enumerate((x0 + 0.42, x1 - 0.42)):
        K.window("wh_w%d" % b, "-Y", (bxw, y0, wh - 0.42), 0.30, 0.40, cols=2, rows=2)

    # ---------------- mixing vats: floating roof ----------------
    for i in range(p["vats"]):
        vx, vy, vr, vh = VATS[i]
        # Purple is the pair's ONLY chroma so it stays sparing: one waistband, on the
        # bigger vat, plus the flue skirt. Two banded vats and it stops being an accent.
        K.float_tank("vat%d" % i, vx, vy, vr, vh, drop=vh * 0.38, mat=K.mat("wall_shell"),
                     band=(i == 0))

    # ---------------- a SECOND rank of process tanks, directly behind the first ----------
    if p["back_tanks"]:
        for i in range(p["tanks"]):
            bx_, by_, br_, btop = BACK_TANKS[i]
            K.dome_vessel("btank%d" % i, bx_, by_, br_, btop, skirt=0.26, seams=(0.36, 0.72),
                          dome_ratio=0.78, mat=K.mat("column"))
            # Cascade STRAIGHT down the shared x into the front tank — the same rule that
            # keeps the front tanks' own feeds apart.
            fx_, fy_, fr2, ftop = TANKS[i]
            lane = btop + br_ * 0.78 + 0.28
            K.pipe_run("cascade%d" % i, [(bx_, by_, btop + br_ * 0.78 - 0.05),
                                         (bx_, by_, lane), (bx_, fy_, lane),
                                         (fx_, fy_, ftop + fr2 * 0.78 - 0.02)], 0.052,
                       bend=0.15)

    # ---------------- THIRD rank (L3), feeding the second with a thick grey line ---------
    if p["rank3"]:
        for i in range(p["tanks"]):
            r3x, r3y, r3r, r3top = RANK3[i]
            K.dome_vessel("r3tank%d" % i, r3x, r3y, r3r, r3top, skirt=0.26,
                          seams=(0.36, 0.72), dome_ratio=0.78, mat=K.mat("column"))
            bx_, by_, br_, btop = BACK_TANKS[i]
            lane = r3top + r3r * 0.78 + 0.30
            # Thick and GREY, not silver: this is the trunk of the cascade and it wants to
            # read as a heavier line than the silver process pipework around it.
            K.pipe_run("trunk3_%d" % i, [(r3x, r3y, r3top + r3r * 0.78 - 0.05),
                                         (r3x, r3y, lane), (r3x, by_, lane),
                                         (bx_, by_, btop + br_ * 0.78 - 0.02)], 0.090,
                       mat=K.mat("duct"), bend=0.20)

    # ---------------- ladder and access balcony on the tallest tank ----------------
    if p["tower"]:
        tx_, ty_, tr_, ttop_ = BACK_TANKS[0]
        # +X face: the tank directly in front shares its x, so the -Y flank is buried behind
        # it while the +X flank clears — a ladder there is a ladder nobody can see.
        bz = ttop_ * 0.62
        K.tank_balcony("tbal", tx_, ty_, bz, tr_)
        K.ladder("tlad", tx_ + tr_ + 0.05, ty_, 0.10, bz + 0.06, face="+X")

    # ---------------- tall process tanks, feeding out over the vats ----------------
    for i in range(p["tanks"]):
        tx, ty, tr, ttop = TANKS[i]
        K.dome_vessel("ptank%d" % i, tx, ty, tr, ttop, skirt=0.26, seams=(0.36, 0.72),
                      dome_ratio=0.78, mat=K.mat("column"))
        # Out of the crown, across, and DOWN into the vat below — the "feeding out" run.
        vx, vy, vr, vh = VATS[min(i, p["vats"] - 1)]
        apex = ttop + tr * 0.78
        lane = apex + 0.30
        K.pipe_run("feed%d" % i, [(tx, ty, apex - 0.05), (tx, ty, lane), (tx, vy, lane),
                                  (vx, vy, lane), (vx, vy, vh + 0.10)], 0.055, bend=0.16)
        K.pipe_end("feed%d_end" % i, (vx, vy, vh + 0.10), (0, 0, -1), 0.055, "collar")

    # ---------------- pumps on the front apron ----------------
    for i in range(p["pumps"]):
        px_, py_ = PUMPS[i]
        K.pump_skid("pump%d" % i, px_, py_, ax="+X", scale=1.0)
    # ---------------- base-level line: vat -> vat -> warehouse ----------------
    # At the vats' BASE, not slung across the yard at mid height. The previous header floated
    # a clear 0.3 above the apron with nothing carrying it, which is what made it read as
    # suspended; a run at skirt height reads as sitting on the ground.
    v0x, v0y, v0r, _v0h = VATS[0]
    v1x, v1y, v1r, _v1h = VATS[1]
    tie_z = 0.30
    for tag, xa, xb in (("mid", v1x - v1r - 0.02, v0x + v0r + 0.02),
                        ("in", v0x - v0r - 0.02, x1 + 0.04)):
        K.pipe_run("tie_%s" % tag, [(xa, v0y, tie_z), (xb, v0y, tie_z)], 0.062)
        K.pipe_end("tie_%s_a" % tag, (xa, v0y, tie_z), (1, 0, 0), 0.062, "collar")
        K.pipe_end("tie_%s_b" % tag, (xb, v0y, tie_z), (-1, 0, 0), 0.062, "collar")
    if not (y0 < v0y < y1):
        print("BASE LINE DOES NOT MEET THE WAREHOUSE WALL")

    # ---------------- horizontal bullet, laid LEFT-TO-RIGHT out in front -----------------
    if p["bullet"]:
        bx0, bx1, bcy, rb = BULLET
        K.bullet("bul", (bx0, bcy, rb + 0.18), (bx1, bcy, rb + 0.18), rb)
        if bcy + rb > VATS[0][1] - VATS[0][2]:
            print("BULLET IS NOT CLEAR IN FRONT OF THE VATS")

    # ---------------- flues, and the apron ----------------
    for i, (fx, fy, fr_, fh_, frt, fz0) in enumerate(p["flues"]):
        K.furnace_stack("flue%d" % i, fx, fy, fr_, fh_, r_top=frt, flame=False, z0=fz0)

    # ---------------- two lines from the building out to the flues ----------------
    # Down the corridor between the vats and the process tanks. On L2 the extension's east
    # wall already reaches the corridor, so each run is straight; on L1 the shed stops short
    # of it and the pair has to step north first, passing WEST of the near vat.
    for i, tz in enumerate(FLUE_LANE_Z):
        fx, fy, fr_, fh_, frt, _fz = p["flues"][min(i, len(p["flues"]) - 1)]
        wall_y = FLUE_LANE_Y if (p["ext"] and y1 < FLUE_LANE_Y < WH_EXT_Y1) else y1 - 0.25
        pts = [(x1 + 0.04, wall_y, tz)]
        if abs(wall_y - FLUE_LANE_Y) > 0.01:
            jog = VATS[0][0] - VATS[0][2] - 0.20
            pts += [(jog, wall_y, tz), (jog, FLUE_LANE_Y, tz)]
        # Where the lines TERMINATE depends on whether the skid exists. With it, they feed
        # the skid and the flues take their supply from that — which is also what makes two
        # flues on one x lane possible at all: routing a second line past the first flue to
        # reach the one behind it drives straight through it.
        if p["skid"]:
            lx = SKID[0] + (-0.28 if i == 0 else 0.28)
            pts += [(lx, FLUE_LANE_Y, tz), (lx, SKID[1] - SKID[3] / 2 - 0.03, tz)]
            end_dir = (0, -1, 0)
        else:
            pts += [(fx, FLUE_LANE_Y, tz),
                    (fx, fy - Kit.r_at(fr_, frt, fh_, tz) - 0.03, tz)]
            end_dir = (0, -1, 0)
        K.pipe_end("fline%d_e" % i, pts[-1], end_dir, 0.055, "collar")
        K.pipe_run("fline%d" % i, pts, 0.055, bend=0.14)
        K.pipe_end("fline%d_w" % i, (x1 + 0.04, wall_y, tz), (1, 0, 0), 0.055, "collar")
    # Stanchions. A long horizontal run with nothing under it reads as suspended in mid-air —
    # the same fault that killed the earlier front header. Posted at stations chosen to sit in
    # the OPEN, not behind a vat where the support would be invisible and the pipe would look
    # unsupported anyway.
    zlo = min(FLUE_LANE_Z)
    for i, sx in enumerate((0.10, 1.30, 2.50, 3.70)):
        if not (x1 + 0.10 < sx < p["flues"][0][0] - 0.30):
            continue
        K.cyl("fpost%d" % i, sx, FLUE_LANE_Y, (zlo - 0.03) / 2, 0.042, zlo - 0.03,
              K.mat("scaffold"), segments=8)
        K.box("fpost%d_cap" % i, sx, FLUE_LANE_Y, zlo - 0.02, 0.10, 0.26, 0.05,
              K.mat("scaffold"))

    # ---------------- long front-to-back skid the flues rise out of ----------------
    if p["skid"]:
        kx, ky, kw, kd, kh = SKID
        K.valve_skid("skid", kx, ky, kw, kd, kh, ribs=7, valves=3)
        # East to the near tank column, west to the far one, each on its own tank row so both
        # are straight runs. They sit NORTH of the flue corridor and so cannot meet it.
        for tag, sgn, tgt, ty_ in (("e", 1, TANKS[1], SKID_TIE_Y[0]),
                                   ("w", -1, BACK_TANKS[0], SKID_TIE_Y[1])):
            ex = kx + sgn * (kw / 2 + 0.02)
            tx_ = tgt[0] - sgn * (tgt[2] + 0.02)
            K.pipe_run("skid_%s" % tag, [(ex, ty_, kh * 0.62), (tx_, ty_, kh * 0.62)], 0.058)
            K.pipe_end("skid_%s_a" % tag, (ex, ty_, kh * 0.62), (sgn, 0, 0), 0.058, "collar")
            K.pipe_end("skid_%s_b" % tag, (tx_, ty_, kh * 0.62), (-sgn, 0, 0), 0.058,
                       "collar")
        for i, f in enumerate(p["flues"]):
            if abs(f[0] - kx) > 0.02 or not (ky - kd / 2 < f[1] < ky + kd / 2):
                print("FLUE %d DOES NOT RISE OUT OF THE SKID" % i)
            if f[5] > kh:
                print("FLUE %d STARTS ABOVE THE SKID — IT WILL NOT LOOK EMBEDDED" % i)
        if ky - kd / 2 < FLUE_LANE_Y + 0.12:
            print("SKID REACHES INTO THE FLUE CORRIDOR")

    for v in VATS[:p["vats"]]:
        if v[1] + v[2] > FLUE_LANE_Y - 0.09:
            print("FLUE LINES CLIP A VAT")
    for t in TANKS[:p["tanks"]]:
        if t[1] - t[2] < FLUE_LANE_Y + 0.09:
            print("FLUE LINES CLIP A PROCESS TANK")

    foot = [(x, y, r) for x, y, r, _h in VATS] + [(x, y, r) for x, y, r, _t in TANKS]
    foot += [(f[0], f[1], f[2]) for f in p["flues"]] + [(x, y, 0.28) for x, y in PUMPS]
    foot += [(wx + ex * ww / 2, wy + ey * wd / 2, 0.0) for ex in (-1, 1) for ey in (-1, 1)]
    if p["ext"]:
        foot += [(wx + ex * ww / 2, WH_EXT_Y1, 0.0) for ex in (-1, 1)]
    if p["back_tanks"]:
        foot += [(x, y, r) for x, y, r, _t in BACK_TANKS]
    if p["rank3"]:
        foot += [(x, y, r) for x, y, r, _t in RANK3]
    if p["bay"]:
        foot += [(wx + ex * ww / 2, WH_BAY_Y1, 0.0) for ex in (-1, 1)]
    # Free-standing items near the slab EDGE get padded footprints. The outline only bounds
    # their footprint, but their bodies rise above it, and a raised object sitting on the rim
    # projects PAST the rim on screen — it reads as hanging off the slab even though its base
    # is on it. The pad buys the apron that makes it read as standing on the pad.
    edge_pad = 0.30
    if p["bullet"]:
        foot += [(BULLET[0], BULLET[2], BULLET[3] + edge_pad),
                 (BULLET[1], BULLET[2], BULLET[3] + edge_pad)]
    if p["skid"]:
        foot += [(SKID[0] + ex * SKID[2] / 2, SKID[1] + ey * SKID[3] / 2, 0.14)
                 for ex in (-1, 1) for ey in (-1, 1)]

    if p["apron_front"]:
        # The apron reaches out IN FRONT of the shed, not merely around what stands on it.
        foot += [(wx + ex * ww / 2, y0 - p["apron_front"], 0.0) for ex in (-1, 1)]
    K.apron_slab("apron", Kit.slab_outline(foot), mat=K.mat("slab_cream"),
                 kerb=K.mat("slab_kerb"))

    # ---------------- checks ----------------
    def _clear(na, a, nb, b, margin=0.20):
        need = math.sqrt(2.0) * (a[2] + b[2])
        got = abs((b[0] + b[1]) - (a[0] + a[1]))
        if got < need + margin:
            print("%s AND %s TOO CLOSE ON SCREEN: |ds| %.2f, need %.2f + margin"
                  % (na.upper(), nb.upper(), got, need))

    _clear("vat0", VATS[0][:3], "vat1", VATS[1][:3])
    _clear("ptank0", TANKS[0][:3], "ptank1", TANKS[1][:3])
    for i in range(len(p["flues"]) - 1):
        _clear("flue%d" % i, p["flues"][i][:3], "flue%d" % (i + 1), p["flues"][i + 1][:3],
               margin=0.10)
    if p["back_tanks"]:
        _clear("btank0", BACK_TANKS[0][:3], "btank1", BACK_TANKS[1][:3])
        # Ranks must clear in PLAN too. Two tanks that intersect read as one lumpy mass
        # however well their tones separate, and the screen check cannot see it.
        for i in range(p["tanks"]):
            if BACK_TANKS[i][1] - TANKS[i][1] < BACK_TANKS[i][2] + TANKS[i][2]:
                print("BACK TANK %d INTERSECTS THE FRONT ONE IN PLAN" % i)
    if p["rank3"]:
        _clear("r3tank0", RANK3[0][:3], "r3tank1", RANK3[1][:3])
        for i in range(p["tanks"]):
            if abs(RANK3[i][0] - BACK_TANKS[i][0]) > 0.02:
                print("RANK-3 TRUNK %d IS NOT A STRAIGHT RUN" % i)
            if RANK3[i][1] - BACK_TANKS[i][1] < RANK3[i][2] + BACK_TANKS[i][2]:
                print("RANK-3 TANK %d INTERSECTS RANK 2 IN PLAN" % i)
            ba = 0.4082 * (BACK_TANKS[i][1] - BACK_TANKS[i][0]) + 0.8165 * (
                BACK_TANKS[i][3] + BACK_TANKS[i][2] * 0.78)
            ta = 0.4082 * (RANK3[i][1] - RANK3[i][0]) + 0.8165 * (
                RANK3[i][3] + RANK3[i][2] * 0.78)
            if ta < ba + 0.60:
                print("RANK-3 TANK %d BARELY CLEARS RANK 2 (%.2f vs %.2f)" % (i, ta, ba))
        for i in range(p["tanks"]):
            if abs(BACK_TANKS[i][0] - TANKS[i][0]) > 0.02:
                print("CASCADE %d IS NOT A STRAIGHT RUN" % i)
            # ...and it has to out-top the tank in front or standing behind buys nothing.
            fa = 0.4082 * (TANKS[i][1] - TANKS[i][0]) + 0.8165 * (TANKS[i][3]
                                                                  + TANKS[i][2] * 0.78)
            ba = 0.4082 * (BACK_TANKS[i][1] - BACK_TANKS[i][0]) + 0.8165 * (
                BACK_TANKS[i][3] + BACK_TANKS[i][2] * 0.78)
            if ba < fa + 0.60:
                print("BACK TANK %d BARELY CLEARS THE FRONT ONE (%.2f vs %.2f)" % (i, ba, fa))
    # BETWEEN the tank columns now. The gap is narrow in screen columns even though it is
    # wide in plan, so a flue will overlap a tank — that is fine while it is much TALLER, and
    # what actually has to hold is that the two flues separate from each other.
    for i in range(len(p["flues"]) - 1):
        a, b = p["flues"][i], p["flues"][i + 1]
        atop = 0.4082 * (a[1] - a[0]) + 0.8165 * a[3]
        btop = 0.4082 * (b[1] - b[0]) + 0.8165 * b[3]
        if abs((b[0] + b[1]) - (a[0] + a[1])) < math.sqrt(2.0) * (a[2] + b[2]) + 0.20 \
                and abs(atop - btop) < 0.70:
            print("FLUES %d/%d SHARE A COLUMN WITHOUT A HEIGHT DIFFERENCE" % (i, i + 1))
    for i, f in enumerate(p["flues"]):
        for j in range(p["tanks"]):
            if abs(f[0] - TANKS[j][0]) < f[2] + TANKS[j][2]:
                print("FLUE %d INTERSECTS TANK COLUMN %d IN PLAN" % (i, j))

    # Do the feeds actually CROSS? The old test asked whether each tank sat over its vat,
    # which is sufficient but not necessary — with the ranks spread, the right-hand feed is an
    # L that turns OUTSIDE the other's column and still cannot meet it. Test the geometry.
    legs = []
    for i in range(p["tanks"]):
        tx_, ty_ = TANKS[i][0], TANKS[i][1]
        vx_, vy_ = VATS[min(i, p["vats"] - 1)][0], VATS[min(i, p["vats"] - 1)][1]
        legs.append((tx_, vy_, ty_, min(tx_, vx_), max(tx_, vx_)))
    for i, (xi, vyi, tyi, _a, _b) in enumerate(legs):
        for j, (_xj, vyj, _tyj, xj0, xj1) in enumerate(legs):
            if i == j:
                continue
            if vyi - 0.01 <= vyj <= tyi + 0.01 and xj0 - 0.01 <= xi <= xj1 + 0.01:
                print("FEED %d CROSSES FEED %d" % (i, j))
    # The alcove has to be DEEP enough to hold the rolls, or they poke out of the facade.
    if WH_ALCOVE < 0.55:
        print("ALCOVE TOO SHALLOW FOR THE ROLLS")
    if WH_DOOR_H > wh - 0.20:
        print("NO LINTEL LEFT ABOVE THE DOORWAY")
    for i in range(p["vats"]):
        if VATS[i][1] - VATS[i][2] < wy + wd / 2 and abs(VATS[i][0] - wx) < ww / 2 + VATS[i][2]:
            print("VAT %d FOULS THE WAREHOUSE" % i)
    for wmsg in K.validate(ground=-0.21):
        print(wmsg)
    return {"building": "poly_plant", "level": level, "objects": len(K.col.objects)}
