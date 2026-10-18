"""Petroleum coke (g_075 pet_coke). The shipped art: three long faceted lumps, a hero lying along the view's falling
diagonal (world X), its far-left end raised on a second lump behind it, and a third in front. Real needle and sponge coke
is a dull grey-black solid with a streaked, flow-like grain, so the lumps split along their length into long parallel
facets. Each lump is a prism of a fluted section whose facets are coloured by role (broad taupe, narrow dark grey,
broken faces slate), tapered homothetically so every facet stays flat, its ends broken by a few planes and its long
edges notched. The hero stands on its wide chipped foot and is lowered until it rests on the left chunk; the front
chunk is pushed clear of both. On the set's grid, camera, light, 12/4 px ink and dots on the shaded sides."""
import random
PC_REVISION = 'pet_coke_v29'
LIGHT = Vector((0.06, -0.56, 0.83)).normalized()
# the shipped art's hue shift: warm taupe on the lit facets, neutral grey in the mid step, slate blue in the shade
# v5: facets coloured by ROLE, as the shipped art paints them (v3/v4's light alone left the whole top one taupe):
# broad facets taupe, narrow (groove) facets dark grey, broken ends slate; all go slate blue in the shade step
COKE = {'broad': ((60, 72, 90), (112, 104, 98), (126, 118, 110)), 'groove': ((48, 56, 70), (72, 70, 74), (82, 80, 84)),
        'end': ((50, 60, 76), (62, 74, 92), (70, 82, 100))}
COKE_STEPS = (0.62, 0.86)
# v3: the shipped art's ridges are flat FACETS, not notches (v2's V grooves inked as tangled slivers): a fluted prism
# whose section alternates ridge points (radius 1) and valley points (radius `valley`) set `skew` of the way to the
# next ridge, so a broad facet leans toward the light (lit) and a narrow one away (dark). Tapered at the ends.
# v4: deeper valleys, steeper narrow facets (v3's all lit one tone)
# v6: ridges packed on the top and front (8 between 15 and 200 deg) where they show, 4 round the back and bottom
# (v5 had two broad facets on the whole top); ends rounded by a two-step taper, not spiky multi-cuts
# v10: five broad strips on the top and front, not eight thin ones (v9 read as corduroy)
SEC = dict(ridges_front=5, arc=(20.0, 200.0), ridges_back=3, rx=0.50, rz=0.46, valley=(0.90, 0.94), skew=(0.55, 0.66), jitter=0.04,   # v9: shallow flutes; the strips come from the role colours
           # v9: a gentle taper and plain broken ends (v8's domes zipped the flutes into starbursts)
           # v12: rounded ends by a stepped taper (homothetic rings, so the facets stay flat; the steep joints near the
           # tips ink as the shipped art's end chamfers), and a slight bulge in the middle so the sides are not ruled
           taper=((0.0, 0.55), (0.02, 0.72), (0.05, 0.84), (0.09, 0.92), (0.15, 0.97), (0.24, 1.0), (0.5, 1.04),
                  (0.76, 1.0), (0.85, 0.97), (0.91, 0.92), (0.95, 0.84), (0.98, 0.72), (1.0, 0.58)))
# (centre x, y, width, height, length, yaw deg, lift deg, seed, label)
# v5: fatter (length ~2x width, as shipped; v4's read as pencils) and nestled closer
# v13 (owner: "The hero needs to be longer, uneven at the end and should have a wider and more jagged/multifaceted
# bottom"): 2.85 long. v14: the shipped hero widens toward its lower (+X) end, so its taper runs 0.72 at the raised top
# to 1.22 at the foot (one homothetic scale per ring keeps the facets flat); the raised top is broken unevenly in three
# steps and the wide foot in five facets. Cuts: (depth back from the end, across, up), normal (along, across, up)
HERO_RAGGED = {1: [((0.04, 0.00, -0.3), (1.0, 0.10, -0.75)), ((0.10, -0.35, 0.6), (1.0, -0.85, 0.90)),
                   ((0.06, 0.40, 0.5), (1.0, 0.90, 0.55)), ((0.20, 0.05, 0.95), (0.8, 0.10, 1.30)),
                   ((0.02, -0.25, -0.6), (1.0, -0.60, -0.70))],
               -1: [((0.05, -0.15, 0.1), (1.0, 0.35, 0.25)), ((0.30, 0.20, 0.9), (1.0, 0.30, 1.2)),
                    ((0.14, -0.40, -0.5), (1.0, -0.70, -0.45)),
                    ((0.45, 0.32, 0.55), (1.0, 0.75, 0.95))]}     # v15: a deep corner break, so the top end is uneven
# v15: chips knocked off round the foot's rim, so its end reads jagged and many-faceted: (rim angle deg across/up,
# depth back from the end, how far out on the section, normal tilt toward the rim)
FOOT_CHIPS = [(205, 0.10, 0.80, 1.1), (250, 0.18, 0.78, 0.8), (300, 0.08, 0.84, 1.3), (340, 0.14, 0.80, 0.9),
              (20, 0.06, 0.86, 1.4), (150, 0.12, 0.82, 1.0), (110, 0.20, 0.80, 0.7)]
HERO_TAPER = ((0.0, 0.62), (0.03, 0.72), (0.08, 0.80), (0.18, 0.86), (0.50, 1.0), (0.80, 1.14), (0.92, 1.22), (1.0, 1.20))
# v16: thicker (the shipped hero shows a tall slate front wall and a dotted back shoulder), rolled further to show the
# wall, and arched (rings lifted along a sine, a translation only, so facets stay flat) for a convex back
# v26 (owner: "make the hero 15% shorter but not narrower. And make the sides of the hero a bit more jagged"): L 2.85 ->
# 2.42; notches knocked out along both long silhouette edges (frac along, rim angle deg, length, depth)
HERO_SIDE_CHIPS = [(0.22, 48, 0.40, 0.16), (0.47, 38, 0.30, 0.13), (0.70, 55, 0.44, 0.17), (0.88, 42, 0.30, 0.12),
                   (0.30, 228, 0.38, 0.16), (0.55, 218, 0.32, 0.14), (0.78, 235, 0.42, 0.17)]   # (chips at 176-194 deg land on the visible face and ink as X marks, not on the outline)
LUMPS = {'long_hero': dict(c=(0.25, 0.30), w=1.32, h=1.26, L=2.42, side_chips=HERO_SIDE_CHIPS, yaw=0.0, lift=34.0, seed=3, label=1, arch=0.05,   # v18: less arch
                              foot=(1.10, 0.28), rest_on=dict(range=(4.0, 60.0)),   # v22: stands on its foot, lowered onto the left chunk; v23: foot nearer, so it rests steeper
                              # v17: a negative roll tips the top back (+Y), showing the front wall (v10-v16 tipped it forward)
                              roll=-12.0, bed=False, ragged=HERO_RAGGED, taper=HERO_TAPER, foot_chips=FOOT_CHIPS,
                              bottom=dict(widen=1.0, ridges=5, jitter=0.08, valley=(0.84, 0.92), front=7, arc=(20.0, 235.0))),   # v21 (owner: "the left side is a regression. we want the ridges still on that side"): no wall; the ridges run on round the front   # v8: steeper, taller; v10: rolled to show its front side
         # v29 (owner: "refine the two supporting chunks to match"): the hero's ridges round the front, ragged ends,
         # notched long edges, uneven taper, no flat bed
         'left_chunk': dict(c=(-0.40, -0.30), w=1.10, h=1.06, L=1.55, yaw=95.0, lift=0.0, seed=7, label=2, ragged='auto', bed=False,
                            taper=((0.0, 0.80), (0.08, 0.92), (0.30, 1.0), (0.75, 1.05), (0.92, 1.0), (1.0, 0.86)),
                            bottom=dict(widen=1.0, ridges=4, jitter=0.07, valley=(0.84, 0.92), front=6, arc=(20.0, 235.0)),
                            side_chips=[(0.30, 46, 0.32, 0.13), (0.65, 40, 0.28, 0.11), (0.45, 228, 0.30, 0.13)]),
         'front_chunk': dict(c=(0.70, -0.34), w=1.02, h=1.02, L=1.40, yaw=-10.0, lift=5.0, seed=11, label=3, roll=-8.0, ragged='auto', bed=False,
                             taper=((0.0, 0.84), (0.10, 0.95), (0.40, 1.04), (0.80, 1.0), (1.0, 0.82)),
                             bottom=dict(widen=1.0, ridges=4, jitter=0.07, valley=(0.84, 0.92), front=6, arc=(20.0, 235.0)),
                             side_chips=[(0.35, 50, 0.30, 0.12), (0.62, 225, 0.28, 0.12)])}


def pc_section(rng, w, h, B=None):
    """the fluted section in (across, up) round its middle: ridge points on an ellipse, a valley point between each
    pair, pulled in and skewed toward the next ridge"""
    P = SEC; out = []; a0, a1 = (B.get('arc') if B and B.get('arc') else P['arc'])
    nf, nb = (B.get('front') if B and B.get('front') else P['ridges_front']), (B['ridges'] if B else P['ridges_back'])
    span = (a1 - a0) / nf; back = (360.0 - (a1 - a0)) / nb
    angs = [(math.radians(a0 + span * (k + rng.uniform(-0.15, 0.15))), 'r') for k in range(nf)]
    angs += [(math.radians(a1 + back * (k + rng.uniform(-0.15, 0.15) * (k > 0))), 'r') for k in range(nb)]
    n = len(angs)
    def pt(a, r):
        q = Vector((P['rx'] * w * r * math.cos(a), P['rz'] * h * r * math.sin(a)))
        if B and q.y < 0:                              # a wider bottom (B['widen'] at the base, none at the middle)
            q.x *= 1 + (B['widen'] - 1) * min(1.0, -math.sin(a) * 1.4)
        return q
    for k in range(n):
        (a0_, kind), (a1_, _) = angs[k], angs[(k + 1) % n]
        if k == n - 1:
            a1_ += 2 * math.pi
        low = B and math.sin(a0_) < -0.15              # the bottom's ridges jagged: radii and valleys vary more
        jit = B['jitter'] if low else P['jitter']; val = B['valley'] if low else P['valley']
        out.append((pt(a0_, 1 + rng.uniform(-jit, jit)), 0))          # ridge -> valley: broad
        out.append((pt(a0_ + (a1_ - a0_) * rng.uniform(*P['skew']), rng.uniform(*val)), 1))   # valley -> ridge: groove
    return out


def pc_auto_ragged(rng):
    """v29: a ragged end for the chunks, like the hero's: a main askew break, a step back across one side and a
    chamfer over the top, (depth, across, up) and normal (along, across, up)"""
    side = rng.choice((-1, 1)); out = {}
    for sgn in (-1, 1):
        out[sgn] = [((0.04, 0.0, rng.uniform(-0.2, 0.2)), (1.0, rng.uniform(-0.35, 0.35), rng.uniform(-0.3, 0.2))),
                    ((rng.uniform(0.14, 0.26), side * rng.uniform(0.25, 0.4), rng.uniform(0.2, 0.6)), (1.0, side * rng.uniform(0.6, 0.9), rng.uniform(0.3, 0.8))),
                    ((rng.uniform(0.10, 0.22), 0.0, 0.85), (1.0, rng.uniform(-0.3, 0.3), rng.uniform(1.0, 1.3)))]
        side = -side
    return out


def pc_toon(name, tones):
    return pw_toon_rgb(name, ((COKE_STEPS[0], pl_rgb(*tones[0])), (COKE_STEPS[1], pl_rgb(*tones[1])), (9.0, pl_rgb(*tones[2]))))


def pc_cut(bm, co, no):
    bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], plane_co=co, plane_no=no, clear_outer=True)
    for f in bmesh.ops.holes_fill(bm, edges=[e for e in bm.edges if e.is_boundary], sides=0)['faces']:
        f.material_index = 2                           # broken faces take the end colour


def pc_lump(K, name, P, mat):
    """a prism of the grooved section along local X, its section scaled down toward the ends (homothetic, so every
    facet stays planar), the ends broken by four planes each, then lifted, turned and set down"""
    rng = random.Random(P['seed']); L = P['L']; sec_r = pc_section(rng, P['w'], P['h'], P.get('bottom')); n = len(sec_r)
    sec = [q for q, _ in sec_r]; roles = [r for _, r in sec_r]
    zc = SEC['rz'] * P['h']
    rings = []
    for f, sc in P.get('taper', SEC['taper']):
        x = -L / 2 + L * f;                            # v7: the taper inside the lump (v6 put it past the cuts)
        off = Vector((rng.uniform(-0.03, 0.03), rng.uniform(-0.03, 0.03) + P.get('arch', 0.0) * math.sin(math.pi * f)))
        rings.append([(x, q.x * sc + off.x, zc + q.y * sc + off.y) for q in sec])
    V = [v for r in rings for v in r]; m = len(rings)
    F = [tuple(reversed(range(n))), tuple((m - 1) * n + k for k in range(n))]
    for j in range(m - 1):
        F += [(j * n + k, j * n + (k + 1) % n, (j + 1) * n + (k + 1) % n, (j + 1) * n + k) for k in range(n)]
    bm = bmesh.new()
    for v in V:
        bm.verts.new(v)
    bm.verts.ensure_lookup_table()
    for i, f in enumerate(F):
        face = bm.faces.new([bm.verts[k] for k in f])
        face.material_index = 2 if i < 2 else roles[(i - 2) % n]
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    for sgn in (-1, 1):                                # broken ends: an askew cut and a chamfer across the top
        e = L / 2 * sgn
        if P.get('ragged'):                            # v13: a ragged end: the break steps back across the section,
            rag = P['ragged'] if P['ragged'] != 'auto' else pc_auto_ragged(random.Random(P['seed'] * 7 + sgn))
            for co, no in rag[sgn]:            # each cut leaving a slanted face at its own depth
                pc_cut(bm, Vector((e - sgn * co[0], co[1] * P['w'], zc + co[2] * SEC['rz'] * P['h'])), Vector((sgn * no[0], no[1], no[2])).normalized())
            if sgn == 1:
                sc_end = P.get('taper', SEC['taper'])[-1][1]
                for ang, dep, out, tilt in P.get('foot_chips', []):
                    a = math.radians(ang); d = Vector((0, math.cos(a), math.sin(a)))
                    r = Vector((0, SEC['rx'] * P['w'] * math.cos(a), SEC['rz'] * P['h'] * math.sin(a))).length * sc_end
                    pc_cut(bm, Vector((e - dep, 0, zc)) + d * r * out, (Vector((1, 0, 0)) + d * tilt).normalized())
            continue
        pc_cut(bm, Vector((e - sgn * 0.06, 0, zc)), Vector((sgn, rng.uniform(-0.35, 0.35), rng.uniform(-0.2, 0.3))).normalized())
        pc_cut(bm, Vector((e - sgn * rng.uniform(0.16, 0.24), 0, zc + SEC['rz'] * P['h'] * 0.75)),
               Vector((sgn, rng.uniform(-0.3, 0.3), rng.uniform(1.0, 1.4))).normalized())
    if P.get('bed', True):
        pc_cut(bm, Vector((0, 0, 0.0)), Vector((0, 0, -1)))   # a flat bed where it lies
    bmesh.ops.dissolve_degenerate(bm, dist=1e-5, edges=bm.edges[:]); bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    M = (Matrix.Rotation(math.radians(P['yaw']), 4, 'Z') @ Matrix.Rotation(math.radians(P['lift']), 4, 'Y') @
         Matrix.Rotation(math.radians(P.get('roll', 0.0)), 4, 'X'))
    bm.transform(M)
    zmin = min(v.co.z for v in bm.verts)
    if P.get('foot'):                                  # set its lowest point down on the ground at the foot's xy
        low = min(bm.verts, key=lambda v: v.co.z).co.copy()
        tv = Vector((P['foot'][0] - low.x, P['foot'][1] - low.y, -zmin))
    else:
        tv = Vector((P['c'][0], P['c'][1], -zmin))
    bmesh.ops.translate(bm, vec=tv, verts=bm.verts[:]); Mtot = Matrix.Translation(tv) @ M
    me = bpy.data.meshes.new(name); bm.to_mesh(me); bm.free()
    for p in me.polygons:
        p.use_smooth = False
    o = K.obj(name, me, mat[0], False)
    for m_ in mat[1:]:
        o.data.materials.append(m_)
    if P.get('side_chips'):                            # v26: notches knocked out of the long silhouette edges
        crng = random.Random(P['seed'] + 99); cutters = []
        for j, (fx, ang, l, r) in enumerate(P['side_chips']):
            a = math.radians(ang); d = Vector((0, math.cos(a), math.sin(a))); t = Vector((0, -math.sin(a), math.cos(a)))
            surf = Vector((0, SEC['rx'] * P['w'] * math.cos(a), zc + SEC['rz'] * P['h'] * math.sin(a)))
            c = Vector((-L / 2 + L * fx, 0, 0)) + surf + d * r * 0.45
            cb = bmesh.new(); bmesh.ops.create_icosphere(cb, subdivisions=1, radius=1.0)
            R = Matrix.Rotation(crng.uniform(-0.4, 0.4), 3, d)
            for v in cb.verts:
                q = R @ Vector((v.co.x * l / 2, 0, 0)) + R @ (d * v.co.y * r) + R @ (t * v.co.z * r * 1.2)
                v.co = Mtot @ (c + q)
            cm = bpy.data.meshes.new('chip_cut%d' % j); cb.to_mesh(cm); cb.free()
            co_ = K.obj('chip_cut%d' % j, cm, mat[1], False); cutters.append(co_)
        for c_ in cutters:                             # a boolean that keeps the facet roles (pl_cut re-appends the
            mod = o.modifiers.new('chip', 'BOOLEAN'); mod.operation = 'DIFFERENCE'; mod.solver = 'EXACT'; mod.object = c_
        bpy.context.view_layer.update()                # slots and every face fell back to the broad colour)
        me2 = bpy.data.meshes.new_from_object(o.evaluated_get(bpy.context.evaluated_depsgraph_get()))
        for mod in list(o.modifiers):
            o.modifiers.remove(mod)
        old = o.data; o.data = me2; bpy.data.meshes.remove(old)
        for c_ in cutters:
            bpy.data.objects.remove(c_, do_unlink=True)
        bm2 = bmesh.new(); bm2.from_mesh(o.data); bmesh.ops.dissolve_degenerate(bm2, dist=1e-5, edges=bm2.edges[:])
        bm2.to_mesh(o.data); bm2.free(); o.data.update()
        for p in o.data.polygons:
            p.use_smooth = False
    noink(o); o['part_label'] = P['label']
    return o


def pc_dots(ob, below=0.62, amount=0.30):
    me = ob.data; at = me.attributes.get('icon_shade_occlusion') or me.attributes.new('icon_shade_occlusion', 'FLOAT', 'CORNER')
    for p in me.polygons:
        for li in p.loop_indices:
            at.data[li].value = amount if p.normal.dot(LIGHT) < below else 0.0


def build_pet_coke():
    return pc_build('pet_coke', LUMPS)


def build_pet_coke_hero():
    """the hero lump alone, for reviewing its shape"""
    return pc_build('pet_coke_hero', {'long_hero': LUMPS['long_hero']})


def pc_tree(o):
    from mathutils.bvhtree import BVHTree
    me = o.data; mw = o.matrix_world
    return BVHTree.FromPolygons([mw @ v.co for v in me.vertices], [tuple(p.vertices) for p in me.polygons])


def pc_hits(a, b):
    return bool(pc_tree(a).overlap(pc_tree(b)))


def pc_nudge(o, d, step=0.01):
    d = Vector((d.x, d.y, 0)).normalized() * step
    o.data.transform(Matrix.Translation(d)); o.data.update()


def pc_build(name_, lumps):
    """v22 (owner: "watch out for the interpenetration of the two nuggets and the hero + make the hero sit leaning
    properly as it would if gravity were a real thing on the other two nuggets"): the two chunks are laid on the ground
    and pushed apart until they only touch; the hero stands on its foot and is lowered (its lift searched from steep to
    shallow) until it first touches a chunk, so it rests on it; the front chunk is pushed clear of it"""
    setup_icon_rig(); K = Kit(open_collection('ICON_' + name_)); hosts = []
    mat = [pc_toon('pc_' + k, COKE[k]) for k in ('broad', 'groove', 'end')]
    built = {}
    for name, P in lumps.items():
        if name != 'long_hero':
            built[name] = pc_lump(K, name, P, mat)
    left, front = built.get('left_chunk'), built.get('front_chunk')
    if left and front:
        for _ in range(200):                           # apart until they only touch
            if not pc_hits(left, front):
                break
            pc_nudge(front, front.data.vertices[0].co * 0 + (Vector(lumps['front_chunk']['c']) - Vector(lumps['left_chunk']['c'])).to_3d())
    if 'long_hero' in lumps:
        P = dict(lumps['long_hero']); rest = P.get('rest_on') if left else None
        if rest:
            def trial(lift):
                Q = dict(P); Q['lift'] = lift; o = pc_lump(K, 'long_hero_trial', Q, mat)
                hit = pc_hits(o, left); bpy.data.objects.remove(o, do_unlink=True); return hit
            lo, hi = rest['range']                     # steep: clear of the chunk; find the first contact going down
            lift = hi; step = 2.0
            while lift - step >= lo and not trial(lift - step):
                lift -= step
            for _ in range(5):                         # then halve the step toward the contact
                step /= 2
                if not trial(lift - step):
                    lift -= step
            P['lift'] = lift; print('PC_SETTLE hero lift', round(lift, 2))
        built['long_hero'] = pc_lump(K, 'long_hero', P, mat)
        if front:                                      # v25: the front chunk clear of the hero AND the left chunk: pushed
            def centre(o):                             # away from whichever it still touches, toward the viewer's side
                vs = [o.matrix_world @ v.co for v in o.data.vertices]; return sum(vs, Vector()) / len(vs)
            for k in range(300):
                touching = [o for o in (built['long_hero'], left) if pc_hits(o, front)]
                if not touching:
                    break
                d = Vector()
                for o in touching:
                    d += (centre(front) - centre(o))
                pc_nudge(front, d + Vector((0.3, -0.3, 0)))
            print('PC_SETTLE front nudged', k)
    names = list(built)
    for i in range(len(names)):                        # report any interpenetration left
        for j in range(i + 1, len(names)):
            print('PC_SETTLE overlap', names[i], names[j], pc_hits(built[names[i]], built[names[j]]))
    for name in lumps:
        o = built[name]; pc_dots(o); hosts.append(o.name)
    bpy.context.view_layer.update()
    for n in hosts:
        ob = bpy.data.objects[n]
        pl_mesh_lines(K, ob, ob['part_label'], 12.0, n, 0.03, contours=False)   # v12: flute edges ink, the gentle taper joints do not
    for ob in K.col.objects:
        if ob.get('ink_width') == 6:
            ob['ink_width'] = PL_INNER
    info = contract(K, hosts, 'Pet coke: three long faceted lumps, the hero along the falling diagonal raised on one behind, '
                    'a stepped section of lit ridges and dark grooves, broken ends', inner=PL_INNER)
    info['revision'] = PC_REVISION; info['outline']['component_boundaries'] = True
    info['outline']['min_fragment_px'] = 24
    info['stipple']['strength'] = 0.34
    info['stipple']['groups'] = [{'name': 'shaded_faces', 'labels': sorted(P['label'] for P in lumps.values()), 'thresholds': [0.575, 0.50, 0.30]}]
    return info
