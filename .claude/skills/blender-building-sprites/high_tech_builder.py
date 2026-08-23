# Parametric builder for the High Tech Manufactory (b_010, `high_tech_manufactory`).
# Run AFTER sprite_kit.py:
#   exec(open(".../sprite_kit.py").read())
#   exec(open(".../high_tech_builder.py").read()); build_high_tech(2)
#
# BUILDING class on z=0, manufacturing family. Two-toned walls — brick orange below, white
# above — under a FRONT HALL whose mono-pitch roof is GLASS on steel rafters and purlins,
# rising from a low eave to the flat-roofed steps behind. Through the pitch: a robotic cell
# of four orange arms converging on one microchip carrier, and server racks along the walls.
# The front-right corner is a two-storey glass box on steel pillars with transoms across the
# panes, white clean rooms and red laser benches aimed at green circuit boards. Conduits, a
# cable tray, switchgear and a transformer at the back; rooftop air handlers and electrical
# units on the flat roofs; a lattice mast with a dish at L3, when the rear block also extends
# back.
#
# ---------------------------------------------------------------------------------------
# 1. THE GLASS PITCH MADE THE HALL HOLLOW. A roof you can see through has to have something
#    under it, so the front section is a floor, a thin end wall, the rear block's face and
#    the corner partitions — not a solid prism — with rafters down the slope and purlins
#    across it under the glass (the structure seen with the glass is what makes it glass).
#    Every ray through the pitch lands on one of those; none reaches background.
#
# 2. WHAT CAN BE SEEN THROUGH THE PITCH IS SET BY THE FRONT WALL. An interior point (y, z) is
#    seen over the 2.0 eave wall iff z + (y − FY0) > EAVE, i.e. y + z > −0.2. So the robot
#    cell sits in the back half of the hall (centre y −0.55) with its elbows at 1.05 — the
#    front pair show from the elbow up, the back pair in full — and the racks stand along the
#    rear wall and the left wall, 1.6 tall.
#
# 3. THE ROOF SLOPES UP TOWARD THE BACK (area ∝ cos t + sin t; toward the camera it is
#    ∝ |cos t − sin t|, dead flat at 45°). Eave 2.0, 3.05 at the junction, 25.5°. The glass
#    corner's +X pillars and panes follow the rake; its fascia is a rotbox at the pitch.
#
# 4. EVERY LASER IS AIMED at a green circuit board square to its beams; every rooftop unit
#    has a duct or tray into the building; the transformer feeds the switchgear which feeds
#    the conduits; the canopy has posts; the roofs have downpipes; step 2 has a goods door.
#    The two flat blocks are LEVEL, so there is one roof deck and no ladder between them. The engineering audit (2026-08-22) added each of these.
#
# 5. GROWTH IS ANCHORED ON THE SHOWCASE CORNER (SKILL.md rule 22): L2 adds the third step;
#    L3 extends it back, adds the mast, the roof electrical units and the fourth robot.

import math

PALETTE["ht_glass"] = (0.200, 0.360, 0.500)
PALETTE["orange"] = (0.620, 0.215, 0.038)
PALETTE["brick_orange"] = (0.440, 0.165, 0.068)   # two-tone lower band, warmer than `brick`
PALETTE["ht_white"] = (0.600, 0.600, 0.590)
PALETTE["pcb"] = (0.060, 0.300, 0.120)
PALETTE["pcb_lo"] = (0.035, 0.180, 0.070)
PALETTE["crate"] = (0.052, 0.055, 0.062)        # sleepers and wheels (the assembly plant's)
PALETTE["rack"] = (0.070, 0.080, 0.095)
PALETTE["rack_face"] = (0.160, 0.175, 0.200)
ROLES["ht_accent"] = "orange"
ROLES["robot"] = "orange"
ROLES["ht_brick"] = "brick_orange"
ROLES["ht_white"] = "ht_white"
ROLES["pcb"] = "pcb"
ROLES["pcb_lo"] = "pcb_lo"
ROLES["crate"] = "crate"
ROLES["rack"] = "rack"
ROLES["rack_face"] = "rack_face"

HT_LEVELS = {
    1: dict(steps=2, back=3.60, upper_room=False, lasers=1, mast=False, tray=False, ahus=1,
            robots=2, racks=2, elec=0),
    2: dict(steps=3, back=3.60, rx1=2.40, rail=False, upper_room=True, lasers=2, mast=False,
            tray=True, ahus=2, robots=3, racks=3, elec=0),
    3: dict(steps=3, back=4.20, rx1=3.40, rail=True, upper_room=True, lasers=3, mast=True,
            tray=True, ahus=3, robots=4, racks=4, elec=3),
}
# The rail bay (L3): a siding along Y beside the widened rear block, two goods wagons, a
# platform at wagon-floor height, a canopy over the track. Everything at the back-right costs
# screen width (column = x + y), which is why the L3 extension back is 4.2 rather than 5.0
# and the apron's front-left overhang is trimmed: the siding's back corner sets the frame.
RAIL_X = 4.10                      # track centreline (wagon bodies clear the platform edge)
RAIL_Y0, RAIL_Y1 = 0.70, 4.30
WAGON = (0.62, 1.50, 0.72)         # width (X), length (Y), body height
WAGON_FLOOR = 0.42                 # = platform height (the assembly dock lesson)
WAGON_YS = (1.70, 3.30)
CANOPY_Z = 2.30

X0, X1 = -3.00, 2.40
FY0, FY1 = -2.20, 0.00
EAVE = 2.00
STEP_H = (3.05, 3.05)              # the two flat blocks are LEVEL (owner): one roof deck
STEP2_Y1 = 2.00
STEP3_X1 = 1.20                    # unused since the rear block went full width; kept for the mast
PARAPET_H, PARAPET_W = 0.14, 0.10
SPLIT = 1.00                       # brick below, white above
GX0 = 0.20
GY1 = -0.60
FLOOR2 = 1.15
FASCIA_D = 0.12
PILLAR = 0.13
TRANSOMS = (0.62, 1.62)
GLASS_ALPHA = 0.35
ENTRANCE_X = -0.25
WALL_T = 0.12
CELL = (-1.00, -0.55)              # robotic cell centre; see note 2
CELL_R = 0.50


def _zr(y):
    return EAVE + (y - FY0) / (FY1 - FY0) * (STEP_H[0] - EAVE)


_PITCH = math.degrees(math.atan((STEP_H[0] - EAVE) / (FY1 - FY0)))


def _glass(name, colour, alpha):
    import bpy
    mt = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    mt.use_nodes = True
    b = mt.node_tree.nodes.get("Principled BSDF")
    b.inputs["Base Color"].default_value = (*colour, 1)
    b.inputs["Roughness"].default_value = 1.0
    if "Specular IOR Level" in b.inputs:
        b.inputs["Specular IOR Level"].default_value = 0.0
    b.inputs["Alpha"].default_value = alpha
    mt.surface_render_method = 'BLENDED'
    mt.use_backface_culling = False
    return mt


def _two_tone_box(K, tag, cx, cy, sx, sy, h):
    """Wall mass painted brick orange to SPLIT and white above: two stacked boxes."""
    K.box("%s_lo" % tag, cx, cy, SPLIT / 2, sx, sy, SPLIT, K.mat("ht_brick"))
    K.box("%s_hi" % tag, cx, cy, SPLIT + (h - SPLIT) / 2, sx, sy, h - SPLIT, K.mat("wall_bright"))


def _parapet(K, tag, x0, x1, y0, y1, z, skip=()):
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    for t, (bx, by, sx, sy) in {
        "f": (cx, y0 + PARAPET_W / 2, x1 - x0, PARAPET_W), "b": (cx, y1 - PARAPET_W / 2, x1 - x0, PARAPET_W),
        "l": (x0 + PARAPET_W / 2, cy, PARAPET_W, y1 - y0), "r": (x1 - PARAPET_W / 2, cy, PARAPET_W, y1 - y0),
    }.items():
        if t in skip:
            continue
        K.box("par_%s_%s" % (tag, t), bx, by, z + PARAPET_H / 2, sx, sy, PARAPET_H, K.mat("wall_bright"))
        K.box("cop_%s_%s" % (tag, t), bx, by, z + PARAPET_H + 0.02, sx + 0.03, sy + 0.03, 0.04,
              K.mat("gear"))


def _block(K, tag, x0, x1, y0, y1, h, skip=()):
    _two_tone_box(K, "blk_%s" % tag, (x0 + x1) / 2, (y0 + y1) / 2, x1 - x0, y1 - y0, h)
    K.box("roof_%s" % tag, (x0 + x1) / 2, (y0 + y1) / 2, h + 0.03, x1 - x0 - 0.02, y1 - y0 - 0.02, 0.06,
          K.mat("roof_deck"))
    _parapet(K, tag, x0, x1, y0, y1, h, skip)


def _front_hall(K, pane, seam):
    """The hollow front section under the glass pitch: floor, front wall, left end wall
    (a trapezoid, two-toned), the glass roof with rafters and purlins, eave fascia and
    gutter downpipe."""
    import bpy, bmesh
    z0, z1 = _zr(FY0), _zr(FY1)
    K.box("hall_floor", (X0 + X1) / 2, (FY0 + FY1) / 2, 0.05, X1 - X0, FY1 - FY0, 0.10, K.mat("yard_pad"))
    # Front wall left of the glass corner, two-toned, up to the eave.
    _two_tone_box(K, "front_wall", (X0 + GX0) / 2, FY0 + WALL_T / 2, GX0 - X0, WALL_T, z0 - 0.02)
    # Left end wall: rectangle to SPLIT in brick, trapezoid above in white.
    K.box("end_wall_lo", X0 + WALL_T / 2, (FY0 + FY1) / 2, SPLIT / 2, WALL_T, FY1 - FY0, SPLIT,
          K.mat("ht_brick"))
    K.prism("end_wall_hi", (X0 + WALL_T / 2, 0.0, 0.0), (0.0, 1.0, 0.0),
            [(FY0, SPLIT), (FY1, SPLIT), (FY1, z1 - 0.02), (FY0, z0 - 0.02)], WALL_T, K.mat("wall_bright"))
    # Rafters down the slope and purlins across it, just under the glass.
    fm = K._fine_mode
    K._fine_mode = True
    ang = _PITCH
    L = (FY1 - FY0) / math.cos(math.radians(ang))
    for i, x in enumerate((X0 + 0.9, X0 + 1.8, X0 + 2.7, X0 + 3.6, X0 + 4.5)):
        K.rotbox("rafter%d" % i, x, (FY0 + FY1) / 2, (z0 + z1) / 2 - 0.07, 0.07, L - 0.06, 0.09,
                 K.mat("gear"), 'X', ang)
    for i, y in enumerate((-1.47, -0.73)):
        K.box("purlin%d" % i, (X0 + X1) / 2, y, _zr(y) - 0.10, X1 - X0 - 0.04, 0.06, 0.06, K.mat("gear"))
    K._fine_mode = fm
    # Glass roof: ONE single-surface mesh, pane quads with seam strips at the rafters (rule 21).
    me = bpy.data.meshes.new("roof_glass")
    bm = bmesh.new()
    flags = []
    xs = [X0] + [x for r in (X0 + 0.9, X0 + 1.8, X0 + 2.7, X0 + 3.6, X0 + 4.5) for x in (r - 0.012, r + 0.012)] + [X1]
    for i in range(len(xs) - 1):
        xa, xb = xs[i], xs[i + 1]
        bm.faces.new([bm.verts.new((xa, FY0, z0 + 0.01)), bm.verts.new((xb, FY0, z0 + 0.01)),
                      bm.verts.new((xb, FY1, z1 + 0.01)), bm.verts.new((xa, FY1, z1 + 0.01))])
        flags.append(i % 2 == 1)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me); bm.free()
    ob = K.obj("roof_glass", me, pane)
    ob.data.materials.append(seam)
    for poly, f in zip(me.polygons, flags):
        poly.material_index = 1 if f else 0
    # Eave fascia/gutter, the ridge flashing where the pitch meets the rear block, downpipe.
    K.box("eave_fascia", (X0 + X1) / 2, FY0 - 0.05, z0 - 0.06, X1 - X0 + 0.08, 0.06, 0.16, K.mat("gear"))
    K.box("ridge_flash", (X0 + X1) / 2, FY1 - 0.04, z1 + 0.03, X1 - X0 + 0.08, 0.08, 0.06, K.mat("gear"))
    K.cyl("downpipe_l", X0 - 0.05, FY0 + 0.02, z0 / 2, 0.03, z0 - 0.2, K.mat("stack"), segments=8)


def _ahu(K, tag, cx, cy, z):
    K.box("ahu%s" % tag, cx, cy, z + 0.24, 0.78, 0.50, 0.48, K.mat("gear"))
    K.box("ahu%s_s" % tag, cx, cy - 0.26, z + 0.24, 0.60, 0.02, 0.10, K.mat("ht_accent"))
    K.washer("ahu%s_fan" % tag, (cx + 0.18, cy, z + 0.52), (0, 0, 1), 0.09, 0.15, 0.08,
             K.mat("wall_steel"), seg=16)
    K.box("ahu%s_duct" % tag, cx - 0.25, cy + 0.10, z + 0.58, 0.22, 0.22, 0.20, K.mat("gear"))
    K.box("ahu%s_drop" % tag, cx - 0.25, cy + 0.10, z + 0.02, 0.26, 0.26, 0.06, K.mat("wall_steel"))


def _elec_unit(K, tag, cx, cy, z):
    """Rooftop electrical cabinet: louvred face, orange stripe, tray stub."""
    K.box("eu%s" % tag, cx, cy, z + 0.36, 0.52, 0.42, 0.72, K.mat("gear"))
    for k in range(3):
        K.box("eu%s_lv%d" % (tag, k), cx, cy - 0.215, z + 0.22 + k * 0.14, 0.36, 0.02, 0.05, K.mat("wall_steel"))
    K.box("eu%s_s" % tag, cx, cy - 0.215, z + 0.64, 0.40, 0.02, 0.05, K.mat("ht_accent"))


def _laser(K, tag, a, b):
    dx, dy = b[0] - a[0], b[1] - a[1]
    n = math.hypot(dx, dy) or 1.0
    ux, uy = dx / n, dy / n
    K.box("lz%s_head" % tag, a[0], a[1], a[2] - 0.10, 0.16, 0.16, 0.26, K.mat("wall_steel"))
    bw, bh = 0.44, 0.32
    K.box("lz%s_stand" % tag, b[0], b[1], b[2] - 0.16, 0.10, 0.10, 0.22, K.mat("wall_steel"))
    K.box("lz%s_pcb" % tag, b[0], b[1], b[2] + 0.04, 0.03 + bw * abs(uy), 0.03 + bw * abs(ux), bh,
          K.mat("pcb"))
    fm = K._fine_mode
    K._fine_mode = True
    for k in range(3):
        K.box("lz%s_chip%d" % (tag, k), b[0] - ux * 0.025, b[1] - uy * 0.025,
              b[2] + 0.04 - 0.09 + k * 0.09, 0.012 + 0.22 * abs(uy), 0.012 + 0.22 * abs(ux), 0.04,
              K.mat("pcb_lo"))
    for k, off in enumerate((-0.07, 0.07)):
        sa = (a[0] - uy * off, a[1] + ux * off, a[2] + 0.02 * k)
        sb = (b[0] - uy * off - ux * 0.03, b[1] + ux * off - uy * 0.03, b[2] + 0.02 * k)
        K.dircyl("lz%s_beam%d" % (tag, k), sa, sb, 0.040, K.M["laser"], segments=8)
    K._fine_mode = fm


def _robot(K, tag, x, y, tx, ty, z_floor):
    """Orange six-axis arm on a pedestal, reaching from (x, y) toward (tx, ty). The elbow is
    a sphere so a diagonal reach needs no axis choice."""
    dx, dy = tx - x, ty - y
    n = math.hypot(dx, dy) or 1.0
    ux, uy = dx / n, dy / n
    fm = K._fine_mode
    K._fine_mode = True
    K.cyl("rb%s_ped" % tag, x, y, z_floor + 0.12, 0.11, 0.24, K.mat("gear"), segments=12)
    K.box("rb%s_tur" % tag, x, y, z_floor + 0.31, 0.20, 0.18, 0.14, K.mat("robot"))
    sh = (x, y, z_floor + 0.38)
    el = (x + ux * 0.30, y + uy * 0.30, z_floor + 1.05)
    wr = (x + ux * 0.66, y + uy * 0.66, z_floor + 0.72)
    K.dirbox("rb%s_ua" % tag, sh, el, 0.10, 0.12, K.mat("robot"))
    K.sphere("rb%s_elb" % tag, el[0], el[1], el[2], 0.075, K.mat("gear"))
    K.dirbox("rb%s_fa" % tag, el, wr, 0.085, 0.095, K.mat("robot"))
    K.box("rb%s_wr" % tag, wr[0], wr[1], wr[2] - 0.05, 0.09, 0.09, 0.07, K.mat("gear"))
    K.box("rb%s_tool" % tag, wr[0] + ux * 0.04, wr[1] + uy * 0.04, wr[2] - 0.13, 0.03, 0.03, 0.10,
          K.mat("wall_steel"))
    K._fine_mode = fm


def _cell(K, n_robots):
    """Four arms round one microchip carrier on a bench: a green board with a silver wafer
    and a dark die, lit by the arms' work lamp."""
    cx, cy = CELL
    zf = 0.10
    K.box("bench", cx, cy, zf + 0.27, 0.74, 0.74, 0.54, K.mat("gear"))
    K.box("bench_top", cx, cy, zf + 0.56, 0.80, 0.80, 0.04, K.mat("wall_steel"))
    K.box("carrier", cx, cy, zf + 0.60, 0.50, 0.50, 0.03, K.mat("pcb"))
    K.cyl("wafer", cx, cy, zf + 0.63, 0.19, 0.025, K.mat("pipe"), segments=24)
    K.box("die", cx, cy, zf + 0.665, 0.11, 0.11, 0.04, K.mat("rack"))
    for k in range(n_robots):
        a = math.radians(45.0 + 90.0 * k)
        _robot(K, str(k), cx + CELL_R * math.cos(a), cy + CELL_R * math.sin(a), cx, cy, zf)


def _racks(K, n):
    """Server racks: along the rear wall, then along the left wall (note 2)."""
    spots = ((-2.55, -0.36, 0), (-1.95, -0.36, 0), (X0 + 0.40, -1.15, 1), (X0 + 0.40, -1.75, 1))
    for k in range(n):
        x, y, along_y = spots[k]
        sx, sy = (0.50, 0.56) if not along_y else (0.56, 0.50)
        K.box("rack%d" % k, x, y, 0.10 + 0.80, sx, sy, 1.60, K.mat("rack"))
        if along_y:
            K.box("rack%d_face" % k, x + sx / 2 + 0.006, y, 0.90, 0.012, 0.42, 1.46, K.mat("rack_face"))
        else:
            K.box("rack%d_face" % k, x, y - sy / 2 - 0.006, 0.90, 0.42, 0.012, 1.46, K.mat("rack_face"))
        fm = K._fine_mode
        K._fine_mode = True
        for j in range(5):                       # blade rows
            z = 0.32 + j * 0.28
            if along_y:
                K.box("rack%d_r%d" % (k, j), x + sx / 2 + 0.014, y, z, 0.008, 0.36, 0.05, K.mat("gear"))
            else:
                K.box("rack%d_r%d" % (k, j), x, y - sy / 2 - 0.014, z, 0.36, 0.008, 0.05, K.mat("gear"))
        K._fine_mode = fm


def _glass_corner(K, p, pane):
    import bpy, bmesh
    y0 = FY0
    xs = [GX0 + (X1 - GX0) * i / 3 for i in range(4)]
    ys = [y0 + (GY1 - y0) * i / 2 for i in range(3)]
    top_f = _zr(y0) - FASCIA_D

    def top_r(y):
        return _zr(y) - FASCIA_D

    for i, x in enumerate(xs):
        K.box("gp_f%d" % i, x, y0 + PILLAR / 2 + 0.02, top_f / 2 + 0.04, PILLAR, PILLAR, top_f + 0.08,
              K.mat("gear"))
    for i, y in enumerate(ys):
        K.box("gp_r%d" % i, X1 - PILLAR / 2 - 0.02, y, top_r(y) / 2 + 0.04, PILLAR, PILLAR,
              top_r(y) + 0.08, K.mat("gear"))
    K.box("gfascia_f", (GX0 + X1) / 2, y0 + 0.10, top_f + FASCIA_D / 2, X1 - GX0, 0.20, FASCIA_D,
          K.mat("gear"))
    ym = (y0 + GY1) / 2
    K.rotbox("gfascia_r", X1 - 0.10, ym, top_r(ym) + FASCIA_D / 2, 0.20,
             (GY1 - y0) / math.cos(math.radians(_PITCH)), FASCIA_D, K.mat("gear"), 'X', _PITCH)
    fm = K._fine_mode
    K._fine_mode = True
    for z in (FLOOR2,) + TRANSOMS:
        hh = 0.10 if z == FLOOR2 else 0.05
        K.box("gt_f%d" % int(z * 100), (GX0 + X1) / 2, y0 - 0.01, z, X1 - GX0, 0.05, hh, K.mat("gear"))
        K.box("gt_r%d" % int(z * 100), X1 + 0.01, ym, z, 0.05, GY1 - y0, hh, K.mat("gear"))
    K._fine_mode = fm
    me = bpy.data.meshes.new("glass_f")
    bm = bmesh.new()
    gy = y0 - 0.005
    for i in range(3):
        bm.faces.new([bm.verts.new((xs[i], gy, 0.10)), bm.verts.new((xs[i + 1], gy, 0.10)),
                      bm.verts.new((xs[i + 1], gy, top_f)), bm.verts.new((xs[i], gy, top_f))])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me); bm.free()
    K.obj("glass_f", me, pane)
    me = bpy.data.meshes.new("glass_r")
    bm = bmesh.new()
    gx = X1 + 0.005
    for i in range(2):
        bm.faces.new([bm.verts.new((gx, ys[i], 0.10)), bm.verts.new((gx, ys[i + 1], 0.10)),
                      bm.verts.new((gx, ys[i + 1], top_r(ys[i + 1]))),
                      bm.verts.new((gx, ys[i], top_r(ys[i])))])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me); bm.free()
    K.obj("glass_r", me, pane)
    K.box("gfloor2", (GX0 + X1) / 2 - 0.05, (y0 + GY1) / 2 + 0.05, FLOOR2, X1 - GX0 - 0.10,
          GY1 - y0 - 0.10, 0.08, K.mat("ht_white"))
    K.prism("gpart_x", (GX0 + 0.06, 0.0, 0.0), (0.0, 1.0, 0.0),
            [(y0, 0.0), (GY1, 0.0), (GY1, _zr(GY1) - 0.02), (y0, _zr(y0) - 0.02)], 0.12, K.mat("ht_white"))
    K.box("gpart_y", (GX0 + X1) / 2, GY1 - 0.06, (_zr(GY1) - 0.02) / 2, X1 - GX0, 0.12, _zr(GY1) - 0.02,
          K.mat("ht_white"))
    K.box("clean1", GX0 + 0.72, GY1 - 0.48, 0.10 + 0.44, 1.10, 0.80, 0.88, K.mat("wall_bright"))
    K.box("clean1_w", GX0 + 0.72, GY1 - 0.89, 0.10 + 0.55, 0.70, 0.02, 0.22, K.mat("window_glass"))
    K.box("clean1_d", GX0 + 1.12, GY1 - 0.89, 0.10 + 0.36, 0.22, 0.02, 0.62, K.mat("gear"))
    _laser(K, "0", (GX0 + 0.35, y0 + 0.75, 0.42), (X1 - 0.40, y0 + 0.75, 0.42))
    if p["upper_room"]:
        K.box("clean2", X1 - 0.70, y0 + 0.55, FLOOR2 + 0.04 + 0.32, 0.95, 0.62, 0.64, K.mat("wall_bright"))
        K.box("clean2_w", X1 - 0.70, y0 + 0.23, FLOOR2 + 0.04 + 0.40, 0.55, 0.02, 0.18, K.mat("window_glass"))
    if p["lasers"] >= 2:
        _laser(K, "1", (X1 - 0.30, y0 + 0.30, FLOOR2 + 0.38), (X1 - 0.30, GY1 - 0.30, FLOOR2 + 0.38))
    if p["lasers"] >= 3:
        _laser(K, "2", (GX0 + 0.30, y0 + 0.35, FLOOR2 + 0.50), (GX0 + 0.30, GY1 - 0.30, FLOOR2 + 0.50))
    # Entrance beside the glass, under a canopy on two posts.
    K.door("entrance", "-Y", (ENTRANCE_X, y0, 0.50), 0.40, 1.00)
    K.box("entrance_mark", ENTRANCE_X, y0 - 0.02, 0.50, 0.46, 0.02, 1.04, K.mat("ht_accent"))
    K.door("entrance2", "-Y", (ENTRANCE_X, y0 - 0.03, 0.50), 0.40, 1.00)
    K.box("canopy", ENTRANCE_X, y0 - 0.30, 1.22, 0.90, 0.62, 0.06, K.mat("gear"))
    for s in (-1, 1):
        K.box("canopy_post%d" % (s > 0), ENTRANCE_X + s * 0.38, y0 - 0.55, 0.61, 0.05, 0.05, 1.22,
              K.mat("gear"))


def _services(K, p):
    """Power: transformer -> switchgear -> conduits up step 2's +X face -> cable tray.
    Goods door and dock pad on that face; downpipe at its corner; ladder between roofs."""
    y0, y1, h = 0.0, STEP2_Y1, STEP_H[0]
    K.gate("goods", "+X", (X1, 0.50, 0.58), 0.70, 1.16)
    K.box("dock_pad", X1 + 0.45, 0.50, 0.03, 0.90, 1.00, 0.06, K.mat("yard_pad"))
    fm = K._fine_mode
    K._fine_mode = True
    for i in range(4):
        y = 1.10 + i * 0.22
        K.pipe_run("conduit%d" % i, [(X1 + 0.09, y, 0.25), (X1 + 0.09, y, h - 0.30),
                                     (X1 - 0.03, y, h - 0.30)], 0.035, K.mat("wall_steel"))
    K._fine_mode = fm
    K.box("tray", X1 + 0.16, 1.43, 0.95, 0.14, 0.90, 0.06, K.mat("wall_steel"))
    K.box("swg", X1 + 0.45, y1 - 0.45, 0.36, 0.44, 0.34, 0.72, K.mat("gear"))
    K.box("swg_cap", X1 + 0.45, y1 - 0.45, 0.735, 0.46, 0.36, 0.03, K.mat("wall_steel"))
    K.pipe_run("swg_feed", [(X1 + 0.45, y1 - 0.28, 0.30), (X1 + 0.16, y1 - 0.28, 0.30),
                            (X1 + 0.16, 1.43, 0.30), (X1 + 0.16, 1.43, 0.92)], 0.04, K.mat("wall_steel"))
    if p["tray"]:
        # Beside the switchgear, in front of the rear block: its old spot (y 2.55) is inside
        # the widened block's footprint at L3.
        tx, ty = X1 + 0.98, 1.15
        K.transformer("tr", tx, ty, 0.0, s=0.95, accent=False)
        K.pipe_run("tr_lv", [(tx - 0.25, ty, 0.30), (X1 + 0.45, ty, 0.30), (X1 + 0.45, y1 - 0.28, 0.30)],
                   0.04, K.mat("wall_steel"))
    K.cyl("downpipe_r", X1 + 0.05, 0.12, h / 2, 0.03, h - 0.2, K.mat("stack"), segments=8)


def _rail_bay(K, p):
    """Siding, wagons, platform, canopy, roller door on the rear block's +X face."""
    rx1, y0, y1 = p["rx1"], STEP2_Y1, p["back"]
    # Ballast strip abutting the apron (never overlapping it — coplanar tops z-fight).
    K.box("ballast", (X1 + 1.4 + 0.05 + RAIL_X + 0.45) / 2, (RAIL_Y0 + RAIL_Y1) / 2, -0.03,
          RAIL_X + 0.45 - (X1 + 1.4 + 0.05), RAIL_Y1 - RAIL_Y0 + 0.20, 0.06, K.mat("yard_pad"))
    fm = K._fine_mode
    K._fine_mode = True
    for s_ in (-1, 1):
        K.box("rail%d" % (s_ > 0), RAIL_X + s_ * 0.10, (RAIL_Y0 + RAIL_Y1) / 2, 0.035, 0.04,
              RAIL_Y1 - RAIL_Y0, 0.05, K.mat("wall_steel"))
    k, y = 0, RAIL_Y0 + 0.12
    while y < RAIL_Y1 - 0.10:
        K.box("sleeper%d" % k, RAIL_X, y, 0.012, 0.40, 0.09, 0.024, K.mat("crate"))
        y += 0.30
        k += 1
    K._fine_mode = fm
    # Platform at wagon-floor height along the block's face, with a roller door.
    K.box("rail_dock", rx1 + 0.18, (y0 + 0.30 + y1 - 0.10) / 2, WAGON_FLOOR / 2, 0.36,
          y1 - 0.10 - (y0 + 0.30), WAGON_FLOOR, K.mat("yard_pad"))
    K.box("rail_dock_edge", rx1 + 0.34, (y0 + 0.30 + y1 - 0.10) / 2, WAGON_FLOOR - 0.04, 0.04,
          y1 - 0.10 - (y0 + 0.30), 0.08, K.mat("wall_steel"))
    K.gate("rail_door", "+X", (rx1, (y0 + y1) / 2, WAGON_FLOOR + 0.55), 0.80, 1.10)
    # Canopy over platform and track, on two posts at the track's far rail.
    cx = (rx1 + RAIL_X + 0.45) / 2
    K.box("rail_canopy", cx, (y0 + 0.2 + y1) / 2, CANOPY_Z, RAIL_X + 0.45 - rx1, y1 - y0 - 0.2, 0.06,
          K.mat("gear"))
    K.box("rail_canopy_edge", RAIL_X + 0.43, (y0 + 0.2 + y1) / 2, CANOPY_Z - 0.05, 0.04,
          y1 - y0 - 0.2, 0.14, K.mat("wall_steel"))
    for i, py in enumerate((y0 + 0.45, y1 - 0.25)):
        K.box("canopy_post%d" % i, RAIL_X + 0.42, py, CANOPY_Z / 2, 0.07, 0.07, CANOPY_Z, K.mat("gear"))
    # Two goods wagons: chassis, body with a sliding door, bogies, buffers.
    W, L, H = WAGON
    for i, wy in enumerate(WAGON_YS):
        K.box("wag%d_ch" % i, RAIL_X, wy, WAGON_FLOOR - 0.06, W - 0.10, L + 0.16, 0.08, K.mat("wall_steel"))
        K.box("wag%d" % i, RAIL_X, wy, WAGON_FLOOR + H / 2, W, L, H, K.mat("gear"))
        K.box("wag%d_roof" % i, RAIL_X, wy, WAGON_FLOOR + H + 0.03, W + 0.04, L + 0.04, 0.06,
              K.mat("wall_steel"))
        K.box("wag%d_door" % i, RAIL_X + W / 2 + 0.008, wy + 0.12, WAGON_FLOOR + H / 2 - 0.02, 0.016,
              0.55, H - 0.16, K.mat("wall_steel"))
        K.box("wag%d_stripe" % i, RAIL_X + W / 2 + 0.006, wy - 0.45, WAGON_FLOOR + 0.18, 0.012, 0.40,
              0.08, K.mat("ht_accent"))
        for j, by in enumerate((wy - L / 2 + 0.28, wy + L / 2 - 0.28)):
            for s_ in (-1, 1):
                K.cyl("wag%d_w%d%d" % (i, j, s_ > 0), RAIL_X + s_ * 0.22, by, 0.11, 0.11, 0.07,
                      K.mat("crate"), axis='X', segments=12)
        for s_ in (-1, 1):
            K.box("wag%d_buf%d" % (i, s_ > 0), RAIL_X, wy + s_ * (L / 2 + 0.10), WAGON_FLOOR - 0.02,
                  0.30, 0.06, 0.08, K.mat("wall_steel"))


def _frame(p):
    yb = p["back"] if p["steps"] == 3 else STEP2_Y1
    top = (STEP_H[1] if p["steps"] == 3 else STEP_H[0]) + PARAPET_H + 0.06
    xs_top = p.get("rx1", X1) if p["steps"] == 3 else X1
    yt = STEP2_Y1 if p["steps"] == 3 else 0.0
    ya = min(yb, 3.0) + 0.2
    pts = [(X0 - 0.1, FY0 - 0.35, 0.0), (X1 + 1.4, FY0 - 0.35, 0.0), (X1 + 1.4, ya, 0.0),
           (X0, FY0, EAVE + 0.2), (p.get("rx1", X1), yb, 0.0)]
    if p.get("rail"):
        pts += [(RAIL_X + 0.45, RAIL_Y1 + 0.10, 0.0), (RAIL_X + 0.45, RAIL_Y0 - 0.10, 0.0),
                (RAIL_X + 0.45, yb, CANOPY_Z + 0.1)]
    pts += [
           (X0, yb, top), (xs_top, yb, top), (X0, yt, top)]
    if p["mast"]:
        pts.append((X0 + 0.45, STEP2_Y1 + 0.45, top + 1.9))
    cs = [x + y for x, y, z in pts]
    hs = [z - (x - y) / 2.0 for x, y, z in pts]
    c, h = (min(cs) + max(cs)) / 2.0, (min(hs) + max(hs) + 0.10) / 2.0
    return (c / 2.0, c / 2.0, h)


def build_high_tech(level: int = 2) -> dict:
    p = HT_LEVELS[level]
    setup_rig(target=_frame(p))
    K = Kit(open_collection("BLDG_hightech"))
    K.M["laser"] = _emissive("laser", (1.0, 0.08, 0.04), 3.0)
    pane = _glass("ht_pane", PALETTE["ht_glass"], GLASS_ALPHA)
    seam = _glass("ht_seam", (0.12, 0.24, 0.36), min(1.0, GLASS_ALPHA + 0.35))

    # The apron reaches the transformer and no further: carried to the back of the L3
    # extension it put the sprite's column range at 1011 px and clipped the frame.
    ya = min(p["back"] if p["steps"] == 3 else STEP2_Y1, 3.0) + 0.2
    K.box("apron", (X0 - 0.1 + X1 + 1.4) / 2, (FY0 - 0.35 + ya) / 2, -0.03,
          X1 + 1.4 - X0 + 0.1, ya - FY0 + 0.35, 0.06, K.mat("yard"))
    # Step 2 first: its front face is the hall's rear wall and must exist before the hall.
    # With the two flat blocks level, the rim between them is left out where they abut so the
    # roof reads as one deck; step 2's back rim survives only beyond step 3's narrower plan.
    _block(K, "s1", X0, X1, 0.0, STEP2_Y1, STEP_H[0], skip=("b",) if p["steps"] == 3 else ())
    K.window("sw0", "+X", (X1, 1.45, STEP_H[0] - 0.75), 1.00, 0.42, cols=4, rows=1)
    _front_hall(K, pane, seam)
    _racks(K, p["racks"])
    _cell(K, p["robots"])
    _glass_corner(K, p, pane)
    if p["steps"] == 3:
        rx1 = p["rx1"]
        _block(K, "s2", X0, rx1, STEP2_Y1, p["back"], STEP_H[1], skip=("f",))
        if rx1 > X1 + 0.05:
            _parapet(K, "s2f", X1, rx1, STEP2_Y1, STEP2_Y1 + PARAPET_W + 0.02, STEP_H[1],
                     skip=("b", "l"))
        # Window strip high on the +X face, above the rail canopy when there is one.
        K.window("sw1", "+X", (rx1, (STEP2_Y1 + p["back"]) / 2, STEP_H[1] - 0.42),
                 p["back"] - STEP2_Y1 - 0.70, 0.32, cols=5, rows=1)
        if p["rail"]:
            _rail_bay(K, p)
    for i in range(p["ahus"]):
        _ahu(K, str(i), X0 + 0.75 + i * 1.05, 1.15, STEP_H[0] + 0.06)
    if p["elec"]:
        z = STEP_H[1] + 0.06
        for i in range(p["elec"]):
            _elec_unit(K, str(i), X0 + 0.55 + i * 0.80, p["back"] - 0.45, z)
        K.box("roof_tray", X0 + 0.55 + (p["elec"] - 1) * 0.40, p["back"] - 0.50 - 0.40, z + 0.03,
              (p["elec"] - 1) * 0.80 + 0.40, 0.10, 0.05, K.mat("wall_steel"))
        K.box("roof_tray_drop", X0 + 0.55 + (p["elec"] - 1) * 0.80 + 0.30, p["back"] - 0.90, z + 0.03,
              0.10, 0.10, 0.05, K.mat("wall_steel"))
    _services(K, p)
    if p["mast"]:
        h = STEP_H[1]
        K.lattice_mast("mast", X0 + 0.45, STEP2_Y1 + 0.45, h + 0.06, h + 1.85, w=0.16, bays=4)
        K.cyl("mast_dish", X0 + 0.45, STEP2_Y1 + 0.45, h + 1.95, 0.16, 0.06, K.mat("wall_bright"), segments=16)

    print("\n".join(K.validate(ground=-0.06)))
    return {"building": "high_tech_manufactory", "level": level, "steps": p["steps"],
            "objects": len(K.col.objects)}
