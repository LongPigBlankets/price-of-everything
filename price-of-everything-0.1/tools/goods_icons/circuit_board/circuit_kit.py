"""Circuit board (g_043 circuit_board): the shipped art's bare green board lying flat, an edge connector tab with gold
fingers split by a key notch on its front-left (-Y) edge, and its copper read off the shipped art (fit/warp.py unwarps
the shipped top face into board coordinates, fit/extract.py reads the traces, vias, pads and fingers into
copper.json): gold traces, vias (a gold ring round a dark hole), outlined pads. On the set's grid, camera, light,
12/4 px ink and dots on the shaded sides; the copper is printed, so undotted and without ink of its own."""
import json
CB_REVISION = 'circuit_board_v6'
BOARD = dict(L=2.0, t=0.10,   # v5 (owner: "give it a bit more thickness"): 0.06 -> 0.10
             r=0.06, tab=(0.295, 0.955), tab_d=0.19, notch=(0.475, 0.540), notch_d=0.15, tab_r=0.012,
             finger_pitch=0.0285, finger_w=0.019, finger_v=(-0.178, -0.045))
TONES = {'board': ((72, 100, 76), (88, 120, 92), (100, 134, 102)), 'gold': ((196, 164, 100), (205, 172, 107), (214, 182, 116)),
         'silk': ((226, 222, 204), (234, 230, 212), (240, 236, 220)),
         'hole': ((28, 34, 56), (32, 38, 62), (36, 42, 68)), 'pad_side': ((30, 36, 60), (36, 42, 68), (44, 50, 76))}


def cb_w(u, v):
    """board coordinates (u, v in [0, 1] over the top face) -> world x, y"""
    L = BOARD['L']; return (u * L - L / 2, v * L - L / 2)


def cb_outline():
    """the board's plan in (u, v): the rounded rectangle with the tab and its notch; points only at corners and on arcs
    (collinear points along a straight run leave slivers in the caps)"""
    B = BOARD; r, tr = B['r'] / B['L'], B['tab_r'] / B['L']; d = -B['tab_d']; (ta, tb), (na, nb) = B['tab'], B['notch']; nd = d + B['notch_d']
    def arc(cx, cy, rad, a0, a1, n=6):
        return [(cx + rad * math.cos(math.radians(a0 + (a1 - a0) * k / n)), cy + rad * math.sin(math.radians(a0 + (a1 - a0) * k / n))) for k in range(n + 1)]
    P = []
    P += arc(r, r, r, 180, 270)                         # the left corner (u = 0, v = 0)
    ej = -0.0005                                        # the tab's roots a hair below the edge: four collinear points on it
    P += [(ta, ej)] + arc(ta + tr, d + tr, tr, 180, 270)  # make zero-area cap triangles; down the tab's left side
    P += arc(na - tr, d + tr, tr, 270, 360) + [(na, nd)] + [(nb, nd)] + arc(nb + tr, d + tr, tr, 180, 270)
    P += arc(tb - tr, d + tr, tr, 270, 360) + [(tb, ej)]
    P += arc(1 - r, r, r, 270, 360) + arc(1 - r, 1 - r, r, 0, 90) + arc(r, 1 - r, r, 90, 180)
    out = []
    for p in P:                                          # no duplicates
        if not out or math.hypot(p[0] - out[-1][0], p[1] - out[-1][1]) > 1e-6:
            out.append(p)
    if math.hypot(out[0][0] - out[-1][0], out[0][1] - out[-1][1]) < 1e-6:
        out.pop()
    return out


def cb_prism(K, name, pts, z0, z1, mat, label):
    """an extruded plan (CCW in x, y), its caps tessellated (zero-area triangles dropped)"""
    from mathutils.geometry import tessellate_polygon
    m = len(pts); vs = [(x, y, z0) for x, y in pts] + [(x, y, z1) for x, y in pts]; tris = []
    for a, b, c in tessellate_polygon([[Vector((x, y, 0)) for x, y in pts]]):
        (xa, ya), (xb, yb), (xc, yc) = pts[a], pts[b], pts[c]; ar = (xb - xa) * (yc - ya) - (xc - xa) * (yb - ya)
        if abs(ar) > 1e-10:
            tris.append((a, b, c) if ar > 0 else (a, c, b))
    fs = [(c, b, a) for a, b, c in tris] + [(m + a, m + b, m + c) for a, b, c in tris] + [(j, (j + 1) % m, m + (j + 1) % m, m + j) for j in range(m)]
    o = mesh(K, name, vs, fs, mat, False); o['part_label'] = label
    return o


def cb_flat(K, name, polys, z, mat, label, clear=True):
    """flat plates (each a list of (x, y)) at height z, in one mesh"""
    from mathutils.geometry import tessellate_polygon
    vs, fs = [], []
    for pts in polys:
        k = len(vs); vs += [(x, y, z) for x, y in pts]
        for a, b, c in tessellate_polygon([[Vector((x, y, 0)) for x, y in pts]]):
            (xa, ya), (xb, yb), (xc, yc) = pts[a], pts[b], pts[c]; ar = (xb - xa) * (yc - ya) - (xc - xa) * (yb - ya)
            if abs(ar) > 1e-12:
                fs.append((k + a, k + b, k + c) if ar > 0 else (k + a, k + c, k + b))
    me = bpy.data.meshes.new(name); me.from_pydata(vs, [], fs); me.update()
    o = K.obj(name, me, mat, False); noink(o); o['part_label'] = label
    if clear:
        at = o.data.attributes.new('icon_stipple_clear', 'FLOAT', 'CORNER')
        for d_ in at.data:
            d_.value = 1.0
    return o


def cb_disc(c, r, n=16):
    return [(c[0] + r * math.cos(2 * math.pi * k / n), c[1] + r * math.sin(2 * math.pi * k / n)) for k in range(n)]


def build_circuit_board():
    setup_icon_rig(); K = Kit(open_collection('ICON_circuit_board')); hosts = []
    mats = {k: pl_toon('cb_' + k, *v) for k, v in TONES.items()}
    B = BOARD; L = B['L']; t = B['t']; zc = t + 0.002; LB = 1
    # v6 (owner: "fix the traces and fingers ... maybe a slot marking where the CPU and its slot will come in"): the copper
    # as fit/route.py made it plausible (no dead ends, a trace from every finger, the socket's land pads)
    C = json.load(open(str(here / 'copper2.json')))
    board = cb_prism(K, 'board', [cb_w(u, v) for u, v in cb_outline()], 0.0, t, mats['board'], LB); hosts.append(board.name)
    # v3: the top edges bevelled (the shipped art's pale band above the dark sides); 45 deg each way, so no crease line
    bm = bmesh.new(); bm.from_mesh(board.data)
    es = [e for e in bm.edges if len(e.link_faces) == 2 and all(v.co.z > t - 1e-6 for v in e.verts)
          and sum(f.normal.z > 0.9 for f in e.link_faces) == 1]
    bmesh.ops.bevel(bm, geom=es, offset=0.03, segments=1, affect='EDGES', profile=0.5)
    bm.to_mesh(board.data); bm.free(); board.data.update()
    bpy.context.view_layer.update()
    pl_mesh_lines(K, board, LB, 50.0, 'board', 0.02)
    # v4: the ink pass skips concave edges (plastics_kit.pl_mesh_lines, this good's copy): the tab's inner corners drew ticks
    # and the bevel's seams at the four inner corners (the tab's roots, the notch's far corners) are cut out of the chains
    d_ = -B['tab_d'] + B['notch_d']
    inner = [Vector(cb_w(u, v) + (0.0,)) for u, v in ((B['tab'][0], 0.0), (B['tab'][1], 0.0), (B['notch'][0], d_), (B['notch'][1], d_))]
    for o in [o for o in K.col.objects if o.name.startswith('board_line')]:
        P = [Vector(o['line_path'][i:i + 3]) for i in range(0, len(o['line_path']), 3)]
        bad = [p.z > 0.003 and any((Vector((p.x, p.y, 0)) - q).length < 0.07 for q in inner) for p in P]
        if not any(bad):
            continue
        runs, cur = [], []
        for p, b_ in zip(P, bad):
            if b_:
                if len(cur) > 1:
                    runs.append(cur)
                cur = []
            else:
                cur.append(p)
        if len(cur) > 1:
            runs.append(cur)
        nm = o.name; bpy.data.objects.remove(o, do_unlink=True)
        for j, r in enumerate(runs):
            ln = tagged_line(K, '%s_%d' % (nm, j), [tuple(p) for p in r], LB, 6, False); ln['ink_width'] = 0
    w = C['width'] * L / 2                               # half the trace width in world units
    plates = []
    for tr in C['traces']:                               # each segment a quad, each vertex a disc (round joins and ends)
        P = [Vector(cb_w(u, v) + (0.0,)) for u, v in tr]
        for a, b in zip(P, P[1:]):
            d = (b - a); d.z = 0
            if d.length < 1e-6:
                continue
            n = Vector((-d.y, d.x, 0)).normalized() * w
            plates.append([(a + n).xy[:], (b + n).xy[:], (b - n).xy[:], (a - n).xy[:]])
        plates += [cb_disc(p.xy, w, 12) for p in P]
    for v_ in C['vias']:
        c = cb_w(*v_['c']); ro = v_['r_out'] * L; ri = v_['r_hole'] * L
        ring_o, ring_i = cb_disc(c, ro, 20), cb_disc(c, ri, 20)
        plates += [[ring_o[k], ring_o[(k + 1) % 20], ring_i[(k + 1) % 20], ring_i[k]] for k in range(20)]
    for q in C['lands']:                                 # the socket's land pads, where traces meet its edge
        s_ = 0.011; plates.append([cb_w(q[0] - s_, q[1] - s_), cb_w(q[0] + s_, q[1] - s_), cb_w(q[0] + s_, q[1] + s_), cb_w(q[0] - s_, q[1] + s_)])
    (fa, fb) = B['finger_v']; pitch = B['finger_pitch']; fw = B['finger_w']
    for a0, a1 in ((B['tab'][0], B['notch'][0]), (B['notch'][1], B['tab'][1])):   # the fingers either side of the key notch
        n = int((a1 - a0 - 0.01) / pitch)
        for k in range(n):
            uc = a0 + 0.005 + pitch * (k + 0.5) + ((a1 - a0 - 0.01) - n * pitch) / 2
            plates.append([cb_w(uc - fw / 2, fa), cb_w(uc + fw / 2, fa), cb_w(uc + fw / 2, fb), cb_w(uc - fw / 2, fb)])
    cb_flat(K, 'copper', plates, zc, mats['gold'], LB)
    # v6: the socket's printed marking (silkscreen): an outline just inside the ring of land pads, and a pin-1 triangle
    S = C['socket']; ins = 0.03; lw = 0.0085
    a0, a1, b0, b1 = S['u0'] + ins, S['u1'] - ins, S['v0'] + ins, S['v1'] - ins
    silk = [[cb_w(a0, b0), cb_w(a1, b0), cb_w(a1, b0 + lw), cb_w(a0, b0 + lw)], [cb_w(a0, b1 - lw), cb_w(a1, b1 - lw), cb_w(a1, b1), cb_w(a0, b1)],
            [cb_w(a0, b0), cb_w(a0 + lw, b0), cb_w(a0 + lw, b1), cb_w(a0, b1)], [cb_w(a1 - lw, b0), cb_w(a1, b0), cb_w(a1, b1), cb_w(a1 - lw, b1)]]
    tri = 0.05; silk.append([cb_w(a0 + 0.02, b1 - 0.02), cb_w(a0 + 0.02 + tri, b1 - 0.02), cb_w(a0 + 0.02, b1 - 0.02 - tri)])
    cb_flat(K, 'socket_silk', silk, zc + 0.0003, mats['silk'], LB)
    # the holes in the vias, dark, just above the copper
    cb_flat(K, 'via_holes', [cb_disc(cb_w(*v_['c']), v_['r_hole'] * L, 16) for v_ in C['vias']], zc + 0.001, mats['hole'], LB)
    # v2: the pads raised (as shipped: a gold top over a thick dark band on their front sides), each a prism with a
    # gold top and dark sides, on its own label so the exporter outlines it
    pads = [[cb_w(u, v) for u, v in p] for p in C['pad_polys']]
    for j, p in enumerate(pads):
        if sum(p[i][0] * p[(i + 1) % len(p)][1] - p[(i + 1) % len(p)][0] * p[i][1] for i in range(len(p))) < 0:
            p = p[::-1]
        pad = cb_prism(K, 'pad%d' % j, p, t - 0.002, t + 0.035, mats['pad_side'], 2)
        pad.data.materials.append(mats['gold'])
        for f in pad.data.polygons:
            if f.normal.z > 0.9:
                f.material_index = 1
        at = pad.data.attributes.new('icon_stipple_clear', 'FLOAT', 'CORNER')
        for d_ in at.data:
            d_.value = 1.0
        hosts.append(pad.name)
    for ob in K.col.objects:
        if ob.get('ink_width') == 6:
            ob['ink_width'] = PL_INNER
    info = contract(K, hosts, 'a bare green circuit board with an edge connector (gold fingers, a key notch), its gold '
                    'traces, vias and pads read off the shipped art', inner=PL_INNER)
    info['revision'] = CB_REVISION; info['outline']['component_boundaries'] = True; info['stipple']['strength'] = 0.38
    info['stipple']['groups'] = [{'name': 'shaded_faces', 'labels': [1, 2, 3, 4, 5, 6, 7], 'thresholds': [0.575, 0.50, 0.30]}]
    info['dimensions'] = {'board': BOARD, 'traces': len(C['traces']), 'vias': len(C['vias']), 'pads': len(C['pad_polys'])}
    return info
