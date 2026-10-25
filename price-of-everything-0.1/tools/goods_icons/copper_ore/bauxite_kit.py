"""Bauxite ore (g_022 bauxite_ore). Real bauxite is an earthy, dull, rust red to orange rock mottled with cream and ochre
(gibbsite and clay), and pisolitic: pea sized round concretions set in a finer matrix. Broken open, the peas show as
concentric rings (a dark iron rich core in a pale rim); weathered, they stand proud as low knobs, and loose ones pile up
as pea gravel. The icon: one rounded knobbly lump sawn in half through its widest point, the rear half standing with its
cut toward the light and the front half lying cut face up, both cut faces full of ringed pea sections, and loose dark
peas in front. On the set's grid, camera, light, 12/4 px ink and dots on the shaded sides."""
import random
from mathutils import noise as mnoise
BX_REVISION = 'bauxite_ore_v19'
TONES = {'matrix': ((134, 58, 40), (172, 80, 52), (198, 104, 70)), 'cream': ((176, 136, 94), (222, 180, 124), (238, 204, 152)),
         'fracture': ((160, 76, 52), (198, 102, 66), (214, 120, 80)), 'core': ((56, 24, 22), (72, 30, 26), (84, 36, 30)),
         'rim': ((184, 132, 80), (222, 168, 102), (234, 188, 124)), 'pea': ((62, 26, 22), (86, 36, 30), (106, 46, 38))}


def bx_lump(K, name, centre, size, seed, mats, label, knobs=24, knob_r=(0.12, 0.20), knob_h=0.035, worn=5,
            fracture=None, split=None, label2=None):
    """a rounded earthy lump: an even icosphere on a squashed ellipsoid, lumpy by low-frequency noise, a few worn flat
    faces pressed in, swollen by low round knobs (the weathered peas), its base cut flat; fracture = (point, normal)
    breaks it open with a flat face (material 2). mats = [matrix, cream, fracture]; cream patches come from 3D noise over
    the weathered surface only"""
    rng = random.Random(seed); sx, sy, sz = size; cx, cy = centre
    bm = bmesh.new(); bmesh.ops.create_icosphere(bm, subdivisions=5, radius=1.0)
    off = Vector((seed * 3.1, seed * 1.7, seed * 0.9))
    for v in bm.verts:
        d = v.co.normalized(); s = 1 + 0.10 * mnoise.noise(d * 1.3 + off) + 0.04 * mnoise.noise(d * 3.1 + off)
        v.co = Vector((d.x * sx * s, d.y * sy * s, (d.z * s * 0.5 + 0.5) * sz * 1.08 - sz * 0.08))
    for _ in range(worn):                              # worn faces: everything past a plane pressed onto it
        a = rng.uniform(0, 2 * math.pi); el = rng.uniform(0.1, 0.9); n = Vector((math.cos(a) * math.cos(el), math.sin(a) * math.cos(el), math.sin(el)))
        far = max(v.co.dot(n) for v in bm.verts); lim = far * rng.uniform(0.86, 0.93)
        for v in bm.verts:
            h = v.co.dot(n)
            if h > lim:
                v.co -= n * (h - lim) * 0.85
    bm.normal_update()
    up = [v for v in bm.verts if v.co.z > sz * 0.12]
    centres = [rng.choice(up).co.copy() for _ in range(knobs)]
    radii = [rng.uniform(*knob_r) for _ in range(knobs)]
    move = []
    for v in bm.verts:
        d = 0.0
        for c, r in zip(centres, radii):
            q = (v.co - c).length / r
            if q < 1:
                d += knob_h * (1 - q * q) ** 2
        foot = max(0.0, min(1.0, v.co.z / (sz * 0.25)))  # the base stays where it stands
        move.append(v.normal * d * foot)
    for v, m in zip(bm.verts, move):
        v.co += m
    bmesh.ops.translate(bm, vec=Vector((cx, cy, 0)), verts=bm.verts[:])
    knob_list = [(c + Vector((cx, cy, 0)), r) for c, r in zip(centres, radii)]
    for f in bm.faces:
        f.material_index = 0
    if not split:
        if fracture:                                   # the fracture first, then the ground: one clean loop each
            bx_cut(bm, Vector(fracture[0]), Vector(fracture[1]).normalized(), 2)
        bx_cut(bm, Vector((0, 0, 0)), Vector((0, 0, -1)), 0)
        return bx_finish(K, name, bm, mats, label, knob_list)
    # split = (point, normal, lying centre (x, y), lying yaw deg, sink): sawn clean through at the point; the half
    # behind the plane stands with its cut toward the viewer, the half in front lies on its back, cut face up
    co, no, lc, yaw, sink = split; no = Vector(no).normalized(); co = Vector(co)
    bm2 = bm.copy()
    bx_cut(bm, co, no, 2); bx_cut(bm, Vector((0, 0, 0)), Vector((0, 0, -1)), 0)
    stand = bx_finish(K, name, bm, mats, label, knob_list)
    bx_cut(bm2, co, -no, 2)
    cap_c = co; R = (-no).rotation_difference(Vector((0, 0, 1))).to_matrix().to_4x4()
    M = Matrix.Rotation(math.radians(yaw), 4, 'Z') @ R @ Matrix.Translation(-cap_c)
    bm2.transform(M)
    zmin = min(v.co.z for v in bm2.verts)
    T = Matrix.Translation((lc[0], lc[1], -zmin - sink))
    bmesh.ops.transform(bm2, matrix=T, verts=bm2.verts[:])
    bx_cut(bm2, Vector((0, 0, 0)), Vector((0, 0, -1)), 0)
    knobs2 = [((T @ M) @ c, r) for c, r in knob_list]
    lie = bx_finish(K, name + '_lying', bm2, mats, label2, knobs2)
    return stand, lie


def bx_cut(bm, co, no, mi):
    """bisect, drop the side the normal points to, fill the hole with material mi"""
    bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], plane_co=co, plane_no=no, clear_outer=True)
    filled = bmesh.ops.holes_fill(bm, edges=[e for e in bm.edges if e.is_boundary], sides=0)['faces']
    for f in filled:
        f.material_index = mi
    return filled


def bx_finish(K, name, bm, mats, label, knob_list):
    bmesh.ops.dissolve_degenerate(bm, dist=1e-5, edges=bm.edges[:])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    for e in bm.edges:                                 # smooth, but for the cut rim and the base
        mi = {f.material_index for f in e.link_faces}
        e.smooth = not (2 in mi and len(mi) > 1) and not any(abs(f.normal.z) > 0.99 and f.normal.z < 0 for f in e.link_faces)
    me = bpy.data.meshes.new(name); bm.to_mesh(me); bm.free()
    o = K.obj(name, me, mats[0], False)
    for m in mats[1:]:
        o.data.materials.append(m)
    for p in o.data.polygons:
        p.use_smooth = p.material_index != 2 and p.normal.z > -0.99
    noink(o); o['part_label'] = label; o['knobs'] = [x for c, r in knob_list for x in (c.x, c.y, c.z, r)]
    return o


def bx_knob_spots(K, host, mat, label, frac=0.45, seed=0, keep=0.8, segs=20):
    """the pisoids standing out of the weathered crust: a dark spot capping each knob, conformed to the surface (each
    rim point ray-cast onto it and lifted a hair), colour only, no ink"""
    from mathutils.bvhtree import BVHTree
    rng = random.Random(seed); me = host.data; mw = host.matrix_world
    tree = BVHTree.FromPolygons([mw @ v.co for v in me.vertices], [tuple(p.vertices) for p in me.polygons])
    mats_idx = [p.material_index for p in me.polygons]; k = list(host['knobs']); n = 0
    for i in range(0, len(k), 4):
        c = Vector(k[i:i + 3]); r = k[i + 3] * frac * rng.uniform(0.8, 1.15)
        if rng.random() > keep:
            continue
        loc, nrm, fi, dist = tree.find_nearest(c)
        if loc is None or dist > 0.06 or mats_idx[fi] == 2 or nrm.z < -0.2:
            continue
        nrm = nrm.normalized(); t = nrm.orthogonal().normalized(); b = nrm.cross(t)
        rings = []; ok = True                          # concentric rings, every point on the surface: a flat fan cut under the knob
        for ri in (0.25, 0.5, 0.75, 1.0):
            ring = []
            for j in range(segs):
                a = 2 * math.pi * j / segs; q = loc + (t * math.cos(a) + b * math.sin(a)) * r * ri
                hit = tree.ray_cast(q + nrm * 0.25, -nrm, 0.6)
                if hit[0] is None or mats_idx[hit[2]] == 2:
                    ok = False; break
                ring.append(hit[0] + hit[1].normalized() * 0.006)
            if not ok:
                break
            rings.append(ring)
        if not ok:
            continue
        vs = [tuple(loc + nrm * 0.006)] + [tuple(p) for ring in rings for p in ring]
        fs = [(0, 1 + j, 1 + (j + 1) % segs) for j in range(segs)]
        for ri in range(len(rings) - 1):
            o0, o1 = 1 + ri * segs, 1 + (ri + 1) * segs
            fs += [(o0 + j, o1 + j, o1 + (j + 1) % segs, o0 + (j + 1) % segs) for j in range(segs)]
        sm = bpy.data.meshes.new('%s_spot%d' % (host.name, n)); sm.from_pydata(vs, [], fs); sm.update()
        o = K.obj('%s_spot%d' % (host.name, n), sm, mat, True); noink(o); o['part_label'] = label; o.pass_index = 73
        for p in o.data.polygons:
            p.use_smooth = True
        n += 1
    return n


def bx_mottled_toon(name, base, patch, scale=2.2, cut=0.60, seed=0.0):
    """the weathered crust: two toon ramps on the same shading, picked per pixel by a noise field in object space, so
    the cream patches have smooth edges (per-triangle patches came out sawtoothed)"""
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True; nt = m.node_tree; nt.nodes.clear()
    out = nt.nodes.new('ShaderNodeOutputMaterial'); emis = nt.nodes.new('ShaderNodeEmission')
    diff = nt.nodes.new('ShaderNodeBsdfDiffuse'); diff.inputs['Color'].default_value = (1, 1, 1, 1)
    s2r = nt.nodes.new('ShaderNodeShaderToRGB'); nt.links.new(diff.outputs[0], s2r.inputs[0])
    ramps = []
    for tones in (base, patch):
        r = nt.nodes.new('ShaderNodeValToRGB'); r.color_ramp.interpolation = 'CONSTANT'; els = r.color_ramp.elements
        els[0].position = 0.0; els[0].color = (*pl_rgb(*tones[0]), 1)
        els[1].position = PL_SHADE_STEP; els[1].color = (*pl_rgb(*tones[1]), 1)
        e = els.new(0.975); e.color = (*pl_rgb(*tones[2]), 1)
        nt.links.new(s2r.outputs['Color'], r.inputs['Fac']); ramps.append(r)
    tc = nt.nodes.new('ShaderNodeTexCoord'); mp = nt.nodes.new('ShaderNodeMapping'); mp.inputs['Location'].default_value = (seed, seed * 0.6, seed * 0.3)
    nz = nt.nodes.new('ShaderNodeTexNoise'); nz.inputs['Scale'].default_value = scale; nz.inputs['Detail'].default_value = 2.0
    nz.inputs['Roughness'].default_value = 0.55
    step = nt.nodes.new('ShaderNodeMath'); step.operation = 'GREATER_THAN'; step.inputs[1].default_value = cut
    mix = nt.nodes.new('ShaderNodeMix'); mix.data_type = 'RGBA'
    nt.links.new(tc.outputs['Object'], mp.inputs['Vector']); nt.links.new(mp.outputs['Vector'], nz.inputs['Vector'])
    nt.links.new(nz.outputs['Fac'], step.inputs[0]); nt.links.new(step.outputs[0], mix.inputs['Factor'])
    nt.links.new(ramps[0].outputs['Color'], mix.inputs['A']); nt.links.new(ramps[1].outputs['Color'], mix.inputs['B'])
    nt.links.new(mix.outputs['Result'], emis.inputs['Color']); nt.links.new(emis.outputs[0], out.inputs[0])
    return m


def bx_face_frame(o):
    """the fracture face's plane: (centre, normal, u, v, boundary points in (u, v))"""
    me = o.data; mw = o.matrix_world
    caps = [p for p in me.polygons if p.material_index == 2]
    N = (mw.to_3x3() @ caps[0].normal).normalized()
    ring = []
    for p in caps:
        ring += [mw @ me.vertices[i].co for i in p.vertices]
    C = sum(ring, Vector()) / len(ring)
    up = Vector((0, 0, 1)) if abs(N.z) < 0.95 else Vector((1, 0, 0))   # a face lying flat has no 'up' of its own
    u = (up - N * N.dot(up)).normalized(); v = N.cross(u).normalized()
    # the boundary loop: the cap faces' outer edges, in order
    ek = {}
    for p in caps:
        for k in p.edge_keys:
            ek[k] = ek.get(k, 0) + 1
    edges = [k for k, c in ek.items() if c == 1]; nb = {}
    for a, b in edges:
        nb.setdefault(a, []).append(b); nb.setdefault(b, []).append(a)
    start = edges[0][0]; loop = [start]; prev = None
    while True:
        nxt = [w for w in nb[loop[-1]] if w != prev]
        if not nxt or nxt[0] == start:
            break
        prev = loop[-1]; loop.append(nxt[0])
    poly = [((mw @ me.vertices[i].co - C).dot(u), (mw @ me.vertices[i].co - C).dot(v)) for i in loop]
    return C, N, u, v, poly


def bx_rim(K, host, label, width):
    """the fracture face's rim as one closed ink line, lifted a hair off the face (a crease filter broke it up where
    the break is shallow)"""
    C, N, u, v, poly = bx_face_frame(host)
    pts = [tuple(C + u * a + v * b + N * 0.004) for a, b in poly]
    ln = tagged_line(K, host.name + '_rim', pts, label, width, True)
    return ln


def bx_inside(pt, poly):
    x, y = pt; ins = False; n = len(poly)
    for i in range(n):
        (x0, y0), (x1, y1) = poly[i], poly[(i + 1) % n]
        if (y0 > y) != (y1 > y) and x < x0 + (y - y0) * (x1 - x0) / (y1 - y0):
            ins = not ins
    return ins


def bx_edge_dist(pt, poly):
    best = 9.0; x, y = pt
    for i in range(len(poly)):
        (x0, y0), (x1, y1) = poly[i], poly[(i + 1) % len(poly)]
        dx, dy = x1 - x0, y1 - y0; L = dx * dx + dy * dy or 1e-9
        t = max(0.0, min(1.0, ((x - x0) * dx + (y - y0) * dy) / L)); best = min(best, math.hypot(x - x0 - t * dx, y - y0 - t * dy))
    return best


def bx_disc(K, name, C, N, u, v, centre, r, lift, mat, label, segs=40):
    vs = [tuple(C + N * lift + u * centre[0] + v * centre[1])]
    for k in range(segs):
        a = 2 * math.pi * k / segs
        vs.append(tuple(C + N * lift + u * (centre[0] + r * math.cos(a)) + v * (centre[1] + r * math.sin(a))))
    fs = [(0, 1 + k, 1 + (k + 1) % segs) for k in range(segs)]
    me = bpy.data.meshes.new(name); me.from_pydata(vs, [], fs); me.update()
    o = K.obj(name, me, mat, False); noink(o); o['part_label'] = label; o.pass_index = 73
    return o


def bx_pisoids(K, host, mats, label, seed, count=40, r=(0.025, 0.085), margin=0.028):
    """the broken peas on the fracture face: concentric rings (pale rim, dark core, and a pale heart on the big ones),
    packed without overlap inside the face"""
    rng = random.Random(seed); C, N, u, v, poly = bx_face_frame(host)
    us = [p[0] for p in poly]; vs = [p[1] for p in poly]; placed = []
    for _ in range(4000):
        if len(placed) >= count:
            break
        rr = rng.uniform(*r); pt = (rng.uniform(min(us), max(us)), rng.uniform(min(vs), max(vs)))
        if not bx_inside(pt, poly) or bx_edge_dist(pt, poly) < rr + margin:
            continue
        if any(math.hypot(pt[0] - q[0], pt[1] - q[1]) < rr + qr + 0.012 for q, qr in placed):
            continue
        placed.append((pt, rr))
    for j, (pt, rr) in enumerate(placed):
        kind = rng.random()
        if kind < 0.55:                                # ringed: a thin pale rim round a dark core (a pale heart on big ones)
            bx_disc(K, 'pea_rim%d' % j, C, N, u, v, pt, rr, 0.003, mats['rim'], label)
            bx_disc(K, 'pea_core%d' % j, C, N, u, v, pt, rr * 0.74, 0.006, mats['core'], label)
            if rr > 0.075:
                bx_disc(K, 'pea_heart%d' % j, C, N, u, v, pt, rr * 0.26, 0.009, mats['rim'], label, segs=24)
        elif kind < 0.85:                              # solid dark iron-rich peas
            bx_disc(K, 'pea_core%d' % j, C, N, u, v, pt, rr, 0.003, mats['core'], label)
        else:                                          # pale gibbsite ooids
            bx_disc(K, 'pea_rim%d' % j, C, N, u, v, pt, rr, 0.003, mats['rim'], label)
    return placed


def bx_pea(K, name, c, r, seed, mat, label, squash=0.86, z=0.0):
    """a loose pea: a slightly irregular, slightly flattened ball sitting on the ground"""
    rng = random.Random(seed)
    bm = bmesh.new(); bmesh.ops.create_icosphere(bm, subdivisions=3, radius=r)
    off = Vector((rng.uniform(0, 50), rng.uniform(0, 50), rng.uniform(0, 50)))
    for vt in bm.verts:
        vt.co *= 1 + 0.07 * mnoise.noise(vt.co / r * 0.9 + off)
        vt.co.z *= squash
    zmin = min(vt.co.z for vt in bm.verts)
    for vt in bm.verts:
        vt.co += Vector((c[0], c[1], z - zmin))
    me = bpy.data.meshes.new(name); bm.to_mesh(me); bm.free()
    o = K.obj(name, me, mat, True); noink(o); o['part_label'] = label
    for p in o.data.polygons:
        p.use_smooth = True
    return o


def bx_dots(ob, light=(0.06, -0.56, 0.83), below=0.62, amount=0.18):
    """dots on every face not turned to the light, via the mask's occlusion attribute"""
    Ld = Vector(light).normalized(); me = ob.data
    at = me.attributes.get('icon_shade_occlusion') or me.attributes.new('icon_shade_occlusion', 'FLOAT', 'CORNER')
    for p in me.polygons:
        val = amount if p.normal.normalized().dot(Ld) < below else 0.0
        for li in p.loop_indices:
            at.data[li].value = val


def scr(sx, d):
    """world (x, y) from screen right sx and depth toward the viewer d"""
    return ((sx + d) / math.sqrt(2), (sx - d) / math.sqrt(2))


HERO_AT = (0.30, -0.10)                            # screen right, depth toward the viewer
HERO_SIZE = (0.86, 0.74, 1.42)
SLICE_N = (-0.22, -0.90, 0.38)                     # the cut faces the light, turned off the view so the crust shows on its right
LIE_AT = (-0.50, 0.82)                              # in front of the standing half's lower left, so the pair sits compact
LIE_YAW = 0.0
BACK_LUMP = False                                  # v19 (owner chose the v18 variant without the back lump)
PEAS = [((0.78, 0.66), 0.12, 0.0), ((1.00, 0.50), 0.11, 0.0), ((0.92, 0.72), 0.10, 0.15)]


def build_bauxite_ore():
    return bx_build('bauxite_ore', BACK_LUMP)


def bx_build(name, back_lump):
    setup_icon_rig(); K = Kit(open_collection('ICON_' + name)); hosts = []
    mats = {k: pl_toon('bx_' + k, *v) for k, v in TONES.items()}
    lump_m = lambda k, cut: [bx_mottled_toon('bx_crust_' + k, TONES['matrix'], TONES['cream'], cut=cut, seed=len(k) * 3.7), mats['cream'], mats['fracture']]
    L_HERO, L_BACK, L_LIE, L_PEA0 = 1, 2, 3, 4
    # v16 (owner: "a cleaner slice down the middle of the right hero ... at the widest point of the rock. The other slice
    # should be lying with the flat sliced side up"): sawn clean through its centre at the widest height; the rear half
    # stands with the cut toward the viewer, the front half lies on its back beside it, cut face up
    hc = scr(HERO_AT[0], HERO_AT[1]); hs = HERO_SIZE
    fn = Vector(SLICE_N).normalized()
    hero, lie = bx_lump(K, 'lump_hero', hc, hs, 11, lump_m('hero', 0.58), L_HERO, knobs=70, knob_r=(0.08, 0.15), knob_h=0.05,
                        split=(Vector((hc[0], hc[1], hs[2] * 0.46)), fn, scr(*LIE_AT), LIE_YAW, 0.05), label2=L_LIE)
    lie.data.materials[0] = lump_m('lying', 0.68)[0]     # its own, sparser cream: the shared field banded its underside
    hosts += [hero.name, lie.name]
    if back_lump:
        back = bx_lump(K, 'lump_back', scr(-0.74, -0.66), (0.62, 0.56, 1.08), 23, lump_m('back', 0.59), L_BACK, knobs=40,
                       knob_r=(0.08, 0.14), knob_h=0.05); hosts.append(back.name)
    bpy.context.view_layer.update()
    bx_pisoids(K, hero, mats, L_HERO, 5); bx_pisoids(K, lie, mats, L_LIE, 9)
    # no lit step on the spots: a highlight on a small dark disc read as an eye
    spot = pl_toon('bx_spot', TONES['pea'][0], TONES['pea'][1], TONES['pea'][1])
    bx_knob_spots(K, hero, spot, L_HERO, seed=3); bx_knob_spots(K, lie, spot, L_LIE, seed=6)
    if back_lump:
        bx_knob_spots(K, back, spot, L_BACK, seed=4)
    for j, (c, r, z) in enumerate(PEAS):
        p = bx_pea(K, 'pea%d' % j, scr(*c), r, 30 + j, mats['pea'], L_PEA0 + j, z=z); hosts.append(p.name)
    for n in hosts:
        bx_dots(bpy.data.objects[n], amount=0.30)
    bpy.context.view_layer.update()
    # only the fracture rim is inked inside a part: knob contours came out as stray ticks (the old attempt's fault)
    bx_rim(K, hero, L_HERO, PL_INNER); bx_rim(K, lie, L_LIE, PL_INNER)
    for ob in K.col.objects:
        if ob.get('ink_width') == 6:
            ob['ink_width'] = PL_INNER
    info = contract(K, hosts, 'Bauxite ore: a rounded rust red lump sawn in half through ringed pisoids, one half standing and one '
                    'lying cut face up, and loose dark pisoids', inner=PL_INNER)
    info['revision'] = BX_REVISION; info['outline']['component_boundaries'] = True; info['stipple']['strength'] = 0.38
    info['stipple']['groups'] = [{'name': 'shaded_faces', 'labels': sorted({bpy.data.objects[n]['part_label'] for n in hosts}),
                                  'thresholds': [0.575, 0.50, 0.30]}]
    return info
