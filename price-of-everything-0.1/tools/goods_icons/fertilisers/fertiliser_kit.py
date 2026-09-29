"""Fertilisers (g_064): a raised bed of soil growing a fruiting tomato plant, with a fertiliser sack
leaning against it, on the isometric grid.

Reference: assets/icons/goods/medium/g_064_fertilisers.png (shipped AI art): a wooden raised bed (two
boards a side) heaped with dark soil, a tomato plant rising from it off-centre toward the front
(serrated compound leaves, a truss of three tomatoes hanging left, a truss of three hanging right,
one big tomato in front), and a green fertiliser sack standing up and leaning back against the bed's
front-left (-Y) side. The shipped art is already lit like the set (the -Y side lighter, the +X side
darker), so its layout is kept as drawn.
Owner rulings carried over: the shipped layout on the grid, the set's light, dots on shaded sides,
ink at every junction, one colour per material, 3 px for small detail, match the shipped details,
reuse parts from approved icons: the sack is the sand icon's pillow sack (legacy_batch.pillow),
stood up, leaning, recoloured green.
Proportions measured off the shipped art (bed width X = 1): bed 1.0 x 1.25 x 0.35; plant ~1.05 above
the soil; sack about 0.8 wide, 1.1 tall.
"""
import math, bmesh
from mathutils import Vector

FZ_REVISION = 'fertiliser_v9'
BOX = (0.0, 1.0, 0.0, 1.25, 0.0, 0.35)       # the bed: x0, x1, y0, y1, z0, z1
WALL, SEAM_Z = 0.05, 0.175                   # board thickness; the seam between the two boards of a side
SOIL_EDGE, SOIL_PEAK, SOIL_SPREAD = 0.31, 0.43, 0.42   # soil height at the walls, at the plant, and the mound's reach
STEM_AT = (0.72, 0.52)                       # where the plant rises (x, y)
STEM_H = 1.02
PLANT_Z = 0.84                                # v3 -> v4: the plant was ~20% too tall for its bed; heights scaled by this (tomatoes keep their size)
# OWNER (v5 -> v6): "the bag needs to look plump. Map its topology and try to do the same". Mapped off
# the shipped sack: a gusseted bag standing on its bottom seam and leaning back against the bed, about
# 0.8 tall and 0.7 wide with its width along the bed (turned ~8 degrees further toward -X) and its bottom
# ~0.3 in front of the bed; a crimped top seam and a bottom seam, each ending in pinched ears; a full body
# whose sides bulge and whose belly sits low; a rounded side panel (the +X side, in shade); creases under
# the top seam and on the lower side; glossy highlight streaks. Built as a loft of rounded-rectangle
# sections: the sand icon's pillow (v1-v5), stood up, stayed a flat cushion.
# v6 -> v7: v6 was a slab (its thickness near full from bottom to top, a boxy section, no ears). Now: a
# round belly sagging low (thickness sin(pi t^sag)^belly), a near-elliptical section, flat crimped seam
# bands at both ends (SEAM of the height), the body pinched in (pinch) so the seams' corners stand out as
# ears, and the lean measured off the shipped sack (~15 degrees; its top seam runs ~28 degrees on screen,
# a touch under the grid's 30, hence a small positive yaw).
# v7 -> v8: the shape FITTED to the shipped sack's silhouette (bag_fit.py: this loft projected through
# the fixed camera, shape compared by IoU after normalising area and centroid; v7 0.928 -> 0.961):
# lean 12.5, yaw 3.0, T/W 0.708, H/W 1.494, belly wider than the seams (pinch -0.134), sag 0.722,
# belly 0.619, an elliptical section (p 1.95). Sized to the shipped bag-to-bed ratio (W 0.56), its
# screen-left edge on the bed's left corner as shipped; EAR flares the flat seam bands' corners past the
# belly (the shipped sack's four ears, the fit's only misses).
BAG = {'W': 0.56, 'H': 0.56 * 1.494, 'T': 0.56 * 0.708, 'lean': 12.5, 'yaw': 3.0, 'p': 1.95,
       'sag': 0.722, 'belly': 0.619, 'pinch': -0.134, 'seam': 0.05, 'ear': 0.30, 'ear_reach': 0.13}
# v8 -> v9: the ears taper to points (they flare toward the very ends; v8's were square tabs).
VIEW = Vector((1.0, -1.0, 1.0)).normalized()  # toward the camera
RIGHT = Vector((1.0, 1.0, 0.0)).normalized()  # screen right, in the view plane
UP = VIEW.cross(RIGHT).normalized()           # screen up, in the view plane
ZUP = Vector((0.0, 0.0, 1.0))
SMALL_INK = 3
# Tomatoes: (screen a, height z above the soil at the stem, depth toward the camera, radius), after
# the shipped positions (a and z in bed widths).
TOMATOES = [(-0.278, 0.561, -0.02, 0.078), (-0.264, 0.373, 0.03, 0.080), (-0.118, 0.433, 0.08, 0.080),
            (0.125, 0.705, -0.02, 0.080), (0.278, 0.679, 0.02, 0.078), (0.305, 0.815, -0.06, 0.076),
            (0.100, 0.300, 0.16, 0.112)]
# Compound leaves: (height on the stem, screen angle in degrees (0 = right, 90 = up), length, depth).
# v4 -> v5: the upper leaves spread wider, toward the shipped silhouette.
LEAVES = [(0.14, 205, 0.44, 0.00), (0.20, -22, 0.38, -0.02), (0.44, 165, 0.42, -0.10), (0.50, 10, 0.38, -0.10),
          (0.66, 152, 0.46, -0.04), (0.74, 26, 0.42, -0.06), (0.88, 124, 0.36, -0.02), (0.95, 60, 0.34, -0.03),
          (0.58, 98, 0.26, -0.12)]


def fz_rgb(*c8):
    """8-bit sRGB -> linear."""
    def f(v):
        v = v / 255
        return v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4
    return tuple(f(v) for v in c8)


def fz_toon(name, shade, mid, lit):
    """Three flat tones by the set's shading steps: +X faces shade, -Y faces mid, tops lit."""
    return pw_toon_rgb(name, ((0.80, fz_rgb(*shade)), (0.975, fz_rgb(*mid)), (9.0, fz_rgb(*lit))))


def fz_soil_z(x, y):
    """The soil's surface: a mound at the plant over a level rim, with a few soft clumps."""
    bx, by = STEM_AT
    d2 = (x - bx) ** 2 + (y - by) ** 2
    z = SOIL_EDGE + (SOIL_PEAK - SOIL_EDGE) * math.exp(-d2 / SOIL_SPREAD ** 2)
    for cx, cy, a, s in ((0.30, 0.30, 0.020, 0.07), (0.25, 0.85, 0.018, 0.08), (0.55, 1.00, 0.020, 0.07), (0.80, 0.95, 0.016, 0.06),
                         (0.45, 0.62, 0.018, 0.06), (0.85, 0.25, 0.015, 0.06), (0.15, 0.55, 0.016, 0.07)):
        z += a * math.exp(-((x - cx) ** 2 + (y - cy) ** 2) / s ** 2)
    return z


def fz_soil(K, mat, label, n=(40, 50)):
    """The soil: a closed solid, its top the heightfield over the bed's inside, its sides down to the
    ground (hidden by the boards)."""
    x0, x1, y0, y1 = BOX[0] + WALL, BOX[1] - WALL, BOX[2] + WALL, BOX[3] - WALL
    nx, ny = n; vs = []; fs = []
    for j in range(ny + 1):
        for i in range(nx + 1):
            x = x0 + (x1 - x0) * i / nx; y = y0 + (y1 - y0) * j / ny
            vs.append((x, y, fz_soil_z(x, y)))
    top = len(vs)
    ring = [(i, 0) for i in range(nx)] + [(nx, j) for j in range(ny)] + [(i, ny) for i in range(nx, 0, -1)] + [(0, j) for j in range(ny, 0, -1)]
    base = len(vs)
    for i, j in ring:
        x, y, _ = vs[j * (nx + 1) + i]; vs.append((x, y, 0.001))
    for j in range(ny):
        for i in range(nx):
            a = j * (nx + 1) + i
            fs.append((a, a + 1, a + nx + 2, a + nx + 1))
    m = len(ring)
    for k in range(m):
        i0, j0 = ring[k]; i1, j1 = ring[(k + 1) % m]
        fs.append((j0 * (nx + 1) + i0, base + k, base + (k + 1) % m, j1 * (nx + 1) + i1))
    fs.append(tuple(base + k for k in range(m)))
    ob = mesh(K, 'soil', vs, fs, mat, False); ob['part_label'] = label
    for p in ob.data.polygons:
        p.use_smooth = True
    return ob


def fz_bed(K, mat, label):
    """Four walls of two boards each, butted at the corners, with the ink: the outer corner, the rim's
    outer and inner outlines and the seam between the boards (6 px); hidden runs drop out."""
    x0, x1, y0, y1, z0, z1 = BOX; w = WALL; hosts = []
    for nm, b in (('front', (x0, x1, y0, y0 + w)), ('back', (x0, x1, y1 - w, y1)), ('left', (x0, x0 + w, y0 + w, y1 - w)), ('right', (x1 - w, x1, y0 + w, y1 - w))):
        hosts.append(alk_box(K, 'bed_' + nm, b[0], b[1], b[2], b[3], z0, z1, mat, label, edges=False).name)
    outer = [(x0 - E, y0 - E), (x1 + E, y0 - E), (x1 + E, y1 + E), (x0 - E, y1 + E)]
    inner = [(x0 + w + E, y0 + w + E), (x1 - w - E, y0 + w + E), (x1 - w - E, y1 - w - E), (x0 + w + E, y1 - w - E)]
    tagged_line(K, 'bed_rim_outer', [(x, y, z1 + E) for x, y in outer], label, 6, True)['ink_width'] = 0
    tagged_line(K, 'bed_rim_inner', [(x, y, z1 + E) for x, y in inner], label, 6, True)['ink_width'] = 0
    tagged_line(K, 'bed_seam', [(x, y, SEAM_Z) for x, y in outer], label, 6, True)['ink_width'] = 0
    for k, (x, y) in enumerate(outer):
        tagged_line(K, 'bed_corner%d' % k, [(x, y, z0), (x, y, z1 + E)], label, 6, False)
    for k, (x, y) in enumerate(inner):                # the inner corners, above the soil
        tagged_line(K, 'bed_inner_corner%d' % k, [(x, y, SOIL_EDGE - 0.02), (x, y, z1 + E)], label, 6, False)
    return hosts


def fz_sphere(K, name, c, r, mat, label):
    bm = bmesh.new(); bmesh.ops.create_uvsphere(bm, u_segments=48, v_segments=24, radius=r)
    bmesh.ops.translate(bm, vec=Vector(c), verts=bm.verts)
    me = bpy.data.meshes.new(name); bm.to_mesh(me); bm.free()
    ob = noink(K.obj(name, me, mat, True)); ob['part_label'] = label
    for p in ob.data.polygons:
        p.use_smooth = True
    return ob


def fz_circle(c, r, n=72):
    """A circle in the view plane: a sphere's silhouette."""
    return [tuple(Vector(c) + (RIGHT * math.cos(t) + UP * math.sin(t)) * r) for t in [2 * math.pi * k / n for k in range(n)]]


def fz_plate(K, name, uv, O, U, V, t, mat, label, width=6, clean=True):
    """A thin plate cut from a (u, v) outline in the plane O + U*u + V*v, t thick along N = U x V;
    ink: one outline at its mid-plane, pushed a hair out in-plane (visible from either side)."""
    O, U, V = Vector(O), Vector(U), Vector(V); N = U.cross(V).normalized()
    def place(u, v, d):
        return tuple(O + U * u + V * v + N * d)
    n = len(uv)
    vs = [place(u, v, -t / 2) for u, v in uv] + [place(u, v, t / 2) for u, v in uv]
    fs = [tuple(range(n)), tuple(n + k for k in range(n))] + [(k, (k + 1) % n, n + (k + 1) % n, n + k) for k in range(n)]
    ob = mesh(K, name, vs, fs, mat, False); ob['part_label'] = label
    if clean:
        pw_clean_water(ob)
    ring = [Vector(q) + o * E for q, o in zip(uv, alk_outward(uv))]
    tagged_line(K, name + '_outline', [place(q.x, q.y, 0.0) for q in ring], label, width, True)['ink_width'] = 0
    return ob, N


def fz_leaflet(L, W, teeth=5):
    """A serrated leaflet outline, u along its axis 0..L, v across."""
    pts = []; n = 40
    for side in (1, -1):
        rng = range(n + 1) if side == 1 else range(n, -1, -1)
        for i in rng:
            u = i / n
            h = W * max(0.0, math.sin(math.pi * u ** 0.85)) ** 0.8
            if 0.12 < u < 0.92:
                h *= 1.0 - 0.22 * ((u * teeth) % 1.0)          # saw teeth pointing to the tip
            pts.append((u * L, side * h))
    out = [pts[0]]
    for p in pts[1:]:
        if (Vector(p) - Vector(out[-1])).length > 1e-6:
            out.append(p)
    if (Vector(out[0]) - Vector(out[-1])).length < 1e-6:
        out.pop()
    return out


def fz_leaf(K, name, P, direction, L, mat, stem_m, label, stem_label):
    """A compound leaf: a rachis from P along `direction` (a view-plane unit vector, tilted a little
    toward the camera and up) with a terminal leaflet and two pairs of side leaflets."""
    D = Vector(direction).normalized()
    Nplane = (VIEW + ZUP * 0.45).normalized()
    Dp = (D - Nplane * D.dot(Nplane)).normalized(); Wp = Nplane.cross(Dp).normalized()
    tip = P + Dp * L * 0.62
    rach = noink(K.sweep(name + '_rachis', [tuple(P), tuple(P + Dp * L * 0.3 + Wp * 0.01), tuple(tip)], 0.009, stem_m, seg=12))
    rach['part_label'] = stem_label
    obs = [rach]
    # v1 -> v2: five narrow leaflets with 6 px outlines filled the plant with ink; three broad
    # leaflets with 3 px outlines, as the shipped leaves read.
    specs = [(0.60, 0.0, 0.46, 0.26), (0.34, 58.0, 0.36, 0.21), (0.34, -58.0, 0.36, 0.21)]
    for k, (s, ang, ll, ww) in enumerate(specs):
        base = P + Dp * L * s
        a = math.radians(ang)
        U = (Dp * math.cos(a) + Wp * math.sin(a)).normalized(); V = Nplane.cross(U).normalized()
        ob, N = fz_plate(K, '%s_leaflet%d' % (name, k), fz_leaflet(L * ll, L * ww / 2), base, U, V, 0.008, mat, label, SMALL_INK)
        side = 1.0 if N.dot(VIEW) > 0 else -1.0
        tagged_line(K, '%s_leaflet%d_rib' % (name, k), [tuple(base + U * (L * ll * f) + N * side * (0.004 + E)) for f in (0.05, 0.5, 0.85)], label, SMALL_INK, False)
        obs.append(ob)
    return obs


def fz_star(n=5, r0=1.0, r1=0.42):
    return [((r0 if k % 2 == 0 else r1) * math.cos(math.pi * k / n + math.pi / 2), (r0 if k % 2 == 0 else r1) * math.sin(math.pi * k / n + math.pi / 2)) for k in range(2 * n)]


def fz_bag(K, mat, glint_m, label, rows=56, cols=96):
    """A plump gusseted bag: horizontal rounded-rectangle sections (superellipses) lofted from the bottom
    seam to the top seam, thick through most of its height and pinched flat at both seams, the seams a
    touch wider than the body so their ends stand out as ears; then leaned back, turned and set against the
    bed's -Y side. Ink: the crimp line under the top seam, the bottom seam's line and a crease on the lower
    side (3 px); glossy streaks as flat glints."""
    b = BAG; H, W, T, p = b['H'], b['W'], b['T'], b['p']; sm = b['seam']
    def f(t):                                     # thickness: a round belly sagging low, flat at the seam bands
        u = (t - sm) / (1 - 2 * sm)
        if u <= 0 or u >= 1:
            return 0.0
        return math.sin(math.pi * u ** b['sag']) ** b['belly']
    def a(t):                                     # half-width: the belly's bulge, and pointed ears flaring to the ends
        d = min(t, 1 - t)
        return W / 2 * (1 - b['pinch'] * f(t) + b['ear'] * max(0.0, 1 - d / b['ear_reach']) ** 2)
    def bth(t):
        return max(0.006, T / 2 * f(t))
    def sec(t, th):                               # the section at height t, angle th (0 = +x, -pi/2 = the front, -y)
        c, sn = math.cos(th), math.sin(th)
        return Vector((a(t) * math.copysign(abs(c) ** (2 / p), c), bth(t) * math.copysign(abs(sn) ** (2 / p), sn), t * H))
    lean, yaw = math.radians(b['lean']), math.radians(b['yaw'])
    def place(q):                                 # lean the top back (+y), then turn about z
        x, y, z = q
        y, z = y * math.cos(lean) + z * math.sin(lean), -y * math.sin(lean) + z * math.cos(lean)
        return Vector((x * math.cos(yaw) - y * math.sin(yaw), x * math.sin(yaw) + y * math.cos(yaw), z))
    vs = []; fs = []
    for j in range(rows + 1):
        for k in range(cols):
            vs.append(place(sec(j / rows, 2 * math.pi * k / cols)))
    for j in range(rows):
        for k in range(cols):
            k2 = (k + 1) % cols
            fs.append((j * cols + k, j * cols + k2, (j + 1) * cols + k2, (j + 1) * cols + k))
    fs.append(tuple(reversed(range(cols)))); fs.append(tuple(rows * cols + k for k in range(cols)))
    # On the ground, against the bed: its back at the rim's height just clears the bed's -Y face.
    zmin = min(v.z for v in vs)
    rim = [v for v in vs if abs(v.z - zmin - (BOX[5] - 0.01)) < 0.03]
    dy = BOX[2] - 0.006 - max(v.y for v in rim)
    dx = -min(v.x + v.y + dy for v in vs)          # screen-left edge (x + y = const) on the bed's left corner (0, 0)
    shift = Vector((dx, dy, -zmin))
    ob = mesh(K, 'fert_bag', [tuple(v + shift) for v in vs], fs, mat, False); ob['part_label'] = label
    for poly in ob.data.polygons:
        poly.use_smooth = True
    def surf(t, th, lift=E):                      # a surface point pushed out along the section's normal
        q = sec(t, th); n2 = Vector((q.x / max(a(t), 1e-6) ** 2, q.y / max(bth(t), 1e-6) ** 2, 0.0))
        n2 = n2.normalized() if n2.length > 1e-9 else Vector((0.0, -1.0, 0.0))
        return tuple(place(q + n2 * lift) + shift)
    front = [-math.pi / 2 + math.pi * 0.46 * (i / 10 - 1) for i in range(21)]
    top_seam, bottom_seam = 1 - sm, sm
    tagged_line(K, 'fert_bag_crimp', [surf(top_seam - 0.004, th) for th in front], label, SMALL_INK, False)
    tagged_line(K, 'fert_bag_bottom', [surf(bottom_seam + 0.004, th) for th in front], label, SMALL_INK, False)
    # Creases, as shipped: a long one down the lower right, two short ones pulled under the top seam.
    tagged_line(K, 'fert_bag_crease0', [surf(0.14 + 0.36 * i / 12, -0.78 + 0.22 * math.sin(math.pi * i / 12)) for i in range(13)], label, SMALL_INK, False)
    # v8 -> v9: one short crease pulled down-left from under the top-right ear (v8's two ticks read as eyes).
    tagged_line(K, 'fert_bag_crease1', [surf(0.90 - 0.10 * i / 10, -0.42 - 0.34 * i / 10 - 0.10 * math.sin(math.pi * i / 10)) for i in range(11)], label, SMALL_INK, False)
    for k, (t0, t1, th0, th1, wdt) in enumerate(((0.26, 0.82, -2.20, -2.40, 0.10), (0.30, 0.46, -0.62, -0.56, 0.08), (0.80, 0.82, -2.05, -1.70, 0.05))):
        pts = [(t0 + (t1 - t0) * i / 8, th0 + (th1 - th0) * i / 8) for i in range(9)]
        left = [surf(t, th - wdt * math.sin(math.pi * i / 8) * 0.5, 0.003) for i, (t, th) in enumerate(pts)]
        right = [surf(t, th + wdt * math.sin(math.pi * i / 8) * 0.5, 0.003) for i, (t, th) in enumerate(pts)]
        n = len(left); vs2 = left + right[::-1]
        g = mesh(K, 'fert_bag_glint%d' % k, vs2, [(i, i + 1, 2 * n - 2 - i, 2 * n - 1 - i) for i in range(n - 1)], glint_m, False)
        g['part_label'] = label; g.pass_index = 73; pw_clean_water(g)
    return ob


def build_fertilisers():
    """Fertilisers v1: the shipped bed, soil, tomato plant and sack on the grid."""
    setup_icon_rig(); K = Kit(open_collection('ICON_fertilisers')); hosts = []
    wood_m = fz_toon('fz_wood', (154, 100, 64), (185, 128, 83), (212, 158, 108))
    soil_m = fz_toon('fz_soil', (84, 50, 33), (109, 66, 42), (143, 92, 60))
    stem_m = fz_toon('fz_stem', (52, 112, 58), (78, 148, 80), (112, 180, 104))
    leaf_m = fz_toon('fz_leaf', (48, 108, 56), (74, 146, 78), (108, 178, 100))
    tomato_m = fz_toon('fz_tomato', (158, 38, 30), (205, 62, 44), (230, 98, 70))
    sack_m = fz_toon('fz_sack', (61, 112, 67), (96, 155, 89), (112, 170, 102))   # v9: a softer lit step, as the shipped sack's flatter green
    glint_m = pw_flat('fz_glint', fz_rgb(246, 226, 214))
    bag_glint_m = pw_flat('fz_bag_glint', fz_rgb(186, 222, 166))
    L_BED, L_SOIL, L_SACK, L_STEM, L_LEAF, L_TOMATO, L_CALYX = 1, 2, 3, 4, 5, 6, 7

    hosts += fz_bed(K, wood_m, L_BED)
    hosts.append(fz_soil(K, soil_m, L_SOIL).name)
    # Crumb marks on the soil, as shipped: short arcs drawn on its surface (3 px).
    for k, (cx, cy, ln, ang) in enumerate(((0.25, 0.30, 0.12, 20), (0.42, 0.95, 0.10, -15), (0.20, 0.78, 0.09, 35), (0.60, 1.05, 0.11, 10),
                                            (0.86, 0.80, 0.09, -25), (0.35, 0.55, 0.08, 5), (0.82, 0.30, 0.08, 30))):
        a = math.radians(ang); d = Vector((math.cos(a), math.sin(a), 0.0)); nrm = Vector((-d.y, d.x, 0.0))
        pts = []
        for i in range(9):
            f = i / 8 - 0.5; q = Vector((cx, cy, 0.0)) + d * ln * f + nrm * (0.022 * (1 - (2 * f) ** 2))
            pts.append((q.x, q.y, fz_soil_z(q.x, q.y) + 0.004))
        tagged_line(K, 'soil_crumb%d' % k, pts, L_SOIL, SMALL_INK, False)

    # The plant.
    bx, by = STEM_AT; B = Vector((bx, by, fz_soil_z(bx, by) - 0.03))
    def at(a, z, d=0.0):
        return B + RIGHT * a + ZUP * z * PLANT_Z + VIEW * d
    stem_pts = [at(0.0, 0.0), at(0.01, 0.25), at(-0.02, 0.55), at(0.0, 0.80), at(0.03, STEM_H)]
    stem = noink(K.sweep('stem', [tuple(p) for p in stem_pts], 0.022, stem_m, seg=20)); stem['part_label'] = L_STEM; hosts.append(stem.name)
    def on_stem(z):
        z *= PLANT_Z                                   # v4 -> v5: attachment heights scale with the plant
        zs = [p.z - B.z for p in stem_pts]
        for i in range(len(zs) - 1):
            if zs[i] <= z <= zs[i + 1]:
                f = (z - zs[i]) / (zs[i + 1] - zs[i]); return stem_pts[i].lerp(stem_pts[i + 1], f)
        return stem_pts[-1]
    for k, (zs, ang, L, d) in enumerate(LEAVES):
        a = math.radians(ang)
        direction = RIGHT * math.cos(a) + UP * math.sin(a)
        P = on_stem(zs) + VIEW * d
        branch = noink(K.sweep('leaf%d_petiole' % k, [tuple(on_stem(zs)), tuple(P + direction * 0.06)], 0.012, stem_m, seg=12))
        branch['part_label'] = L_STEM
        fz_leaf(K, 'leaf%d' % k, P + direction * 0.05, direction, L, leaf_m, stem_m, L_LEAF, L_STEM)
    # Tomatoes: sphere, silhouette ink, a glint, a calyx star on top and a stalk up to a truss.
    trusses = {'left': (0.60, [0, 1, 2]), 'right': (0.84, [3, 4, 5]), 'front': (0.46, [6])}
    for tname, (zs, idx) in trusses.items():
        root = on_stem(zs)
        for k in idx:
            a, z, d, r = TOMATOES[k]
            c = at(a, z, d)
            hosts.append(fz_sphere(K, 'tomato%d' % k, c, r, tomato_m, L_TOMATO).name)
            tagged_line(K, 'tomato%d_rim' % k, fz_circle(c, r + E), L_TOMATO, 6, True)['ink_width'] = 0
            g = [(0.0, 0.0), (0.30, 0.10), (0.50, 0.28), (0.22, 0.14)]
            gc = c + (UP * 0.35 - RIGHT * 0.42) * r + VIEW * r * 0.83
            gl = mesh(K, 'tomato%d_glint' % k, [tuple(gc + (RIGHT * u + UP * v) * r) for u, v in g], [(0, 1, 2, 3)], glint_m, False)
            gl['part_label'] = L_TOMATO; gl.pass_index = 73; pw_clean_water(gl)
            top = c + ZUP * r
            star = [(u * r * 0.55, v * r * 0.55) for u, v in fz_star()]
            cal, _ = fz_plate(K, 'tomato%d_calyx' % k, star, top + ZUP * 0.004, Vector((1, 0, 0)), Vector((0, 1, 0)), 0.01, stem_m, L_CALYX, SMALL_INK)
            hosts.append(cal.name)
            knee = root.lerp(top, 0.5) + ZUP * 0.06
            ped = noink(K.sweep('tomato%d_stalk' % k, [tuple(top), tuple(knee), tuple(root)], 0.010, stem_m, seg=10)); ped['part_label'] = L_STEM

    # The fertiliser bag (see BAG).
    hosts.append(fz_bag(K, sack_m, bag_glint_m, L_SACK).name)

    info = contract(K, hosts, 'wooden raised bed of heaped soil with a fruiting tomato plant; a plump green gusseted fertiliser bag leaning against it')
    info['revision'] = FZ_REVISION
    info['outline']['component_boundaries'] = True
    # OWNER (v5 -> v6): "could use thinner linework on the leaves esp. the outside": leaves and stems take a
    # 6 px outer contour (the set's is 12) and leaves 3 px boundaries (6); tomatoes, bed, soil and bag keep
    # the set's weights. (A per-part option in standard_lines; without it exports are unchanged.)
    info['outline']['outer_by_label'] = {str(L_STEM): 6, str(L_LEAF): 6}
    info['outline']['component_weight_by_label'] = {str(L_LEAF): 3}
    info['stipple']['strength'] = 0.38
    info['stipple']['groups'][0]['thresholds'] = [0.65, 0.60, 0.35]
    info['dimensions'] = {'bed': BOX, 'wall': WALL, 'seam': SEAM_Z, 'soil': [SOIL_EDGE, SOIL_PEAK, SOIL_SPREAD], 'stem_at': STEM_AT, 'stem_h': STEM_H,
                          'bag': BAG, 'tomatoes': TOMATOES, 'leaves': LEAVES}
    return info
