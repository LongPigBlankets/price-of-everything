"""CPU (g_041 cpu): the shipped art's copper socket tray with a CPU seated in it (a silver heat spreader on a green
board), and a second CPU standing on its edge against the tray's right side, its underside to the viewer: a green
board with a grid of gold pads round a gold centre square, corner marks and edge notches. On the set's grid, camera,
light, 12/4 px ink and dots on the shaded sides."""
CPU_REVISION = 'cpu_v5'
TRAY = dict(L=2.0, base=0.22, top=0.44, inset=0.03, ring=0.24, floor=0.36, pocket=1.22, pocket_z=0.28, r=0.12, lug=0.58, lug_h=0.12, rim_r=0.30, arm=0.30, notch=0.08)
CHIP = dict(size=1.32, t=0.05, lean=40.0, y0=-0.60)
TONES = {
    'tray': ((146, 88, 60), (176, 110, 70), (208, 140, 86)),   # v2: deeper copper, as shipped
    'ihs': ((136, 146, 148), (164, 174, 176), (190, 198, 199)),
    'board': ((88, 102, 76), (108, 124, 94), (124, 140, 108)),
    'edge': ((150, 120, 64), (184, 150, 80), (206, 172, 96)),
    'gold': ((200, 164, 84), (227, 188, 100), (236, 200, 116)),
    'glint': ((238, 242, 242), (242, 246, 246), (248, 250, 250))}


def cpu_rbox(K, name, x0, x1, y0, y1, z0, z1, mat, label, r=0.0, seg=4):
    """A box whose vertical edges are rounded by r"""
    bm = bmesh.new(); bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co = Vector((x0 if v.co.x < 0 else x1, y0 if v.co.y < 0 else y1, z0 if v.co.z < 0 else z1))
    if r > 0:
        es = [e for e in bm.edges if abs(e.verts[0].co.z - e.verts[1].co.z) > 1e-6]
        bmesh.ops.bevel(bm, geom=es, offset=r, segments=seg, affect='EDGES', profile=0.5)
    me = bpy.data.meshes.new(name); bm.to_mesh(me); bm.free()
    o = K.obj(name, me, mat, False); noink(o); o['part_label'] = label
    return o


def cpu_tris(o):
    """Triangulate a mesh's n-gons: the exporter's visibility test fans each polygon from its first vertex, which
    leaves gaps in a concave face (a notched board, an L-shaped lug) and lets the lines behind it show through"""
    bm = bmesh.new(); bm.from_mesh(o.data)
    bmesh.ops.triangulate(bm, faces=[f for f in bm.faces if len(f.verts) > 4])
    bm.to_mesh(o.data); bm.free(); o.data.update()
    return o


def cpu_clear(o):
    at = o.data.attributes.get('icon_stipple_clear') or o.data.attributes.new('icon_stipple_clear', 'FLOAT', 'CORNER')
    for d_ in at.data:
        d_.value = 1.0


def cpu_tray(K, mat, label):
    T = TRAY; h = T['L'] / 2; i = h - T['inset']; hosts = []
    base = cpu_rbox(K, 'tray_base', -h, h, -h, h, 0.0, T['base'], mat, label, T['r'])
    upper = cpu_rbox(K, 'tray_upper', -i, i, -i, i, T['base'], T['top'], mat, label, T['r'] - T['inset'])
    w = i - T['ring']; p = T['pocket'] / 2
    cutters = [cpu_rbox(K, 'cut_well', -w, w, -w, w, T['floor'], T['top'] + 1, None, 0, 0.06),
               cpu_rbox(K, 'cut_pocket', -p, p, -p, p, T['pocket_z'], T['top'] + 1, None, 0, 0.04)]
    pl_cut(K, upper, cutters); upper['part_label'] = label
    hosts += [base.name, upper.name]
    # the corner lugs: blocks on the ring's corners, chamfered on their inner corner
    # v5 (owner: "make the corner sections a bit more rounded and follow the layout with the notch from the old image"):
    # raised rim sections on the ring, laid as shipped: one U along the back-left edge (x = -i) wrapping both its corners
    # into short arms, and a short L round each front corner; outer corners rounded (rim_r), inner ones slightly; every
    # arm ends square with its outer corner cut at 45 deg (the notch where it steps down to the ring)
    w = T['ring']; Rc = T['rim_r'] - w / 2; hc = i - w / 2      # the band's centreline: a rounded square
    E_ = 2 * (hc - Rc); Q_ = math.pi / 2 * Rc; per = 4 * (E_ + Q_)
    cs = [(-hc + Rc, -hc + Rc), (hc - Rc, -hc + Rc), (hc - Rc, hc - Rc), (-hc + Rc, hc - Rc)]   # corner centres LL, BR, TR, TL
    def at(s):
        """centreline point and outward normal at arc length s; s = 0 at the start of the LL corner's arc, running
        LL -> BR along y = -hc (counterclockwise seen from above)"""
        s %= per
        for c in range(4):
            if s <= Q_:                                  # the corner arc
                a0 = math.pi + c * math.pi / 2; a = a0 + (s / Q_) * math.pi / 2
                cx, cy = cs[c]; nx, ny = math.cos(a), math.sin(a)
                return (cx + Rc * nx, cy + Rc * ny), (nx, ny)
            s -= Q_
            if s <= E_:                                  # the edge after it
                a = math.pi * 1.5 + c * math.pi / 2; nx, ny = math.cos(a), math.sin(a)
                cx, cy = cs[c]; tx, ty = -ny, nx
                return (cx + Rc * nx + tx * s, cy + Rc * ny + ty * s), (nx, ny)
            s -= E_
    def piece(name, s0, s1):
        ch = T['notch']
        # samples only on the corner arcs (12 each) and at the ends: points along a straight run would be collinear
        ss = {s0, s1, s0 + ch, s1 - ch}
        for c in range(-1, 6):
            a0 = c * (E_ + Q_)
            for j in range(13):
                s = a0 + Q_ * j / 12
                if s0 + ch + 1e-3 < s < s1 - ch - 1e-3:
                    ss.add(s)
        ss = sorted(ss)
        def off(s, d):
            (x, y), (nx, ny) = at(s); return (x + nx * d, y + ny * d)
        outer = [off(s, w / 2) for s in ss if s0 + ch <= s <= s1 - ch]
        inner = [off(s, -w / 2) for s in reversed(ss) if s in (s0, s1) or s0 + ch < s < s1 - ch]   # no collinear chamfer points
        pts = [off(s0, w / 2 - ch)] + outer + [off(s1, w / 2 - ch)] + inner
        # the end caps' chamfer: from the outer edge ch before the end to the end face ch inside the outer edge
        from mathutils.geometry import tessellate_polygon
        m_ = len(pts); z0, z1 = T['top'], T['top'] + T['lug_h']
        vs = [(x, y, z0) for x, y in pts] + [(x, y, z1) for x, y in pts]
        tris = []
        for a_, b_, c_ in tessellate_polygon([[Vector((x, y, 0)) for x, y in pts]]):
            (xa, ya), (xb, yb), (xc, yc) = pts[a_], pts[b_], pts[c_]; ar = (xb - xa) * (yc - ya) - (xc - xa) * (yb - ya)
            if abs(ar) > 1e-9:
                tris.append((a_, b_, c_) if ar > 0 else (a_, c_, b_))
        fs = [(c_, b_, a_) for a_, b_, c_ in tris] + [(m_ + a_, m_ + b_, m_ + c_) for a_, b_, c_ in tris]
        fs += [(j, (j + 1) % m_, m_ + (j + 1) % m_, m_ + j) for j in range(m_)]
        o = mesh(K, name, vs, fs, mat, False); o['part_label'] = label
        return o
    A = T['arm']
    sLL, sBR, sTR, sTL = 0.0, E_ + Q_, 2 * (E_ + Q_), 3 * (E_ + Q_)          # each corner arc's start
    hosts.append(piece('tray_rim_back', sTL - A, per + Q_ + A).name)          # TL arm, the x = -hc edge, LL arm
    hosts.append(piece('tray_rim_br', sBR - A, sBR + Q_ + A).name)
    hosts.append(piece('tray_rim_tr', sTR - A, sTR + Q_ + A).name)
    bpy.context.view_layer.update()
    for nm in hosts:
        pl_mesh_lines(K, bpy.data.objects[nm], label, 40.0, nm, 0.03)
    return hosts


def cpu_seated(K, board_m, ihs_m, glint_m, lb, li):
    T = TRAY; z0 = T['pocket_z']; b = T['pocket'] / 2 - 0.04; hosts = []
    board = cpu_rbox(K, 'seated_board', -b, b, -b, b, z0, z0 + 0.04, board_m, lb, 0.02, 2)
    f = b - 0.05
    flange = cpu_rbox(K, 'seated_flange', -f, f, -f, f, z0 + 0.04, z0 + 0.07, ihs_m, li, 0.03, 3)
    q = f - 0.07
    plateau = cpu_rbox(K, 'seated_plateau', -q, q, -q, q, z0 + 0.07, z0 + 0.12, ihs_m, li, 0.05, 3)
    hosts += [board.name, flange.name, plateau.name]
    bpy.context.view_layer.update()
    for nm in hosts:
        pl_mesh_lines(K, bpy.data.objects[nm], bpy.data.objects[nm]['part_label'], 40.0, nm, 0.03)
    # two glints across the plateau, parallel to the grid's Y (as shipped), undotted
    zt = z0 + 0.12 + 0.002
    lim = q - 0.03
    for k, (c0, c1) in enumerate(((0.05, 0.17), (0.28, 0.34))):   # v3: bands x + y in [c0, c1], straight up the screen
        quad = [(lim, c0 - lim, zt), (lim, c1 - lim, zt), (c1 - lim, lim, zt), (c0 - lim, lim, zt)]
        me = bpy.data.meshes.new('glint%d' % k); me.from_pydata(quad, [], [(0, 1, 2, 3)])
        g = K.obj('glint%d' % k, me, glint_m, False); noink(g); g['part_label'] = li; cpu_clear(g)
    return hosts


def cpu_leaning(K, board_m, edge_m, gold_m, lb):
    """The second CPU on its edge: its face in the plane spanned by the grid's Y and a line leaning CHIP['lean'] deg
    back from vertical, the pad side toward +X; its bottom edge on the ground, its back resting on the tray's top edge"""
    C = CHIP; T = TRAY; a = math.radians(C['lean']); S = C['size']; t = C['t']
    xe = T['L'] / 2 - T['inset']                       # the tray's upper +X edge (x, z) = (xe, top)
    n = Vector((math.cos(a), 0.0, math.sin(a)))        # the face's outward normal
    up = Vector((-math.sin(a), 0.0, math.cos(a)))      # along the face, up
    xb = xe + (T['top'] + T['lug_h']) * math.tan(a) + t * math.cos(a)  # the back's foot on the ground, the back on the lugs' top edge
    O = Vector((xb, C['y0'], t * math.sin(a)))          # the pad face's bottom corner nearest -Y
    def P(u, v, w=0.0):                                 # u along Y, v up the face, w out of the face
        return O + Vector((0, u, 0)) + up * v + n * w
    # the board with two notches in each side edge (as shipped): its outline in (u, v), extruded back by t
    out = [(0, 0), (S, 0)]
    for vv in (0.30, 0.70):                             # right edge notches
        out += [(S, vv * S - 0.05), (S - 0.04, vv * S - 0.03), (S - 0.04, vv * S + 0.03), (S, vv * S + 0.05)]
    out += [(S, S), (0, S)]
    for vv in (0.70, 0.30):                             # left edge notches
        out += [(0, vv * S + 0.05), (0.04, vv * S + 0.03), (0.04, vv * S - 0.03), (0, vv * S - 0.05)]
    m = len(out); vs = [tuple(P(u, v, 0.0)) for u, v in out] + [tuple(P(u, v, -t)) for u, v in out]
    # v3: the faces tessellated here (a concave n-gon fans badly in the visibility test and slivers in the render),
    # zero-area triangles from the edges' collinear points dropped, each triangle wound as the outline (CCW in u, v)
    from mathutils.geometry import tessellate_polygon
    tris = []
    for a_, b_, c_ in tessellate_polygon([[Vector((u, v, 0.0)) for u, v in out]]):
        (ua, va), (ub, vb), (uc, vc) = out[a_], out[b_], out[c_]
        ar = (ub - ua) * (vc - va) - (uc - ua) * (vb - va)
        if abs(ar) < 1e-7:
            continue
        tris.append((a_, b_, c_) if ar > 0 else (a_, c_, b_))
    fs = [t_ for t_ in tris] + [(m + c_, m + b_, m + a_) for a_, b_, c_ in tris] + [(k, m + k, m + (k + 1) % m, (k + 1) % m) for k in range(m)]
    board = mesh(K, 'chip_board', vs, fs, board_m, False); board['part_label'] = lb
    board.data.materials.append(edge_m)                  # v2: the board's thickness in gold, as shipped
    for p_ in board.data.polygons:
        if abs(Vector(p_.normal).dot(n)) < 0.5:
            p_.material_index = 1
    # the pads: a grid on the face, a gold square in the middle, a gold corner mark at two corners (all undotted)
    pv, pf = [], []
    def quad(u0, v0, u1, v1, lift=0.003):
        k = len(pv); pv.extend(tuple(P(u, v, lift)) for u, v in ((u0, v0), (u1, v0), (u1, v1), (u0, v1))); pf.append((k, k + 1, k + 2, k + 3))
    N = 22; pitch = (S - 0.16) / N; pad = pitch * 0.58
    for iu in range(N):
        for iv in range(N):
            cu, cv = 0.08 + (iu + 0.5) * pitch, 0.08 + (iv + 0.5) * pitch
            ring = max(abs(cu - S / 2), abs(cv - S / 2))
            if ring < S * 0.21:                          # the empty field round the centre square
                continue
            quad(cu - pad / 2, cv - pad / 2, cu + pad / 2, cv + pad / 2)
    c = S * 0.14; quad(S / 2 - c, S / 2 - c, S / 2 + c, S / 2 + c)
    for (u0, v0, du, dv) in ((0.05, S - 0.05, 1, -1), (S - 0.05, 0.05, -1, 1)):   # corner triangles
        k = len(pv); pv.extend(tuple(P(u, v, 0.003)) for u, v in ((u0, v0), (u0 + du * 0.12, v0), (u0, v0 + dv * 0.12))); pf.append((k, k + 1, k + 2))
    me = bpy.data.meshes.new('chip_pads'); me.from_pydata(pv, [], pf); me.update()
    pads = K.obj('chip_pads', me, gold_m, False); noink(pads); pads['part_label'] = lb; cpu_clear(pads)
    for p_ in pads.data.polygons:
        p_.use_smooth = False
    cpu_clear(board)
    bpy.context.view_layer.update()
    pl_mesh_lines(K, board, lb, 40.0, 'chip_board', 0.02)
    return [board.name]


def build_cpu():
    setup_icon_rig(); K = Kit(open_collection('ICON_cpu')); hosts = []
    mats = {k: pl_toon('cpu_' + k, *v) for k, v in TONES.items()}
    L_TRAY, L_SEAT_BOARD, L_IHS, L_CHIP = 1, 2, 3, 4
    hosts += cpu_tray(K, mats['tray'], L_TRAY)
    hosts += cpu_seated(K, mats['board'], mats['ihs'], mats['glint'], L_SEAT_BOARD, L_IHS)
    hosts += cpu_leaning(K, mats['board'], mats['edge'], mats['gold'], L_CHIP)
    for ob in K.col.objects:
        if ob.get('ink_width') == 6:
            ob['ink_width'] = PL_INNER
    info = contract(K, hosts, 'a copper CPU socket tray with a CPU seated in it (silver heat spreader, green board) and a '
                    'second CPU on its edge against the tray, its gold pad grid to the viewer', inner=PL_INNER)
    info['revision'] = CPU_REVISION; info['outline']['component_boundaries'] = True; info['stipple']['strength'] = 0.38
    info['stipple']['groups'] = [{'name': 'shaded_faces', 'labels': [1, 2, 3, 4, 5, 6, 7], 'thresholds': [0.575, 0.50, 0.30]}]
    info['dimensions'] = {'tray': TRAY, 'chip': CHIP}
    return info
