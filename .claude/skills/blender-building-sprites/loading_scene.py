"""Loading-screen street scene — Phase 0: scaffold (scene, rig, road, placeholder sky).

A separate Blender Scene "Loading" in the sprite .blend: shared materials and builders,
zero risk to the sprite rig. Its own perspective camera (LoadCam) and sun (LoadSun) — the
sprite `Camera`/`Light` objects are NOT linked here. Builders' setup_rig() still re-poses
the shared sprite Camera object and stomps the ACTIVE scene's render settings, so
`setup_load_rig()` is always asserted AFTER any builder runs (P1 does this).

Composition contract (locked in the plan):
- Street runs along X; buildings stand on the NORTH side (fronts facing -Y, toward the
  street), camera on the south side gliding laterally. Motion later = horizontal layer
  pans in Godot that HALT when the game finishes loading, so any frame must compose.
- NOINK: the sky/backdrop must carry no ink — the 7px external contour would frame the
  backdrop like a picture. Freestyle's per-lineset collection slot is already taken by
  FINE_INK, so NOINK is done with FACE MARKS: every polygon of a NOINK object gets
  `use_freestyle_mark = True`, and all three linesets exclude marked faces
  (`select_by_face_marks`, `face_mark_negation='EXCLUSIVE'`). Composes with the
  collection filter and needs no extra collection slot.

    exec(open("/Users/crisu/Price of Everything/blender-assets/loading_scene.py").read())
    phase0()
"""
import math
import bpy
import bmesh
import mathutils

SCENE_NAME = "Loading"

# ── Street geometry contract (P1 places buildings against these numbers) ─────
ROAD_HALF_W = 0.62          # road half-width; two lanes at building scale
SIDEWALK_W = 0.95           # raised sidewalk flanking the road (owner: on both sides)
SIDEWALK_TOP = 0.105        # visibly a step above the road surface (~0.058)
KERB_W = 0.10               # pale lip on the sidewalk's road edge
SETBACK_W = 1.00            # grass strip between sidewalk and the facades
BACK_STREET_Y = 13.5        # parallel road behind the NORTH row only — the south
#                             side is open sea now
SEA_WALK_Y = -9.30          # quay edge behind the south row: verge, then a walk,
#                             then the drop to the water
# The docks' own shore road ends up here once the port is rotated -90 and staged:
# x 91.75..108.25, y -4.02..-3.22 — running parallel to the main street. A short
# spur links the two into a proper T junction.
PORT_LINK_X, PORT_LINK_W = 92.30, 0.90
DOCK_ROAD_Y = -3.22         # near edge of the port's shore road
SEA_Z = -0.30               # water surface. Deeper than this and it barely reads:
#                             the south buildings run back to y -8.1, so at -10.55 and
#                             -0.52 the water only appeared as a sliver past the last
#                             building, low and at the very edge of frame.
BUILDING_FRONT_Y = ROAD_HALF_W + SIDEWALK_W + SETBACK_W   # facades sit at this y
STREET_X0, STREET_X1 = -20.0, 200.0   # camera end -> far beyond the visible terminus
CITY_X = 74.0               # distant city backdrop plane (P2), faces the camera (-X)
SKY_X = 210.0               # sky backdrop plane, faces the camera
CAM_X = -13.0               # start camera x (the rig asserts this)
CAM_H = 1.62                # camera height (owner: raised 1.0 from 0.62)
# The street used to stop at 92 with the sky plane at 90, so the road's far end met
# the sky plane's base in a visible hard wedge — the owner's "road runs out when
# zooming in". The road now runs to 200 and dissolves into corridor haze long before
# that; the sky plane moves back with it and is scaled to subtend the same angle.
SKY_SCALE = (SKY_X - CAM_X) / (90.0 - CAM_X)
HAZE_WALLS = ((88.0, 2.20), (104.0, 3.40))   # (x, height) far-field haze, far one taller
# The city is BUILT at CITY_X but then pushed back by this factor, scaled about the
# start camera so its projection is identical — the skyline looks the same while
# physically retreating past the new end-of-street buildings (a construction site
# and a power plant now stand at x 78 and 86, which would otherwise poke through a
# backdrop sitting at 74). Everything in LOAD_city rides along: gates, central wall,
# haze walls and clouds.
CITY_PUSH = 1.92
# Owner: no camera move may cross this fraction of the built street — past it the
# far end thins out and the sparse slots show.
TRAVEL_MAX_FRAC = 0.75

# Scene tones — flat Principled, specular 0, roughness 1 (the kit recipe). Large
# surfaces obey the AgX value ceiling: past base ~0.3 everything renders within a few
# luma, so the BIG planes stay low; small crisp objects may go brighter.
CITY_DARK_TONE = (0.150, 0.175, 0.205)   # LOD-2 shaded returns / cornices
TONES = {
    "load_ground":  (0.125, 0.170, 0.092),   # field green
    "load_verge":   (0.128, 0.240, 0.075),   # vivid lawn at the building line (owner)
    "load_asphalt": (0.085, 0.095, 0.115),   # road — darker than ground, navy-leaning
    "load_kerb":    (0.420, 0.400, 0.340),   # pale stone, small surface
    "load_walk":    (0.240, 0.235, 0.215),   # sidewalk concrete — large surface, stays low
    "load_dash":    (0.700, 0.680, 0.600),   # centre-line dashes
    "load_sky":     (0.520, 0.600, 0.660),   # placeholder single tone; banded in P2
    "load_sea":     (0.055, 0.135, 0.190),   # matches the docks' dock_water exactly,
    #                                          so the street's sea and the port's bay
    #                                          are one body of water
}


def _mat(name):
    m = bpy.data.materials.get(name)
    if m is None:
        m = bpy.data.materials.new(name)
        m.use_nodes = True
        bsdf = m.node_tree.nodes.get("Principled BSDF")
        bsdf.inputs["Base Color"].default_value = (*TONES[name], 1.0)
        bsdf.inputs["Roughness"].default_value = 1.0
        bsdf.inputs["Specular IOR Level"].default_value = 0.0
    return m


def get_scene():
    sc = bpy.data.scenes.get(SCENE_NAME)
    if sc is None:
        sc = bpy.data.scenes.new(SCENE_NAME)
    return sc


def _collection(sc, name):
    col = bpy.data.collections.get(name)
    if col is None:
        col = bpy.data.collections.new(name)
    if name not in [c.name for c in sc.collection.children]:
        sc.collection.children.link(col)
    return col


def _wipe(col):
    for ob in list(col.objects):
        bpy.data.objects.remove(ob, do_unlink=True)


def _box(col, name, cx, cy, cz, sx, sy, sz, mat):
    m = bpy.data.meshes.new(name)
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=(sx, sy, sz), verts=bm.verts)
    bmesh.ops.translate(bm, vec=(cx, cy, cz), verts=bm.verts)
    bm.to_mesh(m)
    bm.free()
    ob = bpy.data.objects.new(name, m)
    col.objects.link(ob)
    ob.data.materials.append(mat)
    for p in ob.data.polygons:
        p.use_smooth = False
    return ob


def mark_noink(ob):
    """Every face marked: all linesets exclude marked faces -> the object carries no ink.

    Blender 5.x: `MeshPolygon.use_freestyle_mark` is gone; the mark is a boolean FACE
    attribute named `freestyle_face` (probed 2026-08-05 via mark_freestyle_face + an
    attribute diff — the operator creates exactly this layer).
    """
    mesh = ob.data
    attr = mesh.attributes.get("freestyle_face")
    if attr is None:
        attr = mesh.attributes.new("freestyle_face", 'BOOLEAN', 'FACE')
    for d in attr.data:
        d.value = True


def setup_load_rig(res_x=1920, res_y=1080):
    """Assert the Loading scene's full rig. Idempotent; call AFTER any builder ran."""
    sc = get_scene()
    bpy.context.window.scene = sc

    sc.render.engine = 'BLENDER_EEVEE'
    sc.render.film_transparent = True
    sc.render.resolution_x = res_x
    sc.render.resolution_y = res_y
    sc.render.use_freestyle = True
    sc.render.line_thickness_mode = 'ABSOLUTE'

    # Camera: one-point perspective DOWN the road toward the city (owner's call —
    # replaces the earlier lateral-facade framing). Slightly off the centreline so the
    # two building rows are asymmetric in frame. Tilt stays exactly 90: verticals
    # plumb; framing raised by lens shift. Never the sprite Camera object.
    cam_ob = bpy.data.objects.get("LoadCam")
    if cam_ob is None:
        cam = bpy.data.cameras.new("LoadCam")
        cam_ob = bpy.data.objects.new("LoadCam", cam)
    if cam_ob.name not in [o.name for o in sc.collection.objects]:
        sc.collection.objects.link(cam_ob)
    cam_ob.data.type = 'PERSP'
    cam_ob.data.lens = 32.0
    # Far clip must clear the SKY plane: moving SKY_X to 210 put the backdrop
    # 223 units out, past the old 200 clip, so raw renders came out with a
    # transparent (black) sky. The film composites its own graded sky and never
    # noticed; anything rendering the scene straight did.
    cam_ob.data.clip_end = 420.0
    # Camera height raised 1.0 (owner 2026-08-06): 0.62 was human eye level, this
    # looks over the traffic rather than through it and shows more of the road
    # surface. The camera stays exactly horizontal, so the vanishing point does not
    # move on screen — only the ground/sky balance changes.
    cam_ob.location = (-13.0, 0.0, CAM_H)
    cam_ob.rotation_euler = (math.radians(90.0), 0.0, math.radians(-90.0))  # look +X, plumb verticals
    cam_ob.data.shift_y = 0.125                              # rising front instead of tilt
    sc.camera = cam_ob

    # Sun: shadowless (style contract), aimed so the -Y facades read lit and the east
    # walls fall into tone-shade. Own object; the sprite Light is untouched.
    sun_ob = bpy.data.objects.get("LoadSun")
    if sun_ob is None:
        sun = bpy.data.lights.new("LoadSun", 'SUN')
        sun_ob = bpy.data.objects.new("LoadSun", sun)
    if sun_ob.name not in [o.name for o in sc.collection.objects]:
        sc.collection.objects.link(sun_ob)
    # Owner: light from the RIGHT of the frame (south, -Y) so the left-row facades
    # are well lit — and CAST SHADOWS ON, scene only. The sprites' no-shadow contract
    # stands for sprites; this composed scene follows the print reference, where
    # trees and buildings throw shade (which the stipple pass then densifies).
    sun_ob.data.use_shadow = True
    sun_ob.data.energy = 3.6
    sun_ob.data.color = (1.0, 0.955, 0.87)
    sun_ob.data.angle = 0.02                 # near-hard shadow edges: print, not photo
    if hasattr(sc, "eevee") and hasattr(sc.eevee, "use_shadows"):
        sc.eevee.use_shadows = True
    # Azimuth +25: sun from the south-EAST (ahead-right, down-street), so shadows
    # angle toward the viewer like the reference — at -14 they fell away from camera
    # and hid behind their own casters, reading as "no shadows".
    sun_ob.rotation_euler = (math.radians(48.0), 0.0, math.radians(25.0))

    # Freestyle: same three linesets as the sprite rig, plus the NOINK face-mark
    # exclusion on ALL of them.
    vl = sc.view_layers[0]
    vl.use_freestyle = True
    fs = vl.freestyle_settings
    fs.crease_angle = math.radians(120)

    fine = bpy.data.collections.get("FINE_INK")
    if fine is None:
        fine = bpy.data.collections.new("FINE_INK")

    if "ink" not in fs.linesets:
        ls = fs.linesets.new("ink")
        ls.select_silhouette = True
        ls.select_border = True
        ls.select_crease = True
        ls.select_edge_mark = True
    ink = fs.linesets["ink"]
    ink.linestyle.color = (0.055, 0.065, 0.13)
    ink.linestyle.thickness = 2.4
    ink.select_by_collection = True
    ink.collection = fine
    ink.collection_negation = 'EXCLUSIVE'

    if "ink_fine" not in fs.linesets:
        lf = fs.linesets.new("ink_fine")
        lf.select_silhouette = True
        lf.select_border = True
        lf.select_crease = True
        lf.select_edge_mark = True
    lf = fs.linesets["ink_fine"]
    lf.select_by_collection = True
    lf.collection = fine
    lf.collection_negation = 'INCLUSIVE'
    lf.linestyle.color = (0.055, 0.065, 0.13)
    lf.linestyle.thickness = 1.05

    if "contour" not in fs.linesets:
        ls = fs.linesets.new("contour")
        ls.select_silhouette = False
        ls.select_border = False
        ls.select_crease = False
        ls.select_external_contour = True
        ls.edge_type_combination = 'OR'
    contour = fs.linesets["contour"]
    contour.linestyle.color = (0.045, 0.055, 0.11)
    contour.linestyle.thickness = 7.0
    # DISABLED for the Loading scene (sprite scene unaffected — linesets are
    # per-scene). The external contour is a SPRITE convention: with one isolated
    # building it draws the cutout edge, but in a composed scene it draws a heavy
    # navy ring at EVERY object-vs-object overlap — building against building,
    # kerb against road, tuft against verge (two rounds of "navy lines" notes were
    # both this lineset). Ink at 2.9px carries the scene's line weight instead.
    contour.show_render = False
    ink.linestyle.thickness = 2.9

    for ls in (ink, lf, contour):
        ls.select_by_face_marks = True
        ls.face_mark_negation = 'EXCLUSIVE'
        ls.face_mark_condition = 'ONE'

    world = bpy.data.worlds.get("LoadWorld")
    if world is None:
        world = bpy.data.worlds.new("LoadWorld")
        world.use_nodes = True
    bg = world.node_tree.nodes.get("Background")
    if bg:
        bg.inputs[0].default_value = (1, 1, 1, 1)
        bg.inputs[1].default_value = 0.45   # low ambient: shadows must read (print look)
    sc.world = world
    return sc


# Every place a lane meets the main road. The sidewalk and kerb are BROKEN here
# rather than having a lane painted over them: a side road that runs across an
# unbroken pavement reads as a driveway, not a junction. Widths include a small
# flare so the gap is a touch wider than the lane itself.
JUNCTIONS_N = ((7.5, 0.62), (29.5, 0.62), (48.5, 0.62))
JUNCTIONS_S = ((11.5, 0.62), (33.5, 0.62), (46.0, 0.62), (92.30, 0.90))
JUNCTION_FLARE = 0.13


def _junction_gaps(side):
    js = JUNCTIONS_N if side > 0 else JUNCTIONS_S
    return [(jx - jw / 2 - JUNCTION_FLARE, jx + jw / 2 + JUNCTION_FLARE)
            for jx, jw in js]


def _segmented_strip(col, name, gaps, cy, cz, sy, sz, mat, noink=False):
    """A long strip along X, broken wherever a lane crosses it."""
    spans = []
    x = STREET_X0
    for g0, g1 in sorted(gaps):
        if g0 > x:
            spans.append((x, g0))
        x = max(x, g1)
    if x < STREET_X1:
        spans.append((x, STREET_X1))
    out = []
    for i, (a, b) in enumerate(spans):
        ob = _box(col, "%s_%d" % (name, i), (a + b) / 2, cy, cz, b - a, sy, sz, mat)
        if noink:
            mark_noink(ob)
        out.append(ob)
    return out


def build_street_scaffold():
    """Ground, road, kerbs, centre dashes, placeholder sky. Idempotent."""
    sc = get_scene()
    col = _collection(sc, "LOAD_street")
    _wipe(col)
    EPS = 0.015

    # Ground: one huge low plate. NOINK — a 7px contour along the horizon reads as a
    # picture frame; the ground/sky boundary is carried by tone (and haze, in P2).
    # NOTE the street's x-CENTRE: _box takes a centre + size, and passing cx=0 with the
    # right WIDTH silently builds the road spanning [-37, +37] instead of [-12, +62] —
    # caught on the strip contact sheet as centre-line dashes floating on grass with no
    # road under them (the dashes are placed by true x; the slab was not).
    cx = (STREET_X0 + STREET_X1) / 2.0
    # Ground stops at the south quay: the sea sits BELOW grade (-0.52), so a ground
    # plate running the full width would simply cover it.
    gy0, gy1 = SEA_WALK_Y, 45.0
    ground = _box(col, "ground", cx, (gy0 + gy1) / 2, -0.05,
                  (STREET_X1 - STREET_X0) + 60, gy1 - gy0, 0.1, _mat("load_ground"))
    mark_noink(ground)
    # The sea behind the south row, continuous with the port's bay (owner) — same
    # tone, same level. Behind the buildings: verge, walk, quay wall, water.
    sea = _box(col, "sea", cx, (SEA_WALK_Y - 46.0) / 2, SEA_Z - 0.10,
               (STREET_X1 - STREET_X0) + 60, 46.0 + SEA_WALK_Y, 0.20, _mat("load_sea"))
    mark_noink(sea)
    _box(col, "sea_wall", cx, SEA_WALK_Y + 0.49, -0.28,
         STREET_X1 - STREET_X0, 0.98, 0.77, _mat("load_walk"))
    _box(col, "sea_kerb", cx, SEA_WALK_Y + 0.06, 0.085,
         STREET_X1 - STREET_X0, 0.12, 0.05, _mat("load_kerb"))

    # Road slab: proud of the ground by EPS (coplanar faces smear — rule 1).
    _box(col, "road", cx, 0, 0.0 + EPS / 2,
         STREET_X1 - STREET_X0, ROAD_HALF_W * 2, 0.1 + EPS, _mat("load_asphalt"))

    # Raised sidewalks flanking the road, with a pale kerb lip on the road edge. The
    # slab is a real step above the asphalt (SIDEWALK_TOP vs ~0.058) so the kerb face
    # catches its own ink line down the whole street.
    for side, tag in ((1, "n"), (-1, "s")):
        yc = side * (ROAD_HALF_W + SIDEWALK_W / 2)
        gaps = _junction_gaps(side)
        # Both the pavement AND its kerb stop at every junction. Leaving the kerb
        # running through was the other half of the problem — a continuous kerb
        # line across a side road is exactly the edge-of-road marking that made
        # the lane read as painted on rather than joining.
        _segmented_strip(col, "walk_" + tag, gaps, yc, SIDEWALK_TOP / 2,
                         SIDEWALK_W, SIDEWALK_TOP, _mat("load_walk"))
        _segmented_strip(col, "kerb_" + tag, gaps,
                         side * (ROAD_HALF_W + KERB_W / 2), SIDEWALK_TOP / 2 + 0.006,
                         KERB_W, SIDEWALK_TOP + 0.012, _mat("load_kerb"))

    # Verges: the lawns between sidewalk and facades, proud of the ground by EPS so
    # they read as kept grass against the duller field beyond (owner: vibrant green).
    for side, tag in ((1, "n"), (-1, "s")):
        y0v = side * (ROAD_HALF_W + SIDEWALK_W)
        y1v = (SEA_WALK_Y + 0.98) if side < 0 else side * (BUILDING_FRONT_Y + 7.0)
        #                                        south verge runs right up to the quay
        #                                        walk; north keeps its +1 (owner): the raised camera sees
        #                                         further out, and the kept lawn used
        #                                         to stop short of the back street
        vb = _box(col, "verge_" + tag, cx, (y0v + y1v) / 2, -0.04 + EPS,
                  STREET_X1 - STREET_X0, abs(y1v - y0v), 0.1, _mat("load_verge"))
        mark_noink(vb)   # terrain: its seams must not carry ink (they read as stray
                         # navy lines across the lawns, through gaps and behind trees)

    # Centre dashes.
    dash_l, gap = 0.42, 0.55
    x = STREET_X0
    i = 0
    while x < STREET_X1:
        _box(col, "dash_%d" % i, x + dash_l / 2, 0, 0.061,
             dash_l, 0.045, 0.012, _mat("load_dash"))
        x += dash_l + gap
        i += 1

    # Single-lane side roads between buildings (owner): a crossing slab over the
    # sidewalk, then a lane running back into the lots, plus parking pads with
    # white bay dividers beside some of them.
    for sx, side in ((7.5, 1), (29.5, 1), (48.5, 1), (11.5, -1), (33.5, -1), (46.0, -1)):
        sgn = side
        # ONE lane at road level running from the carriageway edge out to the lot,
        # through the gap the pavement now leaves for it. The old build laid a thin
        # slab ON TOP of the sidewalk, which is why it read as paint.
        depth = SIDEWALK_W + 5.2
        _box(col, "siderd_%s_%d" % (side, int(sx * 10)), sx,
             sgn * (ROAD_HALF_W + depth / 2), 0.0 + EPS / 2,
             0.62, depth, 0.1 + EPS, _mat("load_asphalt"))
    # Parallel BACK STREETS behind each row (owner). The camera now sits high
    # enough to see over the buildings' flanks into what was open field; a road
    # with its own kerbs reads as "this is a district", not an edge of the world.
    for side, tag in ((1, "n"),):          # south side is sea now, no back street
        by = side * BACK_STREET_Y
        _box(col, "backrd_" + tag, cx, by, 0.0 + EPS / 2,
             STREET_X1 - STREET_X0, ROAD_HALF_W * 1.7, 0.1 + EPS, _mat("load_asphalt"))
        for kside in (-1, 1):
            _box(col, "backkerb_%s%d" % (tag, kside > 0), cx,
                 by + kside * (ROAD_HALF_W * 0.85 + KERB_W / 2), 0.03,
                 STREET_X1 - STREET_X0, KERB_W, 0.07, _mat("load_kerb"))
        bd = 0.55
        bx = STREET_X0
        bi = 0
        while bx < STREET_X1:
            _box(col, "backdash_%s_%d" % (tag, bi), bx + bd / 2, by, 0.061,
                 bd, 0.04, 0.012, _mat("load_dash"))
            bx += bd + 0.85
            bi += 1

    # Spur connecting the main road to the docks' shore road, which runs parallel
    # to it. Crossing slab over the sidewalk, then the lane itself, then a mouth
    # flaring into the dock road so the junction reads as a T rather than a lane
    # stopping against a kerb.
    _box(col, "portlink", PORT_LINK_X,
         (-ROAD_HALF_W + DOCK_ROAD_Y) / 2, 0.0 + EPS / 2,
         PORT_LINK_W, abs(DOCK_ROAD_Y + ROAD_HALF_W), 0.1 + EPS,
         _mat("load_asphalt"))
    _box(col, "portlink_mouth", PORT_LINK_X, DOCK_ROAD_Y - 0.18, -0.02 + EPS * 2,
         PORT_LINK_W + 0.70, 0.42, 0.1, _mat("load_asphalt"))
    ld = 0.34
    for k in range(3):
        _box(col, "portlink_d%d" % k, PORT_LINK_X,
             -(ROAD_HALF_W + SIDEWALK_W) - 0.35 - k * 0.80, 0.061,
             0.05, ld, 0.012, _mat("load_dash"))

    for px, side in ((8.9, 1), (30.9, 1), (12.9, -1), (47.4, -1)):
        sgn = side
        py = sgn * (BUILDING_FRONT_Y + 0.9)
        _box(col, "park_pad_%s_%d" % (side, int(px * 10)), px, py, -0.02 + EPS * 2,
             2.3, 1.7, 0.1, _mat("load_asphalt"))
        for bi in range(4):
            _box(col, "park_bay_%s_%d_%d" % (side, int(px * 10), bi),
                 px - 1.15 + 0.575 * bi + 0.2875, py, 0.033,
                 0.03, 1.5, 0.012, _mat("load_dash"))
    return {"objects": len(col.objects), "building_front_y": BUILDING_FRONT_Y}


def phase0():
    info = build_street_scaffold()
    setup_load_rig()
    return {**info, "scene": SCENE_NAME}


# ── Phase 2: backdrop — banded sky, city silhouette, haze ────────────────────
# All backdrop materials are EMISSION (unlit, exact colour through the view transform —
# the ink_seam trick): these planes face -X, which the sun barely grazes, so a lit
# material would render them near-black and any sun tweak would repaint the sky.
# Everything here is NOINK; the far city reads as pure silhouette against the horizon
# band, which is also why the city tones must sit clearly darker than the horizon.

SKY_BANDS = [                    # bottom -> top: compressed pale transition, then the
    # vivid cerulean owns most of the frame (owner reference: one rich blue).
    (4.0,  (0.820, 0.780, 0.620)),
    (2.0,  (0.620, 0.720, 0.800)),
    (2.0,  (0.450, 0.640, 0.850)),
    (2.5,  (0.330, 0.570, 0.860)),
    (3.5,  (0.250, 0.515, 0.860)),
    (49.5, (0.175, 0.445, 0.850)),
]
CITY_FAR_TONE = (0.360, 0.410, 0.470)    # far rank — hazier against the blue
CITY_NEAR_TONE = (0.270, 0.315, 0.375)   # near rank — reads in front of the far rank
HAZE_TONE = (0.560, 0.555, 0.505)        # grounds the city into the horizon


def _emat(name, rgb):
    m = bpy.data.materials.get(name)
    if m is None:
        m = bpy.data.materials.new(name)
        m.use_nodes = True
        nt = m.node_tree
        for n in list(nt.nodes):
            nt.nodes.remove(n)
        out = nt.nodes.new("ShaderNodeOutputMaterial")
        em = nt.nodes.new("ShaderNodeEmission")
        em.inputs["Strength"].default_value = 1.0
        nt.links.new(em.outputs["Emission"], out.inputs["Surface"])
    m.node_tree.nodes["Emission"].inputs["Color"].default_value = (*rgb, 1.0)
    return m


def build_backdrop(seed=7, detail=1):
    """Banded sky (one mesh, one material slot per band), two-rank city silhouette
    peaked at the vanishing point, and a haze strip grounding it. Idempotent.

    `detail` is the city LOD (owner: one for the first half of the run, a richer one
    from 51% on, when the skyline is closer). LOD 2 keeps the SAME seeded massing —
    identical block positions and sizes — and only adds finer elements, so the swap
    cannot shift the skyline: window strips on every block rather than the wide ones,
    a cornice at each parapet, pilasters on broad facades, and a shaded return on
    the faces turned away from the sun (the sun is south, so the +Y flank is the
    dark one, and it is the blocks right of centre that show it).
    """
    import random
    sc = get_scene()
    sky_col = _collection(sc, "LOAD_sky")
    city_col = _collection(sc, "LOAD_city")
    _wipe(sky_col)
    _wipe(city_col)

    # Sky: single plane at SKY_X facing the camera, horizontal band per material slot.
    # Slots on ONE mesh give hard, un-inked boundaries; stacked coplanar boxes would
    # z-fight exactly on the band lines.
    mesh = bpy.data.meshes.new("sky_bands")
    bm = bmesh.new()
    y0, y1 = -260.0 / 2 * SKY_SCALE, 260.0 / 2 * SKY_SCALE
    z = 0.0
    faces = []
    for i, (bh0, _) in enumerate(SKY_BANDS):
        bh = bh0 * SKY_SCALE
        v = [bm.verts.new(p) for p in ((SKY_X, y0, z), (SKY_X, y1, z),
                                       (SKY_X, y1, z + bh), (SKY_X, y0, z + bh))]
        f = bm.faces.new(v)
        f.material_index = i
        faces.append(f)
        z += bh
    bm.to_mesh(mesh)
    bm.free()
    sky = bpy.data.objects.new("sky_bands", mesh)
    sky_col.objects.link(sky)
    for i, (_, rgb) in enumerate(SKY_BANDS):
        sky.data.materials.append(_emat("load_skyband_%d" % i, rgb))
    for p in sky.data.polygons:
        p.use_smooth = False
    mark_noink(sky)

    # City: two ranks of flat box massing, height envelope peaked at y=0 so the
    # skyline crowds the road's vanishing point. Deterministic (seeded) so a rebuild
    # is the same city.
    rng = random.Random(seed)
    tower = False
    for rank, (rx, tone) in enumerate((
            (CITY_X + 2.5, CITY_FAR_TONE), (CITY_X, CITY_NEAR_TONE))):
        m = _emat("load_city_%d" % rank, tone)
        y = -52.0
        i = 0
        while y < 52.0:
            w = rng.uniform(1.4, 4.2)
            # The road runs into the city at y=0: keep a corridor open through BOTH
            # ranks, or a random block walls the street off and the road reads as
            # ending in a field (the owner's "gap to the city").
            if rank == 1 and y < 1.5 and y + w > -1.5:
                y = 1.5
            h = rng.uniform(0.6, 1.7) * (1.0 + 1.1 * math.exp(-(y / 14.0) ** 2))
            # Skyscrapers (owner: "taller — skyscrapers on the horizon", then
            # 2026-08-06 "50% taller again"): roughly a fifth of the near-rank
            # blocks become towers — narrow slabs, clustered toward the centre by
            # the same envelope.
            tower = rank == 1 and rng.random() < 0.22
            if tower:
                w = min(w, 2.2)
                h = rng.uniform(5.1, 9.0) * (1.0 + 0.8 * math.exp(-(y / 16.0) ** 2))
            ob = _box(city_col, "city_r%d_%d" % (rank, i), rx, y + w / 2, h / 2,
                      1.2, w, h, m)
            ob.data.materials[0] = m
            mark_noink(ob)
            # Detail pass (owner: "more detailed"): setback tiers on the taller
            # blocks, rooftop clutter, window-column strips. All same-tone or near-
            # tone flat geometry — detail through SILHOUETTE and faint value shifts,
            # never ink, so the city stays a distant object.
            if h > 1.6:                                   # setback tier
                tw = w * rng.uniform(0.45, 0.7)
                t = _box(city_col, "city_t%d_%d" % (rank, i), rx,
                         y + w / 2, h + 0.35, 1.0, tw, 0.7, m)
                mark_noink(t)
            if tower and h > 4.0:                         # towers get a second tier
                t2 = _box(city_col, "city_t2%d_%d" % (rank, i), rx,
                          y + w / 2, h + 0.95, 0.9, w * 0.35, 0.5, m)
                mark_noink(t2)
            if rank == 1 and rng.random() < 0.45:         # rooftop water tank / hut
                rt = _box(city_col, "city_rt%d_%d" % (rank, i), rx - 0.15,
                          y + w * rng.uniform(0.2, 0.8), h + 0.14,
                          0.3, rng.uniform(0.25, 0.5), 0.28, m)
                mark_noink(rt)
            if rank == 1 and rng.random() < 0.30:         # chimney/spire
                sp = _box(city_col, "city_sp%d_%d" % (rank, i), rx - 0.2,
                          y + w * rng.uniform(0.25, 0.75), h + 0.45,
                          0.14, 0.14, 0.9, m)
                mark_noink(sp)
            if tower:                                     # towers: tall window strip
                wm = _emat("load_city_win", (0.220, 0.260, 0.320))
                ws = _box(city_col, "city_tw%d_%d" % (rank, i),
                          rx - 0.62, y + w / 2, h * 0.5, 0.02, w * 0.42, h * 0.8, wm)
                mark_noink(ws)
            if rank == 1 and w > 2.0:                     # window-column strips
                wm = _emat("load_city_win", (0.220, 0.260, 0.320))
                for k in range(int(w / 0.8)):
                    wy = y + 0.45 + k * 0.8
                    if wy > y + w - 0.35:
                        break
                    ws = _box(city_col, "city_w%d_%d_%d" % (rank, i, k),
                              rx - 0.62, wy, h * 0.45, 0.02, 0.30, h * 0.62, wm)
                    mark_noink(ws)
            if detail >= 2:
                by = y + w / 2
                dm = _emat("load_city_dark", CITY_DARK_TONE)
                wm2 = _emat("load_city_win", (0.220, 0.260, 0.320))
                # Shaded return: only visible on blocks right of the axis (y < 0),
                # whose +Y flank turns away from the southern sun.
                if by < -0.6:
                    sf = _box(city_col, "city_sh%d_%d" % (rank, i), rx - 0.02,
                              y + w, h / 2, 1.16, 0.06, h, dm)
                    mark_noink(sf)
                cor = _box(city_col, "city_co%d_%d" % (rank, i), rx - 0.03,
                           by, h + 0.04, 1.26, w + 0.10, 0.10, dm)   # cornice
                mark_noink(cor)
                if w > 1.2:                                   # pilaster rhythm
                    for k in range(max(2, int(w / 0.55))):
                        px = y + 0.18 + k * 0.55
                        if px > y + w - 0.14:
                            break
                        pil = _box(city_col, "city_pl%d_%d_%d" % (rank, i, k),
                                   rx - 0.63, px, h * 0.5, 0.02, 0.07, h * 0.9, dm)
                        mark_noink(pil)
                if rank == 1 and w <= 2.0:                    # windows on the narrow ones too
                    for k in range(max(1, int(w / 0.7))):
                        wy2 = y + 0.30 + k * 0.7
                        if wy2 > y + w - 0.25:
                            break
                        ws2 = _box(city_col, "city_nw%d_%d_%d" % (rank, i, k),
                                   rx - 0.62, wy2, h * 0.45, 0.02, 0.22, h * 0.6, wm2)
                        mark_noink(ws2)
            y += w + rng.uniform(0.4, 1.6)
            i += 1

    # Haze: grounds the silhouette — but SPLIT around the road corridor. One unbroken
    # strip occluded the road's last stretch, so the street visibly ended in haze a
    # dozen units short of the skyline (the owner's "gap to the city").
    for tag, y0h, y1h in (("s", -121.3, -1.3), ("n", 1.3, 121.3)):
        hz = _box(city_col, "haze_" + tag, CITY_X - 1.6, (y0h + y1h) / 2, 0.65,
                  0.1, y1h - y0h, 1.5, _emat("load_haze", HAZE_TONE))
        mark_noink(hz)

    # Corridor haze (owner: "the road runs out in the distance"). The split haze
    # strip deliberately leaves the road corridor open so the street runs INTO the
    # city; that same opening let the eye follow the road to its far end. Two low
    # walls ACROSS the corridor, in the horizon haze tone and NOINK, close it off
    # in depth: the road fades into atmosphere instead of ending. The far one is
    # taller so the near one reads as a lighter veil in front of it.
    for hi, (hx, hh) in enumerate(HAZE_WALLS):
        # FULL ground width, not just the corridor: at 9 units wide the wall stopped
        # the road but left the verge and field beyond it showing, so the street read
        # as running out into bare grass. Spanning the ground makes the whole far
        # field resolve into one atmospheric band, which is what haze does.
        cw = _box(city_col, "haze_corridor_%d" % hi, hx, 0.0, hh / 2,
                  0.1, 96.0, hh, _emat("load_haze", HAZE_TONE))
        mark_noink(cw)

    # Gate blocks: two deliberate taller buildings flanking the road's entry into the
    # city, so the corridor reads as a street between buildings rather than a slot.
    # Central skyscraper wall (owner: "basically touching across the middle"): a
    # deliberate cluster on the FAR rank spanning the road axis, so the street
    # visibly ends AT the city — tall slabs shoulder to shoulder behind the gates.
    wallm = _emat("load_city_wall", CITY_FAR_TONE)
    for wi, (wy, ww, wh) in enumerate(((-6.8, 2.2, 8.4), (-4.2, 1.8, 11.1),
                                       (-1.6, 2.4, 9.3), (1.2, 1.9, 12.3),
                                       (3.4, 2.1, 9.9), (5.8, 2.3, 7.8))):
        tw = _box(city_col, "city_wall_%d" % wi, CITY_X + 2.5, wy, wh / 2,
                  1.2, ww, wh, wallm)
        mark_noink(tw)
        cap = _box(city_col, "city_wallc_%d" % wi, CITY_X + 2.5, wy, wh + 0.3,
                   1.0, ww * 0.55, 0.6, wallm)
        mark_noink(cap)
        wsm = _emat("load_city_win", (0.220, 0.260, 0.320))
        wstrip = _box(city_col, "city_wallw_%d" % wi, CITY_X + 2.5 - 0.62, wy,
                      wh * 0.5, 0.02, ww * 0.4, wh * 0.8, wsm)
        mark_noink(wstrip)

    # The gates must stand IN FRONT of the haze (haze x = CITY_X - 1.6) or the wash
    # fades them to ghosts and the corridor loses its frame.
    gm = _emat("load_city_gate", (0.245, 0.290, 0.350))
    gx = CITY_X - 2.6
    for tag, gy in (("s", -2.5), ("n", 2.5)):
        g = _box(city_col, "city_gate_" + tag, gx, gy, 1.15, 1.2, 2.4, 2.3, gm)
        mark_noink(g)
        gt = _box(city_col, "city_gate_t_" + tag, gx, gy, 2.62, 1.0, 1.4, 0.65, gm)
        mark_noink(gt)

    # Clouds (owner rev 2): FLAT BOTTOMS — every puff disc is bottom-aligned on one
    # line (centre z = bottom + r), with a fill slab down to that line — plus a light
    # grey underside band drawn just in front for shading, and real size variety
    # (one long, one tall, two small). All emission + NOINK: only silhouette + the
    # two flat tones read, which is the poster grammar.
    cm = _emat("load_cloud", (0.930, 0.905, 0.830))
    sm = _emat("load_cloud_shade", (0.760, 0.735, 0.660))
    CLOUDS = [
        #  cy     bottom  scale  puffs (dy, r)
        (-27.0, 15.5, 1.35, ((-3.6, 1.1), (-1.4, 1.9), (1.2, 2.3), (3.8, 1.5), (5.9, 0.9))),
        ( -5.0, 20.5, 0.85, ((-1.6, 1.2), (0.4, 1.9), (2.2, 1.1))),
        ( 13.0, 13.8, 1.10, ((-2.2, 1.3), (0.0, 2.6), (2.6, 1.6))),   # tall head
        ( 31.0, 18.0, 0.70, ((-1.8, 1.1), (0.2, 1.6), (1.9, 1.0))),
    ]
    for ci, (cy, cz0, sc_f, puffs) in enumerate(CLOUDS):
        y_lo = min(dy - r for dy, r in puffs) * sc_f
        y_hi = max(dy + r for dy, r in puffs) * sc_f
        for pi, (dy, r) in enumerate(puffs):
            rr = r * sc_f
            m2 = bpy.data.meshes.new("cloud%d_%d" % (ci, pi))
            bm2 = bmesh.new()
            bmesh.ops.create_cone(bm2, cap_ends=True, segments=24,
                                  radius1=rr, radius2=rr, depth=0.1)
            bmesh.ops.rotate(bm2, cent=(0, 0, 0),
                             matrix=mathutils.Matrix.Rotation(math.radians(90), 3, 'Y'),
                             verts=bm2.verts)
            bmesh.ops.translate(bm2, vec=(84.0, cy + dy * sc_f, cz0 + rr), verts=bm2.verts)
            bm2.to_mesh(m2)
            bm2.free()
            ob = bpy.data.objects.new("cloud%d_%d" % (ci, pi), m2)
            city_col.objects.link(ob)
            ob.data.materials.append(cm)
            for pl in ob.data.polygons:
                pl.use_smooth = False
            mark_noink(ob)
        # Fill between puff bottoms and the flat base line.
        fill = _box(city_col, "cloud%d_fill" % ci, 84.0, cy + (y_lo + y_hi) / 2,
                    cz0 + 0.45 * sc_f, 0.1, (y_hi - y_lo) * 0.96, 0.9 * sc_f, cm)
        mark_noink(fill)
        # Underside shading: a light grey band hugging the flat bottom, in FRONT of
        # the white so it wins the depth test, inset so no grey pokes past the rim.
        shade = _box(city_col, "cloud%d_shade" % ci, 83.7, cy + (y_lo + y_hi) / 2,
                     cz0 + 0.24 * sc_f, 0.1, (y_hi - y_lo) * 0.80, 0.48 * sc_f, sm)
        mark_noink(shade)
    # Push the city back WITHOUT changing how it looks: scaling every vertex about
    # the start camera leaves the projection from that camera exactly unchanged, so
    # the approved skyline survives while physically retreating behind the new
    # end-of-street buildings.
    if CITY_PUSH != 1.0:
        pivot = mathutils.Vector((CAM_X, 0.0, 0.62))
        for ob in city_col.objects:
            if ob.type != 'MESH':
                continue
            for v in ob.data.vertices:
                w0 = ob.matrix_world @ v.co
                v.co = ob.matrix_world.inverted() @ (pivot + (w0 - pivot) * CITY_PUSH)

    for c in (sky_col, city_col):
        for ob in c.objects:
            ob.visible_shadow = False
    return {"sky_bands": len(SKY_BANDS), "city_objects": len(city_col.objects)}


# ── Parallax layers ──────────────────────────────────────────────────────────
# Depth slices for the Godot push-in. Scaled about the vanishing point at different
# rates, back to front. The street (ground+road) spans every depth, so it rides at the
# NEAR rate — the standard 2.5D-push cheat, invisible at the subtle zoom used here.
FAR_SLOTS = ("off_d", "fur_b", "pp_a", "pp_b", "pet_a", "off_e", "fac_e", "off_f")

# PAINT ORDER MATTERS: the street (ground/road/walks) spans EVERY depth, so it sits
# just above the backdrop — painting it last overdraws tree trunks and building bases
# (caught on the shadowed composite: the whole cast floated on the lawn). It still
# RIDES at the near rate in Godot, same as L4 — that pairing is what keeps building-
# to-ground contact stable during the push; far contacts slide a hair, masked by haze.
# Layers are sliced by the PLANE their content stands on, not by distance. Under a
# forward dolly every plane PARALLEL to the travel axis maps by an exact homography,
# and this street is three such plane families: the ground (z=0) and the two facade
# rows (y = +/-BUILDING_FRONT_Y). Warping each by its own homography reproduces true
# perspective motion — facades shear open, the road and its dashes stream toward the
# camera — from five stills, with no extra renders. `plane` below tells the renderer
# which warp to use: ("ground", z) | ("wall", y) | ("depth", x) for far backdrops.
LAMP_Y = ROAD_HALF_W + 0.30

_north_cache = []
_south_cache = []


def _south_slots():
    """Explicit membership, not "whatever is not north" — that catch-all silently
    swept stray collections into the south layer and warped them backwards."""
    if not _south_cache:
        _south_cache.extend(sl[0] for sl in SLOTS if sl[5] == "s")
    return _south_cache


def _north_slots():
    """Slot suffixes on the north row. Lazy: SLOTS is defined further down the file,
    and the LAYERS lambdas only run at render time, by which point it exists."""
    if not _north_cache:
        _north_cache.extend(sl[0] for sl in SLOTS if sl[5] == "n")
    return _north_cache

LAYERS = [
    ("L0_sky",     lambda n: n == "LOAD_sky"),
    ("L1_city",    lambda n: n == "LOAD_city"),
    ("L2_ground",  lambda n: n == "LOAD_street"),
    ("L3_north",   lambda n: (n.startswith("LOAD_bldg_") and n[10:] in _north_slots())
                   or n == "LOAD_props_n"),
    ("L4_south",   lambda n: (n.startswith("LOAD_bldg_") and n[10:] in _south_slots())
                   or n == "LOAD_props_s"),
    ("L5_lamp_n",  lambda n: n == "LOAD_props_lamp_n"),
    ("L6_lamp_s",  lambda n: n == "LOAD_props_lamp_s"),
    ("L7_vehicles", lambda n: n == "LOAD_props_veh"),
]

# Plane each layer rides, for the dolly warp (consumed by parallax_preview / Godot).
LAYER_PLANES = {
    "L0_sky":    ("depth", SKY_X),
    "L1_city":   ("depth", CITY_X),
    "L2_ground": ("ground", 0.0),
    "L3_north":  ("wall", BUILDING_FRONT_Y),
    "L4_south":  ("wall", -BUILDING_FRONT_Y),
    "L5_lamp_n": ("wall", LAMP_Y),
    "L6_lamp_s": ("wall", -LAMP_Y),
    "L7_vehicles": ("ground", 0.0),   # they stand on the road; the film path ignores this
}


def _show_only_load(pred):
    """Per-layer isolation for the SHADOWED scene: excluded objects become
    CAMERA-INVISIBLE but remain in the render as SHADOW CASTERS (visible_camera off,
    visible_shadow on). Plain hiding removes their cast shadows too, so the street
    layer would render without a single building or tree shadow and the composite
    would lose the ground shade entirely. Collections stay render-enabled; only the
    per-object camera flag varies. (Also the FINE_INK lesson, still: per OBJECT.)"""
    for c in bpy.data.collections:
        if not c.name.startswith("LOAD_"):
            continue
        c.hide_render = False
        c.hide_viewport = False
        included = pred(c.name)
        for ob in c.objects:
            ob.hide_render = False
            ob.hide_viewport = False
            ob.visible_camera = included
            ob.is_holdout = False


def _geo_mask_override(to_sun):
    """Geometric light-mask material: emission = 0.2 + 0.8*max(0, dot(N', to_sun)),
    N' = normal flipped toward the camera when backfacing. Render with 'Standard'
    view transform; see the mask block in render_layers for why this exists."""
    mat = bpy.data.materials.get("_geo_mask_override")
    if mat is None:
        mat = bpy.data.materials.new("_geo_mask_override")
        mat.use_nodes = True
        nt = mat.node_tree
        nt.nodes.clear()
        geo = nt.nodes.new("ShaderNodeNewGeometry")
        neg2 = nt.nodes.new("ShaderNodeMath"); neg2.operation = 'MULTIPLY'
        neg2.inputs[1].default_value = -2.0
        plus1 = nt.nodes.new("ShaderNodeMath"); plus1.operation = 'ADD'
        plus1.inputs[1].default_value = 1.0
        flip = nt.nodes.new("ShaderNodeVectorMath"); flip.operation = 'SCALE'
        sunv = nt.nodes.new("ShaderNodeCombineXYZ"); sunv.name = "sun_vec"
        dot = nt.nodes.new("ShaderNodeVectorMath"); dot.operation = 'DOT_PRODUCT'
        mx = nt.nodes.new("ShaderNodeMath"); mx.operation = 'MAXIMUM'
        mx.inputs[1].default_value = 0.0
        mad = nt.nodes.new("ShaderNodeMath"); mad.operation = 'MULTIPLY_ADD'
        mad.inputs[1].default_value = 0.8
        mad.inputs[2].default_value = 0.2
        em = nt.nodes.new("ShaderNodeEmission")
        out = nt.nodes.new("ShaderNodeOutputMaterial")
        nt.links.new(geo.outputs["Backfacing"], neg2.inputs[0])
        nt.links.new(neg2.outputs[0], plus1.inputs[0])
        nt.links.new(geo.outputs["Normal"], flip.inputs[0])
        nt.links.new(plus1.outputs[0], flip.inputs["Scale"])
        nt.links.new(flip.outputs[0], dot.inputs[0])
        nt.links.new(sunv.outputs[0], dot.inputs[1])
        nt.links.new(dot.outputs["Value"], mx.inputs[0])
        nt.links.new(mx.outputs[0], mad.inputs[0])
        nt.links.new(mad.outputs[0], em.inputs["Strength"])
        nt.links.new(em.outputs[0], out.inputs["Surface"])
    sv = mat.node_tree.nodes["sun_vec"]
    sv.inputs[0].default_value = to_sun.x
    sv.inputs[1].default_value = to_sun.y
    sv.inputs[2].default_value = to_sun.z
    return mat


def render_layers(out_dir=None, width=2400, height=1350):
    """Render each parallax layer alone, at overscan resolution for push headroom.

    Freestyle thickness is ABSOLUTE px, so it scales with the canvas (2400/1920) —
    otherwise the layers' ink is thinner than the 1920 hero and the composite look
    drifts from the approved frame."""
    import os
    if out_dir is None:
        out_dir = "/Users/crisu/Price of Everything/blender-assets/renders/loading/layers"
    os.makedirs(out_dir, exist_ok=True)
    sc = get_scene()
    k = width / 1920.0
    sc.render.resolution_x = width
    sc.render.resolution_y = height
    fs = sc.view_layers[0].freestyle_settings
    fs.linesets["ink"].linestyle.thickness = 2.4 * k
    fs.linesets["contour"].linestyle.thickness = 7.0 * k
    if "ink_fine" in fs.linesets:
        fs.linesets["ink_fine"].linestyle.thickness = 1.05 * k
    done = []
    for name, pred in LAYERS:
        _show_only_load(pred)
        # BUILDING layers: the street is not merely excluded, it's a HOLDOUT —
        # it must still OCCLUDE and cut alpha. Camera-invisible ground exposed the
        # buildings' below-grade apron kerbs (hidden by the verge in the full
        # scene), and the composite painted them over the street as a dark band
        # under the construction site (owner: "looks like it's floating").
        if name not in ("L0_sky", "L1_city", "L2_ground"):
            cc = bpy.data.collections.get("LOAD_street")
            if cc:
                for ob in cc.objects:
                    ob.visible_camera = True
                    ob.is_holdout = True
        # ...and the GROUND layer holds out the backdrop. The ground runs to x=230,
        # far past the haze walls, but it is composited ON TOP of the city layer —
        # so without this the far verge paints straight over the haze meant to hide
        # it, and the street reads as running out into bare grass beyond the road's
        # dissolve. Holdout cuts the alpha instead, letting the haze show through.
        if name == "L2_ground":
            for cn in ("LOAD_city", "LOAD_sky"):
                cc = bpy.data.collections.get(cn)
                if cc:
                    for ob in cc.objects:
                        ob.visible_camera = True
                        ob.is_holdout = True
        # Freestyle ignores visible_camera and inks every hidden caster as a ghost
        # wireframe. The rig's face-mark exclusion is the kill switch: temporarily
        # mark ALL faces of excluded objects (they keep casting shadows, camera-
        # invisible, ink-suppressed), then strip the attribute after the render.
        # Objects that already carry the attribute (permanent NOINK: sky, city,
        # verges, patches) are left alone.
        temp_marked = []
        for c in bpy.data.collections:
            if not c.name.startswith("LOAD_"):
                continue
            if pred(c.name):
                continue
            for ob in c.objects:
                if ob.type != 'MESH':
                    continue
                if ob.data.attributes.get("freestyle_face") is not None:
                    continue
                attr = ob.data.attributes.new("freestyle_face", 'BOOLEAN', 'FACE')
                for d in attr.data:
                    d.value = True
                temp_marked.append(ob.name)
        # COLOUR pass renders FLAT (owner 2026-08-06: "use only stippling of
        # different densities" for shading) — sun off, ambient boosted to the LIT
        # MIX: white 0.45 ambient + warm sun direct 3.6*cos48/pi*(1.0,0.955,0.87)
        # = (1.22, 1.18, 1.12). Plain white 1.22 loses the sun's warmth and veils
        # the whole frame cool — the tint must ride the ambient. Every surface then
        # carries its lit palette tone and ALL light/shade information lives in the
        # stipple pass. Emission backdrop (sky/city/clouds) ignores lights anyway.
        sun_flat = bpy.data.objects.get("LoadSun")
        wbg = sc.world.node_tree.nodes.get("Background") if sc.world else None
        if sun_flat:
            sun_flat.data.energy = 0.0
        if wbg:
            wbg.inputs[0].default_value = (1.0, 0.972, 0.918, 1.0)
            wbg.inputs[1].default_value = 1.216
        sc.render.filepath = os.path.join(out_dir, name)
        bpy.ops.render.render(write_still=True)
        if sun_flat:
            sun_flat.data.energy = 3.6
        if wbg:
            wbg.inputs[0].default_value = (1.0, 1.0, 1.0, 1.0)
            wbg.inputs[1].default_value = 0.45
        # LIGHT MASK for the scene stipple: same camera, white override, no ink,
        # backdrop hidden (emission under an override would read as shaded and
        # collect dots). Pure illumination -> scene_stipple.py bands from it.
        if name not in ("L0_sky", "L1_city"):
            ov = bpy.data.materials.get("_light_mask_override")
            if ov is None:
                ov = bpy.data.materials.new("_light_mask_override")
                ov.use_nodes = True
                b = ov.node_tree.nodes.get("Principled BSDF")
                b.inputs["Base Color"].default_value = (0.8, 0.8, 0.8, 1.0)
                b.inputs["Roughness"].default_value = 1.0
                b.inputs["Specular IOR Level"].default_value = 0.0
            vl = sc.view_layers[0]
            backdrop_state = []
            for cn in ("LOAD_sky", "LOAD_city"):
                cc = bpy.data.collections.get(cn)
                if cc:
                    for ob in cc.objects:
                        backdrop_state.append((ob.name, ob.hide_render))
                        ob.hide_render = True
            # Owner: "fully lit facades carry no stipple". Two mask recipes:
            # - STREET (horizontal surfaces, correct normals, correct shadows):
            #   white diffuse override under the real sun — cast tree/building
            #   shade survives into the mask and gets the deepest dot band.
            # - BUILDINGS (L3/L4): some builder wall faces carry unreliable
            #   normals — a bare control cube lights to 0.76 in the very render
            #   where a facade of identical orientation sits at ambient — so no
            #   diffuse render can classify them. Instead the mask is computed
            #   GEOMETRICALLY in the override shader: emission = 0.2 + 0.8 *
            #   max(0, dot(N', to_sun)) with N' backfacing-corrected (closed
            #   boxes always show the camera their outward side, so flipping
            #   away-pointing normals recovers the true orientation), rendered
            #   under the Standard view transform for predictable values.
            #   scene_stipple gets per-layer cuts to match (0.55/0.30).
            # The crane's lattice jib throws a long THIN dashed shadow line across
            # the entrance lawn — geometrically true, but at dot scale it reads
            # as a dirt trail, not shade (owner). The crane alone stops casting
            # into the street mask; ballast and containers keep their blobs.
            crane_state = []
            if name == "L2_ground":
                cc2 = bpy.data.collections.get("LOAD_bldg_con_a")
                if cc2:
                    for ob2 in cc2.objects:
                        if ob2.type == 'MESH' and ob2.name.split(".")[0].startswith("crane"):
                            crane_state.append((ob2.name, ob2.visible_shadow))
                            ob2.visible_shadow = False
            use_geo = name != "L2_ground"
            vt_prev = sc.view_settings.view_transform
            if use_geo:
                sun_ob = bpy.data.objects.get("LoadSun")
                to_sun = (sun_ob.matrix_world.to_3x3() @ mathutils.Vector((0, 0, 1))).normalized()
                vl.material_override = _geo_mask_override(to_sun)
                sc.view_settings.view_transform = 'Standard'
            else:
                vl.material_override = ov
            sc.render.use_freestyle = False
            os.makedirs(os.path.join(out_dir, "masks"), exist_ok=True)
            sc.render.filepath = os.path.join(out_dir, "masks", name)
            bpy.ops.render.render(write_still=True)
            vl.material_override = None
            sc.render.use_freestyle = True
            sc.view_settings.view_transform = vt_prev
            for obname2, vs in crane_state:
                ob2 = bpy.data.objects.get(obname2)
                if ob2:
                    ob2.visible_shadow = vs
            for obname2, hr in backdrop_state:
                ob = bpy.data.objects.get(obname2)
                if ob:
                    ob.hide_render = hr
        for obname in temp_marked:
            ob = bpy.data.objects.get(obname)
            if ob and ob.type == 'MESH':
                attr = ob.data.attributes.get("freestyle_face")
                if attr is not None:
                    ob.data.attributes.remove(attr)
        done.append(name)
    # Restore: everything camera-visible, hero-resolution ink.
    _show_only_load(lambda n: True)
    sc.render.resolution_x = 1920
    sc.render.resolution_y = 1080
    fs.linesets["ink"].linestyle.thickness = 2.4
    fs.linesets["contour"].linestyle.thickness = 7.0
    if "ink_fine" in fs.linesets:
        fs.linesets["ink_fine"].linestyle.thickness = 1.05
    return {"layers": done, "out": out_dir, "res": [width, height]}


def render_stations(n=6, spacing=2.25, out_root=None, width=2400, height=1350):
    """Render the layer set from N camera positions down the street.

    A single still can only be dollied so far: the nearest building is ~5 units
    ahead, and past ~4.5 of advance it tears apart because nothing was rendered
    behind it. Stations refresh both resolution and occlusion — the player is
    cross-faded from one to the next while both are warping, so the joins read as
    continued motion rather than cuts (impostor/LOD morphing). Each station only
    has to cover `spacing` of travel, which keeps its worst-case magnification at
    spacing/(5.3-spacing) and well inside the tearing limit.

    Writes progress.json after every station: this takes tens of minutes and the
    MCP call will time out long before it finishes, so the log on disk is how the
    run is followed.
    """
    import os
    import json
    if out_root is None:
        out_root = "/Users/crisu/Price of Everything/blender-assets/renders/loading/stations"
    os.makedirs(out_root, exist_ok=True)
    sc = get_scene()
    cam = bpy.data.objects["LoadCam"]
    done = []
    logf = os.path.join(out_root, "progress.json")
    with open(logf, "w") as f:
        json.dump({"done": [], "total": n, "spacing": spacing, "state": "start"}, f)
    for i in range(n):
        cam.location.x = CAM_X + i * spacing
        sub = os.path.join(out_root, "s%d" % i)
        try:
            render_layers(out_dir=sub, width=width, height=height)
            done.append({"i": i, "cam_x": round(cam.location.x, 3)})
            state = "ok"
        except Exception as exc:                      # keep the log honest
            done.append({"i": i, "error": str(exc)})
            state = "error"
        with open(logf, "w") as f:
            json.dump({"done": done, "total": n, "spacing": spacing,
                       "state": state}, f)
        if state == "error":
            break
    cam.location.x = CAM_X
    return {"stations": len(done), "out": out_root}


# ── The film: rendered in CHUNKS ────────────────────────────────────────────
# Travel runs from the start camera to TRAVEL_MAX_FRAC of the built row, which is
# where the far end starts to thin out. 447 keyframes over 45s at ~40s a keyframe
# is about 5 hours all in (owner asked for denser frames than the 3.9h/351 plan),
# and each keyframe then covers ~3 output frames at 30fps — the same interpolation
# ratio the dense probe validated.
FILM_START_X = CAM_X
FILM_END_X = 81.8               # 75% of the built row, the agreed cap
FILM_N = 447
FILM_SECONDS = 45.0
FILM_STEP = (FILM_END_X - FILM_START_X) / (FILM_N - 1)
FILM_DIR = "/Users/crisu/Price of Everything/blender-assets/renders/loading/film"


def build_film_scene(detail=1):
    """Everything a chunk needs standing up, once."""
    bpy.context.window.scene = get_scene()
    phase0()
    build_backdrop(detail=detail)
    phase1()
    phase3()
    setup_load_rig()


def render_film_chunk(i0, i1, out_dir=None, res=(2400, 1350), rebuild=True):
    """Render keyframes [i0, i1). Chunks so a run can be stopped, inspected and
    resumed without redoing work — and so a mistake costs one chunk, not a night.

    The city LOD flips at the halfway mark, so a chunk that straddles it rebuilds
    the backdrop mid-run; chunks that do not, do not pay for it.
    """
    import json
    import os
    out_dir = out_dir or FILM_DIR
    os.makedirs(out_dir, exist_ok=True)
    half = FILM_START_X + (FILM_END_X - FILM_START_X) * 0.5
    lod = 1 if (FILM_START_X + i0 * FILM_STEP) < half else 2
    # Standing the street up costs ~16 min (19 builders, thousands of objects) and
    # is a per-CHUNK fixed cost, not per-frame. Skip it when the scene is already
    # built at the right LOD — that is most of the difference between 5 chunks
    # costing 6.25h and 5.0h.
    if rebuild:
        build_film_scene(detail=lod)
    to_sun = (bpy.data.objects["LoadSun"].matrix_world.to_3x3()
              @ mathutils.Vector((0, 0, 1))).normalized()
    geo = _geo_mask_override(to_sun)
    log = os.path.join(out_dir, "chunk_%04d_%04d.json" % (i0, i1))
    # A chunk holds Blender's main thread for the best part of an hour, which also
    # blocks the MCP server — so there is no way to ask it to stop from outside
    # once it is running. It therefore watches for a sentinel file instead:
    #     touch <FILM_DIR>/STOP
    # Checked every 5 frames (a few minutes at ~40s a frame), and the file is
    # cleared on exit so the next chunk is not stopped by a stale one.
    stop_path = os.path.join(out_dir, "STOP")
    if os.path.exists(stop_path):
        os.remove(stop_path)
    for idx in range(i0, i1):
        if (idx - i0) % 5 == 0 and os.path.exists(stop_path):
            os.remove(stop_path)
            with open(log, "w") as f:
                json.dump({"done": idx - i0, "total": i1 - i0, "next_idx": idx,
                           "state": "stopped"}, f)
            return {"stopped_at": idx, "resume_with": [idx, i1]}
        cx = FILM_START_X + idx * FILM_STEP
        if lod == 1 and cx >= half:
            build_backdrop(detail=2)
            setup_load_rig()
            lod = 2
            to_sun = (bpy.data.objects["LoadSun"].matrix_world.to_3x3()
                      @ mathutils.Vector((0, 0, 1))).normalized()
            geo = _geo_mask_override(to_sun)
        render_film_frame(out_dir, idx, cx, geo_mat=geo, res=res)
        with open(log, "w") as f:
            json.dump({"done": idx - i0 + 1, "total": i1 - i0,
                       "idx": idx, "cam_x": round(cx, 2), "state": "ok"}, f)
    return {"rendered": i1 - i0}


def render_film_frame(out_dir, idx, cam_x, geo_mat=None, res=(2400, 1350)):
    """The three passes one film keyframe needs, with the isolation done right.

    colour : flat (sun off, warm ambient), sky plane hidden — the vivid sky is
             composited in post because AgX crushes the emission bands.
    _geo   : geometric light mask, orientation only, for the walls.
    _gnd   : diffuse mask of the GROUND, for real cast shadows on road and lawn.

    THE TRAP, and why this lives here instead of being retyped per render: the
    ground mask isolates the street by making everything else camera-INVISIBLE.
    That leaves the ground BEHIND a building visible in the mask, so those pixels
    report "ground" while the colour pass shows a wall — and the ground's cast
    shadows print straight across building facades. Everything else must be a
    HOLDOUT instead: it still occludes and cuts the mask's alpha, so the wall
    falls through to the wall bands, and it keeps casting real shadows.
    """
    import os
    sc = get_scene()
    cam = bpy.data.objects["LoadCam"]
    sun = bpy.data.objects["LoadSun"]
    wbg = sc.world.node_tree.nodes.get("Background")
    vl = sc.view_layers[0]
    ov = bpy.data.materials.get("_light_mask_override")
    if geo_mat is None:
        to_sun = (sun.matrix_world.to_3x3() @ mathutils.Vector((0, 0, 1))).normalized()
        geo_mat = _geo_mask_override(to_sun)
    os.makedirs(out_dir, exist_ok=True)
    sc.render.resolution_x, sc.render.resolution_y = res
    fs = vl.freestyle_settings
    k = res[0] / 1920.0
    fs.linesets["ink"].linestyle.thickness = 2.4 * k
    fs.linesets["contour"].linestyle.thickness = 7.0 * k
    if "ink_fine" in fs.linesets:
        fs.linesets["ink_fine"].linestyle.thickness = 1.05 * k

    cam.location.x = cam_x
    place_vehicles(advance=cam_x - CAM_X, cam_x=cam_x)
    street = bpy.data.collections["LOAD_street"]
    sky_objs = list(bpy.data.collections["LOAD_sky"].objects)
    city_objs = list(bpy.data.collections["LOAD_city"].objects)
    _show_only_load(lambda n: True)

    for ob in sky_objs:
        ob.hide_render = True
    sun.data.energy = 0.0
    wbg.inputs[0].default_value = (1.0, 0.972, 0.918, 1.0)
    wbg.inputs[1].default_value = 1.216
    sc.render.filepath = os.path.join(out_dir, "f%03d" % idx)
    bpy.ops.render.render(write_still=True)
    sun.data.energy = 3.6
    wbg.inputs[0].default_value = (1.0, 1.0, 1.0, 1.0)
    wbg.inputs[1].default_value = 0.45

    for ob in city_objs:
        ob.hide_render = True
    sc.render.use_freestyle = False
    prev_vt = sc.view_settings.view_transform
    vl.material_override = geo_mat
    sc.view_settings.view_transform = 'Standard'
    sc.render.filepath = os.path.join(out_dir, "f%03d_geo" % idx)
    bpy.ops.render.render(write_still=True)
    sc.view_settings.view_transform = prev_vt

    for ob in street.objects:
        ob.visible_camera = True
        ob.is_holdout = False
    for c in bpy.data.collections:
        if c.name.startswith("LOAD_") and c is not street:
            for ob in c.objects:
                ob.visible_camera = True
                ob.is_holdout = True          # occlude + cut alpha, keep casting
    vl.material_override = ov
    sc.render.filepath = os.path.join(out_dir, "f%03d_gnd" % idx)
    bpy.ops.render.render(write_still=True)
    vl.material_override = None
    sc.render.use_freestyle = True

    _show_only_load(lambda n: True)
    for ob in sky_objs + city_objs:
        ob.hide_render = False
    return {"idx": idx, "cam_x": cam_x}


# ── Phase 1: buildings along the street ──────────────────────────────────────
# Slot: (collection suffix, builder fn name, level, z-rotation deg, x centre).
# Rotation puts each building's MORE DETAILED LONG SIDE toward the street (owner rule):
#   factory  -> rz -90: the windowed +X long wall swings to face -Y (the street), long
#               axis along the street; the gabled loading-bay end faces west.
#   furnace  -> rz 0: the ember-lit door front already faces -Y.
#   powerplant -> rz 0: transformer/pylon yard and hall front face -Y.
# Zones: primary (likely ~11s of pan) carries the hero cast; the cushion repeats the
# builders at other levels so a slow load never halts on sparse content; the last slot
# is the terminal vista a >60s load rests on.
# Slot: (suffix, builder kind, level/variant, rz deg, x centre, side).
# side "n" = north row (detailed front faces -Y = the road, builders' default);
# side "s" = south row (rotated so the front faces +Y = the road).
# Depth order builds the skyline: offices and factories near the camera, the big
# stack-and-tower plants further east so they stand against the city (P2).
SLOTS = [
    # entrance (owner): construction site first on the LEFT; the right entrance is
    # the park, planted in phase3. rz 180 is the one orientation that brings the
    # CRANE (built centre-back of the sprite) to the street edge, where the frame's
    # wide FOV can still see it — every other rotation leaves it mid-lot, which this
    # close to camera is off-frame left. _stage_con_a() then rescales it into shot.
    ("con_a", "construction", 0, 180.0,  -6.1, "n"),
    # near (west, large in frame)
    ("off_a", "office",      1, 180.0,   2.5, "s"),   # moved east: the park owns the right entrance
    ("fac_a", "factory",     3,  -90.0,  1.5, "n", 0.9),   # L3; set back for the annex
    ("off_b", "office",      2, 180.0,   9.5, "s"),
    ("pol_a", "poly",        2,   0.0,  12.5, "n"),
    # mid
    ("fur_a", "furnace",     3, 180.0,  17.0, "s"),
    ("off_c", "office",      3,   0.0,  24.0, "n"),
    ("fac_b", "factory",     3,  90.0,  27.5, "s"),
    ("pet_a", "petro",       2,   0.0,  34.0, "n"),
    # far (against the city)
    ("off_d", "office",      4, 180.0,  40.0, "s"),
    ("fur_b", "furnace",     2,   0.0,  45.0, "n"),
    ("pp_a",  "powerplant",  3, 180.0,  52.0, "s"),
    ("pp_b",  "powerplant",  2,   0.0,  60.0, "n"),
    # approach: small fillers bridging the last plants to the city skyline, so the
    # street runs continuously INTO the city instead of stopping 14 units short of
    # it (the owner's "gap to the city" — the other half of the fix, with the
    # corridor through the haze).
    ("off_e", "office",      1, 180.0, 66.0, "s"),
    ("fac_e", "factory",     1, -90.0, 67.5, "n"),
    ("off_f", "office",      2,   0.0, 71.5, "n"),
    # End of the street (owner): a construction site on the RIGHT and a power plant
    # on the LEFT, extending the built row from 73 to ~89 so the dolly has content
    # ahead of it for longer.
    ("con_b", "construction", 0, 180.0, 78.0, "s"),
    ("pp_c",  "powerplant",   3,   0.0, 86.0, "n"),
    # THE PORT terminates the street. Left (north) bank gets two construction
    # sites; the right (south) bank is the docks, which is about four slots wide
    # and brings its own water — that water is the street's waterfront, so the
    # last south building before it needs clearance or it stands in the sea.
    ("con_c", "construction", 0,   0.0,  96.0, "n"),
    ("con_d", "construction", 0,   0.0, 108.0, "n"),
    # rz -90 turns the docks a quarter: its SHORE ROAD, which runs along the local
    # Y axis on the sprite's left side, becomes world X and so continues the main
    # road straight to the end of the composition. It also swings the bay away from
    # the street (opening to -Y) instead of across it. No setback — the shore edge
    # meets the verge, and _stage_port drops the whole thing so its land surface
    # sits at street level rather than 0.6 above it.
    ("port_a", "docks",       0, -90.0, 100.0, "s", 0.0),
]

# Every builder file defines a module-level LEVELS and reads it from its exec namespace,
# so exec'ing two builders into ONE namespace makes the second silently feed its LEVELS
# to the first (build_factory read the power plant's table: KeyError 'bays'). Each
# builder therefore gets its OWN namespace; the returned function's __globals__ is that
# namespace, so its LEVELS resolves correctly.
_BASE = "/Users/crisu/Price of Everything/blender-assets/"
BUILDERS = {
    "construction": ("construction_site_builder.py", "build_construction_site", "BLDG_construction"),
    "factory":    ("factory_builder.py",       "build_factory",       "BLDG_factory"),
    "furnace":    ("furnace_builder.py",       "build_furnace",       "BLDG_furnace"),
    "powerplant": ("power_plant_builder.py",   "build_power_plant",   "BLDG_powerplant"),
    "poly":       ("poly_plant_builder.py",    "build_poly_plant",    "BLDG_poly"),
    "petro":      ("petro_refinery_builder.py","build_petro_refinery","BLDG_petro"),
    "office":     ("office_builder.py",        "build_office",        "BLDG_office"),
    "docks":      ("docks_builder.py",         "build_docks",         "BLDG_docks"),
}
_builder_cache = {}


def _builder(kind):
    if kind not in _builder_cache:
        file, fn_name, col_name = BUILDERS[kind]
        ns = {}
        exec(open(_BASE + "sprite_kit.py").read(), ns)   # idempotent; some builders need Kit
        exec(open(_BASE + file).read(), ns)
        _builder_cache[kind] = (ns[fn_name], col_name)
    return _builder_cache[kind]


def _place(col, rz_deg, slot_x, side="n", extra_setback=0.0):
    """Rotate a building about world Z, then drop it so its south face sits on the
    facade line and its centre on slot_x. Fully general about object origins: transforms
    are composed on matrix_world, and the bbox is measured from the matrices actually
    applied rather than read back through the depsgraph."""
    rg = mathutils.Matrix.Rotation(math.radians(rz_deg), 4, 'Z')
    mats = {}
    xs, ys = [], []
    for ob in col.objects:
        if ob.type != 'MESH':
            continue
        m = rg @ ob.matrix_world
        mats[ob.name] = m
        for v in ob.data.vertices:
            w = m @ v.co
            xs.append(w.x)
            ys.append(w.y)
    if side == "n":
        ty = BUILDING_FRONT_Y + extra_setback - min(ys)   # north facade line
    else:
        ty = -BUILDING_FRONT_Y - extra_setback - max(ys)  # mirrored south line
    off = mathutils.Matrix.Translation((
        slot_x - (min(xs) + max(xs)) / 2.0, ty, 0.0))
    for ob in col.objects:
        if ob.name in mats:
            ob.matrix_world = off @ mats[ob.name]
        # Stray hide flags from earlier per-object isolation (show_only) survive on the
        # object; a freshly built copy starts clean, but belt-and-braces:
        ob.hide_render = False
        ob.hide_viewport = False


def _stage_con_a(col):
    """Loading-scene-only dressing of the LOAD copy (the sprite builder is untouched:
    phase1 rebuilds BLDG_construction fresh, so this never leaks back). The sprite
    crane is designed to tower OUT of the sprite frame — at the street entrance that
    means towering out of SHOT: a 5.6 mast exits the frame top anywhere nearer than
    ~10 units, and the jib along +X foreshortens to nothing for this camera. Scale
    the crane 0.58 about its base (frame top at the mast's distance is ~z 3.6, so
    the full jib clears it) and swing the jib to point SOUTH, over the street, so
    mast + raked jib both read inside the frame at ground level."""
    crane = [ob for ob in col.objects
             if ob.type == 'MESH' and ob.name.split(".")[0].startswith("crane")]
    pad = next((ob for ob in crane if ob.name.split(".")[0] == "crane_pad"), None)
    if not crane or pad is None:
        return
    # Kit.box bakes verts at (cx,cy,cz) with an identity object matrix, so the
    # object's translation is meaningless — the pad's bbox centre is the mast axis.
    cs = [pad.matrix_world @ mathutils.Vector(c) for c in pad.bound_box]
    pivot = mathutils.Vector((sum(c.x for c in cs) / 8.0, sum(c.y for c in cs) / 8.0, 0.0))
    m = (mathutils.Matrix.Translation(pivot)
         @ mathutils.Matrix.Rotation(math.radians(90.0), 4, 'Z')
         @ mathutils.Matrix.Scale(0.58, 4)
         @ mathutils.Matrix.Translation(-pivot))
    for ob in crane:
        ob.matrix_world = m @ ob.matrix_world
    # Owner (two rounds): the sprite's platform carried over as artifacts at the
    # site base — its freestyle outline as navy lines across the grass, then its
    # edges as dotted speck trails. Even sunk below grade it leaked through the
    # sub-ground slit at the walk/verge box junction (ray-fan traced the trail to
    # apron_kerb). The plate is invisible-by-design in this scene, so the LOAD
    # copy simply DELETES it; the crane pad and machine feet are separate boxes
    # and keep the site's concrete moments, the yard stands on grass.
    for ob in list(col.objects):
        if ob.type == 'MESH' and ob.name.split(".")[0] in ("apron", "apron_kerb"):
            bpy.data.objects.remove(ob, do_unlink=True)
    # ...and the frame's yard slab keeps its pale plate but loses its OUTLINE —
    # its front edge peeks just over the lawn horizon and drew as a lone navy
    # line floating rightward across the grass (the last of the platform lines).
    for ob in col.objects:
        if ob.type == 'MESH' and ob.name.split(".")[0] == "slab":
            mark_noink(ob)
    # The deep-yard clutter (spoil heaps, pipe stack, excavator, dozer) landed
    # BEHIND the container row when rz 180 staged the crane streetside — from the
    # street camera it can only ever flash sub-pixel slivers between the near
    # boxes, which render as dashed earth/mustard/ink speck trails across the
    # lawn. It contributes nothing legible at this angle: delete it.
    for ob in list(col.objects):
        if ob.type != 'MESH':
            continue
        base = ob.name.split(".")[0]
        if base.startswith(("spoil", "pipe", "dig_", "doze_")) or base in ("dig", "doze"):
            bpy.data.objects.remove(ob, do_unlink=True)


def _recalc_outward(col):
    """Make every face normal point OUT of its shell. Some builder meshes carry
    inverted faces (half a coplanar wall classifying 'away' in the geometric light
    mask while its window frames classify 'lit'). Flat-shaded closed boxes look
    identical either way in beauty+ink, so this only affects the mask. LOAD copies
    only — the sprite pipeline rebuilds BLDG_* fresh and is untouched."""
    for ob in col.objects:
        if ob.type != 'MESH':
            continue
        bm = bmesh.new()
        bm.from_mesh(ob.data)
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        bm.to_mesh(ob.data)
        bm.free()


def _stage_port(col):
    """Drop the docks so its LAND surface meets the street.

    The sprite is authored with its shore at z=0.60 (LAND_TOP) and its water at
    0.06, which is right for a standalone sprite standing on nothing. Dropped into
    the street it has to meet the ground: lower everything by LAND_TOP - 0.02 so
    the shore sits level with the verge and the harbour water falls below grade,
    which is what a harbour does."""
    dz = -(0.62 - 0.02 - 0.02)
    for ob in col.objects:
        if ob.type == 'MESH':
            ob.matrix_world = mathutils.Matrix.Translation((0, 0, dz)) @ ob.matrix_world


def phase1():
    """Build the cast and place it. Builders stomp the ACTIVE scene's render settings
    and the sprite Camera pose (their setup_rig), so the load rig is re-asserted after."""
    sc = get_scene()
    # Drop LOAD_bldg_* collections whose slot no longer exists. phase1 wipes and
    # refills the CURRENT slots but used to leave dropped ones standing, and two
    # orphans (fac_c, fac_d from an older SLOTS) sat intersecting the petro
    # refinery and the furnace with their fronts out on the sidewalk. Worse, the
    # layer predicate is "not north -> south", so these north-side strays were
    # composited into L4_south and warped with the south facade plane, sliding the
    # wrong way and riding over their neighbours.
    live = {sl[0] for sl in SLOTS}
    for col in [c for c in bpy.data.collections if c.name.startswith("LOAD_bldg_")]:
        if col.name[10:] in live:
            continue
        for ob in list(col.objects):
            bpy.data.objects.remove(ob, do_unlink=True)
        for scn in bpy.data.scenes:
            if col.name in [x.name for x in scn.collection.children]:
                scn.collection.children.unlink(col)
        bpy.data.collections.remove(col)
    placed = []
    for slot in SLOTS:
        suffix, kind, level, rz, x, side = slot[:6]
        extra = slot[6] if len(slot) > 6 else 0.0
        fn, col_name = _builder(kind)
        try:
            fn(level)
        except TypeError:
            fn()                       # no-arg builders (construction site)
        src = bpy.data.collections[col_name]
        col = _collection(sc, "LOAD_bldg_%s" % suffix)
        _wipe(col)
        for ob in list(src.objects):
            src.objects.unlink(ob)
            col.objects.link(ob)
        _place(col, rz, x, side, extra)
        if suffix == "con_a":
            _stage_con_a(col)
        if suffix == "port_a":
            _stage_port(col)
        _recalc_outward(col)
        placed.append({"slot": suffix, "level": level, "objects": len(col.objects)})
    setup_load_rig()
    return {"placed": placed}


# ── Phase 3: street props — trees, grass, fences, lampposts ──────────────────
# Built via the props kit (sprite_kit + props_kit patched Kit). MUST run after
# phase1: open_collection() strips FINE_INK links, so a later builder run silently
# reverts every fine-inked prop to thick ink — re-run phase3 after any phase1.
PROPS_SPLIT_X = 30.0        # x >= split -> far parallax layer

TREES = [                   # (x, side, h, r) — y is DERIVED: the canopy must clear the
    # facade line (y = sign*(FRONT - r - 0.12)) or big crowns clip into buildings.
    # Density DOUBLED (owner): a tree roughly every 6 units per side.
    (-5.5,  1, 2.0, 0.48), (2.5,  1, 1.7, 0.40), (9.8,  1, 1.7, 0.42),
    (15.5,  1, 2.0, 0.46), (21.3, 1, 2.1, 0.50), (26.2, 1, 1.6, 0.38),
    (30.5,  1, 1.8, 0.44), (36.8, 1, 1.9, 0.45), (43.0, 1, 1.9, 0.46),
    (50.0,  1, 1.7, 0.41), (56.5, 1, 1.6, 0.40), (62.5, 1, 1.8, 0.43),
    (-2.5, -1, 1.9, 0.46), (2.2, -1, 1.8, 0.44), (8.0, -1, 2.1, 0.50),
    (13.5, -1, 2.2, 0.52), (18.2, -1, 1.6, 0.39), (22.6, -1, 1.6, 0.40),
    (29.0, -1, 2.0, 0.47), (35.5, -1, 1.9, 0.46), (41.0, -1, 1.7, 0.41),
    (47.0, -1, 1.7, 0.42), (52.5, -1, 2.0, 0.48), (57.5, -1, 2.0, 0.48),
    # Out to the new end of the built row. The avenue used to stop at 62 while the
    # buildings ran to 89, so the last 25 units — a third of the whole run, and
    # everything past the 55% mark — was buildings standing on bare grass.
    (67.0,  1, 1.9, 0.46), (72.5, 1, 1.7, 0.42), (78.0, 1, 2.0, 0.48),
    (83.0,  1, 1.8, 0.44), (87.5, 1, 1.7, 0.41),
    (64.5, -1, 1.8, 0.44), (69.5, -1, 2.0, 0.47), (75.0, -1, 1.7, 0.42),
    (80.5, -1, 1.9, 0.46), (85.5, -1, 1.8, 0.43),
    # down to the port
    (92.0,  1, 1.8, 0.44), (98.5, 1, 2.0, 0.47), (104.5, 1, 1.7, 0.42),
    (110.0, 1, 1.9, 0.45),
    (90.5, -1, 1.7, 0.41), (95.5, -1, 1.9, 0.46),
]
LAMPS = [                   # (x, side) — on the sidewalk, arm over the road. Nothing
    # nearer than x=5: the camera sits at -8 and a lamp 2 units ahead fills the frame
    # with pole (the first cut had one at -6 doing exactly that).
    (8.0, 1), (22.0, 1), (36.0, 1), (50.0, 1), (64.0, 1),
    (5.0, -1), (15.0, -1), (29.0, -1), (43.0, -1), (57.0, -1),
    (78.0, 1), (71.0, -1), (85.0, -1),
    (92.0, 1), (100.0, 1), (108.0, 1), (95.0, -1),
]
LANE_Y = 0.29               # lane centres; nothing may cross the centre line
# Traffic (owner: 3-4 trucks + 2-3 cars down the road, a few cars back up it).
# The game is British, so traffic keeps LEFT: down-street (+X) runs on the +Y side,
# which is SCREEN LEFT, and oncoming is screen right — the way it looks from a car.
#
# It MOVES. The camera drives down the centre line, so a parked vehicle in the
# down-street lane gets rear-ended: at camera x=22 the static truck at x=26 filled
# half the frame, because its trailer tail sat 1.85 units off the lens. Down-street
# traffic therefore runs slightly FASTER than the camera and slowly draws away;
# oncoming traffic closes at nearly twice camera speed and sweeps past. Both wrap
# around a window ahead so the stream never runs out — a wrap only ever happens ~90
# units out, where a vehicle is a couple of pixels.
AWAY_SPEED, ONCOMING_SPEED, WRAP = 1.15, 0.85, 125.0
VEH_FADE_AWAY, VEH_FADE_TOWARD = 14.0, 26.0   # fade bands before the wrap
# (kind, x0, direction, colour)
VEHICLES = [
    ("truck", 6.0,   1, "truck_white"),
    ("car",   17.0,  1, "car_red"),
    ("truck", 31.0,  1, "truck_black"),
    ("car",   44.0,  1, "car_blue"),
    ("truck", 58.0,  1, "truck_white"),
    ("car",   70.0,  1, "car_green"),
    ("truck", 84.0,  1, "truck_black"),
    ("car",   97.0,  1, "car_grey"),
    ("truck", 109.0, 1, "truck_white"),
    ("car",   15.0, -1, "car_cream"),
    ("car",   38.0, -1, "car_grey"),
    ("car",   61.0, -1, "car_rust"),
    ("car",   80.0, -1, "car_blue"),
    ("car",   99.0, -1, "car_green"),
    ("car",  113.0, -1, "car_red"),
]


def place_vehicles(advance=0.0, cam_x=None):
    """(Re)build the traffic for a camera that has travelled `advance` units.

    Cheap enough to call per frame — 11 vehicles, a few dozen boxes. Every frame of
    the film is its own render, so this is all the animation system the traffic
    needs; nothing is keyframed in Blender."""
    B = "/Users/crisu/Price of Everything/blender-assets/"
    ns = {}
    exec(open(B + "sprite_kit.py").read(), ns)
    exec(open(B + "props_kit.py").read(), ns)
    exec(open(B + "vehicles_kit.py").read(), ns)
    sc = get_scene()
    col = _collection(sc, "LOAD_props_veh")
    _wipe(col)
    kit = ns["Kit"](ns["open_collection"]("LOAD_props_veh"))
    _collection(sc, "LOAD_props_veh")
    cx = CAM_X + advance if cam_x is None else cam_x
    for vi, (kind, x0, vdir, colour) in enumerate(VEHICLES):
        if vdir > 0:
            x = x0 + AWAY_SPEED * advance
        else:
            x = x0 - ONCOMING_SPEED * advance
        x = cx + ((x - cx) % WRAP)          # keep a stream ahead of the camera
        # Dissolve into the haze approaching the city rather than popping at the
        # wrap. FADE_D is sized to about a second of RELATIVE travel: down-street
        # traffic closes on the wrap slowly (0.15 u per unit of camera advance),
        # oncoming much faster, so they get their own bands.
        ahead = x - cx
        fade_d = VEH_FADE_AWAY if vdir > 0 else VEH_FADE_TOWARD
        fade = 0.0
        if ahead > WRAP - fade_d:
            fade = (ahead - (WRAP - fade_d)) / fade_d
        if fade >= 0.98:                    # gone: never rebuilt, so it cannot pop
            continue
        vy = vdir * LANE_Y
        if kind == "truck":
            kit.truck("veh_%d" % vi, x, vy, face=float(vdir), colour=colour,
                      seed=vi * 977 + 13, fade=fade)
        else:
            kit.car("veh_%d" % vi, x, vy, face=float(vdir), colour=colour,
                    seed=vi * 977 + 13, fade=fade)
    return {"vehicles": len(VEHICLES), "advance": advance}


FENCES = [                  # power-plant and refinery yards get street fencing
    ((48.6, -2.35), (55.4, -2.35)),
    ((56.6,  2.35), (63.4,  2.35)),
    ((31.0,  2.35), (37.0,  2.35)),
    ((82.0,  2.35), (89.0,  2.35)),     # the new power plant yard
    # Fence along the port frontage, stopping short of the crossroads at the very
    # end so the junction stays open (owner).
    ((93.8, -2.35), (105.5, -2.35)),
]


def phase3():
    import random
    B = "/Users/crisu/Price of Everything/blender-assets/"
    ns = {}
    exec(open(B + "sprite_kit.py").read(), ns)
    exec(open(B + "props_kit.py").read(), ns)
    exec(open(B + "vehicles_kit.py").read(), ns)
    # Props are grouped by the PLANE they stand on, not by distance: everything on
    # the north verge shares the facade plane y=+FRONT and takes one dolly
    # homography; the south verge takes its mirror. Lampposts sit far closer to the
    # centreline (|y| ~ 0.92) so they get their own pair of layers — warped on the
    # facade plane they would lag by ~2.8x.
    kits = {}
    for tag in ("n", "s", "lamp_n", "lamp_s"):
        kits[tag] = ns["Kit"](ns["open_collection"]("LOAD_props_" + tag))
    sc = get_scene()
    for tag in ("n", "s", "lamp_n", "lamp_s"):
        _collection(sc, "LOAD_props_" + tag)      # ensure linked into Loading

    def kit_for(side):
        return kits["n"] if side > 0 else kits["s"]

    def lamp_kit(side):
        return kits["lamp_n"] if side > 0 else kits["lamp_s"]

    for i, (x, side, h, r) in enumerate(TREES):
        ty = side * (BUILDING_FRONT_Y - r - 0.12)
        kit_for(side).tree("tree_%d" % i, x, ty, h, r, seed=i * 7 + 3)
    lamp_y = ROAD_HALF_W + 0.30
    for i, (x, side) in enumerate(LAMPS):
        lamp_kit(side).lamppost("lamp_%d" % i, x, side * lamp_y, toward=-side)
    for i, (p0, p1) in enumerate(FENCES):
        kit_for(1 if p0[1] > 0 else -1).fence_run("fence_%d" % i, p0, p1)
    # Spiky bushes between consecutive trees on each side (owner reference).
    n_row = sorted([t for t in TREES if t[1] == 1])
    s_row = sorted([t for t in TREES if t[1] == -1])
    bi = 0
    for row, sgn in ((n_row, 1), (s_row, -1)):
        for a, b in zip(row, row[1:]):
            bx = (a[0] + b[0]) / 2.0
            by = sgn * (BUILDING_FRONT_Y - 0.55)
            kit_for(sgn).spiky_bush("bush_%d" % bi, bx, by,
                                   h=0.45 + 0.25 * ((bi * 7) % 3) / 2.0,
                                   r=0.26 + 0.10 * ((bi * 5) % 2), seed=bi * 3 + 2)
            bi += 1

    # Grass lined along the VISIBLE building bases (owner 2026-08-06: "the grass
    # is most useful near the buildings"): broken bands of dense clumps hugging
    # each building's street-facing edge and its west (camera-facing) end, just
    # outside the apron footprint. Clumps are skipped where a side-road lane or
    # parking pad crosses the line — grass through asphalt reads as neglect.
    grng = random.Random(41)
    avoid = []
    for sx, sside in ((7.5, 1), (29.5, 1), (48.5, 1), (11.5, -1), (33.5, -1), (46.0, -1)):
        ya = sside * (ROAD_HALF_W + SIDEWALK_W)
        yb = sside * (BUILDING_FRONT_Y + 5.2)
        avoid.append((sx - 0.50, sx + 0.50, min(ya, yb), max(ya, yb)))
    for px, pside in ((8.9, 1), (30.9, 1), (12.9, -1), (47.4, -1)):
        ya = pside * (BUILDING_FRONT_Y + 0.05)
        yb = pside * (BUILDING_FRONT_Y + 1.80)
        avoid.append((px - 1.30, px + 1.30, min(ya, yb), max(ya, yb)))

    def blocked(cx, cy):
        return any(ax0 <= cx <= ax1 and ay0 <= cy <= ay1
                   for ax0, ax1, ay0, ay1 in avoid)

    for bcol in bpy.data.collections:
        if not bcol.name.startswith("LOAD_bldg_") or bcol.name == "LOAD_bldg_con_a":
            continue
        bxs, bys = [], []
        for ob in bcol.objects:
            if ob.type != 'MESH':
                continue
            for c in ob.bound_box:
                w = ob.matrix_world @ mathutils.Vector(c)
                bxs.append(w.x)
                bys.append(w.y)
        if not bxs:
            continue
        bx0, bx1, by0, by1 = min(bxs), max(bxs), min(bys), max(bys)
        south = (by0 + by1) < 0
        sname = bcol.name[10:]
        fy = (by1 + 0.14) if south else (by0 - 0.14)   # street-facing edge, outside
        x = bx0 + grng.uniform(0.2, 0.7)
        ci = 0
        while x < bx1 - 0.2:
            if grng.random() < 0.8 and not blocked(x, fy):
                kit_for(-1 if south else 1).grass_patch("base_%s_f%d" % (sname, ci), x, fy,
                                       rx=grng.uniform(0.35, 0.60),
                                       ry=grng.uniform(0.08, 0.14),
                                       dark=grng.random() < 0.5,
                                       seed=1000 + ci * 17 + int(abs(x) * 7) % 97)
            x += grng.uniform(1.05, 1.55)
            ci += 1
        wx = bx0 - 0.14                                 # west (camera-facing) end
        y = by0 + 0.2
        ci = 0
        while y < by1 - 0.2:
            if grng.random() < 0.8 and not blocked(wx, y):
                kit_for(-1 if south else 1).grass_patch("base_%s_w%d" % (sname, ci), wx, y,
                                       rx=grng.uniform(0.08, 0.14),
                                       ry=grng.uniform(0.35, 0.60),
                                       dark=grng.random() < 0.5,
                                       seed=2000 + ci * 13 + int(abs(y) * 7) % 97)
            y += grng.uniform(1.05, 1.55)
            ci += 1

    # THE PARK (owner): the right-hand entrance block is trees, not buildings — a
    # loose two-deep grove with bushes and patches, x -12..-2 on the south side.
    prng = random.Random(23)
    for i in range(9):
        px = -12.0 + i * 1.25 + prng.uniform(-0.4, 0.4)
        py = -(2.2 + prng.uniform(0.0, 3.0))
        kits["s"].tree("park_tree_%d" % i, px, py,
                          h=prng.uniform(1.5, 2.3), r=prng.uniform(0.38, 0.55),
                          seed=100 + i * 11)
    for i in range(6):
        px = -11.5 + i * 2.0 + prng.uniform(-0.5, 0.5)
        py = -(2.0 + prng.uniform(0.2, 2.2))
        kits["s"].spiky_bush("park_bush_%d" % i, px, py,
                                h=prng.uniform(0.4, 0.7), r=prng.uniform(0.22, 0.34),
                                seed=200 + i * 7)
    for i in range(7):
        px = prng.uniform(-12.0, -2.5)
        py = -prng.uniform(1.9, 4.8)
        kits["s"].grass_patch("park_patch_%d" % i, px, py,
                                 rx=prng.uniform(0.35, 0.8), ry=prng.uniform(0.25, 0.5),
                                 dark=prng.random() < 0.5, blades=prng.randint(2, 4),
                                 seed=300 + i * 5)

    rng = random.Random(11)
    # A few loose verge scatters + tufts as accents — the MASS of the grass now
    # lives in the building base bands above (owner). ry is chosen FIRST and the
    # centre y clamped so the whole scatter ellipse stays ON the verge.
    walk_edge = ROAD_HALF_W + SIDEWALK_W
    for i in range(16):
        x = rng.uniform(-7.5, 106.0)
        side = rng.choice((1, -1))
        ry = rng.uniform(0.18, 0.33)
        y = side * rng.uniform(walk_edge + 0.10 + ry, BUILDING_FRONT_Y - 0.10 - ry)
        kit_for(side).grass_patch("patch_%d" % i, x, y,
                                 rx=rng.uniform(0.30, 0.75), ry=ry,
                                 dark=rng.random() < 0.5, blades=rng.randint(2, 4),
                                 seed=i * 13 + 1)
    for i in range(14):
        x = rng.uniform(-7.0, 106.0)
        side = rng.choice((1, -1))
        y = side * rng.uniform(ROAD_HALF_W + SIDEWALK_W + 0.40, BUILDING_FRONT_Y - 0.3)
        kit_for(side).grass_tuft("tuft_%d" % i, x, y, rng.uniform(0.7, 1.0))
    # Traffic lives in place_vehicles(), which is re-run per frame so it can move.
    place_vehicles(0.0)

    setup_load_rig()
    return {"trees": len(TREES), "lamps": len(LAMPS), "fences": len(FENCES),
            "tufts": 26, "vehicles": len(VEHICLES)}
