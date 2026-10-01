"""REE ore (g_032 ree_ore): the shipped art's group: a brown host rock at the back left, a large tan rock mottled with
blue-grey, purple and green mineral patches in the middle, a grey fluted hexagonal crystal on the right, and a red
horseshoe magnet with pale pole ends lying in front (what rare earths become). Angular faceted rocks, as the approved
ores; on the set's grid, camera, light, 12/4 px ink and dots on the shaded sides."""
import random
from mathutils import noise as mnoise
REE_REVISION = 'ree_ore_v19'
TOP_ROLL = 0.0
TOP_SLANT = 10.0                                   # v18: the top square to the lean, tipped 10 deg toward the viewer (as shipped)
CRY_TOWARD = 0.0
MAG_TOWARD = 0.20
MAG_RIGHT = 0.06
MAG_FWD = 0.06                                     # v19: the magnet ~0.034 (about 10 px) from the crystal
CRY_SHIFT = 0.25                                   # v17: as far toward the centre as clears the middle rock
TONES = {'brown': ((128, 102, 82), (160, 130, 105), (180, 150, 122)), 'tan': ((178, 148, 96), (205, 175, 115), (222, 194, 134)),
         'bluegrey': ((100, 120, 134), (122, 145, 160), (140, 164, 178)), 'purple': ((112, 80, 122), (140, 100, 150), (160, 120, 168)),
         'green': ((96, 124, 90), (120, 150, 110), (140, 170, 128)), 'crystal': ((150, 152, 156), (190, 192, 194), (214, 215, 216)),
         'red': ((140, 52, 46), (180, 70, 60), (204, 92, 80)), 'pole': ((180, 174, 158), (215, 208, 190), (232, 226, 210))}


def ree_rock(K, name, centre, size, seed, mat, label, n=18, flat=0.0, notch=0.42, depth=(0.76, 0.88), spread=(0.70, 1.0), smooth=0.0):
    """an angular faceted rock: the convex hull of jittered points on a squashed ellipsoid, its base cut flat"""
    rng = random.Random(seed); sx, sy, sz = size; cx, cy = centre; pts = []
    for i in range(n):
        z = rng.uniform(-0.85, 1.0); t = rng.uniform(0, 2 * math.pi); rr = math.sqrt(max(0.0, 1 - z * z)) * rng.uniform(*spread)
        pts.append(Vector((rr * math.cos(t) * sx, rr * math.sin(t) * sy, (z + 1) / 2 * sz)))
    for t in range(8):                                  # a footprint ring so it stands on the ground
        a = 2 * math.pi * t / 8 + rng.uniform(-0.2, 0.2); pts.append(Vector((math.cos(a) * sx * 0.82, math.sin(a) * sy * 0.82, 0.0)))
    bm = bmesh.new()
    for p in pts:
        bm.verts.new(p + Vector((cx, cy, 0)))
    bmesh.ops.convex_hull(bm, input=bm.verts[:])
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context='VERTS')
    c0 = Vector((cx, cy, sz * 0.45))
    for v in bm.verts:                                  # v2: a third of the upper vertices pushed in: notches, as shipped
        if v.co.z > sz * 0.15 and rng.random() < notch:
            d = v.co - c0; v.co = c0 + d * rng.uniform(*depth)
    bmesh.ops.triangulate(bm, faces=bm.faces[:])
    if smooth:                                         # v6: rounded, smooth-shaded but for real ridges
        for e in bm.edges:
            e.smooth = not (len(e.link_faces) == 2 and math.degrees(e.calc_face_angle()) > smooth)
    me = bpy.data.meshes.new(name); bm.to_mesh(me); bm.free()
    o = K.obj(name, me, mat, False); noink(o); o['part_label'] = label
    if smooth:
        for p in o.data.polygons:
            p.use_smooth = True
    return o


def ree_grooves(K, ob, mat, label, grooves, sy):
    """v5 (owner: "need slightly more details on the rocks. Let's start with the left brown one"): the shipped brown rock's
    deep grooves, cut across its front (-Y) face rising to the right: each a long wedge whose upper face catches no light
    (dotted) above a lit shelf. grooves: [(x0, z0, x1, z1, depth)]"""
    cutters = []
    for j, (x0, z0, x1, z1, dep) in enumerate(grooves):
        yo, yi = -sy - 0.25, -sy + dep; vs = []
        xm, zm = x0 + (x1 - x0) * 0.68, z0 + (z1 - z0) * 0.68
        for x, z, f in ((x0, z0, 1.0), (xm, zm, 1.0), (x1, z1, 0.08)):    # full for two thirds, then tapering out, as shipped
            vs += [(x, yo, z + 0.13 * f), (x, yo, z - 0.10 * f), (x, yo + (yi - yo) * (0.55 + 0.45 * f), z + 0.04 * f)]
        fs = [(0, 1, 2), (8, 7, 6)]
        for s_ in (0, 3):
            fs += [(s_, s_ + 3, s_ + 4, s_ + 1), (s_ + 1, s_ + 4, s_ + 5, s_ + 2), (s_ + 2, s_ + 5, s_ + 3, s_)]
        cutters.append(mesh(K, 'groove_cutter%d' % j, vs, fs, None, False))
    pl_cut(K, ob, cutters); ob['part_label'] = label
    return ob


def ree_taper(ob, a):
    """v7 (owner: "flip it upside down so its wider at the bottom"): a projective taper narrowing the rock toward its top
    (plane faces stay planes), about its own vertical axis"""
    me = ob.data; P = [v.co for v in me.vertices]; cx = sum(p.x for p in P) / len(P); cy = sum(p.y for p in P) / len(P)
    z0 = min(p.z for p in P); hz = max(p.z for p in P) - z0
    for v in me.vertices:
        f = 1.0 + a * (v.co.z - z0) / hz; v.co.x = cx + (v.co.x - cx) / f; v.co.y = cy + (v.co.y - cy) / f
    me.update()


def ree_carve(K, ob, label, bites=(), scoops=(), crevices=()):
    """v7 (owner: "add crevices and concave faces similar to the old icon's"): angular cuts read off the rock's own
    surface (rays from outside toward its axis). bites: (direction, height fraction, radius), cutters stretched along the
    view so they notch the outline; scoops: the same but not stretched, so they scoop a concave facet into a visible face;
    crevices: ((dir, h), (dir, h), width, depth) thin wedges along the surface between two points"""
    from mathutils.bvhtree import BVHTree
    me = ob.data; mw = ob.matrix_world; tree = BVHTree.FromPolygons([mw @ v.co for v in me.vertices], [tuple(p.vertices) for p in me.polygons])
    P = [mw @ v.co for v in me.vertices]; cx = sum(p.x for p in P) / len(P); cy = sum(p.y for p in P) / len(P)
    z0 = min(p.z for p in P); hz = max(p.z for p in P) - z0
    def surf(d, h):
        d = Vector(d).normalized(); c = Vector((cx, cy, z0 + h * hz)); hit = tree.ray_cast(c + d * 6, -d, 12)
        return (hit[0], hit[1].normalized()) if hit[0] is not None else (c, d)
    cutters = []
    for j, (d, h, r) in enumerate(list(bites) + list(scoops)):
        p, n = surf(d, h); stretch = j < len(bites)
        bm = bmesh.new(); bmesh.ops.create_icosphere(bm, subdivisions=1, radius=r)
        for v in bm.verts:
            if stretch:
                v.co += VIEW * v.co.dot(VIEW) * 2.5
            v.co += p + n * r * (0.45 if stretch else 0.62)
        cm = bpy.data.meshes.new('carve%d' % j); bm.to_mesh(cm); bm.free(); cutters.append(K.obj('carve%d' % j, cm, None, False))
    for j, ((da, ha), (db, hb), w, dep) in enumerate(crevices):
        # a thin, long angular cutter (an icosphere flattened across the crevice) laid along the surface
        (pa, na), (pb, nb) = surf(da, ha), surf(db, hb); n = (na + nb).normalized(); t = (pb - pa); L = t.length; t.normalize()
        s = t.cross(n).normalized(); n = s.cross(t).normalized(); c = (pa + pb) / 2 + n * dep * 0.25
        bm = bmesh.new(); bmesh.ops.create_icosphere(bm, subdivisions=1, radius=1.0)
        for v in bm.verts:
            x, y, z = v.co.x, v.co.y, v.co.z; v.co = c + t * x * L * 0.62 + s * y * w * 1.6 + n * z * dep
        cm = bpy.data.meshes.new('crevice%d' % j); bm.to_mesh(cm); bm.free(); cutters.append(K.obj('crevice%d' % j, cm, None, False))
    for c in cutters:                                  # outward normals (an inside-out cutter empties the rock)
        bm = bmesh.new(); bm.from_mesh(c.data)
        if bm.calc_volume(signed=True) < 0:
            bmesh.ops.reverse_faces(bm, faces=bm.faces[:])
        bm.to_mesh(c.data); bm.free()
    for c in cutters:                                  # one at a time, so a cut that fails is reported and skipped
        n0 = len(ob.data.polygons); keep = ob.data.copy(); cname = c.name
        pl_cut(K, ob, [c])
        if len(ob.data.polygons) < n0 * 0.5:
            print('CARVE: cutter %s emptied the rock (%d -> %d faces); skipped' % (cname, n0, len(ob.data.polygons)))
            old_ = ob.data; ob.data = keep; bpy.data.meshes.remove(old_)
        else:
            bpy.data.meshes.remove(keep)
        bm = bmesh.new(); bm.from_mesh(ob.data)        # no slivers left for the next cut
        bmesh.ops.dissolve_degenerate(bm, dist=1e-5, edges=bm.edges[:])
        bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=1e-5)
        bm.to_mesh(ob.data); bm.free(); ob.data.update()
    ob['part_label'] = label
    return ob


def ree_seams(K, ob, label, paths, width=None):
    """v9 (owner: "make the crevices a bit more continuous like the ones on the old icon"): crevices as continuous ink
    following the surface: each path a list of (azimuth deg, height fraction) round the rock's axis, sampled densely and
    each sample ray-cast onto the surface, tapered at both ends"""
    from mathutils.bvhtree import BVHTree
    me = ob.data; mw = ob.matrix_world; tree = BVHTree.FromPolygons([mw @ v.co for v in me.vertices], [tuple(p.vertices) for p in me.polygons])
    P = [mw @ v.co for v in me.vertices]; cx = sum(p.x for p in P) / len(P); cy = sum(p.y for p in P) / len(P)
    z0 = min(p.z for p in P); hz = max(p.z for p in P) - z0
    for j, path in enumerate(paths):
        pts = []
        for (a0, h0), (a1, h1) in zip(path, path[1:]):
            for s in range(12):
                f = s / 12; a = math.radians(a0 + (a1 - a0) * f); h = h0 + (h1 - h0) * f
                d = Vector((math.cos(a), math.sin(a), 0.0)); c = Vector((cx, cy, z0 + h * hz))
                hit = tree.ray_cast(c + d * 6, -d, 12)
                if hit[0] is not None:
                    pts.append(hit[0] + hit[1].normalized() * 0.008)
        if len(pts) > 1:
            ln = tagged_line(K, '%s_seam%d' % (ob.name, j), [tuple(p) for p in pts], label, width or PL_INNER * 1.4, False)
            ln['ink_tip'] = 0.15; ln['ink_centre'] = 1.0


def ree_dots(ob, light=(0.06, -0.56, 0.83), below=0.62, amount=0.18):
    """dots on every face not turned to the light (the shipped rock's dotted sides), via the mask's occlusion attribute"""
    Ld = Vector(light).normalized(); me = ob.data
    at = me.attributes.get('icon_shade_occlusion') or me.attributes.new('icon_shade_occlusion', 'FLOAT', 'CORNER')
    for p in me.polygons:
        v = amount if p.normal.normalized().dot(Ld) < below else 0.0
        for li in p.loop_indices:
            at.data[li].value = v


def ree_cracks(K, ob, label, seed, count=3):
    """tapered crack lines on the largest camera-facing faces: from a point on an edge, a kinked run ending inside the face"""
    rng = random.Random(seed); me = ob.data; mw = ob.matrix_world
    faces = sorted([p for p in me.polygons if (mw.to_3x3() @ p.normal).normalized().dot(VIEW) > 0.25], key=lambda p: -p.area)[:count]
    for i, p in enumerate(faces):
        V = [mw @ me.vertices[j].co for j in p.vertices]; C = mw @ p.center; N = (mw.to_3x3() @ p.normal).normalized()
        a, b = max(zip(V, V[1:] + V[:1]), key=lambda e: (e[1] - e[0]).length)
        root = a.lerp(b, rng.uniform(0.35, 0.65)); mid = root.lerp(C, 0.55) + (b - a).normalized() * 0.03; end = C.lerp(V[(i + 2) % len(V)], 0.35)
        ln = tagged_line(K, '%s_crack%d' % (ob.name, i), [tuple(q + N * 0.006) for q in (root, mid, end)], label, PL_INNER, False)
        ln['ink_tip'] = 0.15; ln['ink_centre'] = 1.0


def ree_mottle(o, mats, seed, scale=1.7, cuts=24, thresh=(0.30, 0.42, 0.40)):
    """mineral patches: the rock's facets subdivided flat, each small face given a patch colour by 3D noise (blobs that
    run across facets, as shipped)"""
    me = o.data; base = len(me.materials)
    for m in mats:
        me.materials.append(m)
    bm = bmesh.new(); bm.from_mesh(me)
    # v7: split long edges until the surface is small, even triangles (the cuts' long slivers gave spiky patch edges)
    for _ in range(12):
        long_ = [e for e in bm.edges if e.calc_length() > 0.035]
        if not long_:
            break
        bmesh.ops.subdivide_edges(bm, edges=long_, cuts=1, use_grid_fill=False)
        bmesh.ops.triangulate(bm, faces=[f for f in bm.faces if len(f.verts) > 3])
    off = [Vector((seed * 1.7 + k * 13.1, seed * 0.3 + k * 7.7, k * 3.3)) for k in range(len(mats))]
    for f in bm.faces:
        c = f.calc_center_median() * scale; best, idx = -9, None
        for k in range(len(mats)):                    # v2: blue-grey dominant, purple and green smaller (as shipped)
            v = mnoise.noise(c * (1.0 if k == 0 else 1.6) + off[k]) - thresh[k]
            if v > 0 and v > best:
                best, idx = v, k
        if idx is not None:
            f.material_index = base + idx
    bmesh.ops.dissolve_degenerate(bm, dist=2e-4, edges=bm.edges[:]); bmesh.ops.triangulate(bm, faces=[f for f in bm.faces if len(f.verts) > 4])
    bm.to_mesh(me); bm.free(); me.update()


def ree_crystal(K, name, centre, r, hgt, mat, label, tilt=8.0, groove_mat=None, seed=7, top_slant=16.0, top_roll=0.0, top_on_axis=False):
    """a fluted crystal column: N flat ridge faces with concave arcs between them, tilted, its bottom cut flat on the
    ground and its top cut by a slanted plane.
    v12 (owner: "angle the bottom so its flat against the ground and the top a bit more so its not at 90 degrees agains
    the ridges. And vary the concave sections to different curvatures and sizes and make some of the ridge holes shaded"):
    sectors, flat widths, arc depths and arc skews vary; the grooves turned from the light (and a few more) take the
    groove material, darker, and dots"""
    rng = random.Random(seed); cx, cy = centre; N = 7; ph = math.radians(8)
    ws = [rng.uniform(0.75, 1.25) for _ in range(N)]; ws = [w / sum(ws) * 2 * math.pi for w in ws]
    ring, arc_of = [], []                              # arc_of[i]: the groove index the edge i -> i+1 belongs to, or -1
    a0 = ph
    for g in range(N):
        sec = ws[g]; fw = rng.uniform(0.40, 0.65) * sec; h = rng.uniform(0.05, 0.15) * r; sk = rng.uniform(0.6, 1.6)
        p0 = Vector((r * math.cos(a0), r * math.sin(a0), 0)); p1 = Vector((r * math.cos(a0 + fw), r * math.sin(a0 + fw), 0))
        p2 = Vector((r * math.cos(a0 + sec), r * math.sin(a0 + sec), 0))
        ring.append(p0.xy[:]); arc_of.append(-1)
        ch = p2 - p1; nout = Vector((ch.y, -ch.x, 0)).normalized()
        if nout.dot((p1 + p2) / 2) < 0:
            nout = -nout
        peak = max((f ** sk) * (1 - f) for f in [j / 200 for j in range(201)])
        for s in range(13):
            f = s / 12; q = p1 + ch * f - nout * h * (f ** sk) * (1 - f) / peak; ring.append(q.xy[:]); arc_of.append(g)
        arc_of[-1] = -1                                 # the last arc point starts the next flat face
        a0 += sec
    n = len(ring); z0, z1 = -0.6, hgt + 0.6            # built long, then cut by the ground and the slanted top
    vs = [(x, y, z0) for x, y in ring] + [(x, y, z1) for x, y in ring]
    fs = [tuple(reversed(range(n))), tuple(n + j for j in range(n))] + [(j, (j + 1) % n, n + (j + 1) % n, n + j) for j in range(n)]
    me = bpy.data.meshes.new(name); me.from_pydata(vs, [], fs); me.update()
    o = K.obj(name, me, mat, False); o['part_label'] = label
    if groove_mat is not None:
        o.data.materials.append(groove_mat)
    Mx = Matrix.Translation((cx, cy, 0.0)) @ Matrix.Rotation(math.radians(tilt), 4, Vector((-1, 1, 0)).normalized())
    Ld = Vector((0.06, -0.56, 0.83)).normalized(); shade = set()
    for g in range(N):                                 # which grooves are in shade: facing away from the light
        idx = [i for i in range(n) if arc_of[i] == g]; mid = Vector(ring[idx[len(idx) // 2]] + (0,))
        if (Mx.to_3x3() @ mid.normalized()).dot(Ld) < 0.05:
            shade.add(g)
    mids = {}
    for g in range(N):
        idx = [i for i in range(n) if arc_of[i] == g]; mids[g] = Vector(ring[idx[len(idx) // 2]] + (0,)).normalized()
    seen = sorted([g for g in range(N) if (Mx.to_3x3() @ mids[g]).dot(VIEW) > 0.05],
                  key=lambda g: (Mx.to_3x3() @ mids[g]).dot(RIGHT))
    shade |= set(seen[1::2])                            # every other groove in view is in shade too
    for p in o.data.polygons:
        vi = list(p.vertices)
        if len(vi) == 4:
            j = min(vi) % n if max(vi) - min(vi) < n + 2 else max(vi) % n   # the quad between j and j+1
            j = min(v % n for v in vi) if (max(v % n for v in vi) - min(v % n for v in vi)) == 1 else max(v % n for v in vi)
            if arc_of[j] >= 0 and arc_of[j] in shade and groove_mat is not None:
                p.material_index = 1
    o.data.transform(Mx)
    bm = bmesh.new(); bm.from_mesh(o.data)
    top_c = Mx @ Vector((0, 0, hgt)); axis = (Mx.to_3x3() @ Vector((0, 0, 1))).normalized()
    # v15 (owner: "it still doesnt look oblong on a left to right perspective like the old icons"): the top cut level
    # (a level face reads as a wide left-to-right oval on this camera), tipped top_slant about the screen's horizontal
    # v16 (owner: "make the silver rock's top face angle the opposite way (lower on the right and higher on the left)"):
    # top_roll tips the normal toward the screen's right (about the ground's (-1, 1, 0) axis)
    tn = (Matrix.Rotation(math.radians(top_roll), 3, Vector((-1, 1, 0)).normalized()) @ Matrix.Rotation(math.radians(top_slant), 3, Vector((1, 1, 0)).normalized()) @ (axis if top_on_axis else Vector((0, 0, 1)))).normalized()
    for co, no in ((Vector((0, 0, 0)), Vector((0, 0, -1))), (top_c, tn)):
        geom = bm.verts[:] + bm.edges[:] + bm.faces[:]
        res = bmesh.ops.bisect_plane(bm, geom=geom, plane_co=co, plane_no=no, clear_outer=True)
        cut = [e for e in res['geom_cut'] if isinstance(e, bmesh.types.BMEdge)]
        f = bmesh.ops.holes_fill(bm, edges=[e for e in bm.edges if e.is_boundary], sides=0)
        for face in f['faces']:
            face.material_index = 0
    bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=1e-5)
    bmesh.ops.triangulate(bm, faces=[f for f in bm.faces if len(f.verts) > 4], ngon_method='BEAUTY')
    for _ in range(3):                                  # no slivers from collinear points on the cut
        bmesh.ops.dissolve_degenerate(bm, dist=1e-4, edges=bm.edges[:])
        bmesh.ops.triangulate(bm, faces=[f for f in bm.faces if len(f.verts) > 4], ngon_method='BEAUTY')
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    for e in bm.edges:                                  # smooth arcs, sharp where a flat face meets an arc and at the ends
        e.smooth = not (len(e.link_faces) == 2 and math.degrees(e.calc_face_angle()) > 20)
    bm.to_mesh(o.data); bm.free(); o.data.update(); noink(o)
    for p in o.data.polygons:
        p.use_smooth = abs(p.normal.dot(axis)) < 0.5 and abs(p.normal.z) < 0.8
    if groove_mat is not None:                          # the shaded grooves take dots too
        at = o.data.attributes.new('icon_shade_occlusion', 'FLOAT', 'CORNER')
        for p in o.data.polygons:
            for li in p.loop_indices:
                at.data[li].value = 0.30 if p.material_index == 1 else 0.0
    return o


def ree_magnet(K, centre, yaw, mats, label_red, label_pole, w=1.10, leg=0.90, bar=0.27, th=0.24):
    """a horseshoe magnet lying flat: a U of square section (red), its two legs ending in pale pole pieces"""
    cx, cy = centre; R = (w - bar) / 2
    path = [Vector((-R, leg, th / 2))]
    path += [Vector((-R * math.cos(math.pi * k / 16), -R * math.sin(math.pi * k / 16) * 0.0 + 0.0, th / 2)) for k in range(0)]
    arc = [Vector((-R * math.cos(math.pi * k / 18), -R * math.sin(math.pi * k / 18), th / 2)) for k in range(19)]
    path = [Vector((-R, leg - 0.14, th / 2)), Vector((-R, 0.0, th / 2))] + arc[1:-1] + [Vector((R, 0.0, th / 2)), Vector((R, leg - 0.14, th / 2))]
    Rz = Matrix.Rotation(math.radians(yaw), 3, 'Z'); P = [Rz @ p + Vector((cx, cy, 0)) for p in path]
    prof = [(-bar / 2, -th / 2), (bar / 2, -th / 2), (bar / 2, th / 2), (-bar / 2, th / 2)]
    body, rings, F = pl_sweep(K, 'magnet', P, prof, (0, 0, 1), mats['red'], label_red); hosts = [body.name]
    for s in (-1, 1):
        a = Rz @ Vector((s * R, leg - 0.14, 0)) + Vector((cx, cy, 0)); b = Rz @ Vector((s * R, leg, 0)) + Vector((cx, cy, 0))
        d = (b - a).normalized(); nrm = Vector((-d.y, d.x, 0))
        q = [a - nrm * bar / 2, a + nrm * bar / 2, b + nrm * bar / 2, b - nrm * bar / 2]
        vs = [tuple(p) for p in q] + [tuple(p + Vector((0, 0, th))) for p in q]
        fs = [(3, 2, 1, 0), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]
        pole = mesh(K, 'magnet_pole_%d' % s, vs, fs, mats['pole'], False); pole['part_label'] = label_pole; hosts.append(pole.name)
    return hosts


def build_ree_ore():
    setup_icon_rig(); K = Kit(open_collection('ICON_ree_ore')); hosts = []
    mats = {k: pl_toon('ree_' + k, *v) for k, v in TONES.items()}
    L_BROWN, L_MOTTLE, L_CRYSTAL, L_RED, L_POLE = 1, 2, 3, 4, 5
    # v16 (owner: "rotate the three rocks around an axis so the brown one gets closer and the silver stone moves away"):
    # the three centres turned GROUP_TURN deg about a vertical axis through their mean (each keeps its own facing)
    GROUP_TURN = 24.0; C3 = [(-1.00, 0.05), (-0.10, 0.30), (0.98, -0.20)]
    gx, gy = sum(c[0] for c in C3) / 3, sum(c[1] for c in C3) / 3; ca, sa = math.cos(math.radians(GROUP_TURN)), math.sin(math.radians(GROUP_TURN))
    def turned(c):
        dx, dy = c[0] - gx, c[1] - gy; return (gx + ca * dx - sa * dy, gy + sa * dx + ca * dy)
    brown = ree_rock(K, 'rock_brown', (-1.00, 0.05), (0.66, 0.56, 1.10), 11, mats['brown'], L_BROWN, n=26)
    ree_grooves(K, brown, mats['brown'], L_BROWN, [(-1.70, 0.28, -0.40, 0.66, 0.50), (-1.70, 0.66, -0.55, 0.98, 0.44),
                                                     (-1.60, 0.02, -0.75, 0.24, 0.40)], 0.56 - 0.05)
    ree_dots(brown, amount=0.30); hosts.append(brown.name)
    tb = turned((-1.00, 0.05)); brown.data.transform(Matrix.Translation((tb[0] + 1.00, tb[1] - 0.05, 0.0)))   # grooves cut in place, then moved
    # v6 (owner: "the middle rock. Needs to look rounder. More polygons"): many more points, near an ellipsoid, shallow notches
    mott = ree_rock(K, 'rock_mottled', turned((-0.10, 0.30)), (0.92, 0.76, 1.55), 23, mats['tan'], L_MOTTLE, n=110, notch=0.12,
                    depth=(0.90, 0.96), spread=(0.90, 1.0), smooth=32.0); hosts.append(mott.name)
    ree_taper(mott, 0.62)
    ree_carve(K, mott, L_MOTTLE,
              # v8 (owner: "it should be a concave face but the backing material should still be there"): no cut through
              # the outline; the hollows are scoops turned toward the viewer, so their concave faces show
              bites=[],
              scoops=[((-0.55, -1.0, 0.25), 0.40, 0.26), ((0.2, 0.0, 1.0), 0.97, 0.20), ((-0.1, -1.0, 0.1), 0.70, 0.30),
                      ((0.6, -0.8, 0.0), 0.28, 0.26)],
              crevices=[])
    ree_mottle(mott, [mats['bluegrey'], mats['purple'], mats['green']], 5, cuts=14)
    # azimuth 0 = +X, -90 = -Y (the viewer's left face), -45 = straight at the viewer
    ree_seams(K, mott, L_MOTTLE, [[(-135, 0.96), (-118, 0.80), (-108, 0.62), (-96, 0.46), (-84, 0.30), (-70, 0.12)],
                                  [(-104, 0.56), (-80, 0.62), (-62, 0.74), (-52, 0.90)],
                                  [(-30, 0.92), (-14, 0.76), (2, 0.64)]])
    # v13 (owner: "make the top a bit more angled so the top face is oblong/ teardrop shaped"): the top cut 12 deg away from the viewer, foreshortened to an oblong
    # v17 (owner: "slant it more so the left side has the same angle as the old image. Then bring the silver rock closer to
    # the centre"): tilt 23 deg (the left edge ~27 deg off vertical on screen, as shipped); moved CRY_SHIFT toward screen left
    tc = turned((0.98, -0.20)); tc = (tc[0] + 0.10 - CRY_SHIFT / math.sqrt(2), tc[1] - 0.02 - CRY_SHIFT / math.sqrt(2))
    # v19 (owner: "closer to the magnet still please. they should almost be touching"): moved CRY_TOWARD toward the magnet
    mv = Vector((0.12 - tc[0], -1.02 - tc[1], 0.0)).normalized(); tc = (tc[0] + mv.x * CRY_TOWARD, tc[1] + mv.y * CRY_TOWARD)
    cry = ree_crystal(K, 'crystal', tc, 0.46, 1.30,   # v14 (owner: "a bit wider (15%)")
                      mats['crystal'], L_CRYSTAL, tilt=23.0, top_slant=TOP_SLANT, top_roll=TOP_ROLL, top_on_axis=True,   # v18: the top follows the lean
                      groove_mat=pl_toon('ree_groove', (118, 120, 126), (146, 148, 152), (162, 164, 168))); hosts.append(cry.name)
    # v19 (owner: "closer to the magnet ... they should almost be touching"): the magnet moved MAG_TOWARD toward the crystal
    # (moving the crystal instead drove it into the middle rock)
    mm = Vector((tc[0] - 0.12, tc[1] + 1.02, 0.0)).normalized()
    sr = MAG_RIGHT / math.sqrt(2)                       # and slid right along the screen (same depth), clear of the rock
    sf = MAG_FWD / math.sqrt(2)                         # and toward the viewer, clear of the middle rock behind it
    hosts += ree_magnet(K, (0.12 + mm.x * MAG_TOWARD + sr + sf, -1.02 + mm.y * MAG_TOWARD + sr - sf), 180.0, mats, L_RED, L_POLE)
    bpy.context.view_layer.update()
    for n in hosts:
        crease = 20.0 if n == 'crystal' else 46.0 if n == 'rock_mottled' else 28.0
        pl_mesh_lines(K, bpy.data.objects[n], bpy.data.objects[n]['part_label'], crease, n, 0.16 if n == 'rock_mottled' else 0.05,
                      contours=(n != 'crystal'))
    ree_cracks(K, brown, L_BROWN, 41, count=3)
    for ob in K.col.objects:
        if ob.get('ink_width') == 6:
            ob['ink_width'] = PL_INNER
    info = contract(K, hosts, 'REE ore: a brown host rock, a tan rock mottled with blue-grey, purple and green mineral, a grey '
                    'fluted crystal, and a red horseshoe magnet in front', inner=PL_INNER)
    info['revision'] = REE_REVISION; info['outline']['component_boundaries'] = True; info['stipple']['strength'] = 0.38
    info['stipple']['groups'] = [{'name': 'shaded_faces', 'labels': [1, 2, 3, 4, 5, 6, 7], 'thresholds': [0.575, 0.50, 0.30]}]
    return info
