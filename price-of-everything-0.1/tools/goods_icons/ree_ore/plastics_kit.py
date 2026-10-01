"""Plastics (g_027): a monobloc garden chair, a PET bottle and a carrier bag of pellets, on the grid.

Reference: assets/icons/goods/medium/g_027_plastics.png (shipped AI art): a cream monobloc armchair
facing the lower right (+X): a tall reclined backrest curved round the seat, its top an arch, with
three slots; armrests running forward from the backrest's sides and bending down into the front legs;
a seat whose back edge follows the backrest; splayed legs with an angle (L) section. In front of its
left side a cream PET bottle (a blue-grey cap, a shoulder, two grooves, a petal base); at its front
right a dusty-blue T-shirt carrier bag, its two handle loops up, its mouth heaped with cream pellets.
OWNER 2026-09-29: "move onto plastics, iterate on that with the topology of the chair and the plastic
bottle. The bag might be difficult but try to get close ... keep looping with the reviewer until its
done". Owner rulings carried over: the shipped layout on the grid, the set's light, dots on shaded
sides, ink at every junction, one colour per material (all the cream plastic one material, the cap
and the bag one blue), 3 px for small detail (pellets, grooves, creases), soft goods plump.
Units: the chair is ~1.75 tall (a real one ~0.85 m), the bottle 0.62, the bag 0.72 plus handles.
v28 (owner 2026-09-30): the chair is the owner's downloaded model, Poly Haven's "Plastic Monobloc Chair 01" by Kuutti
Siitonen (CC0), welded into one solid (monobloc_chair.npz) and placed on the shipped chair (CHAIR_MESH); the parametric
chair (chair_geom.py, pl_chair) stays for reference. v29-33: the bag's left handle and its pellets (pl_bag).
Approved 2026-09-30 as plastics_v33 (owner: "that's pretty good. approved.").
"""
import math, bmesh
import numpy as np
from mathutils import Vector, Matrix

PL_REVISION = 'plastics_v33'
SMALL_INK = 3
PL_INNER = 4          # v23 (owner 2026-09-30: "thinner internal linework (aside from the outer outline)"): interior px at 800
# --- the chair (faces +X) ---
SEAT_Z, SEAT_T = 0.88, 0.05
SEAT_FRONT, SEAT_HALF_W, SEAT_CORNER = 0.45, 0.46, 0.10   # v4: the front edge reaches into the front legs, the back into the wall
BACK_C, BACK_R, BACK_PHI = 0.095, 0.555, 58.0    # the backrest's plan arc: centre x, radius, half-angle (deg from -X)
BACK_TOP, BACK_SIDE, BACK_RECLINE, BACK_T = 1.76, 1.40, 0.14, 0.045
# v2 -> v3: bigger slots, the left one a wide leaf, as shipped: (arc position deg, v0, v1, half-width)
SLOTS = [(-26.0, 0.30, 0.74, 0.060), (-4.0, 0.20, 0.86, 0.042), (16.0, 0.20, 0.86, 0.042)]
BACK_LEAN = 0.20                               # the backrest leans back this far at its top (v3)
ARM_Z, ARM_Y, ARM_X, ARM_BEND = 1.30, 0.50, 0.24, 0.15
# v1 -> v2: the chair is a monobloc: ONE swept band from the left front foot up the leg, back along the
# arm, round the backrest, forward along the right arm and down the right leg. Its section changes along
# the way: a plate facing forward on the legs, a wide flat band on the arms, a tall thin wall round the
# back whose top arches up from the arms and whose bottom drops to the seat, opening the arm gaps.
U_PATH = [(0.30, -0.50), (0.05, -0.52), (-0.20, -0.49), (-0.40, -0.33), (-0.47, 0.0), (-0.40, 0.33), (-0.20, 0.49), (0.05, 0.52), (0.30, 0.50)]
SHELL = {'back_t': 0.045, 'arm_w': 0.13, 'arm_h': 0.05, 'leg_w': 0.16, 'leg_t': 0.045, 'top_q': 0.62, 'open_q': (0.28, 0.62)}
ARM_W, ARM_H = 0.12, 0.05                       # the armrest band: width, thickness
LEG_W, LEG_T = 0.15, 0.035                      # the L section's arm width and plate thickness (v3: wider)
FRONT_FOOT = (0.50, 0.56)
BACK_TOP_XY, BACK_FOOT = (-0.22, 0.40), (-0.40, 0.54)
# --- the bottle and the bag ---
# v14: moved ~10 px right on screen, clear of the rear leg (review v13b); v9: fitted to the shipped bottle (fit/bottle_fit.py, B5_p1.6.json, IoU 0.966): the cap's height measured, the
# shoulder kept a dome (p >= 1.6) above the rings, the cap at least 0.055 so its blue reads at game size
BOTTLE = dict(bx=0.3587, by=-0.8452, R=0.1243, H=0.8217, hc=0.062, rc=0.0554, zs0=0.5625, p=1.6289, rb=0.0195, pinch=0.0941, zf=0.0805)
BOTTLE_RINGS = (0.391, 0.473, 0.557)            # the shipped bottle's three ring lines (heights measured)
# v6: fitted to the shipped bag's silhouette (fit/bag_fit.py on the grid, flush straps: G7_fit, IoU 0.905); v16: the lips and
# the heap read off the shipped bag by back-projection (review v15c), moved ~10 px right off the chair's far post
BAG = dict(bx=1.0115, by=0.0289, yaw=90.0, H=1.1676, W=0.9082, bulge=0.12, D=0.3824, bb=0.5271, s1=0.23, sq=0.05, s2=0.12, hL_c=0.7187, hL_z=-0.050, hL_rx=0.1227, hL_rz=0.1944, hL_w=0.0645, hL_psi=-14.2029, hL_y=0.0511, hL_diag=1, hL_in=-0.26, hR_c=0.6226, hR_z=-0.1327, hR_rx=0.1664, hR_rz=0.2809, hR_w=0.0645, hR_psi=-14.6658, hR_y=-0.0506, hR_outer_lip=0, heap=[[0.13, 0.945, 0.28, 0.17], [-0.31, 0.925, 0.05, 0.05]], shoulders=1, bn=0.0, neck=0.0, pe=2.4, s3=0.1, lips={'x': [-0.454, -0.2, 0.0, 0.18, 0.33, 0.454], 'back': [0.9, 0.95, 0.98, 0.99, 0.9, 0.8], 'front': [0.9, 0.85, 0.8, 0.8, 0.8, 0.8], 'side': [0.9, 0.9, 0.9, 0.9, 0.85, 0.8]}, fill_dz=-0.8, fill_courses=1)
# v30 (owner 2026-09-30: "the left handle looks illogical, it doesnt meet the front face of the bag"; review v29): hL_diag:
# the left loop runs across the mouth's left end as the shipped one does, facing the viewer: its inner leg rises out of
# the front lip at x = hL_in, twisting out of the film into the loop; v31: its outer leg rises out of the bag's rounded
# left end, twisting the same way, so its foot is the bag's side (hL_c, hL_psi, hL_y, hL_rx unused; hL_z -0.014 ->
# -0.050, review v30: the arch ran tangent to the chair seat's edge).
# fill_dz, fill_courses ("the nurdles look suspended, add more underneath, using the same technique used in the alumina
# bag"): the mouth filled to fill_dz pellet radii off the front lip under the fitted heap; courses under the top one
# (alumina's pellet_cluster, offset half a step) down to fill_courses below that level; a cream core under them
# the shipped bag's creases, traced and back-projected onto the fitted bag (fit/bag_creases.py): (t, theta)
BAG_CREASES = {'smile': [(0.92, -2.18), (0.87, -1.944), (0.787, -1.7), (0.714, -1.534), (0.682, -1.368), (0.687, -1.202), (0.697, -1.079)],
               'right': [(0.521, -0.817), (0.501, -1.027), (0.459, -1.193), (0.401, -1.315)],
               'left': [(1.0, -2.923), (0.902, -2.853), (0.774, -2.871), (0.591, -3.037), (0.459, -3.08), (0.401, -3.037)],
               'foot': [(0.306, 3.045), (0.336, -2.958), (0.353, -2.678), (0.348, -2.364)],
               'foot2': [(0.414, 2.976), (0.371, 3.133), (0.371, -3.037)]}
BAG_HEAP_DOME = 0.09                            # v15: the heap's dome above the mouth's rim (review v14d: 30 px too low)
PELLET_R = 0.018                                # v14: ~9 px faces, ~40 brimming the whole mouth (review v13b)

VIEW = Vector((1.0, -1.0, 1.0)).normalized()
RIGHT = Vector((1.0, 1.0, 0.0)).normalized()
UP = VIEW.cross(RIGHT).normalized()


def pl_rgb(*c8):
    return tuple((v / 255) / 12.92 if v / 255 <= 0.04045 else ((v / 255 + 0.055) / 1.055) ** 2.4 for v in c8)


PL_SHADE_STEP = 0.65      # v10: the shade colour starts where ruling 5's dots start, so every shade pixel is dotted


def pl_toon(name, shade, mid, lit):
    return pw_toon_rgb(name, ((PL_SHADE_STEP, pl_rgb(*shade)), (0.975, pl_rgb(*mid)), (9.0, pl_rgb(*lit))))


def pl_frames(path, n0):
    """Parallel-transported frames (T, N, B) along a polyline, N starting as n0 (made square to T)."""
    P = [Vector(p) for p in path]; m = len(P); out = []
    T = [((P[min(i + 1, m - 1)] - P[max(i - 1, 0)]).normalized()) for i in range(m)]
    N = (Vector(n0) - T[0] * Vector(n0).dot(T[0])).normalized()
    for i in range(m):
        if i > 0:
            N = T[i - 1].rotation_difference(T[i]).to_matrix() @ N
            N = (N - T[i] * N.dot(T[i])).normalized()
        out.append((T[i], N, T[i].cross(N).normalized()))
    return P, out


def pl_sweep(K, name, path, profile, n0, mat, label, caps=True):
    """Sweep a closed 2D profile (x along B, y along N) along a path; returns (object, rings of world
    points) so callers can draw ink along chosen profile vertices."""
    P, F = pl_frames(path, n0); m = len(profile); rings = []
    for p, (T, N, B) in zip(P, F):
        rings.append([p + B * x + N * y for x, y in profile])
    vs = [tuple(q) for ring in rings for q in ring]; fs = []
    for i in range(len(rings) - 1):
        a, b = i * m, (i + 1) * m
        fs += [(a + k, a + (k + 1) % m, b + (k + 1) % m, b + k) for k in range(m)]
    if caps:
        fs.append(tuple(reversed(range(m)))); fs.append(tuple((len(rings) - 1) * m + k for k in range(m)))
    ob = mesh(K, name, vs, fs, mat, False); ob['part_label'] = label
    return ob, rings, F


def pl_sweep_n(K, name, path, normals, profile, mat, label):
    """v30: pl_sweep with the section's N given at each path point (made square to the path), so a strap can twist;
    returns (object, rings of world points)."""
    P = [Vector(p) for p in path]; m_ = len(P); rings = []
    for i in range(m_):
        T = (P[min(i + 1, m_ - 1)] - P[max(i - 1, 0)]).normalized(); N = Vector(normals[i])
        N = (N - T * N.dot(T)).normalized(); B = T.cross(N).normalized()
        rings.append([P[i] + B * x + N * y for x, y in profile])
    m = len(profile); vs = [tuple(q) for ring in rings for q in ring]; fs = []
    for i in range(len(rings) - 1):
        a_, b_ = i * m, (i + 1) * m
        fs += [(a_ + k, a_ + (k + 1) % m, b_ + (k + 1) % m, b_ + k) for k in range(m)]
    fs.append(tuple(reversed(range(m)))); fs.append(tuple((len(rings) - 1) * m + k for k in range(m)))
    ob = mesh(K, name, vs, fs, mat, False); ob['part_label'] = label
    return ob, rings


def pl_rrect(w, h, r, n=5):
    """A rounded rectangle, centred, as a closed CCW polygon."""
    pts = []
    for cx, cy, a0 in ((w / 2 - r, h / 2 - r, 0), (-w / 2 + r, h / 2 - r, 90), (-w / 2 + r, -h / 2 + r, 180), (w / 2 - r, -h / 2 + r, 270)):
        for k in range(n + 1):
            a = math.radians(a0 + 90 * k / n); pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return pts


def pl_cut(K, ob, cutters):
    """Boolean difference of cutter objects from ob, applied; the cutters are deleted."""
    for c in cutters:
        mod = ob.modifiers.new('cut', 'BOOLEAN'); mod.operation = 'DIFFERENCE'; mod.solver = 'EXACT'; mod.object = c
    bpy.context.view_layer.update()
    me = bpy.data.meshes.new_from_object(ob.evaluated_get(bpy.context.evaluated_depsgraph_get()))
    mats = list(ob.data.materials)
    for mod in list(ob.modifiers):
        ob.modifiers.remove(mod)
    old = ob.data; ob.data = me; bpy.data.meshes.remove(old)
    me.materials.clear()
    for mt in mats:
        me.materials.append(mt)
    for c in cutters:
        bpy.data.objects.remove(c, do_unlink=True)
    return noink(ob)


# ---------------------------------------------------------------- the chair
def pl_catmull(ctrl, per=12):
    P = [Vector(c) for c in ctrl]; out = []
    for i in range(len(P) - 1):
        p0 = P[i - 1] if i > 0 else P[i] * 2 - P[i + 1]; p1, p2 = P[i], P[i + 1]
        p3 = P[i + 2] if i + 2 < len(P) else P[i + 1] * 2 - P[i]
        for j in range(per):
            t = j / per; t2 = t * t; t3 = t2 * t
            out.append(0.5 * (2 * p1 + (p2 - p0) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (3 * p1 - p0 - 3 * p2 + p3) * t3))
    out.append(P[-1])
    return out


def pl_smooth(x):
    x = max(0.0, min(1.0, x)); return x * x * (3 - 2 * x)


def pl_lean(p):
    """The backrest's recline: points above the seat, toward the back, pushed outward in plan by up to
    BACK_LEAN at the top (the arms' back ends follow a little; the front of the chair does not move)."""
    p = Vector(p)
    wz = max(0.0, (p.z - SEAT_Z) / (BACK_TOP - SEAT_Z)); wx = pl_smooth((-p.x - 0.05) / 0.40)
    d = Vector((p.x, p.y, 0.0))
    if d.length < 1e-6 or wz <= 0 or wx <= 0:
        return p
    return p + d.normalized() * (BACK_LEAN * wz * wx)


def pl_shell(K, mat, label_l, label_r, label_back):
    """The monobloc shell as one sweep: legs, arms and backrest (see SHELL). Returns the object and the
    band's four long edges' ink paths are added here; slots are cut through the back."""
    S = SHELL
    U = pl_catmull([(x, y, 0.0) for x, y in U_PATH], 14)
    L = [0.0]
    for a, b in zip(U, U[1:]):
        L.append(L[-1] + (b - a).length)
    tot = L[-1]
    def heights(u):                                 # (bottom, top) of the band at plan fraction u
        q = abs(u - 0.5) / 0.5
        zt = ARM_Z + S['arm_h'] / 2 + (BACK_TOP - ARM_Z - S['arm_h'] / 2) * pl_smooth(1 - q / S['top_q'])
        q0, q1 = S['open_q']
        zb = SEAT_Z - 0.03 + (ARM_Z - S['arm_h'] / 2 - SEAT_Z + 0.03) * pl_smooth((q - q0) / (q1 - q0))
        return zb, zt
    def width(u):
        q = abs(u - 0.5) / 0.5
        return S['back_t'] + (S['arm_w'] - S['back_t']) * pl_smooth((q - 0.46) / 0.22)
    path, prof_hw = [], []
    # the left leg: from the foot up to the bend, then an arc back into the arm (the arm starts at U[0])
    R = ARM_BEND; a0 = Vector((U_PATH[0][0], U_PATH[0][1], ARM_Z)); C = a0 - Vector((0.0, 0.0, R))
    lf = Vector((FRONT_FOOT[0], -FRONT_FOOT[1], 0.0)); b0 = C + Vector((R, 0.0, 0.0))
    for k in range(10):
        path.append(lf.lerp(b0, k / 10)); prof_hw.append((S['leg_t'], S['leg_w']))
    for k in range(12):
        t = math.radians(90 * k / 12); f = k / 12
        path.append(C + Vector((R * math.cos(t), 0.0, R * math.sin(t))))
        prof_hw.append((S['leg_t'] + (S['arm_h'] - S['leg_t']) * f, S['leg_w'] + (S['arm_w'] - S['leg_w']) * f))
    # the U: arms and backrest
    # The U's centre line stays level at the arm height (a sloping line tilted the frames, and the tall
    # back sections crossed each other); each section is offset up or down along N instead.
    for i, p in enumerate(U):
        u = L[i] / tot; zb, zt = heights(u)
        path.append(Vector((p.x, p.y, ARM_Z))); prof_hw.append((zt - zb, width(u), (zb + zt) / 2 - ARM_Z))
    # the right leg: bending down from the arm to the foot
    a1 = Vector((U_PATH[-1][0], U_PATH[-1][1], ARM_Z)); bend_c2 = a1 + Vector((ARM_BEND, 0.0, -ARM_BEND))
    rf = Vector((FRONT_FOOT[0], FRONT_FOOT[1], 0.0))
    for k in range(1, 13):
        t = math.radians(90 * k / 12)
        path.append(Vector((a1.x + ARM_BEND * math.sin(t), a1.y, ARM_Z - ARM_BEND * (1 - math.cos(t)))))
        f = k / 12; prof_hw.append((S['arm_h'] + (S['leg_t'] - S['arm_h']) * f, S['arm_w'] + (S['leg_w'] - S['arm_w']) * f))
    top_r = path[-1]
    for k in range(1, 11):
        f = k / 10; path.append(top_r.lerp(rf, f)); prof_hw.append((S['leg_t'], S['leg_w']))
    # sweep with a per-sample rounded rectangle (h along N, w along B)
    P, F = pl_frames(path, (1, 0, 0))
    m = None; rings = []
    for pt, (T, N, B), hw in zip(P, F, prof_hw):
        h, w = hw[0], hw[1]; dz = hw[2] if len(hw) > 2 else 0.0
        prof = pl_rrect(w, h, min(0.016, w * 0.3, h * 0.3), 3)
        m = len(prof); rings.append([pl_lean(pt + B * x + N * (y + dz)) for x, y in prof])
    vs = [tuple(q) for ring in rings for q in ring]; fs = []
    for i in range(len(rings) - 1):
        a, b = i * m, (i + 1) * m
        fs += [(a + k, a + (k + 1) % m, b + (k + 1) % m, b + k) for k in range(m)]
    fs.append(tuple(reversed(range(m)))); fs.append(tuple((len(rings) - 1) * m + k for k in range(m)))
    ob = mesh(K, 'chair_shell', vs, fs, mat, False); ob['part_label'] = label_back
    # the band's four long edges as ink (the rounded corners' mid points), split into left, back, right
    corner = [2 + 4 * c for c in range(4)]
    for c, q in enumerate(corner):
        pts = []
        for ring in rings:
            ctr = sum(ring, Vector()) / m; pp = ring[q % m]; pts.append(tuple(pp + (pp - ctr).normalized() * E))
        tagged_line(K, 'shell_edge%d' % c, pts, label_back, 6, False)
    # slots through the back: cutters square to the wall at their plan position
    cutters = []
    for k, (ph, v0, v1, half) in enumerate(SLOTS):
        u = 0.5 + ph / 90.0 * 0.25                  # plan position along the U (degrees of arc -> fraction)
        i = min(range(len(U)), key=lambda j: abs(L[j] / tot - u)); c = U[i]
        tng = (U[min(i + 1, len(U) - 1)] - U[max(i - 1, 0)]).normalized(); nrm = Vector((-tng.y, tng.x, 0.0))
        zb, zt = heights(u); z0 = zb + (zt - zb) * v0; z1 = zb + (zt - zb) * v1
        outline = pl_rrect(2 * half, z1 - z0, half * 0.98, 8)
        zc = (z0 + z1) / 2
        pts = [c + tng * x + Vector((0, 0, zc + y)) for x, y in outline]
        cvs = [tuple(pl_lean(q - nrm * 0.1)) for q in pts] + [tuple(pl_lean(q + nrm * 0.1)) for q in pts]; mm = len(pts)
        cfs = [tuple(range(mm)), tuple(mm + j for j in range(mm))] + [(j, (j + 1) % mm, mm + (j + 1) % mm, mm + j) for j in range(mm)]
        cutters.append(mesh(K, 'slot_cutter%d' % k, cvs, cfs, None, False))
        for sgn, nm in ((-1, 'a'), (1, 'b')):
            tagged_line(K, 'slot%d_%s' % (k, nm), [tuple(pl_lean(q + nrm * sgn * (S['back_t'] / 2 + E))) for q in pts], label_back, 6, True)['ink_width'] = 0
    pl_cut(K, ob, cutters); ob['part_label'] = label_back
    # The front legs' fold (v3): a fin along each leg's outer edge, running back, as the shipped legs'
    # angle section shows.
    for sy, lab in ((-1, label_l), (1, label_r)):
        foot = Vector((FRONT_FOOT[0], sy * FRONT_FOOT[1], 0.0)); top = Vector((U_PATH[0][0] + ARM_BEND, sy * abs(U_PATH[0][1]), ARM_Z - ARM_BEND))
        def at(z):                                  # the leg plate's centre at height z
            return foot.lerp(top, z / top.z)
        z1 = SEAT_Z - SEAT_T - 0.01; fw, ft = 0.11, 0.035
        corners = []
        for z in (0.0, z1):
            c = at(z); xo = c.x - S['leg_t'] / 2; yo = c.y + sy * S['leg_w'] / 2      # the plate's back face, outer edge
            corners.append([(xo + 0.004, yo, z), (xo - fw, yo, z), (xo - fw, yo - sy * ft, z), (xo + 0.004, yo - sy * ft, z)])
        vs = corners[0] + corners[1]
        fs = [(0, 1, 2, 3), (4, 7, 6, 5), (0, 4, 5, 1), (1, 5, 6, 2), (2, 6, 7, 3), (3, 7, 4, 0)]
        fin = mesh(K, 'front_fin_%s' % ('left' if sy < 0 else 'right'), vs, fs, mat, False); fin['part_label'] = lab
        for e, (a, b) in enumerate(((1, 5), (2, 6))):
            pa, pb = Vector(vs[a]), Vector(vs[b]); off = Vector((-E, sy * E if e == 0 else -sy * E, 0.0))
            tagged_line(K, 'front_fin_%d_%d' % (sy, e), [tuple(pa + off), tuple(pb + off)], lab, 6, False)
        tagged_line(K, 'front_fin_%d_top' % sy, [tuple(Vector(vs[4]) + Vector((0, 0, E))), tuple(Vector(vs[5]) + Vector((0, 0, E))), tuple(Vector(vs[6]) + Vector((0, 0, E)))], lab, 6, False)
    return ob


def pl_back_point(phi, v, dr=0.0):
    """(v1 helper, kept for the seat's arc) the backrest arc point."""
    R = BACK_R + BACK_RECLINE * v + dr
    pm = math.radians(BACK_PHI)
    ztop = BACK_TOP - (BACK_TOP - BACK_SIDE) * (phi / pm) ** 2
    z0 = SEAT_Z - 0.03
    return Vector((BACK_C - R * math.cos(phi), R * math.sin(phi), z0 + (ztop - z0) * v))


def pl_seat(K, mat, label):
    """The seat: the front edge straight with rounded corners, the back following the backrest arc."""
    pts = []; ys = SEAT_HALF_W
    U = pl_catmull([(x, y, 0.0) for x, y in U_PATH], 14)
    back = [p for p in U if p.x < 0.05]                              # the U's back half, from -y to +y
    for p in back:
        pts.append((p.x + 0.005, p.y * (ys / 0.52)))           # on the wall's centre line: the seat joins the backrest
    r = SEAT_CORNER
    for cx, cy, s0 in ((SEAT_FRONT - r, ys - r, 90), (SEAT_FRONT - r, -ys + r, 0)):
        for k in range(7):
            a = math.radians(s0 - 90 * k / 6); pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    n = len(pts); z0, z1 = SEAT_Z - SEAT_T, SEAT_Z
    vs = [(x, y, z0) for x, y in pts] + [(x, y, z1) for x, y in pts]
    fs = [tuple(range(n)), tuple(n + k for k in range(n))] + [(k, (k + 1) % n, n + (k + 1) % n, n + k) for k in range(n)]
    ob = mesh(K, 'chair_seat', vs, fs, mat, False); ob['part_label'] = label
    outs = alk_outward(pts); ring = [(x + o.x * E, y + o.y * E) for (x, y), o in zip(pts, outs)]
    tagged_line(K, 'seat_top', [(x, y, z1 + E) for x, y in ring], label, 6, True)['ink_width'] = 0
    tagged_line(K, 'seat_bottom', [(x, y, z0 - E) for x, y in ring], label, 6, True)['ink_width'] = 0
    return ob, pts


def pl_arm(K, name, side, mat, label):
    """An armrest band from the backrest's side, forward, bending down into the front leg's top."""
    y = side * ARM_Y
    xs = BACK_C - math.sqrt(max(0.0, (BACK_R + 0.06) ** 2 - ARM_Y ** 2))
    path = [Vector((xs - 0.02, y, ARM_Z))]
    for k in range(1, 9):
        path.append(Vector((xs + (ARM_X - xs) * k / 8, y, ARM_Z)))
    for k in range(1, 13):
        t = math.radians(90 * k / 12)
        path.append(Vector((ARM_X + ARM_BEND * math.sin(t), y, ARM_Z - ARM_BEND + ARM_BEND * math.cos(t))))
    x_top = ARM_X + ARM_BEND
    for k in range(1, 7):
        f = k / 6; path.append(Vector((x_top + 0.01 * f, y + side * 0.005 * f, ARM_Z - ARM_BEND - (ARM_Z - ARM_BEND - (SEAT_Z - 0.10)) * f)))
    prof = pl_rrect(ARM_W, ARM_H, 0.018)
    ob, rings, F = pl_sweep(K, name, path, prof, (0, 0, 1), mat, label)
    # ink along the band's four long edges (the rounded corners' mid points), 6 px
    m = len(prof)
    for k, q in enumerate((3, 3 + 6, 3 + 12, 3 + 18)):
        pts = []
        for ring, (T, N, B) in zip(rings, F):
            c = sum(ring, Vector()) / m; p = ring[q % m]; pts.append(tuple(p + (p - c).normalized() * E))
        tagged_line(K, '%s_edge%d' % (name, k), pts, label, 6, False)
    return ob


def pl_leg(K, name, top, foot, sx, sy, mat, label):
    """An L-section leg from top (x, y, z) to foot (x, y): two plates meeting at the leg's outer corner
    (sx, sy: the outward signs); the section keeps its axes while the leg splays."""
    top = Vector(top); foot = Vector((foot[0], foot[1], 0.0))
    w, t = LEG_W, LEG_T
    # the L in the leg's local (dx, dy): plate A across y (thin in x), plate B across x (thin in y)
    L = [(0, 0), (0, -sy * w), (-sx * t, -sy * w), (-sx * t, -sy * t), (-sx * w, -sy * t), (-sx * w, 0)]
    if sx * sy < 0:
        L = L[::-1]
    n = len(L)
    vs = [(top.x + dx, top.y + dy, top.z) for dx, dy in L] + [(foot.x + dx, foot.y + dy, 0.0) for dx, dy in L]
    fs = [tuple(range(n)), tuple(n + k for k in range(n))] + [(k, (k + 1) % n, n + (k + 1) % n, n + k) for k in range(n)]
    ob = mesh(K, name, vs, fs, mat, False); ob['part_label'] = label
    outs = alk_outward(L)
    for k, ((dx, dy), o) in enumerate(zip(L, outs)):
        tagged_line(K, '%s_edge%d' % (name, k), [(top.x + dx + o.x * E, top.y + dy + o.y * E, top.z), (foot.x + dx + o.x * E, foot.y + dy + o.y * E, E)], label, 6, False)
    ring = [(dx + o.x * E, dy + o.y * E) for (dx, dy), o in zip(L, outs)]
    tagged_line(K, name + '_foot', [(foot.x + dx, foot.y + dy, E) for dx, dy in ring], label, 6, True)['ink_width'] = 0
    return ob


def pl_rings_mesh(K, name, rings, mat, label):
    """A closed mesh from swept rings (quads between rings, a cap at each end)."""
    n, m = rings.shape[0], rings.shape[1]
    vs = [tuple(map(float, q)) for ring in rings for q in ring]; fs = []
    for i in range(n - 1):
        a, b = i * m, (i + 1) * m
        fs += [(a + k, a + (k + 1) % m, b + (k + 1) % m, b + k) for k in range(m)]
    fs.append(tuple(reversed(range(m)))); fs.append(tuple((n - 1) * m + k for k in range(m)))
    ob = mesh(K, name, vs, fs, mat, False); ob['part_label'] = label
    return ob


def pl_ring_edge(K, name, rings, corner, label, width=6):
    """Ink along one rounded corner of a swept rounded-rectangle section (4 corners of 4 points)."""
    pts = []
    for ring in rings:
        ctr = ring.mean(axis=0); pp = (ring[4 * corner + 1] + ring[4 * corner + 2]) / 2; d = pp - ctr
        pts.append(tuple(map(float, pp + d / (np.linalg.norm(d) + 1e-12) * E)))
    return tagged_line(K, name, pts, label, width, False)


def pl_chair(K, mat, L_SEAT, L_BACK, L_ARM_L, L_ARM_R, L_LEGS):
    """v6: the chair from chair_geom (the shape fitted to the shipped chair's silhouette): the shell
    swept as one band with the slots cut through its back web, the rolled rim along the back's top,
    the seat, the back legs and the front legs' fins."""
    P = CG_P; hosts = []
    rings, i0, i1, U, Q, zb, zt = cg_shell(P)
    shell = pl_rings_mesh(K, 'chair_shell', rings, mat, L_BACK)
    posts = P.get('legs_as_posts', 0)
    for c in range(4):
        rr = rings
        if not posts and c == 2:                      # v10: not along the legs, where the fins continue the outer face
            rr = rings[8:-8]
        if not posts and c == 3:                      # v12: the far post's inner-back edge (its thin side read as a strip)
            rr = rings[:-8]
        pl_ring_edge(K, 'shell_edge%d' % c, rr, c, L_BACK)
    if not posts:
        # v12: the near front foot's Λ (as shipped): from the corner a little above the floor down to the ends of the
        # foot's two faces, offset along each face's own normal
        r0, r1 = rings[0], rings[1]; ctr0 = r0.mean(axis=0)
        corner = (r0[5] + r0[6]) / 2; inner = (r0[1] + r0[2]) / 2; back = (r0[9] + r0[10]) / 2
        CH = 0.08; up = (r1.mean(axis=0) - ctr0); up = up / np.linalg.norm(up)
        apex = corner + up * CH / max(up[2], 1e-6)
        n_front = (inner + corner) / 2 - ctr0; n_front[2] = 0; n_front /= np.linalg.norm(n_front)
        n_side = (back + corner) / 2 - ctr0; n_side[2] = 0; n_side /= np.linalg.norm(n_side)
        for nm, end, nrm in (('front', corner + (inner - corner) * 0.6, n_front), ('side', corner + (back - corner) * 0.95, n_side)):
            tagged_line(K, 'near_foot_lambda_' + nm, [tuple(map(float, apex + nrm * 2 * E)), tuple(map(float, end + nrm * 2 * E + np.array([0, 0, E])))], L_BACK, 6, False)
    cutters = []
    for k, (fr, bk, _) in enumerate(cg_slots(P, U, Q, reach=0.12)):
        mm = len(fr)
        cvs = [tuple(map(float, q)) for q in fr] + [tuple(map(float, q)) for q in bk]
        cfs = [tuple(range(mm)), tuple(mm + j for j in range(mm))] + [(j, (j + 1) % mm, mm + (j + 1) % mm, mm + j) for j in range(mm)]
        cutters.append(mesh(K, 'slot_cutter%d' % k, cvs, cfs, None, False))
    for k, (fr, bk, _) in enumerate(cg_slots(P, U, Q, reach=P['back_t'] / 2 + E)):
        for nm, ring, wd in (('a', fr, 6), ('b', bk, SMALL_INK)):
            ob_ = tagged_line(K, 'slot%d_%s' % (k, nm), [tuple(map(float, q)) for q in ring], L_BACK, wd, True)
            if wd == 6:
                ob_['ink_width'] = 0                      # the standard round-jointed 6 px; the 3 px walls keep their width
    pl_cut(K, shell, cutters); shell['part_label'] = L_BACK; hosts.append(shell.name)
    rims, rqs = cg_rim(dict(P, rim_with_q=1), U, Q, zb, zt)
    for j, (rr, rq) in enumerate(zip(rims, rqs)):
        rim = pl_rings_mesh(K, 'chair_rim%d' % j, rr, mat, L_BACK); hosts.append(rim.name)
        keep = rr                                         # v11: the rim ends at the arm junction (rim_qend 0.50), inked to its end
        for c in (2, 3):                                  # the rim's lower edges, where it leaves the web
            if len(keep) >= 2:
                ln = pl_ring_edge(K, 'rim%d_edge%d' % (j, c), keep, c, L_BACK)
                ln['ink_width'] = 6; ln['ink_tip'] = 0.5; ln['ink_centre'] = 1.0    # v18-19: tapered ends, never under 3 px
    # v7: the seat's top is flat back to a crease, then slopes down to one thin front edge (as shipped)
    ring, ztop, z0, (bp, fp), ends = cg_seat_solid(P, U, Q)
    pts = [tuple(map(float, p)) for p in ring]; n = len(pts); zt_ = [float(z) for z in ztop]
    vs = [(x, y, z0) for x, y in pts] + [(x, y, z) for (x, y), z in zip(pts, zt_)]
    fs = [tuple(reversed(range(n))), tuple(n + i for i in bp), tuple(n + i for i in fp)] + [(i, (i + 1) % n, n + (i + 1) % n, n + i) for i in range(n)]
    seat = mesh(K, 'chair_seat', vs, fs, mat, False); seat['part_label'] = L_SEAT; hosts.append(seat.name)
    outs = alk_outward(pts); oring = [(x + o.x * E, y + o.y * E) for (x, y), o in zip(pts, outs)]
    xfree = P['seat_front'] - 0.13
    front = [(x, y, z + E) for (x, y), z, (px, py) in zip(oring, zt_, pts) if px > xfree]
    tagged_line(K, 'seat_front_edge', front, L_SEAT, 6, False)
    (xa_, ya_), (xb_, yb_) = [tuple(map(float, e)) for e in ends]
    tagged_line(K, 'seat_crease', [(xa_ + (xb_ - xa_) * q / 12, ya_ + (yb_ - ya_) * q / 12, P['seat_z'] + E) for q in range(13)], L_SEAT, SMALL_INK, False)
    if posts:                                         # v23: all four legs one shape (owner), in cg_legs' fixed vertex order
        # v24 (review v23): ink the crease each side shows (near: the corner between the lit side and the dotted
        # front; far: the front flange's inner edge); the legs' outer edges are drawn by the outline and the part
        # boundaries already (inking them too doubled those lines to ~6 px)
        def creases(vs_):
            # v26: the L's vertical edges whose two faces both face the camera (a front leg may be turned)
            ring = [(float(v[0]), float(v[1])) for v in vs_[:6]]; n = 6
            area = sum(ring[k][0] * ring[(k + 1) % n][1] - ring[(k + 1) % n][0] * ring[k][1] for k in range(n))
            sgn = 1.0 if area > 0 else -1.0
            def facing(k):                            # the face from vertex k to k+1
                (x0, y0), (x1, y1) = ring[k], ring[(k + 1) % n]; nx, ny = sgn * (y1 - y0), -sgn * (x1 - x0)
                return nx - ny > 1e-9                     # . (1, -1): toward the camera
            return tuple(k for k in range(n) if facing(k) and facing((k - 1) % n))
        legs = [(d['verts'], d['faces'], d['name'], creases(d['verts'])) for d in cg_legs(P)]
        if P.get('front_leg_style') == 'u':
            # v27: the owner's front legs (cg_front_leg_u): the L seen into its corner, the quarter-circle foot pad, the band
            for sy_ in (-1, 1):
                for nm_, vs_, fs_ in cg_front_leg_u(P, sy_):
                    vl_ = [tuple(map(float, v)) for v in vs_]
                    lab_ = L_BACK if P.get('front_leg_shell_label', 0) else L_LEGS   # one moulding with the arm it bends from
                    ob_ = mesh(K, nm_, vl_, fs_, mat, False); ob_['part_label'] = lab_; hosts.append(ob_.name)
                    if nm_.startswith('front_foot'):
                        q_ = Vector(vl_[len(vl_) // 2]); a_ = Vector(vl_[len(vl_) // 2 + 1]); b_ = Vector(vl_[-1])
                        for tip, tag in ((a_, 'x'), (b_, 'y')):
                            tagged_line(K, '%s_edge_%s' % (nm_, tag), [tuple(q_ + Vector((0, 0, E))), tuple(tip + Vector((0, 0, E)))], lab_, 6, False)
                        continue
                    nring = 6 if nm_.startswith('front_leg') else 4; nr_ = len(vl_) // nring
                    ring0 = [(v[0], v[1]) for v in vl_[:nring]]; outs_ = alk_outward(ring0)
                    area_ = sum(ring0[k][0] * ring0[(k + 1) % nring][1] - ring0[(k + 1) % nring][0] * ring0[k][1] for k in range(nring))
                    sg_ = 1.0 if area_ > 0 else -1.0
                    def face_ok(k):
                        (x0_, y0_), (x1_, y1_) = ring0[k], ring0[(k + 1) % nring]; return sg_ * (y1_ - y0_) + sg_ * (x1_ - x0_) > 1e-9
                    for k in range(nring):
                        if not (face_ok(k) and face_ok((k - 1) % nring)):
                            continue
                        off = Vector((outs_[k].x * E, outs_[k].y * E, 0.0))
                        tagged_line(K, '%s_edge%d' % (nm_, k), [tuple(Vector(vl_[r_ * nring + k]) + off) for r_ in range(nr_)], lab_, 6, False)
    else:
        legs = [(vs, fs, 'back_leg_' + nm, (0, 1, 5)) for (vs, fs), nm in zip(cg_back_legs(P), ('left', 'right'))]
    for vs, fs, name, inked in legs:
        vl = [tuple(map(float, v)) for v in vs]
        ob = mesh(K, name, vl, fs, mat, False); ob['part_label'] = L_LEGS; hosts.append(ob.name)
        top2 = [(v[0], v[1]) for v in vl[:6]]; outs = alk_outward(top2); nr = len(vl) // 6
        for k, o in enumerate(outs):
            if k not in inked:                       # v12: the corner and the side flange's back end only
                continue
            off = Vector((o.x * E, o.y * E, 0.0))    # v22: through every ring (the leg's width profile)
            pts = [Vector(vl[r * 6 + k]) + off for r in range(nr)]; pts[-1] = pts[-1] + Vector((0, 0, E))
            tagged_line(K, '%s_edge%d' % (name, k), [tuple(p) for p in pts], L_LEGS, 6, False)
        foot2 = [(v[0], v[1]) for v in vl[-6:]]; outs = alk_outward(foot2)
        tagged_line(K, name + '_foot', [(x + o.x * E, y + o.y * E, E) for (x, y), o in zip(foot2, outs)], L_LEGS, 6, True)['ink_width'] = 0
    for i, (sy, cl, wd, th) in enumerate(cg_foot_pads(P)):
        nm = ('rear_foot_hook_%s' % ('left' if sy < 0 else 'right')) if not posts else ('foot_hook_%d' % i)
        hk, hrings, HF = pl_sweep(K, nm, [Vector(tuple(map(float, p))) for p in cl], pl_rrect(wd, th, 0.01, 3), (0, 0, 1), mat, L_LEGS)
        hosts.append(hk.name)
    for sy, vs, fs in cg_skirts(P):
        vl = [tuple(map(float, v)) for v in vs]; nm = 'chair_skirt_%s' % ('left' if sy < 0 else 'right')
        sk = mesh(K, nm, vl, fs, mat, False); sk['part_label'] = L_SEAT; hosts.append(sk.name)
        o = Vector((0.0, sy * E, -E))
        tagged_line(K, nm + '_bottom', [tuple(Vector(vl[0]) + o), tuple(Vector(vl[1]) + o)], L_SEAT, 6, False)
    for sy, vs, fs in cg_fins(P):
        if sy > 0:                                    # v11: the far post's fin only showed as a stub under the seat
            continue
        lab = L_BACK; vl = [tuple(map(float, v)) for v in vs]
        fin = mesh(K, 'front_fin_%s' % ('left' if sy < 0 else 'right'), vl, fs, mat, False); fin['part_label'] = lab; hosts.append(fin.name)
        pa, pb = Vector(vl[0]), Vector(vl[4]); off = Vector((E, sy * E, 0.0))     # v13: the L's corner (the fin's front edge)
        tagged_line(K, 'front_fin_%d_corner' % sy, [tuple(pa + off + Vector((0, 0, 0.08))), tuple(pb + off)], lab, 6, False)
        # one line at the fin's thin back end (v8 drew both of its edges, 7 px apart: a sliver)
        pa, pb = Vector(vl[1]), Vector(vl[5]); off = Vector((-E, sy * E, 0.0))
        tagged_line(K, 'front_fin_%d_outer' % sy, [tuple(pa + off), tuple(pb + off)], lab, 6, False)
        tagged_line(K, 'front_fin_%d_top' % sy, [tuple(Vector(vl[4]) + Vector((0, 0, E))), tuple(Vector(vl[5]) + Vector((0, 0, E))), tuple(Vector(vl[6]) + Vector((0, 0, E)))], lab, 6, False)
    return hosts


# v28 (owner 2026-09-30, a downloaded monobloc: "does it contain a blender friendly file you could use instead?"):
# the chair as that mesh (glTF 2.0, Poly Haven's plastic_monobloc_chair_01; welded into one closed solid,
# monobloc_chair.npz, Blender Z-up, facing -Y), turned square to the grid to face +X and placed on the shipped
# chair by its inked silhouette (gltf_fit/gfit.py, yaw fixed at 90: IoU 0.829)
CHAIR_MESH = dict(use=1, file='monobloc_chair.npz', s=0.9002, yaw=90.0, tx=0.0484, ty=0.0504, sharp=45.0, crease=50.0, min_line=0.02)


def pl_mesh_lines(K, ob, label, crease, name, min_line=0.0, contours=True):
    """Ink a solid's visible creases (both faces toward the camera, bent more than `crease` degrees) and its
    self-occluding contours (one face toward the camera, one away), chained into polylines and lifted toward
    the camera by E (the same place on screen); the exporter's ray test hides what the solids cover."""
    me = ob.data; mw = ob.matrix_world
    V = np.array([(mw @ v.co)[:] for v in me.vertices]); FN = np.array([(mw.to_3x3() @ p.normal).normalized()[:] for p in me.polygons])
    view = np.array(VIEW[:]); front = FN @ view > 0; ef = {}
    for pi, p in enumerate(me.polygons):
        for ek in p.edge_keys:
            ef.setdefault(ek, []).append(pi)
    adj = {}
    for (a, b), fl in ef.items():
        if len(fl) != 2:
            continue
        f1, f2 = fl
        if (contours and front[f1] != front[f2]) or (front[f1] and math.degrees(math.acos(max(-1.0, min(1.0, float(FN[f1] @ FN[f2]))))) > crease):
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
    for pass_ in (0, 1):                              # open chains from their ends and junctions first, then loops
        for v0 in adj:
            if pass_ == 0 and len(adj[v0]) == 2:
                continue
            for w in adj[v0]:
                if frozenset((v0, w)) not in used:
                    chains.append(walk(v0, w))
    def screen_len(ch):                               # length on screen (world units; ~310 px each at 800)
        d = np.diff(V[ch], axis=0); d = d - np.outer(d @ view, view); return float(np.linalg.norm(d, axis=1).sum())
    chains = [ch for ch in chains if screen_len(ch) >= min_line]   # no stray dots from short creases
    lift = view * E
    for k, ch in enumerate(chains):
        ln = tagged_line(K, '%s_line%d' % (name, k), [tuple(map(float, V[i] + lift)) for i in ch], label, 6, False)
        ln['ink_width'] = 0                           # the standard round-jointed interior weight
    return len(chains)


def pl_chair_mesh(K, mat, label):
    C = CHAIR_MESH; Z = np.load(str(here / C['file'])); co, tri = Z['co'], Z['faces']
    a = math.radians(C['yaw']); ca, sa = math.cos(a), math.sin(a); p = co * C['s']
    W = np.column_stack([ca * p[:, 0] - sa * p[:, 1] + C['tx'], sa * p[:, 0] + ca * p[:, 1] + C['ty'], p[:, 2]])
    ob = mesh(K, 'chair_mesh', [tuple(map(float, v)) for v in W], [tuple(map(int, t)) for t in tri], mat, False)
    bm = bmesh.new(); bm.from_mesh(ob.data)
    for e in bm.edges:                                # smooth shading, split at the moulding's hard edges
        e.smooth = not (len(e.link_faces) == 2 and math.degrees(e.calc_face_angle()) > C['sharp'])
    for f in bm.faces:
        f.smooth = True
    bm.to_mesh(ob.data); bm.free(); ob.data.update(); noink(ob); ob['part_label'] = label
    bpy.context.view_layer.update()
    n = pl_mesh_lines(K, ob, label, C['crease'], 'chair', C['min_line'])
    return [ob.name], n


# ---------------------------------------------------------------- the bottle
def pl_bottle(K, body_m, cap_m, label):
    """v6: the bottle fitted to the shipped bottle's silhouette (plastics/fit/bottle_fit.py, IoU 0.98): a
    rounded foot pinched into five petals (one facing the viewer), a straight body, a near-conical
    shoulder up to a short cap; three ring lines on the body where the shipped bottle has them."""
    B = BOTTLE; R, H, hc, rc, zs0, p, rb = B['R'], B['H'], B['hc'], B['rc'], B['zs0'], B['p'], B['rb']
    cx, cy = B['bx'], B['by']; zc0 = H - hc; rn = rc - 0.003
    prof = [(0.0, 0.0)]
    for k in range(9):
        a = math.pi / 2 * (1 - k / 8); prof.append((R - rb + rb * math.cos(a), rb - rb * math.sin(a)))
    for k in range(1, 12):
        prof.append((R, rb + (zs0 - rb) * k / 11))
    for k in range(1, 25):
        u = k / 24; prof.append((rn + (R - rn) * max(0.0, 1 - u ** p) ** (1 / p), zs0 + (zc0 - zs0) * u))
    prof += [(rn, zc0 + 0.004), (0.0, zc0 + 0.004)]
    body = pw_lathe_z(K, 'bottle', prof, body_m, (cx, cy), 120); body['part_label'] = label
    for v in body.data.vertices:                  # the petal base
        z = v.co.z
        if z < B['zf']:
            dx, dy = v.co.x - cx, v.co.y - cy; r = math.hypot(dx, dy)
            if r > 1e-6:
                th = math.atan2(dy, dx); s_ = 1 - z / B['zf']
                k = 1 - B['pinch'] * s_ * (0.5 - 0.5 * math.cos(5 * (th + math.pi / 4)))
                v.co.x = cx + dx * k; v.co.y = cy + dy * k
    cap = pw_lathe_z(K, 'bottle_cap', [(0.0, zc0), (rc, zc0), (rc, H), (0.0, H)], cap_m, (cx, cy), 72)
    cap['part_label'] = 7
    for k, z in enumerate(BOTTLE_RINGS):
        pw_circle_z(K, 'bottle_ring%d' % k, (cx, cy), z, R + E, label, SMALL_INK)
    pw_circle_z(K, 'bottle_cap_rim', (cx, cy), H, rc + E, 7, SMALL_INK)
    # the petal base's two front notches (as shipped): an arch over each valley between the lobes that
    # face the viewer (the lobes sit at -45 deg + 72k, so the valleys either side of the front one)
    def surf(th, z):
        r = R if z >= rb else R - rb + math.sqrt(max(0.0, rb * rb - (rb - z) ** 2))
        s_ = max(0.0, 1 - z / B['zf']); k = 1 - B['pinch'] * s_ * (0.5 - 0.5 * math.cos(5 * (th + math.pi / 4)))
        return (cx + (r * k + E) * math.cos(th), cy + (r * k + E) * math.sin(th), z)
    for j, thv in enumerate((math.radians(-81), math.radians(-9))):
        pts = [surf(thv + math.radians(17) * math.cos(math.pi * q / 16), 0.004 + 1.5 * B['zf'] * math.sin(math.pi * q / 16)) for q in range(17)]
        tagged_line(K, 'bottle_petal%d' % j, pts, label, SMALL_INK, False)
    return body, cap


# ---------------------------------------------------------------- the bag and pellets
def pl_bag(K, mat, pellet_m, label):
    """v6: the bag fitted to the shipped bag's silhouette (plastics/fit/bag_fit.py): a soft body (a thin
    closed film), the mouth sagging at the front, two handle loops as bands in planes facing the viewer,
    creases, and the heap of pellets. v29-32 (owner: the left handle "doesnt meet the front face"; the nurdles
    "look suspended, add more underneath, using the same technique used in the alumina bag"): the left loop
    runs across the mouth's left end, its legs rising out of the front lip and the bag's rounded end; the
    right loop's outer leg rises out of the front lip; the pellets fill the mouth down past the lip, packed
    nearest first on screen, over a core in the beads' shaded tone."""
    G = BAG; H, W, D = G['H'], G['W'], G['D']; yaw = math.radians(G['yaw'])
    Rz = Matrix.Rotation(yaw, 3, 'Z'); O = Vector((G['bx'], G['by'], 0.0))
    def place(x, y, z):                            # bag local: x across its width, y through its depth
        return tuple(O + Rz @ Vector((x, y, z)))
    rows, cols = 40, 72; pe = G['pe']

    def a(t):                                      # v13: smooth (no clamped sine: its kink drew a hard shade edge)
        return W / 2 * (1 + G['bulge'] * math.sin(math.pi * t) ** 0.8 - G['neck'] * max(0, t - 0.6) / 0.4)

    def b(t):
        return D / 2 * (0.75 + G['bb'] * math.sin(math.pi * t) ** 0.8 - G['bn'] * max(0, t - 0.55) / 0.45)

    def sec(t, th):
        c, s = math.cos(th), math.sin(th)
        return (a(t) * math.copysign(abs(c) ** (2 / pe), c), b(t) * math.copysign(abs(s) ** (2 / pe), s))

    def lip_profile(xs, zs, x):                   # piecewise linear in the bag's local x
        if x <= xs[0]: return zs[0]
        for i in range(len(xs) - 1):
            if x <= xs[i + 1]:
                f = (x - xs[i]) / (xs[i + 1] - xs[i]); return zs[i] + (zs[i + 1] - zs[i]) * f
        return zs[-1]

    def rim_z(th):
        # v16: the lips read off the shipped bag (back-projected): the back film stands high in the middle and falls
        # under the right loop (its hole stays clear), the front lip sags to ~0.8
        if G.get('lips'):
            x = a(1.0) * math.copysign(abs(math.cos(th)) ** (2 / pe), math.cos(th)); fr = G['lips']
            zb_ = lip_profile(fr['x'], fr['back'], x); zf_ = lip_profile(fr['x'], fr['front'], x)
            s_ = math.sin(th); w = max(0.0, s_) ** 0.6; wf = max(0.0, -s_) ** 0.6
            side = lip_profile(fr['x'], fr['side'], x)
            return side + (zb_ - side) * w + (zf_ - side) * wf
        return H * (1 - G['s1'] * abs(math.sin(th)) ** G.get('sq', 1.0) - G['s2'] * max(0.0, -math.sin(th)) ** 1.5
                    - G.get('s3', 0.0) * max(0.0, math.sin(th)) ** 2)
    FILM = 0.012
    vs = []; fs = []
    def ring(t, inset, zlift):
        out = []
        for k in range(cols):
            th = 2 * math.pi * k / cols; x, y = sec(t, th)
            if inset:
                nrm = Vector((x / max(a(t), 1e-6) ** 2, y / max(b(t), 1e-6) ** 2, 0.0)).normalized()
                x, y = x - nrm.x * inset, y - nrm.y * inset
            z = zlift + t * rim_z(th) * (1 - zlift / H)
            out.append(place(x, y, z))
        return out
    outer = [ring(j / rows, 0.0, 0.0) for j in range(rows + 1)]
    inner = [ring(j / rows, FILM, FILM) for j in range(rows + 1)]
    for grid in (outer, inner):
        for rr in grid:
            vs.extend(rr)
    oi = lambda j, k: j * cols + (k % cols)
    ii = lambda j, k: (rows + 1) * cols + j * cols + (k % cols)
    for j in range(rows):
        for k in range(cols):
            fs.append((oi(j, k), oi(j, k + 1), oi(j + 1, k + 1), oi(j + 1, k)))
            fs.append((ii(j, k), ii(j + 1, k), ii(j + 1, k + 1), ii(j, k + 1)))
    for k in range(cols):
        fs.append((oi(rows, k), oi(rows, k + 1), ii(rows, k + 1), ii(rows, k)))
    fs.append(tuple(oi(0, k) for k in reversed(range(cols))))
    fs.append(tuple(ii(0, k) for k in range(cols)))
    body = mesh(K, 'bag', vs, fs, mat, False); body['part_label'] = label
    for poly in body.data.polygons:
        poly.use_smooth = True
    bm_ = bmesh.new(); bm_.from_mesh(body.data)          # v32: split at the lip (its smoothed normals lit a pale band)
    for e_ in bm_.edges:
        e_.smooth = not (len(e_.link_faces) == 2 and math.degrees(e_.calc_face_angle()) > 50.0)
    bm_.to_mesh(body.data); bm_.free(); body.data.update(); noink(body)
    def film_at(th):                               # v30: the film at the lip: mid-surface point, outward normal (bag local)
        x, y = sec(1.0, th)
        g = Vector((math.copysign(abs(x / a(1.0)) ** (pe - 1), x) / a(1.0), math.copysign(abs(y / b(1.0)) ** (pe - 1), y) / b(1.0), 0.0)).normalized()
        return Vector((x, y, 0.0)) - g * (FILM / 2), g
    def th_front(x):
        u = max(-0.999, min(0.999, x / a(1.0))); c_ = math.copysign(abs(u) ** (pe / 2), u); return -math.acos(c_)
    def scr_x(x, y):
        return Vector(place(x, y, 0.0)).dot(RIGHT)
    u0, u1 = -0.15 * math.pi, 1.15 * math.pi; COS0 = math.cos(u0)
    def loop_frame(side, key):
        """(centre x, y, psi, rxm, legs) of a loop; legs: [(dx, local base point, base normal or None, base z)]"""
        w = G[key + '_w']
        if not G.get(key + '_diag'):
            cxl = side * a(1.0) * G[key + '_c']; rxm = G[key + '_rx'] - w / 2; psi = math.radians(G[key + '_psi']); y0 = G[key + '_y']
            legs = []
            for dx in (rxm * COS0, -rxm * COS0):
                bx_, by_ = cxl + dx * math.cos(psi), y0 + dx * math.sin(psi)
                if G.get(key + '_outer_lip') and side * dx > 0:   # v32: the outer leg rises out of the front lip
                    th_l = th_front(bx_); legs.append((dx, Vector((bx_, by_, 0.0)), film_at(th_l)[1], rim_z(th_l) - 0.01))
                else:
                    legs.append((dx, Vector((bx_, by_, 0.0)), None, rim_z(th_front(bx_)) - 0.14))
            return cxl, y0, psi, rxm, legs
        th_i = th_front(G[key + '_in']); Pi, ni = film_at(th_i)          # the inner leg, in the front film
        th_o = math.pi if side < 0 else 0.0; Po, no = film_at(th_o)       # v31: the outer leg, in the bag's end
        mid = (Pi + Po) / 2; d = (Pi - Po).normalized(); psi = math.atan2(d.y, d.x)   # +dx runs to the inner leg
        rxm = (Pi - Po).length / 2 / COS0
        legs = [(rxm * COS0, Pi, ni, rim_z(th_i) - 0.01), (-rxm * COS0, Po, no, rim_z(th_o) - 0.01)]
        return mid.x, mid.y, psi, rxm, legs
    frames = {side: loop_frame(side, key) for side, key in ((-1, 'hL'), (1, 'hR'))}
    feet = []                                      # (plan segment p0, p1, half thickness): where a leg meets the lip
    scr_cut = {}                                   # v31: the screen x past which the front lip stops, at each end
    for side, key in ((-1, 'hL'), (1, 'hR')):
        cxl, y0, psi, rxm, legs = frames[side]; w = G[key + '_w']; u_ = Vector((math.cos(psi), math.sin(psi), 0.0))
        for dx, P, nf, zb in legs:
            along = Vector((-nf.y, nf.x, 0.0)) if nf is not None else u_
            feet.append((P - along * (w / 2), P + along * (w / 2), 0.006))
        if not G.get(key + '_diag'):               # the outer leg stands on the outline: the lip ends at its inner edge
            dx, P, nf, zb = max(legs, key=lambda l: side * l[1].x)
            al_ = Vector((-nf.y, nf.x, 0.0)) if nf is not None else u_          # v32: a twisted foot follows the film
            e_ = min((P - al_ * (w / 2), P + al_ * (w / 2)), key=lambda q: side * q.x)
            scr_cut[side] = scr_x(e_.x, e_.y)
    def on_foot(x, y, m):
        q = Vector((x, y, 0.0))
        for p0, p1, ht in feet:
            v = p1 - p0; f = max(0.0, min(1.0, (q - p0).dot(v) / v.dot(v)))
            if (q - (p0 + v * f)).length < ht + m:
                return True
        return False
    for nm, t0, t1 in (('front', -math.pi + 0.05, -0.05), ('back', 0.45, math.pi - 0.45)):
        runs = [[]]
        for q in range(161):
            th = t0 + (t1 - t0) * q / 160; x_, y_ = sec(1.0, th)
            cut = nm == 'front' and any(side * (scr_x(x_, y_) - c_) > -0.002 for side, c_ in scr_cut.items())
            if cut or on_foot(x_, y_, 0.004 + E):  # v29-31: the lip line stops at a leg rising out of the film
                if runs[-1]:
                    runs.append([])
                continue
            runs[-1].append(place(x_, y_, rim_z(th) + E))
        for r_, run in enumerate([r for r in runs if len(r) > 1]):
            tagged_line(K, 'bag_lip_%s%s' % (nm, '' if r_ == 0 else r_), run, label, 6, False)
    hosts = [body.name]
    # the handles: bands on ellipses in vertical planes turned psi about the vertical; v30: the left loop's inner leg
    # twists out of the front film (pl_sweep_n), its outer leg stands on the outline and goes down into the pellets
    zr = (H - 0.02) if G.get('shoulders', 0) else (H * (1 - G['s1']) - 0.02)
    leg_boxes = []
    for side, key, nm in ((-1, 'hL', 'left'), (1, 'hR', 'right')):
        cxl, y0, psi, rxm, legs = frames[side]; w = G[key + '_w']
        rzm = G[key + '_rz'] - w / 2; zc = zr + G[key + '_z']
        def lp(dx, z):
            return Vector(place(cxl + dx * math.cos(psi), y0 + dx * math.sin(psi), z))
        n = 48
        arc = [lp(rxm * math.cos(u0 + (u1 - u0) * q / n), zc + rzm * math.sin(u0 + (u1 - u0) * q / n)) for q in range(n + 1)]
        nl = Vector((-math.sin(psi), math.cos(psi), 0.0))                # the loop plane's normal (bag local)
        (dxa, Pa, na, za), (dxb, Pb, nb, zb) = legs                     # legs[0] at the arc's start (u0), legs[1] at its end
        m_ = 8
        start = [lp(dxa, za + (arc[0].z - za) * q / m_) for q in range(m_)] if arc[0].z > za else []
        end = [lp(dxb, arc[-1].z + (zb - arc[-1].z) * q / m_) for q in range(1, m_ + 1)] if arc[-1].z > zb else []
        path = start + arc + end
        def twist(nf, f):                          # the normal f of the way from the film's to the loop's
            if nf is None:
                return nl
            nf_ = nf if nf.dot(nl) >= 0 else -nf; return (nf_ * (1 - f) + nl * f).normalized()
        nrm_l = [twist(na, pl_smooth(q / max(len(start) - 1, 1))) for q in range(len(start))] + [nl] * len(arc) + \
                [twist(nb, pl_smooth(1 - q / max(len(end), 1))) for q in range(1, len(end) + 1)]
        normals = [Rz @ v for v in nrm_l]
        twisted = any(l[2] is not None for l in legs)
        th_ = FILM + 0.002 if twisted else 0.012       # v32: a leg rising out of the film takes in the rim's top face
        hb, rings = pl_sweep_n(K, 'bag_handle_%s' % nm, path, normals, pl_rrect(w, th_, 0.005, 3), mat, label)
        hosts.append(hb.name)
        for dx, P, nf, zb_ in legs:                # v29-30: the legs, for keeping the pellets off them
            u_ = Vector((math.cos(psi), math.sin(psi), 0.0)) if nf is None else Vector((-nf.y, nf.x, 0.0))
            leg_boxes.append((P.x, P.y, u_.x, u_.y, w / 2, th_ / 2))
            if nf is not None:                     # and the twisted leg's top, in the loop plane
                leg_boxes.append((P.x, P.y, math.cos(psi), math.sin(psi), w / 2, th_ / 2))
        for e, (qa, qb) in enumerate(((15, 0), (7, 8))):
            pts = []
            for rr in rings:
                c = sum(rr, Vector()) / len(rr); pp = (rr[qa] + rr[qb]) / 2; pts.append(tuple(pp + (pp - c).normalized() * E))
            tagged_line(K, 'bag_handle_%s_edge%d' % (nm, e), pts, label, 6, False)
    # creases on the front (3 px)
    for name, cpts in BAG_CREASES.items():
        if name == 'left' and G.get('hL_diag'):     # v31: from the left outer leg's inner edge at the lip
            Po_ = frames[-1][4][1][1]; y_e = Po_.y - G['hL_w'] / 2
            th_e = -(math.pi - math.asin(min(1.0, (abs(y_e) / b(1.0)) ** (pe / 2))))
            cpts = [(1.0, th_e)] + [c for c in cpts[1:] if c[1] > th_e or c[0] < 0.95]
        pts = []
        for (t0, th0), (t1, th1) in zip(cpts, cpts[1:]):
            if th1 - th0 > math.pi: th1 -= 2 * math.pi
            if th0 - th1 > math.pi: th1 += 2 * math.pi
            for q in range(6):
                f = q / 6; t = t0 + (t1 - t0) * f; th = th0 + (th1 - th0) * f
                x, y = sec(t, th); nrm = Vector((x / max(a(t), 1e-6) ** 2, y / max(b(t), 1e-6) ** 2, 0)).normalized()
                pts.append(place(x + nrm.x * 0.004, y + nrm.y * 0.004, t * rim_z(th)))
        t, th = cpts[-1]; x, y = sec(t, th); nrm = Vector((x / max(a(t), 1e-6) ** 2, y / max(b(t), 1e-6) ** 2, 0)).normalized()
        pts.append(place(x + nrm.x * 0.004, y + nrm.y * 0.004, t * rim_z(th)))
        tagged_line(K, 'bag_crease_' + name, pts, label, SMALL_INK, False)
    # pellets (v16, as shipped): a jittered mound centred right of the mouth's middle (top ~0.945 at mid-depth) and a
    # small pocket under the left loop, under the back film's lip; the top course placed front to back in screen space
    # so that each pellet shows at least most of its disc (no slivers)
    # v29 (owner: "the nurdles look suspended, add more underneath, using the same technique used in the alumina bag"):
    # under the heap the mouth is filled to fill_dz pellet radii off the front lip (the lip cuts across the front
    # beads, as the alumina sack's rim does), and fill_courses courses sit under the top one, each a grid offset half a
    # step and pulled in from the film (alumina's pellet_cluster), so the gaps between the top beads show beads
    import random; rnd = random.Random(31)
    M = G['heap']; R_ = PELLET_R
    mA, mB = a(1.0) - FILM - R_ * 1.03, b(1.0) - FILM - R_ * 1.03      # the mouth, inside the film (v32: 1.15 -> 1.03)
    def surf(x, y):
        best = -1.0
        for (cx, cz, rx_, ry_) in M:
            d2 = ((x - cx) / rx_) ** 2 + (y / ry_) ** 2
            if d2 < 1:
                best = max(best, cz - (cz - 0.70) * d2 ** 1.2 * 0.6)
        return best
    def top_z(x, y):
        z = surf(x, y)
        if G.get('fill_dz') is not None and G.get('lips'):
            base = lip_profile(G['lips']['x'], G['lips']['front'], x) + G['fill_dz'] * R_
            z = max(z, base)
            # v31: the pile slopes down to the front lip, as pellets resting against the film would (v30 left the heap's
            # front edge standing above the lip, and the beads under it only showed as shards); the fitted peak stays
            y_fi = -mB * max(0.0, 1 - (abs(x) / mA) ** pe) ** (1 / pe)
            z = min(z, base + max(0.0, y - y_fi) * G.get('fill_slope', 1.5))
        return z
    def in_mouth(x, y, m=0.0):
        ai, bi = mA - m, mB - m
        return ai > 0 and bi > 0 and (abs(x) / ai) ** pe + (abs(y) / bi) ** pe <= 1.0
    def on_leg(x, y, m=0.0):
        for (lx, ly, ux, uy, hw, ht) in leg_boxes:
            dx, dy = x - lx, y - ly
            if abs(dx * ux + dy * uy) < hw + R_ + m and abs(-dx * uy + dy * ux) < ht + R_ + m:
                return True
        return False
    def back_cap(x, z):                                # under the back film's lip
        u = max(-0.999, min(0.999, x / a(1.0))); c_ = math.copysign(abs(u) ** (pe / 2), u)
        return min(z, rim_z(math.acos(max(-1.0, min(1.0, c_)))) - R_ * 1.2)
    base_of = lambda x: lip_profile(G['lips']['x'], G['lips']['front'], x) + G['fill_dz'] * R_
    # v30-31: a core under the pellets, out to the film, in the pellets' shade tone with its dots, so a gap between beads
    # shows more pellet in shadow, not the bag's inside
    zc_of = lambda x: base_of(x) - (G.get('fill_courses', 1) + 1) * 1.3 * R_ - 0.3 * R_
    cvs = []; nr_ = 6; ncol = 96
    for q in range(ncol):
        th = 2 * math.pi * q / ncol; x_, y_ = sec(1.0, th)
        for _ in range(4):                             # the wall's section at the core's height there
            t_ = max(0.05, min(1.0, zc_of(x_) / max(rim_z(th), 1e-6))); x_, y_ = sec(t_, th)
            g_ = Vector((x_ / max(a(t_), 1e-6) ** 2, y_ / max(b(t_), 1e-6) ** 2, 0.0)).normalized()
            x_, y_ = x_ - g_.x * (FILM + 0.002), y_ - g_.y * (FILM + 0.002)
        for r in range(1, nr_ + 1):
            xr, yr = x_ * r / nr_, y_ * r / nr_; cvs.append(place(xr, yr, zc_of(xr)))
    cvs.append(place(0.0, 0.0, zc_of(0.0)))
    cfs = [(cols_ * nr_ + r, ((cols_ + 1) % ncol) * nr_ + r, ((cols_ + 1) % ncol) * nr_ + r + 1, cols_ * nr_ + r + 1)
           for cols_ in range(ncol) for r in range(nr_ - 1)]
    cfs += [(ncol * nr_, ((cols_ + 1) % ncol) * nr_, cols_ * nr_) for cols_ in range(ncol)]
    core_m = pl_toon('pl_pellet_core', (224, 220, 200), (224, 220, 200), (224, 220, 200))   # v32: the beads' own shaded tone
    core = mesh(K, 'pellet_core', [tuple(map(float, v)) for v in cvs], cfs, core_m, False); core['part_label'] = label
    for poly in core.data.polygons:
        poly.use_smooth = True
    occ_ = core.data.attributes.new('icon_shade_occlusion', 'FLOAT', 'POINT')   # its dots: the one-dot band (mask ~0.74)
    for d_ in occ_.data:
        d_.value = 0.17
    # v31 (reviews v29-30: suspended, then crumbs and shards): the pellets fill the mouth from the fitted heap down past
    # the lip, packed as alumina's courses are but chosen on screen: candidates through the fill, nearest first; a bead
    # stays if its largest clean piece (not under a bead in front, that bead's 3 px outline included, nor under the film
    # or a strap) is at least half its disc and holds a 3 px circle at 800 px (a third, where it is the lip or a strap
    # that cuts it); beads may sink into each other a little, as alumina's do
    from mathutils.bvhtree import BVHTree
    PXU = 310.0                                        # ~px per world unit at 800 px
    INFL = 1.0 + (E + 1.5 / PXU) / R_                  # a bead in front covers out to its outline's outer edge
    OWN = 1.0 + (E - 1.5 / PXU) / R_                   # a bead's own cream ends at its outline's inner edge
    ST = 0.25; ij = [(i, j) for i in range(-4, 5) for j in range(-4, 5) if (i * i + j * j) * ST * ST <= OWN * OWN]
    lat = np.array(ij, float) * ST; at = {c: n for n, c in enumerate(ij)}
    vs_, fs_ = [], []
    for o_ in K.col.objects:                           # the film, the straps, the chair, the bottle
        if o_.type != 'MESH' or o_.get('edge_ink') or o_.name.startswith('pellet'):
            continue
        mw_ = o_.matrix_world; off_ = len(vs_); vs_.extend(mw_ @ v.co for v in o_.data.vertices)
        fs_.extend(tuple(off_ + i for i in p.vertices) for p in o_.data.polygons)
    tree = BVHTree.FromPolygons(vs_, fs_)
    strap_faces = set()                                # v32: faces of the straps, whose cut counts as a bead's
    off_ = 0
    for o_ in K.col.objects:
        if o_.type != 'MESH' or o_.get('edge_ink') or o_.name.startswith('pellet'):
            continue
        if o_.name.startswith('bag_handle'):
            strap_faces.update(range(off_, off_ + len(o_.data.polygons)))
        off_ += len(o_.data.polygons)
    # v33 (review v32): every visible piece of a bead must hold a 3 px circle, not just its largest (no tips split off
    # by an outline in front); the row along the walls is checked again once the beads in front of it are in; bead
    # sizes vary a little (bead_jitter) so the scallops don't line up in rows
    cands = []
    for _ in range(G.get('fill_samples', 30000)):
        x = rnd.uniform(-mA, mA); y = rnd.uniform(-mB, mB)
        if not in_mouth(x, y) or on_leg(x, y):
            continue
        zt = back_cap(x, top_z(x, y)); zb = base_of(x) - 1.3 * R_
        p = Vector(place(x, y, max(zb, zt - abs(rnd.gauss(0.0, 1.2 * R_)))))
        cands.append((p.dot(VIEW), p, R_ * (1 + rnd.uniform(-1, 1) * G.get('bead_jitter', 0.06))))
    cands.sort(key=lambda t: -t[0])                  # nearest the camera first
    COVER = E + 1.5 / PXU                              # a bead covers out to its outline's outer edge (r + COVER)
    k = 0; g2, g3 = {}, {}; c2, c3 = 2.7 * R_, 2.4 * R_; beads_ = {}
    def bead(p, r, wall_=False):
        nonlocal k
        nm_ = 'pellet%d' % k
        ob_ = fz_sphere(K, nm_, p, r, pellet_m, label); ob_['course'] = 1 if wall_ else 0; ob_['centre'] = tuple(p)
        tagged_line(K, nm_ + '_rim', fz_circle(p, r + E, 32), label, SMALL_INK, True)
        sx, sy = p.dot(RIGHT), p.dot(UP)
        g2.setdefault((int(sx // c2), int(sy // c2)), []).append((sx, sy, p.dot(VIEW), r))
        g3.setdefault((int(p.x // c3), int(p.y // c3), int(p.z // c3)), []).append((p, r)); beads_[nm_] = (p, r)
        k += 1
    def crowded(p, r):                                 # sink into a bead a radius nearer or farther, not one beside it
        k3 = (int(p.x // c3), int(p.y // c3), int(p.z // c3))
        for a_ in (-1, 0, 1):
            for b_ in (-1, 0, 1):
                for d_ in (-1, 0, 1):
                    for q, rq in g3.get((k3[0] + a_, k3[1] + b_, k3[2] + d_), ()):
                        d3 = (p - q).length; rs = (r + rq) / 2
                        if d3 < 1.55 * rs or (abs((p - q).dot(VIEW)) < rs and d3 < 2.25 * rs):
                            return True
        return False
    def health(p, r):
        """(ok, n clean samples): the bead's clean pieces, against the beads nearer the camera (their outlines in),
        the film and the straps; ok if the largest is half the disc (a third where only the lip cuts it) and every
        piece holds a 3 px circle"""
        sx, sy, depth = p.dot(RIGHT), p.dot(UP), p.dot(VIEW); k2 = (int(sx // c2), int(sy // c2))
        near = [(qx, qy, rq) for a_ in (-1, 0, 1) for b_ in (-1, 0, 1)
                for qx, qy, qd, rq in g2.get((k2[0] + a_, k2[1] + b_), ()) if qd > depth + 1e-9]
        if any((sx - qx) ** 2 + (sy - qy) ** 2 < (0.9 * r) ** 2 for qx, qy, rq in near):
            return False, 0
        Px, Py = sx + lat[:, 0] * r, sy + lat[:, 1] * r
        by_bead = np.zeros(len(lat), bool)
        for qx, qy, rq in near:
            by_bead |= (Px - qx) ** 2 + (Py - qy) ** 2 < (rq + COVER) ** 2
        clear = ~by_bead
        for n_ in np.where(clear)[0]:
            u_, v_ = lat[n_]
            q_ = p + (RIGHT * u_ + UP * v_) * r + VIEW * (r * math.sqrt(max(0.0, 1 - u_ * u_ - v_ * v_)) + 1e-4)
            hit_ = tree.ray_cast(q_, VIEW, 60.0)
            if hit_[0] is not None:
                clear[n_] = False
                if hit_[2] in strap_faces:
                    by_bead[n_] = True
        comps, seen_ = [], set()
        for n0 in np.where(clear)[0]:
            if n0 in seen_:
                continue
            comp, st = [], [n0]; seen_.add(n0)
            while st:
                n_ = st.pop(); comp.append(n_); i_, j_ = ij[n_]
                for c_ in ((i_ + 1, j_), (i_ - 1, j_), (i_, j_ + 1), (i_, j_ - 1)):
                    m_ = at.get(c_)
                    if m_ is not None and clear[m_] and m_ not in seen_:
                        seen_.add(m_); st.append(m_)
            comps.append(comp)
        if not comps:
            return False, 0
        own = (r + E - 1.5 / PXU) / r
        def r_in(comp):
            inb = np.zeros(len(lat), bool); inb[comp] = True; B_, O_ = lat[inb], lat[~inb]
            d_ = own - np.hypot(B_[:, 0], B_[:, 1])
            if len(O_):
                d_ = np.minimum(d_, np.sqrt(((B_[:, None, :] - O_[None, :, :]) ** 2).sum(-1)).min(1) - ST / 2)
            return float(d_.max()) * r * PXU
        best = max(comps, key=len); f = len(best) / len(lat)
        if not (f >= 0.5 or (f >= 0.33 and by_bead.mean() <= 0.12)):
            return False, int(clear.sum())
        return all(r_in(c_) >= 3.0 for c_ in comps), int(clear.sum())
    # v32: the pile ends in crowns against the walls (review v31: a wedge of core between the pile and the back wall)
    wall = []
    for q in range(720):
        th = 2 * math.pi * q / 720
        if math.sin(th) < -0.35:                     # not along the front, where the lip hides them
            continue
        c_, s_ = math.cos(th), math.sin(th)
        x = math.copysign(abs(c_) ** (2 / pe), c_) * mA; y = math.copysign(abs(s_) ** (2 / pe), s_) * mB
        if wall and math.hypot(x - wall[-1][0], y - wall[-1][1]) < 2.3 * R_:
            continue
        if not on_leg(x, y):
            wall.append((x, y))
    wall_names = []
    for x, y in wall:
        p = Vector(place(x, y, back_cap(x, top_z(x, y)))); r = R_ * (1 + rnd.uniform(-1, 1) * G.get('bead_jitter', 0.06))
        if not crowded(p, r):
            wall_names.append('pellet%d' % k); bead(p, r, True)
    for depth, p, r in cands:
        if crowded(p, r):
            continue
        ok, _ = health(p, r)
        if ok:
            bead(p, r)
    def unplace(nm_):
        p, r = beads_.pop(nm_); sx, sy = p.dot(RIGHT), p.dot(UP)
        l2 = g2[(int(sx // c2), int(sy // c2))]; l2[:] = [t for t in l2 if (Vector((t[0], t[1], 0)) - Vector((sx, sy, 0))).length > 1e-9]
        l3 = g3[(int(p.x // c3), int(p.y // c3), int(p.z // c3))]; l3[:] = [t for t in l3 if (t[0] - p).length > 1e-9]
        for o_nm in (nm_, nm_ + '_rim'):
            o_ = bpy.data.objects.get(o_nm)
            if o_ is not None:
                bpy.data.objects.remove(o_, do_unlink=True)
    for nm_ in wall_names:                             # v33: the wall row against the beads now in front of it; a bead
        p, r = beads_[nm_]; ok, _ = health(p, r)       # left as tips is nudged up or inward until its pieces are whole
        if ok:
            continue
        unplace(nm_); lx_ = Vector(place(0.0, 0.0, 0.0)); inward = (lx_ - p); inward.z = 0.0; inward.normalize()
        for dz, din in ((0.5, 0.0), (0.9, 0.0), (0.5, 0.3), (0.9, 0.3), (0.0, 0.3), (0.3, 0.6)):
            q = p + Vector((0.0, 0.0, dz * R_)) + inward * (din * R_)
            ql = Rz.inverted() @ (q - O)
            if q.z > back_cap(ql.x, 10.0) + 1e-6 or not in_mouth(ql.x, ql.y) or on_leg(ql.x, ql.y):
                continue                               # under the back film's lip, inside the mouth, off the straps
            if not crowded(q, r) and health(q, r)[0]:
                bead(q, r, True); break
    k = sum(1 for o_ in K.col.objects if o_.name.startswith('pellet') and o_.get('course') is not None)
    n_top = k
    print('pellets: %d top, %d under' % (n_top, k - n_top))
    return hosts, k


def fz_sphere(K, name, c, r, mat, label):
    bm = bmesh.new(); bmesh.ops.create_uvsphere(bm, u_segments=24, v_segments=12, radius=r)
    bmesh.ops.translate(bm, vec=Vector(c), verts=bm.verts)
    me = bpy.data.meshes.new(name); bm.to_mesh(me); bm.free()
    ob = noink(K.obj(name, me, mat, True)); ob['part_label'] = label
    for p in ob.data.polygons:
        p.use_smooth = True
    return ob


def fz_circle(c, r, n=72):
    return [tuple(Vector(c) + (RIGHT * math.cos(t) + UP * math.sin(t)) * r) for t in [2 * math.pi * k / n for k in range(n)]]


def build_plastics():
    """Plastics v1: the shipped chair, bottle and bag of pellets on the grid."""
    setup_icon_rig(); K = Kit(open_collection('ICON_plastics')); hosts = []
    cream_m = pl_toon('pl_cream', (203, 193, 166), (226, 221, 203), (242, 238, 222))
    blue_m = pl_toon('pl_blue', (104, 146, 165), (142, 181, 196), (172, 205, 216))
    pellet_m = pl_toon('pl_pellet', (210, 196, 160), (238, 228, 198), (252, 244, 218))
    L_SEAT, L_BACK, L_ARM_L, L_ARM_R, L_LEGS, L_BOTTLE, L_BAG = 1, 2, 3, 4, 5, 6, 7

    chair_lines = None
    if CHAIR_MESH.get('use'):
        chair_hosts, chair_lines = pl_chair_mesh(K, cream_m, L_BACK); hosts += chair_hosts
    else:
        hosts += pl_chair(K, cream_m, L_SEAT, L_BACK, L_ARM_L, L_ARM_R, L_LEGS)
    body, cap = pl_bottle(K, cream_m, blue_m, L_BOTTLE); hosts += [body.name, cap.name]
    bag_hosts, npellets = pl_bag(K, blue_m, cream_m, L_BAG); hosts += bag_hosts

    for ob in K.col.objects:                          # v23: explicit 6 px lines take the thinner interior weight too
        if ob.get('ink_width') == 6:
            ob['ink_width'] = PL_INNER
    chair_desc = ("cream monobloc armchair (Poly Haven's plastic_monobloc_chair_01, CC0: slotted back and seat, arms bending into "
                  "the front legs)" if CHAIR_MESH.get('use') else
                  'cream monobloc armchair (curved slotted backrest, arms bending into four identical L-section legs)')
    info = contract(K, hosts, '%s; a PET bottle with a blue cap; a blue carrier bag brim-full of %d cream pellets' % (chair_desc, npellets), inner=PL_INNER)
    info['revision'] = PL_REVISION
    info['outline']['component_boundaries'] = True
    info['stipple']['strength'] = 0.38
    # v10: ruling 5's lattice; the toon's shade step is moved to the same 0.65 (PL_SHADE_STEP), so the shade
    # colour and the dots cover the same pixels (review v9c: shade-toned faces left bare)
    # v11: the dot mask is 0.5 + 0.5 N.L while the toon steps on the diffuse factor: measured on v10c, the
    # shade step (factor 0.65) sits at mask 0.575 (1% of pixels disagree; 11% at ruling 5's 0.65)
    info['stipple']['groups'] = [{'name': 'shaded_faces', 'labels': [1, 2, 3, 4, 5, 6, 7], 'thresholds': [0.575, 0.50, 0.30]}]
    chair_dims = dict(CHAIR_MESH, lines=chair_lines) if CHAIR_MESH.get('use') else {k: (v if isinstance(v, (list, tuple, str)) else round(float(v), 4)) for k, v in CG_P.items()}
    info['dimensions'] = {'chair': chair_dims,
                          'bottle': BOTTLE, 'bottle_rings': BOTTLE_RINGS, 'bag': BAG, 'bag_creases': BAG_CREASES, 'pellets': npellets}
    return info
