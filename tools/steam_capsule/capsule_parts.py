"""Capsule-only redesigns of two game parts that turn to mush at capsule scale.

The mine's headframe and the power plant's switchyard are built from many thin members
(lattice legs, X-bracing, fins, insulator discs). In a sprite, one building fills the frame
and they read. On the capsule each building is a few hundred pixels across, so their outlines
fill them: measured at about 45% ink. These are the same things drawn with fewer, bolder
members, on the regular line, so they read as shapes: a tower with wheels, transformers
under a gantry, a pylon.

Both are built in the building's own frame, before buildings.py moves, scales and turns
it, with the Kit of that building's namespace (so its palette roles resolve).

    bold_headframe(K, name, cx, cy, base_z, height, w)
    bold_switchyard(K, yard, pad_h, pylon_xy, pylon_h, pylon_w)

Plus new parts the game has no model for: an EV charging unit (charging_unit), to the scale
of the lot's cars; a coal train (coal_train: a diesel engine and loaded hoppers) for the
railway; and for the mine's pit, haul trucks and floodlight masts (haul_truck, light_mast).
"""
import math

import bpy

HEAD_LEG = 0.10                  # square leg section
HEAD_BELT = 0.08
HEAD_BRACE = 0.065
SHEAVE_R = 0.28


def _leg(K, name, p0, p1, t, mat):
    K.dirbox(name, p0, p1, t, t, mat)


def bold_headframe(K, name, cx, cy, base_z, height, w=0.66, taper=0.62, strut_dy=-1.05,
                   strut_foot_z=None):
    """A pit-head winding tower: four battered legs, two girder belts, one brace per panel on
    the two faces the camera sees, a head deck, two sheave wheels side by side and a pair of
    raking struts. The wheels face the camera (their axis points at it), so they read as
    circles; they sit apart along the screen's horizontal, (1, 1), so they never overlap."""
    steel, dark = K.mat("scaffold"), K.mat("stack")
    wt = w * taper
    top = base_z + height

    def corner(sx, sy, t):
        s = w + (wt - w) * t
        return (cx + sx * s / 2.0, cy + sy * s / 2.0, base_z + height * t)

    corners = ((-1, -1), (1, -1), (1, 1), (-1, 1))
    for i, (sx, sy) in enumerate(corners):
        _leg(K, "%s_leg%d" % (name, i), corner(sx, sy, 0.0), corner(sx, sy, 1.0), HEAD_LEG, steel)
    for j, t in enumerate((0.36, 0.70)):
        for k in range(4):
            a, b = corners[k], corners[(k + 1) % 4]
            _leg(K, "%s_belt%d_%d" % (name, j, k), corner(a[0], a[1], t), corner(b[0], b[1], t),
                 HEAD_BELT, steel)
    # One brace per panel on the faces the camera sees (-Y and +X), alternating direction.
    for j, (t0, t1) in enumerate(((0.0, 0.36), (0.36, 0.70), (0.70, 1.0))):
        for face, (a, b) in (("f", ((-1, -1), (1, -1))), ("r", ((1, -1), (1, 1)))):
            lo, hi = (a, b) if j % 2 == 0 else (b, a)
            _leg(K, "%s_br%d%s" % (name, j, face), corner(lo[0], lo[1], t0), corner(hi[0], hi[1], t1),
                 HEAD_BRACE, steel)
    K.box(name + "_deck", cx, cy, top + 0.06, wt + 0.30, wt + 0.30, 0.12, steel)
    # Two sheave wheels above the deck: a dark rim, a paler web and a hub.
    ax = (1.0 / math.sqrt(2.0), -1.0 / math.sqrt(2.0), 0.0)          # toward the camera
    for i, off in enumerate((-0.22, 0.22)):
        wx, wy = cx + off / math.sqrt(2.0), cy + off / math.sqrt(2.0)
        wz = top + 0.12 + SHEAVE_R
        p0 = (wx - ax[0] * 0.03, wy - ax[1] * 0.03, wz)
        p1 = (wx + ax[0] * 0.03, wy + ax[1] * 0.03, wz)
        K.dircyl("%s_sheave%d" % (name, i), p0, p1, SHEAVE_R, dark, segments=28, smooth=False)
        q1 = (wx + ax[0] * 0.045, wy + ax[1] * 0.045, wz)
        K.dircyl("%s_web%d" % (name, i), p1, q1, SHEAVE_R * 0.72, steel, segments=28, smooth=False)
        h1 = (wx + ax[0] * 0.06, wy + ax[1] * 0.06, wz)
        K.dircyl("%s_hub%d" % (name, i), q1, h1, SHEAVE_R * 0.22, dark, segments=16, smooth=False)
        # The wheel's bearing frame: a short post under each wheel.
        _leg(K, "%s_post%d" % (name, i), (wx, wy, top + 0.12), (wx, wy, wz), 0.07, steel)
    # Raking struts from the head down to the ground in front.
    fz = base_z if strut_foot_z is None else strut_foot_z
    for sx in (-1, 1):
        _leg(K, "%s_strut%d" % (name, sx > 0), (cx + sx * wt / 2.0, cy - wt / 2.0, top - 0.12),
             (cx + sx * w / 2.0, cy + strut_dy, fz), 0.09, steel)


def _transformer(K, name, x, y, z):
    """A power transformer: body, a darker radiator block on the camera side, a conservator
    drum on top, three porcelain bushings and a band in the power plant's accent."""
    body, dark = K.mat("gear"), K.mat("darkmetal")
    bw, bd, bh = 0.52, 0.42, 0.46
    K.box(name + "_body", x, y, z + bh / 2.0, bw, bd, bh, body)
    K.box(name + "_band", x, y, z + bh - 0.05, bw + 0.02, bd + 0.02, 0.07, K.mat("power_accent"))
    K.box(name + "_rad", x, y - bd / 2.0 - 0.07, z + bh * 0.45, bw * 0.80, 0.12, bh * 0.70, dark)
    K.cyl(name + "_drum", x - 0.05, y + 0.06, z + bh + 0.10, 0.075, bw * 0.75, body, axis='X', segments=16)
    for i, dx in enumerate((-0.15, 0.0, 0.15)):
        K.cyl("%s_bush%d" % (name, i), x + dx, y - 0.08, z + bh + 0.11, 0.035, 0.22,
              K.mat("white_wall"), segments=10)


def bold_switchyard(K, yard, pad_h, pylon_xy, pylon_h, pylon_w):
    """Two transformers in a row, one gantry at the yard's outgoing edge and a pylon: the
    power's path from hall to line, in parts bold enough to read."""
    yx0, yx1, yy0, yy1 = yard
    steel = K.mat("scaffold")
    ty = (yy0 + yy1) / 2.0
    for i, tx in enumerate((yx0 + (yx1 - yx0) * 0.28, yx0 + (yx1 - yx0) * 0.62)):
        _transformer(K, "sy_tx%d" % i, tx, ty, pad_h)
    gx = yx1 - 0.14
    for tag, gy in (("a", yy0 + 0.20), ("b", yy1 - 0.20)):
        _leg(K, "sy_gpost_" + tag, (gx, gy, pad_h), (gx, gy, pad_h + 1.05), 0.09, steel)
    _leg(K, "sy_gbeam", (gx, yy0 + 0.12, pad_h + 1.05), (gx, yy1 - 0.12, pad_h + 1.05), 0.09, steel)
    for i in range(3):
        gy = yy0 + 0.20 + (yy1 - yy0 - 0.40) * (i + 0.5) / 3.0
        K.cyl("sy_gins%d" % i, gx, gy, pad_h + 0.93, 0.035, 0.18, K.mat("white_wall"), segments=10)
    # The pylon: four battered legs, three belts, one brace per panel on the camera's faces,
    # and two cross-arms carrying insulators.
    px, py = pylon_xy
    wb, wt = pylon_w, pylon_w * 0.28

    def pc(sx, sy, t):
        s = wb + (wt - wb) * t
        return (px + sx * s / 2.0, py + sy * s / 2.0, pad_h + pylon_h * t)

    corners = ((-1, -1), (1, -1), (1, 1), (-1, 1))
    for i, (sx, sy) in enumerate(corners):
        _leg(K, "sy_pleg%d" % i, pc(sx, sy, 0.0), pc(sx, sy, 1.0), 0.07, steel)
    ts = (0.0, 0.32, 0.62, 0.86)
    for j, t in enumerate(ts[1:]):
        for k in range(4):
            a, b = corners[k], corners[(k + 1) % 4]
            _leg(K, "sy_pbelt%d_%d" % (j, k), pc(a[0], a[1], t), pc(b[0], b[1], t), 0.05, steel)
    for j in range(len(ts) - 1):
        for face, (a, b) in (("f", ((-1, -1), (1, -1))), ("r", ((1, -1), (1, 1)))):
            lo, hi = (a, b) if j % 2 == 0 else (b, a)
            _leg(K, "sy_pbr%d%s" % (j, face), pc(lo[0], lo[1], ts[j]), pc(hi[0], hi[1], ts[j + 1]),
                 0.045, steel)
    for j, t in enumerate((0.72, 0.90)):
        z = pad_h + pylon_h * t
        reach = 0.52 if j == 0 else 0.40
        _leg(K, "sy_parm%d" % j, (px, py - reach, z), (px, py + reach, z), 0.07, steel)
        for s in (-1, 1):
            K.cyl("sy_pins%d_%d" % (j, s > 0), px, py + s * (reach - 0.05), z - 0.11, 0.03, 0.18,
                  K.mat("white_wall"), segments=10)
    _leg(K, "sy_ptop", pc(0, 0, 1.0), (px, py, pad_h + pylon_h + 0.18), 0.06, steel)


PALETTE["charger_green"] = (0.200, 0.400, 0.150)


def charging_unit(K, name, x, y, z, s=1.0):
    """An EV charging post, the goods icon's green cabinet: a plinth, the cabinet, a dark screen
    with a yellow bolt on the face the camera sees (-Y), and a holstered cable loop. At s=1 it
    stands about a third of the lot's car length (0.76) tall."""
    import bmesh as _bm
    green, dark = K.mat("charger_green"), K.mat("window_glass")

    def at(dx, dy, dz):
        return (x + dx * s, y + dy * s, z + dz * s)

    def box(tag, dx, dy, dz, sx, sy, sz, mat):
        K.box(name + tag, *at(dx, dy, dz), sx * s, sy * s, sz * s, mat)

    box("_plinth", 0.0, 0.0, 0.012, 0.18, 0.13, 0.024, K.mat("pad"))
    box("_body", 0.0, 0.0, 0.154, 0.12, 0.08, 0.26, green)
    box("_cap", 0.0, 0.0, 0.289, 0.13, 0.09, 0.02, green)
    box("_screen", 0.0, -0.042, 0.20, 0.08, 0.006, 0.07, dark)
    # the bolt: a zig-zag painted on the screen, no ink
    me = bpy.data.meshes.new(name + "_bolt")
    bm = _bm.new()
    pts = [(0.006, 0.030), (-0.016, -0.002), (0.000, -0.002), (-0.008, -0.030),
           (0.016, 0.004), (0.000, 0.004)]
    bm.faces.new([bm.verts.new(at(px, -0.046, 0.20 + pz)) for px, pz in pts])
    bm.to_mesh(me)
    bm.free()
    K.obj(name + "_bolt", me, K.mat("plant_yellow"))
    attr = me.attributes.get("freestyle_face") or me.attributes.new("freestyle_face", 'BOOLEAN', 'FACE')
    for d in attr.data:
        d.value = True
    # holster on the +X side and a drooping cable loop down to it
    box("_holster", 0.066, -0.01, 0.14, 0.016, 0.03, 0.05, dark)
    K.dircyl(name + "_cable_a", at(0.07, -0.01, 0.20), at(0.10, -0.02, 0.08), 0.008 * s, dark, segments=6)
    K.dircyl(name + "_cable_b", at(0.10, -0.02, 0.08), at(0.074, -0.01, 0.12), 0.008 * s, dark, segments=6)


PALETTE["loco_red"] = (0.30, 0.045, 0.035)
PALETTE["wagon_steel"] = (0.11, 0.12, 0.14)
LOCO_L, HOPPER_L, TRAIN_W = 1.25, 0.95, 0.36     # world: to the lot's cars (0.76) and the gauge
WHEEL_R, DECK_Z = 0.05, 0.14                      # wheel radius; frame top above the rails


def _lamp_box(K, name, x, y, z, mat, size=0.05):
    ob = K.box(name, x, y, z, size * 0.4, size, size, mat)
    a = ob.data.attributes.new("freestyle_face", 'BOOLEAN', 'FACE')
    for d in a.data:
        d.value = True
    return ob


def _bogies(K, name, length, pitch):
    """Two bogies, each two axles of wheels on the capsule's gauge (0.15), and the frame."""
    dark = K.mat("darkmetal")
    for i, bx in enumerate((-length / 2 + 0.25, length / 2 - 0.25)):
        K.box("%s_bogie%d" % (name, i), bx, 0, WHEEL_R + 0.01, pitch + 0.16, 0.20, 0.05, dark)
        for j, ax in enumerate((-pitch / 2, pitch / 2)):
            for sy in (-1, 1):
                K.cyl("%s_w%d%d%d" % (name, i, j, sy > 0), bx + ax, sy * 0.085, WHEEL_R, WHEEL_R, 0.03, dark,
                      axis='Y', segments=10, smooth=False)
    K.box(name + "_frame", 0, 0, DECK_Z - 0.025, length, TRAIN_W - 0.02, 0.05, dark)


def locomotive(K, name):
    """A diesel road-switcher along +X (its front), the rails' top at z = 0: a long hood, the
    cab near the front with windows all round, a short nose, the game's red with hi-vis ends,
    and lamps: two at the front, two red at the back."""
    L, W = LOCO_L, TRAIN_W
    body, dark, yel, glass = K.mat("loco_red"), K.mat("darkmetal"), K.mat("plant_yellow"), K.mat("window_glass")
    _bogies(K, name, L, 0.18)
    K.box(name + "_hood", -0.20, 0, DECK_Z + 0.13, 0.70, W - 0.08, 0.26, body)
    K.box(name + "_cab", 0.32, 0, DECK_Z + 0.19, 0.30, W, 0.38, body)
    K.box(name + "_cabroof", 0.32, 0, DECK_Z + 0.395, 0.34, W + 0.03, 0.03, dark)
    K.box(name + "_nose", 0.545, 0, DECK_Z + 0.10, 0.15, W - 0.08, 0.20, body)
    K.box(name + "_wfront", 0.474, 0, DECK_Z + 0.29, 0.008, W - 0.10, 0.09, glass)
    for sy in (-1, 1):
        K.box("%s_wside%d" % (name, sy > 0), 0.32, sy * (W / 2 + 0.004), DECK_Z + 0.29, 0.20, 0.008, 0.09, glass)
    K.box(name + "_endf", 0.62, 0, DECK_Z + 0.08, 0.01, W - 0.10, 0.12, yel)
    K.box(name + "_endr", -0.55, 0, DECK_Z + 0.08, 0.01, W - 0.10, 0.12, yel)
    K.cyl(name + "_stack", -0.12, 0, DECK_Z + 0.30, 0.03, 0.08, dark, segments=10, smooth=False)
    for sy in (-1, 1):
        _lamp_box(K, "%s_head%d" % (name, sy > 0), L / 2 + 0.005, sy * 0.10, DECK_Z + 0.07, K.mat("car_headlamp"))
        _lamp_box(K, "%s_tail%d" % (name, sy > 0), -L / 2 - 0.005, sy * 0.10, DECK_Z + 0.07, K.mat("car_taillamp"))


def hopper(K, name):
    """A coal hopper along +X, the rails' top at z = 0: a ribbed steel body heaped with coal."""
    L, W = HOPPER_L, TRAIN_W
    steel, dark, coal = K.mat("wagon_steel"), K.mat("darkmetal"), K.mat("coal_seam")
    _bogies(K, name, L, 0.16)
    K.box(name + "_body", 0, 0, DECK_Z + 0.14, L - 0.06, W, 0.28, steel)
    for i, rx in enumerate((-0.28, 0.0, 0.28)):
        for sy in (-1, 1):
            K.box("%s_rib%d%d" % (name, i, sy > 0), rx, sy * (W / 2 + 0.006), DECK_Z + 0.14, 0.03, 0.012,
                  0.28, dark)
    K.box(name + "_coal", 0, 0, DECK_Z + 0.30, L - 0.16, W - 0.08, 0.05, coal)
    K.box(name + "_coal2", 0, 0, DECK_Z + 0.34, L - 0.40, W - 0.16, 0.04, coal)


def coal_train(K, name, path, z, cars=("locomotive", "hopper", "hopper"), front_gap=0.35, gap=0.08):
    """A train on a line's world `path` (xy points), its engine's front `front_gap` short of
    the path's end, heading that way, the rest coupled behind; each vehicle is turned to the
    chord between its ends, so the train follows the curve. The whole train takes the thin
    line, like the cars."""
    import mathutils
    s = [0.0]
    for i in range(len(path) - 1):
        s.append(s[-1] + math.dist(path[i], path[i + 1]))

    def at(d):
        d = max(0.0, min(s[-1], d))
        i = 0
        while i < len(path) - 2 and s[i + 1] < d:
            i += 1
        t = (d - s[i]) / max(s[i + 1] - s[i], 1e-9)
        return (path[i][0] + (path[i + 1][0] - path[i][0]) * t, path[i][1] + (path[i + 1][1] - path[i][1]) * t)

    lengths = {"locomotive": LOCO_L, "hopper": HOPPER_L}
    build = {"locomotive": locomotive, "hopper": hopper}
    fm = K._fine_mode
    K._fine_mode = True
    front = s[-1] - front_gap
    for k, kind in enumerate(cars):
        L = lengths[kind]
        a, b, c = at(front - L), at(front), at(front - L / 2)
        heading = math.atan2(b[1] - a[1], b[0] - a[0])
        before = set(K.col.objects)
        build[kind](K, "%s_%d" % (name, k))
        M = mathutils.Matrix.Translation((c[0], c[1], z)) @ mathutils.Matrix.Rotation(heading, 4, 'Z')
        for ob in K.col.objects:
            if ob not in before:
                ob.matrix_world = M @ ob.matrix_world
        front -= L + gap
    K._fine_mode = fm


def haul_truck(K, name):
    """A mine haul truck along +X (its front), the ground at z = 0: big wheels, a yellow dump
    body heaped with ore that reaches over the cab, the cab on the left, white headlamps and
    a red lamp at each back corner."""
    L, W = 0.80, 0.44
    yel, dark, ore, glass = K.mat("plant_yellow"), K.mat("darkmetal"), K.mat("ore_seam"), K.mat("window_glass")
    for i, (wx, sy) in enumerate(((0.24, 1), (0.24, -1), (-0.22, 1), (-0.22, -1))):
        K.cyl("%s_w%d" % (name, i), wx, sy * (W / 2 - 0.05), 0.11, 0.11, 0.09, dark, axis='Y', segments=12,
              smooth=False)
    K.box(name + "_chassis", 0, 0, 0.15, L - 0.05, W - 0.14, 0.06, dark)
    K.box(name + "_bed", -0.08, 0, 0.28, 0.56, W, 0.20, yel)
    K.box(name + "_load", -0.08, 0, 0.395, 0.46, W - 0.10, 0.05, ore)
    K.box(name + "_cab", 0.30, W / 4, 0.29, 0.16, W / 2 - 0.04, 0.20, yel)
    K.box(name + "_win", 0.385, W / 4, 0.32, 0.008, W / 2 - 0.10, 0.08, glass)
    K.box(name + "_canopy", 0.25, 0, 0.405, 0.26, W, 0.03, yel)
    for sy in (-1, 1):
        _lamp_box(K, "%s_head%d" % (name, sy > 0), L / 2 + 0.005, sy * 0.15, 0.20, K.mat("car_headlamp"), 0.06)
        _lamp_box(K, "%s_tail%d" % (name, sy > 0), -L / 2 + 0.03, sy * 0.19, 0.22, K.mat("car_taillamp"), 0.05)


def light_mast(K, name, height=1.7):
    """A floodlight mast at the origin, its lamps facing +X: a pole, a head frame and four
    lamp panels in a row, which the warm looks light."""
    dark = K.mat("darkmetal")
    K.cyl(name + "_pole", 0, 0, height / 2, 0.035, height, dark, segments=10, smooth=False)
    K.box(name + "_base", 0, 0, 0.03, 0.16, 0.16, 0.06, K.mat("slab"))
    K.box(name + "_frame", 0.03, 0, height + 0.05, 0.05, 0.40, 0.16, dark)
    for i, py in enumerate((-0.14, -0.05, 0.05, 0.14)):
        _lamp_box(K, "%s_lamp%d" % (name, i), 0.065, py, height + 0.05, K.mat("car_headlamp"), 0.08)


def place_built(K, build, name, M):
    """Build a part at the origin with `build(K, name)` and move what it made by M."""
    before = set(K.col.objects)
    build(K, name)
    for ob in K.col.objects:
        if ob not in before:
            ob.matrix_world = M @ ob.matrix_world
