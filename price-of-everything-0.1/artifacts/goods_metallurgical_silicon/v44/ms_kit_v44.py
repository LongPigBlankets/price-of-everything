"""Metallurgical silicon (g_047 metallurgical_silicon): the shipped art's topology. A rough cast log of crystalline silicon
lies along the view's rising diagonal (world Y, its broken end toward the viewer at the lower left). Its skin is a
patchwork of flat polygonal grain facets, mostly dark and mid blue-grey with a few pale, a few mirror-bright and a few
tan (oxide) ones, every facet edge inked thin. The broken end is a radial fan of facets meeting at a point. On the set's
grid, camera, light, 12/4 px ink and dots on the shaded sides."""
import random
MS_REVISION = 'metallurgical_silicon_v44'
LIGHT = Vector((0.06, -0.56, 0.83)).normalized()
# v10 (review: the per-grain colour fought the lighting, no bright crown): body kinds one tone step apart, lit steps high
TONES = {'dark': ((60, 66, 76), (82, 88, 98), (128, 134, 144)), 'mid': ((70, 78, 88), (96, 104, 114), (148, 156, 166)),
         'light': ((84, 92, 102), (116, 124, 134), (166, 174, 182)), 'mirror': ((150, 160, 174), (168, 178, 192), (196, 204, 216)),
         'tan': ((120, 104, 70), (150, 134, 92), (172, 156, 110)),
         'end': ((52, 60, 74), (72, 82, 98), (96, 106, 122)), 'end2': ((78, 90, 106), (104, 116, 132), (126, 138, 154)),
         'streak': ((250, 252, 255), (250, 252, 255), (250, 252, 255)),
         'side': ((96, 106, 120), (126, 136, 150), (150, 160, 174)), 'crev': ((30, 35, 48), (38, 44, 58), (46, 52, 66))}   # v25: crevices near-black blue (v24's read as more plate)
KINDS = ['dark', 'mid', 'light', 'mirror', 'tan', 'end', 'end2', 'side', 'crev']
# v2: v1's tilted ring planes swallowed each other (a few huge facets on a wedge). Tangent planes to an egg tile it
# into even polygons, as the shipped grains; two overlapping eggs give the log its waist
# v5: longer and slimmer (the shipped log is ~2.3:1 on screen), smaller grains; fan spokes alternate two tones
# v10 (review): fatter and shorter (2.22 -> ~2.0 on screen), a little fewer, larger grains; a mirror grain set on the
# crown of the middle and far eggs (~40% and ~75% along)
EGGS = [dict(c=(0.0, -0.70, 0.0), R=(0.63, 0.84, 0.62), n=64, seed=3, fan=True),
        dict(c=(0.03, 0.0, 0.02), R=(0.65, 0.82, 0.64), n=64, seed=8, fan=False, mirror_y=-0.15),
        dict(c=(-0.02, 0.70, 0.0), R=(0.62, 0.84, 0.63), n=64, seed=12, fan=False, mirror_y=0.62)]
# v10 (review: "a sliced pie, not a starburst"): 9 broad blades of uneven angle, deep enough to span the whole end,
# blades alternately dark and darker, one step under the body
FAN = dict(n=10, gap=(26.0, 50.0), t=(13.0, 13.0), apex=-0.50, cut=0.22)   # v11: one tilt again (v10's alternate tilts let the flat blades swallow the rest)
# grain chunks sunk into the skin: (azimuth deg about the log axis, 0 = +X, 90 = up; y; radius). v10 (review: the
# silhouette had 5 notches to the reference's 15): rows along the two silhouette lines (135 deg on top, -45 below)
CHUNKS = [(120, 0.40, 0.17), (35, 0.80, 0.16), (100, 1.10, 0.16),
          (140, -0.35, 0.13), (130, 0.15, 0.11), (138, 0.95, 0.12)]    # v14: none at the fan's rim
# v13: the row along the lower silhouette (-45 deg) left sliver facets that doubled the bottom line; dropped
CHUNK_AT = 0.56                                        # chunk centres from the axis (the skin is ~0.63 out)
# v15 (owner: "the body itself looks great. What needs more detail and a bit more relief is the round-ish face itself"):
# the log is cut flat at END['y'] and capped with a pleated radial fracture: uneven blades, each folded on a raised
# ridge with recessed valleys between, a kink partway out, a sunk centre, the blade tips standing proud of the rim
END = dict(flat=True, y=-0.84, blades=11,   # v17: cut nearer the widest point (behind -0.95 the body was wider and hid the face)
           gap=(20.0, 40.0), skew=(0.38, 0.62), apex_h=0.02, ridge_rim=(0.05, 0.09),
           chipped=2, proud=1.035, rim_steps=4, lift=0.015,   # v20: valleys proud of the cut (flush, the cut z-fought through)
           back=0.14, centre=(0.03, 0.04), seed=21,
           normal=(0.0, -1.0, 0.0))     # v28 (owner: "the original plane was better"): upright again (v24-v27 slanted it 0.45, -1, 0.30)
# v23 (owner: "the triangular slices need more complex shapes. Look at how the old icon does it"): the shipped end is
# ~10 petal-like shards, each a flat plate from a point at the centre widening outward to a broken, stepped end, split
# by dark V crevices (widening outward) in which their light side walls show; some split by a second fold
# v24: eight wider shards, deeper crevices (v23's ten read as thin triangles with no crevices showing)
# v25: kinked sides (broad irregular plates, crevices of varying width), deeper end steps, more tilt per shard
# v26: the shards fill the face to the rim, crevices narrow (v25 showed too much dark floor)
END_INK = 2.0                                          # px at 800: the end face's crack and plate lines (v44)
BEVEL = ((30.0, 0.88, 0.0, 12), (60.0, 0.99, 0.06, 12))   # v43: a narrower band, the face stays dominant   # (deg from the face normal, radius x, set back, facets)
SHARDS = dict(n=8, gap=(30.0, 60.0), inset=(3.4, 6.0), r0=0.04, centre_h=0.03, out_h=(0.06, 0.16), twist=0.06,
              ends=(3, 5), end_r=(0.91, 1.06), split=0.5, fold_h=0.035, base=0.02, seed=27,
              kink_r=(0.45, 0.65), kink=(-1.5, 2.5),
              terrace=0.6, terrace_w=(0.45, 0.7), terrace_r=(0.5, 0.82), terrace_h=0.03)   # v27: layered breaks, as shipped
# v28 (owner: "try a simpler fracture layout on that plane that doesnt emanate from a single point in the middle"):
# the face broken into a few irregular plates (a Voronoi split of the face, crevices between), each tilted on its own,
# stepped where it breaks at the rim, two with a raised terrace
# v29: the cells are cut by two or three jagged cracks right across the face (v28's straight Voronoi cells read as more
# body grains, and its terraces as machined steps); low walls, dark crevices
# v30: the face is seen steeply, so the main cracks run up and down it (0 deg = up the face, 90 = across); bigger zigzags
PLATES = dict(cracks=((-10, 175, 0.06), (-62, 118, -0.08), (-120, 30, 0.05), (35, 200, 0.20), (100, 275, -0.16), (150, 330, 0.22)),
              # v41: every crack joins rim angles 150+ deg apart (closer pairs ran outside the face), bowed to one side
              min_area=0.045, min_round=0.024,   # v39: a crack is skipped where it would leave a sliver (v38's stacked into railroad lines)
             
              zig=(0.06, 0.11), segs=7,
              crevice=0.02, h=(0.03, 0.06),   # v44: narrower crevices (owner: thinner lines between the cracks)
              tilt=(0.12, 0.18), up=0.75,   # v33: most plates tip UP into the light, small
              rim_step=(1.0, 1.02), run=(3, 6), base=0.02, seed=31)   # v31: rim steps outward only; v38: small, the bevel takes the edge
KIND_SHARE = dict(mirror=0, tan=2, light=3, mid=0.55)    # per egg; the mirrors are placed (mirror_y)


def end_frame(zc):
    """the broken end's plane: centre, outward normal, and two in-plane axes (u up the face, v across)"""
    n = Vector(END['normal']).normalized(); C = Vector((END['centre'][0], END['y'], zc + END['centre'][1]))
    u = (Vector((0, 0, 1)) - n * n.z).normalized(); v = n.cross(u).normalized()
    return C, n, u, v


def ms_egg_planes(E, zc):
    """tangent planes to an ellipsoid at jittered Fibonacci points: (point, outward normal, kind or None). With fan,
    the planes looking down -Y are replaced by a fan through one apex point (the broken end)"""
    rng = random.Random(E['seed']); c = Vector(E['c']) + Vector((0, 0, zc)); R = Vector(E['R']); out = []
    n = E['n']; ga = math.pi * (3 - math.sqrt(5))
    for i in range(n):
        y = 1 - 2 * (i + 0.5) / n; rr = math.sqrt(1 - y * y); t = ga * i + rng.uniform(-0.25, 0.25)
        d = Vector((rr * math.cos(t), y, rr * math.sin(t)))      # the Fibonacci axis runs along world Y, the log's
        d = (d + Vector((rng.uniform(-0.08, 0.08), rng.uniform(-0.08, 0.08), rng.uniform(-0.08, 0.08)))).normalized()
        if E['fan'] and d.y < -FAN['cut']:
            continue
        p = Vector((d.x * R.x, d.y * R.y, d.z * R.z)); nrm = Vector((d.x / R.x, d.y / R.y, d.z / R.z)).normalized()
        out.append((c + p * rng.uniform(0.97, 1.03), nrm, None))
    if E['fan'] and END.get('flat'):                   # v15: cut flat; the pleated fracture cap sits on the cut
        out.append((end_frame(zc)[0], end_frame(zc)[1], 'end'))
        # v38 (owner: "a gentler bevel at the corner between the cylinder and the round face"): two rings of bevel
        # facets round the corner, kinds fixed by their own seed so the body's grains keep theirs
        C_, n_, u_, v_ = end_frame(zc); rb = random.Random(77)
        r_ = math.sqrt(max(0.0, 1 - ((C_.y - c.y) / R.y) ** 2)) * (R.x + R.z) / 2
        for ring, (ang, rad, back, m_) in enumerate(BEVEL):
            for k in range(m_):
                a = 2 * math.pi * (k + 0.5 * ring + rb.uniform(-0.12, 0.12)) / m_; d = u_ * math.cos(a) + v_ * math.sin(a)
                nb = (n_ * math.cos(math.radians(ang)) + d * math.sin(math.radians(ang))).normalized()
                kind = rb.choices(['mid', 'dark', 'light'], [0.5, 0.35, 0.15])[0]
                out.append((C_ + d * r_ * rad - n_ * back, nb, kind))
    elif E['fan']:
        apex = c + Vector((0.02, -R.y - FAN['apex'], 0.03))
        gaps = [rng.uniform(*FAN['gap']) for _ in range(FAN['n'])]; gaps = [g * 360.0 / sum(gaps) for g in gaps]; acc = 0.0
        for k in range(FAN['n']):
            a = math.radians(acc); acc += gaps[k]; t = math.radians(FAN['t'][k % 2])
            out.append((apex, Vector((math.cos(a) * math.sin(t), -math.cos(t), math.sin(a) * math.sin(t))).normalized(), ('end', 'end2')[k % 2]))
    return out


def ms_poly(name, planes, kinds):
    bm = bmesh.new(); bmesh.ops.create_cube(bm, size=8.0)
    for f in bm.faces:
        f.material_index = 0
    for i, (co, no, kind) in enumerate(planes):
        bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], plane_co=co, plane_no=no, clear_outer=True)
        for f in bmesh.ops.holes_fill(bm, edges=[e for e in bm.edges if e.is_boundary], sides=0)['faces']:
            f.material_index = KINDS.index(kind or kinds[i])
    bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=1e-5)
    me = bpy.data.meshes.new(name); bm.to_mesh(me); bm.free()
    return me


def ms_kinds(planes, rng, share):
    body = [i for i, p in enumerate(planes) if p[2] is None]
    lit = [i for i in body if planes[i][1].dot(LIGHT) > 0.5 and planes[i][1].dot(VIEW) > 0.3]
    seen = [i for i in body if planes[i][1].dot(VIEW) > 0.05]
    kinds = {}
    for i in rng.sample(lit, min(share['mirror'], len(lit))):
        kinds[i] = 'mirror'
    for k in ('tan', 'light'):                        # v9: no two of a kind side by side (two tans read as one slab)
        pool = [i for i in seen if i not in kinds]
        if k == 'tan':                                 # v10 (review): tan sits on the lower near flank, as shipped
            pool = [i for i in pool if planes[i][1].z < 0.15 and planes[i][1].dot(VIEW) > 0.3]
        rng.shuffle(pool); got = []
        for i in pool:
            if len(got) == share[k]:
                break
            if all(planes[i][1].dot(planes[j][1]) < 0.80 for j in got):
                got.append(i)
        for i in got:
            kinds[i] = k
    for i in body:
        kinds.setdefault(i, 'mid' if rng.random() < share['mid'] else 'dark')
    return kinds


def ms_log(K, name, mats, label, zc=0.60):        # v13: the ground cut kept tiny (an edge-on base drew slivers)
    parts = []
    for j, E in enumerate(EGGS):
        planes = ms_egg_planes(E, zc); kinds = ms_kinds(planes, random.Random(E['seed'] + 100), KIND_SHARE)
        if E.get('mirror_y') is not None:              # the crown grain nearest the target, pushed in so its facet grows
            D = (LIGHT + VIEW).normalized()
            i = max((i for i, p in enumerate(planes) if p[2] is None), key=lambda i: planes[i][1].dot(D) - 1.5 * abs(planes[i][0].y - E['mirror_y']))
            planes[i] = (planes[i][0] - planes[i][1] * 0.025, planes[i][1], None); kinds[i] = 'mirror'
        parts.append(K.obj('%s_%d' % (name, j), ms_poly('%s_%d' % (name, j), planes, kinds), mats[KINDS[0]], False))
        for k in KINDS[1:]:
            parts[-1].data.materials.append(mats[k])
    for j, (az, y, r) in enumerate(CHUNKS):            # a small grain polyhedron sunk half into the skin
        a = math.radians(az); d = Vector((math.cos(a), 0, math.sin(a)))
        E = dict(c=tuple(Vector((0, y, 0)) + d * CHUNK_AT), R=(r, r * 1.15, r), n=16, seed=40 + j, fan=False)
        planes = ms_egg_planes(E, zc); kinds = ms_kinds(planes, random.Random(140 + j), dict(mirror=0, tan=0, light=0, mid=0.5))
        parts.append(K.obj('%s_chunk%d' % (name, j), ms_poly('%s_chunk%d' % (name, j), planes, kinds), mats[KINDS[0]], False))
        for k in KINDS[1:]:
            parts[-1].data.materials.append(mats[k])
    o = parts[0]
    for other in parts[1:]:
        mod = o.modifiers.new('union', 'BOOLEAN'); mod.operation = 'UNION'; mod.solver = 'EXACT'; mod.object = other
        bpy.context.view_layer.update()
        me = bpy.data.meshes.new_from_object(o.evaluated_get(bpy.context.evaluated_depsgraph_get()))
        o.modifiers.remove(mod); old = o.data; o.data = me; bpy.data.meshes.remove(old)
        bpy.data.objects.remove(other, do_unlink=True)
    bm = bmesh.new(); bm.from_mesh(o.data)
    bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], plane_co=(0, 0, 0.0), plane_no=(0, 0, -1), clear_outer=True)
    bmesh.ops.holes_fill(bm, edges=[e for e in bm.edges if e.is_boundary], sides=0)
    bmesh.ops.dissolve_degenerate(bm, dist=1e-5, edges=bm.edges[:]); bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    bm.to_mesh(o.data); bm.free(); o.data.update(); o.name = name
    noink(o); o['part_label'] = label
    return o


def ms_end_cap(K, name, log, mats, label, zc):
    """the broken end: a closed solid whose front is a pleated radial fracture fitted to the log's cut, sides running
    back into the log. Each blade is two folds from the centre: valley edge (flush) up to a raised ridge, down to the
    next valley. Each fold is a fan of thin triangles whose rim follows the log's outline (ray-cast from the axis), so
    only the ridges, valleys and rim bend enough to ink.
    v16: v15's kinked blades (mid-radius points, triangulated quads) inked a crease on every diagonal, and its straight
    rim chords left slivers of the log's cut showing"""
    from mathutils.bvhtree import BVHTree
    P = END; rng = random.Random(P['seed']); me = log.data; mw = log.matrix_world
    tree = BVHTree.FromPolygons([mw @ v.co for v in me.vertices], [tuple(p.vertices) for p in me.polygons])
    y0 = P['y']; cx, cz = P['centre'][0], zc + P['centre'][1]
    def rim(theta):
        d = Vector((math.cos(theta), 0, math.sin(theta))); o = Vector((cx, y0 + 0.004, cz))
        hit = tree.ray_cast(o, d, 3.0)
        return (hit[0] - o).length if hit[0] is not None else 0.5
    gaps = [rng.uniform(*P['gap']) for _ in range(P['blades'])]; gaps = [math.radians(g * 360.0 / sum(gaps)) for g in gaps]
    acc = math.radians(rng.uniform(0, 360)); chipped = set(rng.sample(range(P['blades']), P['chipped']))
    V = [Vector((cx, y0 - P['apex_h'] - P['lift'], cz))]; F = []; mat = []; rim_ids = []
    for k, g in enumerate(gaps):
        va = acc; ra = va + g * rng.uniform(*P['skew']); nxt = va + g; acc = nxt
        hr = 0.012 if k in chipped else rng.uniform(*P['ridge_rim'])
        for half, (t0, t1, h0, h1) in enumerate(((va, ra, 0.0, hr), (ra, nxt, hr, 0.0))):
            steps = P['rim_steps']
            for j in range(steps):                     # the fold's rim samples, its last one the next fold's first
                f = j / steps; t = t0 + (t1 - t0) * f; h = h0 + (h1 - h0) * f
                w = h / max(hr, 1e-6) if hr > 0 else 0.0
                r = rim(t) * (1.0 + (P['proud'] - 1.0) * w)
                rim_ids.append(len(V)); V.append(Vector((cx + math.cos(t) * r, y0 - h - P['lift'], cz + math.sin(t) * r)))
                mat.append(half)
    for v in V:                                        # the proud tips at the bottom rest on the ground (before the folds
        v.z = max(v.z, 0.003)                          # are flattened: clamping after bent them back into two tones)
    m = len(rim_ids); steps = P['rim_steps']
    for f0 in range(0, m, steps):                      # v19: each fold flat (one tone): its inner rim samples slid along
        A = V[0]; a = V[rim_ids[f0]]; b = V[rim_ids[(f0 + steps) % m]]   # y onto the plane through the centre and its ends
        n = (a - A).cross(b - A)
        if abs(n.y) > 1e-6:
            for j in range(1, steps):
                q = V[rim_ids[f0 + j]]; q.y -= (q - A).dot(n) / n.y
    for j in range(m):
        F.append((0, rim_ids[j], rim_ids[(j + 1) % m]))
    back = []
    for i in rim_ids:                                  # the sides run back into the log
        q = V[i]; d = Vector((q.x - cx, 0, q.z - cz)); back.append(len(V))
        V.append(Vector((cx, y0 + P['back'], cz)) + d * 0.94)
    for j in range(m):
        F.append((rim_ids[j], back[j], back[(j + 1) % m], rim_ids[(j + 1) % m])); mat.append(2)
    bc = len(V); V.append(Vector((cx, y0 + P['back'], cz)))
    for j in range(m):
        F.append((back[(j + 1) % m], back[j], bc)); mat.append(2)
    for v in V[bc - m:]:                               # the sides' back ring too
        v.z = max(v.z, 0.003)
    cm = bpy.data.meshes.new(name); cm.from_pydata([tuple(v) for v in V], [], F); cm.update()
    for poly, mi in zip(cm.polygons, mat):
        poly.material_index = mi
    bm = bmesh.new(); bm.from_mesh(cm); bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:]); bm.to_mesh(cm); bm.free()
    o = K.obj(name, cm, mats['end'], False); o.data.materials.append(mats['end2']); o.data.materials.append(mats['dark'])
    noink(o); o['part_label'] = label
    return o


def ms_end_shards(K, name, log, mats, label, zc):
    """the broken end as the shipped art draws it: a recessed dark disc fitted to the log's cut, and on it petal shards
    radiating from the centre, each a flat plate (or two, split by a fold) widening to a broken, stepped end, with dark
    V crevices between them. Built in the end plane's frame. Returns the solids (disc first)."""
    from mathutils.bvhtree import BVHTree
    P = SHARDS; E = END; rng = random.Random(P['seed']); me = log.data; mw = log.matrix_world
    tree = BVHTree.FromPolygons([mw @ v.co for v in me.vertices], [tuple(p.vertices) for p in me.polygons])
    C, n, u, v = end_frame(zc); lift = E['lift']
    def rim(theta):
        d = u * math.cos(theta) + v * math.sin(theta); o = C - n * 0.004
        hit = tree.ray_cast(o, d, 3.0)
        return (hit[0] - o).length if hit[0] is not None else 0.5
    def pt(theta, r, h=0.0):
        d = u * math.cos(theta) + v * math.sin(theta)
        if d.z < 0:                                    # nothing below the ground: shorten a low radius
            r = min(r, (C.z + n.z * lift - 0.006) / -d.z)
        return C + d * r + n * (lift + h)
    def flatten(pts, a, b, c):                         # onto the plane through a, b, c, sliding along the end's normal
        N = (b - a).cross(c - a)
        for q in pts:
            q -= n * (N.dot(q - a) / N.dot(n))
    def solid(nm, top_polys, outline, side_mat, mats_list, depth):
        V = []; F = []; mi = []; key = {}
        def vid(p):
            k = (round(p.x, 6), round(p.y, 6), round(p.z, 6))
            if k not in key:
                key[k] = len(V); V.append(p.copy())
            return key[k]
        for poly, m in top_polys:
            F.append([vid(p) for p in poly]); mi.append(m)
        top = [vid(p) for p in outline]; bot = []
        for p in outline:                              # the underside: the same outline behind the end plane
            q = p - n * ((p - C).dot(n) + depth); q.z = max(q.z, 0.003)     # inside the log; kept off the ground
            bot.append(len(V)); V.append(q)
        k_ = len(outline)
        for j in range(k_):
            F.append([top[j], bot[j], bot[(j + 1) % k_], top[(j + 1) % k_]]); mi.append(side_mat)
        F.append(list(reversed(bot))); mi.append(side_mat)
        cm = bpy.data.meshes.new(nm); cm.from_pydata([tuple(p) for p in V], [], F); cm.update()
        for poly, m in zip(cm.polygons, mi):
            poly.material_index = m
        bm = bmesh.new(); bm.from_mesh(cm); bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:]); bm.to_mesh(cm); bm.free()
        o = K.obj(nm, cm, mats[mats_list[0]], False)
        for k in mats_list[1:]:
            o.data.materials.append(mats[k])
        noink(o); o['part_label'] = label
        return o
    out = []
    ring = [pt(2 * math.pi * j / 72, rim(2 * math.pi * j / 72)) for j in range(72)]
    out.append(solid(name + '_floor', [(ring, 0)], ring, 0, ['crev'], E['back']))
    gaps = [rng.uniform(*P['gap']) for _ in range(P['n'])]; gaps = [math.radians(g * 360.0 / sum(gaps)) for g in gaps]
    edges = [math.radians(rng.uniform(0, 360))]
    for g in gaps[:-1]:
        edges.append(edges[-1] + g)
    insets = [math.radians(rng.uniform(*P['inset'])) for _ in range(P['n'])]
    for k in range(P['n']):
        a1 = edges[k] + insets[k]; a2 = edges[k] + gaps[k] - insets[(k + 1) % P['n']]
        r0 = P['r0']; I1, I2, Ic = pt(a1, r0), pt(a2, r0), pt((a1 + a2) / 2, r0 * 0.5)
        k1 = a1 - math.radians(rng.uniform(*P['kink'])); k2 = a2 + math.radians(rng.uniform(*P['kink']))   # side kinks: + widens
        S1, S2 = pt(k1, rim(k1) * rng.uniform(*P['kink_r'])), pt(k2, rim(k2) * rng.uniform(*P['kink_r']))
        O1, O2 = pt(a1, rim(a1) * rng.uniform(*P['end_r'])), pt(a2, rim(a2) * rng.uniform(*P['end_r']))
        m = rng.randint(*P['ends']); ends = []
        for i in range(m):                             # the broken end: a stepped zigzag between the two sides
            t = a1 + (a2 - a1) * (i + 1) / (m + 1) + (a2 - a1) * rng.uniform(-0.08, 0.08)
            f = rng.uniform(*P['end_r']) if i % 2 else rng.uniform(P['end_r'][0], (P['end_r'][0] + P['end_r'][1]) / 2)
            ends.append(pt(t, rim(t) * f))
        hout = rng.uniform(*P['out_h']); tw = rng.uniform(-P['twist'], P['twist'])
        c0, o1, o2 = Ic + n * P['centre_h'], O1 + n * (hout + tw), O2 + n * (hout - tw)
        outline = [Ic.copy(), I1.copy(), S1.copy(), O1.copy()] + [e.copy() for e in ends] + [O2.copy(), S2.copy(), I2.copy()]
        if rng.random() < P['split'] and m >= 3:       # a second fold from the centre out to a middle end point
            j = 4 + m // 2; em = outline[j] + n * (hout + P['fold_h'] + abs(tw))
            left, right = outline[:j + 1], [outline[0]] + outline[j:]
            flatten(left, c0, o1, em); flatten(right, c0, em, o2)
            right[0] = left[0]; right[1] = left[-1]
            outline = left + right[2:]
            tops = [(left, 0), (right, 0)]
        else:
            flatten(outline, c0, o1, o2); tops = [(outline, 0)]
            if rng.random() < P['terrace']:            # a smaller plate stepped up on one side of the shard
                w = rng.uniform(*P['terrace_w']); left_side = rng.random() < 0.5
                b1, b2 = (a1, a1 + (a2 - a1) * w) if left_side else (a2 - (a2 - a1) * w, a2)
                rr = rng.uniform(*P['terrace_r']); q = rng.randint(2, 3)
                tp = [pt((b1 + b2) / 2, r0 * 0.8), pt(b1, r0 * 1.6), pt(b1, rim(b1) * rr * rng.uniform(0.9, 1.05))]
                for i in range(q):
                    t = b1 + (b2 - b1) * (i + 1) / (q + 1)
                    tp.append(pt(t, rim(t) * rr * (rng.uniform(0.82, 0.92) if i % 2 == 0 else rng.uniform(0.98, 1.08))))
                tp += [pt(b2, rim(b2) * rr * rng.uniform(0.9, 1.05)), pt(b2, r0 * 1.6)]
                flatten(tp, c0, o1, o2)
                tp = [p_ + n * P['terrace_h'] for p_ in tp]
                out.append(solid('%s_step%d' % (name, k), [(tp, 0)], tp, 1, ['end', 'side'], P['base']))
        out.append(solid('%s_shard%d' % (name, k), tops, outline, 1, ['end', 'side'], P['base']))
    return out


def ms_end_plates(K, name, log, mats, label, zc):
    """the broken end as a few irregular plates: the face (fitted to the log's cut by rays from the axis) split into
    Voronoi cells, each shrunk by half a crevice, given its own tilted plane and a stepped edge where it meets the rim;
    a near-black disc behind shows in the crevices. Returns the solids (disc first)."""
    from mathutils.bvhtree import BVHTree
    P = PLATES; E = END; rng = random.Random(P['seed']); me = log.data; mw = log.matrix_world
    tree = BVHTree.FromPolygons([mw @ v.co for v in me.vertices], [tuple(p.vertices) for p in me.polygons])
    C, n, u, v = end_frame(zc); lift = E['lift']
    def rim(theta):
        d = u * math.cos(theta) + v * math.sin(theta); o = C - n * 0.004
        hit = tree.ray_cast(o, d, 3.0)
        return (hit[0] - o).length if hit[0] is not None else 0.5
    def at(q, h=0.0):                                  # face coordinates (along u, along v) and height -> world
        return C + u * q.x + v * q.y + n * (lift + h)
    floor_a = -(at(Vector((0, 0))).z - 0.006) / max(u.z, 1e-6)    # nothing below the ground
    face = [Vector((math.cos(t), math.sin(t))) * rim(t) for t in (2 * math.pi * j / 96 for j in range(96))]
    face = ms_clip(face, Vector((-1, 0)), Vector((floor_a, 0)))
    def solid(nm, tops, outline, side_mat, mats_list, depth):
        V = []; F = []; mi = []; key = {}
        def vid(p):
            k = (round(p.x, 6), round(p.y, 6), round(p.z, 6))
            if k not in key:
                key[k] = len(V); V.append(p.copy())
            return key[k]
        for poly, m in tops:
            F.append([vid(p) for p in poly]); mi.append(m)
        top = [vid(p) for p in outline]; bot = []
        for p in outline:
            q = p - n * ((p - C).dot(n) + depth); q.z = max(q.z, 0.003)
            bot.append(len(V)); V.append(q)
        k_ = len(outline)
        for j in range(k_):                            # side_mat: one material, or one per outline edge
            F.append([top[j], bot[j], bot[(j + 1) % k_], top[(j + 1) % k_]]); mi.append(side_mat[j] if isinstance(side_mat, list) else side_mat)
        F.append(list(reversed(bot))); mi.append(side_mat[0] if isinstance(side_mat, list) else side_mat)
        cm = bpy.data.meshes.new(nm); cm.from_pydata([tuple(p) for p in V], [], F); cm.update()
        for poly, m in zip(cm.polygons, mi):
            poly.material_index = m
        bm = bmesh.new(); bm.from_mesh(cm); bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:]); bm.to_mesh(cm); bm.free()
        o = K.obj(nm, cm, mats[mats_list[0]], False)
        for k in mats_list[1:]:
            o.data.materials.append(mats[k])
        noink(o); o['part_label'] = label
        return o
    out = []
    ring = [at(q) for q in face]
    # v36: the floor's walls short and in the body's tone (0.14 deep, they poked out where the log's skin dips in)
    out.append(solid(name + '_floor', [(ring, 0)], ring, 1, ['crev', 'dark'], 0.03))
    def crack(a0, a1, off):
        """a jagged line across the face from rim angle a0 to a1 (deg), bowed sideways by off, ends well outside"""
        p0 = Vector((math.cos(math.radians(a0)), math.sin(math.radians(a0)))) * 1.4
        p1 = Vector((math.cos(math.radians(a1)), math.sin(math.radians(a1)))) * 1.4
        d = (p1 - p0); side = Vector((-d.y, d.x)).normalized(); pts = []
        for k in range(P['segs'] + 1):
            t = k / P['segs']; z = 0.0 if k in (0, P['segs']) else rng.uniform(*P['zig']) * (1 if k % 2 else -1)
            pts.append(p0 + d * t + side * (off * math.sin(math.pi * t) + z))
        return pts
    def split(poly, line):
        """cut a polygon by a polyline crossing it once (in at one edge, out at another): two polygons, or None"""
        hits = []
        for si in range(len(line) - 1):
            a, b = line[si], line[si + 1]
            for ei in range(len(poly)):
                c, d = poly[ei], poly[(ei + 1) % len(poly)]
                den = (b - a).cross(d - c)
                if abs(den) < 1e-12:
                    continue
                t = (c - a).cross(d - c) / den; w = (c - a).cross(b - a) / den
                if 0 <= t <= 1 and 0 <= w <= 1:
                    hits.append((si + t, si, ei, a + (b - a) * t))
        if len(hits) < 2:
            return None
        hits.sort(key=lambda h: h[0]); (_, s1, e1, A), (_, s2, e2, B) = hits[0], hits[1]
        path = [A] + [line[k] for k in range(s1 + 1, s2 + 1)] + [B]
        m = len(poly); one = list(path); k = (e2 + 1) % m
        while True:
            one.append(poly[k])
            if k == e1:
                break
            k = (k + 1) % m
        two = list(reversed(path)); k = (e1 + 1) % m
        while True:
            two.append(poly[k])
            if k == e2:
                break
            k = (k + 1) % m
        return one, two
    def inset(poly, d):                                # shrink by d along each corner's bisector (mitre capped)
        out_ = []; m = len(poly); area = sum(poly[i].cross(poly[(i + 1) % m]) for i in range(m))
        sgn = 1 if area > 0 else -1
        for i in range(m):
            a, b, c = poly[i - 1], poly[i], poly[(i + 1) % m]
            e1 = (b - a).normalized(); e2 = (c - b).normalized()
            n1 = Vector((-e1.y, e1.x)) * sgn; n2 = Vector((-e2.y, e2.x)) * sgn
            bis = (n1 + n2); L = bis.length
            out_.append(b + (bis / L) * min(d / max(L / 2, 0.35), d * 2.5) if L > 1e-6 else b + n1 * d)
        return out_
    plates = [list(face)]
    area = lambda pl: abs(sum(pl[i].cross(pl[(i + 1) % len(pl)]) for i in range(len(pl)))) / 2
    perim = lambda pl: sum((pl[(i + 1) % len(pl)] - pl[i]).length for i in range(len(pl)))
    for a0, a1, off in P['cracks']:
        line = crack(a0, a1, off); nxt = []
        for pl in plates:
            r = split(pl, line)
            if r and all(len(x) >= 3 and area(x) > P['min_area'] and area(x) / perim(x) ** 2 > P['min_round'] for x in r):
                nxt += list(r)
            else:
                nxt.append(pl)
        plates = nxt
    built = []
    for i, cell in enumerate(plates):
        rim_pts = [k for k, q in enumerate(cell) if abs(q.length - rim(math.atan2(q.y, q.x))) < 0.01]
        f = 1.0; run = 0                               # the broken edge at the rim: runs pushed in or out, a step between
        for k in rim_pts:
            if run <= 0:
                f = rng.uniform(P['rim_step'][0], 1.0) if f >= 1.0 else rng.uniform(1.0, P['rim_step'][1]); run = rng.randint(*P['run'])
            q = cell[k] * f
            if q.x >= floor_a:
                cell[k] = q
            run -= 1
        on_rim = [abs(q.length - rim(math.atan2(q.y, q.x))) < 0.012 or q.length > rim(math.atan2(q.y, q.x)) for q in cell]
        shrunk = inset(cell, P['crevice'] / 2)         # v32: only the crack edges shrink; the rim stays (a dark ring showed)
        m_ = len(cell)
        cell = [cell[k] if on_rim[k] and on_rim[k - 1] and on_rim[(k + 1) % m_] else shrunk[k] for k in range(m_)]
        cen = sum(cell, Vector((0, 0))) / len(cell); h0 = rng.uniform(*P['h'])
        if rng.random() < P['up']:                     # (v32's large random tilts raised tall walls along the cracks)
            g = Vector((-1.0, rng.uniform(-0.5, 0.5))).normalized() * rng.uniform(*P['tilt'])
        else:
            g = Vector((rng.uniform(-1, 1), rng.uniform(-1, 1))).normalized() * rng.uniform(*P['tilt']) * 0.4
        h0 += max(0.0, 0.012 - min(h0 + g.dot(q - cen) for q in cell))   # v35: the whole plate in front of the floor
        top = [at(q, h0 + g.dot(q - cen)) for q in cell]                  # (v34 clamped then re-flattened: tipped plates
                                                                          # dipped behind the floor, which showed through)
        # v31: crack walls dark, so cracks read dark; v34: walls along the rim take the body's tone (a dark band showed)
        walls = [2 if on_rim[k] and on_rim[(k + 1) % m_] else 1 for k in range(m_)]
        built.append((top, walls, -g.x, abs(sum(cell[k].cross(cell[(k + 1) % m_]) for k in range(m_))) / 2))
    # v38 (owner: "add the same lighting and reflective surfaces as the cylinder surface"): the plates take the body's
    # kinds: the most up-tipped large plate a mirror (with the streak), the next pale, the rest mid or dark
    order = sorted(range(len(built)), key=lambda i: -built[i][2] if built[i][3] > 0.10 else 9)   # v40: mirror on a broad plate
    kinds = {order[0]: 'mirror', order[1]: 'light'}
    for i, (top, walls, _, _) in enumerate(built):
        kind = kinds.get(i) or ('mid' if rng.random() < 0.55 else 'dark')
        out.append(solid('%s_plate%d' % (name, i), [(top, 0)], top, walls, [kind, 'crev', 'dark'], P['base']))
    return out


def ms_clip(poly, n, c):
    """Sutherland-Hodgman: the part of a convex 2D polygon where (p - c) . n <= 0"""
    out = []
    for i in range(len(poly)):
        a, b = poly[i], poly[(i + 1) % len(poly)]
        da, db = (a - c).dot(n), (b - c).dot(n)
        if da <= 0:
            out.append(a)
        if (da <= 0) != (db <= 0):
            out.append(a + (b - a) * (da / (da - db)))
    return out


def ms_streaks(K, host, mat, label, bands=((-0.12, 0.16), (0.20, 0.06))):
    """the mirror facets' reflection: white bands across each one, running up the screen's rising diagonal, clipped to
    the facet; bands = (offset from the facet centre, width) as fractions of the facet's size"""
    me = host.data; mw = host.matrix_world; n_ = 0
    for p in me.polygons:
        if not me.materials[p.material_index].name.startswith('ms_mirror') or p.area < 0.01:
            continue
        N = (mw.to_3x3() @ p.normal).normalized(); C = mw @ p.center
        run = (Vector((0.35, 1.0, 0.6)) - N * N.dot(Vector((0.35, 1.0, 0.6)))).normalized(); across = N.cross(run).normalized()
        P2 = [Vector(((mw @ me.vertices[i].co - C).dot(across), (mw @ me.vertices[i].co - C).dot(run))) for i in p.vertices]
        size = max(v.length for v in P2)
        for off, w in bands:
            c0 = Vector((off * size, 0)); poly = ms_clip(P2, Vector((1, 0)), c0 + Vector((w * size / 2, 0)))
            poly = ms_clip(poly, Vector((-1, 0)), c0 - Vector((w * size / 2, 0)))
            if len(poly) < 3:
                continue
            vs = [tuple(C + N * 0.004 + across * q.x + run * q.y) for q in poly]
            nm = '%s_streak%d' % (host.name, n_)
            sm = bpy.data.meshes.new(nm); sm.from_pydata(vs, [], [tuple(range(len(vs)))]); sm.update()
            o = K.obj(nm, sm, mat, False); noink(o); o['part_label'] = label; o.pass_index = 73; n_ += 1
    return n_


def ms_dots(ob, below=0.62, amount=0.30):
    """dots on every face not turned to the light, via the mask's occlusion attribute"""
    me = ob.data
    at = me.attributes.get('icon_shade_occlusion') or me.attributes.new('icon_shade_occlusion', 'FLOAT', 'CORNER')
    for p in me.polygons:
        val = amount if p.normal.normalized().dot(LIGHT) < below else 0.0
        for li in p.loop_indices:
            at.data[li].value = val


def build_metallurgical_silicon():
    setup_icon_rig(); K = Kit(open_collection('ICON_metallurgical_silicon')); hosts = []
    mats = {k: pl_toon('ms_' + k, *v) for k, v in TONES.items()}
    L_LOG, L_END = 1, 2                                  # v18: the cap its own part, so its seam with the body inks
    log = ms_log(K, 'silicon_log', mats, L_LOG); hosts.append(log.name)
    bpy.context.view_layer.update()
    shards = ms_end_plates(K, 'end_fracture', log, mats, L_END, 0.60); hosts.append(shards[0].name)
    for j, o in enumerate(shards[1:]):                 # v42: each plate its own part, so seams where tilted plates
        o['part_label'] = min(L_END + 1 + j, 15)       # overlap are inked (one shared label left them bare)
    ms_dots(log)
    for o in shards:
        ms_dots(o)
    ms_streaks(K, log, mats['streak'], L_LOG)
    for o in shards[1:]:
        ms_streaks(K, o, mats['streak'], o['part_label'])
    bpy.context.view_layer.update()
    pl_mesh_lines(K, log, L_LOG, 4.0, 'grain', 0.03, contours=False)   # every grain edge, thin
    for o in shards:                                   # every plate edge, its turned-away edges too (v31)
        pl_mesh_lines(K, o, o['part_label'], 2.0, o.name, 0.02, contours=True)
    for ob in K.col.objects:                           # v44: the end's lines thin (owner: "thinner lines between the cracks")
        if ob.get('line_path') and ob.name.startswith('end_fracture'):
            ob['ink_width'] = END_INK
    for ob in [o for o in K.col.objects if o.name.startswith('grain_line')]:   # v17: the log's cut edges sit under the cap
        pts = ob.get('line_path')
        C_, n_ = end_frame(0.60)[:2]
        if pts and all((Vector(list(pts)[i:i + 3]) - C_).dot(n_) > -0.03 for i in range(0, len(pts), 3)):
            bpy.data.objects.remove(ob, do_unlink=True)
    for ob in K.col.objects:
        if ob.get('ink_width') == 6:
            ob['ink_width'] = PL_INNER
    info = contract(K, hosts, 'Metallurgical silicon: a rough cast log of flat polygonal grain facets, dark and mid blue-grey '
                    'with pale, mirror-bright and tan ones, its near end a radial fan of facets', inner=PL_INNER)
    info['revision'] = MS_REVISION; info['outline']['component_boundaries'] = True
    info['outline']['min_fragment_px'] = 24             # v14: no stubs where a raised grain hides most of a line
    info['stipple']['strength'] = 0.34
    info['outline']['id_step'] = 16                    # v42: up to 15 parts (the plates)
    info['outline']['component_weight_by_label'] = {str(k): END_INK for k in range(L_END, 16)}   # v44: thin seams on the end
    info['stipple']['groups'] = [{'name': 'shaded_faces', 'labels': list(range(1, 16)), 'thresholds': [0.575, 0.50, 0.30]}]
    return info
