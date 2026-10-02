"""Houses and apartment blocks for the capsule, in the sprite kit's style.

The game has no housing sprites, so these are new. They are drawn to the scale the capsule
shows the game's buildings at (half their sprite size), and kept below them: a home's storey
is 0.45 against the halved factory's 0.55, and blocks run to three or four storeys, so the
works stay the tallest things on the plate.

Windows are PAINTED, not built: one mesh of glass quads just proud of every wall, carrying
no ink. At this size a framed window (glass, four frame strips, sill,
mullions) is mostly outline, which is why the kit's window assembly is kept for the game's
own buildings only. Roofs are two slabs over a wall-coloured gable, so the gable ends read
as wall. The front is -Y, where the door is: buildings are turned to face their street
(buildings.py), so every wall carries windows.

    apartment_block(K, name, cx, cy, w, d, floors, variant)
    terrace(K, name, cx, cy, n, variant)       # n houses side by side along X
"""
import math

import bmesh
import bpy

# A home's storey is lower than a works' (about 3 m against 4 or more), so housing stays
# below the industry it serves: 0.45 against the halved factory's 0.55 a floor.
FLOOR = 0.45                     # one storey
WIN_W, WIN_H, SILL = 0.17, 0.22, 0.12
BAY = 0.36                       # window pitch along a wall
PROUD = 0.008                    # painted windows sit this far off the wall
PALETTE["roof_tile"] = (0.300, 0.105, 0.070)       # red clay, for house roofs

# (wall, trim) per variant: trim is the parapet or the ground-floor band.
BLOCK_WALLS = [("chalk", "deck"), ("wall_brick", "chalk"), ("slab_cream", "wall_brick"),
               ("white_wall", "roof")]
HOUSE_WALLS = [("chalk", "roof_tile"), ("wall_brick", "roof"), ("slab_cream", "roof_tile"),
               ("white_wall", "roof")]


def _noink(ob):
    """Mark every face: the capsule's linesets leave marked faces out."""
    me = ob.data
    attr = me.attributes.get("freestyle_face") or me.attributes.new("freestyle_face", 'BOOLEAN', 'FACE')
    for d in attr.data:
        d.value = True


def _painted(K, name, quads, mat):
    """One mesh of flat quads (each four world points), no ink."""
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    for q in quads:
        bm.faces.new([bm.verts.new(p) for p in q])
    bm.to_mesh(me)
    bm.free()
    ob = K.obj(name, me, K.mat(mat))
    _noink(ob)
    return ob


def _openings(x0, x1, y0, y1, z0, floors, door=True):
    """Window quads on all four walls of a box, and a door quad in the middle of the -Y wall,
    the front. All four, because a building turned to face its street can show any two."""
    wins, doors = [], []
    nx = max(1, int(round((x1 - x0) / BAY)))
    ny = max(1, int(round((y1 - y0) / BAY)))
    door_i = nx // 2 if door else None
    for f in range(floors):
        zb = z0 + f * FLOOR + SILL
        zt = zb + WIN_H
        for i in range(nx):
            xc = x0 + (i + 0.5) * (x1 - x0) / nx
            for yf in (y0 - PROUD, y1 + PROUD):
                if f == 0 and i == door_i and yf < y0:
                    dw = WIN_W * 0.95
                    doors.append([(xc - dw / 2, yf, z0), (xc + dw / 2, yf, z0),
                                  (xc + dw / 2, yf, z0 + FLOOR * 0.70), (xc - dw / 2, yf, z0 + FLOOR * 0.70)])
                    continue
                wins.append([(xc - WIN_W / 2, yf, zb), (xc + WIN_W / 2, yf, zb),
                             (xc + WIN_W / 2, yf, zt), (xc - WIN_W / 2, yf, zt)])
        for j in range(ny):
            yc = y0 + (j + 0.5) * (y1 - y0) / ny
            for xf in (x0 - PROUD, x1 + PROUD):
                wins.append([(xf, yc - WIN_W / 2, zb), (xf, yc + WIN_W / 2, zb),
                             (xf, yc + WIN_W / 2, zt), (xf, yc - WIN_W / 2, zt)])
    return wins, doors


def apartment_block(K, name, cx, cy, w, d, floors, variant=0, z0=0.0):
    """A flat-roofed slab block: walls, a parapet lip, a darker ground-floor band,
    painted windows and a door."""
    wall, trim = BLOCK_WALLS[variant % len(BLOCK_WALLS)]
    h = floors * FLOOR
    x0, x1, y0, y1 = cx - w / 2, cx + w / 2, cy - d / 2, cy + d / 2
    K.box(name + "_body", cx, cy, z0 + h / 2, w, d, h, K.mat(wall))
    K.box(name + "_band", cx, cy, z0 + 0.06, w + 0.02, d + 0.02, 0.12, K.mat(trim))
    # Flat roof: a dark deck inside a parapet ring, so the roof reads as a roof.
    K.box(name + "_deck", cx, cy, z0 + h + 0.01, w - 0.08, d - 0.08, 0.02, K.mat("deck"))
    pw, ph = 0.05, 0.08
    for tag, px_, py_, sx, sy in (("s", cx, y0 + pw / 2, w, pw), ("n", cx, y1 - pw / 2, w, pw),
                                  ("w", x0 + pw / 2, cy, pw, d - 2 * pw), ("e", x1 - pw / 2, cy, pw, d - 2 * pw)):
        K.box("%s_lip_%s" % (name, tag), px_, py_, z0 + h + ph / 2, sx, sy, ph, K.mat(wall))
    # A stair and lift house on the roof, set back from the camera side.
    K.box(name + "_core", cx - w * 0.22, cy + d * 0.18, z0 + h + 0.17, w * 0.18, d * 0.36, 0.30,
          K.mat(wall))
    wins, doors = _openings(x0, x1, y0, y1, z0, floors)
    _painted(K, name + "_win", wins, "window_glass")
    _painted(K, name + "_door", doors, "door")


def house(K, name, cx, cy, w, d, floors=2, variant=0, z0=0.0, chimney=True):
    """A gable-roofed house, ridge along X: walls, a wall-coloured gable at each end, two
    roof slabs with an overhang, painted windows, a door and a chimney stack."""
    wall, roof = HOUSE_WALLS[variant % len(HOUSE_WALLS)]
    h = floors * FLOOR
    pitch = math.radians(38.0)
    rise = (d / 2.0) * math.tan(pitch)
    x0, x1, y0, y1 = cx - w / 2, cx + w / 2, cy - d / 2, cy + d / 2
    K.box(name + "_body", cx, cy, z0 + h / 2, w, d, h, K.mat(wall))
    # Gable infill: the triangle above the eaves, in wall colour, the house's full length.
    K.prism(name + "_gable", (cx, cy, z0 + h), (0.0, 1.0),
            [(-d / 2, 0.0), (d / 2, 0.0), (0.0, rise)], w, K.mat(wall))
    # Roof: two slabs, overhanging the eaves and the gables.
    oh, t = 0.07, 0.05
    slope = (d / 2.0 + oh) / math.cos(pitch)
    for side, sgn in (("s", -1.0), ("n", 1.0)):
        ang = math.degrees(pitch) * (1 if sgn < 0 else -1)
        ycen = cy + sgn * (d / 4.0 + oh / 2.0)
        zcen = z0 + h + rise / 2.0 - oh * math.tan(pitch) / 2.0 + t / 2.0
        K.rotbox(name + "_roof_" + side, cx, ycen, zcen, w + 2 * oh, slope, t, K.mat(roof), 'X', ang)
    if chimney:
        K.box(name + "_chimney", cx + w * 0.28, cy + d * 0.12, z0 + h + rise * 0.75, 0.10, 0.10,
              rise * 0.9, K.mat("wall_brick"))
    wins, doors = _openings(x0, x1, y0, y1, z0, floors)
    _painted(K, name + "_win", wins, "window_glass")
    _painted(K, name + "_door", doors, "door")


def terrace(K, name, cx, cy, n, variant=0, w=0.80, d=0.85, floors=2):
    """n houses side by side along X, alternating finishes, each with its own roof."""
    gap = 0.10
    span = n * w + (n - 1) * gap
    for i in range(n):
        x = cx - span / 2 + w / 2 + i * (w + gap)
        house(K, "%s_%d" % (name, i), x, cy, w, d, floors, variant + i, chimney=(i % 2 == 0))


# ---------------------------------------------------------------- sprites for the game
# The supply chain board stands housing on the slots a tile's works do not use. Three sets,
# baked as house_lvl1..3 (bake_sprite.py): a short terrace, two terraces back to back, and a
# block of flats with a terrace beside it. The number is a variety, not an upgrade. They stand
# straight on the ground: a works has a concrete pad under it, a home does not.
def build_house(level: int = 1) -> dict:
    setup_rig(target=(0.0, 0.0, 0.75))
    # Painted windows carry no ink: the linesets leave out faces marked for it.
    fs = bpy.context.scene.view_layers[0].freestyle_settings
    for ls in fs.linesets:
        ls.select_by_face_marks = True
        ls.face_mark_negation = 'EXCLUSIVE'
        ls.face_mark_condition = 'ONE'
    K = Kit(open_collection("BLDG_house"))
    if level == 1:
        terrace(K, "row", 0.0, 0.0, 3, variant=1)
    elif level == 2:
        terrace(K, "front", 0.0, -0.75, 3, variant=0)
        terrace(K, "back", 0.0, 0.75, 3, variant=2)
    else:
        apartment_block(K, "flats", -0.35, 0.45, 2.0, 1.25, 4, variant=1)
        terrace(K, "row", 0.45, -0.95, 2, variant=3)
    return {"building": "house", "level": level, "objects": len(K.col.objects)}


# ---------------------------------------------------------------- a city's towers
PALETTE["curtain"] = (0.120, 0.190, 0.290)         # a glass curtain wall: blue, lighter than a window
PALETTE["curtain_dark"] = (0.075, 0.115, 0.190)


def _frustum(K, name, cx, cy, z0, half0, half1, h, mat):
    """A square pyramid with its top cut off: base half-width half0 at z0, half1 at z0 + h."""
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    lo = [bm.verts.new((cx + sx * half0, cy + sy * half0, z0)) for sx, sy in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
    hi = [bm.verts.new((cx + sx * half1, cy + sy * half1, z0 + h)) for sx, sy in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
    bm.faces.new(hi)
    for i in range(4):
        bm.faces.new([lo[i], lo[(i + 1) % 4], hi[(i + 1) % 4], hi[i]])
    bm.to_mesh(me)
    bm.free()
    return K.obj(name, me, K.mat(mat))


def stone_tower(K, name, cx, cy, w, floors):
    """Steel and concrete: concrete piers at the corners and between bays, a dark steel
    spandrel under every floor's windows, two setbacks and a flattened pyramid on top."""
    h = floors * FLOOR
    K.box(name + "_body", cx, cy, h / 2, w, w, h, K.mat("chalk"))
    K.box(name + "_base", cx, cy, 0.20, w + 0.10, w + 0.10, 0.40, K.mat("shell"))
    x0, x1, y0, y1 = cx - w / 2, cx + w / 2, cy - w / 2, cy + w / 2
    wins, _ = _openings(x0, x1, y0, y1, 0.0, floors, door=False)
    _painted(K, name + "_win", wins, "window_glass")
    # Steel spandrels, a thin band at each floor line on the two walls the camera sees.
    bands = []
    for f in range(1, floors + 1):
        z = f * FLOOR - 0.035
        bands.append([(x0, y0 - PROUD, z), (x1, y0 - PROUD, z), (x1, y0 - PROUD, z + 0.07), (x0, y0 - PROUD, z + 0.07)])
        bands.append([(x1 + PROUD, y0, z), (x1 + PROUD, y1, z), (x1 + PROUD, y1, z + 0.07), (x1 + PROUD, y0, z + 0.07)])
    _painted(K, name + "_spandrel", bands, "steel_navy")
    for i, (sx, sy) in enumerate(((-1, -1), (1, -1), (1, 1), (-1, 1))):
        K.box("%s_pier%d" % (name, i), cx + sx * (w / 2 - 0.04), cy + sy * (w / 2 - 0.04), h / 2,
              0.14, 0.14, h + 0.02, K.mat("shell"))
    K.box(name + "_crown", cx, cy, h + 0.10, w + 0.06, w + 0.06, 0.20, K.mat("shell"))
    K.box(name + "_set", cx, cy, h + 0.38, w * 0.74, w * 0.74, 0.36, K.mat("chalk"))
    _frustum(K, name + "_cap", cx, cy, h + 0.56, w * 0.40, w * 0.13, 0.42, "steel_navy")
    K.box(name + "_mast", cx, cy, h + 1.20, 0.035, 0.035, 0.46, K.mat("silver"))
    return h + 1.43


def glass_tower(K, name, cx, cy, w, floors):
    """Glass outside: a curtain wall ruled by thin mullions and floor lines, a flat roof
    with a parapet and a plant room."""
    h = floors * FLOOR
    K.box(name + "_body", cx, cy, h / 2, w, w, h, K.mat("curtain"))
    K.box(name + "_lobby", cx, cy, 0.24, w + 0.02, w + 0.02, 0.48, K.mat("curtain_dark"))
    x0, x1, y0, y1 = cx - w / 2, cx + w / 2, cy - w / 2, cy + w / 2
    rules = []
    t = 0.022
    for f in range(1, floors):
        z = f * FLOOR
        rules.append([(x0, y0 - PROUD, z), (x1, y0 - PROUD, z), (x1, y0 - PROUD, z + t), (x0, y0 - PROUD, z + t)])
        rules.append([(x1 + PROUD, y0, z), (x1 + PROUD, y1, z), (x1 + PROUD, y1, z + t), (x1 + PROUD, y0, z + t)])
    n = 5
    for i in range(1, n):
        u = i / float(n)
        xa = x0 + u * w
        ya = y0 + u * w
        rules.append([(xa - t / 2, y0 - PROUD, 0.48), (xa + t / 2, y0 - PROUD, 0.48), (xa + t / 2, y0 - PROUD, h), (xa - t / 2, y0 - PROUD, h)])
        rules.append([(x1 + PROUD, ya - t / 2, 0.48), (x1 + PROUD, ya + t / 2, 0.48), (x1 + PROUD, ya + t / 2, h), (x1 + PROUD, ya - t / 2, h)])
    _painted(K, name + "_rules", rules, "silver")
    K.box(name + "_deck", cx, cy, h + 0.01, w - 0.08, w - 0.08, 0.02, K.mat("deck"))
    pw, ph = 0.05, 0.10
    for tag, px_, py_, sx, sy in (("s", cx, y0 + pw / 2, w, pw), ("n", cx, y1 - pw / 2, w, pw),
                                  ("w", x0 + pw / 2, cy, pw, w - 2 * pw), ("e", x1 - pw / 2, cy, pw, w - 2 * pw)):
        K.box("%s_lip_%s" % (name, tag), px_, py_, h + ph / 2, sx, sy, ph, K.mat("silver"))
    K.box(name + "_plant", cx - w * 0.14, cy + w * 0.14, h + 0.14, w * 0.36, w * 0.36, 0.26, K.mat("annex_grey"))
    return h + 0.28


# A city tile's two towers on the supply chain board, each its own sprite so a crossroads
# can lie between them: 1 is ten floors of steel and concrete under a flattened pyramid, 2 is
# fourteen of glass with a flat roof. One camera for both, so they share a scale.
def build_towers(level: int = 1) -> dict:
    setup_rig(target=(0.0, 0.0, 3.3))
    fs = bpy.context.scene.view_layers[0].freestyle_settings
    for ls in fs.linesets:
        ls.select_by_face_marks = True
        ls.face_mark_negation = 'EXCLUSIVE'
        ls.face_mark_condition = 'ONE'
    K = Kit(open_collection("BLDG_house"))
    if level == 1:
        stone_tower(K, "stone", 0.0, 0.0, 1.30, 10)
    else:
        glass_tower(K, "glass", 0.0, 0.0, 1.25, 14)
    return {"building": "towers", "level": level, "objects": len(K.col.objects)}
