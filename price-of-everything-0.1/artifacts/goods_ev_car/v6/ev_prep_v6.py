"""EV study: the downloaded SUV with its grille covered flat in the body colour, the brand logo removed, a dark glass
greenhouse (it has no roof or glass), and the body painted blue.
    Blender --background --factory-startup --disable-autoexec download.blend --python ev_prep.py -- <out.blend>"""
import bpy, bmesh, sys, math
from mathutils import Vector
out = sys.argv[sys.argv.index('--') + 1]
ob = bpy.data.objects['Plane.002']; me = ob.data; mw = ob.matrix_world
names = [m.name if m else None for m in me.materials]; mi = {n: i for i, n in enumerate(names)}
bm = bmesh.new(); bm.from_mesh(me); bm.faces.ensure_lookup_table()
def islands(faces):
    fset = set(f.index for f in faces); seen = set(); out_ = []
    for f0 in faces:
        if f0.index in seen: continue
        st = [f0]; seen.add(f0.index); comp = []
        while st:
            f = st.pop(); comp.append(f)
            for e in f.edges:
                for g in e.link_faces:
                    if g.index in fset and g.index not in seen and g.material_index == f0.material_index:
                        seen.add(g.index); st.append(g)
        out_.append(comp)
    return out_
def box(comp):
    P = [mw @ v.co for f in comp for v in f.verts]
    return [min(p.x for p in P), max(p.x for p in P), min(p.y for p in P), max(p.y for p in P), min(p.z for p in P), max(p.z for p in P)]
front = [f for f in bm.faces if (mw @ f.calc_center_median()).y < -1.75]
kill, paint = [], []; flatten = []; logo_faces = []
for comp in islands(front):
    nm = names[comp[0].material_index]; x0, x1, y0, y1, z0, z1 = box(comp)
    slat = nm == 'metal' and x1 - x0 < 0.07 and z0 > -0.12 and z1 < 0.18 and 7.45 < x0 < 8.55
    logo = 7.86 < x0 and x1 < 8.12 and z0 > 0.17 and z1 < 0.27 and x1 - x0 < 0.2    # every part of the brand mark
    strip = nm == 'Material.001' and z0 > -0.16 and z1 < -0.08 and x1 - x0 > 0.5
    backing = nm == 'lastil' and 7.4 < x0 and x1 < 8.6 and z0 > -0.13 and z1 < 0.19 and y0 < -2.2
    if slat:
        kill += comp
    elif logo:
        logo_faces += comp
    elif backing or strip:
        paint += comp
    if backing:
        flatten += comp
print('grille: delete %d faces (slats, logo), paint %d (backing, strip)' % (len(kill), len(paint)))
for f in paint:
    f.material_index = mi['ana renk']
import numpy as np
mwi = mw.inverted()
def press_flat(faces, pad):
    """project the faces' vertices onto a plane fitted to the body around them"""
    vs = list({v for f in faces for v in f.verts}); P = np.array([(mw @ v.co)[:] for v in vs])
    lo, hi = P.min(0) - pad, P.max(0) + pad
    ring = np.array([(mw @ v.co)[:] for v in bm.verts if all(lo[i] <= (mw @ v.co)[i] <= hi[i] for i in range(3))])
    c = ring.mean(0); u, s_, vt = np.linalg.svd(ring - c); n = vt[2]
    for v, p in zip(vs, P):
        q = p - np.dot(p - c, n) * n; v.co = mwi @ Vector(q)
# v2: the brand mark goes altogether and its recess is closed with a patch in the body colour (pressing it flat left
# an outline the ink picked up)
if logo_faces:
    bmesh.ops.delete(bm, geom=list(set(logo_faces)), context='FACES')
    lo_ = Vector((7.84, -2.40, 0.15)); hi_ = Vector((8.14, -2.10, 0.30))
    edges = [e for e in bm.edges if e.is_boundary and all(lo_.x <= (mw @ v.co).x <= hi_.x and lo_.y <= (mw @ v.co).y <= hi_.y
                                                         and lo_.z <= (mw @ v.co).z <= hi_.z for v in e.verts)]
    res_ = bmesh.ops.holes_fill(bm, edges=edges, sides=0)
    for f in res_['faces']:
        f.material_index = mi['ana renk']; f.smooth = True
    print('logo: removed, %d boundary edges, %d patch faces' % (len(edges), len(res_['faces'])))
# the covered grille: a clean panel on a smooth surface y = f(x, z) fitted to the ribbed backing, cut to the opening's
# outline (the backing's own boundary in x-z); the backing goes
fv = list({v for f in flatten for v in f.verts})
W = np.array([(mw @ v.co)[:] for v in fv]); xm, zm = W[:, 0].mean(), W[:, 2].mean()
def feats(x, z):
    x, z = np.asarray(x) - xm, np.asarray(z) - zm; return np.column_stack([np.ones_like(x), x, z, x * x, x * z, z * z])
coef = np.linalg.lstsq(feats(W[:, 0], W[:, 2]), W[:, 1], rcond=None)[0]
x0_, x1_, z0_, z1_ = W[:, 0].min(), W[:, 0].max(), W[:, 2].min(), W[:, 2].max()
tris = []                                           # the backing's faces as x-z triangles (the opening's shape)
for f in flatten:
    q = [((mw @ v.co).x, (mw @ v.co).z) for v in f.verts]
    tris += [(q[0], q[k], q[k + 1]) for k in range(1, len(q) - 1)]
T = np.array(tris)
def inside_pts(px, pz):
    a, b, c = T[:, 0], T[:, 1], T[:, 2]; P = np.stack([px, pz], -1)[:, None, :]
    v0, v1, v2 = c - a, b - a, P - a
    d00, d01, d11 = (v0 * v0).sum(-1), (v0 * v1).sum(-1), (v1 * v1).sum(-1); d20, d21 = (v2 * v0).sum(-1), (v2 * v1).sum(-1)
    den = d00 * d11 - d01 * d01; den = np.where(np.abs(den) < 1e-14, 1e-14, den)
    u = (d11 * d20 - d01 * d21) / den; w = (d00 * d21 - d01 * d20) / den
    return ((u >= -1e-6) & (w >= -1e-6) & (u + w <= 1 + 1e-6)).any(-1)
nxg, nzg = 64, 20; gx = np.linspace(x0_, x1_, nxg); gz = np.linspace(z0_, z1_, nzg)
cxs = np.array([(gx[i] + gx[i + 1]) / 2 for j in range(nzg - 1) for i in range(nxg - 1)])
czs = np.array([(gz[j] + gz[j + 1]) / 2 for j in range(nzg - 1) for i in range(nxg - 1)])
cell_in = inside_pts(cxs, czs)
pmesh = bpy.data.meshes.new('ev_grille_cover'); gverts = []; gfaces = []
for j, z in enumerate(gz):
    for i, x in enumerate(gx):
        gverts.append((x, float(feats([x], [z]) @ coef) - 0.003, z))
for j in range(nzg - 1):
    for i in range(nxg - 1):
        if cell_in[j * (nxg - 1) + i]:
            gfaces.append((j * nxg + i, j * nxg + i + 1, (j + 1) * nxg + i + 1, (j + 1) * nxg + i))
pmesh.from_pydata(gverts, [], gfaces); pmesh.update()
cover = bpy.data.objects.new('ev_grille_cover', pmesh); bpy.context.scene.collection.objects.link(cover)
pmesh.materials.append(bpy.data.materials['ana renk'])
for p_ in pmesh.polygons:
    p_.use_smooth = True
kill += flatten
print('grille cover: %d faces over the opening (fit residual %.4f)' % (len(gfaces), float(np.abs(feats(W[:, 0], W[:, 2]) @ coef - W[:, 1]).max())))
# v3 (owner: the shipped art shows the inside): the cabin stays, seen through open windows; its body-blue parts
# (visors, trims) take the cabin colour
killset = set(kill)
for comp in islands([f for f in bm.faces if f not in killset and f.material_index == mi['ana renk']
                     and abs((mw @ f.calc_center_median()).x - 7.99) < 0.75 and (mw @ f.calc_center_median()).z > 0.2
                     and -1.3 < (mw @ f.calc_center_median()).y < 1.7]):
    x0, x1, y0, y1, z0, z1 = box(comp)
    if max(x1 - x0, y1 - y0, z1 - z0) < 1.3:
        for f in comp:
            f.material_index = mi['Material.001']
# v3: the shipped art's lower body: tan cladding round the arches and sills and on the bumpers (the model's black
# cladding and chrome strips), a dark intake and side vents in front; the grille's chrome ring in the body colour
if 'cladding' not in bpy.data.materials:
    cm = bpy.data.materials.new('cladding'); cm.use_nodes = True
    cm.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value = (0.35, 0.34, 0.29, 1); cm.diffuse_color = (0.35, 0.34, 0.29, 1)
me.materials.append(bpy.data.materials['cladding']); mi['cladding'] = len(me.materials) - 1; names.append('cladding')
killset = set(kill)
for comp in islands([f for f in bm.faces if f not in killset and f.material_index in (mi['lastil'], mi['metal'])]):
    nm = names[comp[0].material_index]; x0, x1, y0, y1, z0, z1 = box(comp)
    if nm == 'lastil' and x1 - x0 > 1.5 and y1 - y0 > 4.0 and z1 < 0.2:          # the cladding band
        for f in comp:
            c_ = mw @ f.calc_center_median()
            if not (c_.y < -2.0 and abs(c_.x - 7.99) < 0.65 and c_.z > -0.42):   # but the front intake stays dark
                f.material_index = mi['cladding']
    elif nm == 'metal' and x1 - x0 > 1.5 and y1 - y0 > 4.0 and z1 < -0.2:        # the chrome sill strips and skid plates
        for f in comp: f.material_index = mi['cladding']
    elif nm == 'metal' and y1 < -2.0 and 0.25 < x1 - x0 < 0.4 and z1 < 0.0:      # the chevrons round the side vents
        for f in comp: f.material_index = mi['cladding']
    elif nm == 'metal' and x1 - x0 > 1.5 and y0 < -2.25 and y1 < -1.7 and z1 < 0.3:   # the grille's chrome ring
        for f in comp: f.material_index = mi['ana renk']
# the number plate recess goes to the body colour
for comp in islands([f for f in bm.faces if f not in killset and (mw @ f.calc_center_median()).y < -2.18]):
    x0, x1, y0, y1, z0, z1 = box(comp)
    if 7.65 < x0 and x1 < 8.35 and -0.36 < z0 and z1 < -0.10 and names[comp[0].material_index] != 'ana renk' and x1 - x0 > 0.3:
        for f in comp: f.material_index = mi['ana renk']
# v3: the wheels go (tyres, turbine rims, brakes): everything inside each wheel's cylinder; new ones are built below
WHEELS = [(xw, yw, -0.32) for xw in (7.26, 8.73) for yw in (-1.505, 1.285)]
for f in bm.faces:
    if f in killset: continue
    c_ = mw @ f.calc_center_median()
    for xw, yw, zw in WHEELS:
        if abs(c_.x - xw) < 0.145 and math.hypot(c_.y - yw, c_.z - zw) < 0.325:
            kill.append(f); break
bmesh.ops.delete(bm, geom=list({f for f in kill}), context='FACES')
bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=1e-5)
# v3: the painted panels smoothed a little (the model's lumps showed as blotchy tone steps on the doors); only vertices
# whose faces are all body paint and that are not on an open edge, so panel edges and shut lines stay put
body_i = mi['ana renk']
sv = [v for v in bm.verts if v.link_faces and all(f.material_index == body_i for f in v.link_faces) and not any(e.is_boundary for e in v.link_edges)]
for _ in range(4):
    bmesh.ops.smooth_laplacian_vert(bm, verts=sv, lambda_factor=0.4, lambda_border=0.0, use_x=True, use_y=True, use_z=True, preserve_volume=True)
print('smoothed %d body vertices' % len(sv))
# v4 (owner: "try to shape the headlamps now"): the model's lamps (and their housings) go to the body colour and new
# lamps are laid on the nose as the shipped art draws them: a slim strip under the bonnet's leading edge, tapering from
# the corner, which it wraps, to a slanted inner end
lamp_i = mi['on emis']
for f in bm.faces:
    c_ = mw @ f.calc_center_median()
    if f.material_index == lamp_i or (f.material_index == mi['Material.001'] and c_.y < -1.8 and c_.z > 0.0):
        f.material_index = body_i
# v4 (owner: "remove the artefacts on the sideskirt"): between the arches one clean line, cladding below, body above
SILL = -0.30
for f in bm.faces:
    c_ = mw @ f.calc_center_median()
    if abs(c_.x - 7.99) > 0.55 and -1.05 < c_.y < 0.85 and c_.z < 0.10:
        if c_.z < SILL and f.material_index in (body_i, mi['metal'], mi['lastil'], mi['cladding']):
            f.material_index = mi['cladding']
        elif c_.z >= SILL and f.material_index in (mi['metal'], mi['lastil'], mi['cladding']):
            f.material_index = body_i
# v4 (owner: the interior "should use a single colour and thin linework"): the cabin's dark trim (wheel, vents) joins it
for f in bm.faces:
    c_ = mw @ f.calc_center_median()
    if f.material_index == mi['lastil'] and abs(c_.x - 7.99) < 0.78 and c_.z > 0.0 and -1.25 < c_.y < 1.8:
        f.material_index = mi['Material.001']
from mathutils.bvhtree import BVHTree
bmw = bm.copy(); bmw.transform(mw); tree = BVHTree.FromBMesh(bmw)
# v4b: the nose round each lamp as a smooth surface y = f(x, z) (a front envelope of ray hits, so the old lamp's recess
# is ignored); a body-colour panel on it covers the recess, the lamp strip sits just in front of the panel
def nose_fit(side):
    P = []
    for i in range(40):
        for j in range(18):
            dx = 0.30 + 0.62 * i / 39; z = 0.02 + 0.30 * j / 17
            h = tree.ray_cast(Vector((7.99 + side * dx, -4.0, z)), Vector((0, 1, 0)), 10.0)
            if h[0] is not None:
                P.append((dx, z, h[0].y))
    P = np.array(P); keep = np.ones(len(P), bool)
    A = lambda d, z: np.column_stack([np.ones_like(d), d, z, d * d, d * z, z * z, d ** 3, d * d * z])
    for _ in range(6):
        c = np.linalg.lstsq(A(P[keep, 0], P[keep, 1]), P[keep, 2], rcond=None)[0]
        keep = P[:, 2] <= A(P[:, 0], P[:, 1]) @ c + 0.004        # drop points behind the envelope (the recess)
    return lambda d, z: float(A(np.array([d]), np.array([z])) @ c)
def patch(name, side, f, outline, mat, lift, NU=30, NV=8):
    vs, fs = [], []
    for i in range(NU + 1):
        u = i / NU
        for j in range(NV + 1):
            v = j / NV; dx, z = outline(u, v); y = f(dx, z)
            h = tree.ray_cast(Vector((7.99 + side * dx, -4.0, z)), Vector((0, 1, 0)), 10.0)
            if side < 0 and h[0] is not None and y < h[0].y - 0.03:   # the far nose's fit overshoots its turn: follow the body
                y = h[0].y
            elif False:
                y = h[0].y
            vs.append((7.99 + side * dx, y - lift, z))
    for i in range(NU):
        for j in range(NV):
            a = i * (NV + 1) + j; q = (a, a + NV + 1, a + NV + 2, a + 1); fs.append(q if side > 0 else q[::-1])
    m_ = bpy.data.meshes.new(name); m_.from_pydata(vs, [], fs); m_.update(); m_.materials.append(bpy.data.materials[mat])
    o_ = bpy.data.objects.new(name, m_); bpy.context.scene.collection.objects.link(o_); return len(fs)
lf = []
for side in (-1, 1):
    f = nose_fit(side); tag = 'r' if side > 0 else 'l'
    # the cover: the old lamp's area (dx 0.44..0.84, z 0.05..0.25)
    lf += [0] * patch('ev_nose_' + tag, side, f, lambda u, v: (0.42 + 0.44 * u, 0.045 + 0.215 * v), 'ana renk', 0.002)
    # the lamp: from a slanted inner end to the corner, thicker at the corner
    def lamp_outline(u, v):
        # v5 (owner: "make the angle of the headlamp meet the radiator at a steeper angle"): the inner end a straight
        # diagonal, its foot 0.13 outboard of its top
        x0 = 0.40 + 0.13 * (1 - v); dx = x0 + (0.86 - x0) * u
        zt = 0.248 + 0.004 * u; zb = 0.205 - 0.050 * u
        return dx, zb + (zt - zb) * v
    lf += [0] * patch('ev_lamp_' + tag, side, f, lamp_outline, 'on emis', 0.005)
bmw.free()
print('lamps: %d faces' % len(lf))
bm.to_mesh(me); bm.free(); me.update()
# the body in the shipped EV's blue; the other paints as the icon will need them
def base(name, rgb):
    m = bpy.data.materials[name]; n = m.node_tree.nodes.get('Principled BSDF'); n.inputs['Base Color'].default_value = rgb + (1.0,)
    m.diffuse_color = rgb + (1.0,)
base('ana renk', (0.10, 0.20, 0.42))
# a dark glass greenhouse: the hull of the pillars and frames above the belt line, dropped to inside the doors
cx = 0.5 * (min((mw @ v.co).x for v in me.vertices) + max((mw @ v.co).x for v in me.vertices))
pts = []
for p in me.polygons:
    if names[p.material_index] != 'ana renk':          # the body's frame only: the roof rails stand proud of the glass
        continue
    for vi in p.vertices:
        w = mw @ me.vertices[vi].co
        if w.z > 0.42 and abs(w.x - cx) < 0.80 and -1.55 < w.y < 1.95:
            pts.append(w)
pts = list({(round(p.x, 3), round(p.y, 3), round(p.z, 3)) for p in pts})
bm2 = bmesh.new()
for p in pts:
    bm2.verts.new(p); bm2.verts.new((p[0], p[1], 0.30))
bmesh.ops.convex_hull(bm2, input=bm2.verts[:])
c = sum((v.co for v in bm2.verts), Vector()) / len(bm2.verts)
for v in bm2.verts:                                   # just inside the frames, so the pillars and rails stand proud
    d = v.co - c; d.z *= 0.6; v.co -= d.normalized() * 0.005
bm2.normal_update()
bmesh.ops.delete(bm2, geom=[f for f in bm2.faces if f.normal.z < 0.88 or f.calc_center_median().y < -0.66
                            or f.calc_center_median().y > 1.50], context='FACES')    # v3: the roof only, header to header
bmesh.ops.delete(bm2, geom=[v for v in bm2.verts if not v.link_faces], context='VERTS')
gme = bpy.data.meshes.new('ev_roof'); bm2.to_mesh(gme); bm2.free()
roof = bpy.data.objects.new('ev_roof', gme); bpy.context.scene.collection.objects.link(roof)
gme.materials.append(bpy.data.materials['ana renk'])
print('roof: %d points -> %d faces' % (len(pts), len(gme.polygons)))
# v3: five-spoke wheels as the shipped art draws them: a dark tyre, a light rim of five broad spokes round a hub, a dark
# disc behind the spokes; the outer face toward the car's side
def mat(name, rgb):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name); m.use_nodes = True
    m.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value = rgb + (1,); m.diffuse_color = rgb + (1,); return m
m_tyre, m_rim, m_in = mat('tyre', (0.09, 0.09, 0.08)), mat('rim', (0.34, 0.34, 0.30)), mat('wheel_inner', (0.04, 0.04, 0.04))
RO, RI, WW = 0.314, 0.232, 0.24                         # tyre outer and inner (rim) radius, width (v3b: rim 0.74 of the tyre)
def wheel(name, xw, yw, zw, side):
    wb = bmesh.new(); N = 64
    def P(r, w, a):                                      # (radial, lateral, angle) -> world
        return (xw + side * w, yw + r * math.cos(a), zw + r * math.sin(a))
    # the tyre: a revolved rounded section (closed ring)
    prof = []
    for k in range(7):                                   # outer shoulder (rounded)
        t = math.pi / 2 * k / 6; prof.append((RO - 0.035 + 0.035 * math.cos(t), WW / 2 - 0.035 + 0.035 * math.sin(t)))
    prof = [(RI, WW / 2 - 0.01)] + prof[::-1] + [(RO - 0.035 + 0.035 * math.cos(-t), -(WW / 2 - 0.035) + 0.035 * math.sin(-t)) for t in [math.pi / 2 * k / 6 for k in range(7)]] + [(RI, -(WW / 2 - 0.01))]
    rings = [[wb.verts.new(P(r, w, 2 * math.pi * j / N)) for (r, w) in prof] for j in range(N)]
    m_ = len(prof)
    for j in range(N):
        a, b = rings[j], rings[(j + 1) % N]
        for k in range(m_):
            f = wb.faces.new((a[k], a[(k + 1) % m_], b[(k + 1) % m_], b[k])); f.material_index = 0
    # the dark disc behind the spokes, recessed
    c0 = wb.verts.new(P(0, 0.035, 0)); ring = [wb.verts.new(P(RI + 0.002, 0.035, 2 * math.pi * j / N)) for j in range(N)]
    for j in range(N):
        f = wb.faces.new((c0, ring[j], ring[(j + 1) % N]) if side > 0 else (c0, ring[(j + 1) % N], ring[j])); f.material_index = 2
    # the rim: an outer lip, a hub and five spokes, each a thin slab on the face
    def slab(poly, w0, w1):
        lo = [wb.verts.new(P(r, w0, a)) for r, a in poly]; hi = [wb.verts.new(P(r, w1, a)) for r, a in poly]
        n = len(poly)
        fs = [wb.faces.new(hi if side > 0 else hi[::-1]), wb.faces.new(lo[::-1] if side > 0 else lo)]
        for k in range(n):
            q = (lo[k], lo[(k + 1) % n], hi[(k + 1) % n], hi[k]); fs.append(wb.faces.new(q if side > 0 else q[::-1]))
        for f in fs: f.material_index = 1
    lip = 24
    for j in range(lip):                                 # the outer lip as a ring of blocks
        a0, a1 = 2 * math.pi * j / lip, 2 * math.pi * (j + 1) / lip
        slab([(RI - 0.030, a0), (RI + 0.004, a0), (RI + 0.004, a1), (RI - 0.030, a1)], 0.05, 0.095)
    for j in range(12):                                  # the hub: a disc of wedges out to 0.09
        a0, a1 = 2 * math.pi * j / 12, 2 * math.pi * (j + 1) / 12
        slab([(0.001, (a0 + a1) / 2), (0.074, a0), (0.074, a1)], 0.05, 0.102)
    cap = [wb.verts.new(P(0.036, 0.1035, 2 * math.pi * j / 16)) for j in range(16)]    # the centre cap's ring (an ink loop)
    for s_ in range(5):                                  # v3b: broad spokes (the shipped openings are narrow)
        a = 2 * math.pi * s_ / 5 + math.pi / 2
        hw0, hw1 = math.radians(20), math.radians(12)        # half widths at the hub and at the lip (openings ~ spokes)
        slab([(0.070, a - hw0), (RI - 0.028, a - hw1), (RI - 0.028, a + hw1), (0.070, a + hw0)], 0.05, 0.10)
    wme = bpy.data.meshes.new(name); wb.to_mesh(wme); wb.free()
    for m in (m_tyre, m_rim, m_in): wme.materials.append(m)
    o = bpy.data.objects.new(name, wme); bpy.context.scene.collection.objects.link(o); return o
for xw, yw, zw in WHEELS:
    side = 1 if xw > 7.99 else -1
    wheel('ev_wheel_%s_%s' % ('r' if side > 0 else 'l', 'f' if yw < 0 else 'b'), xw, yw, zw, side)
print('wheels: %d built' % len(WHEELS))
bpy.ops.wm.save_as_mainfile(filepath=out)
