# Parametric builder for the DOCKS sprite — the seaport the whole economy ships through.
# Run AFTER sprite_kit.py:
#   exec(open(".../sprite_kit.py").read())
#   exec(open(".../docks_builder.py").read()); build_docks()
#
# ONE sprite, no levels. This is the biggest thing in the set, so it gets a wider ortho
# scale than the plants — everything else is a building, this is a piece of coastline.
#
# COMPOSITION (owner): concrete arms wrap an enclosed bay in a C, open at one corner for
# the entrance. Containers cover the NEAR arm, two gantry cranes stand on the FAR arm, two
# ships lie alongside — one oil tanker, one container ship — and a small office sits in the
# corner where the arms meet.
#
# The read at empire-view scale is: BLUE HOLE ringed by grey, with two tall gantries and two
# long hulls. That is why the water is a large flat plane of one tone and the cranes are the
# only things breaking the skyline — every other detail here is texture, not silhouette.
#
# Isometric camera: +X goes down-right, +Y goes up-right. The NEAR arm is therefore the one
# at low x AND low y (nearest the camera), and the FAR arm is at high y. Screen height is
# 0.4082*(y-x) + 0.8165*z, which is what decides what actually occludes what.

import math

# Palette additions must land BEFORE any Kit() is constructed — Kit builds its
# material table from PALETTE at __init__, so adding roles inside build_docks()
# raises KeyError on the first mat() call.
PALETTE["dock_water"] = (0.055, 0.135, 0.190)
PALETTE["dock_water_lo"] = (0.038, 0.100, 0.150)
PALETTE["quay"] = (0.300, 0.295, 0.270)
PALETTE["quay_edge"] = (0.400, 0.392, 0.355)
PALETTE["hull_red"] = (0.300, 0.085, 0.065)
PALETTE["hull_black"] = (0.075, 0.078, 0.090)

QUAY_Z = 0.62                 # deck level of the concrete arms, above the water
WATER_Z = 0.06                # water surface; the bay floor is never seen
ARM_W = 2.30                  # width of each concrete arm
BAY = (-6.40, 6.40, -4.60, 5.20)   # x0, x1, y0, y1 of the OUTER edge of the C
ENTRANCE_W = 3.40             # gap in the near-east corner, where ships come in

# Berths, both inside the bay: the boxship lies along the FAR quay under the
# gantries, the tanker along the near quay. Bay interior is x -4.1..6.4,
# y -2.3..2.9, and a hull that overruns it ends up inside the concrete.
SHIP_BOXER = (-0.40, 1.75, 6.40, 1.35)     # cx, cy, length(X), beam(Y)
SHIP_TANKER = (0.70, -1.30, 6.60, 1.45)


def build_docks() -> dict:
    setup_rig(ortho_scale=17.5, target=(0.0, 0.30, 1.30))
    # Hide every other sprite AND the showcase/stack collections the lineup tooling
    # leaves behind. Hiding only BLDG_* is not enough: SHOWCASE_mine_L1..L3 were still
    # render-enabled and dropped the mine's terraced pit into the middle of the docks.
    for other in bpy.data.collections:
        if other.name == "BLDG_docks":
            continue
        if other.name.startswith(("BLDG_", "SHOWCASE_", "STACK_")):
            other.hide_render = True
            other.hide_viewport = True
    K = Kit(open_collection("BLDG_docks"))

    water, water_lo = K.mat("dock_water"), K.mat("dock_water_lo")
    quay, quay_edge = K.mat("quay"), K.mat("quay_edge")

    x0, x1, y0, y1 = BAY

    # ---------------- water: one flat plane, the hole in the middle ----------------
    # Deliberately larger than the bay and slid under the quay, so no sliver of ground
    # shows between water and concrete at any corner.
    K.box("water", 0.0, 0.3, WATER_Z - 0.05, (x1 - x0) + 1.6, (y1 - y0) + 1.6, 0.10, water)
    for i, (wx, wy, wl) in enumerate(((-1.6, 1.0, 4.6), (2.2, 2.9, 3.4), (0.2, -1.2, 3.0),
                                      (3.4, 0.4, 2.4), (-3.4, -1.8, 2.0))):
        K.box("wake%d" % i, wx, wy, WATER_Z + 0.005, wl, 0.10, 0.01, water_lo)

    # ---------------- the C: three concrete arms ----------------
    # THREE BOXES, not one concave polygon. poly_prism builds the cap as an n-gon and
    # triangulates it, which does not respect a concave boundary — the C came out
    # filled solid and the bay (and both ships in it) vanished under concrete.
    # The west arm is run LONG at both ends so its joints with the other two are
    # buried inside the mass rather than abutting flush, where the crease would ink.
    ix0, iy0, iy1 = x0 + ARM_W, y0 + ARM_W, y1 - ARM_W
    K.box("quay_s", (x0 + x1) / 2, (y0 + iy0) / 2, (QUAY_Z - 0.30) / 2,
          x1 - x0, iy0 - y0, QUAY_Z + 0.30, quay)
    K.box("quay_n", (x0 + x1) / 2, (iy1 + y1) / 2, (QUAY_Z - 0.30) / 2,
          x1 - x0, y1 - iy1, QUAY_Z + 0.30, quay)
    K.box("quay_w", (x0 + ix0) / 2, (iy0 + iy1) / 2, (QUAY_Z - 0.30) / 2,
          ix0 - x0, (iy1 - iy0) + 0.30, QUAY_Z + 0.30, quay)
    # Pale lip along the three edges that face the water, which is what reads as a
    # quay rather than a kerb-less slab.
    K.box("lip_s", (x0 + x1) / 2, iy0 - 0.055, QUAY_Z + 0.005,
          x1 - x0, 0.11, 0.065, quay_edge)
    K.box("lip_n", (x0 + x1) / 2, iy1 + 0.055, QUAY_Z + 0.005,
          x1 - x0, 0.11, 0.065, quay_edge)
    K.box("lip_w", ix0 + 0.055, (iy0 + iy1) / 2, QUAY_Z + 0.005,
          0.11, iy1 - iy0, 0.065, quay_edge)
    # Bollards and fenders along the inner faces — the detail that says "quay" rather
    # than "wall". Fine ink: at 0.09 wide the 2.4px line would be the whole bollard.
    K._fine_mode = True
    inner_n = y1 - ARM_W
    for bx in [x0 + ARM_W + 0.55 + i * 1.25 for i in range(8)]:
        if bx > x1 - ARM_W - 0.3:
            break
        K.cyl("bol_n%d" % int(bx * 10), bx, inner_n - 0.16, QUAY_Z, 0.075, 0.16, quay_edge)
        K.cyl("bol_s%d" % int(bx * 10), bx, y0 + ARM_W + 0.16, QUAY_Z, 0.075, 0.16, quay_edge)
    for by in [y0 + ARM_W + 0.6 + i * 1.2 for i in range(6)]:
        if by > inner_n - 0.3:
            break
        K.cyl("bol_w%d" % int(by * 10), x0 + ARM_W + 0.16, by, QUAY_Z, 0.075, 0.16, quay_edge)
    K._fine_mode = False

    # ---------------- containers: all over the NEAR arm ----------------
    # The near arm is the one the camera looks across, so this is where the colour
    # goes; the far arm is left clear for the gantries to read against the sky.
    box_mats = [K.mat("wall_brick"), K.mat("box_blue"), K.mat("plant_yellow"),
                K.mat("gear"), K.mat("cont_blue")]
    near_y = y0 + ARM_W / 2
    for i, (cx, cy, cols, rows) in enumerate((
            (-5.05, near_y + 0.55, 3, 3), (-2.60, near_y + 0.60, 3, 2),
            (-0.10, near_y + 0.50, 3, 3), (2.35, near_y + 0.58, 3, 2),
            (4.60, near_y + 0.45, 2, 2),
            (-4.10, near_y - 0.62, 2, 1), (-1.20, near_y - 0.66, 3, 1),
            (1.60, near_y - 0.60, 2, 2), (3.90, near_y - 0.64, 2, 1))):
        K.container_stack("cs%d" % i, cx, cy, cols=cols, rows=rows, mats=box_mats)
    # A row on the west arm too, so the C reads as one working yard rather than a
    # decorated front edge.
    for i, (cx, cy) in enumerate(((x0 + ARM_W / 2 + 0.1, -0.9), (x0 + ARM_W / 2 - 0.1, 1.4))):
        K.container_stack("csw%d" % i, cx, cy, cols=2, rows=2, mats=box_mats)

    # ---------------- gantry cranes: two, on the FAR arm ----------------
    # These are the silhouette. They straddle the far quay edge with their booms out
    # over the water, which is the shape that says CONTAINER PORT from a long way off.
    for i, gx in enumerate((-3.10, 2.40)):
        _portal_crane(K, "gc%d" % i, gx, inner_n, QUAY_Z)

    # ---------------- ships ----------------
    _boxship(K, "boxr", *SHIP_BOXER, mats=box_mats)
    _tanker(K, "tank", *SHIP_TANKER)

    # ---------------- office in the corner where the arms meet ----------------
    _office(K, "off", x0 + ARM_W / 2 + 0.05, y1 - ARM_W / 2 - 0.05, QUAY_Z)

    for w in K.validate(ground=-0.35):
        print("VALIDATE:", w)
    lo, hi = K.bounds()
    print("bbox world %.2f x %.2f x %.2f" % (hi[0] - lo[0], hi[1] - lo[1], hi[2] - lo[2]))
    return {"objects": len(K.col.objects)}


def _portal_crane(K, name, cx, quay_y, z):
    """Ship-to-shore gantry: portal legs on the quay, a boom reaching out over the water
    and a short counter-boom inland. Legs are lattice (fine ink) and the boom is a solid
    chord pair, so the two do not merge into one dark mass at sprite scale."""
    steel = K.mat("stair")
    span, legh = 1.90, 3.35
    boom_y = quay_y - 2.75                     # out over the berth, not the whole bay
    back_y = quay_y + 1.35
    for sx in (-1, 1):
        for sy, ly in (("f", quay_y - span / 2), ("b", quay_y + span / 2)):
            K._fine_mode = True
            K.lattice_mast("%s_leg%d%s" % (name, sx > 0, sy), cx + sx * 0.95, ly,
                           z, legh, w=0.20, bays=4, mat=steel)
            K._fine_mode = False
            K.box("%s_sill%d%s" % (name, sx > 0, sy), cx + sx * 0.95, ly, z + 0.10,
                  0.34, 0.34, 0.20, K.mat("darkmetal"))
    # Portal beam across the legs, then the boom running out over the water.
    zt = z + legh
    K.box("%s_portal" % name, cx, quay_y, zt + 0.10, 2.55, span + 0.34, 0.22, steel)
    for tag, yy0, yy1 in (("boom", boom_y, quay_y), ("cboom", quay_y, back_y)):
        for sx in (-1, 1):
            K.box("%s_%s%d" % (name, tag, sx > 0), cx + sx * 0.30,
                  (yy0 + yy1) / 2, zt + 0.30, 0.16, abs(yy1 - yy0), 0.14, steel)
        n = max(3, int(abs(yy1 - yy0) / 0.62))
        for k in range(n):                     # bracing, or the boom reads as a plank
            f0, f1 = k / n, (k + 1) / n
            K.dircyl("%s_%s_br%d%d" % (name, tag, sx > 0, k),
                     (cx, yy0 + (yy1 - yy0) * f0, zt + 0.22),
                     (cx, yy0 + (yy1 - yy0) * f1, zt + 0.42), 0.045, steel, segments=6)
    K.box("%s_apex" % name, cx, quay_y, zt + 0.62, 0.42, 0.42, 0.72, steel)
    K.box("%s_trolley" % name, cx, boom_y + 0.85, zt + 0.16, 0.44, 0.52, 0.16,
          K.mat("darkmetal"))
    K.dircyl("%s_rope" % name, (cx, boom_y + 0.85, zt + 0.10),
             (cx, boom_y + 0.85, z + 0.95), 0.02, K.mat("darkmetal"), segments=6)
    K.box("%s_spreader" % name, cx, boom_y + 0.85, z + 0.80, 0.50, 1.05, 0.16,
          K.mat("hi_vis"))
    K.box("%s_cab" % name, cx - 0.52, quay_y - 0.85, zt + 0.02, 0.34, 0.40, 0.30,
          K.mat("hi_vis"))


def _hull(K, name, cx, cy, length, beam, draft_z, deck_z, mat):
    """Ship hull: a box with the bow drawn to a point. Two tapered end sections rather
    than a curve — at sprite scale the taper is all that survives, and a real curve
    would just cost polygons and blur the ink."""
    K.box("%s_mid" % name, cx, cy, (draft_z + deck_z) / 2, length * 0.62, beam,
          deck_z - draft_z, mat)
    for sx, frac in ((1, 0.19), (-1, 0.19)):
        for k in range(3):
            t0, t1 = k / 3.0, (k + 1) / 3.0
            w = beam * (1.0 - 0.85 * t1) if sx > 0 else beam * (1.0 - 0.55 * t1)
            seg = length * frac / 3.0
            K.box("%s_end%d_%d" % (name, sx > 0, k),
                  cx + sx * (length * 0.31 + seg * (k + 0.5)), cy,
                  (draft_z + deck_z) / 2, seg, max(w, 0.12), deck_z - draft_z, mat)
    K.box("%s_deck" % name, cx, cy, deck_z, length * 0.90, beam * 0.94, 0.06,
          K.mat("deck"))


def _tanker(K, name, cx, cy, length, beam):
    """Oil tanker: long low hull, pipe manifold amidships, house right aft. The read is
    LOW AND LONG with one block at the stern — the opposite of the boxship's stacked mass."""
    draft, deck = WATER_Z - 0.14, WATER_Z + 0.52
    _hull(K, name, cx, cy, length, beam, draft, deck, K.mat("hull_black"))
    K.box("%s_boot" % name, cx, cy, WATER_Z + 0.10, length * 0.90, beam + 0.02, 0.10,
          K.mat("hull_red"))
    K._fine_mode = True
    for i in range(5):                                  # deck pipe run
        K.dircyl("%s_pipe%d" % (name, i),
                 (cx - length * 0.34, cy - 0.22 + i * 0.11, deck + 0.10),
                 (cx + length * 0.30, cy - 0.22 + i * 0.11, deck + 0.10),
                 0.035, K.mat("silver"), segments=8)
    for i in range(4):                                  # tank domes
        K.cyl("%s_dome%d" % (name, i), cx - length * 0.26 + i * length * 0.155, cy,
              deck + 0.06, 0.22, 0.14, K.mat("tank_grey"))
    K._fine_mode = False
    K.box("%s_manifold" % name, cx + 0.15, cy, deck + 0.22, 0.55, beam * 0.75, 0.28,
          K.mat("silver"))
    sx = cx - length * 0.40                             # superstructure, aft
    K.box("%s_house" % name, sx, cy, deck + 0.42, 0.95, beam * 0.82, 0.78,
          K.mat("white_wall"))
    K.box("%s_bridge" % name, sx, cy, deck + 0.90, 1.05, beam * 0.90, 0.20, K.mat("glass"))
    K.box("%s_funnel" % name, sx - 0.42, cy, deck + 1.02, 0.34, 0.40, 0.44,
          K.mat("hull_red"))
    K._fine_mode = True
    K.lattice_mast("%s_mast" % name, cx + length * 0.30, cy, deck, 0.95, w=0.13, bays=3,
                   mat=K.mat("stair"))
    K._fine_mode = False


def _boxship(K, name, cx, cy, length, beam, mats):
    """Container ship: the same hull, loaded high. The stacked deck cargo is the whole
    point of the silhouette, so the boxes go on in a proper block, not a scatter."""
    draft, deck = WATER_Z - 0.14, WATER_Z + 0.56
    _hull(K, name, cx, cy, length, beam, draft, deck, K.mat("hull_black"))
    K.box("%s_boot" % name, cx, cy, WATER_Z + 0.10, length * 0.90, beam + 0.02, 0.10,
          K.mat("hull_red"))
    for r in range(3):
        for c in range(5):
            if r == 2 and c in (0, 4):
                continue
            m = mats[(r * 5 + c) % len(mats)]
            K.box("%s_box%d_%d" % (name, r, c),
                  cx - length * 0.28 + c * length * 0.135, cy,
                  deck + 0.16 + r * 0.30, length * 0.115, beam * 0.86, 0.28, m)
    sx = cx - length * 0.41
    K.box("%s_house" % name, sx, cy, deck + 0.52, 0.85, beam * 0.84, 0.95,
          K.mat("white_wall"))
    K.box("%s_bridge" % name, sx, cy, deck + 1.06, 0.95, beam * 0.92, 0.20, K.mat("glass"))
    K.box("%s_funnel" % name, sx - 0.36, cy, deck + 1.22, 0.30, 0.36, 0.42,
          K.mat("hull_red"))


def _office(K, name, cx, cy, z):
    """Port office: small, two storeys, windows on the two faces the camera can see.
    Deliberately modest — anything bigger competes with the gantries for attention."""
    w, d, h = 1.35, 1.15, 1.30
    K.box("%s_body" % name, cx, cy, z + h / 2, w, d, h, K.mat("chalk"))
    K.box("%s_roof" % name, cx, cy, z + h + 0.04, w + 0.10, d + 0.10, 0.08, K.mat("deck"))
    for f in range(2):
        zc = z + 0.34 + f * 0.52
        for i in range(3):
            K.window("%s_wS%d_%d" % (name, f, i), "-Y",
                     (cx - 0.42 + i * 0.42, cy - d / 2, zc), 0.26, 0.30, 1, 1)
        for i in range(2):
            K.window("%s_wE%d_%d" % (name, f, i), "+X",
                     (cx + w / 2, cy - 0.26 + i * 0.42, zc), 0.26, 0.30, 1, 1)
    K.box("%s_door" % name, cx + 0.30, cy - d / 2 - 0.01, z + 0.28, 0.30, 0.05, 0.56,
          K.mat("door"))
