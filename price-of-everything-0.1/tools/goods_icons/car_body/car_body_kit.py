"""Car body (g_045 car_body): the approved diesel car's Passat sedan as an unfitted painted body shell.

The shell is the diesel car's own loft (the owner-approved B5.5 profile, arches cut at the same axles), hollowed to a
thin skin with a primer-coloured inside. The window, screen, lamp, radiator and intake apertures are cut through it
along the outlines the diesel car uses for its glass and lamps, and the bonnet is cut free along its seams and propped
open on a stay. No glass, wheels, lamps, grille, trim or fittings. Colours from the shipped art (slate body, beige
primer inside). On the set's grid, camera, light, 12/4 px ink and dots on the shaded sides.

Owner, 2026-10-17: "ok now let's do the car body one. First appraise the existing diesel car blender file and try to
remove all parts that are not the body", then "Open up the shell: hollow it, cut the window and lamp openings, prop
the bonnet open, and move it to the newer line pipeline. Leave the truck cab for later." """
CB_REVISION = 'car_body_v17'
SKIN = 0.035                       # shell thickness, inward from the painted surface
BONNET_OPEN = 65.0                 # degrees the bonnet is lifted about the hinge line through its rear corners (owner: 65)
HINGE_X = 0.92                     # the hinges sit just inside the bonnet's rear corners
# owner on v3: "Use a grey interior" (the shipped art's beige primer read as trim); a cool grey, a touch of blue
TONES = {'body': ((54, 64, 88), (70, 82, 110), (96, 110, 140)), 'primer': ((108, 112, 120), (136, 140, 148), (166, 170, 178)),
         # owner on v11: "Darken the inside of the wheel arch": the wheelhouse liners take the cavity's deep grey
         'liner': ((34, 38, 52), (46, 50, 64), (60, 64, 78)), 'flange': ((108, 112, 120), (136, 140, 148), (166, 170, 178)),
         'cut': ((108, 112, 120), (136, 140, 148), (166, 170, 178)),
         # review of v5: openings must read as holes, the darkest value on the icon, as in the shipped art; inside faces
         # the shell hides from the light take this deep grey (the interior stays grey, per the owner)
         'cavity': ((34, 38, 52), (46, 50, 64), (60, 64, 78)),
         # the lorry cab in the shipped art's mid blue
         'cab': ((60, 100, 140), (75, 125, 165), (120, 160, 190)),
         'stay': ((112, 116, 120), (146, 150, 154), (184, 188, 192))}
L_SHELL, L_BONNET, L_STAY, L_INNER, L_CAB, L_DEFLECTOR, L_BUMPER = 1, 2, 3, 4, 5, 6, 7
FLANGE = 0.05                      # return flange left at every cut edge, beyond the skin


def cb_mesh(K, name, vs, fs, mat, smooth=True):
    me = bpy.data.meshes.new(name); me.from_pydata([tuple(v) for v in vs], [], fs); me.update()
    bm = bmesh.new(); bm.from_mesh(me); bmesh.ops.recalc_face_normals(bm, faces=bm.faces); bm.to_mesh(me); bm.free()
    ob = K.obj(name, me, mat, smooth)
    for f in me.polygons:
        f.use_smooth = smooth
    return noink(ob)


def cb_apply(ob):
    """Bake an object's modifier stack into its mesh. The baked mesh keeps the evaluated material slots, so faces a
    boolean transferred from a cutter keep the cutter's material."""
    bpy.context.view_layer.update()
    me = bpy.data.meshes.new_from_object(ob.evaluated_get(bpy.context.evaluated_depsgraph_get()))
    for mod in list(ob.modifiers):
        ob.modifiers.remove(mod)
    old = ob.data; ob.data = me; bpy.data.meshes.remove(old)
    return noink(ob)


def cb_boolean(ob, cutters, op='DIFFERENCE'):
    for c in cutters:
        mod = ob.modifiers.new('cut', 'BOOLEAN'); mod.operation = op; mod.solver = 'EXACT'; mod.object = c
        mod.material_mode = 'TRANSFER'
    return cb_apply(ob)


def cb_skin(ob, primer, paint=None):
    """Keep the painted faces of a cut solid and the cutters' walls (the return flanges, and the arch liners), drop the
    cutters' caps, then thicken the open skin inward by SKIN with the inside and the rims in primer."""
    me = ob.data; pi = [i for i, m in enumerate(me.materials) if m and m.name == 'cb_cut']
    bm = bmesh.new(); bm.from_mesh(me)
    bmesh.ops.delete(bm, geom=[f for f in bm.faces if f.material_index in pi], context='FACES')
    bmesh.ops.dissolve_degenerate(bm, dist=1e-6, edges=bm.edges[:])
    bm.to_mesh(me); bm.free()
    body = paint or bpy.data.materials['cb_body']
    old = [m.name if m else '' for m in me.materials]
    idx = [2 if n == 'cb_liner' else 1 if n in ('cb_flange', 'cb_primer') else 0 for n in old]
    face_mat = [idx[p.material_index] if p.material_index < len(idx) else 0 for p in me.polygons]
    # paint, primer, liner: the solidify offset puts the paint's inside in primer; the liner's inside stays liner
    me.materials.clear(); me.materials.append(body); me.materials.append(primer); me.materials.append(bpy.data.materials['cb_liner'])
    for f, m in zip(me.polygons, face_mat):
        f.material_index = m
    sol = ob.modifiers.new('skin', 'SOLIDIFY'); sol.thickness = SKIN; sol.offset = -1.0; sol.use_even_offset = False
    sol.use_rim = True; sol.material_offset = 1; sol.material_offset_rim = 1
    return cb_apply(ob)


def cb_prism(K, name, outer, inner, mat, cap=None):
    """A closed solid between two matching rings of 3D points (fan-capped at each ring's centroid). With `cap`, the
    two caps take that material and the walls `mat`."""
    n = len(outer); vs = [tuple(p) for p in outer] + [tuple(p) for p in inner]
    co = sum((Vector(p) for p in outer), Vector()) / n; ci = sum((Vector(p) for p in inner), Vector()) / n
    vs += [tuple(co), tuple(ci)]
    fs = [(k, (k + 1) % n, n + (k + 1) % n, n + k) for k in range(n)]
    fs += [(2 * n, (k + 1) % n, k) for k in range(n)] + [(2 * n + 1, n + k, n + (k + 1) % n) for k in range(n)]
    ob = cb_mesh(K, name, vs, fs, mat, smooth=False); ob.hide_render = True
    if cap is not None:
        ob.data.materials.append(cap)
        for f in ob.data.polygons:
            f.material_index = 1 if len(f.vertices) == 3 else 0
    return ob


def cb_loft(K, mat):
    """The diesel car's body loft, unchanged (passat.py build_diesel_car): traced profile, sections, nose and tail
    rounds, end grids."""
    def cat(points, steps=8):
        pts = [Vector(p) for p in points]; out = []
        for i in range(len(pts) - 1):
            a = pts[max(0, i - 1)]; b = pts[i]; c = pts[i + 1]; d = pts[min(len(pts) - 1, i + 2)]
            for j in range(steps):
                t = j / steps; out.append(.5 * (2 * b + (-a + c) * t + (2 * a - 5 * b + 4 * c - d) * t * t + (-a + 3 * b - 3 * c + d) * t * t * t))
        return out + [pts[-1]]
    profile_trace = [(60, 413), (100, 409), (180, 392), (300, 372), (430, 354), (482, 341), (545, 300), (625, 254), (704, 225), (800, 204),
                     (905, 191), (1020, 187), (1130, 194), (1230, 213), (1320, 245), (1400, 279), (1490, 313), (1580, 319), (1660, 327),
                     (1687, 347), (1700, 392)]
    sections = []
    for px, py in profile_trace:
        y, crown = cb_trace(px, py)
        belt = 1.23 if y < 2.70 else 1.20 - (y - 2.70) * .07
        belt = min(belt, crown - .095)
        width = 1.19 - .075 * (abs(y - .5) / 3.3) ** 3
        cabin = max(0, min(1, (crown - 1.28) / .42))
        rw = 1.00 - .11 * cabin
        edge = crown - (.060 if cabin > .5 else (.030 if px <= 60 else .043 if px <= 100 else .085))
        sections.append((y, width, belt, rw, edge, crown))
    sections.insert(0, (-2.52, 1.13, .92, .98, .99, 1.02))
    sections.append((3.43, 1.01, .92, .87, .99, 1.06))

    def nose_round(x, z):
        a = abs(x)
        plan = .012 * (a / .33) ** 2 if a <= .33 else .012 + .86 - math.sqrt(max(.00001, .86 ** 2 - (min(a, 1.189) - .33) ** 2))
        return plan + .06 * ((z - .70) / .65) ** 2

    def tail_round(x, z):
        return .15 * (abs(x) / 1.19) ** 4 + .04 * ((z - .70) / .48) ** 2
    dense = cat(sections, 7); vs = []; rings = []
    for y, w, belt, rw, edge, crown in dense:
        rear_t = max(0, min(1, (y - 2.60) / .83)); rear_t = rear_t * rear_t * (3 - 2 * rear_t)
        front_t = max(0, min(1, (-1.90 - y) / .62))
        bottom = .23 + .20 * rear_t + .035 * front_t
        profile = [(0, bottom), (.80 * w, bottom), (.94 * w, bottom + .045), (.985 * w, max(.36, bottom + .10)), (w, .72), (.998 * w, belt - .12),
                   (.985 * w, belt - .025), (.960 * w, belt + .006), (rw + .035, max(belt + .010, edge - .045)), (rw, edge), (.72 * rw, crown - .010), (0, crown)]
        pp = [Vector(p) for p in profile]; half = [pp[0]]
        for k in range(1, len(pp) - 1):
            a = pp[k].lerp(pp[k - 1], .32); b = pp[k].lerp(pp[k + 1], .32); last = half[-1]
            for j in range(1, 6):
                half.append(last.lerp(a, j / 5))
            for j in range(1, 7):
                t = j / 6; half.append((1 - t) ** 2 * a + 2 * t * (1 - t) * pp[k] + t * t * b)
        last = half[-1]
        for j in range(1, 7):
            half.append(last.lerp(pp[-1], j / 6))
        full = half + [Vector((-p.x, p.y)) for p in reversed(half[1:-1])]
        ring = []
        for x, z in full:
            nose = max(0, min(1, (-1.62 - y) / .9)); tail = max(0, min(1, (y - 2.75) / .68))
            yy = y + nose_round(x, z) * nose - tail_round(x, z) * tail
            ring.append(len(vs)); vs.append((x, yy, z))
        rings.append(ring)
    fs = []; N = len(rings[0])
    for a, b in zip(rings, rings[1:]):
        for i in range(N):
            j = (i + 1) % N; fs.append((a[i], a[j], b[j], b[i]))
    for endpoint, yy in ((0, -2.52), (-1, 3.43)):
        boundary = rings[endpoint]; cz = .53 if endpoint == 0 else .72
        center = Vector((0, yy + (nose_round(0, cz) if endpoint == 0 else -tail_round(0, cz)), cz)); prev = None; center_id = len(vs); vs.append(tuple(center))
        for j in range(1, 29):
            current = []
            for idx in boundary:
                q = center.lerp(Vector(vs[idx]), j / 28)
                if endpoint == 0:
                    q.y = yy + nose_round(q.x, q.z)
                else:
                    q.y = yy - tail_round(q.x, q.z)
                if j == 28:
                    current.append(idx)
                else:
                    current.append(len(vs)); vs.append(tuple(q))
            for i in range(N):
                k = (i + 1) % N
                if prev is None:
                    fs.append((center_id, current[k], current[i]))
                else:
                    fs.append((prev[i], prev[k], current[k], current[i]))
            prev = current
    return cb_mesh(K, 'body_shell', vs, fs, mat)


def cb_cavity(objs, sun, cavity, inside=('cb_primer',), occluded=0.7, smooth=3):
    """Inside faces deep in the hollow take the cavity tone: of 24 rays spread over the hemisphere above a face, more than
    `occluded` of them hit the body. Faces near an opening see out and stay grey. A few majority passes over each
    face's neighbours keep the boundary from stair-stepping along the mesh."""
    from mathutils.bvhtree import BVHTree
    verts, faces = [], []
    for ob in objs:
        mw = ob.matrix_world; off = len(verts)
        verts += [mw @ v.co for v in ob.data.vertices]; faces += [tuple(off + i for i in p.vertices) for p in ob.data.polygons]
    tree = BVHTree.FromPolygons(verts, faces); count = 0
    dirs = []
    for k in range(24):                          # a fixed spiral over the unit hemisphere about +Z
        z = 1 - (k + 0.5) / 24; r = math.sqrt(1 - z * z); a = k * 2.399963
        dirs.append(Vector((r * math.cos(a), r * math.sin(a), z)))
    for ob in objs:
        me = ob.data; mw = ob.matrix_world; nm = mw.to_3x3()
        names = [m.name if m else '' for m in me.materials]
        if cavity.name not in names:
            me.materials.append(cavity); names.append(cavity.name)
        ci = names.index(cavity.name); targets = {k for k, n in enumerate(names) if n in inside}
        dark = {}
        for p in me.polygons:
            if p.material_index not in targets:
                continue
            c = mw @ p.center; n = (nm @ p.normal).normalized(); rot = Vector((0, 0, 1)).rotation_difference(n)
            hits = sum(tree.ray_cast(c + n * 0.004, rot @ d, 30.0)[0] is not None for d in dirs)
            dark[p.index] = hits / len(dirs) > occluded
        if smooth:
            bm = bmesh.new(); bm.from_mesh(me); bm.faces.ensure_lookup_table()
            nb = {f.index: {g.index for e in f.edges for g in e.link_faces if g.index != f.index and g.index in dark} for f in bm.faces if f.index in dark}
            bm.free()
            for _ in range(smooth):
                dark = {i: (sum(dark[j] for j in nb[i]) + dark[i]) * 2 > len(nb[i]) + 1 for i in dark}
        for i, d in dark.items():
            if d:
                me.polygons[i].material_index = ci; count += 1
    return count


def cb_trace(px, py):
    """The owner's supplied Passat profile, sampled in image pixels; the axle centres set the scale."""
    s = 3.69 / (1390 - 325)
    return (-1.40 + (px - 325) * s, (710 - py) * s)


def cb_outline(points, rounding=.08):
    pts = [Vector(p) for p in points]; edge = []
    for i, p in enumerate(pts):
        a = p + (pts[i - 1] - p) * rounding; b = p + (pts[(i + 1) % len(pts)] - p) * rounding
        for j in range(8):
            t = j / 8; edge.append((1 - t) ** 2 * a + 2 * t * (1 - t) * p + t * t * b)
    if rounding == 0:
        edge = pts
    dense = []
    for a, b in zip(edge, edge[1:] + edge[:1]):
        n = max(1, int((b - a).length / .025) + 1)
        for k in range(n):
            dense.append(a + (b - a) * k / n)
    return dense


# review of v10: the cab read as a slatted box. A lorry cab stands on legs (a big round arch cut high into a tall skirt,
# the wheel centre at a lorry wheel's height), wears its bumper as a separate step forward, and carries a narrow
# tapered deflector off the windscreen header
# owner on v11: "sweep back a bit the top of the front of the lorry cab compared to the bottom" (the front leans back
# on a curve, more toward the top), "the headlight sockets need to be higher, wider and a bit angled on the inside",
# "the door needs work", "the top of the cab also needs work". On v13: "the headlamps need to be angled the other way
# (narrower at the top). Also they need a radiator slot between them. And look at the old icon's cab for reference on
# height". The shipped cab stands about 1.2x as tall as it is wide (it was 1.0 here, which squeezed the door between its
# window and the arch), and 0.86x as deep as wide
# v15 (owner: "make the door's bottom match the shape on the old icon please. And bring the cab closer to the car body"):
# the door's bottom follows the wheel arch, high behind and sweeping down to the steps; the cab stands in by the car
CAB = dict(at=(2.75, 1.40), scale=1.12, hx=1.0, hy=1.15, z=(0.25, 2.95), corner=0.24, fillet=0.20, rake=0.34, rake_power=1.7,
           arch=dict(x=-0.30, z=0.58, r=0.60),
           door=dict(rear=-0.52, top=2.76, front_gap=0.26, r=0.10, arch_margin=0.14, front_bottom=1.02),
           window=dict(rear=-0.40, bottom=1.98, top=2.64, front_gap=0.36, r=0.09),
           handle=dict(x=(-0.40, -0.20), z=(1.82, 1.89)),
           steps=((0.40, 0.58), (0.78, 0.96)), step_x=(0.38, 0.72),
           bumper=dict(x=(0.80, 1.12), y=1.12, z=(0.30, 1.00), pocket=0.08),
           # (y, z) on the bumper face: outer bottom, outer top, inner top, inner bottom (the inner edge leans in)
           # v17 (owner: "smaller headlamp cutouts (20% less tall and 30% narrower). Then the radiator cutout in the middle can
           # widen at the top to have parallel sides to the headlamp cutouts"): lamps scaled about their outer edge; the
           # radiator's sides run parallel to the lamps' inner edges at a constant gap
           lamp=((1.00, 0.653), (1.00, 0.917), (0.692, 0.917), (0.594, 0.653)), radiator=dict(gap=0.10, z=(0.58, 0.94)),
           roof=dict(front=0.40, rear=-0.90, base=2.87, half=(0.90, 0.66), rise=(0.04, 0.46), rise_end=0.55, r=0.13))


def cab_front_x(z):
    """Where the raked cab front stands at height z (before the cab is placed)."""
    C = CAB; z0, z1 = C['z']
    return C['hx'] - C['rake'] * max(0.0, min(1.0, (z - z0) / (z1 - z0))) ** C['rake_power']


def cb_rslab(K, name, cx, cy, hx, hy, z0, z1, rc, rt, mat, steps=5):
    """A closed rounded-rectangle slab (corner radius rc in plan) with its top edge filleted by rt."""
    def rrect(ax, ay, r, n=8):
        pts = []
        for ccx, ccy, a0 in ((ax - r, ay - r, 0), (-ax + r, ay - r, 90), (-ax + r, -ay + r, 180), (ax - r, -ay + r, 270)):
            for k in range(n + 1):
                a = math.radians(a0 + 90 * k / n); pts.append((ccx + r * math.cos(a), ccy + r * math.sin(a)))
        return pts
    levels = [(z0, 0.0)] + [(z0 + (z1 - rt - z0) * k / 14, 0.0) for k in range(1, 15)] + \
             [(z1 - rt + rt * math.sin(math.radians(90 * k / steps)), rt * (1 - math.cos(math.radians(90 * k / steps)))) for k in range(1, steps + 1)]
    rings = [[(cx + x, cy + y, z) for x, y in rrect(hx - d, hy - d, max(rc - d, 0.01))] for z, d in levels]
    m = len(rings[0]); vs = [v for ring in rings for v in ring]
    fs = [tuple(reversed(range(m))), tuple(range((len(rings) - 1) * m, len(rings) * m))]
    for i in range(len(rings) - 1):
        fs += [(i * m + k, i * m + (k + 1) % m, (i + 1) * m + (k + 1) % m, (i + 1) * m + k) for k in range(m)]
    return cb_mesh(K, name, vs, fs, mat, smooth=True)


def cb_cab(K, mats):
    """The lorry cab: a European cab-over's body shell, front to +X (square to the car, as shipped), on the same
    construction as the car: a closed rounded body, raked at the front, cut open (windscreen, grille, door windows)
    with return flanges, entry-step pockets and a high front wheel arch kept as liners, hollowed to a skin with a grey
    inside, a floor and a dash inside it, a bumper stepped forward with its lamp and grille openings, and a tapered roof
    deflector. Returns the solids' names (shell first)."""
    C = CAB; ax, ay = C['at']; z0, z1 = C['z']
    cab = cb_rslab(K, 'cab_shell', 0, 0, C['hx'], C['hy'], z0, z1, C['corner'], C['fillet'], mats['cab'])
    for v in cab.data.vertices:                  # rake the front: the windscreen leans back toward the roof
        if v.co.x > 0:
            v.co.x -= C['rake'] * ((v.co.z - z0) / (z1 - z0)) ** C['rake_power'] * (v.co.x / C['hx'])
    cab.data.update(); bpy.context.view_layer.update()
    solid = cab.copy(); solid.data = cab.data.copy(); solid.name = 'cab_solid_tool'; K.col.objects.link(solid); solid.hide_render = True

    def hit(o, d, lift=0.0):
        ok, loc, n, i = cab.ray_cast(Vector(o), Vector(d)); assert ok, ('cab miss', o, d)
        return loc + n.normalized() * lift

    def front(y, z):
        return hit((5, y, z), (-1, 0, 0))

    def flank(sign, x, z, lift=0.0):
        return hit((x, sign * 5, z), (0, -sign, 0), lift)

    def rr(u0, u1, v0, v1, r):
        return cb_outline([(u0, v0), (u1, v0), (u1, v1), (u0, v1)], r)

    def cutter(name, pts, at, out, target_mats=None):
        o = [at(*p) + out * 0.12 for p in pts]; i = [at(*p) - out * (SKIN + FLANGE) for p in pts]
        return cb_prism(K, name, o, i, mats['flange'], mats['cut'])
    cut = [cutter('cab_cut_windscreen', rr(-.86, .86, 1.74, 2.70, .10), front, Vector((1, 0, 0))),
           cutter('cab_cut_grille', rr(-.66, .66, 1.16, 1.52, .14), front, Vector((1, 0, 0)))]
    for s in (-1, 1):
        W = C['window']
        win = cb_outline([(W['rear'], W['bottom']), (cab_front_x(W['bottom']) - W['front_gap'], W['bottom']),
                          (cab_front_x(W['top']) - W['front_gap'], W['top']), (W['rear'], W['top'])], W['r'])
        cut.append(cutter('cab_cut_window_%+d' % s, win, lambda x, z, s=s: flank(s, x, z), Vector((0, s, 0))))
    pockets = []
    for k, (za, zb) in enumerate(C['steps']):    # entry steps under the near door, clear of the arch and the corner
        pts = [flank(-1, x, z) for x, z in rr(C['step_x'][0], C['step_x'][1], za, zb, .1)]
        pockets.append(cb_prism(K, 'cab_step_%d' % k, [p + Vector((0, -0.12, 0)) for p in pts], [p + Vector((0, 0.22, 0)) for p in pts], mats['liner']))
    A = C['arch']
    for s in (-1, 1):
        pockets.append(noink(K.cyl('cab_arch_%+d' % s, A['x'], s * (C['hy'] - 0.15), A['z'], A['r'], 0.6, mats['liner'], axis='Y', segments=96, smooth=True)))
    for p in pockets:
        p.hide_render = True
    # the door's shut line, a closed loop lifted along the panel's own normal so it stays outside over the fillets
    # the door: its rear edge upright, its bottom following the wheel arch at a margin (high behind, sweeping down and
    # forward over the arch) until it meets the sill just above the steps, then forward to the front edge, which leans
    # back with the raked front
    Dd = C['door']; Ra = A['r'] + Dd['arch_margin']; fb = Dd['front_bottom']
    def over_arch(x):
        return A['z'] + math.sqrt(max(0.0, Ra * Ra - (x - A['x']) ** 2))
    x_end = A['x'] + math.sqrt(max(0.0, Ra * Ra - (fb - A['z']) ** 2))
    bottom = [(Dd['rear'] + (x_end - Dd['rear']) * k / 16, over_arch(Dd['rear'] + (x_end - Dd['rear']) * k / 16)) for k in range(17)]
    door_outline = cb_outline(bottom + [(cab_front_x(fb) - Dd['front_gap'], fb), (cab_front_x(Dd['top']) - Dd['front_gap'], Dd['top']),
                               (Dd['rear'], Dd['top'])], 0.05)
    door_path = [tuple(flank(-1, x, z, 0.006)) for x, z in door_outline]; door_path.append(door_path[0])
    # the door handle: a small pull recess under the window
    Hh = C['handle']; hp = [flank(-1, x, z) for x, z in rr(Hh['x'][0], Hh['x'][1], Hh['z'][0], Hh['z'][1], .3)]
    pockets.append(cb_prism(K, 'cab_handle', [p + Vector((0, -0.12, 0)) for p in hp], [p + Vector((0, 0.05, 0)) for p in hp], mats['liner']))
    pockets[-1].hide_render = True
    cab = cb_skin(cb_boolean(cab, cut + pockets), mats['primer'], mats['cab'])
    for o in cut + pockets:
        bpy.data.objects.remove(o, do_unlink=True)
    # the cab floor and the dash, clipped to the inside of the closed body
    inner = []
    for nm, box in (('cab_floor', (-1.4, 1.4, -1.5, 1.5, 1.24, 1.29)), ('cab_dash', (0.60, 0.80, -1.5, 1.5, 1.29, 1.70))):
        b = en_box_cb(K, nm + '_box', *box, mats['primer']); b.hide_render = True
        w = solid.copy(); w.data = solid.data.copy(); w.name = nm; K.col.objects.link(w); w.hide_render = False
        w = cb_boolean(w, [b], 'INTERSECT'); bpy.data.objects.remove(b, do_unlink=True)
        me = w.data; paint = [k for k, m in enumerate(me.materials) if m and m.name == 'cb_cab']
        bm = bmesh.new(); bm.from_mesh(me)
        bmesh.ops.delete(bm, geom=[f for f in bm.faces if f.material_index in paint], context='FACES'); bm.to_mesh(me); bm.free()
        me.materials.clear(); me.materials.append(mats['primer'])
        for f in me.polygons:
            f.material_index = 0
        w['part_label'] = L_INNER; inner.append(w)
    bpy.data.objects.remove(solid, do_unlink=True)
    # the bumper: a rounded block stepped forward of the cab front below the grille, its lamp and lower-grille openings
    # cut as pockets, dark inside (owner on v15: "make the headlight holes dark inside and the same for the radiator hole")
    Bm = C['bumper']
    bump = cb_rslab(K, 'cab_bumper', (Bm['x'][0] + Bm['x'][1]) / 2, 0, (Bm['x'][1] - Bm['x'][0]) / 2, Bm['y'], Bm['z'][0], Bm['z'][1], 0.16, 0.05, mats['cab'])
    bpy.context.view_layer.update()

    def bfront(y, z):
        ok, loc, n, i = bump.ray_cast(Vector((5, y, z)), Vector((-1, 0, 0))); assert ok, ('bumper miss', y, z)
        return loc
    (_, _), (_, _), (ty_, tz_), (by_, bz_) = C['lamp']; Rd = C['radiator']
    def inner_edge(z):                           # the lamp's inner edge, extended
        return by_ + (ty_ - by_) * (z - bz_) / (tz_ - bz_)
    rz0, rz1 = Rd['z']; yb_, yt_ = inner_edge(rz0) - Rd['gap'], inner_edge(rz1) - Rd['gap']
    rad = cb_outline([(-yb_, rz0), (yb_, rz0), (yt_, rz1), (-yt_, rz1)], .14)
    bcut = [cb_prism(K, 'bump_cut_grille', [bfront(*p) + Vector((0.1, 0, 0)) for p in rad],
                     [bfront(*p) - Vector((Bm['pocket'], 0, 0)) for p in rad], mats['liner'])]
    for s in (-1, 1):
        lamp = [(s * y, z) for y, z in C['lamp']]
        pts = cb_outline(lamp if s > 0 else lamp[::-1], .14)
        bcut.append(cb_prism(K, 'bump_cut_lamp_%+d' % s, [bfront(*p) + Vector((0.1, 0, 0)) for p in pts], [bfront(*p) - Vector((Bm['pocket'], 0, 0)) for p in pts], mats['liner']))
    for c in bcut:
        c.hide_render = True
    bump = cb_boolean(bump, bcut)
    for c in bcut:
        bpy.data.objects.remove(c, do_unlink=True)
    bump['part_label'] = L_BUMPER
    # the roof: a smooth fairing that springs from the windscreen header, rises over the front third and runs flat to
    # the back of the cab, narrower at its crown than at its base, every corner rounded
    Rf = C['roof']; rings = []; n = 30
    for k in range(n + 1):
        t = k / n; x = Rf['front'] + (Rf['rear'] - Rf['front']) * t
        u = min(1.0, t / Rf['rise_end']); h = Rf['rise'][0] + (Rf['rise'][1] - Rf['rise'][0]) * (u * u * (3 - 2 * u))
        top = Rf['base'] + h; hb, ht = Rf['half']; ht = hb - (hb - ht) * (h / Rf['rise'][1]); r = min(Rf['r'], h * 0.6)
        prof = [(-hb, Rf['base']), (hb, Rf['base'])]
        for q in range(6):                       # right top corner, side to top
            a = math.radians(90 * q / 5); prof.append((ht - r + r * math.cos(a), top - r + r * math.sin(a)))
        for q in range(6):                       # left top corner, top to side
            a = math.radians(90 + 90 * q / 5); prof.append((-ht + r + r * math.cos(a), top - r + r * math.sin(a)))
        rings.append([(x, y, z) for y, z in prof])
    m = len(rings[0]); vs = [v for r_ in rings for v in r_]
    fs = [tuple(reversed(range(m))), tuple(range(n * m, (n + 1) * m))]
    for k in range(n):
        fs += [(k * m + j, (k + 1) * m + j, (k + 1) * m + (j + 1) % m, k * m + (j + 1) % m) for j in range(m)]
    defl = cb_mesh(K, 'cab_deflector', vs, fs, mats['cab'], smooth=True); defl['part_label'] = L_DEFLECTOR
    # place the cab beside the car, scaled about its foot (the shipped cab stands well above the car)
    place = Matrix.Translation((ax, ay, 0)) @ Matrix.Scale(C['scale'], 4)
    for ob in [cab, defl, bump] + inner:
        ob.data.transform(place); ob.data.update()
    cab['part_label'] = L_CAB
    tagged_line(K, 'cab_door_seam', [tuple(place @ Vector(p)) for p in door_path], L_CAB, PL_INNER, False)['ink_width'] = 0
    return [cab.name, defl.name, bump.name] + [w.name for w in inner]


def en_prism_cb(K, name, profile, y0, y1, mat):
    """A closed (x, z) profile extruded along Y."""
    n = len(profile); vs = [(x, y0, z) for x, z in profile] + [(x, y1, z) for x, z in profile]
    fs = [tuple(reversed(range(n))), tuple(range(n, 2 * n))] + [(k, (k + 1) % n, n + (k + 1) % n, n + k) for k in range(n)]
    return cb_mesh(K, name, vs, fs, mat, smooth=False)


def build_car_body():
    setup_icon_rig(); K = Kit(open_collection('ICON_car_body'))
    mats = {k: pl_toon('cb_' + k, *v) for k, v in TONES.items()}
    shell = cb_loft(K, mats['body']); shell['part_label'] = L_SHELL
    # a copy of the closed body: the bulkheads are clipped to it, and the faces that land on its painted surface are
    # dropped, so each bulkhead ends inside the skin
    inner = shell.copy(); inner.data = shell.data.copy(); inner.name = 'inner_tool'; K.col.objects.link(inner); inner.hide_render = True
    # wheel arches: a short cutter each side; its walls stay as the wheelhouse liners (primer, kept), so the floor
    # and the engine bay stay closed between them
    arches = [K.cyl('arch_tool_%d_%+d' % (i, s), s * 1.12, y, .43, .452, .64, mats['liner'], axis='X', segments=96, smooth=True)
              for i, y in enumerate((-1.40, 2.29)) for s in (-1, 1)]
    for a in arches:
        noink(a); a.hide_render = True
    bpy.context.view_layer.update()

    def ray(origin, direction):
        hit, loc, nrm, idx = shell.ray_cast(Vector(origin), Vector(direction))
        return (loc, nrm) if hit else (None, None)

    def project(q, axis, offset=0.0):
        """The diesel car's projection of a 2D outline point onto the painted surface, moved `offset` back out along
        the ray (negative goes in through the skin)."""
        if axis == 'FRONT':
            q = (q[0], q[1] * .84)
        o, d = {'Z': ((q[0], q[1], 4), (0, 0, -1)), 'X': ((3, q[0], q[1]), (-1, 0, 0)), 'XN': ((-3, q[0], q[1]), (1, 0, 0)),
                'BACK': ((q[0], 5, q[1]), (0, -1, 0)), 'FRONT': ((q[0], -5, q[1]), (0, 1, 0))}[axis]
        loc, _ = ray(o, d); assert loc is not None, ('surface miss', axis, tuple(q))
        return loc - Vector(d) * offset

    def aperture(name, points, axis, rounding):
        # the cutter reaches FLANGE past the skin; its walls stay as the opening's return flange, its caps are dropped
        edge = cb_outline(points, rounding)
        return cb_prism(K, name, [project(p, axis, 0.12) for p in edge], [project(p, axis, -(SKIN + FLANGE)) for p in edge],
                        mats['flange'], mats['cut'])

    # the apertures, along the diesel car's glass, lamp and radiator outlines (the bumper's own pockets are not body)
    cut = []
    windscreen = [(.96 * x, -.82 - .28 * (1 - (x / .965) ** 2)) for x in (-.965 + 1.93 * i / 64 for i in range(65))] + \
                 [(.96 * x, y) for x, y in ((.78, .23), (.72, .285), (0, .315), (-.72, .285), (-.78, .23))]
    cut.append(aperture('cut_windscreen', windscreen, 'Z', .035))
    cut.append(aperture('cut_rear_screen', [(-.79, 1.86), (.79, 1.86), (.85, 2.60), (-.85, 2.60)], 'Z', .10))
    side = [('front_door', [(531, 367), (932, 351), (941, 222), (835, 228), (750, 248), (660, 289)], .12),
            ('rear_door', [(966, 349), (1255, 337), (1230, 257), (1120, 233), (966, 221)], .12),
            ('quarter', [(1290, 337), (1380, 334), (1371, 302), (1280, 267)], .17)]
    for nm, pts, r in side:
        for ax in ('X', 'XN'):
            cut.append(aperture('cut_%s_%s' % (nm, ax), [cb_trace(*p) for p in pts], ax, r))
    for ax in ('X', 'XN'):
        cut.append(aperture('cut_tail_lamp_' + ax, [(3.12, 1.10), (3.23, 1.025), (3.30, .76), (3.17, .79)], ax, .08))
    grille = [(-.54, 1.0714), (-.27, 1.067), (0, 1.065), (.27, 1.067), (.54, 1.0714), (.455, .85), (.39, .812), (.30, .81), (-.30, .81),
              (-.39, .812), (-.455, .85)]
    cut.append(aperture('cut_radiator', grille, 'FRONT', .035))
    for s in (-1, 1):
        lamp = [(s * x, z) for x, z in ((.60, 1.06), (.98, 1.07), (1.00, .86), (.62, .86))]
        cut.append(aperture('cut_headlamp_%+d' % s, lamp, 'FRONT', .22))
    # the bonnet: its outline in plan follows the diesel car's bonnet seams (fender seams down each side, the cowl
    # under the windscreen at the back, the radiator brow and lamp tops at the front); a slab hugging that patch of
    # skin cuts it free
    COWL = 0.10                                  # the cowl panel between the bonnet's back edge and the windscreen
    rear = lambda x: -.82 - COWL - .28 * (1 - (x / .965) ** 2)
    cowl = [(x, rear(x)) for x in (.965 - 1.93 * i / 24 for i in range(25))]
    side_r = [(1.04, -1.95), (1.045, -1.55), (1.00, -1.08)]
    front = []                                   # just inside the bonnet lip, traced off the nose at lip height
    for x in [(-.98 + 1.96 * k / 14) for k in range(15)]:
        loc, _ = ray((x, -5, 0.98), (0, 1, 0)); front.append((x, loc.y + 0.06))
    plan = cb_outline(front[7:] + side_r + cowl + [(-x, y) for x, y in reversed(side_r)] + front[:7], 0)
    slab = cb_prism(K, 'cut_bonnet', [project(p, 'Z', 0.12) for p in plan], [project(p, 'Z', -(SKIN + FLANGE)) for p in plan],
                    mats['flange'], mats['cut'])
    # points on the bonnet's skin that the stay and the hinges attach to, taken before the bonnet is cut out
    stay_tip_src = project((.62, -1.70), 'Z', -SKIN - FLANGE)
    lug_src = {s: project((s * HINGE_X, rear(HINGE_X) - 0.10), 'Z', -SKIN - 0.005) for s in (-1, 1)}
    hinge = project((HINGE_X, rear(HINGE_X) - 0.01), 'Z')
    cowl_base = {s: project((s * HINGE_X, rear(HINGE_X) + 0.04), 'Z', -0.01) for s in (-1, 1)}
    # cut every opening (and the bonnet) out of the closed body, then keep the painted skin and the cutters' walls as
    # return flanges; the bonnet is the same patch of skin intersected out of a copy. Each skin is then thickened inward.
    bonnet = shell.copy(); bonnet.data = shell.data.copy(); bonnet.name = 'bonnet'; K.col.objects.link(bonnet)
    bonnet = cb_skin(cb_boolean(bonnet, [slab], 'INTERSECT'), mats['primer']); bonnet['part_label'] = L_BONNET
    shell = cb_skin(cb_boolean(shell, arches + [slab] + cut), mats['primer']); shell['part_label'] = L_SHELL
    # review of v5: the bay, cabin and boot were one tub. A firewall under the cowl, the slam panel across the nose
    # (the stay's foot) and the parcel shelf under the rear screen, each clipped to the inside of the skin
    walls = []
    for nm, box in (('firewall', (-1.4, 1.4, rear(0) - 0.05, rear(0) - 0.01, 0.0, 1.6)),
                    ('slam_panel', (-1.4, 1.4, -2.38, -2.28, 0.80, 0.93)),
                    ('parcel_shelf', (-1.4, 1.4, 2.45, 2.85, 1.10, 1.14))):
        x0, x1, y0, y1, z0, z1 = box
        box = en_box_cb(K, nm + '_box', x0, x1, y0, y1, z0, z1, mats['primer']); box.hide_render = True
        w = inner.copy(); w.data = inner.data.copy(); w.name = nm; K.col.objects.link(w); w.hide_render = False
        w = cb_boolean(w, [box], 'INTERSECT'); bpy.data.objects.remove(box, do_unlink=True)
        me = w.data; skin_i = [k for k, m in enumerate(me.materials) if m and m.name == 'cb_body']
        bm = bmesh.new(); bm.from_mesh(me)
        bmesh.ops.delete(bm, geom=[f for f in bm.faces if f.material_index in skin_i], context='FACES'); bm.to_mesh(me); bm.free()
        w.data.materials.clear(); w.data.materials.append(mats['primer'])
        for f in w.data.polygons:
            f.material_index = 0
        w['part_label'] = L_INNER; walls.append(w.name)
    # owner on v3: "the bonnet would not open at that angle. the hinges would be closer to the corners". The hinge line
    # runs through the bonnet's rear corners (the cowl edge bows forward in the middle, so a hinge there swung the
    # corners down into the cowl), and it opens to a real bonnet's angle (owner: 65)
    hz = hinge.z; hy = hinge.y
    M = Matrix.Translation((0, hy, hz)) @ Matrix.Rotation(math.radians(-BONNET_OPEN), 4, 'X') @ Matrix.Translation((0, -hy, -hz))
    bonnet.data.transform(M); bonnet.data.update()
    # the stay: one line from the slam panel up to the bonnet's underside at half its length
    tagged_line(K, 'bonnet_stay', [(.62, -2.33, .935), tuple(M @ stay_tip_src)], L_STAY, PL_INNER, False)['ink_width'] = 0
    # a hinge bracket at each rear corner: a strap from the cowl up to the bonnet's underside
    for s in (-1, 1):
        br = noink(K.dirbox('bonnet_hinge_%+d' % s, cowl_base[s], M @ lug_src[s], 0.04, 0.05, mats['stay'])); br['part_label'] = L_STAY
    for o in arches + [slab, inner] + cut:
        bpy.data.objects.remove(o, do_unlink=True)
    # the door shut lines and the boot lid, as the diesel car draws them
    def seam(name, pts, axis):
        path = []
        for a, b in zip(pts, pts[1:]):
            a = Vector(a); b = Vector(b); n = max(2, int((a - b).length / .025))
            for i in range(n):
                path.append(project(a.lerp(b, i / n), axis, .004))
        path.append(project(pts[-1], axis, .004))
        tagged_line(K, name, [tuple(p) for p in path], L_SHELL, PL_INNER, False)['ink_width'] = 0
    seam('front_door_seam', [cb_trace(*p) for p in [(511, 376), (507, 460), (511, 579), (928, 579), (943, 357)]], 'X')
    seam('rear_door_seam', [cb_trace(*p) for p in [(928, 579), (1230, 579), (1260, 461), (1265, 350)]], 'X')
    seam('boot_lid_seam', [(-.85, 2.81), (-.83, 3.20), (.83, 3.20), (.85, 2.81)], 'Z')
    bpy.context.view_layer.update()
    # owner: "do make sure to first do the lorry cab body as part of the car body icon"
    cab_parts = cb_cab(K, mats)
    bpy.context.view_layer.update()
    # inside faces in the hollow's shadow take the cavity tone
    solids = [shell, bonnet] + [bpy.data.objects[n] for n in walls + cab_parts]
    dark = cb_cavity(solids, SUN_DIR, mats['cavity'])
    hosts = [shell.name, bonnet.name] + cab_parts + walls
    for n in hosts:
        # the shell's longer minimum drops short interior stubs
        pl_mesh_lines(K, bpy.data.objects[n], bpy.data.objects[n]['part_label'], 40.0, n, 0.06 if n == shell.name else 0.02)
    for ob in K.col.objects:
        if ob.get('ink_width') == 6:
            ob['ink_width'] = PL_INNER
    info = contract(K, [shell.name, bonnet.name, cab_parts[0]], 'the diesel car\'s Passat sedan as a bare painted body shell: hollow skin with a grey '
                    'inside and a dark cavity, open window, screen, lamp and radiator apertures with return flanges, a firewall, slam '
                    'panel and parcel shelf, the bonnet cut free, hinged at its rear corners and propped open on a stay; beside it a blue '
                    'cab-over lorry cab shell, open windscreen, grille, lamps and door windows, steps, wheel arch and roof deflector',
                    inner=PL_INNER)
    info['revision'] = CB_REVISION; info['outline']['component_boundaries'] = True
    info['stipple']['strength'] = 0.38
    info['stipple']['groups'] = [{'name': 'shaded_faces', 'labels': [L_SHELL, L_BONNET, L_STAY, L_INNER, L_CAB, L_DEFLECTOR, L_BUMPER], 'thresholds': [0.575, 0.50, 0.30]}]
    info['dimensions'] = {'skin': SKIN, 'flange': FLANGE, 'cowl': COWL, 'bonnet_open_deg': BONNET_OPEN, 'hinge_x': HINGE_X, 'cavity_faces': dark}
    return info


def en_box_cb(K, name, x0, x1, y0, y1, z0, z1, mat):
    bm = bmesh.new(); bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co = Vector((x0 if v.co.x < 0 else x1, y0 if v.co.y < 0 else y1, z0 if v.co.z < 0 else z1))
    me = bpy.data.meshes.new(name); bm.to_mesh(me); bm.free()
    return noink(K.obj(name, me, mat, False))
