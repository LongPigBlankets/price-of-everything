"""Animation PIECES for the supply-chain view (2026-09-10): a box lorry and a crate, rendered
with the SAME rig as the building sprites (setup_rig: ortho 11 at 1024 px = 93.09 px per world
unit, true iso, camera from (+1,-1,+1)) so the runtime only has to apply each building's export
factor to put them at the building's scale. Level-less builders: bake with level 0.

The lorry lies along +X: cab (front) at +X, cargo doors (rear) at -X. Reversed toward a door
that faces +X it approaches from screen down-right; mirrored horizontally it becomes a lorry
along Y with its rear at +Y (the iso mirror swaps the two ground axes), which is what the L1
factory gate (a -Y face) needs.

World anchors the runtime uses (projected by `project()` in the runtime's bake step):
    rear-bottom-centre  (-LORRY_L/2, 0, 0)     rear lights  (-LORRY_L/2, +-0.24, 0.36)
"""
PALETTE["carton"] = (0.300, 0.165, 0.072)       # cardboard (assembly_plant_builder's)
PALETTE["crate"] = (0.052, 0.055, 0.062)        # black tyres / crates
ROLES["carton"] = "carton"
ROLES["crate"] = "crate"

LORRY_L, LORRY_W = 1.90, 0.62
CAB_L = 0.55
CHASSIS_Z = 0.20
BOX_H = 0.85
CRATE = 0.30


def build_lorry() -> dict:
    setup_rig()
    K = Kit(open_collection("BLDG_lorry"))
    xr, xf = -LORRY_L / 2, LORRY_L / 2
    # chassis rails + rear bumper
    K.box("chassis", 0.0, 0.0, CHASSIS_Z - 0.04, LORRY_L - 0.10, 0.44, 0.08, K.mat("wall_steel"))
    K.box("bumper", xr + 0.02, 0.0, CHASSIS_Z - 0.03, 0.05, LORRY_W, 0.07, K.mat("pipe"))
    # cargo box: long side ribs on the visible (-Y) face, doors on the rear
    bx0, bx1 = xr + 0.02, xf - CAB_L - 0.06
    bcx = (bx0 + bx1) / 2
    K.box("body", bcx, 0.0, CHASSIS_Z + BOX_H / 2, bx1 - bx0, LORRY_W, BOX_H, K.mat("box_blue"))
    for k in range(4):
        K.box("rib%d" % k, bx0 + (bx1 - bx0) * (k + 0.5) / 4, -LORRY_W / 2 - 0.006,
              CHASSIS_Z + BOX_H / 2, 0.045, 0.012, BOX_H - 0.10, K.mat("wall_steel"))
    K.box("doors", xr + 0.012, 0.0, CHASSIS_Z + BOX_H / 2, 0.016, LORRY_W - 0.04, BOX_H - 0.06,
          K.mat("wall_steel"))
    for s in (-1, 1):
        K.box("bar%d" % (s > 0), xr + 0.004, s * 0.15, CHASSIS_Z + BOX_H / 2, 0.024, 0.022,
              BOX_H - 0.12, K.mat("pipe"))
        K.box("light%d" % (s > 0), xr + 0.004, s * 0.24, 0.36, 0.02, 0.07, 0.06, K.mat("hot"))
    # cab: lower and a little narrower than the box, with a windscreen band
    ccx = xf - CAB_L / 2
    K.box("cab", ccx, 0.0, CHASSIS_Z + 0.34, CAB_L, LORRY_W - 0.04, 0.68, K.mat("wall_bright"))
    K.box("screen", xf - 0.03, 0.0, CHASSIS_Z + 0.50, 0.02, LORRY_W - 0.16, 0.22, K.mat("window_glass"))
    K.box("side_glass", ccx + 0.05, -(LORRY_W - 0.04) / 2 - 0.004, CHASSIS_Z + 0.50, 0.26, 0.01,
          0.20, K.mat("window_glass"))
    K.box("grille", xf - 0.01, 0.0, CHASSIS_Z + 0.16, 0.02, LORRY_W - 0.20, 0.12, K.mat("wall_steel"))
    # wheels: two axles under the box, one under the cab
    for wx in (xr + 0.35, xr + 0.62, xf - 0.22):
        for s in (-1, 1):
            K.cyl("wheel%d_%d" % (int(wx * 100), s > 0), wx, s * 0.24, 0.12, 0.12, 0.10,
                  K.mat("crate"), axis='Y', segments=14)
    return {"building": "lorry", "objects": len(K.col.objects)}


def build_crate() -> dict:
    setup_rig()
    K = Kit(open_collection("BLDG_crate"))
    K.box("crate", 0.0, 0.0, CRATE / 2, CRATE, CRATE, CRATE, K.mat("carton"))
    for s in (-1, 1):
        K.box("band%d" % (s > 0), 0.0, 0.0, CRATE / 2 + s * CRATE * 0.28, CRATE + 0.01, CRATE + 0.01,
              0.025, K.mat("wall_steel"))
    return {"building": "crate", "objects": len(K.col.objects)}
