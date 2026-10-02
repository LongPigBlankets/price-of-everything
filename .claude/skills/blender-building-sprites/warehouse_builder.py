"""Tile warehouse — the store every tile's goods pool in. build_warehouse(level).

Shown on the supply chain board as the hub of its tile. One brick shed with a slate gable
roof, a loading dock along the front and a vehicle gate in the right-hand gable.

LEVELS follow the game's three warehouse levels (storage 800 / 1600 / 2500):
  L1  one short shed, two dock doors, a few crates on the apron
  L2  the shed runs longer: three dock doors, a canopy over the dock, a taller crate stack
  L3  a second shed stands behind the first on the same slab (the landmark), four dock
      doors, and a container row on the apron

The front wall (-Y) and the right gable (+X) are the two faces the camera sees, so every
door, window and the dock are on those. The shed is anchored on its right gable: the gate
stays put and the shed runs longer toward -X.
"""
import math

WH_LEVELS = {
    1: dict(length=2.5, sheds=1, doors=2, canopy=False, crates=2, containers=0),
    2: dict(length=3.5, sheds=1, doors=3, canopy=True, crates=3, containers=0),
    3: dict(length=3.9, sheds=2, doors=4, canopy=True, crates=3, containers=3),
}
WH_X1 = 1.6            # the right gable, fixed at every level
WH_DEPTH = 2.0         # one shed, front to back
WH_WALL = 1.15
WH_RISE = 0.62
WH_Y0 = -0.9           # the front wall
WH_APRON = 1.25        # yard in front of the dock
WH_DOCK = 0.42         # dock platform depth
WH_DOCK_H = 0.26


def _shed(K, tag, x0, x1, y0):
    """One gabled shed between x0..x1 with its front wall at y0."""
    cx, ln = (x0 + x1) / 2.0, x1 - x0
    y1 = y0 + WH_DEPTH
    cy = (y0 + y1) / 2.0
    K.box("wall_%s" % tag, cx, cy, WH_WALL / 2.0, ln, WH_DEPTH, WH_WALL, K.mat("wall_brick"))
    # Brick gable: a triangular prism across the shed's length, sunk into the walls.
    K.prism("gable_%s" % tag, (cx, cy, 0.0), (0.0, 1.0),
            [(-WH_DEPTH / 2.0, WH_WALL - 0.04), (WH_DEPTH / 2.0, WH_WALL - 0.04),
             (0.0, WH_WALL + WH_RISE)], ln, K.mat("wall_brick"))
    # Two roof slabs at the gable's own pitch, overhanging the eaves and both gables.
    half = WH_DEPTH / 2.0
    ang = math.degrees(math.atan2(WH_RISE, half))
    run = math.hypot(half, WH_RISE) + 0.16
    lift = 0.05
    for side, sgn in (("f", -1.0), ("b", 1.0)):
        K.rotbox("roof_%s%s" % (tag, side), cx, cy + sgn * (half / 2.0 + 0.04),
                 WH_WALL + WH_RISE / 2.0 + lift - 0.03, ln + 0.20, run, 0.07, K.mat("roof"),
                 'X', -sgn * ang)
    K.box("ridge_%s" % tag, cx, cy, WH_WALL + WH_RISE + lift + 0.01, ln + 0.22, 0.12, 0.07,
          K.mat("darkmetal"))
    return cy


def build_warehouse(level: int = 2) -> dict:
    p = WH_LEVELS[level]
    x0 = WH_X1 - p["length"]
    depth = WH_DEPTH * p["sheds"]
    sx0, sx1 = x0 - 0.30, WH_X1 + 0.95
    sy0, sy1 = WH_Y0 - WH_APRON, WH_Y0 + depth + 0.25
    top = WH_WALL + WH_RISE + 0.15
    setup_rig(target=((sx0 + sx1) / 2.0, (sy0 + sy1) / 2.0, top / 2.0 - 0.05))
    K = Kit(open_collection("BLDG_warehouse"))

    K.box("slab", (sx0 + sx1) / 2.0, (sy0 + sy1) / 2.0, -0.06, sx1 - sx0, sy1 - sy0, 0.12,
          K.mat("yard"))
    K.box("slab_deck", (sx0 + sx1) / 2.0, (sy0 + sy1) / 2.0, 0.005, sx1 - sx0 - 0.24,
          sy1 - sy0 - 0.24, 0.03, K.mat("yard_pad"))

    cy = 0.0
    for s in range(p["sheds"]):
        cy = _shed(K, str(s), x0, WH_X1, WH_Y0 + s * WH_DEPTH)
        # The vehicle gate and a high window in each right-hand gable.
        gy = WH_Y0 + s * WH_DEPTH + WH_DEPTH / 2.0
        K.gate("gate%d" % s, "+X", (WH_X1, gy, 0.44), 0.86, 0.84, slats=5)
        K.window("gwin%d" % s, "+X", (WH_X1, gy, WH_WALL + 0.20), 0.40, 0.26, cols=2, rows=1)

    # The loading dock along the front wall, and its roller doors.
    cx, ln = (x0 + WH_X1) / 2.0, WH_X1 - x0
    K.box("dock", cx, WH_Y0 - WH_DOCK / 2.0 + 0.03, WH_DOCK_H / 2.0, ln - 0.20, WH_DOCK + 0.06,
          WH_DOCK_H, K.mat("slab"))
    n = p["doors"]
    pitch = (ln - 0.5) / n
    for i in range(n):
        dx = x0 + 0.25 + pitch * (i + 0.5)
        K.gate("bay%d" % i, "-Y", (dx, WH_Y0, WH_DOCK_H + 0.33), min(0.56, pitch - 0.22), 0.62,
               slats=4)
        K.box("bump%d" % i, dx, WH_Y0 - WH_DOCK - 0.02, WH_DOCK_H - 0.07, 0.34, 0.05, 0.09,
              K.mat("ink_black"))
    if p["canopy"]:
        cz = WH_DOCK_H + 0.78
        K.box("canopy", cx, WH_Y0 - WH_DOCK / 2.0 - 0.02, cz, ln - 0.10, WH_DOCK + 0.14, 0.05,
              K.mat("darkmetal"))
        for i in range(n + 1):
            px = x0 + 0.25 + pitch * i
            K.box("post%d" % i, px, WH_Y0 - WH_DOCK - 0.02, (WH_DOCK_H + cz) / 2.0, 0.05, 0.05,
                  cz - WH_DOCK_H, K.mat("darkmetal"))

    # Goods on the apron: crates stacked by the dock, containers at the higher level.
    ax = x0 + 0.55
    ay = WH_Y0 - WH_DOCK - 0.42
    mats = [K.mat("wall_grey"), K.mat("box_blue"), K.mat("gear")]
    for i in range(p["crates"]):
        for j in range(p["crates"] - i):
            K.box("crate%d_%d" % (i, j), ax + j * 0.34 + i * 0.17, ay, 0.045 + 0.15 + i * 0.30,
                  0.30, 0.30, 0.28, mats[(i + j) % len(mats)])
    spots = [(WH_X1 - 0.45, 0.0), (WH_X1 - 1.56, 0.0), (WH_X1 - 0.45, 0.43)]
    for c in range(p["containers"]):
        K.box("cont%d" % c, spots[c][0], ay, 0.045 + 0.20 + spots[c][1], 1.05, 0.44, 0.40,
              mats[(c + 1) % len(mats)])

    print("\n".join(K.validate(ground=-0.13)))
    return {"building": "warehouse", "level": level, "objects": len(K.col.objects)}
