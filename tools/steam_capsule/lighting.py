"""Looks for the capsule: the calibrated daylight, and two warmer ones after the AI key art.

    apply_look(name, placed)      # after the camera is framed: lamps stay out of the framing
    pools_off()                   # before a pass that must be lit by the sun alone
    glow_pass(path)               # the look's light sources alone, for the print's bloom

The AI concept's warmth comes from three things, and each look turns them up together:
  * a warm key and a cooler fill: the sun goes amber and the world (the shadow side) blue;
  * light sources: lit windows (every building's glass turns warm and emissive, all alike, in
    golden (owner); a look with a smaller share lights some),
    the arc furnace's melt and the laser, which already glow; lamps on the mine's headframe
    (owner); light coming up out of the mine's pit, from haul trucks' lamps, floodlight masts
    and a lamp low in it (owner); the high tech hall's skylight glowing and the EV plant's
    vaults lit from the floor with the robots, through clearer glass (owner); the high tech hall and the EV
    plant lit from inside, their doorways and openings glowing (owner); lamp posts along the
    pier and floodlights under the crane's boom, with a red light at its apex and tip
    (owner); and the road cars' lamps, cream at the front and red behind (owner);
  * the light off the sea (owner): a low warm area lamp out where the sun stands, falling
    away inland, and glints on the water toward it;
  * pools of warm light spilling out of the works' doors onto the ground (point lamps at
    each works' front, on the camera's side), and a soft bloom round every light source.
And one thing finish_render.py does in 2D: a smoke haze over the mine's side, thinning toward
the sea, as the concept's smoke hangs over its pit (owner; `haze`).
The light sources are also rendered alone (.glow.png) under the Standard view: AgX takes a
bright amber most of the way to white, so finish_render.py paints the lamps from that pass
and blooms them in 2D (EEVEE has no bloom).
"day" is the calibrated look (every map colour holds its measured value) and changes nothing.
"""
import math
import random

LOOKS = {
    "day": None,
    # Late afternoon: the sun amber, the fill cooler and a little dimmer, a third of the
    # windows lit, gentle pools, a soft bloom.
    # The owner's look. Its light runs from the sea to the mine (owner): a low warm light over
    # the sea, which falls away inland (`sea_light`), glints on the water (`glints`), and a
    # smoke haze over the mine's side (`haze`: opacity at the north-west end, and where along
    # the plate it has thinned to nothing; finish_render.py lays it).
    # Its sun and the light off the sea are strong (owner: strong enough to read as one light
    # across the map and the nameplate beside it), and the fill a little dimmer, for contrast.
    "golden": dict(sun=(1.00, 0.74, 0.46), sun_gain=1.50, world=(0.62, 0.72, 1.00), world_strength=0.44,
                   windows=1.0, window_strength=1.0, hall_glow=1.3, pools=2.0, glow=0.55,
                   falloff=None, sea_light=3400.0, glints=90, haze=(0.52, 0.62), pit=1.0),
    # Dusk: a low, deep amber sun and a blue fill, most windows lit, strong pools and bloom.
    "dusk": dict(sun=(1.00, 0.55, 0.28), sun_gain=0.75, world=(0.45, 0.55, 1.00), world_strength=0.40,
                 windows=0.62, window_strength=1.0, hall_glow=0.75, pools=3.5, glow=0.85,
                 falloff=(0.48, 1.04)),
}
LAMP = (1.00, 0.56, 0.20)                # lit window: a warm tungsten amber
POOL = (1.00, 0.62, 0.30)
PORT = (1.00, 0.86, 0.66)                # the pier's lamps: a whiter sodium than the windows
CAR_HEAD, CAR_TAIL = (1.00, 0.97, 0.92), (1.00, 0.06, 0.03)      # white front, red rear (owner)
SEA_SUN = (1.00, 0.66, 0.34)             # the light off the sea: a low sun's amber
GLINT = (1.00, 0.88, 0.62)
WORK = (1.00, 0.95, 0.87)                # the EV plant's floor: white work lighting (owner)
AVIATION = (1.00, 0.10, 0.05)
# Glazing that can light up, by material base name; and the share of it lit, by works kind.
GLAZING = {"glass"}
# The high tech hall's big skylight glows warm and blooms, to draw the eye (owner), and stays
# see-through so the floor shows.
HALLS = {"ht_pane"}
# The EV plant's glazed vaults are lit the other way (owner): the light comes from the floor
# with the robots, through clearer glass, not from the glass itself. Collection -> (watts per
# lamp at "pools" 1.0, the objects whose floor is lit, the glass made clearer, its alpha).
FLOOR_LIT = {"CAP_Assembly_plant": (40.0, "vault", "ap_glass", 0.40)}
# Works lit from inside (owner): collection -> watts, at "pools" 1.0, of the lamp in the
# hall. Their doorways and openings glow as the lit hall shows through them.
INTERIORS = {"CAP_High_tech_manufactory": 24.0, "CAP_Assembly_plant": 0.0}
OPENINGS = {"ink_black", "door"}
LIT_SHARE = {"Office": 2.4, "Apartments": 1.2, "Terrace": 1.1, "Cargo_ship": 2.0}     # a share < 1 leaves some dark
# Materials that are light sources in every look (they glow already).
GLOWS = {"eaf_coil_glow", "eaf_glow", "eaf_melt", "ember", "laser", "car_headlamp", "car_taillamp"}
# Pools of light at the works' fronts: label -> watts at "pools" 1.0.
# The harbour has its own lamps (the pier's), whose pools stay off the ship's white deckhouse.
# The mine, the factory, the arc furnace and the chemical plant are lit up more (owner).
POOLS = {"Electric arc furnace": 240.0, "Power plant": 22.0, "Industrial goods factory": 170.0,
         "Assembly plant": 26.0, "High tech manufactory": 18.0, "Mine": 140.0, "Chemical plant": 150.0}
TOWARD_CAM = (math.sqrt(0.5), -math.sqrt(0.5))
_pools = []


def _base(mat):
    return mat.name.split("@")[0]


def lamp_material(strength, name="_lamp_window", colour=LAMP):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes.get("Principled BSDF")
    b.inputs["Base Color"].default_value = (0.02, 0.02, 0.02, 1)
    b.inputs["Roughness"].default_value = 1.0
    b.inputs["Emission Color"].default_value = (*colour, 1)
    b.inputs["Emission Strength"].default_value = strength
    return m


def _noink(ob):
    """A light is a point of colour: an outline would swallow it."""
    me = ob.data
    a = me.attributes.get("freestyle_face") or me.attributes.new("freestyle_face", 'BOOLEAN', 'FACE')
    for d in a.data:
        d.value = True
    return ob


def _bbox(objs):
    import mathutils
    pts = [ob.matrix_world @ mathutils.Vector(c) for ob in objs if ob.type == 'MESH' for c in ob.bound_box]
    return (min(p.x for p in pts), max(p.x for p in pts), min(p.y for p in pts), max(p.y for p in pts),
            min(p.z for p in pts), max(p.z for p in pts))


def _light_windows(share, lamp):
    """Turn `share` of the glazing warm: whole window objects, or single quads of a painted
    window mesh (housing.py paints a building's windows as one mesh)."""
    lit = 0
    for ob in bpy.data.objects:
        if ob.type != 'MESH' or not ob.users_collection:
            continue
        col = ob.users_collection[0].name
        if not col.startswith("CAP_") or col == "CAP_EV_lot":
            continue
        slots = [i for i, m in enumerate(ob.data.materials) if m is not None and _base(m) in GLAZING]
        if not slots:
            continue
        kind = col[4:].rstrip("_0123456789")
        p = min(1.0, share * LIT_SHARE.get(kind, 1.0))
        rng = random.Random(ob.name)
        polys = [f for f in ob.data.polygons if f.material_index in slots]
        if len(polys) > 12 and ob.data.users == 1:             # painted windows: pick quads
            ob.data.materials.append(lamp)
            k = len(ob.data.materials) - 1
            for f in polys:
                if rng.random() < p:
                    f.material_index = k
                    lit += 1
        elif rng.random() < p:                                 # a window of its own
            if ob.data.users == 1:
                # Its sides only: a glass box's top would glow as a slab (the ship's bridge).
                ob.data.materials.append(lamp)
                k = len(ob.data.materials) - 1
                for f in polys:
                    if abs(f.normal.z) < 0.5:
                        f.material_index = k
            else:
                for i in slots:
                    ob.material_slots[i].link = 'OBJECT'
                    ob.material_slots[i].material = lamp
            lit += 1
    return lit


def _front(col_name):
    """The point on the ground at the middle of a collection's camera-side face, and the
    collection's height."""
    import mathutils
    pts = [ob.matrix_world @ mathutils.Vector(c) for ob in bpy.data.collections[col_name].objects
           if ob.type == 'MESH' for c in ob.bound_box]
    d = mathutils.Vector((*TOWARD_CAM, 0.0))
    cx = sum(p.x for p in pts) / len(pts)
    cy = sum(p.y for p in pts) / len(pts)
    f = max(p.dot(d) for p in pts) - (cx * d.x + cy * d.y)
    return cx + d.x * f, cy + d.y * f, max(p.z for p in pts)


def _lamp(name, x, y, z, watts, colour=POOL):
    lamp = bpy.data.lights.new(name, 'POINT')
    lamp.energy = watts
    lamp.color = colour
    lamp.shadow_soft_size = 0.35
    lamp.use_shadow = False
    ob = bpy.data.objects.new(name, lamp)
    bpy.context.scene.collection.objects.link(ob)
    ob.location = (x, y, z)
    _pools.append(ob)


def _interiors(gain, tint, lamp):
    """The works lit from inside: a lamp in each hall (in a glass hall, at the glass's middle),
    their doorways and openings glowing, and a warm tint in a glass hall's panes, which stay
    see-through, as a lit interior colours its glazing."""
    for m in bpy.data.materials:
        b = m.node_tree.nodes.get("Principled BSDF") if m.use_nodes and _base(m) in HALLS else None
        if b is not None:
            b.inputs["Emission Color"].default_value = (*LAMP, 1)
            b.inputs["Emission Strength"].default_value = tint
    for name, watts in INTERIORS.items():
        col = bpy.data.collections.get(name)
        if col is None:
            continue
        for ob in col.objects:
            for i, m in enumerate(ob.data.materials if ob.type == 'MESH' else []):
                if m is not None and _base(m) in OPENINGS:
                    ob.material_slots[i].link = 'OBJECT'
                    ob.material_slots[i].material = lamp
        glass = [ob for ob in col.objects if ob.type == 'MESH'
                 and any(m is not None and _base(m) in HALLS for m in ob.data.materials)]
        x0, x1, y0, y1, z0, z1 = _bbox(glass or list(col.objects))
        if watts:
            _lamp("inside_" + name, (x0 + x1) / 2, (y0 + y1) / 2, z0 + (z1 - z0) * 0.35, watts * gain)
    for name, (watts, under, clear, alpha) in FLOOR_LIT.items():
        col = bpy.data.collections.get(name)
        if col is None:
            continue
        for m in bpy.data.materials:
            if _base(m) == clear and m.use_nodes:
                m.node_tree.nodes["Principled BSDF"].inputs["Alpha"].default_value = alpha
        floor = _bbox(list(col.objects))[4]
        for ob in col.objects:
            if ob.type != 'MESH' or not ob.name.endswith(under):
                continue
            x0, x1, y0, y1, _, _ = _bbox([ob])
            long_x = (x1 - x0) >= (y1 - y0)
            for k in range(3):
                f = 0.2 + 0.3 * k
                x = x0 + (x1 - x0) * (f if long_x else 0.5)
                y = y0 + (y1 - y0) * (0.5 if long_x else f)
                _lamp("floor_%s_%d" % (ob.name, k), x, y, floor + 0.13, watts * gain, WORK)
                _pools[-1].data.shadow_soft_size = 0.5


def _port_lights(gain):
    """Lamp posts down the pier's far edge, each throwing a pool, and floodlights under the
    crane's boom; a red light on the crane's apex and on its boom's tip."""
    pier = bpy.data.objects.get("Harbour.pier")
    if pier is None:
        return 0
    col = bpy.data.collections.new("CAP_Port_lights")
    bpy.context.scene.collection.children.link(col)
    K = Kit(col)
    K._fine_mode = True
    head = lamp_material(1.6, "_lamp_port", PORT)
    red = lamp_material(1.6, "_lamp_aviation", AVIATION)
    x0, x1, y0, y1, _, top = _bbox([pier])
    n = 5
    for i in range(n):
        y = y0 + 0.45 + (y1 - y0 - 0.9) * i / (n - 1)
        x = x0 + 0.12
        K.dircyl("port_post%d" % i, (x, y, top), (x, y, top + 0.72), 0.022, K.mat("darkmetal"), segments=8)
        K.box("port_arm%d" % i, x + 0.06, y, top + 0.72, 0.14, 0.035, 0.03, K.mat("darkmetal"))
        _noink(K.box("port_head%d" % i, x + 0.11, y, top + 0.70, 0.08, 0.06, 0.025, head))
        _lamp("port_pool%d" % i, x + 0.14, y, top + 0.62, 7.0 * gain, PORT)
    booms = [bpy.data.objects.get("Harbour.gc_boom%d" % i) for i in (0, 1)]
    if all(booms):
        bx0, bx1, by0, by1, bz0, _ = _bbox(booms)
        # Bars of light under the boom, with no pool: the boom hangs over the ship's white
        # deckhouse, the tallest thing under it, which a pool would light white-hot.
        for i, fx in enumerate((0.30, 0.72)):
            x = bx0 + (bx1 - bx0) * fx
            _noink(K.box("crane_flood%d" % i, x, (by0 + by1) / 2, bz0 - 0.03, 0.16, 0.26, 0.04, head))
        _noink(K.box("crane_tip_light", bx1 - 0.05, (by0 + by1) / 2, bz0 + 0.24, 0.07, 0.07, 0.07, red))
    apex = bpy.data.objects.get("Harbour.gc_apex")
    if apex is not None:
        ax0, ax1, ay0, ay1, _, az1 = _bbox([apex])
        _noink(K.box("crane_apex_light", (ax0 + ax1) / 2, (ay0 + ay1) / 2, az1 + 0.05, 0.07, 0.07, 0.07, red))
    return len(col.objects)


def _car_lamps(strength, beam):
    """The road cars' and the engine's lamps lit (owner): white at the front, red at the back;
    and each road car's headlamps throw a short beam onto the road ahead (a spot)."""
    import mathutils
    for name, colour in (("car_headlamp", CAR_HEAD), ("car_taillamp", CAR_TAIL)):
        m = bpy.data.materials.get(name)
        if m is not None:
            b = m.node_tree.nodes.get("Principled BSDF")
            b.inputs["Emission Color"].default_value = (*colour, 1)
            b.inputs["Emission Strength"].default_value = strength
    for i, ((x, y, z), (hx, hy)) in enumerate(CAR_HEADS):
        spot = bpy.data.lights.new("car_beam%d" % i, 'SPOT')
        spot.energy = beam
        spot.color = CAR_HEAD
        spot.spot_size = math.radians(55.0)
        spot.spot_blend = 0.7
        spot.shadow_soft_size = 0.05
        spot.use_shadow = False
        ob = bpy.data.objects.new(spot.name, spot)
        bpy.context.scene.collection.objects.link(ob)
        ob.location = (x, y, z + 0.06)
        aim = mathutils.Vector((hx, hy, -0.55)).normalized()
        ob.rotation_euler = aim.to_track_quat('-Z', 'Y').to_euler()
        _pools.append(ob)


def _tower_lights(gain):
    """The mine's headframe lit (owner): a warm lamp at each front corner of its deck, a red
    light at its top, and a floodlight under the deck washing the tower and the pit head."""
    deck = bpy.data.objects.get("Mine.head_deck")
    if deck is None:
        return 0
    col = bpy.data.collections.new("CAP_Tower_lights")
    bpy.context.scene.collection.children.link(col)
    K = Kit(col)
    lamp = lamp_material(1.6, "_lamp_port", PORT)
    red = lamp_material(1.6, "_lamp_aviation", AVIATION)
    x0, x1, y0, y1, z0, z1 = _bbox([deck])
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    for i, (px, py) in enumerate(((x1, y0), (x0, y0), (x1, y1))):
        _noink(K.box("tower_lamp%d" % i, px, py, z1 + 0.05, 0.08, 0.08, 0.06, lamp))
    heads = [o for o in bpy.data.objects if o.name.startswith("Mine.head_sheave")]
    top = max(_bbox(heads)[5], z1) if heads else z1
    _noink(K.box("tower_red", cx, cy, top + 0.08, 0.08, 0.08, 0.08, red))
    _lamp("tower_flood", cx + TOWARD_CAM[0] * 0.4, cy + TOWARD_CAM[1] * 0.4, z0 - 0.2, 30.0 * gain, PORT)
    return len(col.objects)


def _pit_lights(gain):
    """Light coming up out of the mine's pit (owner): the haul trucks' headlamps throw beams,
    the rim's masts floodlight the benches, and a warm lamp low in the pit lights its walls."""
    import mathutils
    if not PIT:
        return 0
    n = 0
    for (x, y, z), (hx, hy) in PIT["heads"]:
        spot = bpy.data.lights.new("pit_beam%d" % n, 'SPOT')
        spot.energy, spot.color = 30.0 * gain, CAR_HEAD
        spot.spot_size, spot.spot_blend = math.radians(60.0), 0.6
        spot.use_shadow = False
        ob = bpy.data.objects.new(spot.name, spot)
        bpy.context.scene.collection.objects.link(ob)
        ob.location = (x, y, z)
        ob.rotation_euler = mathutils.Vector((hx, hy, -0.35)).normalized().to_track_quat('-Z', 'Y').to_euler()
        _pools.append(ob)
        n += 1
    cx, cy, cz = PIT["centre"]
    for k, (x, y, z) in enumerate(PIT["masts"]):
        spot = bpy.data.lights.new("pit_flood%d" % k, 'SPOT')
        spot.energy, spot.color = 160.0 * gain, PORT
        spot.spot_size, spot.spot_blend = math.radians(75.0), 0.5
        spot.use_shadow = False
        ob = bpy.data.objects.new(spot.name, spot)
        bpy.context.scene.collection.objects.link(ob)
        ob.location = (x, y, z)
        ob.rotation_euler = (mathutils.Vector((cx, cy, cz)) - mathutils.Vector((x, y, z))).to_track_quat('-Z', 'Y').to_euler()
        _pools.append(ob)
    _lamp("pit_glow", cx, cy, cz + 0.45, 120.0 * gain, POOL)
    _pools[-1].data.shadow_soft_size = 1.0
    return n


def _plate_bounds():
    plate = [ob for ob in bpy.data.collections["CAPSULE_plate"].objects if ob.type == 'MESH']
    return _bbox(plate)


def _sea_light(watts):
    """A low warm light out over the sea, where the sun stands (owner): a broad area lamp
    whose light falls away inland, so the sea side of the plate is gold and the mine's side
    far from it gets little. It casts no shadow, like the sun here."""
    import mathutils
    x0, x1, y0, y1, _, z1 = _plate_bounds()
    c = mathutils.Vector(((x0 + x1) / 2, (y0 + y1) / 2, z1))
    d = mathutils.Vector((math.sqrt(0.5), math.sqrt(0.5), 0.0))     # toward the sun (azimuth 45)
    # Over the bay's far side and well up, so it falls on the ground rather than skimming it:
    # the harbour's coast then gets about two thirds of the sun again and the mine a
    # thirtieth (inverse square, and the slant).
    reach = max(x1 - x0, y1 - y0) * 0.34
    lamp = bpy.data.lights.new("sea_light", 'AREA')
    lamp.shape = 'DISK'
    lamp.size = 12.0
    lamp.energy = watts
    lamp.color = SEA_SUN
    lamp.use_shadow = False
    ob = bpy.data.objects.new("sea_light", lamp)
    bpy.context.scene.collection.objects.link(ob)
    ob.location = c + d * reach + mathutils.Vector((0, 0, 9.0))
    ob.rotation_euler = (c - ob.location).to_track_quat('-Z', 'Y').to_euler()
    _pools.append(ob)


def _glints(count):
    """Glints on the sea (owner): short strokes of warm light lying on the water, lengthwise
    across the view, thickest toward the sun's side. Found by dropping rays on the plate and
    keeping those that land on sea or shelf."""
    import mathutils
    scene = bpy.context.scene
    dg = bpy.context.evaluated_depsgraph_get()
    x0, x1, y0, y1, _, z1 = _plate_bounds()
    plate = [ob for ob in bpy.data.collections["CAPSULE_plate"].objects if ob.type == 'MESH']
    col = bpy.data.collections.new("CAP_Glints")
    scene.collection.children.link(col)
    # Not a "_lamp_": the glints lie on the water, so they come from the render itself, where
    # the turbines in front hide them, and are not painted back over the print.
    mat = lamp_material(1.3, "glint", GLINT)
    along = mathutils.Vector((math.sqrt(0.5), math.sqrt(0.5), 0.0))  # across the view
    rng = random.Random(23)
    u0 = x0 * along.x + y0 * along.y
    u1 = x1 * along.x + y1 * along.y
    made = tries = 0
    while made < count and tries < count * 60:
        tries += 1
        x, y = rng.uniform(x0, x1), rng.uniform(y0, y1)
        hit, loc, nrm, idx, ob, _ = scene.ray_cast(dg, mathutils.Vector((x, y, z1 + 30.0)),
                                                   mathutils.Vector((0, 0, -1)))
        if not hit or ob not in plate:
            continue
        me = ob.data
        mi = me.polygons[idx].material_index if idx < len(me.polygons) else -1
        mname = me.materials[mi].name.split("@")[0] if 0 <= mi < len(me.materials) and me.materials[mi] else ""
        if mname not in ("map_sea", "map_shelf"):
            continue
        u = ((x * along.x + y * along.y) - u0) / max(u1 - u0, 1e-6)
        if rng.random() > u ** 1.4:
            continue
        half = rng.uniform(0.06, 0.16)
        wid = rng.uniform(0.018, 0.03)
        side = mathutils.Vector((-along.y, along.x, 0.0))
        z = loc.z + 0.004
        vs = [loc + along * half + side * wid, loc - along * half + side * wid,
              loc - along * half - side * wid, loc + along * half - side * wid]
        g = bpy.data.meshes.new("glint%d" % made)
        g.from_pydata([(v.x, v.y, z) for v in vs], [], [(0, 1, 2, 3)])
        gob = bpy.data.objects.new("glint%d" % made, g)
        col.objects.link(gob)
        g.materials.append(mat)
        _noink(gob)
        made += 1
    return made


def _add_pools(placed, gain):
    for b in placed:
        watts = POOLS.get(b["label"])
        if not watts or b["collection"] not in bpy.data.collections:
            continue
        x, y, top = _front(b["collection"])
        colour = WORK if b["collection"] in FLOOR_LIT else POOL      # the EV plant's is white
        # Close in front of the face and a third of the way up, so the light washes the
        # building's front and spills onto the ground before it.
        _lamp("pool_" + b["collection"], x + TOWARD_CAM[0] * 0.40, y + TOWARD_CAM[1] * 0.40,
              min(1.6, 0.34 * top + 0.35), watts * gain, colour)
        _pools[-1].data.shadow_soft_size = 0.9                 # broad, so the face washes evenly


def apply_look(name, placed, sun, world_bg):
    look = LOOKS[name]
    if look is None:
        return None
    sun.data.color = look["sun"]
    sun.data.energy *= look["sun_gain"]
    if world_bg is not None:
        world_bg.inputs[0].default_value = (*look["world"], 1.0)
        world_bg.inputs[1].default_value = look["world_strength"]
    lamp = lamp_material(look["window_strength"])
    lit = _light_windows(look["windows"], lamp)
    _add_pools(placed, look["pools"])
    _interiors(look["pools"], look["hall_glow"], lamp)
    port = _port_lights(look["pools"])
    tower = _tower_lights(look["pools"])
    _car_lamps(2.6, 6.0 * look["pools"])
    if look.get("pit"):
        _pit_lights(look["pit"] * look["pools"])
    glints = 0
    if look.get("sea_light"):
        _sea_light(look["sea_light"])
    if look.get("glints"):
        glints = _glints(look["glints"])
    print("LOOK %s: %d windows lit, %d lamps, %d port parts, %d tower lights, %d glints" % (
        name, lit, len(_pools), port, tower, glints))
    return look


def side_lighting(name, side, sun, world_bg, sun_energy):
    """Light the scene as one side of the look: its north-west ("nw"), with its sun and fill
    moved part of the way toward another look's, or its sea side ("se"), with a stronger sun
    and fill. The lamps stay the look's own. The render made under it is blended into the
    look's own by finish_render.py along the plate: the north-west one fully at the plate's
    north-west end, easing out by its ramp's end; the sea one easing in from its ramp's
    start to fully at the sea end. So the mine's side sits toward dusk and the sea side is
    brighter (owner). Returns the ramp, or None when the look has no such side."""
    look = LOOKS[name]
    if not look or not look.get(side):
        return None
    sun.data.color = look["sun"]
    sun.data.energy = sun_energy * look["sun_gain"]
    world = look["world"]
    strength = look["world_strength"]
    if side == "nw":
        other, share, ramp = look["nw"]
        o = LOOKS[other]

        def mix(a, b):
            return tuple(x + (y - x) * share for x, y in zip(a, b))

        sun.data.color = mix(look["sun"], o["sun"])
        sun.data.energy = sun_energy * (look["sun_gain"] + (o["sun_gain"] - look["sun_gain"]) * share)
        world = mix(look["world"], o["world"])
        strength = look["world_strength"] + (o["world_strength"] - look["world_strength"]) * share
    else:
        sun_scale, world_scale, ramp = look["se"]
        sun.data.energy *= sun_scale
        strength *= world_scale
    if world_bg is not None:
        world_bg.inputs[0].default_value = (*world, 1.0)
        world_bg.inputs[1].default_value = strength
    return ramp


def pools_off():
    for ob in _pools:
        ob.data.energy = 0.0


def glow_pass(path, sun, world_bg):
    """Every light source alone on black: lamp windows and glows at their emission, all else
    black, no ink, no lights."""
    scene = bpy.context.scene
    pools_off()
    sun.data.energy = 0.0
    if world_bg is not None:
        world_bg.inputs[1].default_value = 0.0
    for mt in bpy.data.materials:
        if not mt.use_nodes:
            continue
        glow = _base(mt) in GLOWS or _base(mt) in HALLS or mt.name.startswith("_lamp_")
        for n in mt.node_tree.nodes:
            if n.type == 'EMISSION' and not glow:
                n.inputs["Strength"].default_value = 0.0
        b = mt.node_tree.nodes.get("Principled BSDF")
        if b is None:
            continue
        b.inputs["Base Color"].default_value = (0, 0, 0, 1)
        if not glow:
            b.inputs["Emission Strength"].default_value = 0.0
    # Under the Standard view the lamps keep their colour: AgX runs a bright amber toward
    # white, so the print paints the light sources from this pass rather than the render.
    fs, vt = scene.render.use_freestyle, scene.view_settings.view_transform
    scene.render.use_freestyle = False
    scene.view_settings.view_transform = 'Standard'
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    scene.render.use_freestyle = fs
    scene.view_settings.view_transform = vt
