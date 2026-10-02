#!/usr/bin/env python3
"""Render the pipe pieces the supply chain board lays its pipework from.

    blender --background --factory-startup --python pipe_pieces.py -- <out_dir>

One small frame per piece, every piece seen by the sprite rig's own camera so it sits with
the building sprites. bake_pipes.py turns the frames into the atlas the game loads.

THE GRID. Pipes on the board run only along twelve plan directions, every 30 degrees, so a
finite set of pieces covers every run. Direction index k is the Blender angle 30*k degrees.
(Map y points down and Blender y up, so the game reads a map direction as k = -angle/30.)

THE PIECES, per colour set (c = pipework, s = reinforced pipework):
    straight_k   k 0..11   a run lying on the ground on sleepers, one sleeper per TILE length,
                           with an off-white triangle on its top pointing the way k: the way
                           its contents flow. A run is the same pipe either way round, so it
                           is the arrow that makes twelve of these and not six.
    raised_k     k 0..11   the same run in the air, no sleepers
    bend_i_j               a bend from travel direction i to travel direction j: 30, 60, 90
                           degrees either way. bend_i_j is the same object as bend_(j+6)_(i+6)
                           walked backwards, so only one of each pair is rendered.
    rise_k       k 0..11   travelling k along the ground, then turning straight up
    top_k        k 0..11   coming straight up, then turning to travel k
    vert                   a vertical run
    entry_k      k 0..11   travelling k, then down into a collar in the ground
and once, shared:  support_k  k 0..5  the trestle a raised run stands on.

Every dimension is in MAP UNITS (the board's own) and divided by UNIT on the way in, so the
numbers here are the numbers the game lays pieces out with; bake_pipes.py writes them into the
atlas index. The camera looks at each piece's ANCHOR, so the anchor is the frame's centre.
"""
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

UNIT = 27.0            # map units per Blender unit (a works footprint is about 4 Blender units)
FRAME = 256            # pixels
ORTHO = 2.4            # Blender units across the frame: 3.95 px per map unit
DIMS = dict(
    r=2.7,             # pipe radius
    flange_r=4.1, flange_t=1.2,
    bend_r=6.0,        # radius of a bend in plan
    riser_r=6.0,       # radius of the turn between flat and vertical
    rest=4.4,          # height of a ground run's centreline: it lies on sleepers
    raise_=17.0,       # a raised run's centreline stands this far above a ground run's
    tile=30.0,         # a straight's repeat length, and so the spacing of its sleepers
    support_w=4.8,
    arrow_l=9.0, arrow_w=6.6,      # the flow marker on a straight: wider than the pipe is thick
)
LIGHT = mathutils.Vector((-0.30, -0.62, 0.72)).normalized()
SETS = {
    "c": dict(body=(0.36, 0.165, 0.075), flange=(0.105, 0.075, 0.07), bands=False),
    "s": dict(body=(0.30, 0.345, 0.40), flange=(0.085, 0.10, 0.135), bands=True),
}

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
K = ns["Kit"](ns["open_collection"]("BLDG_pipes"))
cam = scene.camera


def banded(name, rgb):
    """A flat material in three hard tones picked by which way the face looks. This rig has no
    directional light to speak of, so a tube in one flat tone reads as a ribbon; the bands are
    what make it round."""
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    geo = nt.nodes.new("ShaderNodeNewGeometry")
    dot = nt.nodes.new("ShaderNodeVectorMath")
    dot.operation = 'DOT_PRODUCT'
    dot.inputs[1].default_value = LIGHT
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.interpolation = 'CONSTANT'
    els = ramp.color_ramp.elements
    els[0].position = 0.0
    els[0].color = tuple(c * 0.55 for c in rgb) + (1.0,)
    els[1].position = 0.38
    els[1].color = tuple(rgb) + (1.0,)
    hi = els.new(0.80)
    hi.color = tuple(min(1.0, c * 1.9 + 0.05) for c in rgb) + (1.0,)
    rng = nt.nodes.new("ShaderNodeMapRange")
    rng.inputs["From Min"].default_value = -1.0
    rng.inputs["From Max"].default_value = 1.0
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.inputs["Roughness"].default_value = 1.0
    bsdf.inputs["Specular IOR Level"].default_value = 0.0
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    nt.links.new(geo.outputs["Normal"], dot.inputs[0])
    nt.links.new(dot.outputs["Value"], rng.inputs["Value"])
    nt.links.new(rng.outputs["Result"], ramp.inputs["Fac"])
    nt.links.new(ramp.outputs["Color"], bsdf.inputs["Base Color"])
    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    return mat


MATS = {s: dict(body=banded("pipe_body_" + s, v["body"]), flange=banded("pipe_flange_" + s, v["flange"]))
        for s, v in SETS.items()}
CONCRETE = K.mat("slab")
ARROW = bpy.data.materials.new("pipe_arrow")
ARROW.use_nodes = True
_bsdf = ARROW.node_tree.nodes.get("Principled BSDF")
_bsdf.inputs["Base Color"].default_value = (0.78, 0.76, 0.68, 1.0)      # off-white
_bsdf.inputs["Roughness"].default_value = 1.0
_bsdf.inputs["Specular IOR Level"].default_value = 0.0
STEEL = K.mat("darkmetal")


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


def shoot(name, anchor):
    cam.location = mathutils.Vector(anchor) + mathutils.Vector((1, -1, 1)).normalized() * 26.0
    scene.render.filepath = os.path.join(OUT, name + ".png")
    bpy.ops.render.render(write_still=True)
    print("PIECE_OK", name, flush=True)


def tube(name, pts, s):
    return K.sweep(name, [tuple(p) for p in pts], U(DIMS["r"]), MATS[s]["body"])


def flange(name, at, axis, s):
    K.washer(name, tuple(at), tuple(axis), U(DIMS["r"]) - 0.01, U(DIMS["flange_r"]), U(DIMS["flange_t"]),
             MATS[s]["flange"])


def arc(c0, d0, d1, radius, steps=10):
    """Points of the bend that leaves corner c0 along -d0 and +d1: from the tangent point on the
    incoming leg to the one on the outgoing leg. The two directions may be any pair, flat or
    vertical; the bend lies in their plane."""
    turn = d0.angle(d1)
    t = radius * math.tan(turn / 2.0)
    p0 = c0 - d0 * t
    p1 = c0 + d1 * t
    inward = (d1 - d0).normalized()
    centre = c0 + inward * (radius / math.cos(turn / 2.0))
    a = p0 - centre
    axis = d0.cross(d1).normalized()
    pts = []
    for i in range(steps + 1):
        rot = mathutils.Matrix.Rotation(turn * i / steps, 3, axis)
        pts.append(centre + rot @ a)
    return pts, p0, p1


def bands(name, along, s, centre, half):
    """The hoops of reinforced pipework, two to a tile length, clear of the sleeper and of
    the flow arrow."""
    if not SETS[s]["bands"]:
        return
    step = U(DIMS["tile"]) / 3.0
    n = int(half / step) + 1
    for i in range(-n, n):
        if i % 3 == 1:
            continue                               # the middle of each tile is the arrow's
        K.washer("%s_band%d" % (name, i), tuple(centre + along * (step * (i + 0.5))), tuple(along),
                 U(DIMS["r"]) - 0.01, U(DIMS["r"] + 0.9), U(1.0), MATS[s]["flange"])


def arrows(d, c, half):
    """The flow marker: a flat triangle lying on the pipe's top, pointing along d, one to a
    tile length and midway between sleepers. Big for the pipe on purpose: it has to read at
    the board's scale, where the pipe is a few pixels across."""
    side = Z.cross(d)
    step = U(DIMS["tile"])
    top = c + Z * (U(DIMS["r"]) + 0.004)
    length, width = U(DIMS["arrow_l"]), U(DIMS["arrow_w"])
    n = int(half / step) + 1
    m = bpy.data.meshes.new("arrows")
    bm = bmesh.new()
    for i in range(-n, n):
        at = top + d * (step * (i + 0.5))
        tip = at + d * (length / 2.0)
        back = at - d * (length / 2.0)
        bm.faces.new([bm.verts.new(tip), bm.verts.new(back + side * (width / 2.0)),
                      bm.verts.new(back - side * (width / 2.0))])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(m)
    bm.free()
    ob = K.obj("arrows", m, ARROW)
    for poly in ob.data.polygons:
        if poly.normal.z < 0.0:
            poly.flip()


def straight(s, k, raised):
    clear()
    d = d_of(k)
    c = Z * (U(DIMS["rest"]) if not raised else 0.0)
    half = 4.0
    tube("run", [c - d * half, c + d * half], s)
    bands("run", d, s, c, half)
    arrows(d, c, half)
    if not raised:
        side = Z.cross(d)
        step = U(DIMS["tile"])
        top = U(DIMS["rest"] - DIMS["r"] + 0.5)
        for i in range(-8, 9):
            p = d * (step * i)
            a = p - side * U(DIMS["r"] + 1.4) + Z * (top / 2.0)
            b = p + side * U(DIMS["r"] + 1.4) + Z * (top / 2.0)
            K.dirbox("sleeper%d" % i, tuple(a), tuple(b), U(2.4), top, CONCRETE)
    shoot("%s_%s_%d" % (s, "raised" if raised else "straight", k), c)


def bend(s, i, j):
    clear()
    pts, p0, p1 = arc(O, d_of(i), d_of(j), U(DIMS["bend_r"]))
    tube("bend", pts, s)
    flange("f0", p0, d_of(i), s)
    flange("f1", p1, d_of(j), s)
    shoot("%s_bend_%d_%d" % (s, i, j), O)


def rise(s, k, top):
    clear()
    d = d_of(k)
    pts, p0, p1 = arc(O, Z, d, U(DIMS["riser_r"])) if top else arc(O, d, Z, U(DIMS["riser_r"]))
    tube("turn", pts, s)
    flange("f0", p0, Z if top else d, s)
    flange("f1", p1, d if top else Z, s)
    shoot("%s_%s_%d" % (s, "top" if top else "rise", k), O)


def vert(s):
    clear()
    tube("run", [O - Z * 4.0, O + Z * 4.0], s)
    bands("run", Z, s, O, 4.0)
    shoot("%s_vert" % s, O)


def entry(s, k):
    """The run arrives travelling k at its resting height and turns down into the ground at the
    anchor. The turn's radius is the resting height, so it ends exactly at ground level."""
    clear()
    d = d_of(k)
    corner = Z * U(DIMS["rest"])
    pts, p0, p1 = arc(corner, d, -Z, U(DIMS["rest"]) * 0.999)
    tube("turn", pts, s)
    flange("f0", p0, d, s)
    K.cyl("collar", 0.0, 0.0, U(0.7), U(DIMS["flange_r"] + 1.6), U(1.4), CONCRETE, axis='Z')
    K.washer("ring", (0.0, 0.0, U(1.5)), (0.0, 0.0, 1.0), U(DIMS["r"]) - 0.01, U(DIMS["flange_r"]),
             U(1.0), MATS[s]["flange"])
    shoot("%s_entry_%d" % (s, k), O)


def support(k):
    """A trestle under a raised run: the anchor is the run's centreline."""
    clear()
    d = d_of(k)
    side = Z.cross(d)
    drop = U(DIMS["rest"] + DIMS["raise_"])
    w = U(DIMS["support_w"])
    post = U(1.1)
    for sgn, tag in ((-1.0, "a"), (1.0, "b")):
        foot = side * (sgn * w) - Z * drop
        head = side * (sgn * w) - Z * U(DIMS["r"] + 1.0)
        K.dirbox("post_" + tag, tuple(foot), tuple(head), post, post, STEEL)
        K.box("foot_" + tag, foot.x, foot.y, foot.z + U(0.6), U(2.8), U(2.8), U(1.0), CONCRETE)
    beam_z = -U(DIMS["r"] + 1.0)
    K.dirbox("beam", tuple(side * -(w + U(1.0)) + Z * beam_z), tuple(side * (w + U(1.0)) + Z * beam_z),
             post, U(1.6), STEEL)
    shoot("x_support_%d" % k, O)


names = []
for s in SETS:
    for k in range(12):
        straight(s, k, False)
        straight(s, k, True)
    for i in range(12):
        for step in (1, 2, 3, -1, -2, -3):
            j = (i + step) % 12
            twin = ((j + 6) % 12, (i + 6) % 12)
            if (i, j) <= twin:
                bend(s, i, j)
        rise(s, i, False)
        rise(s, i, True)
        entry(s, i)
    vert(s)
for k in range(6):
    support(k)

json.dump({"unit": UNIT, "frame": FRAME, "ortho": ORTHO, "dims": DIMS},
          open(os.path.join(OUT, "pieces.json"), "w"), indent=1)
print("ALL_OK", flush=True)
