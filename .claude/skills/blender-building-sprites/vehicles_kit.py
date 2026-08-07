"""Road vehicles for the loading street — European cab-over trucks and sedans.

Run AFTER sprite_kit.py (and alongside props_kit.py); patches Kit with .truck()
and .car(), same as props_kit patches the tree/grass helpers.

Owner 2026-08-06: "trucks should use the European style flat face and raised cab
as well as a boxy trailer. All white or black. Cars just regular sedans in
different colours."

Scale check against the street: the road is 1.24 wide (ROAD_HALF_W 0.62), so a
vehicle can be no wider than ~0.55 or two cannot pass. Lane centres sit at
y = +/-0.29 and nothing crosses the centre line. Traffic keeps LEFT (the game is
British): +X traffic on the +Y side, oncoming on -Y.

Everything is flat-shaded boxes and low-segment cylinders — at street distance a
vehicle is a few dozen pixels, and the ink outline carries the read, so detail
past the silhouette is wasted.
"""
import bpy
import math

PALETTE["truck_white"] = (0.560, 0.545, 0.500)   # body white, held under the AgX ceiling
PALETTE["truck_black"] = (0.055, 0.058, 0.075)
PALETTE["car_red"] = (0.330, 0.075, 0.055)
PALETTE["car_blue"] = (0.075, 0.135, 0.290)
PALETTE["car_green"] = (0.080, 0.175, 0.110)
PALETTE["car_cream"] = (0.470, 0.430, 0.330)
PALETTE["car_grey"] = (0.185, 0.195, 0.205)
PALETTE["car_rust"] = (0.360, 0.180, 0.060)
PALETTE["tyre"] = (0.055, 0.055, 0.060)
PALETTE["screen"] = (0.100, 0.135, 0.185)        # glazing, darker than window_glass

CAR_COLOURS = ("car_red", "car_blue", "car_green", "car_cream", "car_grey", "car_rust")


def _wheels(self, name, xs, half_w, r, mat, face=1.0):
    """Axle pairs. Cylinders run along Y; 10 segments is enough at this size."""
    for i, wx in enumerate(xs):
        for s in (-1, 1):
            self.dircyl("%s_w%d%s" % (name, i, "p" if s > 0 else "m"),
                        (face * wx, s * half_w, r), (face * wx, s * (half_w + 0.055), r),
                        r, mat, segments=10, smooth=False)


def _truck(self, name, x, y, face=1.0, colour="truck_white"):
    """European cab-over: FLAT vertical front face, cab raised over the front axle,
    boxy trailer behind. `face` +1 points down-street (+X), -1 points back at the
    camera. Local +x is the front; the whole body is mirrored for face=-1."""
    body = self.mat(colour)
    dark = self.mat("truck_black" if colour != "truck_black" else "darkmetal")
    tyre = self.mat("tyre")
    glass = self.mat("screen")
    f = face

    def bx(nm, cx, cy, cz, sx, sy, sz, m):
        return self.box("%s_%s" % (name, nm), x + f * cx, y + cy, cz, sx, sy, sz, m)

    # ---- tractor: cab sits high and starts AT the bumper (no bonnet) ----
    bx("cab", 1.55, 0.0, 0.66, 1.10, 0.52, 0.86, body)          # z 0.23 .. 1.09
    bx("screen", 2.10, 0.0, 0.86, 0.03, 0.44, 0.30, glass)      # flat front glazing
    bx("grille", 2.10, 0.0, 0.44, 0.03, 0.40, 0.16, dark)
    bx("bumper", 2.09, 0.0, 0.29, 0.06, 0.50, 0.12, dark)
    bx("deflector", 1.35, 0.0, 1.14, 0.60, 0.46, 0.10, body)    # roof air deflector
    bx("chassis", 0.55, 0.0, 0.20, 2.10, 0.34, 0.10, dark)
    for s in (-1, 1):                                            # cab side glazing
        bx("cabwin%d" % (s > 0), 1.72, s * 0.265, 0.86, 0.42, 0.02, 0.26, glass)

    # ---- trailer: plain box, riding above the tractor's deck line ----
    bx("trailer", -0.72, 0.0, 0.76, 2.86, 0.54, 0.96, body)     # z 0.28 .. 1.24
    bx("tskirt", -0.72, 0.0, 0.24, 2.80, 0.44, 0.10, dark)
    bx("tdoor", -2.15, 0.0, 0.76, 0.03, 0.48, 0.88, dark)       # rear doors
    self.seam("%s_seam" % name, x + f * 0.85, y, 0.76, 0.48, axis='Z')

    _wheels(self, name, (1.72, 0.92, -1.40, -1.78), 0.26, 0.115, tyre, f)
    return {"len": 4.3, "w": 0.54}


def _car(self, name, x, y, face=1.0, colour="car_red"):
    """Three-box sedan: bonnet, cabin set back, boot. Read is the silhouette."""
    body = self.mat(colour)
    glass = self.mat("screen")
    tyre = self.mat("tyre")
    f = face

    def bx(nm, cx, cy, cz, sx, sy, sz, m):
        return self.box("%s_%s" % (name, nm), x + f * cx, y + cy, cz, sx, sy, sz, m)

    bx("body", 0.0, 0.0, 0.235, 1.62, 0.48, 0.26, body)          # z 0.105 .. 0.365
    bx("cabin", -0.06, 0.0, 0.45, 0.78, 0.44, 0.17, body)        # z 0.365 .. 0.535
    bx("wscreen", 0.34, 0.0, 0.45, 0.03, 0.40, 0.13, glass)
    bx("rscreen", -0.46, 0.0, 0.45, 0.03, 0.40, 0.13, glass)
    for s in (-1, 1):
        bx("side%d" % (s > 0), -0.06, s * 0.225, 0.45, 0.62, 0.02, 0.12, glass)
    bx("lamp", 0.80, 0.0, 0.27, 0.03, 0.34, 0.08, self.mat("cream"))
    bx("tail", -0.80, 0.0, 0.27, 0.03, 0.34, 0.07, self.mat("car_red"))
    _wheels(self, name, (0.52, -0.52), 0.225, 0.095, tyre, f)
    return {"len": 1.7, "w": 0.48}


Kit.truck = _truck
Kit.car = _car
Kit.CAR_COLOURS = CAR_COLOURS
