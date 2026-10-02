"""The map's three trees as 2.5D sprites, for the isometric zoom tier.

    build_tree(1)  SMALL  a hedgerow broadleaf
    build_tree(2)  FIR    a conifer
    build_tree(3)  LARGE  the specimen broadleaf

Each is the loading film's tree (props_kit.tree: kinked faceted trunk forking into limbs,
each ending in a faceted clump) with more in it: more limbs and clumps, a second ring of
smaller clumps under the crown, low boughs, and for the fir a stack of jittered cone tiers
on a trunk with its lower boughs showing. Same rig, same ink, same print pass as the
buildings, so a tree on the map is drawn by the same hand as the works beside it.

The three levels share one export scale (sprite_export.py), so the PNGs carry their relative
sizes: the map scales each by its kind's canopy radius (tree_shapes.gd) and the proportions
between kinds come from here.

To rebuild (from this directory; OUT is any scratch folder):
    for L in 1 2 3; do blender -b --factory-startup --python render_sprite.py -- \
        tree_builder.py build_tree $L $OUT/tree_L$L.png BLDG_tree; done
    python3 sprite_export.py $OUT tree --size 512 --pad 4
    for L in 1 2 3; do python3 stylize_shade.py $OUT/tree_lvl$L.png $OUT/tree_lvl${L}_mask.png \
        $OUT/tree_lvl${L}_print.png; done
then crop each print to its alpha bbox and install as
    price-of-everything-0.1/assets/iso/trees/tree_{small,fir,large}.png   (levels 1, 2, 3)
and run `godot --headless --path . --import` from the project.
"""
import math
import os
import random
import sys

import bmesh
import bpy

# The kit directory: render_sprite.py execs this file into a namespace of its own, so find
# props_kit.py beside the render script named on Blender's own command line.
_KIT_DIR = os.path.dirname(os.path.abspath(sys.argv[sys.argv.index("--python") + 1])) + "/"
exec(open(_KIT_DIR + "props_kit.py").read())

PALETTE["canopy_light"] = (0.190, 0.360, 0.120)   # the crown's sunward lobes
PALETTE["fir"] = (0.085, 0.200, 0.090)
PALETTE["fir_dark"] = (0.055, 0.140, 0.065)
PALETTE["fir_light"] = (0.120, 0.250, 0.105)


def _broadleaf(K, name, h, r, seed, limbs, under):
    """props_kit's tree, then more: `limbs` outer clumps, `under` smaller clumps in the shade
    beneath the crown, and a pair of low boughs."""
    rng = random.Random(seed)
    K.tree(name, 0.0, 0.0, h=h, r=r, seed=seed)
    top_z = h * 0.52
    # Outer ring of clumps around the crown, lit side lighter.
    for i in range(limbs):
        ang = (i / limbs) * 6.283 + rng.uniform(-0.3, 0.3)
        dx = math.cos(ang) * r * rng.uniform(0.75, 1.15)
        dy = math.sin(ang) * r * rng.uniform(0.75, 1.15)
        dz = rng.uniform(0.0, 0.35) * r
        rf = rng.uniform(0.42, 0.62)
        cz = top_z + dz
        K._taper("%s_xl%d" % (name, i), (0.0, 0.0, top_z),
                 (dx * 0.7, dy * 0.7, cz - r * rf * 0.2), r * 0.05, r * 0.02, K.mat("bark"), segments=6)
        lit = dy < -r * 0.1 and dx < r * 0.3
        K._blob("%s_xc%d" % (name, i), dx, dy, cz, r * rf,
                K.mat("canopy_light" if lit else ("canopy_dark" if dy > r * 0.15 else "canopy")), rng,
                scale=(1.0 + rng.uniform(0.05, 0.2), 1.0 + rng.uniform(0.0, 0.15), rng.uniform(0.7, 0.85)))
    # Smaller clumps in the shade under the crown.
    for i in range(under):
        ang = rng.uniform(0, 6.283)
        dx = math.cos(ang) * r * rng.uniform(0.4, 0.9)
        dy = math.sin(ang) * r * rng.uniform(0.4, 0.9)
        K._blob("%s_uc%d" % (name, i), dx, dy, top_z - r * rng.uniform(0.15, 0.4), r * rng.uniform(0.28, 0.4),
                K.mat("canopy_dark"), rng, scale=(1.1, 1.0, 0.7))
    # Two low boughs off the trunk.
    for i in range(2):
        ang = rng.uniform(0, 6.283)
        z0 = h * rng.uniform(0.28, 0.42)
        ex = math.cos(ang) * r * 0.9
        ey = math.sin(ang) * r * 0.9
        K._taper("%s_bough%d" % (name, i), (0.0, 0.0, z0), (ex, ey, z0 + r * 0.25),
                 r * 0.06, r * 0.025, K.mat("bark"), segments=6)
        K._blob("%s_bc%d" % (name, i), ex, ey, z0 + r * 0.3, r * 0.3, K.mat("canopy"), rng,
                scale=(1.1, 1.0, 0.75))


def _fir(K, name, h, r, seed, tiers):
    """A conifer: a kinked trunk, `tiers` jittered flat-shaded cone tiers narrowing to the
    tip, each a little off-centre, and a few bare lower boughs under the lowest tier."""
    rng = random.Random(seed)
    K._taper("%s_trunk" % name, (0.0, 0.0, 0.0), (rng.uniform(-0.04, 0.04) * r, rng.uniform(-0.04, 0.04) * r, h * 0.96),
             r * 0.16, r * 0.03, K.mat("bark"), segments=7)
    base_z = h * 0.22
    for t in range(tiers):
        f = t / float(max(1, tiers - 1))
        z0 = base_z + (h - base_z) * f * 0.78
        tier_h = (h - base_z) * (0.34 - 0.08 * f)
        tier_r = r * (1.0 - 0.72 * f) * rng.uniform(0.92, 1.08)
        m = bpy.data.meshes.new("%s_tier%d" % (name, t))
        bm = bmesh.new()
        bmesh.ops.create_cone(bm, cap_ends=True, segments=9, radius1=tier_r, radius2=tier_r * 0.12, depth=tier_h)
        for v in bm.verts:
            v.co.x *= 1.0 + rng.uniform(-0.14, 0.14)
            v.co.y *= 1.0 + rng.uniform(-0.14, 0.14)
        bmesh.ops.translate(bm, vec=(rng.uniform(-0.08, 0.08) * r, rng.uniform(-0.08, 0.08) * r, z0 + tier_h / 2), verts=bm.verts)
        bm.to_mesh(m); bm.free()
        ob = K.obj("%s_tier%d" % (name, t), m, K.mat("fir_dark" if t % 2 else "fir"))
        for poly in ob.data.polygons:
            poly.use_smooth = False
    # The tip, lit.
    tip = bpy.data.meshes.new("%s_tip" % name)
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=7, radius1=r * 0.22, radius2=0.01, depth=h * 0.16)
    bmesh.ops.translate(bm, vec=(0.0, 0.0, h * 0.92), verts=bm.verts)
    bm.to_mesh(tip); bm.free()
    ob = K.obj("%s_tip" % name, tip, K.mat("fir_light"))
    for poly in ob.data.polygons:
        poly.use_smooth = False
    # Bare lower boughs.
    for i in range(4):
        ang = i * 1.57 + rng.uniform(-0.4, 0.4)
        K._taper("%s_bough%d" % (name, i), (0.0, 0.0, base_z * rng.uniform(0.7, 1.0)),
                 (math.cos(ang) * r * 0.8, math.sin(ang) * r * 0.8, base_z * 0.75),
                 r * 0.05, r * 0.015, K.mat("bark"), segments=5)


def build_tree(level: int) -> dict:
    # A tree is far smaller than a works: the rig is framed tight on it so the 1024 render
    # carries the facets. One framing for all three, so the export's shared scale holds.
    setup_rig(ortho_scale=5.6, target=(0.0, 0.0, 1.55))
    K = Kit(open_collection("BLDG_tree"))
    if level == 1:
        _broadleaf(K, "small", h=2.0, r=0.62, seed=11, limbs=4, under=3)
    elif level == 2:
        _fir(K, "fir", h=3.4, r=0.72, seed=23, tiers=5)
    else:
        _broadleaf(K, "large", h=3.1, r=0.98, seed=37, limbs=6, under=5)
    return {"building": "tree", "level": level, "objects": len(K.col.objects)}
