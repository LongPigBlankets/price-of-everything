# Parametric builder for the Industrial Goods Factory (levels 1-3).
# Run inside Blender (via MCP or --background):
#   exec(open(".../factory_builder.py").read()); build_factory(2)
# Rebuilds the BLDG_factory collection from scratch each call.
# Camera/lights/Freestyle are configured once in the .blend and left untouched.

import bpy
import bmesh
import math

# ---------------- palette ----------------
PALETTE = {
    # Brick red, shared with the high-tech manufactory's lower band.
    "brick":    (0.380, 0.165, 0.095),   # warm clay orange
    "roof":     (0.208, 0.262, 0.318),
    "glass":    (0.055, 0.075, 0.140),
    "mullion":  (0.780, 0.760, 0.700),
    "concrete": (0.560, 0.570, 0.560),
    "door":     (0.330, 0.380, 0.420),
    "darkmetal":(0.160, 0.190, 0.230),
    "ink_black":(0.028, 0.032, 0.055),
    "silver":   (0.700, 0.720, 0.760),
    # Catalogue-plate pass. Material names matter: the 3D export picks printed patterns by
    # name (brick coursing, standing seams on `roof_metal`, gravel on `membrane`).
    "roof_metal": (0.250, 0.300, 0.330),   # sawtooth slopes: standing-seam sheet
    "membrane":   (0.120, 0.125, 0.130),   # flat annex roofs
    "stone":      (0.600, 0.560, 0.470),   # lintels, sills, chimney bands, coping
    "white_pipe": (0.700, 0.660, 0.580),   # process pipework
    "plinth":     (0.035, 0.037, 0.042),   # the dark base course
    "hazard":     (0.520, 0.352, 0.045),   # safety yellow, small parts only
    "plaster":    (0.720, 0.700, 0.650),   # sawtooth ends and backs: plaster white
    "interior":   (0.040, 0.036, 0.032),   # what is seen through the glass: a dark room
    "interior_lo":(0.085, 0.075, 0.062),   # its lower half: benches and machines catch light
    # The back yard: storage along the long wall the home view does not show.
    "pad":        (0.300, 0.290, 0.260),   # yard hardstanding (printed as paving)
    "container":  (0.105, 0.205, 0.355),   # shipping container, the kit's container blue
}
# Window glass is see-through (BLENDED, alpha < 1): the 3D export gives it the glass shader.
# Warm teal slate, as on the reference plate, over a dark interior panel behind each pane.
GLASS_TINT = (0.070, 0.140, 0.190)
GLASS_ALPHA = 0.72

# ---------------- per-level parameters ----------------
LEVELS = {
    # L1: L2-size body, no loading-bay annex (double gate + door instead), no chimney.
    1: dict(bays=4, front_annex=False, gate=True, chimney=None, wide_window=True, rear_annex=False),
    # L2: the approved sprite, grown to 5 bays (the L1->L2 step carries the lengthwise expansion,
    # since L2's ends are already occupied by the loading bay and the chimney).
    2: dict(bays=5, front_annex=True, gate=False, chimney=dict(top=5.3, collars=(3.6, 4.35)),
            wide_window=True, rear_annex=False),
    # L3: adds the back-right glass-roofed process annex fed by silver piping. The chimney is
    # the SAME height as L2's (owner rule) — an upgrade adds plant, it does not re-raise the
    # stack — which also keeps the shared square crop from growing taller.
    3: dict(bays=5, front_annex=True, gate=False, chimney=dict(top=5.3, collars=(3.6, 4.35)),
            wide_window=True, rear_annex=True),
}

TL = 1.1        # bay length (Y)
RH_L3 = 1.3     # L3 rear process annex height
W = 2.4         # body width (X), before WIDEN
FLOOR = 1.1
H = 2 * FLOOR   # two floors
PH = 0.55       # sawtooth peak height
EPS = 0.015
# The body + roof are extended this far to the LEFT (-X, upper-left on screen) so the
# sprite reads wider against its square crop. One loading-bay door reveal — the same
# module as the chimney flue's thickness. The +X wall (windows, flue, rear annex) and the
# loading bay's position relative to the body are unchanged; the bay stays flush left.
WIDEN = 0.27
X0 = -W / 2 - WIDEN     # left wall
X1 = W / 2              # right wall (windows / flue / rear annex side)
XC = (X0 + X1) / 2      # body centre in X
LEAN_D = 0.70           # back lean-to store: depth out from the long -X wall
LEAN_HI, LEAN_LO = 1.05, 0.70   # its roof at the wall and at the outer eave (one storey at most)
BW = X1 - X0            # body width


def _mat(name):
    mt = bpy.data.materials.get(name)
    if mt is None:
        mt = bpy.data.materials.new(name)
    mt.use_nodes = True
    b = mt.node_tree.nodes.get("Principled BSDF")
    b.inputs["Base Color"].default_value = (*PALETTE[name], 1)
    b.inputs["Roughness"].default_value = 1.0
    if "Specular IOR Level" in b.inputs:      # kill sheen: pure flat cel faces,
        b.inputs["Specular IOR Level"].default_value = 0.0  # keeps glass blue-dominant for stylize.py
    return mt


def _glass_mat():
    mt = bpy.data.materials.get("factory_glass") or bpy.data.materials.new("factory_glass")
    mt.use_nodes = True
    b = mt.node_tree.nodes.get("Principled BSDF")
    b.inputs["Base Color"].default_value = (*GLASS_TINT, 1)
    b.inputs["Roughness"].default_value = 1.0
    if "Specular IOR Level" in b.inputs:
        b.inputs["Specular IOR Level"].default_value = 0.0
    b.inputs["Alpha"].default_value = GLASS_ALPHA
    mt.surface_render_method = 'BLENDED'
    mt.use_backface_culling = False
    return mt


def setup_rig() -> None:
    """Assert the full render rig (camera/sun/film/Freestyle). Idempotent —
    called by build_factory so a stale or fresh Blender session can't drift."""
    import math
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


def build_factory(level: int) -> dict:
    setup_rig()
    p = LEVELS[level]
    N = p["bays"]
    L = N * TL

    # One building per render: hide every other BLDG_* collection in the shared .blend.
    for other in bpy.data.collections:
        if other.name.startswith("BLDG_") and other.name != "BLDG_factory":
            other.hide_render = True
            other.hide_viewport = True

    col = bpy.data.collections.get("BLDG_factory")
    if col is None:
        col = bpy.data.collections.new("BLDG_factory")
        bpy.context.scene.collection.children.link(col)
    col.hide_render = False
    col.hide_viewport = False
    for ob in list(col.objects):
        bpy.data.objects.remove(ob, do_unlink=True)

    M = {n: _mat(n) for n in PALETTE}
    M["glass"] = _glass_mat()

    def new_obj(name, mesh, mat=None):
        ob = bpy.data.objects.new(name, mesh)
        col.objects.link(ob)
        if mat:
            ob.data.materials.append(mat)
        for poly in ob.data.polygons:
            poly.use_smooth = False
        return ob

    def box(name, cx, cy, cz, sx, sy, sz, mat=None):
        m = bpy.data.meshes.new(name)
        bm = bmesh.new()
        bmesh.ops.create_cube(bm, size=1.0)
        bmesh.ops.scale(bm, vec=(sx, sy, sz), verts=bm.verts)
        bmesh.ops.translate(bm, vec=(cx, cy, cz), verts=bm.verts)
        bm.to_mesh(m); bm.free()
        return new_obj(name, m, mat)

    def sqcol(name, cx, cy, z0, z1, side0, side1, mat):
        """Axis-aligned square column tapering side0->side1."""
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

    def cyl(name, cx, cy, cz, r, depth, mat, axis='Z', segments=12):
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
        return new_obj(name, m, mat)

    def sphere(name, cx, cy, cz, r, mat):
        m = bpy.data.meshes.new(name)
        bm = bmesh.new()
        bmesh.ops.create_uvsphere(bm, u_segments=12, v_segments=8, radius=r)
        bmesh.ops.translate(bm, vec=(cx, cy, cz), verts=bm.verts)
        bm.to_mesh(m); bm.free()
        return new_obj(name, m, mat)

    # ---------------- catalogue-plate fittings (helpers) ----------------
    def bar(name, p0, p1, t, mat):
        """A square bar of side t from p0 to p1 (handrails, sloped members)."""
        Vector = __import__("mathutils").Vector
        a, b = Vector(p0), Vector(p1)
        d = b - a
        m = bpy.data.meshes.new(name)
        bm = bmesh.new()
        bmesh.ops.create_cube(bm, size=1.0)
        bmesh.ops.scale(bm, vec=(t, t, d.length), verts=bm.verts)
        rot = Vector((0, 0, 1)).rotation_difference(d.normalized()).to_matrix()
        bmesh.ops.rotate(bm, cent=(0, 0, 0), matrix=rot, verts=bm.verts)
        bmesh.ops.translate(bm, vec=(a + b) / 2, verts=bm.verts)
        bm.to_mesh(m); bm.free()
        return new_obj(name, m, mat)

    def coping(tag, cx, cy, sx, sy, z, skip_left=False):
        """Stone coping round a flat roof's edge."""
        t, h = 0.07, 0.07
        box(f"cop_{tag}_f", cx, cy - sy / 2 + t / 2, z + h / 2, sx, t, h, M["stone"])
        box(f"cop_{tag}_b", cx, cy + sy / 2 - t / 2, z + h / 2, sx, t, h, M["stone"])
        box(f"cop_{tag}_r", cx + sx / 2 - t / 2, cy, z + h / 2, t, sy, h, M["stone"])
        if not skip_left:
            box(f"cop_{tag}_l", cx - sx / 2 + t / 2, cy, z + h / 2, t, sy, h, M["stone"])

    def ventilator(tag, x, y, z):
        """Rooftop turbine ventilator: throat, domed head, cap."""
        cyl(f"vent_{tag}", x, y, z + 0.06, 0.055, 0.12, M["silver"])
        sphere(f"vent_{tag}_head", x, y, z + 0.17, 0.095, M["silver"])
        cyl(f"vent_{tag}_cap", x, y, z + 0.27, 0.03, 0.03, M["darkmetal"])

    def ladder(x, y, z0, z1, cage_from):
        """Access ladder standing off a +X face: rails, rungs, brackets, and a safety cage
        (hoops and a strap) above `cage_from`."""
        for s_ in (-1, 1):
            box(f"lad_rail_{z0:.2f}_{s_}", x, y + s_ * 0.09, (z0 + z1) / 2, 0.025, 0.025, z1 - z0, M["darkmetal"])
        z, k = z0 + 0.10, 0
        while z < z1 - 0.05:
            box(f"lad_rung_{z0:.2f}_{k}", x, y, z, 0.02, 0.18, 0.02, M["darkmetal"])
            z += 0.13
            k += 1
        z, k = z0 + 0.20, 0
        while z < z1:
            box(f"lad_brk_{z0:.2f}_{k}", x - 0.025, y, z, 0.05, 0.20, 0.025, M["darkmetal"])
            z += 0.60
            k += 1
        zc = max(z0 + 0.3, cage_from)
        if zc < z1:
            z, k = zc, 0
            while z <= z1:
                for s_ in (-1, 1):
                    box(f"cage_{z0:.2f}_{k}_{s_}", x + 0.11, y + s_ * 0.13, z, 0.22, 0.02, 0.02, M["darkmetal"])
                box(f"cage_{z0:.2f}_{k}_f", x + 0.22, y, z, 0.02, 0.28, 0.02, M["darkmetal"])
                z += 0.30
                k += 1
            box(f"cage_{z0:.2f}_strap", x + 0.22, y, (zc + z1) / 2, 0.02, 0.02, z1 - zc, M["darkmetal"])

    def interior(axis, tag, x, y, z, w, h):
        """The room behind a pane: dark above, a lighter band of benches and machines below."""
        if axis == "x":
            box(f"{tag}_room", x, y, z + h * 0.15, 0.006, w, h * 0.70, M["interior"])
            box(f"{tag}_room_lo", x, y, z - h * 0.35, 0.006, w, h * 0.30, M["interior_lo"])
        else:
            box(f"{tag}_room", x, y, z + h * 0.15, w, 0.006, h * 0.70, M["interior"])
            box(f"{tag}_room_lo", x, y, z - h * 0.35, w, 0.006, h * 0.30, M["interior_lo"])

    def drainpipe(tag, wall, x, y, top, foot):
        """Downpipe from a gutter hopper at `top` to `foot`: brackets to the wall (`wall` is
        the axis it stands off), a shoe, and a drain grate when it reaches the ground."""
        cyl(f"dp_{tag}", x, y, (top + foot) / 2, 0.03, top - foot, M["silver"], segments=8)
        box(f"dp_{tag}_hopper", x, y, top - 0.02, 0.10, 0.10, 0.08, M["silver"])
        z = foot + 0.45
        k = 0
        while z < top - 0.20:
            if wall == "x":
                box(f"dp_{tag}_b{k}", x - 0.04, y, z, 0.07, 0.07, 0.025, M["darkmetal"])
            elif wall == "-x":
                box(f"dp_{tag}_b{k}", x + 0.04, y, z, 0.07, 0.07, 0.025, M["darkmetal"])
            else:
                box(f"dp_{tag}_b{k}", x, y + 0.04, z, 0.07, 0.07, 0.025, M["darkmetal"])
            z += 0.65
            k += 1
        box(f"dp_{tag}_shoe", x, y, foot + 0.05, 0.08, 0.08, 0.07, M["silver"])
        if foot <= 0.0:
            gx, gy = {"x": (x + 0.04, y), "-x": (x - 0.04, y)}.get(wall, (x, y - 0.04))
            box(f"grate_{tag}_kerb", gx, gy, 0.012, 0.22, 0.22, 0.024, M["concrete"])
            box(f"grate_{tag}", gx, gy, 0.016, 0.16, 0.16, 0.024, M["ink_black"])
            for k in range(3):
                off = (k - 1) * 0.05
                if wall in ("x", "-x"):
                    box(f"grate_{tag}_bar{k}", gx, gy + off, 0.03, 0.16, 0.012, 0.006, M["darkmetal"])
                else:
                    box(f"grate_{tag}_bar{k}", gx + off, gy, 0.03, 0.012, 0.16, 0.006, M["darkmetal"])

    def louvre(tag, x, y, z, w, h):
        """Wall louvre on a -Y face: dark opening, slats, stone head and sill."""
        box(f"louv_{tag}", x, y - 0.006, z, w, 0.01, h, M["ink_black"])
        for k in range(4):
            box(f"louv_{tag}_s{k}", x, y - 0.014, z - h / 2 + (k + 0.6) * h / 4, w - 0.03, 0.012, 0.022, M["darkmetal"])
        for nm, zz in (("t", z + h / 2 + 0.02), ("b", z - h / 2 - 0.02)):
            box(f"louv_{tag}_{nm}", x, y - 0.012, zz, w + 0.06, 0.02, 0.04, M["stone"])


    # ---------------- catalogue-plate details ----------------
    def details(p, N, L):
        rear = p["rear_annex"]
        rear_y0 = L / 2 - 1.30
        # Brick pilasters at every bay line on the +X long wall, a downpipe beside every
        # other one (from the sawtooth valley gutter), clear of the L3 annex.
        for i in range(N + 1):
            y = -L / 2 + i * TL
            if rear and y > rear_y0 - 0.15:
                continue
            box(f"pilaster_{i}", X1 + 0.03, y, H / 2, 0.06, 0.14, H, M["brick"])
        # Rainwater: a gutter along the front eave and one in every sawtooth valley, each
        # running out past the +X wall to a hopper and one downpipe per gutter, which ends on
        # a drain grate at ground level (or, at L3, on the boiler-house roof it stands over).
        GW, GH = 0.11, 0.07
        # Hung below and in front of the eave: its top stays under the roof edge, its back
        # clear of the facade, so it never cuts into the first slope.
        box("gutter_front", XC, -L / 2 - 0.015 - GW / 2, H - 0.012 - GH / 2, BW + 0.08, GW, GH, M["silver"])
        drainpipe("front", "y", X1 - 0.13, -L / 2 - 0.10, H - 0.10, 0.0)
        box("gutter_front_out", X1 - 0.13, -L / 2 - 0.10, H - 0.10, 0.08, 0.06, 0.05, M["silver"])
        for i in range(1, N):
            y = -L / 2 + i * TL
            box(f"gutter_v{i}", XC + 0.02, y, H + 0.035, BW + 0.12, GW, GH, M["silver"])
            dy = y + 0.13
            box(f"gutter_v{i}_out", X1 + 0.10, y + 0.065, H + 0.01, 0.06, 0.19, 0.05, M["silver"])
            over_annex = rear and dy > rear_y0 - 0.05
            drainpipe(f"v{i}", "x", X1 + 0.10, dy, H, (RH_L3 + 0.09) if over_annex else 0.0)
        # Dark plinth round every wall base (open where the L1 gate and door reach the ground).
        PH_, PO = 0.20, 0.03
        def plinth_run(tag, x0, x1, y0, y1):
            box(f"plinth_{tag}", (x0 + x1) / 2, (y0 + y1) / 2, PH_ / 2, x1 - x0, y1 - y0, PH_, M["plinth"])
        plinth_run("e", X1 - PO, X1 + PO, -L / 2 - PO, L / 2 + PO)
        plinth_run("w", X0 - PO, X0 + PO, -L / 2 - PO, L / 2 + PO)
        plinth_run("n", X0 - PO, X1 + PO, L / 2 - PO, L / 2 + PO)
        front = [(X0 - PO, X1 + PO)]
        if p["gate"]:
            gx, gw = -0.25 - WIDEN, 1.30
            front = [(X0 - PO, gx - gw / 2 - 0.08), (gx + gw / 2 + 0.08, 0.75 - 0.22), (0.75 + 0.22, X1 + PO)]
        for k, (a, b) in enumerate(front):
            plinth_run(f"s{k}", a, b, -L / 2 - PO, -L / 2 + PO)
        # Skylights and a turbine ventilator on every sawtooth slope.
        import mathutils
        n = mathutils.Vector((0, -PH, TL)).normalized()
        def on_slope(x, y0, f, lift):
            return mathutils.Vector((x, y0 + f * TL, H + f * PH)) + n * lift
        def slope_quad(name, y0, xa, xb, fa, fb, lift, mat):
            m = bpy.data.meshes.new(name)
            bm = bmesh.new()
            vs = [bm.verts.new(on_slope(x, y0, f, lift)) for x, f in ((xa, fa), (xb, fa), (xb, fb), (xa, fb))]
            bm.faces.new(vs)
            bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
            bm.to_mesh(m); bm.free()
            return new_obj(name, m, mat)
        for i in range(N):
            y0 = -L / 2 + i * TL
            xa, xb, fa, fb = X0 + 0.15, X0 + 1.95, 0.30, 0.78
            slope_quad(f"sky_{i}_frame", y0, xa - 0.05, xb + 0.05, fa - 0.06, fb + 0.06, 0.012, M["stone"])
            slope_quad(f"sky_{i}_room", y0, xa, xb, fa, fb, 0.024, M["interior"])
            slope_quad(f"sky_{i}", y0, xa, xb, fa, fb, 0.040, M["glass"])
            for k in range(1, 8):
                xm = xa + k * (xb - xa) / 8
                slope_quad(f"sky_{i}_m{k}", y0, xm - 0.013, xm + 0.013, fa, fb, 0.060, M["mullion"])
            slope_quad(f"sky_{i}_mh", y0, xa, xb, (fa + fb) / 2 - 0.02, (fa + fb) / 2 + 0.02, 0.058, M["mullion"])
            base = on_slope(X0 + 2.20, y0, 0.70, 0.0)
            ventilator(f"t{i}", base.x, base.y, base.z - 0.02)
        if p["front_annex"]:
            AW, AL, AH = 1.5, 1.4, FLOOR
            ax, ay = X0 + AW / 2, -L / 2 - AL / 2
            afx = ax + AW / 2 + EPS
            dw, dh = 0.85, 0.62
            dz = 0.30 + dh / 2
            plinth_run("ann_f", ax - AW / 2 - PO, ax + AW / 2 + PO, ay - AL / 2 - PO, ay - AL / 2 + PO)
            plinth_run("ann_w", ax - AW / 2 - PO, ax - AW / 2 + PO, ay - AL / 2 - PO, ay + AL / 2)
            # Hazard-striped jambs either side of the bay door, rubber bumpers and a yellow
            # edge on the dock, steps with a handrail at its front end, a lamp, a louvre, a drum.
            for s_ in (-1, 1):
                jy = ay + s_ * (dw / 2 + 0.09)
                for k in range(6):
                    bh = (dh + 0.04) / 6
                    box(f"jamb_{s_}_{k}", afx + 0.03, jy, 0.30 + (k + 0.5) * bh, 0.05, 0.07, bh,
                        M["hazard"] if k % 2 == 0 else M["ink_black"])
                box(f"bumper_{s_}", afx + 0.55, ay + s_ * 0.32, 0.17, 0.06, 0.16, 0.16, M["ink_black"])
            box("dock_edge", afx + 0.50, ay, 0.306, 0.04, AL, 0.014, M["hazard"])
            sx = afx + 0.26
            sy = ay - AL / 2
            box("dock_step_1", sx, sy - 0.10, 0.10, 0.44, 0.20, 0.20, M["concrete"])
            box("dock_step_2", sx, sy - 0.30, 0.05, 0.44, 0.20, 0.10, M["concrete"])
            hx = sx + 0.20
            box("rail_post_a", hx, sy - 0.36, 0.10 + 0.225, 0.025, 0.025, 0.45, M["darkmetal"])
            box("rail_post_b", hx, sy + 0.08, 0.30 + 0.225, 0.025, 0.025, 0.45, M["darkmetal"])
            bar("rail_top", (hx, sy - 0.36, 0.55), (hx, sy + 0.08, 0.75), 0.025, M["darkmetal"])
            box("bay_lamp_arm", afx + 0.05, ay, dz + dh / 2 + 0.17, 0.10, 0.03, 0.03, M["darkmetal"])
            box("bay_lamp", afx + 0.10, ay, dz + dh / 2 + 0.14, 0.08, 0.12, 0.05, M["mullion"])
            louvre("annex", ax - 0.25, ay - AL / 2 - EPS, 0.62, 0.30, 0.26)
            cyl("drum", afx + 0.68, sy + 0.14, 0.12, 0.09, 0.24, M["darkmetal"])
            box("drum_band", afx + 0.68, sy + 0.14, 0.17, 0.19, 0.19, 0.02, M["hazard"])
        if rear:
            RX0, RX1, RY0 = 1.15, 2.75, rear_y0
            plinth_run("rann_f", RX0, RX1 + PO, RY0 - PO, RY0 + PO)
            plinth_run("rann_e", RX1 - PO, RX1 + PO, RY0 - PO, L / 2 + PO)
            box("cabinet", 1.55, RY0 - 0.11, 0.24, 0.34, 0.18, 0.48, M["door"])
            box("cabinet_cap", 1.55, RY0 - 0.11, 0.495, 0.38, 0.22, 0.03, M["darkmetal"])
            louvre("rannex", 1.55, RY0 - EPS, 0.90, 0.28, 0.22)


    # ---------------- the sides the home view does not show ----------------
    def face_window(tag, face, x, y, cz, ww, wh, cols=2):
        """A window on the -X long wall or the +Y back gable: teal glass over a dark room,
        cream frames and mullions, stone lintel and sill."""
        if face == "-x":
            xg = x - EPS
            interior("x", tag, xg + 0.009, y, cz, ww, wh)
            box(f"{tag}_glass", xg, y, cz, 0.01, ww, wh, M["glass"])
            for nm, dy, sy in (("fl", -ww / 2, 0.05), ("fr", ww / 2, 0.05)):
                box(f"{tag}_{nm}", xg - 0.005, y + dy, cz, 0.012, sy, wh + 0.1, M["mullion"])
            box(f"{tag}_ft", xg - 0.005, y, cz + wh / 2, 0.012, ww + 0.09, 0.05, M["mullion"])
            box(f"{tag}_sill", xg - 0.01, y, cz - wh / 2, 0.03, ww + 0.13, 0.055, M["stone"])
            box(f"{tag}_lint", xg - 0.015, y, cz + wh / 2 + 0.085, 0.035, ww + 0.18, 0.10, M["stone"])
            for k in range(1, cols):
                box(f"{tag}_mv{k}", xg - 0.004, y - ww / 2 + k * ww / cols, cz, 0.01, 0.026, wh, M["mullion"])
            for k in range(1, 3):
                box(f"{tag}_mh{k}", xg - 0.004, y, cz - wh / 2 + k * wh / 3, 0.01, ww, 0.026, M["mullion"])
        else:
            yg = y + EPS
            interior("y", tag, x, yg - 0.009, cz, ww, wh)
            box(f"{tag}_glass", x, yg, cz, ww, 0.01, wh, M["glass"])
            for nm, dx in (("fl", -ww / 2), ("fr", ww / 2)):
                box(f"{tag}_{nm}", x + dx, yg + 0.005, cz, 0.05, 0.012, wh + 0.1, M["mullion"])
            box(f"{tag}_ft", x, yg + 0.005, cz + wh / 2, ww + 0.09, 0.012, 0.05, M["mullion"])
            box(f"{tag}_sill", x, yg + 0.01, cz - wh / 2, ww + 0.13, 0.03, 0.055, M["stone"])
            box(f"{tag}_lint", x, yg + 0.015, cz + wh / 2 + 0.085, ww + 0.18, 0.035, 0.10, M["stone"])
            for k in range(1, cols):
                box(f"{tag}_mv{k}", x - ww / 2 + k * ww / cols, yg + 0.004, cz, 0.026, 0.01, wh, M["mullion"])
            for k in range(1, 3):
                box(f"{tag}_mh{k}", x, yg + 0.004, cz - wh / 2 + k * wh / 3, ww, 0.01, 0.026, M["mullion"])

    def prism_x(name, x0, x1, y0, y1, z_at_x0, z_at_x1, mat):
        """A solid whose top slopes across X (z_at_x0 at x0, z_at_x1 at x1), extruded y0..y1."""
        m = bpy.data.meshes.new(name)
        bm = bmesh.new()
        prof = [(x0, 0.0), (x1, 0.0), (x1, z_at_x1), (x0, z_at_x0)]
        va = [bm.verts.new((x, y0, z)) for (x, z) in prof]
        vb = [bm.verts.new((x, y1, z)) for (x, z) in prof]
        bm.faces.new(va)
        bm.faces.new(list(reversed(vb)))
        for a in range(4):
            b = (a + 1) % 4
            bm.faces.new([va[a], va[b], vb[b], vb[a]])
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        bm.to_mesh(m); bm.free()
        return new_obj(name, m, mat)

    def container(tag, cx, y0, length, w=0.66, h=0.70):
        """A shipping container along the wall (long axis Y) on corner blocks: corrugated long
        side, doors with locking bars on its +Y end, corner castings."""
        y1 = y0 + length
        cy = (y0 + y1) / 2
        for k, (bx, by) in enumerate(((cx - w / 2 + 0.06, y0 + 0.08), (cx + w / 2 - 0.06, y0 + 0.08),
                                      (cx - w / 2 + 0.06, y1 - 0.08), (cx + w / 2 - 0.06, y1 - 0.08))):
            box(f"{tag}_block{k}", bx, by, 0.02, 0.10, 0.10, 0.04, M["concrete"])
        zb = 0.04
        box(tag, cx, cy, zb + h / 2, w, length, h, M["container"])
        n_ribs = int(length / 0.12)
        for k in range(n_ribs):
            ry = y0 + (k + 0.5) * length / n_ribs
            box(f"{tag}_rib{k}", cx - w / 2 - 0.006, ry, zb + h / 2, 0.012, 0.035, h - 0.10, M["container"])
        box(f"{tag}_seam", cx, y1 + 0.006, zb + h / 2, 0.012, 0.012, h - 0.08, M["darkmetal"])
        for k, bx in enumerate((cx - 0.20, cx - 0.08, cx + 0.08, cx + 0.20)):
            box(f"{tag}_bar{k}", bx, y1 + 0.012, zb + h / 2, 0.018, 0.018, h - 0.10, M["silver"])
        for sx in (-1, 1):
            for sy, yy in ((-1, y0), (1, y1)):
                for zz in (zb + 0.04, zb + h - 0.04):
                    box(f"{tag}_cc{sx > 0}{sy > 0}{zz > 0.3}", cx + sx * (w / 2 - 0.04), yy - sy * 0.04, zz,
                        0.09, 0.09, 0.09, M["darkmetal"])

    def wall_louvre(tag, x, y, z, w, h):
        """Ventilation louvre on the -X wall: dark opening, slats, stone head and sill."""
        box(f"{tag}", x - 0.006, y, z, 0.01, w, h, M["ink_black"])
        for k in range(4):
            box(f"{tag}_s{k}", x - 0.014, y, z - h / 2 + (k + 0.6) * h / 4, 0.012, w - 0.03, 0.022, M["darkmetal"])
        for nm, zz in (("t", z + h / 2 + 0.02), ("b", z - h / 2 - 0.02)):
            box(f"{tag}_{nm}", x - 0.012, y, zz, 0.02, w + 0.06, 0.04, M["stone"])

    def drum(tag, x, y, mat, band=True):
        cyl(f"drum_{tag}", x, y, 0.15, 0.10, 0.30, mat)
        cyl(f"drum_{tag}_lid", x, y, 0.305, 0.085, 0.012, M["darkmetal"])
        if band:
            cyl(f"drum_{tag}_band", x, y, 0.20, 0.103, 0.035, M["hazard"])

    def back_side(p, N, L):
        # Hardstanding along the long -X wall for the yard.
        box("yard_pad", X0 - 0.48, 0.0, -0.03, 0.96, L, 0.06, M["pad"])
        # Pilasters at every bay line, as on the window wall.
        for i in range(N + 1):
            box(f"pilaster_w{i}", X0 - 0.03, -L / 2 + i * TL, H / 2, 0.06, 0.14, H, M["brick"])
        # Lean-to store against bay 1: brick walls, standing-seam mono-pitch roof below the
        # first-floor sills, a roller door, an eaves gutter and downpipe.
        ya, yb = -L / 2 + TL, -L / 2 + 2 * TL
        lx = X0 - LEAN_D
        prism_x("leanto", X0 + 0.01, lx, ya, yb, LEAN_HI, LEAN_LO, M["brick"])
        m = bpy.data.meshes.new("leanto_roof")
        bm = bmesh.new()
        xo = lx - 0.08
        def zr(x, lift):
            return LEAN_LO + (LEAN_HI - LEAN_LO) * (x - lx) / (X0 - lx) + lift
        corners = [(X0, ya - 0.05), (xo, ya - 0.05), (xo, yb + 0.05), (X0, yb + 0.05)]
        top = [bm.verts.new((x, y, zr(x, 0.05))) for x, y in corners]
        bot = [bm.verts.new((x, y, zr(x, 0.01))) for x, y in corners]
        bm.faces.new(top)
        bm.faces.new(list(reversed(bot)))
        for a in range(4):
            b = (a + 1) % 4
            bm.faces.new([top[a], top[b], bot[b], bot[a]])
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        bm.to_mesh(m); bm.free()
        new_obj("leanto_roof", m, M["roof_metal"])
        box("leanto_flash", X0 - 0.04, (ya + yb) / 2, LEAN_HI + 0.07, 0.08, yb - ya + 0.10, 0.05, M["stone"])
        door_y, dw, dh = (ya + yb) / 2, 0.56, 0.52
        box("leanto_door", lx - EPS, door_y, dh / 2, 0.01, dw, dh, M["door"])
        for nm, dy in (("fl", -dw / 2), ("fr", dw / 2)):
            box(f"leanto_door_{nm}", lx - EPS - 0.005, door_y + dy, dh / 2, 0.012, 0.06, dh + 0.06, M["mullion"])
        box("leanto_door_ft", lx - EPS - 0.005, door_y, dh + 0.02, 0.012, dw + 0.14, 0.05, M["stone"])
        for k in range(1, 5):
            box(f"leanto_slat{k}", lx - EPS - 0.004, door_y, k * dh / 5, 0.008, dw - 0.06, 0.018, M["darkmetal"])
        PO = 0.03
        for k, (a, b) in enumerate(((ya, door_y - dw / 2 - 0.05), (door_y + dw / 2 + 0.05, yb))):
            box(f"leanto_plinth{k}", lx, (a + b) / 2, 0.07, 2 * PO, b - a, 0.14, M["plinth"])
        box("leanto_plinth_b", (lx + X0) / 2, yb, 0.07, X0 - lx, 2 * PO, 0.14, M["plinth"])
        box("leanto_gutter", xo - 0.05, (ya + yb) / 2, LEAN_LO - 0.02, 0.10, yb - ya + 0.10, 0.06, M["silver"])
        drainpipe("leanto", "-x", xo - 0.05, ya + 0.08, LEAN_LO - 0.05, 0.0)
        # One full-length (20 ft) container in the two bays beyond the store, two drums by it.
        c0 = yb + 0.25
        container("cont", X0 - 0.45, c0, 1.60)
        for k, y in enumerate((c0 + 1.60 + 0.20, c0 + 1.60 + 0.42)):
            if y < L / 2 - 0.12:
                drum(f"b{k}", X0 - 0.28, y, M["darkmetal"], band=(k == 0))
        # First-floor windows along the whole wall; on the ground floor, vents where nothing
        # stands in front of the wall.
        for i in range(N):
            cy = -L / 2 + TL / 2 + i * TL
            face_window(f"ww{i}_1", "-x", X0, cy, FLOOR + 0.24 + 0.36, 0.50, 0.72)
            blocked = (ya - 0.01 < cy < yb + 0.01) or (c0 - 0.05 < cy < c0 + 1.65)
            if not blocked:
                wall_louvre(f"wv{i}", X0, cy, 0.58, 0.34, 0.30)
        # Back gable: plain brick and one vent; no window or door at the very back.
        lx_, lw, lh = XC, 0.30, 0.30
        dy = L / 2 + EPS
        box("back_louv", lx_, dy - 0.009, 0.62, lw, 0.01, lh, M["ink_black"])
        for k in range(4):
            box(f"back_louv_s{k}", lx_, dy + 0.004, 0.62 - lh / 2 + (k + 0.6) * lh / 4, lw - 0.03, 0.012, 0.022, M["darkmetal"])
        for nm, zz in (("t", 0.62 + lh / 2 + 0.02), ("b", 0.62 - lh / 2 - 0.02)):
            box(f"back_louv_{nm}", lx_, dy + 0.006, zz, lw + 0.06, 0.02, 0.04, M["stone"])
        # North lights: the upright face of every sawtooth is glazed, as on a real sawtooth
        # roof, with a dark room behind and cream mullions.
        gx0, gx1 = X0 + 0.12, X1 - 0.12
        z0, z1 = H + 0.07, H + PH - 0.07
        for i in range(N):
            y1 = -L / 2 + (i + 1) * TL
            box(f"nl{i}_room", (gx0 + gx1) / 2, y1 + 0.004, (z0 + z1) / 2, gx1 - gx0, 0.006, z1 - z0, M["interior"])
            box(f"nl{i}_glass", (gx0 + gx1) / 2, y1 + 0.010, (z0 + z1) / 2, gx1 - gx0, 0.006, z1 - z0, M["glass"])
            for k in range(9):
                xm = gx0 + k * (gx1 - gx0) / 8
                box(f"nl{i}_m{k}", xm, y1 + 0.016, (z0 + z1) / 2, 0.026, 0.008, z1 - z0 + 0.04, M["mullion"])
            box(f"nl{i}_sill", (gx0 + gx1) / 2, y1 + 0.016, z0 - 0.015, gx1 - gx0 + 0.04, 0.02, 0.03, M["stone"])

    # ---------------- main body ----------------
    box("body", XC, 0, H / 2, BW, L, H, M["brick"])

    # ---------------- flipped sawtooth roof (slope rises toward +Y) ----------------
    for i in range(N):
        y0 = -L / 2 + i * TL
        y1 = y0 + TL
        m = bpy.data.meshes.new(f"tooth_{i}")
        bm = bmesh.new()
        prof = [(y0, H), (y1, H + PH), (y1, H)]
        vf = [bm.verts.new((X0, y, z)) for (y, z) in prof]
        vb = [bm.verts.new((X1, y, z)) for (y, z) in prof]
        ends = [bm.faces.new(vf), bm.faces.new(list(reversed(vb)))]
        sides = []
        for a in range(3):
            b = (a + 1) % 3
            sides.append(bm.faces.new([vf[a], vf[b], vb[b], vb[a]]))
        # The slope is standing-seam sheet; the triangular ends (the zigzag seen along the
        # long walls) are plaster white. The upright back and the underside stay roof: both
        # meet the slope at a grazing angle (ridge, eave), and painted white they flicker
        # through it there. Neither is seen from the board's camera.
        for f in ends:
            f.material_index = 1
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        bm.to_mesh(m); bm.free()
        tooth = new_obj(f"tooth_{i}", m, M["roof_metal"])
        tooth.data.materials.append(M["plaster"])

    # ---------------- long-wall windows: one column per bay (last bay = flue when chimneyed) ----------------
    n_wincols = N - 1 if p["chimney"] else N
    x = X1 + EPS
    ww, wh = 0.50, 0.72
    for i in range(n_wincols):
        cy = -L / 2 + TL / 2 + i * TL
        for f in range(2):
            sill = f * FLOOR + 0.24
            cz = sill + wh / 2
            s = f"w{i}_{f}"
            interior("x", f"{s}", x - 0.009, cy, cz, ww, wh)
            box(f"{s}_glass", x, cy, cz, 0.01, ww, wh, M["glass"])
            box(f"{s}_fl", x + 0.005, cy - ww / 2, cz, 0.012, 0.05, wh + 0.1, M["mullion"])
            box(f"{s}_fr", x + 0.005, cy + ww / 2, cz, 0.012, 0.05, wh + 0.1, M["mullion"])
            box(f"{s}_ft", x + 0.005, cy, cz + wh / 2, 0.012, ww + 0.09, 0.05, M["mullion"])
            box(f"{s}_sill", x + 0.01, cy, cz - wh / 2, 0.03, ww + 0.13, 0.055, M["stone"])
            box(f"{s}_lint", x + 0.015, cy, cz + wh / 2 + 0.085, 0.035, ww + 0.18, 0.10, M["stone"])
            box(f"{s}_mv", x + 0.004, cy, cz, 0.01, 0.026, wh, M["mullion"])
            for k in range(1, 3):
                box(f"{s}_mh{k}", x + 0.004, cy, sill + k * wh / 3, 0.01, ww, 0.026, M["mullion"])

    # ---------------- wide facade window (1st floor, -Y facade) ----------------
    if p["wide_window"]:
        y = -L / 2 - EPS
        fw, fh = 1.7, 0.72
        sill = FLOOR + 0.24
        cz = sill + fh / 2
        interior("y", "fac", XC, y + 0.009, cz, fw, fh)
        box("fac_glass", XC, y, cz, fw, 0.01, fh, M["glass"])
        box("fac_fl", XC - fw / 2, y - 0.005, cz, 0.05, 0.012, fh + 0.1, M["mullion"])
        box("fac_fr", XC + fw / 2, y - 0.005, cz, 0.05, 0.012, fh + 0.1, M["mullion"])
        box("fac_ft", XC, y - 0.005, cz + fh / 2, fw + 0.09, 0.012, 0.05, M["mullion"])
        box("fac_sill", XC, y - 0.01, cz - fh / 2, fw + 0.13, 0.03, 0.055, M["stone"])
        box("fac_lint", XC, y - 0.015, cz + fh / 2 + 0.085, fw + 0.18, 0.035, 0.10, M["stone"])
        for k in range(1, 6):
            box(f"fac_mv{k}", XC - fw / 2 + k * fw / 6, y - 0.004, cz, 0.026, 0.01, fh, M["mullion"])
        for k in range(1, 3):
            box(f"fac_mh{k}", XC, y - 0.004, sill + k * fh / 3, fw, 0.01, 0.026, M["mullion"])

    # ---------------- front: loading-bay annex (L2+) or ground-level double gate (L1) ----------------
    if p["front_annex"]:
        AW, AL, AH = 1.5, 1.4, FLOOR
        ax = X0 + AW / 2        # stays flush with the (new) left wall — unmoved relative to the body
        ay = -L / 2 - AL / 2
        box("annex", ax, ay, AH / 2, AW, AL, AH, M["brick"])
        box("annex_roof", ax, ay, AH + 0.045, AW + 0.14, AL + 0.14, 0.09, M["membrane"])
        coping("annex", ax, ay, AW + 0.14, AL + 0.14, AH + 0.09)
        ventilator("annex", ax - 0.30, ay + 0.20, AH + 0.09)
        afx = ax + AW / 2 + EPS
        box("dock", afx + 0.26, ay, 0.15, 0.52, AL, 0.30, M["concrete"])
        dw, dh = 0.85, 0.62
        dz = 0.30 + dh / 2
        box("bay_door", afx, ay, dz, 0.01, dw, dh, M["door"])
        box("bay_fl", afx + 0.005, ay - dw / 2, dz, 0.012, 0.06, dh + 0.08, M["mullion"])
        box("bay_fr", afx + 0.005, ay + dw / 2, dz, 0.012, 0.06, dh + 0.08, M["mullion"])
        box("bay_ft", afx + 0.005, ay, dz + dh / 2, 0.012, dw + 0.16, 0.06, M["mullion"])
        for k in range(1, 5):
            box(f"bay_slat_{k}", afx + 0.004, ay, 0.30 + k * dh / 5, 0.008, dw - 0.06, 0.018, M["darkmetal"])
        box("bay_canopy", afx + 0.16, ay, AH - 0.10, 0.36, dw + 0.3, 0.06, M["darkmetal"])
        # Personnel door: raised onto the dock platform (threshold at the platform top,
        # centred over it) rather than sitting at ground level beside it.
        dock_cx = afx + 0.26
        box("side_door", dock_cx, -L / 2 - EPS, 0.30 + 0.38, 0.34, 0.01, 0.76, M["darkmetal"])
    if p["gate"]:
        y = -L / 2 - EPS
        gw, gh = 1.30, 0.92        # double-width roller gate, ground level
        gx = -0.25 - WIDEN         # same offset from the left wall as L2's annex
        box("gate", gx, y, gh / 2, gw, 0.01, gh, M["door"])
        box("gate_fl", gx - gw / 2, y - 0.005, gh / 2, 0.06, 0.012, gh + 0.08, M["mullion"])
        box("gate_fr", gx + gw / 2, y - 0.005, gh / 2, 0.06, 0.012, gh + 0.08, M["mullion"])
        box("gate_ft", gx, y - 0.005, gh, gw + 0.16, 0.012, 0.06, M["mullion"])
        for k in range(1, 6):
            box(f"gate_slat_{k}", gx, y - 0.004, k * gh / 6, gw - 0.06, 0.008, 0.018, M["darkmetal"])
        box("side_door", 0.75, y, 0.38, 0.34, 0.01, 0.76, M["darkmetal"])

    # ---------------- chimney: seamless square base tower + plate + tapered stack ----------------
    if p["chimney"]:
        FY = L / 2 - TL / 2
        fx = 1.305
        S0, S1 = 0.48, 0.40
        BASE_S = S0 + 0.18
        BASE_TOP = H + PH + 0.25
        # one continuous square tower from the ground — no corbel seam
        sqcol("chimney_base", fx, FY, 0.0, BASE_TOP, BASE_S, BASE_S, M["brick"])
        sqcol("chimney_plate", fx, FY, BASE_TOP, BASE_TOP + 0.08, S0 + 0.30, S0 + 0.30, M["stone"])
        z0 = BASE_TOP + 0.08
        CH = p["chimney"]["top"]

        def side_at(z):
            return S0 + (S1 - S0) * (z - z0) / (CH - z0)

        sqcol("chimney", fx, FY, z0, CH, S0, S1, M["brick"])
        for j, z in enumerate(p["chimney"]["collars"]):
            s = side_at(z) + 0.10
            sqcol(f"chimney_ridge_{j}", fx, FY, z - 0.065, z + 0.065, s, s, M["stone"])
        tip_h = 0.5
        s_tip = side_at(CH - tip_h) + 0.07
        sqcol("chimney_tip", fx, FY, CH - tip_h + 0.035, CH + 0.035, s_tip, s_tip - 0.05, M["ink_black"])
        sqcol("chimney_tip_band", fx, FY, CH - tip_h - 0.04, CH - tip_h + 0.04, s_tip + 0.06, s_tip + 0.06, M["stone"])
        # Caged access ladder up the stack's +X face, from the roof line to below the cap.
        ladder_x = fx + BASE_S / 2 + 0.05
        ladder(ladder_x, FY, (RH_L3 + 0.15) if p["rear_annex"] else 1.0, BASE_TOP, cage_from=2.0)
        ladder(fx + S0 / 2 + 0.05, FY, BASE_TOP + 0.10, CH - tip_h - 0.10, cage_from=0.0)

        # ---- ink seams: Freestyle can't draw face-intersection contours, so add
        # thin unlit navy beads where the tower meets the wall and the roof slope.
        ink = bpy.data.materials.get("ink_seam")
        if ink is None:
            ink = bpy.data.materials.new("ink_seam")
        ink.use_nodes = True
        ib = ink.node_tree.nodes.get("Principled BSDF")
        ib.inputs["Base Color"].default_value = (0, 0, 0, 1)
        ib.inputs["Emission Color"].default_value = (0.012, 0.016, 0.045, 1)
        ib.inputs["Emission Strength"].default_value = 1.0
        y_seam = FY - BASE_S / 2                     # tower front face
        z_roofhit = H + 0.2 * PH                     # where that face exits the slope
        z_bot = 1.36 if p["rear_annex"] else 0.0     # L3: tower hidden inside annex below its roof
        b = box("seam_wall", X1, y_seam, (z_bot + z_roofhit) / 2, 0.034, 0.032, z_roofhit - z_bot)
        b.data.materials.append(ink)
        x0 = fx - BASE_S / 2                         # tower's -X face (inside the roof)
        b = box("seam_roof", (x0 + X1) / 2, y_seam, z_roofhit, (X1 - x0) + 0.03, 0.032, 0.032)
        b.data.materials.append(ink)

    # ---------------- L3: process annex at the BACK-RIGHT, poking right (+X) past the chimney ----------------
    if p["rear_annex"]:
        # footprint: attached to the +X wall at the far (+Y) end; chimney tower rises at its junction
        RX0, RX1 = 1.15, 2.75             # x span: from just inside the wall, poking right
        RY0, RY1 = L / 2 - 1.30, L / 2    # y span: back corner, clear of the last window column
        RH = RH_L3
        rcx, rcy = (RX0 + RX1) / 2, (RY0 + RY1) / 2
        box("rannex", rcx, rcy, RH / 2, RX1 - RX0, RY1 - RY0, RH, M["brick"])
        # flat roof frame with a glass skylight on the outboard (right) side, clear of the chimney tower
        box("rannex_roof", rcx, rcy, RH + 0.04, RX1 - RX0 + 0.14, RY1 - RY0 + 0.14, 0.08, M["membrane"])
        coping("rannex", rcx, rcy, RX1 - RX0 + 0.14, RY1 - RY0 + 0.14, RH + 0.08, skip_left=True)
        GX0, GX1 = 1.78, RX1 - 0.16       # skylight clear of the tower (tower ends at x=1.635)
        GY0, GY1 = RY0 + 0.16, RY1 - 0.16
        gcx, gcy = (GX0 + GX1) / 2, (GY0 + GY1) / 2
        gw2, gl2 = GX1 - GX0, GY1 - GY0
        box("rannex_glass_room", gcx, gcy, RH + 0.083, gw2, gl2, 0.006, M["interior"])
        box("rannex_glass", gcx, gcy, RH + 0.100, gw2, gl2, 0.012, M["glass"])
        for k in range(1, 3):
            box(f"rannex_mul_x{k}", GX0 + k * gw2 / 3, gcy, RH + 0.112, 0.03, gl2, 0.014, M["mullion"])
        box("rannex_mul_y", gcx, gcy, RH + 0.112, gw2, 0.03, 0.014, M["mullion"])
        # two silver pipes on the RIGHT (+X) face: out of the ground, up the face,
        # short elbow over the parapet, feeding into the skylight roof
        pr = 0.085
        riser_x = RX1 + 0.16
        for j, py in enumerate((rcy - 0.32, rcy + 0.28)):
            top_z = RH + 0.26 + j * 0.12          # hug the roof
            cyl(f"pipe_riser_{j}", riser_x, py, top_z / 2, pr, top_z, M["white_pipe"])
            sphere(f"pipe_elbow_a_{j}", riser_x, py, top_z, pr * 1.25, M["white_pipe"])
            for k, fz in enumerate((0.30, top_z * 0.62)):
                cyl(f"pipe_flange_{j}_{k}", riser_x, py, fz, pr * 1.40, 0.045, M["white_pipe"])
            box(f"pipe_foot_{j}", riser_x, py, 0.04, pr * 3.2, pr * 3.2, 0.08, M["concrete"])
            drop_x = GX1 - 0.18                    # just inside the skylight
            run = riser_x - drop_x
            cyl(f"pipe_run_{j}", riser_x - run / 2, py, top_z, pr, run, M["white_pipe"], axis='X')
            cyl(f"pipe_run_flange_{j}", riser_x - run / 2, py, top_z, pr * 1.40, 0.045, M["white_pipe"], axis='X')
            sphere(f"pipe_elbow_b_{j}", drop_x, py, top_z, pr * 1.25, M["white_pipe"])
            drop = top_z - RH - 0.06
            cyl(f"pipe_drop_{j}", drop_x, py, RH + 0.06 + drop / 2, pr, drop, M["white_pipe"])
        # ink flashing collar where the chimney tower pierces the annex roof
        ink = bpy.data.materials["ink_seam"]
        c = sqcol("seam_collar", 1.305, L / 2 - TL / 2, RH + 0.08, RH + 0.125, 0.66 + 0.055, 0.66 + 0.055, M["brick"])
        c.data.materials.clear()
        c.data.materials.append(ink)
        # one window on the annex front (-Y) face, outboard of the chimney tower
        wy = RY0 - EPS
        aww, awh = 0.50, 0.72
        acx = 2.18
        asill = 0.30
        acz = asill + awh / 2
        interior("y", "aw", acx, wy + 0.009, acz, aww, awh)
        box("aw_glass", acx, wy, acz, aww, 0.01, awh, M["glass"])
        box("aw_fl", acx - aww / 2, wy - 0.005, acz, 0.05, 0.012, awh + 0.1, M["mullion"])
        box("aw_fr", acx + aww / 2, wy - 0.005, acz, 0.05, 0.012, awh + 0.1, M["mullion"])
        box("aw_ft", acx, wy - 0.005, acz + awh / 2, aww + 0.09, 0.012, 0.05, M["mullion"])
        box("aw_sill", acx, wy - 0.01, acz - awh / 2, aww + 0.13, 0.03, 0.055, M["stone"])
        box("aw_lint", acx, wy - 0.015, acz + awh / 2 + 0.085, aww + 0.18, 0.035, 0.10, M["stone"])
        box("aw_mv", acx, wy - 0.004, acz, 0.026, 0.01, awh, M["mullion"])
        for k in range(1, 3):
            box(f"aw_mh{k}", acx, wy - 0.004, asill + k * awh / 3, aww, 0.01, 0.026, M["mullion"])

    details(p, N, L)
    back_side(p, N, L)
    return {"level": level, "bays": N, "objects": len(col.objects)}
