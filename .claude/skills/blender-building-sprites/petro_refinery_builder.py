# Parametric builder for the Petrochemical Refinery (b_011, internal_name `petro_refinery`).
# Run AFTER sprite_kit.py:
#   exec(open(".../sprite_kit.py").read())
#   exec(open(".../petro_refinery_builder.py").read()); build_petro_refinery(2)
#
# REWRITE of a superseded version (see superseded/). Its DESIGN was right and is kept; its
# authoring system is not. That version composed in screen space via an SD(s, d) helper, which
# put every long run — pipe racks, bullets, conveyors — along the world x+y diagonal. That
# diagonal renders DEAD HORIZONTAL at this camera, and it was the single biggest reason the old
# refineries read as flat and sprawling. Everything here is placed in WORLD coordinates, so long
# elements slope at the set's iso grammar like every other building.
#
# L1 IS THE OWNER'S OWN COMPOSITION (2026-07-31), and it replaces the earlier equipment-yard
# attempt entirely:
#   * a LONG single-storey flat-roofed building, factory-sized — the anchor
#   * one SQUAT flat-topped tank with a purple ring around its BASE
#   * one TALL DOMED tank — wide shell, SHALLOW cap. The previous vessels capped a narrow
#     shell with a full hemisphere, which made the dome as tall as the tank was wide; that is
#     what made them unreadable as tanks.
#   * one SPHERE tank on braced legs
#   * a DOUBLE pipe sphere -> flat tank, and a single BIGGER pipe sphere -> the back of the
#     main building
# Every run is on a world axis, so it slopes with the iso grid.
# L2/L3 still hold the older layout and are NOT yet reworked to match.
#
# PURPLE (#8E5BC0, the game's CAT_REFINERY) is the ONLY chroma: column crown bands, one tank
# waistband, one flue band. The flare flame is the single warm note.

import math

PETRO_LEVELS = {
    1: dict(columns=1, tanks=1, bund=False, rack=False, bullets=0, flare=False, hall_w=1.30),
    2: dict(columns=2, tanks=2, bund=True,  rack=True,  bullets=1, flare=False, hall_w=1.70),
    3: dict(columns=3, tanks=3, bund=True,  rack=True,  bullets=2, flare=True,  hall_w=1.70),
}

# SLENDERNESS IS THE WHOLE READ. At r=0.40 against a 2.95 top these came out as squat domed
# drums indistinguishable from the storage tanks, and the two masses fused. A fractionating
# column wants h/r around 12, and the tanks want to be visibly SQUATTER so the hierarchy is
# columns-are-tall / tanks-are-low / flare-is-the-landmark.
COL_X = 0.74                        # columns in a row along +Y: they climb the screen
COL_YS = (-0.50, 0.35, 1.20)
COL_TOPS = (3.30, 2.85, 2.45)
COL_R = 0.27
FARM = (-2.62, -1.28, 0.42, 2.34)   # tank-farm bund: x0, x1, y0, y1
TANKS = ((-2.05, 0.95, 0.50), (-1.70, 1.95, 0.42), (-2.48, 1.88, 0.28))
RACK_Y = -1.10                      # rack runs along +X: down-right on screen
FLARE_XY = (2.18, 1.72)
HALL = (-2.05, -1.62)               # control block centre (front-left)


def build_petro_refinery(level: int = 1) -> dict:
    if level == 1:
        return _build_l1()
    if level == 2:
        return _build_l2()
    if level == 3:
        return _build_l3()
    p = PETRO_LEVELS[level]
    setup_rig()
    K = Kit(open_collection("BLDG_petro"))

    # ---------------- control block: the anchoring mass ----------------
    hw, hd, hh = p["hall_w"], 1.05, 1.00
    hx, hy = HALL
    K.box("hall", hx, hy, hh / 2, hw, hd, hh, K.mat("wall_steel"))
    K.box("hall_deck", hx, hy, hh + 0.012, hw - 0.02, hd - 0.02, 0.05, K.mat("roof_deck"))
    for tag, (bx, by, sx, sy) in {
        "f": (hx, hy - hd / 2, hw + 0.10, 0.09), "b": (hx, hy + hd / 2, hw + 0.10, 0.09),
        "l": (hx - hw / 2, hy, 0.09, hd + 0.10), "r": (hx + hw / 2, hy, 0.09, hd + 0.10),
    }.items():
        K.box("hall_par_%s" % tag, bx, by, hh + 0.05, sx, sy, 0.10, K.mat("roof"))
    bays = max(2, int(round(hw / 0.60)))
    for b in range(bays):
        K.window("hall_w%d" % b, "-Y", (hx - hw / 2 + hw * (b + 0.5) / bays, hy - hd / 2, 0.56),
                 0.30, 0.50, cols=2, rows=3)
    K.door("hall_door", "+X", (hx + hw / 2, hy + 0.10, 0.30), 0.28, 0.58, ribs=3)

    # ---------------- fractionating columns ----------------
    for i in range(p["columns"]):
        top = COL_TOPS[i]
        _, _, noz = K.frac_column("col%d" % i, COL_X, COL_YS[i], top, COL_R, trays=7,
                                  platforms=(top * 0.52, top * 0.78),
                                  draws=(top * 0.42, top * 0.66))
        if p["rack"] and noz:
            # Downcomer to the rack. It has to travel in the DEPTH direction (+x, -y) to meet
            # a rack lying on a world axis — a plain -Y feeder never reaches one.
            n0 = noz[0]
            K.pipe_run("col%d_down" % i, [(n0[0], n0[1], n0[2]),
                                          (n0[0] + 0.42, n0[1] - 0.26, n0[2]),
                                          (n0[0] + 0.42, RACK_Y + 0.22, 1.22)], 0.050)

    # ---------------- tank farm ----------------
    if p["bund"]:
        K.bund("bund", FARM[0], FARM[1], FARM[2], FARM[3])
    for i in range(p["tanks"]):
        tx, ty, tr = TANKS[i]
        K.flat_tank("tank%d" % i, tx, ty, tr, 0.74 + 0.05 * i, band=(i == 0))

    # ---------------- pipe rack: ALONG +X, so it slopes with the grid ----------------
    if p["rack"]:
        K.pipe_rack("rack", (-1.15, RACK_Y), (1.60, RACK_Y), 1.22, 0.82, bents=5)

    # ---------------- LPG bullets on the front apron, also along +X ----------------
    for i in range(p["bullets"]):
        by = -2.00 - i * 0.60
        K.box("bulpad%d" % i, 0.15, by, 0.025, 1.85, 0.80, 0.05, K.mat("yard"))
        K.bullet("bul%d" % i, (-0.62, by, 0.50), (0.92, by, 0.50), 0.29)

    # ---------------- flues ----------------
    nflue = 1 if p["columns"] < 2 else 2
    for i in range(nflue):
        fx, fy = 1.66 + i * 0.34, -0.48 + i * 0.46
        K.flue_stack("flue%d" % i, fx, fy, 0.0, 2.10 + i * 0.20, r_base=0.18, r_top=0.15,
                     bands=1, mat_a="flue", mat_b="flue")
        if i == 0:
            K.cyl("flue%d_band" % i, fx, fy, 1.48, 0.198, 0.16, K.mat("accent"))
            for dz in (-0.08, 0.08):
                K.seam("flue%d_bandseam%d" % (i, dz > 0), fx, fy, 1.48 + dz, 0.210)

    # ---------------- flare derrick: the L3 landmark ----------------
    if p["flare"]:
        K.derrick("flare", FLARE_XY[0], FLARE_XY[1], 0.0, 2.55, 0.78, 0.34, bays=6)
        K.flare_tip("flare", FLARE_XY[0], FLARE_XY[1], 2.55, r=0.13)

    if p["bund"] and FARM[1] > COL_X - COL_R:
        print("TANK FARM OVERLAPS THE COLUMN ROW")
    if p["flare"] and FLARE_XY[0] - 0.39 < COL_X + COL_R:
        print("FLARE OVERLAPS THE COLUMNS")
    if p["rack"] and abs(RACK_Y - HALL[1]) < 0.6 and HALL[0] + p["hall_w"] / 2 > -1.15:
        print("RACK RUNS THROUGH THE CONTROL BLOCK")
    for wmsg in K.validate(ground=0.0):
        print(wmsg)
    return {"building": "petro_refinery", "level": level, "columns": p["columns"],
            "objects": len(K.col.objects)}


# ================================ L1 (owner composition) ================================
# BUILDING ACROSS THE BACK, plant in front of it — the power plant's arrangement, and here it
# is forced rather than chosen. A front-placed building hides its own back wall at this camera
# (nothing ever sees a +Y face), so the brief's "bigger pipe to the back of the main building"
# was rendering a pipe that could not be seen at all; and the tanks behind it lost their bases,
# their purple ring and both pipe runs. Front-placed building = plant reduced to floating tops.
L1_BLD = (-0.85, 1.15, 3.50, 1.25, 1.15)    # cx, cy, length(+X), depth(+Y), height
# The three tanks are spaced by SCREEN separation, not plan separation: two circles are exactly
# tangent on screen when |d(x+y)| = sqrt(2)*(r1+r2), and clearing only in x let them stack into
# each other. Buying that for all three costs ~6 units of width, so only the DOME is fully
# clear; the sphere is deliberately tangent to the flat tank from in FRONT of it, and the two
# carry different material VALUES so the meeting reads as depth instead of fusing.
#
# ORDER MATTERS MORE THAN SPACING. With the sphere at one end and the flat tank at the other,
# every pipe the brief asks for crossed the whole sprite diagonally, and three pale diagonals
# became the loudest thing in it. Sphere between the flat tank and the building makes both runs
# single straight segments on world axes.
L1_FLAT = (-1.66, -0.95, 0.68, 0.86)        # squat flat-top tank: cx, cy, r, h
L1_SPH = (0.60, -1.05, 0.55)                # sphere tank: cx, cy, r
L1_DUCT_Z = (0.82, 0.60)                    # the DOUBLE pipe, at the flat tank's roof line
# THREE domed tanks in a row BEHIND the building. Behind is not hidden: the row clears the back
# wall by its own radius, and each tank still shows its upper two thirds over the roofline —
# what the building eats is the skirt, which is the least interesting part of a tank anyway.
# Radius came DOWN to 0.48 to make the row fit: three tanks need 2 x sqrt(2)*(2r) of screen
# separation between centres, and at r=0.66 that row is wider than the building it stands behind.
L1_DOMES_Y = 2.55
L1_DOMES_X = (-2.55, -0.95, 0.65)
L1_DOME_R, L1_DOME_TOP = 0.48, 1.95
# Thin and TALL — a fired heater is a slender column, and at r=0.40 it was reading as a second
# storage tank stood next to the real ones.
L1_FURN = (2.40, 2.10, 0.28, 4.95, 0.14)    # fired heater: cx, cy, r_base, height, r_top
L1_BOX = (1.18, 0.62, 0.60, 0.60, 1.02)     # corner plant box: cx, cy, sx, sy, h
# Above the furnace's accent skirt (0.36): a tie leaving through the band cuts it in half.
L1_TIE_Z = (0.46, 0.66, 0.86)               # the THREE furnace ties, stacked


def _hall_block(K, tag, bx, by, bw, bd, bh, storeys=1, door=True, keep_clear=()):
    """One block of the main building: white walls, dark flat roof, parapet, factory-proportion
    glazing (2 wide x 3 tall) with the door owning bay 0 so the windows stand BESIDE it.

    `storeys` places that many window BANDS; the block's height is the caller's, because two
    storeys of a one-storey height reads as a warehouse with a mezzanine, not as two floors.
    `keep_clear` is a list of x where pipework lands — a bay it reaches loses its glazing
    rather than getting a flange laid across the mullions."""
    K.box(tag, bx, by, bh / 2, bw, bd, bh, K.mat("wall_bright"))
    K.box("%s_deck" % tag, bx, by, bh + 0.012, bw - 0.02, bd - 0.02, 0.05, K.mat("roof_deck"))
    for t, (px, py, sx, sy) in {
        "f": (bx, by - bd / 2, bw + 0.10, 0.10), "b": (bx, by + bd / 2, bw + 0.10, 0.10),
        "l": (bx - bw / 2, by, 0.10, bd + 0.10), "r": (bx + bw / 2, by, 0.10, bd + 0.10),
    }.items():
        K.box("%s_par_%s" % (tag, t), px, py, bh + 0.055, sx, sy, 0.11, K.mat("roof"))
    bays = max(3, int(round(bw / 0.62)))
    ww, pitch = 0.32, bw / bays
    for st in range(storeys):
        wz = bh * (st + 0.5) / storeys - 0.02
        for b in range(bays):
            if b == 0 and door and st == 0:
                continue                               # the door's bay
            wx = bx - bw / 2 + bw * (b + 0.5) / bays
            if any(abs(wx - c) < pitch * 0.5 for c in keep_clear):
                continue
            K.window("%s_w%d_%d" % (tag, st, b), "-Y", (wx, by - bd / 2, wz), ww, 0.54,
                     cols=2, rows=3)
    if door:
        K.door("%s_door" % tag, "-Y", (bx - bw / 2 + pitch * 0.5, by - bd / 2, 0.36),
               0.32, 0.72, ribs=3)
    K.box("%s_louvre" % tag, bx, by + bd / 2 + 0.02, bh - 0.26, bw * 0.55, 0.04, 0.18,
          K.mat("opening"))
    return bh + 0.11


def _build_l1() -> dict:
    setup_rig()
    K = Kit(open_collection("BLDG_petro"))

    # ---------------- long single-storey building, flat roof ----------------
    bx, by, bw, bd, bh = L1_BLD
    _hall_block(K, "hall", bx, by, bw, bd, bh, storeys=1, keep_clear=(L1_SPH[0],))
    K.gate("hall_gate", "-X", (bx - bw / 2, by, 0.40), 0.54, 0.74, slats=5)

    # ---------------- squat flat-topped tank, purple ring at its BASE ----------------
    fx, fy, fr, fh = L1_FLAT
    # NO spiral stair. The kit's stair is a helical ribbon at r+0.10 wrapping the full height;
    # on a squat tank it out-masses the tank, turns the curb into a pot rim, and — the actual
    # reason it goes — it hides the purple base ring behind its own treads.
    K.flat_tank("flat", fx, fy, fr, fh, band=False, base_band=True, stair=False,
                roof_rise=0.06, mat=K.mat("wall_shell"))

    # ---------------- three tall domed tanks, in a row BEHIND the building ----------------
    # dome_ratio 0.78 reads as domed from this elevation; at 0.38-0.55 we look down far enough
    # on the cap that it just renders as a flat disc. The SHELL is what carries "tank" — wide
    # and tall — and the dome is a cap on top of it, not a hemisphere the width of the tank.
    dr, dtop, dy = L1_DOME_R, L1_DOME_TOP, L1_DOMES_Y
    for i, dxi in enumerate(L1_DOMES_X):
        K.dome_vessel("dome%d" % i, dxi, dy, dr, dtop, skirt=0.24, seams=(0.36, 0.72),
                      dome_ratio=0.78, mat=K.mat("column"))

    # ---------------- sphere tank on braced legs ----------------
    sx_, sy_, sr = L1_SPH
    # Darkest of the three: it stands in FRONT of the pale flat tank, and the two only stay
    # separate because their values differ — at this camera both lit faces land within ~1 luma
    # of each other, so form never reads from shading alone.
    sz = K.sphere_tank("sph", sx_, sy_, sr, legs=6, mat=K.mat("drum"))

    # ---------------- DOUBLE pipe: flat tank -> sphere, via bends ----------------
    # Leaves at the flat tank's ROOF LINE and steps DOWN into the sphere. The two runs drop at
    # different x so neither elbow crosses the other's leg — stacked pipes that turn at the
    # same station weave through each other and read as one tangled bundle.
    fdx = math.sqrt(max(0.01, fr * fr - (sy_ - fy) ** 2))
    scz = sr * 1.35                                    # sphere_tank sets its equator here
    for i, (pz, drop, turn) in enumerate(zip(L1_DUCT_Z, (0.62, 0.40), (-0.34, -0.62))):
        ez = sx_ - math.sqrt(max(0.01, sr * sr - (drop - scz) ** 2))   # meet the SURFACE
        K.pipe_run("xfer%d" % i, [(fx + fdx - 0.03, sy_, pz), (turn, sy_, pz),
                                  (turn, sy_, drop), (ez, sy_, drop)], 0.055, bend=0.10)
        K.pipe_end("xfer%d_f" % i, (fx + fdx - 0.03, sy_, pz), (-1, 0, 0), 0.055, "flange")
        K.pipe_end("xfer%d_e" % i, (ez, sy_, drop), (-1, 0, 0), 0.055, "collar")
        if pz > fh:
            print("XFER %d LEAVES ABOVE THE FLAT TANK'S ROOF" % i)

    # ---------------- single BIGGER pipe: sphere -> the main building ----------------
    # Straight +Y into the wall: the sphere sits directly in front of the building, so this
    # needs no dog-leg, and it enters right of the glazing so it crosses no window.
    K.pipe_run("main", [(sx_, sy_ + sr * 0.62, 0.70),
                        (sx_, by - bd / 2 - 0.04, 0.70)], 0.105)
    K.pipe_end("main_end", (sx_, by - bd / 2 - 0.04, 0.70), (0, 1, 0), 0.105, "collar")
    if not (bx - bw / 2 < sx_ < bx + bw / 2):
        print("MAIN PIPE MISSES THE BUILDING WALL")

    # ---------------- fired heater on the far right ----------------
    ux, uy, ur, uh, urt = L1_FURN
    K.furnace_stack("furn", ux, uy, ur, uh, r_top=urt)

    # ---------------- corner plant box, and THREE ties from the furnace base ----------------
    # The box sits ON the building's front-right corner: its -X face is the building's +X wall
    # and it laps past the front face, so it reads as bolted to the corner rather than parked
    # near it. Everything here is right of the building's last screen column, so none of it is
    # lost behind the mass.
    qx, qy, qsx, qsy, qh = L1_BOX
    K.box("qbox", qx, qy, qh / 2, qsx, qsy, qh, K.mat("wall_grey"))
    K.box("qbox_deck", qx, qy, qh + 0.012, qsx - 0.02, qsy - 0.02, 0.05, K.mat("roof_deck"))
    K.box("qbox_cope", qx, qy, qh + 0.055, qsx + 0.07, qsy + 0.07, 0.07, K.mat("roof"))
    K.cyl("qbox_vent", qx + qsx * 0.24, qy - qsy * 0.18, qh + 0.24, 0.055, 0.34,
          K.mat("pipe"), segments=12)
    # Stacked in Z on ONE plan route: pipes at different heights can share a route and turn at
    # the same station without ever meeting, which a side-by-side bundle cannot do round a bend.
    for i, tz in enumerate(L1_TIE_Z):
        # Start ON the tapered shell, not at a fixed offset from the axis — a constant offset
        # leaves a visible gap the moment the stack narrows.
        K.pipe_run("tie%d" % i, [(ux, uy - Kit.r_at(ur, urt, uh, tz) - 0.02, tz), (ux, qy, tz),
                                 (qx + qsx / 2 + 0.03, qy, tz)], 0.042, bend=0.13)
        K.pipe_end("tie%d_end" % i, (qx + qsx / 2 + 0.03, qy, tz), (1, 0, 0), 0.042, "collar")
        if tz > qh - 0.10:
            print("TIE %d ENTERS ABOVE THE BOX" % i)
        if tz < 0.40:
            print("TIE %d CROSSES THE FURNACE'S ACCENT BAND" % i)

    # ---------------- concrete apron under the whole plant ----------------
    # Derived from the equipment, not typed: every footprint goes in as a disc and the outline
    # is their octagonal hull. Typing a rectangle here costs ~150px of sprite width on the two
    # empty diagonal corners alone.
    foot = [(fx, fy, fr), (sx_, sy_, sr), (ux, uy, ur)]
    foot += [(x, dy, dr) for x in L1_DOMES_X]
    for ccx, ccy, csx, csy in ((bx, by, bw, bd), (qx, qy, qsx, qsy)):
        foot += [(ccx + ex * csx / 2, ccy + ey * csy / 2, 0.0)
                 for ex in (-1, 1) for ey in (-1, 1)]
    K.apron_slab("apron", Kit.slab_outline(foot), mat=K.mat("slab_cream"),
                 kerb=K.mat("slab_kerb"))

    # ---------------- checks ----------------
    # SCREEN separation, not plan separation: two circles touch on screen when their (x+y)
    # differ by sqrt(2)*(r1+r2). Checking x alone passed a layout whose tanks visibly stacked.
    def _clear(na, a, nb, b, margin=0.20):
        need = math.sqrt(2.0) * (a[2] + b[2])
        got = abs((b[0] + b[1]) - (a[0] + a[1]))
        if got < need + margin:
            print("%s AND %s TOO CLOSE ON SCREEN: |ds| %.2f, need %.2f + margin"
                  % (na.upper(), nb.upper(), got, need))

    domes = [(x, dy, dr) for x in L1_DOMES_X]
    for i in range(len(domes) - 1):
        _clear("dome%d" % i, domes[i], "dome%d" % (i + 1), domes[i + 1])
    _clear("dome%d" % (len(domes) - 1), domes[-1], "furnace", (ux, uy, ur))   # widest = base
    # The domes stand behind the building; they have to clear its back wall in PLAN or they
    # grow out of the roof.
    if dy - dr < by + bd / 2:
        print("DOMED TANK ROW FOULS THE BACK WALL")
    # ...and they are only worth putting there if their tops actually break the roofline. The
    # building's silhouette at a shared column is its back-top edge.
    for i, dxi in enumerate(L1_DOMES_X):
        col = dxi + dy
        roof = 0.4082 * (by + bd / 2 - (col - (by + bd / 2))) + 0.8165 * (bh + 0.11)
        apex = 0.4082 * (dy - dxi) + 0.8165 * (dtop + dr * 0.78)
        if col - math.sqrt(2.0) * dr < bx + bw / 2 + (by + bd / 2) and apex < roof + 0.35:
            print("DOME %d BARELY CLEARS THE ROOFLINE (%.2f vs %.2f)" % (i, apex, roof))
    # The sphere is ALLOWED to overlap the flat tank, but only from in front of it.
    if (sx_ - sy_) < (fx - fy):
        print("SPHERE OVERLAPS THE FLAT TANK FROM BEHIND")
    if qx - qsx / 2 > bx + bw / 2 + 0.02:
        print("CORNER BOX DOES NOT TOUCH THE BUILDING")
    if ux - ur < bx + bw / 2:
        print("FURNACE OVERLAPS THE BUILDING IN PLAN")
    for wmsg in K.validate(ground=-0.21):
        print(wmsg)
    return {"building": "petro_refinery", "level": 1, "objects": len(K.col.objects)}


# ================================ L2 (owner composition) ================================
# L1's plant, grown: the building gains a TWO-STOREY block on its left, the dome row becomes
# six in two ranks, the fired heater becomes two, and a riser bank stands off the back-left.
L2_BLD_R = (-0.85, 1.15, 3.50, 1.25, 1.15)   # single-storey right block — L1's, unchanged
L2_BLD_L = (-3.475, 1.15, 1.75, 1.25, 2.00)  # TWO-storey left extension
L2_FLAT = (-2.45, -0.95, 0.72, 0.90)
L2_SPH = (0.60, -1.05, 0.55)
L2_DUCT_Z = (0.86, 0.64)
L2_BOX = (1.18, 0.62, 0.60, 0.60, 1.02)
L2_TIE_Z = (0.46, 0.66, 0.86)
# SIX domes in TWO RANKS, not one row of six. A single row needs 5 x sqrt(2)*2r of screen
# separation — about 7.5 units of sprite width before anything else is placed, which alone
# would push L2 past L3's export budget. Two ranks cost roughly half that.
# The back rank is TALLER on purpose. Ranks 1.40 apart in y sit only 0.4082*1.40 = 0.57 higher
# on screen, so same-height tanks behind would be swallowed where the columns overlap; the
# extra 0.60 of shell buys another 0.49 and their domes clear cleanly.
# The back rank sits BEHIND the front one ON THE WORLD GRID — same x, one row further in y.
# In this projection +Y is up-and-RIGHT, so that reads as a diagonal step up-right, which is
# what "behind" looks like isometrically. Matching SCREEN COLUMNS instead (dx = -dy) stacks the
# ranks straight up the screen: measured identical to the pixel, and it reads as one tank on
# top of another rather than as a second rank.
# The back rank is TALLER on purpose. What it has to clear is not its own counterpart but the
# front tank one place to its RIGHT, whose column sits only 0.20 away; the extra 0.60 of shell
# puts its dome 1.7 screen units clear of that one.
L2_DOMES_F = (2.70, (-4.10, -2.50, -0.90), 0.46, 1.80)   # y, xs, r, shell top
L2_DOMES_B = (4.10, (-4.10, -2.50, -0.90), 0.46, 2.40)
L2_FURN = ((2.40, 2.10, 4.95), (1.90, 3.60, 4.30))   # cx, cy, shell height
L2_FURN_R, L2_FURN_RT = 0.28, 0.14
# Roof risers on the two-storey block: up out of the deck, over to the BACK EDGE, then down.
# Only the stub and the elbow are ever seen — below about z 1.93 the block's own silhouette
# swallows the drop, which is the point: the run reaches the left tanks without a long pale
# diagonal crossing the sprite to get there.
L2_RISER_X = (-4.15, -3.92, -3.69, -3.28, -3.05, -2.82)
L2_RISER_H = (1.05, 0.72, 0.90, 0.55, 0.80, 0.45)   # ABOVE the roof deck
L2_RISER_Y = 1.15                                   # where they leave the roof
L2_RISER_EDGE = 1.955                               # just past the back parapet
L2_TRUNK_Z = 0.40


def _build_l2() -> dict:
    setup_rig()
    K = Kit(open_collection("BLDG_petro"))

    # ---------------- main building: single-storey right + two-storey left ----------------
    rx, ry, rw, rd, rh = L2_BLD_R
    lx, ly, lw, ld, lh = L2_BLD_L
    _hall_block(K, "hall", rx, ry, rw, rd, rh, storeys=1, door=False,
                keep_clear=(L2_SPH[0],))
    _hall_block(K, "hallL", lx, ly, lw, ld, lh, storeys=2, door=True)
    K.gate("hallL_gate", "-X", (lx - lw / 2, ly, 0.40), 0.54, 0.74, slats=5)
    if abs((lx + lw / 2) - (rx - rw / 2)) > 0.01:
        print("THE TWO HALL BLOCKS DO NOT MEET")

    # ---------------- squat flat-topped tank, purple ring at its BASE ----------------
    fx, fy, fr, fh = L2_FLAT
    K.flat_tank("flat", fx, fy, fr, fh, band=False, base_band=True, stair=False,
                roof_rise=0.06, mat=K.mat("wall_shell"))

    # ---------------- six domed tanks, two ranks behind the building ----------------
    domes = []
    for tag, (dy, xs, dr, dtop) in (("F", L2_DOMES_F), ("B", L2_DOMES_B)):
        for i, dxi in enumerate(xs):
            K.dome_vessel("dome%s%d" % (tag, i), dxi, dy, dr, dtop, skirt=0.24,
                          seams=(0.36, 0.72), dome_ratio=0.78, mat=K.mat("column"))
            domes.append((dxi, dy, dr, dtop))

    # ---------------- sphere tank on braced legs ----------------
    sx_, sy_, sr = L2_SPH
    K.sphere_tank("sph", sx_, sy_, sr, legs=6, mat=K.mat("drum"))

    # ---------------- DOUBLE pipe: flat tank -> sphere, via bends ----------------
    fdx = math.sqrt(max(0.01, fr * fr - (sy_ - fy) ** 2))
    scz = sr * 1.35
    for i, (pz, drop, turn) in enumerate(zip(L2_DUCT_Z, (0.64, 0.42), (-0.55, -0.95))):
        ez = sx_ - math.sqrt(max(0.01, sr * sr - (drop - scz) ** 2))
        K.pipe_run("xfer%d" % i, [(fx + fdx - 0.03, sy_, pz), (turn, sy_, pz),
                                  (turn, sy_, drop), (ez, sy_, drop)], 0.055, bend=0.10)
        K.pipe_end("xfer%d_f" % i, (fx + fdx - 0.03, sy_, pz), (-1, 0, 0), 0.055, "flange")
        K.pipe_end("xfer%d_e" % i, (ez, sy_, drop), (-1, 0, 0), 0.055, "collar")

    # ---------------- single BIGGER pipe: sphere -> the main building ----------------
    K.pipe_run("main", [(sx_, sy_ + sr * 0.62, 0.70), (sx_, ry - rd / 2 - 0.04, 0.70)], 0.105)
    K.pipe_end("main_end", (sx_, ry - rd / 2 - 0.04, 0.70), (0, 1, 0), 0.105, "collar")

    # ---------------- two fired heaters on the right ----------------
    for i, (ux, uy, uh) in enumerate(L2_FURN):
        K.furnace_stack("furn%d" % i, ux, uy, L2_FURN_R, uh, r_top=L2_FURN_RT)

    # ---------------- corner plant box, and ties from BOTH heaters ----------------
    qx, qy, qsx, qsy, qh = L2_BOX
    K.box("qbox", qx, qy, qh / 2, qsx, qsy, qh, K.mat("wall_grey"))
    K.box("qbox_deck", qx, qy, qh + 0.012, qsx - 0.02, qsy - 0.02, 0.05, K.mat("roof_deck"))
    K.box("qbox_cope", qx, qy, qh + 0.055, qsx + 0.07, qsy + 0.07, 0.07, K.mat("roof"))
    K.cyl("qbox_vent", qx + qsx * 0.24, qy - qsy * 0.18, qh + 0.24, 0.055, 0.34,
          K.mat("pipe"), segments=12)
    ux0, uy0, uh0 = L2_FURN[0]
    for i, tz in enumerate(L2_TIE_Z):
        K.pipe_run("tie%d" % i,
                   [(ux0, uy0 - Kit.r_at(L2_FURN_R, L2_FURN_RT, uh0, tz) - 0.02, tz),
                    (ux0, qy, tz), (qx + qsx / 2 + 0.03, qy, tz)], 0.042, bend=0.13)
        K.pipe_end("tie%d_end" % i, (qx + qsx / 2 + 0.03, qy, tz), (1, 0, 0), 0.042, "collar")
    # The SECOND heater ties into the building's east wall instead, on its own lane — two
    # bundles converging on one small box reads as a knot.
    ux1, uy1, uh1 = L2_FURN[1]
    for i, tz in enumerate((0.52, 0.76)):
        K.pipe_run("tie2_%d" % i,
                   [(ux1, uy1 - Kit.r_at(L2_FURN_R, L2_FURN_RT, uh1, tz) - 0.02, tz),
                    (ux1, 1.20, tz), (rx + rw / 2 + 0.04, 1.20, tz)], 0.042, bend=0.13)
        K.pipe_end("tie2_%d_end" % i, (rx + rw / 2 + 0.04, 1.20, tz), (1, 0, 0), 0.042,
                   "collar")

    # ---------------- roof risers -> back edge -> down -> the left tanks ----------------
    for i, (px, ph) in enumerate(zip(L2_RISER_X, L2_RISER_H)):
        K.pipe_run("riser%d" % i, [(px, L2_RISER_Y, lh - 0.06),
                                   (px, L2_RISER_Y, lh + ph),
                                   (px, L2_RISER_EDGE, lh + ph),
                                   (px, L2_RISER_EDGE, L2_TRUNK_Z)], 0.055, bend=0.13)
        if not (lx - lw / 2 < px < lx + lw / 2):
            print("RISER %d IS NOT ON THE TWO-STOREY ROOF" % i)
    # Gathered below the sightline and taken to the two LEFT tanks. This leg is invisible by
    # design, but it is still routed clear of both ranks — a pipe modelled through a tank
    # becomes a visible error the moment anything about the camera or the layout changes.
    bx0, by0, br0 = L2_DOMES_B[1][0], L2_DOMES_B[0], L2_DOMES_B[2]
    fx0, fy0, fr0 = L2_DOMES_F[1][0], L2_DOMES_F[0], L2_DOMES_F[2]
    # The back tank now stands directly behind the front one in PLAN too, so the trunk has to
    # go round the outside of the front tank rather than straight up its centre line.
    lane = fx0 - fr0 - 0.20
    K.pipe_run("trunk", [(L2_RISER_X[-1], L2_RISER_EDGE, L2_TRUNK_Z),
                         (lane, L2_RISER_EDGE, L2_TRUNK_Z),
                         (lane, by0, L2_TRUNK_Z),
                         (bx0 - br0 * 0.55, by0, L2_TRUNK_Z)], 0.062, bend=0.16)
    K.pipe_run("trunk_br", [(fx0, L2_RISER_EDGE, L2_TRUNK_Z),
                            (fx0, fy0 - fr0 * 0.55, L2_TRUNK_Z)], 0.055)
    if abs(lane - fx0) < fr0:
        print("TRUNK RUNS THROUGH THE FRONT-LEFT TANK")

    # ---------------- the two RIGHTMOST domes pipe into the building, 2 bends each --------
    # Rightmost is a SCREEN fact, not a plan one: columns are (x+y), so the back rank's
    # right-hand tank outranks the front rank's despite sitting further left in x.
    order = sorted(domes, key=lambda t: t[0] + t[1])
    for i, (dxi, dy, dr, dtop) in enumerate(order[-2:]):
        apex = dtop + dr * 0.78
        legz = apex + 0.40
        # Both rightmost tanks share a world x now, so both drops would land on the same screen
        # line. The back one lands further back on the roof, which separates them by column.
        land = 1.30 + 0.40 * i
        K.pipe_run("crown%d" % i, [(dxi, dy, apex - 0.06), (dxi, dy, legz),
                                   (dxi, land, legz), (dxi, land, rh + 0.02)], 0.058,
                   bend=0.18)
        K.pipe_end("crown%d_end" % i, (dxi, land, rh + 0.02), (0, 0, -1), 0.058, "collar")
        if not (ry - rd / 2 < land < ry + rd / 2):
            print("CROWN PIPE %d LANDS OFF THE ROOF IN Y" % i)
        if not (rx - rw / 2 < dxi < rx + rw / 2):
            print("CROWN PIPE %d LANDS OFF THE SINGLE-STOREY ROOF" % i)

    # ---------------- concrete apron under the whole plant ----------------
    foot = [(fx, fy, fr), (sx_, sy_, sr)]
    foot += [(ux, uy, L2_FURN_R) for ux, uy, _ in L2_FURN]
    foot += [(dxi, dy, dr) for dxi, dy, dr, _ in domes]
    foot += [(px, L2_RISER_EDGE, 0.08) for px in L2_RISER_X]
    for ccx, ccy, csx, csy in ((rx, ry, rw, rd), (lx, ly, lw, ld), (qx, qy, qsx, qsy)):
        foot += [(ccx + ex * csx / 2, ccy + ey * csy / 2, 0.0)
                 for ex in (-1, 1) for ey in (-1, 1)]
    K.apron_slab("apron", Kit.slab_outline(foot), mat=K.mat("slab_cream"),
                 kerb=K.mat("slab_kerb"))

    # ---------------- checks ----------------
    def _clear(na, a, nb, b, margin=0.20):
        need = math.sqrt(2.0) * (a[2] + b[2])
        got = abs((b[0] + b[1]) - (a[0] + a[1]))
        if got < need + margin:
            print("%s AND %s TOO CLOSE ON SCREEN: |ds| %.2f, need %.2f + margin"
                  % (na.upper(), nb.upper(), got, need))

    for rank, (dy, xs, dr, _) in (("F", L2_DOMES_F), ("B", L2_DOMES_B)):
        for i in range(len(xs) - 1):
            _clear("dome%s%d" % (rank, i), (xs[i], dy, dr),
                   "dome%s%d" % (rank, i + 1), (xs[i + 1], dy, dr))
        if dy - dr < ry + rd / 2:
            print("DOME RANK %s FOULS THE BACK WALL" % rank)
    _clear("furn0", (L2_FURN[0][0], L2_FURN[0][1], L2_FURN_R),
           "furn1", (L2_FURN[1][0], L2_FURN[1][1], L2_FURN_R))
    for i, (ux, uy, _uh) in enumerate(L2_FURN):
        for j, (dxi, dy, dr, _) in enumerate(domes):
            _clear("furn%d" % i, (ux, uy, L2_FURN_R), "dome%d" % j, (dxi, dy, dr), margin=0.05)
    # Each back tank must share its front counterpart's screen column, and must out-top it or
    # standing directly behind buys nothing but a hidden tank.
    for i, (bxi, fxi) in enumerate(zip(L2_DOMES_B[1], L2_DOMES_F[1])):
        if abs(bxi - fxi) > 0.02:
            print("BACK DOME %d IS NOT ON THE FRONT RANK'S GRID LINE" % i)
        # It must out-top whichever FRONT tank shares its column — that is the one to its
        # right, not the one directly behind which is 1.40 of column away.
        ba = 0.4082 * (L2_DOMES_B[0] - bxi) + 0.8165 * (L2_DOMES_B[3] + L2_DOMES_B[2] * 0.78)
        for fxj in L2_DOMES_F[1]:
            if abs((fxj + L2_DOMES_F[0]) - (bxi + L2_DOMES_B[0])) > math.sqrt(2.0) * 2 * L2_DOMES_F[2]:
                continue
            fa = 0.4082 * (L2_DOMES_F[0] - fxj) + 0.8165 * (L2_DOMES_F[3]
                                                            + L2_DOMES_F[2] * 0.78)
            if ba < fa + 0.60:
                print("BACK DOME %d BARELY CLEARS A FRONT TANK (%.2f vs %.2f)" % (i, ba, fa))
    for wmsg in K.validate(ground=-0.21):
        print(wmsg)
    return {"building": "petro_refinery", "level": 2, "objects": len(K.col.objects)}


# ================================ L3 (owner composition) ================================
# L2's plant with the FRONT YARD built out: four flat-topped tanks and four spheres, each a
# 2x2 block on the world grid (same "behind = same x, further y" rule the dome ranks use), a
# third and BIGGER fired heater, and four transfer lines arcing over the building into the
# process tanks at the back.
L3_BLD_R = (-0.85, 1.15, 3.50, 1.25, 1.15)
L3_BLD_L = (-3.475, 1.15, 1.75, 1.25, 2.00)
# Within a rank the tanks need the full sqrt(2)*(r1+r2) or they fuse side by side — same
# height, same tone, nothing to separate them. ACROSS ranks they may overlap freely: the back
# one is further from the camera and lands higher on screen, so the pair reads as depth.
L3_FLAT_X, L3_FLAT_Y = (-3.85, -1.90), (-0.95, -2.15)
L3_FLAT_R, L3_FLAT_H = 0.60, 0.86
L3_SPH_X, L3_SPH_Y = (-0.65, 0.90), (-1.10, -2.50)
L3_SPH_R = 0.46
L3_DOMES_F = (2.70, (-4.10, -2.50, -0.90), 0.46, 1.80)
L3_DOMES_B = (4.10, (-4.10, -2.50, -0.90), 0.46, 2.40)
# cx, cy, height, r_base, r_top. The third is the big one.
L3_FURN = ((2.40, 2.10, 4.95, 0.28, 0.14), (2.00, 3.60, 4.30, 0.28, 0.14),
           (3.40, 3.40, 5.80, 0.34, 0.17))
L3_BOX = (1.18, 0.62, 0.60, 0.60, 1.02)
L3_TIE_Z = (0.46, 0.66, 0.86)
L3_RISER_X = (-4.15, -3.92, -3.69, -3.28, -3.05, -2.82)
L3_RISER_H = (1.05, 0.72, 0.90, 0.55, 0.80, 0.45)
L3_RISER_Y, L3_RISER_EDGE, L3_TRUNK_Z = 1.15, 1.955, 0.40
# The four over-the-building transfer lines: (src_x, src_y, is_sphere, lane_z, dome_x, back).
# LANE HEIGHTS ARE NOT DECORATIVE. A line crossing the two-storey block has to clear the roof
# risers standing on it (tops to 3.05), not just its parapet; the two that do are lifted, the
# two crossing the single-storey block are not.
L3_CROSS = ((-3.85, -0.95, False, 3.35, -4.10, True),
            (-1.90, -0.95, False, 2.60, -4.10, False),
            (-0.65, -1.10, True, 2.85, -0.90, False),
            (0.90, -1.10, True, 3.10, -0.90, True))


def _build_l3() -> dict:
    setup_rig()
    K = Kit(open_collection("BLDG_petro"))

    rx, ry, rw, rd, rh = L3_BLD_R
    lx, ly, lw, ld, lh = L3_BLD_L
    _hall_block(K, "hall", rx, ry, rw, rd, rh, storeys=1, door=False,
                keep_clear=(L3_SPH_X[1],))
    _hall_block(K, "hallL", lx, ly, lw, ld, lh, storeys=2, door=True)
    K.gate("hallL_gate", "-X", (lx - lw / 2, ly, 0.40), 0.54, 0.74, slats=5)

    # ---------------- four flat-topped tanks: front yard, 2 x 2 on the grid ----------------
    fr, fh = L3_FLAT_R, L3_FLAT_H
    flats = []
    for r_i, fy in enumerate(L3_FLAT_Y):
        for c_i, fx in enumerate(L3_FLAT_X):
            # The purple ring stays SPARING — two of the four carry it. It is the sprite's
            # only chroma, and on all four it stops being an accent.
            K.flat_tank("flat%d%d" % (r_i, c_i), fx, fy, fr, fh, band=False,
                        base_band=(r_i == 0), stair=False, roof_rise=0.06,
                        mat=K.mat("wall_shell"))
            flats.append((fx, fy))

    # ---------------- four sphere tanks, likewise ----------------
    sr = L3_SPH_R
    sphs = []
    for r_i, sy in enumerate(L3_SPH_Y):
        for c_i, sx in enumerate(L3_SPH_X):
            K.sphere_tank("sph%d%d" % (r_i, c_i), sx, sy, sr, legs=6, mat=K.mat("drum"))
            sphs.append((sx, sy))

    # ---------------- six domed process tanks, two ranks behind the building --------------
    domes = []
    for tag, (dy, xs, dr, dtop) in (("F", L3_DOMES_F), ("B", L3_DOMES_B)):
        for i, dxi in enumerate(xs):
            K.dome_vessel("dome%s%d" % (tag, i), dxi, dy, dr, dtop, skirt=0.24,
                          seams=(0.36, 0.72), dome_ratio=0.78, mat=K.mat("column"))
            domes.append((dxi, dy, dr, dtop))

    # ---------------- front-yard plumbing: tank -> sphere, sphere -> building -------------
    scz = sr * 1.35
    for i, (rowf, rows) in enumerate(((0, 0), (1, 1))):
        fx, fy = L3_FLAT_X[1], L3_FLAT_Y[rowf]
        sx, sy = L3_SPH_X[0], L3_SPH_Y[rows]
        fdx = math.sqrt(max(0.01, fr * fr - (sy - fy) ** 2))
        for j, (pz, drop) in enumerate(zip((0.82, 0.60), (0.60, 0.40))):
            ez = sx - math.sqrt(max(0.01, sr * sr - (drop - scz) ** 2))
            turn = fx + fdx + 0.28 + j * 0.22
            K.pipe_run("xfer%d%d" % (i, j), [(fx + fdx - 0.03, sy, pz), (turn, sy, pz),
                                             (turn, sy, drop), (ez, sy, drop)], 0.050,
                       bend=0.09)
            K.pipe_end("xfer%d%d_f" % (i, j), (fx + fdx - 0.03, sy, pz), (-1, 0, 0), 0.050,
                       "flange")
    K.pipe_run("main", [(L3_SPH_X[1], L3_SPH_Y[0] + sr * 0.62, 0.70),
                        (L3_SPH_X[1], ry - rd / 2 - 0.04, 0.70)], 0.105)
    K.pipe_end("main_end", (L3_SPH_X[1], ry - rd / 2 - 0.04, 0.70), (0, 1, 0), 0.105, "collar")

    # ---------------- three fired heaters ----------------
    for i, (ux, uy, uh, ur, urt) in enumerate(L3_FURN):
        K.furnace_stack("furn%d" % i, ux, uy, ur, uh, r_top=urt)

    # ---------------- corner plant box, and ties from all three heaters -------------------
    qx, qy, qsx, qsy, qh = L3_BOX
    K.box("qbox", qx, qy, qh / 2, qsx, qsy, qh, K.mat("wall_grey"))
    K.box("qbox_deck", qx, qy, qh + 0.012, qsx - 0.02, qsy - 0.02, 0.05, K.mat("roof_deck"))
    K.box("qbox_cope", qx, qy, qh + 0.055, qsx + 0.07, qsy + 0.07, 0.07, K.mat("roof"))
    K.cyl("qbox_vent", qx + qsx * 0.24, qy - qsy * 0.18, qh + 0.24, 0.055, 0.34,
          K.mat("pipe"), segments=12)
    ux0, uy0, uh0, ur0, urt0 = L3_FURN[0]
    for i, tz in enumerate(L3_TIE_Z):
        K.pipe_run("tie%d" % i, [(ux0, uy0 - Kit.r_at(ur0, urt0, uh0, tz) - 0.02, tz),
                                 (ux0, qy, tz), (qx + qsx / 2 + 0.03, qy, tz)], 0.042,
                   bend=0.13)
        K.pipe_end("tie%d_end" % i, (qx + qsx / 2 + 0.03, qy, tz), (1, 0, 0), 0.042, "collar")
    # The other two run to the building's east wall, each on its OWN lane — three bundles
    # converging on one small box reads as a knot.
    for n, (idx, lane, zs) in enumerate(((1, 1.20, (0.52, 0.76)), (2, 1.58, (0.46, 0.70, 0.94)))):
        ux, uy, uh, ur, urt = L3_FURN[idx]
        for i, tz in enumerate(zs):
            K.pipe_run("tieB%d_%d" % (n, i),
                       [(ux, uy - Kit.r_at(ur, urt, uh, tz) - 0.02, tz), (ux, lane, tz),
                        (rx + rw / 2 + 0.04, lane, tz)], 0.042, bend=0.13)
            K.pipe_end("tieB%d_%d_end" % (n, i), (rx + rw / 2 + 0.04, lane, tz), (1, 0, 0),
                       0.042, "collar")

    # ---------------- roof risers -> back edge -> down -> the left tanks ------------------
    for i, (px, ph) in enumerate(zip(L3_RISER_X, L3_RISER_H)):
        K.pipe_run("riser%d" % i, [(px, L3_RISER_Y, lh - 0.06), (px, L3_RISER_Y, lh + ph),
                                   (px, L3_RISER_EDGE, lh + ph),
                                   (px, L3_RISER_EDGE, L3_TRUNK_Z)], 0.055, bend=0.13)
    fx0, fy0, fr0 = L3_DOMES_F[1][0], L3_DOMES_F[0], L3_DOMES_F[2]
    bx0, by0, br0 = L3_DOMES_B[1][0], L3_DOMES_B[0], L3_DOMES_B[2]
    lane = fx0 - fr0 - 0.20
    K.pipe_run("trunk", [(L3_RISER_X[-1], L3_RISER_EDGE, L3_TRUNK_Z),
                         (lane, L3_RISER_EDGE, L3_TRUNK_Z), (lane, by0, L3_TRUNK_Z),
                         (bx0 - br0 * 0.55, by0, L3_TRUNK_Z)], 0.062, bend=0.16)
    K.pipe_run("trunk_br", [(fx0, L3_RISER_EDGE, L3_TRUNK_Z),
                            (fx0, fy0 - fr0 * 0.55, L3_TRUNK_Z)], 0.055)

    # ---------------- four transfer lines OVER the building into the back tanks -----------
    for i, (sx, sy, is_sph, lane_z, dx, back) in enumerate(L3_CROSS):
        top = (sr * 2.35 - 0.06) if is_sph else fh
        dy, dtop, dr = ((L3_DOMES_B[0], L3_DOMES_B[3], L3_DOMES_B[2]) if back
                        else (L3_DOMES_F[0], L3_DOMES_F[3], L3_DOMES_F[2]))
        apex = dtop + dr * 0.78
        pts = [(sx, sy, top), (sx, sy, lane_z), (sx, dy, lane_z)]
        if abs(dx - sx) > 0.02:
            pts.append((dx, dy, lane_z))
        pts.append((dx, dy, apex - 0.05))
        # Thinner than the ground trunks. Four of these arc over the whole sprite; at the
        # trunk radius their 7px contours alone out-mass the building they cross.
        K.pipe_run("cross%d" % i, pts, 0.048, bend=0.16)
        if lane_z < apex + 0.20:
            print("CROSS %d RUNS THROUGH A DOME IT PASSES" % i)

    # ---------------- concrete apron under the whole plant ----------------
    foot = [(x, y, fr) for x, y in flats] + [(x, y, sr) for x, y in sphs]
    foot += [(ux, uy, ur) for ux, uy, _uh, ur, _urt in L3_FURN]
    foot += [(dxi, dy, dr) for dxi, dy, dr, _ in domes]
    foot += [(px, L3_RISER_EDGE, 0.08) for px in L3_RISER_X]
    for ccx, ccy, csx, csy in ((rx, ry, rw, rd), (lx, ly, lw, ld), (qx, qy, qsx, qsy)):
        foot += [(ccx + ex * csx / 2, ccy + ey * csy / 2, 0.0)
                 for ex in (-1, 1) for ey in (-1, 1)]
    K.apron_slab("apron", Kit.slab_outline(foot), mat=K.mat("slab_cream"),
                 kerb=K.mat("slab_kerb"))

    # ---------------- checks ----------------
    def _clear(na, a, nb, b, margin=0.20):
        need = math.sqrt(2.0) * (a[2] + b[2])
        got = abs((b[0] + b[1]) - (a[0] + a[1]))
        if got < need + margin:
            print("%s AND %s TOO CLOSE ON SCREEN: |ds| %.2f, need %.2f + margin"
                  % (na.upper(), nb.upper(), got, need))

    # within a rank only — across ranks overlap is the intended depth read
    for nm, xs, ys, rr in (("flat", L3_FLAT_X, L3_FLAT_Y, fr), ("sph", L3_SPH_X, L3_SPH_Y, sr)):
        for yi, yy in enumerate(ys):
            for ci in range(len(xs) - 1):
                _clear("%s%d%d" % (nm, yi, ci), (xs[ci], yy, rr),
                       "%s%d%d" % (nm, yi, ci + 1), (xs[ci + 1], yy, rr))
    for i in range(len(L3_FURN) - 1):
        _clear("furn%d" % i, L3_FURN[i][:2] + (L3_FURN[i][3],),
               "furn%d" % (i + 1), L3_FURN[i + 1][:2] + (L3_FURN[i + 1][3],))
    for i, (ux, uy, _uh, ur, _urt) in enumerate(L3_FURN):
        for j, (dxi, dy, dr, _) in enumerate(domes):
            _clear("furn%d" % i, (ux, uy, ur), "dome%d" % j, (dxi, dy, dr), margin=0.05)
    # A transfer line has to clear the ROOF RISERS it flies over, not merely the parapet.
    for i, (sx, sy, _is, lane_z, dx, _b) in enumerate(L3_CROSS):
        for px, ph in zip(L3_RISER_X, L3_RISER_H):
            if abs(px - sx) < 0.14 and lane_z < lh + ph + 0.16:
                print("CROSS %d CLIPS RISER AT x=%.2f" % (i, px))
    if any(y + fr > ry - rd / 2 for _x, y in flats) or any(y + sr > ry - rd / 2
                                                          for _x, y in sphs):
        print("FRONT YARD FOULS THE BUILDING")
    for wmsg in K.validate(ground=-0.21):
        print(wmsg)
    return {"building": "petro_refinery", "level": 3, "objects": len(K.col.objects)}
