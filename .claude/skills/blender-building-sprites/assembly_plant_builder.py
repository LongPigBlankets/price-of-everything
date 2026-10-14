# Parametric builder for the Assembly Plant (b_009).
# Run AFTER sprite_kit.py:
#   exec(open(".../sprite_kit.py").read())
#   exec(open(".../assembly_plant_builder.py").read()); build_assembly_plant(2)
#
# BUILDING class on z=0, manufacturing family beside the brick factory — and BRICK like it. A
# wide hall under a gentle segmental barrel vault of PARTLY TRANSPARENT glass, with the front
# wall left out (an open portal frame, the EAF's precedent) so the conveyor and the robots are
# visible through the front as well as faintly through the roof. From L2 the plan is an L: a
# tall flat-roofed head block at the left end of the hall and a second vaulted wing running
# back from it, a bay shorter than the hall so the L reads square in iso. The loading bay at the right end is a CONTAINER bay at
# every level; at L3 a rail-mounted gantry crane straddles it. Orange is the chroma and it is
# carried by the ROBOTS ONLY — cartons are brown and black.
#
# ---------------------------------------------------------------------------------------
# THE FIVE THINGS THAT MAKE IT READ
#
# 1. THE FLOOR IS AT DOCK HEIGHT, AND THAT IS WHAT MAKES THE LOADING BAY PHYSICAL. A real plant
#    floor sits at truck-bed height and the yard is the thing that is low; the dock outside is
#    simply the floor continuing through the wall. The first version had the floor at grade
#    and a dock 0.5 above it, which put the forklift door's sill half a metre above the floor
#    it served — "half suspended", as the owner put it — and a belt that was knee-high inside
#    and lying on the slab outside. Raising the floor to FLOOR = 0.42 fixes every one of those
#    at once, and the exposed slab edge along the open front is the kerb for free.
#
# 2. THE INTERIOR IS VISIBLE BY CONSTRUCTION, NOT BY LUCK. The view ray toward the camera runs
#    (+1, -1, +1), so a point at depth d behind the open front, height z, exits the front plane
#    at height z + d. It is seen iff  FLOOR < z + d < underside of the header beam. Raising
#    the floor pushed the far-flank robot elbows to 2.72, which is why the eave is 3.05 (header
#    underside 2.81). Run the nine-line check before rendering.
#
# 3. GLASS IS TRANSPARENT ONLY AGAINST THE INTERIOR, AND THE INTERIOR IS BRICK TOO. The
#    vault is alpha-blended, so whatever is behind it shows through, and every ray through it
#    must land on something opaque or the map would show through the roof in-game. Traced:
#    the ray runs (-1, +1, -1), so through the hall vault it lands on the back wall's INNER
#    face for almost the whole roof — at the crown it hits that wall at z 2.16. Two things
#    follow. First, that inner face shows, so it has to be the same brick as outside: a pale
#    lining was tried and, seen through the steep part of the vault, it read as a grey wall
#    where a brick one was expected. Second, rays entering the vault's back 0.4 escape OVER the wall
#    top — the highest at 3.08 against an eave of 3.05 (it peaks where dz/dy = -1, i.e. at
#    y = R/sqrt 2) — and would land on background, so a 0.08 parapet lip along the back wall
#    and the wing's far flank catches them. The shading-mask pass uses a material OVERRIDE,
#    so the glass is opaque there and the print pass treats the roof as a surface.
#
# 4. THE HEAD BLOCK IS TALLER THAN BOTH CROWNS. Two vaults meeting at a corner need something
#    for their ends to die into; a flat-roofed block lower than the crowns would show two cut
#    vault ends poking out above it.
#
# 5. THE WING'S LENGTH IS BOUNDED BY SCREEN HEIGHT, NOT WIDTH. Screen height is z - (x - y)/2:
#    the wing's far end (small x, large y) is the highest thing on screen and the yard's
#    front-right corner (large x, small y) the lowest, and the two pull apart. A 6-bay hall
#    with a 6-bay wing and a container lane overran the 1024 frame vertically; 5 + 5 fits with
#    ~25 px to spare. `_frame` measures it — read the bbox after every layout change.

import math

# Glass. MEASURED under the rig: (0.47, 0.61, 0.72) renders 154,166,173 — AgX desaturates
# anything that pale to grey, and blended over the brick back wall it went to mud. This one
# renders 112,140,156, a clear pale blue with room to darken over the interior.
PALETTE["glass_pale"] = (0.090, 0.170, 0.220)   # warm teal slate, a shade lighter than the
PALETTE["glass_seam"] = (0.050, 0.100, 0.140)   # windows' so the vault still reads as glass
# ---- Materials shared with the industrial goods factory and the high-tech manufactory: clay
# brick with lime mortar, a dark membrane roof, stone dressings, warm teal windows seen into a
# dark room, silver rainwater goods. Names matter: the 3D export picks printed patterns by
# material name (*brick* coursing, membrane gravel, apron paving).
PALETTE["ap_brick"] = (0.380, 0.165, 0.095)
PALETTE["membrane"] = (0.120, 0.125, 0.130)
PALETTE["ap_stone"] = (0.600, 0.560, 0.470)
PALETTE["ap_interior"] = (0.040, 0.036, 0.032)
PALETTE["ap_interior_lo"] = (0.085, 0.075, 0.062)
PALETTE["ap_plinth"] = (0.035, 0.037, 0.042)
ROLES["ap_wall"] = "ap_brick"
WINDOW_GLASS = ((0.070, 0.140, 0.190), 0.72)
PALETTE["orange"] = (0.620, 0.215, 0.038)       # ROBOTS ONLY
PALETTE["carton"] = (0.300, 0.165, 0.072)       # cardboard
PALETTE["crate"] = (0.052, 0.055, 0.062)        # black crates / parts bins
PALETTE["gantry_green"] = (0.080, 0.240, 0.135) # the PORT's crane green, so the container
PALETTE["gantry_green_lo"] = (0.050, 0.165, 0.095)  # gantry reads as the same family
ROLES["robot"] = "orange"
ROLES["carton"] = "carton"
ROLES["crate"] = "crate"

# THE HALL IS THE SAME LENGTH AT EVERY LEVEL. The loading bay is built against its right
# gable from L1, so the hall cannot grow to the right afterwards, and the head block takes
# its left end at L2. Levels add PARTS, not length: L1 hall + loading bay; L2 + head block;
# L3 + the wing (the L's back leg) + the gantry crane. Only the robot count grows inside.
AP_LEVELS = {
    1: dict(robots=((1, "far"), (3, "near")), head=False, wing=0, wrobots=(), crane=False),
    2: dict(robots=((0, "far"), (1, "near"), (2, "far"), (4, "far")), head=True, wing=0,
            wrobots=(), crane=False),
    3: dict(robots=((0, "far"), (1, "near"), (2, "far"), (3, "far"), (4, "near")), head=True,
            wing=4, wrobots=((1, "far"), (2, "near"), (3, "far")), crane=True),
}
BAYS = 5

BAY = 1.05
HX0 = -2.75                       # left gable; the hall grows to the right
HY0, HY1 = -1.40, 1.40            # hall depth: WIDE, so the vault is gentle
FLOOR = 0.42                      # floor slab top = dock top (note 1)
EAVE = 3.05
RISE = 0.72                       # rise/half-span 0.51 — a segmental arch, not a half-round
HEADER = 0.24                     # portal header beam; its underside is the view window
COL = 0.20
GABLE_T = 0.14
SEAM = 0.018
GLASS_ALPHA = 0.62                # over BRICK inner faces; 0.55 over pale lining went mauve

HEAD_W = 2.40                     # head block and wing width, in X
WING_RISE = 0.50
WING_BAY = 1.05

BELT_Y = HY0 + 1.05
BELT_H = 0.49                     # belt top above the floor
BELT_W = 0.36
BOX = (0.26, 0.22, 0.20)
ROBOT_OFF = 0.55                  # pedestal centre, off the belt centreline
# The wing's line runs along Y, seen through the wing's OPEN +X face. Depth d is measured in
# from that face and the same window applies: FLOOR < z + d < EAVE - HEADER. Belt at d 0.85
# (top 1.76, cartons 1.96), far robots at d 1.40 (pedestal 1.82, elbow 2.52), near at d 0.30
# (pedestal 0.72, elbow 2.14) — all inside 0.42..2.81.
WING_BELT_D = 0.85
DOCK_OUT = 0.85                   # belt run outside the gable
DOCK_X1 = 1.75                    # dock slab extends to x1 + this
DOCK_Y0 = BELT_Y - 0.75           # dock spans from here to the back of the gable
DOOR_Y = 0.95                     # forklift roller door, clear of the belt arch
CONT = (0.75, 0.50, 0.50)         # a 20-ft box: length (X), width, height
CRANE_X = 2.28                    # gantry centreline over the lane; its front leg stood in
                                  # front of the belt exit at 2.10
CRANE_YF, CRANE_YB = -1.95, HY1 + 0.35
CRANE_H = 3.00
APRON_D = 0.75                    # the front crane rail at y -2.00 has to stand on it
APRON_OVER = 0.10


class _Arc:
    """Segmental arc through (+-hs, eave) with the given rise, centred at `pc` across."""

    def __init__(self, pc, hs, rise, eave):
        self.pc, self.hs, self.rise, self.eave = pc, hs, rise, eave
        self.R = (hs * hs + rise * rise) / (2.0 * rise)
        self.zc = eave + rise - self.R
        self.th0 = math.asin((eave - self.zc) / self.R)
        self.crown = eave + rise

    def pt(self, theta, lift=0.0):
        r = self.R + lift
        return (self.pc + r * math.cos(theta), self.zc + r * math.sin(theta))

    def profile(self, seg=24, lift=0.04):
        prof = [(self.pc - self.hs, 0.0), (self.pc + self.hs, 0.0),
                (self.pc + self.hs, self.eave)]
        for i in range(seg + 1):
            th = self.th0 + (math.pi - 2 * self.th0) * i / seg
            prof.append(self.pt(th, lift))
        prof.append((self.pc - self.hs, self.eave))
        return prof


HALL = _Arc((HY0 + HY1) / 2.0, (HY1 - HY0) / 2.0, RISE, EAVE)
WING = _Arc(HX0 - HEAD_W / 2.0, HEAD_W / 2.0, WING_RISE, EAVE)
HEAD_H = max(HALL.crown, WING.crown) + 0.25


def _glass(name, colour, alpha):
    """Alpha-blended flat material. BLENDED, not DITHERED: dither is noise, and after the
    print pass noise is indistinguishable from stipple."""
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
    mt.use_transparency_overlap = False
    mt.use_backface_culling = False
    return mt


def _vault(K, name, arc, axis, a0, a1, bays, pane, seam, seg=24):
    """Glass barrel vault as one mesh: pane quads and seam strips sharing edges, along `axis`
    ('X' or 'Y') from a0 to a1, with the arc profile ACROSS it. Seams are material slot 1."""
    import bpy, bmesh
    spans_a, a = [], a0
    for b in range(bays):
        ae = a0 + (a1 - a0) * (b + 1) / bays
        if b < bays - 1:
            spans_a.append((a, ae - SEAM / 2.0, False))
            spans_a.append((ae - SEAM / 2.0, ae + SEAM / 2.0, True))
            a = ae + SEAM / 2.0
        else:
            spans_a.append((a, a1, False))
    th_a, th_b = arc.th0, math.pi - arc.th0
    dth = SEAM / arc.R
    cuts = [th_a + (th_b - th_a) * f for f in (1.0 / 3.0, 2.0 / 3.0)]
    spans_t, t, per = [], th_a, max(2, seg // 3)
    for c in cuts:
        for i in range(per):
            spans_t.append((t + (c - dth / 2.0 - t) * i / per,
                            t + (c - dth / 2.0 - t) * (i + 1) / per, False))
        spans_t.append((c - dth / 2.0, c + dth / 2.0, True))
        t = c + dth / 2.0
    for i in range(per):
        spans_t.append((t + (th_b - t) * i / per, t + (th_b - t) * (i + 1) / per, False))

    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    flags, cache = [], {}

    def v(aa, th):
        key = (round(aa, 5), round(th, 6))
        if key not in cache:
            p, z = arc.pt(th)
            cache[key] = bm.verts.new((aa, p, z) if axis == 'X' else (p, aa, z))
        return cache[key]

    for (ta, tb, st) in spans_t:
        for (aa, ab, sa) in spans_a:
            bm.faces.new([v(aa, ta), v(ab, ta), v(ab, tb), v(aa, tb)])
            flags.append(sa or st)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me)
    bm.free()
    ob = K.obj(name, me, pane, smooth=True)
    ob.data.materials.append(seam)
    for poly, f in zip(me.polygons, flags):
        poly.material_index = 1 if f else 0
    # ARCHED RIBS UNDER THE PANES, at half-bay spacing. With the interior lined pale, the roof
    # blended to one flat tint and the transparency was invisible in effect; what makes a
    # glasshouse read as glass is the structure SEEN THROUGH it. Freestyle treats the glass as
    # opaque geometry, so the ribs take no ink — they show only as soft dark arcs through the
    # panes, which is exactly the look.
    fm = K._fine_mode
    K._fine_mode = True
    n_ribs = 2 * bays - 1
    for k in range(n_ribs):
        aa = a0 + (a1 - a0) * (k + 1) / (n_ribs + 1)
        pts = []
        for i in range(15):
            th = th_a + (th_b - th_a) * i / 14
            pp, z = arc.pt(th, -0.075)
            pts.append((aa, pp, z) if axis == 'X' else (pp, aa, z))
        K.sweep("%s_rib%d" % (name, k), pts, 0.032, K.mat("wall_steel"), seg=6)
    K._fine_mode = fm
    return ob


def _gable(K, name, arc, axis, at, mat):
    if axis == 'X':
        K.prism(name, (at, 0.0, 0.0), (0.0, 1.0, 0.0), arc.profile(), GABLE_T, K.mat(mat))
    else:
        K.prism(name, (0.0, at, 0.0), (1.0, 0.0, 0.0), arc.profile(), GABLE_T, K.mat(mat))


# ROBOT POSE (2026-09-10, supply-chain view animation). The arms are baked into the sprite in
# the RAISED pose; the empire view lays animated arm FRAMES over the sprite (render_arms.py
# renders the plant with only the "rb*" objects visible and the rest as a holdout, at each
# pose below, so a pillar still hides the arm behind it). `ROBOT_POSE = (lift, carry)`:
# lift 0 = raised (the baked pose), 1 = wrist down on the belt over a carton; carry = a
# carton held in the fingers. The runtime sequence: down empty, up with carton, down with
# carton, up empty.
ROBOT_POSE = (0.0, False)
ROBOT_NAMES = []               # every object the arm frames must show
# The SHIPPED sprite carries only the pedestal and turret of each robot: the moving arm is
# drawn by the empire view from the frames, so a baked arm would show under the animated one.
# render_arms.py sets this True to render the arms themselves.
ROBOT_ARMS = False


def _robot(K, tag, x, y0, reach):
    """Six-axis arm on a pedestal at (x, y0), standing on the floor and reaching over the belt
    in the horizontal direction `reach` = (dx, dy), a unit vector."""
    dx, dy = reach
    z = FLOOR
    fm = K._fine_mode
    K._fine_mode = True
    before = {o.name for o in K.col.objects}
    K.cyl("rb%s_ped" % tag, x, y0, z + 0.14, 0.13, 0.28, K.mat("gear"), segments=14)
    K.box("rb%s_tur" % tag, x, y0, z + 0.36, 0.24, 0.22, 0.16, K.mat("robot"))
    if not ROBOT_ARMS:
        K._fine_mode = fm
        return
    lift, carry = ROBOT_POSE
    sh = (x, y0, z + 0.44)
    # raised: elbow high, wrist over the belt at hand height; lowered: elbow forward and
    # down, wrist on the carton (belt top + carton + finger reach)
    el_up, el_dn = (x + dx * 0.36, y0 + dy * 0.36, z + 0.99), (x + dx * 0.52, y0 + dy * 0.52, z + 0.80)
    wr_up, wr_dn = (x + dx * 0.78, y0 + dy * 0.78, z + 0.69), (x + dx * 0.55, y0 + dy * 0.55, FLOOR + BELT_H + BOX[2] + 0.16)
    el = tuple(a + (b - a) * lift for a, b in zip(el_up, el_dn))
    wr = tuple(a + (b - a) * lift for a, b in zip(wr_up, wr_dn))
    K.dirbox("rb%s_ua" % tag, sh, el, 0.12, 0.14, K.mat("robot"))
    K.cyl("rb%s_elb" % tag, el[0], el[1], el[2], 0.085, 0.15, K.mat("gear"),
          axis='Y' if dx else 'X', segments=12)
    K.dirbox("rb%s_fa" % tag, el, wr, 0.10, 0.11, K.mat("robot"))
    K.box("rb%s_wr" % tag, wr[0], wr[1], wr[2] - 0.06, 0.10, 0.10, 0.08, K.mat("gear"))
    for d in (-0.035, 0.035):      # fingers, spread ACROSS the reach
        K.box("rb%s_f%d" % (tag, d > 0), wr[0] + d * abs(dy), wr[1] + d * abs(dx),
              wr[2] - 0.15, 0.022 + 0.038 * abs(dx), 0.022 + 0.038 * abs(dy), 0.10,
              K.mat("gear"))
    if carry:
        K.box("rb%s_load" % tag, wr[0], wr[1], wr[2] - 0.16 - BOX[2] / 2 + 0.02, BOX[0] * 0.8,
              BOX[1] * 0.8, BOX[2], K.mat("carton"))
    ROBOT_NAMES.extend(o.name for o in K.col.objects if o.name not in before)
    K._fine_mode = fm


def _belt(K, x0, x1):
    """Level belt at BELT_H above the floor, inside and out — the floor and the dock are the
    same height, so the legs are the same height everywhere."""
    zt = FLOOR + BELT_H
    fm = K._fine_mode
    K._fine_mode = True
    K.box("belt", (x0 + x1) / 2, BELT_Y, zt - 0.03, x1 - x0, BELT_W, 0.06, K.mat("stair"))
    for s in (-1, 1):
        K.box("belt_rail%d" % (s > 0), (x0 + x1) / 2, BELT_Y + s * (BELT_W / 2 + 0.015),
              zt + 0.02, x1 - x0, 0.03, 0.10, K.mat("pipe"))
    x, k = x0 + BAY * 0.25, 0
    while x < x1 - 0.15:
        for s in (-1, 1):
            K.box("belt_leg%d_%d" % (k, s > 0), x, BELT_Y + s * 0.13,
                  FLOOR + (BELT_H - 0.06) / 2, 0.05, 0.05, BELT_H - 0.06, K.mat("scaffold"))
        x += BAY
        k += 1
    K._fine_mode = fm


def _carton(K, name, x, y, z_bottom, k):
    """Brown cardboard or a black crate, by index: the cargo is NOT orange."""
    K.box(name, x, y, z_bottom + BOX[2] / 2, BOX[0], BOX[1], BOX[2],
          K.mat("crate" if k % 3 == 1 else "carton"))


def _boxes(K, x0, x1):
    fm = K._fine_mode
    K._fine_mode = True
    k, x = 0, x0 + 0.25
    while x < x1 - 0.2:
        _carton(K, "carton%d" % k, x, BELT_Y + ((k * 3) % 5 - 2) * 0.012, FLOOR + BELT_H, k)
        x += 0.62 + ((k * 37) % 10) / 10.0 * 0.42
        k += 1
    K._fine_mode = fm


def _container(K, name, cx, cy, z_bottom, mat="box_blue", doors=-1):
    """20-ft box, long axis along X. Doors are on ONE end, and on the dock box that end is
    the one against the dock — which the camera cannot see. The first version put the door
    seams on the camera end because it was visible, which is a container loaded from the
    wrong side. The visible long side carries the corrugation ribs instead."""
    L, W, H = CONT
    K.box(name, cx, cy, z_bottom + H / 2, L, W, H, K.mat(mat))
    dx = cx + doors * (L / 2 + 0.008)
    K.box("%s_doors" % name, dx, cy, z_bottom + H / 2, 0.016, 0.04, H - 0.08, K.mat("wall_steel"))
    for s in (-1, 1):
        K.box("%s_bar%d" % (name, s > 0), dx + doors * 0.004, cy + s * 0.15, z_bottom + H / 2,
              0.024, 0.022, H - 0.12, K.mat("pipe"))
    for k in range(4):
        K.box("%s_rib%d" % (name, k), cx - L / 2 + L * (k + 0.5) / 4, cy - W / 2 - 0.006,
              z_bottom + H / 2, 0.045, 0.012, H - 0.10, K.mat("wall_steel"))


def _loading_bay(K, x1, crane):
    """CONTAINER loading bay. The dock is the hall floor continued outside (note 1); a 20-ft
    box on a chassis is backed END-ON to the dock face so its doors open onto the dock, which
    is how a container is actually loaded from a building. At L3 a rail-mounted gantry
    straddles dock and lane and carries a second box."""
    dx0, dx1 = x1 + 0.05, x1 + DOCK_X1
    K.box("dock", (dx0 + dx1) / 2, (DOCK_Y0 + HY1) / 2, FLOOR / 2, dx1 - dx0, HY1 - DOCK_Y0,
          FLOOR, K.mat("yard_pad"))
    K.box("dock_edge", dx1 - 0.03, (DOCK_Y0 + HY1) / 2, FLOOR - 0.04, 0.06, HY1 - DOCK_Y0,
          0.08, K.mat("wall_steel"))
    K.box("dock_hazard", dx1 - 0.03, (DOCK_Y0 + HY1) / 2, FLOOR + 0.004, 0.06, HY1 - DOCK_Y0,
          0.012, K.mat("plant_yellow"))
    _bollard(K, "dock", dx1 + 0.08, DOCK_Y0 - 0.08)
    for k in range(3):
        K.box("bump%d" % k, dx1 + 0.02, BELT_Y + (k - 1) * 0.40, FLOOR - 0.16, 0.05, 0.14,
              0.22, K.mat("scaffold"))
    # Forklift door: sill ON the dock, which is also the floor — no step either side.
    K.gate("dock_gate", "+X", (x1, DOOR_Y, FLOOR + 0.50), 0.58, 1.00)
    # Belt terminates at a palletising stand; pallets of cartons stand beside it.
    ex = x1 + DOCK_OUT
    K.box("pal_stand", ex + 0.16, BELT_Y, FLOOR + 0.20, 0.30, 0.46, 0.40, K.mat("gear"))
    fm = K._fine_mode
    K._fine_mode = True
    for j, (ox, oy, n) in enumerate(((0.45, 0.55, 2), (0.95, 0.55, 1), (1.30, -0.05, 2),
                                     (0.50, -0.50, 1))):
        K.box("pallet%d" % j, dx0 + ox, BELT_Y + oy, FLOOR + 0.03, 0.34, 0.30, 0.06,
              K.mat("carton"))
        for h in range(n):
            _carton(K, "stack%d_%d" % (j, h), dx0 + ox, BELT_Y + oy, FLOOR + 0.06 + BOX[2] * h,
                    j + h)
    K._fine_mode = fm
    # Container on its chassis, floor level with the dock, doors to the dock face.
    L, W, H = CONT
    ccx = dx1 + 0.04 + L / 2
    # Chassis starts 0.06 off the dock face: flush with it, it ran through the middle bumper.
    K.box("chassis", dx1 + 0.06 + (L + 0.16) / 2, BELT_Y, FLOOR - 0.05, L + 0.16, 0.42, 0.06,
          K.mat("wall_steel"))
    for wx in (ccx - 0.16, ccx + 0.22):
        K.box("axle%d" % (wx > ccx), wx, BELT_Y, 0.11, 0.06, 0.50, 0.05, K.mat("crate"))
        K.box("hanger%d" % (wx > ccx), wx, BELT_Y, 0.24, 0.08, 0.30, 0.24, K.mat("wall_steel"))
        for s in (-1, 1):
            K.cyl("wheel%d_%d" % (wx > ccx, s > 0), wx, BELT_Y + s * 0.22, 0.11, 0.11, 0.08,
                  K.mat("crate"), axis='Y', segments=12)
    _container(K, "cont0", ccx, BELT_Y, FLOOR, doors=-1)

    if crane:
        _gantry(K, x1)


def _gantry(K, x1):
    """Rail-mounted container gantry: two portal legs on rails along X, a box girder across
    in Y, trolley, spreader and a box in the air. Bottle green, like the port's cranes."""
    g, glo, dark = K.mat("gantry_green"), K.mat("gantry_green_lo"), K.mat("wall_steel")
    cx = x1 + CRANE_X
    zt = CRANE_H
    for tag, ly in (("f", CRANE_YF), ("b", CRANE_YB)):
        K.box("rail_%s" % tag, x1 + 1.75, ly, 0.03, 2.30, 0.14, 0.06, K.mat("scaffold"))
        for s in (-1, 1):
            px = cx + s * 0.34
            K.box("leg_%s%d" % (tag, s > 0), px, ly, zt / 2 + 0.06, 0.16, 0.22, zt - 0.12, g)
            K.box("boot_%s%d" % (tag, s > 0), px, ly, 0.12, 0.26, 0.34, 0.14, dark)
        K.box("port_%s" % tag, cx, ly, zt - 0.02, 0.34 * 2 + 0.16, 0.22, 0.20, g)
        K.box("brace_%s" % tag, cx, ly, zt * 0.48, 0.34 * 2, 0.12, 0.10, glo)
    K.box("girder", cx, (CRANE_YF + CRANE_YB) / 2, zt + 0.23, 0.30, CRANE_YB - CRANE_YF + 0.40,
          0.30, g)
    K.box("girder_lo", cx, (CRANE_YF + CRANE_YB) / 2, zt + 0.08, 0.40, CRANE_YB - CRANE_YF,
          0.06, glo)
    ty = BELT_Y + 1.05                                   # trolley over the dock's rear half
    K.box("trolley", cx, ty, zt - 0.08, 0.52, 0.46, 0.16, dark)
    K.box("cab", cx - 0.42, CRANE_YF + 0.55, zt - 0.45, 0.30, 0.34, 0.30, dark)
    fm = K._fine_mode
    K._fine_mode = True
    L, W, H = CONT
    zs = FLOOR + 1.25                                     # spreader, clear of the dock stacks
    for sx in (-1, 1):
        for sy in (-1, 1):
            K.dircyl("wire%d%d" % (sx > 0, sy > 0), (cx + sx * 0.20, ty + sy * 0.18, zt - 0.16),
                     (cx + sx * 0.20, ty + sy * 0.18, zs + 0.03), 0.012, K.mat("scaffold"),
                     segments=6)
    K.box("spreader", cx, ty, zs, L + 0.06, 0.18, 0.06, dark)
    for sx in (-1, 1):
        K.box("sheave%d" % (sx > 0), cx + sx * 0.20, ty, zs + 0.07, 0.08, 0.40, 0.08, glo)
    K._fine_mode = fm
    _gantry_detail(K, x1, cx, zt, ty)
    _container(K, "cont1", cx, ty, zs - 0.03 - H, "cont_blue", doors=1)


def _wing_line(K, hx1, wy0, wy1, wrobots):
    """Second line along Y inside the wing: belt, cartons, robots. It runs toward the head
    block, which is where its output goes."""
    bx = hx1 - WING_BELT_D
    y0, y1 = wy0 + 0.20, wy1 - 0.35
    zt = FLOOR + BELT_H
    fm = K._fine_mode
    K._fine_mode = True
    K.box("wbelt", bx, (y0 + y1) / 2, zt - 0.03, BELT_W, y1 - y0, 0.06, K.mat("stair"))
    for sx in (-1, 1):
        K.box("wbelt_rail%d" % (sx > 0), bx + sx * (BELT_W / 2 + 0.015), (y0 + y1) / 2,
              zt + 0.02, 0.03, y1 - y0, 0.10, K.mat("pipe"))
    y, k = y0 + WING_BAY * 0.25, 0
    while y < y1 - 0.15:
        for sx in (-1, 1):
            K.box("wbelt_leg%d_%d" % (k, sx > 0), bx + sx * 0.13, y,
                  FLOOR + (BELT_H - 0.06) / 2, 0.05, 0.05, BELT_H - 0.06, K.mat("scaffold"))
        y += WING_BAY
        k += 1
    k, y = 0, y0 + 0.25
    while y < y1 - 0.2:
        _carton(K, "wcarton%d" % k, bx + ((k * 3) % 5 - 2) * 0.012, y, FLOOR + BELT_H, k + 1)
        y += 0.62 + ((k * 41) % 10) / 10.0 * 0.42
        k += 1
    K._fine_mode = fm
    for i, (bay, flank) in enumerate(wrobots):
        sgn = 1.0 if flank == "far" else -1.0          # far = beyond the belt, reaches +X
        _robot(K, "w%d" % i, bx - sgn * ROBOT_OFF, wy0 + (bay + 0.5) * WING_BAY, (sgn, 0.0))


def _head(K):
    """Flat-roofed head block at the hall's left end (L2+): offices over the line's feed."""
    hx0, hx1 = HX0 - HEAD_W, HX0
    hcx = (hx0 + hx1) / 2.0
    K.box("head", hcx, HALL.pc, HEAD_H / 2, HEAD_W, HY1 - HY0, HEAD_H, K.mat("ap_wall"))
    K.box("head_roof", hcx, HALL.pc, HEAD_H + 0.03, HEAD_W - 0.02, HY1 - HY0 - 0.02, 0.06,
          K.mat("membrane"))
    # Parapet: a raised brick rim round the roof edge, with a coping course on top.
    pw, ph = 0.11, 0.16
    for tag, (bx, by, sx, sy) in {
        "f": (hcx, HY0 + pw / 2, HEAD_W, pw), "b": (hcx, HY1 - pw / 2, HEAD_W, pw),
        "l": (hx0 + pw / 2, HALL.pc, pw, HY1 - HY0), "r": (hx1 - pw / 2, HALL.pc, pw, HY1 - HY0),
    }.items():
        K.box("parapet_%s" % tag, bx, by, HEAD_H + ph / 2, sx, sy, ph, K.mat("ap_wall"))
        K.box("coping_%s" % tag, bx, by, HEAD_H + ph + 0.02, sx + 0.03, sy + 0.03, 0.04,
              K.mat("ap_stone"))
    # Skylight: a low upstand frame with a mullioned glass lid, centred on the roof.
    sx_, sy_ = 1.00, 0.74
    K.box("sky_frame", hcx - 0.15, HALL.pc, HEAD_H + 0.11, sx_, sy_, 0.10, K.mat("gear"))
    K.box("sky_room", hcx - 0.15, HALL.pc, HEAD_H + 0.158, sx_ - 0.10, sy_ - 0.10, 0.006,
          K.M["ap_interior"])
    K.box("sky_glass", hcx - 0.15, HALL.pc, HEAD_H + 0.175, sx_ - 0.10, sy_ - 0.10, 0.012,
          _glass("ap_window", *WINDOW_GLASS))
    K.box("sky_mul_x", hcx - 0.15, HALL.pc, HEAD_H + 0.20, sx_ - 0.08, 0.03, 0.02,
          K.mat("window_frame"))
    K.box("sky_mul_y", hcx - 0.15, HALL.pc, HEAD_H + 0.20, 0.03, sy_ - 0.08, 0.02,
          K.mat("window_frame"))
    K.box("head_rtu", hcx + 0.80, HALL.pc + 0.85, HEAD_H + 0.21, 0.44, 0.36, 0.30,
          K.mat("gear"))
    for k, (vx, vy) in enumerate(((hcx + 0.75, HALL.pc - 0.55), (hcx - 0.80, HALL.pc + 0.80))):
        _ventilator(K, "head%d" % k, vx, vy, HEAD_H + 0.06)
    # A dark plinth along the front, open at the door; the roof drains through a scupper in
    # the front parapet to a downpipe at the left corner.
    door_x = hx0 + 0.45 + 0.75
    for k, (a, b) in enumerate(((hx0 - 0.03, door_x - 0.22), (door_x + 0.22, hx1))):
        K.box("head_plinth%d" % k, (a + b) / 2, HY0 - 0.015, 0.11, b - a, 0.06, 0.22, K.M["ap_plinth"])
    K.box("head_scupper", hx0 + 0.08, HY0 - 0.04, HEAD_H + 0.05, 0.10, 0.10, 0.06, K.mat("pipe"))
    _downpipe(K, "head", hx0 + 0.08, HY0 - 0.08, HEAD_H + 0.02, "-Y")
    # Three columns on a 0.75 grid, THREE storeys on a 1.15 pitch. Ground floor: window,
    # DOOR, window — the door takes the middle column and the window HEADS align with the
    # door head at 1.00 (windows are 0.52 tall, so the row centre is 0.74). First and second
    # floors: three windows each on the same columns; the top row head is 0.72 below the deck.
    xs = [hx0 + 0.45 + i * 0.75 for i in range(3)]
    for r, z in enumerate((0.74, 1.89, 3.04)):
        for i, x in enumerate(xs):
            if r == 0 and i == 1:
                K.door("head_door", "-Y", (x, HY0, 0.50), 0.36, 1.00)
                lintel = K.col.objects.get("head_door_lintel")
                if lintel is not None: lintel.data.materials[0] = K.M["ap_stone"]
                _lamp(K, "door", x, HY0, 1.22)
            else:
                _window(K, "head_w%d%d" % (r, i), x, HY0, z, 0.40, 0.52)



def _wing(K, wing_bays, wrobots, pane, seam):
    """The L's back leg (L3): a second vault running back from the head block, its +X face an
    open portal frame like the hall's, with its own line inside."""
    hx0, hx1 = HX0 - HEAD_W, HX0
    wy0, wy1 = HY1, HY1 + wing_bays * WING_BAY
    # Floor slab to the +X face, so its exposed edge is the kerb of the open front (note 1).
    K.box("wing_floor", (hx0 + hx1) / 2, (wy0 + wy1) / 2 - 0.01, FLOOR / 2, HEAD_W - 0.04,
          wy1 - wy0 - 0.02, FLOOR, K.mat("yard_pad"))
    # +X face: OPEN portal frame — columns on the bay lines and a header at the eave, the
    # same construction as the hall's front, so the wing's line is seen the same way.
    for b in range(wing_bays + 1):
        cy = min(max(wy0 + b * WING_BAY, wy0 + COL / 2), wy1 - COL / 2)
        K.box("wcol%d" % b, hx1 - COL / 2 + 0.005, cy, EAVE / 2, COL, COL, EAVE, K.mat("gear"))
    K.box("wheader", hx1 - 0.11 + 0.005, (wy0 + wy1) / 2, EAVE - HEADER / 2, 0.22, wy1 - wy0,
          HEADER, K.mat("gear"))
    K.box("wing_flank_l", hx0 + 0.06, (wy0 + wy1) / 2, EAVE / 2, 0.12, wy1 - wy0, EAVE,
          K.mat("ap_wall"))
    K.box("wing_lip_l", hx0 + 0.06, (wy0 + wy1) / 2, EAVE + 0.04, 0.12, wy1 - wy0, 0.08,
          K.mat("ap_wall"))
    _gable(K, "wing_gable", WING, 'Y', wy1 - GABLE_T / 2, "ap_wall")
    _vault(K, "wing_vault", WING, 'Y', wy0, wy1 - GABLE_T, wing_bays, pane, seam)
    K.box("wing_gutter", hx1 + 0.095, (wy0 + wy1) / 2 + 0.03, EAVE - 0.05, 0.11, wy1 - wy0, 0.07, K.mat("pipe"))
    _downpipe(K, "wing", hx1 + 0.08, wy1 - COL / 2, EAVE - 0.07, "+X")
    _wing_line(K, hx1, wy0, wy1, wrobots)


# ---- Fittings in the shared catalogue materials ---------------------------------------
def _window(K, name, x, y, z, w, h):
    """A -Y face window: see-through teal glass over a dark room, stone lintel and sill."""
    K.window(name, "-Y", (x, y, z), w, h)
    glass = K.col.objects.get(name + "_glass")
    if glass is not None: glass.data.materials[0] = _glass("ap_window", *WINDOW_GLASS)
    sill = K.col.objects.get(name + "_sill")
    if sill is not None: sill.data.materials[0] = K.M["ap_stone"]
    K.box(name + "_room", x, y - 0.006, z + h * 0.15, w, 0.006, h * 0.70, K.M["ap_interior"])
    K.box(name + "_room_lo", x, y - 0.006, z - h * 0.35, w, 0.006, h * 0.30, K.M["ap_interior_lo"])
    K.box(name + "_lint", x, y - 0.018, z + h / 2 + 0.085, w + 0.18, 0.035, 0.10, K.M["ap_stone"])


def _downpipe(K, tag, x, y, top, face, compact=False):
    """Rainwater pipe from a gutter or scupper at `top` to a kerbed drain grate. `compact`
    puts a small gully straight under the shoe, for walls at the edge of the footprint."""
    fm = K._fine_mode
    K._fine_mode = True
    K.cyl("dp%s" % tag, x, y, top / 2, 0.03, top, K.mat("pipe"), segments=8)
    K.box("dp%s_hopper" % tag, x, y, top - 0.04, 0.10, 0.10, 0.08, K.mat("pipe"))
    out = 0.035 if face in ("+X", "-Y") else -0.035
    z, k = 0.45, 0
    while z < top - 0.25:
        if face in ("+X", "-X"):
            K.box("dp%s_b%d" % (tag, k), x - out / 2, y, z, 0.07, 0.10, 0.03, K.mat("gear"))
        else:
            K.box("dp%s_b%d" % (tag, k), x, y + (0.035 if face == "-Y" else -0.035), z, 0.10, 0.07, 0.03, K.mat("gear"))
        z += 0.70
        k += 1
    K.box("dp%s_shoe" % tag, x, y, 0.05, 0.09, 0.09, 0.08, K.mat("pipe"))
    if compact:
        K.box("grate%s_kerb" % tag, x, y, 0.012, 0.10, 0.10, 0.024, K.mat("yard_pad"))
        K.box("grate%s" % tag, x, y, 0.016, 0.07, 0.07, 0.024, K.mat("opening"))
        K._fine_mode = fm
        return
    gx, gy = (x + out, y) if face in ("+X", "-X") else (x, y - out)
    K.box("grate%s_kerb" % tag, gx, gy, 0.012, 0.22, 0.22, 0.024, K.mat("yard_pad"))
    K.box("grate%s" % tag, gx, gy, 0.016, 0.16, 0.16, 0.024, K.mat("opening"))
    for k in range(3):
        off = (k - 1) * 0.05
        if face in ("+X", "-X"):
            K.box("grate%s_bar%d" % (tag, k), gx, gy + off, 0.03, 0.16, 0.012, 0.006, K.mat("darkmetal"))
        else:
            K.box("grate%s_bar%d" % (tag, k), gx + off, gy, 0.03, 0.012, 0.16, 0.006, K.mat("darkmetal"))
    K._fine_mode = fm


def _ventilator(K, tag, x, y, z):
    """Rooftop turbine ventilator: throat, domed head, cap."""
    fm = K._fine_mode
    K._fine_mode = True
    K.cyl("vent_%s" % tag, x, y, z + 0.06, 0.055, 0.12, K.mat("pipe"), segments=12)
    K.sphere("vent_%s_head" % tag, x, y, z + 0.17, 0.095, K.mat("pipe"))
    K.cyl("vent_%s_cap" % tag, x, y, z + 0.27, 0.03, 0.03, K.mat("darkmetal"), segments=10)
    K._fine_mode = fm


def _lamp(K, tag, x, y, z):
    """Wall lamp on a -Y face."""
    K.box("lamp_%s_arm" % tag, x, y - 0.05, z, 0.03, 0.10, 0.03, K.mat("darkmetal"))
    K.box("lamp_%s" % tag, x, y - 0.10, z - 0.03, 0.12, 0.08, 0.05, K.mat("window_frame"))


def _lamp_x(K, tag, x, y, z):
    """Wall lamp on a +X face."""
    K.box("lamp_%s_arm" % tag, x + 0.05, y, z, 0.10, 0.03, 0.03, K.mat("darkmetal"))
    K.box("lamp_%s" % tag, x + 0.10, y, z - 0.03, 0.08, 0.12, 0.05, K.mat("window_frame"))


def _louvre_x(K, tag, x, y, z, w, h):
    """Ventilation louvre on a +X face: dark opening, slats, stone head and sill."""
    K.box("louv_%s" % tag, x + 0.008, y, z, 0.012, w, h, K.mat("opening"))
    for k in range(4):
        K.box("louv_%s_s%d" % (tag, k), x + 0.016, y, z - h / 2 + (k + 0.6) * h / 4, 0.012, w - 0.03, 0.022, K.mat("gear"))
    for nm, zz in (("t", z + h / 2 + 0.02), ("b", z - h / 2 - 0.02)):
        K.box("louv_%s_%s" % (tag, nm), x + 0.014, y, zz, 0.02, w + 0.06, 0.04, K.M["ap_stone"])


def _bollard(K, tag, x, y):
    fm = K._fine_mode
    K._fine_mode = True
    K.cyl("bol_%s" % tag, x, y, 0.16, 0.04, 0.32, K.mat("plant_yellow"), segments=10)
    K.cyl("bol_%s_cap" % tag, x, y, 0.33, 0.042, 0.03, K.mat("darkmetal"), segments=10)
    K._fine_mode = fm


# ---- The gable that faces the crane ---------------------------------------------------
def _gable_face(K, x1):
    """The right gable as an elevation: brick pilasters at the corners, a stone string course
    at the eave, stone coping along the arch, a round window in the tympanum, two windows over
    the line, the louvre, iron pattress plates for the tie rods, a stone ring and keystone
    round the belt opening, and the forklift door's lamp fed from the junction box."""
    fm = K._fine_mode
    face = x1
    # Corner pilasters, proud of the face, and the string course at the eave.
    for tag, y in (("f", HY0 + 0.08), ("b", HY1 - 0.08)):
        K.box("gp_%s" % tag, face + 0.025, y, EAVE / 2, 0.05, 0.16, EAVE, K.mat("ap_wall"))
        K.box("gp_%s_cap" % tag, face + 0.035, y, EAVE + 0.04, 0.07, 0.20, 0.08, K.M["ap_stone"])
    K.box("string", face + 0.03, HALL.pc, EAVE - 0.05, 0.06, HY1 - HY0 - 0.30, 0.07, K.M["ap_stone"])
    # Stone coping riding the arch.
    pts = []
    for i in range(25):
        th = HALL.th0 + (math.pi - 2 * HALL.th0) * i / 24
        pp, z = HALL.pt(th, 0.06)
        pts.append((face - GABLE_T / 2, pp, z))
    K.sweep("gable_coping", pts, 0.055, K.M["ap_stone"], seg=8)
    # Round window in the tympanum: dark room, teal glass, stone ring, cross mullions.
    oz = EAVE + 0.33
    K.dircyl("ocu_room", (face - 0.004, HALL.pc, oz), (face + 0.002, HALL.pc, oz), 0.20, K.M["ap_interior"], segments=24)
    K.dircyl("ocu_glass", (face + 0.004, HALL.pc, oz), (face + 0.010, HALL.pc, oz), 0.20,
             _glass("ap_window", *WINDOW_GLASS), segments=24)
    K.washer("ocu_ring", (face + 0.02, HALL.pc, oz), (1, 0, 0), 0.20, 0.27, 0.04, K.M["ap_stone"], seg=28)
    K._fine_mode = True
    K.box("ocu_mv", face + 0.014, HALL.pc, oz, 0.01, 0.026, 0.40, K.mat("window_frame"))
    K.box("ocu_mh", face + 0.014, HALL.pc, oz, 0.01, 0.40, 0.026, K.mat("window_frame"))
    K._fine_mode = fm
    # Two windows over the line, the louvre beside them.
    for k, y in enumerate((HY0 + 0.55, HALL.pc - 0.05)):
        _window_x(K, "gw%d" % k, face, y, 2.15, 0.40, 0.66)
    _louvre_x(K, "gable", face, HY1 - 0.50, 2.15, 0.30, 0.34)
    # Pattress plates where the tie rods come through, in a row under the string course.
    K._fine_mode = True
    for k, y in enumerate((HY0 + 0.32, -0.45, 0.45, HY1 - 0.32)):
        K.dircyl("pat%d" % k, (face, y, 2.72), (face + 0.025, y, 2.72), 0.055, K.mat("darkmetal"), segments=12)
        K.box("pat%d_x" % k, face + 0.03, y, 2.72, 0.012, 0.15, 0.025, K.mat("darkmetal"))
    K._fine_mode = fm
    # The belt opening: a stone ring and keystone round its arch.
    ac = FLOOR + BELT_H + 0.06
    ring = []
    for i in range(17):
        th = math.pi * i / 16
        ring.append((face + 0.03, BELT_Y + 0.43 * math.cos(th), ac + 0.43 * math.sin(th)))
    K.sweep("belt_arch_ring", ring, 0.05, K.M["ap_stone"], seg=8)
    K.box("belt_key", face + 0.04, BELT_Y, ac + 0.45, 0.06, 0.12, 0.14, K.M["ap_stone"])
    # Lamp over the forklift door, fed by a conduit from the junction box beside it.
    _lamp_x(K, "gate", face, DOOR_Y, FLOOR + 1.14)
    K.box("gable_jb", face + 0.04, DOOR_Y - 0.55, FLOOR + 0.62, 0.08, 0.16, 0.20, K.mat("gear"))
    K._fine_mode = True
    K.pipe_run("gable_conduit", [(face + 0.03, DOOR_Y - 0.55, FLOOR + 0.72), (face + 0.03, DOOR_Y - 0.55, FLOOR + 1.22),
                                 (face + 0.03, DOOR_Y - 0.08, FLOOR + 1.22)], 0.014, K.mat("pipe"), bend=0.05)
    K._fine_mode = fm


def _window_x(K, name, x, y, z, w, h):
    """A +X face window: teal glass over a dark room, stone lintel and sill."""
    K.window(name, "+X", (x, y, z), w, h)
    glass = K.col.objects.get(name + "_glass")
    if glass is not None: glass.data.materials[0] = _glass("ap_window", *WINDOW_GLASS)
    sill = K.col.objects.get(name + "_sill")
    if sill is not None: sill.data.materials[0] = K.M["ap_stone"]
    K.box(name + "_room", x + 0.006, y, z + h * 0.15, 0.006, w, h * 0.70, K.M["ap_interior"])
    K.box(name + "_room_lo", x + 0.006, y, z - h * 0.35, 0.006, w, h * 0.30, K.M["ap_interior_lo"])
    K.box(name + "_lint", x + 0.018, y, z + h / 2 + 0.085, 0.035, w + 0.18, 0.10, K.M["ap_stone"])


# ---- Gantry detail --------------------------------------------------------------------
def _gantry_detail(K, x1, cx, zt, ty):
    """Bracing, girder stiffeners, a railed walkway, an access ladder, wheeled bogies,
    hazard banding, rail end stops, cab glazing, the hoist house and beacons."""
    g, glo, dark = K.mat("gantry_green"), K.mat("gantry_green_lo"), K.mat("wall_steel")
    hazard, black = K.mat("plant_yellow"), K.mat("crate")
    fm = K._fine_mode
    for ly in (CRANE_YF, CRANE_YB):
        # K-bracing below the mid brace and knee braces under the portal beam.
        for sx in (-1, 1):
            K.dirbox("kb_%d_%d" % (ly > 0, sx > 0), (cx + sx * 0.34, ly, 0.40), (cx, ly, zt * 0.48 - 0.05), 0.07, 0.08, glo)
            K.dirbox("knee_%d_%d" % (ly > 0, sx > 0), (cx + sx * 0.34, ly, zt - 0.50), (cx + sx * 0.12, ly, zt - 0.13), 0.07, 0.08, glo)
            px = cx + sx * 0.34
            # Hazard banding round the foot of each leg.
            for k in range(4):
                K.box("hz_%d_%d_%d" % (ly > 0, sx > 0, k), px, ly, 0.25 + k * 0.11, 0.18, 0.24, 0.11,
                      hazard if k % 2 == 0 else black)
            # Bogie wheels on the rail, either side of the boot.
            for wx in (-0.08, 0.08):
                for wy in (-1, 1):
                    K.cyl("wh_%d_%d_%d_%d" % (ly > 0, sx > 0, wx > 0, wy > 0), px + wx, ly + wy * 0.19, 0.11, 0.065, 0.04,
                          black, axis='Y', segments=12)
        # End stops at both ends of each rail.
        for k, ex in enumerate((x1 + 0.62, x1 + 2.88)):
            K.box("stop_%d_%d" % (ly > 0, k), ex, ly, 0.10, 0.08, 0.20, 0.14, hazard)
    # Vertical stiffeners down the girder's visible side, and a railed walkway along it.
    gy0, gy1 = CRANE_YF - 0.15, CRANE_YB + 0.15
    K._fine_mode = True
    y, k = gy0 + 0.15, 0
    while y < gy1 - 0.10:
        K.box("stiff%d" % k, cx + 0.16, y, zt + 0.23, 0.02, 0.035, 0.27, glo)
        y += 0.32
        k += 1
    K._fine_mode = fm
    K.box("walkway", cx + 0.32, (gy0 + gy1) / 2, zt + 0.10, 0.22, gy1 - gy0, 0.03, K.mat("darkmetal"))
    K.box("walk_toe", cx + 0.43, (gy0 + gy1) / 2, zt + 0.14, 0.012, gy1 - gy0, 0.05, hazard)
    K._fine_mode = True
    y, k = gy0 + 0.05, 0
    while y <= gy1:
        K.box("walk_post%d" % k, cx + 0.43, y, zt + 0.25, 0.02, 0.02, 0.28, hazard)
        y += 0.45
        k += 1
    for nm, z in (("top", zt + 0.39), ("mid", zt + 0.26)):
        K.box("walk_rail_%s" % nm, cx + 0.43, (gy0 + gy1) / 2, z, 0.02, gy1 - gy0, 0.02, hazard)
    # Caged access ladder up the front-right leg to the walkway.
    lx, ly = cx + 0.34 + 0.12, CRANE_YF
    for s_ in (-1, 1):
        K.box("lad_rail%d" % (s_ > 0), lx, ly + s_ * 0.08, (0.25 + zt + 0.10) / 2, 0.02, 0.02, zt - 0.15, K.mat("darkmetal"))
    z, k = 0.35, 0
    while z < zt + 0.05:
        K.box("lad_rung%d" % k, lx, ly, z, 0.02, 0.16, 0.018, K.mat("darkmetal"))
        z += 0.12
        k += 1
    z, k = 1.20, 0
    while z <= zt + 0.10:
        K.box("cage%d_f" % k, lx + 0.18, ly, z, 0.018, 0.26, 0.018, K.mat("darkmetal"))
        for s_ in (-1, 1):
            K.box("cage%d_%d" % (k, s_ > 0), lx + 0.09, ly + s_ * 0.13, z, 0.18, 0.018, 0.018, K.mat("darkmetal"))
        z += 0.30
        k += 1
    K.box("cage_strap", lx + 0.18, ly, (1.20 + zt + 0.10) / 2, 0.018, 0.018, zt - 1.10, K.mat("darkmetal"))
    K._fine_mode = fm
    # Cab glazing on its two visible faces, and a roof cap.
    cab_x, cab_y, cab_z = cx - 0.42, CRANE_YF + 0.55, zt - 0.45
    pane = _glass("ap_window", *WINDOW_GLASS)
    K.box("cab_room_y", cab_x, cab_y - 0.168, cab_z + 0.05, 0.24, 0.006, 0.14, K.M["ap_interior"])
    K.box("cab_glass_y", cab_x, cab_y - 0.175, cab_z + 0.05, 0.24, 0.006, 0.14, pane)
    K.box("cab_room_x", cab_x + 0.148, cab_y, cab_z + 0.05, 0.006, 0.28, 0.14, K.M["ap_interior"])
    K.box("cab_glass_x", cab_x + 0.155, cab_y, cab_z + 0.05, 0.006, 0.28, 0.14, pane)
    K.box("cab_roof", cab_x, cab_y, cab_z + 0.165, 0.34, 0.38, 0.03, g)
    # Hoist house on the trolley's open side, hoist drums, and beacons at the girder ends.
    K.box("hoist", cx + 0.33, ty, zt - 0.06, 0.14, 0.30, 0.16, K.mat("gear"))
    for s_ in (-1, 1):
        K.cyl("drum%d" % (s_ > 0), cx, ty + s_ * 0.27, zt - 0.08, 0.06, 0.40, dark, axis='X', segments=14)
    for k, by in enumerate((gy0 + 0.06, gy1 - 0.06)):
        K.cyl("beacon%d_base" % k, cx, by, zt + 0.40, 0.035, 0.03, K.mat("darkmetal"), segments=10)
        K.cyl("beacon%d" % k, cx, by, zt + 0.445, 0.028, 0.06, hazard, segments=10)
    # Load-rating plate on the girder.
    K.box("rating", cx + 0.17, (gy0 + gy1) / 2, zt + 0.25, 0.01, 0.30, 0.10, hazard)


# ---- The faces the home view does not show (the board's camera orbits) -----------------
# Owner rules for these sides: no new windows; keep it quiet. The -X side is 0.10 from the
# family footprint's edge (the front apron's overhang), so nothing there stands out further:
# a wider footprint would shrink the whole building on the board.
def _louvre_y(K, tag, x, y, z, w, h):
    """Ventilation louvre on a +Y face."""
    K.box("louv_%s" % tag, x, y + 0.008, z, w, 0.012, h, K.mat("opening"))
    for k in range(4):
        K.box("louv_%s_s%d" % (tag, k), x, y + 0.016, z - h / 2 + (k + 0.6) * h / 4, w - 0.03, 0.012, 0.022, K.mat("gear"))
    for nm, zz in (("t", z + h / 2 + 0.02), ("b", z - h / 2 - 0.02)):
        K.box("louv_%s_%s" % (tag, nm), x, y + 0.014, zz, w + 0.06, 0.02, 0.04, K.M["ap_stone"])


def _louvre_nx(K, tag, x, y, z, w, h):
    """Ventilation louvre on a -X face."""
    K.box("louv_%s" % tag, x - 0.008, y, z, 0.012, w, h, K.mat("opening"))
    for k in range(4):
        K.box("louv_%s_s%d" % (tag, k), x - 0.016, y, z - h / 2 + (k + 0.6) * h / 4, 0.012, w - 0.03, 0.022, K.mat("gear"))
    for nm, zz in (("t", z + h / 2 + 0.02), ("b", z - h / 2 - 0.02)):
        K.box("louv_%s_%s" % (tag, nm), x - 0.014, y, zz, 0.02, w + 0.06, 0.04, K.M["ap_stone"])


def _gable_dress(K, tag, arc, axis, face_at, sign):
    """A plain gable dressed like the dock gable, without its windows: corner pilasters with
    stone caps, a string course at the eave, stone coping along the arch, a centred vent, a
    row of tie-rod pattress plates, and the dark plinth. `axis` 'X': the gable lies in a plane
    x = face_at facing `sign` X; 'Y': in y = face_at facing `sign` Y."""
    def at(across, out, z):
        return (face_at + sign * out, across, z) if axis == 'X' else (across, face_at + sign * out, z)
    def slab(name, across, out, z, w_across, t_out, h, mat):
        x, y, zz = at(across, out, z)
        if axis == 'X':
            K.box(name, x, y, zz, t_out, w_across, h, mat)
        else:
            K.box(name, x, y, zz, w_across, t_out, h, mat)
    pc, hs = arc.pc, arc.hs
    for k, a in enumerate((pc - hs + 0.08, pc + hs - 0.08)):
        slab("%s_pil%d" % (tag, k), a, 0.025, EAVE / 2, 0.16, 0.05, EAVE, K.mat("ap_wall"))
        slab("%s_pil%d_cap" % (tag, k), a, 0.035, EAVE + 0.04, 0.20, 0.07, 0.08, K.M["ap_stone"])
    slab("%s_string" % tag, pc, 0.03, EAVE - 0.05, 2 * hs - 0.30, 0.06, 0.07, K.M["ap_stone"])
    slab("%s_plinth" % tag, pc, 0.015, 0.11, 2 * hs, 0.03, 0.22, K.M["ap_plinth"])
    pts = []
    for i in range(25):
        th = arc.th0 + (math.pi - 2 * arc.th0) * i / 24
        a, z = arc.pt(th, 0.06)
        pts.append(at(a, -GABLE_T / 2, z))
    K.sweep("%s_coping" % tag, pts, 0.055, K.M["ap_stone"], seg=8)
    vx, vy, vz = at(pc, 0.0, EAVE + 0.28)
    if axis == 'Y':
        _louvre_y(K, tag, vx, vy, vz, 0.34, 0.24) if sign > 0 else None
    else:
        _louvre_nx(K, tag, vx, vy, vz, 0.24, 0.34) if sign < 0 else None
    fm = K._fine_mode
    K._fine_mode = True
    for k, a in enumerate((pc - 0.60, pc, pc + 0.60)):
        p0, p1 = at(a, 0.0, 2.55), at(a, 0.025, 2.55)
        K.dircyl("%s_pat%d" % (tag, k), p0, p1, 0.055, K.mat("darkmetal"), segments=12)
    K._fine_mode = fm


def _back_side(K, p, x1):
    """Hall back wall, the hall's left gable (L1), the head block's hidden faces, the wing's
    far gable and left flank."""
    fm = K._fine_mode
    # Hall back wall: gutter at the vault's back eave, pilasters at the bay lines, plinth,
    # pattress plates, two vents, downpipes onto grates.
    K.box("back_gutter", (HX0 + x1) / 2, HY1 + 0.095, EAVE - 0.05, x1 - HX0 + 0.06, 0.11, 0.07, K.mat("pipe"))
    for b in range(0 if not p["head"] else 1, BAYS + 1):
        bx = min(max(HX0 + b * BAY, HX0 + 0.07), x1 - 0.07)
        K.box("bpil%d" % b, bx, HY1 + 0.03, EAVE / 2, 0.14, 0.06, EAVE, K.mat("ap_wall"))
    K.box("back_plinth", (HX0 + x1) / 2, HY1 + 0.015, 0.11, x1 - HX0, 0.03, 0.22, K.M["ap_plinth"])
    K._fine_mode = True
    for b in range(BAYS):
        bx = HX0 + (b + 0.5) * BAY
        K.dircyl("bpat%d" % b, (bx, HY1, 2.55), (bx, HY1 + 0.025, 2.55), 0.055, K.mat("darkmetal"), segments=12)
    K._fine_mode = fm
    for b in (1, 3):
        _louvre_y(K, "back%d" % b, HX0 + (b + 0.5) * BAY, HY1, 1.05, 0.34, 0.30)
    for k, dx in enumerate((HX0 + 2 * BAY + 0.16, x1 - 0.18)):
        _downpipe(K, "back%d" % k, dx, HY1 + 0.08, EAVE - 0.07, "+Y")
    # The hall's left gable shows only at L1; from L2 the head block stands against it.
    if not p["head"]:
        _gable_dress(K, "lgable", HALL, 'X', HX0, -1)
    # Head block: stone bands at the floor lines and a plinth on its hidden faces, a vent,
    # and a downpipe from a scupper near the back corner.
    if p["head"]:
        hx0, hx1 = HX0 - HEAD_W, HX0
        hcx = (hx0 + hx1) / 2
        for k, z in enumerate((1.32, 2.47)):
            K.box("hband_w%d" % k, hx0 - 0.015, HALL.pc, z, 0.03, HY1 - HY0, 0.07, K.M["ap_stone"])
            if not p["wing"]:
                K.box("hband_b%d" % k, hcx, HY1 + 0.015, z, HEAD_W, 0.03, 0.07, K.M["ap_stone"])
        K.box("hplinth_w", hx0 - 0.015, HALL.pc, 0.11, 0.03, HY1 - HY0, 0.22, K.M["ap_plinth"])
        if not p["wing"]:
            K.box("hplinth_b", hcx, HY1 + 0.015, 0.11, HEAD_W, 0.03, 0.22, K.M["ap_plinth"])
        _louvre_nx(K, "head_w", hx0, HALL.pc - 0.45, 0.70, 0.30, 0.30)
        K.box("head_scupper_w", hx0 - 0.04, HY1 - 0.14, HEAD_H + 0.05, 0.08, 0.10, 0.06, K.mat("pipe"))
        _downpipe(K, "head_w", hx0 - 0.045, HY1 - 0.14, HEAD_H + 0.02, "-X", compact=True)
    # The wing: its far gable dressed like the dock gable (no window), and its left flank with
    # pilasters, a plinth, two vents and two downpipes from scuppers through the parapet lip.
    if p["wing"]:
        hx0, hx1 = HX0 - HEAD_W, HX0
        wy0, wy1 = HY1, HY1 + p["wing"] * WING_BAY
        _gable_dress(K, "wgable", WING, 'Y', wy1, 1)
        for b in range(1, p["wing"] + 1):
            by = min(wy0 + b * WING_BAY, wy1 - 0.08)
            K.box("wpil%d" % b, hx0 - 0.03, by, EAVE / 2, 0.06, 0.14, EAVE, K.mat("ap_wall"))
        K.box("wplinth", hx0 - 0.015, (wy0 + wy1) / 2, 0.11, 0.03, wy1 - wy0, 0.22, K.M["ap_plinth"])
        for b in (0, 2):
            _louvre_nx(K, "wing%d" % b, hx0, wy0 + (b + 0.5) * WING_BAY, 1.05, 0.30, 0.30)
        for k, b in enumerate((1, 3)):
            dy = wy0 + b * WING_BAY + 0.16
            K.box("wscupper%d" % k, hx0 - 0.04, dy, EAVE + 0.03, 0.08, 0.10, 0.06, K.mat("pipe"))
            _downpipe(K, "wing%d" % k, hx0 - 0.045, dy, EAVE, "-X", compact=True)


def _frame(p):
    """Camera target from the PROJECTED extents of the extreme corners (SKILL.md rule 20)."""
    bays = BAYS
    x1 = HX0 + bays * BAY
    xl = HX0 - (HEAD_W if p["head"] else 0.0)
    xr = x1 + max(DOCK_X1 + 0.03 + CONT[0] + 0.15, CRANE_X + 0.34 + 0.22)
    yf = HY0 - APRON_D - 0.05
    yr = CRANE_YB + 0.20
    pts = [(xl - APRON_OVER, yf, -0.06), (xr + APRON_OVER, yf, -0.06),
           (xr + APRON_OVER, yr, -0.06), (HX0, HALL.pc, HALL.crown + 0.04),
           (x1, HALL.pc, HALL.crown + 0.04), (x1, HY1, EAVE)]
    if p["head"]:
        pts += [(xl, HY0, HEAD_H + 0.22), (xl, HY1, HEAD_H + 0.22), (HX0, HY1, HEAD_H + 0.22)]
    if p["wing"]:
        wy1 = HY1 + p["wing"] * WING_BAY
        pts += [(WING.pc, wy1, WING.crown + 0.04), (xl, wy1, 0.0), (HX0, wy1, EAVE)]
    if p["crane"]:
        cx = x1 + CRANE_X
        pts += [(cx - 0.4, CRANE_YF, CRANE_H + 0.4), (cx + 0.4, CRANE_YB, CRANE_H + 0.4)]
    cs = [x + y for x, y, z in pts]
    hs = [z - (x - y) / 2.0 for x, y, z in pts]
    # +0.12 on the top: ink width plus the gable lift measured 8 px above the bare geometry.
    c, h = (min(cs) + max(cs)) / 2.0, (min(hs) + max(hs) + 0.12) / 2.0
    return (c / 2.0, c / 2.0, h), (x1, xl, xr, yr)


def build_assembly_plant(level: int = 2) -> dict:
    p = AP_LEVELS[level]
    bays = BAYS
    target, (x1, xl, xr, yr) = _frame(p)
    setup_rig(target=target)
    K = Kit(open_collection("BLDG_assembly"))
    pane = _glass("ap_glass", PALETTE["glass_pale"], GLASS_ALPHA)
    seam = _glass("ap_glass_seam", PALETTE["glass_seam"], min(1.0, GLASS_ALPHA + 0.30))

    # ---- ground: two ABUTTING apron slabs (coplanar overlap would z-fight), floor inside ----
    K.box("apron_f", (xl - APRON_OVER + x1) / 2, HY0 - APRON_D / 2, -0.03,
          x1 - xl + APRON_OVER, APRON_D + 0.10, 0.06, K.mat("yard"))
    K.box("apron_r", (x1 + xr + APRON_OVER) / 2, (HY0 - APRON_D + yr) / 2, -0.03,
          xr + APRON_OVER - x1, yr - HY0 + APRON_D, 0.06, K.mat("yard"))
    # The floor slab: its exposed -Y edge between the columns IS the kerb.
    K.box("floor", (HX0 + x1) / 2, HALL.pc, FLOOR / 2, x1 - HX0 - 0.04, HY1 - HY0, FLOOR,
          K.mat("yard_pad"))

    # ---- the hall: back wall, gables, portal front, vault ----------------------------------
    K.box("back_wall", (HX0 + x1) / 2, HY1 - 0.06, EAVE / 2, x1 - HX0, 0.12, EAVE,
          K.mat("ap_wall"))
    # Parapet lip that stops rays escaping over the wall top (note 3). The inner faces stay
    # BRICK: a pale lining read, through the steep part of the vault, as a grey wall where a
    # brick one was expected, and it stopped short of the gable, which drew a seam in the glass.
    K.box("back_lip", (HX0 + x1) / 2, HY1 - 0.06, EAVE + 0.04, x1 - HX0, 0.12, 0.08,
          K.mat("ap_wall"))
    _gable(K, "gable_l", HALL, 'X', HX0 + GABLE_T / 2, "ap_wall")
    _gable(K, "gable_r", HALL, 'X', x1 - GABLE_T / 2, "ap_wall")
    for b in range(bays + 1):
        cx = min(max(HX0 + b * BAY, HX0 + COL / 2), x1 - COL / 2)
        # Proud of the floor's front face by 0.015: coplanar with it they would z-fight.
        K.box("col%d" % b, cx, HY0 + COL / 2 - 0.015, EAVE / 2, COL, COL, EAVE, K.mat("gear"))
    K.box("header", (HX0 + x1) / 2, HY0 + 0.11 - 0.015, EAVE - HEADER / 2, x1 - HX0, 0.22,
          HEADER, K.mat("gear"))
    _vault(K, "vault", HALL, 'X', HX0 + GABLE_T, x1 - GABLE_T, bays, pane, seam)
    # Eaves gutter hung in front of and below the vault's front eave, over the portal header,
    # falling to downpipes on two of the portal columns.
    K.box("gutter", (HX0 + x1) / 2, HY0 - 0.095, EAVE - 0.05, x1 - HX0 + 0.06, 0.11, 0.07, K.mat("pipe"))
    for b in (2, bays):
        cx = min(max(HX0 + b * BAY, HX0 + COL / 2), x1 - COL / 2)
        _downpipe(K, "c%d" % b, cx, HY0 - 0.08, EAVE - 0.07, "-Y")
    _gable_face(K, x1)
    K.arch_opening("exit", (x1 - GABLE_T / 2, BELT_Y, FLOOR + BELT_H + 0.06), (1.0, 0.0, 0.0),
                   0.36, rect_h=0.56, depth=GABLE_T + 0.04)

    # ---- the line ---------------------------------------------------------------------------
    belt_x1 = x1 + DOCK_OUT
    _belt(K, HX0 + 0.35, belt_x1)
    _boxes(K, HX0 + 0.35, belt_x1)
    for i, (bay, flank) in enumerate(p["robots"]):
        sgn = -1.0 if flank == "far" else 1.0
        _robot(K, str(i), HX0 + (bay + 0.5) * BAY, BELT_Y - sgn * ROBOT_OFF, (0.0, sgn))

    # ---- loading bay at the right end, every level ----------------------------------------
    _loading_bay(K, x1, p["crane"])
    # Switchgear on the apron at the hall's front-right corner: the one electrical item.
    K.box("swg", x1 + 0.40, HY0 - 0.34, 0.36, 0.44, 0.30, 0.72, K.mat("gear"))
    K.box("swg_cap", x1 + 0.40, HY0 - 0.34, 0.735, 0.46, 0.32, 0.03, K.mat("wall_steel"))
    # Clear of the front crane rail, which starts at x1 + 0.60.
    for k, bx in enumerate((x1 + 0.15, x1 + 0.50)):
        _bollard(K, "swg%d" % k, bx, HY0 - 0.60)

    # ---- head block from L2, the wing from L3 ---------------------------------------------
    if p["head"]:
        _head(K)
    if p["wing"]:
        _wing(K, p["wing"], p["wrobots"], pane, seam)

    _back_side(K, p, x1)

    print("\n".join(K.validate(ground=-0.06)))
    return {"building": "assembly_plant", "level": level, "bays": bays,
            "robots": len(p["robots"]), "objects": len(K.col.objects)}
