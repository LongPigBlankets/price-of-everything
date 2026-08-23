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
PALETTE["glass_pale"] = (0.200, 0.360, 0.500)
PALETTE["glass_seam"] = (0.120, 0.240, 0.360)
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


def _robot(K, tag, x, y0, reach):
    """Six-axis arm on a pedestal at (x, y0), standing on the floor and reaching over the belt
    in the horizontal direction `reach` = (dx, dy), a unit vector."""
    dx, dy = reach
    z = FLOOR
    fm = K._fine_mode
    K._fine_mode = True
    K.cyl("rb%s_ped" % tag, x, y0, z + 0.14, 0.13, 0.28, K.mat("gear"), segments=14)
    K.box("rb%s_tur" % tag, x, y0, z + 0.36, 0.24, 0.22, 0.16, K.mat("robot"))
    sh = (x, y0, z + 0.44)
    el = (x + dx * 0.36, y0 + dy * 0.36, z + 0.99)
    wr = (x + dx * 0.78, y0 + dy * 0.78, z + 0.69)
    K.dirbox("rb%s_ua" % tag, sh, el, 0.12, 0.14, K.mat("robot"))
    K.cyl("rb%s_elb" % tag, el[0], el[1], el[2], 0.085, 0.15, K.mat("gear"),
          axis='Y' if dx else 'X', segments=12)
    K.dirbox("rb%s_fa" % tag, el, wr, 0.10, 0.11, K.mat("robot"))
    K.box("rb%s_wr" % tag, wr[0], wr[1], wr[2] - 0.06, 0.10, 0.10, 0.08, K.mat("gear"))
    for d in (-0.035, 0.035):      # fingers, spread ACROSS the reach
        K.box("rb%s_f%d" % (tag, d > 0), wr[0] + d * abs(dy), wr[1] + d * abs(dx),
              wr[2] - 0.15, 0.022 + 0.038 * abs(dx), 0.022 + 0.038 * abs(dy), 0.10,
              K.mat("gear"))
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
    K._fine_mode = fm
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
    K.box("head", hcx, HALL.pc, HEAD_H / 2, HEAD_W, HY1 - HY0, HEAD_H, K.mat("wall_brick"))
    K.box("head_roof", hcx, HALL.pc, HEAD_H + 0.03, HEAD_W - 0.02, HY1 - HY0 - 0.02, 0.06,
          K.mat("roof_deck"))
    # Parapet: a raised brick rim round the roof edge, with a coping course on top.
    pw, ph = 0.11, 0.16
    for tag, (bx, by, sx, sy) in {
        "f": (hcx, HY0 + pw / 2, HEAD_W, pw), "b": (hcx, HY1 - pw / 2, HEAD_W, pw),
        "l": (hx0 + pw / 2, HALL.pc, pw, HY1 - HY0), "r": (hx1 - pw / 2, HALL.pc, pw, HY1 - HY0),
    }.items():
        K.box("parapet_%s" % tag, bx, by, HEAD_H + ph / 2, sx, sy, ph, K.mat("wall_brick"))
        K.box("coping_%s" % tag, bx, by, HEAD_H + ph + 0.02, sx + 0.03, sy + 0.03, 0.04,
              K.mat("slab_cream"))
    # Skylight: a low upstand frame with a mullioned glass lid, centred on the roof.
    sx_, sy_ = 1.00, 0.74
    K.box("sky_frame", hcx - 0.15, HALL.pc, HEAD_H + 0.11, sx_, sy_, 0.10, K.mat("gear"))
    K.box("sky_glass", hcx - 0.15, HALL.pc, HEAD_H + 0.175, sx_ - 0.10, sy_ - 0.10, 0.03,
          K.mat("window_glass"))
    K.box("sky_mul_x", hcx - 0.15, HALL.pc, HEAD_H + 0.20, sx_ - 0.08, 0.03, 0.02,
          K.mat("window_frame"))
    K.box("sky_mul_y", hcx - 0.15, HALL.pc, HEAD_H + 0.20, 0.03, sy_ - 0.08, 0.02,
          K.mat("window_frame"))
    K.box("head_rtu", hcx + 0.80, HALL.pc + 0.85, HEAD_H + 0.21, 0.44, 0.36, 0.30,
          K.mat("gear"))
    # Three columns on a 0.75 grid, THREE storeys on a 1.15 pitch. Ground floor: window,
    # DOOR, window — the door takes the middle column and the window HEADS align with the
    # door head at 1.00 (windows are 0.52 tall, so the row centre is 0.74). First and second
    # floors: three windows each on the same columns; the top row head is 0.72 below the deck.
    xs = [hx0 + 0.45 + i * 0.75 for i in range(3)]
    for r, z in enumerate((0.74, 1.89, 3.04)):
        for i, x in enumerate(xs):
            if r == 0 and i == 1:
                K.door("head_door", "-Y", (x, HY0, 0.50), 0.36, 1.00)
            else:
                K.window("head_w%d%d" % (r, i), "-Y", (x, HY0, z), 0.40, 0.52)



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
          K.mat("wall_brick"))
    K.box("wing_lip_l", hx0 + 0.06, (wy0 + wy1) / 2, EAVE + 0.04, 0.12, wy1 - wy0, 0.08,
          K.mat("wall_brick"))
    _gable(K, "wing_gable", WING, 'Y', wy1 - GABLE_T / 2, "wall_brick")
    _vault(K, "wing_vault", WING, 'Y', wy0, wy1 - GABLE_T, wing_bays, pane, seam)
    _wing_line(K, hx1, wy0, wy1, wrobots)


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
          K.mat("wall_brick"))
    # Parapet lip that stops rays escaping over the wall top (note 3). The inner faces stay
    # BRICK: a pale lining read, through the steep part of the vault, as a grey wall where a
    # brick one was expected, and it stopped short of the gable, which drew a seam in the glass.
    K.box("back_lip", (HX0 + x1) / 2, HY1 - 0.06, EAVE + 0.04, x1 - HX0, 0.12, 0.08,
          K.mat("wall_brick"))
    _gable(K, "gable_l", HALL, 'X', HX0 + GABLE_T / 2, "wall_brick")
    _gable(K, "gable_r", HALL, 'X', x1 - GABLE_T / 2, "wall_brick")
    for b in range(bays + 1):
        cx = min(max(HX0 + b * BAY, HX0 + COL / 2), x1 - COL / 2)
        # Proud of the floor's front face by 0.015: coplanar with it they would z-fight.
        K.box("col%d" % b, cx, HY0 + COL / 2 - 0.015, EAVE / 2, COL, COL, EAVE, K.mat("gear"))
    K.box("header", (HX0 + x1) / 2, HY0 + 0.11 - 0.015, EAVE - HEADER / 2, x1 - HX0, 0.22,
          HEADER, K.mat("gear"))
    _vault(K, "vault", HALL, 'X', HX0 + GABLE_T, x1 - GABLE_T, bays, pane, seam)
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

    # ---- head block from L2, the wing from L3 ---------------------------------------------
    if p["head"]:
        _head(K)
    if p["wing"]:
        _wing(K, p["wing"], p["wrobots"], pane, seam)

    print("\n".join(K.validate(ground=-0.06)))
    return {"building": "assembly_plant", "level": level, "bays": bays,
            "robots": len(p["robots"]), "objects": len(K.col.objects)}
