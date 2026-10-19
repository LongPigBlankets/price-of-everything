"""Carbonised biomass (g_076 carbonised_biomass), i.e. charcoal. The shipped art: a round heap of angular black lumps
with charred sticks and branches lying criss-crossed over it. Real lump charcoal keeps the wood's shape but is matt
blue-black, split by a grid of shrinkage cracks (the 'alligator' pattern across the grain, long checks along it), its
broken faces a little paler and its sawn ends grey with rings. Here a few large lumps make a mound and long charred
sticks rest on them, rolled and slid until they would stay put, tilting down the slopes and crossing one another. On
the set's grid, camera, light, 12/4 px ink and dots on the shaded sides."""
import random
from mathutils import noise as mnoise
CB_REVISION = 'carbonised_biomass_v26'
LIGHT = Vector((0.06, -0.56, 0.83)).normalized()
# charcoal tones, dark enough not to read as grey stone; the sticks a touch greener-black, the ends brown-grey ash
CHAR = {'lump': ((14, 17, 24), (28, 32, 42), (54, 60, 72)), 'lump2': ((18, 21, 28), (36, 40, 50), (66, 72, 84)),
        'stick': ((16, 20, 25), (34, 44, 48), (62, 78, 82)), 'end': ((64, 58, 56), (92, 84, 80), (114, 106, 100))}
# a solid dark dome carries a few large lumps (sunk into its surface where it faces the viewer) and the sticks; lumps
# alone leave a hollow ring for the sticks to hover over
HEAP = dict(c=(0.0, 0.0), r=1.25, h=1.45, lumps=18, skirt=1.0, cap=0.80,
            seed=4, lump_r=(0.32, 0.46), labels=tuple(range(2, 12)), spacing=0.55, sink=0.40)
# mu: rough charcoal on charcoal grips, so sticks stay leaning on the lumps; rise: how far a stick may sit above the
# bare heap (on the lumps, or one stick up)
STICKS = dict(n=17, tries=300, cands=40, seed=13, L=(1.3, 2.0), r=(0.11, 0.16), labels=tuple(range(12, 31)),
              twigs=0.45, mu=0.8, lean=0.9, crown=1.0, step=0.04, settle=60, rise=0.32, w_gap=0.8, res=0.025, half=1.9)


def cb_lump(K, name, c, r, seed, mat, label):
    """an angular charcoal lump: a low-poly noisy ball, a few broad faces, flat shaded, with no facet lines (they ink
    every facet)"""
    rng = random.Random(seed); bm = bmesh.new(); bmesh.ops.create_icosphere(bm, subdivisions=2, radius=1.0)   # level 1 reads as dice
    off = Vector((seed * 1.3, seed * 0.7, 2.1)); sx, sy, sz = rng.uniform(0.9, 1.3), rng.uniform(0.75, 1.0), rng.uniform(0.55, 0.8)
    rot = Matrix.Rotation(rng.uniform(0, 6.3), 3, 'Z')
    for v in bm.verts:
        d = v.co.normalized(); k = 1 + 0.22 * mnoise.noise(d * 1.3 + off)
        v.co = Vector(c) + rot @ Vector((d.x * sx, d.y * sy, d.z * sz)) * r * k
    zmin = min(v.co.z for v in bm.verts)
    if zmin < 0.002:                                   # nothing below the ground
        bmesh.ops.translate(bm, vec=Vector((0, 0, 0.002 - zmin)), verts=bm.verts[:])
    me = bpy.data.meshes.new(name); bm.to_mesh(me); bm.free()
    o = K.obj(name, me, mat, False); noink(o); o['part_label'] = label
    return o


def cb_stick(K, name, a, b, r, seed, mats, label, segs=9, path=None):
    """a charred stick from a to b (or along path): a slightly crooked, tapered prism of segs facets, its ends grey"""
    rng = random.Random(seed); d = (b - a); L = d.length; d.normalize()
    pts = path or [a + d * L * t + Vector((0, 0, 0.03 * math.sin(math.pi * t))) + Vector((rng.uniform(-0.02, 0.02), rng.uniform(-0.02, 0.02), 0)) * (0 < t < 1)
                   for t in (0.0, 0.33, 0.66, 1.0)]
    P, fr = pl_frames(pts, (0, 0, 1)); V = []; F = []
    for i, (p, (T, N, B)) in enumerate(zip(P, fr)):
        rr = r * (1.0 - 0.18 * i / max(1, len(P) - 1))
        for k in range(segs):
            t = 2 * math.pi * k / segs; V.append(p + (N * math.cos(t) + B * math.sin(t)) * rr * rng.uniform(0.93, 1.07))
    for i in range(len(P) - 1):
        for k in range(segs):
            F.append((i * segs + k, i * segs + (k + 1) % segs, (i + 1) * segs + (k + 1) % segs, (i + 1) * segs + k))
    F.append(tuple(reversed(range(segs)))); F.append(tuple((len(P) - 1) * segs + k for k in range(segs)))
    o = bm_solid(K, name, V, F, mats['stick'], label, smooth=True)
    o.data.materials.append(mats['end'])
    for p in o.data.polygons:
        if len(p.vertices) == segs:
            p.material_index = 1; p.use_smooth = False
    # alligator cracks: short dashes across the stick on its visible side, and a long check along it
    for j in range(rng.randint(0, 1)):
        i = rng.randint(1, len(P) - 2) if len(P) > 2 else 0; T, N, B = fr[i]; p = P[i].lerp(P[i + 1], rng.uniform(0.1, 0.9)) if i + 1 < len(P) else P[i]
        n0 = (VIEW - T * T.dot(VIEW)).normalized(); s0 = T.cross(n0)
        q = [p + (n0 * math.cos(u) + s0 * math.sin(u)) * r * 1.04 for u in (-0.7, 0.0, 0.7)]
        ln = tagged_line(K, '%s_crack%d' % (name, j), [tuple(x) for x in q], label, 3, False); ln['ink_tip'] = 0.2; ln['ink_centre'] = 1.0
    n0 = (VIEW - d * d.dot(VIEW) + Vector((0, 0, 0.6))).normalized(); t0, t1 = rng.uniform(0.1, 0.3), rng.uniform(0.6, 0.85)
    m_ = len(P) - 1; i0, i1 = max(0, int(t0 * m_)), min(m_, int(t1 * m_) + 1)
    ln = tagged_line(K, name + '_check', [tuple(P[i] + (VIEW - fr[i][0] * fr[i][0].dot(VIEW) + Vector((0, 0, 0.6))).normalized() * r * 1.03) for i in range(i0, i1 + 1)], label, 3, False)
    ln['ink_tip'] = 0.15; ln['ink_centre'] = 1.0
    for g in range(2):                                 # bark grain: two broken lines along it on the visible side
        u = (-0.55, 0.45)[g] + rng.uniform(-0.12, 0.12); t0, t1 = rng.uniform(0.05, 0.35), rng.uniform(0.55, 0.95)
        m_ = len(P) - 1; i0, i1 = max(0, int(t0 * m_)), min(m_, int(t1 * m_) + 1)
        pts_ = []
        for i in range(i0, i1 + 1):
            T, N, B = fr[i]; n0 = (VIEW - T * T.dot(VIEW)).normalized(); s0 = T.cross(n0)
            pts_.append(tuple(P[i] + (n0 * math.cos(u) + s0 * math.sin(u)) * r * 1.03))
        if len(pts_) >= 2:
            ln = tagged_line(K, '%s_grain%d' % (name, g), pts_, label, 2, False); ln['ink_tip'] = 0.15; ln['ink_centre'] = 1.0
    return o


def build_carbonised_biomass():
    setup_icon_rig(); K = Kit(open_collection('ICON_carbonised_biomass')); hosts = []
    mats = {k: pl_toon('cb_' + k, *v) for k, v in CHAR.items()}
    P = HEAP; rng = random.Random(P['seed']); placed = []
    from mathutils.bvhtree import BVHTree
    base = bm_clump(K, 'heap_base', (P['c'][0], P['c'][1], -P['h'] * 0.08), P['r'], P['h'], P['seed'], mats['lump'], 1)
    for v in base.data.vertices:                       # a flatter top, so straight sticks lie close to it
        if v.co.z > P['h'] * P['cap']:
            v.co.z = P['h'] * P['cap'] + (v.co.z - P['h'] * P['cap']) * 0.35
    base.data.update(); hosts.append(base.name); bpy.context.view_layer.update()
    # the lumps, spread over the dome's visible face
    spots = [(v.co.copy(), v.normal.copy()) for v in base.data.vertices if 0.06 < v.co.z < P['h'] * P['skirt'] and v.normal.dot(VIEW) > -0.25]
    for j in range(P['lumps']):
        for _ in range(80):
            co, no = rng.choice(spots)
            if all((co - q).length > P['spacing'] for q, _, _ in placed):
                break
        else:
            continue
        r = rng.uniform(*P['lump_r']); c = co + no * r * P['sink']
        used = {lab for q, qr, lab in placed if (c - q).length < (r + qr) * 1.2}
        lab = next((L for L in P['labels'] if L not in used), P['labels'][j % len(P['labels'])])
        placed.append((c, r, lab))
        o = cb_lump(K, 'lump%d' % j, c, r, P['seed'] * 31 + j, mats['lump' if j % 3 else 'lump2'], lab); hosts.append(o.name)
    bpy.context.view_layer.update()
    # the pile: a height field of the dome and lumps, then each long straight stick dropped onto it. A stick rests on
    # the support line under its middle (the upper hull of what is beneath it, evaluated at its centre), so it lies
    # on two contacts either side of its middle and never bends or floats; it then rolls and slides (settle) until it
    # would stay put on the lumps, and joins the height field.
    import numpy as np
    S = STICKS; rs = random.Random(S['seed']); res, half = S['res'], S['half']
    n_ = int(2 * half / res) + 1; xs = np.linspace(-half, half, n_)
    V_ = []; F_ = []
    for o in [base] + [o for o in K.col.objects if o.name.startswith('lump')]:
        off = len(V_); V_ += [o.matrix_world @ v.co for v in o.data.vertices]; F_ += [tuple(off + i for i in p.vertices) for p in o.data.polygons]
    tree = BVHTree.FromPolygons(V_, F_)
    H = np.zeros((n_, n_))
    for a_ in range(n_):
        for b_ in range(n_):
            hit = tree.ray_cast(Vector((xs[a_], xs[b_], 5)), Vector((0, 0, -1)), 10)
            H[a_, b_] = hit[0].z if hit[0] is not None else 0.0
    Hb = H.copy()                                      # the bare heap, to measure how high the sticks have piled
    def h_at(x, y, F=None):
        F = H if F is None else F; a_ = int(round((x + half) / res)); b_ = int(round((y + half) / res))
        return F[a_, b_] if 0 <= a_ < n_ and 0 <= b_ < n_ else 0.0
    def rest(a2, b2, r):
        """the stick's centre line resting on the field: (z at a2, z at b2, the two contacts' t), or None"""
        ts = [k / 47 for k in range(48)]; pts = []
        for t in ts:
            q = a2.lerp(b2, t); pts.append((t, max(h_at(q.x, q.y), 0.0) + r * 0.85))
        hull = []
        for p_ in pts:                                 # the upper convex hull (monotone chain)
            while len(hull) >= 2 and (hull[-1][0] - hull[-2][0]) * (p_[1] - hull[-2][1]) - (hull[-1][1] - hull[-2][1]) * (p_[0] - hull[-2][0]) >= 0:
                hull.pop()
            hull.append(p_)
        for (t0, z0_), (t1, z1_) in zip(hull, hull[1:]):
            if t0 <= 0.5 <= t1:
                k = (z1_ - z0_) / max(t1 - t0, 1e-9); za = z0_ - k * t0; zb = za + k
                return za, zb, t0, t1
        return None
    def settle(a2, b2, r):
        """move the stick until it would stay put: it rolls sideways off a contact on a steep cross-slope, and slides
        along itself if steeper than friction allows unless its low end rests on something (then it leans, up to a
        limit). Returns (a2, b2, (za, zb)) or None if it slides off the heap."""
        L2 = (b2 - a2).length; ax = (b2 - a2) / L2; perp = Vector((-ax.y, ax.x, 0)); w = r + 0.08
        for _ in range(S['settle']):
            z = rest(a2, b2, r)
            if z is None or (a2 + b2).length / 2 > half - 0.3:
                return None
            za, zb, t0, t1 = z
            roll = 0.0
            for t in (t0, t1):
                q = a2.lerp(b2, t); qp, qm = q + perp * w, q - perp * w
                roll += (h_at(qp.x, qp.y) - h_at(qm.x, qm.y)) / (2 * w)
            roll /= 2
            if abs(roll) > S['mu']:                    # rolls off its contacts, downhill across itself
                sh = -perp * math.copysign(S['step'], roll); a2, b2 = a2 + sh, b2 + sh; continue
            slope = (zb - za) / L2
            end_rests = (t0 == 0.0) if zb > za else (t1 == 1.0)   # the low end is one of the contacts
            if abs(slope) > S['mu'] and not end_rests:  # slides along itself toward its low end
                sh = ax * math.copysign(S['step'], za - zb); a2, b2 = a2 + sh, b2 + sh; continue
            if abs(slope) > S['lean']:
                return None
            return a2, b2, (za, zb)
        return None
    def stamp(p0, p1, r):
        d2 = (p1 - p0).to_2d(); L2 = max(d2.length_squared, 1e-9)
        lo = [int((min(p0[c], p1[c]) - r - 0.05 + half) / res) for c in (0, 1)]; hi = [int((max(p0[c], p1[c]) + r + 0.05 + half) / res) + 1 for c in (0, 1)]
        for a_ in range(max(0, lo[0]), min(n_, hi[0])):
            for b_ in range(max(0, lo[1]), min(n_, hi[1])):
                q = Vector((xs[a_], xs[b_])); t = max(0.0, min(1.0, (q - p0.to_2d()).dot(d2) / L2)); c = p0.lerp(p1, t)
                dd = (q - c.to_2d()).length
                if dd < r:
                    H[a_, b_] = max(H[a_, b_], c.z + math.sqrt(r * r - dd * dd))
    # each stick tries many placements and takes the one over the least-covered ground that rests lowest over the bare
    # heap, so the sticks spread over the whole visible heap as a low criss-cross mat (the first fit stacks them into a
    # tower; the lowest rest alone caps the top and leaves the front bare)
    sticks = []
    for j in range(S['tries']):
        if len(sticks) >= S['n']:
            break
        L = rs.uniform(*S['L']); r = rs.uniform(*S['r']); best = None
        for _ in range(S['cands']):
            # lying on the mound's slope: centred over the side the camera sees, turned 30-65 degrees off the line
            # down the slope, so each tilts downhill along the nuggets and the sticks cross one another
            cr = S['crown'] * math.sqrt(rs.random()); ca = math.radians(-45 + rs.uniform(-110, 110))
            cx, cy = cr * math.cos(ca), cr * math.sin(ca)
            ang = ca + rs.choice((-1, 1)) * math.radians(rs.uniform(30, 65)); d = Vector((math.cos(ang), math.sin(ang), 0))
            a2, b2 = Vector((cx, cy, 0)) - d * L / 2, Vector((cx, cy, 0)) + d * L / 2
            st = settle(a2, b2, r)
            if st is None:
                continue
            a2, b2, z = st; cx, cy = ((a2 + b2) / 2).x, ((a2 + b2) / 2).y
            gap = (z[0] + z[1]) / 2 - h_at(cx, cy, Hb)
            foot = [a2.lerp(b2, k / 11) for k in range(12)]   # how much of its footprint other sticks already cover
            cov = sum(1 for q in foot if h_at(q.x, q.y) - h_at(q.x, q.y, Hb) > 0.04) / 12
            score = S['w_gap'] * gap + cov
            if gap < S['rise'] and (best is None or score < best[0]):
                best = (score, a2, b2, z)
        if best is None:
            continue
        _, a2, b2, z = best
        a, b = Vector((a2.x, a2.y, z[0])), Vector((b2.x, b2.y, z[1]))
        used = {s_['label'] for s_ in sticks if min((s_['a'] - a).length, (s_['b'] - b).length, ((s_['a'] + s_['b']) / 2 - (a + b) / 2).length) < 1.2}
        lab = next((x for x in S['labels'] if x not in used), S['labels'][len(sticks) % len(S['labels'])])
        side = (b - a).to_2d().normalized(); side = Vector((-side.y, side.x, 0))
        path = [a.lerp(b, t) + side * (0.035 * math.sin(math.pi * t * 1.6 + j)) * (0 < t < 1) for t in (0.0, 0.2, 0.4, 0.6, 0.8, 1.0)]   # a slight crook
        o = cb_stick(K, 'stick%d' % j, a, b, r, S['seed'] * 13 + j, mats, lab, path=path); hosts.append(o.name)
        stamp(a, b, r)
        if rs.random() < S['twigs']:                   # a forked side branch, lying on what is under it
            t = rs.uniform(0.3, 0.7); root = a.lerp(b, t); ax = (b - a).to_2d().normalized()
            sgn = rs.choice((-1, 1)); fa = math.radians(rs.uniform(28, 42)) * sgn
            dirv = Vector((ax.x * math.cos(fa) - ax.y * math.sin(fa), ax.x * math.sin(fa) + ax.y * math.cos(fa)))
            tip2 = root.to_2d() + dirv * rs.uniform(0.45, 0.75); rt = r * 0.55
            tip = Vector((tip2.x, tip2.y, max(h_at(tip2.x, tip2.y) + rt * 0.85, root.z - 0.30)))
            cb_stick(K, 'stick%d_twig' % j, root, tip, rt, S['seed'] * 17 + j, mats, lab); stamp(root, tip, rt)
        sticks.append(dict(a=a, b=b, label=lab))
    print('CB_STICKS placed', len(sticks))
    for ob in K.col.objects:
        if ob.type == 'MESH' and not ob.get('edge_ink'):
            bm_shade_dots(ob)
    bpy.context.view_layer.update()
    for ob in K.col.objects:
        if ob.get('ink_width') == 6:
            ob['ink_width'] = PL_INNER
    info = contract(K, hosts, 'Carbonised biomass: a heap of angular charcoal lumps with charred sticks criss-crossed over it, '
                    'alligator cracks and grey burnt ends', inner=PL_INNER)
    info['revision'] = CB_REVISION; info['outline']['component_boundaries'] = True
    info['outline']['min_fragment_px'] = 24; info['outline']['id_step'] = 8
    info['outline']['component_weight_by_label'] = {str(k): (6 if k >= 12 else 4) for k in range(1, 32)}   # the sticks bolder
    info['stipple']['strength'] = 0.34
    info['stipple']['groups'] = [{'name': 'shaded_faces', 'labels': list(range(1, 32)), 'thresholds': [0.575, 0.50, 0.30]}]
    return info
