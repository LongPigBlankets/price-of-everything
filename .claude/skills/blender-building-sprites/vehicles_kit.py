"""Road vehicles for the loading street — European cab-over trucks and sedans.

Run AFTER sprite_kit.py (and alongside props_kit.py); patches Kit with .truck()
and .car(), same as props_kit patches the tree/grass helpers.

Owner: trucks are European cab-over — flat face, cab raised over the front axle,
boxy trailer, white or black. Cars are sedans in assorted colours, with a rounded
nose, open wheel arches, headlights and a raked windscreen. Both carry red tail
lights and a number plate.

Scale: everything is authored in design units and multiplied by VEH_SCALE on the
way out (owner: 30% smaller against the lanes — they were reading oversized). Lane
centres stay at +/-0.29; nothing crosses the centre line.

Plates are generated from a per-vehicle seed so a given vehicle keeps the same
plate in every frame — a fresh random string each frame would flicker, and the
film re-places all traffic every frame.
"""
import bpy
import bmesh
import math
import random

VEH_SCALE = 0.70
# The ROAD SLAB's top is at z=0.065, not 0 — the vehicles were authored against
# z=0, which buried 40% of every wheel in the tarmac. Everything now sits on this,
# and the wheels are allowed to sink only ~3.5% of their height so the tyre still
# reads as meeting the road rather than hovering on it.
ROAD_TOP = 0.065
WHEEL_SINK = 0.93

PALETTE["truck_white"] = (0.560, 0.545, 0.500)   # body white, under the AgX ceiling
PALETTE["truck_black"] = (0.055, 0.058, 0.075)
PALETTE["car_red"] = (0.330, 0.075, 0.055)
PALETTE["car_blue"] = (0.075, 0.135, 0.290)
PALETTE["car_green"] = (0.080, 0.175, 0.110)
PALETTE["car_cream"] = (0.470, 0.430, 0.330)
PALETTE["car_grey"] = (0.185, 0.195, 0.205)
PALETTE["car_rust"] = (0.360, 0.180, 0.060)
PALETTE["tyre"] = (0.055, 0.055, 0.060)
PALETTE["screen"] = (0.100, 0.135, 0.185)        # glazing, darker than window_glass
PALETTE["lamp_red"] = (0.520, 0.045, 0.040)      # tail lights
PALETTE["lamp_warm"] = (0.720, 0.660, 0.420)     # headlights
PALETTE["plate"] = (0.640, 0.615, 0.520)         # plate backing
PALETTE["plate_ink"] = (0.045, 0.045, 0.055)
PALETTE["veh_shadow"] = (0.088, 0.098, 0.088)   # road tone, darkened

CAR_COLOURS = ("car_red", "car_blue", "car_green", "car_cream", "car_grey", "car_rust")

# Cargo placards on the trailer backs, drawn from the game's own goods art so the
# loading screen advertises the actual economy. Assigned by the vehicle's seed, so
# a given truck always hauls the same cargo — the film rebuilds all traffic every
# frame and a per-frame choice would flicker between goods.
ICON_DIR = ("/Users/crisu/Price of Everything/price-of-everything/"
            "price-of-everything-0.1/assets/icons/goods/medium/")
CARGO_ICONS = ("g_008_motor.png", "g_038_glass.png", "g_029_aluminium.png",
               "g_036_electrical_components.png")


def _cargo_placard(self, name, icon_file, x, y, z, h, nx, mat_bg):
    """Cream placard with a goods icon on the trailer's REAR ONLY.

    Built as a SINGLE QUAD, not a box. A box carries the texture on its front AND
    its back face, and with an alpha-blended material EEVEE does not depth-sort
    the two — so the icon rendered doubled with its own mirror image, and it also
    appeared on the front of the cab. One quad plus backface culling gives exactly
    one icon, on the back, facing the way it should.

    The icon is an IMAGE TEXTURE rather than modelled geometry: these are the
    shipped goods icons, pre-keyed with alpha, and redrawing them as boxes would
    lose the thing that makes them recognisable. NOINK, or Freestyle traces a hard
    rectangle around the placard face.
    """
    import os
    self.box("%s_placard" % name, x, y, z, 0.02, h * 1.42, h * 1.42, mat_bg)
    path = os.path.join(ICON_DIR, icon_file)
    if not os.path.exists(path):
        return None
    mat = bpy.data.materials.get("veh_cargo_" + icon_file)
    if mat is None:
        mat = bpy.data.materials.new("veh_cargo_" + icon_file)
        mat.use_nodes = True
        mat.blend_method = 'BLEND'
        mat.use_backface_culling = True
        nt = mat.node_tree
        nt.nodes.clear()
        img = bpy.data.images.get(icon_file) or bpy.data.images.load(path)
        tex = nt.nodes.new("ShaderNodeTexImage")
        tex.image = img
        tex.interpolation = 'Closest'
        emit = nt.nodes.new("ShaderNodeEmission")
        emit.inputs["Strength"].default_value = 1.0
        trans = nt.nodes.new("ShaderNodeBsdfTransparent")
        mix = nt.nodes.new("ShaderNodeMixShader")
        out = nt.nodes.new("ShaderNodeOutputMaterial")
        nt.links.new(tex.outputs["Color"], emit.inputs["Color"])
        nt.links.new(tex.outputs["Alpha"], mix.inputs["Fac"])
        nt.links.new(trans.outputs[0], mix.inputs[1])
        nt.links.new(emit.outputs[0], mix.inputs[2])
        nt.links.new(mix.outputs[0], out.inputs["Surface"])
    px = x + 0.014 * (1.0 if nx > 0 else -1.0)
    y0, y1, z0, z1 = y - h / 2, y + h / 2, z - h / 2, z + h / 2
    me = bpy.data.meshes.new("%s_cargo" % name)
    bm = bmesh.new()
    order = ((y0, z0), (y1, z0), (y1, z1), (y0, z1)) if nx > 0 else \
            ((y0, z0), (y0, z1), (y1, z1), (y1, z0))
    face = bm.faces.new([bm.verts.new((px, vy, vz)) for vy, vz in order])
    face.smooth = False
    bm.normal_update()
    bm.to_mesh(me)
    bm.free()
    ob = self.obj("%s_cargo" % name, me, mat)
    me.uv_layers.new(name="UVMap")
    uv = me.uv_layers.active.data
    for poly in me.polygons:
        poly.use_smooth = False
        for li in poly.loop_indices:
            co = me.vertices[me.loops[li].vertex_index].co
            # Camera right is -Y, so from the -X side u must run against +Y or the
            # art comes out mirrored.
            uv[li].uv = ((co.y - y0) / h if nx > 0 else (y1 - co.y) / h,
                         (co.z - z0) / h)
    attr = me.attributes.get("freestyle_face") or me.attributes.new("freestyle_face", 'BOOLEAN', 'FACE')
    for d in attr.data:
        d.value = True
    return ob


_LET = "ABCDEFGHJKLMNPRSTVWXYZ"


def plate_text(seed):
    """UK-shaped plate, deterministic per vehicle so it never flickers."""
    rng = random.Random(seed)
    return "%s%s%02d %s%s%s" % (rng.choice(_LET), rng.choice(_LET), rng.randint(1, 74),
                                rng.choice(_LET), rng.choice(_LET), rng.choice(_LET))


def _plate(self, name, text, x, y, z, h, face, mat_bg, mat_ink):
    """Number plate: a pale backing with real extruded characters on it. The text is
    built as a FONT curve, evaluated to a mesh and the temporary object dropped —
    a live curve would be re-evaluated every render for no gain. NOINK: at plate
    size the ink outline would merge the glyphs into one black bar."""
    self.box("%s_plate" % name, x, y, z, 0.02, h * 3.1, h * 1.15, mat_bg)
    cur = bpy.data.curves.new(name + "_pc", type='FONT')
    cur.body = text
    cur.size = h
    cur.align_x = 'CENTER'
    cur.align_y = 'CENTER'
    cur.extrude = 0.004
    tmp = bpy.data.objects.new(name + "_ptmp", cur)
    bpy.context.scene.collection.objects.link(tmp)
    tmp.rotation_euler = (math.radians(90.0), 0.0, math.radians(90.0 * (1 if face > 0 else -1)))
    tmp.location = (x + (0.012 if face > 0 else -0.012), y, z)
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(tmp.evaluated_get(dg))
    # new_from_object hands back LOCAL-space geometry: without this every plate's
    # lettering piled up at the world origin instead of sitting on its vehicle.
    me.transform(tmp.matrix_world)
    bpy.data.objects.remove(tmp, do_unlink=True)
    bpy.data.curves.remove(cur)
    ob = self.obj("%s_ptxt" % name, me, mat_ink)
    for p in ob.data.polygons:
        p.use_smooth = False
    attr = me.attributes.get("freestyle_face") or me.attributes.new("freestyle_face", 'BOOLEAN', 'FACE')
    for d in attr.data:
        d.value = True
    return ob


def _frustum(self, name, cx, cy, z0, z1, lx0, ly0, lx1, ly1, mat):
    """Truncated box: a smaller rectangle on top of a larger one. This is what
    makes the cabin read as a car instead of a crate — the roof is shorter AND
    narrower than the waist, so the ends rake and the sides tumblehome. The glass
    is then laid on those raked faces rather than standing vertical."""
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    bot = [bm.verts.new(v) for v in ((cx - lx0 / 2, cy - ly0 / 2, z0),
                                     (cx + lx0 / 2, cy - ly0 / 2, z0),
                                     (cx + lx0 / 2, cy + ly0 / 2, z0),
                                     (cx - lx0 / 2, cy + ly0 / 2, z0))]
    top = [bm.verts.new(v) for v in ((cx - lx1 / 2, cy - ly1 / 2, z1),
                                     (cx + lx1 / 2, cy - ly1 / 2, z1),
                                     (cx + lx1 / 2, cy + ly1 / 2, z1),
                                     (cx - lx1 / 2, cy + ly1 / 2, z1))]
    bm.faces.new(list(reversed(bot)))
    bm.faces.new(top)
    for i in range(4):
        j = (i + 1) % 4
        bm.faces.new((bot[i], bot[j], top[j], top[i]))
    bm.normal_update()
    bm.to_mesh(me)
    bm.free()
    ob = self.obj(name, me, mat)
    for poly in ob.data.polygons:
        poly.use_smooth = False
    return ob


def _wheel(self, name, cx, cy, cz, r, w, mat, segs=14):
    """A full ROUND wheel (owner: not half-cylinders — those read as bricks). 14
    flat segments is round enough at street size and keeps the faceted look; the
    car body no longer has an underside slab, so the whole wheel is visible."""
    self.dircyl(name, (cx, cy - w * 0.5, cz), (cx, cy + w * 0.5, cz), r, mat,
                segments=segs, smooth=False)


def _wheels(self, name, x, y, xs, half_w, r, mat, face=1.0, s=1.0):
    """NOTE the x/y: these used to be placed in ABSOLUTE coordinates, so every
    vehicle's wheels sat in a heap near the world origin instead of under the
    vehicle — which is why the cars looked like blocks with nothing underneath."""
    for i, wx in enumerate(xs):
        for sg in (-1, 1):
            _wheel(self, "%s_w%d%s" % (name, i, "p" if sg > 0 else "m"),
                   x + face * wx * s, y + sg * half_w * s,
                   ROAD_TOP + WHEEL_SINK * r * s, r * s, 0.055 * s, mat)


def _shadow(self, name, x, y, length, width, mat):
    """A flat dark patch on the road under the vehicle. Grounds it: without one a
    body with open arches reads as floating. NOINK — an outline would make it a
    solid object rather than shade."""
    ob = self.box(name + "_shadow", x, y, ROAD_TOP + 0.004, length, width, 0.008, mat)
    me = ob.data
    attr = me.attributes.get("freestyle_face") or me.attributes.new("freestyle_face", 'BOOLEAN', 'FACE')
    for d in attr.data:
        d.value = True
    return ob


def _truck(self, name, x, y, face=1.0, colour="truck_white", seed=0):
    """European cab-over: FLAT vertical front face, cab raised over the front axle,
    boxy trailer behind. `face` +1 points down-street, -1 back at the camera.

    The trailer floor sits HIGH with a narrow chassis beam under it (owner): with
    the body carried down to the axles the bogie wheels looked like part of the
    cargo box. Now they hang in open air under the trailer, which is what a semi
    actually looks like."""
    s = VEH_SCALE
    body = self.mat(colour)
    dark = self.mat("truck_black" if colour != "truck_black" else "darkmetal")
    tyre, glass = self.mat("tyre"), self.mat("screen")
    red, warm = self.mat("lamp_red"), self.mat("lamp_warm")
    f = face

    def bx(nm, cx, cy, cz, sx, sy, sz, m):
        return self.box("%s_%s" % (name, nm), x + f * cx * s, y + cy * s,
                        cz * s + ROAD_TOP, sx * s, sy * s, sz * s, m)

    # ---- tractor ----
    bx("cab", 1.55, 0.0, 0.70, 1.10, 0.52, 0.86, body)             # z 0.27..1.13
    bx("screen", 2.10, 0.0, 0.90, 0.03, 0.396, 0.27, glass)
    bx("grille", 2.10, 0.0, 0.48, 0.03, 0.40, 0.16, dark)
    bx("bumper", 2.09, 0.0, 0.33, 0.06, 0.50, 0.12, dark)
    for sg in (-1, 1):
        bx("hlamp%d" % (sg > 0), 2.11, sg * 0.17, 0.40, 0.02, 0.11, 0.07, warm)
        bx("cabwin%d" % (sg > 0), 1.72, sg * 0.265, 0.90, 0.42, 0.02, 0.26, glass)
    bx("deflector", 1.35, 0.0, 1.18, 0.60, 0.46, 0.10, body)
    bx("chassis", 0.55, 0.0, 0.28, 2.10, 0.30, 0.09, dark)

    # ---- trailer, floor raised clear of the bogie ----
    bx("trailer", -0.72, 0.0, 0.88, 2.86, 0.54, 0.80, body)        # z 0.48..1.28
    bx("beam", -1.10, 0.0, 0.42, 2.10, 0.28, 0.10, dark)           # the chassis rail
    bx("tdoor", -2.15, 0.0, 0.88, 0.03, 0.48, 0.76, dark)
    bx("tbar", -2.18, 0.0, 0.30, 0.05, 0.46, 0.07, dark)           # rear underrun bar
    for sg in (-1, 1):
        bx("tlamp%d" % (sg > 0), -2.18, sg * 0.17, 0.58, 0.03, 0.10, 0.09, red)
        bx("mudguard%d" % (sg > 0), -1.59, sg * 0.27, 0.40, 0.72, 0.05, 0.05, dark)
    self.seam("%s_seam" % name, x + f * 0.85 * s, y, 0.88 * s + ROAD_TOP, 0.48 * s, axis='Z')
    _plate(self, name, plate_text(seed), x + f * -2.19 * s, y, 0.58 * s + ROAD_TOP,
           0.062 * s, -f, self.mat("plate"), self.mat("plate_ink"))
    _cargo_placard(self, name, CARGO_ICONS[seed % len(CARGO_ICONS)],
                   x + f * -2.18 * s, y, 0.94 * s + ROAD_TOP, 0.255 * s, -f,
                   self.mat("cream"))
    _wheels(self, name, x, y, (1.72, 0.92, -1.40, -1.78), 0.26, 0.115, tyre, f, s)
    _shadow(self, name, x - f * 0.35 * s, y, 4.35 * s, 0.66 * s, self.mat("veh_shadow"))
    return {"len": 4.3 * s}


def _car(self, name, x, y, face=1.0, colour="car_red", seed=0):
    """Sedan. The cabin is a FRUSTUM, not a box (owner): roof shorter and narrower
    than the waist, so both screens rake ~22 degrees toward the middle of the car
    and the sides tumblehome. Everything else follows that shape — glass laid on
    the raked faces at the matching angle, side glass tilted with the tumblehome,
    and the bonnet falling forward into the base of the screen.

    Vertical stack matters as much as the shape. Deleting the underside slab
    outright left the body floating a whole wheel-radius above the road on four
    exposed tyres — it read as a flatbed. There IS a lower body (a rocker), but it
    spans only between the axles, so the wheels stand in open arches while the car
    still has a bottom.
    """
    s = VEH_SCALE
    body = self.mat(colour)
    glass, tyre = self.mat("screen"), self.mat("tyre")
    red, warm = self.mat("lamp_red"), self.mat("lamp_warm")
    f = face

    def bx(nm, cx, cy, cz, sx, sy, sz, m):
        return self.box("%s_%s" % (name, nm), x + f * cx * s, y + cy * s,
                        cz * s + ROAD_TOP, sx * s, sy * s, sz * s, m)

    def rbx(nm, cx, cy, cz, sx, sy, sz, m, ang, axis='Y'):
        return self.rotbox("%s_%s" % (name, nm), x + f * cx * s, y + cy * s,
                           cz * s + ROAD_TOP, sx * s, sy * s, sz * s, m, axis,
                           ang * (f if axis == 'Y' else 1.0))

    # Rocker: between the axles only, so the wheels stand in open arches.
    bx("rocker", 0.0, 0.0, 0.143, 0.72, 0.42, 0.100, body)         # z 0.093..0.193
    # WAIST. Its height against the glasshouse is what decides whether this reads
    # as a car: body 0.167 vs glass 0.118 is roughly 60/40, sedan proportion. The
    # earlier 0.128/0.172 had more glass than body, which is a van.
    bx("belt", 0.0, 0.0, 0.2765, 1.44, 0.48, 0.167, body)          # z 0.193..0.360
    # Nose caps step DOWN inside the waist, which is where the bonnet's forward
    # fall comes from. No separate hood lid: proud of the waist and a hair wider,
    # it flanged all round and the car read as a flatbed with side walls.
    bx("nose1", 0.78, 0.0, 0.2705, 0.12, 0.470, 0.155, body)
    bx("nose2", 0.855, 0.0, 0.2580, 0.05, 0.380, 0.130, body)
    bx("nose3", 0.885, 0.0, 0.2450, 0.03, 0.260, 0.100, body)
    bx("fbumper", 0.845, 0.0, 0.205, 0.09, 0.44, 0.05, body)
    bx("tail_end", -0.76, 0.0, 0.2705, 0.12, 0.470, 0.155, body)
    bx("rbumper", -0.83, 0.0, 0.205, 0.06, 0.44, 0.05, body)

    # ---- the glasshouse ----
    # waist 0.86 long / 0.44 wide at z 0.360; roof 0.765 / 0.37 at z 0.478.
    # 0.048 of run over 0.118 of rise = 22 deg on both screens (owner: ~20); the
    # sides pull in 0.035 over the same rise = 16 deg of tumblehome.
    z0, z1, cxc = 0.360, 0.478, -0.10
    _frustum(self, "%s_cabin" % name, x + f * cxc * s, y,
             z0 * s + ROAD_TOP, z1 * s + ROAD_TOP,
             0.86 * s, 0.44 * s, 0.765 * s, 0.37 * s, body)
    rake, zmid = 22.0, 0.419
    rbx("wscreen", 0.3062, 0.0, zmid, 0.02, 0.38, 0.120, glass, -rake)
    rbx("rscreen", -0.5062, 0.0, zmid, 0.02, 0.38, 0.112, glass, rake)
    for sg in (-1, 1):
        rbx("side%d" % (sg > 0), cxc, sg * 0.204, zmid, 0.58, 0.02, 0.085,
            glass, sg * 16.5, axis='X')
        bx("hlamp%d" % (sg > 0), 0.872, sg * 0.125, 0.278, 0.03, 0.10, 0.055, warm)
        bx("tlamp%d" % (sg > 0), -0.815, sg * 0.155, 0.300, 0.02, 0.10, 0.055, red)
    _plate(self, name, plate_text(seed), x + f * -0.83 * s, y, 0.228 * s + ROAD_TOP,
           0.044 * s, -f, self.mat("plate"), self.mat("plate_ink"))
    _wheels(self, name, x, y, (0.52, -0.52), 0.205, 0.115, tyre, f, s)
    _shadow(self, name, x, y, 1.82 * s, 0.60 * s, self.mat("veh_shadow"))
    return {"len": 1.8 * s}


Kit.truck = _truck
Kit.car = _car
Kit.CAR_COLOURS = CAR_COLOURS
