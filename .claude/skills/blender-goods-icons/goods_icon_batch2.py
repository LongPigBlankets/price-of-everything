"""Goods icons, batch 2 (2026-09-07): phosphate, methane, light oil, heavy oil, lubricants,
durable alloys, conductive alloys, propane. Owner briefs are quoted in each docstring.

Run AFTER sprite_kit.py and goods_icon_kit.py in the same namespace. Everything obeys the
fixed-iso contract (rules 66-71): one camera, world axes as the grid, 90-degree objects built
with K.box, whole-assembly rotations only in 90-degree steps. Lathed bodies are revolved about
Z (upright) or revolved about Z and then turned 90 degrees about X to lie along Y (horizontal
vessels) - the same world diagonal every other good uses.
"""
import bpy, math, mathutils
from mathutils import Vector

# ---------------------------------------------------------------- shared helpers

def mesh_obj(K, name, verts, faces, mat, smooth=True):
    me = bpy.data.meshes.new(name)
    me.from_pydata([tuple(v) for v in verts], [], [tuple(f) for f in faces])
    me.update()
    ob = K.obj(name, me, mat, smooth=smooth)
    for p in ob.data.polygons:
        p.use_smooth = smooth
    return ob


def lathe(K, name, centre, profile, mat, segments=32, levels=2, smooth=True, cap_top=True, cap_bottom=True):
    """Quad cage revolved about Z (profile = [(z, r), ...] bottom to top) under a Subdivision
    Surface, so the silhouette is a smooth bottle/tin/can outline while the cage stays editable.
    Set levels=0 for a hard-edged revolve (rims, rings)."""
    x, y, z = centre
    verts = [(x + r * math.cos(2 * math.pi * i / segments), y + r * math.sin(2 * math.pi * i / segments), z + h)
             for h, r in profile for i in range(segments)]
    faces = []
    if cap_bottom:
        faces.append(tuple(reversed(range(segments))))
    for j in range(len(profile) - 1):
        for i in range(segments):
            a = j * segments + i; b = j * segments + (i + 1) % segments
            faces.append((a, b, b + segments, a + segments))
    if cap_top:
        faces.append(tuple(range((len(profile) - 1) * segments, len(profile) * segments)))
    ob = mesh_obj(K, name, verts, faces, mat, smooth=smooth)
    if levels > 0:
        sd = ob.modifiers.new("cage", 'SUBSURF')
        sd.levels = levels; sd.render_levels = levels
    return ob


def text_face(K, name, text, centre, size, mat, normal, up=None):
    """Flat text lying on a face: converted to mesh, un-inked (the export outlines it if it is
    dark on light). `normal` is the face normal; `up` the text's up direction on that face."""
    cu = bpy.data.curves.new(name, 'FONT'); cu.body = text
    cu.align_x = 'CENTER'; cu.align_y = 'CENTER'; cu.size = size
    ob = bpy.data.objects.new(name, cu); K.col.objects.link(ob)
    n = Vector(normal).normalized()
    u = Vector(up) if up is not None else (Vector((0, 1, 0)) if abs(n.z) > 0.99 else Vector((0, 0, 1)))
    right = u.cross(n).normalized(); u = n.cross(right).normalized()
    ob.rotation_euler = mathutils.Matrix((right, u, n)).transposed().to_euler()
    ob.location = Vector(centre) + n * 0.006
    cu.materials.append(mat)
    bpy.context.view_layer.objects.active = ob; ob.select_set(True)
    bpy.ops.object.convert(target='MESH'); ob.select_set(False)
    noink(ob)
    return ob


def helix_path(centre_a, centre_b, radius, turns, phase, n=64):
    a, b = Vector(centre_a), Vector(centre_b)
    axis = (b - a); L = axis.length; t = axis.normalized()
    ref = Vector((0, 0, 1)) if abs(t.z) < 0.9 else Vector((1, 0, 0))
    u = t.cross(ref).normalized(); v = t.cross(u).normalized()
    pts = []
    for i in range(n + 1):
        s = i / n
        ang = phase + 2 * math.pi * turns * s
        pts.append(a + t * (L * s) + u * (radius * math.cos(ang)) + v * (radius * math.sin(ang)))
    return pts


def smooth_path(pts, per_seg=8):
    """Catmull-Rom resample of a coarse centreline: a swept tube then has no kinks, so its
    silhouette inks continuously instead of flickering into stripes at the bends."""
    P = [Vector(p) for p in pts]
    if len(P) < 3:
        return P
    out = []
    for i in range(len(P) - 1):
        p0 = P[max(i - 1, 0)]; p1 = P[i]; p2 = P[i + 1]; p3 = P[min(i + 2, len(P) - 1)]
        for k in range(per_seg):
            t = k / per_seg
            out.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t + (-p0 + 3 * p1 - 3 * p2 + p3) * t * t * t))
    out.append(P[-1])
    return out


def torus(K, name, centre, R, r, mat, seg_major=48, seg_minor=16, axis='Z'):
    pts = []
    cx, cy, cz = centre
    for i in range(seg_major + 1):
        ang = 2 * math.pi * (i % seg_major) / seg_major
        if axis == 'Z':
            pts.append(Vector((cx + R * math.cos(ang), cy + R * math.sin(ang), cz)))
        elif axis == 'Y':
            pts.append(Vector((cx + R * math.cos(ang), cy, cz + R * math.sin(ang))))
        else:
            pts.append(Vector((cx, cy + R * math.cos(ang), cz + R * math.sin(ang))))
    return sweep_tube(K, name, pts, r, mat, seg=seg_minor)


# ---------------------------------------------------------------- palette (toon bases)
# FIVE steps (review 2026-09-07 vs the approved alternates): deep 0.45 / core 0.59 / base 0.79 /
# lit 1.0 / RIM 1.26, on thresholds of the shading factor s = world + sun*cos/pi (0.58..1.09).
# ~20 luma apart at a lit face of ~200, with headroom above the base for a specular stripe
# that only the faces turned almost exactly to the sun receive.
# Thresholds are set so a VERTICAL cylinder spans all five: its best-facing normal only reaches
# s = 0.93 (cos 0.69 to the sun), so the rim step starts at 0.91 - a stripe ~25-30% in from the
# lit edge on uprights (the approved oxygen cylinder's specular), and every top face.
STEPS5 = ((0.62, 0.45), (0.72, 0.59), (0.84, 0.79), (0.91, 1.00), (9.0, 1.26))


def toon5_mat(name, colour):
    m = bpy.data.materials.get(name)
    if m is None:
        m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree; nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial"); emis = nt.nodes.new("ShaderNodeEmission")
    diff = nt.nodes.new("ShaderNodeBsdfDiffuse"); diff.inputs["Color"].default_value = (1, 1, 1, 1)
    s2r = nt.nodes.new("ShaderNodeShaderToRGB"); ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.interpolation = 'CONSTANT'
    els = ramp.color_ramp.elements
    els[0].position = 0.0; els[0].color = (STEPS5[0][1],) * 3 + (1,)
    els[1].position = STEPS5[0][0]; els[1].color = (STEPS5[1][1],) * 3 + (1,)
    for k in range(2, len(STEPS5)):
        e = els.new(STEPS5[k - 1][0]); e.color = (STEPS5[k][1],) * 3 + (1,)
    mix = nt.nodes.new("ShaderNodeMix"); mix.data_type = 'RGBA'; mix.blend_type = 'MULTIPLY'
    mix.inputs["Factor"].default_value = 1.0; mix.inputs[6].default_value = (*colour, 1.0)
    nt.links.new(diff.outputs[0], s2r.inputs[0]); nt.links.new(s2r.outputs["Color"], ramp.inputs["Fac"])
    nt.links.new(ramp.outputs["Color"], mix.inputs[7]); nt.links.new(mix.outputs[2], emis.inputs["Color"])
    emis.inputs["Strength"].default_value = 1.0; nt.links.new(emis.outputs[0], out.inputs[0])
    return m


def P(name, rgb):
    return toon5_mat("tn5_" + name, rgb)


def setup_batch_rig():
    """The icon rig, then the reviewed line hierarchy: interior 7.5 px at 1024 (~6 px at 800),
    fine 3.4 px for seams and bolts; the export draws the outer contour at 0.009 (~12 px)."""
    setup_icon_rig()
    fs = bpy.context.scene.view_layers[0].freestyle_settings
    fs.linesets["ink"].linestyle.thickness = 7.5
    fs.linesets["ink_fine"].linestyle.thickness = 3.4
    if "ink_edge" in fs.linesets:
        fs.linesets["ink_edge"].linestyle.thickness = 3.4

# ---------------------------------------------------------------- PHOSPHATE
def build_phosphate():
    """OWNER: an open sack beside a small cluster of rounded mineral nodules. Dusty buff, warm
    grey and muted ochre; rounded granular forms distinguish it from jagged ores.
    Round two: a ROLLED CUFF and vertical creases so it reads as cloth, not a jar; fewer,
    larger grains; calmer nodules (the noise ticks read as stray lines)."""
    setup_batch_rig()
    col = open_collection("ICON_phosphate")
    K = Kit(col)
    buff = P("buff", (0.60, 0.46, 0.26)); buff_lo = P("buff_lo", (0.44, 0.35, 0.22))
    grey = P("warm_grey", (0.50, 0.45, 0.36)); ochre = P("ochre", (0.60, 0.42, 0.14))
    navy = K.mat("ic_navy")
    cx, cy = -0.35, 0.25
    prof = [(0.00, 0.60), (0.06, 0.80), (0.45, 0.86), (0.95, 0.84), (1.25, 0.76), (1.40, 0.68), (1.50, 0.66)]
    lathe(K, "sack", (cx, cy, 0.0), prof, buff, levels=2)
    # rolled cuff: a fat torus-like roll at the mouth, sitting outside the neck
    # the cuff: the cloth folded outward and down over itself, one soft revolved fold
    lathe(K, "cuff", (cx, cy, 1.44), [(0.00, 0.62), (0.06, 0.78), (0.16, 0.86), (0.26, 0.82), (0.32, 0.70), (0.34, 0.60)], buff_lo, levels=2, cap_top=False, cap_bottom=False)
    # two vertical creases on the visible flank (front-right), thin navy ribs sunk into the cloth
    for i, ang in enumerate((-35.0, -75.0)):
        th = math.radians(ang)
        rr = 0.86
        K.rotbox("crease%d" % i, cx + rr * math.cos(th), cy + rr * math.sin(th), 0.62, 0.02, 0.06, 0.70, navy, 'Z', ang + 90)
    import random
    rng = random.Random(7)
    for i in range(11):
        a = rng.uniform(0, 2 * math.pi); rr = 0.40 * math.sqrt(rng.random())
        r = rng.uniform(0.16, 0.24)
        m = (buff, ochre, grey)[i % 3]
        blob(K, "grain%d" % i, (cx + rr * math.cos(a), cy + rr * math.sin(a), 1.50 + r * 0.55), r, 100 + i, (1.0, 1.0, 0.80), m, noise_amp=0.06)
    nods = [((0.95, -0.35), 0.42, buff), ((1.35, 0.15), 0.36, ochre), ((0.55, -0.85), 0.30, grey),
            ((1.30, -0.70), 0.27, buff), ((0.90, 0.30), 0.24, grey)]
    for i, ((x, y), r, m) in enumerate(nods):
        blob(K, "nodule%d" % i, (x, y, r * 0.8), r, 300 + i, (1.0, 0.95, 0.82), m, noise_amp=0.07)
    return {"objects": len(col.objects)}


# ---------------------------------------------------------------- METHANE
def wrap_text_on_cylinder(K, name, text, size, r, axis_len_pos, mat, angle_deg=0.0, bold=0.012):
    """Text lying ON a cylinder of radius r whose axis is local Z: built flat facing +X,
    reading along the axis, then every vertex is wrapped around the barrel. Un-inked; the
    cream band behind it makes it read. Returns the mesh object in LOCAL coordinates - apply
    the tank's rotation and location to it afterwards."""
    cu = bpy.data.curves.new(name, 'FONT'); cu.body = text
    cu.align_x = 'CENTER'; cu.align_y = 'CENTER'; cu.size = size
    cu.offset = bold                      # emboldened like the alumina label
    ob = bpy.data.objects.new(name, cu); K.col.objects.link(ob)
    # plane facing +X, text up = +Y (world +Z after the tank's 90-degree X rotation),
    # reading toward -Z local (= world +Y, lower-left to upper-right on screen)
    n = Vector((1, 0, 0)); u = Vector((0, 1, 0)); right = u.cross(n).normalized(); u = n.cross(right).normalized()
    ob.rotation_euler = mathutils.Matrix((right, u, n)).transposed().to_euler()
    cu.materials.append(mat)
    bpy.context.view_layer.objects.active = ob; ob.select_set(True)
    bpy.ops.object.convert(target='MESH'); ob.select_set(False)
    import bmesh
    bm = bmesh.new(); bm.from_mesh(ob.data)
    bmesh.ops.triangulate(bm, faces=list(bm.faces))
    bmesh.ops.subdivide_edges(bm, edges=list(bm.edges), cuts=2, use_grid_fill=True)
    bm.to_mesh(ob.data); bm.free()
    a0 = math.radians(angle_deg)
    M = ob.matrix_world.copy()
    for v in ob.data.vertices:
        w = M @ v.co                      # flat glyph point in local tank space
        ang = a0 + w.y / r                # wrap the across-text coordinate around the barrel
        v.co = Vector((r * math.cos(ang), r * math.sin(ang), axis_len_pos + w.z))
    ob.rotation_euler = (0, 0, 0); ob.location = (0, 0, 0)
    noink(ob)
    return ob


def build_methane():
    """OWNER (photo + round nine, 2026-09-07): an ISO tank-container FRAME around EACH tank whose
    end frames run mid-side to mid-side (a diamond/octagon around the dished end, not corner
    diagonals); tanks WHITE and filling the frame; ONLY a WHITE band wrapped around the
    diameter as the label, with CH4 in navy in an emboldened face like the alumina label.
    The red frame is the icon's warm accent. Valve stack + gauge at the front end kept."""
    setup_batch_rig()
    col = open_collection("ICON_methane")
    K = Kit(col)
    white = P("vessel_white", (0.82, 0.82, 0.80)); band_w = P("band_white", (0.90, 0.90, 0.88))
    frame = P("frame_red", (0.56, 0.11, 0.08)); frame_lo = P("frame_red_lo", (0.40, 0.08, 0.06))
    steel = P("cradle_steel", (0.22, 0.28, 0.40)); valve = P("valve", (0.30, 0.36, 0.48)); dial = P("dial", (0.86, 0.84, 0.74))
    navy = K.mat("ic_navy")
    R, L = 0.52, 2.30
    beam = 0.09
    fx, fz = R + 0.07, 2 * R + 0.16          # the tank fills the frame
    pitch = 2 * fx + beam + 0.03
    xs = (-pitch / 2, pitch / 2)
    zc = fz / 2
    y0, y1 = -L / 2 - 0.10, L / 2 + 0.10
    for i, x in enumerate(xs):
        # ---- tank
        K.cyl("barrel%d" % i, x, 0.0, zc, R, L - 0.30, white, axis='Y', segments=48, smooth=True)
        for sg, nm in ((-1, "front"), (1, "back")):
            end = lathe(K, "end_%s%d" % (nm, i), (0, 0, 0), [(0.0, 0.0), (0.02, 0.28), (0.10, 0.42), (0.16, R - 0.01)], white, levels=1, cap_top=False)
            end.rotation_euler = (math.radians(90 if sg < 0 else -90), 0, 0)
            end.location = (x, sg * (L / 2 - 0.15), zc)
            K.washer("rim_%s%d" % (nm, i), (x, sg * (L / 2 - 0.15), zc), (0.0, 1.0, 0.0), R - 0.02, R + 0.02, 0.05, steel, seg=48)
        for j, y in enumerate((-L / 3, L / 3)):
            K.washer("seam%d%d" % (i, j), (x, y, zc), (0.0, 1.0, 0.0), R - 0.01, R + 0.010, 0.03, navy, seg=48)
        # ---- white wraparound band + navy CH4 on the lit crown (the top rail covers 35-55 deg)
        K.cyl("band%d" % i, x, 0.0, zc, R + 0.010, 0.76, band_w, axis='Y', segments=48, smooth=True)
        for sg in (-1, 1):
            K.washer("band_edge%d%d" % (i, sg > 0), (x, sg * 0.38, zc), (0.0, 1.0, 0.0), R + 0.004, R + 0.018, 0.02, navy, seg=48)
        ch = wrap_text_on_cylinder(K, "ch%d" % i, "CH", 0.40, R + 0.03, 0.0, navy, angle_deg=82)
        four = wrap_text_on_cylinder(K, "four%d" % i, "4", 0.24, R + 0.03, 0.0, navy, angle_deg=66)
        for ob in (ch, four):
            ob.rotation_euler = (math.radians(90), 0, 0)
        ch.location = (x, -0.10, zc); four.location = (x, 0.30, zc)
        # ---- valve stack + gauge on the front end
        yf = -L / 2 - 0.02
        K.cyl("neck%d" % i, x, yf - 0.05, zc, 0.11, 0.16, valve, axis='Y', segments=20, smooth=True)
        K.cyl("wheel%d" % i, x, yf - 0.17, zc, 0.16, 0.05, navy, axis='Y', segments=20, smooth=True)
        K.cyl("outlet%d" % i, x + 0.14, yf - 0.06, zc, 0.045, 0.18, valve, axis='X', segments=12, smooth=True)
        K.cyl("gauge_stem%d" % i, x, yf - 0.06, zc + 0.16, 0.03, 0.14, valve, axis='Z', segments=10, smooth=True)
        K.cyl("gauge%d" % i, x, yf - 0.10, zc + 0.30, 0.10, 0.06, valve, axis='Y', segments=20, smooth=True)
        K.cyl("gauge_face%d" % i, x, yf - 0.135, zc + 0.30, 0.075, 0.01, dial, axis='Y', segments=20, smooth=True)
        # ---- ISO frame: long rails, posts, cross rails, castings, and MID-SIDE braces (a diamond
        #      around each end, the way the photo's octagon meets the tank)
        for cx in (x - fx, x + fx):
            for cz in (beam / 2, fz - beam / 2):
                K.box("rail_%.2f_%.2f" % (cx, cz), cx, 0.0, cz, beam, y1 - y0, beam, frame)
            for cy in (y0, y1):
                K.box("post_%.2f_%.2f" % (cx, cy), cx, cy, fz / 2, beam, beam, fz, frame)
        for cy in (y0, y1):
            for cz in (beam / 2, fz - beam / 2):
                K.box("cross_%.2f_%.2f" % (cy, cz), x, cy, cz, 2 * fx, beam, beam, frame)
            mids = [Vector((x, cy, fz - beam / 2)), Vector((x + fx, cy, fz / 2)), Vector((x, cy, beam / 2)), Vector((x - fx, cy, fz / 2))]
            for k in range(4):
                K.dirbox("brace_%.2f_%d" % (cy, k), mids[k], mids[(k + 1) % 4], beam * 0.8, beam * 0.8, frame)
        for cx in (x - fx, x + fx):
            for cy in (y0, y1):
                for cz in (beam / 2, fz - beam / 2):
                    K.box("casting_%.2f_%.2f_%.2f" % (cx, cy, cz), cx, cy, cz, 0.15, 0.15, 0.15, frame_lo)
    return {"objects": len(col.objects)}


# ---------------------------------------------------------------- LIGHT OIL
def build_light_oil():
    """OWNER: a tall refinery sample bottle with a broad shoulder and short neck. Pale
    straw/amber contents, large light field and a restrained dark cap."""
    setup_batch_rig()
    col = open_collection("ICON_light_oil")
    K = Kit(col)
    straw = P("straw", (0.82, 0.64, 0.24)); cap = P("cap_dark", (0.07, 0.09, 0.16))
    glass_rim = P("bottle_rim", (0.86, 0.82, 0.62))
    prof = [(0.00, 0.50), (0.04, 0.62), (0.30, 0.66), (1.45, 0.66), (1.70, 0.60), (1.86, 0.40), (1.98, 0.26), (2.10, 0.24)]
    lathe(K, "bottle", (0, 0, 0), prof, straw, levels=2, cap_top=False)
    # a clear head-space band above the liquid, then the cap
    lathe(K, "headspace", (0, 0, 2.06), [(0.0, 0.24), (0.14, 0.24)], glass_rim, levels=0, cap_bottom=False, cap_top=False)
    K.cyl("cap", 0, 0, 2.36, 0.29, 0.30, cap, axis='Z', segments=32, smooth=True)
    K.cyl("cap_seam", 0, 0, 2.21, 0.27, 0.03, K.mat("ic_navy"), axis='Z', segments=32, smooth=True)
    return {"objects": len(col.objects)}


# ---------------------------------------------------------------- HEAVY OIL
def build_heavy_oil():
    """OWNER: a squat, wide-necked sample tin with a dark viscous ribbon crossing its rim.
    Deep brown, umber and near-navy; a thick rounded fold communicates viscosity.
    Round two: ribbon is a smooth resampled tube and KEEPS its ink (its outline is what sells
    the fold); one rim; tin lifted in value against a near-navy fill with a lighter meniscus."""
    setup_batch_rig()
    col = open_collection("ICON_heavy_oil")
    K = Kit(col)
    tin = P("tin_umber", (0.46, 0.26, 0.10)); oil = P("oil_dark", (0.07, 0.035, 0.02)); rim = P("tin_rim", (0.52, 0.34, 0.16))
    meniscus = P("oil_sheen", (0.20, 0.10, 0.05))
    prof = [(0.00, 0.70), (0.03, 0.88), (0.62, 0.90), (0.70, 0.82), (0.74, 0.74)]
    lathe(K, "tin", (0, 0, 0), prof, tin, levels=2, cap_top=False)
    K.washer("rim", (0.0, 0.0, 0.76), (0.0, 0.0, 1.0), 0.66, 0.84, 0.10, rim, seg=40)
    K.cyl("surface", 0, 0, 0.66, 0.68, 0.04, oil, axis='Z', segments=40, smooth=True)
    K.cyl("meniscus", 0.10, 0.30, 0.69, 0.20, 0.02, meniscus, axis='Z', segments=24, smooth=True)
    path = smooth_path([(-0.05, -0.10, 0.62), (0.05, -0.40, 0.86), (0.12, -0.70, 0.98), (0.19, -0.92, 0.84),
                        (0.23, -1.00, 0.56), (0.23, -0.98, 0.30), (0.21, -0.94, 0.08)], per_seg=8)
    sweep_tube(K, "ribbon", path, 0.15, oil, seg=20)
    return {"objects": len(col.objects)}


# ---------------------------------------------------------------- LUBRICANTS
def build_lubricants():
    """OWNER: a traditional metal oil can with a long angled spout and one large hanging drop.
    Muted mustard or red-ochre body; pale metal spout and dark amber drop.
    Round two: bell-shaped body on a foot ring, the drop's apex ON the nozzle, navy seams at
    the spout root and the base."""
    setup_batch_rig()
    col = open_collection("ICON_lubricants")
    K = Kit(col)
    body = P("mustard", (0.60, 0.38, 0.06)); metal = P("pale_metal", (0.52, 0.58, 0.70)); amber = P("amber_dark", (0.36, 0.16, 0.03))
    navy = K.mat("ic_navy")
    K.cyl("foot", 0, 0, 0.05, 0.62, 0.10, metal, axis='Z', segments=32, smooth=True)
    K.cyl("foot_seam", 0, 0, 0.115, 0.64, 0.025, navy, axis='Z', segments=32, smooth=True)
    prof = [(0.12, 0.70), (0.16, 0.84), (0.42, 0.84), (0.66, 0.60), (0.86, 0.36), (1.02, 0.24), (1.08, 0.20)]
    lathe(K, "can", (0, 0, 0), prof, body, levels=2)
    K.cyl("pump", 0, 0, 1.18, 0.15, 0.20, metal, axis='Z', segments=24, smooth=True)
    K.cyl("thumb", 0, 0, 1.32, 0.20, 0.06, navy, axis='Z', segments=16, smooth=True)
    tip = Vector((-1.80, -1.10, 1.86))
    path = smooth_path([(-0.50, -0.42, 0.66), (-0.85, -0.62, 0.92), (-1.20, -0.80, 1.22), (-1.55, -0.98, 1.58), tuple(tip)], per_seg=6)
    sweep_tube(K, "spout", path, 0.065, metal, seg=14)
    K.cyl("spout_root", -0.50, -0.42, 0.66, 0.12, 0.10, metal, axis='Z', segments=16, smooth=True)
    K.cyl("root_seam", -0.50, -0.42, 0.72, 0.125, 0.025, navy, axis='Z', segments=16, smooth=True)
    # the drop: apex touching the nozzle tip, body hanging below it
    prof_d = [(0.00, 0.0), (0.06, 0.08), (0.18, 0.16), (0.32, 0.19), (0.46, 0.13), (0.56, 0.04), (0.60, 0.0)]
    lathe(K, "drop", (tip.x, tip.y, tip.z - 0.60), prof_d, amber, levels=2)
    return {"objects": len(col.objects)}


# ---------------------------------------------------------------- DURABLE ALLOYS
def build_durable_alloys():
    """OWNER: a thick forged ring resting against two short cylindrical billets. Cool grey with
    slate-blue shadow planes; broad machined faces and a very substantial cross-section. And a
    dark drill bit leaning on the ring."""
    setup_batch_rig()
    col = open_collection("ICON_durable_alloys")
    K = Kit(col)
    grey = P("cool_grey", (0.40, 0.46, 0.60)); slate = P("slate_blue", (0.25, 0.31, 0.44)); bit = P("bit_dark", (0.07, 0.09, 0.17))
    # ring: a thick annulus standing on edge, facing the camera's left (axis along X)
    R, t, w = 0.80, 0.24, 0.40
    # a forged ring: square-section annulus (four rings of verts, no centre caps)
    prof = [(-w / 2, R - t), (-w / 2, R + t), (w / 2, R + t), (w / 2, R - t), (-w / 2, R - t)]
    ring = lathe(K, "ring", (0, 0, 0), prof, grey, levels=0, cap_top=False, cap_bottom=False, smooth=False)
    ring.rotation_euler = (math.radians(90), 0, 0)         # Z -> -Y: the broad face is the lit FRONT
    ring.location = (0.45, 0.30, R + t)
    # two short billets lying along Y in front-left, one on the other
    K.cyl("billet0", -0.95, -0.55, 0.36, 0.36, 1.10, slate, axis='Y', segments=32, smooth=True)
    K.cyl("billet1", -0.45, -0.75, 0.36, 0.36, 1.10, slate, axis='Y', segments=32, smooth=True)
    # drill bit leaning on the ring: a dark rod from the ground to the ring's top-right
    # leaning ON the ring: foot on the ground front-right, top resting on the outer rim
    p0, p1 = Vector((1.75, -0.80, 0.08)), Vector((1.12, 0.06, 1.86))
    K.dircyl("bit", p0, p1, 0.085, bit, segments=14, smooth=True)
    d = (p1 - p0).normalized()
    K.dircyl("shank", p0 + d * 1.60, p1, 0.10, slate, segments=14, smooth=True)
    # two helical flutes so it reads as a drill, not a rod
    for k in range(2):
        noink(sweep_tube(K, "flute%d" % k, helix_path(p0 + d * 0.05, p0 + d * 1.55, 0.085, 3.0, math.pi * k), 0.040, slate, seg=8))
    return {"objects": len(col.objects)}


# ---------------------------------------------------------------- CONDUCTIVE ALLOYS
def build_conductive_alloys():
    """OWNER: three broad, overlapping metal strips, one gently bent upward. Copper, pale
    silver and muted gold; large colour areas and clearly visible thickness. And a cable made
    of silver wires twined together."""
    setup_batch_rig()
    col = open_collection("ICON_conductive_alloys")
    K = Kit(col)
    copper = P("copper", (0.64, 0.28, 0.12)); silver = P("strip_silver", (0.54, 0.60, 0.72)); gold = P("muted_gold", (0.68, 0.48, 0.14))
    t, w, L = 0.14, 0.55, 1.90
    # flat strips: boxes along Y, staggered and stacked so they overlap
    K.box("strip_copper", -0.55, 0.10, t / 2, w, L, t, copper)
    K.box("strip_gold", 0.05, -0.15, t / 2 + t, w, L, t, gold)
    # the silver strip bends gently upward toward the front: a cage loft along Y
    n = 9
    secs = []
    for i in range(n):
        y = L / 2 - L * i / (n - 1)
        rise = 0.0 if y > -0.1 else 0.55 * ((-0.1 - y) / (L / 2 - 0.1)) ** 1.6
        zb = 2 * t + rise
        secs.append((y, [(0.0, zb), (w / 2, zb), (w / 2, zb + t), (0.0, zb + t)]))
    strip = cage_loft(K, "strip_silver", secs, silver, levels=1, crease_rings=(), mirror=True, cap=True)
    strip.location = (0.65, 0.35, 0.0)
    # twined cable: three silver wires in a helix along X, lying in front
    a, b = Vector((-1.10, -1.22, 0.11)), Vector((1.15, -1.22, 0.11))
    for k in range(3):
        sweep_tube(K, "wire%d" % k, helix_path(a, b, 0.085, 2.0, 2 * math.pi * k / 3, n=48), 0.085, silver, seg=12)
    return {"objects": len(col.objects)}


# ---------------------------------------------------------------- PROPANE
def build_propane():
    """OWNER: a squat upright LPG bottle with a protective handle collar and foot ring. Muted
    terracotta/red-orange, cream band and simple central valve.
    Round two: straight walls (subsurf level 1 with a long straight cage section), one arched
    carry handle across the collar instead of two bars."""
    setup_batch_rig()
    col = open_collection("ICON_propane")
    K = Kit(col)
    terra = P("terracotta", (0.60, 0.20, 0.08)); cream = P("cream_band", (0.82, 0.76, 0.58)); steel = P("lpg_steel", (0.22, 0.28, 0.40))
    navy = K.mat("ic_navy")
    R = 0.72
    K.cyl("wall", 0, 0, 0.62, R, 1.00, terra, axis='Z', segments=40, smooth=True)
    lathe(K, "shoulder", (0, 0, 1.10), [(0.0, R), (0.16, R - 0.03), (0.30, 0.52), (0.38, 0.32)], terra, levels=1, cap_bottom=False)
    lathe(K, "base_dome", (0, 0, 0.12), [(0.0, 0.50), (0.02, R - 0.02), (0.0, R)], terra, levels=0, cap_top=False)
    K.cyl("band", 0, 0, 0.62, R + 0.012, 0.28, cream, axis='Z', segments=40, smooth=True)
    K.cyl("foot", 0, 0, 0.06, 0.56, 0.12, steel, axis='Z', segments=32, smooth=True)
    K.cyl("collar", 0, 0, 1.62, 0.40, 0.28, steel, axis='Z', segments=32, smooth=True)
    K.cyl("collar_hole", 0, 0, 1.70, 0.31, 0.16, navy, axis='Z', segments=32, smooth=True)
    K.cyl("valve", 0, 0, 1.66, 0.09, 0.22, steel, axis='Z', segments=16, smooth=True)
    K.cyl("valve_wheel", 0, 0, 1.80, 0.13, 0.05, navy, axis='Z', segments=16, smooth=True)
    # the carry handle: an arch over the collar in the X-Z plane (grip along X)
    arch = smooth_path([(-0.46, 0.0, 1.62), (-0.46, 0.0, 1.86), (-0.30, 0.0, 2.02), (0.0, 0.0, 2.08), (0.30, 0.0, 2.02), (0.46, 0.0, 1.86), (0.46, 0.0, 1.62)], per_seg=6)
    sweep_tube(K, "handle", arch, 0.06, steel, seg=12)
    return {"objects": len(col.objects)}
