"""The capsule's base: an earth plate of real pointy-top hex columns, land and sea.

Run AFTER sprite_kit.py (it uses the kit's PALETTE, Kit and materials):
    exec(open(".../sprite_kit.py").read())
    exec(open(".../earth_plate.py").read())
    plate, info = build_earth_plate(K)

Each cell is a hex of circumradius R. Its depth is R: half the hex's vertex-to-vertex
height (2R). All cells share ONE mesh with no seams on top, and only the OUTER walls
exist, banded into strata by material slot rather than proud geometry.

One shape runs through the whole plate: the map's land-to-sea edge (survey_overlay.gd,
_coastline_curve), ported below. The coast between land and sea cells follows it, as do
the sand and shelf-water strips beside the coast and every boundary between strata on
the walls. The ore and coal deposits swell and thin by it too, fading toward the back
until they pinch out in places. Sea cells show a water column over seabed sand on their
walls, shallow at the shore and deeper offshore.
"""
import math
from collections import Counter

import bmesh
import bpy
from mathutils import Vector
from mathutils.geometry import delaunay_2d_cdt

SQRT3 = math.sqrt(3.0)

# The hex grid's axes before PLATE_YAW turns it: EAST reads as screen-right and NORTH as
# screen-up under the sprite camera's 45-degree yaw, so a pointy-top hex points its tip
# at the top of the frame. The camera stays on the sprite rig's yaw so buildings keep
# the game's look; the GRID turns under it instead, by the angle that best fits the AI
# concept's slab (12 degrees; a flat-top turn of 30 fits no better).
EAST = (1.0 / math.sqrt(2.0), 1.0 / math.sqrt(2.0))
NORTH = (-1.0 / math.sqrt(2.0), 1.0 / math.sqrt(2.0))
PLATE_YAW = 12.0
# Horizontal direction from the scene toward the sprite camera.
TOWARD_CAMERA = (1.0 / math.sqrt(2.0), -1.0 / math.sqrt(2.0))

# Axial (q, r) cells, r growing SOUTH (toward the camera). This is the AI concept's slab,
# transferred: its top outline projected back onto the ground under the 30-degree camera,
# a hex grid sized so the walls match its average wall height, and every cell kept that
# lies mostly inside (the union covers the outline at 85% overlap). Cells its water
# covers are sea: a four-cell bay at the back right, open to the east and to the back
# corner where the concept's islets sit.
LAND = [(0, -1), (-1, -1),
        (-2, 0), (-1, 0),
        (-2, 1), (-1, 1),
        (-2, 2), (-1, 2),
        (-2, 3)]
SEA = [(1, -1), (0, 0), (1, 0), (0, 1)]

# In-game colours, all from the shipped midcentury map style (map_midcentury_style.gd):
# BAND_COLORS[2] lowland ground, BAND_COLORS[1] coastal sand, SEA_COLORS[4] the shelf
# nearest the shore and SEA_COLORS[3] the next depth out.
TOP_HEX = {"map_ground": "9aa465", "map_sand": "ddd0a6", "map_shelf": "6b8fb5", "map_sea": "4f6f99"}
# Linear albedos that render those hexes on a TOP face through the sprite rig's AgX view
# transform, measured by render (measure_render.py). AgX compresses and desaturates, so
# a plain sRGB->linear conversion renders too grey. Ground, shelf and sea render exactly.
# The pale sand sits at the top of AgX's range, where even 1.0 renders #cac7a8, so it
# needs a base colour above 1; it renders #dbd0ad.
PALETTE["map_ground"] = (0.2814, 0.3705, 0.0864)
PALETTE["map_sand"] = (1.7375, 1.3796, 0.2849)
PALETTE["map_shelf"] = (0.0941, 0.2151, 0.4818)
PALETTE["map_sea"] = (0.0651, 0.1163, 0.2663)
# The owner: the deep sea read too dark beside the shelf, so the sea cells take the shelf's
# colour too (top and wall), and the bay reads as one shallow sea.
PALETTE["map_sea"] = PALETTE["map_shelf"]
TOP_HEX["map_sea"] = TOP_HEX["map_shelf"]
GROUND_HEX = TOP_HEX["map_ground"]

# Strata, top down: (share of the depth, kit palette name, kind). Tones come from the
# kit's MEASURED earth ramp (evenly spaced luma on vertical faces) plus its coal and ore;
# light and dark alternate so neighbours never fuse. The last band takes up whatever
# depth the varied bands above it leave, so the plate's floor stays flat.
STRATA = [
    (0.035, "map_ground", "lip"),       # turf lip: the ground colour carried over the edge
    (0.090, "earth3", "soil"),          # topsoil
    (0.170, "earth", "soil"),           # subsoil
    (0.090, "earth2", "soil"),          # clay
    (0.100, "coal", "deposit"),         # coal seam
    (0.030, "coal2", "deposit"),        # coaly shale under it
    (0.140, "earth2", "soil"),          # sandstone
    (0.080, "ore", "deposit"),          # iron-ore band
    (0.120, "earth3", "soil"),          # rock
    (0.100, "earth4", "soil"),          # bedrock
    (0.045, "earth_deep", "base"),      # floor: absorbs the variation above
]
# Every boundary between two bands is its own coastline: base depth + a profile. Soil
# boundaries move by SOIL_WOBBLE (share of the depth) times the profile, whose smooth part
# spans +/-1 and whose spikes reach +/-4/3. A deposit's floor instead follows its own roof
# by a thickness that swings with the profile (1 + DEPOSIT_SWING * profile) and pinches out
# where that drops below zero. Boundaries never cross: a squeezed band simply vanishes.
# Lenses: a local deposit in the topsoil, swelling from nothing where a wall passes under
# something that came out of the ground, and pinching out again. (map centre in units of R,
# half-length along the wall in R, thickness at its middle as a share of the depth,
# material). Copper under the copper heap by the mine (owner).
LENSES = [((-4.117, -0.621), 0.27, 0.070, "copper_ore")]
SOIL_WOBBLE = 0.035
LIP_SWING = 0.35
DEPOSIT_SWING = 1.25
# Deposits also lose up to this much of their thickness toward the back of the
# camera-facing walls (0 at the front, full at the back ends).
BACK_FADE = 0.95
BACK_FADE_FROM = 0.35      # share of the front-to-back run where the fade starts
MIN_FLOOR = 0.03           # the floor band never thins below this share of the depth
WALL_SAMPLES = 32          # per hex edge: resolves the profile's third octave and spike

# The coast, in the game's proportions: survey_overlay.gd moves a coast up to COAST_AMP
# (30 px) and a shared corner up to CORNER_MAX (40 px) on a ~270 px hex edge.
COAST_AMP = 30.0 / 270.0          # x R
CORNER_JITTER = 40.0 / 270.0      # x R
BEACH_WIDTH = 0.10                # x R: sand between the ground and the water
SHELF_WIDTH = 0.35                # x R: shelf water before the sea deepens
STRIP_SWING = 0.5                 # both strip widths swing with their own profile
STRIP_TAPER = 0.6                 # x R: strips close to nothing where the coast meets the rim
WATER_MAX = 0.26                  # deepest water on the sea walls, share of the depth
SHORE_RUN = 1.2                   # x R: distance from the coast over which the sea deepens
SEABED_WOBBLE = 0.30              # the seabed rises and falls by the profile, too
SEDIMENT = 0.025                  # seabed sand under the water, share of the depth

# The river, 3 times as wide as the game draws it (river_visuals.gd: 15 px, 25 px at the
# mouth, on a hex 480 px flat-to-flat), so a bridge over it can carry the composition. It
# runs west from the head of the bay across the middle of the plate, as the AI concept's
# river runs under its bridge, then snakes north and leaves through the back wall between
# the mine and power-station cells.
RIVER_SCALE = 3.0
RIVER_WIDTH_PX, RIVER_MOUTH_PX, GAME_HEX_PX = 15.0, 25.0, 480.0
RIVER_MOUTH_RUN = 0.8              # x R: the river narrows from mouth width over this run
RIVER_BANK_WOBBLE = 0.15           # banks move by this share of the half-width, by the profile
# Centre line control points in the map frame, in units of R: the first in the bay, the
# last beyond the back rim.
RIVER = [(-0.70, -0.02), (-1.05, -0.06), (-1.50, -0.28), (-2.00, -0.18), (-2.35, 0.22),
         (-2.25, 0.75), (-1.90, 1.10), (-1.88, 1.55), (-1.76, 2.10), (-1.80, 2.60)]

# survey_overlay.gd constants, as ratios of COAST_AMP (30 px).
_AMP_MIN = 20.0 / 30.0
_SPIKE_AMP = 40.0 / 30.0
_SPIKE_W = 0.09

# Salts keep every family of profiles independent of the others on the same edge.
_SALT_BANDS = 300            # + 1000 * boundary index
_SALT_COAST = 20300
_SALT_BEACH = 21300
_SALT_SHELF = 22300
_SALT_SEABED = 23300
_SALT_CORNER = 24330
_SALT_RIVER = 25300

# Rivers and lakes in the midcentury map style (MapMidcenturyStyle.WATER).
TOP_HEX["map_river"] = "5b86b5"
PALETTE["map_river"] = (0.0668, 0.1771, 0.4700)


def _hashf(a, b, salt):
    """survey_overlay.gd _hashf, ported. Small inputs, so 64-bit GDScript ints never wrap."""
    h = (a + 100) * 73856093
    h ^= (b + 100) * 19349663
    h ^= (salt + 100) * 83492791
    return (abs(h) % 1000003) / 1000003.0


def _edge_rand(p, q, salt):
    # Midpoint in hundredths of a unit: the game rounds pixel coordinates, and a hex
    # here is only ~5 units across.
    return _hashf(int(round((p[0] + q[0]) * 50.0)), int(round((p[1] + q[1]) * 50.0)), salt)


def coast_profile(a, b, t, salt0=_SALT_BANDS):
    """The land-to-sea edge wobble from survey_overlay.gd _coastline_curve, as a unitless
    profile along edge a->b at t in [0, 1]: zero at both corners (so neighbouring edges
    meet), the smooth part within +/-1, and on half the edges one sharp spike. Evaluated
    in the same canonical corner order as the game, so an edge has one shape whichever
    way it is walked. `salt0` separates independent profiles on the same edge."""
    flip = a[0] > b[0] or (a[0] == b[0] and a[1] > b[1])
    p, q = (b, a) if flip else (a, b)
    tc = 1.0 - t if flip else t

    def r(s):
        return _edge_rand(p, q, salt0 + s)

    amp = _AMP_MIN + (1.0 - _AMP_MIN) * r(0)
    f1 = 0.8 + 0.8 * r(10)
    f2 = 2.4 + 1.2 * r(11)
    f3 = 4.4 + 2.0 * r(12)
    p1, p2, p3 = r(13) * math.tau, r(14) * math.tau, r(15) * math.tau
    wobble = (0.55 * math.sin(tc * math.pi * f1 + p1)
              + 0.30 * math.sin(tc * math.pi * f2 + p2)
              + 0.15 * math.sin(tc * math.pi * f3 + p3))
    d = math.sin(math.pi * tc) * amp * wobble
    if r(20) > 0.5:
        spike_t = 0.2 + 0.6 * r(21)
        spike_d = (1.0 if r(22) > 0.5 else -1.0) * _SPIKE_AMP
        d += spike_d * max(0.0, 1.0 - abs(tc - spike_t) / _SPIKE_W)
    return d


def _smoothstep(e0, e1, x):
    t = min(1.0, max(0.0, (x - e0) / (e1 - e0)))
    return t * t * (3.0 - 2.0 * t)


def axial_to_map(q, r, R):
    """Pointy-top axial -> map-frame centre (x east, y north)."""
    return R * SQRT3 * (q + r / 2.0), -1.5 * R * r


def hex_corner(cx, cy, R, k):
    """Corner k of a pointy-top hex; k=0 is the north tip, then counter-clockwise."""
    a = math.radians(90.0 + 60.0 * k)
    return cx + R * math.cos(a), cy + R * math.sin(a)


def map_to_world(x, y, yaw=PLATE_YAW):
    c, s = math.cos(math.radians(yaw)), math.sin(math.radians(yaw))
    ex, ey = EAST[0] * c - EAST[1] * s, EAST[0] * s + EAST[1] * c
    nx, ny = NORTH[0] * c - NORTH[1] * s, NORTH[0] * s + NORTH[1] * c
    return (x * ex + y * nx, x * ey + y * ny)


def _away(p):
    """How far back p sits along the ground, seen from the camera: larger is further."""
    return -(p[0] * TOWARD_CAMERA[0] + p[1] * TOWARD_CAMERA[1])


def _unit(v):
    n = math.hypot(v[0], v[1])
    return (v[0] / n, v[1] / n)


def _right_normal(a, b):
    """Unit normal on the right of a->b: out of the region that keeps a CCW walk on its left."""
    return _unit((b[1] - a[1], -(b[0] - a[0])))


def _seg_dist(p, a, b):
    ax, ay = b[0] - a[0], b[1] - a[1]
    t = max(0.0, min(1.0, ((p[0] - a[0]) * ax + (p[1] - a[1]) * ay) / max(ax * ax + ay * ay, 1e-12)))
    return math.hypot(p[0] - a[0] - ax * t, p[1] - a[1] - ay * t)


def _seg_hit(a, b, c, d):
    """Intersection point of segments a-b and c-d, or None."""
    r = (b[0] - a[0], b[1] - a[1]); s = (d[0] - c[0], d[1] - c[1])
    den = r[0] * s[1] - r[1] * s[0]
    if abs(den) < 1e-12:
        return None
    t = ((c[0] - a[0]) * s[1] - (c[1] - a[1]) * s[0]) / den
    u = ((c[0] - a[0]) * r[1] - (c[1] - a[1]) * r[0]) / den
    if 0.0 <= t <= 1.0 and 0.0 <= u <= 1.0:
        return (a[0] + r[0] * t, a[1] + r[1] * t)
    return None


def _catmull(pts, per_seg=24):
    """Catmull-Rom through pts (end points repeated), sampled evenly per segment."""
    P = [pts[0]] + list(pts) + [pts[-1]]
    out = []
    for i in range(1, len(P) - 2):
        p0, p1, p2, p3 = P[i - 1], P[i], P[i + 1], P[i + 2]
        for j in range(per_seg):
            t = j / per_seg
            out.append(tuple(0.5 * (2 * p1[k] + (p2[k] - p0[k]) * t
                                    + (2 * p0[k] - 5 * p1[k] + 4 * p2[k] - p3[k]) * t * t
                                    + (3 * p1[k] - p0[k] - 3 * p2[k] + p3[k]) * t * t * t) for k in range(2)))
    out.append(tuple(pts[-1]))
    return out


def _arc(pts):
    s = [0.0]
    for a, b in zip(pts, pts[1:]):
        s.append(s[-1] + math.dist(a, b))
    return s


def _at(pts, s, target):
    """Point at arc length `target` along pts (s = its arc lengths), clamped."""
    target = min(max(target, 0.0), s[-1])
    for i in range(len(s) - 1):
        if s[i + 1] >= target:
            t = (target - s[i]) / max(s[i + 1] - s[i], 1e-12)
            return (pts[i][0] + (pts[i + 1][0] - pts[i][0]) * t, pts[i][1] + (pts[i + 1][1] - pts[i][1]) * t)
    return pts[-1]


def river_banks(ctrl, R):
    """World-XY centre line of the river from its bay end, with both banks and the width
    at each sample. The width flares to the mouth width over the first stretch, and each
    bank wanders by the coast profile, taken over successive R-long stretches of the line."""
    c = _catmull(ctrl)
    s = _arc(c)
    k = SQRT3 * R / GAME_HEX_PX * RIVER_SCALE
    w_in, w_mouth = RIVER_WIDTH_PX * k, RIVER_MOUTH_PX * k
    left, right, widths = [], [], []
    for i, p in enumerate(c):
        a, b = c[max(i - 1, 0)], c[min(i + 1, len(c) - 1)]
        tx, ty = _unit((b[0] - a[0], b[1] - a[1]))
        nx, ny = -ty, tx
        w = w_in + (w_mouth - w_in) * (1.0 - _smoothstep(0.0, RIVER_MOUTH_RUN * R, s[i]))
        n = int(s[i] // R)
        pa, pb = _at(c, s, n * R), _at(c, s, (n + 1) * R)
        t = (s[i] - n * R) / R
        wl = 1.0 + RIVER_BANK_WOBBLE * coast_profile(pa, pb, t, _SALT_RIVER)
        wr = 1.0 + RIVER_BANK_WOBBLE * coast_profile(pa, pb, t, _SALT_RIVER + 500)
        left.append((p[0] + nx * w / 2 * wl, p[1] + ny * w / 2 * wl))
        right.append((p[0] - nx * w / 2 * wr, p[1] - ny * w / 2 * wr))
        widths.append(w)
    return c, s, left, right, widths


def _chain(edges):
    """Order directed edges head-to-tail. Returns lists of corner keys, one per chain."""
    nxt = dict(edges)
    heads = set(nxt) - set(nxt.values())
    chains, seen = [], set()
    for start in list(heads) + list(nxt):
        if start in seen or start not in nxt:
            continue
        run = [start]
        seen.add(start)
        while run[-1] in nxt and nxt[run[-1]] not in seen:
            run.append(nxt[run[-1]])
            seen.add(run[-1])
        if run[-1] in nxt and nxt[run[-1]] == start:
            pass                                    # a closed loop: first key is not repeated
        chains.append(run)
    return chains


def build_earth_plate(K, land=LAND, sea=SEA, R=5.0, strata=STRATA, name="earth_plate", z_top=0.0,
                      yaw=PLATE_YAW, river=RIVER, pits=()):
    """One mesh for the whole plate. Returns (object, info) where info carries the
    geometry a renderer needs to frame and probe it.

    `pits` are holes cut in the top, each walled straight down to its first bench: dicts of
    `rim` (world xy outline), `depth` (wall height below the top) and `mat` (wall material).
    The benches below are the building's own; the plate supplies the ground they are cut
    into."""
    depth = R
    total = sum(f for f, _, _ in strata)
    if abs(total - 1.0) > 1e-6:
        raise ValueError("strata fractions must sum to 1, got %.4f" % total)
    cells = list(land) + list(sea)
    sea_set = set(sea)

    # Wall bands: water and seabed sand above the land strata. On land both are empty. The
    # topsoil is split round the lens band, which is empty wherever no lens swells it.
    bands = [("map_sea", "water"), ("map_sand", "sediment")] + [(m, k) for _, m, k in strata]
    top_soil = bands[3]
    lens_mat = LENSES[0][3] if LENSES else top_soil[0]
    bands[4:4] = [(lens_mat, "lens"), top_soil]
    lenses = [(map_to_world(cx * R, cy * R, yaw), half * R, th) for (cx, cy), half, th, _ in LENSES]

    def lens_thickness(p):
        th = 0.0
        for (lx, ly), half, peak in lenses:
            u = math.hypot(p[0] - lx, p[1] - ly) / half
            if u < 1.0:
                th = max(th, peak * (1.0 - u * u) ** 1.5)
        return th
    n_bands = len(bands)
    slots = []
    for mat, _ in bands:
        if mat not in slots:
            slots.append(mat)
    for extra in ("map_ground", "map_sand", "map_shelf", "map_sea", "map_river", "earth_deep"):
        if extra not in slots:
            slots.append(extra)

    def key(x, y):
        return (round(x, 5), round(y, 5))

    # ---- cells, corners, rim and coast edges ----
    corners, cell_keys, owners = {}, [], {}
    for q, r in cells:
        cx, cy = axial_to_map(q, r, R)
        ks = []
        for k in range(6):
            wx, wy = map_to_world(*hex_corner(cx, cy, R, k), yaw)
            kk = key(wx, wy)
            corners.setdefault(kk, (wx, wy))
            ks.append(kk)
        cell_keys.append(ks)
        for k in range(6):
            owners.setdefault(frozenset((ks[k], ks[(k + 1) % 6])), []).append((q, r))
    rim, coast = {}, []        # rim: directed edge -> owning cell; coast: land-owned directed edges
    for (q, r), ks in zip(cells, cell_keys):
        for k in range(6):
            a, b = ks[k], ks[(k + 1) % 6]
            own = owners[frozenset((a, b))]
            if len(own) == 1:
                rim[(a, b)] = (q, r)
            elif (q, r) not in sea_set and any(o in sea_set for o in own):
                coast.append((a, b))
    rim_loop = _chain(list(rim))[0]
    coast_chains = _chain(coast)
    sea_corner = {kk for (a, b), c in rim.items() if c in sea_set for kk in (a, b)}

    # ---- the coast: jittered corners, then the coast line and its two strips ----
    def edge_normal(a, b):
        return _right_normal(corners[a], corners[b])

    lines = []                  # per chain: dict of point lists and sample keys
    for chain in coast_chains:
        base = {}
        for i, kk in enumerate(chain):
            x, y = corners[kk]
            if 0 < i < len(chain) - 1:          # interior corners move; rim ends stay put
                n = _unit(tuple(u + v for u, v in zip(edge_normal(chain[i - 1], kk),
                                                     edge_normal(kk, chain[i + 1]))))
                j = CORNER_JITTER * R * (2.0 * _hashf(int(round(x * 100)), int(round(y * 100)), _SALT_CORNER) - 1.0)
                x, y = x + n[0] * j, y + n[1] * j
            base[kk] = (x, y)
        miter = {}
        for i, kk in enumerate(chain):
            ns = []
            if i > 0:
                ns.append(_right_normal(base[chain[i - 1]], base[kk]))
            if i < len(chain) - 1:
                ns.append(_right_normal(base[kk], base[chain[i + 1]]))
            miter[kk] = _unit((sum(n[0] for n in ns), sum(n[1] for n in ns)))
        lengths = [math.dist(base[a], base[b]) for a, b in zip(chain, chain[1:])]
        run_total = sum(lengths)
        coast_pts, beach_pts, shelf_pts, keys = [], [], [], []
        s0 = 0.0
        for e, (a, b) in enumerate(zip(chain, chain[1:])):
            A, B = base[a], base[b]
            ne = _right_normal(A, B)
            for j in range(WALL_SAMPLES + 1):
                if j == 0 and e > 0:
                    continue                                    # shared with the previous edge
                t = j / WALL_SAMPLES
                wa, wb = 1.0 - _smoothstep(0.0, 0.3, t), _smoothstep(0.7, 1.0, t)
                n = _unit((ne[0] + wa * (miter[a][0] - ne[0]) + wb * (miter[b][0] - ne[0]),
                           ne[1] + wa * (miter[a][1] - ne[1]) + wb * (miter[b][1] - ne[1])))
                bx, by = A[0] + (B[0] - A[0]) * t, A[1] + (B[1] - A[1]) * t
                s = s0 + lengths[e] * t
                taper = _smoothstep(0.0, STRIP_TAPER * R, s) * _smoothstep(0.0, STRIP_TAPER * R, run_total - s)
                pa, pb = corners[a], corners[b]
                d = COAST_AMP * R * coast_profile(pa, pb, t, _SALT_COAST)
                w = BEACH_WIDTH * R * (1.0 + STRIP_SWING * coast_profile(pa, pb, t, _SALT_BEACH)) * taper
                sh = SHELF_WIDTH * R * (1.0 + STRIP_SWING * coast_profile(pa, pb, t, _SALT_SHELF)) * taper
                coast_pts.append((bx + n[0] * d, by + n[1] * d))
                beach_pts.append((bx + n[0] * (d - w), by + n[1] * (d - w)))
                shelf_pts.append((bx + n[0] * (d + sh), by + n[1] * (d + sh)))
                keys.append(a if j == 0 else (b if j == WALL_SAMPLES else ("coast", a, b, j)))
            s0 += lengths[e]
        lines.append({"chain": chain, "coast": coast_pts, "beach": beach_pts,
                      "shelf": shelf_pts, "keys": keys})
    coast_segments = [(ln["coast"][i], ln["coast"][i + 1]) for ln in lines for i in range(len(ln["coast"]) - 1)]

    # ---- walls ----
    seen = []
    for (a, b) in rim:
        (ax, ay), (bx, by) = corners[a], corners[b]
        if (by - ay) * 1.0 + -(bx - ax) * -1.0 > 1e-6:     # outward normal faces the camera (1, -1)
            seen += [_away(corners[a]), _away(corners[b])]
    n_front, n_back = min(seen), max(seen)
    base_share = [0.0]
    for frac, _, _ in strata:
        base_share.append(base_share[-1] + frac)

    def column_levels(p, profiles, seabed_prof, is_sea):
        """Band levels (top to floor) at rim point p. profiles[i - 1] shapes strata
        boundary i; seabed_prof shapes the seabed on sea walls."""
        fade = BACK_FADE * _smoothstep(BACK_FADE_FROM, 1.0, (_away(p) - n_front) / max(n_back - n_front, 1e-6))
        water = 0.0
        if is_sea:
            dist = min(_seg_dist(p, u, v) for u, v in coast_segments) if coast_segments else R
            water = WATER_MAX * _smoothstep(0.0, SHORE_RUN * R, dist) * (1.0 + SEABED_WOBBLE * seabed_prof)
        sediment = SEDIMENT * _smoothstep(0.0, 0.05, water)
        d = [0.0, water, water + sediment]
        seabed = d[-1]
        for i in range(1, len(strata)):
            frac, _, kind = strata[i - 1]
            prof = profiles[i - 1]
            if kind == "deposit":
                di = d[-1] + frac * max(0.0, 1.0 + DEPOSIT_SWING * prof - fade)
            elif kind == "lip":
                di = seabed if is_sea else frac * (1.0 + LIP_SWING * prof)
            else:
                di = base_share[i] + SOIL_WOBBLE * prof
            d.append(min(max(di, d[-1]), 1.0 - MIN_FLOOR))
        d.append(1.0)
        # the lens, in the middle of the topsoil (d[3] to d[4]), never more than most of it
        th = min(lens_thickness(p), 0.8 * (d[4] - d[3]))
        mid = (d[3] + d[4]) / 2.0
        d[4:4] = [mid - th / 2.0, mid + th / 2.0]
        return [z_top - depth * x for x in d]

    bm = bmesh.new()
    columns, column_z = {}, {}

    def column(kk, p, profiles, seabed_prof, is_sea):
        if kk not in columns:
            levels = column_levels(p, profiles, seabed_prof, is_sea)
            vs = []
            for i, z in enumerate(levels):
                if vs and abs(z - levels[i - 1]) < 1e-5:
                    vs.append(vs[-1])            # a pinched-out band: share the vertex
                else:
                    vs.append(bm.verts.new((p[0], p[1], z)))
            columns[kk] = vs
            column_z[kk] = levels
        return columns[kk]

    zero = [0.0] * (len(strata) - 1)
    rim_samples = {}
    for (a, b), cell in rim.items():
        pa, pb = corners[a], corners[b]
        is_sea = cell in sea_set
        cols = []
        for j in range(WALL_SAMPLES + 1):
            t = j / WALL_SAMPLES
            if j in (0, WALL_SAMPLES):
                kk = a if j == 0 else b
                cols.append((kk, column(kk, corners[kk], zero, 0.0, kk in sea_corner)))
                continue
            p = (pa[0] + (pb[0] - pa[0]) * t, pa[1] + (pb[1] - pa[1]) * t)
            profiles = [coast_profile(pa, pb, t, _SALT_BANDS + 1000 * i) for i in range(len(strata) - 1)]
            seabed_prof = coast_profile(pa, pb, t, _SALT_SEABED)
            kk = ("rim", a, b, j)
            cols.append((kk, column(kk, p, profiles, seabed_prof, is_sea)))
        rim_samples[(a, b)] = cols

    for (a, b), cols in rim_samples.items():
        for j in range(WALL_SAMPLES):
            c0, c1 = cols[j][1], cols[j + 1][1]
            for i in range(n_bands):
                ring = [c0[i], c1[i], c1[i + 1], c0[i + 1]]
                vs = [v for n, v in enumerate(ring) if v is not ring[n - 1]]
                if len(vs) >= 3 and len(set(vs)) == len(vs):
                    f = bm.faces.new(vs)
                    f.material_index = slots.index(bands[i][0])

    # ---- top: land, sand, shelf and sea, triangulated as one constrained Delaunay ----
    # Rim samples in CCW order around the whole plate, each carrying its wall vertex.
    ring_keys = []
    for a, b in zip(rim_loop, rim_loop[1:] + rim_loop[:1]):
        ring_keys += [k for k, _ in rim_samples[(a, b)][:-1]]
    pts, index, bmv = [], {}, []

    def add(kk, xy, vert=None):
        if kk not in index:
            index[kk] = len(pts)
            pts.append(Vector(xy))
            bmv.append(vert)
        return index[kk]

    top_vert = {k: v[0] for k, v in columns.items()}
    for kk in ring_keys:
        add(kk, top_vert[kk].co.xy, top_vert[kk])
    faces, face_mat = [], []
    if lines:
        ln = lines[0]
        c0, c1 = ln["chain"][0], ln["chain"][-1]
        coast_i = [add(k, xy) for k, xy in zip(ln["keys"], ln["coast"])]
        beach_i = [coast_i[0]] + [add(("beach",) + (k if isinstance(k, tuple) and k[0] == "coast" else ("corner", k)), xy)
                                  for k, xy in zip(ln["keys"][1:-1], ln["beach"][1:-1])] + [coast_i[-1]]
        shelf_i = [coast_i[0]] + [add(("shelf",) + (k if isinstance(k, tuple) and k[0] == "coast" else ("corner", k)), xy)
                                  for k, xy in zip(ln["keys"][1:-1], ln["shelf"][1:-1])] + [coast_i[-1]]
        ring_i = [index[k] for k in ring_keys]
        p0, p1 = ring_i.index(index[c0]), ring_i.index(index[c1])
        sea_arc = ring_i[p0:p1 + 1] if p0 <= p1 else ring_i[p0:] + ring_i[:p1 + 1]
        land_arc = ring_i[p1:p0 + 1] if p1 <= p0 else ring_i[p1:] + ring_i[:p0 + 1]
        faces = [land_arc + beach_i[1:-1],
                 coast_i + beach_i[-2:0:-1],
                 shelf_i + coast_i[-2:0:-1],
                 sea_arc + shelf_i[-2:0:-1]]
        face_mat = ["map_ground", "map_sand", "map_shelf", "map_sea"]
    else:
        faces = [[index[k] for k in ring_keys]]
        face_mat = ["map_sea" if all(c in sea_set for c in cells) else "map_ground"]
    # The river is one more ring laid OVER the others: the triangulator splits every
    # triangle it crosses and reports all the rings each piece sits in. Its banks start in
    # the bay and are cut where they first leave the plate, snapped to the nearest rim
    # sample so the walls keep every vertex the top uses.
    river_info = None
    if river and lines:
        ctrl = [map_to_world(x * R, y * R, yaw) for x, y in river]
        rc, rs, left, right, widths = river_banks(ctrl, R)
        ring_xy = [pts[i] for i in ring_i]

        def cut(bank):
            for i in range(len(bank) - 1):
                for j in range(len(ring_xy)):
                    u, v = ring_xy[j], ring_xy[(j + 1) % len(ring_xy)]
                    hit = _seg_hit(bank[i], bank[i + 1], u, v)
                    if hit:
                        near = j if math.dist(hit, u) <= math.dist(hit, v) else (j + 1) % len(ring_xy)
                        return bank[:i + 1], near
            return bank, None

        left_in, jl = cut(left)
        right_in, jr = cut(right)
        if jl is not None and jr is not None:
            n = len(ring_i)
            fwd = (jr - jl) % n
            rim_run = [ring_i[(jl + k) % n] for k in range(fwd + 1)] if fwd <= n - fwd else \
                      [ring_i[(jl - k) % n] for k in range((n - fwd) + 1)]
            li = [add(("river", "L", i), xy) for i, xy in enumerate(left_in)]
            ri = [add(("river", "R", i), xy) for i, xy in enumerate(right_in)]
            ring = li + rim_run + ri[::-1]
            # The triangulator takes a clockwise ring to mean everything OUTSIDE it, so
            # wind the river counter-clockwise like the other rings.
            wind = sum(pts[ring[i]].x * pts[ring[(i + 1) % len(ring)]].y
                       - pts[ring[(i + 1) % len(ring)]].x * pts[ring[i]].y for i in range(len(ring)))
            faces.append(ring if wind > 0 else ring[::-1])
            face_mat.append("map_river")
            river_info = {"centre": rc, "s": rs, "widths": widths}
    # Pits are rings too, wound the same way; triangles inside one are left out.
    pit_rings = []
    for n, pit in enumerate(pits):
        rim = [tuple(p) for p in pit["rim"]]
        wind = sum(rim[i][0] * rim[(i + 1) % len(rim)][1] - rim[(i + 1) % len(rim)][0] * rim[i][1]
                   for i in range(len(rim)))
        if wind < 0:
            rim = rim[::-1]
        ring = [add(("pit", n, i), xy) for i, xy in enumerate(rim)]
        faces.append(ring)
        face_mat.append("pit")
        pit_rings.append((ring, pit))
        if pit["mat"] not in slots:
            slots.append(pit["mat"])
    for (q, r) in cells:                                    # interior points keep triangles well shaped
        add(("centre", q, r), map_to_world(*axial_to_map(q, r, R), yaw))
    out_v, _, out_f, orig_v, _, orig_f = delaunay_2d_cdt(pts, [], faces, 1, 1e-7, True)
    made = {}

    def out_vert(i):
        if i not in made:
            src = orig_v[i][0] if orig_v[i] else None
            if src is not None and bmv[src] is not None:
                made[i] = bmv[src]
            else:
                made[i] = bm.verts.new((out_v[i].x, out_v[i].y, z_top))
                if src is not None:
                    bmv[src] = made[i]
        return made[i]

    def rings_of(p):
        """Every input ring holding p. The triangulator cannot attribute the few specks
        where a strip closes to nothing at the rim, so those are found by point test."""
        hits = set()
        for n, ring in enumerate(faces):
            inside = False
            for i in range(len(ring)):
                (x0, y0), (x1, y1) = pts[ring[i]], pts[ring[i - 1]]
                if (y0 > p[1]) != (y1 > p[1]) and p[0] < x0 + (p[1] - y0) * (x1 - x0) / (y1 - y0):
                    inside = not inside
            if inside:
                hits.add(n)
        return hits

    def material(rings):
        """The river wins over land and sand; the sea and shelf win over the river at its
        mouth; a piece in no plate ring lies outside the plate."""
        mats = {face_mat[n] for n in rings}
        if "pit" in mats:
            return None
        if "map_river" in mats and mats & {"map_ground", "map_sand"}:
            return "map_river"
        for m in ("map_shelf", "map_sea", "map_sand", "map_ground"):
            if m in mats:
                return m
        return None

    top_faces = []
    for fi, tri in enumerate(out_f):
        vs = [out_vert(i) for i in tri]
        if len(set(vs)) < 3:
            continue
        rings = set(orig_f[fi]) or rings_of(
            (sum(out_v[i].x for i in tri) / 3.0, sum(out_v[i].y for i in tri) / 3.0))
        mat = material(rings)
        if mat is None:
            continue
        f = bm.faces.new(vs)
        f.material_index = slots.index(mat)
        top_faces.append(f)

    # ---- pit walls: from the rim straight down, facing into the pit ----
    from_input = {}
    for oi, srcs in enumerate(orig_v):
        for s in srcs:
            from_input.setdefault(s, oi)
    pit_edges = []
    for ring, pit in pit_rings:
        top = [out_vert(from_input[i]) for i in ring]
        bot = [bm.verts.new((v.co.x, v.co.y, z_top - pit["depth"])) for v in top]
        for i in range(len(top)):
            j = (i + 1) % len(top)
            f = bm.faces.new((top[i], top[j], bot[j], bot[i]))
            f.material_index = slots.index(pit["mat"])
            pit_edges.append((top[i], top[j]))

    # ---- floor: a fan per cell from its centre ----
    inner_bottom = {}
    for (q, r), ks in zip(cells, cell_keys):
        ring = []
        for k in range(6):
            a, b = ks[k], ks[(k + 1) % 6]
            if a in columns:
                ring.append(columns[a][n_bands])
            else:
                if a not in inner_bottom:
                    x, y = corners[a]
                    inner_bottom[a] = bm.verts.new((x, y, z_top - depth))
                ring.append(inner_bottom[a])
            if (a, b) in rim_samples:
                ring.extend(col[n_bands] for _, col in rim_samples[(a, b)][1:-1])
        cx, cy = map_to_world(*axial_to_map(q, r, R), yaw)
        hub = bm.verts.new((cx, cy, z_top - depth))
        for u, v in zip(ring, ring[1:] + ring[:1]):
            f = bm.faces.new((hub, v, u))
            f.material_index = slots.index("earth_deep")
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))

    # ---- ink: the top rim, every edge where land meets water, every vertical rim corner ----
    # Marked outright (flat edges never pass Freestyle's crease test). Land meeting water
    # is the coast and both river banks; water meeting water (the river mouth, the shelf
    # edge) and land meeting land (the sand's inner edge) stay unlined. Corners make each
    # hex wall read as its own face; convex ones sit exactly on the 120-degree threshold.
    marked = []
    for a, b in zip(rim_loop, rim_loop[1:] + rim_loop[:1]):
        run = [col[0] for _, col in rim_samples[(a, b)]]
        marked += [bm.edges.get([u, v]) for u, v in zip(run, run[1:])]
    landish, water = {"map_ground", "map_sand"}, {"map_river", "map_shelf", "map_sea"}
    tops = set(top_faces)
    for e in bm.edges:
        fs = [f for f in e.link_faces if f in tops]
        if len(fs) == 2:
            m0, m1 = slots[fs[0].material_index], slots[fs[1].material_index]
            if (m0 in landish and m1 in water) or (m1 in landish and m0 in water):
                marked.append(e)
    for kk in corners:
        if kk in columns:
            vs = columns[kk]
            marked += [bm.edges.get([vs[i], vs[i + 1]]) for i in range(n_bands) if vs[i] is not vs[i + 1]]
    marked += [bm.edges.get([u, v]) for u, v in pit_edges]
    bm.edges.index_update()
    marked_idx = [e.index for e in marked if e is not None]

    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = K.obj(name, me)
    for s in slots:
        ob.data.materials.append(K.mat(s))
    attr = me.attributes.get("freestyle_edge") or me.attributes.new("freestyle_edge", 'BOOLEAN', 'EDGE')
    for i in marked_idx:
        attr.data[i].value = True

    # Probe points for measure_render.py: one spot per top colour, well inside its area.
    probes = {"map_ground": [], "map_sand": [], "map_shelf": [], "map_sea": [], "map_river": []}
    if river_info:
        rs = river_info["s"]
        for frac in (0.35, 0.5, 0.65):
            probes["map_river"].append(_at(river_info["centre"], rs, rs[-1] * frac))
    for (q, r) in land:
        if not any((q + dq, r + dr) in sea_set for dq, dr in ((1, 0), (-1, 0), (0, 1), (0, -1), (1, -1), (-1, 1))):
            probes["map_ground"].append(map_to_world(*axial_to_map(q, r, R), yaw))
    for ln in lines:
        for i in range(WALL_SAMPLES // 2, len(ln["coast"]) - WALL_SAMPLES // 2, WALL_SAMPLES):
            c, bch, sh = ln["coast"][i], ln["beach"][i], ln["shelf"][i]
            probes["map_sand"].append(((c[0] + bch[0]) / 2, (c[1] + bch[1]) / 2))
            probes["map_shelf"].append(((c[0] + sh[0]) / 2, (c[1] + sh[1]) / 2))
    far = max(sea, key=lambda c: min(_seg_dist(map_to_world(*axial_to_map(*c, R), yaw), u, v)
                                     for u, v in coast_segments)) if sea and coast_segments else None
    if far:
        probes["map_sea"].append(map_to_world(*axial_to_map(*far, R), yaw))

    info = {
        "R": R, "depth": depth, "z_top": z_top, "strata": strata, "bands": bands, "yaw": yaw,
        "cells": cells, "land": list(land), "sea": list(sea),
        "corners": list(corners.values()),
        "rim": {(a, b): [(k, column_z[k]) for k, _ in cols] for (a, b), cols in rim_samples.items()},
        "top_probes": probes,
        "river": river_info,
        "pits": [list(p["rim"]) for p in pits],
    }
    return ob, info


def front_wall_columns(info, cell):
    """The mid-wall sample of a cell's SW and SE walls: (label, world xy, band levels)."""
    R = info["R"]
    cx, cy = axial_to_map(cell[0], cell[1], R)
    out = []
    for label, (k0, k1) in (("SW", (2, 3)), ("SE", (3, 4))):
        a = map_to_world(*hex_corner(cx, cy, R, k0), info["yaw"])
        b = map_to_world(*hex_corner(cx, cy, R, k1), info["yaw"])
        ka, kb = (round(a[0], 5), round(a[1], 5)), (round(b[0], 5), round(b[1], 5))
        cols = info["rim"].get((ka, kb))
        if not cols:
            continue
        mid = len(cols) // 2
        t = mid / (len(cols) - 1)
        out.append((label, (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t), cols[mid][1]))
    return out
