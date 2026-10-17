"""Engine (g_046 engine): the shipped art's V8 long block, crank axis along Y with the timing end to the camera (-Y).

Built as a real 90 degree V8 in cross-section: each bank's cylinder axis runs through the crank at 45 degrees (the
shipped art's cam-cover angle), the deck square to it, the head on the deck and the cam cover on the head. The lower
intake fills the valley between the heads; the plenum sits on it with the throttle body facing forward and arched
runners down to the heads' intake ports. Each exhaust manifold bolts to its head's outer face, four primaries into a
log with the downpipe leaving at the rear. On the front: the timing cover framed in red, the crank pulley on the crank
axis, the water pump casting and pulley above it, the alternator on a pivot bracket with a slotted adjusting strap, and
one belt round all three. A thermostat housing with its hose neck on the intake's nose, an engine mount with its
isolator and the oil filter on the +X side, the pan with a deeper rear sump, the bellhousing flange at the back.

Colours from the shipped art (red covers, taupe castings, grey intake, warm dark pulleys). On the set's grid, camera,
light, 12/4 px ink and dots on the shaded sides. Dimensions in block-length units: the block runs Y -0.74..0.74.

Owner, 2026-10-17, on v7: "keep refining but needs at least one engineering pass + if possible the same angle of the
cams as the old one" (v8)."""
EN_REVISION = 'engine_v12'
# v1-v7: proportions, tones and the red-framed timing end against the shipped art (stylised banks at 20 degrees).
# v8 (owner): the true V8 geometry above; every part placed where it bolts on.
# v9: runners leave the plenum's flanks below its crown and drop to the ports (they arched over it); the downpipe drops
# straight to a flange inside the silhouette instead of hooking out behind.
# v10: the lower intake up to the heads' tops and the plenum lower, so the runners are short humps as shipped.
# v11 (engineering review of v10): smaller crank and pump pulleys so the belt's spans open, the pump on a taller red
# timing frame, no web; the alternator clear of the head with a slotted strap and pivot bracket facing the camera;
# cast-iron exhaust primaries dropping from the heads to a log on the visible side; cam covers chamfered on every top
# edge so their lit strip shows at 45 degrees; mount puck under the log, the filter tilted down in steel, the
# thermostat neck clear of the throttle with the pump's inlet spigot; the filler cap upright; no bellhousing flange.
# v12 (owner: "make the red caps more rounded (like rounded corner rectangles similar to the older model) and also the
# outer outline should be consistent with some of the more recent icons like the CPU and high grade silicon"): cam covers
# as rounded rectangles with filleted tops on a rounded flange, the raised panel its own part so a line rings it; a cleaner
# silhouette (no stepped cover corners, the exhaust outlet turned down under the block, the iron a shade lighter so it
# doesn't merge with the outline)
TILT = 45.0                                       # bank axis from vertical: the shipped art's cam covers and a real 90 degree V
CRANK_Z = 0.62                                    # crank axis height; the banks turn about it
BLOCK = dict(y=0.74, x=0.36, rail_z=0.46, deck=0.55, deck_half=0.21)     # crankcase half width; deck distance along the bank
PAN = dict(x=0.32, front_z=0.18, sump_y=0.05, rail_x=0.44, rail_y=0.78, rail_t=0.06)
HEAD = dict(w=(0.55, 0.78), half=0.21, y=0.70)    # along the bank axis from the crank; half width across it
STAGGER = 0.04                                    # the -X bank sits forward of the +X bank by twice this
COVER = dict(w=(0.77, 0.81, 0.96), half=0.20, inset=0.025, y=0.68, corner=0.07, fillet=0.05, panel_in=0.075, panel_h=0.035, panel_corner=0.05)
LOWER = dict(top=1.30, y=(-0.64, 0.66))           # lower intake
INTAKE = dict(r=0.18, z=1.53, y=(-0.48, 0.48), runner_y=(-0.42, -0.14, 0.14, 0.42), runner_r=0.072, port_x=0.30)
THROTTLE = dict(x=-0.02, z=1.50, r=0.14, y=(-0.76, -0.44), bore=0.10)
THERMO = dict(x=-0.14, z=1.20, r=0.07, neck_r=0.055, neck=(-0.6, -0.4, 0.7), y=-0.64)
EXHAUST = dict(w=0.665, out=0.08, port_r=0.05, log_x=0.66, log_z=CRANK_Z + 0.12, log_r=0.07, y=(-0.55, 0.60))
TIMING = dict(t=0.05, rim=0.045, proud=0.03, profile=((0.34, 0.50), (0.34, 0.76), (0.20, 1.18), (-0.20, 1.18), (-0.34, 0.76), (-0.34, 0.50)))
CRANK = dict(x=0.0, z=CRANK_Z, r=0.16, groove=0.115, hub=0.07, depth=0.12)
PUMP = dict(x=0.0, z=1.06, r=0.11, hub=0.045, body=0.09, depth=0.08)
ALT = dict(x=0.40, z=1.04, r=0.11, pulley=0.065, y=(-0.80, -0.68))
CAP = dict(u=0.06, y=-0.38, r=0.07)
TONES = {'block': ((126, 114, 102), (162, 150, 138), (204, 200, 176)), 'head': ((130, 118, 106), (168, 156, 144), (208, 204, 180)),
         'red': ((150, 68, 58), (190, 88, 72), (216, 124, 100)), 'intake': ((104, 96, 86), (130, 122, 112), (160, 152, 140)),
         'dark': ((66, 60, 52), (84, 78, 68), (104, 96, 86)), 'belt': ((154, 138, 104), (186, 168, 128), (206, 190, 148)),
         'iron': ((62, 66, 76), (80, 84, 94), (102, 106, 116)),
         'steel': ((112, 116, 120), (146, 150, 154), (184, 188, 192)), 'bore': ((22, 28, 50), (26, 32, 56), (30, 36, 62))}

L_BLOCK, L_PAN, L_HEAD, L_COVER, L_INTAKE, L_RUNNER, L_THROTTLE, L_EXHAUST, L_TIMING, L_PANEL, L_PULLEY, L_BELT, L_FIT, L_ALT, L_PLATEAU = range(1, 16)


def en_box(K, name, x0, x1, y0, y1, z0, z1, mat, label):
    bm = bmesh.new(); bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co = Vector((x0 if v.co.x < 0 else x1, y0 if v.co.y < 0 else y1, z0 if v.co.z < 0 else z1))
    me = bpy.data.meshes.new(name); bm.to_mesh(me); bm.free()
    o = K.obj(name, me, mat, False); noink(o); o['part_label'] = label
    return o


def en_rbox(K, name, x0, x1, y0, y1, z0, z1, mat, label, r):
    return rounded_box(K, name, ((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2), (x1 - x0, y1 - y0, z1 - z0), mat, label, r)


def en_prism(K, name, profile, axis, a0, a1, mat, label):
    """A closed 2D profile extruded along a world axis: 'Y' takes (x, z) points, 'X' takes (y, z) points."""
    def at(p, a):
        return (p[0], a, p[1]) if axis == 'Y' else (a, p[0], p[1])
    n = len(profile); vs = [at(p, a0) for p in profile] + [at(p, a1) for p in profile]
    fs = [tuple(reversed(range(n))), tuple(range(n, 2 * n))] + [(k, (k + 1) % n, n + (k + 1) % n, n + k) for k in range(n)]
    ob = mesh(K, name, vs, fs, mat); ob['part_label'] = label
    return ob


def en_cyl_y(K, name, x, z, r, y0, y1, mat, label, seg=64):
    ob = K.cyl(name, x, (y0 + y1) / 2, z, r, y1 - y0, mat, axis='Y', segments=seg, smooth=True); noink(ob); ob['part_label'] = label
    return ob


def en_hull(circles, n=144):
    """Support-function hull of circles (cx, cz, r) in the XZ plane, one point per direction, so two hulls built from
    the same circles with different radii correspond point for point."""
    pts = []
    for k in range(n):
        a = 2 * math.pi * k / n; u = (math.cos(a), math.sin(a))
        cx, cz, r = max(circles, key=lambda c: c[0] * u[0] + c[1] * u[1] + c[2])
        pts.append((cx + r * u[0], cz + r * u[1]))
    return pts


def en_belt(K, name, circles, t, y0, y1, mat, label):
    """A flat belt round the pulleys: the ring between the hull of their rims and the hull t further out."""
    return en_ring(K, name, en_hull([(cx, cz, r + t) for cx, cz, r in circles]), en_hull(circles), y0, y1, mat, label)


def en_ring(K, name, outer, inner, y0, y1, mat, label):
    """The band between two closed XZ outlines with matching points, from y0 to y1."""
    n = len(inner)
    vs = [(x, y0, z) for x, z in outer] + [(x, y0, z) for x, z in inner] + [(x, y1, z) for x, z in outer] + [(x, y1, z) for x, z in inner]
    fs = []
    for k in range(n):
        j = (k + 1) % n
        fs += [(k, j, n + j, n + k), (2 * n + k, 3 * n + k, 3 * n + j, 2 * n + j),      # front and back faces
               (k, 2 * n + k, 2 * n + j, j), (n + k, n + j, 3 * n + j, 3 * n + k)]       # outer and inner bands
    ob = mesh(K, name, vs, fs, mat); ob['part_label'] = label
    return ob


def en_inset(profile, d):
    """Shrink a convex CCW polygon by d (each edge moved in, neighbouring lines intersected)."""
    n = len(profile); lines = []
    for k in range(n):
        p, q = Vector(profile[k]), Vector(profile[(k + 1) % n]); e = (q - p).normalized(); nrm = Vector((-e.y, e.x))
        lines.append((p + nrm * d, e))
    out = []
    for k in range(n):
        (p1, e1), (p2, e2) = lines[k - 1], lines[k]
        den = e1.x * e2.y - e1.y * e2.x; t = ((p2.x - p1.x) * e2.y - (p2.y - p1.y) * e2.x) / den
        out.append(tuple(p1 + e1 * t))
    return out


def en_bank(s, u, w):
    """World (x, z) of a point of bank s (+1 = +X, -1 = -X): u across the bank (outward positive), w out along its
    cylinder axis from the crank."""
    t = math.radians(TILT)
    return (s * (u * math.cos(t) + w * math.sin(t)), CRANK_Z - u * math.sin(t) + w * math.cos(t))


def en_tilt(ob, s):
    """Turn a part built upright (x = s*u, z = CRANK_Z + w) onto bank s: a rotation about the crank axis."""
    M = Matrix.Translation((0, 0, CRANK_Z)) @ Matrix.Rotation(math.radians(TILT * s), 4, 'Y') @ Matrix.Translation((0, 0, -CRANK_Z))
    ob.data.transform(M); ob.data.update()
    return ob


def en_bank_box(K, name, s, u0, u1, y0, y1, w0, w1, mat, label):
    x0, x1 = sorted((s * u0, s * u1))
    return en_tilt(en_box(K, name, x0, x1, y0, y1, CRANK_Z + w0, CRANK_Z + w1, mat, label), s)


def en_strip(K, name, p0, p1, w, y0, y1, mat, label):
    """A flat bar in the XZ plane from p0 to p1 (x, z), w wide, from y0 to y1."""
    a, b = Vector(p0), Vector(p1); d = (b - a).normalized(); n = Vector((-d.y, d.x)) * (w / 2)
    return en_prism(K, name, [tuple(a - n), tuple(b - n), tuple(b + n), tuple(a + n)], 'Y', y0, y1, mat, label)


def en_hipped(K, name, x0, x1, y0, y1, z0, z1, c, mat, label):
    """A box whose four top edges are chamfered by c."""
    vs = [(x0, y0, z0), (x1, y0, z0), (x1, y1, z0), (x0, y1, z0), (x0, y0, z1 - c), (x1, y0, z1 - c), (x1, y1, z1 - c), (x0, y1, z1 - c),
          (x0 + c, y0 + c, z1), (x1 - c, y0 + c, z1), (x1 - c, y1 - c, z1), (x0 + c, y1 - c, z1)]
    fs = [(3, 2, 1, 0), (8, 9, 10, 11)] + [(k, (k + 1) % 4, 4 + (k + 1) % 4, 4 + k) for k in range(4)] + \
         [(4 + k, 4 + (k + 1) % 4, 8 + (k + 1) % 4, 8 + k) for k in range(4)]
    ob = mesh(K, name, vs, fs, mat); ob['part_label'] = label
    return ob


def en_rrect(hx, hy, r, n=8):
    """A rounded rectangle about the origin (half sizes hx, hy, corner radius r) as a CCW ring of points."""
    pts = []
    for cx, cy, a0 in ((hx - r, hy - r, 0), (-hx + r, hy - r, 90), (-hx + r, -hy + r, 180), (hx - r, -hy + r, 270)):
        for k in range(n + 1):
            a = math.radians(a0 + 90 * k / n); pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return pts


def en_rslab(K, name, cx, cy, hx, hy, z0, z1, rc, rt, mat, label, steps=5):
    """A rounded-rectangle slab (corner radius rc in plan) whose top edge is filleted by rt: rings of the outline lofted
    up the side and in over the fillet, smooth shaded so the toon steps follow the curve."""
    levels = [(z0, 0.0), (z1 - rt, 0.0)] + [(z1 - rt + rt * math.sin(math.radians(90 * k / steps)), rt * (1 - math.cos(math.radians(90 * k / steps))))
                                            for k in range(1, steps + 1)]
    rings = [[(cx + x, cy + y, z) for x, y in en_rrect(hx - d, hy - d, max(rc - d, 0.01))] for z, d in levels]
    m = len(rings[0]); vs = [v for ring in rings for v in ring]
    fs = [tuple(reversed(range(m))), tuple(range((len(rings) - 1) * m, len(rings) * m))]
    for i in range(len(rings) - 1):
        fs += [(i * m + k, i * m + (k + 1) % m, (i + 1) * m + (k + 1) % m, (i + 1) * m + k) for k in range(m)]
    ob = mesh(K, name, vs, fs, mat, smooth=True); ob['part_label'] = label
    return ob


def en_label(ob, label):
    noink(ob); ob['part_label'] = label
    return ob


def build_engine():
    setup_icon_rig(); K = Kit(open_collection('ICON_engine')); hosts = []
    mats = {k: pl_toon('en_' + k, *v) for k, v in TONES.items()}
    B, P, H, C, I, T, EX = BLOCK, PAN, HEAD, COVER, INTAKE, THROTTLE, EXHAUST
    sin_t, cos_t = math.sin(math.radians(TILT)), math.cos(math.radians(TILT))
    # the block in section: crankcase sides, each bank's outer wall up to its deck, the deck square to the bank axis,
    # the inner walls meeting in the valley
    O, I_ = en_bank(1, B['deck_half'], B['deck']), en_bank(1, -B['deck_half'], B['deck'])
    side_z = O[1] - (O[0] - B['x']) / sin_t * cos_t; valley_z = I_[1] - I_[0] / sin_t * cos_t
    right = [(B['x'], B['rail_z']), (B['x'], side_z), O, I_]
    prof = right + [(0.0, valley_z)] + [(-x, z) for x, z in reversed(right)]
    block = en_prism(K, 'block', prof, 'Y', -B['y'], B['y'], mats['block'], L_BLOCK); hosts.append(block.name)
    # the pan under a bolted rail: shallow at the front, the sump deeper behind
    rz0 = B['rail_z'] - P['rail_t']
    pan = en_prism(K, 'pan', [(-B['y'] + 0.02, rz0 + 0.01), (-B['y'] + 0.02, P['front_z']), (P['sump_y'] - 0.10, P['front_z']),
                              (P['sump_y'], 0.0), (B['y'] - 0.02, 0.0), (B['y'] - 0.02, rz0 + 0.01)], 'X', -P['x'], P['x'], mats['block'], L_PAN)
    hosts.append(pan.name)
    hosts.append(en_box(K, 'pan_rail', -P['rail_x'], P['rail_x'], -P['rail_y'], P['rail_y'], rz0, B['rail_z'] + 0.005, mats['block'], L_PAN).name)
    # the banks: head on the deck, cam cover on the head (a flange, a body with chamfered ends, a raised top panel),
    # exhaust manifold on the head's outer face: four primaries into a log, the downpipe leaving at the rear
    for s in (-1, 1):
        dy = STAGGER * s; h = H['half']
        hosts.append(en_bank_box(K, 'head_%+d' % s, s, -h, h, -H['y'] + dy, H['y'] + dy, H['w'][0] - 0.02, H['w'][1], mats['head'], L_HEAD).name)
        w0, w1, w2 = C['w']; ch = C['half']
        # the cam cover: a rounded-rectangle flange, the cover on it rounded in plan with a filleted top, and a raised
        # rounded panel on top (its own part, so a line rings it)
        hosts.append(en_tilt(en_rslab(K, 'cover_flange_%+d' % s, 0.0, dy, ch, C['y'], CRANK_Z + w0, CRANK_Z + w1, C['corner'], 0.012,
                                      mats['red'], L_COVER, steps=2), s).name)
        hx, hy = ch - C['inset'], C['y'] - C['inset']
        hosts.append(en_tilt(en_rslab(K, 'cover_%+d' % s, 0.0, dy, hx, hy, CRANK_Z + w1 - 0.02, CRANK_Z + w2, C['corner'] - C['inset'], C['fillet'],
                                      mats['red'], L_COVER), s).name)
        px_, py_ = hx - C['panel_in'], hy - C['panel_in']
        hosts.append(en_tilt(en_rslab(K, 'cover_panel_%+d' % s, 0.0, dy, px_, py_, CRANK_Z + w2 - 0.02, CRANK_Z + w2 + C['panel_h'], C['panel_corner'],
                                      0.015, mats['red'], L_PLATEAU, steps=3), s).name)
        # exhaust: a primary off each port square to the head's outer face, turning down onto a log along the block
        lx, lz = s * EX['log_x'], EX['log_z']; ey0, ey1 = EX['y'][0] + dy, EX['y'][1] + dy
        for k, py in enumerate(I['runner_y']):
            y_ = py + dy; a0 = en_bank(s, H['half'] - 0.03, EX['w']); a1 = en_bank(s, H['half'] + EX['out'], EX['w'])
            path = pl_catmull([Vector((a0[0], y_, a0[1])), Vector((a1[0], y_, a1[1])), Vector((lx, y_, a1[1] - 0.08)), Vector((lx, y_, lz))], 8)
            hosts.append(en_label(K.sweep('primary_%+d_%d' % (s, k), path, EX['port_r'], mats['iron'], seg=32), L_EXHAUST).name)
        log = en_cyl_y(K, 'exhaust_log_%+d' % s, lx, lz, EX['log_r'], ey0, ey1, mats['iron'], L_EXHAUST); hosts.append(log.name)
        out = K.sweep('exhaust_outlet_%+d' % s, pl_catmull([Vector((lx, ey1 - 0.04, lz)), Vector((lx - s * 0.03, ey1 - 0.02, lz - 0.10)),
                                                            Vector((lx - s * 0.16, ey1, lz - 0.20))], 8), EX['log_r'] * 0.85, mats['iron'], seg=32)
        hosts.append(en_label(out, L_EXHAUST).name)
    # the oil filler cap on the -X cover's panel, near the front
    cx_, cz_ = en_bank(-1, -C['half'] + 0.06, C['w'][2] - 0.01)
    cap = K.cyl('filler_cap', cx_, CAP['y'] - STAGGER, cz_ + 0.03, CAP['r'], 0.10, mats['intake'], axis='Z', segments=48)
    hosts.append(en_label(cap, L_FIT).name)
    # the lower intake filling the valley between the heads' inner faces (sunk into them), flat on top
    L_ = LOWER; tx = I_[0] + (L_['top'] - I_[1]) / cos_t * sin_t; nx, nz = 0.02 * cos_t, -0.02 * sin_t
    lprof = [(0.0, valley_z), (I_[0] + nx, I_[1] + nz), (tx + nx, L_['top']), (-tx - nx, L_['top']), (-I_[0] - nx, I_[1] + nz)]
    hosts.append(en_prism(K, 'lower_intake', lprof, 'Y', *L_['y'], mats['intake'], L_INTAKE).name)
    # the plenum on it with a domed rear; arched runners from its flanks down to a flange over each head's ports
    plenum = en_cyl_y(K, 'plenum', 0.0, I['z'], I['r'], *I['y'], mats['intake'], L_RUNNER); hosts.append(plenum.name)
    hosts.append(en_label(K.sphere('plenum_dome', 0.0, I['y'][1], I['z'], I['r'], mats['intake']), L_RUNNER).name)
    for s in (-1, 1):
        px = s * I['port_x']
        for k, y in enumerate(I['runner_y']):
            y_ = y + STAGGER * s
            path = pl_catmull([Vector((s * 0.08, y_, I['z'] - 0.01)), Vector((s * 0.20, y_, I['z'] - 0.02)), Vector((s * 0.28, y_, I['z'] - 0.10)),
                               Vector((px, y_, L_['top'] + 0.06)), Vector((px, y_, L_['top'] - 0.04))], 8)
            hosts.append(en_label(K.sweep('runner_%+d_%d' % (s, k), path, I['runner_r'], mats['intake'], seg=32), L_RUNNER).name)
            hosts.append(en_box(K, 'runner_flange_%+d_%d' % (s, k), px - 0.10, px + 0.10, y_ - 0.10, y_ + 0.10, L_['top'] - 0.01, L_['top'] + 0.03,
                                mats['intake'], L_INTAKE).name)
    # the throttle body out of the plenum's front: one rib, a lip and a dark bore
    hosts.append(en_cyl_y(K, 'throttle', T['x'], T['z'], T['r'], T['y'][0] + 0.02, T['y'][1], mats['intake'], L_THROTTLE).name)
    y = T['y'][0] + 0.16
    hosts.append(en_cyl_y(K, 'throttle_rib', T['x'], T['z'], T['r'] + 0.02, y - 0.02, y + 0.02, mats['intake'], L_THROTTLE).name)
    hosts.append(en_cyl_y(K, 'throttle_lip', T['x'], T['z'], T['r'] + 0.02, T['y'][0], T['y'][0] + 0.05, mats['intake'], L_THROTTLE).name)
    en_cyl_y(K, 'throttle_bore', T['x'], T['z'], T['bore'], T['y'][0] - 0.004, T['y'][0] + 0.02, mats['bore'], L_THROTTLE)
    # the thermostat housing on the intake's nose and its hose neck, forward and up toward the radiator
    TH = THERMO; ty = TH['y']; tx_ = TH['x']; nd = Vector(TH['neck']).normalized(); n0 = Vector((tx_, ty - 0.05, TH['z']))
    hosts.append(en_cyl_y(K, 'thermostat', tx_, TH['z'], TH['r'], ty - 0.07, ty + 0.02, mats['intake'], L_THROTTLE).name)
    neck = K.dircyl('hose_neck', n0, n0 + nd * 0.16, TH['neck_r'], mats['intake'], segments=32); hosts.append(en_label(neck, L_THROTTLE).name)
    bead = K.dircyl('hose_bead', n0 + nd * 0.11, n0 + nd * 0.13, TH['neck_r'] + 0.012, mats['intake'], segments=32)
    hosts.append(en_label(bead, L_THROTTLE).name)
    # the timing cover on the block's front: a plate framed by a raised red rim, a red web beside the belt
    ty1 = -B['y'] + 0.005; ty0 = ty1 - TIMING['t']; pr = TIMING['proud']
    tprof = [tuple(p) for p in TIMING['profile']]
    tc = en_prism(K, 'timing_cover', tprof, 'Y', ty0, ty1, mats['block'], L_PANEL); hosts.append(tc.name)
    hosts.append(en_ring(K, 'timing_rim', tprof, en_inset(tprof, TIMING['rim']), ty0 - pr, ty0 + 0.01, mats['red'], L_TIMING).name)
    # the front drive, every pulley in one belt plane: crank pulley on the crank axis with a groove ring, the water pump
    # casting and pulley above it, the alternator on a pivot bracket with a slotted adjusting strap
    face0 = ty0 - pr; plane = (face0 - 0.10, face0 - 0.02)
    CR, PU, AL = CRANK, PUMP, ALT
    hosts.append(en_cyl_y(K, 'crank_pulley', CR['x'], CR['z'], CR['r'], face0 - CR['depth'], face0 + 0.01, mats['dark'], L_PULLEY).name)
    hosts.append(en_cyl_y(K, 'crank_groove', CR['x'], CR['z'], CR['groove'], face0 - CR['depth'] - 0.012, face0, mats['dark'], L_PULLEY).name)
    hosts.append(en_cyl_y(K, 'crank_hub', CR['x'], CR['z'], CR['hub'], face0 - CR['depth'] - 0.06, face0, mats['dark'], L_PULLEY).name)
    en_cyl_y(K, 'crank_bolt', CR['x'], CR['z'], CR['hub'] * 0.35, face0 - CR['depth'] - 0.064, face0 - CR['depth'] - 0.05, mats['bore'], L_PULLEY, seg=32)
    hosts.append(en_cyl_y(K, 'pump_body', PU['x'], PU['z'], PU['body'], plane[1] - 0.01, LOWER['y'][0] + 0.03, mats['block'], L_FIT).name)
    hosts.append(en_cyl_y(K, 'pump_pulley', PU['x'], PU['z'], PU['r'], *plane, mats['dark'], L_PULLEY).name)
    hosts.append(en_cyl_y(K, 'pump_hub', PU['x'], PU['z'], PU['hub'], plane[0] - 0.05, plane[0] + 0.01, mats['dark'], L_PULLEY).name)
    yb_ = (plane[1] + LOWER['y'][0]) / 2
    spig = K.dircyl('pump_inlet', (PU['x'] - 0.05, yb_, PU['z'] - 0.02), (PU['x'] - 0.24, yb_, PU['z'] - 0.07), 0.04, mats['block'], segments=32)
    hosts.append(en_label(spig, L_FIT).name)
    hosts.append(en_cyl_y(K, 'alternator', AL['x'], AL['z'], AL['r'], plane[1] + 0.01, AL['y'][1], mats['steel'], L_ALT).name)
    for k, yy in enumerate((plane[1] + 0.06, AL['y'][1] - 0.04)):
        hosts.append(en_cyl_y(K, 'alternator_band%d' % k, AL['x'], AL['z'], AL['r'] + 0.015, yy - 0.015, yy + 0.015, mats['steel'], L_ALT).name)
    hosts.append(en_cyl_y(K, 'alternator_pulley', AL['x'], AL['z'], AL['pulley'], *plane, mats['dark'], L_PULLEY).name)
    hosts.append(en_cyl_y(K, 'alternator_nut', AL['x'], AL['z'], AL['pulley'] * 0.5, plane[0] - 0.03, plane[0] + 0.01, mats['dark'], L_PULLEY).name)
    # alternator brackets in the front plane just behind the pulleys: a pivot bracket down to the block and a slotted
    # adjusting strap across to the pump, a bolt at each end
    by0, by1 = plane[1] + 0.005, plane[1] + 0.025
    hosts.append(en_strip(K, 'alt_pivot_bracket', (AL['x'], AL['z'] - AL['r'] + 0.03), (B['x'] - 0.04, side_z - 0.08), 0.08, by0, by1, mats['steel'], L_ALT).name)
    sa, sb = (AL['x'] - 0.07, AL['z'] + AL['r'] - 0.01), (PU['x'] + PU['body'] + 0.02, PU['z'] + 0.10)
    hosts.append(en_strip(K, 'alt_strap', sa, sb, 0.055, by0, by1, mats['steel'], L_ALT).name)
    va, vb = Vector(sa), Vector(sb)
    en_label(en_strip(K, 'alt_strap_slot', tuple(va.lerp(vb, 0.25)), tuple(va.lerp(vb, 0.75)), 0.018, by0 - 0.004, by0 + 0.002, mats['bore'], L_ALT), L_ALT)
    for k, (bx, bz) in enumerate((tuple(va.lerp(vb, 0.5)), (B['x'] - 0.04, side_z - 0.08))):
        en_cyl_y(K, 'alt_bolt%d' % k, bx, bz, 0.022, by0 - 0.02, by0 + 0.002, mats['dark'], L_ALT, seg=24)
    belt = en_belt(K, 'belt', [(CR['x'], CR['z'], CR['r'] - 0.02), (PU['x'], PU['z'], PU['r'] - 0.02), (AL['x'], AL['z'], AL['pulley'] - 0.015)], 0.035,
                   plane[0] + 0.015, plane[1] - 0.015, mats['belt'], L_BELT); hosts.append(belt.name)
    # on the +X side: an engine mount (cast bracket, rubber puck along X, frame plate) and the oil filter tilted down
    mz = (B['rail_z'] + side_z) / 2 - 0.02
    hosts.append(en_box(K, 'mount_bracket', B['x'] - 0.01, B['x'] + 0.06, -0.38, -0.16, B['rail_z'] + 0.01, side_z - 0.01, mats['block'], L_FIT).name)
    puck = K.cyl('mount_isolator', B['x'] + 0.09, -0.27, mz, 0.06, 0.07, mats['dark'], axis='X', segments=48); hosts.append(en_label(puck, L_PULLEY).name)
    hosts.append(en_box(K, 'mount_plate', B['x'] + 0.12, B['x'] + 0.15, -0.38, -0.16, mz - 0.11, mz + 0.09, mats['block'], L_ALT).name)
    fdir = Vector((math.cos(math.radians(30)), 0, -math.sin(math.radians(30)))); f0 = Vector((B['x'] - 0.01, 0.30, mz + 0.02))
    hosts.append(en_label(K.dircyl('filter_boss', f0, f0 + fdir * 0.06, 0.07, mats['block'], segments=48), L_FIT).name)
    hosts.append(en_label(K.dircyl('oil_filter', f0 + fdir * 0.05, f0 + fdir * 0.21, 0.085, mats['steel'], segments=48), L_TIMING).name)
    bpy.context.view_layer.update()
    for n in hosts:
        pl_mesh_lines(K, bpy.data.objects[n], bpy.data.objects[n]['part_label'], 40.0, n, 0.02)
    for ob in K.col.objects:
        if ob.get('ink_width') == 6:
            ob['ink_width'] = PL_INNER
    info = contract(K, [block.name, pan.name, plenum.name, tc.name], 'a 90 degree V8 long block: taupe block with banks at 45 degrees, heads and red '
                    'chamfered cam covers, lower intake and plenum with arched runners, forward throttle body and thermostat neck, exhaust '
                    'logs with primaries and rear downpipes, red-framed timing cover with crank, pump and alternator pulleys on one belt, '
                    'engine mount and oil filter, pan with rear sump and bellhousing flange', inner=PL_INNER)
    info['revision'] = EN_REVISION; info['outline']['component_boundaries'] = True; info['outline']['id_step'] = 17
    info['stipple']['strength'] = 0.38
    info['stipple']['groups'] = [{'name': 'shaded_faces', 'labels': list(range(1, 16)), 'thresholds': [0.575, 0.50, 0.30]}]
    info['dimensions'] = {'tilt': TILT, 'crank_z': CRANK_Z, 'block': BLOCK, 'head': HEAD, 'cover': COVER, 'intake': INTAKE, 'timing': TIMING}
    return info
