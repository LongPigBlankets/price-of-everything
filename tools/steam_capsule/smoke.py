"""Smoke from the stacks (owner): the game's puff, strung into plumes.

    build_smoke()          # after the camera is framed, so the plumes stay out of the framing

The puff is the goods FX puff (`goods_icon_batch3_fx.py`): one big sphere, a ring of medium
ones round its upper half and a few small ones in the gaps, flattened a little, with two or
three darker patch spheres tucked in; inked round every sphere so the cloud scallops. Grey
from the furnaces and the power plant's flue, near-white steam from the cooling tower.

A plume climbs from the stack's mouth and bends over downwind as it rises. Its puffs grow
along it, each overlapping the last so the plume reads as one body, and near its end they
shrink and draw apart as it breaks up. The wind blows off the sea, so every plume drifts
north-west, over the plate's darker side, as the AI concept's smoke does. The puffs take the
thin line and cast no shadow (they would print as dot bands on the ground). The factory's
chimney is left without: any plume from it drifts across the rail bridge.
"""
import math
import random

import bmesh
from mathutils import Vector

# Stack mouth (its object, as buildings.py names it) -> kind, rise, drift and the plume's
# widest puff radius, in world units.
STACKS = {
    "Electric_arc_furnace.back_pipe0_cap": ("smoke", 1.5, 2.6, 0.62),
    "Electric_arc_furnace.back_pipe1_cap": ("smoke", 1.8, 3.0, 0.70),
    "Power_plant.flue_mouth": ("smoke", 2.1, 3.4, 0.80),
    "Power_plant.tower_rim": ("steam", 1.1, 1.5, 0.85),
}
OVERLAP = 0.80                            # puff spacing, as a share of the puff's radius
BREAK_UP = 0.78                           # past this share of the plume, it breaks up
WIND_MAP = (-1.0, 1.0)                    # map north-west: off the sea, over the dark side
# The game's puff colours, the smoke a step lighter: at the puffs' size on the plate, the
# game's grey reads as soot against the navy.
PUFF_COLOURS = {"smoke": ((0.27, 0.265, 0.255), (0.14, 0.135, 0.13)),
                "steam": ((0.90, 0.92, 0.93), (1.0, 1.0, 1.0))}


def _puff_spheres(rng):
    """The goods FX puff in unit size: (centre, radius, patch?) for each sphere."""
    spheres = [(Vector((0, 0, 0)), 1.00, False)]
    n = rng.randint(5, 7)
    for i in range(n):
        ang = 2 * math.pi * i / n + rng.uniform(-0.3, 0.3)
        rr = rng.uniform(0.85, 1.05)
        spheres.append((Vector((rr * math.cos(ang), rr * math.sin(ang), rng.uniform(-0.15, 0.45))),
                        rng.uniform(0.48, 0.70), False))
    for _ in range(rng.randint(2, 4)):
        ang = rng.uniform(0, 2 * math.pi)
        rr = rng.uniform(1.1, 1.35)
        spheres.append((Vector((rr * math.cos(ang), rr * math.sin(ang), rng.uniform(-0.1, 0.3))),
                        rng.uniform(0.28, 0.42), False))
    patches = set(rng.sample(range(1, len(spheres)), min(3, len(spheres) - 1)))
    out = []
    for i, (c, r, _) in enumerate(spheres):
        if i in patches:
            c, r = c * 0.75, r * 0.9
        out.append((Vector((c.x, c.y, c.z * 0.85)), r, i in patches))
    return out


def _sphere(K, name, c, r, mat):
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=18, v_segments=12, radius=r)
    bmesh.ops.translate(bm, vec=c, verts=bm.verts)
    bm.to_mesh(me)
    bm.free()
    ob = K.obj(name, me, mat)
    for poly in me.polygons:
        poly.use_smooth = True
    ob.visible_shadow = False
    return ob


def _mouth(ob):
    pts = [ob.matrix_world @ Vector(c) for c in ob.bound_box]
    cx = sum(p.x for p in pts) / 8.0
    cy = sum(p.y for p in pts) / 8.0
    r = (max(p.x for p in pts) - min(p.x for p in pts) + max(p.y for p in pts) - min(p.y for p in pts)) / 4.0
    return Vector((cx, cy, max(p.z for p in pts))), r


def build_smoke():
    for kind, (base, patch) in PUFF_COLOURS.items():
        PALETTE["%s_puff" % kind] = base
        PALETTE["%s_patch" % kind] = patch
    col = bpy.data.collections.new("CAP_Smoke")
    bpy.context.scene.collection.children.link(col)
    K = Kit(col)
    K._fine_mode = True                                        # the thin line, like small parts
    wx, wy = map_to_world(WIND_MAP[0], WIND_MAP[1], PLATE_YAW)
    ox, oy = map_to_world(0.0, 0.0, PLATE_YAW)
    wind = Vector((wx - ox, wy - oy, 0.0)).normalized()
    up = Vector((0.0, 0.0, 1.0))
    made = 0
    for stack, (kind, rise, drift, r_end) in STACKS.items():
        ob = bpy.data.objects.get(stack)
        if ob is None:
            print("SMOKE: no stack", stack)
            continue
        mouth, r0 = _mouth(ob)
        base, patch = K.mat("%s_puff" % kind), K.mat("%s_patch" % kind)
        rng = random.Random(stack)

        def along(s):
            return mouth + wind * (drift * s ** 1.25) + up * (rise * (1.0 - (1.0 - s) ** 2))

        def radius(s):
            rho = r0 * 1.4 + (r_end - r0 * 1.4) * min(1.0, s / BREAK_UP) ** 0.8
            return rho * (1.0 - 0.55 * max(0.0, s - BREAK_UP) / (1.0 - BREAK_UP))

        s, k = 0.0, 0
        while s <= 1.0:
            rho = radius(s)
            centre = along(s) + up * (rho * 0.55)
            scale = rho / 1.6
            for i, (c, r, is_patch) in enumerate(_puff_spheres(rng)):
                _sphere(K, "Smoke.%s_%d_%d" % (stack.split(".")[-1], k, i), centre + c * scale, r * scale,
                        patch if is_patch else base)
                made += 1
            # step on by a share of the radius (wider apart as it breaks up)
            gap = rho * (OVERLAP if s < BREAK_UP else 1.6)
            ds = 0.002
            while s + ds <= 1.0 and (along(s + ds) - along(s)).length < gap:
                ds += 0.002
            s += ds
            k += 1
    print("SMOKE: %d puff spheres" % made)
    return col
