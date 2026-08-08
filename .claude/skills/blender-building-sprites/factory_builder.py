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
    "brick":    (0.318, 0.118, 0.082),
    "roof":     (0.208, 0.262, 0.318),
    "glass":    (0.055, 0.075, 0.140),
    "mullion":  (0.780, 0.760, 0.700),
    "concrete": (0.560, 0.570, 0.560),
    "door":     (0.330, 0.380, 0.420),
    "darkmetal":(0.160, 0.190, 0.230),
    "ink_black":(0.028, 0.032, 0.055),
    "silver":   (0.700, 0.720, 0.760),
}

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
        bm.faces.new(vf)
        bm.faces.new(list(reversed(vb)))
        for a in range(3):
            b = (a + 1) % 3
            bm.faces.new([vf[a], vf[b], vb[b], vb[a]])
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        bm.to_mesh(m); bm.free()
        new_obj(f"tooth_{i}", m, M["roof"])

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
            box(f"{s}_glass", x, cy, cz, 0.01, ww, wh, M["glass"])
            box(f"{s}_fl", x + 0.005, cy - ww / 2, cz, 0.012, 0.05, wh + 0.1, M["mullion"])
            box(f"{s}_fr", x + 0.005, cy + ww / 2, cz, 0.012, 0.05, wh + 0.1, M["mullion"])
            box(f"{s}_ft", x + 0.005, cy, cz + wh / 2, 0.012, ww + 0.09, 0.05, M["mullion"])
            box(f"{s}_sill", x + 0.01, cy, cz - wh / 2, 0.03, ww + 0.13, 0.055, M["mullion"])
            box(f"{s}_mv", x + 0.004, cy, cz, 0.01, 0.026, wh, M["mullion"])
            for k in range(1, 3):
                box(f"{s}_mh{k}", x + 0.004, cy, sill + k * wh / 3, 0.01, ww, 0.026, M["mullion"])

    # ---------------- wide facade window (1st floor, -Y facade) ----------------
    if p["wide_window"]:
        y = -L / 2 - EPS
        fw, fh = 1.7, 0.72
        sill = FLOOR + 0.24
        cz = sill + fh / 2
        box("fac_glass", XC, y, cz, fw, 0.01, fh, M["glass"])
        box("fac_fl", XC - fw / 2, y - 0.005, cz, 0.05, 0.012, fh + 0.1, M["mullion"])
        box("fac_fr", XC + fw / 2, y - 0.005, cz, 0.05, 0.012, fh + 0.1, M["mullion"])
        box("fac_ft", XC, y - 0.005, cz + fh / 2, fw + 0.09, 0.012, 0.05, M["mullion"])
        box("fac_sill", XC, y - 0.01, cz - fh / 2, fw + 0.13, 0.03, 0.055, M["mullion"])
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
        box("annex_roof", ax, ay, AH + 0.045, AW + 0.14, AL + 0.14, 0.09, M["roof"])
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
        sqcol("chimney_plate", fx, FY, BASE_TOP, BASE_TOP + 0.08, S0 + 0.30, S0 + 0.30, M["darkmetal"])
        z0 = BASE_TOP + 0.08
        CH = p["chimney"]["top"]

        def side_at(z):
            return S0 + (S1 - S0) * (z - z0) / (CH - z0)

        sqcol("chimney", fx, FY, z0, CH, S0, S1, M["brick"])
        for j, z in enumerate(p["chimney"]["collars"]):
            s = side_at(z) + 0.10
            sqcol(f"chimney_ridge_{j}", fx, FY, z - 0.065, z + 0.065, s, s, M["brick"])
        tip_h = 0.5
        s_tip = side_at(CH - tip_h) + 0.07
        sqcol("chimney_tip", fx, FY, CH - tip_h + 0.035, CH + 0.035, s_tip, s_tip - 0.05, M["ink_black"])

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
        RH = 1.3
        rcx, rcy = (RX0 + RX1) / 2, (RY0 + RY1) / 2
        box("rannex", rcx, rcy, RH / 2, RX1 - RX0, RY1 - RY0, RH, M["brick"])
        # flat roof frame with a glass skylight on the outboard (right) side, clear of the chimney tower
        box("rannex_roof", rcx, rcy, RH + 0.04, RX1 - RX0 + 0.14, RY1 - RY0 + 0.14, 0.08, M["roof"])
        GX0, GX1 = 1.78, RX1 - 0.16       # skylight clear of the tower (tower ends at x=1.635)
        GY0, GY1 = RY0 + 0.16, RY1 - 0.16
        gcx, gcy = (GX0 + GX1) / 2, (GY0 + GY1) / 2
        gw2, gl2 = GX1 - GX0, GY1 - GY0
        box("rannex_glass", gcx, gcy, RH + 0.085, gw2, gl2, 0.012, M["glass"])
        for k in range(1, 3):
            box(f"rannex_mul_x{k}", GX0 + k * gw2 / 3, gcy, RH + 0.09, 0.03, gl2, 0.014, M["mullion"])
        box("rannex_mul_y", gcx, gcy, RH + 0.09, gw2, 0.03, 0.014, M["mullion"])
        # two silver pipes on the RIGHT (+X) face: out of the ground, up the face,
        # short elbow over the parapet, feeding into the skylight roof
        pr = 0.085
        riser_x = RX1 + 0.16
        for j, py in enumerate((rcy - 0.32, rcy + 0.28)):
            top_z = RH + 0.26 + j * 0.12          # hug the roof
            cyl(f"pipe_riser_{j}", riser_x, py, top_z / 2, pr, top_z, M["silver"])
            sphere(f"pipe_elbow_a_{j}", riser_x, py, top_z, pr * 1.25, M["silver"])
            drop_x = GX1 - 0.18                    # just inside the skylight
            run = riser_x - drop_x
            cyl(f"pipe_run_{j}", riser_x - run / 2, py, top_z, pr, run, M["silver"], axis='X')
            sphere(f"pipe_elbow_b_{j}", drop_x, py, top_z, pr * 1.25, M["silver"])
            drop = top_z - RH - 0.06
            cyl(f"pipe_drop_{j}", drop_x, py, RH + 0.06 + drop / 2, pr, drop, M["silver"])
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
        box("aw_glass", acx, wy, acz, aww, 0.01, awh, M["glass"])
        box("aw_fl", acx - aww / 2, wy - 0.005, acz, 0.05, 0.012, awh + 0.1, M["mullion"])
        box("aw_fr", acx + aww / 2, wy - 0.005, acz, 0.05, 0.012, awh + 0.1, M["mullion"])
        box("aw_ft", acx, wy - 0.005, acz + awh / 2, aww + 0.09, 0.012, 0.05, M["mullion"])
        box("aw_sill", acx, wy - 0.01, acz - awh / 2, aww + 0.13, 0.03, 0.055, M["mullion"])
        box("aw_mv", acx, wy - 0.004, acz, 0.026, 0.01, awh, M["mullion"])
        for k in range(1, 3):
            box(f"aw_mh{k}", acx, wy - 0.004, asill + k * awh / 3, aww, 0.01, 0.026, M["mullion"])

    return {"level": level, "bays": N, "objects": len(col.objects)}
