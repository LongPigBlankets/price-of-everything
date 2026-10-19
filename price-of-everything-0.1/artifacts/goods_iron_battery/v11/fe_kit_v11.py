"""Iron-air battery (g_061 iron_battery). The shipped art: a long grey steel cabinet on a yellow skid with castor
wheels, a black stack of fins (the cell stack's air-cathode plates) down its long front (-Y) side under a header pipe,
rounded windows in its short (+X) side, and a charcoal cover printed "Fe-Air" on top. Real iron-air storage (Form
Energy and others) packs deep stacks of iron-anode and air-cathode cells in such enclosures, so the cabinet is deep
and the stack sits in an open bay, its plates seen from above, behind a braced frame. It is drawn in the battery
family's style (the sodium and lithium packs): the same steel, slots, cover and print. The blades fill the whole front,
crossed by a V of two thin steel bars hooked over the housing, which wraps round flush with them. On the set's grid,
camera, light, 12/4 px ink and dots on the shaded sides."""
FE_REVISION = 'iron_battery_v11'
CAB = (1.10, 1.30, 0.80)                     # cabinet X (long, its -Y side the fin face), Y (deep), Z
SKID = (1.24, 1.44, 0.09)                    # the yellow skid under it
WHEEL = (0.10, 0.06)                         # castor wheel radius, width
BAY = 0.38                                   # the open bay's depth behind the fin face, where the cabinet roof stops
Z_SKID = 2 * WHEEL[0] - 0.02                 # the skid's underside, on the castors
FINS = dict(x=(0.06, 1.04), z=(0.05, 0.74), pitch=0.048, t=0.020, out=0.06)   # the blades fill the whole front
FRONT = -FINS['out'] - 0.04                  # the housing's front: its end walls and sill wrap round flush with the bars
WIN = [('+X', 0.86, 0.56, 0.62, 0.22), ('+X', 0.86, 0.25, 0.62, 0.28)]   # (wall, u, v centre, w, h): two big openings in the end
COVER = (0.20, 1.02, 0.50, 1.22, 0.05)       # x0, x1, y0, y1, thickness: behind the open bay


def fe_bar(K, name, p, q, w, y0, y1, mat, label):
    """a flat bar of width w from p to q (x, z) on the fin face, between y0 and y1"""
    (px, pz), (qx, qz) = p, q; L = math.hypot(qx - px, qz - pz); nx, nz = -(qz - pz) / L * w / 2, (qx - px) / L * w / 2
    quad = [(px + nx, pz + nz), (qx + nx, qz + nz), (qx - nx, qz - nz), (px - nx, pz - nz)]
    vs = [(x, y0, z) for x, z in quad] + [(x, y1, z) for x, z in quad]
    fs = [(0, 1, 2, 3), (7, 6, 5, 4), (0, 4, 5, 1), (1, 5, 6, 2), (2, 6, 7, 3), (3, 7, 4, 0)]
    ob = mesh(K, name, vs, fs, mat, False); noink(ob); ob['part_label'] = label
    bm = bmesh.new(); bm.from_mesh(ob.data); bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:]); bm.to_mesh(ob.data); bm.free()
    return ob


def fe_window_place(wall):
    X1, Y1, _ = CAB
    if wall == '-Y':
        return lambda u, v, a: (u, a, Z_SKID + SKID[2] + v)
    return lambda u, v, a: (X1 - a, u, Z_SKID + SKID[2] + v)


def build_iron_battery():
    setup_icon_rig(); K = Kit(open_collection('ICON_iron_battery')); hosts = []
    steel = pw_toon('fe_steel', (0.60, 0.62, 0.63), ((0.70, 0.34), (0.95, 0.62), (9.0, 1.0)))
    inner = pw_toon('fe_inner', (0.10, 0.11, 0.13), ((0.70, 0.45), (0.95, 0.70), (9.0, 1.0)))
    # the fins' own ramp: their -Y edges (diffuse ~0.56) take a mid charcoal, not the shade step, so the plates read
    fin = pw_toon('fe_fin', (0.12, 0.13, 0.15), ((0.40, 0.55), (0.80, 1.0), (9.0, 1.6)))
    yellow = pw_toon('fe_skid', (0.90, 0.62, 0.06), ((0.70, 0.55), (0.95, 0.80), (9.0, 1.0)))
    rubber = pw_toon('fe_wheel', (0.10, 0.11, 0.13), ((0.70, 0.5), (0.95, 0.8), (9.0, 1.2)))
    cover_m = pw_toon('fe_cover', (0.095, 0.11, 0.11), ((0.70, 0.45), (0.95, 0.70), (9.0, 1.0)))
    text_m = pw_flat('fe_print', (0.86, 0.86, 0.84))
    L_SKID, L_CAB, L_FIN, L_COVER, L_WHEEL, L_PIPE, L_BRACE = 1, 2, 3, 4, 5, 6, 7
    X1, Y1, Z1 = CAB; z0 = Z_SKID + SKID[2]
    # the skid and its castors
    sx0, sy0 = (X1 - SKID[0]) / 2, (FRONT + Y1 - SKID[1]) / 2
    hosts.append(alk_box(K, 'skid', sx0, sx0 + SKID[0], sy0, sy0 + SKID[1], Z_SKID, z0, yellow, L_SKID).name)
    for k, (fx, fy) in enumerate(((0.06, 0.07), (0.94, 0.07), (0.06, 0.93), (0.94, 0.93))):
        # a castor: a swivel plate under the skid, a steel fork, the wheel with a steel hub on its outer face
        cx, cy = sx0 + SKID[0] * fx, sy0 + SKID[1] * fy; r, wd = WHEEL
        hosts.append(alk_box(K, 'swivel%d' % k, cx - 0.06, cx + 0.06, cy - 0.06, cy + 0.06, Z_SKID - 0.018, Z_SKID + 0.002, steel, L_WHEEL).name)
        hosts.append(alk_box(K, 'fork%d' % k, cx - wd / 2 - 0.016, cx + wd / 2 + 0.016, cy - 0.045, cy + 0.035, r, Z_SKID - 0.018, steel, L_WHEEL).name)
        w = noink(K.cyl('wheel%d' % k, cx, cy, r, r, wd, rubber, axis='X', segments=32)); w['part_label'] = L_WHEEL; hosts.append(w.name)
        hub = noink(K.cyl('hub%d' % k, cx + wd / 2 + 0.004, cy, r, r * 0.48, 0.008, steel, axis='X', segments=24)); hub['part_label'] = L_WHEEL; hosts.append(hub.name)
    # the cabinet, its windows cut through into a dark inside
    cab = alk_box(K, 'cabinet', 0.0, X1, FRONT, Y1, z0, z0 + Z1, steel, L_CAB); hosts.append(cab.name)
    vs, fs = [], []
    for wall, u, v, w, h in WIN:
        ion_prism_mesh(rect_points(u, v, w, h, min(w, h) * 0.42, 10), fe_window_place(wall), -0.02, 0.03, vs, fs)
    # the open bay for the fin stack: the front of the cabinet over the fins, roof included, cut away
    bx0, bx1 = FINS['x'][0] - 0.02, FINS['x'][1] + 0.02; n0 = len(vs)
    vs += [(x, y, z) for z in (z0 + 0.03, z0 + Z1 + 0.05) for y in (FRONT - 0.05, BAY) for x in (bx0, bx1)]
    fs += [tuple(n0 + i for i in f) for f in ((0, 2, 3, 1), (4, 5, 7, 6), (0, 1, 5, 4), (2, 6, 7, 3), (0, 4, 6, 2), (1, 3, 7, 5))]
    ion_cut(cab, mesh(K, 'win_cutters', vs, fs, None, False), steel)
    cab.data.materials.append(inner)
    for p in cab.data.polygons:                        # the windows' reveal and back in the dark inside tone
        c = p.center
        if 0.0005 < c.x < X1 - 0.0005 and FRONT + 0.0005 < c.y < Y1 - 0.0005 and z0 + 0.0005 < c.z < z0 + Z1 - 0.0005:
            p.material_index = 1
    cab['part_label'] = L_CAB
    hosts.append(alk_box(K, 'cabinet_inside', 0.03, X1 - 0.03, BAY + 0.02, Y1 - 0.03, z0 + 0.02, z0 + Z1 - 0.02, inner, L_CAB, edges=False).name)   # behind the windows
    for k, (wall, u, v, w, h) in enumerate(WIN):
        place = fe_window_place(wall); pts = rect_points(u, v, w - 2 * E, h - 2 * E, min(w, h) * 0.42 - E, 10)
        tagged_line(K, 'win%d' % k, [place(p, q, -E) for p, q in pts], L_CAB, 6, True)['ink_width'] = 0
    # the fin stack in the bay, the plates running back to its rear wall, under a header pipe
    x = FINS['x'][0]; n = 0
    while x + FINS['t'] <= FINS['x'][1]:
        hosts.append(alk_box(K, 'fin%d' % n, x, x + FINS['t'], -FINS['out'], BAY - 0.02, z0 + FINS['z'][0], z0 + FINS['z'][1], fin, L_FIN).name)
        x += FINS['pitch']; n += 1
    back_plate = alk_box(K, 'fin_back', FINS['x'][0] - 0.02, x - FINS['pitch'] + FINS['t'] + 0.02, BAY - 0.03, BAY - 0.002, z0 + FINS['z'][0] - 0.03,
                         z0 + FINS['z'][1] + 0.03, inner, L_FIN); hosts.append(back_plate.name)
    pipe = noink(K.cyl('header_pipe', (FINS['x'][0] + x) / 2, -FINS['out'] * 0.55, z0 + FINS['z'][1] + 0.055, 0.035, x - FINS['x'][0] + 0.06, steel, axis='X', segments=24))
    pipe['part_label'] = L_PIPE; hosts.append(pipe.name)
    # the bracing over the blades, as shipped: two thin diagonal bars meeting at the bottom middle, a symmetric V, in
    # steel and standing proud so they read over the dark blades. Each runs up over the housing's end wall and its tip
    # hooks over the wall's top edge; the point of the V hooks over the sill
    xa = FINS['x'][0] - 0.02; xb = x - FINS['pitch'] + FINS['t'] + 0.02; xm = (xa + xb) / 2
    top = z0 + Z1; w = 0.034
    by0, by1 = FRONT - 0.014, FRONT + 0.004               # proud of the housing's front, so the bars lie over its walls
    tips = (xa / 2, X1 - (X1 - xb) / 2)                 # the middle of each end wall
    apex = (xm, z0 + 0.012)
    for k, tx in enumerate(tips):
        hosts.append(fe_bar(K, 'brace%d' % k, (tx, top - 0.008), apex, w, by0, by1, steel, L_BRACE).name)
        hosts.append(alk_box(K, 'hook%d' % k, tx - w * 0.75, tx + w * 0.75, by0, FRONT + 0.075, top - 0.004, top + 0.016, steel, L_BRACE).name)
        hosts.append(alk_box(K, 'hook_tip%d' % k, tx - w * 0.75, tx + w * 0.75, FRONT + 0.055, FRONT + 0.075, top - 0.035, top + 0.016, steel, L_BRACE).name)
    hosts.append(alk_box(K, 'sill_hook', xm - 0.04, xm + 0.04, by0, FRONT + 0.045, z0 + 0.018, z0 + 0.036, steel, L_BRACE).name)
    # the cover with the chemistry printed on it
    c0, c1, d0, d1, t = COVER
    hosts.append(alk_box(K, 'cover', c0, c1, d0, d1, z0 + Z1, z0 + Z1 + t, cover_m, L_COVER).name)
    word = formula_mesh(K.col, 'cover_print', 'Fe-Air', text_m, (c1 - c0) * 0.80, (d1 - d0) * 0.42, chemical=False)
    cx, cy = (c0 + c1) / 2, (d0 + d1) / 2
    for v in word.data.vertices:                       # baseline along +X, letters up along +Y, as the sodium pack
        v.co = Vector((cx + v.co.x, cy + v.co.y, z0 + Z1 + t + 0.002))
    word['part_label'] = L_COVER; pw_clean_water(noink(word))
    for ob in K.col.objects:                           # the fins in 3 px lines (thicker ones at their pitch merge into a block)
        if ob.get('line_path') and ob.name.startswith('fin'):
            ob['ink_width'] = 3
        elif ob.get('ink_width') == 6:                 # the rest at the set's thinner 4 px interior weight
            ob['ink_width'] = 4
    info = contract(K, hosts, 'iron-air battery: grey steel cabinet on a yellow castor skid, black fin stack down its long side '
                    'braced by a steel frame with crossbars under a header pipe, rounded windows, charcoal cover printed "Fe-Air"', inner=4)
    info['revision'] = FE_REVISION
    info['outline']['component_boundaries'] = True
    info['outline']['component_weight_by_label'] = {'3': 2.5, '5': 3, '6': 3, '7': 2.5}   # thin lines on the fins, castors, pipe and bracing
    info['stipple']['strength'] = 0.38
    info['stipple']['groups'][0]['thresholds'] = [0.65, 0.60, 0.35]
    info['structural_hosts'] = ['cabinet', 'skid', 'cover']
    return info
