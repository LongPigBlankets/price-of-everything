"""Building frame (g_023 building_frame): the shipped art's steel cube frame (four square-tube corner posts, a ring of
beams at the bottom, the middle and the top), a white pane on the top ring, bundles of cable draped over the top
at three corners, and copper pipes up through the beams by the front post (the recipe's steel, windows, electrical components and
copper pipe). Steel in the approved steel icon's blue-grey, the pipe in the copper pipe icon's copper, the pane in the
windows icon's white. On the set's grid, camera, light, 12/4 px ink and dots on the shaded sides."""
BF_REVISION = 'building_frame_v6'
FRAME = dict(h=1.0, H=2.0, post=0.24, beam=0.19, beam_h=0.22, inset=0.025, rings=(0.0, 0.84, 1.78), slab_t=0.06)   # v2: chunkier, as shipped
TONES = {'steel': ((78, 96, 102), (108, 132, 138), (132, 162, 174)), 'pane': ((214, 214, 208), (234, 234, 228), (244, 244, 240)),
         'copper': ((156, 96, 66), (180, 108, 72), (204, 132, 84)), 'cable': ((50, 52, 58), (62, 64, 70), (80, 82, 90)),
         'stripe': ((196, 156, 64), (222, 182, 84), (236, 200, 104)), 'bore': ((52, 34, 26), (60, 40, 30), (70, 46, 34)),
         'ebox': ((150, 156, 168), (176, 182, 194), (204, 210, 220)), 'lid': ((206, 160, 40), (232, 186, 56), (246, 206, 84)),
         'wrap': ((40, 42, 50), (54, 56, 64), (72, 74, 84))}
# v6 (owner: "make the cables come out of grey electrical boxes with yellow lids ... a little wrapping around the place
# where the cables meet the electrical boxes. The boxes should sit where the cables currently end on the top"): a box on
# the pane at each bundle's top end, the bundle leaving through the face toward its edge in a short wrapped sleeve
EBOX = dict(w=0.34, d=0.26, h=0.25, lid=0.03, lip=0.012, sleeve=0.09, sleeve_pad=0.018, band=0.016, band_pad=0.014)


def bf_box(K, name, x0, x1, y0, y1, z0, z1, mat, label):
    bm = bmesh.new(); bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co = Vector((x0 if v.co.x < 0 else x1, y0 if v.co.y < 0 else y1, z0 if v.co.z < 0 else z1))
    me = bpy.data.meshes.new(name); bm.to_mesh(me); bm.free()
    o = K.obj(name, me, mat, False); noink(o); o['part_label'] = label
    return o


def bf_frame(K, mat, label):
    F = FRAME; h, s, b, bh, ins, H = F['h'], F['post'], F['beam'], F['beam_h'], F['inset'], F['H']; hosts = []
    for sx in (-1, 1):
        for sy in (-1, 1):
            xa, xb = sorted((sx * h, sx * (h - s))); ya, yb = sorted((sy * h, sy * (h - s)))
            hosts.append(bf_box(K, 'post_%d_%d' % (sx, sy), xa, xb, ya, yb, 0.0, H, mat, label).name)
    for k, z0 in enumerate(F['rings']):
        z1 = z0 + bh
        for sy in (-1, 1):                               # beams along X, between the posts
            ya, yb = sorted((sy * (h - ins), sy * (h - ins - b)))
            hosts.append(bf_box(K, 'beam_x_%d_%d' % (k, sy), -h + s, h - s, ya, yb, z0, z1, mat, label).name)
        for sx in (-1, 1):                               # beams along Y
            xa, xb = sorted((sx * (h - ins), sx * (h - ins - b)))
            hosts.append(bf_box(K, 'beam_y_%d_%d' % (k, sx), xa, xb, -h + s, h - s, z0, z1, mat, label).name)
    bpy.context.view_layer.update()
    for n in hosts:
        pl_mesh_lines(K, bpy.data.objects[n], label, 40.0, n, 0.02)
    return hosts


def bf_cable(K, name, pts, mat, labels, n=4, gap=0.064, r=0.028, across=(1, 0, 0), stripe=None):   # v3: four thicker cables, so the black shows
    """a flat bundle of n cables along a centre path, side by side along `across`; v3 (owner: "make the cables black
    with yellow stripes"): each black with a yellow stripe along it, on the side toward the viewer"""
    P = pl_catmull([Vector(p) for p in pts], 8); hosts = []
    # v4 (owner: the horizontal run "should go to the right not become hidden"): the bundle turns as a flat ribbon, its
    # spread carried along the path (parallel transport), so the cables stay side by side through every bend
    T = [(P[min(i + 1, len(P) - 1)] - P[max(i - 1, 0)]).normalized() for i in range(len(P))]
    a = Vector(across); a = (a - T[0] * a.dot(T[0])).normalized(); A = [a]
    for i in range(1, len(P)):
        a = T[i - 1].rotation_difference(T[i]).to_matrix() @ a; a = (a - T[i] * a.dot(T[i])).normalized(); A.append(a)
    for k in range(n):
        f = (k - (n - 1) / 2) * gap
        ob = K.sweep('%s_%d' % (name, k), [p + a_ * f for p, a_ in zip(P, A)], r, mat, seg=32); noink(ob)
        ob['part_label'] = labels[k % len(labels)]
        if stripe is not None:
            ob.data.materials.append(stripe)
        me_ = ob.data
        for poly in me_.polygons:
            poly.use_smooth = True
            if stripe is None:
                continue
            # the stripe: faces turned toward the viewer as far as the cable's own direction allows (the face's long
            # edge is along the cable)
            vs_ = [me_.vertices[i].co for i in poly.vertices]
            es_ = [(vs_[j] - vs_[j - 1]) for j in range(len(vs_))]; T_ = max(es_, key=lambda e: e.length).normalized()
            Vp = VIEW - T_ * VIEW.dot(T_)
            if Vp.length > 1e-6 and poly.normal.normalized().dot(Vp.normalized()) > 0.985:
                poly.material_index = 1
        hosts.append(ob.name)
    return hosts


def bf_ebox(K, name, cx, cy, out, z0, mats, labels):
    """a grey box with a yellow lid on the pane, its face toward `out` (a unit X or Y step) at (cx, cy), and the black taped
    wrap the bundle leaves it through just outside that face: a sleeve with a raised band of tape at each end. Returns
    the inked hosts."""
    E = EBOX; ox, oy = out; along = 0 if ox else 1; step = ox if ox else oy; c_al, c_ac = (cx, cy) if ox else (cy, cx)
    def part(nm, a0, a1, b0, b1, z_0, z_1, mat, lab):    # a box given along / across the bundle
        x0, x1, y0, y1 = (a0, a1, b0, b1) if along == 0 else (b0, b1, a0, a1)
        return bf_box(K, nm, x0, x1, y0, y1, z_0, z_1, mat, lab)
    a0, a1 = sorted((c_al, c_al - step * E['d'])); b0, b1 = c_ac - E['w'] / 2, c_ac + E['w'] / 2
    parts = [(part(name, a0, a1, b0, b1, z0, z0 + E['h'], mats['ebox'], labels[0]), labels[0]),
             (part(name + '_lid', a0 - E['lip'], a1 + E['lip'], b0 - E['lip'], b1 + E['lip'], z0 + E['h'], z0 + E['h'] + E['lid'],
                   mats['lid'], labels[1]), labels[1])]
    bundle_top = z0 + 2 * 0.028 + 0.03
    s0, s1 = sorted((c_al, c_al + step * E['sleeve']))
    parts.append((part(name + '_sleeve', s0, s1, b0 - 0.004, b1 + 0.004, z0, bundle_top + E['sleeve_pad'], mats['wrap'], labels[2]), labels[2]))
    for k, at in enumerate((c_al + step * E['band'] * 0.5, c_al + step * (E['sleeve'] - E['band'] * 0.5))):
        parts.append((part('%s_band%d' % (name, k), at - E['band'] / 2, at + E['band'] / 2, b0 - 0.004 - E['band_pad'], b1 + 0.004 + E['band_pad'],
                           z0, bundle_top + E['sleeve_pad'] + E['band_pad'], mats['wrap'], labels[2]), labels[2]))
    bpy.context.view_layer.update()
    hosts = []
    for o, lab in parts:
        pl_mesh_lines(K, o, lab, 40.0, o.name, 0.02); hosts.append(o.name)
    return hosts


def build_building_frame():
    setup_icon_rig(); K = Kit(open_collection('ICON_building_frame')); hosts = []
    mats = {k: pl_toon('bf_' + k, *v) for k, v in TONES.items()}
    F = FRAME; h, H, s, t = F['h'], F['H'], F['post'], F['slab_t']; top = H
    L_STEEL, L_PANE, L_CAB_A, L_CAB_B, L_PIPE, L_BOX, L_LID, L_WRAP = 1, 2, 3, 4, 5, 6, 7, 8
    hosts += bf_frame(K, mats['steel'], L_STEEL)
    pane = bf_box(K, 'pane', -h + s, h - s, -h + s, h - s, top, top + t, mats['pane'], L_PANE); hosts.append(pane.name)
    at = pane.data.attributes.new('icon_stipple_clear', 'FLOAT', 'CORNER')
    for d_ in at.data:
        d_.value = 1.0
    bpy.context.view_layer.update(); pl_mesh_lines(K, pane, L_PANE, 40.0, 'pane', 0.02)
    # the cables: over the top edge and down the outside, as shipped
    zt = top + t + 0.03; out = h + 0.04
    # v3 (owner: "make the cables from the left feed into the middle cables"): the left bundle comes down to the middle
    # ring, runs along it to the front bundle and goes down to the ground beside it
    zm = F['rings'][1] + F['beam_h'] / 2; xj = 0.60 - 4 * 0.064
    hosts += bf_cable(K, 'cable_left', [(-0.60, -0.56, zt), (-0.60, -h + 0.02, zt), (-0.60, -out, top - 0.10), (-0.60, -out, zm + 0.26),
                                        (-0.40, -out, zm), (xj - 0.20, -out, zm), (xj, -out, zm - 0.20), (xj, -out, 0.06)],
                      mats['cable'], (L_CAB_B, L_CAB_A), across=(0, 0, 1) if False else (1, 0, 0), stripe=mats['stripe'])
    hosts += bf_cable(K, 'cable_front', [(0.62, -0.56, zt), (0.62, -h + 0.02, zt), (0.62, -out, top - 0.10), (0.62, -out, 0.06)],
                      mats['cable'], (L_CAB_A, L_CAB_B), stripe=mats['stripe'])
    hosts += bf_cable(K, 'cable_right', [(0.56, 0.62, zt), (h - 0.02, 0.62, zt), (out, 0.62, top - 0.10), (out, 0.62, top - 0.42),
                                         (h - 0.08, 0.62, top - 0.62), (h - 0.32, 0.62, top - 0.42)], mats['cable'], (L_CAB_A, L_CAB_B), across=(0, 1, 0),
                      stripe=mats['stripe'])
    # v6: the boxes the bundles come out of, where they used to start on the pane
    z_pane = top + t; box_labels = (L_BOX, L_LID, L_WRAP)
    hosts += bf_ebox(K, 'ebox_left', -0.60, -0.70, (0, -1), z_pane, mats, box_labels)
    hosts += bf_ebox(K, 'ebox_front', 0.62, -0.70, (0, -1), z_pane, mats, box_labels)
    hosts += bf_ebox(K, 'ebox_right', 0.70, 0.62, (1, 0), z_pane, mats, box_labels)
    # v4 (owner: "the horizontal beam is too far in. Just put the pipe through a cutout in the beam"): each pipe centred in
    # the +X beams' depth, slim enough to leave a wall either side, through a cutout in each of the three rings' beams,
    # standing proud of the top with its bore dark, a coupling between the bottom and middle rings.
    # v5 (owner: "add a 2nd pipe between the existing one and the corner. Same layout"): a second pipe nearer the front
    # corner, as far toward it as the front post leaves it in view
    pr = 0.068; px = h - F['inset'] - F['beam'] / 2; ztop = top + t + 0.14
    cz = (F['rings'][0] + F['beam_h'] + F['rings'][1]) / 2
    PIPES = (-0.40, -0.575)
    for j, py in enumerate(PIPES):
        nm = 'pipe' if j == 0 else 'pipe%d' % (j + 1)
        pipe = tube_z(K, nm, (px, py), pr, pr - 0.016, 0.0, ztop, mats['copper'], L_PIPE); noink(pipe); hosts.append(pipe.name)
        coup = K.cyl(nm + '_coupling', px, py, cz, pr + 0.016, 0.08, mats['copper'], axis='Z', segments=24, smooth=True)
        noink(coup); coup['part_label'] = L_PIPE; hosts.append(coup.name)
        bore = K.cyl(nm + '_bore', px, py, ztop - 0.05, pr - 0.018, 0.004, mats['bore'], axis='Z', segments=32, smooth=False)
        noink(bore); bore['part_label'] = L_PIPE
    for kr, z0 in enumerate(F['rings']):                  # the cutouts, both pipes in each beam
        holes = [K.cyl('pipe_hole%d_%d' % (kr, j), px, py, z0 + F['beam_h'] / 2, pr + 0.004, F['beam_h'] + 0.2, None, axis='Z', segments=48, smooth=False)
                 for j, py in enumerate(PIPES)]
        bn = 'beam_y_%d_1' % kr; beam = bpy.data.objects[bn]; pl_cut(K, beam, holes); beam['part_label'] = L_STEEL
        for o in [o for o in K.col.objects if o.name.startswith(bn + '_line')]:
            bpy.data.objects.remove(o, do_unlink=True)
        bpy.context.view_layer.update(); pl_mesh_lines(K, beam, L_STEEL, 40.0, bn, 0.02)
    bpy.context.view_layer.update()
    for j in range(len(PIPES)):
        nm = 'pipe' if j == 0 else 'pipe%d' % (j + 1)
        for n in (nm, nm + '_coupling'):
            pl_mesh_lines(K, bpy.data.objects[n], L_PIPE, 40.0, n, 0.02)
    for ob in K.col.objects:
        if ob.get('ink_width') == 6:
            ob['ink_width'] = PL_INNER
    info = contract(K, hosts, 'a steel cube frame (corner posts, three rings of beams) with a white pane on top, yellow '
                    'striped cable bundles out of grey electrical boxes with yellow lids over three corners and two copper '
                    'pipes through the beams by the front post', inner=PL_INNER)
    info['revision'] = BF_REVISION; info['outline']['component_boundaries'] = True; info['stipple']['strength'] = 0.38
    info['stipple']['groups'] = [{'name': 'shaded_faces', 'labels': [1, 2, 3, 4, 5, 6, 7, 8], 'thresholds': [0.575, 0.50, 0.30]}]
    info['dimensions'] = {'frame': FRAME}
    return info
