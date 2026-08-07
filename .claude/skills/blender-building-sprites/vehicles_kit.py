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

CAR_COLOURS = ("car_red", "car_blue", "car_green", "car_cream", "car_grey", "car_rust")
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


def _wheels(self, name, xs, half_w, r, mat, face=1.0, s=1.0):
    for i, wx in enumerate(xs):
        for sg in (-1, 1):
            self.dircyl("%s_w%d%s" % (name, i, "p" if sg > 0 else "m"),
                        (face * wx * s, sg * half_w * s, r * s),
                        (face * wx * s, sg * (half_w + 0.055) * s, r * s),
                        r * s, mat, segments=10, smooth=False)


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
    _wheels(self, name, (1.72, 0.92, -1.40, -1.78), 0.26, 0.115, tyre, f, s)
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
    _wheels(self, name, (0.52, -0.52), 0.205, 0.115, tyre, f, s)
    return {"len": 1.8 * s}


Kit.truck = _truck
Kit.car = _car
Kit.CAR_COLOURS = CAR_COLOURS
