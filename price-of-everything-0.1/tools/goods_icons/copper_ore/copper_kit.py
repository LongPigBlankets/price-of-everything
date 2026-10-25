"""Copper ore (g_003 copper_ore). Real oxidised copper ore is an earthy brown host rock (limonite and goethite stained)
carrying copper minerals along its cracks and in its grain: malachite in green streaks and stripes that run roughly
parallel through a lump, green flecks scattered through the matrix, and brassy coppery gold grains of chalcopyrite,
loose in the rock and caught in the green veins. The icon: a few hard, broken lumps of that rock in the old icon's red
brown, with broad planar breaks, streaked, striped and speckled all over, the hero's biggest break turned to the light.
On the set's grid, camera, light, 12/4 px ink and dots on the shaded sides."""
import random
from mathutils import noise as mnoise
CU_REVISION = 'copper_ore_v15'
# owner (v9): "use a more reddish brown like ones in the old icon"; the old art's browns measure mid (150, 90, 66),
# lit (186, 126, 90), shaded (126, 78, 54) and darkest (90, 54, 42)
CU_TONES = {'host': ((112, 64, 46), (150, 90, 66), (184, 124, 90)),
            'host_hi': ((130, 80, 56), (172, 112, 80), (204, 148, 106)),
            # owner (v10): "make them less bright in the centre - a single green colour and darken it a bit": no pale core
            'green': ((16, 70, 52), (28, 108, 77), (46, 138, 96)),
            'gold': ((156, 100, 38), (220, 164, 64), (250, 208, 118)),
            'gold_hi': ((214, 162, 72), (246, 208, 120), (252, 230, 168)),   # the glint in a big grain: metal, not paint
            'dark': ((70, 38, 30), (90, 52, 40), (104, 62, 46))}


def cu_in(node, name):
    """the node's AVAILABLE input called name (a Mix node holds float, vector and colour sockets of one name)"""
    for s in node.inputs:
        if s.name == name and getattr(s, 'enabled', True):
            return s
    return node.inputs[name]


def cu_out(node, name):
    for s in node.outputs:
        if s.name == name and getattr(s, 'enabled', True):
            return s
    return node.outputs[name]


def cu_ore_mat(name, seed=0.0, vein_dir=(0.55, -0.20, 0.80), freq=11.0, stripe=0.585, thick=0.065, warp=0.40, broken=0.42,
               speck=0.68, gold=0.74, s_scale=17.0, g_scale=9.5):
    """the ore's skin: a toon ramp per mineral on ONE shading factor, picked per pixel by fields in object space.
    Stripes thin out as the surface turns from the view, and past ~77 degrees the pattern is off (slivers there).
    Stripes: t = position along the vein direction, warped by low noise; a 1D noise of t picks bands of irregular width
    and spacing, some whole stripes widened by a slow noise of t, broken into streaks by a slow 3D noise. Paler and darker
    brown bands run beside them. Specks are Voronoi cells on noise-jittered coordinates
    (irregular grains) kept by their random colour; brassy grains also sit inside the green streaks."""
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True; nt = m.node_tree; nt.nodes.clear(); L = nt.links.new
    out = nt.nodes.new('ShaderNodeOutputMaterial'); emis = nt.nodes.new('ShaderNodeEmission')
    diff = nt.nodes.new('ShaderNodeBsdfDiffuse'); diff.inputs['Color'].default_value = (1, 1, 1, 1)
    s2r = nt.nodes.new('ShaderNodeShaderToRGB'); L(diff.outputs[0], s2r.inputs[0])
    ramps = {}
    for k, tones in CU_TONES.items():
        r = nt.nodes.new('ShaderNodeValToRGB'); r.color_ramp.interpolation = 'CONSTANT'; els = r.color_ramp.elements
        lit_at = 0.80 if k.startswith('gold') else 0.975            # the brassy grains catch the light more readily
        els[0].position = 0.0; els[0].color = (*pl_rgb(*tones[0]), 1)
        els[1].position = PL_SHADE_STEP; els[1].color = (*pl_rgb(*tones[1]), 1)
        e = els.new(lit_at); e.color = (*pl_rgb(*tones[2]), 1)
        L(s2r.outputs['Color'], r.inputs['Fac']); ramps[k] = r.outputs['Color']
    P = nt.nodes.new('ShaderNodeTexCoord').outputs['Object']
    Nw = nt.nodes.new('ShaderNodeNewGeometry').outputs['Normal']

    def math(op, a, b=None):
        n = nt.nodes.new('ShaderNodeMath'); n.operation = op
        for i, x in enumerate((a, b)):
            if x is None:
                continue
            if isinstance(x, (int, float)):
                n.inputs[i].default_value = x
            else:
                L(x, n.inputs[i])
        return n.outputs[0]

    def vmath(op, a, b):
        n = nt.nodes.new('ShaderNodeVectorMath'); n.operation = op
        for i, x in enumerate((a, b)):
            if isinstance(x, (tuple, list)):
                n.inputs[i].default_value = x
            else:
                L(x, n.inputs[i])
        return n.outputs['Value'] if op == 'DOT_PRODUCT' else n.outputs['Vector']

    def noise(vec, scale, detail=2.0, rough=0.55, off=0.0, colour=False):
        n = nt.nodes.new('ShaderNodeTexNoise'); n.inputs['Scale'].default_value = scale
        n.inputs['Detail'].default_value = detail; n.inputs['Roughness'].default_value = rough
        L(vmath('ADD', vec, (off, off * 0.6, off * 0.3)), n.inputs['Vector'])
        return n.outputs['Color'] if colour else n.outputs['Fac']

    def noise1(w, scale, detail=1.5, off=0.0):
        n = nt.nodes.new('ShaderNodeTexNoise'); n.noise_dimensions = '1D'; n.inputs['Scale'].default_value = scale
        n.inputs['Detail'].default_value = detail; n.inputs['Roughness'].default_value = 0.5
        L(math('ADD', w, off), n.inputs['W']); return n.outputs['Fac']

    def voronoi(vec, scale):
        n = nt.nodes.new('ShaderNodeTexVoronoi'); n.distance = 'EUCLIDEAN'; n.feature = 'F1'
        n.inputs['Scale'].default_value = scale; n.inputs['Randomness'].default_value = 1.0
        L(vec, n.inputs['Vector'])
        sep = nt.nodes.new('ShaderNodeSeparateColor'); L(n.outputs['Color'], sep.inputs[0])
        return n.outputs['Distance'], sep.outputs[0], sep.outputs[1], sep.outputs[2]

    AND = lambda a, b: math('MULTIPLY', a, b)
    GT = lambda a, b: math('GREATER_THAN', a, b)
    s = seed
    zone = noise(P, 1.2, off=s + 11)
    # stripes along the vein direction
    wv = math('MULTIPLY', math('SUBTRACT', noise(P, 1.0, 2.0, off=s), 0.5), warp)
    t = math('ADD', vmath('DOT_PRODUCT', P, tuple(Vector(vein_dir).normalized())), wv)
    band = noise1(t, freq, off=s * 7.3)
    # review (v12): grazing faces squeezed the stripes into slivers; past N.V 0.45 every threshold rises
    ndv = vmath('DOT_PRODUCT', Nw, tuple(VIEW))
    graze = math('MINIMUM', math('MAXIMUM', math('MULTIPLY', math('SUBTRACT', 0.45, ndv), 0.6), 0.0), 0.25)
    # past ~77 degrees from the view the pattern is off: specks squashed into slivers and a thinned stripe into a hairline
    face_on = GT(ndv, 0.22)
    thr = math('ADD', math('SUBTRACT', stripe, math('MULTIPLY', math('SUBTRACT', zone, 0.5), 0.20)), graze)
    # owner (v10): "thicken some of the lines": a slow noise of t widens whole stripes, not patches along one
    thr = math('SUBTRACT', thr, math('MULTIPLY', GT(noise1(t, freq * 0.35, off=s * 1.9 + 90), 0.53), thick))
    whole = GT(noise(P, 3.4, off=s + 3), broken)
    green = AND(GT(band, thr), whole)
    brown = AND(GT(noise1(t, freq * 0.8, off=s * 3.1 + 40), math('ADD', graze, 0.635)), GT(noise(P, 2.2, off=s + 17), 0.40))
    dark_band = AND(GT(noise1(t, freq * 0.9, off=s * 2.3 + 70), math('ADD', graze, 0.66)), GT(noise(P, 3.0, off=s + 23), 0.46))
    # no crossing veins: thin ones inked as 1 px hairlines (review, v12) and a wider one, a sheet in 3D, spread into a
    # green blob wherever a face ran nearly parallel to it (v12-v13)
    # specks on jittered coordinates: irregular grains, not discs
    jit = vmath('ADD', P, vmath('MULTIPLY', vmath('SUBTRACT', noise(P, 9.0, 2.0, off=s + 5, colour=True), (0.5, 0.5, 0.5)), (0.07, 0.07, 0.07)))
    d1, r1, g1, b1 = voronoi(vmath('ADD', jit, (s * 3.1, s * 0.5, s * 2.2)), s_scale)
    grain1 = AND(GT(r1, speck), math('LESS_THAN', d1, math('ADD', math('MULTIPLY', g1, 0.12), 0.16)))   # no crumbs under ~5 px
    speck_g = AND(grain1, math('LESS_THAN', b1, 0.78))
    speck_d = AND(grain1, GT(b1, 0.78))
    d2, r2, g2, b2 = voronoi(vmath('ADD', jit, (s * 0.7 + 9, s * 2.6, s * 1.3)), g_scale)
    gr = math('ADD', math('MULTIPLY', g2, 0.18), 0.11)
    speck_y = AND(GT(r2, gold), math('LESS_THAN', d2, gr))
    glint = AND(AND(speck_y, GT(g2, 0.35)), math('LESS_THAN', d2, math('MULTIPLY', gr, 0.42)))
    vein_y = AND(AND(GT(band, math('ADD', thr, 0.02)), whole), GT(noise(P, 7.0, 2.0, off=s + 13), 0.64))   # owner (v11): 30-40% fewer gold specks
    # layers, back to front
    col = ramps['host']
    layers = ((brown, 'host_hi'), (dark_band, 'dark'), (green, 'green'),
                     (speck_d, 'dark'), (speck_g, 'green'), (vein_y, 'gold'), (speck_y, 'gold'), (glint, 'gold_hi'))
    for fac, top in layers:
        fac = AND(fac, face_on)
        mix = nt.nodes.new('ShaderNodeMix'); mix.data_type = 'RGBA'
        L(fac, cu_in(mix, 'Factor')); L(col, cu_in(mix, 'A')); L(ramps[top], cu_in(mix, 'B')); col = cu_out(mix, 'Result')
    L(col, emis.inputs['Color']); L(emis.outputs[0], out.inputs[0])
    return m


def cu_rock(K, name, centre, size, seed, mat, label, cuts=6, depth=(0.66, 0.82), first=None, yaw=0.0):
    """a hard broken lump: a lumpy rounded core (an icosphere on an ellipsoid under low noise) broken by planar cuts,
    each a flat face; `first` = (normal, depth) places the big break deliberately. Breaks are material slot 1 (the same
    skin, flat shaded), the old crust slot 0 (smooth)."""
    rng = random.Random(seed); sx, sy, sz = size; cx, cy = centre
    bm = bmesh.new(); bmesh.ops.create_icosphere(bm, subdivisions=4, radius=1.0)
    off = Vector((seed * 3.1, seed * 1.7, seed * 0.9))
    for v in bm.verts:
        d = v.co.normalized(); s = 1 + 0.10 * mnoise.noise(d * 1.3 + off) + 0.04 * mnoise.noise(d * 3.4 + off)
        v.co = Vector((d.x * sx * s, d.y * sy * s, (d.z * s * 0.5 + 0.5) * sz * 1.08 - sz * 0.08 - sz * 0.5))
    bmesh.ops.rotate(bm, cent=Vector(), matrix=Matrix.Rotation(math.radians(yaw), 3, 'Z'), verts=bm.verts[:])
    planes = []
    if first:
        planes.append((Vector(first[0]).normalized(), first[1]))
    while len(planes) < cuts:
        a = rng.uniform(0, 2 * math.pi); el = rng.uniform(-0.15, 0.85)
        n = Vector((math.cos(a) * math.cos(el), math.sin(a) * math.cos(el), math.sin(el)))
        if any(n.dot(p) > 0.72 for p, _ in planes):       # no two breaks on one side: a sliver between them
            continue
        planes.append((n, rng.uniform(*depth)))
    region = bm.faces.layers.int.new('cu_region')    # 0 = the old crust, k = the k-th break (a layer survives later bisects)
    for k, (n, dep) in enumerate(planes):
        far = max(v.co.dot(n) for v in bm.verts)
        for f in bx_cut(bm, n * far * dep, n, 1):
            f[region] = k + 1
    bmesh.ops.translate(bm, vec=Vector((cx, cy, sz * 0.5)), verts=bm.verts[:])
    for f in bx_cut(bm, Vector((0, 0, 0)), Vector((0, 0, -1)), 0):
        f[region] = -1
    bmesh.ops.dissolve_degenerate(bm, dist=1e-5, edges=bm.edges[:])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    for e in bm.edges:                                 # breaks keep hard rims; the crust is smooth
        fs = e.link_faces
        e.smooth = not (len(fs) == 2 and (fs[0].material_index == 1 or fs[1].material_index == 1))
    me = bpy.data.meshes.new(name); bm.to_mesh(me); bm.free()
    o = K.obj(name, me, mat, False); o.data.materials.append(mat)
    for p in o.data.polygons:
        p.use_smooth = p.material_index == 0 and p.normal.z > -0.99
    noink(o); o['part_label'] = label
    return o


def cu_region_lines(K, ob, label, name, min_line=0.03):
    """ink every edge where two regions meet (a break and the crust, or two breaks) with both faces toward the camera,
    chained into polylines: a rim always runs on to another rim or the silhouette, so no line stops mid-face (an angle
    threshold faded shallow rims out and left dangling ends)"""
    me = ob.data; mw = ob.matrix_world; reg = [d.value for d in me.attributes['cu_region'].data]
    V = np.array([(mw @ v.co)[:] for v in me.vertices]); FN = np.array([(mw.to_3x3() @ p.normal).normalized()[:] for p in me.polygons])
    view = np.array(VIEW[:]); front = FN @ view > 0; ef = {}
    for pi, p in enumerate(me.polygons):
        for ek in p.edge_keys:
            ef.setdefault(ek, []).append(pi)
    adj = {}
    for (a, b), fl in ef.items():
        if len(fl) == 2 and reg[fl[0]] != reg[fl[1]] and -1 not in (reg[fl[0]], reg[fl[1]]) and front[fl[0]] and front[fl[1]]:
            adj.setdefault(a, []).append(b); adj.setdefault(b, []).append(a)
    used = set(); chains = []

    def walk(v0, v1):
        path = [v0, v1]; used.add(frozenset((v0, v1)))
        while len(adj[path[-1]]) == 2:
            nxt = [w for w in adj[path[-1]] if frozenset((path[-1], w)) not in used]
            if not nxt:
                break
            used.add(frozenset((path[-1], nxt[0]))); path.append(nxt[0])
        return path
    for pass_ in (0, 1):
        for v0 in adj:
            if pass_ == 0 and len(adj[v0]) == 2:
                continue
            for w in adj[v0]:
                if frozenset((v0, w)) not in used:
                    chains.append(walk(v0, w))

    def screen_len(ch):
        d = np.diff(V[ch], axis=0); d = d - np.outer(d @ view, view); return float(np.linalg.norm(d, axis=1).sum())
    chains = [ch for ch in chains if screen_len(ch) >= min_line]
    for k, ch in enumerate(chains):
        tagged_line(K, '%s_line%d' % (name, k), [tuple(map(float, V[i] + view * E)) for i in ch], label, 6, False)
    return len(chains)


CU_HERO = dict(at=(0.12, -0.05), size=(0.84, 0.78, 1.46), seed=11, yaw=10.0, cuts=8,
               first=((-0.20, -0.72, 0.66), 0.72), vein=(0.20, 0.55, 0.81))
CU_ROCKS = [  # the back left and the front left lumps
    dict(at=(-0.70, -0.52), size=(0.56, 0.52, 1.00), seed=23, yaw=30.0, cuts=7, first=None, vein=(-0.30, -0.60, 0.74)),
    dict(at=(-0.40, 0.66), size=(0.42, 0.38, 0.48), seed=31, yaw=-20.0, cuts=6, first=None, vein=(0.20, 0.70, 0.68)),
]
CU_CHIPS = [((0.66, 0.62), (0.20, 0.18, 0.17), 41), ((0.88, 0.42), (0.15, 0.13, 0.12), 43)]
CU_LINE_TIP = 0.45                                 # break rims fade toward their ends (hand drawn, like iron ore)
CU_LINE_MIN = 0.03                                 # world units on screen: only crumbs of rim are dropped


def build_copper_ore():
    return cu_build('copper_ore')


def cu_build(name):
    setup_icon_rig(); K = Kit(open_collection('ICON_' + name)); hosts = []
    rocks = [CU_HERO] + CU_ROCKS
    for j, r in enumerate(rocks):
        mat = cu_ore_mat('cu_skin_%d' % j, 1.3 + 2.1 * j, vein_dir=r['vein'])
        o = cu_rock(K, 'rock_hero' if j == 0 else 'rock_%d' % j, scr(*r['at']), r['size'], r['seed'], mat, 1 + j,
                    cuts=r['cuts'], first=r['first'], yaw=r['yaw'])
        hosts.append(o.name)
    for j, (at, size, seed) in enumerate(CU_CHIPS):
        mat = cu_ore_mat('cu_chip_%d' % j, 7.1 + j, freq=9.0, stripe=0.53, gold=0.64, g_scale=14.0)
        o = cu_rock(K, 'chip_%d' % j, scr(*at), size, seed, mat, 1 + len(rocks) + j, cuts=5, depth=(0.55, 0.74))   # review (v12): 3 cuts read as coffee beans
        hosts.append(o.name)
    for n in hosts:
        bx_dots(bpy.data.objects[n], amount=0.30)
    bpy.context.view_layer.update()
    for n in hosts:
        ob = bpy.data.objects[n]
        cu_region_lines(K, ob, ob['part_label'], n, min_line=CU_LINE_MIN)
    for ob in K.col.objects:
        if ob.get('line_path'):
            ob['ink_width'] = PL_INNER; ob['ink_tip'] = CU_LINE_TIP
    info = contract(K, hosts, 'Copper ore: hard broken lumps of dark brown host rock streaked and striped with green '
                    'malachite and speckled with green and brassy coppery gold grains, the hero\'s big break turned to the light',
                    inner=PL_INNER)
    info['revision'] = CU_REVISION; info['outline']['component_boundaries'] = True; info['stipple']['strength'] = 0.34
    info['stipple']['protect_gold'] = True              # review (v12): halftone on the grains read as dirty paint
    info['stipple']['groups'] = [{'name': 'shaded_faces', 'labels': sorted({bpy.data.objects[n]['part_label'] for n in hosts}),
                                  'thresholds': [0.575, 0.50, 0.30]}]
    return info
