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
STREET_X0, STREET_X1 = -20.0, 92.0    # camera end -> vanishing point at the city
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
    cam_ob.location = (-13.0, 0.0, 0.62)   # pulled back: entrance zone in frame (owner)
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
        _box(col, "siderd_x_%s_%d" % (side, int(sx * 10)), sx,
             sgn * (ROAD_HALF_W + SIDEWALK_W / 2), SIDEWALK_TOP + 0.004,
             0.62, SIDEWALK_W + EPS, 0.014, _mat("load_asphalt"))
        _box(col, "siderd_l_%s_%d" % (side, int(sx * 10)), sx,
             sgn * (ROAD_HALF_W + SIDEWALK_W + 2.6), -0.02 + EPS,
             0.62, 5.2, 0.1, _mat("load_asphalt"))
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
LAYERS = [
    ("L0_sky",    lambda n: n == "LOAD_sky"),
    ("L1_city",   lambda n: n == "LOAD_city"),
    ("L2_street", lambda n: n == "LOAD_street"),
    ("L3_far",    lambda n: (n.startswith("LOAD_bldg_") and n[10:] in FAR_SLOTS)
                  or n == "LOAD_props_far"),
    ("L4_near",   lambda n: (n.startswith("LOAD_bldg_") and n[10:] not in FAR_SLOTS)
                  or n == "LOAD_props_near"),
]


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
        if name in ("L3_far", "L4_near"):
            cc = bpy.data.collections.get("LOAD_street")
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
            if name == "L2_street":
                cc2 = bpy.data.collections.get("LOAD_bldg_con_a")
                if cc2:
                    for ob2 in cc2.objects:
                        if ob2.type == 'MESH' and ob2.name.split(".")[0].startswith("crane"):
                            crane_state.append((ob2.name, ob2.visible_shadow))
                            ob2.visible_shadow = False
            use_geo = name in ("L3_far", "L4_near")
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


def phase1():
    """Build the cast and place it. Builders stomp the ACTIVE scene's render settings
    and the sprite Camera pose (their setup_rig), so the load rig is re-asserted after."""
    sc = get_scene()
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
]
LAMPS = [                   # (x, side) — on the sidewalk, arm over the road. Nothing
    # nearer than x=5: the camera sits at -8 and a lamp 2 units ahead fills the frame
    # with pole (the first cut had one at -6 doing exactly that).
    (8.0, 1), (22.0, 1), (36.0, 1), (50.0, 1), (64.0, 1),
    (5.0, -1), (15.0, -1), (29.0, -1), (43.0, -1), (57.0, -1),
]
FENCES = [                  # power-plant and refinery yards get street fencing
    ((48.6, -2.35), (55.4, -2.35)),
    ((56.6,  2.35), (63.4,  2.35)),
    ((31.0,  2.35), (37.0,  2.35)),
]


def phase3():
    import random
    B = "/Users/crisu/Price of Everything/blender-assets/"
    ns = {}
    exec(open(B + "sprite_kit.py").read(), ns)
    exec(open(B + "props_kit.py").read(), ns)
    kits = {}
    for tag in ("near", "far"):
        kits[tag] = ns["Kit"](ns["open_collection"]("LOAD_props_" + tag))
    sc = get_scene()
    for tag in ("near", "far"):
        _collection(sc, "LOAD_props_" + tag)      # ensure linked into Loading

    def kit_for(x):
        return kits["far"] if x >= PROPS_SPLIT_X else kits["near"]

    for i, (x, side, h, r) in enumerate(TREES):
        ty = side * (BUILDING_FRONT_Y - r - 0.12)
        kit_for(x).tree("tree_%d" % i, x, ty, h, r, seed=i * 7 + 3)
    lamp_y = ROAD_HALF_W + 0.30
    for i, (x, side) in enumerate(LAMPS):
        kit_for(x).lamppost("lamp_%d" % i, x, side * lamp_y, toward=-side)
    for i, (p0, p1) in enumerate(FENCES):
        kit_for(p0[0]).fence_run("fence_%d" % i, p0, p1)
    # Spiky bushes between consecutive trees on each side (owner reference).
    n_row = sorted([t for t in TREES if t[1] == 1])
    s_row = sorted([t for t in TREES if t[1] == -1])
    bi = 0
    for row, sgn in ((n_row, 1), (s_row, -1)):
        for a, b in zip(row, row[1:]):
            bx = (a[0] + b[0]) / 2.0
            by = sgn * (BUILDING_FRONT_Y - 0.55)
            kit_for(bx).spiky_bush("bush_%d" % bi, bx, by,
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
                kit_for(x).grass_patch("base_%s_f%d" % (sname, ci), x, fy,
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
                kit_for(wx).grass_patch("base_%s_w%d" % (sname, ci), wx, y,
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
        kits["near"].tree("park_tree_%d" % i, px, py,
                          h=prng.uniform(1.5, 2.3), r=prng.uniform(0.38, 0.55),
                          seed=100 + i * 11)
    for i in range(6):
        px = -11.5 + i * 2.0 + prng.uniform(-0.5, 0.5)
        py = -(2.0 + prng.uniform(0.2, 2.2))
        kits["near"].spiky_bush("park_bush_%d" % i, px, py,
                                h=prng.uniform(0.4, 0.7), r=prng.uniform(0.22, 0.34),
                                seed=200 + i * 7)
    for i in range(7):
        px = prng.uniform(-12.0, -2.5)
        py = -prng.uniform(1.9, 4.8)
        kits["near"].grass_patch("park_patch_%d" % i, px, py,
                                 rx=prng.uniform(0.35, 0.8), ry=prng.uniform(0.25, 0.5),
                                 dark=prng.random() < 0.5, blades=prng.randint(2, 4),
                                 seed=300 + i * 5)

    rng = random.Random(11)
    # A few loose verge scatters + tufts as accents — the MASS of the grass now
    # lives in the building base bands above (owner). ry is chosen FIRST and the
    # centre y clamped so the whole scatter ellipse stays ON the verge.
    walk_edge = ROAD_HALF_W + SIDEWALK_W
    for i in range(7):
        x = rng.uniform(-7.5, 18.0)
        side = rng.choice((1, -1))
        ry = rng.uniform(0.18, 0.33)
        y = side * rng.uniform(walk_edge + 0.10 + ry, BUILDING_FRONT_Y - 0.10 - ry)
        kits["near"].grass_patch("patch_%d" % i, x, y,
                                 rx=rng.uniform(0.30, 0.75), ry=ry,
                                 dark=rng.random() < 0.5, blades=rng.randint(2, 4),
                                 seed=i * 13 + 1)
    for i in range(7):
        x = rng.uniform(-7.0, 12.0)
        side = rng.choice((1, -1))
        y = side * rng.uniform(ROAD_HALF_W + SIDEWALK_W + 0.40, BUILDING_FRONT_Y - 0.3)
        kits["near"].grass_tuft("tuft_%d" % i, x, y, rng.uniform(0.7, 1.0))
    setup_load_rig()
    return {"trees": len(TREES), "lamps": len(LAMPS), "fences": len(FENCES), "tufts": 26}
