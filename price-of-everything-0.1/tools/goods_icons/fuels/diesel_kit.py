"""Diesel fuel (g_031, internal name 'fuels'): a fuel pump filling a jerrycan, on the isometric grid.

Reference: assets/icons/goods/medium/g_031_fuels.png (shipped AI art): a red fuel pump on a grey
plinth, its edges rounded; a light display panel (two readouts, three buttons) on its lower-right
face; a holster on its lower-left face, a light bezel round a recess, with a hose coming out of the
recess and hanging in a loop round the front-left corner; a second hose arcing from the pump over to
a pistol nozzle whose spout feeds a red jerrycan standing in front, its cap hinged open.
The shipped layout is kept on the grid under the set's light: the display on the +X face (the shade
side, dotted), the holster on the -Y face, the can in front of the +X face.
OWNER (v5 -> v6): "reuse the canister used on the ICE car, dont build it from scratch. The refine
the shape of the pistol and look at the hose coming out of the petrol pump, the cable needs to come
out of a hole". So:
- the can is the ICE car's (g_056) jerrycan, built by base_kit.build_reference_jerrycan unchanged
  (the same call as the car's, yaw 90), sized to the shipped can. That builder was inked by the old
  Freestyle pass; ds_ice_can only adds what the standard exporter needs: part labels, and ink paths
  read off the can's own geometry (the broad face's perimeter and the depth corners from its loft
  profile, the pressed X's rims from the finished mesh, the neck and the cap), and swings the can's
  own cap open on its neck so the spout can go in;
- the nozzle is a profiled pistol: a tall head with the spout at its front, a slimmer handle rising
  back to a grey hose collar, a trigger guard hanging under the handle with the lever inside;
- the holster is a real hole in the pump's -Y face (light walls, a bezel round it), and the hose
  comes out of it.
Owner rulings carried over: the shipped layout on the grid, the set's light, dots on shaded sides,
ink at every junction, one colour per material, 3 px for small detail and cross-cut rims.
Proportions measured off the shipped art (pump depth X = 1): pump 1.0 x 1.5 x 3.05 on a 0.15 plinth.
"""
import math, bmesh
from mathutils import Vector

DS_REVISION = 'diesel_v9'
PUMP = (0.0, 1.0, 0.0, 1.5, 0.15, 3.2)        # x0, x1, y0, y1, z0, z1
R_EDGE = 0.15                                 # the pump's rounded edges
RIM_IN = 0.08                                 # the +X face's rim line, in from the flat of the face
PLINTH = (-0.15, 1.2, -0.35, 1.7, 0.0, 0.15)
DISPLAY = (0.33, 1.17, 1.85, 2.78)            # on the +X face: y0, y1, z0, z1
BEZEL = (0.30, 0.70, 1.70, 2.65)              # the holster's bezel on the -Y face: x0, x1, z0, z1
HOLE = (0.38, 0.62, 1.80, 2.55, 0.25)         # its hole: x0, x1, z0, z1, depth into the pump
CAN_D, CAN_AT = 1.25, (2.07, 0.60)            # the ICE car's can: its size factor, and where it stands
CAP_SWING = 158.0                             # the can's cap, swung open on its neck (degrees); v6's 118 left it edge-on
NOZ_TILT = 22.0                               # the nozzle's rise
SPOUT_DIR = (0.0, -0.25, -0.97)               # the spout drops from the head's underside, leaning forward, as shipped
SPOUT_LEN = 0.40                              # from the head's underside to the neck's top
R_HOSE, R_SPOUT = 0.085, 0.05
# The pump's red, three flat tones in linear light: shade (160,58,50), -Y faces (190,78,66), tops
# (211,113,100) as shipped. OWNER (v8 -> v9): "make the canister the same colour as the pump in this
# icon and the diesel car icon too": the can's own two materials take these tones (a darker set for
# its neck and pressing floors), keeping the can's toon thresholds so its approved banding stays.
PUMP_RED = ((0.352, 0.042, 0.031), (0.515, 0.076, 0.054), (0.651, 0.165, 0.127))
CAN_DARK = 0.55                               # the neck's and pressing floors' tones: the pump red x this, in linear light
CAN_STEPS = (0.66, 0.92)                      # the can's toon thresholds (base_kit.toon_mat's defaults)
SMALL_INK = 3
# The pistol, in its own side plane (u back along the nozzle, v up). v7 -> v8, after the shipped
# nozzle: a tall chamfered head (0.48) with the spout under it, a slim handle (0.14) back to the
# collar, and a big D-shaped trigger guard hanging under the handle, its opening clear, the lever in it.
NOZ_BODY = [(0.05, -0.18), (0.19, -0.18), (0.26, -0.10), (0.26, 0.06), (0.30, 0.10), (0.80, 0.10), (0.80, 0.24),
            (0.34, 0.24), (0.29, 0.27), (0.24, 0.30), (0.06, 0.30), (0.00, 0.22), (0.00, -0.10)]
NOZ_GUARD = [(0.25, -0.05), (0.29, -0.18), (0.36, -0.23), (0.62, -0.21), (0.71, -0.14), (0.76, 0.00), (0.77, 0.11),
             (0.70, 0.11), (0.69, 0.02), (0.65, -0.10), (0.60, -0.15), (0.38, -0.16), (0.33, -0.12), (0.31, -0.05)]
NOZ_LEVER = [(0.36, 0.105), (0.62, 0.105), (0.60, 0.05), (0.38, 0.03)]
NOZ_W = (0.20, 0.08, 0.05)                    # widths: body, guard, lever
SPOUT_AT = (0.10, -0.18)                      # where the spout leaves the head's underside (u, v)
COLLAR_V = 0.17                               # the hose collar's axis (v), on the handle's centreline


def ds_spline(ctrl, per=10):
    """Catmull-Rom points through the control points."""
    P = [Vector(p) for p in ctrl]; out = []
    for i in range(len(P) - 1):
        p0 = P[i - 1] if i > 0 else P[i] * 2 - P[i + 1]
        p1, p2 = P[i], P[i + 1]
        p3 = P[i + 2] if i + 2 < len(P) else P[i + 1] * 2 - P[i]
        for j in range(per):
            t = j / per; t2 = t * t; t3 = t2 * t
            out.append(0.5 * (2 * p1 + (p2 - p0) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (3 * p1 - p0 - 3 * p2 + p3) * t3))
    out.append(P[-1])
    return [tuple(p) for p in out]


def ds_print(K, name, uv, plane, d0, d1, mat, label):
    """A flat printed shape: a (u, v) outline on a face plane, d0..d1 thick along the plane's normal.
    '+X': (d, u, v); '-Y': (u, d, v); '+Z': (u, v, d). Never dotted."""
    place = {'+X': lambda u, v, d: (d, u, v), '-Y': lambda u, v, d: (u, d, v), '+Z': lambda u, v, d: (u, v, d)}[plane]
    n = len(uv)
    vs = [place(u, v, d0) for u, v in uv] + [place(u, v, d1) for u, v in uv]
    fs = [tuple(range(n)), tuple(n + k for k in range(n))] + [(k, (k + 1) % n, n + (k + 1) % n, n + k) for k in range(n)]
    ob = pw_clean_water(mesh(K, name, vs, fs, mat, False)); ob['part_label'] = label
    return ob


def ds_outline(K, name, uv, plane, d, label, width=SMALL_INK):
    place = {'+X': lambda u, v: (d, u, v), '-Y': lambda u, v: (u, d, v), '+Z': lambda u, v: (u, v, d)}[plane]
    return tagged_line(K, name, [place(u, v) for u, v in uv], label, width, True)


def ds_cut(K, ob, boxes):
    """Boolean difference of axis boxes ((x0, x1), (y0, y1), (z0, z1)) from ob, applied in place;
    the object keeps its material slots."""
    vs, fs = [], []
    for (x0, x1), (y0, y1), (z0, z1) in boxes:
        b = len(vs)
        vs += [(x, y, z) for z in (z0, z1) for y in (y0, y1) for x in (x0, x1)]
        fs += [(b, b + 2, b + 3, b + 1), (b + 4, b + 5, b + 7, b + 6), (b, b + 1, b + 5, b + 4),
               (b + 2, b + 6, b + 7, b + 3), (b, b + 4, b + 6, b + 2), (b + 1, b + 3, b + 7, b + 5)]
    cutter = mesh(K, ob.name + '_cutter', vs, fs, None, False)
    mats = list(ob.data.materials)
    mod = ob.modifiers.new('cut', 'BOOLEAN'); mod.operation = 'DIFFERENCE'; mod.solver = 'EXACT'; mod.object = cutter
    bpy.context.view_layer.update()
    me = bpy.data.meshes.new_from_object(ob.evaluated_get(bpy.context.evaluated_depsgraph_get()))
    ob.modifiers.remove(mod); old = ob.data; ob.data = me; bpy.data.meshes.remove(old)
    me.materials.clear()
    for m in mats:
        me.materials.append(m)
    for poly in me.polygons:
        poly.use_smooth = False
    bpy.data.objects.remove(cutter, do_unlink=True)
    return noink(ob)


def ds_pump_body(K, mat, wall_m, label):
    """The pump: a box with its four vertical and four top edges rounded (bevelled, 6 segments),
    the holster's hole cut into its -Y face (its walls in wall_m), and the ink: each visible
    rounding's tangent lines, the +X face's rim line, and the hole's inner corners (3 px)."""
    x0, x1, y0, y1, z0, z1 = PUMP; r = R_EDGE
    bm = bmesh.new(); bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=(x1 - x0, y1 - y0, z1 - z0), verts=bm.verts)
    bmesh.ops.translate(bm, vec=((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2), verts=bm.verts)
    sel = [e for e in bm.edges if not (abs(e.verts[0].co.z - z0) < 1e-6 and abs(e.verts[1].co.z - z0) < 1e-6)]
    bmesh.ops.bevel(bm, geom=sel, offset=r, offset_type='OFFSET', segments=6, profile=0.5, affect='EDGES', clamp_overlap=True)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    me = bpy.data.meshes.new('pump_body'); bm.to_mesh(me); bm.free()
    ob = noink(K.obj('pump_body', me, mat, False)); ob['part_label'] = label
    hx0, hx1, hz0, hz1, hd = HOLE
    ob.data.materials.append(wall_m)
    ds_cut(K, ob, [((hx0, hx1), (y0 - 0.2, y0 + hd), (hz0, hz1))])
    for poly in ob.data.polygons:                    # the hole's walls take the light bezel tone
        c = poly.center
        if c.y > y0 + 1e-4 and hx0 - 1e-4 < c.x < hx1 + 1e-4 and hz0 - 1e-4 < c.z < hz1 + 1e-4:
            poly.material_index = 1
    lines = [
        ('front_on_side', [(x1 - r, y0 - E, z0), (x1 - r, y0 - E, z1 - r)]),
        ('front_on_face', [(x1 + E, y0 + r, z0), (x1 + E, y0 + r, z1 - r)]),
        ('left_on_side', [(x0 + r, y0 - E, z0), (x0 + r, y0 - E, z1 - r)]),
        ('back_on_face', [(x1 + E, y1 - r, z0), (x1 + E, y1 - r, z1 - r)]),
        ('top_on_side', [(x0 + r, y0 - E, z1 - r), (x1 - r, y0 - E, z1 - r)]),
        ('top_on_top_front', [(x0 + r, y0 + r, z1 + E), (x1 - r, y0 + r, z1 + E)]),
        ('top_on_face', [(x1 + E, y0 + r, z1 - r), (x1 + E, y1 - r, z1 - r)]),
        ('top_on_top_right', [(x1 - r, y0 + r, z1 + E), (x1 - r, y1 - r, z1 + E)]),
    ]
    for nm, pts in lines:
        tagged_line(K, 'pump_' + nm, pts, label, 6, False)
    rim = alk_rect(y0 + r + RIM_IN, y1 - r - RIM_IN, z0 + 0.12, z1 - r - RIM_IN, 0.10)
    tagged_line(K, 'pump_face_rim', [(x1 + E, u, v) for u, v in rim], label, 6, True)['ink_width'] = 0
    # The hole's inner corners: pushed a hair into the open hole so they stay in front of its walls.
    a0, a1, b0, b1, back = hx0 + E, hx1 - E, hz0 + E, hz1 - E, y0 + hd - E
    tagged_line(K, 'hole_back', [(a0, back, b0), (a1, back, b0), (a1, back, b1), (a0, back, b1)], label, SMALL_INK, True)
    for k, (x, z) in enumerate(((a0, b0), (a1, b0), (a1, b1), (a0, b1))):
        tagged_line(K, 'hole_corner%d' % k, [(x, y0 - E, z), (x, back, z)], label, SMALL_INK, False)
    return ob


def ds_bezel(K, name, outer, inner, y_front, y_back, mat, label):
    """A ring plate on the -Y face: the (x, z) outer loop less the inner loop (equal point counts),
    from y_back (sunk into the face) to y_front (standing proud of it)."""
    n = len(outer)
    loops = [[(x, y_front, z) for x, z in outer], [(x, y_back, z) for x, z in outer],
             [(x, y_back, z) for x, z in inner], [(x, y_front, z) for x, z in inner]]
    vs = [p for loop in loops for p in loop]; fs = []
    for j in range(4):
        a, b = j * n, ((j + 1) % 4) * n
        fs += [(a + k, a + (k + 1) % n, b + (k + 1) % n, b + k) for k in range(n)]
    ob = pw_clean_water(mesh(K, name, vs, fs, mat, False)); ob['part_label'] = label
    return ob


def ds_plate(K, name, uv, O, U, V, w, mat, label, width, turn_deg=30.0):
    """A plate cut from a (u, v) outline in the side plane O + U*u + V*v, w thick along world X (the
    plane's normal), with ink at `width` px: both outlines, and the depth edges at corners that turn
    more than turn_deg (hidden runs drop out)."""
    N = Vector((1.0, 0.0, 0.0)); O, U, V = Vector(O), Vector(U), Vector(V)
    def place(u, v, d):
        return tuple(O + U * u + V * v + N * d)
    n = len(uv)
    vs = [place(u, v, -w / 2) for u, v in uv] + [place(u, v, w / 2) for u, v in uv]
    fs = [tuple(range(n)), tuple(n + k for k in range(n))] + [(k, (k + 1) % n, n + (k + 1) % n, n + k) for k in range(n)]
    ob = mesh(K, name, vs, fs, mat, False); ob['part_label'] = label
    ring = [Vector(q) + o * E for q, o in zip(uv, alk_outward(uv))]
    for side, d in (('near', w / 2 + E), ('far', -w / 2 - E)):
        tagged_line(K, '%s_%s' % (name, side), [place(q.x, q.y, d) for q in ring], label, width, True)['ink_width'] = 0
    for k in range(n):
        a, b, c = Vector(uv[k - 1]), Vector(uv[k]), Vector(uv[(k + 1) % n])
        if (b - a).angle(c - b, 0.0) > math.radians(turn_deg):
            q = ring[k]
            tagged_line(K, '%s_depth%d' % (name, k), [place(q.x, q.y, -w / 2 - E), place(q.x, q.y, w / 2 + E)], label, width, False)
    return ob


def ds_chain(edges):
    """Chain undirected (a, b) vertex-index edges into polylines of indices."""
    adj = {}
    for a, b in edges:
        adj.setdefault(a, []).append(b); adj.setdefault(b, []).append(a)
    seen = set(); chains = []
    def key(a, b):
        return (a, b) if a < b else (b, a)
    for start in sorted(adj, key=lambda v: len(adj[v]) == 2):   # open ends first, loops after
        for nb in adj[start]:
            if key(start, nb) in seen:
                continue
            chain = [start, nb]; seen.add(key(start, nb))
            while len(adj[chain[-1]]) == 2:
                nxt = [w for w in adj[chain[-1]] if key(chain[-1], w) not in seen]
                if not nxt:
                    break
                seen.add(key(chain[-1], nxt[0])); chain.append(nxt[0])
            chains.append(chain)
    return chains


def ds_ice_can(K, L_CAN, L_CAP, dark_m):
    """The ICE car's jerrycan, built by its own builder, plus the adapter for the standard exporter.
    Returns (host names, the neck's top centre, the neck's axis), both in world coordinates."""
    before = set(K.col.objects)
    D = CAN_D
    res = build_reference_jerrycan(K, K.col, origin=(CAN_AT[0], CAN_AT[1], -0.055 * 1.06 * D), yaw_deg=90, D=D, prefix='diesel_can')
    bpy.context.view_layer.update()
    root = res['root']; M = root.matrix_world.copy(); Mi = M.inverted()
    # The can in the pump's red: its two materials rebuilt in place (every can part keeps its own).
    (t0, t1) = CAN_STEPS
    pw_toon_rgb('tn_diesel_red', ((t0, PUMP_RED[0]), (t1, PUMP_RED[1]), (9.0, PUMP_RED[2])))
    dark = [tuple(c * CAN_DARK for c in tone) for tone in PUMP_RED]
    pw_toon_rgb('tn_diesel_red_dark', ((t0, dark[0]), (t1, dark[1]), (9.0, dark[2])))
    for ob in K.col.objects:
        if ob not in before:
            ob['part_label'] = L_CAN
    body = bpy.data.objects['diesel_can_body']; neck = bpy.data.objects['diesel_can_neck']; cap = bpy.data.objects['diesel_can_cap']
    neck['part_label'] = L_CAP; cap['part_label'] = L_CAP
    # The loft's two rings (local y = -depth/2 is the broad face, which faces world +X).
    loc = [v.co.copy() for v in body.data.vertices]; m = len(loc) // 2
    front, back = loc[:m], loc[m:]
    prof = [(p.x, p.z) for p in front]; outs = alk_outward(prof); e = E / D
    def world(p):
        return tuple(M @ Vector(p))
    for nm, ring, dy in (('front', front, -e), ('back', back, e)):
        pts = [world((p.x + o.x * e, p.y + dy, p.z + o.y * e)) for p, o in zip(ring, outs)]
        tagged_line(K, 'can_%s_outline' % nm, pts, L_CAN, 6, True)['ink_width'] = 0
    for k in range(m):                                # depth corners where the profile turns sharply
        a, b, c = Vector(prof[k - 1]), Vector(prof[k]), Vector(prof[(k + 1) % m])
        if (b - a).angle(c - b, 0.0) > math.radians(30):
            o = outs[k]
            tagged_line(K, 'can_corner%d' % k, [world((b.x + o.x * e, front[k].y - e, b.y + o.y * e)),
                                                world((b.x + o.x * e, back[k].y + e, b.y + o.y * e))], L_CAN, 6, False)
    # The pressed X: rims where the finished broad face (after its Boolean pressings) steps in,
    # away from the perimeter; 3 px.
    dg = bpy.context.evaluated_depsgraph_get(); ev = body.evaluated_get(dg); me = ev.to_mesh()
    P = [body.matrix_world @ v.co for v in me.vertices]
    y_face = front[0].y
    on = [abs((Mi @ p).y - y_face) < 1e-5 for p in P]
    bm = bmesh.new(); bm.from_mesh(me)
    def far_from_outline(p):
        q = Mi @ p; x, z = q.x, q.z; best = 9.0
        for (ax, az), (bx, bz) in zip(prof, prof[1:] + prof[:1]):
            dx, dz = bx - ax, bz - az; t = max(0.0, min(1.0, ((x - ax) * dx + (z - az) * dz) / max(dx * dx + dz * dz, 1e-12)))
            best = min(best, math.hypot(x - ax - t * dx, z - az - t * dz))
        return best > 0.05
    rims = []
    for edge in bm.edges:
        i, j = edge.verts[0].index, edge.verts[1].index
        if not (on[i] and on[j]) or len(edge.link_faces) != 2:
            continue
        flat = [all(on[v.index] for v in f.verts) for f in edge.link_faces]
        if flat[0] != flat[1] and far_from_outline((P[i] + P[j]) / 2):
            rims.append((i, j))
    bm.free()
    push = (M.to_3x3() @ Vector((0.0, -1.0, 0.0))).normalized() * E
    for k, chain in enumerate(ds_chain(rims)):
        pts = [tuple(P[i] + push) for i in chain]
        closed = chain[0] == chain[-1]
        tagged_line(K, 'can_press%d' % k, pts[:-1] if closed else pts, L_CAN, SMALL_INK, closed)
    ev.to_mesh_clear()
    # The cap: swung open on a hinge at the neck's downhill rim (the builder's own shoulder frame).
    a, b = Vector((-.420, 0, 1.026)), Vector((-.190, 0, 1.105)); t = (b - a).normalized(); nrm = Vector((-t.z, 0, t.x))
    base = a.lerp(b, .5); top = base + nrm * .050     # the neck's top centre (neck: centre +0.020, depth 0.060)
    hinge = top - t * .105
    th = math.radians(CAP_SWING)
    def swing(p):
        q = p - hinge; x, z = q.x, q.z
        return hinge + Vector((x * math.cos(th) - z * math.sin(th), q.y, x * math.sin(th) + z * math.cos(th)))
    for v in cap.data.vertices:
        v.co = swing(v.co)
    cap.data.update()
    Y = Vector((0, 1, 0))
    for k, s in enumerate((0.040, 0.090)):            # the cap's two rims (its faces), after the swing
        pts = [world(swing(base + nrm * s + (t * math.cos(f) + Y * math.sin(f)) * (.096 + e))) for f in [2 * math.pi * i / 64 for i in range(64)]]
        tagged_line(K, 'can_cap_rim%d' % k, pts, L_CAP, SMALL_INK, True)
    # The open filler: a dark mouth on the neck's top, and the neck's and mouth's rims.
    disc = [top + nrm * .003 + (t * math.cos(f) + Y * math.sin(f)) * .072 for f in [2 * math.pi * i / 48 for i in range(48)]]
    vs = [world(p) for p in disc] + [world(p + nrm * .004) for p in disc]
    fs = [tuple(range(48)), tuple(48 + i for i in range(48))] + [(i, (i + 1) % 48, 48 + (i + 1) % 48, 48 + i) for i in range(48)]
    mouth = pw_clean_water(mesh(K, 'can_mouth', vs, fs, dark_m, False)); mouth['part_label'] = L_CAP; mouth.pass_index = 73
    tagged_line(K, 'can_neck_rim', [world(top + nrm * e + (t * math.cos(f) + Y * math.sin(f)) * (.105 + e)) for f in [2 * math.pi * i / 64 for i in range(64)]], L_CAP, SMALL_INK, True)
    tagged_line(K, 'can_mouth_rim', [world(top + nrm * .008 + (t * math.cos(f) + Y * math.sin(f)) * .072) for f in [2 * math.pi * i / 48 for i in range(48)]], L_CAP, SMALL_INK, True)
    axis = (M.to_3x3() @ nrm).normalized()
    return [body.name, neck.name, cap.name], M @ top, axis


def build_fuels():
    """Diesel fuel v6: the shipped pump on the grid, the ICE car's jerrycan, a pistol nozzle."""
    setup_icon_rig(); K = Kit(open_collection('ICON_fuels')); hosts = []
    red_m = pw_toon_rgb('ds_red', ((0.80, PUMP_RED[0]), (0.975, PUMP_RED[1]), (9.0, PUMP_RED[2])))
    plinth_m = pw_toon('ds_plinth', (0.503, 0.462, 0.366), ((0.70, 0.45), (0.95, 0.62), (9.0, 1.0)))   # top (188,181,163)
    hose_m = pw_toon('ds_hose', (0.40, 0.39, 0.35), ((0.70, 0.45), (0.95, 0.75), (9.0, 1.0)))
    metal_m = pw_toon('ds_metal', (0.62, 0.64, 0.66), ((0.70, 0.45), (0.95, 0.78), (9.0, 1.0)))
    panel_m = pw_flat('ds_panel', (0.503, 0.468, 0.381))                 # (188,182,166)
    readout_m = pw_flat('ds_readout', (0.223, 0.202, 0.150))             # (130,124,108)
    dark_m = pw_flat('ds_dark', (0.012, 0.014, 0.030))
    # Labels (1-7): parts that touch on screen never share one, except where their joint is inked.
    L_PUMP, L_CAP, L_PANEL, L_HOSE, L_NOZZLE, L_CAN, L_METAL = 1, 2, 3, 4, 5, 6, 7
    L_PLINTH = L_CAP                                                     # the plinth and the cap are far apart

    # Plinth and pump (with the holster's hole).
    hosts.append(alk_box(K, 'plinth', *PLINTH, plinth_m, L_PLINTH).name)
    hosts.append(ds_pump_body(K, red_m, plinth_m, L_PUMP).name)
    x0, x1, y0, y1, z0, z1 = PUMP
    # Display on the +X face: a light panel, two readouts and three buttons (3 px lines).
    dy0, dy1, dz0, dz1 = DISPLAY
    ds_print(K, 'display', alk_rect(dy0, dy1, dz0, dz1, 0.05), '+X', x1 - 0.002, x1 + 0.006, panel_m, L_PANEL)
    for k, (a0, a1, b0, b1) in enumerate(((0.40, 1.16, 2.36, 2.62), (0.52, 1.04, 2.10, 2.26))):
        uv = alk_rect(a0, a1, b0, b1, 0.03)
        ds_print(K, 'readout_%d' % k, uv, '+X', x1 + 0.004, x1 + 0.010, readout_m, L_PANEL)
        ds_outline(K, 'readout_%d_line' % k, uv, '+X', x1 + 0.014, L_PANEL)
    for k, yc in enumerate((0.58, 0.78, 0.98)):
        uv = alk_rect(yc - 0.065, yc + 0.065, 1.86, 1.99, 0.02)
        ds_outline(K, 'button_%d' % k, uv, '+X', x1 + 0.014, L_PANEL)
    # Holster: a light bezel round the hole, and the hose coming out of the hole.
    bx0, bx1, bz0, bz1 = BEZEL; hx0, hx1, hz0, hz1, hd = HOLE
    ds_bezel(K, 'holster_bezel', alk_rect(bx0, bx1, bz0, bz1, 0.06), alk_rect(hx0, hx1, hz0, hz1, 0.012),
             y0 - 0.012, y0 + 0.002, panel_m, L_PANEL)
    left = ds_spline([(0.50, y0 + hd + 0.07, 2.30), (0.50, 0.14, 2.28), (0.50, -0.03, 2.18), (0.49, -0.13, 1.92), (0.47, -0.16, 1.45),
                      (0.44, -0.18, 0.80), (0.30, -0.23, 0.40), (0.05, -0.27, 0.31), (-0.18, -0.21, 0.50), (-0.29, -0.02, 0.97),
                      (-0.23, 0.22, 1.45), (-0.04, 0.40, 1.70)], 10)
    hose = noink(K.sweep('hose_left', left, R_HOSE, hose_m, seg=28)); hose['part_label'] = L_HOSE; hosts.append(hose.name)

    # The ICE car's jerrycan.
    can_hosts, neck_top, neck_axis = ds_ice_can(K, L_CAN, L_CAP, dark_m)
    hosts += can_hosts

    # The pistol nozzle, in the side plane through the can's neck, rising back toward the pump; its
    # spout drops from the head's underside into the neck.
    a = math.radians(NOZ_TILT)
    U = Vector((0.0, math.cos(a), math.sin(a))); V = Vector((0.0, -math.sin(a), math.cos(a)))
    sd = Vector(SPOUT_DIR).normalized()
    P0 = neck_top - sd * SPOUT_LEN                                       # the spout's exit under the head
    O = P0 - U * SPOUT_AT[0] - V * SPOUT_AT[1]
    wb, wg, wl = NOZ_W
    hosts.append(ds_plate(K, 'nozzle_body', NOZ_BODY, O, U, V, wb, red_m, L_NOZZLE, 6).name)
    hosts.append(ds_plate(K, 'nozzle_guard', NOZ_GUARD, O, U, V, wg, red_m, L_NOZZLE, SMALL_INK).name)
    lever = ds_plate(K, 'nozzle_lever', NOZ_LEVER, O, U, V, wl, metal_m, L_METAL, SMALL_INK); hosts.append(lever.name)
    collar = noink(K.sweep('nozzle_collar', [tuple(O + U * 0.76 + V * COLLAR_V), tuple(O + U * 0.92 + V * COLLAR_V)], 0.075, metal_m, seg=40))
    collar['part_label'] = L_METAL; hosts.append(collar.name)
    ring = noink(K.sweep('spout_collar', [tuple(P0 - sd * 0.06), tuple(P0 + sd * 0.02)], 0.065, metal_m, seg=32))
    ring['part_label'] = L_METAL; hosts.append(ring.name)
    spout_pts = ds_spline([tuple(neck_top - neck_axis * 0.05), tuple(neck_top + neck_axis * 0.10), tuple(P0 + sd * 0.10), tuple(P0 - sd * 0.04)], 10)
    spout = noink(K.sweep('nozzle_spout', spout_pts, R_SPOUT, metal_m, seg=28)); spout['part_label'] = L_METAL; hosts.append(spout.name)
    # The pump's second hose: out of the collar, one arch over and down behind the can into the pump.
    right = ds_spline([tuple(O + U * 0.88 + V * COLLAR_V), tuple(O + U * 1.02 + V * (COLLAR_V + 0.02)), (2.06, 1.40, 2.50), (2.03, 1.58, 2.48),
                       (1.99, 1.72, 2.26), (1.95, 1.79, 1.90), (1.90, 1.78, 1.45), (1.82, 1.70, 1.08), (1.62, 1.55, 0.84),
                       (1.35, 1.40, 0.73), (1.10, 1.28, 0.70), (0.96, 1.22, 0.70)], 10)
    hose2 = noink(K.sweep('hose_right', right, R_HOSE, hose_m, seg=28)); hose2['part_label'] = L_HOSE; hosts.append(hose2.name)

    info = contract(K, hosts, 'fuel pump on a plinth (display, holster hole with its hose, a second hose) with a pistol nozzle filling the ICE car\'s jerrycan')
    info['revision'] = DS_REVISION
    info['outline']['component_boundaries'] = True
    info['stipple']['strength'] = 0.38
    info['stipple']['groups'][0]['thresholds'] = [0.65, 0.60, 0.35]    # +X faces take the 2x lattice, as on power
    info['dimensions'] = {'pump': PUMP, 'edge_radius': R_EDGE, 'rim_in': RIM_IN, 'plinth': PLINTH, 'display': DISPLAY, 'bezel': BEZEL,
                          'hole': HOLE, 'can': {'builder': 'base_kit.build_reference_jerrycan (the ICE car, g_056)', 'D': CAN_D, 'at': CAN_AT,
                          'yaw_deg': 90, 'cap_swing_deg': CAP_SWING, 'colour': 'the pump red', 'dark': CAN_DARK}, 'nozzle': {'tilt_deg': NOZ_TILT, 'spout': [SPOUT_DIR, SPOUT_LEN, SPOUT_AT], 'body': NOZ_BODY,
                          'guard': NOZ_GUARD, 'lever': NOZ_LEVER, 'widths': NOZ_W}, 'hose_radius': R_HOSE, 'spout_radius': R_SPOUT}
    return info
