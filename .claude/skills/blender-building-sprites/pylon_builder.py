"""Transmission pylon for the supply chain board: one per cabled tile. build_pylon().

One fixed scene, no levels. The kit's own lattice pylon on a small concrete pad.
"""

PYLON_HEIGHT = 5.2


def build_pylon() -> dict:
    setup_rig(target=(0.0, 0.0, PYLON_HEIGHT / 2.0))
    K = Kit(open_collection("BLDG_pylon"))
    K.box("pad", 0.0, 0.0, -0.04, 1.1, 1.1, 0.10, K.mat("yard_pad"))
    K.pylon("tower", 0.0, 0.0, 0.01, PYLON_HEIGHT, w_base=0.80, tiers=2)
    print("\n".join(K.validate(ground=-0.10)))
    return {"building": "pylon", "objects": len(K.col.objects)}
