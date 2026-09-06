# sprite_kit.py — shared primitives, materials and ASSEMBLIES for building sprites.
#
# Every new building builder starts here. Load it first, then your builder:
#   exec(open(".../sprite_kit.py").read())
#   exec(open(".../<building>_builder.py").read()); build_<building>(2)
#
# The geometry in this file is extracted verbatim from the approved industrial-goods
# factory and furnace, including the fixes each one cost. Do not re-derive these shapes;
# change a PARAMETER, or if the shape itself is wrong, fix it HERE so every building
# inherits the fix.
#
# Usage: build a Kit bound to your collection, then call primitives/assemblies on it.
#   K = Kit(col)
#   K.window("w0", "+X", (x, y, z), 0.50, 0.72, cols=2, rows=3)

import bpy
import bmesh


def absf_(v):
    return v if v >= 0 else -v
import math

EPS = 0.015                      # applied detail sits this far proud of a face


# ============================== MATERIALS ==============================
# Raw palette. Flat Principled, roughness 1, specular 0 (sheen breaks stylize.py's
# blue-dominant glass test AND the cel look).
PALETTE = {
    "brick":     (0.318, 0.118, 0.082),   # the one warm accent on a brick building
    "steel_navy":(0.150, 0.185, 0.240),   # dark clad hall
    "annex_grey":(0.175, 0.190, 0.205),   # dark grey secondary block
    "stack_grey":(0.330, 0.355, 0.395),   # chimney shafts, ducts
    "tank_grey": (0.400, 0.435, 0.490),   # process vessels
    "roof":      (0.208, 0.262, 0.318),   # slate
    "concrete":  (0.560, 0.570, 0.560),
    "glass":     (0.055, 0.075, 0.140),   # near-navy; stylize.py leaves it unstippled
    "mullion":   (0.780, 0.760, 0.700),   # cream frames
    "door":      (0.330, 0.380, 0.420),
    "darkmetal": (0.160, 0.190, 0.230),   # scaffolding, stairs, walkways
    "silver":    (0.700, 0.720, 0.760),   # pipework
    "ink_black": (0.028, 0.032, 0.055),   # stack tips, openings
    "heat_red":  (0.430, 0.120, 0.065),   # painted hot zones (flat)
    # A graded earth RAMP, not two tones — with no cast shadows in this style, a pit only
    # reads as deep if every bench down is a clear step darker. Kit.pit_mats() picks the
    # right subset for a given bench count.
    # These five are NOT eyeballed. Under this rig's AgX view transform, a VERTICAL face
    # (which is what a pit wall shows) responds like this — measured, not guessed:
    #     base 0.02->L0  0.05->L34  0.09->L80  0.14->L121  0.20->L147  0.28->L168  0.38->L176
    # i.e. it saturates above ~0.28 and everything brighter renders as the same cream. A
    # plausible-looking light-earth ramp (0.35 down to 0.10) therefore lands its top three
    # tones inside 8 luma of each other and the terracing vanishes. These are that curve
    # INVERTED for evenly spaced output luma ~172/143/114/85/56.
    # KEEP ANY NEW EARTH TONE INSIDE 0.05-0.30. Note this ceiling is why `concrete` (0.56)
    # cannot be used for a yard-sized apron — it renders as a blank white plate.
    "earth":     (0.310, 0.273, 0.226),   # surface / rim
    "earth2":    (0.192, 0.169, 0.140),
    "earth3":    (0.132, 0.116, 0.096),
    "earth4":    (0.095, 0.084, 0.069),
    "earth_deep":(0.070, 0.062, 0.051),   # pit floor, deepest strata
    "ore":       (0.240, 0.105, 0.070),   # exposed METAL seam — a warm accent. Held under
                                          # the 0.28 ceiling too: at 0.37 the red channel
                                          # saturates and the seam glows like neon.
    "coal":      (0.032, 0.030, 0.036),   # coal seam / worked pit bottom. MEASURED: it has
                                          # to land clearly below the navy ink (L70) or the
                                          # band reads as a fat outline, not as coal. 0.058
                                          # rendered at L72 and did exactly that; this sits
                                          # near L30, so coal masses swallow their own ink.
    "coal2":     (0.058, 0.055, 0.062),   # the measure just above it — reads as coaly shale
                                          # and keeps the black zone from being one flat mass.
    # Mid greys for BIG surfaces. `concrete` (0.56) and `tank_grey` (0.40) are both past the
    # 0.28 saturation ceiling — fine on a door frame, but a cooling-tower-sized area of either
    # renders as a blank white plate. These sit just under it so a large shell still shades.
    "pad":       (0.170, 0.176, 0.172),   # switchyard concrete. A neutral mid grey chosen to
                                          # sit BETWEEN the pale walls (~L170) and the dark
                                          # roof decks (~L88): `concrete` at 0.56 is past the
                                          # saturation ceiling and a yard-sized plate of it
                                          # would out-bright the buildings standing on it.
    "chalk":     (0.318, 0.308, 0.284),   # white building walls. Sits just above `shell` so
                                          # the buildings still read lighter than the tower,
                                          # and low enough that lit and shaded faces separate
                                          # (~L170 vs ~L140) — pushed to a true paper white the
                                          # walls flatten and the massing stops reading.
    "shell":     (0.275, 0.270, 0.256),   # cooling-tower concrete — the composition's LIGHT
    "steel_mid": (0.212, 0.222, 0.244),   # transformer tanks, switchgear
    # ...and its DARK. Everything from 0.14 up renders between L120 and L176 (the AgX curve
    # again), so a plant built only from the existing wall/roof greys measured a 26-luma
    # spread — one flat mid mass. A big flat roof is the natural place to put the dark tier.
    # A flat roof is the one surface pointing at the sky, so it CATCHES the light — and in
    # this print pass lit faces stay clean. At 0.082 it rendered luma 0.363, which after
    # stylize's contrast lands at darkness 0.37: inside the stipple band, and the only large
    # surface in it, so the whole sprite read as "a dotted roof". Lifted clear of the t_hi
    # threshold (rendered luma must exceed 0.50) so it prints clean. Density does not taper
    # inside a band — a surface is stippled or it is not — so half-measures here do nothing.
    "deck":      (0.196, 0.206, 0.228),   # flat-roof deck, LIT: reads clean, no halftone
    # POWER livery. Yellow is the game's power colour, so it is a signal, not decoration:
    # a band or two per sprite. Red held just under the 0.28 ceiling keeps it a dusky
    # mustard — push it higher and the channel saturates into a hazard-tape orange.
    "mustard":   (0.268, 0.181, 0.034),
    # CONSTRUCTION yellow — brighter and more saturated than the power-livery mustard, which
    # is deliberately dusky because it is a signal there. Plant yellow has to look like paint
    # on a machine, so it sits well up the curve (measured: 0.48 -> L171 on a vertical face).
    "hi_vis":    (0.520, 0.352, 0.045),
    "hi_vis_lo": (0.300, 0.196, 0.028),   # its shaded partner, for gloss banding
    # Container blue. The only cool chroma in the set; it reads at once against the yellows
    # and the rust, which is the point of a container yard.
    "cont_blue": (0.105, 0.205, 0.355),
    # ---- process-plant steels (refineries). Ported from the superseded refinery_kit fork,
    # but RE-TUNED to this rig: that fork measured its own headless --factory-startup scene
    # (0.40 -> L148) which does not match this one, where 0.28 is already near the ceiling.
    # Values below are first guesses on THIS curve and were then corrected by measurement.
    "plant_steel":  (0.205, 0.218, 0.242),   # vessel shells, columns, silos
    "plant_steel2": (0.132, 0.140, 0.158),   # drums, bullets, secondary vessels
    "flue_steel":   (0.262, 0.272, 0.292),   # flues read as the brightest steel
    "apron":        (0.095, 0.099, 0.107),   # yard slabs and bund walls — deliberately the
                                             # DARK base that lets the steels read as metal.
                                             # MEASURED on this rig (vertical faces): steels
                                             # land at L132/L108, flues L145, purple L102 at
                                             # rgb(118,92,157) — the game's CAT_REFINERY hue —
                                             # and the yard needs to sit clearly under all of
                                             # them, so ~L92.
    # ---- MEASURED ON THIS RIG (2026-07-31), -Y vertical cube faces, centroid-sampled after
    # ray-casting each face so the reading cannot land on ink or a neighbour:
    #     0.150->L123  0.170->L120  0.238->L134  0.268->L140  0.318->L151  0.400->L160
    #     0.480->L171  0.620->L181  0.700->L188  0.800->L191   (top faces run ~7 higher)
    # The response is COMPRESSIVE but it does NOT saturate at 0.28 — the earth-ramp note above
    # is specific to pit-wall orientations and must not be generalised. Above ~0.6 it does
    # flatten: 0.62 and 0.80 land 10 luma apart, so there is no headroom past `silver`.
    "cream":      (0.330, 0.306, 0.246),   # cream-concrete apron deck (~L150, warm). Sits a
                                           # hue apart from `shell` (neutral, ~L141) so the
                                           # flat tank standing on it separates by TINT as
                                           # well as value — 9 luma alone would fuse.
    "cream_deep": (0.142, 0.130, 0.104),   # its kerb (~L110): the slab needs an edge or the
                                           # apron is one flat diamond.
    "white_wall": (0.520, 0.514, 0.500),   # white main building (~L173). Deliberately NOT
                                           # higher: `silver` pipework lands at L188 and runs
                                           # across these walls, and above ~0.60 the curve
                                           # flattens so a brighter wall buys nothing but a
                                           # lost pipe.
    # The game's refinery-category purple (#8E5BC0, CAT_REFINERY in tile_view_data.gd).
    # The ONLY chroma on either refinery, so one band carries the whole signal.
    "purple":       (0.178, 0.074, 0.330),
    "purple_deep":  (0.098, 0.042, 0.182),
}

# Semantic roles → palette key. Prefer these in builders: `K.mat("pipe")` says what the
# thing IS, so a palette retune lands everywhere at once.
ROLES = {
    "pipe": "silver", "duct": "stack_grey", "stack": "stack_grey",
    "stair": "darkmetal", "walkway": "darkmetal", "scaffold": "darkmetal",
    "rail": "darkmetal", "handrail": "darkmetal",
    "wall_brick": "brick", "wall_steel": "steel_navy", "wall_grey": "annex_grey",
    "window_glass": "glass", "window_frame": "mullion",
    "door_leaf": "door", "opening": "ink_black",
    "vessel": "tank_grey", "slab": "concrete", "hot": "heat_red",
    "ground": "earth", "ground2": "earth2", "ground3": "earth3",
    "ground4": "earth4", "ground_deep": "earth_deep", "ore_seam": "ore",
    "coal_seam": "coal", "coal_upper": "coal2",
    "wall_shell": "shell", "wall_pale": "chalk", "yard_pad": "pad",
    "wall_bright": "white_wall", "slab_cream": "cream", "slab_kerb": "cream_deep",
    "gear": "steel_mid",
    "roof_deck": "deck",
    "power_accent": "mustard", "plant_yellow": "hi_vis", "box_blue": "cont_blue",
    "column": "plant_steel", "drum": "plant_steel2", "flue": "flue_steel",
    "yard": "apron", "accent": "purple", "accent_deep": "purple_deep",
}


def _flat_mat(name):
    mt = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    mt.use_nodes = True
    b = mt.node_tree.nodes.get("Principled BSDF")
    b.inputs["Base Color"].default_value = (*PALETTE[name], 1)
    b.inputs["Roughness"].default_value = 1.0
    if "Specular IOR Level" in b.inputs:
        b.inputs["Specular IOR Level"].default_value = 0.0
    return mt


def _emissive(name, colour, strength):
    mt = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    mt.use_nodes = True
    b = mt.node_tree.nodes.get("Principled BSDF")
    b.inputs["Base Color"].default_value = (0, 0, 0, 1)
    b.inputs["Emission Color"].default_value = (*colour, 1)
    b.inputs["Emission Strength"].default_value = strength
    return mt


def build_materials():
    """All materials, keyed by palette name plus `ember` and `seam`."""
    M = {n: _flat_mat(n) for n in PALETTE}
    # Glowing fire accent — emissive so heat reads constant-bright on any face.
    M["ember"] = _emissive("ember", (0.820, 0.300, 0.085), 1.45)
    # Unlit navy seam bead. Freestyle cannot ink the INTERSECTION of two separate meshes,
    # so every metal-to-metal joint needs one of these explicitly.
    M["seam"] = _emissive("ink_seam", (0.012, 0.016, 0.045), 1.0)
    return M


# ============================== RENDER RIG ==============================
def setup_rig(ortho_scale=11.0, target=(0.0, 0.55, 2.25), res=1024):
    """The locked style contract. Idempotent — call at the top of every build_*() so a
    restarted Blender session can never leave stale camera/shadow state in a render."""
    import mathutils
    scene = bpy.context.scene
    scene.render.engine = 'BLENDER_EEVEE'
    scene.render.film_transparent = True
    scene.render.resolution_x = res
    scene.render.resolution_y = res
    scene.render.use_freestyle = True
    scene.render.line_thickness_mode = 'ABSOLUTE'

    cam = bpy.data.objects.get("Camera")
    cam.data.type = 'ORTHO'
    cam.rotation_euler = (math.radians(54.736), 0.0, math.radians(45.0))   # true isometric
    cam.location = mathutils.Vector(target) + mathutils.Vector((1, -1, 1)).normalized() * 26.0
    cam.data.ortho_scale = ortho_scale

    sun = bpy.data.objects.get("Light")
    sun.data.use_shadow = False          # NEVER cast shadows in this style
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
    # FINE INK. Freestyle thickness is per-LINESET, not per-object, so a transformer's fins and
    # bushings carry the same 2.4px line as a whole building — and a cluster of small equipment
    # then dissolves into one navy smudge at sprite scale. Objects linked into FINE_INK are cut
    # out of the main lineset and drawn by a thinner one instead. The 7px external contour is
    # deliberately left alone: that is the sprite's outer silhouette, and punching a hole in it
    # would leave the compound with no outline at all.
    fine = bpy.data.collections.get("FINE_INK")
    if fine is None:
        fine = bpy.data.collections.new("FINE_INK")
        bpy.context.scene.collection.children.link(fine)
    ink = fs.linesets["ink"]
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
    fs.linesets["contour"].linestyle.color = (0.045, 0.055, 0.11)
    fs.linesets["contour"].linestyle.thickness = 7.0

    world = scene.world
    if world and world.use_nodes:
        bg = world.node_tree.nodes.get("Background")
        if bg:
            bg.inputs[0].default_value = (1, 1, 1, 1)
            bg.inputs[1].default_value = 0.75


def open_collection(name):
    """Fresh collection for this building; every OTHER BLDG_* is hidden so one render
    shows one building."""
    for other in bpy.data.collections:
        if other.name.startswith("BLDG_") and other.name != name:
            other.hide_render = True
            other.hide_viewport = True
    col = bpy.data.collections.get(name)
    if col is None:
        col = bpy.data.collections.new(name)
        bpy.context.scene.collection.children.link(col)
    col.hide_render = False
    col.hide_viewport = False
    for ob in list(col.objects):
        bpy.data.objects.remove(ob, do_unlink=True)
    fine = bpy.data.collections.get("FINE_INK")
    if fine is not None:
        for ob in list(fine.objects):
            fine.objects.unlink(ob)        # unlink only: the object lives in its BLDG_ collection
    return col


class Kit:
    """Primitives + assemblies bound to one collection."""

    def __init__(self, collection):
        self.col = collection
        self.M = build_materials()
        self.fine_col = bpy.data.collections.get("FINE_INK")
        self._fine_mode = False

    def mat(self, role_or_name):
        return self.M[ROLES.get(role_or_name, role_or_name)]

    # ------------------------- primitives -------------------------
    def obj(self, name, mesh, mat=None, smooth=False):
        ob = bpy.data.objects.new(name, mesh)
        self.col.objects.link(ob)
        if mat is not None:
            ob.data.materials.append(mat if not isinstance(mat, str) else self.mat(mat))
        # Flat by default (cel faces). `smooth` rounds the SIDES of a revolved form only:
        # quads = side facets → smooth; n-gon caps stay flat so rims keep a hard ink edge.
        for poly in ob.data.polygons:
            poly.use_smooth = smooth and len(poly.vertices) == 4
        if self._fine_mode and self.fine_col is not None:
            self.fine_col.objects.link(ob)      # thinner Freestyle line — see setup_rig
        return ob

    def box(self, name, cx, cy, cz, sx, sy, sz, mat=None):
        m = bpy.data.meshes.new(name)
        bm = bmesh.new()
        bmesh.ops.create_cube(bm, size=1.0)
        bmesh.ops.scale(bm, vec=(sx, sy, sz), verts=bm.verts)
        bmesh.ops.translate(bm, vec=(cx, cy, cz), verts=bm.verts)
        bm.to_mesh(m); bm.free()
        return self.obj(name, m, mat)

    def rotbox(self, name, cx, cy, cz, sx, sy, sz, mat, axis, angle_deg):
        """Box rotated about a GLOBAL axis. Sign trap: a Y-long box rotated about X by
        -angle ramps DOWNHILL toward +Y; use +angle for uphill."""
        import mathutils
        m = bpy.data.meshes.new(name)
        bm = bmesh.new()
        bmesh.ops.create_cube(bm, size=1.0)
        bmesh.ops.scale(bm, vec=(sx, sy, sz), verts=bm.verts)
        bmesh.ops.rotate(bm, cent=(0, 0, 0),
                         matrix=mathutils.Matrix.Rotation(math.radians(angle_deg), 3, axis),
                         verts=bm.verts)
        bmesh.ops.translate(bm, vec=(cx, cy, cz), verts=bm.verts)
        bm.to_mesh(m); bm.free()
        return self.obj(name, m, mat)

    def prism(self, name, origin, tdir, profile, width, mat):
        """Extrude a SIDE PROFILE — (along, up) points in the vertical plane through the
        horizontal direction `tdir` — across `width`. Use for inclined members that need a
        FLAT foot or a VERTICAL end cut; an oriented box caps both ends perpendicular to
        the run, leaving a knife-edge base and corners driven through whatever it meets."""
        import mathutils
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
        for i in range(len(profile)):
            j = (i + 1) % len(profile)
            bm.faces.new([fa[i], fa[j], fb[j], fb[i]])
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        bm.to_mesh(m); bm.free()
        return self.obj(name, m, mat)

    def sqcol(self, name, cx, cy, z0, z1, side0, side1, mat):
        """Axis-aligned square column tapering side0→side1."""
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
        return self.obj(name, m, mat)

    def cyl(self, name, cx, cy, cz, r, depth, mat, axis='Z', segments=32, smooth=True):
        import mathutils
        m = bpy.data.meshes.new(name)
        bm = bmesh.new()
        bmesh.ops.create_cone(bm, cap_ends=True, segments=segments, radius1=r, radius2=r, depth=depth)
        if axis == 'Y':
            bmesh.ops.rotate(bm, cent=(0, 0, 0), matrix=mathutils.Matrix.Rotation(math.radians(90), 3, 'X'), verts=bm.verts)
        elif axis == 'X':
            bmesh.ops.rotate(bm, cent=(0, 0, 0), matrix=mathutils.Matrix.Rotation(math.radians(90), 3, 'Y'), verts=bm.verts)
        bmesh.ops.translate(bm, vec=(cx, cy, cz), verts=bm.verts)
        bm.to_mesh(m); bm.free()
        return self.obj(name, m, mat, smooth)

    def cone(self, name, cx, cy, cz, r0, r1, depth, mat, segments=32, smooth=True):
        m = bpy.data.meshes.new(name)
        bm = bmesh.new()
        bmesh.ops.create_cone(bm, cap_ends=True, segments=segments, radius1=r0, radius2=r1, depth=depth)
        bmesh.ops.translate(bm, vec=(cx, cy, cz), verts=bm.verts)
        bm.to_mesh(m); bm.free()
        return self.obj(name, m, mat, smooth)

    def oval_cone(self, name, cx, cy, z0, z1, u, ax0, ay0, ax1, ay1, mat, seg=32):
        """Cone with an ELLIPTICAL section: semi-axis ax along horizontal unit `u`, ay
        across, lerping z0→z1."""
        import mathutils
        U = mathutils.Vector((u[0], u[1], 0.0)).normalized()
        V = mathutils.Vector((-U.y, U.x, 0.0))
        m = bpy.data.meshes.new(name)
        bm = bmesh.new()
        rings = []
        for (z, ax, ay) in ((z0, ax0, ay0), (z1, ax1, ay1)):
            rings.append([bm.verts.new(mathutils.Vector((cx, cy, z))
                                       + U * (ax * math.cos(2 * math.pi * k / seg))
                                       + V * (ay * math.sin(2 * math.pi * k / seg)))
                          for k in range(seg)])
        for k in range(seg):
            k2 = (k + 1) % seg
            bm.faces.new([rings[0][k], rings[0][k2], rings[1][k2], rings[1][k]])
        bm.faces.new(list(reversed(rings[0])))
        bm.faces.new(rings[1])
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        bm.to_mesh(m); bm.free()
        return self.obj(name, m, mat, True)

    def sphere(self, name, cx, cy, cz, r, mat):
        m = bpy.data.meshes.new(name)
        bm = bmesh.new()
        bmesh.ops.create_uvsphere(bm, u_segments=24, v_segments=16, radius=r)
        bmesh.ops.translate(bm, vec=(cx, cy, cz), verts=bm.verts)
        bm.to_mesh(m); bm.free()
        ob = self.obj(name, m, mat)
        for poly in ob.data.polygons:
            poly.use_smooth = True
        return ob

    def dircyl(self, name, p0, p1, r, mat, segments=24, smooth=True):
        """Cylinder from p0 to p1, any direction."""
        import mathutils
        a, b = mathutils.Vector(p0), mathutils.Vector(p1)
        d = b - a
        m = bpy.data.meshes.new(name)
        bm = bmesh.new()
        bmesh.ops.create_cone(bm, cap_ends=True, segments=segments, radius1=r, radius2=r, depth=d.length)
        rot = mathutils.Vector((0, 0, 1)).rotation_difference(d.normalized()).to_matrix()
        bmesh.ops.rotate(bm, cent=(0, 0, 0), matrix=rot, verts=bm.verts)
        bmesh.ops.translate(bm, vec=(a + b) / 2, verts=bm.verts)
        bm.to_mesh(m); bm.free()
        return self.obj(name, m, mat, smooth)

    def dirbox(self, name, p0, p1, w, h, mat):
        """Slab running p0→p1, `w` across, `h` thick."""
        import mathutils
        a, b = mathutils.Vector(p0), mathutils.Vector(p1)
        d = b - a
        m = bpy.data.meshes.new(name)
        bm = bmesh.new()
        bmesh.ops.create_cube(bm, size=1.0)
        bmesh.ops.scale(bm, vec=(w, d.length, h), verts=bm.verts)
        rot = mathutils.Vector((0, 1, 0)).rotation_difference(d.normalized()).to_matrix()
        bmesh.ops.rotate(bm, cent=(0, 0, 0), matrix=rot, verts=bm.verts)
        bmesh.ops.translate(bm, vec=(a + b) / 2, verts=bm.verts)
        bm.to_mesh(m); bm.free()
        return self.obj(name, m, mat)

    def sweep(self, name, pts, r, mat, seg=24):
        """Smooth tube along `pts`, using a PARALLEL-TRANSPORTED frame: picking a fresh
        perpendicular per point flips when the tangent passes vertical and twists the tube."""
        import mathutils
        P = [mathutils.Vector(q) for q in pts]
        n = len(P)
        tans = []
        for i in range(n):
            t = P[1] - P[0] if i == 0 else (P[-1] - P[-2] if i == n - 1 else P[i + 1] - P[i - 1])
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
            rings.append([bm.verts.new(P[i] + a * (r * math.cos(2 * math.pi * k / seg))
                                       + b * (r * math.sin(2 * math.pi * k / seg)))
                          for k in range(seg)])
        for i in range(n - 1):
            for k in range(seg):
                k2 = (k + 1) % seg
                bm.faces.new([rings[i][k], rings[i][k2], rings[i + 1][k2], rings[i + 1][k]])
        bm.faces.new(list(reversed(rings[0])))
        bm.faces.new(rings[-1])
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        bm.to_mesh(m); bm.free()
        return self.obj(name, m, mat, True)

    def washer(self, name, c, axis, r_in, r_out, thick, mat, seg=28):
        """Annular ring — frames a pipe where it passes through structure, so the pipe
        reads as going THROUGH a fitted opening rather than a bar through a pipe."""
        import mathutils
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
                R[(side, which)] = [bm.verts.new(C + A * t + U * (r * math.cos(2 * math.pi * k / seg))
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
        return self.obj(name, m, mat)

    def seam(self, name, cx, cy, cz, r, axis='Z', t=0.035):
        """Thin unlit-navy band marking a metal-to-metal joint."""
        return self.cyl(name, cx, cy, cz, r, t, self.M["seam"], axis=axis, segments=28)

    def seam_bar(self, name, cx, cy, cz, sx, sy, sz):
        """Straight seam bead (wall/roof junctions). On a SLOPED eave use rotbox at the
        roof's own angle — a level bar pokes out wherever the roof has dropped below it."""
        return self.box(name, cx, cy, cz, sx, sy, sz, self.M["seam"])

    @staticmethod
    def hermite(p0, p1, m0, m1, steps=18):
        out = []
        for i in range(steps + 1):
            t = i / steps
            t2, t3 = t * t, t * t * t
            h00, h10 = 2 * t3 - 3 * t2 + 1, t3 - 2 * t2 + t
            h01, h11 = -2 * t3 + 3 * t2, t3 - t2
            out.append(tuple(h00 * p0[k] + h10 * m0[k] + h01 * p1[k] + h11 * m1[k] for k in range(3)))
        return out

    # ------------------------- PIPES -------------------------
    def elbow(self, name, corner, d0, d1, r, bend, mat, steps=10):
        """Quarter-turn swept bend tangent to both runs meeting at `corner`. Pipes TURN
        instead of meeting in a ball."""
        import mathutils
        C0 = mathutils.Vector(corner)
        D0 = mathutils.Vector(d0).normalized()
        D1 = mathutils.Vector(d1).normalized()
        p_start = C0 - D0 * bend
        centre = p_start + D1 * bend
        u, v = p_start - centre, D0 * bend
        pts = [tuple(centre + u * math.cos((math.pi / 2) * i / steps) + v * math.sin((math.pi / 2) * i / steps))
               for i in range(steps + 1)]
        return self.sweep(name, pts, r, mat)

    def pipe_run(self, name, waypoints, r, mat=None, bend=0.28, ends=("", "")):
        """Axis-aligned pipe route through `waypoints`, with a quarter-bend elbow at every
        corner and the adjoining straights SHORTENED by the bend radius so they meet it
        cleanly. `ends` is (start_kind, end_kind), each of:
            ""        nothing (the run dies inside a shell — most common)
            "collar"  penetration ring, for where the pipe enters a wall/shell
            "cap"     flat closing disc
            "flange"  raised rim
        Reminder: terminate runs INSIDE the vessel they feed. A run ended past the far wall
        pokes out the other side into open air."""
        import mathutils
        mat = mat if mat is not None else self.mat("pipe")
        P = [mathutils.Vector(p) for p in waypoints]
        dirs = [(P[i + 1] - P[i]).normalized() for i in range(len(P) - 1)]
        made = []
        for i in range(len(P) - 1):
            a = P[i] + (dirs[i] * bend if i > 0 else mathutils.Vector((0, 0, 0)))
            b = P[i + 1] - (dirs[i] * bend if i < len(P) - 2 else mathutils.Vector((0, 0, 0)))
            if (b - a).length > 1e-4:
                made.append(self.dircyl(f"{name}_seg{i}", a, b, r, mat))
        for i in range(1, len(P) - 1):
            made.append(self.elbow(f"{name}_elb{i}", P[i], dirs[i - 1], dirs[i], r, bend, mat))
        for idx, kind in ((0, ends[0]), (-1, ends[1])):
            if not kind:
                continue
            pt = P[idx]
            d = dirs[0] if idx == 0 else dirs[-1]
            made.append(self.pipe_end(f"{name}_end{idx}", pt, d, r, kind, mat))
        return made

    def pipe_end(self, name, point, direction, r, kind="collar", mat=None):
        mat = mat if mat is not None else self.mat("pipe")
        if kind == "collar":
            return self.washer(name, point, direction, r + 0.02, r + 0.09, 0.05, self.M["seam"])
        if kind == "flange":
            return self.washer(name, point, direction, r + 0.01, r + 0.12, 0.06, self.M["darkmetal"])
        import mathutils
        d = mathutils.Vector(direction).normalized()
        return self.dircyl(name, tuple(mathutils.Vector(point) - d * 0.02),
                           tuple(mathutils.Vector(point) + d * 0.02), r + 0.015, self.M["darkmetal"])

    # ------------------------- OPENINGS -------------------------
    _FACE = {"-Y": (0, -1), "+Y": (0, 1), "-X": (-1, 0), "+X": (1, 0)}

    def _face_axes(self, face):
        """Return (outward, across) unit vectors for a wall face."""
        import mathutils
        nx, ny = self._FACE[face]
        out = mathutils.Vector((nx, ny, 0.0))
        across = mathutils.Vector((-ny, nx, 0.0))
        return out, across

    def window(self, name, face, centre, w, h, cols=2, rows=3, sill=True):
        """Standard opening: proud glass + 4 frame strips + sill + mullion grid.
        2 wide x 3 tall is the house default; wide strip windows use 6x3."""
        import mathutils
        out, across = self._face_axes(face)
        C = mathutils.Vector(centre) + out * EPS
        F = C + out * 0.005                       # frames sit just proud of the glass
        def put(nm, off, sx, sy, sz, mat):
            p = C + across * off[0] + mathutils.Vector((0, 0, off[1])) + out * off[2]
            self.box(nm, p.x, p.y, p.z, sx, sy, sz, mat)
        ax, ay = abs(across.x), abs(across.y)
        gx, gy = (w if ax else 0.01), (w if ay else 0.01)
        self.box(f"{name}_glass", C.x, C.y, C.z, gx or 0.01, gy or 0.01, h, self.mat("window_glass"))
        fw = 0.05
        put(f"{name}_fl", (-w / 2, 0, 0.005), fw if ax else 0.012, fw if ay else 0.012, h + 0.10, self.mat("window_frame"))
        put(f"{name}_fr", (w / 2, 0, 0.005), fw if ax else 0.012, fw if ay else 0.012, h + 0.10, self.mat("window_frame"))
        put(f"{name}_ft", (0, h / 2, 0.005), (w + 0.09) if ax else 0.012, (w + 0.09) if ay else 0.012, fw, self.mat("window_frame"))
        put(f"{name}_fb", (0, -h / 2, 0.005), (w + 0.09) if ax else 0.012, (w + 0.09) if ay else 0.012, fw, self.mat("window_frame"))
        if sill:
            put(f"{name}_sill", (0, -h / 2, 0.012), (w + 0.13) if ax else 0.03, (w + 0.13) if ay else 0.03, 0.055, self.mat("window_frame"))
        for k in range(1, cols):
            put(f"{name}_mv{k}", (-w / 2 + k * w / cols, 0, 0.004), 0.026 if ax else 0.01, 0.026 if ay else 0.01, h, self.mat("window_frame"))
        for k in range(1, rows):
            put(f"{name}_mh{k}", (0, -h / 2 + k * h / rows, 0.004), w if ax else 0.01, w if ay else 0.01, 0.026, self.mat("window_frame"))

    def door(self, name, face, centre, w, h, ribs=3, glow=False):
        """Personnel/sliding door. `glow` fills it with ember for a heat-lit interior."""
        import mathutils
        out, across = self._face_axes(face)
        C = mathutils.Vector(centre) + out * EPS
        ax, ay = abs(across.x), abs(across.y)
        leaf = self.M["ember"] if glow else self.mat("door_leaf")
        self.box(f"{name}_leaf", C.x, C.y, C.z, w if ax else 0.01, w if ay else 0.01, h, leaf)
        for k in range(1, ribs + 1):
            p = C + out * -0.004 + mathutils.Vector((0, 0, -h / 2 + k * h / (ribs + 1)))
            self.box(f"{name}_rib{k}", p.x, p.y, p.z, (w - 0.06) if ax else 0.008,
                     (w - 0.06) if ay else 0.008, 0.018, self.mat("scaffold"))
        lp = C + out * -0.006 + mathutils.Vector((0, 0, h / 2 + 0.03))
        self.box(f"{name}_lintel", lp.x, lp.y, lp.z, (w + 0.16) if ax else 0.012,
                 (w + 0.16) if ay else 0.012, 0.06, self.mat("window_frame"))

    def gate(self, name, face, centre, w, h, slats=5):
        """Wide roller gate — vehicle-scale opening."""
        self.door(name, face, centre, w, h, ribs=slats)

    def arch_opening(self, name, centre, normal, hw, rect_h=0.22, depth=0.28):
        """Arched hole (flat base, semicircle up) sunk into a wall or CYLINDER shell.
        On a cylinder the normal must face the CAMERA (0.707,-0.707): the -Y face of a
        cylinder lies on its silhouette at this iso and an opening there half-vanishes.
        Front face sits on the tangent plane — further out its side walls show (reads as a
        box stuck on), further in the curve clips it away."""
        import mathutils
        n = mathutils.Vector((normal[0], normal[1], 0.0)).normalized()
        C = mathutils.Vector(centre)
        ang = math.degrees(math.atan2(n.y, n.x)) - 90.0
        self.rotbox(f"{name}_rect", C.x, C.y, C.z - rect_h / 2, hw * 2, depth, rect_h,
                    self.mat("opening"), 'Z', ang)
        self.dircyl(f"{name}_arch", tuple(C - n * depth / 2), tuple(C + n * depth / 2),
                    hw, self.mat("opening"), segments=24)

    # ------------------------- STAIRS & WALKWAYS -------------------------
    def stairwell(self, name, x, y0, y1, z0, z1, flights=4, steps=6,
                  tread=0.30, half_gap=0.16, posts=True):
        """Switchback stair. Flights alternate SIDE as well as direction, so consecutive
        runs sit BESIDE each other — alternating direction alone stacks them in one column
        and reads wrong. Half-landings span both runs at every turn.
        An EVEN flight count lands the top back at y0 (the near end).
        Returns dict(top=(x, y, z), post_x=…) for attaching a walkway."""
        zs = [z0 + (z1 - z0) * k / flights for k in range(flights + 1)]
        for fl in range(flights):
            za, zb = zs[fl], zs[fl + 1]
            rx = x - half_gap if fl % 2 == 0 else x + half_gap
            ya, yb = (y0, y1) if fl % 2 == 0 else (y1, y0)
            for k in range(steps):
                t = (k + 0.5) / steps
                self.box(f"{name}_step{fl}_{k}", rx, ya + t * (yb - ya), za + t * (zb - za),
                         tread, abs(yb - ya) / steps * 0.86, 0.04, self.mat("stair"))
            for si, so in enumerate((-tread / 2 - 0.02, tread / 2 + 0.02)):
                self.dircyl(f"{name}_str{fl}_{si}", (rx + so, ya, za - 0.03), (rx + so, yb, zb - 0.03),
                            0.028, self.mat("stair"), segments=8)
        land_w = 2 * half_gap + tread + 0.10
        for k in range(1, flights + 1):
            ly = (y1 + 0.17) if (k % 2 == 1) else (y0 - 0.17)
            self.box(f"{name}_landing{k}", x, ly, zs[k], land_w, 0.34, 0.05, self.mat("stair"))
        post_x = x + half_gap + tread / 2 + 0.14
        if posts:
            # OUTBOARD of both runs: inboard posts spear every flight.
            for k, ly in enumerate((y0 - 0.17, y1 + 0.17)):
                self.box(f"{name}_post{k}", post_x, ly, z1 / 2, 0.07, 0.07, z1, self.mat("stair"))
        return {"top": (x, y0 - 0.17, z1), "post_x": post_x, "landing_w": land_w}

    def walkway(self, name, x0, x1, y, z, width=0.52, rail_h=0.25, posts=6, extend_to=None):
        """Deck with half-height guardrails both sides. `extend_to` carries the rail on past
        the deck (e.g. over a stair head) so the two read as one continuous run."""
        self.box(f"{name}_deck", (x0 + x1) / 2, y, z, x1 - x0, width, 0.06, self.mat("walkway"))
        half = width / 2 + 0.02
        for si, off in enumerate((-half, half)):
            self.dircyl(f"{name}_rail{si}", (x0, y + off, z + rail_h), (x1, y + off, z + rail_h),
                        0.027, self.mat("handrail"), segments=8)
            self.dircyl(f"{name}_mid{si}", (x0, y + off, z + rail_h / 2), (x1, y + off, z + rail_h / 2),
                        0.022, self.mat("handrail"), segments=8)
            for k in range(posts):
                wx = x0 + (x1 - x0) * k / max(1, posts - 1)
                self.box(f"{name}_post{si}_{k}", wx, y + off, z + rail_h / 2, 0.04, 0.04, rail_h + 0.01,
                         self.mat("handrail"))
        if extend_to is not None:
            for si, off in enumerate((-half, half)):
                if si == 1:
                    continue                       # leave the far side open for stair entry
                self.dircyl(f"{name}_ext{si}", (x1, y + off, z + rail_h), (extend_to, y + off, z + rail_h),
                            0.026, self.mat("handrail"), segments=8)
                self.dircyl(f"{name}_extm{si}", (x1, y + off, z + rail_h / 2), (extend_to, y + off, z + rail_h / 2),
                            0.026, self.mat("handrail"), segments=8)
            self.dircyl(f"{name}_extend_cap", (extend_to, y - half, z + rail_h), (extend_to, y + half, z + rail_h),
                        0.026, self.mat("handrail"), segments=8)

    # ------------------------- CHIMNEY FAMILY -------------------------
    def chimney_square(self, name, cx, cy, top, side0=0.48, side1=0.40,
                       base_top=None, collars=(), tip_h=0.5):
        """Square stack. Cel-shades cleanly with no facet gradients — the DEFAULT choice.
        `base_top` adds a continuous square base tower from the ground (no corbel seam)
        with a dark plate where the stack proper begins."""
        z0 = 0.0
        if base_top is not None:
            bs = side0 + 0.18
            self.sqcol(f"{name}_base", cx, cy, 0.0, base_top, bs, bs, self.mat("wall_brick"))
            self.sqcol(f"{name}_plate", cx, cy, base_top, base_top + 0.08, side0 + 0.30, side0 + 0.30,
                       self.mat("scaffold"))
            z0 = base_top + 0.08
        self.sqcol(name, cx, cy, z0, top, side0, side1, self.mat("wall_brick"))
        def side_at(z):
            return side0 + (side1 - side0) * (z - z0) / max(1e-6, top - z0)
        for j, z in enumerate(collars):
            s = side_at(z) + 0.10
            self.sqcol(f"{name}_collar{j}", cx, cy, z - 0.065, z + 0.065, s, s, self.mat("wall_brick"))
        s_tip = side_at(top - tip_h) + 0.07
        self.sqcol(f"{name}_tip", cx, cy, top - tip_h + 0.035, top + 0.035, s_tip, s_tip - 0.05,
                   self.mat("opening"))

    def chimney_round(self, name, cx, cy, top, r=0.36, heat_z=None, collar_z=None,
                      capped=True, seg=32):
        """Round tower, CONSTANT diameter (so a duct of the same radius continues it
        seamlessly). Sides smooth, caps flat. Optional glowing heat band and service collar,
        each with seam rings at both edges."""
        self.cyl(name, cx, cy, top / 2, r, top, self.mat("stack"), segments=seg)
        if heat_z is not None:
            self.cyl(f"{name}_heat", cx, cy, heat_z, r + 0.055, 0.22, self.M["ember"], segments=seg)
            self.cyl(f"{name}_heatrim", cx, cy, heat_z + 0.155, r + 0.07, 0.07, self.mat("hot"), segments=seg)
            for tag, z in (("lo", heat_z - 0.11), ("hi", heat_z + 0.11)):
                self.seam(f"{name}_heatseam_{tag}", cx, cy, z, r + 0.065)
        if collar_z is not None:
            self.cyl(f"{name}_collar", cx, cy, collar_z, r + 0.045, 0.10, self.mat("stack"), segments=seg)
            for tag, dz in (("lo", -0.05), ("hi", 0.05)):
                self.seam(f"{name}_collarseam_{tag}", cx, cy, collar_z + dz, r + 0.055)
        if capped:
            self.cyl(f"{name}_capring", cx, cy, top - 0.12, r + 0.045, 0.10, self.mat("stack"), segments=seg)
            self.cone(f"{name}_tip", cx, cy, top + 0.215, r + 0.035, r + 0.005, 0.43,
                      self.mat("opening"), segments=seg)

    def merge_pair(self, name, a, b, r, tower_top, merge_z, exhaust_top, seg=32):
        """Two round stacks gathered into ONE exhaust. `a`/`b` are the tower (x, y).

        The duct PATH is built explicitly in three parts and swept — this is the shape that
        works, after three that did not:
          1. a short VERTICAL lead-in coaxial with the tower;
          2. a constant-radius fillet turning exactly 45 degrees;
          3. a straight 45-degree run into the stack's foot.
        The foot is a downward-flaring OVAL breeches piece, widening ONLY along the axis
        joining the two towers (a circular flare balloons on the two empty sides) and
        starting just ABOVE where the ducts converge (lower, its open rim reads as a dark
        line floating in the gap). The swept sleeve is a hair fatter than the tower so the
        coaxial overlap cannot z-fight.

        What does NOT work: a Hermite whose START tangent aims at the target leaves the
        shell at ~39 deg and opens a V-notch; patching that with a bisector cylinder bulges
        past the silhouette; a MITRED cut reaches tan(67.5)*r (~2.4r) below the kink on the
        outer side, inverting the vertical section into an open hole. Curvature, not cuts."""
        import mathutils
        exc = ((a[0] + b[0]) / 2.0, (a[1] + b[1]) / 2.0)
        sleeve = r + 0.012
        for tag, (fx, fy) in (("A", a), ("B", b)):
            up = mathutils.Vector((0, 0, 1))
            h = (mathutils.Vector((exc[0], exc[1], 0)) - mathutils.Vector((fx, fy, 0)))
            D = h.length
            h = h.normalized()
            R_BEND = 0.46
            z_b = tower_top - 0.06
            P_lead = mathutils.Vector((fx, fy, tower_top - 0.62))
            P_arc0 = mathutils.Vector((fx, fy, z_b))
            C = P_arc0 + h * R_BEND
            pts = [tuple(P_lead), tuple(P_lead.lerp(P_arc0, 0.55)), tuple(P_arc0)]
            for k in range(1, 15):
                phi = math.radians(45.0) * k / 14
                pts.append(tuple(C + (-h * math.cos(phi) + up * math.sin(phi)) * R_BEND))
            arc_end = mathutils.Vector(pts[-1])
            bdir = (h + up).normalized()
            run = (D * 0.90 - (arc_end - P_arc0).dot(h)) * math.sqrt(2.0)
            for k in (0.34, 0.67, 1.0):
                pts.append(tuple(arc_end + bdir * (run * k)))
            self.sweep(f"{name}_duct{tag}", pts, sleeve, self.mat("duct"), seg=seg)
            self.seam(f"{name}_ductseam{tag}", fx, fy, tower_top - 0.60, sleeve + 0.02)
        u = (b[0] - a[0], b[1] - a[1])
        self.oval_cone(f"{name}_flare", exc[0], exc[1], merge_z + 0.20, merge_z + 0.78, u,
                       0.76, r + 0.07, r + 0.07, r + 0.07, self.mat("duct"), seg=seg)
        self.cyl(f"{name}_flarerim", exc[0], exc[1], merge_z + 0.76, r + 0.095, 0.08,
                 self.mat("scaffold"), segments=seg)
        E0 = merge_z + 0.80
        self.cone(f"{name}_stack", exc[0], exc[1], (E0 + exhaust_top) / 2, r + 0.06, r - 0.02,
                  exhaust_top - E0, self.mat("duct"), segments=seg)
        self.cyl(f"{name}_stackring", exc[0], exc[1], exhaust_top - 0.05, r + 0.05, 0.10,
                 self.mat("duct"), segments=seg)
        self.cone(f"{name}_tip", exc[0], exc[1], exhaust_top + 0.43, r + 0.035, r + 0.005, 0.43,
                  self.mat("opening"), segments=seg)
        return {"exhaust_xy": exc}

    # ------------------------- SUBTRACTIVE MASSING -------------------------
    _PIT_TONES = ("ground", "ground2", "ground3", "ground4", "ground_deep")

    def pit_mats(self, rings):
        """`rings + 1` materials (one per ring, last one for the floor) spread evenly over
        the earth ramp, so a shallow pit still darkens all the way to the bottom."""
        n = rings + 1
        last = len(self._PIT_TONES) - 1
        return [self.mat(self._PIT_TONES[int(round(k * last / max(1, n - 1)))])
                for k in range(n)]

    def terraced_pit(self, name, rects, tops, base_z=0.0, mats=None, grow=0.03, strata=1):
        """Open-pit massing. A sprite floats with no ground plane, so a HOLE cannot be
        subtracted — it is built as nested rectangular RINGS of solid earth, each one
        shorter than the last. The benches ARE the ring tops; the pit walls are the ring
        inner faces.

        rects : [(x0,x1,y0,y1), ...] outermost → innermost. len(rects) = benches + 1.
        tops  : top z of each ring, descending; the last entry is the pit floor.
        Rings are grown outward by `grow` so consecutive rings OVERLAP — sharing an exact
        vertical face would z-fight into a smear.

        `strata` > 1 splits the OUTERMOST ring into that many horizontal bands, darkening
        downward. Do not skip this: ring 0 carries the block's whole exposed section — on a
        1024 render it is the majority of all earth pixels — so leaving it one flat tone
        makes the block, not the pit, the brightest mass and the terracing stops reading.
        Banded, it reads as strata cut through, which is also what it physically is.
        Returns the floor rect and floor z, for placing galleries and plant."""
        mats = mats or [self.mat("ground")] + [self.mat("ground_deep")] * (len(rects) - 1)
        for i in range(len(rects) - 1):
            ox0, ox1, oy0, oy1 = rects[i]
            ix0, ix1, iy0, iy1 = rects[i + 1]
            if i > 0:                       # overlap back into the ring above
                ox0, ox1, oy0, oy1 = ox0 - grow, ox1 + grow, oy0 - grow, oy1 + grow
            top = tops[i]
            m = mats[min(i, len(mats) - 1)]
            h = top - base_z
            nb_ = strata if i == 0 else 1
            for tag, (bx0, bx1, by0, by1) in {
                "f": (ox0, ox1, oy0, iy0), "b": (ox0, ox1, iy1, oy1),
                "l": (ox0, ix0, iy0, iy1), "r": (ix1, ox1, iy0, iy1),
            }.items():
                if bx1 - bx0 <= 1e-4 or by1 - by0 <= 1e-4:
                    continue
                for k in range(nb_):
                    lh = h / nb_
                    lz = base_z + h - (k + 0.5) * lh
                    lm = m if nb_ == 1 else self.mat(
                        self._PIT_TONES[int(round(k * (len(self._PIT_TONES) - 1) / max(1, nb_ - 1)))])
                    self.box("%s_ring%d%s%d" % (name, i, tag, k), (bx0 + bx1) / 2,
                             (by0 + by1) / 2, lz, bx1 - bx0, by1 - by0, lh, lm)
        fx0, fx1, fy0, fy1 = rects[-1]
        self.box("%s_floor" % name, (fx0 + fx1) / 2, (fy0 + fy1) / 2, base_z + (tops[-1] - base_z) / 2,
                 fx1 - fx0, fy1 - fy0, tops[-1] - base_z, mats[-1])
        return {"floor_rect": rects[-1], "floor_z": tops[-1]}

    def seam_band(self, name, rects, i, z, thick=0.09, mat=None):
        """Exposed ore seam: a band lying ON the pit wall at boundary `rects[i]`, sunk into
        the face and standing only EPS proud.

        It must NOT straddle the boundary: a band grown outward on both sides wraps the rim
        as a continuous raised rail and reads as a handrail or a neon strip, not as strata.
        Only the -X and +Y walls face this camera, so those two carry the band; the other
        two are emitted for completeness and are never seen."""
        mat = mat or self.mat("ore_seam")
        x0, x1, y0, y1 = rects[i]
        t = 0.024
        for tag, (cx, cy, sx, sy) in {
            "l": (x0 + t / 2 + EPS, (y0 + y1) / 2, t, y1 - y0),      # faces +X — visible
            "b": ((x0 + x1) / 2, y1 - t / 2 - EPS, x1 - x0, t),      # faces -Y — visible
            "r": (x1 - t / 2 - EPS, (y0 + y1) / 2, t, y1 - y0),
            "f": ((x0 + x1) / 2, y0 + t / 2 + EPS, x1 - x0, t),
        }.items():
            self.box("%s_%s" % (name, tag), cx, cy, z, sx, sy, thick, mat)

    def headframe(self, name, cx, cy, base_z, height, w=0.62, taper=0.62, brace_to=None):
        """Pit-head winding tower: four battered legs, X-bracing on the two camera-facing
        sides, a capping deck, and the sheave wheel at the head. `brace_to` adds the raking
        back-brace (dy, dz-foot) that stops the tower reading like a bare box."""
        wt = w * taper                       # head is narrower than the foot (battered legs)
        top = base_z + height
        corners = ((-1, -1), (1, -1), (1, 1), (-1, 1))
        for i, (sx, sy) in enumerate(corners):
            self.dircyl("%s_leg%d" % (name, i),
                        (cx + sx * w / 2, cy + sy * w / 2, base_z),
                        (cx + sx * wt / 2, cy + sy * wt / 2, top), 0.045, self.mat("scaffold"),
                        segments=8)
        for j, t in enumerate((0.18, 0.42, 0.66, 0.90)):
            s_ = w + (wt - w) * t
            z = base_z + height * t
            for tag, (ax, ay, bx, by) in {
                "f": (-1, -1, 1, -1), "r": (1, -1, 1, 1),
            }.items():
                self.dircyl("%s_belt%d%s" % (name, j, tag),
                            (cx + ax * s_ / 2, cy + ay * s_ / 2, z),
                            (cx + bx * s_ / 2, cy + by * s_ / 2, z), 0.032, self.mat("scaffold"),
                            segments=8)
        for j in range(3):
            t0, t1 = 0.18 + j * 0.24, 0.42 + j * 0.24
            s0, s1 = w + (wt - w) * t0, w + (wt - w) * t1
            z0, z1 = base_z + height * t0, base_z + height * t1
            for tag, (ax, ay, bx, by) in {
                "f": (-1, -1, 1, -1), "r": (1, -1, 1, 1),
            }.items():
                self.dircyl("%s_brX%d%s" % (name, j, tag),
                            (cx + ax * s0 / 2, cy + ay * s0 / 2, z0),
                            (cx + bx * s1 / 2, cy + by * s1 / 2, z1), 0.026, self.mat("scaffold"), segments=8)
                self.dircyl("%s_brY%d%s" % (name, j, tag),
                            (cx + ax * s0 / 2, cy + ay * s0 / 2, z1),
                            (cx + bx * s1 / 2, cy + by * s1 / 2, z0), 0.026, self.mat("scaffold"), segments=8)
        self.box("%s_deck" % name, cx, cy, top + 0.05, wt + 0.22, wt + 0.22, 0.09, self.mat("scaffold"))
        # sheave wheel, axis across the screen-horizontal so the rim reads as a circle
        self.cyl("%s_sheave" % name, cx, cy, top - 0.30, 0.24, 0.10, self.mat("stack"),
                 axis='X', segments=24)
        self.cyl("%s_sheave_hub" % name, cx, cy, top - 0.30, 0.07, 0.13, self.mat("opening"),
                 axis='X', segments=16)
        if brace_to is not None:
            dy, foot_z = brace_to
            for sx in (-1, 1):
                self.dircyl("%s_backbrace%d" % (name, sx),
                            (cx + sx * wt / 2, cy, top - 0.16),
                            (cx + sx * w / 2, cy + dy, foot_z), 0.040, self.mat("scaffold"), segments=8)

    # ------------------------- POLYGON (ORGANIC) PIT MASSING -------------------------
    # Rectangular benches read as a quarry cut by a machine. A real open pit is an irregular
    # bowl, so the ring stack below is driven by an arbitrary closed OUTLINE instead. Every
    # ring shares one angular parametrisation, which is what lets a rectangular block and a
    # bean-shaped hole be strip-meshed into a single annulus.

    @staticmethod
    def poly_bean(cx, cy, rx, ry, n=18, lobe=0.10, dent=0.16, phase=0.0):
        """Closed bean/kidney outline, CCW. `lobe` makes it lopsided, `dent` pinches one
        flank. Keep r(t) > 0 (it stays star-shaped) or the inset below will fold."""
        pts = []
        for i in range(n):
            t = 2 * math.pi * i / n
            r = 1.0 + lobe * math.cos(t + phase) - dent * math.cos(2 * (t + phase))
            pts.append((cx + rx * r * math.cos(t), cy + ry * r * math.sin(t)))
        return pts

    @staticmethod
    def poly_rect(x0, x1, y0, y1, n):
        """Rectangle sampled by casting n rays from its centre — same angular
        parametrisation as poly_bean, so vertex j of each corresponds.
        The four CORNER angles displace their nearest samples: without that the outline is
        a decagon inscribed in the rectangle and the block loses its corners."""
        cx, cy, hx, hy = (x0 + x1) / 2, (y0 + y1) / 2, (x1 - x0) / 2, (y1 - y0) / 2
        angs = [2 * math.pi * i / n for i in range(n)]
        for sx, sy in ((1, 1), (-1, 1), (-1, -1), (1, -1)):
            ca = math.atan2(sy * hy, sx * hx) % (2 * math.pi)
            j = min(range(n), key=lambda i: abs(((angs[i] - ca + math.pi)
                                                 % (2 * math.pi)) - math.pi))
            angs[j] = ca
        pts = []
        for t in angs:
            dx, dy = math.cos(t), math.sin(t)
            s = min(hx / abs(dx) if abs(dx) > 1e-9 else 1e9,
                    hy / abs(dy) if abs(dy) > 1e-9 else 1e9)
            pts.append((cx + dx * s, cy + dy * s))
        return pts

    @staticmethod
    def poly_normals(pts):
        out, n = [], len(pts)
        for j in range(n):
            nx = ny = 0.0
            for (p, q) in ((pts[j - 1], pts[j]), (pts[j], pts[(j + 1) % n])):
                ex, ey = q[0] - p[0], q[1] - p[1]
                L = math.hypot(ex, ey) or 1.0
                nx += ey / L
                ny += -ex / L                    # outward for CCW winding
            L = math.hypot(nx, ny) or 1.0
            out.append((nx / L, ny / L))
        return out

    @staticmethod
    def poly_offset(pts, fn):
        """Move every vertex along its own outward normal by fn(nx, ny); negative grows.
        `fn` takes the normal so a caller can inset the CAMERA-FACING flank harder than the
        rest — which is how the sightline rule survives an organic outline."""
        return [(p[0] - nx * fn(nx, ny), p[1] - ny * fn(nx, ny))
                for p, (nx, ny) in zip(pts, Kit.poly_normals(pts))]

    @staticmethod
    def point_in_poly(pts, x, y):
        inside, n = False, len(pts)
        for j in range(n):
            (ax, ay), (bx, by) = pts[j], pts[(j + 1) % n]
            if (ay > y) != (by > y) and x < (bx - ax) * (y - ay) / (by - ay) + ax:
                inside = not inside
        return inside

    @staticmethod
    def _clip_halfplane(poly, f, lim, keep_lo):
        def inside(q):
            return f(q) <= lim if keep_lo else f(q) >= lim
        out, n = [], len(poly)
        for j in range(n):
            a, b = poly[j], poly[(j + 1) % n]
            ia, ib = inside(a), inside(b)
            if ia:
                out.append(a)
            if ia != ib:
                fa, fb = f(a) - lim, f(b) - lim
                t = fa / (fa - fb)
                out.append((a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t))
        return out

    @staticmethod
    def slab_outline(items, pad=0.16, margin=0.14):
        """Smallest octagon containing every (x, y, r) footprint — the axis bounding box cut
        by the four DIAGONAL supporting lines.

        A plain bounding rectangle is the wrong slab. Two of its corners are empty and sit
        furthest out along the screen diagonal (x+y), so each one buys sprite width for
        nothing; the other two push the silhouette up-left and down-right. Cutting them back
        to the equipment costs nothing visually and can be the difference between a slab that
        fits the level's size budget and one that does not."""
        k = math.sqrt(2.0)
        xs = (min(x - r for x, y, r in items) - pad, max(x + r for x, y, r in items) + pad)
        ys = (min(y - r for x, y, r in items) - pad, max(y + r for x, y, r in items) + pad)
        sm = (min(x + y - k * r for x, y, r in items) - margin,
              max(x + y + k * r for x, y, r in items) + margin)
        dm = (min(y - x - k * r for x, y, r in items) - margin,
              max(y - x + k * r for x, y, r in items) + margin)
        poly = [(xs[0], ys[0]), (xs[1], ys[0]), (xs[1], ys[1]), (xs[0], ys[1])]
        sf, df = (lambda q: q[0] + q[1]), (lambda q: q[1] - q[0])
        for f, lim, lo in ((sf, sm[0], False), (sf, sm[1], True),
                           (df, dm[0], False), (df, dm[1], True)):
            poly = Kit._clip_halfplane(poly, f, lim, lo)
        return poly

    def apron_slab(self, name, pts, t=0.20, lip=0.13, top=0.02, mat=None, kerb=None):
        """Ground slab under a plant. TWO prisms, not one: a darker kerb at the full outline
        and a lighter deck inset on top of it. A single-tone pad fuses into one flat diamond
        that owns the bottom of the sprite — measured on the old refinery bund — whereas the
        inset step gives it an edge and a second value.

        `top` sits slightly ABOVE ground so equipment beds INTO the slab. A deck flush at 0.0
        is coplanar with every vessel's base cap, and a deck below it leaves a hairline gap.

        Its real job is not decoration: Freestyle's 7 px external contour is view-map based,
        not per-object, so anything with background behind it — every pipe run, every leg —
        carries the heavy outline. Put a slab behind them and they drop to the 2.4 px ink."""
        self.poly_prism("%s_kerb" % name, pts, -t, top - 0.07,
                        kerb if kerb is not None else self.mat("yard"))
        self.poly_prism(name, Kit.poly_offset(pts, lambda nx, ny: lip), -t + 0.02, top,
                        mat if mat is not None else self.mat("yard_pad"))
        return top

    def poly_ring(self, name, outer, inner, z0, z1, mat):
        """Closed annular solid between two same-length outlines."""
        m = bpy.data.meshes.new(name)
        bm = bmesh.new()
        ob = [bm.verts.new((p[0], p[1], z0)) for p in outer]
        ot = [bm.verts.new((p[0], p[1], z1)) for p in outer]
        ib = [bm.verts.new((p[0], p[1], z0)) for p in inner]
        it = [bm.verts.new((p[0], p[1], z1)) for p in inner]
        for j in range(len(outer)):
            k = (j + 1) % len(outer)
            bm.faces.new([ob[j], ob[k], ot[k], ot[j]])
            bm.faces.new([it[j], it[k], ib[k], ib[j]])
            bm.faces.new([ot[j], ot[k], it[k], it[j]])
            bm.faces.new([ib[j], ib[k], ob[k], ob[j]])
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        bm.to_mesh(m); bm.free()
        return self.obj(name, m, mat)

    def poly_prism(self, name, pts, z0, z1, mat):
        m = bpy.data.meshes.new(name)
        bm = bmesh.new()
        vb = [bm.verts.new((p[0], p[1], z0)) for p in pts]
        vt = [bm.verts.new((p[0], p[1], z1)) for p in pts]
        caps = [bm.faces.new(list(reversed(vb))), bm.faces.new(vt)]
        for j in range(len(pts)):
            k = (j + 1) % len(pts)
            bm.faces.new([vb[j], vb[k], vt[k], vt[j]])
        bmesh.ops.triangulate(bm, faces=caps)     # the outline may be concave
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        bm.to_mesh(m); bm.free()
        return self.obj(name, m, mat)

    def terraced_pit_poly(self, name, polys, tops, base_z=0.0, mats=None, grow=0.03, strata=1):
        """Outline-driven twin of terraced_pit; see that docstring for why a sprite pit is
        built additively and why `strata` on ring 0 matters."""
        mats = mats or self.pit_mats(len(polys) - 1)
        for i in range(len(polys) - 1):
            outer = polys[i] if i == 0 else Kit.poly_offset(polys[i], lambda nx, ny: -grow)
            h = tops[i] - base_z
            n_ = strata if i == 0 else 1
            for k in range(n_):
                z1 = base_z + h - k * h / n_
                lm = (mats[min(i, len(mats) - 1)] if n_ == 1 else
                      self.mat(self._PIT_TONES[int(round(k * (len(self._PIT_TONES) - 1)
                                                         / max(1, n_ - 1)))]))
                self.poly_ring("%s_ring%d_%d" % (name, i, k), outer, polys[i + 1],
                               z1 - h / n_, z1, lm)
        self.poly_prism("%s_floor" % name, polys[-1], base_z, tops[-1], mats[-1])
        return {"floor_poly": polys[-1], "floor_z": tops[-1]}

    def poly_band(self, name, pts, z, thick=0.10, mat=None, t=0.03):
        """Ore seam lying ON a curved pit wall — see seam_band for why it must not straddle
        the boundary."""
        self.poly_ring(name, Kit.poly_offset(pts, lambda nx, ny: -0.002),
                       Kit.poly_offset(pts, lambda nx, ny: t),
                       z - thick / 2, z + thick / 2, mat or self.mat("ore_seam"))

    @staticmethod
    def _poly_at(pts, jj):
        n = len(pts)
        j = int(math.floor(jj)) % n
        f = jj - math.floor(jj)
        a, b = pts[j], pts[(j + 1) % n]
        return (a[0] + (b[0] - a[0]) * f, a[1] + (b[1] - a[1]) * f)

    def spiral_road(self, name, polys, tops, j0, width, mat, turns=1.0, steps=30,
                    skirt=0.4, ground_fn=None):
        """Haul road spiralling down the benches of a poly pit, one ring per `turns`.

        A STRAIGHT ramp is only correct over a rectangular pit, where the bench noses happen
        to be collinear. Laid across a bean it rests on nothing and reads as a plank dropped
        into the hole. This follows the outline instead.

        The road descends continuously while the ground under it is stepped. Pass `ground_fn`
        — WITHOUT IT MOST OF THE ROAD IS INVISIBLE: every stretch where the smooth descent
        falls below the stepped bench is simply buried inside it, which in practice is more
        than half the length. Clamping to the terrain turns the spiral into flat runs joined
        by short ramps, which is what a haul road does anyway. `skirt` extrudes downward by
        more than one riser so the raised stretches read as a cut edge, not a floating slab."""
        n = len(polys[0])
        rows = []
        for i in range(steps + 1):
            s = i / steps
            bb = 1.0 + s * (len(polys) - 2)
            k = min(int(bb), len(polys) - 2)
            f = bb - k
            jj = j0 + s * turns * n
            a = Kit._poly_at(polys[k], jj)
            b = Kit._poly_at(polys[k + 1], jj)
            c = (a[0] + (b[0] - a[0]) * f, a[1] + (b[1] - a[1]) * f)
            z = tops[k - 1] + (tops[k] - tops[k - 1]) * f
            if ground_fn is not None:
                z = max(z, ground_fn(c[0], c[1]) + 0.02)
            dx, dy = b[0] - a[0], b[1] - a[1]
            L = math.hypot(dx, dy) or 1.0
            dx, dy = dx / L, dy / L                 # unit vector pointing INTO the pit
            # The road lies ENTIRELY INBOARD of its boundary. Centring it on the boundary
            # pushes its outer edge half a width outside, which on the widest ring overhangs
            # the block and renders as a 1px bright sliver down the cut face.
            rows.append(((c[0], c[1]), (c[0] + dx * width, c[1] + dy * width), z))
        m = bpy.data.meshes.new(name)
        bm = bmesh.new()
        vt = [(bm.verts.new((o[0], o[1], z)), bm.verts.new((q[0], q[1], z)))
              for o, q, z in rows]
        vb = [(bm.verts.new((o[0], o[1], z - skirt)), bm.verts.new((q[0], q[1], z - skirt)))
              for o, q, z in rows]
        for i in range(steps):
            bm.faces.new([vt[i][0], vt[i][1], vt[i + 1][1], vt[i + 1][0]])
            bm.faces.new([vb[i + 1][0], vb[i + 1][1], vb[i][1], vb[i][0]])
            bm.faces.new([vt[i][1], vb[i][1], vb[i + 1][1], vt[i + 1][1]])
            bm.faces.new([vb[i][0], vt[i][0], vt[i + 1][0], vb[i + 1][0]])
        for e in (0, steps):
            bm.faces.new([vt[e][0], vt[e][1], vb[e][1], vb[e][0]])
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        bm.to_mesh(m); bm.free()
        return self.obj(name, m, mat)

    def shaft_cutaway(self, name, xface, y, top_z, bottom_z, levels=(), reach=0.55,
                      bore=0.15, cage_at=None, stagger=0.0, dip=0.0):
        """Section through the workings drawn FLUSH on the block's cut edge — the sprite has
        no interior, so this is draughtsmanship on the face, not a void. Sits EPS proud of
        `xface` (a +X face) so it overlays the strata banding.
        `levels` are the z heights of the horizontal galleries."""
        self.box("%s_bore" % name, xface + EPS, y, (top_z + bottom_z) / 2, 0.024, bore,
                 top_z - bottom_z, self.mat("opening"))
        for i, lz in enumerate(levels):
            # Equal arms at every level draw a plus sign. `stagger` shortens alternate
            # levels so the section reads as workings following a seam.
            k = 1.0 - stagger * (i % 2)
            for s, ln in ((-1, reach * k), (1, reach * 0.62 * (2.0 - k))):
                if s < 0 and dip and i == len(levels) - 1:
                    # Deepest -Y arm dives instead of running level: an inclined drift chasing
                    # the seam down. Rotating about X tilts it within the face plane; the +Y
                    # end is pinned to the bore so the junction stays tight.
                    a = math.radians(dip)
                    ln *= 0.95
                    cy = y - bore / 2 + 0.01 - (ln / 2) * math.cos(a)
                    cz = lz - (ln / 2) * math.sin(a)
                    self.rotbox("%s_dip%d" % (name, i), xface + EPS, cy, cz, 0.024, ln,
                                bore * 0.55, self.mat("opening"), 'X', dip)
                    continue
                self.box("%s_gal%d_%d" % (name, i, s > 0), xface + EPS,
                         y + s * (ln / 2 + bore / 2 - 0.01), lz, 0.024, ln, bore * 0.55,
                         self.mat("opening"))
                self.box("%s_stope%d_%d" % (name, i, s > 0), xface + EPS,
                         y + s * (ln + bore / 2 - 0.02), lz + bore * 0.10, 0.024,
                         bore * 0.7, bore * 0.95, self.mat("opening"))
        if cage_at is not None:
            self.box("%s_cage" % name, xface + EPS * 1.6, y, cage_at, 0.020, bore * 0.66,
                     bore * 0.9, self.mat("scaffold"))

    def excavator(self, name, cx, cy, z, s=0.75, face=1.0, mat=None):
        """Simplified tracked excavator, read at sprite scale: tracks, slew deck, house, cab
        and a boom-dipper-bucket. Deliberately silhouette-first — at 100px only the boom line
        survives, so that is the part that carries the machine."""
        # `mat` paints the HOUSE only; tracks and boom stay dark. A machine painted yellow all
        # over loses its own detail — the contrast between the painted body and the black
        # running gear is what makes it read as a machine at sprite scale.
        dark, steel = self.mat("opening"), self.mat("scaffold")
        body = mat if mat is not None else steel
        for sy in (-1, 1):
            self.box("%s_track%d" % (name, sy > 0), cx, cy + sy * 0.16 * s, z + 0.07 * s,
                     0.64 * s, 0.15 * s, 0.14 * s, dark)
        self.box("%s_deck" % name, cx, cy, z + 0.17 * s, 0.52 * s, 0.40 * s, 0.07 * s, body)
        self.box("%s_house" % name, cx - 0.11 * s * face, cy, z + 0.34 * s,
                 0.34 * s, 0.34 * s, 0.28 * s, dark)
        self.box("%s_cab" % name, cx + 0.12 * s * face, cy, z + 0.33 * s,
                 0.17 * s, 0.24 * s, 0.26 * s, body)
        kn = (cx + 0.56 * s * face, cy, z + 0.70 * s)
        self.dircyl("%s_boom" % name, (cx + 0.12 * s * face, cy, z + 0.33 * s), kn,
                    0.035 * s, dark, segments=8)
        tip = (cx + 0.84 * s * face, cy, z + 0.14 * s)
        self.dircyl("%s_dipper" % name, kn, tip, 0.028 * s, dark, segments=8)
        self.box("%s_bucket" % name, tip[0] + 0.05 * s * face, cy, tip[1] * 0 + z + 0.08 * s,
                 0.16 * s, 0.20 * s, 0.16 * s, dark)

    # ------------------------- POWER PLANT -------------------------
    def cooling_tower(self, name, cx, cy, base_z, height, r_base=1.05, r_throat=0.66,
                      throat_frac=0.70, seg=32, rings=20, leg_h=0.30, legs=10, bands=3):
        """Natural-draught cooling tower: a TRUE hyperboloid shell standing on a ring of raking
        legs, with the throat about 0.7 of the way up.

        The profile is r(z) = r_t * sqrt(1 + ((z - z_t)/c)^2) with `c` SOLVED so the shell meets
        r_base at its foot — so the top flare is a consequence of the geometry rather than a
        second guess that has to be kept in sync. Smooth-shaded on purpose: unlike the pit walls
        (which need flat facets so their value steps read), this is one continuous curved
        surface, and Freestyle's external contour carries the silhouette.
        """
        if r_base <= r_throat:
            print("COOLING TOWER: r_base must exceed r_throat")
            return {}
        shell_z0 = base_z + leg_h
        sh = height - leg_h
        z_t = throat_frac * sh
        c = z_t / math.sqrt((r_base / r_throat) ** 2 - 1.0)

        def prof(zz):
            return r_throat * math.sqrt(1.0 + ((zz - z_t) / c) ** 2)

        m = bpy.data.meshes.new(name)
        bm = bmesh.new()
        grid = []
        for i in range(rings + 1):
            zz = sh * i / rings
            r = prof(zz)
            grid.append([bm.verts.new((cx + r * math.cos(2 * math.pi * j / seg),
                                       cy + r * math.sin(2 * math.pi * j / seg),
                                       shell_z0 + zz)) for j in range(seg)])
        for i in range(rings):
            for j in range(seg):
                k = (j + 1) % seg
                bm.faces.new([grid[i][j], grid[i][k], grid[i + 1][k], grid[i + 1][j]])
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        bm.to_mesh(m); bm.free()
        self.obj(name, m, self.mat("wall_shell"), True)

        r_top = prof(sh)
        # Rim + a dark disc sunk below it: the shell is a hollow chimney, and without the void
        # the top reads as a solid drum.
        self.washer("%s_rim" % name, (cx, cy, shell_z0 + sh), (0, 0, 1), r_top - 0.055, r_top + 0.02,
                    0.05, self.mat("scaffold"), seg=seg)
        self.cyl("%s_void" % name, cx, cy, shell_z0 + sh - 0.16, r_top - 0.06, 0.05,
                 self.mat("opening"), segments=seg)
        for b in range(1, bands + 1):
            zz = sh * b / (bands + 1.4)
            self.seam("%s_lift%d" % (name, b), cx, cy, shell_z0 + zz, prof(zz) + 0.012)

        # Raking colonnade: V-pairs converging on the shell foot, the classic air intake.
        self.washer("%s_ring" % name, (cx, cy, shell_z0), (0, 0, 1), r_base - 0.07, r_base + 0.03,
                    0.09, self.mat("scaffold"), seg=seg)
        for k in range(legs):
            a0 = 2 * math.pi * k / legs
            a1 = 2 * math.pi * (k + 1) / legs
            am = (a0 + a1) * 0.5
            apex = (cx + (r_base - 0.02) * math.cos(am), cy + (r_base - 0.02) * math.sin(am),
                    shell_z0)
            for a in (a0, a1):
                self.dircyl("%s_leg%d_%d" % (name, k, int(a * 100)),
                            (cx + (r_base + 0.05) * math.cos(a),
                             cy + (r_base + 0.05) * math.sin(a), base_z + 0.04),
                            apex, 0.045, self.mat("scaffold"), segments=6)
        def radius_at(z):
            """Shell radius at a WORLD height — so a caller can meet the shell exactly
            instead of guessing an offset that drifts whenever the tower is resized."""
            return prof(min(max(z - shell_z0, 0.0), sh))

        return {"top": shell_z0 + sh, "r_top": r_top, "r_base": r_base,
                "cx": cx, "cy": cy, "radius_at": radius_at}

    def flue_stack(self, name, cx, cy, base_z, height, r_base=0.36, r_top=0.30, bands=7,
                   seg=20, mat_a="hot", mat_b="window_frame"):
        """Slender steel flue in alternating hazard bands, with a slight uniform taper.

        The banding is done with TWO MATERIAL SLOTS on ONE mesh, not stacked cone segments and
        not proud collars. Stacked cones put coincident annulus caps at every band boundary and
        z-fight; proud collars pick up a Freestyle border and read as RINGS — which is exactly
        what a flue must not have (that is the cooling tower's language). Flush slots give a
        pure colour change: the linesets here select silhouette/border/crease, not material
        boundary, so nothing is drawn at the joins."""
        m = bpy.data.meshes.new(name)
        bm = bmesh.new()
        rings = []
        for b in range(bands + 1):
            t = float(b) / bands
            z = base_z + height * t
            r = r_base + (r_top - r_base) * t
            rings.append([bm.verts.new((cx + r * math.cos(2 * math.pi * j / seg),
                                        cy + r * math.sin(2 * math.pi * j / seg), z))
                          for j in range(seg)])
        for b in range(bands):
            for j in range(seg):
                k = (j + 1) % seg
                bm.faces.new([rings[b][j], rings[b][k], rings[b + 1][k], rings[b + 1][j]])
        bm.faces.new(list(reversed(rings[0])))
        bm.faces.new(rings[-1])
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        bm.to_mesh(m); bm.free()
        ob = self.obj(name, m, self.mat(mat_a), True)
        ob.data.materials.append(self.mat(mat_b))
        band_h = height / float(bands)
        for poly in m.polygons:
            b = int((poly.center.z - base_z) / band_h - 1e-6)
            poly.material_index = 1 if (max(0, min(bands - 1, b)) % 2) else 0
        # Open mouth + a base collar, so it terminates as a flue rather than a painted pole.
        self.cyl("%s_mouth" % name, cx, cy, base_z + height - 0.03, r_top - 0.045, 0.06,
                 self.mat("opening"), segments=seg)
        self.cyl("%s_foot" % name, cx, cy, base_z + 0.07, r_base + 0.035, 0.14,
                 self.mat("scaffold"), segments=seg)
        return {"top": base_z + height, "r_base": r_base, "r_top": r_top}

    def transformer(self, name, cx, cy, z, s=1.0, fins=4, accent=False):
        """Grid transformer: tank, radiator fin banks on both flanks, three HV bushings and a
        conservator drum. Silhouette-first — at sprite scale the bushings are what say
        'transformer' rather than 'crate', so they stay proud even when `s` is small."""
        body = self.mat("gear")
        _fm = self._fine_mode
        self._fine_mode = True
        self.box(name, cx, cy, z + 0.22 * s, 0.46 * s, 0.34 * s, 0.44 * s, body)
        self.box("%s_plinth" % name, cx, cy, z + 0.03 * s, 0.56 * s, 0.44 * s, 0.06 * s,
                 self.mat("wall_grey"))
        for side in (-1, 1):
            for f in range(fins):
                fy = cy + (f - (fins - 1) * 0.5) * 0.062 * s
                self.box("%s_fin%d_%d" % (name, side > 0, f), cx + side * 0.29 * s, fy,
                         z + 0.24 * s, 0.10 * s, 0.028 * s, 0.30 * s, self.mat("scaffold"))
        self.cyl("%s_cons" % name, cx - 0.10 * s, cy, z + 0.52 * s, 0.075 * s, 0.34 * s,
                 body, axis='Y', segments=14)
        for i in (-1, 0, 1):
            bx = cx + i * 0.14 * s
            self.cyl("%s_bush%d" % (name, i + 1), bx, cy, z + 0.52 * s, 0.030 * s, 0.16 * s,
                     self.mat("scaffold"), segments=10)
            for d in range(2):
                self.cyl("%s_ins%d_%d" % (name, i + 1, d), bx, cy,
                         z + 0.60 * s + d * 0.062 * s, 0.056 * s - d * 0.007 * s, 0.028 * s,
                         self.mat("window_frame"), segments=12)
        self.seam_bar("%s_seam" % name, cx, cy - 0.175 * s, z + 0.44 * s, 0.48 * s, 0.03, 0.03)
        if accent:
            self.box("%s_band" % name, cx, cy - 0.171 * s, z + 0.13 * s, 0.46 * s, 0.012,
                     0.07 * s, self.mat("power_accent"))
        self._fine_mode = _fm

    def lattice_mast(self, name, cx, cy, z0, z1, w=0.15, bays=4, mat=None):
        """Lattice is the densest ink in the set — always drawn as fine detail. `mat` lets a
        caller take it off the default dark scaffold tone: a crane mast in the SAME dark as
        the scaffolding beside it fuses with it, and the mast is meant to be the subject."""
        """Slim four-legged lattice mast with X-bracing on the two camera-facing sides. The
        substation twin of `headframe` — no batter, no head gear."""
        m = mat if mat is not None else self.mat("scaffold")
        _fm = self._fine_mode
        self._fine_mode = True
        corners = ((-1, -1), (1, -1), (1, 1), (-1, 1))
        for i, (sx, sy) in enumerate(corners):
            self.dircyl("%s_leg%d" % (name, i), (cx + sx * w / 2, cy + sy * w / 2, z0),
                        (cx + sx * w / 2, cy + sy * w / 2, z1), 0.022, m,
                        segments=6)
        for b in range(bays + 1):
            z = z0 + (z1 - z0) * b / bays
            for (ax, ay, bx, by) in ((-1, -1, 1, -1), (1, -1, 1, 1)):
                self.dircyl("%s_belt%d_%d" % (name, b, ax), (cx + ax * w / 2, cy + ay * w / 2, z),
                            (cx + bx * w / 2, cy + by * w / 2, z), 0.016, m,
                            segments=6)
        for b in range(bays):
            za = z0 + (z1 - z0) * b / bays
            zb = z0 + (z1 - z0) * (b + 1) / bays
            for (ax, ay, bx, by) in ((-1, -1, 1, -1), (1, -1, 1, 1)):
                self.dircyl("%s_x%d_%da" % (name, b, ax), (cx + ax * w / 2, cy + ay * w / 2, za),
                            (cx + bx * w / 2, cy + by * w / 2, zb), 0.013, m,
                            segments=6)
                self.dircyl("%s_x%d_%db" % (name, b, ax), (cx + ax * w / 2, cy + ay * w / 2, zb),
                            (cx + bx * w / 2, cy + by * w / 2, za), 0.013, m,
                            segments=6)
        self._fine_mode = _fm

    def insulator_string(self, name, x, y, z_top, drop, discs=4):
        """Suspension insulator: a hanging stack of discs. Reads as the thing that makes a
        substation a substation once there are three of them on a crossarm."""
        _fm = self._fine_mode
        self._fine_mode = True
        for d in range(discs):
            self.cyl("%s_d%d" % (name, d), x, y, z_top - drop * (d + 0.5) / discs, 0.036,
                     drop / discs * 0.55, self.mat("window_frame"), segments=10)
        self._fine_mode = _fm

    def pylon(self, name, cx, cy, base_z, height, w_base=0.60, tiers=3, insulators=True,
              arm_len=None, peak=True):
        """Lattice transmission pylon in the British L-series shape (owner reference photo).

        Three things make that silhouette, and all three are easy to lose:
          * a KINKED mast — splayed feet narrowing hard to a shoulder at ~45% height, then
            near-parallel through the arm zone. A single straight batter reads as a mast, not
            a pylon.
          * TRIANGULAR cantilever arms: a horizontal top chord and a bottom chord raking up to
            meet it at the tip, webbed between. A plain bar per arm reads as a stray line.
          * arms that LENGTHEN downward, so the stack tapers as a whole.
        `tiers` counts arm LEVELS; each is a pair, so 1/2/3 tiers give the 2/4/6 arms asked for.
        Drawn in FINE ink — lattice is the densest linework in the set and fills in solid at the
        standard 2.4px.
        """
        _fm = self._fine_mode
        self._fine_mode = True
        steel = self.mat("scaffold")
        body_h = height * (0.92 if peak else 1.0)
        top = base_z + body_h
        w_mid = w_base * 0.42
        w_top = w_base * 0.30
        sh_t = 0.45                                   # shoulder, as a fraction of the body
        arm_len = arm_len if arm_len is not None else w_base * 0.95

        def half_at(z):
            t = max(0.0, min(1.0, (z - base_z) / body_h))
            if t <= sh_t:
                return (w_base + (w_mid - w_base) * (t / sh_t)) / 2.0
            return (w_mid + (w_top - w_mid) * ((t - sh_t) / (1.0 - sh_t))) / 2.0

        corners = ((-1, -1), (1, -1), (1, 1), (-1, 1))
        z_sh = base_z + body_h * sh_t
        for i, (sx, sy) in enumerate(corners):
            for tag, (za, zb) in (("lo", (base_z, z_sh)), ("hi", (z_sh, top))):
                ha, hb = half_at(za), half_at(zb)
                self.dircyl("%s_leg%s%d" % (name, tag, i), (cx + sx * ha, cy + sy * ha, za),
                            (cx + sx * hb, cy + sy * hb, zb), 0.017, steel, segments=6)
        # Belts and X-bracing, denser below the shoulder where the taper is fastest.
        edges = ((-1, -1, 1, -1), (1, -1, 1, 1), (1, 1, -1, 1), (-1, 1, -1, -1))
        faces = ((-1, -1, 1, -1), (1, -1, 1, 1))      # only the two the camera sees
        zs = ([base_z + (z_sh - base_z) * k / 3.0 for k in range(4)]
              + [z_sh + (top - z_sh) * k / 4.0 for k in range(1, 5)])
        for k, z in enumerate(zs):
            h = half_at(z)
            for (ax, ay, bx, by) in edges:
                self.dircyl("%s_belt%d_%d%d" % (name, k, ax, ay),
                            (cx + ax * h, cy + ay * h, z), (cx + bx * h, cy + by * h, z),
                            0.011, steel, segments=6)
        for k in range(len(zs) - 1):
            za, zb = zs[k], zs[k + 1]
            ha, hb = half_at(za), half_at(zb)
            for (ax, ay, bx, by) in faces:
                self.dircyl("%s_x%d_%d%da" % (name, k, ax, ay),
                            (cx + ax * ha, cy + ay * ha, za), (cx + bx * hb, cy + by * hb, zb),
                            0.009, steel, segments=6)
                self.dircyl("%s_x%d_%d%db" % (name, k, ax, ay),
                            (cx + ax * ha, cy + ay * ha, zb), (cx + bx * hb, cy + by * hb, za),
                            0.009, steel, segments=6)

        # Arm tiers, counted DOWN from the head so the top arm always sits just under the peak.
        for t in range(tiers):
            az = base_z + body_h * (0.93 - 0.20 * t)
            h = half_at(az)
            L = arm_len * (1.0 + 0.20 * t)            # lower arms reach further
            dep = height * 0.055                      # cantilever depth at the mast
            for sgn in (-1, 1):
                root_y = cy + sgn * h
                tip_y = cy + sgn * (h + L)
                tip_z = az + dep * 0.30
                self.dircyl("%s_a%d_%d_top" % (name, t, sgn > 0), (cx, root_y, az + dep),
                            (cx, tip_y, tip_z), 0.012, steel, segments=6)
                self.dircyl("%s_a%d_%d_bot" % (name, t, sgn > 0), (cx, root_y, az - dep * 0.5),
                            (cx, tip_y, tip_z), 0.012, steel, segments=6)
                for k in (0.34, 0.67):
                    wy = root_y + (tip_y - root_y) * k
                    zt = (az + dep) + (tip_z - (az + dep)) * k
                    zb = (az - dep * 0.5) + (tip_z - (az - dep * 0.5)) * k
                    self.dircyl("%s_a%d_%d_w%d" % (name, t, sgn > 0, int(k * 100)),
                                (cx, wy, zb), (cx, wy, zt), 0.008, steel, segments=6)
                self.dircyl("%s_a%d_%d_d" % (name, t, sgn > 0), (cx, root_y, az + dep),
                            (cx, root_y + (tip_y - root_y) * 0.67, az - dep * 0.5 +
                             (tip_z - (az - dep * 0.5)) * 0.67), 0.008, steel, segments=6)
                if insulators:
                    self.insulator_string("%s_ins%d_%d" % (name, t, sgn > 0), cx, tip_y,
                                          tip_z - 0.02, height * 0.085, discs=3)
        if peak:
            pk = base_z + height
            hp = half_at(top)
            for i, (sx, sy) in enumerate(corners):
                self.dircyl("%s_pk%d" % (name, i), (cx + sx * hp, cy + sy * hp, top),
                            (cx, cy, pk), 0.010, steel, segments=6)
        self._fine_mode = _fm
        return {"top": base_z + height,
                "half_y": half_at(base_z + body_h * (0.93 - 0.20 * max(0, tiers - 1)))
                          + arm_len * (1.0 + 0.20 * max(0, tiers - 1))}

    def substation_gantry(self, name, p0, p1, z0, height, strings=3, busbar=True, bays=1):
        """Takeoff gantry between two ground points: lattice masts, an upper crossarm carrying
        suspension insulator strings, and busbars dropping to equipment height. Takes ENDPOINTS
        rather than an axis + span so the run can lie along x, along y, or on a diagonal — a
        substation reads best drawn across the free frontage, whichever way that runs."""
        n = max(1, bays) + 1
        pts = [(p0[0] + (p1[0] - p0[0]) * i / (n - 1), p0[1] + (p1[1] - p0[1]) * i / (n - 1))
               for i in range(n)]
        for i, (mx, my) in enumerate(pts):
            self.lattice_mast("%s_m%d" % (name, i), mx, my, z0, z0 + height)
        for k, hz in enumerate((height, height * 0.70)):
            self.dircyl("%s_arm%d" % (name, k), (p0[0], p0[1], z0 + hz),
                        (p1[0], p1[1], z0 + hz), 0.022, self.mat("scaffold"), segments=6)
        total = max(1, strings)
        for i in range(total):
            f = (i + 1) / (total + 1)
            sx = p0[0] + (p1[0] - p0[0]) * f
            sy = p0[1] + (p1[1] - p0[1]) * f
            self.insulator_string("%s_s%d" % (name, i), sx, sy, z0 + height, height * 0.22)
            if busbar:
                self.dircyl("%s_bus%d" % (name, i), (sx, sy, z0 + height * 0.78),
                            (sx, sy, z0 + height * 0.26), 0.014, self.mat("pipe"), segments=6)

    def turbine(self, name, cx, cy, z, length=1.5, s=1.0, accent=False):
        """Steam turbine-generator set on its plinth, laid along +X: HP cylinder, two stepping
        LP casings, the generator drum and an end bearing pedestal. Stepping the casing
        diameters is what separates it from a plain pipe at sprite scale."""
        body, steel = self.mat("gear"), self.mat("scaffold")
        self.box("%s_plinth" % name, cx, cy, z + 0.05 * s, length + 0.24 * s, 0.60 * s,
                 0.10 * s, self.mat("wall_grey"))
        segs = ((0.20, 0.15), (0.26, 0.20), (0.30, 0.24), (0.24, 0.30))
        total = sum(w for w, _ in segs)
        x = cx - length / 2.0
        for i, (wfrac, r) in enumerate(segs):
            seg_w = length * wfrac / total
            self.cyl("%s_c%d" % (name, i), x + seg_w / 2.0, cy, z + 0.34 * s, r * s, seg_w,
                     body, axis='X', segments=20)
            if i:
                self.washer("%s_flange%d" % (name, i), (x, cy, z + 0.34 * s), (1, 0, 0),
                            r * s * 0.72, r * s + 0.022 * s, 0.030 * s, steel, seg=20)
            x += seg_w
        self.cyl("%s_gen" % name, cx + length * 0.42, cy, z + 0.34 * s, 0.19 * s, length * 0.30,
                 steel, axis='X', segments=18)
        for px in (cx - length * 0.52, cx + length * 0.58):
            self.box("%s_brg%d" % (name, int(px * 100)), px, cy, z + 0.20 * s, 0.14 * s,
                     0.42 * s, 0.24 * s, self.mat("wall_grey"))
        if accent:
            self.box("%s_band" % name, cx + length * 0.42, cy - 0.20 * s, z + 0.34 * s,
                     length * 0.28, 0.012, 0.07 * s, self.mat("power_accent"))

    # ------------------------- PROCESS PLANT (refineries) -------------------------
    # Ported from the superseded `refinery_kit.py` fork. Its SHAPES were good and are kept
    # verbatim where they were earned; what is NOT kept is its authoring system. That fork
    # composed in screen space via an SD(s, d) helper, which put every long run along the
    # world x+y diagonal — dead horizontal on screen, and the reason its refineries read as
    # flat and wide. Everything here takes WORLD coordinates, so long elements slope at the
    # set's iso grammar like every other building. (S/D is still the right algebra for
    # CHECKING a placement — see the occlusion note — just never for authoring one.)

    def helix_band(self, name, cx, cy, r_in, r_out, z0, z1, turns, start_deg, thick, mat,
                   steps=26):
        """ONE mesh describing a helical ribbon. Building the same shape from per-tread boxes
        is the trap: Freestyle inks every box, so a spiral stair comes out as a chain of
        outlined crates. As a single surface it inks only its own silhouette. The same logic
        applies to any ramp, band or gallery."""
        m = bpy.data.meshes.new(name)
        bm = bmesh.new()
        rings = []
        for k in range(steps + 1):
            f = k / steps
            a = math.radians(start_deg + turns * 360.0 * f)
            z = z0 + (z1 - z0) * f
            ca, sa = math.cos(a), math.sin(a)
            rings.append([bm.verts.new((cx + rr * ca, cy + rr * sa, z + dz))
                          for rr, dz in ((r_in, 0.0), (r_out, 0.0),
                                         (r_out, -thick), (r_in, -thick))])
        for k in range(steps):
            A, B = rings[k], rings[k + 1]
            for i in range(4):
                j = (i + 1) % 4
                bm.faces.new([A[i], A[j], B[j], B[i]])
        bm.faces.new(list(reversed(rings[0])))
        bm.faces.new(rings[-1])
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        bm.to_mesh(m); bm.free()
        return self.obj(name, m, mat)

    def spiral_stair(self, name, cx, cy, r, z0, z1, turns=0.55, start_deg=-118.0, steps=26):
        """Stair winding up the outside of a tank: one ribbon plus a handrail. Starts on the
        camera-facing quadrant so the visible run climbs up-and-right and the back half
        disappears behind the shell."""
        self.helix_band(name, cx, cy, r + 0.025, r + 0.195, z0, z1, turns, start_deg, 0.055,
                        self.mat("stair"), steps=steps)
        ro = r + 0.175
        pts = []
        for k in range(steps + 1):
            f = k / steps
            a = math.radians(start_deg + turns * 360.0 * f)
            pts.append((cx + ro * math.cos(a), cy + ro * math.sin(a),
                        z0 + (z1 - z0) * f, math.degrees(a)))
        for k in range(steps):
            (ax, ay, az, _), (bx, by, bz, _) = pts[k], pts[k + 1]
            self.dircyl("%s_rail%d" % (name, k), (ax, ay, az + 0.26), (bx, by, bz + 0.26),
                        0.023, self.mat("handrail"), segments=6)
            if k % 6 == 0:
                self.dircyl("%s_post%d" % (name, k), (ax, ay, az), (ax, ay, az + 0.26), 0.021,
                            self.mat("handrail"), segments=6)
        ex, ey, ez, ea = pts[-1]
        self.rotbox("%s_landing" % name, ex, ey, ez + 0.01, 0.26, 0.30, 0.05,
                    self.mat("stair"), 'Z', ea)

    def frac_column(self, name, cx, cy, top, r, trays=7, tray_z0=0.62, band=True,
                    platforms=(), draws=(), skirt_h=0.40):
        """Fractionating column — the shape that says PETROLEUM. Tall and slender on a plain
        skirt, banded with tray rings the whole way up, closed by a domed head.

        Earned numbers, do not re-derive: tray rings must read as ink LINES (r+0.020,
        t=0.028) — at t=0.048 they became a spine of vertebrae; platforms at r+0.19, because
        r+0.32 is a lampshade that hides the column entirely. The head is a SPHERE sunk to
        its equator, not a disc lid, so Freestyle has no uninked T-junction to miss.
        Returns (cx, cy, nozzles) for hanging downcomers."""
        self.cyl("%s_skirt" % name, cx, cy, skirt_h / 2, r + 0.015, skirt_h,
                 self.mat("scaffold"))
        self.seam("%s_skirtseam" % name, cx, cy, skirt_h, r + 0.030)
        z0 = skirt_h - 0.04
        self.cyl(name, cx, cy, (z0 + top) / 2, r, top - z0, self.mat("column"))
        tray_top = top - 0.55
        for i in range(trays):
            z = tray_z0 + (tray_top - tray_z0) * i / max(1, trays - 1)
            self.seam("%s_tray%d" % (name, i), cx, cy, z, r + 0.020, t=0.028)
        self.sphere("%s_head" % name, cx, cy, top, r, self.mat("column"))
        self.seam("%s_headseam" % name, cx, cy, top, r + 0.020)
        if band:
            bz = top - 0.36
            self.cyl("%s_band" % name, cx, cy, bz, r + 0.020, 0.22, self.mat("accent"))
            for tag, dz in (("lo", -0.11), ("hi", 0.11)):
                self.seam("%s_bandseam_%s" % (name, tag), cx, cy, bz + dz, r + 0.032)
        # Platform width is PROPORTIONAL to the column, not a fixed offset. The inherited
        # value (r + 0.19) was earned on r=0.42 columns, where it is 45% of the radius; reused
        # on a properly slender r=0.27 column it becomes 70% and they are lampshades again —
        # which is exactly what made the first slimming pass look like it had done nothing.
        pw = max(0.10, r * 0.45)
        for j, pz in enumerate(platforms):
            self.washer("%s_plat%d" % (name, j), (cx, cy, pz), (0, 0, 1), r + 0.010, r + pw,
                        0.050, self.mat("walkway"))
            # Solid parapet ring, not posts+rail: 0.04 posts fall under the ink width and
            # turn to scribble.
            self.washer("%s_rail%d" % (name, j), (cx, cy, pz + 0.100), (0, 0, 1),
                        r + pw - 0.028, r + pw, 0.15, self.mat("handrail"))
        nozzles = []
        for j, dz in enumerate(draws):
            # FANNED, and aimed at the camera normal: on the -Y side of a cylinder a nozzle
            # grazes the silhouette and half-vanishes, and co-aimed draws make coaxial
            # (invisible) downcomers.
            a = math.radians(-45.0 + (j - (len(draws) - 1) / 2.0) * 24.0)
            n = (math.cos(a), math.sin(a), 0.0)
            p0 = (cx + n[0] * (r - 0.05), cy + n[1] * (r - 0.05), dz)
            p1 = (cx + n[0] * (r + 0.22), cy + n[1] * (r + 0.22), dz)
            self.dircyl("%s_draw%d" % (name, j), p0, p1, 0.052, self.mat("pipe"), segments=12)
            self.washer("%s_drawflange%d" % (name, j), p1, n, 0.055, 0.100, 0.04,
                        self.M["seam"], seg=14)
            nozzles.append(p1)
        return cx, cy, nozzles

    def flat_tank(self, name, cx, cy, r, h, band=True, stair=True, vent=True, mat=None,
                  base_band=False, roof_rise=0.11):
        """Flat-topped storage tank. The dark curb rim is what makes the top read FLAT — a
        bare cone cap reads as a dome at this size."""
        body = mat if mat is not None else self.mat("column")
        self.cyl(name, cx, cy, h / 2, r, h, body)
        self.seam("%s_girder" % name, cx, cy, h * 0.60, r + 0.016)
        self.cyl("%s_curb" % name, cx, cy, h + 0.025, r + 0.020, 0.065, self.mat("scaffold"))
        # `roof_rise` is fixed, not scaled off r: on a WIDE tank a proportional cone becomes a
        # visible cap and the tank reads as a lidded pot rather than as flat-topped.
        self.cone("%s_roof" % name, cx, cy, h + 0.058 + roof_rise / 2, r + 0.002, r * 0.34,
                  roof_rise, body)
        if vent:
            self.cyl("%s_vent" % name, cx, cy, h + 0.26, 0.070, 0.20, self.mat("pipe"),
                     segments=12)
            self.cone("%s_venthood" % name, cx, cy, h + 0.385, 0.105, 0.02, 0.09,
                      self.mat("opening"), segments=12)
        if band:
            bz = h * 0.46
            self.cyl("%s_band" % name, cx, cy, bz, r + 0.014, 0.19, self.mat("accent"))
            for tag, dz in (("lo", -0.095), ("hi", 0.095)):
                self.seam("%s_bandseam_%s" % (name, tag), cx, cy, bz + dz, r + 0.026)
        if base_band:
            self.cyl("%s_baseband" % name, cx, cy, 0.13, r + 0.016, 0.26, self.mat("accent"))
            for tag, dz in (("lo", -0.13), ("hi", 0.13)):
                self.seam("%s_basebandseam_%s" % (name, tag), cx, cy, 0.13 + dz, r + 0.028)
        if stair:
            self.spiral_stair("%s_stair" % name, cx, cy, r, 0.10, h + 0.06)

    def dome_cap(self, name, cx, cy, z0, r, h, mat, seg=32, rings=8):
        """Half-ellipsoid cap: radius r, rise h. A tank's dome is a SHALLOW cap (h ~ 0.35r),
        not a hemisphere — capping a shell with a full sphere makes the dome as tall as the
        tank's own radius, which is what makes a vessel read as an ambiguous blob rather than
        as a tank. Keep `h` well under `r` for storage; use h == r only for a true sphere."""
        m = bpy.data.meshes.new(name)
        bm = bmesh.new()
        grid = []
        for i in range(rings + 1):
            t = (math.pi / 2.0) * i / rings
            rr, zz = r * math.cos(t), h * math.sin(t)
            grid.append([bm.verts.new((cx + rr * math.cos(2 * math.pi * j / seg),
                                       cy + rr * math.sin(2 * math.pi * j / seg), z0 + zz))
                         for j in range(seg)])
        for i in range(rings):
            for j in range(seg):
                k = (j + 1) % seg
                bm.faces.new([grid[i][j], grid[i][k], grid[i + 1][k], grid[i + 1][j]])
        bm.faces.new(list(reversed(grid[0])))
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        bm.to_mesh(m); bm.free()
        return self.obj(name, m, mat, True)

    def sphere_tank(self, name, cx, cy, r, legs=6, ladder=True, band=False, mat=None):
        """Horton sphere on braced legs — the pressurised-storage shape, and unmistakable
        beside cylinders. Sits with its equator at `r * 1.35` so the legs read as legs."""
        cz = r * 1.35
        # Milder darkening than the cylinders get: the sphere's base is the darkest tone in
        # the set, and the curve is steepest down there, so a uniform multiplier that reads as
        # a shaded face on steel turns a drum-toned sphere near-black.
        self.gloss(self.sphere(name, cx, cy, cz, r,
                               mat if mat is not None else self.mat("column")),
                   dark=0.60, light=2.60)
        self.seam("%s_eq" % name, cx, cy, cz, r + 0.012)
        if band:
            self.cyl("%s_band" % name, cx, cy, cz - r * 0.62, r * 0.80, 0.14,
                     self.mat("accent"), segments=28)
        _fm = self._fine_mode
        self._fine_mode = True
        for i in range(legs):
            a = 2 * math.pi * i / legs
            fx, fy = cx + r * 0.92 * math.cos(a), cy + r * 0.92 * math.sin(a)
            tx, ty = cx + r * 0.70 * math.cos(a), cy + r * 0.70 * math.sin(a)
            self.dircyl("%s_leg%d" % (name, i), (fx, fy, 0.0), (tx, ty, cz), 0.042,
                        self.mat("scaffold"), segments=8)
            a2 = 2 * math.pi * (i + 1) / legs
            gx, gy = cx + r * 0.92 * math.cos(a2), cy + r * 0.92 * math.sin(a2)
            self.dircyl("%s_brace%d" % (name, i), (fx, fy, cz * 0.52), (gx, gy, cz * 0.30),
                        0.022, self.mat("scaffold"), segments=6)
        if ladder:
            self.helix_band("%s_stair" % name, cx, cy, r * 0.98, r * 1.16, 0.10, cz + r * 0.55,
                            0.42, -120.0, 0.05, self.mat("stair"), steps=22)
        self._fine_mode = _fm
        return cz

    def dome_vessel(self, name, cx, cy, r, h, skirt=0.30, agit=False, band_z=None,
                    seams=(0.35, 0.70), dome_ratio=0.42, base_band=False, mat=None):
        """Tall dome-topped process vessel. Shared vocabulary: a petrochem knock-out drum and
        a polymer reactor are the same shell — `agit` is what makes it a STIRRED reactor."""
        if skirt:
            self.cyl("%s_skirt" % name, cx, cy, skirt / 2, r + 0.014, skirt,
                     self.mat("scaffold"))
            self.seam("%s_skirtseam" % name, cx, cy, skirt, r + 0.028)
        z0 = max(0.0, skirt - 0.04)
        body = mat if mat is not None else self.mat("column")
        self.gloss(self.cyl(name, cx, cy, (z0 + h) / 2, r, h - z0, body))
        for k in seams:
            self.seam("%s_seam%d" % (name, int(k * 100)), cx, cy, z0 + (h - z0) * k, r + 0.016)
        # SHALLOW cap, not a hemisphere (see dome_cap): `dome_ratio` is the rise as a
        # fraction of the radius. At 1.0 the dome is as tall as the tank is wide and the
        # vessel stops reading as a tank at all.
        self.gloss(self.dome_cap("%s_dome" % name, cx, cy, h, r, r * dome_ratio, body))
        self.seam("%s_domeseam" % name, cx, cy, h, r + 0.020)
        if base_band:
            self.cyl("%s_baseband" % name, cx, cy, max(0.10, skirt) + 0.11, r + 0.016, 0.22,
                     self.mat("accent"))
            for tag, dz in (("lo", -0.11), ("hi", 0.11)):
                self.seam("%s_basebandseam_%s" % (name, tag), cx, cy,
                          max(0.10, skirt) + 0.11 + dz, r + 0.028)
        if band_z is not None:
            self.cyl("%s_band" % name, cx, cy, band_z, r + 0.016, 0.18, self.mat("accent"))
            for tag, dz in (("lo", -0.09), ("hi", 0.09)):
                self.seam("%s_bandseam_%s" % (name, tag), cx, cy, band_z + dz, r + 0.028)
        if agit:
            self.agitator("%s_agit" % name, cx, cy, h + r - 0.04, s=max(0.72, r / 0.55))

    def agitator(self, name, cx, cy, z, s=1.0):
        """Top-entry agitator drive: pedestal, gearbox, motor. Bolted to a crown it is the
        one detail separating a stirred reactor from a storage vessel at sprite size."""
        self.cyl("%s_ped" % name, cx, cy, z + 0.06 * s, 0.19 * s, 0.14 * s,
                 self.mat("scaffold"), segments=16)
        self.seam("%s_pedseam" % name, cx, cy, z + 0.13 * s, 0.20 * s)
        self.box("%s_gear" % name, cx, cy, z + 0.29 * s, 0.31 * s, 0.27 * s, 0.30 * s,
                 self.mat("gear"))
        self.seam_bar("%s_gearseam" % name, cx, cy - 0.136 * s, z + 0.44 * s, 0.33 * s,
                      0.03, 0.03)
        self.cyl("%s_motor" % name, cx, cy, z + 0.58 * s, 0.105 * s, 0.28 * s,
                 self.mat("drum"), segments=16)
        self.cyl("%s_fan" % name, cx, cy, z + 0.75 * s, 0.075 * s, 0.07 * s,
                 self.mat("scaffold"), segments=12)

    def pellet_silo(self, name, cx, cy, r, leg_top, hopper_h, top, accent=True):
        """Hopper-bottomed pellet silo on legs — THE polymer-plant giveaway. A liquids plant
        stores in flat-bottomed tanks on the ground; only a granular SOLID needs a cone
        discharging into a truck, so the raised cone is the point and carries the accent."""
        hop_top = leg_top + hopper_h
        for i, (sx, sy) in enumerate(((-1, -1), (1, -1), (1, 1), (-1, 1))):
            lx, ly = cx + sx * r * 0.62, cy + sy * r * 0.62
            self.dircyl("%s_leg%d" % (name, i), (lx, ly, 0.0), (lx, ly, hop_top + 0.10),
                        0.048, self.mat("scaffold"), segments=8)
        self.cone("%s_hopper" % name, cx, cy, leg_top + hopper_h / 2, r * 0.16, r, hopper_h,
                  self.mat("accent") if accent else self.mat("drum"))
        self.seam("%s_hopseam" % name, cx, cy, hop_top, r + 0.020)
        self.washer("%s_ringbeam" % name, (cx, cy, hop_top + 0.02), (0, 0, 1), r + 0.004,
                    r + 0.075, 0.045, self.mat("scaffold"))
        self.cyl(name, cx, cy, (hop_top + top) / 2, r, top - hop_top, self.mat("column"))
        for k in (35, 70):
            self.seam("%s_strake%d" % (name, k), cx, cy, hop_top + (top - hop_top) * k / 100.0,
                      r + 0.015)
        self.cone("%s_roof" % name, cx, cy, top + 0.105, r + 0.010, r * 0.26, 0.21,
                  self.mat("column"))
        self.cyl("%s_inlet" % name, cx, cy, top + 0.30, 0.055, 0.24, self.mat("pipe"),
                 segments=12)
        self.cyl("%s_spout" % name, cx, cy, leg_top - 0.07, r * 0.17, 0.20,
                 self.mat("scaffold"), segments=14)
        return top

    def bullet(self, name, p0, p1, r, saddles=True):
        """Horizontal pressure vessel with dished ends on saddles — the LPG/product bullet.
        Takes WORLD endpoints: run it along a world axis so it slopes with the iso grid.
        Its long low silhouette is one nothing else on either refinery has."""
        import mathutils
        A, B = mathutils.Vector(p0), mathutils.Vector(p1)
        self.dircyl(name, p0, p1, r, self.mat("drum"), segments=28)
        for tag, P in (("0", A), ("1", B)):
            self.sphere("%s_head%s" % (name, tag), P.x, P.y, P.z, r, self.mat("drum"))
        u = (B - A).normalized()
        for tag, f in (("a", 0.16), ("b", 0.84)):
            M = A + (B - A) * f
            self.washer("%s_ring%s" % (name, tag), tuple(M), tuple(u), r + 0.005, r + 0.045,
                        0.035, self.M["seam"], seg=20)
            if saddles:
                ang = math.degrees(math.atan2(u.y, u.x))
                self.rotbox("%s_saddle%s" % (name, tag), M.x, M.y, max(0.06, M.z - r + 0.02) / 2,
                            0.20, r * 1.5, max(0.06, M.z - r + 0.02), self.mat("yard"), 'Z', ang)

    def derrick(self, name, cx, cy, z0, z1, w0, w1, bays=5, leg_r=0.026):
        """Tapering four-leg lattice tower, X-braced on the two camera-facing sides only."""
        _fm = self._fine_mode
        self._fine_mode = True

        def half(z):
            f = (z - z0) / (z1 - z0) if z1 > z0 else 0.0
            return (w0 + (w1 - w0) * f) / 2.0

        corners = ((-1, -1), (1, -1), (1, 1), (-1, 1))
        for i, (sx, sy) in enumerate(corners):
            self.dircyl("%s_leg%d" % (name, i), (cx + sx * half(z0), cy + sy * half(z0), z0),
                        (cx + sx * half(z1), cy + sy * half(z1), z1), leg_r,
                        self.mat("scaffold"), segments=6)
        faces = ((-1, -1, 1, -1), (1, -1, 1, 1))
        for b in range(bays + 1):
            z = z0 + (z1 - z0) * b / bays
            h = half(z)
            for (ax, ay, bx, by) in faces:
                self.dircyl("%s_belt%d_%d" % (name, b, ax), (cx + ax * h, cy + ay * h, z),
                            (cx + bx * h, cy + by * h, z), leg_r * 0.62,
                            self.mat("scaffold"), segments=6)
        for b in range(bays):
            za, zb = z0 + (z1 - z0) * b / bays, z0 + (z1 - z0) * (b + 1) / bays
            ha, hb = half(za), half(zb)
            for (ax, ay, bx, by) in faces:
                self.dircyl("%s_x%d_%da" % (name, b, ax), (cx + ax * ha, cy + ay * ha, za),
                            (cx + bx * hb, cy + by * hb, zb), leg_r * 0.5,
                            self.mat("scaffold"), segments=6)
                self.dircyl("%s_x%d_%db" % (name, b, ax), (cx + ax * ha, cy + ay * ha, zb),
                            (cx + bx * hb, cy + by * hb, za), leg_r * 0.5,
                            self.mat("scaffold"), segments=6)
        self._fine_mode = _fm

    def flare_tip(self, name, cx, cy, top, r=0.13):
        """Flare burner and flame — THE petroleum landmark and the plant's one warm accent.
        The plume is stacked cones leaning toward screen-right; a single cone reads as a
        traffic cone, and anything fussier turns to mush under the 7px contour."""
        self.cyl("%s_shield" % name, cx, cy, top + 0.10, r + 0.075, 0.30,
                 self.mat("scaffold"))
        for tag, dz in (("lo", -0.14), ("hi", 0.14)):
            self.seam("%s_shieldseam_%s" % (name, tag), cx, cy, top + 0.10 + dz, r + 0.088)
        em = self.M["ember"]
        lean = 0.085                                   # per stage, along +x+y = screen right
        z = top + 0.26
        self.cone("%s_f0" % name, cx + lean * 0.4, cy + lean * 0.4, z + 0.15, r + 0.01,
                  r + 0.10, 0.30, em, segments=20)
        self.cone("%s_f1" % name, cx + lean * 1.6, cy + lean * 1.6, z + 0.50, r + 0.10,
                  r + 0.02, 0.44, em, segments=20)
        self.cone("%s_f2" % name, cx + lean * 3.2, cy + lean * 3.2, z + 1.02, r + 0.02,
                  0.008, 0.62, em, segments=20)

    def flame(self, name, cx, cy, z0, r0, h, mat, seg=26, rings=20, lean=0.0, bulge=0.32):
        """A flame as ONE lofted mesh, shaped as a tilted DROPLET: round wide base, widest a
        third of the way up, tapering to a sharp tip.

        Two things make that read. The base is a QUARTER-CIRCLE in profile — radius zero at the
        very bottom, curving out to full width — which is what gives a droplet its rounded
        underside; a profile that simply starts at full width reads as a cone stood on a flat
        bottom. Above the bulge the sides are CONCAVE (exponent > 1), which is what sharpens
        the tip: a linear taper from the same widest point gives a traffic cone.

        Stacked cones do not work here. Freestyle inks every object, so a multi-cone plume
        renders as separate outlined party hats with air between them — same rule as the tank
        stairs, a swept form must be a single mesh.

        Tessellated finer than the kit's usual 12-16: the radius collapses fast above the
        bulge, so a coarse ring count puts a visible facet notch in the SILHOUETTE, where the
        contour ink then traces the kink."""
        def prof(t):
            if t <= bulge:                             # rounded underside
                u = (t - bulge) / bulge                # -1 -> 0
                return r0 * math.sqrt(max(0.0, 1.0 - u * u))
            # sin(), not a plain power. Both give a sharp tip, but a power law leaves the
            # slope jumping from 0 to -2.35*r0 at the join, and that CORNER shows as a notch
            # in the silhouette which the contour ink then traces. sin() arrives at the bulge
            # with zero slope, matching the quarter-circle below it.
            v = (1.0 - t) / (1.0 - bulge)              # 1 -> 0
            return r0 * math.sin(math.pi * 0.5 * v) ** 2.2

        m = bpy.data.meshes.new(name)
        bm = bmesh.new()
        bot = bm.verts.new((cx, cy, z0))               # the droplet's bottom IS a point
        grid = []
        for i in range(1, rings):
            t = i / float(rings)
            rr = prof(t)
            off = lean * (t ** 1.8) * 0.7071           # lean loaded at the tip, so it curls
            grid.append([bm.verts.new((cx + off + rr * math.cos(2 * math.pi * j / seg),
                                       cy + off + rr * math.sin(2 * math.pi * j / seg),
                                       z0 + h * t)) for j in range(seg)])
        tipo = lean * 0.7071
        tip = bm.verts.new((cx + tipo, cy + tipo, z0 + h))
        for j in range(seg):
            k = (j + 1) % seg
            bm.faces.new([bot, grid[0][k], grid[0][j]])
            bm.faces.new([grid[-1][j], grid[-1][k], tip])
        for i in range(len(grid) - 1):
            for j in range(seg):
                k = (j + 1) % seg
                bm.faces.new([grid[i][j], grid[i][k], grid[i + 1][k], grid[i + 1][j]])
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        bm.to_mesh(m); bm.free()
        return self.obj(name, m, mat, True)

    def tone(self, src, factor, tag):
        """Cached tonal variant of a MATERIAL: same hue, scaled value. Derived from the
        material's own base colour rather than from a palette name, so it works on whatever
        the caller actually assigned — passing a name meant guessing it back at the call site.

        Value only. Shift the hue and the band reads as a different material bolted on rather
        than as a lit and shaded face of the same shell."""
        key = "%s_%s" % (src.name, tag)
        mt = bpy.data.materials.get(key)
        if mt is not None:
            return mt
        sb = src.node_tree.nodes.get("Principled BSDF").inputs["Base Color"].default_value
        rgb = tuple(min(0.95, sb[i] * factor) for i in range(3))
        mt = bpy.data.materials.new(key)
        mt.use_nodes = True
        b = mt.node_tree.nodes.get("Principled BSDF")
        b.inputs["Base Color"].default_value = (*rgb, 1)
        b.inputs["Roughness"].default_value = 1.0
        if "Specular IOR Level" in b.inputs:
            b.inputs["Specular IOR Level"].default_value = 0.0
        return mt

    def gloss(self, ob, dark=0.46, light=1.95, dark_from=0.30,
              glint=(-0.95, -0.63), cap=0.15):
        """Fake reflection: hard-edged tonal banding down a curved shell, the flat-art trick
        for making a cylinder read as metal without a gradient.

        Banding is by SCREEN POSITION, not by azimuth in the abstract. For a face whose
        horizontal normal is (cos t, sin t), `u = cos(t - 45deg)` is exactly where that face
        sits across the shell's screen width: -1 at the left silhouette, 0 at the point facing
        the camera, +1 at the right. So `dark_from` and `glint` are read directly as fractions
        of the visible width, which is how the look is actually judged.

        Extra material SLOTS on the one mesh — never proud geometry. Freestyle's linesets do
        not select material boundaries, so the bands land hard-edged and un-inked, which is
        the point; a separate band object would get its own 7px contour and read as a collar.

        Caps are left at base tone (`cap` is the horizontal-normal cut-off) — a dome's apex
        banded the same way puts a hard horizontal seam across the top of the vessel."""
        me = ob.data
        if not me.materials:
            return ob
        me.materials.append(self.tone(me.materials[0], dark, "shade"))
        me.materials.append(self.tone(me.materials[0], light, "glint"))
        k = 1.0 / math.sqrt(2.0)
        for poly in me.polygons:
            n = poly.normal
            h = math.hypot(n.x, n.y)
            if h < cap:
                continue
            u = (n.x + n.y) * k / h
            if u > dark_from:
                poly.material_index = 1
            elif glint[0] < u < glint[1]:
                poly.material_index = 2
        return ob

    def furnace_stack(self, name, cx, cy, r, h, base=0.36, flame=True, mat=None, seg=20,
                      r_top=None, z0=0.0):
        """Fired heater: a silver shell with an accent skirt band and a flame at the crown.
        Deliberately distinct from the other two vertical shapes in the kit — a `flue_stack`
        is narrow, banded and cold, and a `derrick` + `flare_tip` is an open lattice tower.

        `z0` lifts the whole stack — a flue rising out of a flat ROOF is a different object
        from one standing in the yard beside the building, and only the first reads as part of
        the building's plant.

        `r_top` tapers the shell. The taper is what keeps a TALL stack from reading as a pipe
        offcut: parallel sides give the eye no cue to its height, whereas convergence does.
        Seams, crown and flame all follow the local radius — a crown sized off the base on a
        tapered stack is a mushroom."""
        rt = r if r_top is None else r_top
        body = mat if mat is not None else self.mat("pipe")
        # Dark band only. `silver` is already near the top of the AgX curve — 0.62 and 0.80
        # render 10 luma apart — so a glint above it is invisible and only costs a slot.
        self.gloss(self.cone(name, cx, cy, z0 + h / 2, r, rt, h, body, segments=seg),
                   dark=0.44, glint=(0.0, 0.0))
        for k in (0.24, 0.48, 0.74):
            self.seam("%s_seam%d" % (name, int(k * 100)), cx, cy, z0 + h * k,
                      r + (rt - r) * k + 0.016)
        self.cyl("%s_base" % name, cx, cy, z0 + base / 2, self.r_at(r, rt, h, base) + 0.018, base,
                 self.mat("accent"), segments=seg)
        self.seam("%s_baseseam" % name, cx, cy, z0 + base, self.r_at(r, rt, h, base) + 0.030)
        self.cyl("%s_crown" % name, cx, cy, z0 + h - 0.05, rt + 0.038, 0.13, self.mat("scaffold"),
                 segments=seg)
        if not flame:
            return z0 + h
        # Flame sized off the THROAT, not the base. Fixed plume heights are what make
        # `flare_tip` a bonfire on a wide stack and a wisp on a narrow one.
        # Started just BELOW the crown's top so the droplet's pointed underside is tucked
        # inside the throat — left proud it reads as a flame balanced on its tip.
        top = z0 + h - 0.02
        fh = max(0.78, rt * 5.6)
        self.flame("%s_flame" % name, cx, cy, top, rt * 1.20, fh, self.M["ember"],
                   lean=fh * 0.26)
        return top + fh

    @staticmethod
    def r_at(r_base, r_top, h, z):
        """Shell radius of a tapered stack at height z — use it to land pipework ON the shell
        rather than a fixed offset from the axis, which leaves a gap once the stack tapers."""
        return r_base + (r_top - r_base) * max(0.0, min(1.0, z / h))

    def conveyor_bridge(self, name, p0, p1, w=0.34, h=0.42, ribs=6, legs=()):
        """Enclosed conveyor casing on lattice legs. Takes WORLD endpoints — run it along a
        world axis. Keep it LEVEL: an inclined bridge fights this camera (the furnace's
        gantry was abandoned for exactly that), while a level run reads instantly."""
        import mathutils
        A, B = mathutils.Vector(p0), mathutils.Vector(p1)
        self.dirbox("%s_case" % name, p0, p1, w, h, self.mat("drum"))
        for tag, dz in (("lo", -h / 2), ("hi", h / 2)):
            self.dircyl("%s_edge_%s" % (name, tag), (A.x, A.y, A.z + dz), (B.x, B.y, B.z + dz),
                        0.026, self.mat("scaffold"), segments=6)
        u = (B - A)
        ang = math.degrees(math.atan2(u.y, u.x))
        for k in range(ribs):
            R = A + u * ((k + 0.5) / ribs)
            self.rotbox("%s_rib%d" % (name, k), R.x, R.y, R.z, 0.05, w + 0.035, h + 0.030,
                        self.mat("scaffold"), 'Z', ang)
        for j, f in enumerate(legs):
            L = A + u * f
            self.derrick("%s_leg%d" % (name, j), L.x, L.y, 0.0, L.z - h / 2, 0.34, 0.22,
                         bays=6)

    def ring_rail(self, name, cx, cy, z, r, h=0.20, posts=10, seg=28):
        """Circular guardrail — the tell that a tank top is WALKED ON, and what separates a
        mixing vat from a sealed storage tank at a glance."""
        for tag, rz, rr in (("top", z + h, 0.024), ("mid", z + h * 0.55, 0.019)):
            self.cyl("%s_%s" % (name, tag), cx, cy, rz, r, rr * 2, self.mat("handrail"),
                     segments=seg)
        for k in range(posts):
            a = 2 * math.pi * k / posts
            self.box("%s_p%d" % (name, k), cx + r * math.cos(a), cy + r * math.sin(a),
                     z + h / 2, 0.035, 0.035, h, self.mat("handrail"))

    def float_tank(self, name, cx, cy, r, h, drop=0.24, mat=None, rail=True, hatch=True,
                   seg=32, deck_mat=None, band=False):
        """Mixing vat — an EXTERNAL FLOATING ROOF tank. The deck sits down inside the shell
        and rides on the liquid, so the shell rim stands proud of it: that recess is the whole
        read, and it is why this cannot be a flat_tank with a rail added.

        Built as an annulus, not a solid cylinder with a lid: a solid one's top face closes the
        shell at full height and there is no recess to see."""
        body = mat if mat is not None else self.mat("column")
        # A thin rim does not read. The recess is only legible if the shell edge has visible
        # thickness and the deck below it is DARK — a pale deck at this elevation just looks
        # like a lid sitting on the tank.
        wall = max(0.045, r * 0.085)
        outer = [(cx + r * math.cos(2 * math.pi * i / seg),
                  cy + r * math.sin(2 * math.pi * i / seg)) for i in range(seg)]
        inner = [(cx + (r - wall) * math.cos(2 * math.pi * i / seg),
                  cy + (r - wall) * math.sin(2 * math.pi * i / seg)) for i in range(seg)]
        self.gloss(self.poly_ring("%s_shell" % name, outer, inner, 0.0, h, body), dark=0.52)
        self.cyl("%s_deck" % name, cx, cy, h - drop, r - wall - 0.004, 0.06,
                 deck_mat if deck_mat is not None else self.mat("yard"), segments=seg)
        self.seam("%s_rim" % name, cx, cy, h, r + 0.012)
        self.seam("%s_girder" % name, cx, cy, h * 0.52, r + 0.014)
        if band:
            bz = h * 0.62
            self.cyl("%s_band" % name, cx, cy, bz, r + 0.014, 0.17, self.mat("accent"),
                     segments=seg)
            for tag, dz in (("lo", -0.085), ("hi", 0.085)):
                self.seam("%s_bandseam_%s" % (name, tag), cx, cy, bz + dz, r + 0.026)
        if hatch:
            self.cyl("%s_hatch" % name, cx + r * 0.30, cy - r * 0.16, h - drop + 0.04,
                     r * 0.17, 0.05, self.mat("accent"), segments=16)
        if rail:
            self.ring_rail("%s_rail" % name, cx, cy, h, r - wall * 0.5, 0.20, posts=10)
        return h

    def pump_skid(self, name, cx, cy, ax="+X", scale=1.0, mat=None):
        """Motor + volute on a plinth. Small, and that is the point: a scatter of pumps at
        ground level is what makes a plant look like it MOVES fluid rather than just stores
        it, and they fill the apron at a size nothing else in the kit works at."""
        s = scale
        body = mat if mat is not None else self.mat("gear")
        dx, dy = (1.0, 0.0) if ax in ("+X", "-X") else (0.0, 1.0)
        self.box("%s_pad" % name, cx, cy, 0.03 * s, 0.46 * s, 0.34 * s, 0.06 * s,
                 self.mat("yard_pad"))
        self.cyl("%s_motor" % name, cx - dx * 0.10 * s, cy - dy * 0.10 * s, 0.19 * s,
                 0.105 * s, 0.28 * s, body,
                 axis=('X' if dx else 'Y'), segments=16)
        self.cyl("%s_volute" % name, cx + dx * 0.13 * s, cy + dy * 0.13 * s, 0.17 * s,
                 0.115 * s, 0.10 * s, self.mat("drum"), segments=18)
        self.seam("%s_flange" % name, cx + dx * 0.13 * s, cy + dy * 0.13 * s, 0.17 * s,
                  0.128 * s)
        self.cyl("%s_out" % name, cx + dx * 0.13 * s, cy + dy * 0.13 * s, 0.30 * s,
                 0.038 * s, 0.16 * s, self.mat("pipe"), segments=12)

    def roll_stack(self, name, cx, cy, y0, y1, r=0.17, cols=3, rows=2, light=None, dark=None,
                   rod=True, z0=0.0):
        """Rolls of sheet stored on their sides, axis in DEPTH so their circular ends face the
        camera. Alternating light/dark is doing real work: it is the only thing in either
        refinery that reads as FINISHED GOODS rather than plant, so it wants to be unmistakable
        through a doorway."""
        lm = light if light is not None else self.mat("wall_pale")
        dm = dark if dark is not None else self.mat("opening")
        for c in range(cols):
            for w in range(rows):
                bx = cx + (c - (cols - 1) / 2.0) * (r * 2.16)
                bz = z0 + r + 0.02 + w * (r * 1.94)
                if w % 2:
                    bx += r * 1.08
                    if c == cols - 1:
                        continue
                self.cyl("%s_r%d_%d" % (name, c, w), bx, (y0 + y1) / 2, bz, r, y1 - y0,
                         lm if (c + w) % 2 == 0 else dm, axis='Y', segments=20)
                # axis='Y': a roll lying in depth needs its end ring in the XZ plane, and
                # seam() defaults to a HORIZONTAL band.
                self.seam("%s_s%d_%d" % (name, c, w), bx, y0 + 0.02, bz, r + 0.010, axis='Y')
                if rod:
                    # Through the bore and PROUD of both ends — a rod flush with the roll
                    # reads as a dark centre circle, not as a spool it is hung on.
                    self.cyl("%s_rod%d_%d" % (name, c, w), bx, (y0 + y1) / 2, bz, r * 0.20,
                             (y1 - y0) + 0.30, self.mat("stair"), axis='Y', segments=10)

    def ladder(self, name, cx, cy, z0, z1, face="+X", w=0.28, mat=None, rung=0.24):
        """Caged-free vertical ladder on a face. Put it on a face the camera actually SEES
        (+X or -Y): on the hidden flanks it is pure object count."""
        m = mat if mat is not None else self.mat("accent")
        ax = 1 if face in ("+X", "-X") else 0
        for sgn in (-1, 1):
            sx = cx + (0.0 if ax else sgn * w / 2)
            sy = cy + (sgn * w / 2 if ax else 0.0)
            self.box("%s_stile%d" % (name, sgn > 0), sx, sy, (z0 + z1) / 2,
                     0.048 if ax else 0.060, 0.060 if ax else 0.048, z1 - z0, m)
        n = max(2, int((z1 - z0) / rung))
        for k in range(n):
            self.box("%s_r%d" % (name, k), cx, cy, z0 + (z1 - z0) * (k + 0.5) / n,
                     0.038 if ax else w, w if ax else 0.038, 0.038, m)

    def tank_balcony(self, name, cx, cy, z, r, width=0.26, mat=None, seg=28):
        """Annular walkway round a vessel, with its rail. An access platform is what makes a
        tall tank read as SERVICED rather than as a plain cylinder."""
        outer = [(cx + (r + width) * math.cos(2 * math.pi * i / seg),
                  cy + (r + width) * math.sin(2 * math.pi * i / seg)) for i in range(seg)]
        inner = [(cx + (r + 0.008) * math.cos(2 * math.pi * i / seg),
                  cy + (r + 0.008) * math.sin(2 * math.pi * i / seg)) for i in range(seg)]
        self.poly_ring("%s_deck" % name, outer, inner, z, z + 0.055,
                       mat if mat is not None else self.mat("walkway"))
        self.ring_rail("%s_rail" % name, cx, cy, z + 0.055, r + width - 0.03, 0.20, posts=10)
        return z + 0.055

    def gantry_crane(self, name, x0, x1, cy, z, cab_at=None, span_w=0.30):
        """Overhead travelling crane: bridge girder on end trucks, a trolley, and a cab slung
        at one end. Sits HIGH on purpose — in an open-topped bay the floor is hidden by
        whatever stands in front of it, and the crane is the part that clears the roofline."""
        steel = self.mat("stair")
        for tag, dy in (("f", -span_w / 2), ("b", span_w / 2)):
            self.box("%s_girder_%s" % (name, tag), (x0 + x1) / 2, cy + dy, z,
                     x1 - x0, 0.075, 0.16, steel)
        for k in range(5):
            gx = x0 + (x1 - x0) * (k + 0.5) / 5
            self.box("%s_web%d" % (name, k), gx, cy, z, 0.05, span_w, 0.10, steel)
        for sgn, ex in ((-1, x0), (1, x1)):
            self.box("%s_truck%d" % (name, sgn > 0), ex, cy, z - 0.16, 0.18, span_w + 0.10,
                     0.18, steel)
        tx = (x0 + x1) * 0.5 + (x1 - x0) * 0.14
        self.box("%s_trolley" % name, tx, cy, z + 0.14, 0.30, span_w + 0.06, 0.14, steel)
        self.cyl("%s_hoist" % name, tx, cy, z - 0.26, 0.028, 0.52, steel, segments=8)
        self.box("%s_hook" % name, tx, cy, z - 0.56, 0.11, 0.11, 0.12, steel)
        # The cab is the one warm note, so it wants to be a solid block of colour, not a
        # detailed box — at this size any glazing on it just reads as noise.
        ccx = x0 + (x1 - x0) * 0.20 if cab_at is None else cab_at
        self.box("%s_cab" % name, ccx, cy - span_w / 2 - 0.10, z - 0.30, 0.34, 0.26, 0.34,
                 self.mat("power_accent"))
        self.box("%s_cabroof" % name, ccx, cy - span_w / 2 - 0.10, z - 0.11, 0.38, 0.30, 0.05,
                 steel)

    def valve_skid(self, name, cx, cy, w, d, h, ribs=5, valves=3, mat=None):
        """Shallow packaged plant unit — a low metal box with transverse RIDGES and a row of
        VALVE handwheels. Deliberately squat: everything else on these plants is a vertical
        cylinder, so a horizontal slab of machinery at knee height is the one thing that reads
        instantly as different equipment.

        Ribs and valves march along the unit's LONG axis whichever way round it is built, so
        the same call works for a wide unit or a deep one. Ribbing the short axis of a long
        skid gives a handful of fat bands instead of a ridged deck.

        The wheels are washers on stems, not discs — a flat disc at this size reads as a cap.
        """
        body = mat if mat is not None else self.mat("gear")
        self.box(name, cx, cy, h / 2, w, d, h, body)
        self.box("%s_deck" % name, cx, cy, h + 0.018, w - 0.05, d - 0.05, 0.05,
                 self.mat("roof_deck"))
        self.box("%s_plinth" % name, cx, cy, 0.035, w + 0.08, d + 0.08, 0.07,
                 self.mat("yard_pad"))
        along_x = w >= d
        span = w if along_x else d
        for k in range(ribs):
            t = -span / 2 + span * (k + 0.5) / ribs
            rx, ry = (cx + t, cy) if along_x else (cx, cy + t)
            self.box("%s_rib%d" % (name, k), rx, ry, h / 2,
                     0.055 if along_x else w + 0.035,
                     d + 0.035 if along_x else 0.055, h * 0.86, body)
        for k in range(valves):
            t = -span / 2 + span * (k + 0.75) / valves
            off = (d if along_x else w) * 0.18
            vx, vy = (cx + t, cy - off) if along_x else (cx - off, cy + t)
            self.cyl("%s_stem%d" % (name, k), vx, vy, h + 0.13, 0.032, 0.26,
                     self.mat("pipe"), segments=10)
            self.washer("%s_wheel%d" % (name, k), (vx, vy, h + 0.27),
                        (1, 0, 0) if along_x else (0, 1, 0), 0.055, 0.105, 0.030,
                        self.mat("accent"))
        return h

    def tower_crane(self, name, cx, cy, h, jib=3.40, cjib=1.30, mast_w=0.34, mat=None):
        """Tower crane. The one silhouette on a building site that reads from any distance, so
        it is built to TOWER: the mast runs the full height and the jib is a long horizontal
        against a field of low, busy machinery.

        The jib runs along +X on purpose. Along +Y it would climb the screen and fight the
        mast for the same vertical; along +X it falls down-right and the two read as a cross."""
        steel = mat if mat is not None else self.mat("pipe")
        dark = self.mat("stair")
        # Ballast at the foot, so it is obviously counterweighted rather than planted.
        self.box("%s_pad" % name, cx, cy, 0.06, mast_w * 4.4, mast_w * 4.4, 0.12,
                 self.mat("yard_pad"))
        for i, (bx, by) in enumerate(((-1, -1), (1, -1), (-1, 1), (1, 1))):
            self.box("%s_ball%d" % (name, i), cx + bx * mast_w * 1.5, cy + by * mast_w * 1.5,
                     0.22, mast_w * 1.5, mast_w * 1.5, 0.32, self.mat("plant_yellow"))
        # FEWER, BIGGER bays. lattice_mast draws in fine ink, and at 9 bays over this height
        # the members and their outlines merge into a solid dark pillar — the openness is the
        # only thing that says lattice rather than chimney.
        self.lattice_mast("%s_mast" % name, cx, cy, 0.14, h, w=mast_w, bays=6, mat=steel)
        # Slewing deck + cab, at the top where the operator would actually sit.
        self.box("%s_slew" % name, cx, cy, h + 0.10, mast_w * 2.6, mast_w * 2.6, 0.20, dark)
        self.box("%s_cab" % name, cx + mast_w * 0.4, cy - mast_w * 1.9, h + 0.34,
                 mast_w * 1.7, mast_w * 1.5, 0.40, self.mat("plant_yellow"))
        self.box("%s_cabroof" % name, cx + mast_w * 0.4, cy - mast_w * 1.9, h + 0.56,
                 mast_w * 1.9, mast_w * 1.7, 0.05, dark)
        # Jib and counter-jib as chord pairs with bracing — a solid bar reads as a plank.
        zt = h + 0.26
        for tag, x0, x1, depth in (("jib", cx + mast_w, cx + jib, 0.30),
                                   ("cj", cx - cjib, cx - mast_w, 0.24)):
            # The jib's top chord runs level then RAKES DOWN to meet the bottom chord at the
            # tip — that taper is what makes it read as a jib rather than a plank, and it is
            # how a real one is built (the last bays carry no load worth the depth).
            xt = x1 - (x1 - x0) * (0.24 if tag == "jib" else 0.0)
            self.dircyl("%s_%s_top" % (name, tag), (x0, cy, zt + depth), (xt, cy, zt + depth),
                        0.045, steel, segments=8)
            if xt < x1 - 0.01:
                self.dircyl("%s_%s_rake" % (name, tag), (xt, cy, zt + depth), (x1, cy, zt),
                            0.042, steel, segments=8)
            for sgn in (-1, 1):
                self.dircyl("%s_%s_bot%d" % (name, tag, sgn > 0), (x0, cy + sgn * 0.10, zt),
                            (x1, cy + sgn * 0.10, zt), 0.045, steel, segments=8)
            n = max(3, int(absf_(x1 - x0) / 0.42))
            for k in range(n):
                f0 = float(k) / n
                f1 = float(k + 1) / n
                bx0 = x0 + (x1 - x0) * f0
                bx1 = x0 + (x1 - x0) * f1
                # Braces stop at the RAKED chord: past xt the top chord descends
                # toward the tip, and a brace still rising to full depth pokes out
                # of the frame (owner 2026-08-06: two diagonals sticking out at
                # the jib tip).
                if bx1 <= xt + 1e-6:
                    bz1 = zt + depth
                else:
                    bz1 = zt + depth * max(0.0, (x1 - bx1) / max(x1 - xt, 1e-6))
                self.dircyl("%s_%s_br%d" % (name, tag, k),
                            (bx0, cy, zt), (bx1, cy, bz1), 0.028, steel, segments=6)
        self.box("%s_cw" % name, cx - cjib - 0.10, cy, zt + 0.10, 0.34, 0.46, 0.46, dark)
        # Hoist: trolley, rope, hook block. The rope is what says the crane is WORKING.
        # Trolley well OUT on the jib: parked near the mast it reads as stowed, and the hook
        # hanging in open air over the site is what says the crane is lifting.
        tx = cx + jib * 0.70
        self.box("%s_trolley" % name, tx, cy, zt - 0.04, 0.20, 0.30, 0.12, dark)
        self.dircyl("%s_rope" % name, (tx, cy, zt - 0.10), (tx, cy, zt - 2.05), 0.016, dark,
                    segments=6)
        self.box("%s_hook" % name, tx, cy, zt - 2.17, 0.16, 0.16, 0.22, dark)
        return zt + 0.26


    def container_stack(self, name, cx, cy, cols=3, rows=2, cl=1.05, cw=0.44, ch=0.40,
                        mats=None):
        """Stacked shipping containers — the cheapest thing that says SITE COMPOUND. Ribbed,
        because a plain box at this size reads as a crate; the corrugation is the tell."""
        pal = mats if mats is not None else [self.mat("wall_brick"), self.mat("box_blue"),
                                             self.mat("plant_yellow"), self.mat("gear"),
                                             self.mat("box_blue")]
        for r in range(rows):
            for c in range(cols):
                if r > 0 and c == cols - 1:
                    continue                       # top course short, so it reads as stacked
                bx = cx + (float(c) - (cols - 1) * 0.5) * (cw * 1.06)
                bz = 0.02 + ch * 0.5 + r * (ch + 0.03)
                m = pal[(c + r) % len(pal)]
                self.box("%s_c%d_%d" % (name, c, r), bx, cy, bz, cl, cw, ch, m)
                for k in range(5):
                    self.box("%s_r%d_%d_%d" % (name, c, r, k),
                             bx - cl * 0.5 + cl * (k + 0.5) / 5.0, cy, bz,
                             0.035, cw + 0.016, ch * 0.88, m)
                self.box("%s_d%d_%d" % (name, c, r), bx + cl * 0.5 + 0.012, cy, bz,
                         0.02, cw * 0.86, ch * 0.86, self.mat("stair"))


    def scaffold(self, name, x0, x1, y0, y1, h, lifts=3, boards=True):
        """Tube-and-board scaffold around a footprint: standards at the corners and midpoints,
        ledgers per lift, diagonal braces on the two CAMERA-FACING faces only — bracing the
        hidden faces doubles the object count for nothing at this scale."""
        steel = self.mat("scaffold")
        xs = [x0, (x0 + x1) * 0.5, x1]
        ys = [y0, (y0 + y1) * 0.5, y1]
        for i, sx in enumerate(xs):
            for j, sy in enumerate(ys):
                self.dircyl("%s_st%d_%d" % (name, i, j), (sx, sy, 0.0), (sx, sy, h), 0.030,
                            steel, segments=6)
        for k in range(1, lifts + 1):
            z = h * float(k) / lifts
            for sy in (y0, y1):
                self.dircyl("%s_lx%d_%.0f" % (name, k, sy * 100), (x0, sy, z), (x1, sy, z),
                            0.026, steel, segments=6)
            for sx in (x0, x1):
                self.dircyl("%s_ly%d_%.0f" % (name, k, sx * 100), (sx, y0, z), (sx, y1, z),
                            0.026, steel, segments=6)
        # Braces on the -Y and +X faces (the two the camera sees).
        for k in range(lifts):
            za = h * float(k) / lifts
            zb = h * float(k + 1) / lifts
            self.dircyl("%s_bx%d" % (name, k), (x0, y0, za), ((x0 + x1) * 0.5, y0, zb),
                        0.022, steel, segments=6)
            self.dircyl("%s_by%d" % (name, k), (x1, y0, za), (x1, (y0 + y1) * 0.5, zb),
                        0.022, steel, segments=6)
        if boards:
            for k in (lifts - 1, lifts):
                z = h * float(k) / lifts
                self.box("%s_bd%d" % (name, k), (x0 + x1) * 0.5, y0 + 0.13, z + 0.03,
                         x1 - x0, 0.26, 0.05, self.mat("wall_pale"))

    def bulldozer(self, name, cx, cy, z=0.0, s=0.72, face=1.0, mat=None):
        """Tracked dozer: a BLADE is the whole read. Beside an excavator the two machines have
        to differ in silhouette or they are one shape twice — the excavator's tell is a raised
        boom, so this one stays low and wide and pushes something."""
        body = mat if mat is not None else self.mat("plant_yellow")
        trk = self.mat("stair")
        f = 1.0 if face >= 0.0 else -1.0
        for sgn in (-1, 1):
            self.box("%s_trk%d" % (name, sgn > 0), cx, cy + sgn * 0.30 * s, z + 0.15 * s,
                     1.15 * s, 0.22 * s, 0.30 * s, trk)
            for k in range(4):
                self.box("%s_rl%d_%d" % (name, sgn > 0, k),
                         cx - 0.44 * s + k * 0.29 * s, cy + sgn * 0.30 * s, z + 0.12 * s,
                         0.07 * s, 0.26 * s, 0.20 * s, trk)
        self.box("%s_hull" % name, cx, cy, z + 0.40 * s, 0.95 * s, 0.52 * s, 0.28 * s, body)
        self.box("%s_cab" % name, cx - 0.16 * s * f, cy, z + 0.66 * s,
                 0.44 * s, 0.44 * s, 0.30 * s, body)
        self.box("%s_glass" % name, cx - 0.16 * s * f, cy - 0.23 * s, z + 0.70 * s,
                 0.34 * s, 0.03 * s, 0.18 * s, self.mat("window_glass"))
        self.cyl("%s_stack" % name, cx - 0.34 * s * f, cy + 0.14 * s, z + 0.92 * s,
                 0.035 * s, 0.26 * s, trk, segments=8)
        # Blade: angled push-plate out front, on two arms.
        bx = cx + 0.78 * s * f
        self.box("%s_blade" % name, bx, cy, z + 0.30 * s, 0.10 * s, 1.05 * s, 0.46 * s, body)
        self.box("%s_edge" % name, bx + 0.05 * s * f, cy, z + 0.09 * s, 0.06 * s, 1.05 * s,
                 0.10 * s, trk)
        for sgn in (-1, 1):
            self.dircyl("%s_arm%d" % (name, sgn > 0),
                        (cx + 0.30 * s * f, cy + sgn * 0.26 * s, z + 0.22 * s),
                        (bx, cy + sgn * 0.30 * s, z + 0.30 * s), 0.045 * s, trk, segments=6)

    def bale_stack(self, name, cx, cy, cols=2, rows=2, w=0.34, hgt=0.24, strap=True):
        """Palletised finished product. Nothing on a fuels refinery leaves as a solid, so
        wrapped bales in the yard are a cheap, unambiguous 'this plant makes THINGS'."""
        for c in range(cols):
            for rr in range(rows):
                bx = cx + (c - (cols - 1) / 2.0) * (w * 1.10)
                bz = 0.04 + hgt / 2 + rr * (hgt + 0.028)
                self.box("%s_b%d_%d" % (name, c, rr), bx, cy, bz, w, w, hgt,
                         self.mat("accent_deep"))
                if strap:
                    self.box("%s_s%d_%d" % (name, c, rr), bx, cy, bz, w + 0.012, w * 0.20,
                             hgt * 0.16, self.mat("pipe"))
                self.box("%s_p%d_%d" % (name, c, rr), bx, cy, bz - hgt / 2 - 0.018, w + 0.02,
                         w + 0.02, 0.036, self.mat("scaffold"))

    def bund(self, name, x0, x1, y0, y1, h=0.26, t=0.11, floor=True):
        """Low retaining wall around a liquid tank farm. Every fuels terminal has one and no
        solids plant does, so it quietly reinforces which building is which."""
        if floor:
            self.box("%s_floor" % name, (x0 + x1) / 2, (y0 + y1) / 2, 0.025, x1 - x0,
                     y1 - y0, 0.05, self.mat("yard"))
        for tag, (bx, by, sx, sy) in (
            ("s", ((x0 + x1) / 2, y0, x1 - x0, t)), ("n", ((x0 + x1) / 2, y1, x1 - x0, t)),
            ("w", (x0, (y0 + y1) / 2, t, y1 - y0)), ("e", (x1, (y0 + y1) / 2, t, y1 - y0)),
        ):
            self.box("%s_%s" % (name, tag), bx, by, h / 2, sx, sy, h, self.mat("yard"))
            self.box("%s_%scap" % (name, tag), bx, by, h + 0.014, sx + 0.02, sy + 0.02,
                     0.038, self.mat("scaffold"))

    def pipe_rack(self, name, p0, p1, z_hi, z_lo, bents=5, width=0.72, lines_hi=4,
                  lines_lo=3):
        """Elevated pipe rack between two WORLD points. The fork ran these along the x+y
        diagonal, which renders dead horizontal and was the single biggest reason its
        refineries looked flat — run them along a world axis and they slope with the grid."""
        import mathutils
        A, B = mathutils.Vector((p0[0], p0[1], 0.0)), mathutils.Vector((p1[0], p1[1], 0.0))
        u = (B - A)
        L = u.length or 1.0
        un = u / L
        side = mathutils.Vector((-un.y, un.x, 0.0))
        for b in range(bents):
            f = b / max(1, bents - 1)
            C = A + u * f
            for sgn in (-1, 1):
                P = C + side * (sgn * width / 2)
                self.dircyl("%s_col%d_%d" % (name, b, sgn > 0), (P.x, P.y, 0.0),
                            (P.x, P.y, z_hi), 0.045, self.mat("scaffold"), segments=8)
            for tag, z in (("hi", z_hi), ("lo", z_lo)):
                Pa = C + side * (-width / 2)
                Pb = C + side * (width / 2)
                self.dircyl("%s_beam%s%d" % (name, tag, b), (Pa.x, Pa.y, z), (Pb.x, Pb.y, z),
                            0.038, self.mat("scaffold"), segments=6)
        for tag, z, n in (("hi", z_hi, lines_hi), ("lo", z_lo, lines_lo)):
            for i in range(n):
                off = (-width / 2 + width * (i + 0.5) / n)
                Pa = A + side * off - un * 0.10
                Pb = B + side * off + un * 0.10
                self.dircyl("%s_line%s%d" % (name, tag, i), (Pa.x, Pa.y, z + 0.055),
                            (Pb.x, Pb.y, z + 0.055), 0.052, self.mat("pipe"), segments=12)

    # ------------------------- VESSELS -------------------------
    def tank(self, name, cx, cy, r, h, riser=None):
        """Process vessel: shell + domed lid, seams at the lid joint and mid-strake, and a
        collar where a riser penetrates the crown."""
        self.cyl(name, cx, cy, h / 2, r, h, self.mat("vessel"), segments=32)
        self.cone(f"{name}_lid", cx, cy, h + 0.13, r + 0.03, 0.10, 0.26, self.mat("scaffold"), segments=32)
        self.seam(f"{name}_lidseam", cx, cy, h, r + 0.02)
        self.seam(f"{name}_midseam", cx, cy, h * 0.55, r + 0.015)
        if riser is not None:
            self.seam(f"{name}_riserseam", cx + riser, cy, h + 0.02, 0.20)

    # ------------------------- VALIDATION -------------------------
    def bounds(self, prefix=""):
        import mathutils
        lo = mathutils.Vector((1e9, 1e9, 1e9))
        hi = mathutils.Vector((-1e9, -1e9, -1e9))
        for ob in self.col.objects:
            if prefix and not ob.name.startswith(prefix):
                continue
            for v in ob.data.vertices:
                w = ob.matrix_world @ v.co
                lo = mathutils.Vector((min(lo.x, w.x), min(lo.y, w.y), min(lo.z, w.z)))
                hi = mathutils.Vector((max(hi.x, w.x), max(hi.y, w.y), max(hi.z, w.z)))
        return lo, hi

    def validate(self, ground=0.0, roof=None, tol=0.02):
        """Cheap geometric checks that catch the bug classes that otherwise cost a full
        render-and-zoom cycle each. Returns a list of warning strings — PRINT IT and fix
        before rendering.
          ground : anything dipping below this is flagged (members sunk under the floor)
          roof   : (z, x0, x1, y0, y1) — anything crossing that plane INSIDE the footprint
                   is flagged (inclines punching through a roof)"""
        out = []
        for ob in self.col.objects:
            zs = [(ob.matrix_world @ v.co).z for v in ob.data.vertices]
            if not zs:
                continue
            if min(zs) < ground - tol:
                out.append("BELOW GROUND: %s (min z %.3f)" % (ob.name, min(zs)))
            if roof is not None:
                rz, rx0, rx1, ry0, ry1 = roof
                pts = [ob.matrix_world @ v.co for v in ob.data.vertices]
                inside = [p for p in pts if rx0 <= p.x <= rx1 and ry0 <= p.y <= ry1]
                if inside and min(p.z for p in inside) < rz - tol < max(p.z for p in inside):
                    out.append("CROSSES ROOF PLANE inside footprint: %s" % ob.name)
        lo, hi = self.bounds()
        w, h = hi.x - lo.x, hi.z - lo.z
        out.append("bbox world %.2f x %.2f x %.2f" % (hi.x - lo.x, hi.y - lo.y, hi.z - lo.z))
        return out
