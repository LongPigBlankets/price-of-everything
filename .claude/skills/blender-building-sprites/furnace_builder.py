# Parametric builder for the Furnace (generic; L1/L2/L3 split later).
# Run inside Blender (via MCP or --background):
#   exec(open(".../furnace_builder.py").read()); build_furnace()
# Rebuilds the BLDG_furnace collection from scratch each call; hides other BLDG_* collections.
# Shares the render rig contract with factory_builder.py (same camera/sun/Freestyle).
#
# Design brief (owner, 2026-07-29): double chimney; metal scaffolding; diagonal lift;
# thick pipework; process tanks on the LEFT (-X) feeding the furnace; flat-roofed hall
# at the base with the chimneys rising through a large rectangular roof gap; mostly
# dark navy/grey with red/fire accents where heat is high (fire = the one warm accent).

import bpy
import bmesh
import math

# ---------------- palette ----------------
# Shared names match factory_builder values exactly (same materials, same .blend).
PALETTE = {
    "roof":      (0.208, 0.262, 0.318),
    "glass":     (0.055, 0.075, 0.140),
    "mullion":   (0.780, 0.760, 0.700),
    "concrete":  (0.560, 0.570, 0.560),
    "door":      (0.330, 0.380, 0.420),
    "darkmetal": (0.160, 0.190, 0.230),
    "ink_black": (0.028, 0.032, 0.055),
    "silver":    (0.700, 0.720, 0.760),
    # furnace-specific
    "steel_navy":(0.150, 0.185, 0.240),   # hall cladding
    "stack_grey":(0.330, 0.355, 0.395),   # chimney shafts
    "tank_grey": (0.400, 0.435, 0.490),   # process tanks
    "heat_red":  (0.430, 0.120, 0.065),   # painted heat zones (flat)
    "annex_grey":(0.175, 0.190, 0.205),   # L3 charging house — dark grey
}

# ---------------- per-level parameters ----------------
# L1: bare plant — two SEPARATE capped chimneys, no hoist, no scaffold cage, one tank.
# L2: still separate chimneys; gains the scaffold cage, the steep trussed skip gantry and
#     the second (front-left) process tank.
# L3: the pair MERGES into one exhaust, and the gantry is replaced by a two-floor charging
#     house on the same (right) side.
LEVELS = {
    1: dict(merge=False, store=False, annex=False, scaffold=False, tanks=("T2",)),
    2: dict(merge=False, store=True,  annex=False, scaffold=True,  tanks=("T1", "T2")),
    3: dict(merge=True,  store=True,  annex=True,  scaffold=True,  tanks=("T1", "T2")),
}

EPS = 0.015


def _mat(name):
    mt = bpy.data.materials.get(name)
    if mt is None:
        mt = bpy.data.materials.new(name)
    mt.use_nodes = True
    b = mt.node_tree.nodes.get("Principled BSDF")
    b.inputs["Base Color"].default_value = (*PALETTE[name], 1)
    b.inputs["Roughness"].default_value = 1.0
    if "Specular IOR Level" in b.inputs:
        b.inputs["Specular IOR Level"].default_value = 0.0
    return mt


def _ember_mat():
    """Glowing fire accent: emissive so the heat reads constant-bright on any face."""
    mt = bpy.data.materials.get("ember")
    if mt is None:
        mt = bpy.data.materials.new("ember")
    mt.use_nodes = True
    b = mt.node_tree.nodes.get("Principled BSDF")
    b.inputs["Base Color"].default_value = (0, 0, 0, 1)
    b.inputs["Emission Color"].default_value = (0.820, 0.300, 0.085, 1)
    b.inputs["Emission Strength"].default_value = 1.45
    return mt


def _seam_mat():
    """Unlit navy used for seam beads: Freestyle cannot ink the intersection of two
    separate meshes, so metal-to-metal joints get an explicit bead instead."""
    mt = bpy.data.materials.get("ink_seam")
    if mt is None:
        mt = bpy.data.materials.new("ink_seam")
    mt.use_nodes = True
    b = mt.node_tree.nodes.get("Principled BSDF")
    b.inputs["Base Color"].default_value = (0, 0, 0, 1)
    b.inputs["Emission Color"].default_value = (0.012, 0.016, 0.045, 1)
    b.inputs["Emission Strength"].default_value = 1.0
    return mt


def setup_rig() -> None:
    """Same rig contract as factory_builder.setup_rig (idempotent)."""
    import mathutils
    scene = bpy.context.scene
    scene.render.engine = 'BLENDER_EEVEE'
    scene.render.film_transparent = True
    scene.render.resolution_x = 1024
    scene.render.resolution_y = 1024
    scene.render.use_freestyle = True
    scene.render.line_thickness_mode = 'ABSOLUTE'

    cam = bpy.data.objects.get("Camera")
    cam.data.type = 'ORTHO'
    cam.rotation_euler = (math.radians(54.736), 0.0, math.radians(45.0))
    target = mathutils.Vector((0, 0.55, 2.25))
    cam.location = target + mathutils.Vector((1, -1, 1)).normalized() * 26.0
    cam.data.ortho_scale = 11.0

    sun = bpy.data.objects.get("Light")
    sun.data.use_shadow = False
    sun.data.energy = 2.6
    sun.rotation_euler = (math.radians(50), math.radians(-15), math.radians(70))

    vl = scene.view_layers[0]
    vl.use_freestyle = True
    fs = vl.freestyle_settings
    fs.crease_angle = math.radians(120)
    if "ink" not in fs.linesets:
        ls = fs.linesets.new("ink")
        ls.select_silhouette = True
        ls.select_border = True
        ls.select_crease = True
        ls.select_edge_mark = True
    fs.linesets["ink"].linestyle.color = (0.055, 0.065, 0.13)
    fs.linesets["ink"].linestyle.thickness = 2.4
    if "contour" not in fs.linesets:
        ls = fs.linesets.new("contour")
        ls.select_silhouette = False
        ls.select_border = False
        ls.select_crease = False
        ls.select_external_contour = True
        ls.edge_type_combination = 'OR'
    fs.linesets["contour"].linestyle.color = (0.045, 0.055, 0.11)
    fs.linesets["contour"].linestyle.thickness = 7.0

    world = scene.world
    if world and world.use_nodes:
        bg = world.node_tree.nodes.get("Background")
        if bg:
            bg.inputs[0].default_value = (1, 1, 1, 1)
            bg.inputs[1].default_value = 0.75


def build_furnace(level: int = 2) -> dict:
    setup_rig()
    p = LEVELS[level]

    for other in bpy.data.collections:
        if other.name.startswith("BLDG_") and other.name != "BLDG_furnace":
            other.hide_render = True
            other.hide_viewport = True

    col = bpy.data.collections.get("BLDG_furnace")
    if col is None:
        col = bpy.data.collections.new("BLDG_furnace")
        bpy.context.scene.collection.children.link(col)
    col.hide_render = False
    col.hide_viewport = False
    for ob in list(col.objects):
        bpy.data.objects.remove(ob, do_unlink=True)

    M = {n: _mat(n) for n in PALETTE}
    M["ember"] = _ember_mat()
    M["seam"] = _seam_mat()
    M["well"] = _mat("steel_navy")

    # Feed-pipe geometry is needed BOTH by the pipework and by the scaffold, which has to
    # open a framed hole where T1's run pierces its front face.
    PIPE_R = 0.13
    T1X, T1Z = 1.05, 2.40                 # where T1's north run crosses the cage front plane

    def new_obj(name, mesh, mat=None, smooth=False):
        ob = bpy.data.objects.new(name, mesh)
        col.objects.link(ob)
        if mat:
            ob.data.materials.append(mat)
        # Flat everywhere by default (cel faces). `smooth` rounds the SIDES of a
        # revolved form only: quads = side facets -> smooth, n-gon caps stay flat so
        # the rim keeps its hard ink edge.
        for poly in ob.data.polygons:
            poly.use_smooth = smooth and len(poly.vertices) == 4
        return ob

    def box(name, cx, cy, cz, sx, sy, sz, mat=None):
        m = bpy.data.meshes.new(name)
        bm = bmesh.new()
        bmesh.ops.create_cube(bm, size=1.0)
        bmesh.ops.scale(bm, vec=(sx, sy, sz), verts=bm.verts)
        bmesh.ops.translate(bm, vec=(cx, cy, cz), verts=bm.verts)
        bm.to_mesh(m); bm.free()
        return new_obj(name, m, mat)

    def rotbox(name, cx, cy, cz, sx, sy, sz, mat, axis, angle_deg):
        """Box rotated about `axis` ('X'/'Y'/'Z') by angle_deg, centred at (cx,cy,cz)."""
        m = bpy.data.meshes.new(name)
        bm = bmesh.new()
        bmesh.ops.create_cube(bm, size=1.0)
        bmesh.ops.scale(bm, vec=(sx, sy, sz), verts=bm.verts)
        Matrix = __import__("mathutils").Matrix
        bmesh.ops.rotate(bm, cent=(0, 0, 0),
                         matrix=Matrix.Rotation(math.radians(angle_deg), 3, axis), verts=bm.verts)
        bmesh.ops.translate(bm, vec=(cx, cy, cz), verts=bm.verts)
        bm.to_mesh(m); bm.free()
        return new_obj(name, m, mat)

    def sqcol(name, cx, cy, z0, z1, side0, side1, mat):
        m = bpy.data.meshes.new(name)
        bm = bmesh.new()
        h0, h1 = side0 / 2, side1 / 2
        corners = ((-1, -1), (1, -1), (1, 1), (-1, 1))
        vb = [bm.verts.new((cx + sx * h0, cy + sy * h0, z0)) for sx, sy in corners]
        vt = [bm.verts.new((cx + sx * h1, cy + sy * h1, z1)) for sx, sy in corners]
        bm.faces.new(list(reversed(vb)))
        bm.faces.new(vt)
        for a in range(4):
            b = (a + 1) % 4
            bm.faces.new([vb[a], vb[b], vt[b], vt[a]])
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        bm.to_mesh(m); bm.free()
        return new_obj(name, m, mat)

    def cyl(name, cx, cy, cz, r, depth, mat, axis='Z', segments=12, smooth=False):
        m = bpy.data.meshes.new(name)
        bm = bmesh.new()
        bmesh.ops.create_cone(bm, cap_ends=True, segments=segments, radius1=r, radius2=r, depth=depth)
        Matrix = __import__("mathutils").Matrix
        if axis == 'Y':
            bmesh.ops.rotate(bm, cent=(0, 0, 0), matrix=Matrix.Rotation(math.radians(90), 3, 'X'), verts=bm.verts)
        elif axis == 'X':
            bmesh.ops.rotate(bm, cent=(0, 0, 0), matrix=Matrix.Rotation(math.radians(90), 3, 'Y'), verts=bm.verts)
        bmesh.ops.translate(bm, vec=(cx, cy, cz), verts=bm.verts)
        bm.to_mesh(m); bm.free()
        return new_obj(name, m, mat, smooth)

    def cone(name, cx, cy, cz, r0, r1, depth, mat, segments=12, smooth=False):
        m = bpy.data.meshes.new(name)
        bm = bmesh.new()
        bmesh.ops.create_cone(bm, cap_ends=True, segments=segments, radius1=r0, radius2=r1, depth=depth)
        bmesh.ops.translate(bm, vec=(cx, cy, cz), verts=bm.verts)
        bm.to_mesh(m); bm.free()
        return new_obj(name, m, mat, smooth)

    def sweep(name, pts, r, mat, seg=20):
        """Smooth tube swept along `pts`. Uses a parallel-transported frame: picking a
        fresh perpendicular per point flips when the tangent passes vertical and twists
        the tube, so each ring's frame is carried from the previous one instead."""
        mathutils = __import__("mathutils")
        P = [mathutils.Vector(q) for q in pts]
        n = len(P)
        tans = []
        for i in range(n):
            if i == 0:
                t = P[1] - P[0]
            elif i == n - 1:
                t = P[-1] - P[-2]
            else:
                t = P[i + 1] - P[i - 1]
            tans.append(t.normalized())
        ref = mathutils.Vector((0, 0, 1))
        if abs(tans[0].dot(ref)) > 0.9:
            ref = mathutils.Vector((1, 0, 0))
        a = tans[0].cross(ref).normalized()
        m = bpy.data.meshes.new(name)
        bm = bmesh.new()
        rings = []
        for i in range(n):
            if i > 0:
                a = tans[i - 1].rotation_difference(tans[i]).to_matrix() @ a
                a = (a - tans[i] * a.dot(tans[i])).normalized()
            b = tans[i].cross(a).normalized()
            ring = []
            for k in range(seg):
                ang = 2.0 * math.pi * k / seg
                ring.append(bm.verts.new(P[i] + a * (r * math.cos(ang)) + b * (r * math.sin(ang))))
            rings.append(ring)
        for i in range(n - 1):
            for k in range(seg):
                k2 = (k + 1) % seg
                bm.faces.new([rings[i][k], rings[i][k2], rings[i + 1][k2], rings[i + 1][k]])
        bm.faces.new(list(reversed(rings[0])))
        bm.faces.new(rings[-1])
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        bm.to_mesh(m); bm.free()
        return new_obj(name, m, mat, smooth=True)

    def hermite(p0, p1, m0, m1, steps=18):
        """Cubic Hermite samples; vertical tangents at both ends give a smooth S-gather."""
        out = []
        for i in range(steps + 1):
            t = i / steps
            t2, t3 = t * t, t * t * t
            h00 = 2 * t3 - 3 * t2 + 1
            h10 = t3 - 2 * t2 + t
            h01 = -2 * t3 + 3 * t2
            h11 = t3 - t2
            out.append(tuple(h00 * p0[k] + h10 * m0[k] + h01 * p1[k] + h11 * m1[k] for k in range(3)))
        return out

    def dirbox(name, p0, p1, w, h, mat, side=(0.0, 1.0, 0.0)):
        """Slab running p0 -> p1, `w` across (along `side`, made perpendicular) and `h` thick."""
        mathutils = __import__("mathutils")
        a = mathutils.Vector(p0)
        b = mathutils.Vector(p1)
        d = b - a
        m = bpy.data.meshes.new(name)
        bm = bmesh.new()
        bmesh.ops.create_cube(bm, size=1.0)
        bmesh.ops.scale(bm, vec=(w, d.length, h), verts=bm.verts)
        rot = mathutils.Vector((0, 1, 0)).rotation_difference(d.normalized()).to_matrix()
        bmesh.ops.rotate(bm, cent=(0, 0, 0), matrix=rot, verts=bm.verts)
        bmesh.ops.translate(bm, vec=(a + b) / 2, verts=bm.verts)
        bm.to_mesh(m); bm.free()
        return new_obj(name, m, mat)

    def seam_ring(name, cx, cy, cz, r, mat, axis='Z', t=0.035):
        """Thin unlit-navy band marking a metal-to-metal joint (Freestyle can't ink the
        intersection of two separate meshes, so every real joint needs one of these)."""
        return cyl(name, cx, cy, cz, r, t, mat, axis=axis, segments=28, smooth=True)

    def elbow(name, corner, d0, d1, r, bend, mat, steps=10):
        """Quarter-turn swept bend between two runs meeting at `corner`.
        d0 = incoming unit direction, d1 = outgoing unit direction (perpendicular).
        The arc is tangent to both runs, so pipes turn instead of meeting in a ball."""
        mathutils = __import__("mathutils")
        C0 = mathutils.Vector(corner)
        D0 = mathutils.Vector(d0).normalized()
        D1 = mathutils.Vector(d1).normalized()
        p_start = C0 - D0 * bend
        centre = p_start + D1 * bend
        u = p_start - centre                      # radius vector at the start
        v = D0 * bend                             # perpendicular radius, along travel
        pts = []
        for i in range(steps + 1):
            a = (math.pi / 2.0) * i / steps
            pts.append(tuple(centre + u * math.cos(a) + v * math.sin(a)))
        return sweep(name, pts, r, mat)

    def oval_cone(name, cx, cy, z0, z1, u, ax0, ay0, ax1, ay1, mat, seg=32):
        """Cone whose cross-section is an ELLIPSE: semi-axis ax along the horizontal
        unit vector `u`, ay perpendicular to it, both lerping from z0 to z1."""
        mathutils = __import__("mathutils")
        U = mathutils.Vector((u[0], u[1], 0.0)).normalized()
        V = mathutils.Vector((-U.y, U.x, 0.0))
        m = bpy.data.meshes.new(name)
        bm = bmesh.new()
        rings = []
        for (z, ax, ay) in ((z0, ax0, ay0), (z1, ax1, ay1)):
            ring = []
            for k in range(seg):
                th = 2.0 * math.pi * k / seg
                ring.append(bm.verts.new(mathutils.Vector((cx, cy, z))
                                         + U * (ax * math.cos(th)) + V * (ay * math.sin(th))))
            rings.append(ring)
        for k in range(seg):
            k2 = (k + 1) % seg
            bm.faces.new([rings[0][k], rings[0][k2], rings[1][k2], rings[1][k]])
        bm.faces.new(list(reversed(rings[0])))
        bm.faces.new(rings[1])
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        bm.to_mesh(m); bm.free()
        return new_obj(name, m, mat, smooth=True)

    def washer(name, c, axis, r_in, r_out, thick, mat, seg=28):
        """Flat annular ring with its hole along `axis` — frames a pipe where it passes
        through the scaffolding, so the pipe reads as going THROUGH a fitted opening."""
        mathutils = __import__("mathutils")
        C = mathutils.Vector(c)
        A = mathutils.Vector(axis).normalized()
        ref = mathutils.Vector((0, 0, 1))
        if abs(A.dot(ref)) > 0.9:
            ref = mathutils.Vector((1, 0, 0))
        U = A.cross(ref).normalized()
        V = A.cross(U).normalized()
        m = bpy.data.meshes.new(name)
        bm = bmesh.new()
        R = {}
        for side, t in (("a", -thick / 2.0), ("b", thick / 2.0)):
            for which, r in (("in", r_in), ("out", r_out)):
                R[(side, which)] = [
                    bm.verts.new(C + A * t + U * (r * math.cos(2 * math.pi * k / seg))
                                 + V * (r * math.sin(2 * math.pi * k / seg)))
                    for k in range(seg)]
        for k in range(seg):
            k2 = (k + 1) % seg
            bm.faces.new([R[("a", "out")][k], R[("a", "out")][k2], R[("b", "out")][k2], R[("b", "out")][k]])
            bm.faces.new([R[("b", "in")][k], R[("b", "in")][k2], R[("a", "in")][k2], R[("a", "in")][k]])
            bm.faces.new([R[("a", "in")][k], R[("a", "in")][k2], R[("a", "out")][k2], R[("a", "out")][k]])
            bm.faces.new([R[("b", "out")][k], R[("b", "out")][k2], R[("b", "in")][k2], R[("b", "in")][k]])
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        bm.to_mesh(m); bm.free()
        return new_obj(name, m, mat)

    def prism(name, origin, tdir, profile, width, mat):
        """Prism whose SIDE PROFILE is `profile` — a list of (along, up) points in the
        vertical plane through the horizontal direction `tdir` — extruded `width` across.
        Lets an inclined member have a FLAT (horizontal) foot and a VERTICAL end cut
        instead of the perpendicular caps a plain oriented box gives."""
        mathutils = __import__("mathutils")
        O = mathutils.Vector(origin)
        T = mathutils.Vector((tdir[0], tdir[1], 0.0)).normalized()
        S = mathutils.Vector((-T.y, T.x, 0.0))
        Z = mathutils.Vector((0.0, 0.0, 1.0))
        m = bpy.data.meshes.new(name)
        bm = bmesh.new()
        fa = [bm.verts.new(O + T * a + Z * u - S * (width / 2.0)) for (a, u) in profile]
        fb = [bm.verts.new(O + T * a + Z * u + S * (width / 2.0)) for (a, u) in profile]
        bm.faces.new(fa)
        bm.faces.new(list(reversed(fb)))
        n = len(profile)
        for i in range(n):
            j = (i + 1) % n
            bm.faces.new([fa[i], fa[j], fb[j], fb[i]])
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        bm.to_mesh(m); bm.free()
        return new_obj(name, m, mat)

    def sphere(name, cx, cy, cz, r, mat, smooth=True):
        m = bpy.data.meshes.new(name)
        bm = bmesh.new()
        bmesh.ops.create_uvsphere(bm, u_segments=24, v_segments=16, radius=r)
        bmesh.ops.translate(bm, vec=(cx, cy, cz), verts=bm.verts)
        bm.to_mesh(m); bm.free()
        ob = new_obj(name, m, mat)
        for poly in ob.data.polygons:
            poly.use_smooth = smooth
        return ob

    # ================= the hall (flat-roofed base building) =================
    HX0, HX1 = -1.965, 1.6      # -X edge extended 15% of the original width (owner: wider read)
    HY0, HY1 = -1.7, 1.7
    HH_F = 1.45                 # front mass (lower)
    HH = 1.85                   # back mass — its roof tops out at 1.95, just under the feed pipe
    YSPLIT = -0.30              # where the sloped front roof meets the flat back roof
    ROOF_F = HH_F + 0.10        # 1.55 front eave top
    ROOF_B = HH + 0.10          # 1.95 back roof top
    hcx, hcy = (HX0 + HX1) / 2, (HY0 + HY1) / 2
    # FRONT section is a single solid prism whose top IS the slope — building it as a box
    # plus a wedge left a horizontal joint line across the wall at the box's top.
    _m = bpy.data.meshes.new("hall_front")
    _bm = bmesh.new()
    _prof = [(HY0, 0.0), (YSPLIT, 0.0), (YSPLIT, HH), (HY0, HH_F)]
    _vf = [_bm.verts.new((HX0, y, z)) for (y, z) in _prof]
    _vb = [_bm.verts.new((HX1, y, z)) for (y, z) in _prof]
    _bm.faces.new(_vf)
    _bm.faces.new(list(reversed(_vb)))
    for _a in range(4):
        _b2 = (_a + 1) % 4
        _bm.faces.new([_vf[_a], _vf[_b2], _vb[_b2], _vb[_a]])
    bmesh.ops.recalc_face_normals(_bm, faces=_bm.faces)
    _bm.to_mesh(_m); _bm.free()
    new_obj("hall_front", _m, M["steel_navy"])
    # BACK section, full height
    box("hall_back", hcx, (YSPLIT + HY1) / 2, HH / 2, HX1 - HX0, HY1 - YSPLIT, HH, M["steel_navy"])
    _sl_len = math.hypot(YSPLIT - HY0, HH - HH_F)
    _sl_ang = math.degrees(math.atan2(HH - HH_F, YSPLIT - HY0))
    rotbox("hall_roof_front", hcx, (HY0 + YSPLIT) / 2, (HH_F + HH) / 2 + 0.05,
           HX1 - HX0 + 0.16, _sl_len, 0.10, M["roof"], 'X', _sl_ang)
    # seam bead where the sloped roof meets the raised back block
    box("seam_roof_ridge", hcx, YSPLIT, HH + 0.10, HX1 - HX0 + 0.17, 0.045, 0.045, M["seam"])
    # eaves beads where roof meets wall
    box("seam_eave_f", hcx, HY0 - 0.02, HH_F + 0.10, HX1 - HX0 + 0.17, 0.04, 0.04, M["seam"])
    box("seam_eave_r", HX1 + 0.02, (YSPLIT + HY1) / 2, HH + 0.10, 0.04, HY1 - YSPLIT + 0.17, 0.04, M["seam"])
    # flat roof slab over the back section
    box("hall_roof", hcx, (YSPLIT + HY1) / 2, HH + 0.05,
        HX1 - HX0 + 0.16, HY1 - YSPLIT + 0.16, 0.10, M["roof"])

    # ---- the rectangular roof gap the chimneys rise through: sunken dark pit + ink rim ----
    # (back-right corner, under the twin round furnaces)
    GX0, GX1 = -0.44, 1.52
    GY0, GY1 = -0.24, 1.66
    gcx, gcy = (GX0 + GX1) / 2, (GY0 + GY1) / 2
    # A real opening, not a black rectangle: four inner wall panels line the shaft so the
    # chimneys are seen passing THROUGH the roof, plus a floor to stop the view at a surface.
    WELL_D = 1.05                                  # how far the shaft is lined
    WZ = ROOF_B - WELL_D / 2
    box("well_floor", gcx, gcy, ROOF_B - WELL_D, GX1 - GX0, GY1 - GY0, 0.05, M["ink_black"])
    box("well_wall_f", gcx, GY0 + 0.03, WZ, GX1 - GX0, 0.06, WELL_D, M["well"])
    box("well_wall_b", gcx, GY1 - 0.03, WZ, GX1 - GX0, 0.06, WELL_D, M["well"])
    box("well_wall_l", GX0 + 0.03, gcy, WZ, 0.06, GY1 - GY0, WELL_D, M["well"])
    box("well_wall_r", GX1 - 0.03, gcy, WZ, 0.06, GY1 - GY0, WELL_D, M["well"])
    for nm, (bx, by, bw, bh) in {
        "gap_rim_f": (gcx, GY0, GX1 - GX0 + 0.05, 0.05),
        "gap_rim_b": (gcx, GY1, GX1 - GX0 + 0.05, 0.05),
        "gap_rim_l": (GX0, gcy, 0.05, GY1 - GY0 + 0.05),
        "gap_rim_r": (GX1, gcy, 0.05, GY1 - GY0 + 0.05),
    }.items():
        b = box(nm, bx, by, ROOF_B + 0.015, bw, bh, 0.035, M["darkmetal"])

    # ---- hall front (-Y): sliding door + heat mouth + window strip ----
    yf = HY0 - EPS
    box("hall_door", -0.95, yf, 0.62, 1.05, 0.01, 1.24, M["door"])
    for k in range(1, 4):
        box(f"hall_door_rib_{k}", -0.95, yf - 0.004, k * 1.24 / 4, 0.95, 0.008, 0.02, M["darkmetal"])
    box("hall_door_frame", -0.95, yf - 0.006, 1.27, 1.17, 0.012, 0.06, M["mullion"])
    # furnace mouth: dark hatch with a glowing ember slit — the hottest point
    box("mouth_frame", 0.28, yf, 0.42, 0.78, 0.01, 0.84, M["darkmetal"])
    box("mouth_glow", 0.28, yf - 0.004, 0.26, 0.58, 0.008, 0.34, M["ember"])
    box("mouth_lintel", 0.28, yf - 0.006, 0.88, 0.90, 0.012, 0.06, M["heat_red"])
    # high window, right half
    wy0 = 1.02
    box("fwin_glass", 1.10, yf, wy0 + 0.17, 0.62, 0.01, 0.34, M["glass"])
    box("fwin_fl", 1.10 - 0.31, yf - 0.005, wy0 + 0.17, 0.05, 0.012, 0.42, M["mullion"])
    box("fwin_fr", 1.10 + 0.31, yf - 0.005, wy0 + 0.17, 0.05, 0.012, 0.42, M["mullion"])
    box("fwin_ft", 1.10, yf - 0.005, wy0 + 0.36, 0.66, 0.012, 0.05, M["mullion"])
    box("fwin_fb", 1.10, yf - 0.005, wy0 - 0.02, 0.66, 0.012, 0.05, M["mullion"])
    box("fwin_mv", 1.10, yf - 0.004, wy0 + 0.17, 0.024, 0.01, 0.34, M["mullion"])

    # ---- hall right (+X): long high window band + heat vents ----
    xr = HX1 + EPS
    for i in range(3):
        cy = -1.05 + i * 1.05
        box(f"rwin_glass_{i}", xr, cy, 1.19, 0.01, 0.72, 0.34, M["glass"])
        box(f"rwin_fl_{i}", xr + 0.005, cy - 0.36, 1.19, 0.012, 0.05, 0.42, M["mullion"])
        box(f"rwin_fr_{i}", xr + 0.005, cy + 0.36, 1.19, 0.012, 0.05, 0.42, M["mullion"])
        box(f"rwin_ft_{i}", xr + 0.005, cy, 1.38, 0.012, 0.76, 0.05, M["mullion"])
        box(f"rwin_fb_{i}", xr + 0.005, cy, 1.00, 0.012, 0.76, 0.05, M["mullion"])
        box(f"rwin_mv_{i}", xr + 0.004, cy, 1.19, 0.01, 0.024, 0.34, M["mullion"])
    # low heat vents with ember cores
    for i in range(2):
        cy = -0.55 + i * 1.05
        box(f"vent_frame_{i}", xr, cy, 0.34, 0.01, 0.46, 0.30, M["darkmetal"])
        box(f"vent_glow_{i}", xr + 0.004, cy, 0.30, 0.008, 0.34, 0.12, M["ember"])

    # ================= the twin ROUND furnaces, merging into one exhaust =================
    # Two round furnace towers at the BACK-RIGHT corner, rising through the roof gap,
    # converging via angled branches into a single exhaust stack with a black tip.
    def dircyl(name, p0, p1, r, mat, segments=16, smooth=False):
        """Cylinder from point p0 to p1 (any direction)."""
        mathutils = __import__("mathutils")
        a = mathutils.Vector(p0)
        b = mathutils.Vector(p1)
        d = b - a
        m = bpy.data.meshes.new(name)
        bm = bmesh.new()
        bmesh.ops.create_cone(bm, cap_ends=True, segments=segments, radius1=r, radius2=r, depth=d.length)
        rot = mathutils.Vector((0, 0, 1)).rotation_difference(d.normalized()).to_matrix()
        bmesh.ops.rotate(bm, cent=(0, 0, 0), matrix=rot, verts=bm.verts)
        bmesh.ops.translate(bm, vec=(a + b) / 2, verts=bm.verts)
        bm.to_mesh(m); bm.free()
        return new_obj(name, m, mat, smooth)

    FA = (0.08, 0.28)                    # screen-horizontal = world (x+y): separate the pair
    FB = (1.05, 1.25)                    # along equal +x/+y so both towers read side by side at iso
    FR = 0.36                            # constant tower radius == duct radius
    F_TOP = 4.05
    SEG = 32                              # finer wall so the smooth-shaded silhouette reads round
    for key, (fx_, fy_) in (("A", FA), ("B", FB)):
        cyl(f"furn{key}", fx_, fy_, F_TOP / 2, FR, F_TOP, M["stack_grey"], segments=SEG, smooth=True)
        # glowing heat band just above the roofline — the hottest visible zone
        cyl(f"furn{key}_heat", fx_, fy_, 2.78, FR + 0.055, 0.22, M["ember"], segments=SEG, smooth=True)
        cyl(f"furn{key}_heatrim", fx_, fy_, 2.935, FR + 0.07, 0.07, M["heat_red"], segments=SEG, smooth=True)
        # seams at the top and bottom edge of every ring that sits on the shell
        for _rn, _rz, _rr in (("heat_lo", 2.78 - 0.11, FR + 0.065), ("heat_hi", 2.78 + 0.11, FR + 0.065),
                              ("rim", 2.935 + 0.035, FR + 0.08)):
            seam_ring(f"furn{key}_seam_{_rn}", fx_, fy_, _rz, _rr, M["seam"])
        # service collar
        cyl(f"furn{key}_ring", fx_, fy_, 2.35, FR + 0.045, 0.10, M["stack_grey"], segments=SEG, smooth=True)
        seam_ring(f"furn{key}_seam_collar_lo", fx_, fy_, 2.35 - 0.05, FR + 0.055, M["seam"])
        seam_ring(f"furn{key}_seam_collar_hi", fx_, fy_, 2.35 + 0.05, FR + 0.055, M["seam"])
        # flashing collar where the tower passes through the roof + flange where the
        # constant-diameter shell becomes the duct
        cyl(f"furn{key}_flash", fx_, fy_, ROOF_B + 0.03, FR + 0.075, 0.07, M["darkmetal"], segments=SEG, smooth=True)
        cyl(f"furn{key}_flash_seam", fx_, fy_, ROOF_B + 0.075, FR + 0.085, 0.035, M["seam"], segments=SEG, smooth=True)
        cyl(f"furn{key}_flange", fx_, fy_, F_TOP - 0.10, FR + 0.03, 0.04, M["seam"], segments=SEG, smooth=True)
    # Head: short vertical stubs -> ONE horizontal crossbar duct -> single exhaust.
    # (Angled branches converging on a point read as odd acute intersections; every
    #  junction here is a right angle, which stays legible under the ink pass.)
    EXC = ((FA[0] + FB[0]) / 2, (FA[1] + FB[1]) / 2)
    DR = FR                               # duct == tower: one constant tube base -> junction
    if p["merge"]:
        MERGE_Z = 4.52                    # underside of the exhaust — where the pair joins
        # Each duct runs STRAIGHT and shallow from its tower toward the stack and bends only
        # at the very top, turning vertical to enter the exhaust's UNDERSIDE. m0 points
        # straight at the target (so the run stays straight); only the short m1 curls it
        # upright. The two ends stop SHORT of the axis (offset toward their own tower) —
        # arriving dead-centre would make two identical vertical cylinders coincide.
        # SHOULDER-ARC duct. The path is built explicitly in three parts so the tube can
        # never gap or bulge:
        #   1. a short VERTICAL lead-in, coaxial with the tower (start tangent = +Z, which is
        #      what the old straight-at-the-target Hermite got wrong and opened a V-notch);
        #   2. a constant-radius fillet turning exactly 45 degrees toward the stack;
        #   3. a straight 45-degree run that plunges into the flaring exhaust base.
        # A mitred cut was tried instead and is worse: a 45-degree mitre reaches tan(67.5)*r
        # (~2.4r) below the kink on the OUTER side, so unless the sleeve is extended at least
        # that far the vertical section inverts and leaves an open hole exactly there.
        mathutils = __import__("mathutils")
        R_BEND = 0.46                         # shoulder fillet radius
        SLEEVE = DR + 0.012                   # a hair fatter than the tower: fitted collar,
        #                                       and no coaxial coplanar faces to z-fight

        for key, (fx_, fy_) in (("A", FA), ("B", FB)):
            a = mathutils.Vector((0, 0, 1))
            h = (mathutils.Vector((EXC[0], EXC[1], 0)) - mathutils.Vector((fx_, fy_, 0)))
            D = h.length
            h = h.normalized()
            z_b = F_TOP - 0.06                # where the fillet starts
            P_lead = mathutils.Vector((fx_, fy_, F_TOP - 0.62))
            P_arc0 = mathutils.Vector((fx_, fy_, z_b))
            C = P_arc0 + h * R_BEND           # fillet centre
            pts = [tuple(P_lead), tuple(P_lead.lerp(P_arc0, 0.55)), tuple(P_arc0)]
            NARC = 14
            for k in range(1, NARC + 1):
                phi = math.radians(45.0) * k / NARC
                pts.append(tuple(C + (-h * math.cos(phi) + a * math.sin(phi)) * R_BEND))
            arc_end = mathutils.Vector(pts[-1])
            b = (h + a).normalized()          # the 45-degree run
            horiz_left = D * 0.90 - (arc_end - P_arc0).dot(h)
            run = horiz_left * math.sqrt(2.0)
            for k in (0.34, 0.67, 1.0):
                pts.append(tuple(arc_end + b * (run * k)))
            sweep(f"furn{key}_duct", pts, SLEEVE, M["stack_grey"], seg=SEG)
            seam_ring(f"furn{key}_duct_seam", fx_, fy_, F_TOP - 0.60, SLEEVE + 0.02, M["seam"])

        # The flare is OVAL, not conical: it widens only along the axis joining the two
        # chimneys (they both arrive in that vertical plane) and stays as narrow as the
        # stack across it, so the breeches reads as a two-into-one and nothing balloons
        # on the empty sides. It closes to a circle at the top to meet the round stack.
        _u = (FB[0] - FA[0], FB[1] - FA[1])
        # Start the flare just ABOVE where the ducts converge, so its open bottom rim is
        # hidden behind them — sat lower, that rim reads as a dark line floating in the gap.
        oval_cone("exhaust_base", EXC[0], EXC[1], MERGE_Z + 0.20, MERGE_Z + 0.78, _u,
                  0.76, 0.43, 0.43, 0.43, M["stack_grey"], seg=SEG)
        cyl("exhaust_base_rim", EXC[0], EXC[1], MERGE_Z + 0.76, 0.455, 0.08, M["darkmetal"], segments=SEG, smooth=True)
        E0 = MERGE_Z + 0.80
        cone("exhaust", EXC[0], EXC[1], E0 + 0.78, 0.42, 0.34, 1.56, M["stack_grey"], segments=SEG, smooth=True)
        cyl("exhaust_ring", EXC[0], EXC[1], E0 + 1.26, 0.41, 0.10, M["stack_grey"], segments=SEG, smooth=True)
        cone("exhaust_tip", EXC[0], EXC[1], E0 + 1.74, 0.395, 0.365, 0.43, M["ink_black"], segments=SEG, smooth=True)
    else:
        # L1: no gather. Each chimney carries on alone to its own capped top.
        for key, (fx_, fy_) in (("A", FA), ("B", FB)):
            cyl(f"furn{key}_upper", fx_, fy_, (F_TOP + 4.62) / 2, FR, 4.62 - F_TOP,
                M["stack_grey"], segments=SEG, smooth=True)
            seam_ring(f"furn{key}_seam_upper", fx_, fy_, F_TOP, FR + 0.03, M["seam"])
            cyl(f"furn{key}_cap_ring", fx_, fy_, 4.50, FR + 0.045, 0.10, M["stack_grey"], segments=SEG, smooth=True)
            cone(f"furn{key}_tip", fx_, fy_, 4.83, FR + 0.035, FR + 0.005, 0.43,
                 M["ink_black"], segments=SEG, smooth=True)

    if p["scaffold"]:
    # ================= metal scaffolding around the furnaces (denser) =================
        SX0, SX1 = GX0 - 0.04, GX1 + 0.02
        SY0, SY1 = GY0 + 0.06, GY1 - 0.02
        S_TOP = 4.50
        pi = 0
        for px, py in ((SX0, SY0), (SX1, SY0),                       # front: corners only
                       (SX0, SY1), ((SX0 + SX1) / 2, SY1), (SX1, SY1)):
            box(f"scaf_post_{pi}", px, py, (ROOF_B + S_TOP) / 2, 0.06, 0.06, S_TOP - ROOF_B, M["darkmetal"])
            pi += 1
        rail_zs = (2.45, 3.45, S_TOP - 0.05)
        for li, z in enumerate(rail_zs):
            # Scaffolding lives on the FRONT face (fully visible now that the gantry docks
            # through the right); the RIGHT face carries no rails so the gantry and the
            # charging hole stay unobstructed.
            if "T1" in p["tanks"] and abs(z - T1Z) < 0.30:
                # T1's feed pierces the cage here: break the rail and frame the opening
                # with a ring slightly larger than the pipe, so it reads as a fitted hole
                # rather than a bar driven through a pipe.
                RO = PIPE_R + 0.11
                for si, (a0, a1) in enumerate((((SX0 - 0.03), T1X - RO), (T1X + RO, (SX1 + 0.03)))):
                    box(f"scaf_rail_f_{li}_{si}", (a0 + a1) / 2, SY0, z, a1 - a0, 0.05, 0.05, M["darkmetal"])
                washer(f"scaf_pipe_ring_{li}", (T1X, SY0, T1Z), (0, 1, 0),
                       PIPE_R + 0.035, RO, 0.09, M["darkmetal"])
            else:
                box(f"scaf_rail_f_{li}", (SX0 + SX1) / 2, SY0, z, SX1 - SX0 + 0.06, 0.05, 0.05, M["darkmetal"])
            box(f"scaf_rail_b_{li}", (SX0 + SX1) / 2, SY1, z, SX1 - SX0 + 0.06, 0.05, 0.05, M["darkmetal"])
            box(f"scaf_rail_l_{li}", SX0, (SY0 + SY1) / 2, z, 0.05, SY1 - SY0 + 0.06, 0.05, M["darkmetal"])
        # diagonal X-braces on the front face
        for bi, (x0b, x1b, z0b, z1b) in enumerate((
                (SX0 + 0.05, (SX0 + SX1) / 2, 2.45, 3.45),
                ((SX0 + SX1) / 2, SX1 - 0.05, 3.45, 2.45))):
            dircyl(f"scaf_brace_f_{bi}", (x0b, SY0, z0b), (x1b, SY0, z1b), 0.028, M["darkmetal"], segments=8)
        # work platform on the front face
        box("scaf_platform", (SX0 + SX1) / 2, SY0 - 0.14, 3.45, (SX1 - SX0) * 0.62, 0.24, 0.05, M["door"])
        # a mid-post on the front face to carry the rails (the right face keeps corners only)
        box(f"scaf_post_{pi}", (SX0 + SX1) / 2, SY0, (ROOF_B + S_TOP) / 2, 0.06, 0.06, S_TOP - ROOF_B, M["darkmetal"])

    # ====== vertical hoist on a ridged storage bunker, BEHIND the chimneys ======
    if p["store"]:
        HZ_ARCH = 3.15                                   # charging hole height on B
        # The bunker matches the L3 annex's width (1.55) and stands the full height of the
        # hoist, so both levels' side structures read as the same kit of parts.
        BX0, BX1 = 0.30, 1.85
        # y clears the hall ROOF's back overhang (HY1 + 0.08 = 1.78), not just the wall —
        # sat at 1.78 the bunker's front face was coplanar with the eave and clipped it.
        BY0, BY1 = 2.05, 3.10
        # Short enough that the conveyor lands on the shell WELL below where the two ducts
        # start bending (L3's lead-in begins at F_TOP-0.62); taller and it aimed at the joint.
        BH = 3.00
        bcx, bcy = (BX0 + BX1) / 2, (BY0 + BY1) / 2
        box("store_body", bcx, bcy, BH / 2, BX1 - BX0, BY1 - BY0, BH, M["stack_grey"])
        box("store_roof", bcx, bcy, BH + 0.05, BX1 - BX0 + 0.12, BY1 - BY0 + 0.12, 0.10, M["roof"])
        box("store_seam_eave", bcx, BY0 - 0.03, BH + 0.10, BX1 - BX0 + 0.14, 0.04, 0.04, M["seam"])
        box("store_plinth", bcx, bcy, 0.09, BX1 - BX0 + 0.10, BY1 - BY0 + 0.10, 0.18, M["darkmetal"])

        # RIDGES: vertical corrugations on the two faces the camera sees (-Y and +X).
        NRX = int((BX1 - BX0) / 0.19)
        for k in range(1, NRX):
            rx = BX0 + (BX1 - BX0) * k / NRX
            box(f"store_rib_f_{k}", rx, BY0 - 0.035, (0.18 + BH) / 2, 0.055, 0.07, BH - 0.18, M["stack_grey"])
        NRY = int((BY1 - BY0) / 0.19)
        for k in range(1, NRY):
            ry = BY0 + (BY1 - BY0) * k / NRY
            box(f"store_rib_r_{k}", BX1 + 0.035, ry, (0.18 + BH) / 2, 0.07, 0.055, BH - 0.18, M["stack_grey"])

        # VERTICAL hoist shaft, standing against the bunker's chimney-facing side
        # x clear of chimney B (which spans 0.69..1.41) or the shell swallows the shaft
        HX, HY = 1.62, BY0 - 0.02                        # front face at 1.86, clear of the eave
        HTOP = 3.46
        box("hoist_shaft", HX, HY, HTOP / 2, 0.44, 0.34, HTOP, M["darkmetal"])
        for i, off in enumerate((-0.15, 0.15)):
            box(f"hoist_guide_{i}", HX + off, HY - 0.18, HTOP / 2, 0.05, 0.05, HTOP, M["silver"])
        box("hoist_head", HX, HY, HTOP + 0.14, 0.58, 0.46, 0.28, M["darkmetal"])
        box("hoist_head_seam", HX, HY - 0.24, HTOP + 0.28, 0.60, 0.035, 0.035, M["seam"])
        box("hoist_car", HX, HY - 0.20, 1.30, 0.34, 0.10, 0.40, M["door"])

        # discharge hopper at the bunker's foot
        box("store_chute", BX1 - 0.42, BY0 - 0.14, 0.62, 0.46, 0.28, 0.52, M["darkmetal"])
        box("store_chute_lip", BX1 - 0.42, BY0 - 0.27, 0.40, 0.52, 0.10, 0.10, M["darkmetal"])

        # short chute from the hoist head across to the chimney's charging hole
        _nh = (0.70711, 0.70711)
        _hx = FB[0] + _nh[0] * FR
        _hy = FB[1] + _nh[1] * FR
        dirbox("hoist_conveyor", (HX, HY - 0.08, HTOP - 0.04), (_hx, _hy, HZ_ARCH + 0.06),
               0.26, 0.26, M["darkmetal"])                # squarish box-section tube
        dirbox("hoist_conveyor_cap", (HX, HY - 0.08, HTOP + 0.10), (_hx, _hy, HZ_ARCH + 0.20),
               0.30, 0.05, M["stack_grey"])

        # Charging hole: arched opening on B's back-right (camera-facing) shell, where the
        # chute lands. Rectangle plus a disc of the same half-width on its top edge = arch.
        HW = 0.175
        _cx, _cy = _hx - _nh[0] * 0.135, _hy - _nh[1] * 0.135
        rotbox("charge_hole_rect", _cx, _cy, HZ_ARCH - 0.11, HW * 2, 0.28, 0.22,
               M["ink_black"], 'Z', 45.0)
        dircyl("charge_hole_arch",
               (_cx - _nh[0] * 0.14, _cy - _nh[1] * 0.14, HZ_ARCH),
               (_cx + _nh[0] * 0.14, _cy + _nh[1] * 0.14, HZ_ARCH),
               HW, M["ink_black"], segments=24, smooth=True)

    # ====== L3: two-floor charging house at the BACK-RIGHT, beside the furnaces ======
    if p["annex"]:
        AX0, AX1 = HX1 - 0.02, HX1 + 1.55         # sunk 0.02 into the hall wall (no coplanar faces)
        AY1 = HY1                                  # BACK half of the depth, so it sits beside
        AY0 = HY1 - (HY1 - HY0) / 2.0              # the chimneys rather than out in front
        acx, acy = (AX0 + AX1) / 2, (AY0 + AY1) / 2
        # FLAT roof, level with the hall's back block (same HH, same slab, same top at ROOF_B)
        box("annex_body", acx, acy, HH / 2, AX1 - AX0, AY1 - AY0, HH, M["annex_grey"])
        box("annex_roof", acx, acy, HH + 0.05, AX1 - AX0 + 0.14, AY1 - AY0 + 0.14, 0.09, M["roof"])
        box("annex_seam_eave_f", acx, AY0 - 0.03, HH + 0.10, AX1 - AX0 + 0.16, 0.04, 0.04, M["seam"])
        box("annex_seam_eave_r", AX1 + 0.03, acy, HH + 0.10, 0.04, AY1 - AY0 + 0.16, 0.04, M["seam"])
        box("annex_seam_floor", acx, AY0 - 0.015, 0.95, AX1 - AX0 + 0.05, 0.035, 0.035, M["seam"])

        # ---- wide doorway on the FRONT (-Y) face, glowing yellow-orange inside ----
        _dy = AY0 - EPS
        DW, DH = 1.02, 0.92
        dcx = AX0 + 0.72
        box("annex_door_glow", dcx, _dy + 0.02, DH / 2, DW, 0.06, DH, M["ember"])
        box("annex_door_jamb_l", dcx - DW / 2 - 0.05, _dy - 0.01, DH / 2, 0.10, 0.05, DH + 0.10, M["darkmetal"])
        box("annex_door_jamb_r", dcx + DW / 2 + 0.05, _dy - 0.01, DH / 2, 0.10, 0.05, DH + 0.10, M["darkmetal"])
        box("annex_door_lintel", dcx, _dy - 0.01, DH + 0.06, DW + 0.20, 0.05, 0.12, M["darkmetal"])
        box("annex_door_seam", dcx, _dy - 0.035, DH + 0.135, DW + 0.22, 0.035, 0.035, M["seam"])
        box("annex_door_spill", dcx, AY0 - 0.20, 0.015, DW - 0.06, 0.34, 0.03, M["heat_red"])

        # ---- stairwell on the OUTER (+X) face: FOUR flights, TRUE switchback ----
        # Flights alternate SIDE as well as direction, so consecutive runs sit beside each
        # other rather than stacked in one column. Treads are narrowed (0.30) and made
        # shallower (6 per flight) so the two parallel runs together are barely wider than
        # the single run was — the composition does not grow.
        WALK_Z = ROOF_B + 0.07                     # walkway deck, just clear of the roof slab
        SX_ = AX1 + 0.36
        HALF = 0.16                                # half the gap between the two runs
        TW = 0.30                                  # tread width
        SY_A, SY_B = AY0 + 0.26, AY1 - 0.20
        NFL, NST = 4, 6
        _zs = [0.10 + (WALK_Z - 0.10) * k / NFL for k in range(NFL + 1)]
        for fl in range(NFL):
            za, zb = _zs[fl], _zs[fl + 1]
            rx = SX_ - HALF if fl % 2 == 0 else SX_ + HALF          # alternate side
            ya, yb = (SY_A, SY_B) if fl % 2 == 0 else (SY_B, SY_A)  # alternate direction
            for k in range(NST):
                t = (k + 0.5) / NST
                box(f"annex_step_{fl}_{k}", rx, ya + t * (yb - ya), za + t * (zb - za),
                    TW, abs(yb - ya) / NST * 0.86, 0.04, M["darkmetal"])
            for si, so in enumerate((-TW / 2 - 0.02, TW / 2 + 0.02)):
                dircyl(f"annex_stringer_{fl}_{si}", (rx + so, ya, za - 0.03), (rx + so, yb, zb - 0.03),
                       0.028, M["darkmetal"], segments=8)
        # Half-landings span BOTH runs at each turn; the last one is the top landing.
        for k in range(1, NFL + 1):
            ly = (SY_B + 0.17) if (k % 2 == 1) else (SY_A - 0.17)
            box(f"annex_landing_{k}", SX_, ly, _zs[k], 2 * HALF + TW + 0.10, 0.34, 0.05, M["darkmetal"])
        # Posts sit OUTBOARD of both runs, carrying the landings without spearing a flight.
        POST_X = SX_ + HALF + TW / 2 + 0.14
        for k, ly in enumerate((SY_A - 0.17, SY_B + 0.17)):
            box(f"annex_stair_post_{k}", POST_X, ly, WALK_Z / 2, 0.07, 0.07, WALK_Z, M["darkmetal"])

        # ---- roof walkway across to the furnace cage, with guardrails ----
        WY = SY_A - 0.17
        WX0, WX1 = 1.58, AX1 + 0.07                # ends AT the roofline
        box("walkway_deck", (WX0 + WX1) / 2, WY, WALK_Z, WX1 - WX0, 0.52, 0.06, M["darkmetal"])
        for k, wx in enumerate((AX0 + 0.45, AX0 + 1.15)):
            box(f"walkway_prop_{k}", wx, WY, (ROOF_B + WALK_Z) / 2, 0.07, 0.07, WALK_Z - ROOF_B, M["darkmetal"])
        for si, off in enumerate((-0.28, 0.28)):
            dircyl(f"walk_rail_{si}", (WX0, WY + off, WALK_Z + 0.25), (WX1, WY + off, WALK_Z + 0.25),
                   0.027, M["darkmetal"], segments=8)
            dircyl(f"walk_midrail_{si}", (WX0, WY + off, WALK_Z + 0.13), (WX1, WY + off, WALK_Z + 0.13),
                   0.022, M["darkmetal"], segments=8)
            for k in range(6):
                wx = WX0 + (WX1 - WX0) * k / 5
                box(f"walk_post_{si}_{k}", wx, WY + off, WALK_Z + 0.13, 0.04, 0.04, 0.26, M["darkmetal"])
        # rail carries on over the stair head so walkway and stairwell read as one run
        EXT_X = POST_X - 0.09
        for nm, (a, b) in {
            "walk_rail_ext_f": ((WX1, WY - 0.28, WALK_Z + 0.25), (EXT_X, WY - 0.28, WALK_Z + 0.25)),
            "walk_midrail_ext_f": ((WX1, WY - 0.28, WALK_Z + 0.13), (EXT_X, WY - 0.28, WALK_Z + 0.13)),
            "walk_rail_end": ((EXT_X, WY - 0.28, WALK_Z + 0.25), (EXT_X, WY + 0.28, WALK_Z + 0.25)),
            "walk_midrail_end": ((EXT_X, WY - 0.28, WALK_Z + 0.13), (EXT_X, WY + 0.28, WALK_Z + 0.13)),
        }.items():
            dircyl(nm, a, b, 0.026, M["darkmetal"], segments=8)
        for k, (px, py) in enumerate(((EXT_X, WY - 0.28), (EXT_X, WY + 0.28))):
            box(f"walk_ext_post_{k}", px, py, WALK_Z + 0.13, 0.04, 0.04, 0.26, M["darkmetal"])

    # ================= process tanks on the LEFT (-X), feeding the furnace bases =================
    ALL_TANKS = {
        "T1": dict(c=(-2.665, -0.95), r=0.50, h=1.62),      # front-left (L2+ only)
        "T2": dict(c=(-2.665, 0.42), r=0.50, h=1.62),
    }
    tanks = {k: v for k, v in ALL_TANKS.items() if k in p["tanks"]}
    for key, tk in tanks.items():
        tx, ty = tk["c"]
        cyl(f"tank{key}", tx, ty, tk["h"] / 2, tk["r"], tk["h"], M["tank_grey"], segments=32, smooth=True)
        cone(f"tank{key}_lid", tx, ty, tk["h"] + 0.13, tk["r"] + 0.03, 0.10, 0.26, M["darkmetal"], segments=32, smooth=True)
        # shell-to-lid seam, and the mid-height strake
        seam_ring(f"tank{key}_seam_lid", tx, ty, tk["h"], tk["r"] + 0.02, M["seam"])
        seam_ring(f"tank{key}_seam_mid", tx, ty, tk["h"] * 0.55, tk["r"] + 0.015, M["seam"])
        # collar where the riser penetrates the tank crown
        seam_ring(f"tank{key}_seam_riser", tx + 0.28, ty, tk["h"] + 0.02, 0.20, M["seam"])
    # shared foundation pad
    _tys = [v["c"][1] for v in tanks.values()]
    box("tank_pad", -2.665, (min(_tys) + max(_tys)) / 2, 0.06,
        1.18, (max(_tys) - min(_tys)) + 1.22, 0.12, M["concrete"])

    # ---- thick pipework: every line enters a furnace SHELL just above the roofline ----
    pr = PIPE_R
    # T1 (front tank) -> furnace B: riser, east run OVER the lift bridge, north into B's shell
    BR = 0.30                             # elbow bend radius
    if "T1" in tanks:
    # T1 (front tank) -> furnace B: up, east over the bridge, north into B's shell
        cyl("feedT1_riser", -2.385, -0.95, (1.62 + 2.40 - BR) / 2, pr, 2.40 - BR - 1.62, M["silver"], segments=24, smooth=True)
        elbow("feedT1_elb_a", (-2.385, -0.95, 2.40), (0, 0, 1), (1, 0, 0), pr, BR, M["silver"])
        cyl("feedT1_run", (-2.385 + BR + 1.05 - BR) / 2, -0.95, 2.40, pr,
            (1.05 - BR) - (-2.385 + BR), M["silver"], axis='X', segments=24, smooth=True)
        elbow("feedT1_elb_b", (1.05, -0.95, 2.40), (1, 0, 0), (0, 1, 0), pr, BR, M["silver"])
        cyl("feedT1_north", 1.05, (-0.95 + BR + 1.30) / 2, 2.40, pr,
            1.30 - (-0.95 + BR), M["silver"], axis='Y', segments=24, smooth=True)

    # T2 (rear tank, aligned with furnace A) -> straight east run into A's shell
    cyl("feedT2_riser", -2.385, 0.42, (1.62 + 2.15 - BR) / 2, pr, 2.15 - BR - 1.62, M["silver"], segments=24, smooth=True)
    elbow("feedT2_elb_a", (-2.385, 0.42, 2.15), (0, 0, 1), (1, 0, 0), pr, BR, M["silver"])
    cyl("feedT2_run", (-2.385 + BR + 0.16) / 2, 0.42, 2.15, pr, 0.16 - (-2.385 + BR), M["silver"], axis='X', segments=24, smooth=True)
    # penetration collars: pipe meets chimney shell (A on its -X side, B on its -Y side)
    seam_ring("feedT2_seam_shell", FA[0] - FR + 0.02, 0.42, 2.15, pr + 0.05, M["seam"], axis='X', t=0.05)
    if "T1" in tanks:
        seam_ring("feedT1_seam_shell", 1.05, FB[1] - FR + 0.02, 2.40, pr + 0.05, M["seam"], axis='Y', t=0.05)

    return {"building": "furnace", "level": level, "merge": p["merge"], "store": p["store"],
            "annex": p["annex"], "scaffold": p["scaffold"], "tanks": list(p["tanks"]),
            "objects": len(col.objects)}
