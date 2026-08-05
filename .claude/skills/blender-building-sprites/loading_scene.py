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
BUILDING_FRONT_Y = ROAD_HALF_W + SIDEWALK_W + SETBACK_W   # facades sit at this y
STREET_X0, STREET_X1 = -14.0, 92.0    # camera end -> vanishing point at the city
CITY_X = 74.0               # distant city backdrop plane (P2), faces the camera (-X)
SKY_X = 90.0                # sky backdrop plane, faces the camera

# Scene tones — flat Principled, specular 0, roughness 1 (the kit recipe). Large
# surfaces obey the AgX value ceiling: past base ~0.3 everything renders within a few
# luma, so the BIG planes stay low; small crisp objects may go brighter.
TONES = {
    "load_ground":  (0.125, 0.170, 0.092),   # field green
    "load_verge":   (0.128, 0.240, 0.075),   # vivid lawn at the building line (owner)
    "load_asphalt": (0.085, 0.095, 0.115),   # road — darker than ground, navy-leaning
    "load_kerb":    (0.420, 0.400, 0.340),   # pale stone, small surface
    "load_walk":    (0.240, 0.235, 0.215),   # sidewalk concrete — large surface, stays low
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
    cam_ob.location = (-8.0, 0.0, 0.62)    # centreline, LOW — buildings loom (owner)
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

    # Raised sidewalks flanking the road, with a pale kerb lip on the road edge. The
    # slab is a real step above the asphalt (SIDEWALK_TOP vs ~0.058) so the kerb face
    # catches its own ink line down the whole street.
    for side, tag in ((1, "n"), (-1, "s")):
        yc = side * (ROAD_HALF_W + SIDEWALK_W / 2)
        _box(col, "walk_" + tag, cx, yc, SIDEWALK_TOP / 2,
             STREET_X1 - STREET_X0, SIDEWALK_W, SIDEWALK_TOP, _mat("load_walk"))
        _box(col, "kerb_" + tag, cx, side * (ROAD_HALF_W + KERB_W / 2),
             SIDEWALK_TOP / 2 + 0.006,
             STREET_X1 - STREET_X0 + EPS, KERB_W, SIDEWALK_TOP + 0.012, _mat("load_kerb"))

    # Verges: the lawns between sidewalk and facades, proud of the ground by EPS so
    # they read as kept grass against the duller field beyond (owner: vibrant green).
    for side, tag in ((1, "n"), (-1, "s")):
        y0v = side * (ROAD_HALF_W + SIDEWALK_W)
        y1v = side * (BUILDING_FRONT_Y + 6.0)
        _box(col, "verge_" + tag, cx, (y0v + y1v) / 2, -0.04 + EPS,
             STREET_X1 - STREET_X0, abs(y1v - y0v), 0.1, _mat("load_verge"))

    # Centre dashes.
    dash_l, gap = 0.42, 0.55
    x = STREET_X0
    i = 0
    while x < STREET_X1:
        _box(col, "dash_%d" % i, x + dash_l / 2, 0, 0.061,
             dash_l, 0.045, 0.012, _mat("load_dash"))
        x += dash_l + gap
        i += 1

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

SKY_BANDS = [                    # bottom -> top: pale warm horizon rising into SKY BLUE.
    # Eight bands interpolated between the four original keys (owner: "blend the sky
    # bands more") — still visibly banded, poster-style, but each step is half the
    # jump. Saturation pushed because AgX desaturates emission.
    (4.5,  (0.740, 0.720, 0.600)),
    (3.0,  (0.650, 0.690, 0.670)),
    (3.0,  (0.560, 0.660, 0.740)),
    (3.0,  (0.480, 0.610, 0.735)),
    (4.0,  (0.400, 0.560, 0.730)),
    (5.0,  (0.345, 0.515, 0.715)),
    (6.0,  (0.290, 0.470, 0.695)),
    (35.0, (0.240, 0.430, 0.680)),
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


def build_backdrop(seed=7):
    """Banded sky (one mesh, one material slot per band), two-rank city silhouette
    peaked at the vanishing point, and a haze strip grounding it. Idempotent."""
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
    y0, y1 = -260.0 / 2, 260.0 / 2
    z = 0.0
    faces = []
    for i, (bh, _) in enumerate(SKY_BANDS):
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
            # Skyscrapers (owner: "taller — skyscrapers on the horizon"): roughly a
            # fifth of the near-rank blocks become towers — narrow slabs 3-5x the
            # low-rise height, clustered toward the centre by the same envelope.
            tower = rank == 1 and rng.random() < 0.22
            if tower:
                w = min(w, 2.2)
                h = rng.uniform(3.4, 6.0) * (1.0 + 0.8 * math.exp(-(y / 16.0) ** 2))
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
            y += w + rng.uniform(0.4, 1.6)
            i += 1

    # Haze: grounds the silhouette — but SPLIT around the road corridor. One unbroken
    # strip occluded the road's last stretch, so the street visibly ended in haze a
    # dozen units short of the skyline (the owner's "gap to the city").
    for tag, y0h, y1h in (("s", -121.3, -1.3), ("n", 1.3, 121.3)):
        hz = _box(city_col, "haze_" + tag, CITY_X - 1.6, (y0h + y1h) / 2, 0.65,
                  0.1, y1h - y0h, 1.5, _emat("load_haze", HAZE_TONE))
        mark_noink(hz)

    # Gate blocks: two deliberate taller buildings flanking the road's entry into the
    # city, so the corridor reads as a street between buildings rather than a slot.
    # Central skyscraper wall (owner: "basically touching across the middle"): a
    # deliberate cluster on the FAR rank spanning the road axis, so the street
    # visibly ends AT the city — tall slabs shoulder to shoulder behind the gates.
    wallm = _emat("load_city_wall", CITY_FAR_TONE)
    for wi, (wy, ww, wh) in enumerate(((-6.8, 2.2, 5.6), (-4.2, 1.8, 7.4),
                                       (-1.6, 2.4, 6.2), (1.2, 1.9, 8.2),
                                       (3.4, 2.1, 6.6), (5.8, 2.3, 5.2))):
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
    cm = _emat("load_cloud", (0.880, 0.890, 0.880))
    sm = _emat("load_cloud_shade", (0.665, 0.690, 0.715))
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
    return {"sky_bands": len(SKY_BANDS), "city_objects": len(city_col.objects)}


# ── Parallax layers ──────────────────────────────────────────────────────────
# Depth slices for the Godot push-in. Scaled about the vanishing point at different
# rates, back to front. The street (ground+road) spans every depth, so it rides at the
# NEAR rate — the standard 2.5D-push cheat, invisible at the subtle zoom used here.
FAR_SLOTS = ("off_d", "fur_b", "pp_a", "pp_b", "pet_a", "off_e", "fac_e", "off_f")

LAYERS = [
    ("L0_sky",   lambda n: n == "LOAD_sky"),
    ("L1_city",  lambda n: n == "LOAD_city"),
    ("L2_far",   lambda n: n.startswith("LOAD_bldg_") and n[10:] in FAR_SLOTS),
    ("L3_near",  lambda n: n.startswith("LOAD_bldg_") and n[10:] not in FAR_SLOTS),
    ("L4_street", lambda n: n == "LOAD_street"),
]


def _show_only_load(pred):
    """Visibility per OBJECT as well as per collection: power plants dual-link their
    pylons/transformers into FINE_INK, which stays visible — collection hiding alone
    leaves them rendering into every other layer (the FINE_INK lesson, third time)."""
    for c in bpy.data.collections:
        if not c.name.startswith("LOAD_"):
            continue
        off = not pred(c.name)
        c.hide_render = off
        c.hide_viewport = off
        for ob in c.objects:
            ob.hide_render = off
            ob.hide_viewport = off


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
        sc.render.filepath = os.path.join(out_dir, name)
        bpy.ops.render.render(write_still=True)
        done.append(name)
    # Restore: everything visible, hero-resolution ink.
    _show_only_load(lambda n: True)
    sc.render.resolution_x = 1920
    sc.render.resolution_y = 1080
    fs.linesets["ink"].linestyle.thickness = 2.4
    fs.linesets["contour"].linestyle.thickness = 7.0
    if "ink_fine" in fs.linesets:
        fs.linesets["ink_fine"].linestyle.thickness = 1.05
    return {"layers": done, "out": out_dir, "res": [width, height]}


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
    ("fac_a", "factory",     3,  -90.0,  1.5, "n", 0.9),   # L3; set back for the annex
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
    # approach: small fillers bridging the last plants to the city skyline, so the
    # street runs continuously INTO the city instead of stopping 14 units short of
    # it (the owner's "gap to the city" — the other half of the fix, with the
    # corridor through the haze).
    ("off_e", "office",      1, 180.0, 66.0, "s"),
    ("fac_e", "factory",     1, -90.0, 67.5, "n"),
    ("off_f", "office",      2,   0.0, 71.5, "n"),
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


def phase1():
    """Build the cast and place it. Builders stomp the ACTIVE scene's render settings
    and the sprite Camera pose (their setup_rig), so the load rig is re-asserted after."""
    sc = get_scene()
    placed = []
    for slot in SLOTS:
        suffix, kind, level, rz, x, side = slot[:6]
        extra = slot[6] if len(slot) > 6 else 0.0
        fn, col_name = _builder(kind)
        fn(level)
        src = bpy.data.collections[col_name]
        col = _collection(sc, "LOAD_bldg_%s" % suffix)
        _wipe(col)
        for ob in list(src.objects):
            src.objects.unlink(ob)
            col.objects.link(ob)
        _place(col, rz, x, side, extra)
        placed.append({"slot": suffix, "level": level, "objects": len(col.objects)})
    setup_load_rig()
    return {"placed": placed}
