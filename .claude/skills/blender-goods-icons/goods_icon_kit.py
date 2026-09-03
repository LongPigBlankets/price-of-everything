"""Goods icons in the shipped goods-icon style, built on sprite_kit.

Style sheet (measured 2026-09-03 from assets/icons/goods/medium/*):
  * ink navy  sRGB ~(20, 30, 60); OUTER contour 1.2-1.8% of the long side (12-14 px at 800),
    INNER lines 0.4-1.5% (4-12 px at 800), both the same navy. The outer line is NOT
    Freestyle's: it is synthesised in 2D by icon_export.py so holes and slots don't get one.
  * three-tone cel shading: top brightest, front (-Y) lit, right (+X) shaded ~0.6x, and the
    shaded face carries a halftone (stylize.py, spacing ~1.2% of width).
  * palette per icon: one body tone, one warm accent, navy glass/openings, white where the
    good IS white (aluminium), wood for pallets. Colours below are BASE values calibrated on
    the Standard view transform with sun 3.0 / world 0.30 (swatch_std2.png):
        teal (0.19,0.29,0.29) -> front 117/136/136   yellow (0.80,0.55,0.05) -> 219/185/59
        white (0.95,0.95,0.93) -> ~245                wood (0.65,0.45,0.26) -> ~200/168/128
        car blue-grey (0.12,0.18,0.28) -> 92/111/136  glass (0.012,0.02,0.06) -> ~20/28/60
        jerry red (0.32,0.07,0.07) -> ~145/70/68      steel (0.30,0.40,0.44) -> 141/160/168
  * true-iso ortho camera (the sprite rig), framed from PROJECTED extents with ~6% margin.
Run AFTER sprite_kit.py in the same namespace (exec both).
"""
import bpy, math, mathutils

ICON_PALETTE = {
    "ic_teal":      (0.215, 0.315, 0.315),
    "ic_teal_dark": (0.12, 0.19, 0.19),
    "ic_yellow":    (0.80, 0.55, 0.05),
    "ic_yellow_lo": (0.55, 0.36, 0.03),
    "ic_white":     (1.00, 1.00, 0.98),
    "ic_wood":      (0.65, 0.45, 0.26),
    "ic_wood_lo":   (0.42, 0.28, 0.15),
    "ic_strap":     (0.08, 0.09, 0.10),
    "ic_carbody":   (0.12, 0.18, 0.28),
    "ic_glass":     (0.012, 0.020, 0.060),
    "ic_red":       (0.32, 0.07, 0.07),
    "ic_red_lo":    (0.20, 0.045, 0.045),
    "ic_steel":     (0.30, 0.40, 0.44),
    "ic_silver":    (0.62, 0.66, 0.70),
    "ic_tyre":      (0.040, 0.040, 0.045),
    "ic_lamp":      (0.85, 0.80, 0.55),
    "ic_lamp_red":  (0.60, 0.05, 0.04),
    "ic_navy":      (0.006, 0.012, 0.045),
}
for k, v in ICON_PALETTE.items():
    PALETTE[k] = v

INK = (0.006, 0.012, 0.045)


def toon_mat(name, colour, steps=((0.66, 0.32), (0.92, 0.60), (9.0, 1.0))):
    """Three FLAT tone steps instead of a Lambert gradient: a white diffuse -> Shader to RGB
    -> constant ColorRamp -> multiplied into the base colour -> emission. A cylinder then
    renders as a lit band, a mid band and a shadow band, which is how the reference icons
    describe round forms (round-three review: the smooth gradient was the single biggest
    'this is a 3D render' tell). Thresholds are on the shading factor s = world + sun*cos/pi
    (0.58 .. 1.09 on this rig): s < 0.66 shadow, < 0.92 mid, else lit."""
    m = bpy.data.materials.get(name)
    if m is None:
        m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    emis = nt.nodes.new("ShaderNodeEmission")
    diff = nt.nodes.new("ShaderNodeBsdfDiffuse")
    diff.inputs["Color"].default_value = (1, 1, 1, 1)
    s2r = nt.nodes.new("ShaderNodeShaderToRGB")
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.interpolation = 'CONSTANT'
    els = ramp.color_ramp.elements
    els[0].position = 0.0; els[0].color = (steps[0][1],) * 3 + (1,)
    els[1].position = steps[0][0]; els[1].color = (steps[1][1],) * 3 + (1,)
    e3 = els.new(steps[1][0]); e3.color = (steps[2][1],) * 3 + (1,)
    mix = nt.nodes.new("ShaderNodeMix")
    mix.data_type = 'RGBA'; mix.blend_type = 'MULTIPLY'
    mix.inputs["Factor"].default_value = 1.0
    mix.inputs[6].default_value = (*colour, 1.0)          # A = base colour
    nt.links.new(diff.outputs[0], s2r.inputs[0])
    nt.links.new(s2r.outputs["Color"], ramp.inputs["Fac"])
    nt.links.new(ramp.outputs["Color"], mix.inputs[7])     # B = step
    nt.links.new(mix.outputs[2], emis.inputs["Color"])
    emis.inputs["Strength"].default_value = 1.0
    nt.links.new(emis.outputs[0], out.inputs[0])
    return m   # LINEAR: Freestyle colour goes through the view transform -> sRGB (20,28,60). (The earlier "black" was the factory LineSet drawing over ours.)


def setup_icon_rig(res=1024):
    """The sprite rig, then the icon overrides: Standard view transform (AgX crushes the
    icons' whites and yellows), a real SUN (a fresh scene's 'Light' is a POINT light and
    lights nothing), lower ambient so faces split, thicker interior ink."""
    cube = bpy.data.objects.get("Cube")
    if cube:
        bpy.data.objects.remove(cube, do_unlink=True)
    setup_rig(ortho_scale=6.0, target=(0.0, 0.0, 0.0), res=res)
    scene = bpy.context.scene
    scene.view_settings.view_transform = 'Standard'
    scene.view_settings.look = 'None'
    scene.view_settings.exposure = 0.0
    scene.view_settings.gamma = 1.0
    scene.world.use_nodes = True
    bg = scene.world.node_tree.nodes.get("Background")
    bg.inputs[0].default_value = (1, 1, 1, 1)
    # GOODS shading is gentler than the buildings': world 0.58 / sun 1.6 puts the shaded
    # (+X) face at ~0.65x the lit face (world/(world + sun*cos62/pi)); the sprites' 3.0/0.30
    # gave 0.33x, which the owner read as too aggressive on an icon
    bg.inputs[1].default_value = 0.58
    sun = bpy.data.objects["Light"]
    if sun.data.type != 'SUN':
        sun.data.type = 'SUN'
    sun.data.energy = 1.6
    sun.data.use_shadow = False
    sun.data.angle = 0.0
    d = mathutils.Vector(SUN_DIR).normalized()
    sun.rotation_euler = (-d).to_track_quat('-Z', 'Y').to_euler()
    fs = scene.view_layers[0].freestyle_settings
    # a factory scene ships its own black "LineSet"; it drew every interior line black
    # over ours (the reviewer measured 13k pure-black pixels). Ours are the only linesets.
    for ls in fs.linesets:
        if ls.name not in ("ink", "ink_fine", "contour"):
            ls.show_render = False
    fs.linesets["ink"].linestyle.color = INK
    fs.linesets["ink"].linestyle.thickness = 6.0      # owner: interior lines thinner still      # ~6 px at 800: the reference icons' interior line (measured 6-12 px)
    fs.linesets["ink_fine"].linestyle.color = INK
    fs.linesets["ink_fine"].linestyle.thickness = 2.6
    fs.linesets["contour"].show_render = False        # synthesised in 2D instead
    fs.crease_angle = math.radians(150)   # ink the facet edges of a 10-sided barrel (dihedral 144)
    # faces marked `freestyle_face` take NO ink at all (straps get a 2D outline in export;
    # Freestyle's silhouette flickers segment-by-segment on a near-edge-on flat strip)
    for ls in (fs.linesets["ink"], fs.linesets["ink_fine"]):
        ls.select_by_face_marks = True
        ls.face_mark_negation = 'EXCLUSIVE'
        ls.face_mark_condition = 'ONE'


def hide_other_icons(keep):
    for c in bpy.data.collections:
        if c.name.startswith("BLDG_") or c.name.startswith("ICON_"):
            hidden = c.name != keep
            c.hide_render = hidden
            c.hide_viewport = hidden


def frame_collection(col, margin=0.06):
    """Camera target = centre of the PROJECTED extents; ortho_scale from the larger range."""
    right = mathutils.Vector((1, 1, 0)).normalized()
    up = mathutils.Vector((-1, 1, 2)).normalized()
    cols, hts, pts = [], [], []
    for ob in col.objects:
        if ob.type != 'MESH':
            continue
        for v in ob.data.vertices:
            p = ob.matrix_world @ v.co
            pts.append(p)
            cols.append(p.dot(right))
            hts.append(p.dot(up))
    c0, c1, h0, h1 = min(cols), max(cols), min(hts), max(hts)
    mean = sum(pts, mathutils.Vector()) / len(pts)
    target = mean + right * ((c0 + c1) / 2 - mean.dot(right)) + up * ((h0 + h1) / 2 - mean.dot(up))
    span = max(c1 - c0, h1 - h0) * (1 + 2 * margin)
    cam = bpy.data.objects["Camera"]
    cam.location = target + mathutils.Vector((1, -1, 1)).normalized() * 26.0
    cam.data.ortho_scale = span
    return {"span": round(span, 3), "target": [round(t, 3) for t in target]}


SUN_DIR = (0.06, -0.56, 0.83)   # overhead-front: top lit, upper flank mid, lower flank shadow (review v7)


def shade_mask_material():
    """Emission = dot(N, L) mapped to 0..1, so a second pass records which faces are lit.
    CREATED every call (a fresh Blender has no such material and a None override renders
    the scene normally, which is exactly the silent failure the sprite skill warns about)."""
    m = bpy.data.materials.get("_icon_shade_mask")
    if m is None:
        m = bpy.data.materials.new("_icon_shade_mask")
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    emis = nt.nodes.new("ShaderNodeEmission")
    geo = nt.nodes.new("ShaderNodeNewGeometry")
    dot = nt.nodes.new("ShaderNodeVectorMath"); dot.operation = 'DOT_PRODUCT'
    L = mathutils.Vector(SUN_DIR).normalized()
    dot.inputs[1].default_value = (L.x, L.y, L.z)
    mul = nt.nodes.new("ShaderNodeMath"); mul.operation = 'MULTIPLY_ADD'
    mul.inputs[1].default_value = 0.5
    mul.inputs[2].default_value = 0.5
    nt.links.new(geo.outputs["Normal"], dot.inputs[0])
    nt.links.new(dot.outputs["Value"], mul.inputs[0])
    nt.links.new(mul.outputs[0], emis.inputs["Color"])
    emis.inputs["Strength"].default_value = 1.0
    nt.links.new(emis.outputs[0], out.inputs[0])
    return m


def render_icon(col_name, out_path):
    """Colour pass, then the shading-mask pass (same camera, Freestyle off, Standard view) to
    <out_path minus .png>_mask.png. icon_export.py stipples from the mask, never from luma."""
    hide_other_icons(col_name)
    col = bpy.data.collections[col_name]
    fr = frame_collection(col)
    scene = bpy.context.scene
    vl = scene.view_layers[0]
    scene.render.filepath = out_path
    bpy.ops.render.render(write_still=True)
    # mask pass
    prev_override = vl.material_override
    prev_fs = scene.render.use_freestyle
    prev_bg = scene.world.node_tree.nodes["Background"].inputs[1].default_value
    vl.material_override = shade_mask_material()
    scene.render.use_freestyle = False
    scene.world.node_tree.nodes["Background"].inputs[1].default_value = 0.0
    scene.render.filepath = out_path[:-4] + "_mask.png"
    bpy.ops.render.render(write_still=True)
    vl.material_override = prev_override
    scene.render.use_freestyle = prev_fs
    scene.world.node_tree.nodes["Background"].inputs[1].default_value = prev_bg
    scene.render.filepath = out_path
    return fr


# ---------------------------------------------------------------- MOTOR
def build_motor():
    """Induction motor v4 (owner, round three): FLAT front plate with a bold shaft cover,
    a 10-sided faceted barrel carrying thick long side plates, a much bigger front-mounted
    terminal box, an angled skirt between the two feet, three-step toon tones, thinner
    interior ink. Proportions in D (barrel diameter): L 1.15 D, cowl 1.3 D, flange 1.15 D."""
    setup_icon_rig()
    col = open_collection("ICON_motor")
    K = Kit(col)
    teal = toon_mat("tn_teal", (0.34, 0.44, 0.44))
    dark = toon_mat("tn_teal_dark", (0.24, 0.32, 0.32))
    yel = toon_mat("tn_yellow", (0.90, 0.62, 0.06))
    yel_lo = toon_mat("tn_yellow_lo", (0.55, 0.36, 0.03))
    steel = toon_mat("tn_steel", (0.40, 0.50, 0.54))
    silver = toon_mat("tn_silver", (0.62, 0.66, 0.70))
    navy = K.mat("ic_navy")
    R = 0.95
    D = 2 * R
    L = 1.15 * D
    yc = 0.0
    y_front, y_back = yc - L / 2, yc + L / 2
    # BARREL: a 10-sided prism, flat-shaded, so it reads as plates with inked facet edges
    barrel = K.cyl("body", 0.0, yc, 0.0, R, L, teal, axis='Y', segments=10, smooth=False)
    # thick long plates on the left and right flanks (three per side), full length
    for sg in (-1, 1):
        for i, z in enumerate((0.42, 0.0, -0.42)):
            x_face = math.sqrt(max(R * R - z * z, 0.0)) * math.cos(math.radians(18))
            K.box("plate%s%d" % ("p" if sg > 0 else "m", i), sg * (x_face + 0.05), yc + 0.04, z, 0.16, L + 0.06, 0.22, dark)   # runs INTO flange and cowl
    # FRONT: flat end plate ring (1.15 D, proud), FLAT face, bolted; a bold shaft cover
    K.cyl("flange", 0.0, y_front - 0.10, 0.0, 1.15 * R, 0.20, dark, axis='Y', segments=48, smooth=True)
    K.cyl("face", 0.0, y_front - 0.20 - 0.03, 0.0, 1.06 * R, 0.10, teal, axis='Y', segments=48, smooth=True)
    y_face = y_front - 0.20 - 0.08
    for i, ang in enumerate((30, 90, 150, 210, 270, 330)):
        th = math.radians(ang)
        bolt_dot(K, "fbolt%d" % i, (0.92 * R * math.sin(th), y_face - 0.012, 0.92 * R * math.cos(th)), 'Y', 0.06, navy)
    K.cyl("cover_rim", 0.0, y_face - 0.05, 0.0, 0.52, 0.12, dark, axis='Y', segments=48, smooth=True)   # bold cover
    K.cyl("cover", 0.0, y_face - 0.10 - 0.14, 0.0, 0.44, 0.30, teal, axis='Y', segments=48, smooth=True)
    K.cyl("cover_face", 0.0, y_face - 0.10 - 0.28 - 0.02, 0.0, 0.36, 0.06, dark, axis='Y', segments=48, smooth=True)
    y_shaft0 = y_face - 0.42
    K.cyl("shaft", 0.0, y_shaft0 - 0.47, 0.0, 0.19, 0.96, steel, axis='Y', segments=32, smooth=True)
    # REAR: fan cowl 1.3 D, larger than the barrel, with a flat grille cap
    K.cyl("cowl", 0.0, y_back + 0.30 - 0.04, 0.0, 1.15 * R, 0.68, dark, axis='Y', segments=48, smooth=True)
    K.cyl("cowl_cap", 0.0, y_back + 0.62, 0.0, 1.06 * R, 0.06, teal, axis='Y', segments=48, smooth=True)
    for i in range(3):
        K.cyl("grille%d" % i, 0.0, y_back + 0.66, 0.0, 0.28 + 0.28 * i, 0.02, dark, axis='Y', segments=48, smooth=True)
    # TERMINAL BOX: big (0.42 D wide, 0.45 D long, 0.5 D tall) and front-mounted on a pad
    bw, bl, bh = 0.57 * D, 0.60 * D, 0.32 * D
    by = y_front + 0.10 + bl / 2
    pad_y0, pad_y1 = by - bl / 2 - 0.07, y_back - 0.09     # up to the rear face, not through its rim
    K.box("pad", 0.0, (pad_y0 + pad_y1) / 2, R - 0.08, bw + 0.14, pad_y1 - pad_y0, 0.34, dark)   # back to the rear face
    zb = R + 0.09
    K.box("tbox", 0.0, by, zb + bh / 2, bw, bl, bh, yel)
    K.box("tlid", 0.0, by, zb + bh + 0.045, bw + 0.05, bl + 0.05, 0.09, yel_lo)
    K.box("tlid_top", 0.0, by, zb + bh + 0.11, bw - 0.05, bl - 0.05, 0.04, yel)
    K.box("box_seam", 0.0, by, zb + 0.012, bw + 0.02, bl + 0.02, 0.024, navy)      # ink where box meets pad
    for i, y in enumerate((by - 0.18, by + 0.18)):
        gz = zb + bh * 0.45
        K.cyl("gland%d" % i, bw / 2 + 0.08, y, gz, 0.10, 0.18, yel, axis='X', segments=24, smooth=True)
        K.cyl("gland_seam%d" % i, bw / 2 + 0.012, y, gz, 0.115, 0.024, navy, axis='X', segments=24, smooth=True)   # clear seam
        K.cyl("bore%d" % i, bw / 2 + 0.175, y, gz, 0.055, 0.02, navy, axis='X', segments=12, smooth=True)
    # lifting eye on the crown behind the box
    K.box("eye_post", 0.0, by + bl / 2 + 0.30, R + 0.04, 0.10, 0.10, 0.16, dark)
    K.washer("eye", (0.0, by + bl / 2 + 0.30, R + 0.24), (1.0, 1.0, 0.0), 0.06, 0.14, 0.06, dark, seg=24)
    # FEET: two cast feet at the reviewed height, an ANGLED SKIRT between them, thin plate
    plate_top = -1.40
    foot_h = (-R + 0.12) - plate_top
    for i, y in enumerate((y_front + 0.28, y_back - 0.28)):
        # angled: wide at the base plate, narrow where it meets the barrel (the reference's
        # feet are splayed brackets, not posts)
        wedge_y(K, "foot%d" % i, y - 0.20, y + 0.20, plate_top + 0.02, -R + 0.12, 1.56, 0.86, dark)
        K.box("foot_web%d" % i, 0.0, y, plate_top + 0.09, 1.72, 0.40, 0.18, dark)
        for sg in (-1, 1):
            K.box("fslot%d%d" % (i, sg > 0), sg * 0.72, y, plate_top + 0.185, 0.10, 0.22, 0.012, navy)
    # skirt: a plate leaning from under the barrel down to the base between the feet
    wedge_y(K, "skirt", y_front + 0.28 + 0.18, y_back - 0.28 - 0.18, plate_top + 0.02, -R + 0.18, 1.40, 0.70, dark)
    K.box("plate", 0.0, yc + 0.06, plate_top - 0.06, 1.66, L - 0.02, 0.12, teal)   # ends at the flange plane
    # nameplate low on the front-right facet
    K.rotbox("plate_bezel", 0.86 * R, y_front + 0.36, -0.10, 0.03, 0.30, 0.20, navy, 'Y', 0)
    K.rotbox("nameplate", 0.86 * R + 0.02, y_front + 0.36, -0.10, 0.03, 0.26, 0.16, silver, 'Y', 0)
    print("\n".join(K.validate(ground=-1.6)))
    return {"objects": len(col.objects)}


def noink(ob):
    """Mark every face so Freestyle draws nothing on this object."""
    me = ob.data
    attr = me.attributes.get("freestyle_face") or me.attributes.new("freestyle_face", 'BOOLEAN', 'FACE')
    for d in attr.data:
        d.value = True
    return ob


def bolt_dot(K, name, c, axis, r, mat):
    """A bolt head as the reference draws it: a plain dark disc, no ink of its own (tiny inked
    cylinders came out as broken C marks)."""
    cx, cy, cz = c
    return noink(K.cyl(name, cx, cy, cz, r, 0.03, mat, axis=axis, segments=16, smooth=True))


def wedge_y(K, name, y0, y1, z_bot, z_top, w_bot, w_top, mat):
    """Solid trapezoidal prism along Y: wide at the bottom, narrow at the top - an angled
    casting skirt between two feet."""
    import bmesh
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    prof = [(-w_bot / 2, z_bot), (w_bot / 2, z_bot), (w_top / 2, z_top), (-w_top / 2, z_top)]
    a = [bm.verts.new((x, y0, z)) for (x, z) in prof]
    b = [bm.verts.new((x, y1, z)) for (x, z) in prof]
    bm.faces.new(list(reversed(a))); bm.faces.new(b)
    for i in range(4):
        j = (i + 1) % 4
        bm.faces.new((a[i], a[j], b[j], b[i]))
    bm.normal_update()
    bm.to_mesh(me); bm.free()
    ob = K.obj(name, me, mat)
    for pgon in ob.data.polygons:
        pgon.use_smooth = False
    return ob


def ribbon(K, name, pts, y, width, thick, mat, closed=False):
    """A flat strap with real thickness, every face marked `freestyle_face` so Freestyle
    draws NOTHING on it (its silhouette flickered segment-by-segment on the near-edge-on
    parts); icon_export.py draws the strap's outline in 2D instead. The thickness matters
    even un-inked: an open strip seen edge-on through the gaps between rods vanished into
    grey slivers, a solid one reads as the strap's edge."""
    import bmesh
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    rows = []
    for (x, z, nx, nz) in pts:
        ia = bm.verts.new((x, y - width / 2, z)); ib = bm.verts.new((x, y + width / 2, z))
        oa = bm.verts.new((x + nx * thick, y - width / 2, z + nz * thick))
        ob = bm.verts.new((x + nx * thick, y + width / 2, z + nz * thick))
        rows.append((ia, ib, oa, ob))
    n = len(rows)
    rng = range(n) if closed else range(n - 1)
    for i in rng:
        a, b = rows[i], rows[(i + 1) % n]
        bm.faces.new((a[2], a[3], b[3], b[2]))
        bm.faces.new((b[0], b[1], a[1], a[0]))
        bm.faces.new((a[0], a[2], b[2], b[0]))
        bm.faces.new((b[1], b[3], a[3], a[1]))
    if not closed:
        bm.faces.new((rows[0][0], rows[0][1], rows[0][3], rows[0][2]))
        bm.faces.new((rows[-1][2], rows[-1][3], rows[-1][1], rows[-1][0]))
    bm.normal_update()
    bm.to_mesh(me); bm.free()
    ob = K.obj(name, me, mat, smooth=True)
    attr = me.attributes.get("freestyle_face") or me.attributes.new("freestyle_face", 'BOOLEAN', 'FACE')
    for d in attr.data:
        d.value = True
    return ob


def stack_outline(circles, r, off, n_ang=180):
    """A TENSIONED strap does not dip into the valleys between rods: its path is the convex
    hull of the offset discs (arcs over the outer rods, straight runs between them). Returns
    an angle-ordered polyline of (x, z, nx, nz) with outward normals."""
    R = r + off
    samples = []
    for (cx, cz) in circles:
        for k in range(n_ang):
            th = 2 * math.pi * k / n_ang
            samples.append((cx + R * math.cos(th), cz + R * math.sin(th), math.cos(th), math.sin(th)))
    samples.sort()
    def cross(o, a, b):
        return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])
    lower, upper = [], []
    for p in samples:
        while len(lower) >= 2 and cross(lower[-2], lower[-1], p) <= 1e-9:
            lower.pop()
        lower.append(p)
    for p in reversed(samples):
        while len(upper) >= 2 and cross(upper[-2], upper[-1], p) <= 1e-9:
            upper.pop()
        upper.append(p)
    hull = lower[:-1] + upper[:-1]
    mx = sum(c[0] for c in circles) / len(circles)
    mz = sum(c[1] for c in circles) / len(circles)
    hull.sort(key=lambda p: math.atan2(p[1] - mz, p[0] - mx))
    return hull


# ---------------------------------------------------------------- ALUMINIUM
def build_aluminium():
    """Aluminium rods in a 4-5-4 hex pack on a wooden pallet, ends to the camera, two
    straps that follow the scalloped outline of the bundle (owner: they must curve
    around the rods, not box them)."""
    setup_icon_rig()
    col = open_collection("ICON_aluminium")
    K = Kit(col)
    wood, wood_lo, strap = K.mat("ic_wood"), K.mat("ic_wood_lo"), K.mat("ic_strap")
    # the reference rods are FLAT white with stipple on the underside only: an unlit
    # (emissive) white takes no gradient, and the mask pass still shades the stipple
    white = _emissive("ic_white_flat", (0.86, 0.86, 0.84), 1.0)
    r, L = 0.40, 3.40
    pitch = 2 * r + 0.01
    rise = pitch * math.sqrt(3) / 2
    pz = 0.0
    deck_top = pz + 0.36
    z0 = deck_top + r
    rows = [(4, z0), (5, z0 + rise), (4, z0 + 2 * rise)]
    circles = []
    for n, z in rows:
        for i in range(n):
            circles.append(((i - (n - 1) / 2) * pitch, z))
    # pallet: bearers along Y, deck boards along Y (their ends show like the rod ends)
    for i, x in enumerate((-1.60, 0.0, 1.60)):
        K.box("bearer%d" % i, x, 0.0, pz + 0.12, 0.30, L + 0.30, 0.24, wood_lo)
    for i, x in enumerate((-1.66, -0.83, 0.0, 0.83, 1.66)):
        K.box("deck%d" % i, x, 0.0, pz + 0.30, 0.58, L + 0.30, 0.12, wood)
    for i, y in enumerate((-L / 2 - 0.05, 0.0, L / 2 + 0.05)):
        K.box("bottom%d" % i, 0.0, y, pz + 0.02, 3.62, 0.30, 0.04, wood_lo)
    for j, (cx, cz) in enumerate(circles):
        K.cyl("rod%02d" % j, cx, 0.0, cz, r, L, white, axis='Y', segments=48, smooth=True)
    # straps: the union outline of the rods, clipped where it dives into the pallet
    outline = stack_outline(circles, r, 0.025)
    keep = [p for p in outline if p[1] > deck_top + 0.02]
    # rotate so the open end (the gap under the pallet) is at the list ends
    gaps = [(math.hypot(keep[(i + 1) % len(keep)][0] - keep[i][0], keep[(i + 1) % len(keep)][1] - keep[i][1]), i)
            for i in range(len(keep))]
    _, gi = max(gaps)
    keep = keep[gi + 1:] + keep[:gi + 1]
    first, last = keep[0], keep[-1]
    path = [(first[0], pz + 0.06, first[2], 0.0)] + keep + [(last[0], pz + 0.06, last[2], 0.0)]   # under the deck
    for i, y in enumerate((-0.95, 0.85)):
        ribbon(K, "strap%d" % i, path, y, 0.11, 0.045, strap)
        # a small crimp seal where the strap closes, on the top-left rod
        K.box("seal%d" % i, -0.78 * 1.5, y, z0 + 2 * rise + r + 0.05, 0.14, 0.14, 0.07, strap)
    print("\n".join(K.validate(ground=-0.05)))
    return {"objects": len(col.objects)}


# ---------------------------------------------------------------- DIESEL CAR
def build_diesel_car():
    """Sedan nose to the camera (-Y) with a jerrycan at its front-right, as in the icon."""
    setup_icon_rig()
    col = open_collection("ICON_diesel_car")
    K = Kit(col)
    body, glass, tyre = K.mat("ic_carbody"), K.mat("ic_glass"), K.mat("ic_tyre")
    silver, lamp, lamp_r = K.mat("ic_silver"), K.mat("ic_lamp"), K.mat("ic_lamp_red")
    red, red_lo, navy = K.mat("ic_red"), K.mat("ic_red_lo"), K.mat("ic_navy")
    S = 2.6                       # design units below are the vehicles_kit sedan, scaled
    def bx(nm, cx, cy, cz, sx, sy, sz, m):
        # design frame: length along +X (nose +X). Rotate -90 about Z so nose -> -Y.
        return K.box(nm, cy * S, -cx * S, cz * S, sy * S, sx * S, sz * S, m)
    def rbx(nm, cx, cy, cz, sx, sy, sz, m, ang, axis='Y'):
        # a Y-rotation in the design frame becomes an X-rotation after the -90 turn
        ax = 'X' if axis == 'Y' else 'Y'
        return K.rotbox(nm, cy * S, -cx * S, cz * S, sy * S, sx * S, sz * S, m, ax, ang if axis == 'Y' else -ang)
    bx("rocker", 0.0, 0.0, 0.143, 0.72, 0.42, 0.100, body)
    bx("belt", 0.0, 0.0, 0.2765, 1.44, 0.48, 0.167, body)
    # wheel arches: navy "cut-outs" on the flanks above each wheel, proud by EPS, so the
    # wheels read as standing in openings rather than bolted to a slab
    for wx in (0.52, -0.52):
        for sg in (-1, 1):
            bx("arch%s%d" % ("f" if wx > 0 else "r", sg > 0), wx, sg * (0.24 + EPS / S), 0.215, 0.30, 0.01, 0.045, navy)
    bx("nose1", 0.78, 0.0, 0.2705, 0.12, 0.470, 0.155, body)
    bx("nose2", 0.855, 0.0, 0.2580, 0.05, 0.380, 0.130, body)
    bx("nose3", 0.885, 0.0, 0.2450, 0.03, 0.260, 0.100, body)
    bx("fbumper", 0.845, 0.0, 0.205, 0.09, 0.44, 0.05, body)
    bx("tail_end", -0.76, 0.0, 0.2705, 0.12, 0.470, 0.155, body)
    bx("rbumper", -0.83, 0.0, 0.205, 0.06, 0.44, 0.05, body)
    # cabin frustum: build in the design frame then rotate the object
    z0, z1, cxc = 0.360, 0.478, -0.10
    me = bpy.data.meshes.new("cabin")
    import bmesh
    bm = bmesh.new()
    lx0, ly0, lx1, ly1 = 0.86 * S, 0.44 * S, 0.765 * S, 0.37 * S
    bot = [bm.verts.new(v) for v in ((-lx0/2, -ly0/2, z0*S), (lx0/2, -ly0/2, z0*S), (lx0/2, ly0/2, z0*S), (-lx0/2, ly0/2, z0*S))]
    top = [bm.verts.new(v) for v in ((-lx1/2, -ly1/2, z1*S), (lx1/2, -ly1/2, z1*S), (lx1/2, ly1/2, z1*S), (-lx1/2, ly1/2, z1*S))]
    bm.faces.new(list(reversed(bot))); bm.faces.new(top)
    for i in range(4):
        j = (i + 1) % 4
        bm.faces.new((bot[i], bot[j], top[j], top[i]))
    bm.normal_update(); bm.to_mesh(me); bm.free()
    cab = K.obj("cabin", me, body)
    cab.location = (0.0, -cxc * S, 0.0)
    cab.rotation_euler = (0, 0, math.radians(-90))
    for p in cab.data.polygons:
        p.use_smooth = False
    rake, zmid = 22.0, 0.419
    rbx("wscreen", 0.3062, 0.0, zmid, 0.02, 0.38, 0.120, glass, -rake)
    rbx("rscreen", -0.5062, 0.0, zmid, 0.02, 0.38, 0.112, glass, rake)
    for sg in (-1, 1):
        rbx("side%d" % (sg > 0), cxc, sg * 0.204, zmid, 0.58, 0.02, 0.085, glass, sg * 16.5, axis='X')
        bx("hlamp%d" % (sg > 0), 0.872, sg * 0.125, 0.278, 0.03, 0.10, 0.055, lamp)
        bx("tlamp%d" % (sg > 0), -0.815, sg * 0.155, 0.300, 0.02, 0.10, 0.055, lamp_r)
        bx("mirror%d" % (sg > 0), 0.30, sg * 0.26, 0.385, 0.06, 0.05, 0.04, body)
        bx("handle%d" % (sg > 0), -0.05, sg * 0.245, 0.33, 0.10, 0.015, 0.02, navy)
    bx("grille", 0.90, 0.0, 0.245, 0.01, 0.22, 0.06, navy)
    # wheels: tyre + proud silver rim, in open arches; axle Y in design = X in world
    # wheels PROUD of the flanks (body half-width 0.24): tucked inside they vanish
    for i, wx in enumerate((0.52, -0.52)):
        for sg in (-1, 1):
            cy_w, cx_w = -wx * S, sg * 0.255 * S
            zc = 0.115 * S * 0.93 + 0.02
            K.cyl("tyre%d%s" % (i, "p" if sg > 0 else "m"), cx_w, cy_w, zc, 0.115 * S, 0.075 * S, tyre, axis='X', segments=18, smooth=True)
            K.cyl("rim%d%s" % (i, "p" if sg > 0 else "m"), cx_w + sg * 0.040 * S, cy_w, zc, 0.075 * S, 0.012 * S, silver, axis='X', segments=18, smooth=True)
    # jerrycan at the car's front-right (+X, -Y), about half the car's height, clear of the wheel
    j = 0.62
    jx, jy = 0.24 * S + 0.42, -0.60 * S - 0.20     # overlapping the front-right corner, as in the icon
    K.box("jerry", jx, jy, 0.62 * j, 0.62 * j, 0.34 * j, 1.22 * j, red)
    K.box("jerry_rim", jx, jy, 1.25 * j, 0.66 * j, 0.38 * j, 0.06 * j, red_lo)
    for i, dx in enumerate((-0.16, 0.0, 0.16)):
        K.box("jhandle%d" % i, jx + dx * j, jy, 1.38 * j, 0.06 * j, 0.22 * j, 0.20 * j, red_lo)
    K.box("jhandle_bar", jx, jy, 1.49 * j, 0.44 * j, 0.22 * j, 0.05 * j, red_lo)
    K.cyl("jspout", jx + 0.24 * j, jy - 0.05 * j, 1.36 * j, 0.07 * j, 0.14 * j, navy, axis='Z', segments=12, smooth=True)
    K.rotbox("jbraceA", jx, jy - 0.34 * j / 2 - EPS, 0.62 * j, 0.05 * j, 0.03, 0.95 * j, red_lo, 'Y', 32)
    K.rotbox("jbraceB", jx, jy - 0.34 * j / 2 - EPS, 0.62 * j, 0.05 * j, 0.03, 0.95 * j, red_lo, 'Y', -32)
    print("\n".join(K.validate(ground=-0.05)))
    return {"objects": len(col.objects)}


# ---------------------------------------------------------------- CONTROL CAGE
def cage_loft(K, name, sections, mat, levels=2, crease_rings=(), mirror=True, cap=True):
    """Sectioned, MIRRORED control cage under a Subdivision Surface.

    `sections` = [(y, [(x, z), ...]), ...] along Y, each a HALF profile (x >= 0) with the same
    point count, ordered from the bottom seam (x=0, low z) round the outside to the top seam
    (x=0, high z). Quads are laid between consecutive sections, the two ends are capped, a
    Mirror modifier (across X, clipped and merged at the seam) gives the other half, and a
    Subdivision Surface (`levels`) smooths the cage into the surface. `crease_rings` = indices
    of sections whose ring edges stay HARD (crease 1.0): a windscreen base, a bumper line.
    Freestyle inks the evaluated (subdivided) mesh, so the silhouette is the smooth one.
    Use it for lofted bodies (car shells, tanks with domed ends, castings); never for things
    that must stay faceted."""
    import bmesh
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    rings = []
    n = len(sections[0][1])
    for (y, prof) in sections:
        assert len(prof) == n, "every section needs the same point count"
        rings.append([bm.verts.new((x, y, z)) for (x, z) in prof])
    for a, b in zip(rings, rings[1:]):
        for i in range(n - 1):
            bm.faces.new((a[i], a[i + 1], b[i + 1], b[i]))
    if cap:
        bm.faces.new(list(reversed(rings[0])))
        bm.faces.new(rings[-1])
    bm.normal_update()
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me); bm.free()
    ob = K.obj(name, me, mat, smooth=True)
    for pgon in ob.data.polygons:
        pgon.use_smooth = True
    if crease_rings:
        attr = me.attributes.get("crease_edge") or me.attributes.new("crease_edge", 'FLOAT', 'EDGE')
        ring_of = {}
        for ri, ring in enumerate(sections):
            for k in range(n):
                ring_of[ri * n + k] = ri
        for e in me.edges:
            va, vb = e.vertices
            if ring_of.get(va) == ring_of.get(vb) and ring_of.get(va) in crease_rings:
                attr.data[e.index].value = 1.0
    if mirror:
        mm = ob.modifiers.new("Mirror", 'MIRROR')
        mm.use_axis[0] = True; mm.use_axis[1] = False; mm.use_axis[2] = False
        mm.use_clip = True; mm.use_mirror_merge = True; mm.merge_threshold = 0.002
    sd = ob.modifiers.new("Subd", 'SUBSURF')
    sd.levels = levels; sd.render_levels = levels
    return ob


def build_cage_test():
    """Smoke test for cage_loft: a lofted rounded body (a car-shell-like loaf) with hard
    crease rings at the windscreen base and the boot lip."""
    setup_icon_rig()
    col = open_collection("ICON_cage_test")
    K = Kit(col)
    body = toon_mat("tn_carbody", (0.16, 0.24, 0.36))
    def prof(w, h, zb, r):
        # half of a rounded rectangle: bottom seam -> outer side -> top seam
        return [(0.0, zb), (w * 0.8, zb), (w, zb + r), (w, zb + h - r), (w * 0.85, zb + h), (w * 0.45, zb + h + r * 0.5), (0.0, zb + h + r * 0.6)]
    sections = [
        (-1.9, prof(0.55, 0.30, 0.25, 0.10)),
        (-1.3, prof(0.62, 0.42, 0.22, 0.12)),
        (-0.5, prof(0.66, 0.78, 0.20, 0.14)),
        ( 0.4, prof(0.66, 0.82, 0.20, 0.14)),
        ( 1.2, prof(0.62, 0.50, 0.22, 0.12)),
        ( 1.8, prof(0.55, 0.34, 0.25, 0.10)),
    ]
    cage_loft(K, "shell", sections, body, levels=2, crease_rings=(2, 4))
    return {"objects": len(col.objects)}


# ---------------------------------------------------------------- IRON ORE
def nugget(K, name, centre, r, seed, squash=(1.0, 0.92, 0.80), mats=(None, None), cuts=2, noise_amp=0.20, subdiv=2, planes=5):
    """An ore nugget as a ROCK, not a die: an icosphere (level 3, 1280 facets) displaced by
    seeded noise, then CLEAVED by `cuts` random planes whose fills become the grey fracture
    faces the reference draws on every lump. Flat-shaded, so every small facet takes its own
    tone step and the surface reads as rough; the ink only lands on the sharp cleavage rims
    and the silhouette (crease angle 150), so the rock is not a wireframe. Seeded and
    deterministic: bake twice, same rock."""
    import bmesh, random
    from mathutils import noise, Vector
    rng = random.Random(seed)
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=subdiv, radius=r)   # level 2 = 320 chunky facets
    cx, cy, cz = centre
    off = Vector((rng.random() * 50, rng.random() * 50, rng.random() * 50))
    for v in bm.verts:
        n = noise.noise((v.co * (1.1 / r)) + off)          # -1..1, low frequency: big lumps
        n2 = noise.noise((v.co * (3.0 / r)) + off * 1.7)
        v.co = v.co * (1.0 + noise_amp * n + 0.035 * n2)
        v.co = Vector((v.co.x * squash[0], v.co.y * squash[1], v.co.z * squash[2]))
    # cleave: each cut removes the outer cap beyond a plane at ~0.55-0.75 r, then fills it.
    # Fill faces are TAGGED in a face layer, not kept as references: a later bisect may
    # split or remove them and the stale BMFace handle then raises.
    # `planes` flat cuts all round make the lump ANGULAR (the reference lumps are blocks, not
    # balls); only the first `cuts` of them, biased toward the camera, are grey fracture faces
    cut_layer = bm.faces.layers.int.new("cut")
    for k in range(planes):
        d = Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-0.6, 1.0))).normalized()
        if k < cuts:
            d = (d + Vector((0.6, -0.6, 0.5))).normalized()
        dist = r * rng.uniform(0.62, 0.80)
        res = bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:],
                                     plane_co=d * dist, plane_no=d, clear_outer=True, clear_inner=False)
        edges = [g for g in res["geom_cut"] if isinstance(g, bmesh.types.BMEdge)]
        if edges:
            fill = bmesh.ops.holes_fill(bm, edges=edges, sides=0)
            for f in fill["faces"]:
                f[cut_layer] = 1 if k < cuts else 0
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    for f in bm.faces:
        f.material_index = 1 if f[cut_layer] else 0
    # bake the centre into the vertices: an object `location` is not in matrix_world until the
    # depsgraph runs, and frame_collection read every rock at the origin (span 1.6 for a heap)
    for v in bm.verts:
        v.co = v.co + Vector(centre)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me); bm.free()
    ob = K.obj(name, me, mats[0])
    ob.data.materials.append(mats[1])
    for p in ob.data.polygons:
        p.use_smooth = False
    return ob


def build_iron_ore():
    """A tight heap of iron-ore rocks: rust bodies, grey cleavage planes, ink on the sharp rims
    only, halftone on the shadow facets. Reference g_002_iron_ore.png (six lumps, two layers,
    overlapping)."""
    setup_icon_rig()
    fs = bpy.context.scene.view_layers[0].freestyle_settings
    fs.crease_angle = math.radians(150)
    col = open_collection("ICON_iron_ore")
    K = Kit(col)
    rust = toon_mat("tn_rust", (0.39, 0.066, 0.040))
    grey = toon_mat("tn_fracture", (0.35, 0.39, 0.44))
    lumps = [  # (centre, r, seed, cuts)  - bottom layer touching, two smaller on top
        ((-1.05, -0.45, 0.00), 0.72, 21, 2),
        (( 0.25, -0.70, 0.00), 0.66, 22, 1),
        (( 1.32, -0.05, 0.00), 0.64, 23, 2),
        ((-0.35,  0.70, 0.00), 0.68, 24, 2),
        (( 0.95,  0.90, 0.00), 0.62, 25, 1),
        ((-0.50,  0.05, 1.00), 0.60, 26, 2),
        (( 0.70,  0.20, 1.00), 0.56, 27, 1),
    ]
    for i, (c, r, seed, cuts) in enumerate(lumps):
        cz = r * 0.80 * 0.90 if c[2] == 0.0 else c[2]
        nugget(K, "nugget%d" % i, (c[0], c[1], cz), r, seed, mats=(rust, grey), cuts=cuts)
    return {"objects": len(col.objects)}
