"""The game's own buildings on the capsule plate, from the builders their sprites were baked by.

    placed = build_buildings(R, yaw)        # BEFORE the capsule's rig and plate
    ...restate the rig, build the plate with pits_of(placed), the infra...
    finish_buildings(placed)                # just before rendering

Every building is built by its sprite builder in a namespace of its own (two builders in one
namespace feed each other their LEVELS tables), then moved into place. Nothing is scaled or
turned. The capsule camera keeps the sprite rig's 45-degree yaw, so the faces each builder
details (-Y and +X) are still the ones in view, and each building keeps the size it was
approved at, which puts one or two on a tile.

Builders are written to make one sprite per scene, so three of their habits are undone here:
  * each calls setup_rig(), which resets the render settings, so the capsule restates its
    rig after build_buildings();
  * open_collection() hides every other BLDG_* collection and unlinks everything from
    FINE_INK. A finished building is renamed out of BLDG_*, and finish_buildings() relinks
    its fine-ink parts (turbine blades, pylons, lattice) so they keep the thinner line;
  * materials are shared by name and a builder may redefine one for itself (the assembly
    plant's `crate` is black, the factory's is wood). Each building gets its own copies, and
    its objects get its name as a prefix so later builders' names cannot collide with them.
"""
import math
import os

import bpy
from mathutils import Matrix, Vector

SKILL_DIR = os.path.normpath(os.path.join(HERE, "..", "..", ".claude", "skills", "blender-building-sprites"))
# mine_builder.py never made it into the repo; the copy the shipped mine sprite came from is here.
ASSET_DIR = "/Users/crisu/Price of Everything/blender-assets"

# source: (directory, builder file, build function, sprite collection)
SOURCES = {
    "mine": (ASSET_DIR, "mine_builder.py", "build_mine", "BLDG_mine"),
    "furnace": (SKILL_DIR, "furnace_builder.py", "build_furnace", "BLDG_furnace"),
    "eaf": (SKILL_DIR, "eaf_builder.py", "build_eaf", "BLDG_eaf"),
    "office": (SKILL_DIR, "office_builder.py", "build_office", "BLDG_office"),
    "power_plant": (SKILL_DIR, "power_plant_builder.py", "build_power_plant", "BLDG_powerplant"),
    "industrial_factory": (SKILL_DIR, "factory_builder.py", "build_factory", "BLDG_factory"),
    "assembly_plant": (SKILL_DIR, "assembly_plant_builder.py", "build_assembly_plant", "BLDG_assembly"),
    "high_tech_manufactory": (SKILL_DIR, "high_tech_builder.py", "build_high_tech", "BLDG_hightech"),
    "solar_farm": (SKILL_DIR, "solar_farm_builder.py", "build_solar_farm", "BLDG_solar"),
    "chem_plant": (SKILL_DIR, "chem_plant_builder.py", "build_chem_plant", "BLDG_chem"),
    "wind": (SKILL_DIR, "wind_farm_builder.py", None, None),            # parts only
    "electrolyser": (SKILL_DIR, "electrolyser_builder.py", None, None),  # parts only
    "docks": (SKILL_DIR, "docks_builder.py", None, None),                # parts only
    "vehicles": (SKILL_DIR, "vehicles_kit.py", None, None),              # the film's cars
}

# (label, source, level, map x, map y, scale, turn): where the centre of the building's
# footprint goes, in units of R in the plate's map frame, its size against its sprite, and its
# turn in degrees. The sun stands over the sea, off the right of the frame, so the +X walls
# are lit and the -Y walls shaded. A sprite details its -Y front, so the buildings whose front
# is the show (the power hall's windows) turns +90 to bring it round to +X, into the light;
# the side that comes round into view on the shaded side is plain but whole. The arc
# furnace turns +45, so its bay faces the camera square on (owner); the high tech glass hall
# and the EV plant's open line +20, most of the way back to the sprite's own three-quarter
# view, so their fronts face the camera and a side shows too (owner). The factory's long window wall is already its +X side, so it stays as
# built. Coal and heavy industry at the back, the clean end at the front, as in the concept.
# EV Assembly is an Assembly Plant recipe, so that is the EV plant. The works stand at half
# their sprite size (owner), which leaves each tile room for a town; the mine keeps its size,
# its pit being cut into the plate. The works are at 0.6 (owner: half, then a fifth bigger)
# and the EAF at 0.45 (owner): its level-2 melt shop is far the biggest of them.
PLACEMENTS = [
    ("Mine", "mine", 3, -3.50, 0.02, 1.0, 0),
    ("Power plant", "power_plant", 3, -0.94, 1.62, 0.6, 90),
    ("Electric arc furnace", "eaf", 3, -2.80, 1.55, 0.45, 45),
    ("Industrial goods factory", "industrial_factory", 3, -2.93, -1.38, 0.6, 0),
    ("High tech manufactory", "high_tech_manufactory", 3, -1.97, -2.72, 0.6, 20),
    ("Assembly plant", "assembly_plant", 3, -0.79, -4.53, 0.6, 20),
    ("Chemical plant", "chem_plant", 3, -1.72, -0.915, 0.48, 0),
]
# Houses and offices stand on lots along the roads (owner): (label, kind, road, at, side, params).
# `road` indexes blockout's ROADS, `at` is how far along it (0 to 1) and `side` which side
# (+1 left of its direction, -1 right). Each is turned to face the road, its front (-Y, the
# door side) toward it, SETBACK back from the road's edge. Kinds: "office" (the office builder,
# `variant`, at `scale`), "block" (`floors`) and "terrace" (`count` houses) from housing.py.
SETBACK = 0.16
# Owner: homes well below the works, "even smaller than the buildings", so houses and blocks go
# at half the size housing.py draws them; offices at 70% of their first size (0.4 -> 0.28).
HOUSING_SCALE = 0.5
FRONTAGE = [
    # the town, inside the river's bend
    ("Office", "office", 3, 0.35, -1, dict(variant=3, scale=0.28)),
    ("Apartments", "block", 0, 0.28, 1, dict(floors=4, variant=0)),
    ("Terrace 2", "terrace", 4, 0.72, -1, dict(count=3, variant=1)),
    ("Terrace 7", "terrace", 5, 0.14, 1, dict(count=2, variant=2)),
    # by the harbour and the factory
    ("Office 3", "office", 1, 0.10, -1, dict(variant=2, scale=0.28)),
    ("Apartments 2", "block", 1, 0.24, 1, dict(floors=3, variant=1)),
    ("Terrace", "terrace", 1, 0.52, 1, dict(count=4, variant=0)),
    ("Terrace 4", "terrace", 1, 0.34, -1, dict(count=3, variant=3)),
    # down the spine and the front road
    ("Office 2", "office", 0, 0.50, -1, dict(variant=1, scale=0.28)),
    ("Apartments 3", "block", 0, 0.72, -1, dict(floors=3, variant=2)),
    ("Terrace 5", "terrace", 1, 0.60, -1, dict(count=2, variant=1)),
    # the north road, west of the river
    ("Terrace 6", "terrace", 5, 0.92, 1, dict(count=2, variant=0)),
]
# Wind turbines from the wind farm's own machine, standing along the bay shore: map x, map y
# (units of R) and hub height (world units; the farm's run 2.70 to 3.85).
TURBINES = [(0.52, -2.45, 3.05), (0.70, -2.95, 2.85), (0.62, -3.50, 3.20)]
TURBINE_WHITE = (0.80, 0.79, 0.77)
# Offshore wind in the distant sea, in the back-right tile and the far-right one:
# the same machines on monopiles, and nothing else, as the game's offshore farm has no yard.
# Three, in the back-right tile: the two dead ahead of the ship as it leaves the harbour, and
# the lone one on the east tile, are gone (owner).
OFFSHORE = [(0.55, 2.00, 3.30), (1.25, 1.95, 3.55), (0.95, 1.25, 3.40)]
# Solar: the solar farm's own panel rows (modules on bents and rails), without the rest of the
# farm sprite. Centre (map, units of R), rows, panels per row.
SOLAR = ((-0.03, -3.20), 4, 5)
# The panels face the sun (owner): the key art is laid out mirrored, its light from the left,
# so the array is mirrored on screen, left to right, about its own centre: reflected across
# the upright plane through the camera's line of sight (the rig looks along (-1, 1) in plan,
# render_earth_plate.py's 45-degree yaw). Its panels then tilt toward the lower left of the
# mirrored picture, toward the light, and still show their faces to the camera.
SOLAR_MIRROR = True
# The EV plant's lot of finished cars (owner): five rows of five on a concrete pad between the
# high tech manufactory and the EV plant, with a green charging unit at the road end. The car
# is the game's own Blender sedan, the diesel goods icon's (committed with the goods icons,
# read from that commit), without its jerry can and repainted per bay. Centre (map, units of
# R), rows, cars per row, and the turn that lays the rows along the gap (the cars then stand
# side-on to the camera). A car is EV_LENGTH long: a little over a storey beside the works.
DIESEL_SRC = ("2245ef44", "price-of-everything-0.1/tools/goods_icons/complex_goods/diesel_car/source")
EV_LOT = ((-1.575, -3.57), 5, 5, 57.0)
EV_LENGTH = 0.76
EV_FACES = (1500, 150)          # most faces a car part keeps: the body and glass, the small parts
EV_BAY = 0.30                   # the pad's run past the rows, for the charging unit
EV_CHARGER = 1.2                # its scale: a little over a car's height, as a real post stands
EV_COLOURS = [(0.62, 0.60, 0.55), (0.14, 0.26, 0.45), (0.23, 0.32, 0.37), (0.16, 0.34, 0.22),
              (0.50, 0.12, 0.09)]          # cream, blue, the icon's own steel, green, red
# Grid batteries: the electrolyser's battery block, in a row. Centre (map, units of R), count.
BATTERIES = ((-0.22, -2.18), 3, 0.5)          # centre, units, scale
# The harbour, from the port sprite's own parts: a pier out into the bay along world +Y, a
# container ship alongside on its +X side under a gantry crane, containers at the root. The
# port builds all of these along X with the water at -Y; turned a quarter to the left (+90
# degrees) the faces it details (-Y, and the crane cab and the ship's house at -X) come round
# to +X and -Y, which the camera still sees.
PIER = ((-0.62, -0.81), 7.0, 2.0, 0.35)     # root (map, units of R), length, width, deck z
SHIP = (6.2, 1.35, 0.743)                    # length, beam (the port's), centre along the pier

# Parts a sprite carries only because it stands alone. The mine stands on its own block of
# earth (pit ring 0, banded down its cut faces) with the shaft drawn in section on the block's
# edge; the farms stand on a raised turf slab with banded sides. Here the plate is the ground,
# so those go, and each building drops by the slab's height to stand on the plate's top.
STRIP = {
    "mine": ("pit_ring0_", "shaft_"),
    "solar_farm": ("ground", "turf", "strat"),
}
KEEP = {"shaft_mouth"}                       # the shaft's opening under the headframe stays
EPS_Z = 0.004                                # clears the plate top: aprons are built flush at z = 0
NEAR_GROUND = 0.30                           # objects starting lower than this make the footprint


def _slug(label):
    return label.replace(" ", "_")


_ns_cache = {}


def _namespace(src):
    """The kit and one builder, exec'd into a namespace of their own."""
    if src not in _ns_cache:
        d, file, _, _ = SOURCES[src]
        ns = {"__name__": "capsule_" + src}
        exec(open(os.path.join(d, "sprite_kit.py")).read(), ns)
        exec(open(os.path.join(d, file)).read(), ns)
        _ns_cache[src] = ns
    return _ns_cache[src]


def _adopt(col, slug):
    """Take a finished building out of the builders' way: rename its collection and
    objects, record its fine-ink parts, give it its own materials."""
    col.name = "CAP_" + slug
    fine = bpy.data.collections.get("FINE_INK")
    fine_objs = [ob for ob in col.objects if fine is not None and ob.name in fine.objects]
    copies = {}
    for ob in list(col.objects):
        ob.name = "%s.%s" % (slug, ob.name)
        if ob.type != 'MESH':
            continue
        for i, m in enumerate(ob.data.materials):
            if m is None:
                continue
            if m.name not in copies:
                c = m.copy()
                c.name = "%s@%s" % (m.name, slug)
                copies[m.name] = c
            ob.data.materials[i] = copies[m.name]
    return fine_objs


def _strip(col, prefixes):
    """Delete the parts named by `prefixes`. Runs before _adopt renames anything."""
    gone = 0
    for ob in list(col.objects):
        if ob.name in KEEP:
            continue
        if any(ob.name.startswith(p) for p in prefixes):
            bpy.data.objects.remove(ob, do_unlink=True)
            gone += 1
    return gone


def _xy_extent(objs):
    xs, ys, zs = [], [], []
    for ob in objs:
        if ob.type != 'MESH':
            continue
        mw = ob.matrix_world
        for v in ob.data.vertices:
            w = mw @ v.co
            xs.append(w.x)
            ys.append(w.y)
            zs.append(w.z)
    return (min(xs), max(xs), min(ys), max(ys), min(zs), max(zs))


def _move(objs, dx, dy, dz):
    T = Matrix.Translation((dx, dy, dz))
    for ob in objs:
        ob.matrix_world = T @ ob.matrix_world


def _place(objs, R, yaw, mx, my, dz, scale=1.0, turn=0.0):
    """Move so the footprint's centre lands on map (mx, my), units of R, scaled and turned
    about that centre at ground level, and dropped by dz."""
    x0, x1, y0, y1, _, _ = _xy_extent(objs)
    cx, cy = (x0 + x1) / 2.0, (y0 + y1) / 2.0
    tx, ty = map_to_world(mx * R, my * R, yaw)
    M = (Matrix.Translation((tx, ty, dz + EPS_Z)) @ Matrix.Rotation(math.radians(turn), 4, 'Z')
         @ Matrix.Scale(scale, 4) @ Matrix.Translation((-cx, -cy, 0.0)))
    for ob in objs:
        ob.matrix_world = M @ ob.matrix_world
    return tx - cx * scale, ty - cy * scale


def _redo_parts(src, ns, col, level):
    """Swap the parts that turn to mush at capsule scale for the bold versions in
    capsule_parts.py, in the building's own frame, before it is moved."""
    K = ns["Kit"](col)
    if src == "mine":
        for ob in list(col.objects):
            if (ob.name.startswith("head_") and ob.name != "head_plinth") or \
                    ob.name in ("rope0", "rope1", "cage", "cage_seam"):
                bpy.data.objects.remove(ob, do_unlink=True)
        g, outer = ns["MINE_LEVELS"][level]["ground"], ns["OUTER"]
        bold_headframe(K, "head", outer[1] - 0.64, 0.25, g + 0.24, 2.30, w=0.66,
                       strut_dy=-1.05, strut_foot_z=g + 0.10)
    elif src == "power_plant":
        for ob in list(col.objects):
            if ob.name.startswith(("tx", "feed", "fence_", "gantry", "pylon")):
                bpy.data.objects.remove(ob, do_unlink=True)
        py_h, py_w, _, _ = ns["PP_LEVELS"][level]["pylon"]
        bold_switchyard(K, ns["YARD"], ns["PAD_H"], ns["PYLON_XY"], py_h, py_w)


def _building(label, src, level, mx, my, R, yaw, scale=1.0, turn=0.0):
    d, file, fn, col_name = SOURCES[src]
    ns = _namespace(src)
    result = ns[fn](level) if level else ns[fn]()
    col = bpy.data.collections[col_name]
    _redo_parts(src, ns, col, level)
    stripped = _strip(col, STRIP.get(src, ()))
    fine_objs = _adopt(col, _slug(label))
    dz = 0.0
    if src == "mine":
        dz = -ns["MINE_LEVELS"][level]["ground"]
    elif src == "solar_farm":
        dz = -ns["SITE_H"]
    dx, dy = _place(list(col.objects), R, yaw, mx, my, dz, scale, turn)
    info = {"label": label, "collection": col.name, "fine": fine_objs, "result": str(result)[:160],
            "stripped": stripped}
    if src == "mine":
        # The pit's rim: pit ring 0's inner outline, which is where the plate is cut.
        p = ns["MINE_LEVELS"][level]
        pc, seg = ns["PC"], ns["SEG"]
        rim = ns["Kit"].poly_bean(pc[0], pc[1], p["rx"], p["ry"], n=seg, lobe=0.10, dent=0.14,
                                  phase=math.radians(28))
        step = p["depth"] / (p["benches"] + 1)
        info["pit"] = {"rim": [(x + dx, y + dy) for x, y in rim],
                       # down to the first bench, and a little past it so the joint is buried
                       "depth": step + 0.05, "mat": "earth"}
    return info


def _turbines(R, yaw, label, spots, offshore=False):
    """Wind turbines from the wind farm's own machine, without its yard. Offshore ones stand on
    the offshore farm's monopile (wash collar and the yellow boat-landing band) rather than on
    the onshore concrete pad."""
    ns = _namespace("wind")
    col = bpy.data.collections.new("CAP_" + _slug(label))
    bpy.context.scene.collection.children.link(col)
    K = ns["Kit"](col)
    for i, (mx, my, hub) in enumerate(spots):
        x, y = map_to_world(mx * R, my * R, yaw)
        # The tag is an index: the builder phases each rotor from it.
        ns["_turbine"](K, str(i), x, y, hub, base_z=EPS_Z, offshore=offshore)
    fine_objs = _adopt(col, _slug(label))
    # The kit's "white" is a mid grey on purpose (for buildings); a turbine is white, and at
    # this size in the capsule's light the grey read dark against the sea (owner).
    for ob in col.objects:
        for m in (ob.data.materials if ob.type == 'MESH' else []):
            if m is not None and m.name.startswith("white_wall@"):
                m.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (*TURBINE_WHITE, 1)
    return {"label": label, "collection": col.name, "fine": fine_objs, "stripped": 0}


def _solar(R, yaw):
    """Rows of the solar farm's modules. Rows step back by the panel pitch, as the farm's do,
    so every module in the array shares a screen column with others and it reads as a grid."""
    ns = _namespace("solar_farm")
    col = bpy.data.collections.new("CAP_Solar_panels")
    bpy.context.scene.collection.children.link(col)
    K = ns["Kit"](col)
    (mx, my), rows, cols = SOLAR
    for k in range(rows):
        # The middle rows step one panel to the right (owner), so the array staggers.
        x0 = ns["PITCH"] if 0 < k < rows - 1 else 0.0
        ns["_row"](K, str(k), cols, x0, k * ns["PITCH"], EPS_Z, False)
    fine_objs = _adopt(col, "Solar_panels")
    _place(list(col.objects), R, yaw, mx, my, 0.0)
    if SOLAR_MIRROR:
        objs = list(col.objects)
        x0, x1, y0, y1, _, _ = _xy_extent(objs)
        c = Vector(((x0 + x1) / 2.0, (y0 + y1) / 2.0, 0.0))
        n = Vector((1.0, 1.0, 0.0)).normalized()                   # across the line of sight
        ref = Matrix.Identity(4)
        for i in range(3):
            for j in range(3):
                ref[i][j] -= 2.0 * n[i] * n[j]
        M = Matrix.Translation(c) @ ref @ Matrix.Translation(-c)
        for ob in objs:
            ob.matrix_world = M @ ob.matrix_world
    return {"label": "Solar panels", "collection": col.name, "fine": fine_objs, "stripped": 0}


def _diesel_namespace():
    """The diesel icon's kit and car, read from the commit that shipped them."""
    import subprocess
    commit, src = DIESEL_SRC
    repo = os.path.normpath(os.path.join(HERE, "..", ".."))
    ns = {"__name__": "capsule_diesel"}
    for fn in ("sprite_kit.py", "goods_icon_kit.py", "passat.py"):
        code = subprocess.run(["git", "-C", repo, "show", "%s:%s/%s" % (commit, src, fn)],
                              capture_output=True, text=True, check=True).stdout
        exec(compile(code, fn, "exec"), ns)
    return ns


def _ev_car():
    """The diesel icon's sedan, once, ready to copy: no jerry can, its boolean cuts (wheel
    arches, lamp recesses) baked and their cutting tools gone, and its parts cut down from
    the icon's 300k faces to what a car a few dozen pixels long needs."""
    ns = _diesel_namespace()
    ns["build_diesel_car"]()
    proto = bpy.data.collections["ICON_diesel_car"]
    for ob in list(proto.objects):
        if ob.name.startswith("diesel_can"):                  # no jerry can: these are EVs
            bpy.data.objects.remove(ob, do_unlink=True)
    parts = [ob for ob in proto.objects if ob.type == 'MESH']
    length = max(max(ob.dimensions) for ob in parts)

    def bake(ob):
        dg = bpy.context.evaluated_depsgraph_get()
        me = bpy.data.meshes.new_from_object(ob.evaluated_get(dg), preserve_all_data_layers=True,
                                             depsgraph=dg)
        ob.modifiers.clear()
        ob.data = me

    for ob in parts:
        if ob.modifiers:
            bake(ob)
    tools = bpy.data.collections.get("PASSAT_CONSTRUCTION")
    if tools is not None:
        for ob in list(tools.objects):
            bpy.data.objects.remove(ob, do_unlink=True)
        bpy.data.collections.remove(tools)
    for ob in parts:
        cap = EV_FACES[0] if max(ob.dimensions) > 0.3 * length else EV_FACES[1]
        n = len(ob.data.polygons)
        if n > cap:
            dec = ob.modifiers.new("fewer", 'DECIMATE')
            dec.ratio = cap / n
            bake(ob)
    return proto, parts


def _ev_lot(R, yaw):
    proto, parts = _ev_car()
    x0, x1, y0, y1, _, _ = _xy_extent(parts)
    s = EV_LENGTH / (y1 - y0)                                 # the icon car runs along Y
    width = (x1 - x0) * s
    body = bpy.data.materials["tn_passat_body"]
    paints = []
    for i, rgb in enumerate(EV_COLOURS):
        m = body.copy()
        m.name = "ev_paint_%d" % i
        for n in m.node_tree.nodes:
            if n.type == 'MIX' and n.blend_type == 'MULTIPLY':
                n.inputs[6].default_value = (*rgb, 1.0)
        paints.append(m)
    col = bpy.data.collections.new("CAP_EV_lot")
    bpy.context.scene.collection.children.link(col)
    (mx, my), rows, cols, turn = EV_LOT
    pitch_r, pitch_c = EV_LENGTH + 0.12, width + 0.08
    # Each bay: the car turned to lie along the lot's X, scaled, and moved to its bay.
    to_origin = Matrix.Translation((-(x0 + x1) / 2.0, -(y0 + y1) / 2.0, 0.0))
    lay = Matrix.Rotation(math.radians(-90.0), 4, 'Z') @ Matrix.Scale(s, 4) @ to_origin
    for r in range(rows):
        for c in range(cols):
            M = Matrix.Translation(((r - (rows - 1) / 2.0) * pitch_r, (c - (cols - 1) / 2.0) * pitch_c,
                                    0.02)) @ lay
            paint = paints[(r * 2 + c) % len(paints)]
            for ob in parts:
                o2 = ob.copy()
                col.objects.link(o2)
                o2.matrix_world = M @ ob.matrix_world
                for k, slot in enumerate(o2.material_slots):
                    if slot.material is body:
                        slot.link = 'OBJECT'
                        o2.material_slots[k].material = paint
    # The prototype stays, unrendered, for the cars on the roads (road_cars).
    proto.name = "EV_car_proto"
    proto.hide_render = True
    for ob in proto.objects:
        ob.hide_render = True
    _EV_CAR.update(parts=parts, x0=x0, x1=x1, y0=y0, y1=y1, s=s, paints=paints)
    # The pad runs on past the rows at the end nearest the camera's left, where the charging
    # unit stands on the concrete, in the open and at the front corner, so it is seen.
    K = Kit(col)
    half_x, half_y = rows * pitch_r / 2.0 + 0.12, cols * pitch_c / 2.0 + 0.12
    K.box("lot_pad", -EV_BAY / 2.0, 0.0, 0.01, 2 * half_x + EV_BAY, 2 * half_y, 0.02, K.mat("pad"))
    charging_unit(K, "charger", -half_x - EV_BAY / 2.0, -half_y + 0.16, 0.02, s=EV_CHARGER)
    fine_objs = _adopt(col, "EV_lot")
    _place(list(col.objects), R, yaw, mx, my, 0.0, 1.0, turn)
    return {"label": "EV lot", "collection": col.name, "fine": fine_objs, "stripped": 0}


_EV_CAR = {}
PALETTE["car_headlamp"] = (0.85, 0.82, 0.70)   # unlit by day; the warm looks make them lamps
PALETTE["car_taillamp"] = (0.45, 0.03, 0.02)
ROAD_CARS = 9                   # cars on the roads (owner), each lit front and back
CAR_LAMP = 0.065                # a lamp's size: a few pixels, lit in the warm looks
CAR_HEADS = []                  # each road car's headlamps (world xyz) and heading, for its beam


def road_cars(runs, z, seed=5):
    """A few of the lot's cars out on the roads (owner), each in its lane (they keep to the
    right) and facing along it, with two lamps at the front and two at the back: cream
    headlamps and red tail lamps, which the warm looks light (lighting.py). Seen from the
    camera a car shows one end or the other, so the lanes read white one way, red the other."""
    import random
    car = _EV_CAR
    if not car or not runs:
        return 0
    col = bpy.data.collections.new("CAP_Road_cars")
    bpy.context.scene.collection.children.link(col)
    K = Kit(col)
    head = K.mat("car_headlamp")
    tail = K.mat("car_taillamp")
    rng = random.Random(seed)
    length, width = EV_LENGTH, (car["x1"] - car["x0"]) * car["s"]
    # the icon car's front is its +Y end when its headlamps sit there
    lamps = [ob for ob in car["parts"] if ob.name.startswith("headlamp")]
    ly = sum((ob.matrix_world @ Vector(c)).y for ob in lamps for c in ob.bound_box) / max(1, 8 * len(lamps))
    front = 1.0 if ly > (car["y0"] + car["y1"]) / 2.0 else -1.0
    to_origin = Matrix.Translation((-(car["x0"] + car["x1"]) / 2.0, -(car["y0"] + car["y1"]) / 2.0, 0.0))
    runs = [r for r in runs if sum(math.dist(r[i], r[i + 1]) for i in range(len(r) - 1)) > 2.5]
    placed_at = []
    made = 0
    tries = 0
    while made < ROAD_CARS and tries < 400:
        tries += 1
        run = rng.choice(runs)
        seg = [math.dist(run[i], run[i + 1]) for i in range(len(run) - 1)]
        at = rng.uniform(0.8, sum(seg) - 0.8)
        i = 0
        while i < len(seg) - 1 and at > seg[i]:
            at -= seg[i]
            i += 1
        a, b = run[i], run[i + 1]
        t = at / seg[i]
        px, py = a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t
        if any(math.dist((px, py), q) < 2.2 for q in placed_at):
            continue
        placed_at.append((px, py))
        tx, ty = (b[0] - a[0]) / seg[i], (b[1] - a[1]) / seg[i]
        way = 1.0 if rng.random() < 0.5 else -1.0
        hx, hy = tx * way, ty * way                            # heading
        rx, ry = hy, -hx                                       # its right
        cx, cy = px + rx * 0.05, py + ry * 0.05                # keep right
        yaw = math.atan2(hy, hx) - math.radians(90.0) * front  # the car's front along the heading
        M = Matrix.Translation((cx, cy, z)) @ Matrix.Rotation(yaw, 4, 'Z') @ Matrix.Scale(car["s"], 4) @ to_origin
        paint = car["paints"][rng.randrange(len(car["paints"]))]
        for ob in car["parts"]:
            o2 = ob.copy()
            o2.hide_render = False
            col.objects.link(o2)
            o2.matrix_world = M @ ob.matrix_world
            for k, slot in enumerate(o2.material_slots):
                if slot.material is not None and slot.material.name == "tn_passat_body":
                    slot.link = 'OBJECT'
                    o2.material_slots[k].material = paint
        CAR_HEADS.append(((cx + hx * (length / 2.0 + 0.02), cy + hy * (length / 2.0 + 0.02), z + 0.09), (hx, hy)))
        for end, mat in ((1.0, head), (-1.0, tail)):
            for side in (-1.0, 1.0):
                lx = cx + hx * end * (length / 2.0 - 0.02) + rx * side * (width / 2.0 - 0.06)
                ly2 = cy + hy * end * (length / 2.0 - 0.02) + ry * side * (width / 2.0 - 0.06)
                lamp = K.box("car%d_lamp_%d_%d" % (made, end > 0, side > 0), lx, ly2, z + 0.09,
                             CAR_LAMP, CAR_LAMP, CAR_LAMP * 0.7, mat)
                attr = lamp.data.attributes.new("freestyle_face", 'BOOLEAN', 'FACE')
                for d in attr.data:
                    d.value = True
        made += 1
    fine = bpy.data.collections.get("FINE_INK")
    if fine is not None:
        for ob in col.objects:
            if ob.name not in fine.objects:
                fine.objects.link(ob)
    return made


# (share of the way to the rim, turn round the pit, heading off the camera's line in degrees):
# two coming toward the camera, headlamps on, and one going away, its tail lamps showing.
PIT_TRUCKS = ((0.62, 0.30, 25.0), (0.66, 0.46, -30.0), (0.58, 0.64, 165.0))
PIT_MASTS = (0.26, 0.50)                                  # turn round the pit of the rim's two masts
PIT = {}                                                  # what lighting.py lights: heads, masts, centre


def pit_works(placed):
    """The mine's pit at work (owner): haul trucks on the far benches, where the camera sees
    them, with their lamps on; and two floodlight masts on the rim facing into the pit. Found by dropping rays on the pit; recorded for lighting.py,
    which lights them and puts a lamp low in the pit, so light comes up out of it."""
    mine = next((b for b in placed if "pit" in b), None)
    if mine is None:
        return 0
    rim = mine["pit"]["rim"]
    cx = sum(p[0] for p in rim) / len(rim)
    cy = sum(p[1] for p in rim) / len(rim)
    scene = bpy.context.scene
    dg = bpy.context.evaluated_depsgraph_get()
    col = bpy.data.collections.new("CAP_Pit_works")
    scene.collection.children.link(col)
    K = Kit(col)
    K._fine_mode = True

    def rim_at(f):
        """The rim point round the pit at share f of the way round (0 = east, anticlockwise)."""
        a = 2 * math.pi * f
        best = max(rim, key=lambda p: math.cos(math.atan2(p[1] - cy, p[0] - cx) - a))
        return best

    def ground(x, y):
        hit, loc, _, _, ob, _ = scene.ray_cast(dg, Vector((x, y, 40.0)), Vector((0, 0, -1)))
        return loc.z if hit else 0.0

    heads = []
    for k, (reach, f, off) in enumerate(PIT_TRUCKS):
        rx, ry = rim_at(f)
        x, y = cx + (rx - cx) * reach, cy + (ry - cy) * reach
        z = ground(x, y)
        ang = math.radians(-45.0 + off)                           # the camera looks from -45
        M = Matrix.Translation((x, y, z)) @ Matrix.Rotation(ang, 4, 'Z')
        place_built(K, haul_truck, "pit_truck%d" % k, M)
        hx, hy = math.cos(ang), math.sin(ang)
        heads.append(((x + hx * 0.42, y + hy * 0.42, z + 0.22), (hx, hy)))
    masts = []
    for k, f in enumerate(PIT_MASTS):
        rx, ry = rim_at(f)
        d = math.hypot(cx - rx, cy - ry)
        ox, oy = (rx - cx) / d, (ry - cy) / d                     # outward
        x, y = rx + ox * 0.35, ry + oy * 0.35
        z = ground(x, y)
        ang = math.atan2(-oy, -ox)                                 # lamps toward the pit
        M = Matrix.Translation((x, y, z)) @ Matrix.Rotation(ang, 4, 'Z')
        place_built(K, light_mast, "pit_mast%d" % k, M)
        masts.append((x - ox * 0.07, y - oy * 0.07, z + 1.75))
    PIT.update(heads=heads, masts=masts, centre=(cx, cy, ground(cx, cy)), rim=rim,
               top=max(ground(p[0], p[1]) for p in rim[:1]))
    return len(col.objects)


def _batteries(R, yaw):
    """The electrolyser's battery block, as a row of grid-storage units."""
    ns = _namespace("electrolyser")
    col = bpy.data.collections.new("CAP_Battery_storage")
    bpy.context.scene.collection.children.link(col)
    K = ns["Kit"](col)
    W, L, H = ns["BATT_W"], ns["BATT_L"], ns["BATT_H"]
    (mx, my), n, scale = BATTERIES
    cx, cy = 0.0, 0.0
    gap = 0.30
    for u in range(n):
        x, y, t = cx + (u - (n - 1) / 2.0) * (W + gap), cy, "batt%d" % u
        K.box(t, x, y, H / 2 + EPS_Z, W, L, H, K.mat("wall_bright"))
        K.box(t + "_lid", x, y, H + 0.05 + EPS_Z, W + 0.10, L + 0.10, 0.10, K.mat("roof_deck"))
        for j, fz in enumerate((0.34, 0.72)):          # green stripes on the two faces in view
            K.box("%s_sy%d" % (t, j), x, y - L / 2 - 0.014, fz + EPS_Z, W - 0.10, 0.03, 0.10,
                  K.mat("tie_rod"))
            K.box("%s_sx%d" % (t, j), x + W / 2 + 0.014, y, fz + EPS_Z, 0.03, L - 0.16, 0.10,
                  K.mat("tie_rod"))
        for j in range(3):
            K.box("%s_rib%d" % (t, j), x, y - L / 2 - 0.02, H / 2 + EPS_Z, 0.05, 0.03, H - 0.24,
                  K.mat("gear"))
    fine_objs = _adopt(col, "Battery_storage")
    _place(list(col.objects), R, yaw, mx, my, 0.0, scale)
    return {"label": "Battery storage", "collection": col.name, "fine": fine_objs, "stripped": 0}


def _harbour(R, yaw):
    """The pier with its crane and containers, and the ship, as two buildings: the checker
    lets the pier stand over water and requires the ship to be in it."""
    ns = _namespace("docks")
    (mx, my), length, width, deck = PIER
    ship_l, beam, at = SHIP
    out = []
    for label, parts in (("Harbour", "pier"), ("Cargo ship", "ship")):
        col = bpy.data.collections.new("CAP_" + _slug(label))
        bpy.context.scene.collection.children.link(col)
        K = ns["Kit"](col)
        # Built in the port's own frame: the pier along +X from its root at the origin, the
        # water (and the ship) at -Y.
        if parts == "pier":
            K.box("pier", length / 2, 0.0, deck / 2, length, width, deck, K.mat("quay"))
            K.box("pier_edge", length / 2, -width / 2 + 0.06, deck + 0.02, length, 0.12, 0.04,
                  K.mat("quay_edge"))
            ns["_portal_crane"](K, "gc", length * at, -width / 2 + 0.35, width / 2 - 0.35, -1, deck)
            ns["_lift"](K, deck, K.container_stack, "cs0", 0.95, 0.35, cols=3, rows=2)
            ns["_lift"](K, deck, K.container_stack, "cs1", 2.25, 0.35, cols=2, rows=2)
        else:
            mats = [K.mat(m) for m in ("wall_brick", "box_blue", "plant_yellow", "gantry_green",
                                       "box_blue", "white_wall")]
            # The port floats its ships on water at WATER_Z; the plate's water is its top.
            ns["_lift"](K, -ns["WATER_Z"], ns["_boxship"], K, "ship", length * at,
                        -(width / 2 + 0.15 + beam / 2), ship_l, beam, mats)
        fine_objs = _adopt(col, _slug(label))
        # A quarter turn left about the pier root, then out to the shore.
        rx, ry = map_to_world(mx * R, my * R, yaw)
        M = Matrix.Translation((rx, ry, EPS_Z)) @ Matrix.Rotation(math.radians(90.0), 4, 'Z')
        for ob in col.objects:
            ob.matrix_world = M @ ob.matrix_world
        out.append({"label": label, "collection": col.name, "fine": fine_objs, "stripped": 0})
    _crane_over_ship(ns, out)
    return out


SPREADER = (1.05, 0.44)         # a container's top, length (along the ship) by width, world


def _crane_over_ship(ns, placed):
    """The crane's trolley run out along the boom until it stands over the ship's middle, and
    its hook, block and chain swapped for a container spreader (owner): a yellow frame the
    size of a container's top with a twistlock at each corner, slung from a head block on
    four ropes, hovering just above the stack it is about to take."""
    trolley = bpy.data.objects.get("Harbour.gc_trolley")
    ship = bpy.data.collections.get("CAP_Cargo_ship")
    col = bpy.data.collections.get("CAP_Harbour")
    if trolley is None or ship is None or col is None:
        return
    gone = [ob for ob in col.objects if ob.name.split(".", 1)[1] in ("gc_block", "gc_hook_bo", "gc_hook_pt",
                                                                       "gc_hook_sh")
            or ob.name.split(".", 1)[1].startswith("gc_link")]
    for b in placed:                                   # out of the thin-line lists first
        b["fine"] = [o for o in b["fine"] if o not in gone]
    for ob in gone:
        bpy.data.objects.remove(ob, do_unlink=True)
    # The boom runs along world X here (the port's frame turned a quarter), across the ship.
    tx0, tx1, ty0, ty1, tz0, _ = _xy_extent([trolley])
    sx0, sx1, _, _, _, _ = _xy_extent([o for o in ship.objects if o.type == 'MESH'])
    cx, cy = (sx0 + sx1) / 2.0, (ty0 + ty1) / 2.0
    _move([trolley], cx - (tx0 + tx1) / 2.0, 0.0, 0.0)
    bpy.context.view_layer.update()
    dg = bpy.context.evaluated_depsgraph_get()
    hit, loc, _, _, _, _ = bpy.context.scene.ray_cast(dg, Vector((cx, cy, tz0 - 0.05)), Vector((0, 0, -1)))
    top = loc.z if hit else 1.2
    K = ns["Kit"](col)
    yel, dark = K.mat("plant_yellow"), K.mat("darkmetal")
    L, W = SPREADER
    zf = top + 0.16
    n = "Harbour.gc_spr_"
    for i, sx in enumerate((-1, 1)):
        K.box(n + "side%d" % i, cx + sx * (W / 2 - 0.025), cy, zf, 0.05, L, 0.06, yel)
    for i, sy in enumerate((-1, 1)):
        K.box(n + "end%d" % i, cx, cy + sy * (L / 2 - 0.025), zf, W, 0.05, 0.06, yel)
    K.box(n + "spine", cx, cy, zf + 0.04, 0.12, L - 0.20, 0.08, yel)
    corners = ((-1, -1), (1, -1), (1, 1), (-1, 1))
    for i, (sx, sy) in enumerate(corners):
        K.box(n + "lock%d" % i, cx + sx * (W / 2 - 0.03), cy + sy * (L / 2 - 0.03), zf - 0.05, 0.06, 0.06,
              0.05, dark)
        K.dircyl(n + "sling%d" % i, (cx + sx * 0.08, cy + sy * 0.12, zf + 0.25),
                 (cx + sx * (W / 2 - 0.05), cy + sy * (L / 2 - 0.10), zf + 0.03), 0.010, dark, segments=6)
    K.box(n + "head", cx, cy, zf + 0.30, 0.22, 0.30, 0.10, dark)
    for i, (dx, dy) in enumerate(((-0.07, -0.10), (0.07, -0.10), (0.07, 0.10), (-0.07, 0.10))):
        K.dircyl(n + "rope%d" % i, (cx + dx, cy + dy, tz0), (cx + dx, cy + dy, zf + 0.35), 0.012, dark,
                 segments=6)


def _lot(road, at, side, R, yaw):
    """The point where a building's front goes, and the direction it backs away along (a unit
    normal pointing off the road)."""
    path = _catmull([map_to_world(x * R, y * R, yaw) for x, y in ROADS[road]], per_seg=16)
    ps = _arc(path)
    s = ps[-1] * at
    p = _at(path, ps, s)
    a, b = _at(path, ps, max(0.0, s - 0.1)), _at(path, ps, min(ps[-1], s + 0.1))
    t = _unit((b[0] - a[0], b[1] - a[1]))
    n = (-t[1] * side, t[0] * side)
    edge = ROAD_WIDTH * R / 2.0 + SETBACK
    return (p[0] + n[0] * edge, p[1] + n[1] * edge), n


def _face_road(objs, front, n, scale=1.0):
    """Turn, scale and move a building made at the origin so the middle of its front (-Y)
    face lands on `front` with its back along n."""
    x0, x1, y0, y1, _, _ = _xy_extent(objs)
    theta = math.atan2(n[1], n[0]) - math.pi / 2.0
    M = (Matrix.Translation((front[0], front[1], EPS_Z)) @ Matrix.Rotation(theta, 4, 'Z')
         @ Matrix.Scale(scale, 4) @ Matrix.Translation((-(x0 + x1) / 2.0, -y0, 0.0)))
    for ob in objs:
        ob.matrix_world = M @ ob.matrix_world


def _frontage(R, yaw, label, kind, road, at, side, p):
    front, n = _lot(road, at, side, R, yaw)
    if kind == "office":
        ns = _namespace("office")
        ns["build_office"](p["variant"])
        col = bpy.data.collections["BLDG_office"]
        fine_objs = _adopt(col, _slug(label))
        _face_road(list(col.objects), front, n, p["scale"])
        return {"label": label, "collection": col.name, "fine": fine_objs, "stripped": 0}
    col = bpy.data.collections.new("CAP_" + _slug(label))
    bpy.context.scene.collection.children.link(col)
    K = Kit(col)
    tag = _slug(label).lower()
    if kind == "block":
        apartment_block(K, tag, 0.0, 0.0, 2.1, 1.0, p["floors"], p["variant"])
    else:
        terrace(K, tag, 0.0, 0.0, p["count"], p["variant"])
    _face_road(list(col.objects), front, n, HOUSING_SCALE)
    return {"label": label, "collection": col.name, "fine": [], "stripped": 0}


def build_buildings(R, yaw, placements=PLACEMENTS):
    placed = []
    for label, src, level, mx, my, scale, turn in placements:
        placed.append(_building(label, src, level, mx, my, R, yaw, scale, turn))
        print("BUILT %-26s %s" % (label, placed[-1]["result"]), flush=True)
    placed.append(_solar(R, yaw))
    placed.append(_turbines(R, yaw, "Wind turbines", TURBINES))
    placed.append(_turbines(R, yaw, "Offshore wind", OFFSHORE, offshore=True))
    placed.append(_batteries(R, yaw))
    placed.append(_ev_lot(R, yaw))
    placed += _harbour(R, yaw)
    for label, kind, road, at, side, p in FRONTAGE:
        placed.append(_frontage(R, yaw, label, kind, road, at, side, p))
    return placed


def pits_of(placed):
    return [b["pit"] for b in placed if "pit" in b]


# A part smaller than this on screen (world units along the camera's axes; 35 px at the
# 3072 review size) takes the thin line. The ink is a fixed width, so on a small part it is
# all there is: measured, the offices went 48% ink to 35%, terraces 37% to 19%.
SMALL_PART = 0.69


def finish_buildings(placed, elevation=30.0):
    """Undo what later builders did to earlier buildings: show them, relink fine ink. Then
    move every small part onto the thin line."""
    fine = bpy.data.collections.get("FINE_INK")
    for b in placed:
        col = bpy.data.collections[b["collection"]]
        col.hide_render = col.hide_viewport = False
        for ob in col.objects:
            ob.hide_render = ob.hide_viewport = False
        for ob in b["fine"]:
            if fine is not None and ob.name not in fine.objects:
                fine.objects.link(ob)
    e = math.radians(elevation)
    right = Vector((1.0, 1.0, 0.0)).normalized()
    up = Vector((-math.sin(e) / math.sqrt(2.0), math.sin(e) / math.sqrt(2.0), math.cos(e)))
    moved = 0
    for b in placed:
        for ob in bpy.data.collections[b["collection"]].objects:
            if ob.type != 'MESH' or fine is None or ob.name in fine.objects:
                continue
            pts = [ob.matrix_world @ Vector(c) for c in ob.bound_box]
            sx, sy = [p.dot(right) for p in pts], [p.dot(up) for p in pts]
            if max(max(sx) - min(sx), max(sy) - min(sy)) < SMALL_PART:
                fine.objects.link(ob)
                moved += 1
    # The land turbines keep the full line, blades and all (owner): on the thin one their
    # blades faded out against the sea behind them.
    thick = bpy.data.collections.get("CAP_Wind_turbines")
    if thick is not None and fine is not None:
        for ob in thick.objects:
            if ob.name in fine.objects:
                fine.objects.unlink(ob)
    print("THIN LINE: %d small parts" % moved, flush=True)


def label_points(placed):
    """(label, world point) at each building's highest vertex, for annotated renders. The
    top of its bounding box floats above the footprint wherever a chimney sets the height."""
    out = []
    for b in placed:
        best = None
        for ob in bpy.data.collections[b["collection"]].objects:
            if ob.type != 'MESH':
                continue
            mw = ob.matrix_world
            for v in ob.data.vertices:
                w = mw @ v.co
                if best is None or w.z > best.z:
                    best = w
        out.append((b["label"], (best.x, best.y, best.z)))
    return out


def footprints(placed, z_top=0.0):
    """Per building, the plan outline of every object standing on (or sunk into) the ground,
    as convex hulls; blades, roofs and anything else in the air are left out."""
    out = {}
    for b in placed:
        hulls = []
        for ob in bpy.data.collections[b["collection"]].objects:
            if ob.type != 'MESH' or not ob.data.vertices:
                continue
            mw = ob.matrix_world
            ws = [mw @ v.co for v in ob.data.vertices]
            if min(w.z for w in ws) > z_top + NEAR_GROUND:
                continue
            hulls.append(xy_hull([(w.x, w.y) for w in ws]))
        out[b["collection"]] = hulls
    return out
