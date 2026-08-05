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
KERB_W = 0.10
PAVEMENT_W = 0.55           # pavement strip between kerb and building fronts
BUILDING_FRONT_Y = ROAD_HALF_W + KERB_W + PAVEMENT_W   # facades sit at this y
STREET_X0, STREET_X1 = -14.0, 92.0    # camera end -> vanishing point at the city
CITY_X = 74.0               # distant city backdrop plane (P2), faces the camera (-X)
SKY_X = 90.0                # sky backdrop plane, faces the camera

# Scene tones — flat Principled, specular 0, roughness 1 (the kit recipe). Large
# surfaces obey the AgX value ceiling: past base ~0.3 everything renders within a few
# luma, so the BIG planes stay low; small crisp objects may go brighter.
TONES = {
    "load_ground":  (0.128, 0.150, 0.098),   # dry green-grey field
    "load_asphalt": (0.085, 0.095, 0.115),   # road — darker than ground, navy-leaning
    "load_kerb":    (0.420, 0.400, 0.340),   # pale stone, small surface
    "load_dash":    (0.700, 0.680, 0.600),   # centre-line dashes
    "load_sky":     (0.520, 0.600, 0.660),   # placeholder single tone; banded in P2
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
    cam_ob.data.clip_end = 200.0
    cam_ob.location = (-8.0, -0.45, 0.95)
    cam_ob.rotation_euler = (math.radians(90.0), 0.0, math.radians(-90.0))  # look +X, plumb verticals
    cam_ob.data.shift_y = 0.10                               # rising front instead of tilt
    sc.camera = cam_ob

    # Sun: shadowless (style contract), aimed so the -Y facades read lit and the east
    # walls fall into tone-shade. Own object; the sprite Light is untouched.
    sun_ob = bpy.data.objects.get("LoadSun")
    if sun_ob is None:
        sun = bpy.data.lights.new("LoadSun", 'SUN')
        sun_ob = bpy.data.objects.new("LoadSun", sun)
    if sun_ob.name not in [o.name for o in sc.collection.objects]:
        sc.collection.objects.link(sun_ob)
    sun_ob.data.use_shadow = False
    sun_ob.data.energy = 2.6
    sun_ob.rotation_euler = (math.radians(60.0), math.radians(-12.0), math.radians(15.0))

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
        bg.inputs[1].default_value = 0.75
    sc.world = world
    return sc


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
    ground = _box(col, "ground", cx, 0, -0.05,
                  (STREET_X1 - STREET_X0) + 60, 90, 0.1, _mat("load_ground"))
    mark_noink(ground)

    # Road slab: proud of the ground by EPS (coplanar faces smear — rule 1).
    _box(col, "road", cx, 0, 0.0 + EPS / 2,
         STREET_X1 - STREET_X0, ROAD_HALF_W * 2, 0.1 + EPS, _mat("load_asphalt"))

    # Kerbs: slim pale strips, slightly proud of the road.
    for side, name in ((1, "kerb_n"), (-1, "kerb_s")):
        _box(col, name, cx, side * (ROAD_HALF_W + KERB_W / 2), 0.03,
             STREET_X1 - STREET_X0, KERB_W, 0.06 + EPS, _mat("load_kerb"))

    # Centre dashes.
    dash_l, gap = 0.42, 0.55
    x = STREET_X0
    i = 0
    while x < STREET_X1:
        _box(col, "dash_%d" % i, x + dash_l / 2, 0, 0.061,
             dash_l, 0.045, 0.012, _mat("load_dash"))
        x += dash_l + gap
        i += 1

    # Sky placeholder: one flat tone, NOINK; banded properly in P2. Stands at the far
    # east end facing the camera (the road's vanishing point lands on it). Tall + wide
    # enough that no plausible framing can look past an edge — the first hero shot
    # escaped a 30-high plane and rendered black.
    sky = _box(col, "sky", SKY_X, 0, 27.0, 0.1, 260, 60, _mat("load_sky"))
    mark_noink(sky)
    return {"objects": len(col.objects), "building_front_y": BUILDING_FRONT_Y}


def phase0():
    info = build_street_scaffold()
    setup_load_rig()
    return {**info, "scene": SCENE_NAME}


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
    # near (west, large in frame)
    ("off_a", "office",      1, 180.0,  -3.0, "s"),
    ("fac_a", "factory",     2,  -90.0,  1.5, "n"),
    ("off_b", "office",      2, 180.0,   6.0, "s"),
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
]

# Every builder file defines a module-level LEVELS and reads it from its exec namespace,
# so exec'ing two builders into ONE namespace makes the second silently feed its LEVELS
# to the first (build_factory read the power plant's table: KeyError 'bays'). Each
# builder therefore gets its OWN namespace; the returned function's __globals__ is that
# namespace, so its LEVELS resolves correctly.
_BASE = "/Users/crisu/Price of Everything/blender-assets/"
BUILDERS = {
    "factory":    ("factory_builder.py",       "build_factory",       "BLDG_factory"),
    "furnace":    ("furnace_builder.py",       "build_furnace",       "BLDG_furnace"),
    "powerplant": ("power_plant_builder.py",   "build_power_plant",   "BLDG_powerplant"),
    "poly":       ("poly_plant_builder.py",    "build_poly_plant",    "BLDG_poly"),
    "petro":      ("petro_refinery_builder.py","build_petro_refinery","BLDG_petro"),
    "office":     ("office_builder.py",        "build_office",        "BLDG_office"),
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


def _place(col, rz_deg, slot_x, side="n"):
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
        ty = BUILDING_FRONT_Y - min(ys)        # front face on the north facade line
    else:
        ty = -BUILDING_FRONT_Y - max(ys)       # mirrored line south of the road
    off = mathutils.Matrix.Translation((
        slot_x - (min(xs) + max(xs)) / 2.0, ty, 0.0))
    for ob in col.objects:
        if ob.name in mats:
            ob.matrix_world = off @ mats[ob.name]
        # Stray hide flags from earlier per-object isolation (show_only) survive on the
        # object; a freshly built copy starts clean, but belt-and-braces:
        ob.hide_render = False
        ob.hide_viewport = False


def phase1():
    """Build the cast and place it. Builders stomp the ACTIVE scene's render settings
    and the sprite Camera pose (their setup_rig), so the load rig is re-asserted after."""
    sc = get_scene()
    placed = []
    for suffix, kind, level, rz, x, side in SLOTS:
        fn, col_name = _builder(kind)
        fn(level)
        src = bpy.data.collections[col_name]
        col = _collection(sc, "LOAD_bldg_%s" % suffix)
        _wipe(col)
        for ob in list(src.objects):
            src.objects.unlink(ob)
            col.objects.link(ob)
        _place(col, rz, x, side)
        placed.append({"slot": suffix, "level": level, "objects": len(col.objects)})
    setup_load_rig()
    return {"placed": placed}
