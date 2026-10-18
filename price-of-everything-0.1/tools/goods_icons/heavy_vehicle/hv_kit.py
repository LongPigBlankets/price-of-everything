"""Heavy vehicle (g_055 heavy_vehicle), after the shipped art: a blue cab-over tipper lorry in front of a green electric
locomotive, both running along the view's falling diagonal (world X) with their noses toward the viewer's right (+X).
The lorry is the car-body cab with a long open tipper on three axles. The locomotive is a 2010s Bo'Bo' electric in
real proportion: a taupe hood over each cab end, a three-face nose with a framed two-pane windscreen, long side grilles
and a builder's plate, a wide flat roof with folded pantographs, and two framed bogies. On the set's grid, camera,
light, 12/4 px ink and dots on the shaded sides."""
HV_REVISION = 'heavy_vehicle_v38'
COL = {'blue': ((32, 46, 96), (54, 74, 140), (84, 108, 176)), 'green': ((34, 70, 44), (52, 104, 64), (78, 134, 90)),
       'vent': ((22, 46, 30), (34, 68, 44), (52, 92, 62)),   # the side grilles, a shade under the body green
       'sky': ((92, 110, 120), (136, 156, 164), (178, 194, 198)),   # the loco's pale glass, as shipped
       'taupe': ((70, 66, 62), (104, 98, 90), (132, 124, 114)),   # the loco's warm grey-brown hood and roof
       'roof': ((82, 88, 96), (126, 132, 140), (160, 166, 172)), 'glass': ((26, 34, 48), (42, 54, 72), (70, 88, 112)),
       'dark': ((24, 26, 32), (40, 44, 52), (62, 66, 76)), 'tyre': ((20, 22, 26), (34, 36, 42), (54, 56, 62)),
       'hub': ((96, 100, 108), (150, 154, 162), (186, 190, 196)), 'steel': ((88, 94, 102), (136, 142, 150), (170, 176, 184)),
       'lamp': ((180, 160, 90), (236, 214, 130), (250, 236, 170)), 'lens': ((176, 182, 190), (224, 228, 234), (246, 248, 250)),
       'visor': ((44, 40, 40), (70, 62, 58), (96, 86, 78)), 'plate': ((200, 200, 196), (236, 236, 232), (250, 250, 248)), 'inside': ((22, 34, 76), (32, 48, 104), (44, 64, 132))}


def hv_cut(ob, cutter):
    """boolean difference, applied, keeping the material slots"""
    mod = ob.modifiers.new('cut', 'BOOLEAN'); mod.operation = 'DIFFERENCE'; mod.solver = 'EXACT'; mod.object = cutter
    bpy.context.view_layer.update()
    me = bpy.data.meshes.new_from_object(ob.evaluated_get(bpy.context.evaluated_depsgraph_get()))
    ob.modifiers.remove(mod); old = ob.data; ob.data = me; bpy.data.meshes.remove(old)
    bpy.data.objects.remove(cutter, do_unlink=True)
    return noink(ob)


def hv_wheel(K, name, x, y, r, w, m, label):
    tyre = noink(K.cyl(name, x, y, r, r, w, m['tyre'], axis='Y', segments=40)); tyre['part_label'] = label
    face = y - w / 2 - 0.004 if y < 0.5 else y - w / 2 - 0.004
    hub = noink(K.cyl(name + '_hub', x, face, r, r * 0.55, 0.01, m['hub'], axis='Y', segments=32)); hub['part_label'] = label
    return [tyre.name, hub.name]


# the lorry: the car-body cab (cb_cab) built at the origin in its own units and glazed, then the lorry built back from
# it (chassis, front wheels under its arch, two rear axles, a fuel tank, the tipper body), the whole scaled into the
# scene. The tipper rides above the tyres on tall rails, so the tyre tops stay out of its floor.
LORRY = dict(scale=0.43, at=(0.46, -1.30),   # close in: the cab just overlaps the loco's front bogie
             rail=(-6.86, 0.20, 0.55, 0.72, 1.20), tyre=(0.54, 0.44), axles=(-0.30, -4.35, -5.55),
             tipper=(-6.96, -1.18, 1.12, 1.22, 2.45, 0.06), tank=(-3.20, -1.45, 0.60, 1.02, 0.55, 0.95))


def hv_glass_slab(K, name, pts3, inward, mat, label, t=0.012):
    """a thin closed glass slab from a 3D outline and the direction into the cab"""
    n = len(pts3); vs = [tuple(p) for p in pts3] + [tuple(p + inward * t) for p in pts3]
    fs = [tuple(range(n)), tuple(reversed(range(n, 2 * n)))] + [(k, n + k, n + (k + 1) % n, (k + 1) % n) for k in range(n)]
    me = bpy.data.meshes.new(name); me.from_pydata(vs, [], fs); me.update()
    bm = bmesh.new(); bm.from_mesh(me); bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:]); bm.to_mesh(me); bm.free()
    o = K.obj(name, me, mat, False); noink(o); o['part_label'] = label
    return o


def hv_arc_guard(K, name, x, y0, y1, r_in, r_out, a0, a1, mat, label, n=24):
    """a wheel guard: a band of the arc a0..a1 (degrees, 0 = +X, 90 = up) round an axle at (x, axle z) between y0 and y1"""
    ring = []
    for k in range(n + 1):
        a = math.radians(a0 + (a1 - a0) * k / n); ring.append((math.cos(a), math.sin(a)))
    V = []
    for (c, s_) in ring:
        for r in (r_in, r_out):
            for y in (y0, y1):
                V.append((x + c * r, y, LORRY['tyre'][0] + s_ * r))
    F = []
    for k in range(n):
        b0, b1 = k * 4, (k + 1) * 4
        F += [(b0 + 0, b1 + 0, b1 + 1, b0 + 1), (b0 + 2, b0 + 3, b1 + 3, b1 + 2), (b0 + 0, b0 + 2, b1 + 2, b1 + 0), (b0 + 1, b1 + 1, b1 + 3, b0 + 3)]
    F += [(0, 1, 3, 2), (n * 4 + 0, n * 4 + 2, n * 4 + 3, n * 4 + 1)]
    me = bpy.data.meshes.new(name); me.from_pydata(V, [], F); me.update()
    bm = bmesh.new(); bm.from_mesh(me); bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:]); bm.to_mesh(me); bm.free()
    for p in me.polygons:
        p.use_smooth = True
    o = K.obj(name, me, mat, False); noink(o); o['part_label'] = label
    return o


def hv_lorry_details(K, m, hosts):
    """the shipped art's lorry details (the tipper's headboard and rims, the under-run bar, the wheel guards, the
    visor, wipers, mirror, headlamps, plate and grille), in the cab's units before the lorry is scaled"""
    C = CAB; Bm = C['bumper']; L_GUARD, L_MIRROR, L_TRIM = 16, 17, 18
    tx0, tx1, ty, tz0, tz1, tw = LORRY['tipper']
    # the trailer: a tall headboard, a thick top rim, a bottom rail band, an inset side panel
    hosts.append(alk_box(K, 'tipper_headboard', tx1 - 0.12, tx1, -ty, ty, tz1 - 0.05, tz1 + 0.55, m['blue'], 2).name)
    hosts.append(alk_box(K, 'tipper_headboard_cap', tx1 - 0.16, tx1 + 0.04, -ty - 0.03, ty + 0.03, tz1 + 0.55, tz1 + 0.63, m['blue'], 2).name)
    for nm, (a, b, c, d) in (('rim_near', (tx0 - 0.04, tx1 - 0.12, -ty - 0.05, -ty + tw)), ('rim_far', (tx0 - 0.04, tx1 - 0.12, ty - tw, ty + 0.05)),
                             ('rim_back', (tx0 - 0.05, tx0 + tw, -ty - 0.05, ty + 0.05))):
        hosts.append(alk_box(K, 'tipper_' + nm, a, b, c, d, tz1 - 0.02, tz1 + 0.10, m['blue'], 2).name)
    hosts.append(alk_box(K, 'tipper_rail_near', tx0 - 0.02, tx1, -ty - 0.04, -ty + 0.02, tz0, tz0 + 0.18, m['blue'], 2).name)
    tagged_line(K, 'tipper_panel', [(tx0 + 0.18, -ty - 0.006, tz0 + 0.30), (tx1 - 0.30, -ty - 0.006, tz0 + 0.30),
                                    (tx1 - 0.30, -ty - 0.006, tz1 - 0.20), (tx0 + 0.18, -ty - 0.006, tz1 - 0.20)], 2, PL_INNER, True)['ink_width'] = 0
    # the rear under-run bar on two brackets, out past the tipper's tail
    hosts.append(alk_box(K, 'underrun_bar', tx0 - 0.42, tx0 - 0.22, -ty + 0.08, ty - 0.08, 0.62, 0.80, m['dark'], L_TRIM).name)
    for sgn in (-1, 1):
        hosts.append(alk_box(K, 'underrun_bracket%+d' % sgn, tx0 - 0.24, LORRY['rail'][0] + 0.10, sgn * 0.45 - 0.07, sgn * 0.45 + 0.07, 0.70, 1.00, m['dark'], L_TRIM).name)
    # guards over the rear tandem: one band from in front of the first axle to behind the second
    r, w = LORRY['tyre']; a1x, a2x = LORRY['axles'][1], LORRY['axles'][2]
    for sgn in (-1, 1):
        y0, y1 = sorted((sgn * (C['hy'] - w - 0.03), sgn * (C['hy'] + 0.02)))
        hosts.append(hv_arc_guard(K, 'guard_front%+d' % sgn, a1x, y0, y1, r + 0.06, r + 0.14, 0, 180, m['blue'], L_GUARD).name)
        hosts.append(hv_arc_guard(K, 'guard_rear%+d' % sgn, a2x, y0, y1, r + 0.06, r + 0.14, 0, 180, m['blue'], L_GUARD).name)
        hosts.append(alk_box(K, 'guard_link%+d' % sgn, a2x + r + 0.06, a1x - r - 0.06, y0, y1, r + r + 0.06, r + r + 0.14, m['blue'], L_GUARD).name)
    # the windscreen: a dark sun visor over it and two wipers on the glass
    zt = 2.74; xv = cab_front_x(zt)
    hosts.append(alk_box(K, 'cab_visor', xv - 0.02, xv + 0.14, -0.98, 0.98, zt - 0.02, zt + 0.10, m['visor'], L_TRIM).name)
    for k, (ya, yb) in enumerate(((-0.62, -0.10), (0.10, 0.62))):
        pts = [(cab_front_x(z) - SKIN * 1.6 + 0.012, y, z) for y, z in ((ya, 1.84), (yb, 2.28))]
        tagged_line(K, 'cab_wiper%d' % k, pts, L_TRIM, 4, False)
    # the mirror on its arm at the near front corner
    hosts.append(alk_box(K, 'mirror_head', 0.80, 0.98, -C['hy'] - 0.50, -C['hy'] - 0.36, 1.72, 2.48, m['visor'], L_MIRROR).name)
    hosts.append(alk_box(K, 'mirror_arm', 0.84, 0.92, -C['hy'] - 0.38, -C['hy'] + 0.06, 2.36, 2.42, m['dark'], L_MIRROR).name)
    hosts.append(alk_box(K, 'mirror_arm_low', 0.84, 0.92, -C['hy'] - 0.38, -C['hy'] + 0.06, 1.80, 1.86, m['dark'], L_MIRROR).name)
    # headlamp lenses in the bumper pockets, a number plate, grille slats
    bx = Bm['x'][1] - Bm['pocket'] * 0.45
    for sgn in (-1, 1):
        q = [(bx, sgn * y, z) for y, z in C['lamp']]
        c = sum((Vector(v) for v in q), Vector()) / 4
        q = [Vector(v).lerp(c, 0.18) for v in q]
        if sgn < 0:
            q = q[::-1]
        hosts.append(hv_glass_slab(K, 'headlamp%+d' % sgn, q, Vector((-1, 0, 0)), m['lens'], L_TRIM).name)
    hosts.append(alk_box(K, 'number_plate', Bm['x'][1] - 0.01, Bm['x'][1] + 0.012, -0.24, 0.24, 0.38, 0.50, m['plate'], L_TRIM).name)
    for k, z in enumerate((1.24, 1.32, 1.40)):
        tagged_line(K, 'grille_slat%d' % k, [(cab_front_x(z) - SKIN * 2.4 + 0.012, y, z) for y in (-0.56, 0.56)], L_TRIM, 4, False)
    return hosts


def hv_lorry2(K, m, cbm):
    C = CAB; saved = (C['at'], C['scale']); C['at'], C['scale'] = (0.0, 0.0), 1.0
    before = set(o.name for o in K.col.objects)
    hosts = cb_cab(K, cbm)
    C['at'], C['scale'] = saved
    L_GLASS, L_CHASSIS, L_TIPPER, L_WHEEL, L_TANK = 8, 1, 2, 3, 9
    def rr(u0, u1, v0, v1, r):
        return cb_outline([(u0, v0), (u1, v0), (u1, v1), (u0, v1)], r)
    ins = SKIN * 1.6
    ws = [Vector((cab_front_x(z) - ins, y, z)) for y, z in rr(-.84, .84, 1.76, 2.68, .09)]
    hosts.append(hv_glass_slab(K, 'cab_windscreen', ws, Vector((-1, 0, 0)), m['glass'], L_GLASS).name)
    gr = [Vector((cab_front_x(z) - ins * 1.5, y, z)) for y, z in rr(-.64, .64, 1.18, 1.50, .12)]
    hosts.append(hv_glass_slab(K, 'cab_grille_plate', gr, Vector((-1, 0, 0)), m['dark'], L_GLASS).name)
    W = C['window']
    for sgn in (-1, 1):
        out = cb_outline([(W['rear'] + 0.02, W['bottom'] + 0.02), (cab_front_x(W['bottom']) - W['front_gap'] - 0.02, W['bottom'] + 0.02),
                          (cab_front_x(W['top']) - W['front_gap'] - 0.02, W['top'] - 0.02), (W['rear'] + 0.02, W['top'] - 0.02)], W['r'])
        pts = [Vector((x, sgn * (C['hy'] - ins), z)) for x, z in out]
        hosts.append(hv_glass_slab(K, 'cab_side_window%+d' % sgn, pts, Vector((0, -sgn, 0)), m['glass'], L_GLASS).name)
    x0, x1, y_, z0, z1 = LORRY['rail']
    hosts.append(alk_box(K, 'lorry_chassis', x0, x1, -y_, y_, z0, z1, m['dark'], L_CHASSIS).name)
    tx0, tx1, ty, tz0, tz1, tw = LORRY['tipper']
    body = alk_box(K, 'lorry_tipper', tx0, tx1, -ty, ty, tz0, tz1, m['blue'], L_TIPPER)
    hv_cut(body, K.box('tipper_cavity', (tx0 + tx1) / 2, 0, (tz0 + tw + tz1 + 1) / 2, tx1 - tx0 - 2 * tw, 2 * (ty - tw), tz1 + 1 - tz0 - tw))
    body.data.materials.clear(); body.data.materials.append(m['blue']); body.data.materials.append(m['inside'])
    for p in body.data.polygons:
        c = p.center
        p.material_index = 1 if (tx0 + tw * 0.5 < c.x < tx1 - tw * 0.5 and -ty + tw * 0.5 < c.y < ty - tw * 0.5 and c.z > tz0 + tw * 0.5) else 0
    body['part_label'] = L_TIPPER; hosts.append(body.name)
    a0, a1, b0, b1, c0, c1 = LORRY['tank']
    hosts.append(alk_box(K, 'lorry_tank', a0, a1, -b1, -b0, c0, c1, m['steel'], L_TANK).name)
    r, w = LORRY['tyre']
    for k, x in enumerate(LORRY['axles']):
        for sgn in (-1, 1):
            y = sgn * (C['hy'] - w / 2 - 0.01)
            tyre = noink(K.cyl('lorry_tyre%d%+d' % (k, sgn), x, y, r, r, w, m['tyre'], axis='Y', segments=48)); tyre['part_label'] = L_WHEEL; hosts.append(tyre.name)
            hub = noink(K.cyl('lorry_hub%d%+d' % (k, sgn), x, y + sgn * (w / 2 + 0.005), r, r * 0.56, 0.012, m['hub'], axis='Y', segments=40))
            hub['part_label'] = L_WHEEL; hosts.append(hub.name)
    hv_lorry_details(K, m, hosts)
    for k, x in enumerate(LORRY['axles']):             # the hubs' concentric rings, as shipped
        for sgn in (-1, 1):
            y = sgn * (C['hy'] - w / 2 - 0.01) + sgn * (w / 2 + 0.012)
            for j, (rf, mat) in enumerate(((0.36, m['dark']), (0.16, m['hub']))):
                d = noink(K.cyl('lorry_hubring%d%+d_%d' % (k, sgn, j), x, y + sgn * 0.006 * (j + 1), r, r * rf, 0.008, mat, axis='Y', segments=32))
                d['part_label'] = L_WHEEL; d.pass_index = 73
    # into the scene: every new mesh and every ink path scaled about the origin and moved
    M = Matrix.Translation((LORRY['at'][0], LORRY['at'][1], 0)) @ Matrix.Scale(LORRY['scale'], 4)
    for o in K.col.objects:
        if o.name in before:
            continue
        o.data.transform(M); o.data.update()
        if o.get('line_path'):
            fl = list(o['line_path']); q = []
            for i in range(0, len(fl), 3):
                q += list(M @ Vector(fl[i:i + 3]))
            o['line_path'] = q
    return hosts


# proportioned on a 2010s Bo'Bo' electric (Siemens Vectron: 18.98 m over buffers, 3.01 m wide, 4.25 m over the lowered
# pantograph; 3.0 m bogie wheelbase) at the body's width, 0.349 units a metre: 6.0 long, roof at 1.60
LOCO3 = dict(x=(-5.00, 1.00), y=(0.30, 1.35), z=(0.56, 1.60), cant=0.14,   # a tight shoulder: a wide flat top for the gear
             band=1.28, chamfer=0.26,
             lower=(15.0, 0.71), screen=(28.0, 0.97), cap=(60.0, 1.45), skirt=(0.42, 0.565),
             bogie_centres=3.57, bogie_len=1.57, wheel=0.22)   # bogie centres 55% of the length (TRAXX AC3), 1.05 between
                                                            # axles, 1.25 m wheels: Bo'Bo', as both are


def hv_loco_section3(P):
    """the body's section in (y, z): upright sides with a knuckle at the shoulder band, a rounded roof shoulder"""
    (y0, y1), (z0, z1), r, zb = P['y'], P['z'], P['cant'], P['band']
    pts = [(y0, z0), (y1, z0), (y1, zb), (y1, z1 - r)]
    for k in range(1, 9):
        a = math.radians(90 * k / 8); pts.append((y1 - r + r * math.cos(a), z1 - r + r * math.sin(a)))
    pts.append((y0 + r, z1))
    for k in range(1, 9):
        a = math.radians(90 + 90 * k / 8); pts.append((y0 + r + r * math.cos(a), z1 - r + r * math.sin(a)))
    pts.append((y0, zb))
    return pts


def hv_nose_planes(P, sgn, xe):
    """the nose's three tilted faces, front to top: (normal, point). Each leans back more than the one below, so the
    nose stays convex and each is one half-space cut"""
    yc = sum(P['y']) / 2; out = []
    (al, zl), (as_, zs), (ac, zc) = P['lower'], P['screen'], P['cap']
    xs = xe - sgn * (zs - zl) * math.tan(math.radians(al))
    xc = xs - sgn * (zc - zs) * math.tan(math.radians(as_))
    for a, x, z in ((al, xe, zl), (as_, xs, zs), (ac, xc, zc)):
        out.append((Vector((sgn * math.cos(math.radians(a)), 0, math.sin(math.radians(a)))), Vector((x, yc, z))))
    return out


def hv_on_plane(n, c, y, z):
    """the point on the plane (n, c) at this y, z"""
    return Vector((c.x - (n.z * (z - c.z) + n.y * (y - c.y)) / n.x, y, z))


def hv_rod(K, name, p, q, r, mat, label, segments=16):
    """a round tube from p to q (its mesh built in place, no object transform)"""
    p, q = Vector(p), Vector(q); d = q - p
    bm = bmesh.new(); bmesh.ops.create_cone(bm, cap_ends=True, segments=segments, radius1=r, radius2=r, depth=d.length)
    bmesh.ops.rotate(bm, cent=(0, 0, 0), matrix=Vector((0, 0, 1)).rotation_difference(d.normalized()).to_matrix(), verts=bm.verts)
    bmesh.ops.translate(bm, vec=(p + q) / 2, verts=bm.verts)
    me = bpy.data.meshes.new(name); bm.to_mesh(me); bm.free()
    ob = K.obj(name, me, mat, False); noink(ob); ob['part_label'] = label
    return ob


def hv_clip(poly, a, b, c):
    """Sutherland-Hodgman: keep the part of a 2D polygon where a*u + b*v + c >= 0"""
    out = []
    for k in range(len(poly)):
        p, q = poly[k], poly[(k + 1) % len(poly)]; fp, fq = a * p[0] + b * p[1] + c, a * q[0] + b * q[1] + c
        if fp >= 0:
            out.append(p)
        if (fp >= 0) != (fq >= 0):
            t = fp / (fp - fq); out.append((p[0] + (q[0] - p[0]) * t, p[1] + (q[1] - p[1]) * t))
    return out


def hv_inset(poly, d):
    """a convex 2D polygon inset by d: clipped by every edge's line moved inward (short edges just clip less)"""
    if sum(p[0] * q[1] - q[0] * p[1] for p, q in zip(poly, poly[1:] + poly[:1])) < 0:
        poly = poly[::-1]
    out = list(poly)
    for p, q in zip(poly, poly[1:] + poly[:1]):
        eu, ev = q[0] - p[0], q[1] - p[1]; L = math.hypot(eu, ev)
        if L < 1e-6:
            continue
        a, b = -ev / L, eu / L                         # the left (inward) normal of a CCW edge
        out = hv_clip(out, a, b, -(a * p[0] + b * p[1]) - d)
    return out


def hv_loco3(K, m, L0):
    """the shipped Vectron-like electric: a taupe hood over each cab end (roof, shoulder band, every nose face) over
    green machine-room sides; a convex nose of three tilted faces (the lower face, a steeper two-pane windscreen, a
    cap with the top lamp) between chamfered corners carrying two round lamps; a buffer beam with buffers, a coupler,
    hoses and a deflector down to rail level; pantographs as tubes; a rounded roof shoulder; vents and a builder's
    plate along the side; an angled skirt; detailed bogies"""
    # labels L0..L0+5 and L0+9..L0+14: the lorry holds 1..9 and 16..18
    P = LOCO3; hosts = []; (x0, x1), (y0, y1), (z0, z1) = P['x'], P['y'], P['z']; yc = (y0 + y1) / 2; ch = P['chamfer']
    sec = hv_loco_section3(P); n = len(sec)
    V = [(x0, y, z) for y, z in sec] + [(x1, y, z) for y, z in sec]
    F = [tuple(reversed(range(n))), tuple(range(n, 2 * n))] + [(k, (k + 1) % n, n + (k + 1) % n, n + k) for k in range(n)]
    bm = bmesh.new()
    for v in V:
        bm.verts.new(v)
    bm.verts.ensure_lookup_table()
    for f in F:
        bm.faces.new([bm.verts[k] for k in f])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])

    def cut(no, co):
        bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], plane_co=co, plane_no=no, clear_outer=True)
        bmesh.ops.holes_fill(bm, edges=[e for e in bm.edges if e.is_boundary], sides=0)
    for sgn, xe in ((1, x1), (-1, x0)):
        for no, co in hv_nose_planes(P, sgn, xe):
            cut(no, co)
        for ys, ny in ((y0, -1), (y1, 1)):
            cut(Vector((sgn * 0.8, ny * 0.6, 0)).normalized(), Vector((xe - sgn * ch, ys, 0)))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    for f in bm.faces:                                 # the taupe hood: the shoulder band and roof, and every end face
        c = f.calc_center_median(); nrm = f.normal
        f.material_index = 1 if (c.z > P['band'] + 0.01 or abs(nrm.x) > 0.3) else 0
    me = bpy.data.meshes.new('loco_body'); bm.to_mesh(me); bm.free()
    body = K.obj('loco_body', me, m['green'], False); body.data.materials.append(m['taupe']); noink(body); body['part_label'] = L0
    for p in body.data.polygons:
        p.use_smooth = False
    hosts.append(body.name); bpy.context.view_layer.update()
    for sgn, xe in ((1, x1), (-1, x0)):
        (nl, cl), (ns, cs), (nc, cc) = hv_nose_planes(P, sgn, xe)
        # the windscreen: two panes either side of a centre pillar
        face = max((p for p in body.data.polygons if p.normal.dot(ns) > 0.98), key=lambda p: p.area)
        pts = [body.data.vertices[i].co.copy() for i in face.vertices]; c = sum(pts, Vector()) / len(pts)
        ua = Vector((0, 1, 0)); va = ns.cross(ua).normalized()
        if va.z < 0:
            va = -va
        # the panes follow the screen face's own outline (wider at the top, where the chamfers fall back), inset
        # from it, in a dark frame; the pillar between them is the frame showing through
        poly = [((q - c).dot(ua), (q - c).dot(va)) for q in pts]
        frame = hv_inset(poly, 0.025); lite = hv_inset(poly, 0.06)
        us = [p[0] for p in lite]; vs_ = [p[1] for p in lite]
        u0, u1, v0, v1 = min(us), max(us), min(vs_), max(vs_); um = (u0 + u1) / 2
        hosts.append(hv_glass_slab(K, 'loco_screenframe%+d' % sgn, [c + ua * u + va * v + ns * 0.004 for u, v in frame], -ns, m['dark'], 25).name)
        for k, half in enumerate((hv_clip(lite, -1, 0, um - 0.03), hv_clip(lite, 1, 0, -um - 0.03))):
            glass = [c + ua * u + va * v + ns * 0.010 for u, v in half]
            hosts.append(hv_glass_slab(K, 'loco_windscreen%+d_%d' % (sgn, k), glass, -ns, m['sky'], L0 + 5).name)
        gc = c + ua * um + va * (v0 + v1) / 2; hv_ = (v1 - v0) / 2
        for k, du in enumerate((-(um - u0) / 2, (u1 - um) / 2)):   # a wiper parked at the foot of each pane
            a = gc + ua * (du - 0.10) - va * hv_ * 0.80; b = gc + ua * (du + 0.04) + va * hv_ * 0.55
            tagged_line(K, 'loco_wiper%+d_%d' % (sgn, k), [tuple(a + ns * 0.035), tuple(b + ns * 0.035)], L0 + 5, 3, False)
        # the top lamp in the cap
        lc = hv_on_plane(nc, cc, yc, cc.z + 0.05)
        lamp = [lc + ua * u + (nc.cross(ua).normalized() * (1 if nc.cross(ua).z > 0 else -1)) * v + nc * 0.006
                for u, v in rect_points(0, 0, 0.16, 0.08, 0.03, 4)]
        hosts.append(hv_glass_slab(K, 'loco_toplamp%+d' % sgn, lamp, -nc, m['lamp'], L0 + 5).name)
        # the radiators: a narrow flush grille down each corner of the lower face, its outer edge running with the
        # corner chamfer's edge (the face widens as it leans back), so it reads as part of the nose
        zl0, zl1 = cl.z + 0.03, cs.z - 0.04; tl = math.tan(math.radians(P['lower'][0]))
        def edge(z, ny):                                 # the lower face's corner edge at height z, on the -Y or +Y side
            dd = max(0.0, z - cl.z) * tl
            return y0 + 1.3333 * (ch - dd) if ny < 0 else y1 - 1.3333 * (ch - dd)
        for k, ny in enumerate((-1, 1)):
            w0, w1 = 0.035, 0.145
            quad = [(edge(z, ny) - ny * w, z) for z, w in ((zl0, w0), (zl0, w1), (zl1, w1), (zl1, w0))]
            panel = [hv_on_plane(nl, cl, y, z) + nl * 0.004 for y, z in quad]
            hosts.append(hv_glass_slab(K, 'loco_louvre%+d_%d' % (sgn, k), panel, -nl, m['green'], L0 + 9, t=0.008).name)
            for j in range(5):
                z = zl0 + (zl1 - zl0) * (j + 1) / 6
                tagged_line(K, 'loco_slat%+d_%d_%d' % (sgn, k, j), [tuple(hv_on_plane(nl, cl, edge(z, ny) - ny * (w0 + 0.015), z) + nl * 0.012),
                                                                    tuple(hv_on_plane(nl, cl, edge(z, ny) - ny * (w1 - 0.015), z) + nl * 0.012)], L0 + 9, 2, False)
        # two round lamps in a dark housing on the near corner chamfer, the housing's top leaning out, away from the
        # radiator (the far corner faces away, and its leaning housing poked past the nose's outline)
        for ys, ny in ((y0, -1),):
            cn = Vector((sgn * 0.8, ny * 0.6, 0)).normalized(); tu = Vector((cn.y, -cn.x, 0))
            tf = tu if tu.x * sgn > 0 else -tu           # along the chamfer towards the nose front
            a = math.radians(-16); up = Vector((0, 0, 1)) * math.cos(a) + tf * math.sin(a); ac = tf * math.cos(a) - Vector((0, 0, 1)) * math.sin(a)
            dd = max(0.0, 0.84 - cl.z) * math.tan(math.radians(P['lower'][0]))
            hc = Vector(((xe - sgn * ch + xe - sgn * dd) / 2, ys - ny * 0.6667 * (ch - dd), 0.84)) - tf * 0.02 + cn * 0.003
            house = [hc + ac * u + up * v for u, v in rect_points(0, 0, 0.2125, 0.375, 0.09, 6)]
            hosts.append(hv_glass_slab(K, 'loco_lamphouse%+d_%d' % (sgn, ny), house, -cn, m['dark'], 26, t=0.008).name)
            for k, (v, r) in enumerate(((-0.090, 0.074), (0.095, 0.060))):
                lc = hc + up * v + cn * 0.004
                disc = [lc + ac * r * math.cos(math.radians(t)) + up * r * math.sin(math.radians(t)) for t in range(0, 360, 20)]
                hosts.append(hv_glass_slab(K, 'loco_lamp%+d_%d%d' % (sgn, ny, k), disc, -cn, m['lamp'], L0 + 5, t=0.006).name)
        # the buffer beam, buffers, coupler, hoses and the deflector down to rail level
        xa, xb = min(xe - sgn * 0.08, xe + sgn * 0.04), max(xe - sgn * 0.08, xe + sgn * 0.04); xbf = xe + sgn * 0.04
        hosts.append(alk_box(K, 'loco_beam%+d' % sgn, xa, xb, y0 + 0.03, y1 - 0.03, 0.42, 0.58, m['taupe'], L0 + 10).name)
        for k, yy in enumerate((y0 + 0.17, y1 - 0.17)):   # buffers: long stocks, big round heads, as shipped
            b = noink(K.cyl('loco_buffer%+d_%d' % (sgn, k), xbf + sgn * 0.08, yy, 0.50, 0.060, 0.16, m['steel'], axis='X', segments=24)); b['part_label'] = L0 + 11; hosts.append(b.name)
            h = noink(K.cyl('loco_bufhead%+d_%d' % (sgn, k), xbf + sgn * 0.175, yy, 0.50, 0.115, 0.035, m['steel'], axis='X', segments=28)); h['part_label'] = L0 + 11; hosts.append(h.name)
        hosts.append(alk_box(K, 'loco_coupler%+d' % sgn, min(xbf, xbf + sgn * 0.14), max(xbf, xbf + sgn * 0.14), yc - 0.06, yc + 0.06, 0.44, 0.54, m['dark'], L0 + 12).name)
        hosts.append(alk_box(K, 'loco_hook%+d' % sgn, min(xbf + sgn * 0.12, xbf + sgn * 0.17), max(xbf + sgn * 0.12, xbf + sgn * 0.17), yc - 0.035, yc + 0.035, 0.40, 0.56, m['dark'], L0 + 12).name)
        for k, yy in enumerate((yc - 0.20, yc + 0.20)):
            tagged_line(K, 'loco_hose%+d_%d' % (sgn, k), [(xbf + sgn * 0.005, yy, 0.56), (xbf + sgn * 0.05, yy, 0.50), (xbf + sgn * 0.03, yy - 0.02, 0.42)], L0 + 12, 3, False)
        dx0, dx1 = min(xe - sgn * 0.14, xe + sgn * 0.02), max(xe - sgn * 0.14, xe + sgn * 0.02)
        hosts.append(alk_box(K, 'loco_deflector%+d' % sgn, dx0, dx1, y0 + 0.12, y1 - 0.12, 0.16, 0.42, m['roof'], L0 + 12).name)
    # the roof, all of it on the flat top (x0+0.69..x1-0.69, yc +- 0.245) and centred across it: two pantographs
    # folded down low on insulators near the ends, a main breaker on its box inboard of each, a conductor bar between
    # the breakers, a raised hatch with two fan grilles in the middle
    rf = P['y'][1] - yc - P['cant']                    # the flat top's half width
    def insulator(name, x, y, z0_, h, r=0.026):
        ob = noink(K.cyl(name, x, y, z0_ + h / 2, r, h, m['lamp'], axis='Z', segments=16)); ob['part_label'] = 28; hosts.append(ob.name)
        for q in range(2):                             # the sheds
            z = z0_ + h * (0.35 + 0.35 * q)
            tagged_line(K, name + '_shed%d' % q, [(x - r * 1.3, y - 0.001, z), (x + r * 1.3, y - 0.001, z)], 28, 2, False)
    hx0, hx1 = (x0 + x1) / 2 - 0.75, (x0 + x1) / 2 + 0.75
    hosts.append(alk_box(K, 'loco_hatch', hx0, hx1, yc - rf * 0.85, yc + rf * 0.85, z1 - 0.01, z1 + 0.09, m['taupe'], L0 + 1).name)
    for k, fx in enumerate(((hx0 + hx1) / 2 - 0.46, (hx0 + hx1) / 2, (hx0 + hx1) / 2 + 0.46)):
        fan = noink(K.cyl('loco_fan%d' % k, fx, yc, z1 + 0.095, 0.175, 0.012, m['dark'], axis='Z', segments=32)); fan['part_label'] = 27; hosts.append(fan.name)
        for q in range(3):                             # the fan guard's bars
            a = math.radians(30 + 60 * q)
            tagged_line(K, 'loco_fanbar%d_%d' % (k, q), [(fx - 0.155 * math.cos(a), yc - 0.155 * math.sin(a), z1 + 0.105),
                                                         (fx + 0.155 * math.cos(a), yc + 0.155 * math.sin(a), z1 + 0.105)], 27, 2, False)
    PT = 28; tube = m['steel']
    for k, (px, d) in enumerate(((x0 + 1.05, 1), (x1 - 1.05, -1))):
        zb = z1 + 0.08                                 # the base frame, up on four insulators
        for q, (ix, iy) in enumerate(((-0.17, -0.20), (0.17, -0.20), (-0.17, 0.20), (0.17, 0.20))):
            insulator('loco_panto%d_ins%d' % (k, q), px + ix, yc + iy, z1, 0.08)
        # the pantograph as real tubes (its own label, thin outer line, so it reads as grey tubes and not as
        # outline), folded down so it stays over the roof: base frame, a two-tube lower arm with braces and a push
        # rod, a knee bar, the upper arm folded back over it, the collector head with horns
        hosts.append(alk_box(K, 'loco_panto_base%d' % k, px - 0.23, px + 0.23, yc - 0.25, yc + 0.25, zb, zb + 0.03, m['roof'], PT).name)
        hosts.append(alk_box(K, 'loco_panto_drive%d' % k, px - d * 0.18 - 0.05, px - d * 0.18 + 0.05, yc - 0.05, yc + 0.05, zb + 0.03, zb + 0.08, m['dark'], PT).name)
        foot, knee, head = (px - d * 0.18, zb + 0.05), (px + d * 0.40, zb + 0.14), (px - d * 0.14, zb + 0.22)
        for j, dy in enumerate((-0.19, 0.19)):
            hosts.append(hv_rod(K, 'loco_panto%d_low%d' % (k, j), (foot[0], yc + dy, foot[1]), (knee[0], yc + dy, knee[1]), 0.024, tube, PT).name)
            hosts.append(hv_rod(K, 'loco_panto%d_up%d' % (k, j), (knee[0], yc + dy, knee[1]), (head[0], yc + dy * 0.45, head[1]), 0.020, tube, PT).name)
        hosts.append(hv_rod(K, 'loco_panto%d_rod' % k, (foot[0] + d * 0.06, yc, foot[1] + 0.02), (knee[0] - d * 0.04, yc, knee[1] - 0.01), 0.015, tube, PT).name)
        for j, t in enumerate((0.30, 0.65)):            # the lower arm's cross tubes
            mx, mz = foot[0] + (knee[0] - foot[0]) * t, foot[1] + (knee[1] - foot[1]) * t
            hosts.append(hv_rod(K, 'loco_panto%d_brace%d' % (k, j), (mx, yc - 0.19, mz), (mx, yc + 0.19, mz), 0.017, tube, PT).name)
        hosts.append(hv_rod(K, 'loco_panto%d_knee' % k, (knee[0], yc - 0.22, knee[1]), (knee[0], yc + 0.22, knee[1]), 0.022, m['roof'], PT).name)
        hosts.append(alk_box(K, 'loco_panto_head%d' % k, head[0] - 0.045, head[0] + 0.045, yc - 0.28, yc + 0.28, head[1], head[1] + 0.04, tube, PT).name)
        for e in (-1, 1):                              # the collector's horns, inside the flat top
            a_, b_, c_ = (head[0], yc + e * 0.27, head[1] + 0.02), (head[0], yc + e * 0.32, head[1] + 0.01), (head[0], yc + e * 0.35, head[1] - 0.04)
            hosts.append(hv_rod(K, 'loco_panto%d_horn%+da' % (k, e), a_, b_, 0.016, tube, PT).name)
            hosts.append(hv_rod(K, 'loco_panto%d_horn%+db' % (k, e), b_, c_, 0.016, tube, PT).name)
        bx = px + d * 0.72                             # the main breaker on its box, inboard of the pantograph
        hosts.append(alk_box(K, 'loco_roofbox%d' % k, bx - 0.18, bx + 0.18, yc - rf * 0.80, yc + rf * 0.80, z1 - 0.01, z1 + 0.11, m['roof'], L0 + 1).name)
        for q, (ix, iy) in enumerate(((-0.08, -0.14), (0.08, -0.14), (-0.08, 0.14), (0.08, 0.14))):
            insulator('loco_breaker%d_ins%d' % (k, q), bx + ix, yc + iy, z1 + 0.11, 0.09, 0.024)
    tagged_line(K, 'loco_roofbar', [(x0 + 1.05 + 0.72 + 0.08, yc, z1 + 0.20), (x1 - 1.05 - 0.72 - 0.08, yc, z1 + 0.20)], L0 + 1, 3, False)
    # the sides: small windows in the taupe band, a cab door with its window behind each nose
    for k, xa in enumerate((x0 + 1.30, x1 - 1.62)):
        hosts.append(alk_box(K, 'loco_window%d' % k, xa, xa + 0.30, y0 - 0.006, y0 + 0.012, 1.31, 1.37, m['sky'], L0).name)
    for k, xd in enumerate((x1 - ch - 0.42, x0 + ch + 0.18)):
        # a tall door with rounded corners, its window high up, a handle, a grab rail beside it, a step under it
        cx = xd + 0.12
        tagged_line(K, 'loco_door%d' % k, [(x, y0 - 0.008, z) for x, z in rect_points(cx, 0.92, 0.24, 0.62, 0.05, 4)], L0, 4, True)
        win = [Vector((x, y0 - 0.010, z)) for x, z in rect_points(cx, 1.10, 0.15, 0.18, 0.04, 4)]
        hosts.append(hv_glass_slab(K, 'loco_door_window%d' % k, win, Vector((0, 1, 0)), m['sky'], L0 + 5, t=0.008).name)
        tagged_line(K, 'loco_door_handle%d' % k, [(xd + 0.17, y0 - 0.012, 0.86), (xd + 0.21, y0 - 0.012, 0.86)], L0, 4, False)
        tagged_line(K, 'loco_grab%d' % k, [(xd - 0.06, y0 - 0.012, 0.68), (xd - 0.06, y0 - 0.012, 1.12)], L0, 4, False)
        hosts.append(alk_box(K, 'loco_step%d' % k, xd + 0.02, xd + 0.22, y0 - 0.07, y0 + 0.04, 0.40, 0.44, m['dark'], L0 + 3).name)
    # the skirt band, equipment between the bogies, framed bogies
    sk0, sk1 = P['skirt']
    # two long continuous side grilles along the machine room, either side of the builder's plate (four screws, three
    # pointed-top hexes, one over two)
    pc = ((x0 + x1) / 2, 1.03); pw, ph = 0.42, 0.30; plate_x = (pc[0] - pw / 2, pc[0] + pw / 2)
    for k, (va_, vb_) in enumerate(((x0 + ch + 0.50, plate_x[0] - 0.09), (plate_x[1] + 0.09, x1 - ch - 0.74))):
        vz0, vz1 = 0.83, 1.23
        vent = [Vector((x, y0 - 0.005, z)) for x, z in rect_points((va_ + vb_) / 2, (vz0 + vz1) / 2, vb_ - va_, vz1 - vz0, 0.03, 3)]
        hosts.append(hv_glass_slab(K, 'loco_vent%d' % k, vent, Vector((0, 1, 0)), m['vent'], 30, t=0.006).name)
        for q in range(8):
            z = vz0 + (vz1 - vz0) * (q + 1) / 9
            tagged_line(K, 'loco_vent%d_slat%d' % (k, q), [(va_ + 0.03, y0 - 0.008, z), (vb_ - 0.03, y0 - 0.008, z)], 30, 2, False)
    plate = [Vector((x, y0 - 0.006, z)) for x, z in rect_points(pc[0], pc[1], pw, ph, 0.02, 3)]
    hosts.append(hv_glass_slab(K, 'loco_plate', plate, Vector((0, 1, 0)), m['steel'], 31, t=0.006).name)
    for q, (sx, sz) in enumerate(((-1, -1), (1, -1), (1, 1), (-1, 1))):
        x, z = pc[0] + sx * (pw / 2 - 0.035), pc[1] + sz * (ph / 2 - 0.035)
        dot = [Vector((x + 0.014 * math.cos(math.radians(a)), y0 - 0.010, z + 0.014 * math.sin(math.radians(a)))) for a in range(0, 360, 45)]
        hosts.append(hv_glass_slab(K, 'loco_screw%d' % q, dot, Vector((0, 1, 0)), m['dark'], 27, t=0.004).name)
    r = 0.052; dx = r * math.sqrt(3) / 2 + 0.006
    for q, (hx, hz) in enumerate(((0, 0.044), (-dx, -0.037), (dx, -0.037))):   # one over two
        hexa = [Vector((pc[0] + hx + r * math.cos(math.radians(90 + 60 * t)), y0 - 0.010, pc[1] + hz + r * math.sin(math.radians(90 + 60 * t)))) for t in range(6)]
        hosts.append(hv_glass_slab(K, 'loco_hex%d' % q, hexa, Vector((0, 1, 0)), m['green'], 27, t=0.004).name)
    # the skirt: angled ends (shorter along the bottom) and sides that tuck in towards the bottom, as shipped
    sv = [(x0 + 0.04, y0, sk1), (x1 - 0.04, y0, sk1), (x1 - 0.04, y1, sk1), (x0 + 0.04, y1, sk1),
          (x0 + 0.36, y0 + 0.08, sk0), (x1 - 0.36, y0 + 0.08, sk0), (x1 - 0.36, y1 - 0.08, sk0), (x0 + 0.36, y1 - 0.08, sk0)]
    sf = [(0, 1, 2, 3), (7, 6, 5, 4), (0, 4, 5, 1), (1, 5, 6, 2), (2, 6, 7, 3), (3, 7, 4, 0)]
    skirt = mesh(K, 'loco_skirt', sv, sf, m['taupe'], False); noink(skirt); skirt['part_label'] = L0 + 2
    bm = bmesh.new(); bm.from_mesh(skirt.data); bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:]); bm.to_mesh(skirt.data); bm.free()
    hosts.append(skirt.name)
    xm, bc, bl = (x0 + x1) / 2, P['bogie_centres'] / 2, P['bogie_len'] / 2
    g0, g1 = xm - bc + bl + 0.05, xm + bc - bl - 0.05  # the gap between the bogies: a tank and an equipment box
    hosts.append(alk_box(K, 'loco_tank', g0, g0 + 0.80, y0 + 0.10, y1 - 0.10, 0.16, sk0 + 0.01, m['dark'], L0 + 3).name)
    hosts.append(alk_box(K, 'loco_eqbox', g0 + 0.88, g1, y0 + 0.06, y1 - 0.06, 0.20, sk0 + 0.01, m['roof'], L0 + 13).name)
    tagged_line(K, 'loco_eqbox_seam', [((g0 + 0.88 + g1) / 2, y0 + 0.052, 0.21), ((g0 + 0.88 + g1) / 2, y0 + 0.052, sk0)], L0 + 13, 3, False)
    wr = P['wheel']; yw = y0 + 0.10                   # the wheels' radius; their plane, inside the frame
    for k, (xa, xb) in enumerate(((xm + bc - bl, xm + bc + bl), (xm - bc - bl, xm - bc + bl))):
        # a framed bogie (Bo'Bo': two axles): the frame over the axles, an axlebox on each axle's end under
        # a spring nest, the brake rod along the middle, sandboxes at the ends; the wheels' light webs show
        hosts.append(alk_box(K, 'loco_bogie%d' % k, xa, xb, y0 + 0.10, y1 - 0.10, 0.26, sk0 + 0.02, m['dark'], L0 + 3).name)
        for j, x in enumerate((xa + 0.26, xb - 0.26)):
            hosts += hv_wheel(K, 'loco_wheel%d%d' % (k, j), x, yw, wr, 0.12, m, L0 + 4)
            web = noink(K.cyl('loco_web%d%d' % (k, j), x, yw - 0.068, wr, wr * 0.80, 0.006, m['hub'], axis='Y', segments=36)); web['part_label'] = L0 + 4; hosts.append(web.name)
        hosts.append(alk_box(K, 'loco_sideframe%d' % k, xa + 0.02, xb - 0.02, y0 - 0.02, y0 + 0.02, 0.31, 0.39, m['dark'], L0 + 14).name)
        for j, x in enumerate((xa + 0.26, xb - 0.26)):
            hosts.append(alk_box(K, 'loco_axlebox%d%d' % (k, j), x - 0.045, x + 0.045, y0 - 0.04, y0 + 0.02, wr - 0.045, wr + 0.045, m['dark'], 27).name)
            hosts.append(alk_box(K, 'loco_spring%d%d' % (k, j), x - 0.04, x + 0.04, y0 - 0.035, y0 + 0.01, wr + 0.045, 0.31, m['roof'], 29).name)   # the spring nest up to the frame
        tagged_line(K, 'loco_brakerod%d' % k, [((xa + xb) / 2 - 0.30, y0 - 0.05, 0.25), ((xa + xb) / 2 + 0.30, y0 - 0.05, 0.25)], 27, 2, False)
        for j, sx in enumerate((xa + 0.07, xb - 0.07)):   # the sandboxes, at the frame's ends
            hosts.append(alk_box(K, 'loco_sandbox%d%d' % (k, j), sx - 0.05, sx + 0.05, y0 - 0.01, y0 + 0.07, 0.27, 0.38, m['dark'], 27).name)
    return hosts


def build_heavy_vehicle():
    setup_icon_rig(); K = Kit(open_collection('ICON_heavy_vehicle')); hosts = []
    m = {k: pl_toon('hv_' + k, *v) for k, v in COL.items()}
    hosts += hv_loco3(K, m, 10)
    cbm = {k: pl_toon('cb_' + k, *v) for k, v in TONES.items()}
    cbm['cab'] = m['blue']                             # one royal blue for the whole lorry, as shipped
    hosts += hv_lorry2(K, m, cbm)
    for ob in K.col.objects:
        if ob.type == 'MESH' and not ob.get('edge_ink'):
            me = ob.data; at = me.attributes.get('icon_shade_occlusion') or me.attributes.new('icon_shade_occlusion', 'FLOAT', 'CORNER')
            for p in me.polygons:
                for li in p.loop_indices:
                    at.data[li].value = 0.30 if p.normal.dot(Vector((0.06, -0.56, 0.83)).normalized()) < 0.62 else 0.0
    bpy.context.view_layer.update()
    for n in ('loco_body', 'loco_skirt', 'cab_shell', 'cab_deflector', 'cab_bumper'):   # loco_body: its facet edges between shoulder steps ink
        pl_mesh_lines(K, bpy.data.objects[n], bpy.data.objects[n]['part_label'], 35.0, n, 0.05)
    for ob in K.col.objects:
        if ob.get('ink_width') == 6:
            ob['ink_width'] = PL_INNER
        if ob.name.startswith('loco_body_line') and max(list(ob['line_path'])[0::3]) > LOCO3['x'][1] - 0.75:
            ob['ink_width'] = 3                        # the nose's facet lines, thinner
    info = contract(K, hosts, 'heavy vehicle: a blue cab-over tipper lorry in front of a green electric locomotive', inner=PL_INNER)
    info['revision'] = HV_REVISION; info['outline']['component_boundaries'] = True; info['outline']['id_step'] = 8
    info['outline']['min_fragment_px'] = 24
    # the loco's front and its small parts in thinner lines (body 10, nose details 15, radiators 19, beam 20, buffers 21,
    # coupler 22, screen frame 25, lamp housings 26)
    # the pantographs and insulators (28), the bogies (13 frames, 14 wheels, 24 side frames, 27 small parts, 29 steel bits):
    # thin outer lines
    info['outline']['outer_by_label'] = {'28': 4, '29': 5, '13': 6, '14': 6, '24': 6, '27': 5}
    info['outline']['component_weight_by_label'] = {'10': 3, '15': 2.5, '19': 2.5, '20': 3, '21': 3, '22': 3, '25': 2.5, '26': 2.5,
                                                    '27': 2, '28': 2, '29': 2, '30': 2.5, '31': 2.5, '13': 2, '14': 2, '24': 2}
    info['stipple']['strength'] = 0.34
    info['stipple']['groups'] = [{'name': 'shaded_faces', 'labels': list(range(1, 32)), 'thresholds': [0.575, 0.50, 0.30]}]
    info['structural_hosts'] = ['loco_body']
    return info
