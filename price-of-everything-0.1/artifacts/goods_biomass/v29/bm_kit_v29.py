"""Biomass (g_062 biomass). The shipped art: three wooden logs stacked two and one, their sawn ends toward the viewer
at the lower left, a basket of apples and carrots on top and a heap of wood chips in front. This file builds the logs
first. Real cut logs: rough dark bark with long furrows, a thin bark rim round the sawn end, pale sapwood with darker
growth rings round an off-centre pith, and a radial check or two where the wood dried. On the set's grid, camera,
light, 12/4 px ink and dots on the shaded sides."""
import random
from mathutils import noise as mnoise
BM_REVISION = 'biomass_v29'
LIGHT = Vector((0.06, -0.56, 0.83)).normalized()
BARK = ((70, 46, 34), (98, 66, 46), (124, 86, 60))
# the sawn ends face -Y (diffuse ~0.56): their own ramp, so they read lit and tan as shipped, not shaded
END_STEPS = (0.42, 0.72)
WOOD = {'sap': ((178, 128, 82), (206, 152, 100), (222, 174, 122)), 'ring': ((146, 94, 58), (166, 110, 68), (182, 126, 82)),
        'rim': ((84, 56, 40), (102, 68, 48), (116, 80, 56)), 'pith': ((112, 70, 44), (128, 82, 52), (140, 92, 60))}
# (screen-free world placement) centre x, centre y, radius, length, seed
LOGS = [(-0.44, 0.00, 0.42, 2.30, 3), (0.44, -0.10, 0.43, 2.25, 7), (0.00, 0.10, 0.41, 2.20, 11)]
# the wood-chip heap leaning on the right log: ~90 broad flat angular chips laid over a low dark dome, each outlined.
# Dead ends (see the README): small chips read as confetti, clumps as potatoes or pebbles, bumps on one surface blotched.
# v20 (owner: "move the heap of woodchips back and make it lean against the rightmost log"): beside the right log's
# middle, its base running into the log so it piles up against the bark
HEAP = dict(c=(0.98, 0.25), r=(0.92, 0.88), h=0.84,   # v21: further back, its peak into the log's flank, piled higher
            profile=1.5, seed=5, chips=90, spacing=0.105, rho_max=0.95, tilt=0.30,   # v19: denser, the base barely between chips
            chip=((0.30, 0.42), (0.13, 0.19)), thick=0.03, chip_labels=tuple(range(5, 16)))
CHIP = {'mound': ((122, 82, 50), (156, 108, 66), (178, 128, 82)), 'fresh': ((186, 140, 88), (216, 172, 116), (234, 196, 142)),
        'tan': ((164, 116, 70), (196, 148, 96), (214, 170, 116)), 'bark': ((80, 54, 38), (104, 70, 50), (122, 84, 60))}
# the basket on the top log (as shipped): an oval wicker tub, long along the log, a rim, a band handle across it, three
# apples toward the front and two carrots lying toward the back with their leaves above the rim
# v23: 1.35x larger and centred on the top log (v22 sat small at its back end), a coarser weave as shipped
BASKET = dict(y=0.0, sink=0.09, rb=(0.48, 0.66), rt=(0.64, 0.86), hgt=0.58, sq=2.6, rim_r=0.045, handle_h=0.86,
              handle_w=0.09, handle_t=0.035, handle_y=0.08, bed=0.44, courses=4, posts=18)   # v25: a deep basket
BK = {'wicker': ((166, 118, 66), (204, 156, 98), (224, 182, 124)), 'rim': ((150, 104, 58), (190, 142, 88), (214, 170, 114)),
      # v27 (owner: "mute the carrots and apples colours a bit")
      'apple': ((120, 46, 48), (150, 62, 62), (176, 88, 84)), 'carrot': ((176, 98, 48), (208, 132, 70), (222, 156, 98)),
      'inside': ((104, 68, 38), (130, 88, 50), (146, 100, 58)),
      'leaf': ((84, 112, 50), (112, 146, 64), (140, 172, 84)), 'stem': ((70, 48, 32), (90, 62, 42), (106, 76, 52))}
# v25 (owner: "the apples and carrots look like they sit on top of a shelf ... let the basket be deeper inside or find
# a way for the apples to look half inside"): the bed is deep and dark, the produce sunk to the rim and packed, so
# only their tops show and the gaps fall into shadow
APPLES = [(-0.26, -0.48, 0.24), (0.20, -0.44, 0.235), (-0.30, -0.06, 0.23), (0.06, -0.16, 0.24), (0.34, -0.06, 0.22)]
APPLE_SINK = 0.06                                     # apple centres this far below the rim   # (x, y offset in the basket, radius)
CARROTS = [((-0.26, 0.05), (-0.16, 0.66), 0.115), ((0.04, 0.08), (0.24, 0.62), 0.11), ((0.34, 0.12), (0.40, 0.58), 0.10)]
CARROT_Z = (-0.20, 0.10)
# v27 (owner: "add some leaves to the left of the carrots and partly overlapped. These are just leaves, not attached to
# anything"): loose leaves standing in the basket behind the left carrot, (base x, y, z below the rim, direction, length)
LOOSE_LEAVES = [((-0.42, 0.24, 0.10), (-0.45, 0.25, 1.0), 0.42), ((-0.33, 0.44, 0.10), (-0.20, 0.45, 1.0), 0.40),
                ((-0.28, 0.14, 0.12), (0.05, 0.15, 1.0), 0.38),   # one far left only showed as a nub behind the handle
                # v29 (owner: "make it at least 6 or 7 leaves")
                ((-0.20, 0.34, 0.10), (-0.10, 0.30, 1.0), 0.36), ((-0.38, 0.36, 0.14), (-0.60, 0.50, 1.0), 0.38),
                ((-0.14, 0.06, 0.12), (0.30, -0.10, 1.0), 0.34), ((-0.30, 0.56, 0.12), (-0.35, 0.70, 1.0), 0.36)]                              # tip and top heights against the rim: they rise out of the basket   # (tip xy, top xy, top radius)
L_BASKET, L_RIM, L_HANDLE, L_APPLE0, L_CARROT0, L_LEAF0 = 16, 17, 18, 19, 24, 27
RINGS = (0.24, 0.46, 0.68)                             # growth bands, as fractions from pith to bark
RING_W = 0.075


def bm_end_toon(name, tones):
    return pw_toon_rgb(name, ((END_STEPS[0], pl_rgb(*tones[0])), (END_STEPS[1], pl_rgb(*tones[1])), (9.0, pl_rgb(*tones[2]))))


def bm_log(K, name, c, R, L, seed, mats, label, segs=144, rows=72, taper=0.06):   # v2: finer (the tone steps sawtoothed)
    """a log along world Y: a lumpy, slightly oval cylinder (bark, material 0) closed by flat sawn ends (material 1).
    Returns the object and its front rim: [(angle, point)]"""
    rng = random.Random(seed); off = Vector((seed * 1.7, seed * 0.9, seed * 0.3)); ov = rng.uniform(0.93, 0.98)
    cx, cy, cz = c
    def rad(a, t):
        q = Vector((math.cos(a) * 1.3, math.sin(a) * 1.3, t * 0.45)) + off   # v3: gentler, longer lumps (blotchy tone steps)
        return R * (1 + 0.022 * mnoise.noise(q) + 0.006 * mnoise.noise(q * 3.1)) * (1 - taper * (t / L + 0.5))   # narrower toward the back
    V = []; F = []; mi = []
    for j in range(rows + 1):
        t = -L / 2 + L * j / rows
        for i in range(segs):
            a = 2 * math.pi * i / segs; r = rad(a, t)
            V.append((cx + r * math.cos(a), cy + t, cz + r * math.sin(a) * ov))
    for j in range(rows):
        for i in range(segs):
            a0, a1 = j * segs + i, j * segs + (i + 1) % segs
            F.append((a0, a1, a1 + segs, a0 + segs)); mi.append(0)
    front = len(V); V.append((cx, cy - L / 2, cz)); back = len(V); V.append((cx, cy + L / 2, cz))
    for i in range(segs):
        F.append((front, (i + 1) % segs, i)); mi.append(1)
        F.append((back, rows * segs + i, rows * segs + (i + 1) % segs)); mi.append(1)
    me = bpy.data.meshes.new(name); me.from_pydata(V, [], F); me.update()
    bm = bmesh.new(); bm.from_mesh(me); bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:]); bm.to_mesh(me); bm.free()
    for p, m in zip(me.polygons, mi):
        p.material_index = m; p.use_smooth = m == 0
    o = K.obj(name, me, mats[0], False); o.data.materials.append(mats[1]); noink(o); o['part_label'] = label
    rim = [(2 * math.pi * i / segs, Vector(V[i])) for i in range(segs)]
    return o, rim


def bm_band(K, name, rim, P, f0, f1, lift, mat, label, wobble=0.0, seed=0):
    """an annulus decal on the sawn end between fractions f0 and f1 of the way from the pith P to the rim"""
    rng = random.Random(seed); n = len(rim); V = []
    w = [wobble * mnoise.noise(Vector((math.cos(a) * 2.0, math.sin(a) * 2.0, seed * 0.37))) for a, _ in rim]
    for f in (f0, f1):
        for (a, q), d in zip(rim, w):
            p = P + (q - P) * max(0.0, f + d); V.append((p.x, p.y - lift, p.z))
    F = [(i, (i + 1) % n, n + (i + 1) % n, n + i) for i in range(n)] if f0 > 0 else []
    if f0 <= 0:                                        # a filled disc
        V = V[n:]; V.append((P.x, P.y - lift, P.z)); F = [(n, (i + 1) % n, i) for i in range(n)]
    me = bpy.data.meshes.new(name); me.from_pydata(V, [], F); me.update()
    bm = bmesh.new(); bm.from_mesh(me)
    for f in bm.faces:
        if f.normal.y > 0:
            f.normal_flip()
    bm.to_mesh(me); bm.free()
    o = K.obj(name, me, mat, False); noink(o); o['part_label'] = label; o.pass_index = 73
    return o


def bm_end(K, log, rim, mats, label, seed, check=False):
    """the sawn end: bark rim, sapwood, growth bands round an off-centre pith, and (check) a radial drying crack"""
    rng = random.Random(seed); C = sum((q for _, q in rim), Vector()) / len(rim)
    R = sum((q - C).length for _, q in rim) / len(rim)
    P = C + Vector((rng.uniform(-0.12, 0.12) * R, 0, rng.uniform(-0.12, 0.08) * R))
    bm_band(K, log.name + '_rim', rim, P, 0.87, 1.0, 0.002, mats['rim'], label)   # v3: a bolder bark rim
    for k, f in enumerate(RINGS):
        bm_band(K, '%s_ring%d' % (log.name, k), rim, P, f - RING_W / 2, f + RING_W / 2, 0.004, mats['ring'], label,
                wobble=0.025, seed=seed * 10 + k)
    bm_band(K, log.name + '_pith', rim, P, 0.0, 0.07, 0.004, mats['pith'], label)
    if check:                                          # a drying check from near the pith out to the bark
        a = rng.uniform(0, 2 * math.pi); q = min(rim, key=lambda r_: abs(((r_[0] - a + math.pi) % (2 * math.pi)) - math.pi))[1]
        side = Vector((-(q - P).z, 0, (q - P).x)).normalized()
        pts = [P + (q - P) * f + side * (0.02 * R * (1 if k % 2 else -1)) for k, f in enumerate((0.12, 0.4, 0.66, 0.9))]
        ln = tagged_line(K, log.name + '_check', [tuple(p - Vector((0, 0.008, 0))) for p in pts], label, 4, False)
        ln['ink_tip'] = 0.2; ln['ink_centre'] = 1.0


def bm_dashes(K, log, c, R, L, seed, label, count=16):
    """bark furrows as the shipped art draws them: short tapered ink dashes along the length, on the visible side,
    each laid on the bark (rays from the axis) and lifted a hair"""
    from mathutils.bvhtree import BVHTree
    rng = random.Random(seed); me = log.data; mw = log.matrix_world
    tree = BVHTree.FromPolygons([mw @ v.co for v in me.vertices], [tuple(p.vertices) for p in me.polygons])
    cx, cy, cz = c; n = 0
    for _ in range(200):
        if n == count:
            break
        a = math.radians(rng.uniform(-20, 110)); t0 = rng.uniform(-L / 2 + 0.25, L / 2 - 0.6); ln_ = rng.uniform(0.25, 0.55)
        da = math.radians(rng.uniform(-6, 6)); pts = []
        for k in range(7):
            f = k / 6; aa = a + da * f; d = Vector((math.cos(aa), 0, math.sin(aa))); o = Vector((cx, cy + t0 + ln_ * f, cz))
            hit = tree.ray_cast(o + d * 2, -d, 3)
            if hit[0] is None:
                break
            pts.append(tuple(hit[0] + hit[1].normalized() * 0.006))
        if len(pts) == 7:
            ln = tagged_line(K, '%s_dash%d' % (log.name, n), pts, label, 5, False); ln['ink_tip'] = 0.15; ln['ink_centre'] = 1.0
            n += 1


def bm_chip(K, name, at, nrm, size, mat, label, rng, flat=False, th=0.018, corners=4):
    """one wood chip: a flat angular plate, thin, lying on the surface (flat) or tilted at random"""
    L, W = size; m = corners; pts = []                 # v17: a broad angular chip, its corners jittered
    for k in range(m):
        ang = 2 * math.pi * (k + rng.uniform(-0.2, 0.2)) / m + math.pi / m
        pts.append(Vector((math.cos(ang) * L / 2 * rng.uniform(0.8, 1.0), math.sin(ang) * W / 2 * rng.uniform(0.8, 1.0), 0)))
    V = [(p.x, p.y, th / 2) for p in pts] + [(p.x, p.y, -th / 2) for p in pts]
    F = [tuple(range(m)), tuple(reversed(range(m, 2 * m)))] + [(k, m + k, m + (k + 1) % m, (k + 1) % m) for k in range(m)]
    me = bpy.data.meshes.new(name); me.from_pydata(V, [], F); me.update()
    n = Vector(nrm).normalized() if flat else (Vector(nrm) + Vector((rng.uniform(-0.5, 0.5), rng.uniform(-0.5, 0.5), rng.uniform(-0.1, 0.3)))).normalized()
    Mx = Matrix.Translation(at) @ n.to_track_quat('Z', 'X').to_matrix().to_4x4() @ Matrix.Rotation(rng.uniform(0, 2 * math.pi), 4, 'Z')
    me.transform(Mx)
    bm = bmesh.new(); bm.from_mesh(me); bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    for v in bm.verts:
        v.co.z = max(v.co.z, 0.002)
    bm.to_mesh(me); bm.free()
    o = K.obj(name, me, mat, False); noink(o); o['part_label'] = label
    return o


def bm_clump(K, name, c, r, h, seed, mat, label):
    """one rounded clump of the heap: a squashed, lumpy icosphere sunk into the ground and cut flat there"""
    off = Vector((seed * 1.9, seed * 0.7, 2.3)); bm = bmesh.new(); bmesh.ops.create_icosphere(bm, subdivisions=4, radius=1.0)
    for v in bm.verts:
        d = v.co.normalized(); k = 1 + 0.10 * mnoise.noise(d * 1.7 + off)
        v.co = Vector((c[0] + d.x * r * k, c[1] + d.y * r * 0.92 * k, c[2] + d.z * h * k))
    bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], plane_co=(0, 0, 0), plane_no=(0, 0, -1), clear_outer=True)
    bmesh.ops.holes_fill(bm, edges=[e for e in bm.edges if e.is_boundary], sides=0)
    bmesh.ops.dissolve_degenerate(bm, dist=1e-5, edges=bm.edges[:]); bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    me = bpy.data.meshes.new(name); bm.to_mesh(me); bm.free()
    for p in me.polygons:
        p.use_smooth = p.normal.z > -0.99
    o = K.obj(name, me, mat, False); noink(o); o['part_label'] = label
    return o


def bm_heap(K, mats, L0):
    """v17: a heap OF wood chips: broad flat angular chips laid over a low dark dome, each following the slope, tipped
    a little, later ones lying on earlier ones; overlapping chips take different part labels (greedy colouring), so
    each is outlined. Broad chips keep the outline count down (v6/v7's small chips read as confetti), and flat chips
    read as wood where v16's rounded clumps read as stones."""
    P = HEAP; rng = random.Random(P['seed'] + 1); cx, cy = P['c']; rx, ry = P['r']; H = P['h']
    base = bm_clump(K, 'heap_base', (cx, cy, -H * 0.10), max(rx, ry) * 0.95, H * 0.98, P['seed'], mats['mound'], L0)
    bpy.context.view_layer.update()                    # v18: chips laid on the base's own surface (v17's cone sat inside it)
    lx, _, lr, _, _ = LOGS[1]; lz = lr * 1.04          # v20: no chips inside the log the heap leans on
    spots = [(v.co.copy(), v.normal.copy()) for v in base.data.vertices if v.co.z > 0.04 and v.normal.dot(VIEW) > -0.2
             and math.hypot(v.co.x - lx, v.co.z - lz) > lr + 0.06]
    placed = []; kinds = ['fresh'] * 5 + ['tan'] * 5 + ['bark']
    for j in range(P['chips']):
        for _ in range(60):
            co, no = rng.choice(spots)
            rho = min(1.0, math.hypot((co.x - cx) / rx, (co.y - cy) / ry))
            if all((co - q).length > P['spacing'] for q, _, _ in placed):
                break
        L = rng.uniform(*P['chip'][0]) * (1 - 0.25 * rho); W = rng.uniform(*P['chip'][1]) * (1 - 0.25 * rho)
        used = {lab for q, qr, lab in placed if (co - q).length < (L + qr) * 0.6}
        lab = next((x for x in P['chip_labels'] if x not in used), P['chip_labels'][j % len(P['chip_labels'])])
        placed.append((co, L, lab))
        tilt = (no + Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), 0)) * P['tilt']).normalized()
        bm_chip(K, 'chip%d' % j, co + no * (0.02 + 0.0012 * j), tilt, (L, W), mats[rng.choice(kinds)], lab, rng, flat=True,
                th=P['thick'], corners=rng.choice((4, 5, 5)))
    return [base]


def bm_shade_dots(ob, amount=0.30, below=0.62):
    me = ob.data; at = me.attributes.get('icon_shade_occlusion') or me.attributes.new('icon_shade_occlusion', 'FLOAT', 'CORNER')
    for p in me.polygons:
        for li in p.loop_indices:
            at.data[li].value = amount if p.normal.dot(LIGHT) < below else 0.0


def bm_solid(K, name, V, F, mat, label, smooth=True):
    me = bpy.data.meshes.new(name); me.from_pydata([tuple(v) for v in V], [], F); me.update()
    bm = bmesh.new(); bm.from_mesh(me); bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=1e-6)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:]); bm.to_mesh(me); bm.free()
    for p in me.polygons:
        p.use_smooth = smooth
    o = K.obj(name, me, mat, False); noink(o); o['part_label'] = label
    return o


def bm_tube(K, name, path, profile, n0, mat, label, closed=False, smooth=True):
    """a profile (2D points round the centreline) swept along a path; closed loops join, open ones are capped"""
    P, fr = pl_frames(path, n0); m = len(profile); V = []; F = []
    for p, (T, N, B) in zip(P, fr):
        for a, b in profile:
            V.append(p + N * a + B * b)
    n = len(P); last = n if closed else n - 1
    for i in range(last):
        i2 = (i + 1) % n
        for k in range(m):
            F.append((i * m + k, i * m + (k + 1) % m, i2 * m + (k + 1) % m, i2 * m + k))
    if not closed:
        F.append(tuple(reversed(range(m)))); F.append(tuple((n - 1) * m + k for k in range(m)))
    return bm_solid(K, name, V, F, mat, label, smooth)


def bm_sq(a, rx, ry, e):
    """a superellipse point: an oval with squarer sides, as a woven basket"""
    c, s_ = math.cos(a), math.sin(a)
    return Vector((rx * math.copysign(abs(c) ** (2 / e), c), ry * math.copysign(abs(s_) ** (2 / e), s_), 0))


def bm_basket(K, mats, B):
    """the wicker tub (closed: its top a bed under the produce), the rim, the woven lines and the handle"""
    P = BASKET; segs = 128; rings = 10; V = []; F = []
    for j in range(rings + 1):
        f = j / rings; rx = P['rb'][0] + (P['rt'][0] - P['rb'][0]) * f; ry = P['rb'][1] + (P['rt'][1] - P['rb'][1]) * f
        for i in range(segs):
            V.append(B + bm_sq(2 * math.pi * i / segs, rx, ry, P['sq']) + Vector((0, 0, P['hgt'] * f)))
    for j in range(rings):
        for i in range(segs):
            F.append((j * segs + i, j * segs + (i + 1) % segs, (j + 1) * segs + (i + 1) % segs, (j + 1) * segs + i))
    bot = len(V); V.append(B.copy()); top = len(V); V.append(B + Vector((0, 0, P['hgt'] - P['bed'])))
    for i in range(segs):
        F.append((bot, (i + 1) % segs, i))
    # the bed: the top ring pulled in and down to the bed level, then a fan
    bed0 = len(V)
    for i in range(segs):
        fb = (P['hgt'] - P['bed']) / P['hgt']           # v25: the bed ring inside the wall at its own height (the deep bed's
        rbx = (P['rb'][0] + (P['rt'][0] - P['rb'][0]) * fb) * 0.90; rby = (P['rb'][1] + (P['rt'][1] - P['rb'][1]) * fb) * 0.90
        V.append(B + bm_sq(2 * math.pi * i / segs, rbx, rby, P['sq']) + Vector((0, 0, P['hgt'] - P['bed'])))   # ring poked out)
    n_out = len(F)
    for i in range(segs):
        F.append((rings * segs + i, rings * segs + (i + 1) % segs, bed0 + (i + 1) % segs, bed0 + i))
        F.append((top, bed0 + i, bed0 + (i + 1) % segs))
    tub = bm_solid(K, 'basket', V, F, mats['wicker'], L_BASKET)
    tub.data.materials.append(mats['inside'])          # v24: the inside dark, as a basket's shadowed interior
    for p in tub.data.polygons:                        # v25: every face of the inside (the wall faces the axis, the bed up)
        c = p.center; out = Vector((c.x - B.x, c.y - B.y, 0))
        if (p.normal.z > 0.3 and c.z > B.z + 0.05) or (out.length > 1e-6 and Vector((p.normal.x, p.normal.y, 0)).dot(out) < 0):
            p.material_index = 1
    rim_path = [B + bm_sq(2 * math.pi * i / segs, P['rt'][0] * 0.985, P['rt'][1] * 0.985, P['sq']) + Vector((0, 0, P['hgt'])) for i in range(segs)]
    prof = [(math.cos(2 * math.pi * k / 16) * P['rim_r'], math.sin(2 * math.pi * k / 16) * P['rim_r'] * 1.4) for k in range(16)]
    rim = bm_tube(K, 'basket_rim', rim_path, prof, (0, 0, 1), mats['rim'], L_RIM, closed=True)
    # the weave as the shipped art draws it: courses round the wall and short staggered uprights between them
    from mathutils.bvhtree import BVHTree
    me = tub.data; tree = BVHTree.FromPolygons([v.co.copy() for v in me.vertices], [tuple(p.vertices) for p in me.polygons])
    def on_wall(a, f):
        rx = P['rb'][0] + (P['rt'][0] - P['rb'][0]) * f; ry = P['rb'][1] + (P['rt'][1] - P['rb'][1]) * f
        q = B + bm_sq(a, rx, ry, P['sq']) + Vector((0, 0, P['hgt'] * f)); d = (q - B - Vector((0, 0, P['hgt'] * f))).normalized()
        hit = tree.ray_cast(q + d * 0.3, -d, 0.6)
        return hit[0] + hit[1].normalized() * 0.006 if hit[0] is not None else None
    nc = P['courses']
    for c in range(1, nc):
        f = c / nc; pts = [on_wall(2 * math.pi * i / 160, f) for i in range(161)]
        if all(pts):
            tagged_line(K, 'weave_course%d' % c, [tuple(p) for p in pts], L_BASKET, 4, False)
    for c in range(nc):
        for i in range(P['posts']):
            a = 2 * math.pi * (i + 0.5 * (c % 2)) / P['posts']; f0, f1 = (c + 0.18) / nc, (c + 0.82) / nc
            p0, p1 = on_wall(a, f0), on_wall(a, f1)
            if p0 and p1:
                tagged_line(K, 'weave_post%d_%d' % (c, i), [tuple(p0), tuple(p1)], L_BASKET, 4, False)
    # the handle: a flat band arching across the basket, its feet inside the rim
    hy = B.y + P['handle_y']; z0 = B.z + P['hgt'] - 0.06; rx = P['rt'][0] * 0.93; path = []
    for k in range(41):
        t = math.pi * k / 40; path.append(Vector((B.x - rx * math.cos(t), hy, z0 + (P['handle_h'] + 0.06) * math.sin(t))))
    hp = [(-P['handle_w'], -P['handle_t']), (P['handle_w'], -P['handle_t']), (P['handle_w'], P['handle_t']), (-P['handle_w'], P['handle_t'])]
    handle = bm_tube(K, 'basket_handle', path, hp, (0, 1, 0), mats['rim'], L_HANDLE, smooth=False)
    return [tub, rim, handle]


def bm_leaf(K, name, base, direction, length, width, mat, label, rng, fold=0.35):
    """a leaf: a pointed oval folded a little along its midrib, a thin plate with a midrib line"""
    d = Vector(direction).normalized(); side = d.cross(Vector((0, 0, 1)))
    if side.length < 1e-3:
        side = Vector((1, 0, 0))
    side.normalize(); up = side.cross(d).normalized(); n = 12; top = []; bot = []
    for k in range(n + 1):
        t = k / n; w = width * math.sin(math.pi * t) ** 0.8; c = base + d * length * t
        top.append((c + side * w + up * w * fold, c - side * w + up * w * fold, c))
    V = []; F = []; th = up * 0.008
    for c_l, c_r, c in top:
        V += [c_l, c, c_r, c_l - th, c - th * 1.5, c_r - th]
    for k in range(n):
        a, b = k * 6, (k + 1) * 6
        F += [(a, a + 1, b + 1, b), (a + 1, a + 2, b + 2, b + 1), (a + 4, a + 3, b + 3, b + 4), (a + 5, a + 4, b + 4, b + 5),
              (a + 3, a, b, b + 3), (a + 2, a + 5, b + 5, b + 2)]
    F += [(0, 3, 4, 1), (1, 4, 5, 2)]
    o = bm_solid(K, name, V, F, mat, label, smooth=False)
    ln = tagged_line(K, name + '_rib', [tuple(base + d * length * t + up * 0.004) for t in (0.08, 0.5, 0.86)], label, 3, False)
    ln['ink_tip'] = 0.3; ln['ink_centre'] = 1.0
    return o


def bm_apple(K, name, c, r, mats, label, leaf_label, rng):
    bm = bmesh.new(); bmesh.ops.create_icosphere(bm, subdivisions=4, radius=r)
    for v in bm.verts:
        d = v.co.normalized(); v.co.z *= 0.90
        v.co *= 1 + 0.06 * max(0.0, d.z) ** 6 * -1.0 + 0.04 * (1 - abs(d.z))   # a dimple at the top, broad shoulders
        if d.z > 0.92:
            v.co.z -= r * 0.10 * (d.z - 0.92) / 0.08
    bmesh.ops.translate(bm, vec=c, verts=bm.verts[:])
    me = bpy.data.meshes.new(name); bm.to_mesh(me); bm.free()
    for p in me.polygons:
        p.use_smooth = True
    o = K.obj(name, me, mats['apple'], False); noink(o); o['part_label'] = label
    top = c + Vector((0, 0, r * 0.80))
    st = tagged_line(K, name + '_stem', [tuple(top), tuple(top + Vector((0.02, -0.01, 0.07))), tuple(top + Vector((0.035, -0.02, 0.11)))], label, 5, False)
    st['ink_tip'] = 0.6; st['ink_centre'] = 1.0
    bm_leaf(K, name + '_leaf', top + Vector((0.02, -0.01, 0.07)), (rng.uniform(-1, 1), rng.uniform(-1, -0.2), 0.45), 0.26, 0.085, mats['leaf'], leaf_label, rng)
    return o


def bm_carrot(K, name, tip, top, r, mats, label, leaf_label, rng):
    d = (top - tip); L = d.length; d.normalize(); prof = []
    path = [tip + d * L * t for t in [k / 24 for k in range(25)]]
    radii = [r * (0.12 + 0.88 * (t ** 0.55)) for t in [k / 24 for k in range(25)]]
    for k in range(1, 9):                              # v26 (owner: "make the carrots rounded at the top"): a domed shoulder
        th = math.pi / 2 * k / 9
        path.append(top + d * r * 0.7 * math.sin(th)); radii.append(r * math.cos(th))
    P, fr = pl_frames(path, (0, 0, 1)); m = 32; V = []; F = []
    for p, (T, N, Bv), rr in zip(P, fr, radii):
        for k in range(m):
            a = 2 * math.pi * k / m; V.append(p + N * math.cos(a) * rr + Bv * math.sin(a) * rr)
    for i in range(len(P) - 1):
        for k in range(m):
            F.append((i * m + k, i * m + (k + 1) % m, (i + 1) * m + (k + 1) % m, (i + 1) * m + k))
    F.append(tuple(reversed(range(m)))); F.append(tuple((len(P) - 1) * m + k for k in range(m)))
    o = bm_solid(K, name, V, F, mats['carrot'], label)
    for k in range(4):                                 # the carrot's ring marks: short tapered dashes across it
        t = 0.25 + 0.17 * k; p = tip + d * L * t; T, N, Bv = fr[int(t * 24)]; rr = radii[int(t * 24)]   # (dome rings follow index 24)
        a0 = rng.uniform(0.6, 1.6); pts = [p + (N * math.cos(a0 + q) + Bv * math.sin(a0 + q)) * rr * 1.03 for q in (-0.5, 0.0, 0.5)]
        ln = tagged_line(K, '%s_ring%d' % (name, k), [tuple(x) for x in pts], label, 3, False); ln['ink_tip'] = 0.2; ln['ink_centre'] = 1.0
    for k in range(4):                                 # leaves fanning up and back from the top, above the rim
        dirn = d * 0.5 + Vector(((k - 1.5) * 0.45, 0.2, 1.0))
        bm_leaf(K, '%s_leaf%d' % (name, k), top + d * r * 0.55, dirn, rng.uniform(0.34, 0.44), 0.075, mats['leaf'], leaf_label + k % 2, rng, fold=0.5)
    return o


def bm_dots(ob, below=0.62, amount=0.30):
    """dots on the bark turned from the light; none on the sawn ends"""
    me = ob.data
    at = me.attributes.get('icon_shade_occlusion') or me.attributes.new('icon_shade_occlusion', 'FLOAT', 'CORNER')
    for p in me.polygons:
        val = amount if p.material_index == 0 and p.normal.normalized().dot(LIGHT) < below else 0.0
        for li in p.loop_indices:
            at.data[li].value = val


def build_biomass():
    setup_icon_rig(); K = Kit(open_collection('ICON_biomass')); hosts = []
    bark = pl_toon('bm_bark', *BARK); sap = bm_end_toon('bm_sap', WOOD['sap'])
    end = {k: bm_end_toon('bm_' + k, v) for k, v in WOOD.items()}
    z_low = max(r for _, _, r, _, _ in LOGS[:2]) * 1.04; top_log = None
    for j, (x, y, R, L, seed) in enumerate(LOGS):
        if j < 2:
            z = R * 1.04
        else:                                          # resting in the groove of the two below
            gap = (LOGS[1][0] - LOGS[0][0]) / 2; z = z_low + math.sqrt(max(0.0, (R + LOGS[0][2]) ** 2 * 0.97 - gap ** 2))
        log, rim = bm_log(K, 'log%d' % j, (x, y, z), R, L, seed, [bark, sap], j + 1); hosts.append(log.name)
        if j == 2:
            top_log = (x, y, z, R)
        bpy.context.view_layer.update()
        bm_end(K, log, rim, end, j + 1, seed, check=(j == 2))
        bm_dashes(K, log, (x, y, z), R, L, seed + 50, j + 1)
        bm_dots(log)
    chip_mats = {k: pl_toon('bm_chip_' + k, *v) for k, v in CHIP.items()}
    heap = bm_heap(K, chip_mats, 4); hosts += [o.name for o in heap]
    for ob in K.col.objects:                           # dots on the heap's and the chips' shaded sides
        if ob.name.startswith(('chip', 'heap_base')):
            me = ob.data; at = me.attributes.get('icon_shade_occlusion') or me.attributes.new('icon_shade_occlusion', 'FLOAT', 'CORNER')
            for p in me.polygons:
                for li in p.loop_indices:
                    at.data[li].value = 0.30 if p.normal.dot(LIGHT) < 0.62 else 0.0
    # the basket of apples and carrots on the top log
    bk = {k: pl_toon('bm_bk_' + k, *v) for k, v in BK.items()}
    tx, ty, tz, tR = top_log; Bc = Vector((tx, BASKET['y'], tz + tR - BASKET['sink']))
    parts = bm_basket(K, bk, Bc); rim_z = Bc.z + BASKET['hgt']; rng = random.Random(41)
    for j, (ax, ay, r) in enumerate(APPLES):
        parts.append(bm_apple(K, 'apple%d' % j, Vector((Bc.x + ax, Bc.y + ay, rim_z - APPLE_SINK)), r, bk, L_APPLE0 + j, L_LEAF0 + j % 3, rng))
    for j, ((x0, y0), (x1, y1), r) in enumerate(CARROTS):
        tip = Vector((Bc.x + x0, Bc.y + y0, rim_z + CARROT_Z[0])); top = Vector((Bc.x + x1, Bc.y + y1, rim_z + CARROT_Z[1]))
        parts.append(bm_carrot(K, 'carrot%d' % j, tip, top, r, bk, L_CARROT0 + j, L_LEAF0 + 3, rng))
    for j, ((lx, ly, lz), dirn, ln_) in enumerate(LOOSE_LEAVES):
        bm_leaf(K, 'loose_leaf%d' % j, Vector((Bc.x + lx, Bc.y + ly, rim_z - lz)), dirn, ln_, 0.085, bk['leaf'], (31, 28, 29, 27)[j % 4], rng, fold=0.45)
    hosts += [o.name for o in parts]
    for ob in K.col.objects:
        if ob.name.startswith(('basket', 'apple', 'carrot')) and ob.type == 'MESH' and not ob.get('edge_ink'):
            bm_shade_dots(ob)
    bpy.context.view_layer.update()
    for n in hosts[:3]:
        pl_mesh_lines(K, bpy.data.objects[n], bpy.data.objects[n]['part_label'], 50.0, n, 0.03, contours=False)
    for ob in K.col.objects:
        if ob.get('ink_width') == 6:
            ob['ink_width'] = PL_INNER
    info = contract(K, hosts, 'Biomass: three wooden logs stacked two and one, sawn ends toward the viewer with bark rims, '
                    'growth rings and a drying check, furrowed bark; a heap of wood chips against the right log; a wicker basket of '
                    'apples and carrots on top', inner=PL_INNER)
    info['revision'] = BM_REVISION; info['outline']['component_boundaries'] = True
    info['outline']['min_fragment_px'] = 24
    info['outline']['id_step'] = 8                     # labels up to 31: logs 1-3, heap 4, chips 5-15, basket and produce 16-31
    info['outline']['component_weight_by_label'] = {str(k): 3 for k in HEAP['chip_labels']}   # thin chip outlines
    info['outline']['component_weight_by_label']['4'] = 3
    info['stipple']['strength'] = 0.34
    info['stipple']['groups'] = [{'name': 'shaded_faces', 'labels': list(range(1, 32)), 'thresholds': [0.575, 0.50, 0.30]}]
    return info
