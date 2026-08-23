# Parametric builder for the Solar Farm (b_024).
# Run AFTER sprite_kit.py:
#   exec(open(".../sprite_kit.py").read())
#   exec(open(".../solar_farm_builder.py").read()); build_solar_farm(2)
#
# SITE class, like the wind farm and the mine: an earth block with strata on the cut edge, not
# a building on z=0. Power category, so mustard is the chroma, and it shares the wind farm's
# turf and gravel so the two renewables read as the same kind of place.
#
# ---------------------------------------------------------------------------------------
# THE FIVE THINGS THAT MAKE AN ARRAY READ
#
# 1. THE CELL GRID IS ONE MESH WITH TWO MATERIAL SLOTS, NOT STACKED PLATES. Thin white lines
#    laid ON a navy plate would be coplanar faces (rule 1, z-fighting) and, as separate
#    objects, would each earn their own contour — six inked rectangles per panel. Instead the
#    whole panel face is TILED: 5 cell columns and 4 line columns, 3 cell rows and 2 line
#    rows, 45 quads sharing edges, assigned to slot 0 (navy) or slot 1 (white). Material
#    boundaries inside one mesh are hard-edged and UNINKED, which is exactly a cell grid.
#
# 2. ROW PITCH EQUALS PANEL PITCH, DELIBERATELY. Screen column is x+y, so with the two pitches
#    equal every panel sharing (i + k) lands on exactly the same column and the array reads as
#    a regular grid. Any other pitch shears rows against columns, and the measured near-misses
#    are the worst outcome of all — 1.20 and 1.30 shift the back row by 6 and 12 px, which
#    looks like rows that were meant to line up and failed:
#
#      pitch   column shift
#      1.02        0 px      <- chosen: a regular grid
#      +0.09       6 px         near-miss
#      +0.19      12 px         near-miss
#      +0.44      29 px         clearly offset, but the array goes sparse
#
#    Inter-row occlusion is `rise + (depth - pitch)/2` and at these proportions it is NEGATIVE,
#    so the rows do not overlap at all and there is about 9 px of ground showing between them.
#
# 3. THE TILT IS SAFE AT ANY POSITIVE ANGLE, AND THAT IS WORTH KNOWING. A panel face is
#    edge-on — zero screen area — when its two spanning directions project parallel. Spanning
#    X and the slope (0, -cos t, -sin t) that happens at tan t = -1, i.e. only for a panel
#    tilted UP toward the camera at 45 deg. Panels tilt DOWN toward the front, so every angle
#    in the real 20-35 deg range is clear. 30 deg is used and its screen area is within 3% of
#    the best available.
#
# 4. CELLS ARE SQUARE ON SCREEN, WHICH IS NOT THE SAME AS BEING SQUARE. The two panel axes
#    project at 80.5 and 103.8 px per unit, so the slope is stretched 29%; the module is cut
#    to 2.15:1 to cancel it, and the two cell-gap widths are set independently for the same
#    reason. Uncorrected, a 5x3 grid reads as rectangular cells and looks like an error.
#
# 5. THE SITE IS SIZED TO THE CONTENT, NOT FIXED. A solar farm is flat, so unlike the wind
#    farm it has no tall object to grow the silhouette — with a constant plate all three
#    levels exported at exactly 870x534 and the level was invisible. The plate is therefore
#    computed from the actual extents each level, which is also just true: a small farm takes
#    less land. L1 comes out at roughly a third of L3's area.

import math

# Shared with the wind farm: the two renewables sit on the same kind of ground, and the port's
# land green is the set's only grass. Soil strata on the cut faces stay inside the 0.05-0.30
# earth band; the turf sits above it, which is what makes the top read as turf ON soil.
PALETTE["turf"] = (0.128, 0.235, 0.080)
PALETTE["turf_lo"] = (0.086, 0.168, 0.052)
PALETTE["gravel"] = (0.192, 0.186, 0.166)
ROLES["turf"] = "turf"
ROLES["turf_lo"] = "turf_lo"
ROLES["gravel"] = "gravel"
# PV. Measured, because the AgX response is steep down here and guessing overshoots: linear
# 0.030 -> luma 40, 0.026 -> 41, 0.023 -> 38, 0.0205 -> 35.5, 0.019 -> 28.5. The last is level
# with the background (26) and too far.
# The cell navy is the darkest material in the sprite set on purpose — a solar panel that
# is merely dark blue reads as painted metal. The floor on how dark it can go is NOT the
# background (luma ~26) but the synthesized contour colour (47, 59, 89, luma ~57): a cell
# darker than its own outline would invert the drawing. That is survivable only because the
# contour bands the sprite's OUTER boundary alone and the turf plate always surrounds the
# array, so the two never actually touch.
PALETTE["pv_cell"] = (0.0205, 0.0275, 0.0820)
# THE FRAME IS BRIGHTER THAN THE CELL GAPS, and that is what makes individual modules read.
# Frames of adjacent modules almost touch, exactly as they do in the field, so a module
# boundary is a band about five times a cell gap; giving it the brighter tone as well makes it
# the dominant line, and each panel reads as a framed unit instead of the row reading as one
# continuous grid.
PALETTE["pv_line"] = (0.300, 0.315, 0.355)
PALETTE["pv_frame"] = (0.400, 0.415, 0.450)
ROLES["pv_cell"] = "pv_cell"
ROLES["pv_line"] = "pv_line"
ROLES["pv_frame"] = "pv_frame"

SF_LEVELS = {
    1: dict(cols=3, rows=2, inverters=1, transformers=0, tracker=False),
    2: dict(cols=4, rows=3, inverters=2, transformers=1, tracker=True),
    3: dict(cols=5, rows=4, inverters=3, transformers=1, tracker=True),
}

PANEL_W = 0.94
PANEL_GAP = 0.08
TILT = 30.0
CELLS_A, CELLS_B = 5, 3
FRAME_W = 0.026                   # frame border showing round the glass
FRAME_T = 0.040                   # panel slab thickness
MOUNT_Z = 0.22                    # height of the panel's FRONT edge above the site top

_T = math.radians(TILT)
# THE TWO PANEL AXES DO NOT PROJECT AT THE SAME SCALE, and everything drawn on the face has to
# be corrected for it or nothing on the module looks square. The rig is TRUE isometric
# (elevation 35.264 deg, not 2:1 dimetric): a world X unit is 65.8 px across and 38.0 px up,
# a world Z unit is 76.0 px up. Along the row, a = (1,0,0) therefore projects to 76.0 px per
# unit; up the slope, b = (0, cos t, sin t) projects to 91.0. So a physically square cell comes
# out 20% taller than it is wide, and a uniform-width grid line comes out 20% heavier across
# the rows than down the columns. (A first version used dimetric numbers — 80.5 / 103.8 — and
# left the cells 6% wider than tall.)
_PX = 1024.0 / 11.0
_EL = math.radians(35.264)
_HX, _VX, _VZ = _PX / math.sqrt(2.0), _PX * math.sin(_EL) / math.sqrt(2.0), _PX * math.cos(_EL)
_SA = math.hypot(_HX, _VX)
_SB = math.hypot(_HX * math.cos(_T), _VX * math.cos(_T) + _VZ * math.sin(_T))
_KB = _SA / _SB                                     # 0.835
# Slope length set so a 5x3 grid gives cells that are square ON SCREEN, which also makes the
# module a realistic 2.0:1 landscape panel rather than the 5:3 it was.
PANEL_S = PANEL_W * (float(CELLS_B) / CELLS_A) * _KB
# Cell gaps, likewise corrected: 1.2 px each way. 0.024 was 14% of a cell and turned the panels
# grey; a real gap is nearer 1%, which is sub-pixel here, so LINE_A is about the thinnest that
# survives the export downscale without breaking up.
LINE_A = 0.015                    # width of the column gaps, measured along a
LINE_B = LINE_A * _KB             # width of the row gaps, measured along b

PANEL_DEPTH = PANEL_S * math.cos(_T)      # plan depth
PANEL_RISE = PANEL_S * math.sin(_T)
PITCH = PANEL_W + PANEL_GAP               # 1.02, used for BOTH axes — see note 2


def _under(d):
    """z of the slab's UNDERSIDE at plan offset `d` back from the module's front edge.

    Every member that carries the modules is placed from this, never by eye. The back rail was
    once put at `MOUNT_Z + PANEL_RISE - 0.035`, which reads as 'just under the back edge' and
    is in fact 0.045 ABOVE the sloping face at the rail's own y — so a bar crossed the top of
    every module and ate part of the top row of cells."""
    return MOUNT_Z + d * math.tan(_T) - (FRAME_T / 2.0) / math.cos(_T)

# Everything below is RELATIVE to the array's front-left corner, which sits at (0, 0). The
# whole site is shifted at the end so its centre lands under the camera target — see _origin.
#
# NO BUILDINGS. A solar farm's only structures are electrical: inverter cabinets on pads, a
# pad-mount transformer and the takeoff pole. There was a control room here with a window, a
# door and a pitched roof, and it read as a house in a field — the one thing a solar farm never
# has. Dropping it also shrinks the plate, since the site is sized to its content.
#
# Yard runs across the front, left to right: inverters, transformer, pole. Ordering it that way
# is what keeps the SCREEN COLUMNS (x+y) apart, since the inverters all share a y. Measured
# columns are -0.83 / 0.35 / 1.53 / 2.58 / 3.83, tightest pair 1.05 (69 px).
INV_X0, INV_DX, INV_Y = 0.15, 1.18, -0.98
TR_Y = -1.52
CMB_DX = -0.22                    # string combiner at each row's left end
TRAY_DX = -0.48                   # DC tray running back along Y
DC_Y = -0.42                      # DC tray running across, BEHIND the inverters
TRACK_DY = -0.28                  # access track, inside the plate's front margin
# Grid takeoff. A DISTRIBUTION POLE, not a lattice mast: a small farm connects at MV on a pole,
# and the wind farm already owns the lattice silhouette. Offset right of whatever it is fed
# from, which is the transformer at L2/L3 and the inverter itself at L1.
POLE_DX, POLE_DY = 0.95, 0.30
POLE_H, POLE_ARM, POLE_DROP = 1.55, 0.72, 0.16
MARGIN = 0.45
SITE_H = 0.34


def _tr_x(p):
    return INV_X0 + p["inverters"] * INV_DX + 0.41


def _pole_xy(p):
    """Where the takeoff pole stands, and what feeds it."""
    if p["transformers"]:
        return _tr_x(p) + POLE_DX, TR_Y + POLE_DY
    return INV_X0 + POLE_DX, INV_Y + POLE_DY


def _extents(p):
    """Relative bounding box of everything that is not ground, before the margin."""
    aw = p["cols"] * PANEL_W + (p["cols"] - 1) * PANEL_GAP
    ad = (p["rows"] - 1) * PITCH + PANEL_DEPTH
    x_lo, x_hi = TRAY_DX - 0.09, max(aw, INV_X0 + (p["inverters"] - 1) * INV_DX + 0.48)
    y_lo, y_hi = INV_Y - 0.32, ad
    if p["transformers"]:
        x_hi = max(x_hi, _tr_x(p) + 0.58)
        y_lo = min(y_lo, TR_Y - 0.48)
    px, py = _pole_xy(p)
    x_hi = max(x_hi, px + POLE_ARM / 2 + 0.10)
    y_lo = min(y_lo, py - 0.20)
    return aw, ad, x_lo, x_hi, y_lo, y_hi


def _origin(p):
    """Offset that centres the finished plate under the camera target."""
    _, _, x_lo, x_hi, y_lo, y_hi = _extents(p)
    return (0.30 - (x_lo + x_hi) / 2.0, 0.15 - (y_lo + y_hi) / 2.0)


def _panel(K, name, px, py, base_z):
    """One framed module: a slab in the tilted plane, plus the tiled cell grid on its face.

    `px`, `py` are the FRONT-LEFT corner in plan. Local frame: `a` along +X (the row), `b` up
    the slope toward +Y, `n` the outward normal."""
    import bpy, bmesh
    a = (1.0, 0.0, 0.0)
    b = (0.0, math.cos(_T), math.sin(_T))
    n = (0.0, -math.sin(_T), math.cos(_T))
    org = (px, py, base_z + MOUNT_Z)

    def at(ua, ub, un):
        return tuple(org[k] + a[k] * ua + b[k] * ub + n[k] * un for k in range(3))

    # --- frame slab: the glass rectangle grown by FRAME_W, extruded along the normal --------
    me = bpy.data.meshes.new("%s_fr" % name)
    bm = bmesh.new()
    hi = FRAME_T / 2.0
    corners = ((-FRAME_W, -FRAME_W), (PANEL_W + FRAME_W, -FRAME_W),
               (PANEL_W + FRAME_W, PANEL_S + FRAME_W), (-FRAME_W, PANEL_S + FRAME_W))
    top = [bm.verts.new(at(ua, ub, hi)) for ua, ub in corners]
    bot = [bm.verts.new(at(ua, ub, hi - FRAME_T)) for ua, ub in corners]
    bm.faces.new(top)
    bm.faces.new(list(reversed(bot)))
    for i in range(4):
        j = (i + 1) % 4
        bm.faces.new([top[i], top[j], bot[j], bot[i]])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me)
    bm.free()
    K.obj("%s_fr" % name, me, K.mat("pv_frame"))

    # --- cell grid: ONE mesh, two slots, 45 tiled quads that share edges (see note 1) -------
    ca = (PANEL_W - (CELLS_A - 1) * LINE_A) / CELLS_A
    cb = (PANEL_S - (CELLS_B - 1) * LINE_B) / CELLS_B
    spans_a, x = [], 0.0
    for i in range(2 * CELLS_A - 1):
        w = ca if i % 2 == 0 else LINE_A
        spans_a.append((x, x + w, i % 2 == 1))
        x += w
    spans_b, y = [], 0.0
    for j in range(2 * CELLS_B - 1):
        h = cb if j % 2 == 0 else LINE_B
        spans_b.append((y, y + h, j % 2 == 1))
        y += h

    mg = bpy.data.meshes.new("%s_pv" % name)
    bm = bmesh.new()
    zf = FRAME_T / 2.0 + 0.004                  # clear of the frame's top face, no z-fight
    flags = []
    for (b0, b1, lb) in spans_b:
        for (a0, a1, la) in spans_a:
            bm.faces.new([bm.verts.new(at(a0, b0, zf)), bm.verts.new(at(a1, b0, zf)),
                          bm.verts.new(at(a1, b1, zf)), bm.verts.new(at(a0, b1, zf))])
            flags.append(la or lb)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(mg)
    bm.free()
    ob = K.obj("%s_pv" % name, mg, K.mat("pv_cell"))
    ob.data.materials.append(K.mat("pv_line"))
    for poly, is_line in zip(mg.polygons, flags):
        poly.material_index = 1 if is_line else 0
    return ob


def _cable(K, name, p0, p1, sag=0.10, segs=5, r=0.014):
    """Straight-ish conductor with a little sag, as a chain of short cylinders.

    Sag scales with SPAN, so a short drop stays taut and a long run droops — a fixed sag makes
    every cable look like the same piece of rope regardless of how far it goes."""
    span = math.dist(p0, p1)
    pts = []
    for i in range(segs + 1):
        t = i / float(segs)
        pts.append((p0[0] + (p1[0] - p0[0]) * t, p0[1] + (p1[1] - p0[1]) * t,
                    p0[2] + (p1[2] - p0[2]) * t - sag * span * 4.0 * t * (1.0 - t)))
    for i in range(segs):
        K.dircyl("%s_%d" % (name, i), pts[i], pts[i + 1], r, K.mat("stair"), segments=6)


def _takeoff(K, p, ox, oy, base_z):
    """Pole, crossarm, three insulator strings, and one cable per phase back to the source.

    The cables land on the transformer's HV BUSHINGS, never on its conservator drum or its
    radiator fins — those are not electrical, and a cable touching them is drawn nonsense. This
    is the error the electrolyser's audit turned up, so it is worth naming twice."""
    px, py = _pole_xy(p)
    px, py = ox + px, oy + py
    fm = K._fine_mode
    K._fine_mode = True
    K.cyl("pole", px, py, base_z + POLE_H / 2, 0.055, POLE_H, K.mat("gear"), segments=10)
    K.box("pole_arm", px, py, base_z + POLE_H - 0.13, POLE_ARM, 0.07, 0.07, K.mat("gear"))
    xs = (px - POLE_ARM * 0.36, px, px + POLE_ARM * 0.36)
    for i, ix in enumerate(xs):
        K.insulator_string("pins%d" % i, ix, py, base_z + POLE_H - 0.155, POLE_DROP, discs=3)
    if p["transformers"]:
        # HV bushing tops, read straight off transformer(): bushings sit at cx + i*0.14*s and
        # their top disc finishes at z + 0.676*s.
        s_ = 1.15
        tx, ty = ox + _tr_x(p), oy + TR_Y
        src = [(tx + i * 0.14 * s_, ty, base_z + 0.676 * s_) for i in (-1, 0, 1)]
    else:
        # L1 has no transformer, so the pole is fed from the inverter's own AC riser box.
        ix, iy = ox + INV_X0, oy + INV_Y
        K.box("acbox", ix + 0.30, iy, base_z + 0.62, 0.20, 0.24, 0.18, K.mat("gear"))
        src = [(ix + 0.30 + j * 0.055, iy, base_z + 0.71) for j in (-1, 0, 1)]
    for i in range(3):
        _cable(K, "hv%d" % i, src[i], (xs[i], py, base_z + POLE_H - 0.155 - POLE_DROP))
    K._fine_mode = fm


def _row(K, tag, cols, x0, row_y, base_z, tracker):
    """One row on its bents: a short front post and a tall back post at three stations, tied
    by two rails. The rails are what stop the modules floating."""
    width = cols * PANEL_W + (cols - 1) * PANEL_GAP
    fm = K._fine_mode
    K._fine_mode = True
    for i in range(cols):
        _panel(K, "p%s_%d" % (tag, i), x0 + i * PITCH, row_y, base_z)
    # Rail centres come from _under(), not from the back edge — see the note there.
    rh, df, db = 0.055, 0.05, PANEL_DEPTH - 0.05
    zf = base_z + _under(df) - 0.004 - rh / 2.0
    zb = base_z + _under(db) - 0.004 - rh / 2.0
    K.box("rf%s" % tag, x0 + width / 2.0, row_y + df, zf, width, rh, rh, K.mat("pv_frame"))
    K.box("rb%s" % tag, x0 + width / 2.0, row_y + db, zb, width, rh, rh, K.mat("pv_frame"))
    # TWO BENTS PER MODULE, at quarter points. Three stations spread over a whole row left
    # most modules spanning nothing, so the array looked pegged down rather than carried.
    for i in range(cols):
        for j, f in enumerate((0.26, 0.74)):
            sx = x0 + i * PITCH + PANEL_W * f
            K.box("pf%s_%d%d" % (tag, i, j), sx, row_y + df,
                  base_z + (zf - base_z) / 2.0, 0.050, 0.050, zf - base_z,
                  K.mat("pv_frame"))
            K.box("pb%s_%d%d" % (tag, i, j), sx, row_y + db,
                  base_z + (zb - base_z) / 2.0, 0.060, 0.060, zb - base_z,
                  K.mat("pv_frame"))
    if tracker:
        # Single-axis tracker torque tube (the L2 research), OVERHANGING the row's left end so
        # it is visible at all — buried under the modules it would be pure object count.
        zt = base_z + _under(PANEL_DEPTH / 2.0) - 0.004 - 0.042
        K.dircyl("tt%s" % tag, (x0 - 0.20, row_y + PANEL_DEPTH / 2.0, zt),
                 (x0 + width, row_y + PANEL_DEPTH / 2.0, zt), 0.042, K.mat("gear"),
                 segments=10)
        K.box("dr%s" % tag, x0 - 0.28, row_y + PANEL_DEPTH / 2.0, zt, 0.20, 0.17, 0.20,
              K.mat("power_accent"))
    K._fine_mode = fm


def _site(K, p, ox, oy):
    _, _, x_lo, x_hi, y_lo, y_hi = _extents(p)
    x0, x1 = ox + x_lo - MARGIN, ox + x_hi + MARGIN
    y0, y1 = oy + y_lo - MARGIN, oy + y_hi + MARGIN
    K.box("ground", (x0 + x1) / 2, (y0 + y1) / 2, SITE_H / 2, x1 - x0, y1 - y0, SITE_H,
          K.mat("ground"))
    K.box("ground_top", (x0 + x1) / 2, (y0 + y1) / 2, SITE_H + 0.012, x1 - x0 - 0.06,
          y1 - y0 - 0.06, 0.05, K.mat("turf"))
    ysw = oy + y_hi - 0.30
    K.box("turf_far", (x0 + x1) / 2, (ysw + y1) / 2, SITE_H + 0.020, x1 - x0 - 0.06,
          y1 - ysw, 0.05, K.mat("turf_lo"))
    # Strata on the two cut faces the camera SEES. Earth tones stay inside 0.05-0.30: above
    # that the bands render within a few luma of each other and the layering vanishes.
    for i, m in enumerate(("ground3", "ground_deep")):
        z = SITE_H * (0.60 - 0.30 * i)
        K.box("strat_f%d" % i, (x0 + x1) / 2, y0 - 0.012, z, x1 - x0, 0.03, SITE_H * 0.22,
              K.mat(m))
        K.box("strat_r%d" % i, x1 + 0.012, (y0 + y1) / 2, z, 0.03, y1 - y0, SITE_H * 0.22,
              K.mat(m))
    K.box("track", (x0 + x1) / 2, y0 + 0.30, SITE_H + 0.030, x1 - x0 - 0.30, 0.30, 0.05,
          K.mat("gravel"))
    return SITE_H


def _yard(K, p, ox, oy, base_z):
    """Inverter cabinets and the transformer, plus the runs that CLOSE both circuits: DC
    from the string combiners to the inverters, AC from the inverters out to the transformer.
    Without them the array powers nothing and the yard is fed by nothing."""
    aw, ad, _, _, _, _ = _extents(p)
    iy = oy + INV_Y
    for k in range(p["inverters"]):
        ix = ox + INV_X0 + k * INV_DX
        K.box("pad_i%d" % k, ix, iy, base_z + 0.025, 0.80, 0.50, 0.05, K.mat("gravel"))
        K.box("inv%d" % k, ix, iy, base_z + 0.29, 0.66, 0.36, 0.52, K.mat("wall_bright"))
        # Cap is FLUSH, not an overhang. An overhanging lid is a roof, and a roof is what made
        # these read as sheds rather than as switchgear.
        K.box("inv%d_cap" % k, ix, iy, base_z + 0.565, 0.68, 0.38, 0.035, K.mat("gear"))
        K.box("inv%d_band" % k, ix, iy, base_z + 0.10, 0.67, 0.37, 0.11,
              K.mat("power_accent"))
        K.box("inv%d_plin" % k, ix, iy, base_z + 0.035, 0.70, 0.40, 0.07, K.mat("wall_grey"))
        for j in range(3):          # cooling louvres on the -Y face the camera actually sees
            K.box("inv%d_lv%d" % (k, j), ix, iy - 0.185, base_z + 0.28 + j * 0.085,
                  0.48, 0.02, 0.05, K.mat("gear"))
        K.box("inv%d_hn" % k, ix + 0.245, iy - 0.185, base_z + 0.34, 0.10, 0.03, 0.22,
              K.mat("gear"))
    if p["transformers"]:
        K.transformer("tr0", ox + _tr_x(p), oy + TR_Y, base_z, s=1.15, accent=True)

    # --- DC: a combiner at each row's left end, onto a tray that runs to the inverters ------
    dcy = oy + DC_Y
    for r in range(p["rows"]):
        ry = oy + r * PITCH + PANEL_DEPTH / 2.0
        K.box("cmb%d" % r, ox + CMB_DX, ry, base_z + 0.19, 0.20, 0.17, 0.38,
              K.mat("wall_bright"))
        K.box("cmb%d_b" % r, ox + CMB_DX, ry, base_z + 0.06, 0.22, 0.19, 0.12,
              K.mat("power_accent"))
        # SPUR onto the tray. Without it every combiner floats 0.26 from the run and the whole
        # DC side is an open circuit — caught by the audit, not by the eye.
        K.box("spur%d" % r, ox + (CMB_DX + TRAY_DX) / 2, ry, base_z + 0.055,
              CMB_DX - TRAY_DX, 0.10, 0.07, K.mat("stair"))
    K.box("tray_y", ox + TRAY_DX, (dcy + oy + ad - PANEL_DEPTH / 2.0) / 2, base_z + 0.055,
          0.14, (oy + ad - PANEL_DEPTH / 2.0) - dcy, 0.07, K.mat("stair"))
    last = ox + INV_X0 + (p["inverters"] - 1) * INV_DX
    K.box("tray_x", (ox + TRAY_DX + last) / 2, dcy, base_z + 0.055, last - ox - TRAY_DX,
          0.14, 0.07, K.mat("stair"))
    for k in range(p["inverters"]):
        ix = ox + INV_X0 + k * INV_DX
        K.box("drop%d" % k, ix, (dcy + iy) / 2, base_z + 0.055, 0.12, dcy - iy, 0.07,
              K.mat("stair"))
    # --- AC: inverters out to the transformer ----------------------------------------------
    if p["transformers"]:
        acy, tx = oy + TR_Y, ox + _tr_x(p)
        K.box("acbus", (ox + INV_X0 + tx) / 2, acy, base_z + 0.055, tx - ox - INV_X0, 0.14,
              0.07, K.mat("stair"))
        for k in range(p["inverters"]):
            ix = ox + INV_X0 + k * INV_DX
            K.box("acsp%d" % k, ix, (acy + iy) / 2, base_z + 0.055, 0.12, iy - acy, 0.07,
                  K.mat("stair"))


def build_solar_farm(level: int = 2) -> dict:
    p = SF_LEVELS[level]
    setup_rig(target=(0.30, 0.15, 0.72))
    K = Kit(open_collection("BLDG_solar"))
    ox, oy = _origin(p)
    base_z = _site(K, p, ox, oy)
    for r in range(p["rows"]):
        _row(K, str(r), p["cols"], ox, oy + r * PITCH, base_z, p["tracker"])
    _yard(K, p, ox, oy, base_z)
    _takeoff(K, p, ox, oy, base_z)
    print("\n".join(K.validate(ground=0.0)))
    return {"building": "solar_farm", "level": level,
            "panels": p["rows"] * p["cols"], "objects": len(K.col.objects)}
