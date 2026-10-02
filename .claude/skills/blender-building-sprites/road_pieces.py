#!/usr/bin/env python3
"""Render the road pieces the supply chain board lays its streets from.

    blender --background --factory-startup --python road_pieces.py -- <out_dir>

One small frame per piece, seen by the sprite rig's own camera; bake_pipes.py packs the frames
into the atlas the game loads (its --kind roads).

THE STREET PLAN. Every tile on the board has the same streets: two streets along the map's x
axis, two avenues across them, a short spur to each building, and a link running off at 60
degrees to each of the four diagonal neighbours. So roads run along only four lines, and the
junctions that can occur are a known, finite set. Direction index k is the Blender angle 30*k
degrees, as for the pipes: 0 and 6 are the street's two ways, 3 and 9 the avenue's, and
2, 4, 8, 10 the links'.

A road has a LEVEL, 1 to 3, which is its width: spurs are always level 1, and a tile's own
streets take the level of its roads.

THE PIECES:
    r_straight_k_L   k in 0, 2, 3, 4     a run of road, repeating every TILE
    r_bridge_k_L     k in 0, 2, 3, 4     a truss bridge carrying that road over a river
    r_j_<arms>                           a junction; <arms> is its arms as k.L, sorted by k and
                                         joined by "_". Two arms that are not in line make a
                                         bend; two in line at different levels make the road
                                         narrow; three make a T or a Y; four a crossing.

Dimensions are in MAP UNITS, divided by UNIT on the way in, and written out for the game.
The camera looks at each piece's anchor, so the anchor is the frame's centre.
"""
import itertools
import json
import math
import os
import sys

import bmesh
import bpy
import mathutils

B = os.path.dirname(os.path.abspath(__file__)).replace("\\", "/") + "/"
argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
if not argv:
    raise SystemExit("need: <out_dir>")
OUT = argv[0]
os.makedirs(OUT, exist_ok=True)

UNIT = 27.0
FRAME = 256
ORTHO = 2.4
DIMS = dict(
    tile=24.0,             # a straight's repeat length: one dash and one gap
    arm=20.0,              # how far a junction's arms reach from its centre
    bridge=50.0,           # a bridge's length
    half_1=4.5, half_2=7.5, half_3=10.5,     # carriageway half-width, by level
    walk_1=1.6, walk_2=2.2, walk_3=2.6,      # pavement beyond it, each side
)
ASPHALT = (0.085, 0.088, 0.095)
PAVING = (0.33, 0.32, 0.29)
PAINT = (0.62, 0.61, 0.56)
STEEL = (0.16, 0.19, 0.24)
Z_WALK = 0.5
Z_ROAD = 0.7

for ob in list(bpy.data.objects):
    if ob.name not in ("Camera", "Light"):
        bpy.data.objects.remove(ob, do_unlink=True)
ns = {}
exec(open(B + "sprite_kit.py").read(), ns)
ns["setup_rig"](ortho_scale=ORTHO, target=(0.0, 0.0, 0.0), res=FRAME)
scene = bpy.context.scene
fs = scene.view_layers[0].freestyle_settings
for ls in list(fs.linesets):
    if ls.name not in ("ink", "ink_fine"):
        fs.linesets.active_index = list(fs.linesets).index(ls)
        bpy.ops.scene.freestyle_lineset_remove()
scene.render.image_settings.file_format = 'PNG'
scene.render.image_settings.color_mode = 'RGBA'
scene.render.film_transparent = True
K = ns["Kit"](ns["open_collection"]("BLDG_roads"))
cam = scene.camera


def flat(name, rgb):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = tuple(rgb) + (1.0,)
    bsdf.inputs["Roughness"].default_value = 1.0
    bsdf.inputs["Specular IOR Level"].default_value = 0.0
    return mat


M_ASPHALT = flat("road_asphalt", ASPHALT)
M_PAVING = flat("road_paving", PAVING)
M_PAINT = flat("road_paint", PAINT)
M_STEEL = flat("road_steel", STEEL)


def U(v):
    return v / UNIT


def d_of(k):
    a = math.radians(30.0 * k)
    return mathutils.Vector((math.cos(a), math.sin(a), 0.0))


Z = mathutils.Vector((0.0, 0.0, 1.0))
O = mathutils.Vector((0.0, 0.0, 0.0))


def clear():
    for ob in list(K.col.objects):
        bpy.data.objects.remove(ob, do_unlink=True)


def shoot(name):
    cam.location = mathutils.Vector((1, -1, 1)).normalized() * 26.0
    scene.render.filepath = os.path.join(OUT, name + ".png")
    bpy.ops.render.render(write_still=True)
    print("PIECE_OK", name, flush=True)


def plate(name, pts, z, mat):
    """A flat slab with the outline `pts`, top at z."""
    return K.poly_prism(name, [(p.x, p.y) for p in pts], 0.0, U(z), mat)


def carriageway(name, d, half, level, reach):
    """The road's surface along d, as ONE mesh whose lane lines are material slots: a line
    laid on top as its own object would take an ink outline thicker than itself."""
    side = Z.cross(d)
    lines = []                      # (offset, half width, dashed)
    if level == 2:
        lines = [(0.0, 0.45, True)]
    elif level == 3:
        lines = [(-0.7, 0.3, False), (0.7, 0.3, False), (-half * 0.5, 0.35, True), (half * 0.5, 0.35, True)]
    cuts = sorted({-half, half} | {o + s * w for o, w, _ in lines for s in (-1.0, 1.0)})
    step = DIMS["tile"] / 2.0
    n = int(reach / step) + 1
    m = bpy.data.meshes.new(name)
    bm = bmesh.new()
    for i in range(-n, n):
        a0, a1 = step * i, step * (i + 1)
        painted_row = (i % 2 == 0)
        for j in range(len(cuts) - 1):
            c0, c1 = cuts[j], cuts[j + 1]
            mid = (c0 + c1) / 2.0
            paint = any(abs(mid - o) < w and (not dashed or painted_row) for o, w, dashed in lines)
            vs = [bm.verts.new(d * U(a) + side * U(c) + Z * U(Z_ROAD)) for a, c in
                  ((a0, c0), (a1, c0), (a1, c1), (a0, c1))]
            f = bm.faces.new(vs)
            f.material_index = 1 if paint else 0
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(m)
    bm.free()
    ob = K.obj(name, m, M_ASPHALT)
    ob.data.materials.append(M_PAINT)
    for poly in ob.data.polygons:
        if poly.normal.z < 0.0:
            poly.flip()
    return ob


def strip(d, half, reach):
    side = Z.cross(d)
    return [d * U(-reach) - side * U(half), d * U(reach) - side * U(half),
            d * U(reach) + side * U(half), d * U(-reach) + side * U(half)]


def straight(k, level):
    clear()
    d = d_of(k)
    half = DIMS["half_%d" % level]
    plate("walk", strip(d, half + DIMS["walk_%d" % level], 110.0), Z_WALK, M_PAVING)
    carriageway("road", d, half, level, 110.0)
    shoot("r_straight_%d_%d" % (k, level))


def outline(arms, extra):
    """The outline of a junction: each arm a strip reaching DIMS['arm'] from the centre, and
    between two neighbouring arms the corner where their edges meet. `arms` is [(k, level)]
    sorted by k; `extra` widens every arm (the pavement)."""
    reach = U(DIMS["arm"])
    pts = []
    n = len(arms)
    for i in range(n):
        k, level = arms[i]
        d = d_of(k)
        left = Z.cross(d)
        w = U(DIMS["half_%d" % level] + (DIMS["walk_%d" % level] if extra else 0.0))
        pts.append(d * reach - left * w)
        pts.append(d * reach + left * w)
        k2, level2 = arms[(i + 1) % n]
        d2 = d_of(k2)
        left2 = Z.cross(d2)
        w2 = U(DIMS["half_%d" % level2] + (DIMS["walk_%d" % level2] if extra else 0.0))
        # This arm's left edge and the next arm's right edge.
        p, q = left * w, -left2 * w2
        det = d.x * (-d2.y) - d.y * (-d2.x)
        if abs(det) < 1e-4:
            continue                                   # in line: the outline runs straight on
        t = ((q.x - p.x) * (-d2.y) - (q.y - p.y) * (-d2.x)) / det
        corner = p + d * t
        if corner.length < reach * 0.97:
            pts.append(corner)
        elif d.angle(d2) < math.radians(100.0) and (k2 - k) % 12 < 6:
            # Two arms close together: their edges meet beyond the arms' own reach, so the
            # corner is brought in along the line between them.
            pts.append((d + d2).normalized() * reach * 0.97)
    return pts


def star_plate(name, pts, z, mat):
    """A flat slab whose outline is seen whole from its centre, built as a fan about it. A
    junction's outline is concave between its arms, and an n-gon cap fills that in."""
    m = bpy.data.meshes.new(name)
    bm = bmesh.new()
    top = [bm.verts.new((p.x, p.y, U(z))) for p in pts]
    bot = [bm.verts.new((p.x, p.y, 0.0)) for p in pts]
    hub = bm.verts.new((0.0, 0.0, U(z)))
    for i in range(len(pts)):
        j = (i + 1) % len(pts)
        bm.faces.new([hub, top[i], top[j]])
        bm.faces.new([top[i], bot[i], bot[j], top[j]])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(m)
    bm.free()
    return K.obj(name, m, mat)


def junction(arms):
    clear()
    star_plate("walk", outline(arms, True), Z_WALK, M_PAVING)
    star_plate("road", outline(arms, False), Z_ROAD, M_ASPHALT)
    shoot("r_j_" + "_".join("%d.%d" % a for a in arms))


def bridge(k, level):
    """A Warren truss either side of the deck. The deck is the road itself, so the road's own
    straight carries on underneath and only the trusses and the abutments are new."""
    clear()
    d = d_of(k)
    side = Z.cross(d)
    half = DIMS["half_%d" % level]
    out = half + DIMS["walk_%d" % level]
    length = DIMS["bridge"]
    plate("deck", strip(d, out + 0.6, length / 2.0), Z_WALK + 0.5, M_PAVING)
    carriageway("road", d, half, level, length / 2.0 - 0.01)
    for ob in K.col.objects:
        if ob.name == "road":
            ob.location.z += U(0.5)
    height = 13.0
    bays = 4
    bar = U(1.1)
    prev_fine = K._fine_mode
    K._fine_mode = True
    for sgn, tag in ((-1.0, "a"), (1.0, "b")):
        base = side * U(sgn * (out + 0.2))
        lo = [base + d * U(-length / 2.0 + length * i / bays) + Z * U(1.4) for i in range(bays + 1)]
        hi = [base + d * U(-length / 2.0 + length * (i + 0.5) / bays) + Z * U(height) for i in range(bays)]
        K.dirbox("bot_" + tag, tuple(lo[0]), tuple(lo[-1]), bar, bar, M_STEEL)
        K.dirbox("top_" + tag, tuple(hi[0]), tuple(hi[-1]), bar, bar, M_STEEL)
        for i in range(bays):
            K.dirbox("up_%s%d" % (tag, i), tuple(lo[i]), tuple(hi[i]), bar, bar, M_STEEL)
            K.dirbox("dn_%s%d" % (tag, i), tuple(hi[i]), tuple(lo[i + 1]), bar, bar, M_STEEL)
    K._fine_mode = prev_fine
    for end in (-1.0, 1.0):
        c = d * U(end * (length / 2.0 - 1.5))
        K.dirbox("abut%d" % int(end), tuple(c - side * U(out + 1.6) - Z * U(0.2)),
                 tuple(c + side * U(out + 1.6) - Z * U(0.2)), U(3.4), U(1.6), M_PAVING)
    shoot("r_bridge_%d_%d" % (k, level))


def configs():
    """Every junction the street plan can produce."""
    out = set()

    def add(arms):
        arms = tuple(sorted(arms))
        ks = [a[0] for a in arms]
        if len(arms) == 2 and (ks[0] + 6) % 12 == ks[1] and arms[0][1] == arms[1][1]:
            return                                     # two arms in line at one level: a straight
        out.add(arms)

    for level in (1, 2, 3):
        # Street against avenue, every way of using two to four of the arms.
        for n in (2, 3, 4):
            for ks in itertools.combinations((0, 3, 6, 9), n):
                add([(k, level) for k in ks])
        # A spur, always level 1, off a street of this level.
        for street in ((0,), (6,), (0, 6)):
            for spur in ((3,), (9,), (3, 9)):
                add([(k, level) for k in street] + [(k, 1) for k in spur])
        # A link to a diagonal neighbour leaving a street.
        for link in (2, 4, 8, 10):
            for street in ((0,), (6,), (0, 6)):
                add([(k, level) for k in street] + [(link, level)])
    # The road changing width where two tiles of different levels meet.
    for line in ((3, 9), (2, 8), (4, 10), (0, 6)):
        for la in (1, 2, 3):
            for lb in (1, 2, 3):
                if la != lb:
                    add([(line[0], la), (line[1], lb)])
    return sorted(out)


for level in (1, 2, 3):
    for k in (0, 2, 3, 4):
        straight(k, level)
        bridge(k, level)
for arms in configs():
    junction(list(arms))

json.dump({"unit": UNIT, "frame": FRAME, "ortho": ORTHO, "dims": DIMS},
          open(os.path.join(OUT, "pieces.json"), "w"), indent=1)
print("ALL_OK", flush=True)
