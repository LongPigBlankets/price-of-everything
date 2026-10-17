"""Rotatable supply-chain variant of the original sprite kit's pylon.

The regular-map builder stays unchanged. Retain its proportions and palette,
but fix the reversed brace endpoints and complete the two previously unseen faces.
"""

PYLON_HEIGHT = 5.2


def build_pylon():
    setup_rig(target=(0.0, 0.0, PYLON_HEIGHT / 2.0))
    k = Kit(open_collection("BLDG_pylon"))
    k.box("pad", 0.0, 0.0, -0.04, 1.1, 1.1, 0.10, k.mat("yard_pad"))
    k.pylon("tower", 0.0, 0.0, 0.01, PYLON_HEIGHT, w_base=0.80, tiers=2)
    # The source was viewed from one fixed isometric angle. Both endpoints of
    # the descending braces used the width of the opposite end of the bay.
    for ob in list(k.col.objects):
        if ob.name.startswith("tower_x"):
            bpy.data.objects.remove(ob, do_unlink=True)
    base = 0.01
    body = PYLON_HEIGHT * 0.92
    shoulder = base + body * 0.45
    top = base + body

    def half_at(z):
        t = (z - base) / body
        return ((0.80 + (0.336 - 0.80) * t / 0.45) if t <= 0.45
                else (0.336 + (0.24 - 0.336) * (t - 0.45) / 0.55)) / 2.0

    zs = ([base + (shoulder - base) * i / 3.0 for i in range(4)]
          + [shoulder + (top - shoulder) * i / 4.0 for i in range(1, 5)])
    corners = [(-1, -1), (1, -1), (1, 1), (-1, 1)]
    k._fine_mode = True
    steel = k.mat("scaffold")
    for bay, (za, zb) in enumerate(zip(zs, zs[1:])):
        ha, hb = half_at(za), half_at(zb)
        for face, (a, b) in enumerate(zip(corners, corners[1:] + corners[:1])):
            for suffix, p, q in [
                ("a", (a[0] * ha, a[1] * ha, za), (b[0] * hb, b[1] * hb, zb)),
                ("b", (a[0] * hb, a[1] * hb, zb), (b[0] * ha, b[1] * ha, za)),
            ]:
                k.dircyl(f"tower_x{bay}_{face}{suffix}", p, q, 0.009, steel, segments=6)
    # Export the actual conductor clamps, in source coordinates, along with the
    # mesh. Runtime cables use these instead of guessing a height above terrain.
    contacts = []
    for tier in range(2):
        az = base + body * (0.93 - 0.20 * tier)
        reach = half_at(az) + 0.80 * 0.95 * (1.0 + 0.20 * tier)
        tip_z = az + PYLON_HEIGHT * 0.055 * 0.30
        bottom = tip_z - 0.02 - PYLON_HEIGHT * 0.085
        for sign in [-1, 1]:
            y = sign * reach
            k.dircyl(f"tower_ins{tier}_{sign}_core", (0, y, tip_z), (0, y, bottom),
                     0.010, steel, segments=6)
            k.dircyl(f"tower_ins{tier}_{sign}_clamp", (-0.025, y, bottom), (0.025, y, bottom),
                     0.013, steel, segments=6)
            contacts.append([0.0, y, bottom])
    k._fine_mode = False
    return {"building": "pylon", "cable_anchors": contacts}
