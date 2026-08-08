# Parametric builder for the Power Plant. Run AFTER sprite_kit.py:
#   exec(open(".../sprite_kit.py").read())
#   exec(open(".../power_plant_builder.py").read()); build_power_plant(2)
#
# Brief (owner, 2026-07-31): large cooling tower, transformer yard and substation, main
# building with a flat roof. Revised: ducts between the towers AT THEIR FEET, the transformer
# boxes gathered into a rectangle directly right of the hall, MUSTARD YELLOW (the game's power
# colour) as a dado on the ground floor plus small equipment stripes, an exposed turbine and a
# second storey at L3, factory-proportion 2x3 windows standing BESIDE the door, and towers 25%
# taller than the first pass.
#
# LAYOUT, in the owner's screen vocabulary (back = +Y / top-right, right = +X / lower-right):
#   * COOLING TOWERS across the BACK. At 50px the tower silhouette is the only part that still
#     says "power plant".
#   * TURBINE HALL centre-left, flat-roofed, glazed flank facing the camera.
#   * TRANSFORMER COMPOUND directly right of the hall, in line with it.
#   * TURBINE (L3) on the free frontage in front of the hall.
#
# OCCLUSION IS PER SCREEN COLUMN. Two things can only overlap if their (x + y) match; only
# then does screen height, z - (x - y)/2, decide which wins. Comparing heights at different
# columns is meaningless — an earlier version of the duct check did exactly that, wrongly
# concluded the run was buried behind the hall, and pushed the bridge up to the tower throats.
#
# No ground slab: like the factory and furnace, the structures sit directly on z=0.

import math

# ---------------- per-level parameters ----------------
# PREFIXED: every builder is exec'd into ONE globals dict, so a plain `LEVELS`
# lets the last file loaded silently overwrite the others' level tables.
PP_LEVELS = {
    1: dict(hall_x0=-1.70, floors=1, tower=None, flue_top=3.69, tower_cy=1.95,
            transformers=2, gantry=False, roof_plant=False, turbine=False,
            pylon=(1.70, 0.42, 1, True)),
    2: dict(hall_x0=-2.45, floors=1, tower=(1.05, 3.69), flue_top=3.69, tower_cy=1.95,
            transformers=4, gantry=True,  roof_plant=True,  turbine=False,
            pylon=(2.35, 0.54, 2, True)),
    3: dict(hall_x0=-2.45, floors=2, tower=(1.05, 3.69), flue_top=3.69, tower_cy=1.95,
            transformers=6, gantry=True,  roof_plant=True,  turbine=True,
            pylon=(3.00, 0.66, 3, True)),
}

HALL_X1 = 0.65
HALL_Y0, HALL_Y1 = -0.90, 0.50
FLOOR_H = 1.15                      # one storey; L3 stacks two
TOWER_CX = 1.62
YARD = (1.00, 2.60, -0.90, 0.50)    # transformer compound: in line with the hall, to its right
PAD_H = 0.10                        # switchyard slab thickness
# BOILER HOUSE: single storey, DEEP (2.1 in y against 1.75 in x) — it is the plant room the
# flue serves, so it reads as a long low shed rather than another cube.
BOILER = (-2.70, -0.95, 0.80, 2.90)  # x0, x1, y0, y1
BOILER_H = 1.15
FLUE_XY = (-1.62, 2.18)             # the flue rises out of the boiler house roof
DUCT_Z = 0.62                       # at the tower's foot, on the widest part of the shell
DUCT_YS = (2.28, 2.48, 2.68)        # run along the BACK (owner) — clear of the hall entirely
# The pylon sits to the RIGHT of the compound and shares its y band, so hall -> transformers
# -> pylon lie on one isometric axis and read left to right as the power actually flows. In
# front of the yard (the previous placement) it broke that line and its cross-arms landed on
# the transformers.
PYLON_XY = (3.22, -0.20)
FLUE_TOP = 3.69                     # the SAME on every level (owner): the flue is the plant's
                                    # constant vertical, so it must not shrink at L1 where it
                                    # is the only one. Asserted below against every level.
WIN_W, WIN_H = 0.34, 0.58           # factory proportion: 2 panes wide, 3 tall
DOOR_TOP = 0.76                     # ground-floor windows share this head line with the door


def build_power_plant(level: int = 2) -> dict:
    p = PP_LEVELS[level]
    setup_rig()
    K = Kit(open_collection("BLDG_powerplant"))
    hx0 = p["hall_x0"]
    r_base, t_h = p["tower"] if p["tower"] else (0.0, 0.0)
    hall_h = FLOOR_H * p["floors"]
    hall_max_xy = HALL_X1 + HALL_Y1     # the hall's furthest screen column

    def hall_top_at(col):
        """Highest the hall reaches in screen column `col` (points with x + y = col), as a
        screen height z - (x - y)/2. Returns -inf where the hall does not reach that column.
        Sharing a column is NOT the same as being hidden — height still has to lose — so both
        halves belong in one predicate."""
        y = min(HALL_Y1, max(HALL_Y0, col - hx0))
        x = col - y
        if x < hx0 - 1e-6 or x > HALL_X1 + 1e-6:
            return -1e9
        return (hall_h + 0.11) - (x - y) / 2.0

    # ---------------- cooling tower (back-right; L2+ only) ----------------
    # L1 has no tower at all (owner): it is the plant before the cooling works were built, so
    # the flue on the boiler house carries the whole vertical.
    tw = None
    if p["tower"]:
        tw = K.cooling_tower("tower", TOWER_CX, p["tower_cy"], 0.0, t_h,
                             r_base=r_base, r_throat=r_base * 0.71, legs=10, bands=3)

    # ---------------- turbine hall ----------------
    cx = (hx0 + HALL_X1) / 2.0
    cy = (HALL_Y0 + HALL_Y1) / 2.0
    w = HALL_X1 - hx0
    d = HALL_Y1 - HALL_Y0
    # TWO stacked boxes, so the mustard dado wraps every face instead of being a decal on one
    # wall: lower half of the ground floor in the power livery, everything above it in steel.
    dado = FLOOR_H * 0.5
    K.box("hall_dado", cx, cy, dado / 2.0, w, d, dado, K.mat("power_accent"))
    K.box("hall", cx, cy, dado + (hall_h - dado) / 2.0, w, d, hall_h - dado,
          K.mat("wall_pale"))
    # The roof DECK is its own dark plate: the largest horizontal surface in the sprite, and
    # the composition's dark tier against the pale tower.
    K.box("hall_deck", cx, cy, hall_h + 0.012, w - 0.02, d - 0.02, 0.05, K.mat("roof_deck"))
    # PARAPET, not a lid — four bars round the perimeter. A full-footprint coping box simply
    # covers the deck it exists to reveal.
    for tag, (px, py, sx_, sy_) in {
        "f": (cx, HALL_Y0 - 0.02, w + 0.10, 0.10),
        "b": (cx, HALL_Y1 + 0.02, w + 0.10, 0.10),
        "l": (hx0 - 0.02, cy, 0.10, d + 0.10),
        "r": (HALL_X1 + 0.02, cy, 0.10, d + 0.10),
    }.items():
        K.box("hall_parapet_%s" % tag, px, py, hall_h + 0.055, sx_, sy_, 0.11, K.mat("roof"))

    # Windows: factory proportion, and the DOOR OWNS THE FIRST BAY so the ground-floor windows
    # stand BESIDE it in the same band rather than one sitting directly above it. Their heads
    # share the door's top line, which is what makes the row read as one band.
    bays = max(4, int(round(w / 0.62)))
    for f in range(p["floors"]):
        wz = (DOOR_TOP - WIN_H / 2.0) if f == 0 else (FLOOR_H * f + FLOOR_H * 0.54)
        for b in range(bays):
            if f == 0 and b == 0:
                continue                                  # the door's bay
            bx = hx0 + w * (b + 0.5) / bays
            K.window("hall_w%d_%d" % (f, b), "-Y", (bx, HALL_Y0, wz), WIN_W, WIN_H,
                     cols=2, rows=3)
        if f:
            K.seam_bar("hall_floor%d" % f, cx, HALL_Y0 - 0.03, FLOOR_H * f, w + 0.02,
                       0.04, 0.04)
    K.door("hall_door", "-Y", (hx0 + w * 0.5 / bays, HALL_Y0, DOOR_TOP - 0.37), 0.32, 0.74,
           ribs=3)
    K.gate("hall_gate", "-X", (hx0, cy + 0.10, 0.36), 0.52, 0.68, slats=5)
    K.box("hall_louvre", cx, HALL_Y1 + 0.02, hall_h - 0.24, w * 0.72, 0.04, 0.16,
          K.mat("opening"))

    if p["roof_plant"]:
        K.box("roof_block", cx + w * 0.18, cy, hall_h + 0.32, w * 0.30, d * 0.52, 0.46,
              K.mat("wall_pale"))
        K.box("roof_block_cap", cx + w * 0.18, cy, hall_h + 0.58, w * 0.30 + 0.08,
              d * 0.52 + 0.08, 0.07, K.mat("roof"))
        K.walkway("roof_walk", hx0 + 0.25, cx + w * 0.02, cy + d * 0.22, hall_h + 0.10,
                  width=0.30, rail_h=0.20, posts=5)
        # (the pair of thin grey roof vents that used to stand here read as small chimneys and
        # competed with the flue for the same job — removed, owner 2026-07-31)

    # ---------------- switchyard: ONE concrete pad under the transformers AND the pylon ----
    # Without it the equipment and the pylon legs stand on nothing and dissolve into the
    # background, and the two read as unrelated objects rather than one switchyard. Extents are
    # DERIVED from the yard rectangle and the pylon's own base width, so a level that widens
    # either still lands on its pad.
    yx0, yx1, yy0, yy1 = YARD
    py_h, py_w, py_tiers, py_ins = p["pylon"]
    px0 = min(yx0, PYLON_XY[0] - py_w / 2.0) - 0.12
    px1 = max(yx1, PYLON_XY[0] + py_w / 2.0) + 0.12
    py0 = min(yy0, PYLON_XY[1] - py_w / 2.0) - 0.12
    py1 = max(yy1, PYLON_XY[1] + py_w / 2.0) + 0.12
    K.box("yard_pad", (px0 + px1) / 2, (py0 + py1) / 2, PAD_H / 2.0, px1 - px0, py1 - py0,
          PAD_H, K.mat("yard_pad"))
    # A kerb just proud of the slab edge: the pad's own silhouette is a single ink line, and a
    # lipped edge is what makes it read as a raised slab rather than a painted rectangle.
    for tag, (kx, ky, ksx, ksy) in {
        "f": ((px0 + px1) / 2, py0, px1 - px0 + 0.05, 0.05),
        "b": ((px0 + px1) / 2, py1, px1 - px0 + 0.05, 0.05),
        "l": (px0, (py0 + py1) / 2, 0.05, py1 - py0 + 0.05),
        "r": (px1, (py0 + py1) / 2, 0.05, py1 - py0 + 0.05),
    }.items():
        K.box("pad_kerb_%s" % tag, kx, ky, PAD_H - 0.012, ksx, ksy, 0.05, K.mat("wall_grey"))
    n = p["transformers"]
    rows = 2 if n > 2 else 1
    per = int(math.ceil(n / float(rows)))
    placed = 0
    for r in range(rows):
        ty = yy1 - (yy1 - yy0) * (r + 0.5) / rows
        for i in range(min(per, n - placed)):
            tx = yx0 + (yx1 - yx0) * (i + 0.5) / per
            K.transformer("tx%d_%d" % (r, i), tx, ty, PAD_H, s=0.86, accent=True)
            placed += 1
    # Feeders straight out of the hall's right flank into the compound.
    for i in range(rows):
        fy = yy1 - (yy1 - yy0) * (i + 0.5) / rows
        K.dircyl("feed%d" % i, (HALL_X1 + 0.02, fy, 0.86), (yx0 + 0.24, fy, 0.72),
                 0.020, K.mat("pipe"), segments=6)
    for tag, (a, b) in {
        "f": ((yx0, yy0), (yx1, yy0)), "b": ((yx0, yy1), (yx1, yy1)),
        "l": ((yx0, yy0), (yx0, yy1)), "r": ((yx1, yy0), (yx1, yy1)),
    }.items():
        K.dircyl("fence_%s" % tag, (a[0], a[1], PAD_H + 0.30), (b[0], b[1], PAD_H + 0.30),
                 0.014, K.mat("scaffold"), segments=6)

    if p["gantry"]:
        K.substation_gantry("gantry", (yx1 - 0.06, yy0 + 0.18), (yx1 - 0.06, yy1 - 0.18),
                            PAD_H, 1.02, strings=2, bays=1)

    # ---------------- boiler house + banded flue (all levels) ----------------
    bx0, bx1, by0, by1 = BOILER
    bcx, bcy = (bx0 + bx1) / 2.0, (by0 + by1) / 2.0
    bw, bd = bx1 - bx0, by1 - by0
    K.box("boiler_dado", bcx, bcy, 0.13, bw, bd, 0.26, K.mat("power_accent"))
    K.box("boiler", bcx, bcy, 0.26 + (BOILER_H - 0.26) / 2.0, bw, bd, BOILER_H - 0.26,
          K.mat("wall_pale"))
    K.box("boiler_deck", bcx, bcy, BOILER_H + 0.012, bw - 0.02, bd - 0.02, 0.05,
          K.mat("roof_deck"))
    for tag, (px, py, sx_, sy_) in {
        "f": (bcx, by0 - 0.02, bw + 0.10, 0.10), "b": (bcx, by1 + 0.02, bw + 0.10, 0.10),
        "l": (bx0 - 0.02, bcy, 0.10, bd + 0.10), "r": (bx1 + 0.02, bcy, 0.10, bd + 0.10),
    }.items():
        K.box("boiler_parapet_%s" % tag, px, py, BOILER_H + 0.055, sx_, sy_, 0.11,
              K.mat("roof"))
    # Glazing on the -Y flank (the one facing the camera) and a louvre band on the right.
    for b in range(3):
        K.window("boiler_w%d" % b, "-Y", (bx0 + bw * (b + 0.5) / 3.0, by0, DOOR_TOP - WIN_H / 2.0),
                 WIN_W, WIN_H, cols=2, rows=3)
    K.box("boiler_louvre", bx1 + 0.02, bcy, BOILER_H - 0.26, 0.04, bd * 0.66, 0.18,
          K.mat("opening"))

    # The flue rises OUT of the boiler house roof and is topped out level with the cooling
    # tower, so the two verticals read as a pair rather than a tall thing beside a short one.
    fl = K.flue_stack("flue", FLUE_XY[0], FLUE_XY[1], BOILER_H, p["flue_top"] - BOILER_H,
                      r_base=0.36, r_top=0.30, bands=7)

    # ---------------- ducts: boiler house -> the large cooling tower ----------------
    # Pushed to the BACK (owner): at y >= 2.28 the run sits past the hall's furthest screen
    # column entirely, so it is clear at one storey and two alike and needs no height solve.
    duct_ys = list(DUCT_YS) if tw else []
    for i, py in enumerate(duct_ys):
        r1 = tw["radius_at"](DUCT_Z)
        d1 = r1 * r1 - (py - tw["cy"]) ** 2
        if d1 <= 0.0:
            print("DUCT %d MISSES THE TOWER at y=%.2f" % (i, py))
            continue
        xa = bx1
        xb = tw["cx"] - math.sqrt(d1)
        duct_h = DUCT_Z - (xa - py) / 2.0
        if duct_h < hall_top_at(xa + py):
            print("DUCT %d HIDDEN BY THE HALL: height %.2f vs hall %.2f at column %.2f"
                  % (i, duct_h, hall_top_at(xa + py), xa + py))
        K.dircyl("duct%d" % i, (xa, py, DUCT_Z), (xb, py, DUCT_Z), 0.095,
                 K.mat("duct"), segments=16)
        K.pipe_end("duct%d_a" % i, (xa, py, DUCT_Z), (-1, 0, 0), 0.095, "collar")
        K.pipe_end("duct%d_b" % i, (xb, py, DUCT_Z), (1, 0, 0), 0.095, "collar")

    # NOTE (owner decision recorded): L3's small second cooling tower is GONE. The boiler house
    # now owns the back-left and the big tower the back-right, which leaves only a ~1.2-wide
    # gap between them; a shell squeezed into that is slender enough to read as another
    # chimney — the very confusion that removing the grey roof vents was meant to fix. It also
    # sat exactly across the y band the ducts need once the hall gains its second storey. L3
    # is still distinguished by the second floor, the exposed turbine and six transformers.

    # ---------------- transmission pylon (front-right, outboard of the compound) ----------------
    # It grows with the level exactly as the plant's export capacity would: taller and wider,
    # gaining insulator strings at L3. Same fine ink as the transformers.
    # tiers, not arms: each tier is a PAIR, so 1/2/3 tiers give the 2/4/6 arms asked for.
    pyl = K.pylon("pylon", PYLON_XY[0], PYLON_XY[1], PAD_H, py_h, w_base=py_w,
                  tiers=py_tiers, insulators=py_ins)

    if p["turbine"]:
        K.turbine("turb", cx + 0.10, HALL_Y0 - 0.86, 0.0, length=1.72, s=1.08, accent=True)

    # ---------------- checks ----------------
    if tw:
        if TOWER_CX - r_base < HALL_X1 and p["tower_cy"] - r_base < HALL_Y1:
            print("TOWER OVERLAPS HALL")
        if p["tower_cy"] - r_base < YARD[3]:
            print("TOWER OVERLAPS THE COMPOUND")
        if BOILER[1] > TOWER_CX - r_base and BOILER[3] > p["tower_cy"] - r_base:
            print("BOILER HOUSE OVERLAPS THE TOWER")
        for py in duct_ys:
            if abs(py - p["tower_cy"]) >= tw["radius_at"](DUCT_Z):
                print("DUCT AT y=%.2f CANNOT REACH THE TOWER SHELL" % py)
            if py > BOILER[3] or py < BOILER[2]:
                print("DUCT AT y=%.2f LEAVES THE BOILER HOUSE WALL" % py)
    if BOILER[3] > HALL_Y1 and BOILER[1] > HALL_X1:
        print("BOILER HOUSE OVERLAPS THE HALL")
    # Sharing the compound's y band is the POINT now, so the clearance that matters is in x:
    # the pylon's legs (and its girder, which lies at constant x) must stay outboard of the
    # yard fence.
    if PYLON_XY[0] + py_w / 2.0 > px1 - 0.05 or PYLON_XY[1] + py_w / 2.0 > py1 - 0.05:
        print("PYLON FEET OVERHANG THE PAD")
    if PYLON_XY[0] - py_w / 2.0 < YARD[1] + 0.15:
        print("PYLON TOO CLOSE TO THE COMPOUND: %.2f vs yard right edge %.2f"
              % (PYLON_XY[0] - py_w / 2.0, YARD[1]))
    if tw and PYLON_XY[0] - py_w / 2.0 < TOWER_CX + r_base \
            and PYLON_XY[1] + pyl["half_y"] > p["tower_cy"] - r_base:
        print("PYLON FOULS THE COOLING TOWER")
    if abs(fl["top"] - FLUE_TOP) > 0.02:
        print("FLUE HEIGHT DRIFTED FROM THE SET VALUE: %.2f vs %.2f" % (fl["top"], FLUE_TOP))
    if tw and abs(fl["top"] - tw["top"]) > 0.02:
        print("FLUE NOT TOPPED OUT WITH THE TOWER: %.2f vs %.2f" % (fl["top"], tw["top"]))
    for wmsg in K.validate(ground=0.0):
        print(wmsg)
    return {"building": "power_plant", "level": level, "floors": p["floors"],
            "tower_top": round(tw["top"], 2) if tw else None, "transformers": n,
            "objects": len(K.col.objects)}
