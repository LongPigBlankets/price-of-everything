# Parametric builder for the Mine. Run AFTER sprite_kit.py:
#   exec(open(".../sprite_kit.py").read())
#   exec(open(".../mine_builder.py").read()); build_mine(2)
#
# Brief (owner, 2026-07-30, from two references): a COMBINATION open-pit and shaft mine —
# terraced benches cut 3-4 levels below ground, plus a winding tower on the pit edge with a
# lift. The pit is SUBTRACTIVE, which a floating sprite cannot do (no ground plane to boolean
# against), so it is built from nested rings of solid earth whose tops ARE the benches. The
# rings follow a BEAN outline, not a rectangle — rectangles read as a machined box, a real
# working is an irregular bowl.
#
# CAMERA FACTS this layout is built around (iso from +X,-Y,+Z):
#   * THE SIGHTLINE RULE. The view ray gains 1 unit of height per 1 unit of horizontal
#     travel, so a bench on the NEAR flank (normal pointing +X/-Y) only lets you see past it
#     if its TREAD EXCEEDS ITS RISER. Get that backwards and the pit is a sealed dark slot no
#     matter how many levels you cut. With an organic outline "near flank" is per-vertex, so
#     the inset is a FUNCTION OF THE VERTEX NORMAL (see `tread`), never a constant.
#   * the pit walls we SEE are the -X and +Y flanks (their inner faces point at the camera).
#     Those carry the ore seam, the haul ramp and the gallery portals.
#   * no cast shadows in this style, so DEPTH IS CARRIED BY VALUE — each ring is a step
#     darker down the earth ramp (Kit.pit_mats), and the block's own cut faces are banded
#     (strata=4) so the block does not out-bright the pit it contains.
#   * the block base sits at z=0 like every other building in the set, so the mine shares the
#     --ref export scale.

import math

# ---------------- per-level parameters ----------------
# PREFIXED: every builder is exec'd into ONE globals dict, so a plain `LEVELS`
# lets the last file loaded silently overwrite the others' level tables.
# The HOLE is what grows: 2 levels below ground at L1, 4 at L2, 5 at L3. The SHAFT is
# present from L1 (a bare bore, no galleries) and gains
# gallery levels as the mine deepens; it is drawn as a section on the block's cut +X edge at
# the headgear's own y.
MINE_LEVELS = {
    1: dict(benches=1, ground=1.30, depth=0.62, rx=1.60, ry=1.74,
            headframe=False, tall=False, galleries=0, conveyor=False, shaft_levels=0),
    2: dict(benches=3, ground=1.55, depth=1.10, rx=1.73, ry=1.86,
            headframe=True,  tall=True,  galleries=2, conveyor=False, shaft_levels=2),
    3: dict(benches=4, ground=1.80, depth=1.35, rx=1.78, ry=1.90,
            headframe=True,  tall=True,  galleries=3, conveyor=True,  shaft_levels=3),
}

OUTER = (-2.75, 2.75, -2.35, 2.35)
PC = (-0.62, -0.05)        # pit centre
SEG = 12                   # outline segments — see the note in build_mine
FAR_TREAD = 0.30           # -X / +Y flanks: the walls the camera looks AT; a look choice
NEAR_MARGIN = 0.10         # +X / -Y flanks: tread = riser + this, so the floor stays in view.
                           # 0.06 satisfies the rule on paper but leaves nothing for the haul
                           # road's berm, which also stands on the benches: a ray-cast over
                           # L3's pit returned ZERO samples on the two deepest surfaces.
NEAR = (0.7071, -0.7071)   # the direction "towards the camera" in plan


def build_mine(level: int = 2) -> dict:
    p = MINE_LEVELS[level]
    setup_rig()
    K = Kit(open_collection("BLDG_mine"))
    nb, G = p["benches"], p["ground"]
    step = p["depth"] / (nb + 1)
    near = step + NEAR_MARGIN

    def tread(nx, ny):
        """Per-vertex bench tread. Blends to `near` as the wall turns to face the camera —
        the generalisation of THE SIGHTLINE RULE to an outline that is not axis-aligned."""
        f = max(0.0, nx * NEAR[0] + ny * NEAR[1])
        return FAR_TREAD + (near - FAR_TREAD) * f

    # ---------------- terraced pit ----------------
    # SEG is deliberately low, and this is MEASURED, not taste. The facets are flat-shaded
    # and Freestyle will not ink a break this shallow, so each ring's own facets span a wider
    # luma range than the step between rings: at 18 segments a scan down one wall read
    # 152-129-108-131-107, i.e. brighter facets appearing BELOW darker ones, and the terracing
    # dissolved into a smooth bowl. Few long flanks keep the ring steps dominant.
    rim = K.poly_bean(PC[0], PC[1], p["rx"], p["ry"], n=SEG,
                      lobe=0.10, dent=0.14, phase=math.radians(28))
    polys = [K.poly_rect(OUTER[0], OUTER[1], OUTER[2], OUTER[3], SEG), rim]
    for _ in range(nb):
        polys.append(K.poly_offset(polys[-1], tread))
    tops = [G - step * i for i in range(nb + 2)]
    # The rim must clear the block's own faces by more than terraced_pit_poly's `grow`
    # overlap. Miss it and ring 1's grown outline breaches the cut face by a hair; because
    # its normal is not the face's, it shades differently and renders as a 1px bright sliver
    # down the strata — invisible in review, obvious once you know to look.
    slack = min([min(q[0] - OUTER[0], OUTER[1] - q[0],
                     q[1] - OUTER[2], OUTER[3] - q[1]) for q in rim])
    if slack < 0.09:
        print("RIM BREACHES THE BLOCK: clearance %.3f (need > grow 0.03 + margin)" % slack)
    # The pit BOTTOM is the coal being worked, not just more earth — so it breaks out of the
    # earth ramp entirely and goes near-black.
    # Both of the two deepest surfaces go coal, not just the floor: at L3 the floor alone is
    # under 1 x 2 units at the bottom of a five-level pit and reads as a smudge — measured at
    # ~1% of the sprite's opaque pixels. The working bench above it carries the colour.
    # Geology, not decoration: two bands of overburden on top, coal measures below. Coaling
    # only the floor was measured at ~1% of the sprite — the floor of a five-level pit is a
    # smudge — so everything from the third surface down goes black.
    pmats = K.pit_mats(len(polys) - 1)
    for ci in range(2, len(pmats)):
        pmats[ci] = K.mat("coal_seam")
    if len(pmats) > 3:              # only band in the paler measure when something is below it
        pmats[2] = K.mat("coal_upper")
    pit = K.terraced_pit_poly("pit", polys, tops, mats=pmats, strata=4)
    floor, fz = pit["floor_poly"], pit["floor_z"]
    fx0 = min(q[0] for q in floor); fx1 = max(q[0] for q in floor)
    fy0 = min(q[1] for q in floor); fy1 = max(q[1] for q in floor)
    rim_x1 = max(q[0] for q in rim)

    def ground_at(x, y):
        for k in range(len(polys) - 1, 0, -1):
            if K.point_in_poly(polys[k], x, y):
                return tops[k] if k == len(polys) - 1 else tops[k - 1]
        return tops[0]

    # exposed COAL veins banding the bench walls — dark, not the warm metal-ore accent
    for vi in {1, min(2, nb)}:
        K.poly_band("vein%d" % vi, polys[vi], (tops[vi - 1] + tops[vi]) / 2,
                    thick=step * 0.62, mat=K.mat("coal_seam"))

    # ---------------- haul road spiralling down the benches ----------------
    # Starts at the -X flank (vertex j0, the one facing furthest away from the camera) so it
    # descends across the two walls we actually see.
    j0 = min(range(SEG), key=lambda j: K.poly_normals(rim)[j][0])
    # The berm on the road's outer edge is inherently about one riser tall (that is the most
    # the smooth descent can ever stand above the stepped bench), so it is kept narrow and in
    # a mid tone — bright and wide it reads as a retaining wall ringing the pit.
    K.spiral_road("road", polys, tops, j0, 0.30, K.mat("ground3"),
                  turns=1.15, steps=56, skirt=step + 0.05, ground_fn=ground_at)

    # ---------------- galleries driven into the +Y wall at pit-floor level ----------------
    for g in range(p["galleries"]):
        back = sorted(floor, key=lambda q: -q[1])[:max(2, p["galleries"] + 1)]
        back.sort(key=lambda q: q[0])
        gx, gy = back[g % len(back)]
        # A portal is bounded by the RISER it is cut into — the wall above the floor is only
        # `step` tall. Fixed sizes burst through the bench above and strand the lintel.
        ph, pr = step * 0.52, step * 0.34
        K.arch_opening("gal%d" % g, (gx, gy + 0.12, fz + ph), (0.0, -1.0), pr,
                       rect_h=ph, depth=0.24)
        K.box("gal%d_lintel" % g, gx, gy - 0.03, fz + ph + pr + 0.04, pr * 3.0, 0.05, 0.045,
              K.mat("scaffold"))

    # ---------------- working floor ----------------
    # Placed off the floor CENTROID, not its bounding box: on a bean outline the bbox corners
    # are outside the polygon, so bbox-relative props end up perched on a bench or in space.
    cxf = sum(q[0] for q in floor) / len(floor)
    cyf = sum(q[1] for q in floor) / len(floor)
    K.box("haul_road", cxf - 0.04, cyf + 0.06, fz + 0.015,
          0.32, (fy1 - fy0) * 0.50, 0.03, K.mat("ground4"))
    hs = min(fx1 - fx0, fy1 - fy0)              # offsets scale with the floor, which narrows
    for hn, (ox, oy, hr) in enumerate((((0.20, -0.22, 0.20)), ((-0.18, -0.06, 0.15)))):
        hx, hy = cxf + ox * hs, cyf + oy * hs
        hr = hr * min(1.0, hs / 1.45)
        # Pull toward the centroid until it is genuinely on the floor: L3's floor is narrow
        # and lopsided, so a fixed offset that fits L1 hangs off the edge there.
        for _ in range(6):
            if K.point_in_poly(floor, hx, hy):
                break
            hx, hy = cxf + (hx - cxf) * 0.7, cyf + (hy - cyf) * 0.7
        else:
            print("HEAP %d OFF THE FLOOR at (%.2f, %.2f)" % (hn, hx, hy))
        # proper cones, not squat pads: at r > h a heap reads as a spilled orange puddle
        K.cone("heap%d" % hn, hx, hy, fz + hr * 0.55, hr, 0.02, hr * 1.10,
               K.mat("coal_seam"), segments=6, smooth=False)

    # ---------------- headgear and the shaft section ----------------
    # No apron slab: `concrete` sits deep in the AgX shoulder and a yard-sized plate of it
    # renders as a blank white rectangle. The earth surface IS the yard.
    # Tower pushed to the RIGHT EDGE — as far out as its plinth can sit without overhanging.
    HX, HY = OUTER[1] - 0.64, 0.25
    HEAD_W = 0.66                               # headgear foot spread; the base square
    K.box("head_plinth", HX, HY, G + 0.04, 1.22, 1.22, 0.08, K.mat("wall_grey"))
    K.box("collar", HX, HY, G + 0.14, 0.80, 0.80, 0.20, K.mat("scaffold"))
    K.box("shaft_mouth", HX, HY, G + 0.25, 0.48, 0.48, 0.05, K.mat("opening"))
    # The section is drawn on the block's cut +X edge at the headgear's own y, so it reads as
    # that same shaft in cutaway. It cannot sit under the tower in plan — the tower is inboard
    # of the edge — which is exactly why it is confined to the sprite edge.
    sl = p["shaft_levels"]
    # Screen-horizontal position is proportional to (x + y), so the section sits DIRECTLY
    # BENEATH the headgear when its x+y matches the tower's — not when its y matches. The
    # section is pinned to the cut face at OUTER[1], so solve the y instead of guessing it.
    # The bore head is the MIDPOINT OF THE RIGHT SIDE of the headgear's base, laid onto the
    # face. That is a PLAN projection — match (x + y) and nothing else — and deliberately not
    # the full screen-position match: two points coincide on screen iff (x + y) matches AND
    # z - (x - y)/2 matches, and honouring the second term would drag the bore head up above
    # ground and run it through the tower. The shaft is only ever underground, so the head
    # stays pinned to the block's top edge and only its horizontal position is projected.
    SHY = (HX + HEAD_W / 2) + HY - OUTER[1]
    K.shaft_cutaway("shaft", OUTER[1], SHY, G - 0.02, 0.16,
                    levels=[G - 0.10 - (i + 1) * (G - 0.26) / (sl + 1) for i in range(sl)],
                    reach=0.72, stagger=0.34, dip=30.0,
                    cage_at=(G * 0.52) if sl else None)

    if p["headframe"]:
        K.headframe("head", HX, HY, G + 0.24, 2.30, w=HEAD_W, brace_to=(-1.05, G + 0.10))
        for sx in (-0.12, 0.12):                      # winding ropes off the sheave
            K.dircyl("rope%d" % (sx > 0), (HX + sx, HY, G + 2.24), (HX + sx, HY, G + 0.26),
                     0.020, K.mat("pipe"), segments=8)
        K.box("cage", HX, HY, G + 0.86, 0.36, 0.32, 0.44, K.mat("door_leaf"))
        K.seam_bar("cage_seam", HX, HY - 0.16, G + 1.08, 0.38, 0.04, 0.04)
    else:
        # L1's shaft is simple but still needs a surface expression, or the section on the
        # cut edge reads as belonging to nothing.
        for sx in (-1, 1):
            K.dircyl("gantry%d" % (sx > 0), (HX + sx * 0.30, HY - 0.28, G + 0.24),
                     (HX, HY, G + 0.92), 0.042, K.mat("scaffold"), segments=8)
        K.dircyl("gantry_back", (HX, HY + 0.34, G + 0.24), (HX, HY, G + 0.92), 0.042,
                 K.mat("scaffold"), segments=8)
        K.cyl("gantry_sheave", HX, HY, G + 0.92, 0.15, 0.08, K.mat("stack"),
              axis='X', segments=20)

    if p["tall"]:
        # Three-storey winding house: one window per floor, door on the ground floor.
        BX, BY, FL = HX + 0.04, 1.62, 0.46
        K.box("hoist_plinth", BX, BY, G + 0.04, 1.00, 0.80, 0.08, K.mat("wall_grey"))
        K.box("hoist", BX, BY, G + 0.08 + FL * 1.5, 0.86, 0.68, FL * 3, K.mat("wall_steel"))
        K.box("hoist_roof", BX, BY, G + 0.08 + FL * 3 + 0.05, 0.98, 0.80, 0.10, K.mat("roof"))
        # All three windows share one column, offset left, with the door on the RIGHT of the
        # same wall. Centring the column instead leaves the window frame (which overhangs the
        # glass by 0.09) colliding with the door leaf on this 0.86-wide face.
        WX = BX - 0.09
        for f in range(3):
            wz = G + 0.08 + FL * (f + 0.58)
            K.window("hoist_w%d" % f, "-Y", (WX, BY - 0.34, wz), 0.24, 0.26, cols=2, rows=2)
        K.door("hoist_door", "-Y", (BX + 0.26, BY - 0.34, G + 0.08 + 0.24), 0.24, 0.44, ribs=2)
        for f in (1, 2):                             # floor bands, so the storeys read
            K.seam_bar("hoist_band%d" % f, BX, BY - 0.35, G + 0.08 + FL * f, 0.88, 0.03, 0.035)
    else:
        K.box("hut_plinth", HX + 0.04, 1.52, G + 0.04, 1.08, 0.88, 0.08, K.mat("wall_grey"))
        K.box("hut", HX + 0.04, 1.52, G + 0.36, 0.92, 0.72, 0.64, K.mat("wall_steel"))
        K.box("hut_roof", HX + 0.04, 1.52, G + 0.72, 1.04, 0.84, 0.09, K.mat("roof"))
        K.door("hut_door", "-Y", (HX + 0.04, 1.16, G + 0.26), 0.30, 0.44, ribs=2)

    if p["conveyor"]:
        # Incline conveyor: foot on the pit floor, head over a stockpile bunker. It runs
        # DIAGONALLY out to the front-right — straight along +X it shares a screen line with
        # the haul ramp and the two read as one stray beam.
        # The foot loads from a MID BENCH, not the pit bottom. The near flank climbs at
        # riser/tread ~= 0.82, so any belt crossing it is forced to about 40 degrees no
        # matter where it starts; starting at the floor only makes it long enough to tower
        # over the whole pit. A loading point two benches down keeps it short.
        BUNK = (2.12, -1.62)
        bench_z = tops[min(2, nb)]
        FOOT = (cxf, cyf, fz + 0.14)
        for i in range(41):
            t = i / 40.0
            px = BUNK[0] + (cxf - BUNK[0]) * t
            py = BUNK[1] + (cyf - BUNK[1]) * t
            if ground_at(px, py) <= bench_z + 1e-6:
                FOOT = (px, py, ground_at(px, py) + 0.14)
                break
        K.box("conv_hopper", FOOT[0], FOOT[1], FOOT[2] + 0.10, 0.40, 0.36, 0.36,
              K.mat("scaffold"))
        dx, dy = BUNK[0] - FOOT[0], BUNK[1] - FOOT[1]
        run = math.hypot(dx, dy)
        # The head height is SOLVED, not chosen. On a diagonal the belt crosses both ring
        # families at once, so "the rim is the binding constraint" is false; sample the real
        # terraced surface and take the steepest requirement.
        # Sample only t >= 0.35. Nearer the foot the required rise is divided by a vanishing
        # t, so one sample that happens to land on a bench demands an unbounded climb and the
        # belt turns into a tower over the pit.
        TS = [i / 40.0 for i in range(14, 41)]
        rise = max([(ground_at(FOOT[0] + t * dx, FOOT[1] + t * dy) + 0.09 - FOOT[2]) / t
                    for t in TS] + [(G + 1.30) - FOOT[2]])
        if rise > run * 0.95:
            print("CONVEYOR TOO STEEP: rise %.2f over run %.2f" % (rise, run))
        K.prism("conveyor", FOOT, (dx / run, dy / run),
                [(0.0, 0.0), (run, rise), (run, rise + 0.19), (0.0, 0.19)], 0.36,
                K.mat("scaffold"))
        K.box("conv_foot", FOOT[0], FOOT[1], (fz + FOOT[2]) / 2, 0.10, 0.10,
              FOOT[2] - fz, K.mat("scaffold"))
        for t in (0.55, 0.80):
            lx, ly = FOOT[0] + t * dx, FOOT[1] + t * dy
            gz, bz = ground_at(lx, ly), FOOT[2] + t * rise
            K.box("conv_leg%d" % int(t * 100), lx, ly, (gz + bz) / 2, 0.10, 0.10,
                  bz - gz, K.mat("scaffold"))
        K.box("bunker_plinth", BUNK[0], BUNK[1], G + 0.04, 1.11, 1.01, 0.08, K.mat("wall_grey"))
        K.box("bunker", BUNK[0], BUNK[1], G + 0.45, 0.95, 0.85, 0.90, K.mat("wall_grey"))
        K.box("bunker_roof", BUNK[0], BUNK[1], G + 0.94, 1.07, 0.97, 0.09, K.mat("roof"))
        K.seam_bar("bunker_seam", BUNK[0], BUNK[1] - 0.44, G + 0.94, 1.09, 0.04, 0.04)
        K.gate("bunker_gate", "-Y", (BUNK[0], BUNK[1] - 0.43, G + 0.26), 0.44, 0.42, slats=3)

    if p["conveyor"]:
        # Back-left corner in the owner's vocabulary: back = +Y, left = -X, i.e. the TOP
        # corner of the diamond on screen. Seated on whatever surface is actually there
        # (rim or bench) via ground_at rather than an assumed height.
        EX, EY = -2.02, 1.48
        K.excavator("dig", EX, EY, ground_at(EX, EY) + 0.02, s=0.78, face=1.0)

    if near <= step:
        print("PIT SEALED: near tread %.3f <= riser %.3f" % (near, step))
    if fx1 - fx0 < 0.7 or fy1 - fy0 < 0.7:
        print("PIT FLOOR TOO SMALL: %.2f x %.2f" % (fx1 - fx0, fy1 - fy0))
    if rim_x1 + 1.34 > OUTER[1]:
        print("SHELF TOO NARROW: rim reaches %.2f, block ends %.2f" % (rim_x1, OUTER[1]))
    for w in K.validate(ground=0.0):
        print(w)
    return {"building": "mine", "level": level, "benches": nb, "floor_z": round(fz, 3),
            "levels_below_ground": nb + 1, "shaft_levels": sl,
            "floor": "%.2f x %.2f" % (fx1 - fx0, fy1 - fy0), "objects": len(K.col.objects)}


def build_mine_flush(level: int = 2) -> dict:
    """The mine for a map that has ground of its own: the same build, with the block of earth
    it is cut into, and the shaft section drawn on that block's face, marked to be cut away
    after rendering. What is left is the pit, seen down into, and what stands at its rim."""
    out = build_mine(level)
    for ob in bpy.data.collections["BLDG_mine"].objects:
        if "_ring0_" in ob.name or ob.name.startswith("shaft"):
            ob["cut"] = 1
    out["ground"] = MINE_LEVELS[level]["ground"]
    return out
