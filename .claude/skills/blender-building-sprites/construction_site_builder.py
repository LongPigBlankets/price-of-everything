# Parametric builder for the CONSTRUCTION SITE sprite (shown while a building is being built).
# Run AFTER sprite_kit.py:
#   exec(open(".../sprite_kit.py").read())
#   exec(open(".../construction_site_builder.py").read()); build_construction_site()
#
# ONE sprite, no levels — this stands in for any building under construction, so it must not
# look like a particular industry. Everything on it is generic site plant: a tower crane, a
# container compound, excavators, scaffolding round a part-built frame, on the same cream
# apron the finished buildings use so it drops into the row without re-reading.
#
# THE CRANE IS THE SUBJECT. It runs the full height of the sprite and its jib is the only long
# horizontal, against a field of low busy machinery — that silhouette is what has to say
# "under construction" at empire-view scale, where nothing else on the sprite is legible.

import math

# Crane moved LEFT so the jib could grow 20% (3.05 -> 3.66) without widening the sprite: the
# tip lands at x 4.21 against the old 4.20, so the extra length is bought from the left-hand
# side of the yard rather than from the frame.
CRANE = (0.55, 2.30, 5.60, 3.66, 1.25)      # cx, cy, mast height, jib, counter-jib
CONTAINERS = (1.80, 1.10)                   # compound at the crane's foot
FRAME = (-1.85, 0.75, 2.35, 1.75)           # part-built structure: cx, cy, width(+X), depth(+Y)
FRAME_H = 1.05                              # slab-to-slab: one storey standing, next one open
COL_W = 0.20                                # columns are square in plan
# How far a slab runs PAST the centreline of the column at its edge. Must exceed COL_W/2 or
# the column is standing on the slab's edge with nothing under the rest of it.
DECK_LIP = 0.15
SCAFF_H = 2.15
# One excavator, one DOZER. Two excavators read as the same shape twice and their booms
# overlapped; the dozer is low and wide where the excavator is tall and jointed.
EXCAVATOR = (-0.85, -1.05, 1.0)             # cx, cy, facing
DOZER = (1.40, -1.55, -1.0)


def build_construction_site() -> dict:
    setup_rig()
    K = Kit(open_collection("BLDG_construction"))

    # ---------------- part-built frame: slab, columns, one poured floor ----------------
    fx, fy, fw, fd = FRAME
    cols_x = [fx - fw / 2 + fw * i / 2.0 for i in range(3)]
    cols_y = [fy - fd / 2, fy + fd / 2]

    # A SLAB HAS TO COVER THE COLUMNS THAT STAND ON IT, not stop at their centrelines.
    # deck1 was fw x fd and deck2 fw*0.52 x fd — those are the grid the columns are SET OUT
    # on, so every outer column was half off its own floor and the four corner ones three
    # quarters off, each standing on a slab edge with nothing under the rest. deck2 covered
    # 26% of the column at its left end. The ground slab always had the lip (fw + 0.30); the
    # decks never got it, which is why the storey read as unsupported even once its columns
    # reached the deck below.
    #
    # All three slabs are DERIVED from the columns now, so a slab cannot be sized from the
    # frame while the columns are sized from the grid and the two quietly disagree.
    decks = {}

    def deck(name, xs, zc):
        x0, x1 = min(xs) - DECK_LIP, max(xs) + DECK_LIP
        y0, y1 = cols_y[0] - DECK_LIP, cols_y[1] + DECK_LIP
        decks[name] = (x0, x1, y0, y1)
        K.box(name, (x0 + x1) * 0.5, (y0 + y1) * 0.5, zc, x1 - x0, y1 - y0, 0.10,
              K.mat("yard_pad"))

    deck("slab", cols_x, 0.05)
    for i, ccx in enumerate(cols_x):
        for j, ccy in enumerate(cols_y):
            K.box("col%d_%d" % (i, j), ccx, ccy, FRAME_H / 2 + 0.10, COL_W, COL_W, FRAME_H,
                  K.mat("wall_shell"))
    # First floor poured, second only started — the gap is what reads as UNFINISHED.
    deck("deck1", cols_x, FRAME_H + 0.14)
    deck("deck2", cols_x[:2], FRAME_H * 2.0 + 0.18)
    # SEATED, not floating. These ran z 1.337..2.198 against a deck1 top of 1.240 and a deck2
    # underside of 2.230 — so the whole second storey, columns and slab, hung in the air with
    # 0.097 of clear sky beneath it. It read as suspended concrete because it was suspended.
    # The storey is DEFINED by the two decks now — from the top of the one it stands on to the
    # underside of the one it carries — so it cannot drift again if either deck moves.
    for i, ccx in enumerate(cols_x[:2]):
        for j, ccy in enumerate(cols_y):
            K.box("col2_%d_%d" % (i, j), ccx, ccy, FRAME_H * 1.5 + 0.16, COL_W, COL_W,
                  FRAME_H - 0.06, K.mat("wall_shell"))
    # One wall panel hung, so the frame is visibly being CLAD and not just poured.
    K.box("panel", fx - fw * 0.30, fy - fd / 2 - 0.04, FRAME_H * 0.62 + 0.10, fw * 0.34, 0.06,
          FRAME_H * 0.86, K.mat("wall_bright"))

    # ---------------- scaffolding wrapping the frame ----------------
    K.scaffold("scaf", fx - fw / 2 - 0.28, fx + fw / 2 + 0.28,
               fy - fd / 2 - 0.28, fy + fd / 2 + 0.28, SCAFF_H, lifts=3)

    # ---------------- the crane, and the compound at its foot ----------------
    kx, ky, kh, kjib, kcj = CRANE
    top = K.tower_crane("crane", kx, ky, kh, jib=kjib, cjib=kcj)
    K.container_stack("cont", CONTAINERS[0], CONTAINERS[1], cols=3, rows=2)

    # ---------------- machines working the front ----------------
    K.excavator("dig", EXCAVATOR[0], EXCAVATOR[1], 0.0, s=0.78, face=EXCAVATOR[2],
                mat=K.mat("plant_yellow"))
    K.bulldozer("doze", DOZER[0], DOZER[1], 0.0, s=0.78, face=DOZER[2])

    # ---------------- spoil heaps and a pipe stack, to fill the yard ----------------
    for i, (hx, hy, hr) in enumerate(((-2.75, -0.95, 0.42), (-2.10, -1.55, 0.34))):
        K.cone("spoil%d" % i, hx, hy, hr * 0.34, hr, hr * 0.18, hr * 0.68, K.mat("ground2"),
               segments=16)
    for i in range(3):
        K.bullet("pipe%d" % i, (-0.35 + i * 0.02, -0.35, 0.14 + i * 0.24),
                 (0.85 + i * 0.02, -0.35, 0.14 + i * 0.24), 0.115)

    # ---------------- apron ----------------
    foot = [(kx, ky, 0.55), (CONTAINERS[0], CONTAINERS[1], 0.80)]
    foot += [(EXCAVATOR[0], EXCAVATOR[1], 0.62), (DOZER[0], DOZER[1], 0.72)]
    foot += [(fx + sx * (fw / 2 + 0.30), fy + sy * (fd / 2 + 0.30), 0.0)
             for sx in (-1, 1) for sy in (-1, 1)]
    foot += [(-2.75, -0.95, 0.55), (-0.35, -0.35, 0.34), (0.85, -0.35, 0.34)]
    K.apron_slab("apron", Kit.slab_outline(foot), mat=K.mat("slab_cream"),
                 kerb=K.mat("slab_kerb"))

    # ---------------- checks ----------------
    # The crane has to TOWER. Screen height is 0.4082*(y-x) + 0.8165*z, so a tall mast placed
    # far right can still land BELOW a lower object placed further back — the check compares
    # what the camera sees, not the z values.
    def sh(x, y, z):
        return 0.4082 * (y - x) + 0.8165 * z

    crane_top = sh(kx, ky, top)
    for nm, (ox, oy, oz) in (("scaffold", (fx, fy, SCAFF_H)),
                             ("frame", (fx, fy, FRAME_H * 2.0 + 0.28)),
                             ("containers", (CONTAINERS[0], CONTAINERS[1], 0.85))):
        if crane_top < sh(ox, oy, oz) + 1.20:
            print("CRANE DOES NOT TOWER OVER %s (%.2f vs %.2f)"
                  % (nm.upper(), crane_top, sh(ox, oy, oz)))
    if CONTAINERS[0] - 0.80 < kx - 0.55 and abs(CONTAINERS[1] - ky) < 0.90:
        print("CONTAINER COMPOUND FOULS THE CRANE BASE")
    for nm, (ex, ey, _f) in (("excavator", EXCAVATOR), ("dozer", DOZER)):
        if abs(ex - fx) < fw / 2 + 0.55 and abs(ey - fy) < fd / 2 + 0.55:
            print("%s IS INSIDE THE SCAFFOLD" % nm.upper())
    # The two machines must not sit on top of each other — that was the fault with two
    # excavators, and it is a SCREEN overlap, so compare columns not plan distance.
    if abs((DOZER[0] + DOZER[1]) - (EXCAVATOR[0] + EXCAVATOR[1])) < 1.55:
        print("THE TWO MACHINES SHARE A SCREEN COLUMN")
    # EVERY COLUMN MUST STAND WHOLLY ON THE SLAB BENEATH IT. This builder shipped the same
    # fault twice — once in Z (a storey hanging 0.097 above the deck) and once in PLAN (slabs
    # sized to the setting-out grid, so the corner columns were 75% off their own floor).
    # Neither is visible to a silhouette check: the sprite's alpha IoU reads 0.999 across both.
    # Only arithmetic on the extents catches this class, so it is done here, every build.
    for slab_name, carried in (("slab", [(cx, cy) for cx in cols_x for cy in cols_y]),
                               ("deck1", [(cx, cy) for cx in cols_x[:2] for cy in cols_y])):
        sx0, sx1, sy0, sy1 = decks[slab_name]
        for cx, cy in carried:
            off_x = max(0.0, sx0 - (cx - COL_W / 2)) + max(0.0, (cx + COL_W / 2) - sx1)
            off_y = max(0.0, sy0 - (cy - COL_W / 2)) + max(0.0, (cy + COL_W / 2) - sy1)
            if off_x > 1e-6 or off_y > 1e-6:
                print("COLUMN AT (%.3f, %.3f) OVERHANGS %s BY x %.3f y %.3f"
                      % (cx, cy, slab_name.upper(), off_x, off_y))
    for wmsg in K.validate(ground=-0.21):
        print(wmsg)
    return {"building": "construction_site", "objects": len(K.col.objects)}
