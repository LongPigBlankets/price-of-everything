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


def _cargo_placard(self, name, icon_file, x, y, z, h, face, mat_bg):
    """Cream placard with a goods icon, inset from the trailer edges.

    The icon is an IMAGE TEXTURE rather than modelled geometry — these are the
    shipped goods icons, pre-keyed with alpha, and redrawing them in boxes would
    lose the thing that makes them recognisable. Alpha-blended so the keyed
    surround does not print as a cream square, and NOINK so Freestyle does not
    trace a hard rectangle around the placard face."""
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
    ob = self.box("%s_cargo" % name, x + (0.014 if face > 0 else -0.014), y, z,
                  0.004, h, h, mat)
    me = ob.data
    me.uv_layers.new(name="UVMap")
    uv = me.uv_layers.active.data
    for poly in me.polygons:
        poly.use_smooth = False
        n = poly.normal
        for li in poly.loop_indices:
            vi = me.loops[li].vertex_index
            co = me.vertices[vi].co
            if abs(n.x) > 0.5:                       # the two faces we actually see
                u = (co.y - (y - h / 2)) / h
                v = (co.z - (z - h / 2)) / h
                uv[li].uv = (u if n.x * face > 0 else 1.0 - u, v)
            else:
                uv[li].uv = (0.0, 0.0)
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
    bpy.data.objects.remove(tmp, do_unlink=True)
    bpy.data.curves.remove(cur)
    ob = self.obj("%s_ptxt" % name, me, mat_ink)
    for p in ob.data.polygons:
        p.use_smooth = False
    attr = me.attributes.get("freestyle_face") or me.attributes.new("freestyle_face", 'BOOLEAN', 'FACE')
    for d in attr.data:
        d.value = True
    return ob


def _half_wheel(self, name, cx, cy, cz, r, w, mat, segs=9):
    """The BOTTOM HALF of a wheel (owner) — a semicircular prism lying along Y.
    Only the lower half is ever outside the arch, so a full cylinder spends its
    top half buried in the bodywork; this also keeps it from poking through.
    Built by hand: a semicircle plus its chord, extruded across the tyre width."""
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    prof = []
    for i in range(segs + 1):
        a = math.pi + math.pi * i / segs           # 180 -> 360 deg = the lower half
        prof.append((cx + r * math.cos(a), cz + r * math.sin(a)))
    ring = [bm.verts.new((px, cy - w * 0.5, pz)) for px, pz in prof]
    back = [bm.verts.new((px, cy + w * 0.5, pz)) for px, pz in prof]
    bm.faces.new(ring)
    bm.faces.new(list(reversed(back)))
    for i in range(len(ring) - 1):
        bm.faces.new((ring[i], ring[i + 1], back[i + 1], back[i]))
    bm.faces.new((ring[-1], ring[0], back[0], back[-1]))   # close along the chord
    bm.normal_update()
    bm.to_mesh(me)
    bm.free()
    ob = self.obj(name, me, mat)
    for poly in ob.data.polygons:
        poly.use_smooth = False
    return ob


def _wheels(self, name, x, y, xs, half_w, r, mat, face=1.0, s=1.0):
    """NOTE the x/y: these used to be placed in ABSOLUTE coordinates, so every
    vehicle's wheels sat in a heap near the world origin instead of under the
    vehicle — which is why the cars looked like blocks with nothing underneath."""
    for i, wx in enumerate(xs):
        for sg in (-1, 1):
            _half_wheel(self, "%s_w%d%s" % (name, i, "p" if sg > 0 else "m"),
                        x + face * wx * s, y + sg * half_w * s, r * s,
                        r * s, 0.075 * s, mat)


def _shadow(self, name, x, y, length, width, mat):
    """A flat dark patch on the road under the vehicle. Grounds it: without one a
    body with open arches reads as floating. NOINK — an outline would make it a
    solid object rather than shade."""
    ob = self.box(name + "_shadow", x, y, 0.004, length, width, 0.008, mat)
    me = ob.data
    attr = me.attributes.get("freestyle_face") or me.attributes.new("freestyle_face", 'BOOLEAN', 'FACE')
    for d in attr.data:
        d.value = True
    return ob


def _truck(self, name, x, y, face=1.0, colour="truck_white", seed=0):
    """European cab-over: FLAT vertical front face, cab raised over the front axle,
    boxy trailer behind. `face` +1 points down-street, -1 back at the camera."""
    s = VEH_SCALE
    body = self.mat(colour)
    dark = self.mat("truck_black" if colour != "truck_black" else "darkmetal")
    tyre, glass = self.mat("tyre"), self.mat("screen")
    red, warm = self.mat("lamp_red"), self.mat("lamp_warm")
    f = face

    def bx(nm, cx, cy, cz, sx, sy, sz, m):
        return self.box("%s_%s" % (name, nm), x + f * cx * s, y + cy * s, cz * s,
                        sx * s, sy * s, sz * s, m)

    bx("cab", 1.55, 0.0, 0.66, 1.10, 0.52, 0.86, body)
    bx("screen", 2.10, 0.0, 0.86, 0.03, 0.44, 0.30, glass)
    bx("grille", 2.10, 0.0, 0.44, 0.03, 0.40, 0.16, dark)
    bx("bumper", 2.09, 0.0, 0.29, 0.06, 0.50, 0.12, dark)
    for sg in (-1, 1):
        bx("hlamp%d" % (sg > 0), 2.11, sg * 0.17, 0.36, 0.02, 0.11, 0.07, warm)
        bx("cabwin%d" % (sg > 0), 1.72, sg * 0.265, 0.86, 0.42, 0.02, 0.26, glass)
    bx("deflector", 1.35, 0.0, 1.14, 0.60, 0.46, 0.10, body)
    bx("chassis", 0.55, 0.0, 0.20, 2.10, 0.34, 0.10, dark)

    bx("trailer", -0.72, 0.0, 0.76, 2.86, 0.54, 0.96, body)
    bx("tskirt", -0.72, 0.0, 0.24, 2.80, 0.44, 0.10, dark)
    bx("tdoor", -2.15, 0.0, 0.78, 0.03, 0.48, 0.84, dark)
    bx("tbar", -2.18, 0.0, 0.24, 0.05, 0.46, 0.07, dark)          # rear underrun bar
    for sg in (-1, 1):                                             # tail lights
        bx("tlamp%d" % (sg > 0), -2.18, sg * 0.17, 0.42, 0.03, 0.10, 0.09, red)
    self.seam("%s_seam" % name, x + f * 0.85 * s, y, 0.76 * s, 0.48 * s, axis='Z')
    _plate(self, name, plate_text(seed), x + f * -2.19 * s, y, 0.42 * s,
           0.062 * s, -f, self.mat("plate"), self.mat("plate_ink"))
    _cargo_placard(self, name, CARGO_ICONS[seed % len(CARGO_ICONS)],
                   x + f * -2.18 * s, y, 0.84 * s, 0.255 * s, -f, self.mat("cream"))
    _wheels(self, name, x, y, (1.72, 0.92, -1.40, -1.78), 0.26, 0.115, tyre, f, s)
    _shadow(self, name, x - f * 0.35 * s, y, 4.35 * s, 0.66 * s, self.mat("veh_shadow"))
    return {"len": 4.3 * s}


def _car(self, name, x, y, face=1.0, colour="car_red", seed=0):
    """Sedan with a ROUNDED nose (stepped, so it reads round without smoothing),
    OPEN wheel arches — the body only spans between the axles below the belt line,
    so the wheels sit in gaps rather than against a slab — a RAKED windscreen, and
    headlights and tail lights."""
    s = VEH_SCALE
    body = self.mat(colour)
    glass, tyre = self.mat("screen"), self.mat("tyre")
    red, warm = self.mat("lamp_red"), self.mat("lamp_warm")
    f = face

    def bx(nm, cx, cy, cz, sx, sy, sz, m):
        return self.box("%s_%s" % (name, nm), x + f * cx * s, y + cy * s, cz * s,
                        sx * s, sy * s, sz * s, m)

    def rbx(nm, cx, cy, cz, sx, sy, sz, m, ang):
        return self.rotbox("%s_%s" % (name, nm), x + f * cx * s, y + cy * s, cz * s,
                           sx * s, sy * s, sz * s, m, 'Y', ang * f)

    # The sill spans only BETWEEN the axles, so from the wheel stations there is
    # nothing below the belt line and the wheel stands in an open arch. The wheels
    # are also wider than the body (0.205+0.055 out vs a 0.24 half-width): tucked
    # inside they simply vanished behind the flanks at street distance.
    bx("sill", 0.0, 0.0, 0.16, 0.76, 0.42, 0.12, body)             # z 0.10..0.22
    bx("belt", 0.0, 0.0, 0.30, 1.44, 0.48, 0.16, body)             # z 0.22..0.38
    # Rounded nose: steps that shrink in WIDTH as well as height, so the front
    # narrows the way a bonnet does instead of just stepping down.
    rbx("bonnet", 0.58, 0.0, 0.375, 0.46, 0.47, 0.07, body, -9.0)
    bx("nose1", 0.78, 0.0, 0.32, 0.12, 0.44, 0.16, body)
    bx("nose2", 0.855, 0.0, 0.30, 0.05, 0.36, 0.13, body)
    bx("nose3", 0.885, 0.0, 0.285, 0.03, 0.24, 0.09, body)
    bx("fbumper", 0.845, 0.0, 0.215, 0.09, 0.44, 0.05, body)
    bx("tail_end", -0.76, 0.0, 0.32, 0.12, 0.46, 0.15, body)
    bx("rbumper", -0.83, 0.0, 0.215, 0.06, 0.44, 0.05, body)
    # Cabin + raked glazing.
    bx("cabin", -0.10, 0.0, 0.475, 0.66, 0.44, 0.19, body)         # z 0.38..0.57
    rbx("wscreen", 0.26, 0.0, 0.475, 0.05, 0.42, 0.23, glass, -34.0)
    rbx("rscreen", -0.46, 0.0, 0.475, 0.05, 0.42, 0.21, glass, 27.0)
    for sg in (-1, 1):
        bx("side%d" % (sg > 0), -0.10, sg * 0.222, 0.48, 0.52, 0.02, 0.12, glass)
        bx("hlamp%d" % (sg > 0), 0.872, sg * 0.125, 0.315, 0.03, 0.10, 0.06, warm)
        bx("tlamp%d" % (sg > 0), -0.815, sg * 0.155, 0.335, 0.02, 0.10, 0.06, red)
    _plate(self, name, plate_text(seed), x + f * -0.83 * s, y, 0.255 * s,
           0.048 * s, -f, self.mat("plate"), self.mat("plate_ink"))
    _wheels(self, name, x, y, (0.52, -0.52), 0.205, 0.115, tyre, f, s)
    _shadow(self, name, x, y, 1.82 * s, 0.60 * s, self.mat("veh_shadow"))
    return {"len": 1.8 * s}


Kit.truck = _truck
Kit.car = _car
Kit.CAR_COLOURS = CAR_COLOURS
