# Parametric builder for the Wind Farm (b_025 onshore, b_026 offshore).
# Run AFTER sprite_kit.py:
#   exec(open(".../sprite_kit.py").read())
#   exec(open(".../wind_farm_builder.py").read()); build_wind_farm(2)
#   build_offshore_wind_farm(2)          # turbines in water, no yard at all
#
# SITE class, 25 tiles, like the mine: an earth block with strata on the cut edge, not a
# building on z=0. Power category, so mustard is the chroma.
#
# ---------------------------------------------------------------------------------------
# THE THREE THINGS THAT MAKE A TURBINE READ, none of them obvious
#
# 1. A BLADE IS A LOFTED TAPERED AEROFOIL, NEVER A CYLINDER. The props kit learned this on
#    grass: an outlined constant-radius cylinder reads as a navy scratch, because at this
#    scale the outline IS the blade. A blade needs real chord that narrows to the tip, built
#    as ONE lofted mesh — the same lesson as `flame` being one lofted droplet rather than
#    stacked cones.
#
# 2. CHORD IS SET IN SCREEN PIXELS, NOT BY REALISM. A real blade is about 8% of its length in
#    chord; at 93 px per world unit that is sub-pixel here. These are ~22% at the root, which
#    is deliberately fat and is what makes the rotor a shape instead of three scratches.
#
# 3. THE ROTOR PLANE FACES THE CAMERA, not a world axis. Its normal is the horizontal view
#    vector (0.707, -0.707, 0), so the disc lies in the plane spanned by u = (0.707, 0.707, 0)
#    — screen-horizontal — and world Z. The payoff is exact: (x - y) is CONSTANT everywhere on
#    that disc, and screen height is z - (x - y)/2, so the rotor projects as a true circle. In
#    a world-axis plane it presents edge-on and disappears.
#
# Turbine placement follows the same rule as the furnace's twin stacks: two rows, and no two
# machines sharing a screen column. Where columns do come close (0.2 and 0.9) the two sit in
# different rows, so they are ~2.7 apart in screen height and cannot merge.

import math

# The port's own water, so the two sea-going sprites match rather than each inventing a blue.
PALETTE["dock_water"] = (0.055, 0.135, 0.190)
PALETTE["dock_water_lo"] = (0.038, 0.100, 0.150)
ROLES["water"] = "dock_water"
ROLES["water_lo"] = "dock_water_lo"
# Grass. This is the PORT's land green, not a new one: the two are the only sprites with an
# unbuilt natural surface, and a wind farm inventing its own green would read as a different
# world. `turf_lo` is the mown/rougher second tone that keeps the plate from being one flat
# field, and both sit above the 0.05-0.30 earth band on purpose -- the soil strata on the cut
# faces stay inside it, which is what makes the top read as turf ON soil.
PALETTE["turf"] = (0.128, 0.235, 0.080)
PALETTE["turf_lo"] = (0.086, 0.168, 0.052)
ROLES["turf"] = "turf"
ROLES["turf_lo"] = "turf_lo"
# Crushed-stone tracks and hardstandings. `ground4`, the pale gravel that worked against an
# EARTH top, measures luma 66 against turf at 103 — on green it stopped reading as stone and
# turned the tracks into dark ditches. This is set to land near luma 130: clear of the turf
# below it and of the towers (158) above it, so the tracks are the light element on the plate
# without competing with the machines.
PALETTE["gravel"] = (0.192, 0.186, 0.166)
ROLES["gravel"] = "gravel"
# Wave wash round a monopile. With the yard gone, open water is the largest single surface in
# the offshore sprite and at L1 it is two machines on a flat plate; a pale collar where each
# pile breaks the surface is the only thing that can break it up WITHOUT being a structure.
PALETTE["wash"] = (0.118, 0.218, 0.268)
ROLES["wash"] = "wash"

WF_LEVELS = {
    1: dict(turbines=2, control=False, gantry=False, batteries=0),
    2: dict(turbines=4, control=True,  gantry=False, batteries=0),
    3: dict(turbines=6, control=True,  gantry=True,  batteries=2),
}

# x, y, hub height. ORDER IS THE BUILD ORDER — L1 takes the first two and they never move.
# SCREEN COLUMN (x+y) is what governs overlap, not plan distance. The columns are
# -1.60 / 2.70 / -3.40 / 4.50 / 0.55 / -0.70, so the tightest pair is 0.90 apart (59 px).
# The last two are L3-only, so moving them costs nothing at L1/L2: the tall machine was at
# column 0.90, only 0.70 from its neighbour, and went left to -0.70 with turbine 4 stepping
# right to open the gap. Its 3D clearance is the binding check, not the column: the rotor
# plane spans u = (0.342, 0.940, 0), so a rotor reaches +/- 0.94 R along Y - 1.52 for the tall
# machine and 1.07 for turbine 2 below it, summing to 2.59 against their 2.80 of separation.
TURBINES = (
    (-0.40, -1.20, 2.95),
    (1.10, 1.60, 3.20),
    (-2.20, -1.20, 2.70),
    (2.90, 1.60, 3.05),
    (1.75, -1.20, 2.85),
    (-2.30, 1.60, 3.85),      # L3: the visibly taller next-generation machine
)
ROTOR_FRAC = 0.42             # rotor radius as a fraction of hub height
# BLADE PLANFORM. A turbine blade is NOT a tapered plank, which is what a monotonic
# root-to-tip taper gives you. Its chord is narrow at the root, peaks at about 22% of span and
# only then tapers - that shoulder is the thing that makes the silhouette recognisable. The
# first version peaked at r/R = 0, exactly where a real blade is at its narrowest. Measured
# against a real large-machine distribution (fraction of max chord):
#
#   r/R      0.05   0.22   0.35   0.50   0.75   1.00
#   real     0.55   1.00   0.82   0.62   0.42   0.20
#   was      0.92   0.77   0.67   0.57   0.41   0.27   <- no shoulder
#   now      0.65   1.00   0.81   0.65   0.41   0.20
BLADE_MAX_C = 0.215           # chord at the shoulder
BLADE_ROOT_F, BLADE_TIP_F = 0.55, 0.20      # chord there, as a fraction of BLADE_MAX_C
BLADE_SHOULDER = 0.22         # r/R of maximum chord
BLADE_ROOT_T, BLADE_TIP_T = 0.062, 0.014    # thickness
# The leading edge is held STRAIGHT and the taper is thrown entirely onto the trailing edge,
# which is how a real blade is built and reads. Sweeping the section centre instead (the first
# version) curves both edges and the blade goes back to looking like a bent plank.
BLADE_LE = 0.30               # fraction of max chord that sits ahead of the blade axis
BLADE_SWEEP = 0.085           # tip-only sweep-back, applied to the whole section
BLADE_TWIST = 14.0            # degrees at the root, washing out to 0 at the tip
TOWER_R0, TOWER_R1 = 0.185, 0.098

# THE ROTOR IS YAWED OFF THE CAMERA, and this is the whole reason the nacelle works.
#
# At this camera a horizontal vector d projects to screen column (dx+dy) and screen height
# -(dx-dy)/2. A rotor facing the camera dead-on has normal (0.707,-0.707,0), whose column is
# ZERO -- so the nacelle, which by definition runs along that normal, projects to a purely
# VERTICAL bar. The first render showed exactly that: the nacelle read as the tower carrying
# on past the blades. It is not a placement bug, it is the projection, and no amount of moving
# the box fixes it.
#
# The two demands are in direct conflict. A round rotor needs its in-plane horizontal to be
# (1,1)/sqrt2; a horizontal-reading nacelle needs the normal to be near that same direction --
# but the normal is perpendicular to it. So yaw is a dial between them, measured:
#
#   yaw    nacelle screen angle    rotor aspect
#     0        90 deg (vertical)       1.00      <- what we had
#    15        69 deg                  0.98
#    25        57 deg                  0.95
#    35        45 deg                  0.91
#    45        35 deg (iso grid)       0.87
#
# 25 deg buys the nacelle a real horizontal component for 5% of rotor roundness, which at
# sprite scale is under two pixels on a 250 px disc. Past 35 deg the disc visibly squashes.
ROTOR_YAW = 25.0
_TH = math.radians(-45.0 + ROTOR_YAW)
ROTOR_N = (math.cos(_TH), math.sin(_TH), 0.0)      # rotor normal / nacelle axis
ROTOR_U = (-math.sin(_TH), math.cos(_TH), 0.0)     # in-plane horizontal
# Nacelle. It sits ON the tower top rather than being centred on the hub, and the hub is
# pushed UPWIND of the tower by NAC_OVERHANG so the tower meets the nacelle body about
# two-fifths from its rear -- which is where a real yaw bearing is, and which stops the
# nacelle reading as a box stuck on the end of a stick.
NAC_L, NAC_W, NAC_H = 0.70, 0.285, 0.255
NAC_OVERHANG = 0.34
# Hub drum and nose. The drum has to be WIDER than the blade root radius or the three roots
# stop short of it and the rotor reads as three separate objects floating near a box — which
# is what the first slim-blade render did, because the root started at 0.16 * R and R now
# varies from 1.07 to 1.75 across the set. BLADE_R0 is therefore absolute, not a fraction.
# HUB MUST NOT OUTGROW THE NACELLE. At 0.185 the drum was wider than the nacelle's 0.13
# semi-axis and simply ate it — the lofted body has an ELLIPTICAL section, so unlike the old
# box it has no corners reaching out past the drum to stay visible. On a real machine the
# spinner is about nacelle width, so that is what these are set to.
BLADE_R0 = 0.095
HUB_R, NOSE_R = 0.132, 0.078

SITE = (-3.35, 3.95, -2.50, 2.95)     # x0, x1, y0, y1
# Service tracks. They run on WORLD AXES, never on the x+y diagonal — that diagonal renders
# dead horizontal at this camera and was the single biggest reason the superseded refinery
# read flat. Two runs are enough to break the plate up and to say the turbines are reachable.
TRACK_Y = -0.30                       # the spine, along X
TRACK_X = 0.35                        # the spur, along Y
TRACK_W = 0.34
SITE_H = 0.34
CONTROL = (-3.05, -1.70, -2.35, -1.45)
TR_XY = (-1.05, -2.20)
# Takeoff gantry, and it is placed by its LEGS, not its centre. substation_gantry puts a
# lattice_mast on each endpoint, so a 1.60 span centred at 3.35 planted the right leg at
# x = 4.15 - past the site edge at x1 = 3.95, with its own half-width on top of that, and the
# leg hung off the composition. The span is 1.00 now and both legs clear the edge by 0.25.
GANTRY_XY = (3.20, -1.55)
GANTRY_HALF = 0.50
BATT_XY = (2.55, -2.25)
MONOPILE_BAND = (0.42, 0.86)          # offshore: boat-landing band, z0..z1
# The sea is its own rectangle, tighter in Y than SITE: onshore that depth is spent on the
# control building and the switchyard, and offshore there is nothing to spend it on.
SEA = (-3.15, 3.85, -2.10, 2.50)

# OFFSHORE CARRIES NO YARD AT ALL — no substation platform, no control room, no transformers,
# mast, gantry or batteries. The whole sprite is turbines standing in water.
#
# It went through a platform first, because the yard equipment obviously cannot sit on the sea
# surface, and a jacket-legged deck is the honest fix. But the deck then had to be squeezed
# clear of every turbine footprint, it competed with the rotors for the eye, and it made the
# offshore sprite a near-copy of the onshore one. Dropping it is better on every count: the
# real export cable runs to shore and is off-frame, so nothing is left dangling.
#
# The cost is that offshore has NOTHING but turbines to signal level with, so the level must
# be carried by COUNT and SIZE alone. The sea plate is therefore the same rectangle at every
# level — if it grew with the turbines, the shared-scale export would normalise the growth
# straight back out and every level would come back the same size.
OFFSHORE_HUB = {1: 0.86, 2: 0.96, 3: 1.08}   # hub-height multiplier, per level


def _blade(K, name, hub, ang_deg, R, mat, stations=7):
    """One blade: a lofted tapered aerofoil in the rotor plane, as a single mesh.

    Local frame — `d` runs along the blade, `c` is chord (perpendicular, in the rotor plane),
    `n` is thickness (roughly the rotor normal). See the BLADE PLANFORM note: chord peaks at
    BLADE_SHOULDER, the leading edge is held straight, and each section is TWISTED about `d`
    by an angle that washes out to zero at the tip."""
    import bpy, bmesh
    a = math.radians(ang_deg)
    u, n = ROTOR_U, ROTOR_N                    # see the ROTOR_YAW note
    w = (0.0, 0.0, 1.0)
    d = tuple(u[k] * math.cos(a) + w[k] * math.sin(a) for k in range(3))
    c = tuple(-u[k] * math.sin(a) + w[k] * math.cos(a) for k in range(3))

    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    rings = []
    for i in range(stations):
        t = i / float(stations - 1)
        r = BLADE_R0 + (R - BLADE_R0) * t                      # root buried in the hub drum
        rr = r / R
        if rr <= BLADE_SHOULDER:
            f = BLADE_ROOT_F + (1.0 - BLADE_ROOT_F) * (rr / BLADE_SHOULDER)
        else:
            f = 1.0 - (1.0 - BLADE_TIP_F) * (
                (rr - BLADE_SHOULDER) / (1.0 - BLADE_SHOULDER)) ** 0.80
        chord = BLADE_MAX_C * f
        thick = BLADE_ROOT_T + (BLADE_TIP_T - BLADE_ROOT_T) * (rr ** 0.6)
        off = BLADE_SWEEP * (rr ** 2.5)                        # tip sweep only
        # Twist the section about the span axis. Safe against the edge-on trap: 14 deg on a
        # rotor already yawed 25 deg off the camera leaves every section well clear of lying
        # along the view ray.
        bt = math.radians(BLADE_TWIST) * (1.0 - rr) ** 2
        cb, sb = math.cos(bt), math.sin(bt)
        ct = tuple(c[k] * cb + n[k] * sb for k in range(3))
        nt = tuple(-c[k] * sb + n[k] * cb for k in range(3))
        # Leading edge pinned at a CONSTANT offset; the chord grows backwards from it.
        le = BLADE_LE * BLADE_MAX_C + off
        quad = []
        for sc, sn in ((0.0, -1), (1.0, -1), (1.0, 1), (0.0, 1)):
            quad.append(bm.verts.new(tuple(
                hub[k] + d[k] * r + ct[k] * (le - sc * chord) + nt[k] * sn * thick / 2.0
                for k in range(3))))
        rings.append(quad)
    for i in range(stations - 1):
        for j in range(4):
            k = (j + 1) % 4
            bm.faces.new([rings[i][j], rings[i][k], rings[i + 1][k], rings[i + 1][j]])
    bm.faces.new(list(reversed(rings[0])))
    bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me)
    bm.free()
    return K.obj(name, me, mat)


def _nacelle(K, name, front, axis, mat, stations=9, seg=10):
    """Nacelle as a LOFTED body with a rounded, tapering tail rather than a box.

    A `dirbox` ends in a flat slab that reads as a cut-off crate, and the rotor yaw is exactly
    what turned that slab to face the viewer. The rear 45% therefore closes on an ELLIPTICAL
    profile - sqrt(1 - x*x) has a vertical tangent at the end, which is what makes the tail
    read as rounded rather than merely narrowed."""
    import bpy, bmesh
    u, w = ROTOR_U, (0.0, 0.0, 1.0)
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    rings = []
    for i in range(stations):
        sv = i / float(stations - 1)
        if sv <= 0.55:
            f = 1.0
        else:
            f = 0.22 + 0.78 * math.sqrt(max(0.0, 1.0 - ((sv - 0.55) / 0.45) ** 2))
        cen = tuple(front[k] + axis[k] * (sv * NAC_L) for k in range(3))
        ring = []
        for j in range(seg):
            a = 2.0 * math.pi * j / seg
            ring.append(bm.verts.new(tuple(
                cen[k] + u[k] * (NAC_W / 2.0 * f) * math.cos(a)
                + w[k] * (NAC_H / 2.0 * f) * math.sin(a) for k in range(3))))
        rings.append(ring)
    for i in range(stations - 1):
        for j in range(seg):
            k2 = (j + 1) % seg
            bm.faces.new([rings[i][j], rings[i][k2], rings[i + 1][k2], rings[i + 1][j]])
    bm.faces.new(list(reversed(rings[0])))
    bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me)
    bm.free()
    return K.obj(name, me, mat)


def _turbine(K, tag, cx, cy, hub_z, base_z=0.0, offshore=False):
    """Tower, nacelle, hub and three blades. Blades and nacelle go in FINE_INK: at 2.4 px a
    rotor's linework fills in solid, and the outer contour is synthesized at export anyway."""
    R = hub_z * ROTOR_FRAC
    n = ROTOR_N
    # Tower. The TAPER is what sells the height — parallel sides give the eye no cue and read
    # as a pipe offcut (the furnace-stack lesson). It stops at the nacelle UNDERSIDE, with a
    # 0.03 overlap, so the nacelle rests on it instead of being skewered by it.
    twr_h = hub_z - NAC_H / 2.0 + 0.03
    K.cone("twr%s" % tag, cx, cy, base_z + twr_h / 2.0, TOWER_R0, TOWER_R1, twr_h,
           K.mat("wall_bright"), segments=24)
    if offshore:
        # Wash collar first, so the pile draws over it.
        K.cyl("wash%s" % tag, cx, cy, 0.015, TOWER_R0 + 0.19, 0.03, K.mat("wash"),
              segments=20)
        # Transition piece with the hi-vis boat-landing band: the real-world signature, and it
        # doubles as the power chroma.
        z0, z1 = MONOPILE_BAND
        K.cyl("tp%s" % tag, cx, cy, base_z + (z0 + z1) / 2.0, TOWER_R0 + 0.045, z1 - z0,
              K.mat("plant_yellow"), segments=24)
        # EXPLICIT material. ladder() defaults to mat("accent"), and `accent` resolves to
        # `purple` — the refinery chroma — so the default put a lilac bar on every monopile.
        K.ladder("lad%s" % tag, cx, cy - TOWER_R0 - 0.03, base_z + z1, base_z + z1 + 0.55,
                 face="-Y", w=0.16, mat=K.mat("handrail"))
    else:
        # Square hardstanding under a round tower: the pad is a real thing on a real farm and
        # it also stops the tower's base cap sitting coplanar with the site top.
        K.box("pad%s" % tag, cx, cy, base_z + 0.035, 0.86, 0.86, 0.07, K.mat("gravel"))
        K.cyl("base%s" % tag, cx, cy, base_z + 0.11, TOWER_R0 + 0.10, 0.16,
              K.mat("yard_pad"), segments=20)

    # Hub sits upwind of the tower axis, at nacelle mid-height on top of the tower.
    nz = base_z + hub_z
    hub = (cx + n[0] * NAC_OVERHANG, cy + n[1] * NAC_OVERHANG, nz)
    fm = K._fine_mode
    K._fine_mode = True
    # Nacelle runs back along the rotor normal, PAST the tower axis (which is NAC_OVERHANG
    # behind the hub) and on to its rounded tail.
    _nacelle(K, "nac%s" % tag, tuple(hub[k] + n[k] * 0.06 for k in range(3)),
             tuple(-v for v in n), K.mat("wall_bright"))
    # Hub drum, then a stepped nose. Both grey: three white blades want one darker anchor
    # where they meet, and the step is enough of a taper at sprite scale.
    K.dircyl("hub%s" % tag,
             tuple(hub[k] - n[k] * 0.04 for k in range(3)),
             tuple(hub[k] + n[k] * 0.20 for k in range(3)),
             HUB_R, K.mat("gear"), segments=16)
    K.dircyl("nose%s" % tag,
             tuple(hub[k] + n[k] * 0.17 for k in range(3)),
             tuple(hub[k] + n[k] * 0.29 for k in range(3)),
             NOSE_R, K.mat("gear"), segments=14)
    # Three blades, 120 apart, and the START ANGLE varies per turbine — a farm of rotors all
    # frozen at the same clock position reads as one object stamped out repeatedly.
    #
    # DERIVED FROM THE INDEX, never from hash(). Python randomises string hashing per process,
    # so `hash(tag)` gave every render a different set of clock positions: the sprite was not
    # reproducible, two bakes of an unchanged builder differed by 45 px of bounding box, and a
    # future re-bake would have tripped the verify gate for no reason at all.
    # 47 is coprime with 120, so six turbines land on six well-separated angles.
    phase = (int(tag) * 47.0) % 120.0
    for b in range(3):
        _blade(K, "bld%s_%d" % (tag, b), tuple(hub[k] + n[k] * 0.09 for k in range(3)),
               phase + b * 120.0, R, K.mat("wall_bright"))
    K._fine_mode = fm


def _site(K, offshore):
    x0, x1, y0, y1 = SEA if offshore else SITE
    if offshore:
        # Water: a flat plate. It needs no stipple exclusion any more — a +Z face is the
        # brightest thing in the shading mask, so the print pass leaves it clean by itself.
        # (The old luma-keyed pass screened the whole harbour and needed --skip-hex.)
        K.box("sea", (x0 + x1) / 2, (y0 + y1) / 2, -0.06, x1 - x0, y1 - y0, 0.12,
              K.mat("water"))
        return 0.0
    K.box("ground", (x0 + x1) / 2, (y0 + y1) / 2, SITE_H / 2, x1 - x0, y1 - y0, SITE_H,
          K.mat("ground"))
    # Turf, not earth. A wind farm's ground is FIELD — the pads and tracks are the only made
    # surfaces on it — and the green also separates the onshore sprite from the offshore one at
    # a glance, which matters now that offshore is turbines alone.
    K.box("ground_top", (x0 + x1) / 2, (y0 + y1) / 2, SITE_H + 0.012, x1 - x0 - 0.06,
          y1 - y0 - 0.06, 0.05, K.mat("turf"))
    # A darker sward across the back half. One flat green over 7 x 5 units is the largest
    # single tone in the sprite; splitting it on a WORLD AXIS (never the x+y diagonal) costs
    # one box and stops the plate reading as a billiard table.
    K.box("turf_far", (x0 + x1) / 2, (0.55 + y1) / 2, SITE_H + 0.020, x1 - x0 - 0.06,
          y1 - 0.55, 0.05, K.mat("turf_lo"))
    # Strata on the two cut faces the camera SEES. Earth tones stay inside 0.05-0.30: above
    # that the bands render within a few luma of each other and the layering vanishes.
    for i, m in enumerate(("ground3", "ground_deep")):
        z = SITE_H * (0.60 - 0.30 * i)
        K.box("strat_f%d" % i, (x0 + x1) / 2, y0 - 0.012, z, x1 - x0, 0.03, SITE_H * 0.22,
              K.mat(m))
        K.box("strat_r%d" % i, x1 + 0.012, (y0 + y1) / 2, z, 0.03, y1 - y0, SITE_H * 0.22,
              K.mat(m))
    # Tracks and hardstandings, so the site is a place rather than a plate.
    K.box("track_sp", (x0 + x1) / 2, TRACK_Y, SITE_H + 0.030, x1 - x0 - 0.30, TRACK_W, 0.05,
          K.mat("gravel"))
    K.box("track_sr", TRACK_X, (TRACK_Y + y1) / 2, SITE_H + 0.030, TRACK_W,
          y1 - TRACK_Y - 0.25, 0.05, K.mat("gravel"))
    return SITE_H


def _yard(K, p, base_z):
    """Everything that is not a turbine: the power take-off that makes it read as `power`.

    ONSHORE ONLY — see the OFFSHORE_HUB note."""
    if p["control"]:
        cx0, cx1, cy0, cy1 = CONTROL
        h = 0.92
        K.box("ctrl", (cx0 + cx1) / 2, (cy0 + cy1) / 2, base_z + h / 2, cx1 - cx0,
              cy1 - cy0, h, K.mat("wall_pale"))
        K.box("ctrl_dado", (cx0 + cx1) / 2, (cy0 + cy1) / 2, base_z + 0.16, cx1 - cx0 + 0.02,
              cy1 - cy0 + 0.02, 0.30, K.mat("power_accent"))
        K.box("ctrl_roof", (cx0 + cx1) / 2, (cy0 + cy1) / 2, base_z + h + 0.05,
              cx1 - cx0 + 0.12, cy1 - cy0 + 0.12, 0.10, K.mat("roof_deck"))
        K.window("ctrl_w0", "-Y", (cx0 + 0.42, cy0, base_z + 0.58), 0.30, 0.42)
        K.window("ctrl_w1", "-Y", (cx0 + 0.95, cy0, base_z + 0.58), 0.30, 0.42)
        K.door("ctrl_d", "-Y", (cx1 - 0.32, cy0, base_z + 0.34), 0.30, 0.68)

    for k in range(2 if p["control"] else 1):
        K.transformer("tr%d" % k, TR_XY[0] + k * 0.92, TR_XY[1], base_z, s=1.25, accent=True)

    if p["gantry"]:
        K.substation_gantry("sg", (GANTRY_XY[0] - GANTRY_HALF, GANTRY_XY[1]),
                            (GANTRY_XY[0] + GANTRY_HALF, GANTRY_XY[1]), base_z, 1.60)
    for k in range(p["batteries"]):
        bx = BATT_XY[0] + k * 1.05
        by = BATT_XY[1]
        K.box("batt%d" % k, bx, by, base_z + 0.29, 0.92, 0.44, 0.58,
              K.mat("wall_bright"))
        K.box("batt%d_lid" % k, bx, by, base_z + 0.61, 1.00, 0.50, 0.07,
              K.mat("roof_deck"))
        K.box("batt%d_band" % k, bx, by - 0.235, base_z + 0.34, 0.84, 0.03, 0.09,
              K.mat("power_accent"))


def _build(level, offshore):
    p = WF_LEVELS[level]
    setup_rig(target=(0.35, 0.20, 1.35))
    K = Kit(open_collection("BLDG_offshore_wind" if offshore else "BLDG_wind"))
    base_z = _site(K, offshore)
    # Offshore machines grow with the level as well as multiplying, because count and size are
    # the only two things left to say it with.
    hs = OFFSHORE_HUB[level] if offshore else 1.0
    for i in range(p["turbines"]):
        cx, cy, hz = TURBINES[i]
        _turbine(K, str(i), cx, cy, hz * hs, base_z=base_z, offshore=offshore)
    if not offshore:
        _yard(K, p, base_z)
    print("\n".join(K.validate(ground=0.0)))
    return {"building": "offshore_wind_farm" if offshore else "onshore_wind_farm",
            "level": level, "turbines": p["turbines"], "objects": len(K.col.objects)}


def build_wind_farm(level: int = 2) -> dict:
    return _build(level, offshore=False)


def build_offshore_wind_farm(level: int = 2) -> dict:
    return _build(level, offshore=True)
