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
    d = mathutils.Vector((0.06, -0.56, 0.83)).normalized()
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


SUN_DIR = (0.06, -0.56, 0.83)


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
    # Manufactured wheel faces opt out of body stipple (local asset pass index73).
    info=nt.nodes.new('ShaderNodeObjectInfo')
    exclude=nt.nodes.new('ShaderNodeMath');exclude.operation='COMPARE'
    exclude.inputs[1].default_value=73;exclude.inputs[2].default_value=.1
    nt.links.new(info.outputs['Object Index'],exclude.inputs[0])
    clean=nt.nodes.new('ShaderNodeMath');clean.operation='MAXIMUM'
    nt.links.new(mul.outputs[0],clean.inputs[0]);nt.links.new(exclude.outputs[0],clean.inputs[1])
    nt.links.new(clean.outputs[0], emis.inputs["Color"])
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
    K.box("keyflat", 0.0, y_shaft0 - 0.52, 0.19 - 0.004, 0.08, 0.40, 0.012, silver)
    # REAR: fan cowl 1.3 D, larger than the barrel, with a flat grille cap
    K.cyl("cowl", 0.0, y_back + 0.30 - 0.04, 0.0, 1.15 * R, 0.68, dark, axis='Y', segments=48, smooth=True)
    K.cyl("cowl_cap", 0.0, y_back + 0.62, 0.0, 1.06 * R, 0.06, teal, axis='Y', segments=48, smooth=True)
    for i in range(3):
        K.cyl("grille%d" % i, 0.0, y_back + 0.66, 0.0, 0.28 + 0.28 * i, 0.02, dark, axis='Y', segments=48, smooth=True)
    # TERMINAL BOX: big (0.42 D wide, 0.45 D long, 0.5 D tall) and front-mounted on a pad
    bw, bl, bh = 0.57 * D, 0.60 * D, 0.32 * D
    by = y_front + 0.10 + bl / 2
    pad_y0, pad_y1 = by - bl / 2 - 0.07, y_back + 0.02
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
def build_diesel_car_legacy_v10():
    """The game's long-roof diesel passenger car with its foreground 20 L fuel can.

    Owner/reference rulings: the car is a rounded four-door hatch/estate, not a cuboid
    saloon; body curvature comes from varying cross-sections in one coherent shell; wheel
    arches are cut into that shell; the can has a tapered volume, rolled seam, real handle
    opening, offset cap and inset X stamping.  All dimensions are ratios of wheel diameter D.
    """
    import bmesh

    setup_icon_rig()
    col = open_collection("ICON_diesel_car")
    K = Kit(col)

    body = toon_mat("tn_carbody", (0.28, 0.36, 0.42))
    body_dark = toon_mat("tn_carbody_dark", (0.18, 0.25, 0.30))
    silver = toon_mat("tn_car_silver", (0.52, 0.58, 0.62))
    red = toon_mat("tn_diesel_red", (0.36, 0.085, 0.070))
    red_lo = toon_mat("tn_diesel_red_dark", (0.245, 0.040, 0.035))
    navy = K.mat("ic_navy")

    def loft_y(name, stations, mat, smooth=True):
        """Join equal-count X/Z section loops along Y into one closed volume."""
        me = bpy.data.meshes.new(name)
        bm = bmesh.new()
        rings = []
        for y, xz in stations:
            rings.append([bm.verts.new((x, y, z)) for x, z in xz])
        n = len(rings[0])
        bm.faces.new(list(reversed(rings[0])))
        bm.faces.new(rings[-1])
        for i in range(len(rings) - 1):
            for j in range(n):
                j2 = (j + 1) % n
                bm.faces.new((rings[i][j], rings[i][j2], rings[i + 1][j2], rings[i + 1][j]))
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        bm.to_mesh(me); bm.free()
        return K.obj(name, me, mat, smooth=smooth)

    def body_section(bw, bottom, shoulder, upper_w, upper_z, crown):
        """Nine-point symmetric section: sill, shoulder, roof/bonnet edge and crown."""
        return [(-bw, bottom), (-bw, shoulder), (-upper_w, upper_z),
                (-0.44 * upper_w, crown - 0.025), (0.0, crown),
                (0.44 * upper_w, crown - 0.025), (upper_w, upper_z),
                (bw, shoulder), (bw, bottom)]

    def cabin_section(belt_w, bottom, roof_w, roof_edge, crown):
        """Seven-point greenhouse section with a broad crowned roof and sloped shoulders."""
        return [(-belt_w, bottom), (-roof_w, roof_edge),
                (-0.44 * roof_w, crown - 0.025), (0.0, crown),
                (0.44 * roof_w, crown - 0.025), (roof_w, roof_edge),
                (belt_w, bottom)]

    def panel(name, verts, faces, mat, thickness=0.022):
        """A surface-following trim/glass patch with real thickness."""
        me = bpy.data.meshes.new(name)
        bm = bmesh.new()
        vv = [bm.verts.new(v) for v in verts]
        for f in faces:
            bm.faces.new([vv[i] for i in f])
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        bm.to_mesh(me); bm.free()
        ob = K.obj(name, me, mat, smooth=False)
        sol = ob.modifiers.new("panel_thickness", 'SOLIDIFY')
        sol.thickness = thickness
        sol.offset = 0.0
        return ob

    def ring_prism(name, outer, inner, y0, y1, mat):
        """Extruded planar ring with a genuine opening, used for the can handle."""
        me = bpy.data.meshes.new(name)
        bm = bmesh.new()
        ro0 = [bm.verts.new((x, y0, z)) for x, z in outer]
        ro1 = [bm.verts.new((x, y1, z)) for x, z in outer]
        ri0 = [bm.verts.new((x, y0, z)) for x, z in inner]
        ri1 = [bm.verts.new((x, y1, z)) for x, z in inner]
        n = len(outer)
        for i in range(n):
            j = (i + 1) % n
            bm.faces.new((ro0[i], ro0[j], ro1[j], ro1[i]))
            bm.faces.new((ri0[j], ri0[i], ri1[i], ri1[j]))
            bm.faces.new((ro0[j], ro0[i], ri0[i], ri0[j]))
            bm.faces.new((ro1[i], ro1[j], ri1[j], ri1[i]))
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        bm.to_mesh(me); bm.free()
        return K.obj(name, me, mat, smooth=False)

    D = 0.96
    R = 0.45 * D                  # slightly smaller wheels restore the reference's ~5D stance
    L = 5.05 * D
    y_front, y_back = -L / 2, L / 2

    # A changing-width lower shell establishes the bonnet crown, fender shoulders and
    # tapered tail.  Unlike an extruded side profile, every station changes in X and Z.
    specs = [
        (-2.53, 0.66, 0.25, 0.52, 0.54, 0.63),
        (-2.40, 0.80, 0.23, 0.64, 0.67, 0.77),
        (-1.98, 0.88, 0.22, 0.72, 0.73, 0.90),
        (-1.62, 0.91, 0.21, 0.79, 0.77, 1.04),
        (-1.30, 0.92, 0.21, 0.80, 0.77, 1.06),
        (-1.05, 0.91, 0.22, 0.78, 0.75, 1.03),
        (-0.60, 0.89, 0.23, 0.77, 0.73, 1.06),
        ( 0.30, 0.90, 0.23, 0.77, 0.75, 1.02),
        ( 1.10, 0.90, 0.23, 0.76, 0.76, 1.00),
        ( 1.62, 0.90, 0.23, 0.74, 0.77, 0.97),
        ( 2.12, 0.86, 0.23, 0.70, 0.73, 0.91),
        ( 2.38, 0.79, 0.24, 0.63, 0.66, 0.82),
        ( 2.52, 0.67, 0.28, 0.54, 0.57, 0.70),
    ]
    stations = [(y * D, body_section(bw * D, bot * D, sh * D,
                                      uw * D, (cr - 0.08) * D, cr * D))
                for y, bw, bot, sh, uw, cr in specs]
    shell = loft_y("car_shell", stations, body, smooth=True)

    # The greenhouse is a second sectioned skin sunk into the lower shell.  This keeps a
    # readable bonnet/cowl break while its varying sections still form a curved, long roof.
    cabin_specs = [
        (-0.62, 0.75, 1.00, 0.68, 1.02, 1.07),
        (-0.48, 0.75, 1.00, 0.67, 1.10, 1.16),
        (-0.12, 0.74, 1.00, 0.62, 1.48, 1.57),
        ( 0.16, 0.73, 0.99, 0.61, 1.55, 1.63),
        ( 0.66, 0.73, 0.99, 0.61, 1.58, 1.66),
        ( 1.18, 0.74, 0.99, 0.62, 1.58, 1.66),
        ( 1.50, 0.75, 0.99, 0.64, 1.56, 1.65),
        ( 1.70, 0.76, 0.99, 0.68, 1.50, 1.60),
        ( 1.82, 0.77, 0.99, 0.73, 1.05, 1.12),
    ]
    cabin_stations = [(y * D, cabin_section(bw * D, bot * D, rw * D,
                                             edge * D, cr * D))
                      for y, bw, bot, rw, edge, cr in cabin_specs]
    loft_y("greenhouse", cabin_stations, body, smooth=True)

    # Real wheel wells are Boolean cuts in the shell, not decorative arcs pasted over it.
    helpers = bpy.data.collections.new("GOODS_ICON_HELPERS")
    bpy.context.scene.collection.children.link(helpers)
    wheel_y = (-1.52 * D, 1.62 * D)
    for axle, yw in enumerate(wheel_y):
        cutter = K.cyl("wheelwell_cutter_%d" % axle, 0, yw, R,
                       0.48 * D, 2.6 * D, navy, axis='X', segments=48, smooth=True)
        col.objects.unlink(cutter); helpers.objects.link(cutter)
        cutter.hide_render = True
        cutter.display_type = 'WIRE'
        boo = shell.modifiers.new("wheelwell_%d" % axle, 'BOOLEAN')
        boo.operation = 'DIFFERENCE'
        boo.solver = 'EXACT'
        boo.object = cutter

    # The windshield is a two-panel crowned surface laid directly on the shell.
    panel("windshield",
          [(-0.65 * D, -0.50 * D, 1.09 * D), (0, -0.52 * D, 1.16 * D),
           (0.65 * D, -0.50 * D, 1.09 * D), (-0.56 * D, -0.13 * D, 1.48 * D),
           (0, -0.15 * D, 1.56 * D), (0.56 * D, -0.13 * D, 1.48 * D)],
          [(0, 1, 4, 3), (1, 2, 5, 4)], navy, 0.025 * D)

    # Surface-following side glass establishes four doors and proper A/B/C pillars.
    panel("front_side_window",
          [(0.705 * D, -0.39 * D, 0.92 * D), (0.632 * D, -0.04 * D, 1.49 * D),
           (0.622 * D, 0.52 * D, 1.57 * D), (0.718 * D, 0.52 * D, 0.92 * D)],
          [(0, 1, 2, 3)], navy, 0.024 * D)
    panel("rear_side_window",
          [(0.725 * D, 0.60 * D, 0.92 * D), (0.632 * D, 0.60 * D, 1.57 * D),
           (0.646 * D, 1.34 * D, 1.57 * D), (0.682 * D, 1.65 * D, 1.50 * D),
           (0.742 * D, 1.70 * D, 0.92 * D)],
          [(0, 1, 2, 3, 4)], navy, 0.024 * D)
    # Upright C/hatch closure, separated from the long roof rather than a fastback point.
    K.box("hatch_pillar", 0.755 * D, 1.76 * D, 1.25 * D,
          0.035 * D, 0.045 * D, 0.58 * D, navy)
    K.box("tail_lamp", 0.855 * D, 2.18 * D, 0.73 * D,
          0.035 * D, 0.20 * D, 0.25 * D, red)

    # Bonnet seams follow the crown; fascia pieces are nested and slightly rounded.
    for sg in (-1, 1):
        hood_line = [(sg * 0.46 * D, y * D, z * D) for y, z in
                     ((-2.25, 0.76), (-1.65, 0.89), (-1.05, 0.98), (-0.60, 1.04))]
        K.sweep("bonnet_seam_%s" % ("r" if sg > 0 else "l"),
                hood_line, 0.015 * D, navy, seg=12)
    bumper = K.box("front_bumper", 0, y_front - 0.055 * D, 0.36 * D,
                   1.58 * D, 0.11 * D, 0.16 * D, body_dark)
    bb = bumper.modifiers.new("bumper_round", 'BEVEL'); bb.width = 0.045 * D; bb.segments = 3
    K.box("front_grille", 0, y_front - 0.118 * D, 0.49 * D,
          0.64 * D, 0.025 * D, 0.20 * D, navy)
    for sg in (-1, 1):
        lamp_ob = K.box("headlamp_%s" % ("r" if sg > 0 else "l"), sg * 0.55 * D,
                        y_front - 0.121 * D, 0.66 * D,
                        0.34 * D, 0.026 * D, 0.19 * D, silver)
        bev = lamp_ob.modifiers.new("lamp_round", 'BEVEL')
        bev.width = 0.05 * D; bev.segments = 3

    # Wheels sit inside the subtracted wells.  Only the camera-facing pair is required.
    for axle, yw in enumerate(wheel_y):
        xw = 0.92 * D
        arch = [(0.915 * D,
                 yw + math.cos(math.pi * k / 24) * 0.485 * D,
                 R + math.sin(math.pi * k / 24) * 0.485 * D)
                for k in range(25)]
        K.sweep("fender_lip_%d" % axle, arch, 0.024 * D, body, seg=12)
        K.cyl("tyre_%d" % axle, xw, yw, R, R, 0.24 * D,
              navy, axis='X', segments=48, smooth=True)
        K.cyl("sidewall_%d" % axle, xw + 0.13 * D, yw, R,
              0.375 * D, 0.055 * D, body_dark, axis='X', segments=48, smooth=True)
        K.cyl("rim_%d" % axle, xw + 0.165 * D, yw, R,
              0.265 * D, 0.030 * D, silver, axis='X', segments=48, smooth=True)
        face_x = xw + 0.185 * D
        bolt_dot(K, "hub_%d" % axle, (face_x, yw, R), 'X', 0.047 * D, navy)
        for k in range(5):
            th = 2 * math.pi * k / 5 + math.radians(18)
            bolt_dot(K, "wheel_slot_%d_%d" % (axle, k),
                     (face_x, yw + math.cos(th) * 0.16 * D,
                      R + math.sin(th) * 0.16 * D), 'X', 0.047 * D, navy)

    # Door/sill draughtsmanship follows the visible side rather than slicing the roof.
    xdraw = 0.905 * D
    K.sweep("belt_highlight", [(xdraw, y * D, z * D) for y, z in
                                ((-0.42, 1.03), (0.45, 1.04), (1.48, 1.03))],
            0.020 * D, silver, seg=12)
    K.box("rocker_line", xdraw, 0.40 * D, 0.30 * D,
          0.028 * D, 2.55 * D, 0.055 * D, body_dark)
    for i, yd in enumerate((-0.43, 0.52, 1.50)):
        K.box("door_seam_%d" % i, xdraw, yd * D, 0.69 * D,
              0.030 * D, 0.032 * D, 0.68 * D, navy)
    for i, yh in enumerate((0.18, 0.93)):
        K.box("handle_%d" % i, xdraw + 0.012, yh * D, 0.88 * D,
              0.035 * D, 0.21 * D, 0.052 * D, navy)
    mirror_ob = K.box("mirror", 0.98 * D, -0.39 * D, 1.16 * D,
                      0.24 * D, 0.18 * D, 0.15 * D, body)
    mb = mirror_ob.modifiers.new("mirror_round", 'BEVEL'); mb.width = 0.05 * D; mb.segments = 3

    # Tapered 20 L can: shaped front/back sections, a rolled perimeter seam and inset panel.
    jx, jy = 2.20 * D, -1.74 * D
    can_profile = [(-0.36, 0.04), (-0.43, 0.13), (-0.43, 1.07),
                   (-0.35, 1.20), (-0.20, 1.39), (-0.10, 1.44),
                   (0.20, 1.44), (0.31, 1.34), (0.43, 1.12),
                   (0.43, 0.13), (0.36, 0.04)]
    depth = 0.44 * D
    front_y, back_y = jy - depth / 2, jy + depth / 2
    front_xz = [(jx + x * D, z * D) for x, z in can_profile]
    back_xz = [(jx + x * D * 0.96, z * D) for x, z in can_profile]
    can = loft_y("jerrycan", [(front_y, front_xz), (back_y, back_xz)], red, smooth=False)
    cb = can.modifiers.new("can_edge_roll", 'BEVEL'); cb.width = 0.055 * D; cb.segments = 3

    seam_path = [(x, front_y - 0.030 * D, z) for x, z in front_xz]
    seam_path.append(seam_path[0])
    K.sweep("jerry_rolled_seam", seam_path, 0.032 * D, red_lo, seg=12)

    # Inset stamped panel: a dark border, warm inner field and two narrow raised ribs.
    outer_panel = [(-0.32, 0.23), (0.25, 0.23), (0.35, 0.39),
                   (0.30, 0.91), (0.15, 1.05), (-0.31, 0.96)]
    inner_panel = [(-0.25, 0.30), (0.19, 0.30), (0.27, 0.43),
                   (0.23, 0.84), (0.11, 0.97), (-0.24, 0.89)]
    K.prism("jerry_panel_border", (jx, front_y - 0.050 * D, 0), (1, 0),
            [(x * D, z * D) for x, z in outer_panel], 0.026 * D, navy)
    K.prism("jerry_panel_inset", (jx, front_y - 0.070 * D, 0), (1, 0),
            [(x * D, z * D) for x, z in inner_panel], 0.024 * D, red_lo)
    for i, ang in enumerate((-32, 32)):
        K.rotbox("jerry_rib_%d" % i, jx, front_y - 0.092 * D, 0.63 * D,
                 0.052 * D, 0.024 * D, 0.64 * D, red, 'Y', ang)

    # Camera-facing raised handle: two posts buried into the shoulders, one bridge, and a
    # navy aperture large enough to survive the 128 px derivative.
    handle_y = front_y - 0.085 * D
    K.box("jerry_handle_opening", jx, handle_y, 1.54 * D,
          0.42 * D, 0.026 * D, 0.14 * D, navy)
    K.rotbox("jerry_handle_left", jx - 0.24 * D, handle_y - 0.018 * D, 1.55 * D,
             0.082 * D, 0.045 * D, 0.26 * D, red, 'Y', -11)
    K.rotbox("jerry_handle_right", jx + 0.24 * D, handle_y - 0.018 * D, 1.55 * D,
             0.082 * D, 0.045 * D, 0.26 * D, red, 'Y', 11)
    K.box("jerry_handle_bridge", jx, handle_y - 0.018 * D, 1.66 * D,
          0.51 * D, 0.045 * D, 0.080 * D, red)

    # Offset cap and short neck face the camera and overlap the left shoulder.
    cap_x, cap_y = jx - 0.38 * D, front_y - 0.035 * D
    K.cyl("fuel_neck", cap_x, cap_y, 1.41 * D,
          0.095 * D, 0.12 * D, red_lo, axis='Z', segments=48, smooth=True)
    K.cyl("fuel_cap", cap_x, cap_y, 1.49 * D,
          0.075 * D, 0.045 * D, red, axis='Z', segments=48, smooth=True)

    print("\n".join(K.validate(ground=0.0)))
    return {"objects": len(col.objects)}


# --------------------------------------------------------- DIESEL CAR, CAGE REBUILD
def build_diesel_car():
    """Compact four-door diesel estate and foreground 20 L fuel can.

    Owner/reference rulings: the bonnet is short and integrated into a full rear estate
    volume; the nose, wings, roof and hatch are one mirrored subdivision cage rather than
    stacked primitives; doors are shaped surface panels; the can is yawed toward camera and
    has one angular open handle with fine internal ink.  Dimensions are ratios of wheel D.
    """
    import bmesh
    import mathutils

    setup_icon_rig()
    col = open_collection("ICON_diesel_car")
    K = Kit(col)

    body = toon_mat("tn_carbody", (0.18, 0.26, 0.32))
    body_dark = toon_mat("tn_carbody_dark", (0.18, 0.25, 0.30))
    silver = toon_mat("tn_car_silver", (0.52, 0.58, 0.62))
    # Keep the complete can in the cap's deep fuel-red family.  The former salmon base
    # became pink under the icon rig's lit band and separated the side plane from the cap.
    red = toon_mat("tn_diesel_red", (0.36, 0.060, 0.085))
    red_lo = toon_mat("tn_diesel_red_dark", (0.22, 0.025, 0.050))
    navy = K.mat("ic_navy")

    def cage_shell(name, sections, mat, crease_rings=()):
        """Mirrored half-cage with a two-level subdivision surface."""
        me = bpy.data.meshes.new(name)
        bm = bmesh.new()
        rings = []
        count = len(sections[0][1])
        for y, profile in sections:
            assert len(profile) == count
            rings.append([bm.verts.new((x, y, z)) for x, z in profile])
        for first, second in zip(rings, rings[1:]):
            for i in range(count - 1):
                bm.faces.new((first[i], first[i + 1], second[i + 1], second[i]))
        bm.faces.new(list(reversed(rings[0])))
        bm.faces.new(rings[-1])
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        bm.to_mesh(me); bm.free()
        ob = K.obj(name, me, mat, smooth=True)
        for poly in me.polygons:
            poly.use_smooth = True
        if crease_rings:
            attr = me.attributes.get("crease_edge") or me.attributes.new(
                "crease_edge", 'FLOAT', 'EDGE')
            for edge in me.edges:
                ra, rb = edge.vertices[0] // count, edge.vertices[1] // count
                if ra == rb and ra in crease_rings:
                    attr.data[edge.index].value = 0.78
        mirror = ob.modifiers.new("Mirror", 'MIRROR')
        mirror.use_axis[0] = True
        mirror.use_axis[1] = mirror.use_axis[2] = False
        mirror.use_clip = True
        mirror.use_mirror_merge = True
        mirror.merge_threshold = 0.002
        subd = ob.modifiers.new("Subd", 'SUBSURF')
        subd.subdivision_type = 'CATMULL_CLARK'
        subd.levels = subd.render_levels = 2
        return ob

    def half_profile(width, bottom, shoulder, belt, roof_width, roof_edge, crown):
        """Centre seam to sill, shoulder, glazing/bonnet edge and crowned top."""
        return [(0.00, bottom),
                (0.68 * width, bottom),
                (0.94 * width, bottom + 0.055),
                (width, shoulder),
                (0.97 * width, belt),
                (roof_width, roof_edge),
                (0.45 * roof_width, crown - 0.030),
                (0.00, crown)]

    def surface_panel(name, vertices, mat, thickness=0.014, fine=True):
        """One outlined n-gon laid onto a curved shell or fascia."""
        previous = K._fine_mode
        K._fine_mode = fine
        me = bpy.data.meshes.new(name)
        bm = bmesh.new()
        verts = [bm.verts.new(v) for v in vertices]
        bm.faces.new(verts)
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        bm.to_mesh(me); bm.free()
        ob = K.obj(name, me, mat, smooth=False)
        solid = ob.modifiers.new("surface_thickness", 'SOLIDIFY')
        solid.thickness = thickness
        solid.offset = 0.0
        K._fine_mode = previous
        return ob

    def loft_local(name, sections, mat, smooth=False):
        """Closed local-space X/Z profiles along local Y, for the can."""
        me = bpy.data.meshes.new(name)
        bm = bmesh.new()
        rings = []
        for y, xz in sections:
            rings.append([bm.verts.new((x, y, z)) for x, z in xz])
        n = len(rings[0])
        bm.faces.new(list(reversed(rings[0])))
        bm.faces.new(rings[-1])
        for a, b in zip(rings, rings[1:]):
            for i in range(n):
                j = (i + 1) % n
                bm.faces.new((a[i], a[j], b[j], b[i]))
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        bm.to_mesh(me); bm.free()
        return K.obj(name, me, mat, smooth=smooth)

    def ring_local(name, outer, inner, y0, y1, mat):
        """A single extruded polygon ring: no stacked handle bars."""
        me = bpy.data.meshes.new(name)
        bm = bmesh.new()
        o0 = [bm.verts.new((x, y0, z)) for x, z in outer]
        o1 = [bm.verts.new((x, y1, z)) for x, z in outer]
        i0 = [bm.verts.new((x, y0, z)) for x, z in inner]
        i1 = [bm.verts.new((x, y1, z)) for x, z in inner]
        n = len(outer)
        for k in range(n):
            j = (k + 1) % n
            bm.faces.new((o0[k], o0[j], o1[j], o1[k]))
            bm.faces.new((i0[j], i0[k], i1[k], i1[j]))
            bm.faces.new((o0[j], o0[k], i0[k], i0[j]))
            bm.faces.new((o1[k], o1[j], i1[j], i1[k]))
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        bm.to_mesh(me); bm.free()
        return K.obj(name, me, mat, smooth=False)

    D = 1.0
    R = 0.43 * D
    y_front, y_back = -1.88 * D, 2.90 * D
    wheel_y = (-0.98 * D, 1.80 * D)

    # One control cage carries the complete silhouette.  The cowl stays forward while the
    # wheelbase and estate load bay extend rearward to the reference's near-five-D stance.
    specs = [
        (-1.99, .78, .17, .52, .70, .69, .79, .82),
        (-1.78, .86, .18, .59, .78, .76, .84, .90),
        (-1.34, .89, .20, .62, .84, .70, .89, .96),
        (-0.82, .92, .20, .64, .91, .72, .97, 1.04),
        (-0.35, .92, .20, .65, .96, .68, 1.20, 1.29),
        ( 0.12, .91, .20, .66, .98, .65, 1.40, 1.48),
        ( 0.72, .91, .20, .66, .98, .65, 1.43, 1.51),
        ( 1.30, .91, .20, .66, .98, .65, 1.43, 1.51),
        ( 1.72, .90, .21, .66, .97, .65, 1.42, 1.50),
        ( 2.22, .88, .22, .66, .95, .65, 1.38, 1.47),
        ( 2.55, .84, .24, .64, .91, .63, 1.32, 1.46),
        ( 2.80, .75, .27, .60, .82, .58, 1.12, 1.23),
        ( 2.90, .65, .31, .55, .72, .51, .99, 1.09),
    ]
    sections = [(y * D, half_profile(w * D, b * D, s * D, belt * D,
                                      rw * D, re * D, c * D))
                for y, w, b, s, belt, rw, re, c in specs]
    shell = cage_shell("car_unified_shell", sections, body,
                       crease_rings=(0, 1, 10, 11))

    # Front skin is continuous paint. Suppress cage creases beneath the authored fascia.
    marks=shell.data.attributes.get('freestyle_face') or shell.data.attributes.new('freestyle_face','BOOLEAN','FACE')
    for face,mark in zip(shell.data.polygons,marks.data):
        if face.center.y < -1.25: mark.value=True
    for v in shell.data.vertices:
        if v.co.y < -1.34:
            weight=min(1.0,(-1.34-v.co.y)/.65)
            v.co.y += .24*(v.co.x/.86)**2*weight

    # Wheel wells cut the evaluated shell; the wings remain part of the same moulded nose.
    helpers = bpy.data.collections.new("GOODS_ICON_HELPERS")
    bpy.context.scene.collection.children.link(helpers)
    for axle, yw in enumerate(wheel_y):
        cutter = K.cyl("wheelwell_cutter_%d" % axle, 0, yw, R,
                       0.46 * D, 2.6 * D, navy, axis='X', segments=48, smooth=True)
        col.objects.unlink(cutter); helpers.objects.link(cutter)
        cutter.hide_render = True
        cutter.display_type = 'WIRE'
        boolean = shell.modifiers.new("wheelwell_%d" % axle, 'BOOLEAN')
        boolean.operation = 'DIFFERENCE'
        boolean.solver = 'EXACT'
        boolean.object = cutter

    # Project dense glazing patches onto the EVALUATED shell: the rake and body agree.
    bpy.context.view_layer.update()
    evaluated=shell.evaluated_get(bpy.context.evaluated_depsgraph_get())
    def glazing(name, corners, axis):
        # Rounded corners and continuous surface-following glazing, studied from the
        # downloaded VW model. Corner radius stays modest at icon size.
        pts=[mathutils.Vector((p[0],p[1])) for p in corners]
        outline=[]
        for i,p in enumerate(pts):
            a=p+(pts[i-1]-p)*.075;b=p+(pts[(i+1)%len(pts)]-p)*.075
            for j in range(9):
                t=j/8;outline.append((1-t)**2*a+2*t*(1-t)*p+t*t*b)
        dense=[]
        for a,b in zip(outline,outline[1:]+outline[:1]):
            count=max(1,int((b-a).length/.035)+1)
            for k in range(count):dense.append(a+(b-a)*(k/count))
        outline=dense
        center=sum(outline,mathutils.Vector((0,0)))/len(outline)
        def project(q):
            if axis=='Z': origin=mathutils.Vector((q.x,q.y,4)); direction=mathutils.Vector((0,0,-1))
            else: origin=mathutils.Vector((3,q.x,q.y)); direction=mathutils.Vector((-1,0,0))
            hit,loc,normal,index=evaluated.ray_cast(origin,direction)
            assert hit,(name,tuple(q))
            return tuple(loc+normal*.014)
        vs=[project(center)];faces=[];N=len(outline);bands=24
        for j in range(1,bands+1):
            for p in outline:vs.append(project(center+(p-center)*(j/bands)))
        for i in range(N):faces.append((0,1+i,1+(i+1)%N))
        for j in range(bands-1):
            for i in range(N):
                a=1+j*N+i;b=1+j*N+(i+1)%N
                faces.append((a,b,b+N,a+N))
        me=bpy.data.meshes.new(name);me.from_pydata(vs,[],faces);me.update()
        ob=K.obj(name,me,navy,smooth=True);noink(ob)
        return ob
    glazing('windscreen',[(-.65,-.74,0),(.65,-.74,0),(.57,.13,0),(-.57,.13,0)],'Z')
    glazing('front_side_window',[(-.55,1.005,0),(.74,1.005,0),(.74,1.415,0),(.19,1.38,0)],'X')
    glazing('rear_side_window',[(.83,1.005,0),(2.28,1.005,0),(2.12,1.375,0),(.83,1.415,0)],'X')

    glazing('rear_hatch_glass',[(-.53,2.39,0),(.53,2.39,0),(.45,2.78,0),(-.45,2.78,0)],'Z')

    # Door seams sit on the actual body, avoiding flat plates hovering over curved
    # wings. The B-pillar and front/rear door seam now share the same longitudinal datum.
    def side_line(name, yz, radius, mat):
        path=[]
        for first,second in zip(yz,yz[1:]):
            for j in range(12):
                t=j/12;y=first[0]*(1-t)+second[0]*t;z=first[1]*(1-t)+second[1]*t
                hit,loc,normal,index=evaluated.ray_cast(mathutils.Vector((3,y,z)),mathutils.Vector((-1,0,0)))
                if hit:path.append(tuple(loc+normal*.012))
        ob=K.sweep(name,path,radius,mat,seg=8);noink(ob)
    old_fine = K._fine_mode
    K._fine_mode = True
    side_line('front_door_seam',[(-.57,.95),(-.49,.75),(-.32,.45),(-.17,.34),(.78,.34),(.78,.98)],.007,navy)
    side_line('rear_door_seam',[(.78,.34),(1.34,.34),(1.49,.47),(1.55,.68),(1.69,.94)],.007,navy)
    side_line('shoulder_crease',[(-.55,.965),(.78,.977),(1.70,.961),(2.36,.89)],.006,body_dark)
    for i, (yh, zh) in enumerate(((0.13, .88), (1.12, .87))):
        surface_panel("door_handle_outer_%d" % i,
                      [(0.950, yh - .12, zh), (0.950, yh - .08, zh + .055),
                       (0.950, yh + .09, zh + .045), (0.950, yh + .12, zh),
                       (0.950, yh + .07, zh - .045), (0.950, yh - .08, zh - .040)],
                      navy, .015, fine=True)
        surface_panel("door_handle_inner_%d" % i,
                      [(0.960, yh - .065, zh), (0.960, yh - .035, zh + .018),
                       (0.960, yh + .045, zh + .016), (0.960, yh + .065, zh),
                       (0.960, yh + .035, zh - .015), (0.960, yh - .038, zh - .014)],
                      body, .012, fine=True)
    K._fine_mode = old_fine
    # All front graphics follow the evaluated curved nose, without framed boxes.
    bpy.context.view_layer.update()
    front_eval=shell.evaluated_get(bpy.context.evaluated_depsgraph_get())
    grille_mat=toon_mat('tn_front_grille',(0.075,.115,.155),steps=((.66,.70),(.92,.70),(9,.70)))
    lens_mat=toon_mat('tn_headlamp_lens',(.68,.80,.85),steps=((.66,.85),(.92,.85),(9,.85)))
    reflector=toon_mat('tn_lamp_reflector',(.30,.44,.50),steps=((.66,.70),(.92,.70),(9,.70)))
    amber=toon_mat('tn_indicator',(.88,.25,.085))
    white=toon_mat('tn_lens_white',(.95,.97,.96),steps=((.66,1),(.92,1),(9,1)))
    def project_front(x,z,offset=.035):
        hit,loc,normal,index=front_eval.ray_cast(mathutils.Vector((x,-3.5,z)),mathutils.Vector((0,1,0)))
        assert hit,('front patch missed shell',x,z)
        return loc+mathutils.Vector((0,-offset,0))
    def front_patch(name,points,mat,rounding=.16,ink=True,offset=.035):
        pts=[mathutils.Vector(p) for p in points];outline=[]
        for i,p in enumerate(pts):
            prev=pts[i-1];nxt=pts[(i+1)%len(pts)]
            start=p+(prev-p)*rounding;end=p+(nxt-p)*rounding
            for j in range(7):
                t=j/6;outline.append((1-t)**2*start+2*t*(1-t)*p+t*t*end)
        if rounding==0: outline=pts
        center=sum(outline,mathutils.Vector((0,0)))/len(outline)
        vs=[tuple(project_front(center.x,center.y,offset))];N=len(outline);bands=28
        for j in range(1,bands+1):
            for p in outline:
                q=center.lerp(p,j/bands);vs.append(tuple(project_front(q.x,q.y,offset)))
        faces=[(0,1+i,1+(i+1)%N) for i in range(N)]
        for j in range(bands-1):
            for i in range(N):
                a=1+j*N+i;b=1+j*N+(i+1)%N;faces.append((a,b,b+N,a+N))
        me=bpy.data.meshes.new(name);me.from_pydata(vs,[],faces);me.update()
        bm=bmesh.new();bm.from_mesh(me);bm.normal_update()
        if sum(f.normal.y for f in bm.faces)>0: bmesh.ops.reverse_faces(bm,faces=bm.faces[:])
        bm.to_mesh(me);bm.free()
        noink(K.obj(name,me,mat,smooth=True))
        if ink:
            path=[tuple(project_front(p.x,p.y,offset+.004)) for p in outline+[outline[0]]]
            noink(K.sweep(name+'_ink',path,.009,navy,seg=10))
    front_patch('upper_grille',[(-.37,.765),(.37,.765),(.305,.565),(-.305,.565)],grille_mat,.20)
    for side in (-1,1):
        def signed(points):return [(side*x,z) for x,z in points]
        front_patch('headlamp_'+str(side),signed([(.41,.790),(.715,.824),(.805,.665),(.395,.670)]),lens_mat,.12)
        front_patch('indicator_'+str(side),signed([(.715,.824),(.825,.79),(.855,.68),(.805,.665)]),amber,.13)
        for i,(x,z,r) in enumerate([(.49,.736,.052),(.63,.752,.055)]):
            ring=[(side*(x+math.cos(t*2*math.pi/32)*r),z+math.sin(t*2*math.pi/32)*r) for t in range(32)]
            front_patch('reflector_'+str(side)+'_'+str(i),ring,reflector,0,False,.055)
            glint=[(side*(x-.011+math.cos(t*2*math.pi/32)*r*.55),z+.010+math.sin(t*2*math.pi/32)*r*.65) for t in range(32)]
            front_patch('lens_'+str(side)+'_'+str(i),glint,white,0,False,.065)
        front_patch('bumper_strip_'+str(side),signed([(.33,.48),(.82,.545),(.81,.47),(.34,.415)]),grille_mat,.26)
        front_patch('lower_corner_'+str(side),signed([(.38,.315),(.79,.36),(.75,.24),(.39,.22)]),grille_mat,.25)
    front_patch('lower_intake',[(-.33,.34),(.33,.34),(.32,.225),(-.32,.225)],grille_mat,.16)
    # Bonnet's two bowed creases turn with the wings, terminating before the windscreen.
    for side in (-1,1):
        xy=[(side*x,y) for x,y in ((.41,-1.73),(.46,-1.55),(.53,-1.30),(.60,-1.04),(.59,-.89),(.54,-.83))]
        path=[]
        controls=[mathutils.Vector(q) for q in xy];smooth=[]
        for j in range(len(controls)-1):
            p0=controls[max(0,j-1)];p1=controls[j];p2=controls[j+1];p3=controls[min(len(controls)-1,j+2)]
            for k in range(12):
                t=k/12
                smooth.append(.5*((2*p1)+(-p0+p2)*t+(2*p0-5*p1+4*p2-p3)*t*t+(-p0+3*p1-3*p2+p3)*t*t*t))
        smooth.append(controls[-1])
        for x,y in smooth:
            hit,loc,normal,index=front_eval.ray_cast(mathutils.Vector((x,y,3)),mathutils.Vector((0,0,-1)))
            assert hit
            path.append(tuple(loc+normal*.012))
        noink(K.sweep('bonnet_crease_'+str(side),path,.009,navy,seg=12))

    # Wheels are slightly proud, with a clean five-hole steel rim.
    for axle, yw in enumerate(wheel_y):
        xw = 0.815
        arch = [(0.920, yw + math.cos(math.pi * k / 30) * 0.455,
                 R + math.sin(math.pi * k / 30) * 0.455) for k in range(31)]
        K._fine_mode = True
        # OWNER: no extra arch tube: tyre/body boundary already carries its ink.
        K._fine_mode = old_fine
        K.cyl("tyre_%d" % axle, xw, yw, R, R, 0.24, navy,
              axis='X', segments=48, smooth=True)
        K.cyl("sidewall_%d" % axle, xw + .13, yw, R, .350, .055,
              body_dark, axis='X', segments=48, smooth=True)
        K.cyl("rim_%d" % axle, xw + .165, yw, R, .255, .030,
              silver, axis='X', segments=48, smooth=True)
        face_x = xw + .185
        bolt_dot(K, "hub_%d" % axle, (face_x, yw, R), 'X', .042, navy)
        for k in range(5):
            angle = 2 * math.pi * k / 5 + math.radians(18)
            bolt_dot(K, "wheel_slot_%d_%d" % (axle, k),
                     (face_x, yw + math.cos(angle) * .165,
                      R + math.sin(angle) * .165), 'X', .050, navy)

    mirror = K.box("mirror", .98, -.48, 1.16, .20, .15, .13, body)
    bevel = mirror.modifiers.new("mirror_round", 'BEVEL')
    bevel.width = .045; bevel.segments = 3
    surface_panel("tail_lamp", [(.865, 2.61, .73), (.835, 2.83, .72),
                                (.822, 2.82, .93), (.854, 2.61, .94)],
                  red, .012, fine=True)

    # Shared can model, with a real raised open handle and offset cap.
    can=build_reference_jerrycan(K,col,origin=(1.95,-1.30,0),yaw_deg=90,D=1.06,prefix='diesel_can')
    bpy.context.view_layer.update()
    return {'objects':len(col.objects),'revision':'owner_front_can_revision_01','can_dimensions':can['dimensions']}


# --------------------------------------------------------- JERRYCAN TOPOLOGY STUDY
def build_reference_jerrycan(K, col, origin=(0, 0, 0), yaw_deg=86.0, D=1.0,
                             prefix="jerry_study"):
    """Build the reference's 20 L can as reusable topology, not assembled boxes.

    Owner/reference rulings: a tall tapered can with chamfered lower corners, a shallow
    rolled front seam, four branching pressed channels, a prominent offset cap, and one
    proud angular handle whose opening sits clear above the body shoulder.  The broad face
    remains dominant but exposes a useful right side plane.  Every dimension is in can width D.
    """
    import bmesh

    # Keep the complete can in the cap's deep burgundy family.  Green is deliberately
    # lower than blue so the lit plane stays red instead of drifting salmon/orange.
    red = toon_mat("tn_diesel_red", (0.34, 0.042, 0.070))
    red_lo = toon_mat("tn_diesel_red_dark", (0.20, 0.014, 0.035))
    navy = K.mat("ic_navy")

    helpers = bpy.data.collections.get("GOODS_ICON_HELPERS_JERRYCAN")
    if helpers is None:
        helpers = bpy.data.collections.new("GOODS_ICON_HELPERS_JERRYCAN")
        bpy.context.scene.collection.children.link(helpers)
    root = bpy.data.objects.new(prefix + "_root", None)
    helpers.objects.link(root)
    root.location = origin
    root.rotation_euler[2] = math.radians(yaw_deg)
    # Screen-space calibration: the reference is substantially taller and narrower than
    # an unscaled ISO box, even though its nominal 20 L proportions are conventional.
    root.scale = (.88 * D, D, 1.06 * D)

    made = []

    def keep(ob):
        ob.parent = root
        made.append(ob)
        return ob

    def as_cutter(ob):
        """Move a modelled solid out of the render collection for Boolean subtraction."""
        if ob in made:
            made.remove(ob)
        if ob.name in col.objects:
            col.objects.unlink(ob)
        if ob.name not in helpers.objects:
            helpers.objects.link(ob)
        ob.hide_render = True
        ob.display_type = 'WIRE'
        return ob

    def no_ink(ob):
        """Let a recessed floor read as fill, without a second outline inside its rim."""
        attr = ob.data.attributes.get("freestyle_face") or ob.data.attributes.new(
            "freestyle_face", 'BOOLEAN', 'FACE')
        for datum in attr.data:
            datum.value = True
        return ob

    def no_ink_below(ob, z_limit):
        """Suppress only buried/root faces while preserving the readable upper cage."""
        attr = ob.data.attributes.get("freestyle_face") or ob.data.attributes.new(
            "freestyle_face", 'BOOLEAN', 'FACE')
        for poly, datum in zip(ob.data.polygons, attr.data):
            datum.value = max(ob.data.vertices[index].co.z
                              for index in poly.vertices) <= z_limit
        return ob

    def loft(name, sections, mat, smooth=False):
        me = bpy.data.meshes.new(prefix + "_" + name)
        bm = bmesh.new()
        rings = []
        for y, profile in sections:
            rings.append([bm.verts.new((x, y, z)) for x, z in profile])
        count = len(rings[0])
        bm.faces.new(list(reversed(rings[0])))
        bm.faces.new(rings[-1])
        for first, second in zip(rings, rings[1:]):
            for i in range(count):
                j = (i + 1) % count
                bm.faces.new((first[i], first[j], second[j], second[i]))
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        bm.to_mesh(me); bm.free()
        return keep(K.obj(prefix + "_" + name, me, mat, smooth=smooth))

    def ring(name, outer, inner, y0, y1, mat):
        """Closed front/back annular mesh with a real aperture."""
        me = bpy.data.meshes.new(prefix + "_" + name)
        bm = bmesh.new()
        o0 = [bm.verts.new((x, y0, z)) for x, z in outer]
        o1 = [bm.verts.new((x, y1, z)) for x, z in outer]
        i0 = [bm.verts.new((x, y0, z)) for x, z in inner]
        i1 = [bm.verts.new((x, y1, z)) for x, z in inner]
        count = len(outer)
        for k in range(count):
            j = (k + 1) % count
            bm.faces.new((o0[k], o0[j], o1[j], o1[k]))
            bm.faces.new((i0[j], i0[k], i1[k], i1[j]))
            bm.faces.new((o0[j], o0[k], i0[k], i0[j]))
            bm.faces.new((o1[k], o1[j], i1[j], i1[k]))
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        bm.to_mesh(me); bm.free()
        return keep(K.obj(prefix + "_" + name, me, mat, smooth=False))

    def ribbon(name, points, width, y0, y1, mat, bevel_width=.006):
        """Constant-width pressed strip in the X/Z face plane, with mitred elbows."""
        pts = [mathutils.Vector((x, z)) for x, z in points]
        half = width / 2.0
        seg_normals = []
        for a, b in zip(pts, pts[1:]):
            direction = (b - a).normalized()
            seg_normals.append(mathutils.Vector((-direction.y, direction.x)))
        offsets = []
        for i in range(len(pts)):
            if i == 0:
                offsets.append(seg_normals[0] * half)
            elif i == len(pts) - 1:
                offsets.append(seg_normals[-1] * half)
            else:
                miter = (seg_normals[i - 1] + seg_normals[i]).normalized()
                denom = max(.35, abs(miter.dot(seg_normals[i])))
                offsets.append(miter * (half / denom))
        polygon = [p + off for p, off in zip(pts, offsets)]
        polygon += [p - off for p, off in reversed(list(zip(pts, offsets)))]

        me = bpy.data.meshes.new(prefix + "_" + name)
        bm = bmesh.new()
        front = [bm.verts.new((p.x, y0, p.y)) for p in polygon]
        back = [bm.verts.new((p.x, y1, p.y)) for p in polygon]
        bm.faces.new(front)
        bm.faces.new(list(reversed(back)))
        count = len(polygon)
        for i in range(count):
            j = (i + 1) % count
            bm.faces.new((front[i], front[j], back[j], back[i]))
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        bm.to_mesh(me); bm.free()
        ob = keep(K.obj(prefix + "_" + name, me, mat, smooth=False))
        if bevel_width > 0:
            bevel = ob.modifiers.new("pressed_edge_round", 'BEVEL')
            bevel.width = bevel_width
            bevel.segments = 3
        return ob

    def oriented_cyl(name, centre, radius, depth, mat, normal, segments=48):
        """Cylinder whose axis follows the mounting-face normal instead of global Z."""
        me = bpy.data.meshes.new(prefix + "_" + name)
        bm = bmesh.new()
        bmesh.ops.create_cone(bm, cap_ends=True, segments=segments,
                              radius1=radius, radius2=radius, depth=depth)
        axis = mathutils.Vector(normal).normalized()
        rotation = axis.to_track_quat('Z', 'Y').to_matrix()
        bmesh.ops.rotate(bm, cent=(0, 0, 0), matrix=rotation, verts=bm.verts)
        bmesh.ops.translate(bm, vec=mathutils.Vector(centre), verts=bm.verts)
        bm.to_mesh(me); bm.free()
        return keep(K.obj(prefix + "_" + name, me, mat, smooth=True))

    def planar_shape(name, polygon, origin, u_axis, v_axis, normal,
                     w0, w1, mat, inner=None):
        """Extrude a polygon or annulus in an arbitrary tangent plane."""
        me = bpy.data.meshes.new(prefix + "_" + name)
        bm = bmesh.new()
        O = mathutils.Vector(origin)
        U = mathutils.Vector(u_axis).normalized()
        V = mathutils.Vector(v_axis).normalized()
        N = mathutils.Vector(normal).normalized()

        def point(uv, w):
            return O + U * uv[0] + V * uv[1] + N * w

        o0 = [bm.verts.new(point(uv, w0)) for uv in polygon]
        o1 = [bm.verts.new(point(uv, w1)) for uv in polygon]
        count = len(polygon)
        if inner is None:
            bm.faces.new(list(reversed(o0)))
            bm.faces.new(o1)
            for i in range(count):
                j = (i + 1) % count
                bm.faces.new((o0[i], o0[j], o1[j], o1[i]))
        else:
            i0 = [bm.verts.new(point(uv, w0)) for uv in inner]
            i1 = [bm.verts.new(point(uv, w1)) for uv in inner]
            for i in range(count):
                j = (i + 1) % count
                bm.faces.new((o0[i], o0[j], o1[j], o1[i]))
                bm.faces.new((i0[j], i0[i], i1[i], i1[j]))
                bm.faces.new((o0[j], o0[i], i0[i], i0[j]))
                bm.faces.new((o1[i], o1[j], i1[j], i1[i]))
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        bm.to_mesh(me); bm.free()
        return keep(K.obj(prefix + "_" + name, me, mat, smooth=False))

    def rounded_body_cage(name, sections, mat, sides=32, exponent=8.0):
        """Unified subdivision cage made from rounded-rectangle XY rings.

        Dense support rings hold the tank walls while the upper rings shrink and shift to
        form the stamped shoulders and central handle deck of a real steel jerry can.
        """
        me = bpy.data.meshes.new(prefix + "_" + name)
        bm = bmesh.new()
        rings = []
        power = 2.0 / exponent
        for z, cx, half_x, half_y in sections:
            ring_verts = []
            for i in range(sides):
                angle = 2.0 * math.pi * i / sides
                ca, sa = math.cos(angle), math.sin(angle)
                x = cx + half_x * math.copysign(abs(ca) ** power, ca)
                y = half_y * math.copysign(abs(sa) ** power, sa)
                ring_verts.append(bm.verts.new((x, y, z)))
            rings.append(ring_verts)
        bm.faces.new(list(reversed(rings[0])))
        bm.faces.new(rings[-1])
        for lower, upper in zip(rings, rings[1:]):
            for i in range(sides):
                j = (i + 1) % sides
                bm.faces.new((lower[i], lower[j], upper[j], upper[i]))
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        bm.to_mesh(me); bm.free()
        body_ob = keep(K.obj(prefix + "_" + name, me, mat, smooth=True))
        for poly in body_ob.data.polygons: poly.use_smooth = True
        subd = body_ob.modifiers.new("rounded_tank_cage", 'SUBSURF')
        subd.subdivision_type = 'CATMULL_CLARK'
        subd.levels = 1
        subd.render_levels = 1
        return body_ob

    # OWNER: rising rear corner and one planar cap shoulder; there is no separate pad.
    depth=.370
    # New owner profile: cap shoulder about22deg; a low deck under a nearly
    # level bridge, then a curved rising rear shoulder that merges with the bridge.
    profile=[(-.40,.055),(.40,.055),(.455,.115),(.455,1.160),
             (.450,1.196),(.432,1.230),(.404,1.254),(.372,1.270),
             (.337,1.270),(.302,1.256),(.270,1.230),(.237,1.194),
             (.199,1.163),(.155,1.138),(.100,1.117),(.035,1.105),
             (-.100,1.100),(-.190,1.105),(-.420,1.026),
             (-.445,.980),(-.455,.940),(-.455,.12)]
    body=loft('body',[(-depth/2,profile),(depth/2,profile)],red,smooth=False)
    bevel=body.modifiers.new('pressed_corner_rounding','BEVEL')
    bevel.width=.022;bevel.segments=4
    bevel.affect='EDGES'
    no_ink(body)

    fine_before = K._fine_mode
    K._fine_mode = True

    # The front perimeter is carried by the unified cage and its tonal face break.  An
    # extra swept roll was redundant at icon scale and left visible end-caps near the top.
    front_y = -depth / 2 - .025

    # Reference-like pressed topology: four constant-width channels Boolean-cut into the
    # broad face.  Their floors are real recessed faces, never strips laid on top.
    cut_front = -depth / 2 - .035
    # Sheet-metal pressings are shallow.  A deep trench shows a large lit wall and reads
    # like piping laid on top, even when it is technically a Boolean subtraction.
    cut_back = -depth / 2 + .014
    branch_paths = [
        [(-.300, .855), (-.150, .675)],
        [(.300, .875), (.150, .675)],
        [(-.290, .235), (-.150, .440)],
        [(.295, .255), (.150, .440)],
    ]
    for i, path in enumerate(branch_paths):
        cutter = ribbon("press_cutter_%d" % i, path, .052,
                        cut_front, cut_back, navy, bevel_width=.002)
        as_cutter(cutter)
        boolean = body.modifiers.new("recess_branch_%d" % i, 'BOOLEAN')
        boolean.operation = 'DIFFERENCE'
        boolean.solver = 'EXACT'
        boolean.object = cutter
        # A dark floor is placed at the back of the Boolean channel.  It does not sit on
        # the body surface: the visible step down to this plane is what makes the mark
        # unambiguously pressed inward at icon scale.
        floor = ribbon("press_floor_%d" % i, path, .046,
                       cut_back - .0015, cut_back + .002, red_lo, bevel_width=0)
        no_ink(floor)
    # A recessed central ring closes the four branches around a small untouched field.
    centre_outer = [(-.160, .415), (.160, .415), (.160, .700), (-.160, .700)]
    centre_inner = [(-.080, .495), (.080, .495), (.080, .620), (-.080, .620)]
    centre_cutter = ring("press_centre_cutter", centre_outer, centre_inner,
                         cut_front, cut_back, navy)
    as_cutter(centre_cutter)
    centre_bool = body.modifiers.new("recess_centre", 'BOOLEAN')
    centre_bool.operation = 'DIFFERENCE'
    centre_bool.solver = 'EXACT'
    centre_bool.object = centre_cutter
    floor_outer = [(-.151, .424), (.151, .424), (.151, .691), (-.151, .691)]
    floor_inner = [(-.089, .486), (.089, .486), (.089, .629), (-.089, .629)]
    centre_floor = ring("press_centre_floor", floor_outer, floor_inner,
                        cut_back - .0015, cut_back + .002, red_lo)
    no_ink(centre_floor)

    # Raised open bridge, longitudinal on the can's broad face. Two parallel plates
    # form one handle assembly; the space beneath is real empty geometry.
    handle_outer=[(-.180,1.075),(-.165,1.125),(-.105,1.275),(.340,1.275),(.395,1.240),(.380,1.170)]
    handle_inner=[(-.110,1.090),(-.100,1.130),(-.065,1.225),(.250,1.225),(.290,1.205),(.280,1.160)]
    def soften_handle(path):
        result=[path[0]]
        for i in range(1,len(path)-1):
            p=mathutils.Vector(path[i]);a=p.lerp(mathutils.Vector(path[i-1]),.12);b=p.lerp(mathutils.Vector(path[i+1]),.12)
            for j in range(7):
                t=j/6;result.append(tuple((1-t)**2*a+2*t*(1-t)*p+t*t*b))
        return result+[path[-1]]
    handle_outer=soften_handle(handle_outer);handle_inner=soften_handle(handle_inner)
    for i,yy in enumerate((-.105,.085)):
        handle=planar_shape('handle_bridge_%d'%i,handle_outer+list(reversed(handle_inner)),
                            (0,yy,0),(1,0,0),(0,0,1),(0,1,0),-.027,.027,red)
        no_ink(handle)
        recess=planar_shape('handle_recess_%d'%i,handle_inner,(0,yy,0),
                           (1,0,0),(0,0,1),(0,1,0),-.006,.006,navy)
        no_ink(recess)
        # Explicit strokes stay smooth at the roots; Freestyle intersections serrated here.
        for label,path in [('outer',handle_outer),('inner',handle_inner)]:
            coords=[(x,yy-.030,z) for x,z in path]
            line=keep(K.sweep(prefix+'_bridge_'+label+'_'+str(i),coords,.006,navy,seg=12))
            no_ink(line)
    K._fine_mode = fine_before

    # Normal is derived from the shell's actual sloped corner, not independently chosen.
    shoulder_a=mathutils.Vector((-.420,0,1.026))
    shoulder_b=mathutils.Vector((-.190,0,1.105))
    tangent=(shoulder_b-shoulder_a).normalized()
    cap_axis=mathutils.Vector((-tangent.z,0,tangent.x))
    cap_base=shoulder_a.lerp(shoulder_b,.5)
    no_ink(oriented_cyl('neck',cap_base+cap_axis*.020,.105,.060,red_lo,cap_axis))
    oriented_cyl('cap',cap_base+cap_axis*.065,.096,.050,red,cap_axis)

    return {"root": root, "objects": made,
            "dimensions": {"width": .8008 * D, "depth": depth * D,
                           "body_height": (1.270-.055)*1.06*D, "total_height": (1.275-.055)*1.06*D, "cap_shoulder_degrees": math.degrees(math.atan2(.079*1.06,.230*.88))}}


def build_jerrycan_study():
    """Standalone owner-review render for the diesel icon's 20 L can topology."""
    setup_icon_rig()
    col = open_collection("ICON_jerrycan_study")
    K = Kit(col)
    result = build_reference_jerrycan(K, col, origin=(0, 0, 0), yaw_deg=86.0, D=1.0)
    print("\n".join(K.validate(ground=0.0)))
    return {"objects": len(col.objects), "topology": "reference_jerrycan_cage_v12",
            "dimensions": result["dimensions"]}
