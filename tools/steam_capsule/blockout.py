"""Rough massing for what the game's buildings do not cover yet: the harbour, the roads, the
railway and the bridges.

Run after earth_plate.py, with the plate's info:
    items = build_blockout(Kit(open_collection("CAPSULE_buildings")),
                           Kit(open_collection("CAPSULE_infra")), info)

Grey boxes only, placed in the plate's map frame (units of R) and turned into world
coordinates with the plate's yaw. Buildings stay square to the WORLD axes, as the sprite
builders expect under the rig's 45-degree camera; roads and rails follow their paths.
The real buildings are in buildings.py. Returns (label, world top point) pairs for
annotating a render.
"""
import math

# Kit palette roles per kind of shape. A blockout only has to tell kinds apart.
MAT = {
    "coal_works": "wall_grey", "heap": "coal_seam", "brick": "wall_brick", "copper": "copper_ore",
    "cooling": "wall_shell", "stack": "stack", "hall": "gear",
    "clean": "wall_bright", "battery": "box_blue", "solar": "window_glass", "turbine": "wall_pale",
    "harbour": "box_blue", "crane": "plant_yellow", "ship": "wall_steel", "village": "slab_cream",
    "road": "slab_cream", "rail": "rail", "bridge_road": "stack", "bridge_rail": "wall_steel",
}

# Buildings: (label, kind, map x, map y, size x, size y, height) in units of R. Boxes sit
# on the ground; "cyl" and "cone" kinds give (radius, height) in the size slots.
# Only the railway's coal heaps are left here; every building is a real one (buildings.py).
BUILDINGS = [
    ("Coal heap", "mound:heap", -3.30, -0.96, 0.13, 0.07, None),    # the mine's stock, by the south leg
    ("Coal heap 2", "cone:heap", -1.46, 1.55, 0.07, 0.05, None),    # the power plant's stock
    # copper ore beside the mine, right against the tile's edge that faces the camera, some of
    # it spilling over and falling down the wall (owner): dark orange, with malachite green
    ("Copper heap", "mound:copper", -4.00, -0.42, 0.21, 0.12, None),
]

# Roads and the railway, as map-frame control points in units of R; smoothed through.
# The coal railway: a trunk from the plate's north edge (owner), past the power plant's coal
# heap, over the river's west bend on the truss, crossing on a slant to the south-west so nothing turns hard
# off the bridge's west end (owner). Just past the bridge it splits (owner) with the two legs
# leaving the trunk a few degrees either side of straight on, like a turnout: the west leg
# swings north round the mine's headframe and the south leg runs down between the mine and
# the river, round past the mine's coal heap. Both legs run off the plate's edge, into the
# country beyond, each leaving nearly square through its wall; the legs are laid as arcs of
# 0.3 R or more and straights. Every line starts on a control point of another, so the legs
# meet the trunk exactly. The roads join the harbour to the works on either side, down to the
# EV plant at the front, and over the river's lower stretch into the town inside the bend. A
# road may end at a building (that is its access); check_layout.py only minds one running past.
RAIL_LINES = [
    # trunk: from the tile's north edge, past the power plant's coal heap, over the truss to
    # the junction
    ("Coal railway", [(-1.575, 2.09), (-1.625, 1.87), (-1.64, 1.66), (-1.61, 1.38), (-1.56, 1.12),
                      (-1.66, 0.86), (-1.86, 0.60), (-2.08, 0.40), (-2.32, 0.25), (-2.56, 0.13),
                      (-2.65, 0.085)]),
    # west leg: north round the headframe, off the plate's north-west edge
    ("Coal railway west", [(-2.650, 0.085), (-2.788, 0.070), (-2.917, 0.118), (-3.011, 0.220),
                           (-3.085, 0.350), (-3.159, 0.481), (-3.247, 0.598), (-3.339, 0.695),
                           (-3.431, 0.792), (-3.523, 0.889), (-3.569, 0.937)]),
    # south leg: between the mine and the river, past the coal heap, off the south-west edge
    ("Coal railway south", [(-2.650, 0.085), (-2.745, -0.018), (-2.784, -0.152), (-2.791, -0.312),
                            (-2.821, -0.444), (-2.895, -0.558), (-3.005, -0.638), (-3.139, -0.682),
                            (-3.280, -0.721), (-3.422, -0.760), (-3.558, -0.806), (-3.660, -0.887)]),
]
# One network: every road starts on a control point of another (the smoothing passes through
# control points, so they meet exactly), and the first two start at the pier's root.
#   0 spine:       the dock, south past the harbour and the solar field to the EV plant
#   1 west road:   off the spine, past the harbour and the factory, over the south leg
#                  (a level crossing) to the mine's yard
#   2 town road:   the dock, north over the river's lower stretch (a road bridge) to the town
#   3 town street: west along the river's north bank, under the railway
#   4 power road:  north up the bay shore to the power plant
#   5 north road:  off the power road, over the railway and the river's north stretch (a second
#                  road bridge, side-on) to the electric arc furnace
#   6 front road:  off the spine to the high tech manufactory
#   7 lot road:    off the spine into the EV plant's car lot
#   8 chem road:   off the west road, north to the chemical plant's door
ROADS = [
    [(-0.62, -0.81), (-0.68, -1.40), (-0.74, -2.00), (-0.78, -2.70), (-0.84, -3.45), (-0.88, -3.80)],
    [(-0.68, -1.40), (-1.10, -1.58), (-1.38, -1.595), (-1.60, -1.60), (-2.10, -1.52), (-2.40, -1.30), (-2.48, -0.95),
     (-2.66, -0.70), (-2.84, -0.58), (-3.05, -0.465)],
    [(-0.62, -0.81), (-0.86, -0.60), (-1.02, -0.25), (-1.10, 0.05), (-1.14, 0.20)],
    [(-1.14, 0.20), (-1.45, 0.16), (-1.80, 0.18), (-2.02, 0.25)],
    [(-1.14, 0.20), (-1.02, 0.50), (-0.95, 0.85), (-0.98, 1.20)],
    [(-0.95, 0.85), (-1.30, 0.98), (-1.62, 1.14), (-1.80, 1.28), (-2.10, 1.36), (-2.34, 1.39)],
    [(-0.78, -2.70), (-1.10, -2.62), (-1.38, -2.58)],
    [(-0.84, -3.45), (-0.97, -3.495), (-1.08, -3.535)],
    [(-1.38, -1.595), (-1.42, -1.40), (-1.49, -1.19)],
]
# The chemical plant's pipelines (owner): bundles that leave the plant, run a short way on low
# supports and turn down into the ground. (from, to) in map units of R, then how many pipes
# side by side.
PIPELINES = [
    ((-1.40, -0.95), (-1.14, -0.91), 3),        # east, toward the town road and the harbour
    ((-2.22, -0.66), (-2.37, -0.81), 2),        # west, toward the mine's yard
]                                               # (each starts in the vessel nearest `from`)
PIPE_R, PIPE_H, PIPE_GAP = 0.045, 0.37, 0.13    # world: radius, height of the run, spacing
ROAD_WIDTH, RAIL_WIDTH, BED = 0.09, 0.07, 0.02
ENDS = []                                # world xy of every road and rail end, for the checker
ROAD_RUNS = []                           # world xy runs of road on land (bridges left out), and
ROAD_TOP = [0.0]                         # the roads' top, for the lights on them (lighting.py)
RAIL_PATHS = {}                          # each line's smoothed world path, and the rails' top,
RAIL_TOP = [0.0]                         # for the train
BRIDGE_MARGIN = 0.10                     # x R: deck carries on past each bank
# The rail bridge: a Pratt through-truss in red oxide, the railway's one warm accent and the
# composition's centrepiece. World units, at the scale of the halved buildings (a storey is
# 0.55), so the truss stands a little over one storey above the deck.
PALETTE["bridge_red"] = (0.300, 0.085, 0.060)
# Track: a stone ballast bed carrying the outline, timber sleepers across it and two steel
# rails on top. Sleepers and rails are painted (no ink): at a few pixels each, an outline
# would be all there is of them.
PALETTE["ballast"] = (0.300, 0.280, 0.250)
PALETTE["sleeper"] = (0.100, 0.075, 0.060)
SLEEPER_PITCH, SLEEPER_W, SLEEPER_T = 0.12, 0.045, 0.018
RAIL_GAUGE, RAIL_W, RAIL_H = 0.15, 0.022, 0.020
RAIL_LIFT = 0.008                        # the bed rides a hair above the roads
SINK = 0.03                              # road and bed walls start below the plate top
TRUSS_H = 0.62
TRUSS_PANEL = 0.34                       # target panel length along the span
DECK_Z = 0.16                            # deck top above the plate: just over the rail bed


def _noink_mark(ob):
    me = ob.data
    attr = me.attributes.get("freestyle_face") or me.attributes.new("freestyle_face", 'BOOLEAN', 'FACE')
    for d in attr.data:
        d.value = True


def _ribbon_strip(K, name, run, width, z_lo, z_hi, mat, offset=0.0, noink=False):
    """A flat strip along a run of points, `offset` to the left of it: one closed mesh."""
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    lo, hi = [], []
    for i, p in enumerate(run):
        a, b = run[max(i - 1, 0)], run[min(i + 1, len(run) - 1)]
        tx, ty = _unit((b[0] - a[0], b[1] - a[1]))
        cx, cy = p[0] - ty * offset, p[1] + tx * offset
        nx, ny = -ty * width / 2, tx * width / 2
        row = []
        for sx, sy in ((cx + nx, cy + ny), (cx - nx, cy - ny)):
            row.append((bm.verts.new((sx, sy, z_lo)), bm.verts.new((sx, sy, z_hi))))
        lo.append((row[0][0], row[1][0]))
        hi.append((row[0][1], row[1][1]))
    for i in range(len(run) - 1):
        bm.faces.new((hi[i][0], hi[i][1], hi[i + 1][1], hi[i + 1][0]))
        bm.faces.new((lo[i][0], lo[i + 1][0], lo[i + 1][1], lo[i][1]))
        bm.faces.new((lo[i][0], hi[i][0], hi[i + 1][0], lo[i + 1][0]))
        bm.faces.new((lo[i][1], lo[i + 1][1], hi[i + 1][1], hi[i][1]))
    for end in (0, len(run) - 1):
        bm.faces.new((lo[end][0], lo[end][1], hi[end][1], hi[end][0]))
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.to_mesh(me)
    bm.free()
    ob = K.obj(name, me, K.mat(mat))
    if noink:
        _noink_mark(ob)
    return ob


def _sleepers(K, name, runs, length, z_lo):
    """Every sleeper along the runs as boxes in ONE mesh, painted: square to the track,
    SLEEPER_PITCH apart."""
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    for run in runs:
        ps = _arc(run)
        s = SLEEPER_PITCH / 2.0
        while s < ps[-1]:
            p = _at(run, ps, s)
            q, o = _at(run, ps, min(ps[-1], s + 0.02)), _at(run, ps, max(0.0, s - 0.02))
            tx, ty = _unit((q[0] - o[0], q[1] - o[1]))
            nx, ny = -ty, tx
            vs = []
            for dz in (0.0, SLEEPER_T):
                for a, b in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
                    vs.append(bm.verts.new((p[0] + tx * a * SLEEPER_W / 2 + nx * b * length / 2,
                                            p[1] + ty * a * SLEEPER_W / 2 + ny * b * length / 2, z_lo + dz)))
            for f in ((0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)):
                bm.faces.new([vs[i] for i in f])
            s += SLEEPER_PITCH
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.to_mesh(me)
    bm.free()
    ob = K.obj(name, me, K.mat("sleeper"))
    _noink_mark(ob)
    return ob


def union_ribbons(K, name, runs, width, z_lo, z_hi, mat):
    """All the runs as ONE solid: the union of their strips, triangulated together, walled
    only round its outer edge. Separate strips each carry their own outline, which crosses
    every junction where they overlap; the union's only outline is the network's own."""
    import mathutils
    from mathutils.geometry import delaunay_2d_cdt
    polys = []
    for run in runs:
        left, right = [], []
        for i, p in enumerate(run):
            a, b = run[max(i - 1, 0)], run[min(i + 1, len(run) - 1)]
            tx, ty = _unit((b[0] - a[0], b[1] - a[1]))
            nx, ny = -ty * width / 2, tx * width / 2
            left.append((p[0] + nx, p[1] + ny))
            right.append((p[0] - nx, p[1] - ny))
        polys.append(right + left[::-1])
    pts, faces = [], []
    for poly in polys:
        area = sum(poly[i][0] * poly[i - 1][1] - poly[i - 1][0] * poly[i][1] for i in range(len(poly)))
        if area > 0:                                        # (x_i y_{i-1} - x_{i-1} y_i): CW is > 0
            poly = poly[::-1]
        faces.append(list(range(len(pts), len(pts) + len(poly))))
        pts += [mathutils.Vector(q) for q in poly]
    out_v, _, out_f, _, _, _ = delaunay_2d_cdt(pts, [], faces, 1, 1e-6, True)

    def inside(x, y):
        for poly in polys:
            c = False
            for i in range(len(poly)):
                (x0, y0), (x1, y1) = poly[i], poly[i - 1]
                if (y0 > y) != (y1 > y) and x < x0 + (y - y0) * (x1 - x0) / (y1 - y0):
                    c = not c
            if c:
                return True
        return False

    tris = []
    for tri in out_f:
        cx = sum(out_v[i].x for i in tri) / 3.0
        cy = sum(out_v[i].y for i in tri) / 3.0
        if not inside(cx, cy):
            continue
        a, b, c = (out_v[i] for i in tri)
        if (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x) < 0:
            tri = (tri[0], tri[2], tri[1])
        tris.append(tri)
    count = {}
    for tri in tris:
        for i in range(3):
            e = (tri[i], tri[(i + 1) % 3])
            k = (min(e), max(e))
            count[k] = count.get(k, 0) + 1
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    top, bot = {}, {}

    def vt(i):
        if i not in top:
            top[i] = bm.verts.new((out_v[i].x, out_v[i].y, z_hi))
        return top[i]

    def vb(i):
        if i not in bot:
            bot[i] = bm.verts.new((out_v[i].x, out_v[i].y, z_lo))
        return bot[i]

    for tri in tris:
        try:
            bm.faces.new([vt(i) for i in tri])
        except ValueError:
            pass
    for tri in tris:
        for i in range(3):
            a, b = tri[i], tri[(i + 1) % 3]
            if count[(min(a, b), max(a, b))] == 1:          # an outer edge: wall it down
                try:
                    bm.faces.new((vt(b), vt(a), vb(a), vb(b)))
                except ValueError:
                    pass
    bm.to_mesh(me)
    bm.free()
    return K.obj(name, me, K.mat(mat))


def coal_mound(K, name, x, y, z0, r, h, mat):
    """A tipped heap: a lumpy, faceted dome, longer one way than the other, sunk so only its
    upper part shows. Facets are the look (the prop kit's trees are built the same way)."""
    import mathutils
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=2, radius=1.0)
    for i, v in enumerate(bm.verts):
        j = 1.0 + 0.10 * math.sin(i * 12.9898) * math.cos(i * 78.233)       # fixed lumps
        v.co = mathutils.Vector((v.co.x * r * 1.25 * j, v.co.y * r * 0.85 * j, v.co.z * h * 2.0 * j))
    bmesh.ops.translate(bm, vec=(x, y, z0 - h), verts=bm.verts)
    bm.to_mesh(me)
    bm.free()
    ob = K.obj(name, me, mat)
    for poly in ob.data.polygons:
        poly.use_smooth = False
    return ob


PALETTE["copper_ore"] = (0.30, 0.095, 0.032)      # dark orange: oxidised copper ore
PALETTE["copper_green"] = (0.055, 0.20, 0.115)     # malachite


def _accents(ob, mat, share, seed=9):
    """Paint a share of a heap's facets in a second material, in small clusters."""
    import random
    me = ob.data
    me.materials.append(mat)
    k = len(me.materials) - 1
    rng = random.Random(seed)
    polys = list(me.polygons)
    seeds = rng.sample(range(len(polys)), max(1, int(len(polys) * share / 3)))
    centres = [polys[i].center for i in seeds]
    reach = max(ob.dimensions) * 0.09
    for f in polys:
        if any((f.center - c).length < reach for c in centres):
            f.material_index = k


# The plate's wall below the copper heap faces the camera (south-west, map); nuggets roll
# down the heap, over the edge and fall down that wall.
SPILL_EDGE = ((-4.119, -0.620), (-4.002, -0.688))   # two points on the plate's edge there


def _spill(K, name, x, y, r, w, z0, seed=4):
    """Nuggets off the heap: a few on the ground between it and the edge, one on the lip, and
    some falling, out from the wall at falling heights. Their own collection keeps them out
    of the layout check (they hang off the plate on purpose)."""
    import random
    import mathutils
    col = bpy.data.collections.new("CAP_Copper_spill")
    bpy.context.scene.collection.children.link(col)
    Ks = Kit(col)
    rng = random.Random(seed)
    (ax, ay), (bx, by) = SPILL_EDGE
    ex, ey = w(ax, ay), w(bx, by)
    tx, ty = _unit((ey[0] - ex[0], ey[1] - ex[1]))
    nx, ny = ty, -tx                                              # out of the plate
    cx, cy = w(x, y)
    if (cx - ex[0]) * nx + (cy - ex[1]) * ny > 0:
        nx, ny = -nx, -ny
    # where the heap's side meets the edge: the edge point nearest the heap's centre
    t = (cx - ex[0]) * tx + (cy - ex[1]) * ty
    px, py = ex[0] + tx * t, ex[1] + ty * t
    spots = []
    for k in range(5):                                            # on the ground, rolling out
        along, inward = rng.uniform(-0.6, 0.6), rng.uniform(0.12, 0.45)
        spots.append((px + tx * along - nx * inward, py + ty * along - ny * inward, z0 + 0.05, rng.uniform(0.10, 0.15)))
    spots.append((px + tx * 0.2 + nx * 0.03, py + ty * 0.2 + ny * 0.03, z0 + 0.04, 0.13))   # on the lip
    for k, (drop, out) in enumerate(((0.30, 0.18), (0.70, 0.26), (1.15, 0.34), (1.70, 0.42),
                                     (2.35, 0.50), (3.10, 0.58))):                        # falling
        along = rng.uniform(-0.5, 0.5)
        spots.append((px + tx * along + nx * out, py + ty * along + ny * out, z0 - drop, rng.uniform(0.11, 0.17)))
    copper, green = Ks.mat("copper_ore"), Ks.mat("copper_green")
    for k, (sx_, sy_, sz, size) in enumerate(spots):
        me = bpy.data.meshes.new("%s_nugget%d" % (name, k))
        bm = bmesh.new()
        bmesh.ops.create_icosphere(bm, subdivisions=1, radius=size)
        for v in bm.verts:
            v.co *= rng.uniform(0.7, 1.25)
        rot = mathutils.Euler((rng.uniform(0, 3.1), rng.uniform(0, 3.1), rng.uniform(0, 3.1))).to_matrix()
        bmesh.ops.rotate(bm, cent=(0, 0, 0), matrix=rot, verts=bm.verts)
        bmesh.ops.translate(bm, vec=(sx_, sy_, sz), verts=bm.verts)
        bm.to_mesh(me)
        bm.free()
        Ks.obj("%s_nugget%d" % (name, k), me, green if k % 4 == 3 else copper)


def truss_bridge(K, name, a, b, z0, width):
    """Pratt through-truss from a to b (world xy), deck at z0 + DECK_Z. Two side trusses of
    bottom chord, inclined end posts, top chord, verticals and diagonals sloping down toward
    mid-span; struts across the top at every panel point; a concrete abutment at each end.
    Members carry the fine line: at the full line a lattice this size inks solid."""
    import mathutils
    A = mathutils.Vector((a[0], a[1], z0))
    B = mathutils.Vector((b[0], b[1], z0))
    u = B - A
    L = u.length
    u.normalize()
    v = mathutils.Vector((-u.y, u.x, 0.0))
    n = max(3, int(round(L / TRUSS_PANEL)))
    p = L / n
    zd, H, half = DECK_Z, TRUSS_H, width / 2.0

    def P(s, side, z):
        return tuple(A + u * s + v * (side * half) + mathutils.Vector((0.0, 0.0, z)))

    red, dark = K.mat("bridge_red"), K.mat("darkmetal")
    for tag, s0, s1 in (("a", -0.20, 0.06), ("b", L - 0.06, L + 0.20)):
        c0, c1 = A + u * s0, A + u * s1
        K.dirbox("%s_abut_%s" % (name, tag), (c0.x, c0.y, z0 + zd / 2), (c1.x, c1.y, z0 + zd / 2),
                 width + 0.14, zd, K.mat("pad"))
    K.dirbox(name + "_deck", P(0, 0, zd - 0.03), P(L, 0, zd - 0.03), width + 0.04, 0.06, dark)
    fm = K._fine_mode
    K._fine_mode = True
    K._fine_mode = fm
    deck_run = [P(0, 0, 0)[:2], P(L, 0, 0)[:2]]
    _sleepers(K, name + "_sleepers", [deck_run], width * 0.80, z0 + zd)
    for side in (-1, 1):
        _ribbon_strip(K, "%s_rail%d" % (name, side > 0), deck_run, RAIL_W, z0 + zd + SLEEPER_T,
               z0 + zd + SLEEPER_T + RAIL_H, "silver", offset=side * RAIL_GAUGE / 2, noink=True)
    K._fine_mode = True
    for side in (-1, 1):
        k = "%s_%s" % (name, "l" if side < 0 else "r")
        K.dirbox(k + "_bot", P(0, side, zd + 0.03), P(L, side, zd + 0.03), 0.05, 0.06, red)
        K.dirbox(k + "_top", P(p, side, zd + H), P(L - p, side, zd + H), 0.06, 0.06, red)
        K.dirbox(k + "_endA", P(0, side, zd + 0.03), P(p, side, zd + H), 0.06, 0.06, red)
        K.dirbox(k + "_endB", P(L, side, zd + 0.03), P(L - p, side, zd + H), 0.06, 0.06, red)
        for i in range(1, n):
            K.dirbox("%s_v%d" % (k, i), P(i * p, side, zd + 0.03), P(i * p, side, zd + H), 0.035, 0.035, red)
        for i in range(1, n - 1):
            s0, s1 = i * p, (i + 1) * p
            if s1 <= L / 2 + 1e-6:
                K.dirbox("%s_d%d" % (k, i), P(s0, side, zd + H), P(s1, side, zd + 0.03), 0.03, 0.03, red)
            else:
                K.dirbox("%s_d%d" % (k, i), P(s1, side, zd + H), P(s0, side, zd + 0.03), 0.03, 0.03, red)
    for i in range(1, n):                                       # top struts, portal at each end
        K.dirbox("%s_strut%d" % (name, i), P(i * p, -1, zd + H), P(i * p, 1, zd + H),
                 0.05 if i in (1, n - 1) else 0.03, 0.05 if i in (1, n - 1) else 0.03, red)
    K._fine_mode = fm


def road_bridge(K, name, a, b, z0, width):
    """A plain deck on the road's own line, with a low parapet each side."""
    import mathutils
    A = mathutils.Vector((a[0], a[1], z0))
    B = mathutils.Vector((b[0], b[1], z0))
    u = (B - A).normalized()
    v = mathutils.Vector((-u.y, u.x, 0.0))
    K.dirbox(name + "_deck", (A.x, A.y, z0 + 0.09), (B.x, B.y, z0 + 0.09), width + 0.06, 0.08, K.mat("pad"))
    for side in (-1, 1):
        o = v * (side * (width / 2 + 0.03))
        K.dirbox("%s_par%d" % (name, side > 0), (A.x + o.x, A.y + o.y, z0 + 0.16),
                 (B.x + o.x, B.y + o.y, z0 + 0.16), 0.03, 0.07, K.mat("pad"))


def build_blockout(Kb, Ki, info):
    import mathutils
    R, yaw, z0 = info["R"], info["yaw"], info["z_top"]
    items = []
    ENDS.clear()

    def w(x, y):
        return map_to_world(x * R, y * R, yaw)

    for label, kind, x, y, sx, sy, h in BUILDINGS:
        wx, wy = w(x, y)
        name = "BO_" + label.replace(" ", "_")
        if kind.startswith("cyl:"):
            Kb.cyl(name, wx, wy, z0 + sy * R / 2, sx * R, sy * R, Kb.mat(MAT[kind[4:]]), segments=24, smooth=False)
            items.append((label, (wx, wy, z0 + sy * R)))
        elif kind.startswith("mound:"):
            ob = coal_mound(Kb, name, wx, wy, z0, sx * R, sy * R, Kb.mat(MAT[kind[6:]]))
            if kind == "mound:copper":
                _accents(ob, Kb.mat("copper_green"), 0.16)
                _spill(Kb, name, x, y, sx, w, z0)
            items.append((label, (wx, wy, z0 + sy * R)))
        elif kind.startswith("cone:"):
            Kb.cone(name, wx, wy, z0 + sy * R / 2, sx * R, sx * R * 0.15, sy * R, Kb.mat(MAT[kind[5:]]),
                    segments=18, smooth=False)
            items.append((label, (wx, wy, z0 + sy * R)))
        else:
            Kb.box(name, wx, wy, z0 + h * R / 2, sx * R, sy * R, h * R, Kb.mat(MAT[kind]))
            items.append((label, (wx, wy, z0 + h * R)))

    river = info.get("river")

    def crossing(path):
        """Where a path crosses the river centre line: (arc length along path, point,
        river width there), for each crossing."""
        out = []
        ps = _arc(path)
        if not river:
            return out
        rc, rw = river["centre"], river["widths"]
        for i in range(len(path) - 1):
            for j in range(len(rc) - 1):
                hit = _seg_hit(path[i], path[i + 1], rc[j], rc[j + 1])
                if hit:
                    out.append((ps[i] + math.dist(path[i], hit), hit, rw[j]))
        return out

    def runs_between(path, ps, gaps):
        runs, run = [], []
        for i, p in enumerate(path):
            if any(g0 <= ps[i] <= g1 for g0, g1 in gaps):
                if len(run) > 1:
                    runs.append(run)
                run = []
            else:
                run.append(p)
        if len(run) > 1:
            runs.append(run)
        return runs

    def lay(label, ctrl, width, bridge_kind, K):
        """The path, its arc lengths and its river crossings, with a bridge at each."""
        path = _catmull([w(x, y) for x, y in ctrl], per_seg=16)
        ps = _arc(path)
        ENDS.extend([path[0], path[-1]])
        gaps = [(s - (rw / 2 + BRIDGE_MARGIN * R), s + (rw / 2 + BRIDGE_MARGIN * R), p, rw)
                for s, p, rw in crossing(path)]
        items.append((label, (*_at(path, ps, ps[-1] * 0.5), z0 + BED * R)))
        for n, (g0, g1, p, rw) in enumerate(gaps):
            a, b = _at(path, ps, g0), _at(path, ps, g1)
            tag = "BO_%s_bridge_%d" % (label.replace(" ", "_"), n)
            if bridge_kind == "bridge_rail":
                truss_bridge(K, tag, a, b, z0, (width + 0.04) * R)
                items.append(("Rail bridge", (p[0], p[1], z0 + DECK_Z + TRUSS_H)))
            else:
                road_bridge(K, tag, a, b, z0, width * R)
                items.append(("Road bridge", (p[0], p[1], z0 + 0.2)))
        return path, ps, [(g0, g1) for g0, g1, _, _ in gaps]

    # Roads first: the railway needs to know where it crosses them.
    road_runs, road_paths = [], []
    for n, road in enumerate(ROADS):
        path, ps, gaps = lay("Road %d" % (n + 1), road, ROAD_WIDTH, "bridge_road", Ki)
        road_paths.append(path)
        road_runs += runs_between(path, ps, gaps)
    # Walls go a little below the plate top: an edge lying exactly on it breaks into dashes
    # (its visibility is a coin toss), and sunk, it is simply hidden.
    union_ribbons(Ki, "BO_Roads", road_runs, ROAD_WIDTH * R, z0 - SINK, z0 + BED * R, MAT["road"])
    ROAD_RUNS[:] = road_runs
    ROAD_TOP[0] = z0 + BED * R

    # The railway: ballast and sleepers stop at a level crossing, the rails run on over it. The
    # lines' beds are one union, like the roads, so the junction carries no crossing outline.
    bed_top = z0 + BED * R + RAIL_LIFT
    bed_runs = []
    for n, (label, ctrl) in enumerate(RAIL_LINES):
        path, ps, gaps = lay(label, ctrl, RAIL_WIDTH, "bridge_rail", Ki)
        RAIL_PATHS[label] = path
        level = []
        for rp in road_paths:
            for i in range(len(path) - 1):
                for j in range(len(rp) - 1):
                    hit = _seg_hit(path[i], path[i + 1], rp[j], rp[j + 1])
                    if hit:
                        sh = ps[i] + math.dist(path[i], hit)
                        level.append((sh - ROAD_WIDTH * R / 2 - 0.10, sh + ROAD_WIDTH * R / 2 + 0.10))
        bed_runs += runs_between(path, ps, gaps + level)
        for k, r in enumerate(runs_between(path, ps, gaps)):
            for side in (-1, 1):
                _ribbon_strip(Ki, "BO_Coal_railway_rail%d_%d_%d" % (n, k, side > 0), r, RAIL_W,
                              bed_top + SLEEPER_T, bed_top + SLEEPER_T + RAIL_H, "silver",
                              offset=side * RAIL_GAUGE / 2, noink=True)
    union_ribbons(Ki, "BO_Coal_railway_bed", bed_runs, RAIL_WIDTH * R, z0 - SINK, bed_top, "ballast")
    _sleepers(Ki, "BO_Coal_railway_sleepers", bed_runs, RAIL_WIDTH * R * 0.80, bed_top)
    RAIL_TOP[0] = bed_top + SLEEPER_T + RAIL_H
    # A coal train on the south leg (owner), between the factory and the mine: the engine
    # leads toward the plate's edge with two loaded hoppers behind, clear of the crossing.
    south = RAIL_PATHS.get("Coal railway south")
    if south:
        coal_train(Ki, "BO_Coal_railway_train", south, RAIL_TOP[0])
    # The chemical plant's pipelines: each pipe runs level from inside the plant, bends down at
    # the far end and goes into the ground through a concrete collar; T-supports carry them.
    # Each bundle starts inside the plant vessel nearest its start, a tank ("tNN") or a
    # reaction column ("cN"), so the pipes come out of its side (owner: a bundle that started
    # in the open read as unrelated to anything).
    shells = []
    for ob in bpy.data.objects:
        if ob.type == 'MESH' and ob.name.startswith("Chemical_plant."):
            tag = ob.name.split(".", 1)[1]
            if (tag[:1] == "t" and len(tag) == 3 and tag[1:].isdigit()) or \
                    (tag[:1] == "c" and len(tag) == 2 and tag[1:].isdigit()):
                pts = [ob.matrix_world @ mathutils.Vector(c) for c in ob.bound_box]
                shells.append((sum(p.x for p in pts) / 8.0, sum(p.y for p in pts) / 8.0))
    for n, (a, b, count) in enumerate(PIPELINES):
        ax, ay = w(*a)
        bx, by = w(*b)
        if shells:
            ax, ay = min(shells, key=lambda c: math.dist(c, (ax, ay)))
        tx, ty = _unit((bx - ax, by - ay))
        nx, ny = -ty, tx
        run = math.dist((ax, ay), (bx, by))
        for k in range(count):
            off = (k - (count - 1) / 2.0) * PIPE_GAP
            p0 = (ax + nx * off, ay + ny * off, z0 + PIPE_H)
            p1 = (bx + nx * off, by + ny * off, z0 + PIPE_H)
            p2 = (bx + nx * off, by + ny * off, z0 - 0.40)
            Ki.pipe_run("BO_Pipeline%d_%d" % (n, k), [p0, p1, p2], PIPE_R, Ki.mat("pipe"), bend=0.16)
            Ki.cyl("BO_Pipeline%d_%d_collar" % (n, k), p1[0], p1[1], z0 + 0.03, PIPE_R * 2.0, 0.06,
                   Ki.mat("slab"), segments=16)
        half = (count - 1) / 2.0 * PIPE_GAP + 0.07
        for j in range(1, int(run / 0.42) + 1):
            f = j * 0.42 / run
            if f > 0.85:
                break
            sx, sy = ax + (bx - ax) * f, ay + (by - ay) * f
            Ki.box("BO_Pipeline%d_post%d" % (n, j), sx, sy, z0 + (PIPE_H - PIPE_R) / 2.0, 0.035, 0.035,
                   PIPE_H - PIPE_R, Ki.mat("darkmetal"))
            Ki.dirbox("BO_Pipeline%d_bar%d" % (n, j), (sx - nx * half, sy - ny * half, z0 + PIPE_H - PIPE_R - 0.015),
                      (sx + nx * half, sy + ny * half, z0 + PIPE_H - PIPE_R - 0.015), 0.03, 0.03, Ki.mat("darkmetal"))
    return items
