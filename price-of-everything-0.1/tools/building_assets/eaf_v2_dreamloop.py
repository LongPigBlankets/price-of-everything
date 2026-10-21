"""Dreamloop blockouts for the EAF rebuild: three compositions at the same massing fidelity,
on one sheet, so the owner picks a direction before the detail is spent.

Executed after eaf_v2_builder.py in sprite_kit's namespace. Each blockout is masses only:
walls on a brick base, roofs, the open bay, the furnace shell with its rods and mast on its
platform, the vault, the fume plant, the chimney, the scrap bay and the ladle car.

A  gable bay    the old composition restyled: ridge along Y, the bay in the front gable end
B  long front   ridge along X, the bay in the long front face, vault at the end wall
C  open aisle   no hall: the furnace under a flat canopy on columns in front of a low range
"""
import math


def _m_shop(K, x0, x1, y0, y1, eave, ridge, bay):
    w, d = x1-x0, y1-y0; cx, cy = (x0+x1)/2, (y0+y1)/2
    wall, brick, frame = K.mat('f2_refractory'), K.mat('f_brick'), K.mat('f_frame')
    K.box('m_footing', cx, cy, .08, w+.10, d+.10, .16, K.mat('f_base'))
    K.box('m_floor', cx, cy, .13, w-.16, d-.16, .02, K.mat('f_base'))
    t = .08

    def slab(nm, sx_, sy_, lx, ly):
        K.box(nm+'_base', sx_, sy_, (.10+BASE_Z)/2, lx, ly, BASE_Z-.10, brick)
        K.box(nm, sx_, sy_, (BASE_Z+eave)/2, lx, ly, eave-BASE_Z, wall)
    slab('m_back', cx, y1-t/2, w, t)
    slab('m_end_l', x0+t/2, cy, t, d-2*t)
    slab('m_end_r', x1-t/2, cy, t, d-2*t)
    a0, a1 = bay
    slab('m_pier_l', (x0+a0)/2, y0+t/2, a0-x0, t)
    slab('m_pier_r', (a1+x1)/2, y0+t/2, x1-a1, t)
    K.box('m_lintel', (a0+a1)/2, y0+.05, eave-LINTEL_H/2, a1-a0+.02, .13, LINTEL_H, frame)
    for px in (a0-.045, a1+.045, x0+.06, x1-.06):
        K.box('m_column', px, y0-.03, (.12+eave)/2, .11, .07, eave-.12, frame)
    if ridge == 'x':
        K.prism('m_gable_l', (x0+t/2, cy, 0), (0, 1), [(-d/2, eave), (0, eave+RISE), (d/2, eave)], t, wall)
        K.prism('m_gable_r', (x1-t/2, cy, 0), (0, 1), [(-d/2, eave), (0, eave+RISE), (d/2, eave)], t, wall)
        K.prism('m_roof', (cx, cy, 0), (0, 1), [(-d/2-.09, eave-.02), (0, eave+RISE), (d/2+.09, eave-.02), (d/2+.09, eave+.04), (0, eave+RISE+.06), (-d/2-.09, eave+.04)], w+.16, K.mat('f_roof'))
        K.box('m_monitor', cx, cy, eave+RISE+.22, w*.70, .40, .36, frame)
        K.box('m_monitor_roof', cx, cy, eave+RISE+.44, w*.70+.10, .50, .08, K.mat('f_roof'))
    else:
        K.prism('m_gable_f', (cx, y0+t/2, 0), (1, 0), [(-w/2, eave), (0, eave+RISE), (w/2, eave)], t, wall)
        K.prism('m_gable_b', (cx, y1-t/2, 0), (1, 0), [(-w/2, eave), (0, eave+RISE), (w/2, eave)], t, wall)
        K.prism('m_roof', (cx, cy, 0), (1, 0), [(-w/2-.09, eave-.02), (0, eave+RISE), (w/2+.09, eave-.02), (w/2+.09, eave+.04), (0, eave+RISE+.06), (-w/2-.09, eave+.04)], d+.16, K.mat('f_roof'))
        K.box('m_monitor', cx, cy, eave+RISE+.22, .40, d*.70, .36, frame)
        K.box('m_monitor_roof', cx, cy, eave+RISE+.44, .50, d*.70+.10, .08, K.mat('f_roof'))


def _m_furnace(K, bx, by, mast_x):
    frame, zinc = K.mat('f_frame'), K.mat('f_zinc')
    px0, px1 = bx-1.15, mast_x+.45
    K.box('m_platform', (px0+px1)/2, by+.30, PLATFORM_Z-.04, px1-px0, 1.40, .08, K.mat('r_deck'))
    for x in (px0+.12, (px0+px1)/2, px1-.12):
        for y in (by-.28, by+.88):
            K.dirbox('m_platform_col', (x, y, .14), (x, y, PLATFORM_Z-.08), .09, .09, frame)
    _r_rail(K, 'm_rail_l', (px0, by-.40, PLATFORM_Z), (bx-BOWL_R-.06, by-.40, PLATFORM_Z))
    _r_rail(K, 'm_rail_r', (bx+BOWL_R+.06, by-.40, PLATFORM_Z), (px1, by-.40, PLATFORM_Z))
    K.cyl('m_pedestal', bx, by, (PLATFORM_Z+RIM_Z-BOWL_RISE+.12)/2, .42, RIM_Z-BOWL_RISE+.12-PLATFORM_Z, frame, segments=20)
    _e_bowl(K, 'm_shell', bx, by, RIM_Z, BOWL_R, BOWL_RISE, BOWL_WALL, K.mat('f_shell'), K.mat('f_oxide'))
    melt = _emissive('e_melt', (.95, .32, .02), 1.0)
    melt_z = RIM_Z-MELT_DROP; rm = _e_melt_radius()
    K.cyl('m_melt', bx, by, melt_z, rm, .05, melt, segments=24)
    for i in range(3):
        a = math.radians(ROD_ANGLES[i]); rx, ry = bx+ROD_RING*math.cos(a), by+ROD_RING*math.sin(a)
        z1 = ROD_TOPS[i]
        K.cyl(f'm_rod{i}', rx, ry, (melt_z-ROD_SUBMERGE+z1)/2, ROD_R, z1-(melt_z-ROD_SUBMERGE), K.mat('e_graphite'), segments=16)
        az = z1-ARM_DROP
        K.cyl(f'm_clamp{i}', rx, ry, az, ROD_R+.06, .22, zinc, segments=16)
        K.dirbox(f'm_bracket{i}', (mast_x, by, az), (mast_x, ry, az), .14, .14, frame)
        K.dirbox(f'm_arm{i}', (mast_x-MAST_W/2+.02, ry, az), (rx+ROD_R, ry, az), .11, .13, zinc)
    mt = max(ROD_TOPS)-ARM_DROP+.20
    K.box('m_mast', mast_x, by, (PLATFORM_Z+mt)/2, MAST_W, MAST_W, mt-PLATFORM_Z, frame)
    K.box('m_mast_cap', mast_x, by, mt+.03, MAST_W+.08, MAST_W+.08, .06, zinc)


def _m_block(K, name, x0, x1, y0, y1, h, wall='f_brick'):
    return _r_block(K, name, x0, x1, y0, y1, h, wall=wall)


def _m_bag(K, x0, x1, y0, y1):
    cx, cy = (x0+x1)/2, (y0+y1)/2
    bz0, bz1 = BAG_Z
    K.box('m_bag', cx, cy, (bz0+bz1)/2, x1-x0, y1-y0, bz1-bz0, K.mat('f2_filter'))
    K.box('m_bag_lid', cx, cy, bz1+.04, x1-x0+.10, y1-y0+.10, .08, K.mat('f_roof'))
    _e_frustum(K, 'm_bag_hopper', x0, x1, y0, y1, bz0+.02, .62, .34, .30, K.mat('f2_filter'))
    for sx_ in (x0+.12, x1-.12):
        for sy_ in (y0+.12, y1-.12):
            K.dirbox('m_bag_leg', (sx_, sy_, .10), (sx_, sy_, bz0-.02), .12, .12, K.mat('f_frame'))
    K.box('m_bag_skip', cx, cy, .20, .56, .46, .40, K.mat('f_frame'))
    return cx, cy


def _m_chimney(K, sx, sy):
    K.box('m_stack_base', sx, sy, .16+.55, .62, .62, 1.10, K.mat('f_brick'))
    K.box('m_stack_plate', sx, sy, 1.30, .70, .70, .08, K.mat('stone'))
    barrel = STACK_TOP-.24-1.34
    K.cone('m_stack_barrel', sx, sy, 1.34+barrel/2, .27, .21, barrel, K.mat('f_brick'))
    K.cyl('m_stack_cap', sx, sy, STACK_TOP-.24+.08, .24, .16, K.mat('f_frame'))
    K.cyl('m_stack_top', sx, sy, STACK_TOP-.08+.04, .21, .08, K.mat('ink_black'))


def _m_scrap(K, x0, x1, y0, y1):
    h = .95; brick = K.mat('f_brick')
    K.box('m_scrap_back', (x0+x1)/2, y1-.06, .08+h/2, x1-x0, .12, h, brick)
    for xe in (x0+.06, x1-.06):
        K.box('m_scrap_end', xe, (y0+y1)/2, .08+h/2, .12, y1-y0, h, brick)
    K.dome_cap('m_scrap_heap', (x0+x1)/2, (y0+y1)/2, .08, .38, .42, K.mat('f_steel'), rings=5)


def _m_tubes(K, pts, collar):
    K._fine_mode = True
    for k in range(3):
        off = (k-1)*.15
        K.pipe_run(f'm_bus{k}', [(x+(off if ax == 'x' else 0), y+(off if ax == 'y' else 0), z) for (x, y, z, ax) in pts], .038, mat=K.mat('f_zinc'), bend=.09)
    K._fine_mode = False
    x, y, z, face = collar
    _v2_flange(K, 'm_bus_collar', x, y, z, face, w=.46, h=.16)


def _m_finish(K, tag):
    return _r_finish(K, 2, 'blockout '+tag)


def build_eaf_blockout_a(level=2):
    """A: ridge along Y, the bay in the front gable end (the old composition restyled)."""
    K = _e_begin()
    x0, x1, y0, y1 = -2.30, 2.30, -.30, 3.00
    bx, by, mast_x = -.10, .40, 1.00
    eave = _e_solve_eave()
    _r_pad(K, 'm_pad', -1.4, x1+.2, -1.75, y0)
    _m_shop(K, x0, x1, y0, y1, eave, 'y', (-1.25, 1.80))
    _m_furnace(K, bx, by, mast_x)
    # Vault at the front left, tubes along the pier into the bay.
    _m_block(K, 'm_vault', -3.20, -2.35, -1.30, -.40, 2.70)
    _m_tubes(K, [(-2.78, -.40, 2.60, 'x'), (-2.78, -.05, 2.60, 'x'), (-1.35, -.05, 2.60, 'x')], (-1.33, -.05, 2.60, 'x'))
    # Fume: out of the right wall mid-depth to the bag house, flue to the chimney behind.
    K.pipe_run('m_duct', [(x1-.02, 1.20, eave-.6), (3.05, 1.20, eave-.6), (3.05, 1.20, BAG_Z[1]+.08)], .19, mat=K.mat('white_pipe'), bend=.30)
    cx, cy = _m_bag(K, 2.70, 3.40, .80, 1.60)
    K.dircyl('m_flue', (3.40, cy, FLUE_Z), (3.95-.31, cy, FLUE_Z), .13, K.mat('white_pipe'), segments=14)
    _m_chimney(K, 3.95, cy)
    _m_scrap(K, -2.20, -1.45, -1.40, -.65)
    _v2_ladles(K, 'm_ladle', .75, -.95)
    return _m_finish(K, 'A gable bay')


def build_eaf_blockout_b(level=2):
    """B: ridge along X, the bay in the long front face, the vault at the end wall."""
    K = _e_begin()
    x0, x1, y0, y1 = SHOP
    eave = _e_solve_eave()
    _r_pad(K, 'm_pad', -1.4, x1+.2, -1.75, y0)
    _r_pad(K, 'm_pad_r', x1, VAULT[1]+.15, VAULT[2]-.2, 1.0)
    _m_shop(K, x0, x1, y0, y1, eave, 'x', BAY)
    _m_furnace(K, BX, BY, MAST_X)
    _m_block(K, 'm_vault', *VAULT, VAULT_H)
    _m_tubes(K, [(2.60, BY, VAULT_H+.2, 'y'), (2.60, BY, BUS_Z, 'y'), (x1+.01, BY, BUS_Z, 'y')], (x1+.02, BY, BUS_Z, 'x'))
    cx, cy = _m_bag(K, *BAG)
    K.pipe_run('m_duct', [(x1-.02, DUCT_Y, eave-.6), (cx, DUCT_Y, eave-.6), (cx, DUCT_Y, BAG_Z[1]+.08)], .19, mat=K.mat('white_pipe'), bend=.30)
    sx, sy = STACK_XY
    K.dircyl('m_flue', (BAG[1]+.02, sy-.15, FLUE_Z), (sx-.31, sy-.15, FLUE_Z), .13, K.mat('white_pipe'), segments=14)
    _m_chimney(K, sx, sy)
    _m_scrap(K, *SCRAP)
    _v2_ladles(K, 'm_ladle', *LADLE_XY)
    return _m_finish(K, 'B long front')


def build_eaf_blockout_c(level=2):
    """C: no hall. The furnace under a flat canopy on columns, a low brick range behind."""
    K = _e_begin()
    bx, by, mast_x = -.10, .40, 1.00
    _r_pad(K, 'm_pad', -1.4, 2.2, -1.75, 1.9)
    _r_pad(K, 'm_pad_r', 2.0, 3.1, -.5, 1.0)
    # The back range: brick, two storeys, monitor roof, in the place of the shop's back half.
    roof = _m_block(K, 'm_range', -2.40, 2.00, 1.30, 2.60, 2.60)
    K.box('m_range_monitor', -.20, 1.95, roof+.18, 3.0, .40, .36, K.mat('f_frame'))
    K.box('m_range_monitor_roof', -.20, 1.95, roof+.40, 3.1, .50, .08, K.mat('f_roof'))
    # Canopy: a membrane slab on six dark columns, high enough to clear the rods.
    cz = max(ROD_TOPS)+.45
    cx0, cx1, cy0, cy1 = -1.60, 1.80, -.50, 1.30
    for x in (cx0+.10, (cx0+cx1)/2, cx1-.10):
        for y in (cy0+.10, cy1-.10):
            K.box('m_canopy_foot', x, y, .05, .22, .22, .10, K.mat('f_base'))
            K.dirbox('m_canopy_col', (x, y, .10), (x, y, cz), .13, .13, K.mat('f_frame'))
    K.box('m_canopy_beam_f', (cx0+cx1)/2, cy0+.10, cz+.06, cx1-cx0, .14, .14, K.mat('f_frame'))
    K.box('m_canopy_beam_b', (cx0+cx1)/2, cy1-.10, cz+.06, cx1-cx0, .14, .14, K.mat('f_frame'))
    K.box('m_canopy', (cx0+cx1)/2, (cy0+cy1)/2, cz+.17, cx1-cx0+.30, cy1-cy0+.30, .10, K.mat('membrane'))
    K.box('m_canopy_edge', (cx0+cx1)/2, (cy0+cy1)/2, cz+.24, cx1-cx0+.34, cy1-cy0+.34, .05, K.mat('stone'))
    _m_furnace(K, bx, by, mast_x)
    _m_block(K, 'm_vault', 2.05, 2.95, -.30, .60, 2.70)
    _m_tubes(K, [(2.60, by, 2.90, 'y'), (2.60, by, BUS_Z, 'y'), (mast_x+.2, by, BUS_Z, 'y')], (mast_x+.16, by, BUS_Z, 'x'))
    # Fume: a hood under the canopy with the duct out of its back to the bag house.
    K.box('m_hood', bx+.10, by+.25, cz-.40, 1.60, .90, .22, K.mat('f_zinc'))
    cx, cy = _m_bag(K, *BAG)
    K.pipe_run('m_duct', [(bx+.85, by+.25, cz-.40), (2.5, by+.25, cz-.40), (2.5, DUCT_Y, cz-.40), (cx, DUCT_Y, cz-.40), (cx, DUCT_Y, BAG_Z[1]+.08)], .19, mat=K.mat('white_pipe'), bend=.30)
    sx, sy = STACK_XY
    K.dircyl('m_flue', (BAG[1]+.02, sy-.15, FLUE_Z), (sx-.31, sy-.15, FLUE_Z), .13, K.mat('white_pipe'), segments=14)
    _m_chimney(K, sx, sy)
    _m_scrap(K, *SCRAP)
    _v2_ladles(K, 'm_ladle', *LADLE_XY)
    return _m_finish(K, 'C open aisle')


# ------------------------------------------------------------------ round 2: from scratch
# The owner asked for compositions that do not keep the old "shed with a bay round a bowl".
# Three directions, same massing fidelity, one sheet.
#
# D  electrode house   a closed refractory hall; the three electrode columns rise through
#                      the roof on their masts, the fume elbow leaves the roof
# E  open yard         no hall: a roofed furnace on an open steel platform in the yard,
#                      its elbow sweeping to the bag house, brick vault and control house
# F  tapping tower     the open bath on top of a brick tower under a steel headframe,
#                      tapping down the tower's side into a ladle on the ground


def _m_rods(K, bx, by, melt_z, tops, mast_x, mast_z0, arm_z_off=.35):
    zinc, frame = K.mat('f_zinc'), K.mat('f_frame')
    for i in range(3):
        a = math.radians(ROD_ANGLES[i]); rx, ry = bx+ROD_RING*math.cos(a), by+ROD_RING*math.sin(a)
        z1 = tops[i]
        K.cyl(f'm_rod{i}', rx, ry, (melt_z+z1)/2, ROD_R, z1-melt_z, K.mat('e_graphite'), segments=16)
        az = z1-arm_z_off
        K.cyl(f'm_clamp{i}', rx, ry, az, ROD_R+.06, .22, zinc, segments=16)
        K.dirbox(f'm_bracket{i}', (mast_x, by, az), (mast_x, ry, az), .14, .14, frame)
        K.dirbox(f'm_arm{i}', (mast_x-MAST_W/2+.02, ry, az), (rx+ROD_R, ry, az), .11, .13, zinc)
    mt = max(tops)-arm_z_off+.20
    K.box('m_mast', mast_x, by, (mast_z0+mt)/2, MAST_W, MAST_W, mt-mast_z0, frame)
    K.box('m_mast_cap', mast_x, by, mt+.03, MAST_W+.08, MAST_W+.08, .06, zinc)
    return mt


def _m_elbow(K, start, bag_cxy, z_run, r=.19):
    cx, cy = bag_cxy
    K.pipe_run('m_elbow', [start, (start[0], start[1], z_run), (cx, start[1], z_run), (cx, cy, z_run), (cx, cy, BAG_Z[1]+.08)], r, mat=K.mat('white_pipe'), bend=.30)


def _m_tap(K, x, y, z, ladle_xy):
    """A glowing tap opening with its ladle car in front."""
    K.box('m_tap_reveal', x, y-.02, z, .50, .05, .62, K.mat('ink_black'))
    K.box('m_tap_glow', x, y-.01, z-.04, .34, .05, .44, _emissive('e_glow', (1.0, .42, .09), .42))
    _v2_ladles(K, 'm_ladle', *ladle_xy)


def build_eaf_blockout_d(level=2):
    """D: electrode house. A closed hall; the electrodes and their masts stand above the roof."""
    K = _e_begin()
    x0, x1, y0, y1 = -1.70, 1.70, -.80, 1.90
    bx, by = -.10, .55
    eave = 3.20
    _r_pad(K, 'm_pad', -1.4, 2.0, -1.80, y0)
    _r_pad(K, 'm_pad_r', x1, 3.0, -.5, 1.2)
    # Hall with no bay: the roof carries the furnace's crown.
    _m_shop(K, x0, x1, y0, y1, eave, 'x', (bx-.01, bx+.01))
    K.box('m_bay_fill', bx, y0+.04, (BASE_Z+eave)/2, .04, .08, eave-BASE_Z, K.mat('f2_refractory'))
    roof_z = eave+RISE*(1-abs(by-(y0+y1)/2)/((y1-y0)/2))+.06
    # Electrodes through the roof on their masts; a collar where each passes the roof.
    tops = (5.05, 5.45, 5.25)
    for i in range(3):
        a = math.radians(ROD_ANGLES[i]); rx, ry = bx+ROD_RING*math.cos(a), by+ROD_RING*math.sin(a)
        K.washer(f'm_rod_collar{i}', (rx, ry, roof_z+.04), (0, 0, 1), ROD_R-.005, ROD_R+.12, .10, K.mat('f_frame'))
    _m_rods(K, bx, by, roof_z, tops, bx+1.05, roof_z-.02)
    K.box('m_mast_foot', bx+1.05, by, roof_z+.02, .50, .50, .08, K.mat('f_zinc'))
    # Fume elbow out of the roof behind the electrodes, over to the bag house.
    cx, cy = _m_bag(K, 3.00, 3.65, .90, 1.70)
    _m_elbow(K, (bx+.40, by+.95, roof_z-.05), (cx, cy), 4.70, r=.22)
    K.washer('m_elbow_collar', (bx+.40, by+.95, roof_z+.03), (0, 0, 1), .20, .30, .08, K.mat('f_frame'))
    sx, sy = 4.15, 1.75
    K.dircyl('m_flue', (3.65+.02, sy-.15, FLUE_Z), (sx-.31, sy-.15, FLUE_Z), .13, K.mat('white_pipe'), segments=14)
    _m_chimney(K, sx, sy)
    # Vault against the end wall, tubes over its roof into the hall high up.
    _m_block(K, 'm_vault', 1.75, 2.65, -.30, .60, 2.50)
    _m_tubes(K, [(2.30, by, 2.70, 'y'), (2.30, by, 2.95, 'y'), (x1+.01, by, 2.95, 'y')], (x1+.02, by, 2.95, 'x'))
    # Tap hole in the front wall with the ladle; scrap bay with a conveyor into the hall.
    _m_tap(K, .70, y0-.04, .75, (.70, -1.25))
    _m_scrap(K, -2.35, -1.55, -1.40, -.65)
    K.dirbox('m_charge_conveyor', (-1.95, -.90, 1.00), (-1.95, y0-.02, 2.40), .34, .30, K.mat('f_zinc'))
    _v2_flange(K, 'm_charge_collar', -1.95, y0-.03, 2.40, 'y', w=.46, h=.42)
    K.dirbox('m_charge_leg', (-1.95, -.90, .10), (-1.95, -.90, .85), .10, .10, K.mat('f_frame'))
    return _m_finish(K, 'D electrode house')


def build_eaf_blockout_e(level=2):
    """E: open yard. A roofed furnace on an open steel platform, no hall at all."""
    K = _e_begin()
    bx, by = .10, .30
    pz = 1.10
    _r_pad(K, 'm_pad', -1.6, 2.2, -1.80, 1.60)
    _r_pad(K, 'm_pad_r', 2.2, 3.3, -.5, 1.2)
    # Operating platform on dark columns, yellow rails all round, a stair at the left.
    px0, px1, py0, py1 = bx-1.35, bx+1.60, by-.95, by+.95
    K.box('m_platform', (px0+px1)/2, (py0+py1)/2, pz-.04, px1-px0, py1-py0, .08, K.mat('r_deck'))
    for x in (px0+.12, (px0+px1)/2, px1-.12):
        for y in (py0+.12, py1-.12):
            K.dirbox('m_platform_col', (x, y, .06), (x, y, pz-.08), .11, .11, K.mat('f_frame'))
    _r_rail(K, 'm_rail_f', (px0, py0, pz), (px1, py0, pz))
    _r_rail(K, 'm_rail_r', (px1, py0, pz), (px1, py1, pz))
    _r_rail(K, 'm_rail_b', (px0, py1, pz), (px1, py1, pz))
    _r_rail(K, 'm_rail_l', (px0, py0+.55, pz), (px0, py1, pz))
    K.prism('m_stair', (px0-.50, py0+.25, 0), (1, 0), [(-.50, .06), (.50, pz-.06), (.50, pz+.02), (-.50, .14)], .34, K.mat('r_deck'))
    # The furnace: shell, roof dome with the electrodes through it, the fume elbow off the roof.
    rim = pz+.95
    K.cyl('m_pedestal', bx, by, (pz+rim-BOWL_RISE+.12)/2, .42, rim-BOWL_RISE+.12-pz, K.mat('f_frame'), segments=20)
    _e_bowl(K, 'm_shell', bx, by, rim, BOWL_R, BOWL_RISE, BOWL_WALL, K.mat('f_shell'), K.mat('f_oxide'))
    K.cyl('m_roof_ring', bx, by, rim+.05, BOWL_R+.02, .10, K.mat('f_zinc'), segments=28)
    K.dome_cap('m_roof', bx, by, rim+.10, BOWL_R-.02, .34, K.mat('f_shell'), rings=6)
    tops = (3.55, 3.95, 3.75)
    _m_rods(K, bx, by, rim+.30, tops, bx+1.25, pz)
    K.washer('m_elbow_collar', (bx+.55, by+.45, rim+.30), (0, 0, 1), .16, .24, .06, K.mat('f_frame'))
    cx, cy = _m_bag(K, 3.00, 3.65, .80, 1.60)
    _m_elbow(K, (bx+.55, by+.45, rim+.30), (cx, cy), 4.20, r=.19)
    sx, sy = 4.15, 1.65
    K.dircyl('m_flue', (3.65+.02, sy-.15, FLUE_Z), (sx-.31, sy-.15, FLUE_Z), .13, K.mat('white_pipe'), segments=14)
    _m_chimney(K, sx, sy)
    # Brick vault and a two-storey control house behind the platform.
    _m_block(K, 'm_vault', 2.30, 3.10, -.40, .40, 2.20)
    _m_tubes(K, [(2.70, by, 2.40, 'y'), (2.70, by, 2.85, 'y'), (bx+1.25+.16, by, 2.85, 'y')], (bx+1.25+.15, by, 2.85, 'x'))
    _m_block(K, 'm_control', -1.90, -.30, 1.45, 2.45, 2.30)
    # Tap: the spout pours off the platform's front into the ladle below.
    K.rotbox('m_spout', bx+.55, by-.70, rim-.12, .44, .22, .14, K.mat('f_oxide'), 'Z', -60)
    _v2_ladles(K, 'm_ladle', bx+.75, -1.10)
    _m_scrap(K, -2.50, -1.70, -1.30, -.55)
    return _m_finish(K, 'E open yard')


def build_eaf_blockout_f(level=2):
    """F: tapping tower. The open bath crowns a brick tower under a steel headframe."""
    K = _e_begin()
    tx0, tx1, ty0, ty1 = -1.10, 1.10, -.60, 1.50
    th = 2.40
    bx, by = 0.0, .45
    _r_pad(K, 'm_pad', -1.6, 2.4, -1.90, ty1+.2)
    roof = _m_block(K, 'm_tower', tx0, tx1, ty0, ty1, th)
    # Working floor on the tower: black-grey deck, yellow rails, the bath on its pedestal.
    K.box('m_deck', bx, (ty0+ty1)/2, roof+.04, tx1-tx0+.30, ty1-ty0+.30, .08, K.mat('r_deck'))
    dz = roof+.08
    _r_rail(K, 'm_rail_f', (tx0-.15, ty0-.15, dz), (bx-BOWL_R-.1, ty0-.15, dz))
    _r_rail(K, 'm_rail_f2', (bx+BOWL_R+.1, ty0-.15, dz), (tx1+.15, ty0-.15, dz))
    _r_rail(K, 'm_rail_r', (tx1+.15, ty0-.15, dz), (tx1+.15, ty1+.15, dz))
    rim = dz+.95
    K.cyl('m_pedestal', bx, by, (dz+rim-BOWL_RISE+.12)/2, .42, rim-BOWL_RISE+.12-dz, K.mat('f_frame'), segments=20)
    _e_bowl(K, 'm_shell', bx, by, rim, BOWL_R, BOWL_RISE, BOWL_WALL, K.mat('f_shell'), K.mat('f_oxide'))
    melt = _emissive('e_melt', (.95, .32, .02), 1.0)
    K.cyl('m_melt', bx, by, rim-MELT_DROP, _e_melt_radius(), .05, melt, segments=24)
    # Headframe: four dark legs from the ground past the deck to a top frame that carries
    # the electrode arms; the canopy hood hangs from it with the duct to the bag house.
    hz = rim+2.10
    for sx_ in (tx0-.35, tx1+.35):
        for sy_ in (ty0-.30, ty1+.30):
            K.box('m_leg_foot', sx_, sy_, .05, .26, .26, .10, K.mat('f_base'))
            K.dirbox('m_leg', (sx_, sy_, .10), (sx_, sy_, hz), .14, .14, K.mat('f_frame'))
    for sy_ in (ty0-.30, ty1+.30):
        K.dirbox('m_head_beam', (tx0-.35, sy_, hz), (tx1+.35, sy_, hz), .14, .16, K.mat('f_frame'))
    for sx_ in (tx0-.35, tx1+.35):
        K.dirbox('m_head_beam', (sx_, ty0-.30, hz), (sx_, ty1+.30, hz), .14, .16, K.mat('f_frame'))
    tops = (rim+1.05, rim+1.45, rim+1.25)
    _m_rods(K, bx, by, rim-MELT_DROP-.10, tops, tx1+.35, dz)
    K.box('m_hood', bx+.10, by+.30, hz-.30, 1.50, .90, .22, K.mat('f_zinc'))
    cx, cy = _m_bag(K, 2.60, 3.25, .80, 1.60)
    _m_elbow(K, (bx+.75, by+.30, hz-.30), (cx, cy), hz+.10, r=.19)
    sx, sy = 3.75, 1.65
    K.dircyl('m_flue', (3.25+.02, sy-.15, FLUE_Z), (sx-.31, sy-.15, FLUE_Z), .13, K.mat('white_pipe'), segments=14)
    _m_chimney(K, sx, sy)
    # The pour: spout over the tower's front edge, a glowing stream into the ladle below.
    K.rotbox('m_spout', bx+.55, by-.75, rim-.12, .44, .22, .14, K.mat('f_oxide'), 'Z', -60)
    K.box('m_pour', bx+.72, ty0-.45, (rim-.20+.70)/2, .07, .07, rim-.20-.70, melt)
    _v2_ladles(K, 'm_ladle', bx+.72, ty0-.45)
    # Vault on the ground beside the tower, tubes up to the headframe's mast.
    _m_block(K, 'm_vault', 1.60, 2.40, -.55, .25, 2.00)
    _m_tubes(K, [(2.00, by, 2.20, 'y'), (2.00, by, tops[1]-.35, 'y'), (tx1+.35+.16, by, tops[1]-.35, 'y')], (tx1+.35+.15, by, tops[1]-.35, 'x'))
    # Scrap: a skip hoist up the tower's left side from the scrap bay.
    _m_scrap(K, -2.60, -1.80, -1.20, -.45)
    K.dirbox('m_hoist', (-1.45, -.10, .20), (-1.45, -.10, dz+.40), .36, .30, K.mat('f_zinc'))
    K.dirbox('m_hoist_head', (-1.45, -.10, dz+.40), (tx0+.05, -.10, dz+.40), .34, .30, K.mat('f_zinc'))
    return _m_finish(K, 'F tapping tower')
