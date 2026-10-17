"""Large engine (g_052 large_engine): concept blockouts for a locomotive power unit that reads as both a combustion
engine and an electric machine, the way a diesel-electric locomotive's is. A diesel prime mover (an EMD 710-like V16
with its turbocharger and exhaust) drives a main alternator coupled at its end; the alternator feeds traction motors.

Three directions, all on the long axis along X (the alternator's end face to +X, lower right; the engine's -Y flank,
lower left, toward the camera):
- A, power pack: the V16 and its main alternator on a long skid.
- B, compact genset: an inline six, its alternator and a radiator frame on a skid.
- C, power pack on a powered bogie: A, smaller, above a bogie whose axle carries a nose-hung traction motor.

Colours from the shipped art (slate blue-grey castings, brass fittings, pale grey). On the set's grid, camera, light,
12/4 px ink and dots on the shaded sides.

Owner, 2026-10-17: "Let's do large engine next. First dreamloop a locomotive engine and use real world references for
that. Try to make it somehow a combustion engine and a potential electric engine at the same time so we can abstract
that" """
import bmesh
from mathutils import Vector, Matrix

LE_REVISION = 'large_engine_v10'
TONES = {'slate': ((70, 88, 98), (95, 115, 125), (128, 148, 158)), 'pale': ((120, 128, 124), (155, 165, 155), (188, 196, 186)),
         'brass': ((120, 104, 70), (150, 132, 90), (190, 160, 108)), 'dark': ((44, 50, 60), (58, 64, 74), (76, 82, 92)),
         'copper': ((140, 82, 54), (176, 106, 70), (204, 136, 92)), 'yellow': ((165, 135, 75), (215, 165, 85), (235, 185, 95)),
         'bore': ((22, 28, 50), (26, 32, 56), (30, 36, 62)), 'sleeve': ((30, 32, 38), (40, 42, 50), (54, 56, 66))}
(L_SKID, L_BLOCK, L_HEAD, L_TURBO, L_ALT, L_ALT_END, L_TERM, L_CABLE, L_DOOR, L_PIPE, L_RAD, L_BOGIE, L_WHEEL, L_TMOTOR) = range(1, 15)


def le_box(K, name, x0, x1, y0, y1, z0, z1, mat, label, r=0.0):
    if r:
        return rounded_box(K, name, ((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2), (x1 - x0, y1 - y0, z1 - z0), mat, label, r)
    bm = bmesh.new(); bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co = Vector((x0 if v.co.x < 0 else x1, y0 if v.co.y < 0 else y1, z0 if v.co.z < 0 else z1))
    me = bpy.data.meshes.new(name); bm.to_mesh(me); bm.free()
    ob = K.obj(name, me, mat, False); noink(ob); ob['part_label'] = label
    return ob


def le_prism_x(K, name, profile, x0, x1, mat, label):
    """A closed (y, z) profile extruded along X."""
    n = len(profile); vs = [(x0, y, z) for y, z in profile] + [(x1, y, z) for y, z in profile]
    fs = [tuple(reversed(range(n))), tuple(range(n, 2 * n))] + [(k, (k + 1) % n, n + (k + 1) % n, n + k) for k in range(n)]
    me = bpy.data.meshes.new(name); me.from_pydata(vs, [], fs); me.update()
    bm = bmesh.new(); bm.from_mesh(me); bmesh.ops.recalc_face_normals(bm, faces=bm.faces); bm.to_mesh(me); bm.free()
    ob = K.obj(name, me, mat, False); noink(ob); ob['part_label'] = label
    return ob


def le_cyl(K, name, p0, p1, r, mat, label, seg=48, smooth=True):
    ob = K.dircyl(name, tuple(p0), tuple(p1), r, mat, segments=seg, smooth=smooth); noink(ob); ob['part_label'] = label
    return ob


def le_ring(K, name, c, axis, r_in, r_out, t, mat, label, seg=48):
    ob = noink(K.washer(name, tuple(c), tuple(axis), r_in, r_out, t, mat, seg=seg)); ob['part_label'] = label
    return ob


def le_alternator(K, mats, x0, x1, z, r, hosts, terminal=True):
    """The main alternator, coupled to the engine at x0: a bell housing, a ribbed drum, an end bell with a vent ring and a
    bearing hub facing +X, a terminal box on top with its output cables leaving toward the back."""
    bell = le_cyl(K, 'alt_bell', (x0 - 0.05, 0, z), (x0 + 0.22, 0, z), r * 0.92, mats['slate'], L_BLOCK, seg=64); hosts.append(bell.name)
    drum = le_cyl(K, 'alt_drum', (x0 + 0.18, 0, z), (x1 - 0.12, 0, z), r, mats['pale'], L_ALT, seg=64); hosts.append(drum.name)
    n = 7
    for k in range(n):
        x = x0 + 0.30 + (x1 - x0 - 0.55) * k / (n - 1)
        hosts.append(le_ring(K, 'alt_rib%d' % k, (x, 0, z), (1, 0, 0), r - 0.02, r + 0.05, 0.05, mats['pale'], L_ALT, seg=64).name)
    end = le_cyl(K, 'alt_end', (x1 - 0.14, 0, z), (x1, 0, z), r * 0.96, mats['brass'], L_ALT_END, seg=64); hosts.append(end.name)
    hosts.append(le_ring(K, 'alt_vent', (x1 + 0.005, 0, z), (1, 0, 0), r * 0.48, r * 0.80, 0.02, mats['dark'], L_ALT_END, seg=64).name)
    hosts.append(le_cyl(K, 'alt_hub', (x1 - 0.02, 0, z), (x1 + 0.10, 0, z), r * 0.30, mats['brass'], L_ALT_END, seg=48).name)
    hosts.append(le_cyl(K, 'alt_cap', (x1 + 0.09, 0, z), (x1 + 0.13, 0, z), r * 0.14, mats['dark'], L_ALT_END, seg=32).name)
    for k in range(8):
        a = math.radians(45 * k + 22.5); yy, zz = r * 0.64 * math.cos(a), z + r * 0.64 * math.sin(a)
        b = bolt_dot(K, 'alt_vent_slot%d' % k, (x1 + 0.016, yy, zz), 'X', r * 0.05, mats['bore']); b['part_label'] = L_ALT_END
    for s in (-1, 1):                            # feet down to the skid
        hosts.append(le_box(K, 'alt_foot_%+d' % s, x0 + 0.25, x1 - 0.20, s * r * 0.55 - 0.12, s * r * 0.55 + 0.12, 0.15, z - r * 0.55, mats['slate'], L_BLOCK).name)
    if terminal:
        tx = (x0 + x1) / 2
        hosts.append(le_box(K, 'alt_terminal', tx - 0.30, tx + 0.30, -0.28, 0.28, z + r - 0.08, z + r + 0.30, mats['brass'], L_TERM, 0.03).name)
        for k, yy in enumerate((-0.16, 0.0, 0.16)):     # three phases out through glands, bending back to the skid end
            g = le_cyl(K, 'alt_gland%d' % k, (tx - 0.30, yy, z + r + 0.12), (tx - 0.40, yy, z + r + 0.12), 0.05, mats['dark'], L_TERM, seg=24)
            hosts.append(g.name)
            path = pl_catmull([Vector((tx - 0.38, yy, z + r + 0.12)), Vector((tx - 0.62, yy, z + r + 0.10)), Vector((tx - 0.80, yy * 1.4, z + r - 0.25))], 8)
            c = noink(K.sweep('alt_cable%d' % k, path, 0.04, mats['copper'], seg=16)); c['part_label'] = L_CABLE; hosts.append(c.name)


def le_v16(K, mats, x0, x1, z0, hosts, cyl=8, turbo=True):
    """The prime mover: a crankcase on its pan, the V block with a cylinder head per cylinder on each bank, crankcase
    doors along the near flank, the air box rail, and the turbocharger with its exhaust stack at the free end (-X)."""
    hosts.append(le_box(K, 'pan', x0 + 0.05, x1 - 0.05, -0.50, 0.50, z0, z0 + 0.32, mats['slate'], L_BLOCK).name)
    prof = [(-0.58, z0 + 0.30), (0.58, z0 + 0.30), (0.58, z0 + 0.80), (0.82, z0 + 1.08), (0.46, z0 + 1.42), (0, z0 + 1.18),
            (-0.46, z0 + 1.42), (-0.82, z0 + 1.08), (-0.58, z0 + 0.80)]
    hosts.append(le_prism_x(K, 'block', prof, x0, x1, mats['slate'], L_BLOCK).name)
    pitch = (x1 - x0 - 0.30) / cyl
    for s in (-1, 1):
        for k in range(cyl):
            cx = x0 + 0.15 + pitch * (k + 0.5)
            cy, cz = s * 0.66, z0 + 1.28
            h = K.rotbox('head_%+d_%d' % (s, k), cx, cy, cz, pitch * 0.82, 0.42, 0.22, mats['pale'], 'X', -45.0 * s)
            noink(h); h['part_label'] = L_HEAD; hosts.append(h.name)
    for k in range(cyl):                         # crankcase inspection doors along the near flank
        cx = x0 + 0.15 + pitch * (k + 0.5)
        hosts.append(le_box(K, 'door_%d' % k, cx - pitch * 0.34, cx + pitch * 0.34, -0.62, -0.57, z0 + 0.40, z0 + 0.72, mats['pale'], L_DOOR, 0.02).name)
    hosts.append(le_cyl(K, 'air_box', (x0 + 0.10, -0.84, z0 + 0.86), (x1 - 0.10, -0.84, z0 + 0.86), 0.09, mats['brass'], L_PIPE, seg=32).name)
    hosts.append(le_box(K, 'exhaust_manifold', x0 + 0.10, x1 - 0.10, -0.16, 0.16, z0 + 1.10, z0 + 1.40, mats['dark'], L_PIPE, 0.04).name)
    if turbo:
        tx = x0 - 0.05
        hosts.append(le_cyl(K, 'turbo', (tx, -0.30, z0 + 1.62), (tx, 0.30, z0 + 1.62), 0.38, mats['brass'], L_TURBO, seg=64).name)
        hosts.append(le_cyl(K, 'turbo_inlet', (tx, -0.30, z0 + 1.62), (tx, -0.56, z0 + 1.62), 0.24, mats['brass'], L_TURBO, seg=48).name)
        hosts.append(le_ring(K, 'turbo_mouth', (tx, -0.57, z0 + 1.62), (0, -1, 0), 0.14, 0.24, 0.02, mats['dark'], L_TURBO).name)
        hosts.append(le_box(K, 'turbo_bracket', tx - 0.25, tx + 0.30, -0.30, 0.30, z0 + 1.10, z0 + 1.40, mats['slate'], L_BLOCK).name)
        hosts.append(le_box(K, 'stack', tx - 0.22, tx + 0.22, -0.16, 0.16, z0 + 1.90, z0 + 2.42, mats['dark'], L_PIPE, 0.03).name)
        hosts.append(le_box(K, 'stack_lip', tx - 0.25, tx + 0.25, -0.19, 0.19, z0 + 2.38, z0 + 2.46, mats['dark'], L_PIPE, 0.02).name)


def le_finish(K, hosts, desc):
    bpy.context.view_layer.update()
    for n in hosts:
        pl_mesh_lines(K, bpy.data.objects[n], bpy.data.objects[n]['part_label'], 40.0, n, 0.03)
    for ob in K.col.objects:
        if ob.get('ink_width') == 6:
            ob['ink_width'] = PL_INNER
    info = contract(K, hosts[:3], desc, inner=PL_INNER)
    info['revision'] = LE_REVISION; info['outline']['component_boundaries'] = True; info['outline']['id_step'] = 17
    info['stipple']['strength'] = 0.38
    info['stipple']['groups'] = [{'name': 'shaded_faces', 'labels': list(range(1, 15)), 'thresholds': [0.575, 0.50, 0.30]}]
    return info


def build_le_a():
    """A, power pack: the V16 and its main alternator on a long skid."""
    setup_icon_rig(); K = Kit(open_collection('ICON_le_a')); hosts = []
    mats = {k: pl_toon('le_' + k, *v) for k, v in TONES.items()}
    hosts.append(le_box(K, 'skid', -2.35, 2.75, -0.80, 0.80, 0.0, 0.16, mats['dark'], L_SKID).name)
    le_v16(K, mats, -2.0, 1.15, 0.16, hosts)
    le_alternator(K, mats, 1.15, 2.60, 0.98, 0.74, hosts)
    return le_finish(K, hosts, 'locomotive power pack: V16 prime mover with turbocharger and stack, coupled main alternator, skid')


def build_le_b():
    """B, compact genset: an inline six, its alternator and a radiator frame on a skid."""
    setup_icon_rig(); K = Kit(open_collection('ICON_le_b')); hosts = []
    mats = {k: pl_toon('le_' + k, *v) for k, v in TONES.items()}
    hosts.append(le_box(K, 'skid', -2.30, 2.45, -0.75, 0.75, 0.0, 0.16, mats['dark'], L_SKID).name)
    z0 = 0.16
    hosts.append(le_box(K, 'pan', -1.15, 0.95, -0.42, 0.42, z0, z0 + 0.36, mats['slate'], L_BLOCK).name)
    hosts.append(le_box(K, 'block', -1.20, 1.00, -0.50, 0.50, z0 + 0.34, z0 + 1.10, mats['slate'], L_BLOCK).name)
    for k in range(6):
        cx = -1.08 + 0.34 * (k + 0.5)
        hosts.append(le_box(K, 'head_%d' % k, cx - 0.15, cx + 0.15, -0.40, 0.40, z0 + 1.08, z0 + 1.30, mats['pale'], L_HEAD, 0.03).name)
        hosts.append(le_box(K, 'door_%d' % k, cx - 0.11, cx + 0.11, -0.55, -0.50, z0 + 0.48, z0 + 0.86, mats['pale'], L_DOOR, 0.02).name)
    hosts.append(le_cyl(K, 'turbo', (-0.40, -0.25, z0 + 1.55), (-0.40, 0.25, z0 + 1.55), 0.28, mats['brass'], L_TURBO, seg=64).name)
    hosts.append(le_box(K, 'turbo_bracket', -0.60, -0.20, -0.25, 0.25, z0 + 1.25, z0 + 1.40, mats['slate'], L_BLOCK).name)
    hosts.append(le_box(K, 'stack', -0.52, -0.28, -0.12, 0.12, z0 + 1.75, z0 + 2.15, mats['dark'], L_PIPE, 0.03).name)
    hosts.append(le_cyl(K, 'air_box', (-1.10, -0.62, z0 + 0.95), (0.90, -0.62, z0 + 0.95), 0.08, mats['brass'], L_PIPE, seg=32).name)
    hosts.append(le_box(K, 'radiator', -2.20, -1.70, -0.72, 0.72, z0, z0 + 1.80, mats['slate'], L_RAD, 0.03).name)
    hosts.append(le_box(K, 'radiator_core', -1.72, -1.66, -0.60, 0.60, z0 + 0.15, z0 + 1.65, mats['dark'], L_RAD).name)
    hosts.append(le_cyl(K, 'radiator_hose', (-1.68, 0.30, z0 + 1.30), (-1.18, 0.30, z0 + 1.00), 0.07, mats['dark'], L_PIPE, seg=24).name)
    le_alternator(K, mats, 1.00, 2.30, 0.86, 0.62, hosts)
    return le_finish(K, hosts, 'compact genset: inline six with turbocharger, coupled alternator, radiator frame, skid')


def build_le_c():
    """C, power pack on a powered bogie: A, smaller, above a bogie whose axle carries a nose-hung traction motor."""
    setup_icon_rig(); K = Kit(open_collection('ICON_le_c')); hosts = []
    mats = {k: pl_toon('le_' + k, *v) for k, v in TONES.items()}
    zb = 1.10                                    # the power pack's deck height above the rails
    # the bogie: side frames, two wheelsets, a traction motor hung on the front axle, a cable from the alternator
    for s in (-1, 1):
        hosts.append(le_box(K, 'bogie_frame_%+d' % s, -1.70, 1.70, s * 0.78 - 0.08, s * 0.78 + 0.08, 0.45, 0.85, mats['dark'], L_BOGIE, 0.03).name)
    hosts.append(le_box(K, 'bogie_transom', -0.25, 0.25, -0.78, 0.78, 0.50, 0.82, mats['dark'], L_BOGIE).name)
    for k, x in enumerate((-1.05, 1.05)):
        hosts.append(le_cyl(K, 'axle_%d' % k, (x, -0.95, 0.58), (x, 0.95, 0.58), 0.08, mats['dark'], L_WHEEL, seg=32).name)
        for s in (-1, 1):
            hosts.append(le_cyl(K, 'wheel_%d_%+d' % (k, s), (x, s * 0.62, 0.58), (x, s * 0.74, 0.58), 0.52, mats['slate'], L_WHEEL, seg=64).name)
            hosts.append(le_cyl(K, 'flange_%d_%+d' % (k, s), (x, s * 0.60, 0.58), (x, s * 0.63, 0.58), 0.57, mats['slate'], L_WHEEL, seg=64).name)
    hosts.append(le_cyl(K, 'traction_motor', (1.05 - 0.48, -0.50, 0.55), (1.05 - 0.48, 0.50, 0.55), 0.36, mats['pale'], L_TMOTOR, seg=64).name)
    hosts.append(le_box(K, 'gear_case', 0.80, 1.30, 0.50, 0.62, 0.20, 0.80, mats['slate'], L_TMOTOR, 0.04).name)
    hosts.append(le_box(K, 'deck', -2.05, 2.25, -0.85, 0.85, 0.88, zb, mats['dark'], L_SKID).name)
    le_v16(K, mats, -1.75, 0.70, zb, hosts, cyl=6)
    le_alternator(K, mats, 0.70, 1.95, zb + 0.72, 0.60, hosts)
    path = pl_catmull([Vector((1.30, -0.62, zb + 0.20)), Vector((1.25, -0.88, zb - 0.20)), Vector((0.75, -0.72, 0.72))], 8)
    c = noink(K.sweep('motor_cable', path, 0.05, mats['copper'], seg=16)); c['part_label'] = L_CABLE; hosts.append(c.name)
    return le_finish(K, hosts, 'diesel-electric power pack on a powered bogie with a nose-hung traction motor')


def build_le_a2():
    """A2 (loop 2: A was a long thin diagonal that shrank to a sliver at 60 px): a compact V12 with a bigger alternator
    on a short skid, about 1.6x as long as tall."""
    setup_icon_rig(); K = Kit(open_collection('ICON_le_a2')); hosts = []
    mats = {k: pl_toon('le_' + k, *v) for k, v in TONES.items()}
    hosts.append(le_box(K, 'skid', -1.55, 2.25, -0.85, 0.85, 0.0, 0.18, mats['dark'], L_SKID).name)
    le_v16(K, mats, -1.20, 0.80, 0.18, hosts, cyl=6)
    le_alternator(K, mats, 0.80, 2.10, 1.02, 0.84, hosts)
    return le_finish(K, hosts, 'compact locomotive power pack: V12 prime mover with turbocharger and stack, large coupled main alternator')


def build_le_c2():
    """C2 (loop 2: C's deck hid the bogie): a narrower deck so the bogie's wheels, frame and traction motor show."""
    setup_icon_rig(); K = Kit(open_collection('ICON_le_c2')); hosts = []
    mats = {k: pl_toon('le_' + k, *v) for k, v in TONES.items()}
    zb = 1.05; zw = 0.58
    for s in (-1, 1):
        hosts.append(le_box(K, 'bogie_frame_%+d' % s, -1.55, 1.55, s * 0.86 - 0.07, s * 0.86 + 0.07, 0.48, 0.86, mats['yellow'], L_BOGIE, 0.03).name)
        for k, x in enumerate((-0.95, 0.95)):
            hosts.append(le_box(K, 'axlebox_%d_%+d' % (k, s), x - 0.16, x + 0.16, s * 0.94 - 0.06, s * 0.94 + 0.06, zw - 0.16, zw + 0.16, mats['dark'], L_BOGIE, 0.02).name)
            hosts.append(le_cyl(K, 'spring_%d_%+d' % (k, s), (x, s * 0.94, zw + 0.16), (x, s * 0.94, 0.86), 0.09, mats['dark'], L_BOGIE, seg=24).name)
    for k, x in enumerate((-0.95, 0.95)):
        hosts.append(le_cyl(K, 'axle_%d' % k, (x, -1.0, zw), (x, 1.0, zw), 0.08, mats['dark'], L_WHEEL, seg=32).name)
        for s in (-1, 1):
            hosts.append(le_cyl(K, 'wheel_%d_%+d' % (k, s), (x, s * 0.60, zw), (x, s * 0.74, zw), zw - 0.05, mats['slate'], L_WHEEL, seg=64).name)
            hosts.append(le_cyl(K, 'flange_%d_%+d' % (k, s), (x, s * 0.58, zw), (x, s * 0.61, zw), zw - 0.01, mats['slate'], L_WHEEL, seg=64).name)
    hosts.append(le_cyl(K, 'traction_motor', (0.45, -0.48, 0.60), (0.45, 0.48, 0.60), 0.38, mats['pale'], L_TMOTOR, seg=64).name)
    hosts.append(le_box(K, 'gear_case', 0.62, 1.20, -0.56, -0.44, 0.22, 0.86, mats['slate'], L_TMOTOR, 0.04).name)
    hosts.append(le_box(K, 'deck', -1.65, 2.05, -0.62, 0.62, 0.90, zb, mats['dark'], L_SKID).name)
    le_v16(K, mats, -1.35, 0.55, zb, hosts, cyl=6)
    le_alternator(K, mats, 0.55, 1.85, zb + 0.70, 0.62, hosts)
    path = pl_catmull([Vector((1.20, -0.60, zb + 0.15)), Vector((1.05, -0.80, zb - 0.15)), Vector((0.60, -0.52, 0.80))], 8)
    c = noink(K.sweep('motor_cable', path, 0.05, mats['copper'], seg=16)); c['part_label'] = L_CABLE; hosts.append(c.name)
    return le_finish(K, hosts, 'diesel-electric power pack on a powered bogie with a traction motor and its cable')


# Loop 3 (owner: "this needs to represent both lorry engines and locomotive engines and in the future be a part that
# together with other inputs results in ship components (as a single good abstracting ship engines, turbines etc)"):
# the common form across a lorry's straight six, a locomotive's prime mover and a ship's medium-speed engine is a
# heavy-duty inline diesel with a turbocharger at its free end and an output end that can drive anything.

def le_inline(K, mats, x0, x1, z0, hosts, cyl=6):
    """A tall inline heavy-duty diesel along X, free end at x0 (-X), output end at x1 (+X): a pan, a tall block with a
    crankcase door per cylinder on the near flank, a cylinder head and rocker cover per cylinder, the exhaust manifold
    along the far side up to a turbocharger at the free end, a charge-air pipe back down the near side to the intake
    rail, and the flywheel housing at the output end."""
    pitch = (x1 - x0 - 0.20) / cyl
    hosts.append(le_box(K, 'pan', x0 + 0.08, x1 - 0.08, -0.46, 0.46, z0, z0 + 0.34, mats['slate'], L_BLOCK, 0.03).name)
    hosts.append(le_box(K, 'block', x0, x1, -0.56, 0.56, z0 + 0.30, z0 + 1.30, mats['slate'], L_BLOCK).name)
    for k in range(cyl):
        cx = x0 + 0.10 + pitch * (k + 0.5)
        hosts.append(le_box(K, 'door_%d' % k, cx - pitch * 0.32, cx + pitch * 0.32, -0.61, -0.555, z0 + 0.44, z0 + 0.86, mats['pale'], L_DOOR, 0.02).name)
        hosts.append(le_box(K, 'head_%d' % k, cx - pitch * 0.46, cx + pitch * 0.46, -0.50, 0.50, z0 + 1.28, z0 + 1.56, mats['pale'], L_HEAD, 0.02).name)
        hosts.append(le_box(K, 'rocker_%d' % k, cx - pitch * 0.36, cx + pitch * 0.36, -0.36, 0.30, z0 + 1.54, z0 + 1.72, mats['slate'], L_HEAD, 0.03).name)
        hosts.append(le_cyl(K, 'runner_%d' % k, (cx, 0.40, z0 + 1.40), (cx, 0.70, z0 + 1.40), 0.07, mats['dark'], L_PIPE, seg=24).name)
    hosts.append(le_cyl(K, 'exhaust_manifold', (x0 + 0.05, 0.72, z0 + 1.40), (x1 - 0.10, 0.72, z0 + 1.40), 0.13, mats['dark'], L_PIPE, seg=32).name)
    hosts.append(le_cyl(K, 'intake_rail', (x0 + 0.05, -0.68, z0 + 1.12), (x1 - 0.15, -0.68, z0 + 1.12), 0.11, mats['brass'], L_PIPE, seg=32).name)
    tx = x0 - 0.08
    hosts.append(le_box(K, 'turbo_bracket', tx - 0.20, tx + 0.30, -0.30, 0.55, z0 + 1.30, z0 + 1.62, mats['slate'], L_BLOCK).name)
    hosts.append(le_cyl(K, 'turbo', (tx, -0.28, z0 + 1.86), (tx, 0.42, z0 + 1.86), 0.36, mats['brass'], L_TURBO, seg=64).name)
    hosts.append(le_cyl(K, 'turbo_inlet', (tx, -0.28, z0 + 1.86), (tx, -0.52, z0 + 1.86), 0.22, mats['brass'], L_TURBO, seg=48).name)
    hosts.append(le_ring(K, 'turbo_mouth', (tx, -0.53, z0 + 1.86), (0, -1, 0), 0.12, 0.22, 0.02, mats['dark'], L_TURBO).name)
    hosts.append(le_box(K, 'stack', tx - 0.20, tx + 0.20, 0.0, 0.32, z0 + 2.10, z0 + 2.55, mats['dark'], L_PIPE, 0.03).name)
    path = pl_catmull([Vector((tx, -0.52, z0 + 1.62)), Vector((tx + 0.10, -0.70, z0 + 1.40)), Vector((x0 + 0.25, -0.70, z0 + 1.16))], 8)
    c = noink(K.sweep('charge_air', path, 0.10, mats['brass'], seg=24)); c['part_label'] = L_PIPE; hosts.append(c.name)
    hosts.append(le_cyl(K, 'flywheel_housing', (x1 - 0.02, 0, z0 + 0.80), (x1 + 0.22, 0, z0 + 0.80), 0.78, mats['slate'], L_BLOCK, seg=64).name)


def le_output(K, mats, x, z, hosts, shaft=0.0):
    """The output end: a flywheel face with a bolted coupling flange on the shaft, optionally a length of shaft beyond."""
    hosts.append(le_cyl(K, 'coupling', (x, 0, z), (x + 0.16, 0, z), 0.46, mats['brass'], L_ALT_END, seg=64).name)
    for k in range(8):
        a = math.radians(45 * k + 22.5)
        b = bolt_dot(K, 'coupling_bolt%d' % k, (x + 0.162, 0.36 * math.cos(a), z + 0.36 * math.sin(a)), 'X', 0.035, mats['bore']); b['part_label'] = L_ALT_END
    hosts.append(le_cyl(K, 'coupling_hub', (x + 0.14, 0, z), (x + 0.26 + shaft, 0, z), 0.16, mats['pale'], L_ALT_END, seg=48).name)
    if shaft:
        hosts.append(le_cyl(K, 'shaft_flange', (x + 0.20 + shaft, 0, z), (x + 0.28 + shaft, 0, z), 0.30, mats['brass'], L_ALT_END, seg=48).name)


def le_motor_gen(K, mats, x0, x1, z, r, hosts):
    """A slim motor-generator on the shaft: a ribbed drum with a terminal box and three cables."""
    hosts.append(le_cyl(K, 'mg_drum', (x0, 0, z), (x1, 0, z), r, mats['pale'], L_ALT, seg=64).name)
    for k in range(4):
        x = x0 + 0.08 + (x1 - x0 - 0.16) * k / 3
        hosts.append(le_ring(K, 'mg_rib%d' % k, (x, 0, z), (1, 0, 0), r - 0.02, r + 0.05, 0.05, mats['pale'], L_ALT, seg=64).name)
    tx = (x0 + x1) / 2
    hosts.append(le_box(K, 'mg_terminal', tx - 0.18, tx + 0.18, -0.20, 0.20, z + r - 0.06, z + r + 0.22, mats['brass'], L_TERM, 0.03).name)
    for k, yy in enumerate((-0.11, 0.0, 0.11)):
        path = pl_catmull([Vector((tx - 0.18, yy, z + r + 0.10)), Vector((tx - 0.40, yy, z + r + 0.08)), Vector((tx - 0.55, yy * 1.4, z + r - 0.20))], 8)
        cbl = noink(K.sweep('mg_cable%d' % k, path, 0.035, mats['copper'], seg=16)); cbl['part_label'] = L_CABLE; hosts.append(cbl.name)


def le_mounts(K, mats, xs, hosts, z0=0.0, z1=0.30):
    """Resilient mounts on a pair of base rails: a low rubber block under a foot bracket at each station."""
    x0, x1 = min(xs) - 0.40, max(xs) + 0.40
    for s in (-1, 1):
        hosts.append(le_box(K, 'base_rail_%+d' % s, x0, x1, s * 0.66 - 0.16, s * 0.66 + 0.16, z0, z0 + 0.10, mats['dark'], L_SKID).name)
    for k, x in enumerate(xs):
        for s in (-1, 1):
            hosts.append(le_box(K, 'mount_rubber_%d_%+d' % (k, s), x - 0.14, x + 0.14, s * 0.66 - 0.10, s * 0.66 + 0.10, z0 + 0.10, z1 - 0.04, mats['dark'], L_SKID, 0.03).name)
            hosts.append(le_box(K, 'mount_foot_%d_%+d' % (k, s), x - 0.18, x + 0.18, s * 0.56 - 0.14, s * 0.66 + 0.12, z1 - 0.06, z1 + 0.20, mats['slate'], L_BLOCK).name)


def le_flywheel(K, mats, x, z, R, hosts, depth=0.30):
    """The output flywheel, laid out as the shipped icon's (owner on loop 3: "do D2 with a lip in the same layout as the
    old icon's - set out from the face with the holes in a circle"): a deep brass disc set out from the end, a raised
    lip round its face, a hub plate set into the lip with a circle of bolt holes, and a bored boss at the centre."""
    hosts.append(le_cyl(K, 'flywheel', (x, 0, z), (x + depth, 0, z), R, mats['brass'], L_ALT_END, seg=96).name)
    hosts.append(le_ring(K, 'flywheel_lip', (x + depth + 0.03, 0, z), (1, 0, 0), R * 0.80, R, 0.06, mats['brass'], L_ALT_END, seg=96).name)
    hosts.append(le_cyl(K, 'hub_plate', (x + depth - 0.01, 0, z), (x + depth + 0.025, 0, z), R * 0.58, mats['slate'], L_TERM, seg=96).name)
    for k in range(10):
        a = math.radians(36 * k)
        b = bolt_dot(K, 'flywheel_hole%d' % k, (x + depth + 0.03, R * 0.40 * math.cos(a), z + R * 0.40 * math.sin(a)), 'X', R * 0.05, mats['bore'])
        b['part_label'] = L_TERM
    hosts.append(le_cyl(K, 'flywheel_boss', (x + depth, 0, z), (x + depth + 0.07, 0, z), R * 0.18, mats['slate'], L_TERM, seg=48).name)
    b = bolt_dot(K, 'flywheel_bore', (x + depth + 0.072, 0, z), 'X', R * 0.09, mats['bore']); b['part_label'] = L_TERM


def build_le_d1():
    """D1: the universal inline diesel alone, ending in its flywheel and output coupling."""
    setup_icon_rig(); K = Kit(open_collection('ICON_le_d1')); hosts = []
    mats = {k: pl_toon('le_' + k, *v) for k, v in TONES.items()}
    z0 = 0.22; le_mounts(K, mats, (-0.70, 0.75), hosts, 0.0, z0)
    le_inline(K, mats, -1.15, 1.10, z0, hosts)
    le_output(K, mats, 1.32, z0 + 0.80, hosts)
    return le_finish(K, hosts, 'universal heavy-duty inline diesel with turbocharger, flywheel housing and output coupling, on mounts')


def le_inline2(K, mats, x0, x1, z0, hosts, cyl=6):
    """v5 (review of D2): the inline six with its hot and cold paths legible. Slate heads under six raised pale rocker
    covers (the inline-six signature at 60 px), brass crankcase doors as on the shipped art. Cold side, toward the camera
    (-Y): air into the brass compressor, down the charge-air pipe to the intake rail, a runner up into each head. Hot
    side (+Y): a runner from each head into the dark exhaust manifold, back to the dark turbine and up the open stack."""
    pitch = (x1 - x0 - 0.20) / cyl; zt = z0 + 1.78; tx = x0 - 0.10
    hosts.append(le_box(K, 'pan', x0 + 0.08, x1 - 0.08, -0.46, 0.46, z0, z0 + 0.34, mats['slate'], L_BLOCK, 0.03).name)
    hosts.append(le_box(K, 'block', x0, x1, -0.56, 0.56, z0 + 0.30, z0 + 1.30, mats['slate'], L_BLOCK).name)
    for k in range(cyl):
        cx = x0 + 0.10 + pitch * (k + 0.5)
        hosts.append(le_box(K, 'door_%d' % k, cx - pitch * 0.32, cx + pitch * 0.32, -0.61, -0.555, z0 + 0.44, z0 + 0.86, mats['brass'], L_DOOR, 0.02).name)
        hosts.append(le_box(K, 'head_%d' % k, cx - pitch * 0.46, cx + pitch * 0.46, -0.50, 0.50, z0 + 1.28, z0 + 1.56, mats['slate'], L_HEAD, 0.02).name)
        hosts.append(le_box(K, 'rocker_%d' % k, cx - pitch * 0.38, cx + pitch * 0.38, -0.34, 0.32, z0 + 1.54, z0 + 1.78, mats['pale'], L_HEAD, 0.04).name)
        hosts.append(le_cyl(K, 'exhaust_runner_%d' % k, (cx, 0.40, z0 + 1.40), (cx, 0.70, z0 + 1.40), 0.07, mats['dark'], L_PIPE, seg=24).name)
        hosts.append(le_cyl(K, 'intake_runner_%d' % k, (cx, -0.62, z0 + 1.30), (cx, -0.44, z0 + 1.42), 0.06, mats['brass'], L_PIPE, seg=24).name)
    hosts.append(le_cyl(K, 'exhaust_manifold', (x0 + 0.02, 0.72, z0 + 1.40), (x1 - 0.10, 0.72, z0 + 1.40), 0.13, mats['dark'], L_PIPE, seg=32).name)
    hosts.append(le_cyl(K, 'intake_rail', (x0 + 0.02, -0.60, z0 + 1.30), (x1 - 0.15, -0.60, z0 + 1.30), 0.11, mats['brass'], L_PIPE, seg=32).name)
    # the turbocharger at the free end: compressor (cold, brass) toward the camera, turbine (hot, dark) behind
    hosts.append(le_box(K, 'turbo_bracket', tx - 0.18, tx + 0.28, -0.25, 0.40, z0 + 1.30, z0 + 1.58, mats['slate'], L_BLOCK).name)
    hosts.append(le_cyl(K, 'compressor', (tx, -0.30, zt), (tx, 0.05, zt), 0.26, mats['brass'], L_TURBO, seg=64).name)
    hosts.append(le_cyl(K, 'compressor_inlet', (tx, -0.30, zt), (tx, -0.48, zt), 0.16, mats['brass'], L_TURBO, seg=48).name)
    hosts.append(le_ring(K, 'compressor_mouth', (tx, -0.49, zt), (0, -1, 0), 0.08, 0.16, 0.02, mats['dark'], L_TURBO).name)
    hosts.append(le_cyl(K, 'turbine', (tx, 0.03, zt), (tx, 0.45, zt), 0.26, mats['dark'], L_PIPE, seg=64).name)
    hosts.append(le_cyl(K, 'stack', (tx, 0.24, zt + 0.10), (tx, 0.24, zt + 0.62), 0.14, mats['dark'], L_PIPE, seg=48).name)
    hosts.append(le_cyl(K, 'stack_lip', (tx, 0.24, zt + 0.56), (tx, 0.24, zt + 0.64), 0.17, mats['dark'], L_PIPE, seg=48).name)
    b = bolt_dot(K, 'stack_bore', (tx, 0.24, zt + 0.645), 'Z', 0.11, mats['bore']); b['part_label'] = L_PIPE
    hot = pl_catmull([Vector((x0 + 0.08, 0.72, z0 + 1.40)), Vector((tx + 0.08, 0.66, z0 + 1.52)), Vector((tx, 0.42, zt - 0.06))], 8)
    c = noink(K.sweep('exhaust_to_turbine', hot, 0.12, mats['dark'], seg=24)); c['part_label'] = L_PIPE; hosts.append(c.name)
    cold = pl_catmull([Vector((tx, -0.18, zt - 0.20)), Vector((tx + 0.04, -0.46, z0 + 1.48)), Vector((x0 + 0.06, -0.60, z0 + 1.30))], 8)
    c = noink(K.sweep('charge_air', cold, 0.10, mats['brass'], seg=24)); c['part_label'] = L_PIPE; hosts.append(c.name)
    hosts.append(le_cyl(K, 'flywheel_housing', (x1 - 0.02, 0, z0 + 0.80), (x1 + 0.20, 0, z0 + 0.80), 0.78, mats['slate'], L_BLOCK, seg=64).name)


JBOX = dict(y=(-1.22, -0.92), z=(0.10, 0.34), w=0.44, sleeve=0.055)                # the cable junction box under the terminal box, on its own plate


def le_motor_gen2(K, mats, x0, x1, z, r, rail_y, hosts):
    """A short slate motor-generator: axial cooling fins over its top and far side, the yellow terminal box of the
    approved motor icon on its near flank below the fins, three slim phase cables dropping straight from glands under
    the box into a cable junction box on its own plate out beside the base rail, where the vehicle's or ship's wiring
    connects. Only the shaft and flywheel turn; the housing, fins, box and cables are fixed (v7, owner: "cables
    interpenetrate the ridges. I think move the box further out or reconsider the cables' position if that drive is
    meant to rotate")."""
    hosts.append(le_cyl(K, 'mg_drum', (x0, 0, z), (x1, 0, z), r, mats['slate'], L_ALT, seg=64).name)
    for k in range(13):
        phi = -100 + 165 * k / 12                # fins from the far side over the crown to 65 deg on the near side
        a = math.radians(phi); rc = r + 0.03
        f = K.rotbox('mg_fin%02d' % k, (x0 + x1) / 2, -rc * math.sin(a), z + rc * math.cos(a), x1 - x0 - 0.08, 0.035, 0.08, mats['slate'], 'X', phi)
        noink(f); f['part_label'] = L_ALT; hosts.append(f.name)
    tx = (x0 + x1) / 2; jb = JBOX
    # the terminal box on the near flank, seated into the drum below the last fin
    tb_y, tb_z = (-r - 0.20, -r + 0.18), (z - 0.46, z - 0.02)
    hosts.append(le_box(K, 'mg_terminal', tx - 0.22, tx + 0.22, tb_y[0], tb_y[1], tb_z[0], tb_z[1], mats['yellow'], L_TERM, 0.03).name)
    jy = (jb['y'][0] + jb['y'][1]) / 2
    for k, gx in enumerate((tx - 0.12, tx, tx + 0.12)):
        gy = tb_y[0] + 0.10
        hosts.append(le_cyl(K, 'mg_gland%d' % k, (gx, gy, tb_z[0] + 0.01), (gx, gy, tb_z[0] - 0.07), 0.034, mats['yellow'], L_TERM, seg=24).name)
        zt, zb = tb_z[0] - 0.06, jb['z'][1] + 0.02 + jb['sleeve'] - 0.01      # into the top of its sleeve
        path = pl_catmull([Vector((gx, gy, zt)), Vector((gx, gy - (gy - jy) * 0.15, zt - (zt - zb) * 0.45)), Vector((gx, jy, zb))], 12)
        cbl = noink(K.sweep('mg_cable%d' % k, path, 0.026, mats['copper'], seg=16)); cbl['part_label'] = L_CABLE; hosts.append(cbl.name)
        # v8 (owner: "the cables should meet the top of the little box in black sleeves"): a black sleeve over each
        # cable where it enters the junction box lid
        hosts.append(le_cyl(K, 'jb_sleeve%d' % k, (gx, jy, jb['z'][1] + 0.02), (gx, jy, jb['z'][1] + 0.02 + jb['sleeve']), 0.046, mats['sleeve'], L_DOOR, seg=24).name)
        hosts.append(le_cyl(K, 'jb_sleeve_collar%d' % k, (gx, jy, jb['z'][1] + 0.01), (gx, jy, jb['z'][1] + 0.045), 0.06, mats['sleeve'], L_DOOR, seg=24).name)
    hw = jb['w'] / 2
    hosts.append(le_box(K, 'junction_box', tx - hw, tx + hw, jb['y'][0], jb['y'][1], jb['z'][0], jb['z'][1], mats['slate'], L_TERM, 0.03).name)
    hosts.append(le_box(K, 'junction_lid', tx - hw - 0.02, tx + hw + 0.02, jb['y'][0] - 0.02, jb['y'][1] + 0.02, jb['z'][1] - 0.04, jb['z'][1] + 0.03,
                        mats['yellow'], L_TERM, 0.02).name)
    hosts.append(le_box(K, 'junction_plate', tx - hw - 0.06, tx + hw + 0.06, jb['y'][0] - 0.05, rail_y, 0.0, 0.10, mats['dark'], L_SKID).name)
    for k, bx in enumerate((tx - hw + 0.07, tx + hw - 0.07)):
        b = bolt_dot(K, 'junction_bolt%d' % k, (bx, jb['y'][0] - 0.005, jb['z'][0] + 0.08), 'Y', 0.022, mats['bore']); b['part_label'] = L_TERM


def le_mounts2(K, mats, xs, x_end, hosts, z0=0.0, z1=0.22):
    """v5: base rails to x_end; at each engine station a rubber block under a foot that runs in under the pan."""
    for s in (-1, 1):
        y0, y1 = sorted((s * 0.50, s * 0.82))
        hosts.append(le_box(K, 'base_rail_%+d' % s, min(xs) - 0.40, x_end, y0, y1, z0, z0 + 0.10, mats['dark'], L_SKID).name)
    for k, x in enumerate(xs):
        for s in (-1, 1):
            y0, y1 = sorted((s * 0.56, s * 0.76))
            hosts.append(le_box(K, 'mount_rubber_%d_%+d' % (k, s), x - 0.14, x + 0.14, y0, y1, z0 + 0.10, z1 - 0.04, mats['dark'], L_SKID, 0.03).name)
            y0, y1 = sorted((s * 0.42, s * 0.80))
            hosts.append(le_box(K, 'mount_foot_%d_%+d' % (k, s), x - 0.18, x + 0.18, y0, y1, z1 - 0.06, z1 + 0.20, mats['slate'], L_BLOCK).name)


def le_mounts3(K, mats, stations, x_end, hosts, z_rail=0.10):
    """v6 (owner: "the legs have lost some detail and maybe need a small raise and thinning and reshaping into smaller
    supports"): base rails; at each station and side a small pad on the rail, a round rubber isolator, a flange plate
    with two bolts, a slim web up into the body above and a triangular gusset between them. stations: (x, top z of
    the web, y where the web meets the body)."""
    xs = [st[0] for st in stations]
    for s in (-1, 1):
        y0, y1 = sorted((s * 0.52, s * 0.80))
        hosts.append(le_box(K, 'base_rail_%+d' % s, min(xs) - 0.40, x_end, y0, y1, 0.0, z_rail, mats['dark'], L_SKID).name)
    for k, (x, ztop, yin) in enumerate(stations):
        for s in (-1, 1):
            yc = s * 0.66
            y0, y1 = sorted((yc - 0.11, yc + 0.11))
            hosts.append(le_box(K, 'mount_pad_%d_%+d' % (k, s), x - 0.13, x + 0.13, y0, y1, z_rail - 0.01, z_rail + 0.03, mats['dark'], L_SKID).name)
            hosts.append(le_cyl(K, 'mount_iso_%d_%+d' % (k, s), (x, yc, z_rail + 0.02), (x, yc, z_rail + 0.14), 0.08, mats['dark'], L_SKID, seg=32).name)
            zf = z_rail + 0.14
            y0, y1 = sorted((yc + s * 0.10, s * yin))
            hosts.append(le_box(K, 'mount_flange_%d_%+d' % (k, s), x - 0.12, x + 0.12, min(y0, yc - 0.10), max(y1, yc + 0.10), zf, zf + 0.04, mats['slate'], L_BLOCK).name)
            for q, bx in enumerate((x - 0.07, x + 0.07)):
                b = bolt_dot(K, 'mount_bolt_%d_%+d_%d' % (k, s, q), (bx, yc + s * 0.06, zf + 0.042), 'Z', 0.022, mats['bore']); b['part_label'] = L_BLOCK
            wy0, wy1 = sorted((s * (yin - 0.06), s * (yin + 0.02)))
            hosts.append(le_box(K, 'mount_web_%d_%+d' % (k, s), x - 0.035, x + 0.035, wy0, wy1, zf, ztop, mats['slate'], L_BLOCK).name)
            g = [(s * (yin - 0.02), zf + 0.04), (s * (yc + 0.06), zf + 0.04), (s * (yin - 0.02), zf + 0.04 + (ztop - zf) * 0.55)]
            n = len(g); vs = [(x - 0.03, y, z) for y, z in g] + [(x + 0.03, y, z) for y, z in g]
            fs = [tuple(reversed(range(n))), tuple(range(n, 2 * n))] + [(i, (i + 1) % n, n + (i + 1) % n, n + i) for i in range(n)]
            me = bpy.data.meshes.new('mount_gusset_%d_%+d' % (k, s)); me.from_pydata(vs, [], fs); me.update()
            bm = bmesh.new(); bm.from_mesh(me); bmesh.ops.recalc_face_normals(bm, faces=bm.faces); bm.to_mesh(me); bm.free()
            ob = K.obj(me.name, me, mats['slate'], False); noink(ob); ob['part_label'] = L_BLOCK; hosts.append(ob.name)


def le_hexa(K, name, bottom, top, mat, label):
    """A closed six-faced solid from a bottom and a top quad (each four (x, y, z) points, same winding)."""
    vs = [tuple(p) for p in bottom] + [tuple(p) for p in top]
    fs = [(3, 2, 1, 0), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]
    me = bpy.data.meshes.new(name); me.from_pydata(vs, [], fs); me.update()
    bm = bmesh.new(); bm.from_mesh(me); bmesh.ops.recalc_face_normals(bm, faces=bm.faces); bm.to_mesh(me); bm.free()
    ob = K.obj(name, me, mat, False); noink(ob); ob['part_label'] = label
    return ob


def le_mounts4(K, mats, stations, x_end, hosts, z_rail=0.10):
    """v9 (owner: "thicken the supports for the whole engine. Maybe a trapezoidal support that's narrower at the engine
    end/top and wide and thick connecting the black bars"): base rails; at each station and side a cast trapezoidal
    support, wide and thick on a bolted base flange across the rail, narrowing up into the body above.
    stations: (x, top z, y where the support meets the body)."""
    xs = [st[0] for st in stations]
    for s in (-1, 1):
        y0, y1 = sorted((s * 0.52, s * 0.80))
        hosts.append(le_box(K, 'base_rail_%+d' % s, min(xs) - 0.40, x_end, y0, y1, 0.0, z_rail, mats['dark'], L_SKID).name)
    for k, (x, ztop, yin) in enumerate(stations):
        for s in (-1, 1):
            y0, y1 = sorted((s * 0.50, s * 0.82))
            hosts.append(le_box(K, 'mount_flange_%d_%+d' % (k, s), x - 0.32, x + 0.32, y0, y1, z_rail - 0.01, z_rail + 0.05, mats['slate'], L_BLOCK).name)
            for q, bx in enumerate((x - 0.25, x + 0.25)):
                b = bolt_dot(K, 'mount_bolt_%d_%+d_%d' % (k, s, q), (bx, s * 0.66, z_rail + 0.052), 'Z', 0.026, mats['bore']); b['part_label'] = L_BLOCK
            zb = z_rail + 0.05
            ya, yb = s * 0.54, s * 0.78                  # bottom: across the rail, thick
            yc, yd = s * (yin - 0.04), s * (yin + 0.14)  # top: narrower, reaching in under the body
            bottom = [(x - 0.26, ya, zb), (x + 0.26, ya, zb), (x + 0.26, yb, zb), (x - 0.26, yb, zb)]
            top = [(x - 0.12, yc, ztop), (x + 0.12, yc, ztop), (x + 0.12, yd, ztop), (x - 0.12, yd, ztop)]
            hosts.append(le_hexa(K, 'mount_%d_%+d' % (k, s), bottom, top, mats['slate'], L_BLOCK).name)


def le_mounts5(K, mats, stations, x_end, hosts, z_rail=0.10):
    """v10 (owner: "two to three trapezoidal supports that go from rail to rail and looks like a trapeze from the
    front"): base rails, and across them cast cross supports, each a trapezoid seen from the front: wide where its feet
    are bolted to both rails, narrowing up to a saddle under the body. stations: (x, top z, top half width)."""
    xs = [st[0] for st in stations]
    for s in (-1, 1):
        y0, y1 = sorted((s * 0.52, s * 0.80))
        hosts.append(le_box(K, 'base_rail_%+d' % s, min(xs) - 0.40, x_end, y0, y1, 0.0, z_rail, mats['dark'], L_SKID).name)
    for k, (x, ztop, half) in enumerate(stations):
        zb = z_rail - 0.01; t = 0.17
        prof = [(-0.82, zb), (0.82, zb), (0.82, zb + 0.08), (half + 0.02, ztop), (-half - 0.02, ztop), (-0.82, zb + 0.08)]
        hosts.append(le_prism_x(K, 'cross_support_%d' % k, prof, x - t, x + t, mats['slate'], L_BLOCK).name)
        for s in (-1, 1):
            for q, bx in enumerate((x - t * 0.55, x + t * 0.55)):
                b = bolt_dot(K, 'support_bolt_%d_%+d_%d' % (k, s, q), (bx, s * 0.70, zb + 0.082), 'Z', 0.026, mats['bore']); b['part_label'] = L_BLOCK


def le_flywheel2(K, mats, x, z, R, hosts, depth=0.18):
    """v5: the shipped icon's flywheel, laid out as the owner asked ("a lip in the same layout as the old icon's - set
    out from the face with the holes in a circle"): a brass disc set out from the motor-generator, a raised lip round
    its face, a dark recess inside the lip, a raised hub plate with a circle of ten holes and a bored boss."""
    hosts.append(le_cyl(K, 'flywheel', (x - 0.02, 0, z), (x + depth, 0, z), R, mats['brass'], L_ALT_END, seg=96).name)
    hosts.append(le_ring(K, 'flywheel_lip', (x + depth + 0.05, 0, z), (1, 0, 0), R * 0.80, R, 0.10, mats['brass'], L_ALT_END, seg=96).name)
    hosts.append(le_ring(K, 'flywheel_recess', (x + depth + 0.005, 0, z), (1, 0, 0), R * 0.62, R * 0.80, 0.01, mats['dark'], L_ALT_END, seg=96).name)
    hosts.append(le_cyl(K, 'hub_plate', (x + depth - 0.01, 0, z), (x + depth + 0.06, 0, z), R * 0.62, mats['slate'], L_TERM, seg=96).name)
    for k in range(10):
        a = math.radians(36 * k)
        b = bolt_dot(K, 'flywheel_hole%d' % k, (x + depth + 0.065, R * 0.42 * math.cos(a), z + R * 0.42 * math.sin(a)), 'X', R * 0.05, mats['bore'])
        b['part_label'] = L_TERM
    hosts.append(le_cyl(K, 'flywheel_boss', (x + depth + 0.05, 0, z), (x + depth + 0.11, 0, z), R * 0.18, mats['slate'], L_TERM, seg=48).name)
    b = bolt_dot(K, 'flywheel_bore', (x + depth + 0.112, 0, z), 'X', R * 0.09, mats['bore']); b['part_label'] = L_TERM


def build_le_d2():
    """D2: the universal inline six with a motor-generator on its shaft (the hybrid and diesel-electric read) and the
    shipped icon's lipped flywheel at the output end. v5 folds in the review of v4: a short finned motor-generator with a
    yellow terminal box and its own pedestal, a thinner larger flywheel, legible air and exhaust paths, attached mounts."""
    setup_icon_rig(); K = Kit(open_collection('ICON_le_d2')); hosts = []
    mats = {k: pl_toon('le_' + k, *v) for k, v in TONES.items()}
    z0 = 0.32; zc = z0 + 0.80; mg = (1.30, 2.05); R_mg = 0.70
    # mounts: two under the pan (the web rises into the pan's flank), one under the motor-generator (into the drum)
    le_mounts5(K, mats, [(-0.62, z0 + 0.06, 0.40), (0.72, z0 + 0.06, 0.40), ((mg[0] + mg[1]) / 2, zc - R_mg * 0.84, 0.36)], 2.30, hosts)
    le_inline2(K, mats, -1.15, 1.10, z0, hosts)
    le_motor_gen2(K, mats, mg[0], mg[1], zc, R_mg, -0.66, hosts)

    le_flywheel2(K, mats, mg[1], zc, 0.80, hosts)
    return le_finish(K, hosts, 'universal heavy-duty inline six with turbocharger, a finned motor-generator on its shaft and a lipped output flywheel, on mounts')


def build_le_d3():
    """D3: D2 on resilient mounts with a length of output shaft and a coupling flange, suggesting propulsion."""
    setup_icon_rig(); K = Kit(open_collection('ICON_le_d3')); hosts = []
    mats = {k: pl_toon('le_' + k, *v) for k, v in TONES.items()}
    z0 = 0.22; le_mounts(K, mats, (-0.70, 0.75, 1.85), hosts, 0.0, z0)
    le_inline(K, mats, -1.15, 1.10, z0, hosts)
    le_motor_gen(K, mats, 1.30, 2.25, z0 + 0.80, 0.62, hosts)
    le_output(K, mats, 2.25, z0 + 0.80, hosts, shaft=0.55)
    return le_finish(K, hosts, 'universal heavy-duty inline diesel with a motor-generator, an output shaft and coupling flange, on resilient mounts')
