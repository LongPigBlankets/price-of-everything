"""Construction equipment (g_071 construction_equipment_ice and g_072 construction_equipment_ev share this icon): a
backhoe loader and a standing hand-held breaker (jackhammer), the only two parts of the icon.

The backhoe loader stands along X, its loader to +X (lower right) and its backhoe to -X (upper left), with the
visible -Y flank showing its profile:
- a chassis on big rear wheels and smaller steered front wheels, with mudguards over both;
- a glazed cab on a deck between the rear guards, and the engine hood forward of it with the grille at the nose;
- loader arms from the cab's front pillars down the hood sides to a full-width bucket resting at the nose;
- at the rear, a swing post carrying a curved boom, the dipper hanging from its tip and the digging bucket curled
  under, each moved by its own ram;
- stabiliser legs splayed down to pads.

The breaker stands upright on its chisel in front, drawn with a thinner outline and no hose (owner). The icon is neutral
between the diesel and electric goods: there is no exhaust stack and no charge port.

Colours from the shipped art (construction yellow, slate darks, dark glazing). On the set's grid, camera, light, 12/4 px
ink and dots on the shaded sides.

Owner, 2026-10-17: "Next once done, I suggest iterating through construction equipment (choose 1 jackhammer standing +
1 backhoe) as the only parts of the icon"; one icon for both the ICE and EV goods; a backhoe loader."""
import bmesh
from mathutils import Vector, Matrix

CE_REVISION = 'construction_equipment_v7'
TONES = {'yellow': ((165, 135, 75), (215, 165, 85), (235, 185, 95)), 'dark': ((55, 65, 75), (65, 75, 85), (78, 88, 98)),
         'glass': ((40, 48, 64), (52, 60, 78), (70, 80, 98)), 'steel': ((112, 116, 120), (146, 150, 154), (184, 188, 192)),
         'hose': ((40, 42, 50), (54, 56, 64), (72, 74, 84)), 'tyre': ((44, 48, 56), (56, 60, 68), (70, 74, 84)),
         # v5 (owner: "a better colouring on the backhoe itself"): the digging bucket in worn dark steel, its edge bright
         'bucket': ((70, 74, 82), (92, 96, 104), (118, 122, 130)), 'bore': ((22, 28, 50), (26, 32, 56), (30, 36, 62))}
(L_CHASSIS, L_BODY, L_CAB, L_GLASS, L_TYRE, L_RIM, L_ARM, L_LBUCKET, L_BOOM, L_DIPPER, L_HBUCKET, L_RAM, L_LEG, L_BREAKER,
 L_HOSE) = range(1, 16)
REAR = dict(x=-0.75, r=0.68, w=0.46, y=1.02)          # rear axle, tyre radius, width, track half
FRONT = dict(x=1.45, r=0.50, w=0.38, y=1.00)
# v7 (owner: "move the jackhammer a bit to the right and add a yellow Dewalt style toolbox (about the same size as the
# jackhammer)"): the breaker moves toward the loader's nose; a yellow-and-black site toolbox stands where it was
BREAKER = dict(at=(1.30, -3.30), scale=1.85)
TOOLBOX = dict(at=(-0.55, -3.20), scale=1.30)
SIDESHIFT = -0.55                                     # the backhoe carriage slid toward the visible side


def ce_mesh(K, name, vs, fs, mat, label, smooth=False):
    me = bpy.data.meshes.new(name); me.from_pydata([tuple(v) for v in vs], [], fs); me.update()
    bm = bmesh.new(); bm.from_mesh(me); bmesh.ops.recalc_face_normals(bm, faces=bm.faces); bm.to_mesh(me); bm.free()
    ob = K.obj(name, me, mat, smooth)
    for f in me.polygons:
        f.use_smooth = smooth
    noink(ob); ob['part_label'] = label
    return ob


def ce_box(K, name, x0, x1, y0, y1, z0, z1, mat, label, r=0.0):
    if r:
        ob = rounded_box(K, name, ((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2), (x1 - x0, y1 - y0, z1 - z0), mat, label, r)
        return ob
    bm = bmesh.new(); bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co = Vector((x0 if v.co.x < 0 else x1, y0 if v.co.y < 0 else y1, z0 if v.co.z < 0 else z1))
    me = bpy.data.meshes.new(name); bm.to_mesh(me); bm.free()
    ob = K.obj(name, me, mat, False); noink(ob); ob['part_label'] = label
    return ob


def ce_prism_y(K, name, profile, y0, y1, mat, label):
    """A closed (x, z) profile extruded along Y."""
    n = len(profile); vs = [(x, y0, z) for x, z in profile] + [(x, y1, z) for x, z in profile]
    fs = [tuple(reversed(range(n))), tuple(range(n, 2 * n))] + [(k, (k + 1) % n, n + (k + 1) % n, n + k) for k in range(n)]
    return ce_mesh(K, name, vs, fs, mat, label)


def ce_prism_z(K, name, profile, z0, z1, mat, label):
    """A closed (x, y) plan extruded up Z."""
    n = len(profile); vs = [(x, y, z0) for x, y in profile] + [(x, y, z1) for x, y in profile]
    fs = [tuple(reversed(range(n))), tuple(range(n, 2 * n))] + [(k, (k + 1) % n, n + (k + 1) % n, n + k) for k in range(n)]
    return ce_mesh(K, name, vs, fs, mat, label)


def ce_cyl(K, name, p0, p1, r, mat, label, seg=48, smooth=True):
    ob = K.dircyl(name, tuple(p0), tuple(p1), r, mat, segments=seg, smooth=smooth); noink(ob); ob['part_label'] = label
    return ob


def ce_arc_shell(K, name, cx, cz, r0, r1, y0, y1, a0, a1, mat, label, n=24):
    """A curved guard: the band between radii r0 and r1 about an axis along Y, from angle a0 to a1 (degrees, 0 = +X,
    90 = up)."""
    pts = []
    for k in range(n + 1):
        a = math.radians(a0 + (a1 - a0) * k / n); pts.append((cx + r1 * math.cos(a), cz + r1 * math.sin(a)))
    for k in range(n, -1, -1):
        a = math.radians(a0 + (a1 - a0) * k / n); pts.append((cx + r0 * math.cos(a), cz + r0 * math.sin(a)))
    return ce_prism_y(K, name, pts, y0, y1, mat, label)


def ce_beam(K, name, path, w, h, mat, label):
    """A box-section member along a path in the XZ plane (y = 0): w across (Y), h deep, swept with parallel frames."""
    pts = pl_catmull([Vector(p) for p in path], 8)
    prof = [(-w / 2, -h / 2), (w / 2, -h / 2), (w / 2, h / 2), (-w / 2, h / 2)]
    t0 = (pts[1] - pts[0]).normalized(); n0 = Vector((0, 1, 0)).cross(t0).normalized()
    ob, rings, F = pl_sweep(K, name, pts, prof, tuple(n0), mat, label)
    noink(ob)
    return ob


def ce_ram(K, name, p0, p1, mats, label, r=0.07):
    """A hydraulic ram: a dark barrel over the first 55% and a bright rod the rest of the way."""
    a, b = Vector(p0), Vector(p1); m = a.lerp(b, 0.55)
    return [ce_cyl(K, name + '_barrel', a, m + (b - a).normalized() * 0.02, r, mats['dark'], label).name,
            ce_cyl(K, name + '_rod', m, b, r * 0.6, mats['steel'], label).name]


def ce_wheel(K, name, x, y, z, r, w, mats, side, lugs=18):
    """A tyre with its tread lugs (alternating blocks, half the width each, angled like a tractor tread) and a
    sidewall ring, and on its outer face a yellow wheel: a dished disc, a raised centre, a bolt circle and vent holes.
    v5 (owner: "more detailed wheels (tyre indents, inner detail on the wheel hubcaps)")."""
    out = []
    t = ce_cyl(K, name + '_tyre', (x, y - w / 2, z), (x, y + w / 2, z), r - 0.06, mats['tyre'], L_TYRE, seg=64); out.append(t.name)
    for k in range(lugs):
        a = 360.0 * k / lugs; ar = math.radians(a); off = (0.25 if k % 2 else -0.25) * w
        cx_, cz_ = x + (r - 0.06) * math.cos(ar), z + (r - 0.06) * math.sin(ar)
        lug = K.rotbox('%s_lug%02d' % (name, k), cx_, y + off, cz_, 2 * math.pi * r / lugs * 0.55, w * 0.50, 0.13, mats['tyre'], 'Y', 90.0 - a)
        noink(lug); lug['part_label'] = L_TYRE; out.append(lug.name)
    face = y + side * w / 2
    ring = noink(K.washer(name + '_sidewall', (x, face, z), (0, side, 0), r * 0.70, r * 0.78, 0.024, mats['tyre'], seg=64))
    ring['part_label'] = L_TYRE; out.append(ring.name)
    rim = ce_cyl(K, name + '_rim', (x, face - side * 0.06, z), (x, face + side * 0.012, z), r * 0.62, mats['yellow'], L_RIM, seg=64); out.append(rim.name)
    dish = noink(K.washer(name + '_dish', (x, face + side * 0.012, z), (0, side, 0), r * 0.40, r * 0.46, 0.02, mats['dark'], seg=48))
    dish['part_label'] = L_RIM; out.append(dish.name)
    hub = ce_cyl(K, name + '_hub', (x, face, z), (x, face + side * 0.06, z), r * 0.22, mats['yellow'], L_RIM, seg=48); out.append(hub.name)
    cap = ce_cyl(K, name + '_cap', (x, face + side * 0.05, z), (x, face + side * 0.075, z), r * 0.10, mats['dark'], L_RIM, seg=32); out.append(cap.name)
    for k in range(6):                           # wheel nuts round the hub, vent holes in the disc between them
        a = math.radians(60 * k + 30); bx_, bz_ = x + r * 0.16 * math.cos(a), z + r * 0.16 * math.sin(a)
        n = bolt_dot(K, '%s_nut%d' % (name, k), (bx_, face + side * 0.062, bz_), 'Y', r * 0.028, mats['bore']); n['part_label'] = L_RIM
        a2 = math.radians(60 * k); hx, hz = x + r * 0.31 * math.cos(a2), z + r * 0.31 * math.sin(a2)
        h = bolt_dot(K, '%s_vent%d' % (name, k), (hx, face + side * 0.013, hz), 'Y', r * 0.055, mats['bore']); h['part_label'] = L_RIM
    return out


def build_construction_equipment():
    setup_icon_rig(); K = Kit(open_collection('ICON_construction_equipment')); hosts = []
    mats = {k: pl_toon('ce_' + k, *v) for k, v in TONES.items()}
    R, F = REAR, FRONT
    # chassis rails and the rear deck the backhoe hangs from
    hosts.append(ce_box(K, 'chassis', -1.80, 1.95, -0.50, 0.50, 0.45, 0.92, mats['dark'], L_CHASSIS).name)
    hosts.append(ce_box(K, 'rear_deck', -1.80, -1.12, -0.95, 0.95, 0.80, 1.32, mats['yellow'], L_BODY, 0.04).name)
    # engine hood, sloping down to the nose, and its grille
    hood = ce_prism_y(K, 'hood', [(0.20, 0.90), (2.05, 0.90), (2.05, 1.42), (1.92, 1.56), (0.20, 1.80)], -0.62, 0.62, mats['yellow'], L_BODY)
    hosts.append(hood.name)
    hosts.append(ce_box(K, 'grille', 2.04, 2.08, -0.44, 0.44, 1.02, 1.36, mats['glass'], L_GLASS).name)
    # the cab: a glazed box on the deck between the rear guards, four corner pillars, a roof with an overhang
    cz0, cz1 = 1.08, 2.82; cx0, cx1, cy = -1.22, 0.22, 0.76
    hosts.append(ce_box(K, 'cab_floor', cx0 - 0.04, cx1 + 0.04, -cy - 0.04, cy + 0.04, 0.92, cz0 + 0.06, mats['yellow'], L_BODY).name)
    # v5 (owner: "the cab of the vehicle needs to have angles like a half octagon towards the front (use the old icon for
    # reference)"): in plan the cab's front corners are cut back, a pillar at every angle, the sill and roof following
    ch = 0.34
    def plan(grow):
        return [(cx0 - grow, -cy - grow), (cx1 - ch + grow * 0.41, -cy - grow), (cx1 + grow, -cy + ch - grow * 0.41),
                (cx1 + grow, cy - ch + grow * 0.41), (cx1 - ch + grow * 0.41, cy + grow), (cx0 - grow, cy + grow)]
    hosts.append(ce_prism_z(K, 'cab_glass', plan(-0.03), cz0, cz1, mats['glass'], L_GLASS).name)
    for k, (x, y) in enumerate(plan(0.0)):
        hosts.append(ce_box(K, 'cab_pillar_%d' % k, x - 0.06, x + 0.06, y - 0.06, y + 0.06, cz0, cz1, mats['yellow'], L_CAB).name)
    hosts.append(ce_prism_z(K, 'cab_sill', plan(0.02), cz0, cz0 + 0.30, mats['yellow'], L_CAB).name)
    hosts.append(ce_prism_z(K, 'cab_roof', plan(0.11), cz1 - 0.02, cz1 + 0.13, mats['yellow'], L_CAB).name)
    # wheels and guards
    for s in (-1, 1):
        hosts += ce_wheel(K, 'rear_%+d' % s, R['x'], s * R['y'], R['r'], R['r'], R['w'], mats, s)
        hosts += ce_wheel(K, 'front_%+d' % s, F['x'], s * F['y'], F['r'], F['r'], F['w'], mats, s)
        y0, y1 = sorted((s * (R['y'] - R['w'] / 2 - 0.02), s * (R['y'] + R['w'] / 2 + 0.03)))
        hosts.append(ce_arc_shell(K, 'rear_guard_%+d' % s, R['x'], R['r'], R['r'] + 0.06, R['r'] + 0.16, y0, y1, 0, 180, mats['yellow'], L_BODY).name)
        y0, y1 = sorted((s * (F['y'] - F['w'] / 2 - 0.02), s * (F['y'] + F['w'] / 2 + 0.03)))
        hosts.append(ce_arc_shell(K, 'front_guard_%+d' % s, F['x'], F['r'], F['r'] + 0.05, F['r'] + 0.15, y0, y1, 20, 160, mats['yellow'], L_BODY).name)
    # the loader (review of v3): a tower each side at the cab front carries the arm's pivot and the lift ram's foot; the
    # arm runs down past the hood to a pin on the bucket's back; the ram lies inboard of the arm
    for s_ in (-1, 1):
        y0, y1 = sorted((s_ * 0.58, s_ * 0.82))
        hosts.append(ce_box(K, 'loader_tower_%+d' % s_, 0.30, 0.55, y0, y1, 0.90, 2.05, mats['yellow'], L_BODY).name)
        arm = ce_beam(K, 'loader_arm_%+d' % s_, [(0.42, 0, 1.95), (1.30, 0, 1.76), (2.10, 0, 1.15), (2.36, 0, 0.72)], 0.12, 0.22, mats['yellow'], L_ARM)
        arm.data.transform(Matrix.Translation((0, s_ * 0.76, 0))); arm.data.update(); hosts.append(arm.name)
        hosts += ce_ram(K, 'loader_ram_%+d' % s_, (0.50, s_ * 0.62, 1.00), (1.40, s_ * 0.62, 1.66), mats, L_RAM, 0.06)
        for nm, (x, z) in (('pivot', (0.42, 1.95)), ('bucket', (2.36, 0.72))):
            hosts.append(ce_cyl(K, 'loader_pin_%s_%+d' % (nm, s_), (x, s_ * 0.66, z), (x, s_ * 0.88, z), 0.06, mats['dark'], L_RAM, seg=32).name)
    bucket = [(2.42, 1.02), (2.32, 0.34), (2.46, 0.10), (3.16, 0.07), (3.16, 0.15), (2.62, 0.25), (2.55, 0.98)]
    hosts.append(ce_prism_y(K, 'loader_bucket', bucket, -1.16, 1.16, mats['yellow'], L_LBUCKET).name)
    for s_ in (-1, 1):
        cheek = [(2.42, 1.02), (2.32, 0.34), (2.46, 0.10), (3.16, 0.07), (2.92, 0.62)]
        y0, y1 = sorted((s_ * 1.16, s_ * 1.21))
        hosts.append(ce_prism_y(K, 'loader_bucket_side_%+d' % s_, cheek, y0, y1, mats['yellow'], L_LBUCKET).name)
    # the backhoe (review of v3): a 3CX pose (a 2.3 m boom over a 1.9 m dipper, the dipper's lever above the knuckle)
    # on a sideshift carriage slid toward the visible side, so the kingpost and the rams show; each ram stands off its
    # member on lugs; a D-shaped bucket on a link
    hosts.append(ce_box(K, 'carriage_rail', -1.92, -1.80, -1.00, 1.00, 1.00, 1.45, mats['dark'], L_CHASSIS).name)
    arm_parts = []
    arm_parts.append(ce_box(K, 'swing_post', -2.12, -1.72, -0.28, 0.28, 0.70, 1.62, mats['yellow'], L_BODY, 0.03))
    arm_parts.append(ce_beam(K, 'boom', [(-1.95, 0, 1.30), (-2.05, 0, 2.40), (-2.30, 0, 3.20), (-2.45, 0, 3.55)], 0.30, 0.44, mats['yellow'], L_BOOM))
    arm_parts.append(ce_beam(K, 'dipper', [(-2.75, 0, 3.95), (-2.45, 0, 3.55), (-2.62, 0, 2.60), (-2.85, 0, 1.70)], 0.24, 0.30, mats['yellow'], L_DIPPER))
    c = (-3.00, 1.30); rb = 0.40; hb = []
    for k in range(17):
        a = math.radians(70 + 220 * k / 16); hb.append((c[0] + rb * math.cos(a), c[1] + rb * math.sin(a)))
    hb += [(-2.62, 0.98), (-2.72, 1.42)]
    arm_parts.append(ce_prism_y(K, 'digging_bucket', hb, -0.36, 0.36, mats['bucket'], L_HBUCKET))
    arm_parts.append(ce_box(K, 'digging_bucket_edge', -2.72, -2.58, -0.37, 0.37, 0.93, 1.03, mats['steel'], L_HBUCKET))
    names = []
    for nm, a_, b_, r_ in (('boom_ram', (-1.60, 0, 0.98), (-1.75, 0, 2.55), 0.08), ('dipper_ram', (-2.40, 0, 2.25), (-2.74, 0, 3.92), 0.07),
                           ('bucket_ram', (-2.52, 0, 3.72), (-3.08, 0, 1.88), 0.06)):
        names += ce_ram(K, nm, a_, b_, mats, L_RAM, r_)
    arm_parts += [bpy.data.objects[n] for n in names]
    arm_parts.append(noink(K.dirbox('bucket_link', (-3.08, 0, 1.88), (-3.20, 0, 1.64), 0.10, 0.08, mats['dark']))); arm_parts[-1]['part_label'] = L_RAM
    for nm, (x, z), w, r_ in (('pin_boom_foot', (-1.95, 1.30), 0.24, 0.09), ('pin_knuckle', (-2.45, 3.55), 0.20, 0.10),
                              ('pin_bucket', (-2.85, 1.70), 0.40, 0.07), ('lug_boom_ram', (-1.75, 2.55), 0.20, 0.06),
                              ('lug_dipper_ram', (-2.40, 2.25), 0.20, 0.06)):
        arm_parts.append(ce_cyl(K, nm, (x, -w, z), (x, w, z), r_, mats['dark'], L_RAM, seg=32))
    for nm, a_, b_ in (('lug_boom_ram_plate', (-1.80, 0, 2.50), (-2.02, 0, 2.47)), ('lug_dipper_plate', (-2.40, 0, 2.25), (-2.10, 0, 2.30))):
        o = noink(K.dirbox(nm, a_, b_, 0.14, 0.10, mats['yellow'])); o['part_label'] = L_BOOM; arm_parts.append(o)
    for o in arm_parts:
        o.data.transform(Matrix.Translation((0, SIDESHIFT, 0))); o.data.update(); hosts.append(o.name)
    # stabilisers: box-section legs rooted in towers at the rear corners, splayed down to pads
    for s_ in (-1, 1):
        y0, y1 = sorted((s_ * 0.85, s_ * 1.10))
        hosts.append(ce_box(K, 'stabiliser_tower_%+d' % s_, -2.00, -1.75, y0, y1, 0.85, 1.55, mats['yellow'], L_BODY).name)
        leg = noink(K.dirbox('stabiliser_%+d' % s_, (-1.88, s_ * 0.98, 1.20), (-1.98, s_ * 1.42, 0.10), 0.20, 0.22, mats['yellow'])); leg['part_label'] = L_LEG
        hosts.append(leg.name)
        hosts.append(ce_box(K, 'stabiliser_pad_%+d' % s_, -2.18, -1.78, s_ * 1.42 - 0.20, s_ * 1.42 + 0.20, 0.0, 0.07, mats['dark'], L_LEG).name)
    # the breaker, standing on its chisel in front of the loader, clear of the wheels
    bx, by = BREAKER['at']; sc = BREAKER['scale']
    parts = []
    parts.append(ce_cyl(K, 'breaker_chisel', (0, 0, 0.0), (0, 0, 0.28), 0.045, mats['steel'], L_BREAKER, seg=24))
    parts.append(ce_cyl(K, 'breaker_collar', (0, 0, 0.26), (0, 0, 0.36), 0.075, mats['dark'], L_BREAKER, seg=32))
    parts.append(ce_cyl(K, 'breaker_body', (0, 0, 0.35), (0, 0, 0.80), 0.11, mats['yellow'], L_BREAKER, seg=48))
    parts.append(ce_cyl(K, 'breaker_band', (0, 0, 0.56), (0, 0, 0.62), 0.118, mats['dark'], L_BREAKER, seg=48))
    parts.append(ce_cyl(K, 'breaker_head', (0, 0, 0.79), (0, 0, 0.92), 0.09, mats['dark'], L_BREAKER, seg=32))
    parts.append(ce_cyl(K, 'breaker_post', (0, 0, 0.90), (0, 0, 1.00), 0.03, mats['steel'], L_BREAKER, seg=16))
    parts.append(ce_cyl(K, 'breaker_bar', (-0.32, 0, 0.99), (0.32, 0, 0.99), 0.026, mats['steel'], L_BREAKER, seg=16))
    for s_ in (-1, 1):
        parts.append(ce_cyl(K, 'breaker_grip_%+d' % s_, (s_ * 0.18, 0, 0.99), (s_ * 0.34, 0, 0.99), 0.045, mats['hose'], L_BREAKER, seg=24))
    place = Matrix.Translation((bx, by, 0)) @ Matrix.Scale(sc, 4)
    for ob in parts:
        ob.data.transform(place); ob.data.update(); hosts.append(ob.name)
    # the toolbox: a yellow body on a black base, a black lid rim under a yellow lid, two black latches on the front, a
    # black carry handle on posts; no maker's marks
    tb = []
    tb.append(ce_box(K, 'toolbox_base', -0.48, 0.48, -0.28, 0.28, 0.0, 0.07, mats['dark'], L_HOSE))
    tb.append(ce_box(K, 'toolbox_body', -0.50, 0.50, -0.30, 0.30, 0.05, 0.60, mats['yellow'], L_BREAKER, 0.04))
    tb.append(ce_box(K, 'toolbox_lid_rim', -0.52, 0.52, -0.32, 0.32, 0.58, 0.68, mats['dark'], L_HOSE, 0.03))
    tb.append(ce_box(K, 'toolbox_lid', -0.48, 0.48, -0.28, 0.28, 0.66, 0.76, mats['yellow'], L_BREAKER, 0.03))
    for k, x in enumerate((-0.28, 0.28)):
        tb.append(ce_box(K, 'toolbox_latch_%d' % k, x - 0.07, x + 0.07, -0.345, -0.28, 0.44, 0.66, mats['dark'], L_HOSE, 0.015))
    for k, x in enumerate((-0.30, 0.30)):
        tb.append(ce_box(K, 'toolbox_handle_post_%d' % k, x - 0.04, x + 0.04, -0.05, 0.05, 0.74, 0.92, mats['dark'], L_HOSE))
    tb.append(ce_box(K, 'toolbox_handle', -0.34, 0.34, -0.06, 0.06, 0.88, 0.95, mats['dark'], L_HOSE, 0.02))
    tplace = Matrix.Translation((TOOLBOX['at'][0], TOOLBOX['at'][1], 0)) @ Matrix.Scale(TOOLBOX['scale'], 4)
    for ob in tb:
        ob.data.transform(tplace); ob.data.update(); hosts.append(ob.name)
    bpy.context.view_layer.update()
    for n in hosts:
        # the breaker's small rounds left short stubs as ticks along the grips; it keeps only longer lines
        pl_mesh_lines(K, bpy.data.objects[n], bpy.data.objects[n]['part_label'], 40.0, n, 0.09 if n.startswith(('breaker', 'toolbox')) else 0.03)
    for ob in K.col.objects:
        if ob.get('ink_width') == 6:
            ob['ink_width'] = PL_INNER
    info = contract(K, ['chassis', 'hood', 'boom'], 'a backhoe loader (cab, hood, loader arms and bucket, rear boom, dipper and '
                    'bucket, rams, stabilisers, wheels and guards) and a hand-held hydraulic breaker standing on its chisel, its '
                    'no hose', inner=PL_INNER)
    info['revision'] = CE_REVISION; info['outline']['component_boundaries'] = True; info['outline']['id_step'] = 17
    # owner on v4: "the jackhammer needs thinner outlines and no cable"
    info['outline']['outer_by_label'] = {str(L_BREAKER): 6, str(L_HOSE): 6}
    info['outline']['component_weight_by_label'] = {str(L_BREAKER): 3, str(L_HOSE): 3}
    info['stipple']['strength'] = 0.38
    info['stipple']['groups'] = [{'name': 'shaded_faces', 'labels': list(range(1, 16)), 'thresholds': [0.575, 0.50, 0.30]}]
    return info
