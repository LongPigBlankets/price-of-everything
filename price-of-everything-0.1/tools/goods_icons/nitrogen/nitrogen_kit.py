"""Nitrogen (g_068): a dark blue-grey gas cylinder carrying a green-bordered N2 diamond.

OWNER 2026-09-29: "I recommend using the new nitrogen (should be a canister with grey body and green
diamond on it) rather than the current silver one". No file matching that description was found
(every nitrogen image in the project, its git history, the research icons and recent downloads
show the silver liquid-nitrogen dewar), so the icon is built from the description: one upright
steel cylinder, grey, with the UN class 2.2 green diamond (white border, white cylinder symbol, a
"2" in the bottom corner) and a white "N2" band, in the family of the approved gas icons (oxygen's
cylinders and labels, ammonia's valve).
On the grid: the cylinder stands on Z, its prints are wrapped round the side that faces the camera
(azimuth 45 degrees between -Y and +X, as oxygen and ammonia do), and the valve's outlet points -Y.
The set's light makes the shoulder palest and turns the right (+X) flank to shade, dotted.
Units: body radius 0.5 (diameter 1.0); shell 2.19 tall, valve and wheel to 2.73.
"""
import math, bmesh
from mathutils import Vector

N2_REVISION = 'nitrogen_v5'
# v1 -> v2: a stockier canister (v1's 2.5:1 cylinder left the tile mostly empty) and a larger
# diamond, the owner's named feature.
R_BODY, Z_FOOT, Z_SHOULDER, Z_NECK = 0.5, 0.06, 1.72, 2.19
R_NECK = 0.17
# OWNER (v2 -> v3): "darker grey, slightly metallic blue and make the green label be in the middle
# and the N2 text sits inside the diamond. Navy text on white diamond with thick green outline".
# The white band goes; one diamond, centred on the body, carries the formula.
DIAMOND = (0.95, 0.96, 0.70)                 # centre height (mid-body on screen), outer diagonal, white face's diagonal (v4: border 0.09 thick)
# OWNER (v4 -> v5): "thicker green outline for nitrogen and rounded corners on the diamond. maybe also
# green shoulders". The white face shrinks to a 0.58 diagonal (the green border 0.134 thick, was 0.092),
# both diamonds get rounded corners (radius in the square's own frame), and the shoulder dome is painted
# the diamond's green (its mid tone is the diamond's flat green).
DIAMOND = (0.95, 0.96, 0.58)
CORNER_R = (0.075, 0.045)                    # corner radius of the green diamond and of the white face
TEXT_WH = (0.30, 0.20)                       # the N2 lettering's bounds
SHEEN = (-84.0, 7.0)                         # the metallic streak: azimuth of the most lit side (deg), width (deg)
GREEN_LIN = (0.021, 0.262, 0.071)            # UN 2.2 green, about (40,140,75)
PAPER_LIN = (0.86, 0.86, 0.84)


def fz_lin(*c8):
    """8-bit sRGB -> linear."""
    return tuple((v / 255) / 12.92 if v / 255 <= 0.04045 else ((v / 255 + 0.055) / 1.055) ** 2.4 for v in c8)


def n2_wrap(r, z0):
    """(u, v) on the label plane -> world: u is arc length round the cylinder from the side that
    faces the camera (u grows to screen right), v is height above z0."""
    def f(u, v):
        th = math.pi / 4 + u / r
        return Vector((r * math.sin(th), -r * math.cos(th), z0 + v))
    return f


def n2_grid_mesh(K, name, corner, du, dv, n, wrap, mat, label):
    """A parallelogram corner + s*du + t*dv (s, t in [0, 1]) as an n x n quad grid, wrapped."""
    vs = []; fs = []
    for j in range(n + 1):
        for i in range(n + 1):
            p = Vector(corner) + Vector(du) * (i / n) + Vector(dv) * (j / n)
            vs.append(tuple(wrap(p.x, p.y)))
    for j in range(n):
        for i in range(n):
            a = j * (n + 1) + i
            fs.append((a, a + 1, a + n + 2, a + n + 1))
    ob = pw_clean_water(mesh(K, name, vs, fs, mat, False)); ob['part_label'] = label; ob.pass_index = 73
    return ob


def n2_diamond(K, name, cz, diag, r, mat, label, n=18):
    """A diamond (square on its point) of the given diagonal, centred at height cz, wrapped at r."""
    h = diag / 2
    return n2_grid_mesh(K, name, (-h, 0.0), (h, h), (h, -h), n, n2_wrap(r, cz), mat, label)


def n2_rounded_diamond(K, name, cz, diag, rc, r, mat, label, n=28):
    """A diamond (a square on its point) with rounded corners of radius rc (in the square's own frame):
    an n x n grid over the square, each point pulled along its ray from the centre onto the rounded
    outline, turned onto its point, then wrapped round the cylinder at radius r (fine enough that no
    face sags into the body)."""
    hs = diag / (2 * math.sqrt(2)); rc = min(rc, hs * 0.95)
    def boundary(dx, dy):                         # distance from the centre to the rounded square along unit (dx, dy)
        t = hs / max(abs(dx), abs(dy))
        if abs(t * dx) > hs - rc and abs(t * dy) > hs - rc:
            cx, cy = math.copysign(hs - rc, dx), math.copysign(hs - rc, dy)
            dc = dx * cx + dy * cy
            t = dc + math.sqrt(max(0.0, dc * dc - (cx * cx + cy * cy) + rc * rc))
        return t
    wrap = n2_wrap(r, cz); vs = []; fs = []
    for j in range(n + 1):
        for i in range(n + 1):
            x = -hs + 2 * hs * i / n; y = -hs + 2 * hs * j / n; ln = math.hypot(x, y)
            if ln > 1e-9:
                dx, dy = x / ln, y / ln
                k = boundary(dx, dy) / (hs / max(abs(dx), abs(dy)))
                x, y = x * k, y * k
            vs.append(tuple(wrap((x - y) / math.sqrt(2), (x + y) / math.sqrt(2))))
    for j in range(n):
        for i in range(n):
            a = j * (n + 1) + i
            fs.append((a, a + 1, a + n + 2, a + n + 1))
    ob = pw_clean_water(mesh(K, name, vs, fs, mat, False)); ob['part_label'] = label; ob.pass_index = 73
    return ob


def n2_flat_poly(K, name, uv, wrap, mat, label):
    """A small flat polygon (fan-triangulated, edges split) wrapped onto the cylinder."""
    me = bpy.data.meshes.new(name); me.from_pydata([(u, v, 0.0) for u, v in uv], [], [tuple(range(len(uv)))]); me.update()
    bm = bmesh.new(); bm.from_mesh(me); bmesh.ops.triangulate(bm, faces=bm.faces[:])
    bmesh.ops.subdivide_edges(bm, edges=bm.edges[:], cuts=3, use_grid_fill=True); bm.to_mesh(me); bm.free()
    for v in me.vertices:
        v.co = wrap(v.co.x, v.co.y)
    ob = K.obj(name, me, mat, False); noink(pw_clean_water(ob)); ob['part_label'] = label; ob.pass_index = 73
    return ob


def build_nitrogen():
    """Nitrogen v1: grey cylinder, green 2.2 diamond, white N2 band, valve with handwheel."""
    setup_icon_rig(); K = Kit(open_collection('ICON_nitrogen')); hosts = []
    body_m = pw_toon('n2_body', (0.17, 0.20, 0.26), ((0.70, 0.45), (0.95, 0.75), (9.0, 1.0)))   # shoulder (115,124,140), lit side (100,108,122), shade (79,85,97)
    sheen_m = pw_flat('n2_sheen', (0.36, 0.40, 0.48))                                           # (162,170,184)
    steel_m = pw_toon('n2_valve', (0.58, 0.62, 0.68), ((0.70, 0.45), (0.95, 0.75), (9.0, 1.0)))
    green_m = pw_flat('n2_green', GREEN_LIN)
    paper_m = pw_flat('n2_paper', PAPER_LIN)
    navy_m = pw_flat('n2_navy', (0.007, 0.012, 0.042))
    L_BODY, L_DIAMOND, L_COLLAR, L_VALVE, L_WHEEL = 1, 3, 4, 5, 6

    # Shell: foot bevel, straight body, elliptical shoulder, neck.
    prof = [(0.0, 0.0), (0.46, 0.0), (0.49, 0.02), (R_BODY, Z_FOOT), (R_BODY, Z_SHOULDER)]
    for k in range(1, 13):
        t = k / 12 * math.pi / 2
        prof.append((R_NECK + (R_BODY - R_NECK) * math.cos(t), Z_SHOULDER + (Z_NECK - 0.07 - Z_SHOULDER) * math.sin(t)))
    prof += [(R_NECK, Z_NECK), (0.0, Z_NECK)]
    shell = pw_lathe_z(K, 'n2_shell', prof, body_m, (0.0, 0.0), 160); shell['part_label'] = L_BODY; hosts.append(shell.name)
    # Green shoulders (owner, v5): the dome above the shoulder seam in the diamond's green.
    shoulder_m = pw_toon_rgb('n2_shoulder', ((0.70, fz_lin(26, 98, 52)), (0.95, GREEN_LIN), (9.0, fz_lin(72, 168, 100))))
    shell.data.materials.append(shoulder_m)
    for poly in shell.data.polygons:
        if poly.center.z > Z_SHOULDER + 1e-4:
            poly.material_index = 1
    pw_circle_z(K, 'n2_foot_seam', (0.0, 0.0), Z_FOOT + E, R_BODY + E, L_BODY)
    pw_circle_z(K, 'n2_shoulder_seam', (0.0, 0.0), Z_SHOULDER, R_BODY + E, L_BODY)

    # The metallic streak down the lit side (below the shoulder seam), as on oxygen's cylinders.
    a0, a1 = math.radians(SHEEN[0] - SHEEN[1] / 2), math.radians(SHEEN[0] + SHEEN[1] / 2); n = 12; vs = []
    for z in (Z_FOOT + 0.05, Z_SHOULDER - 0.05):
        for k in range(n + 1):
            a = a0 + (a1 - a0) * k / n; vs.append(((R_BODY + 0.002) * math.cos(a), (R_BODY + 0.002) * math.sin(a), z))
    sheen = mesh(K, 'n2_sheen', vs, [(k, k + 1, k + n + 2, k + n + 1) for k in range(n)], sheen_m, False)
    sheen['part_label'] = L_BODY; sheen.pass_index = 73; pw_clean_water(sheen)

    # The label: a white diamond with a thick green border, N2 in navy on it, centred on the body.
    cz, dg, dw = DIAMOND
    n2_rounded_diamond(K, 'n2_diamond', cz, dg, CORNER_R[0], R_BODY + 0.005, green_m, L_DIAMOND)
    n2_rounded_diamond(K, 'n2_diamond_face', cz, dw, CORNER_R[1], R_BODY + 0.008, paper_m, L_DIAMOND)
    word = formula_mesh(K.col, 'n2_formula', 'N2', navy_m, TEXT_WH[0], TEXT_WH[1], chemical=True)
    wrap = n2_wrap(R_BODY + 0.011, cz)
    for v in word.data.vertices:
        v.co = wrap(v.co.x, v.co.y)
    word['part_label'] = L_DIAMOND; noink(pw_clean_water(word))

    # Valve: collar on the neck, body, outlet to -Y, spindle and handwheel.
    col = pw_lathe_z(K, 'n2_collar', [(0.0, Z_NECK - 0.02), (0.2, Z_NECK - 0.02), (0.2, Z_NECK + 0.10), (0.0, Z_NECK + 0.10)], steel_m, (0.0, 0.0), 96)
    col['part_label'] = L_COLLAR; hosts.append(col.name)
    zv0, zv1 = Z_NECK + 0.09, Z_NECK + 0.40
    vb = pw_lathe_z(K, 'n2_valve_body', [(0.0, zv0), (0.11, zv0), (0.11, zv1), (0.0, zv1)], steel_m, (0.0, 0.0), 96)
    vb['part_label'] = L_VALVE; hosts.append(vb.name)
    out = K.cyl('n2_outlet', 0.0, -0.17, zv0 + 0.13, 0.062, 0.16, steel_m, axis='Y', segments=64)
    noink(out); out['part_label'] = L_VALVE; hosts.append(out.name)
    bore = noink(K.cyl('n2_outlet_bore', 0.0, -0.2505, zv0 + 0.13, 0.034, 0.002, navy_m, axis='Y', segments=48)); bore['part_label'] = L_VALVE; bore.pass_index = 73
    sp = pw_lathe_z(K, 'n2_spindle', [(0.0, zv1 - 0.01), (0.04, zv1 - 0.01), (0.04, zv1 + 0.12), (0.0, zv1 + 0.12)], steel_m, (0.0, 0.0), 48)
    sp['part_label'] = L_VALVE; hosts.append(sp.name)
    zw = zv1 + 0.12
    wheel = noink(K.washer('n2_handwheel', (0.0, 0.0, zw), (0, 0, 1), 0.15, 0.22, 0.045, steel_m, seg=96)); wheel['part_label'] = L_WHEEL; hosts.append(wheel.name)
    for k, (sx, sy) in enumerate(((0.32, 0.035), (0.035, 0.32))):
        s = noink(K.box('n2_spoke_%d' % k, 0.0, 0.0, zw, sx, sy, 0.035, steel_m)); s['part_label'] = L_WHEEL
    for part in (col, vb, out, sp, wheel):
        pw_clean_water(part)                           # small bright hardware stays clean, as on oxygen

    info = contract(K, hosts, 'dark blue-grey steel gas cylinder with green shoulders: a rounded white diamond with a thick green border and N2 in navy, valve with side outlet and handwheel')
    info['revision'] = N2_REVISION
    info['outline']['component_boundaries'] = True
    info['stipple']['strength'] = 0.38
    info['stipple']['groups'][0]['thresholds'] = [0.65, 0.60, 0.35]
    info['dimensions'] = {'body_radius': R_BODY, 'foot': Z_FOOT, 'shoulder': Z_SHOULDER, 'neck': [R_NECK, Z_NECK], 'sheen': SHEEN,
                          'diamond': DIAMOND, 'corner_r': CORNER_R, 'text': TEXT_WH, 'green_linear': GREEN_LIN, 'shoulders': 'green'}
    return info
