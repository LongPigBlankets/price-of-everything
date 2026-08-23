# Parametric builder for the Electrolyser (b_020, internal_name `electrolyser`).
# Run AFTER sprite_kit.py:
#   exec(open(".../sprite_kit.py").read())
#   exec(open(".../electrolyser_builder.py").read()); build_electrolyser(2)
#
# Brief (owner, 2026-08-21, mirrored layout): CELL STACKS on the RIGHT, transformers in the
# MIDDLE, tanks on the LEFT, shed back-RIGHT, grid PYLON back-LEFT. Forest green accents;
# stack count = level (1/2/3).
#
# THE MIRROR IS A ROTATION, NOT A REFLECTION. Reflecting x -> -x would put the end plates and
# rod banks — the building's signature detail — on the barrels' -X ends, which sit on the
# SILHOUETTE at this camera and vanish. So the stacks turn 90 degrees instead: barrels run
# along Y (front to back), ranked along X, with every end plate and bank on the -Y end,
# facing the camera square-on. Everything else then re-routes around that.
#
# LAYOUT in the owner's screen vocabulary (back = +Y / top-right, right = +X / lower-right):
#   * STACKS right, barrels front-to-back, banks facing front.
#   * TRANSFORMERS a rank along Y in the true middle band, feeding a copper BUS that runs
#     across the stack fronts overhead and drops onto each bank.
#   * TANK FARM left (2x2 block), swan-necking LEFT onto the header main at the yard edge.
#   * SHED back-right (gas processing), EXT + LIQUID TANK at L3.
#   * PYLON back-left: the grid tie the yard lost when the substation towers were cut.
#   * BATTERY front-middle-left, beside the transformer rank it feeds. Present at every level.

import math

# Forest green, per the owner. Held well down: a thin member at a high value reads as a
# highlight rather than as paint. The darker variant is for masses.
PALETTE["forest"] = (0.085, 0.255, 0.105)
PALETTE["forest_lo"] = (0.038, 0.118, 0.052)
ROLES["tie_rod"] = "forest"
ROLES["skid"] = "steel_mid"
# Copper for the electrics. Same entries the EAF adds — PALETTE is a plain dict, so declaring
# them in both builders is idempotent and neither depends on the other having been exec'd.
PALETTE["copper"] = (0.435, 0.195, 0.075)
PALETTE["copper_lo"] = (0.250, 0.108, 0.042)
ROLES["busbar"] = "copper"
ROLES["busbar_lo"] = "copper_lo"

# The stack count IS the level: identical units, which is what an electrolyser hall actually
# is, so the upgrade reads as capacity rather than decoration.
ELY_LEVELS = {
    # The shed is present from L1 (owner call): the plant always has its process building,
    # and L1's single tank connects to it by a SINGLE pipe — the pipe pairs arrive at L2.
    1: dict(stacks=1, tanks=1, pipes=1, shed=True, liquid=False, ext=False),
    2: dict(stacks=2, tanks=2, pipes=2, shed=True, liquid=False, ext=False),
    3: dict(stacks=3, tanks=4, pipes=2, shed=True, liquid=True,  ext=True),
}

# ---- the cell stacks (RIGHT, barrels along Y) ----------------------------------------------
STK_Y0, STK_Y1 = -0.90, 1.90     # barrel extent in depth
STK_R = 0.60
STK_Z = 1.18                     # axis height
# Ranked along X. Build order: L1 takes the middle lane, L2 adds the right, L3 the left —
# existing stacks never move ("upgrades extend, they never relocate").
STK_XS = (2.30, 4.05, 0.55)
STK_BANDS = 13                   # lamination flutes, as material slots (see _ridged_barrel_y)
TIE_RODS = 5
TIE_R = STK_R + 0.075
SKID_H = 0.34
# Gas riser lane per stack, as an X-offset from the barrel axis. NOT uniform: each offset is
# chosen to land between two tie-rods (rod x-offsets are 0, +-0.397, +-0.64, and a lane needs
# 0.106 of clearance) AND inside the shed's x-span so the run has a wall to enter.
RISER_OFF = (-0.28, -0.52, 0.28)

# ---- electrics (MIDDLE) ---------------------------------------------------------------------
TR_X = -1.05                     # the transformer rank: the true middle band of the yard
TR_YS = (-1.05, 0.25, 1.55)
RECT_S = 2.05
# The copper BUS: transformers cannot cable straight to the banks — a run from the middle band
# to the far stack passes THROUGH the nearer barrels (checked, not guessed: a sag from y 0.25
# toward y -1.25 is still inside the neighbouring stack's x-span while already inside the
# barrel band y >= -0.90). So the power goes UP: a takeoff post at the bus's left end, an
# overhead copper bus across the stack fronts, and an L-shaped drop onto each bank.
BUS_Y, BUS_Z = -1.55, 2.30
BATT_X, BATT_Y = -1.10, -2.90    # battery front-middle-left, long axis Y, beside the rank
BATT_W, BATT_L, BATT_H = 1.05, 2.40, 1.28

# ---- tank farm (LEFT) -----------------------------------------------------------------------
TANK_R, TANK_H = 0.46, 1.30
# 2x2 block. Identical vessels (owner call): the duplicated-object trap is handled by the
# columns landing at different screen heights, so the block reads as a farm.
TANKS = ((-2.20, -0.90), (-3.20, -0.90), (-2.20, -1.80), (-3.20, -1.80))
# The gas HEADER main runs down the yard's LEFT edge, behind the tanks, and crosses to the
# shed along the back. Tanks tap it with swan-necks over their own domes.
HDR_X = -3.88
HDR_Z = 0.83
HDR_R = 0.10
HDR_BEND = 0.18
HDR_XRUN_Y = 3.10                # cross run: in front of the shed and the pylon, behind plant
HDR_WALL_X = 1.35                # where it enters the shed front wall
BR_R = 0.058                     # branch radius

# ---- buildings and landmarks ----------------------------------------------------------------
SHED = (0.55, 3.65, 3.30, 4.90)  # back-RIGHT
SHED_H, SHED_RISE = 1.85, 0.72
EXT = (0.85, 2.35, 4.80, 6.10)   # L3 flat-roofed extension; x1 held in so its back-right
                                 # corner stays inside the frame's column budget
LIQ = (-0.85, 4.40, 0.60, 1.55)  # L3 flat-top liquid tank, LEFT of the shed
PYLON_XY = (-3.10, 3.90)         # back-LEFT, the grid tie
# THREE tiers, not two. `tiers` counts PAIRS, so 3 gives six arms and — the point — three
# insulator strings on the -Y side, one per phase, which is what lets each conductor land on
# its own string instead of three bundling onto one arm. Raised to 3.40 at the same time: the
# extra tier hangs BELOW the others, and at 2.90 the lowest string sat at z 1.20, under the
# transformer's 1.42 bushing tops, so that phase would have run uphill to the tower. 3.40 put
# it at 1.405 — level to within 15 mm, which reads as a drawing error rather than a cable; the
# lowest conductor's height is 0.4191*H - 0.02, so 3.70 is the shortest tower that gives all
# three a visible fall toward the transformer.
PYLON_H, PYLON_W, PYLON_TIERS = 3.70, 0.62, 3
# Where the incoming line actually lands, DERIVED from pylon()'s own arm maths rather than
# eyeballed: lower tier (t=1), -Y side (the arm facing the yard), tip minus the insulator
# drop. Recomputed by _pylon_conductor() so the cable follows if the pylon is ever resized.
# WHERE A CABLE MAY LAND ON A TRANSFORMER. transformer() models three HV bushings with
# insulator discs on top, a conservator drum and radiator fin banks. Only the bushings are an
# electrical terminal: the conservator is an oil expansion vessel and the fins are a cooler,
# so a cable touching either is drawn nonsense. The grid line therefore lands on the BUSHING
# TOPS, one conductor each.
TR_BUSH_Z = 1.42                 # top of a transformer's insulator stack at RECT_S
TR_BUSH_DX = 0.14 * RECT_S       # bushing pitch, from transformer()'s own spacing
# And everything LEAVING the transformer leaves from an LV terminal box on its front face —
# not from the same bushings the grid arrives on. Sharing them would have the incoming
# high-voltage line and both outgoing loads on one set of terminals.
TR_LV_Z = 0.92
BATH = (1.55, 3.05, -2.95, -2.25)  # open cell, mirrored to the front-RIGHT


def _ridged_barrel_y(K, name, y0, y1, cx, cz, r, bands, mat, mat2, seg=32):
    """Horizontal barrel along Y with axial lamination flutes as MATERIAL SLOTS.

    The real stack is hundreds of clamped plates; modelling them is a Freestyle bill with no
    upside, and proud rings would each earn their own 7 px contour and read as collars. Extra
    slots on the ONE mesh land hard-edged and un-inked — the fluted read for free."""
    import bpy, bmesh
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    rings = []
    for i in range(bands + 1):
        y = y0 + (y1 - y0) * i / bands
        rings.append([bm.verts.new((cx + r * math.cos(2 * math.pi * j / seg), y,
                                    cz + r * math.sin(2 * math.pi * j / seg)))
                      for j in range(seg)])
    band_of = {}
    for i in range(bands):
        for j in range(seg):
            k = (j + 1) % seg
            f = bm.faces.new([rings[i][j], rings[i][k], rings[i + 1][k], rings[i + 1][j]])
            band_of[f] = i
    bm.faces.new(list(reversed(rings[0])))
    bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    idx = [band_of.get(f, 0) % 2 for f in bm.faces]
    bm.to_mesh(me)
    bm.free()
    ob = K.obj(name, me, mat, True)
    ob.data.materials.append(mat2)
    for poly, want in zip(ob.data.polygons, idx):
        poly.material_index = want
    return ob


def _rod_bank(K, name, y, cx, cz, cols=4, rows=5, pitch=0.235):
    """Terminal bushings on the end plate, pointing -Y at the camera. Capped at 20 (the
    reference photo has ~40): they are small parts, so FINE_INK, and past this count they
    merge into one navy block anyway."""
    fm = K._fine_mode
    K._fine_mode = True
    for c in range(cols):
        for r_ in range(rows):
            bx = cx + (c - (cols - 1) / 2.0) * pitch
            bz = cz + (r_ - (rows - 1) / 2.0) * pitch
            K.cyl("%s_f%d_%d" % (name, c, r_), bx, y - 0.10, bz, 0.070, 0.20,
                  K.mat("pipe"), axis='Y', segments=10)
            K.cyl("%s_b%d_%d" % (name, c, r_), bx, y - 0.30, bz, 0.052, 0.30,
                  K.mat("opening"), axis='Y', segments=10)
    K._fine_mode = fm


def _stack(K, tag, cx):
    """One cell stack: skid, barrel, tie-rods, end plate and rod bank on the FRONT end."""
    cz = STK_Z
    yc = (STK_Y0 + STK_Y1) / 2.0
    K.box("skid%s" % tag, cx, yc, SKID_H / 2, STK_R * 1.85, STK_Y1 - STK_Y0 + 0.30,
          SKID_H, K.mat("skid"))
    for sy in (STK_Y0 + 0.20, STK_Y1 - 0.20):     # saddles
        K.box("sad%s_%d" % (tag, sy > yc), cx, sy, SKID_H + 0.20, STK_R * 1.55, 0.24,
              0.42, K.mat("skid"))
    _ridged_barrel_y(K, "barrel%s" % tag, STK_Y0, STK_Y1, cx, cz, STK_R, STK_BANDS,
                     K.mat("wall_bright"), K.tone(K.mat("wall_bright"), 0.84, "flute"))
    # Tie-rods over the UPPER half only — the lower ones are hidden by the barrel itself.
    for i in range(TIE_RODS):
        a = math.radians(18.0 + 144.0 * i / max(1, TIE_RODS - 1))
        K.cyl("tie%s_%d" % (tag, i), cx + TIE_R * math.cos(a), yc,
              cz + TIE_R * math.sin(a), 0.046, STK_Y1 - STK_Y0 + 0.34, K.mat("tie_rod"),
              axis='Y', segments=10)
    # End plate on the FRONT (-Y) end, square to the camera.
    K.cyl("endp%s" % tag, cx, STK_Y0 - 0.09, cz, STK_R + 0.16, 0.18, K.mat("gear"),
          axis='Y', segments=32)
    K.seam("endseam%s" % tag, cx, STK_Y0 - 0.18, cz, STK_R + 0.17, axis='Y')
    _rod_bank(K, "bank%s" % tag, STK_Y0 - 0.18, cx, cz)


def _pylon_conductor(tier=1, sgn=-1):
    """The point where a conductor hangs off the pylon — the bottom of the insulator string on
    one arm tip. Mirrors pylon()'s internals (body_h, the shoulder taper, arm lengthening per
    tier, cantilever depth, drop) so the cable cannot drift away from the steel it hangs on."""
    base_z, h, w = 0.0, PYLON_H, PYLON_W
    body_h = h * 0.92
    w_mid, w_top, sh_t = w * 0.42, w * 0.30, 0.45
    az = base_z + body_h * (0.93 - 0.20 * tier)
    t = max(0.0, min(1.0, (az - base_z) / body_h))
    half = ((w + (w_mid - w) * (t / sh_t)) / 2.0 if t <= sh_t
            else (w_mid + (w_top - w_mid) * ((t - sh_t) / (1.0 - sh_t))) / 2.0)
    arm = w * 0.95 * (1.0 + 0.20 * tier)
    tip_z = az + (h * 0.055) * 0.30
    return (PYLON_XY[0], PYLON_XY[1] + sgn * (half + arm), tip_z - 0.02 - h * 0.085)


def _nearest_tr(ys, target):
    """The transformer in the rank closest to `target`, as (x, y). Which one that is CHANGES
    with level — the rank grows backward, so the pylon's nearest partner is the newest
    transformer at L3 and the only one at L1."""
    best = min(ys, key=lambda ty: math.hypot(TR_X - target[0], ty - target[1]))
    return TR_X, best


def _cables(K, tag, p0, p1, n=3, sag=None, segs=3, w=0.045, spread=0.17):
    """A sagging run of short boxes — never a cylinder: an outlined constant-radius tube at
    this scale reads as a navy scratch, because the outline IS the tube (grass-blade lesson).

    `sag` defaults to a function of SPAN. A fixed value is wrong across this build: 0.16 looks
    right on the 1.3-unit jumper between two transformers and dead taut on the 4.6-unit run to
    the pylon, where the eye expects a catenary. Longer spans also get more segments, or the
    curve turns back into a polyline."""
    dx, dy = p1[0] - p0[0], p1[1] - p0[1]
    dist = math.hypot(dx, dy)
    if sag is None:
        sag = 0.07 + 0.062 * dist
    segs = max(segs, int(dist / 1.1) + 2)
    # Spread the conductors ACROSS the run, not along it, or they stack into one line.
    ox, oy = (0.0, spread) if abs(dx) >= abs(dy) else (spread, 0.0)
    for c in range(n):
        for seg in range(segs):
            t0, t1 = seg / float(segs), (seg + 1) / float(segs)

            def pt(t):
                return (p0[0] + dx * t + (c - (n - 1) / 2.0) * ox,
                        p0[1] + dy * t + (c - (n - 1) / 2.0) * oy,
                        p0[2] + (p1[2] - p0[2]) * t - sag * math.sin(math.pi * t))
            K.dirbox("%s_%d_%d" % (tag, c, seg), pt(t0), pt(t1), w, w, K.mat("opening"))


def build_electrolyser(level: int = 2) -> dict:
    p = ELY_LEVELS[level]
    setup_rig(target=(0.30, 0.90, 1.40))
    K = Kit(open_collection("BLDG_electrolyser"))

    xs = [STK_XS[k] for k in range(p["stacks"])]

    # ---------------- the cell stacks ----------------
    for k, cx in enumerate(xs):
        _stack(K, str(k), cx)

    # ---------------- stack gas take-off ----------------
    # One riser per stack off the barrel's back quarter, over to a drop in front of the shed,
    # then through its wall. At L1 (no shed yet) the riser ends in a capped vent.
    for k, cx in enumerate(xs):
        rx = cx + RISER_OFF[k]
        off = abs(RISER_OFF[k])
        base_z = STK_Z + math.sqrt(STK_R * STK_R - off * off) - 0.03
        if p["shed"]:
            K.pipe_run("gas%d" % k,
                       [(rx, 1.55, base_z), (rx, 1.55, 2.42), (rx, 3.05, 2.42),
                        (rx, 3.05, 1.45), (rx, SHED[2] + 0.02, 1.45)],
                       0.06, K.mat("pipe"), bend=0.16, ends=("", "collar"))
        else:
            K.pipe_run("gas%d" % k, [(rx, 1.55, base_z), (rx, 1.55, 2.30)],
                       0.06, K.mat("pipe"), bend=0.16, ends=("", "cap"))

    # ---------------- transformers (middle band) + the overhead bus ----------------
    for k in range(p["stacks"]):
        K.transformer("rect%d" % k, TR_X, TR_YS[k], 0.0, s=RECT_S)
        # At 2.05 these are yard machines, not models of them — OUT of FINE_INK, which exists
        # for parts small enough that a 2.4 px line would swallow them.
        fine = bpy.data.collections.get("FINE_INK")
        if fine is not None:
            for ob in list(fine.objects):
                if ob.name.startswith("rect%d" % k):
                    fine.objects.unlink(ob)
        # LV terminal box on the front face: the single place anything leaves this machine.
        K.box("lvbox%d" % k, TR_X, TR_YS[k] - 0.34 * RECT_S / 2.0 - 0.09, TR_LV_Z,
              0.34, 0.18, 0.30, K.mat("gear"))
        K.seam_bar("lvseam%d" % k, TR_X, TR_YS[k] - 0.34 * RECT_S / 2.0 - 0.18, TR_LV_Z,
                   0.36, 0.03, 0.32)
    bus_x1 = max(xs) + 0.45
    K.box("bus", (TR_X + bus_x1) / 2.0, BUS_Y, BUS_Z, bus_x1 - TR_X, 0.085, 0.085,
          K.mat("busbar"))
    K.box("bus_takeoff", TR_X, BUS_Y, BUS_Z / 2.0, 0.11, 0.11, BUS_Z, K.mat("stair"))
    for px_ in (0.35, 1.85, 3.35):
        if px_ < bus_x1 - 0.30:
            K.box("bus_post%d" % int(px_ * 10), px_, BUS_Y, (BUS_Z - 0.05) / 2.0,
                  0.10, 0.10, BUS_Z - 0.05, K.mat("stair"))
    for k, cx in enumerate(xs):      # L-shaped drop onto each bank: down, then forward
        K.box("bus_d%d" % k, cx, BUS_Y, (BUS_Z + 1.80) / 2.0, 0.07, 0.07, BUS_Z - 1.80,
              K.mat("busbar"))
        K.box("bus_f%d" % k, cx, (BUS_Y + STK_Y0 - 0.12) / 2.0, 1.80, 0.07,
              BUS_Y - (STK_Y0 - 0.12), 0.07, K.mat("busbar"))
        K.box("bus_end%d" % k, cx, STK_Y0 - 0.14, 1.80, 0.15, 0.12, 0.15, K.mat("gear"))
    # Feeder cables: battery -> first transformer -> daisy-chained jumpers -> takeoff post.
    _cables(K, "cab_bat", (BATT_X, BATT_Y + BATT_L / 2 - 0.10, BATT_H + 0.05),
            (TR_X - 0.22, TR_YS[0] - 0.34 * RECT_S / 2.0 - 0.14, TR_LV_Z + 0.10))
    # The takeoff to the overhead bus also leaves from an LV box, not from the HV bushings.
    _cables(K, "cab_take", (TR_X, TR_YS[0] - 0.34 * RECT_S / 2.0 - 0.14, TR_LV_Z + 0.12),
            (TR_X, BUS_Y + 0.06, BUS_Z - 0.06))
    for k in range(p["stacks"] - 1):
        _cables(K, "cab_j%d" % k, (TR_X, TR_YS[k] + 0.25, 1.48),
                (TR_X, TR_YS[k + 1] - 0.25, 1.48))

    # ---------------- incoming grid line, and the bath's supply ----------------
    # Both land on the NEAREST transformer in the rank, which is a different one per level.
    tr_ys = [TR_YS[k] for k in range(p["stacks"])]

    # Pylon -> transformer: the grid feed. ONE conductor per insulator string, taken off the
    # three -Y arms — the side facing the yard. The +Y strings stay empty and carry the route
    # on past, which is what makes this a tower on a line rather than a terminal post.
    #
    # The pairing is chosen so the three never cross. Both ends are ordered by SCREEN COLUMN
    # (x + y): on the tower the arms lengthen downward, so the lowest string is leftmost and
    # tier 2 -> 1 -> 0 runs left to right; on the transformer the bushings spread in x, so
    # i = -1 -> 0 -> +1 does the same. Hence bushing index = 1 - tier.
    ptx, pty = _nearest_tr(tr_ys, _pylon_conductor(tier=1, sgn=-1)[:2])
    for t in range(PYLON_TIERS):
        pc = _pylon_conductor(tier=t, sgn=-1)
        bush_x = ptx + (1 - t) * TR_BUSH_DX
        _cables(K, "cab_grid%d" % t, pc, (bush_x, pty, TR_BUSH_Z), n=1, w=0.038)
    # A terminal gantry across the bushing tops: three separate conductors arriving at three
    # separate porcelain stacks want something tying them together, or each reads as a loose
    # end resting on a disc.
    K.box("cab_grid_gantry", ptx, pty, TR_BUSH_Z + 0.05, TR_BUSH_DX * 2 + 0.22, 0.10, 0.07,
          K.mat("gear"))

    # Bath -> transformer: the cell's DC supply. It leaves from the LV terminal box on the
    # transformer's FRONT face, not from the HV bushings the grid arrives on.
    bcx = (BATH[0] + BATH[1]) / 2.0
    bcy = (BATH[2] + BATH[3]) / 2.0
    btx, bty = _nearest_tr(tr_ys, (bcx, bcy))
    lv_y = bty - 0.34 * RECT_S / 2.0 - 0.09
    _cables(K, "cab_bath", (BATH[0] + 0.10, bcy, 1.18), (btx + 0.20, lv_y, TR_LV_Z),
            n=3, spread=0.15, w=0.040)
    K.box("cab_bath_pot", BATH[0] + 0.02, bcy, 1.20, 0.20, 0.42, 0.26, K.mat("gear"))

    # ---------------- battery (every level) ----------------
    K.box("batt", BATT_X, BATT_Y, BATT_H / 2, BATT_W, BATT_L, BATT_H, K.mat("wall_bright"))
    K.box("batt_lid", BATT_X, BATT_Y, BATT_H + 0.05, BATT_W + 0.10, BATT_L + 0.10, 0.10,
          K.mat("roof_deck"))
    for j, fz in enumerate((0.34, 0.72)):    # green stripes on the two faces the camera sees
        K.box("batt_sy%d" % j, BATT_X, BATT_Y - BATT_L / 2 - 0.014, fz, BATT_W - 0.10,
              0.03, 0.10, K.mat("tie_rod"))
        K.box("batt_sx%d" % j, BATT_X + BATT_W / 2 + 0.014, BATT_Y, fz, 0.03,
              BATT_L - 0.16, 0.10, K.mat("tie_rod"))
    for j in range(3):
        K.box("batt_rib%d" % j, BATT_X, BATT_Y - BATT_L / 2 - 0.02, BATT_H / 2, 0.05,
              0.03, BATT_H - 0.24, K.mat("gear"))

    # ---------------- tank farm (left) ----------------
    for k in range(p["tanks"]):
        (cx, cy), r, h = TANKS[k], TANK_R, TANK_H
        K.cyl("gtank%d" % k, cx, cy, h / 2, r, h, K.mat("wall_bright"), segments=28,
              smooth=True)
        # dome rise 0.80 r: at 0.52 the crown foreshortened away entirely at this camera.
        K.dome_cap("gcap%d" % k, cx, cy, h, r, r * 0.80, K.mat("wall_bright"))
        K.seam("gseam%d" % k, cx, cy, h, r + 0.012)
        K.cyl("gband%d" % k, cx, cy, h * 0.40, r + 0.022, 0.16, K.mat("tie_rod"),
              segments=28)
        K.washer("gcrown%d" % k, (cx, cy, h + 0.02), (0, 0, 1), r * 0.42, r * 0.68, 0.05,
                 K.mat("tie_rod"))
        # Swan-necks LEFT onto the header: over the dome shoulder, across at 2.05 (clears the
        # neighbouring dome at 1.67), and a clean drop onto the main's back. Straight
        # waist-height branches were tried and ran through the neighbouring tank.
        for j, dy in enumerate((0.0,) if p["pipes"] == 1 else (-0.16, 0.16)):
            by_ = cy + dy
            K.pipe_run("gpipe%d_%d" % (k, j),
                       [(cx - 0.28, by_, 1.50), (cx - 0.28, by_, 2.05),
                        (HDR_X, by_, 2.05), (HDR_X, by_, 0.88)],
                       BR_R, K.mat("pipe"), bend=0.14)
            K.sphere("gtee%d_%d" % (k, j), HDR_X, by_, 0.87, HDR_R * 1.30, K.mat("pipe"))
        K.ladder("glad%d" % k, cx, cy - r, 0.05, h, face="-Y")

    # ---------------- the gas header ----------------
    hy0 = min(TANKS[k][1] for k in range(p["tanks"])) - 0.30
    if p["shed"]:
        K.pipe_run("header",
                   [(HDR_X, hy0, HDR_Z), (HDR_X, HDR_XRUN_Y, HDR_Z),
                    (HDR_WALL_X, HDR_XRUN_Y, HDR_Z), (HDR_WALL_X, SHED[2] + 0.02, HDR_Z)],
                   HDR_R, K.mat("pipe"), bend=HDR_BEND, ends=("cap", "collar"))
    else:
        # L1: the main ends in a capped down-stub — the stub-out a real yard leaves for the
        # expansion the next level builds.
        K.pipe_run("header",
                   [(HDR_X, hy0, HDR_Z), (HDR_X, 0.90, HDR_Z), (HDR_X, 0.90, 0.22)],
                   HDR_R, K.mat("pipe"), bend=HDR_BEND, ends=("cap", "cap"))
    for sy_ in (hy0 + 0.55, 2.20):
        if not p["shed"] and sy_ > 0.8:
            continue
        K.box("hdr_post%d" % int(abs(sy_) * 10), HDR_X, sy_, (HDR_Z - HDR_R) / 2,
              0.12, 0.12, HDR_Z - HDR_R, K.mat("stair"))

    # ---------------- the bath (front-right) ----------------
    bx0, bx1, by0, by1 = BATH
    K.box("bath", (bx0 + bx1) / 2, (by0 + by1) / 2, 0.31, bx1 - bx0, by1 - by0, 0.62,
          K.mat("wall_grey"))
    K.box("bath_liq", (bx0 + bx1) / 2, (by0 + by1) / 2, 0.56, bx1 - bx0 - 0.16,
          by1 - by0 - 0.16, 0.05, K.tone(K.mat("tie_rod"), 0.62, "liq"))
    for i in range(7):
        px = bx0 + (bx1 - bx0) * (i + 0.5) / 7
        K.box("plate%d" % i, px, (by0 + by1) / 2, 0.78, 0.055, by1 - by0 - 0.30, 0.52,
              K.mat("busbar") if i % 2 else K.mat("gear"))
    K.box("bath_bus", (bx0 + bx1) / 2, (by0 + by1) / 2, 1.08, bx1 - bx0 - 0.10, 0.16, 0.14,
          K.mat("busbar"))

    # ---------------- pylon (back-left, every level) ----------------
    # The grid tie the yard lost when the substation towers were cut — one L-series pylon,
    # the power plant's assembly, standing beside the building line.
    K.pylon("pylon", PYLON_XY[0], PYLON_XY[1], 0.0, PYLON_H, w_base=PYLON_W,
            tiers=PYLON_TIERS)

    # ---------------- shed (back-right) ----------------
    if p["shed"]:
        sx0, sx1, sy0, sy1 = SHED
        K.box("shed", (sx0 + sx1) / 2, (sy0 + sy1) / 2, SHED_H / 2, sx1 - sx0, sy1 - sy0,
              SHED_H, K.mat("wall_pale"))
        syc = (sy0 + sy1) / 2
        ang = math.degrees(math.atan2(SHED_RISE, syc - sy0))
        slope = math.hypot(syc - sy0, SHED_RISE)
        for tag, (cy_, sgn) in {"f": ((sy0 + syc) / 2, 1.0),
                                "b": ((syc + sy1) / 2, -1.0)}.items():
            K.rotbox("shed_roof_%s" % tag, (sx0 + sx1) / 2, cy_,
                     SHED_H + SHED_RISE / 2 + 0.05, sx1 - sx0 + 0.22, slope, 0.14,
                     K.mat("roof_deck"), 'X', sgn * ang)
        K.box("shed_ridge", (sx0 + sx1) / 2, syc, SHED_H + SHED_RISE + 0.08,
              sx1 - sx0 + 0.26, 0.14, 0.10, K.mat("stair"))
        for gx in (sx0, sx1):
            K.prism("shed_gable_%d" % (gx > sx0), (gx, 0.0, 0.0), (0.0, 1.0, 0.0),
                    [(sy0, SHED_H), (syc, SHED_H + SHED_RISE), (sy1, SHED_H)], 0.14,
                    K.mat("wall_pale"))
        for k in range(3):
            K.gate("bay%d" % k, "-Y", (sx0 + 0.55 + k * 1.05, sy0, 0.52), 0.80, 1.02)

    # ---------------- L3: flat-roofed extension ----------------
    if p["ext"]:
        ex0, ex1, ey0, ey1 = EXT
        eh = SHED_H - 0.15
        K.box("ext", (ex0 + ex1) / 2, (ey0 + ey1) / 2, eh / 2, ex1 - ex0, ey1 - ey0, eh,
              K.mat("wall_pale"))
        K.box("ext_deck", (ex0 + ex1) / 2, (ey0 + ey1) / 2, eh + 0.05, ex1 - ex0 + 0.02,
              ey1 - ey0 + 0.02, 0.10, K.mat("roof_deck"))
        # Parapet as bars, not a lid — a full coping box covers the deck it exists to reveal.
        for tag, (px, py, sx_, sy_) in {
            "l": (ex0 - 0.04, (ey0 + ey1) / 2, 0.09, ey1 - ey0),
            "r": (ex1 + 0.04, (ey0 + ey1) / 2, 0.09, ey1 - ey0),
            "b": ((ex0 + ex1) / 2, ey1, ex1 - ex0 + 0.10, 0.09),
        }.items():
            K.box("ext_par_%s" % tag, px, py, eh + 0.14, sx_, sy_, 0.14, K.mat("wall_pale"))
        K.box("ext_unit", (ex0 + ex1) / 2 + 0.30, (ey0 + ey1) / 2 - 0.12, eh + 0.42,
              0.62, 0.52, 0.60, K.mat("gear"))
        K.box("ext_unit_lid", (ex0 + ex1) / 2 + 0.30, (ey0 + ey1) / 2 - 0.12, eh + 0.75,
              0.70, 0.60, 0.07, K.mat("roof_deck"))

    # ---------------- L3: liquid tank (left of the shed) ----------------
    if p["liquid"]:
        lx, ly, lr, lh = LIQ
        K.cyl("liq_lo", lx, ly, lh * 0.25, lr, lh * 0.5, K.mat("tie_rod"), segments=28,
              smooth=True)
        K.cyl("liq_hi", lx, ly, lh * 0.75, lr, lh * 0.5, K.mat("wall_bright"), segments=28,
              smooth=True)
        K.seam("liq_seam", lx, ly, lh * 0.5, lr + 0.014)
        K.cyl("liq_top", lx, ly, lh + 0.035, lr + 0.05, 0.09, K.mat("gear"), segments=28)
        K.ring_rail("liq_rail", lx, ly, lh + 0.09, lr + 0.05)
        K.ladder("liq_lad", lx, ly - lr, 0.05, lh, face="-Y")

    print("\n".join(K.validate(ground=0.0)))
    return {"building": "electrolyser", "level": level, "stacks": p["stacks"],
            "objects": len(K.col.objects)}
