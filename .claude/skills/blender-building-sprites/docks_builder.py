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
PALETTE["gantry_green"] = (0.080, 0.240, 0.135)
PALETTE["gantry_green_lo"] = (0.050, 0.165, 0.095)

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


def _lift(K, dz, fn, *args, **kwargs):
    """Run a Kit helper, then raise whatever it just made by dz.

    Kit.container_stack (and friends) build from z=0 with no z argument, so on a
    0.62 quay every stack stood half-sunk in the concrete. Rather than change a
    shared kit signature, record the collection before and after and translate the
    difference."""
    before = {ob.name for ob in K.col.objects}
    out = fn(*args, **kwargs)
    for ob in K.col.objects:
        if ob.name not in before:
            for v in ob.data.vertices:
                v.co.z += dz
    return out


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
        _lift(K, QUAY_Z, K.container_stack, "cs%d" % i, cx, cy,
              cols=cols, rows=rows, mats=box_mats)
    # A row on the west arm too, so the C reads as one working yard rather than a
    # decorated front edge.
    for i, (cx, cy) in enumerate(((x0 + ARM_W / 2 + 0.1, -0.9), (x0 + ARM_W / 2 - 0.1, 1.4))):
        _lift(K, QUAY_Z, K.container_stack, "csw%d" % i, cx, cy,
              cols=2, rows=2, mats=box_mats)

    # ---------------- gantry cranes: two, on the FAR arm ----------------
    # These are the silhouette. They straddle the far quay edge with their booms out
    # over the water, which is the shape that says CONTAINER PORT from a long way off.
    # One per arm, on rails, BOTH legs on concrete (owner). Before, both stood on
    # the far arm with their inner legs out past the quay edge, standing in water.
    # Far arm spans y 2.90..5.20, near arm -4.60..-2.30; the legs sit inside those
    # and only the boom reaches over the bay.
    _portal_crane(K, "gcN", -1.20, iy1 + 0.45, iy1 + 1.85, -1.0, QUAY_Z)
    _portal_crane(K, "gcS", 1.90, y0 + 0.45, y0 + 1.85, 1.0, QUAY_Z)

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


def _portal_crane(K, name, cx, y_out, y_in, face, z):
    """Ship-to-shore gantry on rails.

    Owner: the sides are TRIANGLES in green BEAM, not lattice — so each frame is a
    pair of solid legs converging on an apex, which is also what carries the boom.
    `face` is +1 if the bay lies at greater y than the crane, -1 if less; the boom
    always reaches over the water and the back-stay always over the land.

    Both feet stand on concrete. y_out is the leg nearest the water, y_in the leg
    inland — keeping both inside the arm is the whole point, since the previous
    version put its inner leg past the quay edge and stood it in the bay.
    """
    green, green_lo = K.mat("gantry_green"), K.mat("gantry_green_lo")
    dark = K.mat("darkmetal")
    H, half = 2.55, 0.88
    y_apex = (y_out + y_in) / 2
    zt = z + H
    reach = 3.10                                  # how far the boom hangs over water
    y_tip = y_out + face * reach
    # 0.85 pushed the back-stay and its counterweight past the outer quay edge, so
    # the crane's tail hung over open water on the landward side.
    y_back = y_in - face * 0.40

    for tag, rail_y in (("o", y_out), ("i", y_in)):
        K.box("%s_rail%s" % (name, tag), cx, rail_y, z + 0.035, 2.60, 0.16, 0.07, dark)
    for sx in (-1, 1):
        bx = cx + sx * half
        for tag, ly in (("o", y_out), ("i", y_in)):
            K.dirbox("%s_leg%d%s" % (name, sx > 0, tag), (bx, ly, z + 0.06),
                     (bx, y_apex, zt), 0.20, 0.26, green)
            K.box("%s_boot%d%s" % (name, sx > 0, tag), bx, ly, z + 0.11,
                  0.34, 0.36, 0.16, dark)
        # the tie that turns two legs into a triangle rather than a pair of props
        K.dirbox("%s_tie%d" % (name, sx > 0), (bx, y_out + (y_in - y_out) * 0.22,
                 z + H * 0.42), (bx, y_out + (y_in - y_out) * 0.78, z + H * 0.42),
                 0.16, 0.14, green_lo)
    K.box("%s_apex" % name, cx, y_apex, zt + 0.10, half * 2 + 0.30, 0.42, 0.24, green)

    # Boom out over the water, and a back-stay so it is not cantilevered off nothing.
    for sx in (-1, 1):
        K.dirbox("%s_boom%d" % (name, sx > 0), (cx + sx * 0.26, y_apex, zt + 0.22),
                 (cx + sx * 0.26, y_tip, zt + 0.22), 0.17, 0.20, green)
        K.dirbox("%s_stay%d" % (name, sx > 0), (cx + sx * 0.26, y_apex, zt + 0.22),
                 (cx + sx * 0.26, y_back, zt + 0.22), 0.17, 0.18, green)
    n = max(4, int(reach / 0.55))
    for k in range(n):                            # web between the boom chords
        f0, f1 = k / n, (k + 1) / n
        K.dirbox("%s_web%d" % (name, k),
                 (cx, y_apex + (y_tip - y_apex) * f0, zt + 0.13),
                 (cx, y_apex + (y_tip - y_apex) * f1, zt + 0.31), 0.09, 0.09, green_lo)
    K.box("%s_cw" % name, cx, y_back - face * 0.14, zt + 0.30, 1.05, 0.42, 0.40, green_lo)
    K.box("%s_cab" % name, cx - half - 0.26, y_apex - face * 0.55, zt - 0.55,
          0.36, 0.44, 0.34, K.mat("hi_vis"))

    # Trolley at the BOOM TIP with a chain and a hook on the end (owner).
    ty = y_tip - face * 0.30
    K.box("%s_trolley" % name, cx, ty, zt + 0.06, 0.46, 0.50, 0.16, dark)
    K._fine_mode = True
    link_top, link_bot = zt - 0.02, z + 1.05
    links = 7
    for k in range(links):                        # chain: alternating link plates
        z0 = link_top + (link_bot - link_top) * k / links
        z1 = link_top + (link_bot - link_top) * (k + 1) / links
        w, d = (0.055, 0.02) if k % 2 == 0 else (0.02, 0.055)
        K.box("%s_link%d" % (name, k), cx, ty, (z0 + z1) / 2, w, d, abs(z1 - z0) * 0.94, dark)
    K._fine_mode = False
    K.box("%s_block" % name, cx, ty, z + 0.94, 0.24, 0.26, 0.20, K.mat("hi_vis"))
    # Hook: a J — shank, throat, and the point curling back up.
    K.box("%s_hook_sh" % name, cx, ty, z + 0.74, 0.09, 0.09, 0.22, dark)
    K.box("%s_hook_bo" % name, cx, ty + face * 0.09, z + 0.645, 0.09, 0.27, 0.09, dark)
    K.box("%s_hook_pt" % name, cx, ty + face * 0.20, z + 0.715, 0.09, 0.09, 0.16, dark)


def _hull(K, name, cx, cy, length, beam, draft_z, deck_z, mat):
    """A LOFTED hull with a real bow (owner): stations along the length, each a
    rectangle of its own half-beam and its own bottom height, skinned together.

    That gives the two things a stepped wedge cannot — the waterline narrows to a
    stem, and the forefoot RISES toward the bow so the stem rakes forward instead of
    sitting on a flat-bottomed box. The stern keeps a flat transom, which is what a
    working ship has and what distinguishes the two ends at a glance.

    Stations are (fraction of length from centre, half-beam fraction, bottom rise,
    top rise). Bottom rise pulls the forefoot up; top rise gives the bow its sheer.
    """
    st = [
        (-0.500, 0.42, 0.00, 0.00),      # transom
        (-0.440, 0.50, 0.00, 0.00),
        (-0.150, 0.50, 0.00, 0.00),
        ( 0.180, 0.49, 0.00, 0.00),
        ( 0.300, 0.45, 0.03, 0.01),
        ( 0.380, 0.37, 0.09, 0.03),
        ( 0.440, 0.25, 0.17, 0.06),
        ( 0.480, 0.13, 0.25, 0.09),
        ( 0.500, 0.035, 0.32, 0.12),     # stem
    ]
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    rings = []
    for xf, hwf, zb, zt in st:
        x = cx + xf * length
        hw = max(beam * hwf, 0.02)
        z0, z1 = draft_z + zb, deck_z + zt
        rings.append([bm.verts.new(v) for v in ((x, cy - hw, z0), (x, cy + hw, z0),
                                                (x, cy + hw, z1), (x, cy - hw, z1))])
    for i in range(len(rings) - 1):
        a_, b_ = rings[i], rings[i + 1]
        for j in range(4):
            k = (j + 1) % 4
            bm.faces.new((a_[j], a_[k], b_[k], b_[j]))
    bm.faces.new(list(reversed(rings[0])))          # transom
    bm.faces.new(rings[-1])                          # stem cap
    bm.normal_update()
    bm.to_mesh(me)
    bm.free()
    ob = K.obj(name, me, mat)
    for poly in ob.data.polygons:
        poly.use_smooth = False
    # Deck plate, inset so the hull's sheer still shows as a line round the edge.
    K.box("%s_deck" % name, cx - length * 0.04, cy, deck_z + 0.015,
          length * 0.84, beam * 0.92, 0.05, K.mat("deck"))
    return ob


def _tanker(K, name, cx, cy, length, beam):
    """Oil tanker: long low hull, pipe manifold amidships, house right aft. The read is
    LOW AND LONG with one block at the stern — the opposite of the boxship's stacked mass."""
    draft, deck = WATER_Z - 0.14, WATER_Z + 0.52
    _hull(K, name, cx, cy, length, beam, draft, deck, K.mat("hull_black"))
    K.box("%s_boot" % name, cx - length * 0.06, cy, WATER_Z + 0.02,
          length * 0.72, beam + 0.015, 0.09, K.mat("hull_red"))
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
    K.box("%s_boot" % name, cx - length * 0.06, cy, WATER_Z + 0.02,
          length * 0.72, beam + 0.015, 0.09, K.mat("hull_red"))
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
