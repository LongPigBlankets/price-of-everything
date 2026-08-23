# Parametric builder for the Electric Arc Furnace (b_008, internal_name `eaf`).
# Run AFTER sprite_kit.py:
#   exec(open(".../sprite_kit.py").read())
#   exec(open(".../eaf_builder.py").read()); build_eaf(2)
#
# Brief (owner, 2026-08-21): three rod-shaped electrodes with FLAT ENDS, submerged in a
# half-sphere bath of molten metal. A building enclosure around it — but the roof tall
# enough and the bowl forward enough to SEE INSIDE.
#
# It is the blast furnace's sibling: same steel-and-heat family, no slab (both metallurgy
# buildings sit on z=0), ember as the only chroma because CAT_METALLURGY's steel blue is
# already the body colour. What it must NOT borrow is the furnace's silhouette — no towers,
# no merged stacks. The bath is the landmark and everything else is set back from it.
#
# LAYOUT in the owner's screen vocabulary (back = +Y / top-right, right = +X / lower-right):
#   * MELT SHOP filling the back, its FRONT gable an open portal bay.
#   * BOWL straddling that portal line, more than half of it standing proud of the building.
#   * BAG HOUSE to the right, clear of the hall in x, fed by a canopy hood over the bath.
#   * TRANSFORMER on the front-left frontage; CASTER ANNEX (L3) behind it.
#
# ---------------------------------------------------------------------------------------
# THE SIGHTLINE, WHICH IS THE WHOLE DESIGN
#
# "Can you see the bath" is an equation, not a judgement, and it is NOT the parapet form of
# the rule. A wall you see OVER is `z_p + y_p > z_wall + y_wall`. An opening you see THROUGH
# is the other way round: the sightline from an interior point to the camera crosses the
# front wall plane at
#
#       z_cross = z_p + (y_p - FY0)
#
# (camera direction is (1,-1,1)/sqrt3, so one unit of travel toward -Y buys exactly one unit
# of z) and the point is visible only if that crossing lands BELOW the opening's head. Every
# lever in the owner's note is in that expression: raise the head (tall roof), or lower y_p
# (bowl forward). _check_sightlines() below asserts it for the melt rim and every rod tip
# rather than trusting the layout — this is the one thing here that cannot be fixed by
# eyeballing a render, because a hidden bath looks exactly like a bath that is not there.

import math

# PALETTE additions must be at MODULE scope, before any Kit() is constructed: Kit.__init__
# calls build_materials(), which snapshots PALETTE, so a role added inside build_eaf() would
# raise KeyError on its first mat() call.
# Copper is a SECOND warm tone but not a second chroma family — it sits between heat_red
# (0.43, 0.12, 0.065) and the ember, differing by having real green in it, which is what
# separates orange-brown metal from painted red. Held at 0.435 so it lands near L162, clearly
# above the navy ink and clearly below the melt.
PALETTE["copper"] = (0.435, 0.195, 0.075)
PALETTE["copper_lo"] = (0.250, 0.108, 0.042)
ROLES["busbar"] = "copper"
ROLES["busbar_lo"] = "copper_lo"

# The EAVE IS THE SAME ON EVERY LEVEL, and that is not laziness. The shop's height is set by
# what has to be SEEN inside it — the same argument the power plant makes for its flue ("the
# plant's constant vertical, so it must not shrink at L1 where it is the only one"). L1 dropped
# to a 3.20 eave once and _check_sightlines refused the build: the back rod's tip crossed the
# portal head at -0.14. L1 differs in DEPTH and in equipment instead.
#
# 4.55 is SOLVED, not chosen. The transformer now stands inside, and it is 3.21 tall; at
# y = 1.15 its sightline crossing is 4.16, so anything under about 4.2 buries its bushings.
# The old 3.55 eave would have hidden the top third of it.
EAF_LEVELS = {
    1: dict(hall_y1=3.44, bag=False, ladle=False,
            bag_x1=5.05, caster=False, elec=False, chute=False),
    2: dict(hall_y1=3.44, bag=True,  ladle=True,
            bag_x1=5.05, caster=False, elec=True,  chute=False),
    3: dict(hall_y1=3.44, bag=True,  ladle=True,
            bag_x1=5.05, caster=True,  elec=True,  chute=True),
}

# ---- melt shop -------------------------------------------------------------------------
HX0, HX1 = -2.30, 3.10          # hall x extent — widened to take the transformer
FY0 = 0.20                      # FRONT wall line. The bowl straddles it.
WALL_T = 0.16
RIDGE_RISE = 0.70               # ridge stands this far above the eave
PORTAL = (-1.85, 2.60)          # the open bay: x range of the portal between the returns
FASCIA = 0.17                   # eave beam depth — this IS the opening's head member

# ---- the bowl --------------------------------------------------------------------------
# rise/r = 1.03. The first pass used 0.55 and rendered as a saucer: dome_cap's rise and
# radius are independent, which is exactly what lets a bowl be got wrong in either
# direction, and the proportion lesson from the tanks applies unchanged — 0.52r x 0.74h
# read as discs on the ground, 0.42 x 1.15 read as tanks. A furnace shell is about as deep
# as it is wide.
# Centred in X, FORWARD in Y. Centring in Y as well was tried and measured: it moved the
# bowl 1.67 back, every sightline crossing carries that one-for-one, and the solved eave went
# 3.62 -> 6.04. The shed then took 56% of the sprite and the bath 4.8%. X was the axis that
# was actually off-centre, once the shop was widened to the right.
BX, BY = (HX0 + HX1) / 2.0, 0.15
BOWL_R, BOWL_RISE, BOWL_WALL = 0.92, 0.95, 0.09
RIM_Z = 1.62
MELT_DROP = 0.16                # melt surface below the rim: what makes the inner lip show
# The plinth is deliberately NARROWER in plan than the bowl (1.55 across against a 1.84
# vessel) so the shell overhangs it. At the first size it was wider, and its top face
# occluded the entire lower shell — the bowl was there and simply could not be seen.
PLINTH_TOP = 0.42
PLINTH_XY = 1.55

# ---- electrodes ------------------------------------------------------------------------
# Equilateral triangle on a 0.40 ring. WHICH rotation is not cosmetic: screen-horizontal is
# (x+y), and a ring vertex at angle t contributes R*sqrt2*sin(t+45), so the three screen
# columns are set entirely by the rotation. At 90/210/330 they came out at 0.40 / -0.55 /
# 0.15 — the right-hand pair only 16 px apart, so the sprite read as two rods, not three.
# The three sines always sum to zero, so they are evenly spread exactly when one of them is
# zero: t + 45 = 0 (mod 120). Hence 75 / 195 / 315, giving columns +0.49 / -0.49 / 0.00 —
# 32 px between neighbours, even.
ROD_R = 0.115
ROD_RING = 0.40
ROD_ANGLES = (75.0, 195.0, 315.0)
# Index 0 is the BACK rod (y = +0.39) and it is the SHORT one: its sightline crossing carries
# the +y penalty, so making it the tall one is what pushes a tip up behind the eave.
ROD_TOPS = (3.00, 3.45, 3.28)
ROD_SUBMERGE = 0.10             # how far the flat bottom end sits UNDER the melt surface
# The arms are carried on a single thick beam across the back of the bay. It is deep enough
# in z to receive all three arms, which sit at their own rods' clamp heights — a bar at one
# level could only ever meet one of them.
# The rail sits at the shop's MID-DEPTH, not just behind the bowl. That costs height: its top
# is the binding sightline in the whole build, and moving it from y=0.93 to y=1.82 pushes its
# crossing 4.09 -> 4.88, so the solved eave follows. Trimming its z-depth from 0.86 to 0.64
# pays about a third of that back while still covering all three arms.
BEAM_DY = 1.67                  # -> beam_y = (FY0 + FY1)/2, the middle of the shop
BEAM_SY, BEAM_Z0, BEAM_Z1 = 0.38, 2.62, 3.26
# The rail spans WALL TO WALL, so the arms read as riding it rather than as being propped on
# a stub. It is carried by the side walls; the floor legs it used to need are gone.
JOINT = 0.21                    # reinforcement collar section at every arm end

# ---- yard ------------------------------------------------------------------------------
BAG_X0, BAG_Y0, BAG_Y1 = 3.65, 0.30, 1.80   # x1 is per-level: L3 widens the filter plant,
                                            # which is a capability step, not more fittings.
                                            # x0 clears the hall so it never occludes the portal
BAG_Z0, BAG_Z1 = 1.55, 3.45
HOP_Z = 0.52                    # hopper throat height, where the downpipe starts
# The throat is DERIVED, not chosen — see _hopper_throat(). A hopper wall that recedes one
# unit horizontally per unit it drops lies exactly along the view ray and disappears, so the
# wall angle is the constraint and the throat is whatever satisfies it. That makes the throat
# RECTANGULAR on a rectangular box, and more so the wider the box gets: L3's filter plant is
# 2.30 across and 1.50 deep, so its throat is a 1.13 x 0.33 slot rather than a square hole.
HOP_RATIO = 0.55                # target wall inset per unit drop
HOP_MAX_RATIO = 0.75            # hard limit the assertion refuses to build past
HOOD_XY = (BX + 0.20, BY + 1.02)
DUCT_Z = 2.30
# The high run's height is set by the hopper's LID, not by taste. At 3.35 with r=0.24 it
# topped out at 3.59 while the lid spans 3.45-3.55, so its upper half broke through and sat
# on the roof of the vessel as a stray lump between the two buildings.
DUCT_RUN_Z = 3.05
CASTER = (-4.05, -2.40, 1.15, 2.90)
# Electrics. The bus duct runs along +Y at BUS_X, outboard of the shop's right wall, and the
# furnace transformer stands beside the shop's +X flank at 3x the size it started at.
BUS_DROP_Z = 2.70               # where a bar meets its bushing
XFMR_XY = (-2.25, -0.85)        # OUTSIDE, front-left, on the frontage the scrap vacated
XFMR_S = 4.35                   # 3x the 1.45 it started at, in every dimension
# Two thick pipes up the shop's +X flank. They stand a hair PROUD of the wall rather than
# being applied to it: at this camera only what breaks a silhouette shows.
# Against the BACK wall, standing a little proud of it so they are not swallowed by a face
# the camera cannot see, and tall enough to break the roofline.
#
# SIDE BY SIDE means equal +x/+y, not equal y. Screen height is z - (x - y)/2, so two pipes
# sharing a y but 1.2 apart in x sit 0.6 apart in screen height — which is exactly the
# "angled" look. Stepping BOTH coordinates by the same amount keeps (x - y) constant, so they
# land at the same height and separate purely across the picture. Same rule as the furnace's
# twin stacks.
# You cannot have both, and it is worth being exact about why. Screen height is z - (x-y)/2,
# so equal height requires equal (x - y) — a plan DIAGONAL — and a diagonal necessarily puts
# the two at different distances from an axis-aligned wall. The last pass chose equal height
# and left one pipe 0.72 further out than the other, which is what read as wrong.
#
# This pass chooses EQUAL DISTANCE from the wall, separated purely in x, and levels the TOPS
# instead by giving the right-hand pipe exactly dx/2 more height. Their bases step down to the
# right, which is simply what nearer-in-x looks like, and the eye reads a pair off their crowns.
BACK_PIPE_Y_OFF = 0.34          # both pipes, the same distance off the back wall
BACK_PIPE_DX = 1.05
BACK_PIPE_CLEAR = 0.40          # how far the LOWER crown stands above the roof ON SCREEN
BACK_PIPE_SCALE = 1.10          # 10% taller
# L3 charging lift. A run along Y that RISES TOWARD THE FRONT has on-screen slope
# dH = dz - |dy|/2, so it renders DEAD FLAT at a 26.57 deg incline and reads as DESCENDING
# below it. That is the precise reason the furnace's inclined gantry was abandoned. At 52 deg
# it reads as a 48 deg diagonal, which is what makes this one work where that one did not.
# Starting FURTHER BACK and finishing HIGHER. The head used to sit close over the mouth and
# covered the very thing it was feeding; lifting it and reaching further back leaves the hole
# open around the spout. The incline barely changes — both numbers grew together.
LIFT_RUN_Y = 1.80               # horizontal run; with a 4.65 rise that is 68.8 deg
LIFT_HEAD_DY = 0.72             # head sits this far behind the chute's centre
LIFT_HEAD_Z = 4.75
LIFT_FOOT_Z = 0.10
LIFT_W, LIFT_D = 0.74, 0.60
LIFT_MIN_INCLINE = 40.0


def _melt_radius():
    """Bowl radius at the melt surface, measured on the INNER shell. Two ways to get this
    wrong, both of which flood the pool over its own lip: using the rim radius (ignores the
    ellipsoid) or using the outer shell (ignores the wall thickness)."""
    r_in, rise_in = BOWL_R - BOWL_WALL, BOWL_RISE - BOWL_WALL
    d = MELT_DROP / rise_in
    return r_in * math.sqrt(max(0.0, 1.0 - d * d))


def _melt_mat():
    """Molten steel. The kit's `ember` is tuned for a door reveal — at strength 1.45 over a
    small opening it reads right, but across a bath-sized disc the AgX curve desaturates it
    to cream. Lower strength and a more saturated hue keeps it orange at area."""
    import bpy
    mt = bpy.data.materials.get("eaf_melt")
    if mt is not None:
        return mt
    mt = bpy.data.materials.new("eaf_melt")
    mt.use_nodes = True
    b = mt.node_tree.nodes.get("Principled BSDF")
    b.inputs["Base Color"].default_value = (0, 0, 0, 1)
    b.inputs["Emission Color"].default_value = (1.0, 0.355, 0.050, 1)
    b.inputs["Emission Strength"].default_value = 0.95
    b.inputs["Roughness"].default_value = 1.0
    if "Specular IOR Level" in b.inputs:
        b.inputs["Specular IOR Level"].default_value = 0.0
    return mt


def _frustum(K, name, x0, x1, y0, y1, z_top, z_bot, tx, ty, mat):
    """Four-sided frustum: full rectangle at z_top, a small centred rectangle at z_bot.
    An inverted pyramid receding on ALL sides, which is what a single central hopper is —
    `sqcol` only does squares and the bag house footprint is not square."""
    import bpy, bmesh
    cx, cy = (x0 + x1) / 2.0, (y0 + y1) / 2.0
    top = [(x0, y0), (x1, y0), (x1, y1), (x0, y1)]
    bot = [(cx - tx / 2, cy - ty / 2), (cx + tx / 2, cy - ty / 2),
           (cx + tx / 2, cy + ty / 2), (cx - tx / 2, cy + ty / 2)]
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    vt = [bm.verts.new((x, y, z_top)) for (x, y) in top]
    vb = [bm.verts.new((x, y, z_bot)) for (x, y) in bot]
    for i in range(4):
        j = (i + 1) % 4
        bm.faces.new([vt[i], vt[j], vb[j], vb[i]])
    bm.faces.new(list(reversed(vb)))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me); bm.free()
    return K.obj(name, me, mat)


def _glow_mat():
    """A dimmer amber than the bath. It has to read as light SPILLING from further in, so it
    must never approach the melt's brightness — the bath is the landmark and a second light of
    equal strength would simply split the sprite's attention in two."""
    import bpy
    mt = bpy.data.materials.get("eaf_glow")
    if mt is not None:
        return mt
    mt = bpy.data.materials.new("eaf_glow")
    mt.use_nodes = True
    b = mt.node_tree.nodes.get("Principled BSDF")
    b.inputs["Base Color"].default_value = (0, 0, 0, 1)
    b.inputs["Emission Color"].default_value = (1.0, 0.42, 0.09, 1)
    b.inputs["Emission Strength"].default_value = 0.42
    b.inputs["Roughness"].default_value = 1.0
    if "Specular IOR Level" in b.inputs:
        b.inputs["Specular IOR Level"].default_value = 0.0
    return mt


def _coil_glow_mat():
    """The coil's hot end. Dimmer and redder than the melt, and non-competing by design —
    the bath stays the one thing in this sprite that is properly bright."""
    import bpy
    mt = bpy.data.materials.get("eaf_coil_glow")
    if mt is not None:
        return mt
    mt = bpy.data.materials.new("eaf_coil_glow")
    mt.use_nodes = True
    b = mt.node_tree.nodes.get("Principled BSDF")
    b.inputs["Base Color"].default_value = (0, 0, 0, 1)
    b.inputs["Emission Color"].default_value = (1.0, 0.20, 0.055, 1)
    b.inputs["Emission Strength"].default_value = 0.34
    b.inputs["Roughness"].default_value = 1.0
    if "Specular IOR Level" in b.inputs:
        b.inputs["Specular IOR Level"].default_value = 0.0
    return mt


def _shell_r(z):
    """Outer radius of the bowl at height z. The coil has to TAPER with the vessel — a
    constant-radius coil floats off the shell everywhere except one ring."""
    d = max(0.0, min(BOWL_RISE, RIM_Z - z))
    return BOWL_R * math.sqrt(max(0.0, 1.0 - (d / BOWL_RISE) ** 2))


def _rod_xy(i):
    a = math.radians(ROD_ANGLES[i])
    return BX + ROD_RING * math.cos(a), BY + ROD_RING * math.sin(a)


def _sightline_tests():
    """Every feature that has to be SEEN through the portal, as (name, x, y, z)."""
    rm = _melt_radius()
    t = [("melt near lip", BX, BY - rm, RIM_Z - MELT_DROP),
         ("melt centre",   BX, BY,      RIM_Z - MELT_DROP),
         ("melt far lip",  BX, BY + rm, RIM_Z - MELT_DROP),
         ("bowl far rim",  BX, BY + BOWL_R, RIM_Z)]
    for i in range(3):
        rx, ry = _rod_xy(i)
        t.append(("rod %d tip" % (i + 1), rx, ry, ROD_TOPS[i]))
    t.append(("hood", HOOD_XY[0], HOOD_XY[1], DUCT_Z))
    t.append(("arm beam top", BX, BY + BEAM_DY, BEAM_Z1))
    return t


def _solve_eave(margin=0.28):
    """Lowest eave that still shows everything, rather than a number typed and then defended.

    Recentring the bowl in the deepened shop moved it 1.67 back, and every crossing carries
    that move one-for-one, so the eave is no longer something to pick: it is an output. For
    the record, the same building with the bowl left forward at y=0.15 solves to 3.62."""
    return max(pz + (py - FY0) for _, _, py, pz in _sightline_tests()) + margin


def _check_sightlines(eave):
    """Assert every feature the owner asked to SEE actually clears the portal head.

    Returns a list of report lines; raises if anything is buried. Render to CONFIRM, not to
    search — a bath hidden behind a header looks identical to a bath that was never built."""
    head = eave                      # the opening runs full height to the eave fascia
    out, worst = [], None
    for name, px, py, pz in _sightline_tests():
        z_cross = pz + (py - FY0)
        margin = head - z_cross
        out.append("  %-14s crosses front plane at z=%.2f  head=%.2f  margin=%+.2f %s"
                   % (name, z_cross, head, margin, "OK" if margin > 0 else "** BURIED **"))
        if worst is None or margin < worst[1]:
            worst = (name, margin)
    out.append("  tightest: %s %+.2f" % worst)
    if worst[1] <= 0.0:
        raise RuntimeError("EAF sightline failed: %s is behind the portal head (%+.2f). "
                           "Raise `eave` or move the bowl forward (lower BY)." % worst)
    return out


def _hopper_throat(bx1):
    """Throat section that keeps both hopper walls steeper than the view ray."""
    drop = (BAG_Z0 + 0.03) - HOP_Z
    tx = max(0.34, (bx1 - BAG_X0) - 2.0 * HOP_RATIO * drop)
    ty = max(0.34, (BAG_Y1 - BAG_Y0) - 2.0 * HOP_RATIO * drop)
    return tx, ty


def _lift_geom(ccy):
    """Foot and head of the charging lift, derived from where the chute actually is."""
    head_y = ccy + LIFT_HEAD_DY
    return head_y + LIFT_RUN_Y, head_y


def _lift_incline(ccy):
    """Incline of the charging lift, and its resulting angle ON SCREEN.

    These are two different numbers and only the second one matters. A run along Y that rises
    toward the FRONT has screen slope `dH = dz - |dy|/2`, because travelling one unit toward
    -Y already lifts a point half a unit up the picture. So the incline that renders DEAD FLAT
    is atan(0.5) = 26.57 deg, and anything shallower reads as going DOWNHILL while climbing.
    This is the whole of why the furnace's inclined gantry was abandoned; it is not a
    mysterious fact about "inclines fighting the camera"."""
    foot_y, head_y = _lift_geom(ccy)
    dy = foot_y - head_y
    dz = LIFT_HEAD_Z - LIFT_FOOT_Z
    inc = math.degrees(math.atan2(dz, dy))
    screen = math.degrees(math.atan2(dz - dy / 2.0, dy / math.sqrt(2.0)))
    if inc < LIFT_MIN_INCLINE:
        raise RuntimeError("EAF lift incline %.1f deg is below %.1f: a back-to-front run "
                           "flattens on screen at 26.6 deg and inverts below it."
                           % (inc, LIFT_MIN_INCLINE))
    return "  lift incline %.1f deg  ->  %.1f deg ON SCREEN (flat at 26.6)" % (inc, screen)


def _lift(K, cx, ccy):
    """Enclosed inclined lift, foot at the back, head delivering into the chute at the front.

    Built with `prism`, not an oriented box: a box caps both ends perpendicular to the run,
    which leaves a knife-edge at the foot and drives its corners through whatever it lands on.
    The profile is a PARALLELOGRAM — convex, so the n-gon end caps are safe."""
    foot_y, head_y = _lift_geom(ccy)
    fy, fz = foot_y, LIFT_FOOT_Z
    dy = fy - head_y
    dz = LIFT_HEAD_Z - fz
    run = math.hypot(dy, dz)
    # profile is (along -Y from the foot, up); casing depth measured PERPENDICULAR to the run
    nx, nz = dz / run, dy / run          # unit normal to the run, in the (along, up) plane
    a0, u0 = 0.0, 0.0
    a1, u1 = dy, dz
    d = LIFT_D
    K.prism("lift", (cx, fy, fz), (0.0, -1.0, 0.0),
            [(a0 - nx * d / 2, u0 - nz * d / 2), (a1 - nx * d / 2, u1 - nz * d / 2),
             (a1 + nx * d / 2, u1 + nz * d / 2), (a0 + nx * d / 2, u0 + nz * d / 2)],
            LIFT_W, K.mat("wall_grey"))
    # Ribs along the casing, as material-free proud strips: they give the diagonal a rhythm
    # so it reads as machinery rather than as a plain wedge.
    for k in range(6):
        t = (k + 0.5) / 6.0
        K.box("lift_rib%d" % k, cx, fy - dy * t, fz + dz * t + 0.12,
              LIFT_W + 0.06, 0.09, 0.24, K.mat("stair"))
    K.box("lift_foot", cx, fy - 0.16, 0.22, LIFT_W + 0.12, 0.56, 0.44, K.mat("yard"))
    for sgn in (-1, 1):     # two legs propping the middle of the run
        ty = 0.42 + 0.22 * (sgn > 0)
        K.box("lift_leg%d" % (sgn > 0), cx + sgn * (LIFT_W / 2 - 0.06), fy - dy * ty,
              (fz + dz * ty) / 2.0, 0.11, 0.11, fz + dz * ty, K.mat("stair"))
    K.box("lift_head", cx, head_y - 0.06, LIFT_HEAD_Z - 0.18, LIFT_W + 0.16, 0.46, 0.50,
          K.mat("gear"))
    # DISCHARGE SPOUT: the head has to be seen delivering INTO the hole, not just ending
    # above it. A short chute angled down over the mouth is what makes the two one machine.
    K.prism("lift_spout", (cx - (LIFT_W - 0.22) / 2, 0.0, 0.0), (0.0, -1.0, 0.0),
            [(head_y - 0.02, LIFT_HEAD_Z - 0.34), (head_y - 0.86, LIFT_HEAD_Z - 1.16),
             (head_y - 0.86, LIFT_HEAD_Z - 1.40), (head_y - 0.02, LIFT_HEAD_Z - 0.58)],
            LIFT_W - 0.22, K.mat("stair"))


def _check_hopper(bx1):
    """A hopper is only visible if its walls are STEEPER than the view ray.

    The camera gains one unit of z per unit travelled toward -Y, so a face that insets one
    unit horizontally per unit it drops is parallel to the ray and has zero screen area. The
    first single-hopper pass measured 0.97 on the -Y wall and 0.90 on the +X wall: the
    geometry was built, correctly, at the right size, and rendered as nothing at all. Neither
    a render nor `validate()` says anything about this — the object is present, unoccluded and
    invisible — so it is asserted here."""
    drop = (BAG_Z0 + 0.03) - HOP_Z
    tx, ty = _hopper_throat(bx1)
    ry = ((BAG_Y1 - BAG_Y0) / 2 - ty / 2) / drop
    rx = ((bx1 - BAG_X0) / 2 - tx / 2) / drop
    line = ("  hopper throat %.2f x %.2f; wall inset/drop -Y %.2f +X %.2f (max %.2f)"
            % (tx, ty, ry, rx, HOP_MAX_RATIO))
    if max(ry, rx) > HOP_MAX_RATIO:
        raise RuntimeError("EAF hopper is edge-on to the camera (%.2f). Deepen it (lower "
                           "HOP_Z / raise BAG_Z0), widen HOP_THROAT, or shrink the box."
                           % max(ry, rx))
    return line


def _bowl(K, name, cx, cy, rim_z, r, rise, wall, mat, rim_mat=None, seg=32, rings=9):
    """Open half-ellipsoid BOWL with a real wall thickness: outer shell, inner shell, and an
    annulus closing the rim between them.

    It must NOT be capped. dome_cap's n-gon cap is right for a tank lid and fatal here — the
    first version borrowed it and the disc sat straight over the melt, so the bath rendered
    as a dull metal plate and looked exactly like a bath that had not been built. An open
    vessel also needs the inner surface to be real geometry rather than the outer shell's
    backface, or the lip has no thickness and the pool has nothing to sit inside."""
    import bpy, bmesh
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()

    def shell(rad, ris):
        g = []
        for i in range(rings + 1):
            t = (math.pi / 2.0) * i / rings
            rr, dz = rad * math.cos(t), ris * math.sin(t)   # dz measured DOWN from the rim
            g.append([bm.verts.new((cx + rr * math.cos(2 * math.pi * j / seg),
                                    cy + rr * math.sin(2 * math.pi * j / seg),
                                    rim_z - dz)) for j in range(seg)])
        return g

    out, inn = shell(r, rise), shell(r - wall, rise - wall)
    for g in (out, inn):
        for i in range(rings):
            for j in range(seg):
                k = (j + 1) % seg
                bm.faces.new([g[i][j], g[i][k], g[i + 1][k], g[i + 1][j]])
    for j in range(seg):                                    # rim annulus
        k = (j + 1) % seg
        bm.faces.new([out[0][j], out[0][k], inn[0][k], inn[0][j]])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me); bm.free()
    ob = K.obj(name, me, mat, True)
    if rim_mat is not None:
        # The hot lip is a material SLOT on the rim annulus, not a band object. A cylinder
        # used as a band caps itself: the first version put a heat_red cyl at the rim and its
        # solid top face lidded the whole vessel, so the bath rendered as a flat red plate.
        # Slots also land un-inked, which is what a painted zone should do.
        ob.data.materials.append(rim_mat)
        for poly in ob.data.polygons[-seg:]:
            poly.material_index = 1
            poly.use_smooth = False
    return ob


def build_eaf(level: int = 2) -> dict:
    p = EAF_LEVELS[level]
    # PAN the camera, do not rescale it. `ortho_scale` and the rotation are the shared style
    # contract and must stay 11.0 / true iso so the whole set keeps one scale; `target` only
    # slides the frame, and the export crops to the alpha box regardless. L3's content is
    # 900 px inside a 1024 frame, so its right edge clipping was never a size problem — the
    # composition had simply grown rightward and downward of the default target.
    setup_rig(target=(0.47, 1.02, 3.24))
    K = Kit(open_collection("BLDG_eaf"))

    FY1 = p["hall_y1"]
    EAVE = _solve_eave()
    RIDGE = EAVE + RIDGE_RISE
    YC = (FY0 + FY1) / 2.0
    XC = (HX0 + HX1) / 2.0

    report = _check_sightlines(EAVE)
    if p["bag"]:
        report.append(_check_hopper(p["bag_x1"]))
    if p["chute"]:
        report.append(_lift_incline(BAG_Y1 - 0.62))

    # ---------------- melt shop ----------------
    # Pale walls: the hall is the largest surface in the sprite and it is the composition's
    # LIGHT tier — the ember has to have something to be bright against, and a dark shed
    # would put the two biggest masses (shed and bowl) in the same value band. MEASURED on
    # the first pass: chalk walls came out L131 against an L109 roof, a 22-luma spread that
    # read as one mass. white_wall lands ~L171, which with the L109 roof, the L140 bag house
    # and the L80 plinth gives the four tiers ~90 luma of range to work in.
    wall = K.mat("wall_bright")
    for tag, (cx, cy, sx, sy) in {
        "back":  (XC, FY1, HX1 - HX0, WALL_T),
        "left":  (HX0, (FY0 + FY1) / 2, WALL_T, FY1 - FY0),
        "right": (HX1, (FY0 + FY1) / 2, WALL_T, FY1 - FY0),
    }.items():
        K.box("shop_%s" % tag, cx, cy, EAVE / 2.0, sx, sy, EAVE, wall)

    # FRONT: two narrow returns and nothing between them. A portal frame, not a wall with a
    # hole — the returns and the fascia read as structure framing the bath, which is a better
    # graphic than an opening cut in a plane, and it is what a charging aisle actually is.
    for tag, (x0, x1) in {"fl": (HX0, PORTAL[0]), "fr": (PORTAL[1], HX1)}.items():
        K.box("shop_%s" % tag, (x0 + x1) / 2, FY0, EAVE / 2.0,
              x1 - x0, WALL_T, EAVE, wall)
    # The fascia IS the opening's head member — _check_sightlines is run against `EAVE`.
    K.box("shop_fascia", XC, FY0, EAVE + FASCIA / 2.0, HX1 - HX0 + 0.10, WALL_T + 0.06,
          FASCIA, K.mat("stair"))

    # Roof: two slopes. Rotating a Y-long box about X by +angle ramps UPHILL toward +Y.
    ang = math.degrees(math.atan2(RIDGE_RISE, YC - FY0))
    slope = math.hypot(YC - FY0, RIDGE_RISE)
    for tag, (cy, sgn) in {"f": ((FY0 + YC) / 2, 1.0), "b": ((YC + FY1) / 2, -1.0)}.items():
        K.rotbox("shop_roof_%s" % tag, XC, cy, (EAVE + RIDGE) / 2.0,
                 HX1 - HX0 + 0.22, slope, 0.16, K.mat("roof_deck"), 'X', sgn * ang)
    K.box("shop_monitor", XC, YC, RIDGE + 0.22, HX1 - HX0 - 0.70, 0.50, 0.44, wall)
    # The monitor's slot used to be `opening` (ink_black, 0.028) at 0.24 tall — the darkest
    # thing in the sprite, sitting alone on an otherwise empty L1 roof, where it read as a
    # foreign black object rather than as a vent. Standard `window_glass`, and thinner.
    for sgn in (-1, 1):
        K.box("shop_mon_louvre%d" % (sgn > 0), XC, YC + sgn * 0.255, RIDGE + 0.17,
              HX1 - HX0 - 0.86, 0.03, 0.11, K.mat("window_glass"))
    K.box("shop_mon_roof", XC, YC, RIDGE + 0.47, HX1 - HX0 - 0.56, 0.64, 0.10,
          K.mat("roof_deck"))
    K.box("shop_ridge", XC, YC, RIDGE + 0.06, HX1 - HX0 + 0.26, 0.16, 0.12, K.mat("stair"))
    # Gable ends: a TRIANGLE is convex, so prism's n-gon cap is safe here (a chevron roof
    # band would not be — that is the concave-outline trap that filled the quay solid).
    for tag, gx in {"l": HX0, "r": HX1}.items():
        K.prism("shop_gable_%s" % tag, (gx, 0.0, 0.0), (0.0, 1.0, 0.0),
                [(FY0, EAVE), (YC, RIDGE), (FY1, EAVE)], WALL_T, wall)

    # Two thick verticals against the BACK wall, standing a little proud of it. A pipe applied
    # to that wall would be invisible — the +Y face points away from this camera — so what
    # makes them read is breaking the ROOFLINE, which is a screen-height test, not a world one.
    # IDENTICAL pipes, same y, same length. They were already the same distance from the wall
    # — both at y = 3.78 — and levelling their CROWNS was what made them read as though they
    # were not: it forced the right one to be 0.52 longer, and the eye takes a longer stack as
    # a nearer one. Two identical objects on a wall running along X must step in screen height
    # (by dx/2), and that step IS the perspective; faking it flat is what looked wrong.
    #
    # Length is still derived from the roofline, off the LOWER crown — the right-hand pipe.
    pipe_y = FY1 + BACK_PIPE_Y_OFF
    mon_screen = (RIDGE + 0.47) - (XC - YC) / 2.0
    x_lo = BX + BACK_PIPE_DX / 2                    # largest x -> lowest crown on screen
    base_top = mon_screen + BACK_PIPE_CLEAR + (x_lo - pipe_y) / 2.0
    ptop = 0.30 + (base_top - 0.30) * BACK_PIPE_SCALE
    pipes = [(px_, ptop) for px_ in (BX - BACK_PIPE_DX / 2, x_lo)]
    for k, (px_, ptop) in enumerate(pipes):
        K.cyl("back_pipe%d" % k, px_, pipe_y, (0.30 + ptop) / 2.0, 0.27, ptop - 0.30,
              K.mat("duct"), segments=24, smooth=True)
        K.cyl("back_pipe%d_cap" % k, px_, pipe_y, ptop + 0.07, 0.30, 0.14,
              K.mat("opening"), segments=24)
        for sz in (1.30, 2.60, 3.90):
            K.seam("back_pipe%d_s%d" % (k, int(sz * 10)), px_, pipe_y, sz, 0.278)
        for bz in (1.60, 3.30):     # braced back to the wall, equally
            K.box("back_pipe%d_br%d" % (k, int(bz * 10)), px_, (pipe_y + FY1) / 2.0, bz,
                  0.10, pipe_y - FY1 + 0.16, 0.10, K.mat("stair"))
    for bz in (1.60, 3.30):
        K.box("back_pipe_tie%d" % int(bz * 10), BX, pipe_y, bz, BACK_PIPE_DX, 0.09, 0.09,
              K.mat("stair"))

    K.door("shop_door", "-Y", ((HX0 + PORTAL[0]) / 2 + 0.02, FY0, 0.52), 0.44, 1.04)
    K.window("shop_w0", "-Y", ((HX0 + PORTAL[0]) / 2 + 0.02, FY0, 1.95), 0.34, 0.58)
    K.window("shop_w1", "+X", (HX1, FY1 - 0.62, 2.55), 0.34, 0.58)

    # ---------------- plinth, bowl, melt ----------------
    K.box("plinth", BX, BY, PLINTH_TOP / 2.0, PLINTH_XY, PLINTH_XY, PLINTH_TOP,
          K.mat("yard"))
    K.box("plinth_top", BX, BY, PLINTH_TOP + 0.012, PLINTH_XY - 0.10, PLINTH_XY - 0.10,
          0.05, K.mat("gear"))

    _bowl(K, "bowl", BX, BY, RIM_Z, BOWL_R, BOWL_RISE, BOWL_WALL, K.mat("wall_grey"),
          rim_mat=K.mat("hot"))
    # A heat_red COLLAR around the outside, below the rim: an annulus, so it has no cap to
    # bury the bath with. Its inner radius is set inside the shell at that depth so it bites
    # into the surface rather than floating off it.
    d = 0.30
    r_at = BOWL_R * math.sqrt(max(0.0, 1.0 - (d / BOWL_RISE) ** 2))
    K.washer("bowl_collar", (BX, BY, RIM_Z - d), (0, 0, 1), r_at - 0.05, r_at + 0.055, 0.11,
             K.mat("hot"))
    # Support pedestal + trunnions instead of rocker rails: a rail's section (concave top,
    # flat bottom) is non-convex, and prism/poly_prism fill a concave outline solid.
    K.cyl("bowl_pedestal", BX, BY, (PLINTH_TOP + RIM_Z - BOWL_RISE) / 2.0,
          BOWL_R * 0.36, (RIM_Z - BOWL_RISE) - PLINTH_TOP + 0.16, K.mat("stair"), segments=24)
    for sgn in (-1, 1):
        K.cyl("bowl_trunnion%d" % (sgn > 0), BX + sgn * (BOWL_R * 0.80), BY,
              RIM_Z - BOWL_RISE * 0.55, 0.105, 0.36, K.mat("stair"), axis='X', segments=16)

    # ---- induction coil round the bowl: hot at the top, cold at the bottom ----
    # Rings rather than a true helix: at this scale the two are indistinguishable, and a
    # helix's start/end seam would need covering. The RAMP is the point — five tones from a
    # dim red glow down to near-black, which is what says "heated from above".
    coil_z = (1.48, 1.26, 1.04, 0.86, 0.72)
    coil_mats = [_coil_glow_mat(), K.tone(K.mat("hot"), 1.35, "c1"),
                 K.tone(K.mat("hot"), 0.90, "c2"), K.tone(K.mat("hot"), 0.58, "c3"),
                 K.tone(K.mat("hot"), 0.34, "c4")]
    for k, cz in enumerate(coil_z):
        rr = _shell_r(cz)
        K.washer("coil%d" % k, (BX, BY, cz), (0, 0, 1), rr - 0.03, rr + 0.075, 0.105,
                 coil_mats[k])
    # Feed bar from the coil's hot end back to the shed wall.
    cr = _shell_r(coil_z[0])
    K.box("coil_bar", BX, (BY + cr + FY1 - 0.10) / 2.0, coil_z[0],
          0.155, (FY1 - 0.10) - (BY + cr), 0.155, K.mat("gear"))
    K.box("coil_bar_joint", BX, BY + cr + 0.10, coil_z[0], 0.23, 0.26, 0.23,
          K.mat("busbar"))

    melt_z = RIM_Z - MELT_DROP
    rm = _melt_radius()
    K.cyl("melt", BX, BY, melt_z, rm, 0.05, _melt_mat(), segments=32)
    # A thin lining ring between melt and shell: without it the ember meets the grey shell on
    # a single edge and the bath reads as a painted disc rather than as a pool inside a lip.
    K.washer("melt_lining", (BX, BY, melt_z - 0.008), (0, 0, 1), rm - 0.075, rm + 0.085,
             0.042, K.mat("hot"))

    # ---------------- electrodes ----------------
    # Plain rods, constant radius, FLAT n-gon caps (kit rule 6 for a deliberate round form).
    # The bottoms are SUNK below the melt surface so the ember disc draws over the cut: a rod
    # ending flush with the liquid is two coplanar faces and z-fights into a smear.
    for i in range(3):
        rx, ry = _rod_xy(i)
        z0 = melt_z - ROD_SUBMERGE
        z1 = ROD_TOPS[i]
        K.cyl("rod%d" % i, rx, ry, (z0 + z1) / 2.0, ROD_R, z1 - z0,
              K.mat("opening"), segments=24, smooth=True)
        # The clamp and the two rings under it are the busbars WRAPPED on the rod, so they
        # are copper, not the silver the pipework uses.
        K.cyl("rod%d_clamp" % i, rx, ry, z1 - 0.30, ROD_R + 0.055, 0.21,
              K.mat("busbar"), segments=24)
        for w, dz in enumerate((0.46, 0.60)):
            K.cyl("rod%d_wrap%d" % (i, w), rx, ry, z1 - dz, ROD_R + 0.036, 0.075,
                  K.mat("busbar"), segments=24)
        # The arm runs back to the beam, so its LENGTH is whatever that distance is — the
        # three differ, because the rods sit on a triangle. Both ends get a collar a size
        # bigger than the member: a bar meeting a bar at its own section reads as a drawing
        # error, and the thickening is what says the joint is carrying something.
        arm_y1 = BY + BEAM_DY
        az = z1 - 0.295
        K.box("rod%d_arm" % i, rx, (ry + arm_y1) / 2.0, az, 0.095, arm_y1 - ry, 0.115,
              K.mat("stair"))
        for tag, jy in (("a", ry + 0.02), ("b", arm_y1 - 0.10)):
            K.box("rod%d_joint%s" % (i, tag), rx, jy, az, JOINT, 0.26, JOINT,
                  K.mat("gear"))
            K.seam_bar("rod%d_jseam%s" % (i, tag), rx, jy, az, JOINT + 0.02, 0.03,
                       JOINT + 0.02)

    # ---------------- busbars -> bus duct -> transformer ----------------
    if p["elec"]:
        # Each rod's bar runs +X, then -Y, then straight DOWN onto its own bushing: three
        # right-angled L-runs. Angled members converging on a point read as acute scribble at
        # this scale (kit rule 6), and a bar that turns square reads as switchgear.
        # ORDER MATTERS. Running -X first would take the bars out past the shop's left wall
        # while they are still deep in +Y, and at this camera anything to the left of the
        # building at a shared column sits BEHIND it — they would vanish. Forward first
        # (out through the open portal, where they read), THEN left, then down.
        for i in range(3):
            rx, ry = _rod_xy(i)
            cz = ROD_TOPS[i] - 0.30
            bx_ = XFMR_XY[0] + (i - 1) * 0.14 * XFMR_S
            K.box("bus_y%d" % i, rx, (ry + XFMR_XY[1]) / 2.0, cz, 0.055,
                  ry - XFMR_XY[1], 0.105, K.mat("busbar"))
            K.box("bus_x%d" % i, (rx + bx_) / 2.0, XFMR_XY[1], cz, rx - bx_, 0.105, 0.055,
                  K.mat("busbar"))
            K.box("bus_d%d" % i, bx_, XFMR_XY[1], (cz + BUS_DROP_Z) / 2.0, 0.105, 0.055,
                  cz - BUS_DROP_Z, K.mat("busbar"))
        # No wall bead any more: with the transformer inside, none of the three runs leaves
        # the building.
        K.transformer("xfmr", XFMR_XY[0], XFMR_XY[1], 0.0, s=XFMR_S)
        # FINE_INK is a decision about SIZE, not about what a thing is. `transformer` opts
        # itself in because a yard transformer is small enough for a 2.4 px line to swallow;
        # at 3x it is the size of a building and the 1.05 px line leaves it looking unfinished
        # beside the shop. Pull it back out into the main lineset.
        fine = bpy.data.collections.get("FINE_INK")
        if fine is not None:
            for ob in list(fine.objects):
                if ob.name.startswith("xfmr"):
                    fine.objects.unlink(ob)
        # Busbar SUPPORTS: a post per run of bars, with black rubber-block holders. The three
        # bars sit at their own rods' clamp heights, so the holders climb the post rather than
        # sharing a crossarm.
        # ONE support only. The second post sat at x=-1.55, inside the transformer's own
        # footprint (x -3.25..-1.25, y -1.59..-0.11), so it was a pillar standing through a
        # machine.
        for k, sx_ in enumerate((-0.45,)):
            zs = sorted(ROD_TOPS[i] - 0.30 for i in range(3))
            K.box("bussup%d_post" % k, sx_, XFMR_XY[1], (zs[-1] + 0.18) / 2.0, 0.17, 0.17,
                  zs[-1] + 0.18, K.mat("stair"))
            K.box("bussup%d_base" % k, sx_, XFMR_XY[1], 0.07, 0.42, 0.42, 0.14,
                  K.mat("yard"))
            for j, hz in enumerate(zs):
                K.box("bussup%d_rub%d" % (k, j), sx_, XFMR_XY[1], hz, 0.30, 0.24, 0.20,
                      K.mat("opening"))
                K.box("bussup%d_cap%d" % (k, j), sx_, XFMR_XY[1], hz + 0.115, 0.34, 0.28,
                      0.05, K.mat("gear"))

    # A FLOOR. Without one the open portal shows straight through to the transparent film,
    # so the inside of the building rendered as a void — and the glow pools sat on nothing.
    # `yard_pad`, not raw `concrete`. concrete is 0.56 and the walls are white_wall at 0.52 —
    # a floor plate that size at that value renders as a blank sheet the same tone as the
    # walls behind it, which is the exact failure the palette note warns about. `pad` is the
    # switchyard concrete, tuned to sit between pale walls and dark decks.
    K.box("shop_floor", XC, (FY0 + FY1) / 2.0, -0.04, HX1 - HX0 - 0.04, FY1 - FY0 - 0.04,
          0.10, K.mat("yard_pad"))

    # ---------------- amber spill from the back ----------------
    # A lit opening in the back wall plus a wash on the floor in front of it: the shop reads
    # as one bay of several. Both are placed to sit UNDER the portal head — the panel's own
    # crossing is z + 3.16, so it can only be about 1.2 tall before its top is cut, and a
    # taller one would simply be a rectangle nobody sees the top of.
    # TWO lit openings, not one wash. The first attempt put an emissive slab on the floor and
    # a wide panel on the wall; between the bowl and the plinth only a strip of each survived,
    # and a strip of emissive is a glowing BAR, not a glow. Openings read as openings because
    # they have a dark reveal around them and a pool of light on the floor in front.
    # DOOR-SHAPED, and both to the RIGHT of the rail's screen columns. Two earlier attempts
    # failed for different reasons and both are worth keeping straight:
    #  * a floor wash plus a wide wall panel — deep in +Y a floor patch appears HIGH on
    #    screen, so it read as an orange rectangle floating in mid-air, not as light on a
    #    floor. The pools are gone.
    #  * openings at BX-1.15 sat in the rail's columns (-1.29 to 4.03) and the rail, being
    #    far nearer the camera, simply covered them. Past column 4.03 they are clear.
    gm = _glow_mat()
    wy = FY1 - WALL_T / 2 - 0.02
    for k, ox in enumerate((BX + 0.65, BX + 1.65)):
        K.box("glow_reveal%d" % k, ox, wy - 0.03, 0.57, 0.78, 0.05, 1.22, K.mat("opening"))
        K.box("glow_panel%d" % k, ox, wy, 0.55, 0.62, 0.05, 1.08, gm)

    # ---------------- the arm beam ----------------
    # One thick member across the back of the bay carrying all three arms. It is DEEP in z
    # (0.86) rather than a bar at one level: the arms hang at their own rods' clamp heights,
    # which differ by 0.45, and a single-level bar could only ever meet one of them.
    beam_y = BY + BEAM_DY
    rail_x0, rail_x1 = HX0 + WALL_T / 2, HX1 - WALL_T / 2
    K.box("arm_beam", (rail_x0 + rail_x1) / 2.0, beam_y, (BEAM_Z0 + BEAM_Z1) / 2.0,
          rail_x1 - rail_x0, BEAM_SY, BEAM_Z1 - BEAM_Z0, K.mat("wall_grey"))
    K.gloss(bpy.data.objects["arm_beam"], dark=0.62, light=1.35)
    for sgn, ex in ((-1, rail_x0), (1, rail_x1)):   # end brackets into the side walls
        K.box("arm_beam_end%d" % (sgn > 0), ex, beam_y, (BEAM_Z0 + BEAM_Z1) / 2.0,
              0.12, BEAM_SY + 0.14, BEAM_Z1 - BEAM_Z0 + 0.14, K.mat("gear"))
    # A PARKED CARRIAGE on the free length. Without it the rail's right half is a bare bar
    # running from the bowl to the wall — which is exactly what it was mistaken for.
    park_x = (max(_rod_xy(i)[0] for i in range(3)) + rail_x1) / 2.0 + 0.25
    K.box("rail_carriage", park_x, beam_y, BEAM_Z1 - 0.10, 0.44, BEAM_SY + 0.22, 0.36,
          K.mat("gear"))
    K.box("rail_carriage_arm", park_x, beam_y - BEAM_SY / 2 - 0.30, BEAM_Z1 - 0.62,
          0.13, 0.62, 0.13, K.mat("stair"))
    K.box("rail_carriage_joint", park_x, beam_y - BEAM_SY / 2 - 0.06, BEAM_Z1 - 0.62,
          JOINT, 0.26, JOINT, K.mat("gear"))
    # A running edge along the rail's face reads as the track the carriages travel on.
    for rz in (BEAM_Z0 + 0.14, BEAM_Z1 - 0.14):
        K.box("arm_beam_track%d" % int(rz * 10), (rail_x0 + rail_x1) / 2.0,
              beam_y - BEAM_SY / 2 - 0.025, rz, rail_x1 - rail_x0 - 0.20, 0.05, 0.09,
              K.mat("stair"))

    # ---------------- canopy hood + duct ----------------
    hx, hy = HOOD_XY
    K.box("hood", hx, hy, DUCT_Z, 1.45, 0.66, 0.26, K.mat("duct"))
    # Throat: a wedge dropping from the hood's front lip toward the bath. prism's profile is
    # a TRIANGLE here, which is convex, so its n-gon caps are safe.
    K.prism("hood_throat", (hx - 0.725, 0.0, 0.0), (0.0, 1.0, 0.0),
            [(hy - 0.33, DUCT_Z - 0.13), (hy + 0.33, DUCT_Z - 0.13),
             (hy + 0.33, DUCT_Z - 0.62)], 1.45, K.mat("duct"))
    for sgn in (-1, 1):     # hangers back to the shop frame
        K.box("hood_hang%d" % (sgn > 0), hx + sgn * 0.62, hy + 0.30, DUCT_Z + 0.52,
              0.08, 0.08, 1.00, K.mat("stair"))
    if p["bag"]:
        # The filter plant now sits further back, so the run turns: out through the flank in
        # +X, then +Y into its front face. Right angles, per the junction rule — a diagonal
        # shortcut between the two reads as an acute scribble at this scale.
        # The transformer now stands in the duct's old path and is 3.21 tall, so the run
        # LIFTS over it before turning: up at the hood, across high, then -Y into the
        # vessel. Right angles throughout — a diagonal shortcut reads as acute scribble here.
        K.pipe_run("duct", [(HOOD_XY[0] + 0.62, HOOD_XY[1], DUCT_Z),
                            (HOOD_XY[0] + 0.62, HOOD_XY[1], DUCT_RUN_Z),
                            (BAG_X0 + 0.14, HOOD_XY[1], DUCT_RUN_Z),
                            (BAG_X0 + 0.14, BAG_Y1 - 0.25, DUCT_RUN_Z)], 0.24, K.mat("duct"))
        # The duct pierces the shop's +X wall: Freestyle cannot ink a face intersection, so
        # the penetration needs an explicit collar or the pipe reads as passing through.
        K.pipe_end("duct_collar", (HX1, HOOD_XY[1], DUCT_Z), (1, 0, 0), 0.24, "collar")
    else:
        # L1 has no filter plant, so its fume goes back to the pipes at the wall. It used to
        # have its own stack at (2.35, 1.17) rising to 4.75 — which, once the eave was solved
        # down to 4.37, sat entirely UNDER the roof at that point (4.79) and pushed only its
        # black cap through the slope. The back pipes already give L1 its verticals.
        K.pipe_run("duct", [(HOOD_XY[0] + 0.62, HOOD_XY[1], DUCT_Z),
                            (HOOD_XY[0] + 0.62, HOOD_XY[1], DUCT_RUN_Z),
                            (HOOD_XY[0] + 0.62, FY1 - 0.22, DUCT_RUN_Z)], 0.24, K.mat("duct"))
        K.pipe_end("duct_collar", (HOOD_XY[0] + 0.62, FY1 - WALL_T / 2, DUCT_RUN_Z), (0, 1, 0),
                   0.24, "collar")

    # ---------------- bag house ----------------
    if p["bag"]:
        bx0, bx1, by0, by1 = BAG_X0, p["bag_x1"], BAG_Y0, BAG_Y1
        K.box("bag", (bx0 + bx1) / 2, (by0 + by1) / 2, (BAG_Z0 + BAG_Z1) / 2,
              bx1 - bx0, by1 - by0, BAG_Z1 - BAG_Z0, K.mat("flue"))
        for k in range(7):                      # cladding ribs, as proud strips
            rx = bx0 + (bx1 - bx0) * (k + 0.5) / 7
            K.box("bag_rib%d" % k, rx, by0 - 0.012, (BAG_Z0 + BAG_Z1) / 2, 0.07,
                  0.03, BAG_Z1 - BAG_Z0 - 0.10, K.mat("gear"))
        K.box("bag_lid", (bx0 + bx1) / 2, (by0 + by1) / 2, BAG_Z1 + 0.05,
              bx1 - bx0 + 0.10, by1 - by0 + 0.10, 0.10, K.mat("roof_deck"))
        # ONE central hopper: an inverted pyramid receding on all four sides, discharging
        # into the ground through a rectangular downpipe. Two earlier shapes failed here and
        # both failed the same way — they did not continue the vessel. A 2x2 grid of inset
        # `sqcol` pyramids read as splayed legs (the box overhung them on a shelf and the gaps
        # between them read as daylight); a pair of troughs fixed the shelf but still left the
        # thing standing in mid-air on stilts. A single frustum from the FULL footprint has no
        # step to give the game away, and a pipe running into the ground closes the bottom of
        # the composition instead of leaving it open.
        tx_, ty_ = _hopper_throat(bx1)
        _frustum(K, "bag_hopper", bx0, bx1, by0, by1, BAG_Z0 + 0.03, HOP_Z,
                 tx_, ty_, K.mat("flue"))
        K.box("bag_downpipe", (bx0 + bx1) / 2.0, (by0 + by1) / 2.0, HOP_Z / 2.0,
              tx_ - 0.04, ty_ - 0.04, HOP_Z + 0.04, K.mat("gear"))
        K.seam_bar("bag_dp_seam", (bx0 + bx1) / 2.0, (by0 + by1) / 2.0, HOP_Z - 0.02,
                   tx_ + 0.02, ty_ + 0.02, 0.035)
        # ...and the whole vessel stands on a FRAME, which is what says "supported" rather
        # than "standing on its own feet".
        for sx_ in (bx0 + 0.13, bx1 - 0.13):
            for sy_ in (by0 + 0.13, by1 - 0.13):
                K.box("bag_col%d_%d" % (sx_ > bx0 + 0.5, sy_ > by0 + 0.5), sx_, sy_,
                      (BAG_Z0 - 0.03) / 2.0, 0.20, 0.20, BAG_Z0 - 0.03, K.mat("stair"))
        for tag, (cy_, sy_) in {"f": (by0 + 0.13, 0.14), "b": (by1 - 0.13, 0.14)}.items():
            K.box("bag_beam_%s" % tag, (bx0 + bx1) / 2.0, cy_, BAG_Z0 - 0.10,
                  bx1 - bx0 - 0.10, sy_, 0.16, K.mat("stair"))

        # ---- L3: loading chute + enclosed diagonal lift ----
        if p["chute"]:
            ccx, ccy = (bx0 + bx1) / 2.0 - 0.20, BAG_Y1 - 0.62
            # The chute is an UPRIGHT frustum — wide mouth at the top, narrow throat into the
            # lid — i.e. the hopper's shape the other way up, which is what makes the pair
            # read as "in at the top, out at the bottom" rather than as two unrelated cones.
            _frustum(K, "chute", ccx - 0.54, ccx + 0.54, ccy - 0.50, ccy + 0.50,
                     BAG_Z1 + 0.62, BAG_Z1 + 0.10, 0.42, 0.38, K.mat("gear"))
            # THE HOLE. A frustum is an open funnel, so what the camera sees inside it is the
            # far inner wall — lit, and the same tone as the outside, which is why it read as
            # a solid lump. A second frustum just inside it in ink_black gives the mouth a
            # dark interior; inset by 0.05 so the rim still reads as a rim.
            _frustum(K, "chute_bore", ccx - 0.49, ccx + 0.49, ccy - 0.45, ccy + 0.45,
                     BAG_Z1 + 0.585, BAG_Z1 + 0.10, 0.36, 0.32, K.mat("opening"))
            K.seam_bar("chute_seam", ccx, ccy, BAG_Z1 + 0.12, 0.46, 0.42, 0.04)
            _lift(K, ccx, ccy)
    # ---------------- ladle + tap ----------------
    if p["ladle"]:
        lx, ly = 1.35, -0.95
        K.cyl("ladle", lx, ly, 0.46, 0.40, 0.92, K.mat("wall_grey"), segments=24, smooth=True)
        K.cyl("ladle_band", lx, ly, 0.80, 0.425, 0.10, K.mat("hot"), segments=24)
        K.cyl("ladle_melt", lx, ly, 0.905, 0.355, 0.04, K.M["ember"], segments=24)
        for sgn in (-1, 1):
            K.cyl("ladle_lug%d" % (sgn > 0), lx + sgn * 0.41, ly, 0.72, 0.075, 0.20,
                  K.mat("stair"), axis='X', segments=12)

    # ---------------- L3: caster annex ----------------
    if p["caster"]:
        cx0, cx1, cy0, cy1 = CASTER
        K.box("caster", (cx0 + cx1) / 2, (cy0 + cy1) / 2, 0.85, cx1 - cx0, cy1 - cy0, 1.70,
              K.mat("wall_grey"))
        K.box("caster_roof", (cx0 + cx1) / 2, (cy0 + cy1) / 2, 1.76, cx1 - cx0 + 0.12,
              cy1 - cy0 + 0.12, 0.12, K.mat("roof_deck"))
        # The strand: a glowing bar running out of the annex on rollers. The one place a
        # second ember is allowed, because it is the product of the first one.
        K.box("strand", (cx0 + cx1) / 2 + 0.30, cy0 - 0.55, 0.46, 1.55, 0.26, 0.08,
              K.M["ember"])
        for k in range(5):
            K.cyl("roller%d" % k, (cx0 + cx1) / 2 - 0.42 + k * 0.36, cy0 - 0.55, 0.36,
                  0.085, 0.34, K.mat("stair"), axis='Y', segments=12)
        K.roll_stack("coil", cx1 + 0.62, 0.0, -0.05, 0.62, r=0.19, cols=3, rows=2)

    print("\n".join(["SIGHTLINES:"] + report))
    print("\n".join(K.validate(ground=0.0)))
    return {"building": "eaf", "level": level, "objects": len(K.col.objects),
            "eave": EAVE, "melt_r": round(rm, 3)}
