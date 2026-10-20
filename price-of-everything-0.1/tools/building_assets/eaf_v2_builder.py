"""The electric arc furnace, rebuilt in the catalogue look as the furnace's sibling.

Executed in sprite_kit's namespace after furnace_builder.py, furnace_v2_builder.py,
refinery_v2_builder.py and power_plant_v2_builder.py, whose palette and helpers it shares.
Staged as family 'eaf_v2'; it installs as 'eaf'.

Screen vocabulary at this camera: back = +Y (top-right), right = +X (lower-right),
front = -Y (bottom-left), left = -X (upper-left).

Composition: a refractory-clad melt shop on a brick base course, its ridge along X with a
louvred monitor, and an open charging bay in the long front face. Through the bay: the
furnace on its operating platform (black-grey deck, yellow rails, a stair down into the
yard), an open dark-metal shell with silver water-cooled hoops, the bath glowing, three
graphite electrodes on arms from a mast at the lit side. A brick transformer vault stands
against the shop's right end wall and feeds the mast through three bus tubes. Fume leaves
the shop's end wall high up by a white duct into a bag house on legs, and the cleaned gas
runs on into one thin black-topped brick chimney. Scrap waits in a brick bay at the
front-left under a yellow goliath crane; a ladle car stands in front of the tapping side.

Flows: scrap bay -> crane -> bucket -> bath; vault -> bus tubes -> mast -> arms -> electrodes
-> bath; bath -> spout -> ladle car; fume -> hood -> duct -> bag house -> flue -> chimney;
dust -> hopper -> skip; rain -> gutters -> downpipes -> drains; L3: ladle -> caster -> strand
-> billets.

Fixed across levels: the shop, its eave (solved from the sightlines through the bay), the
furnace, the mast, the chimney and the vault's place. L1 has a small switch kiosk, no bag
house (the duct drops to a ground flue into the chimney) and no crane; L2 adds the full vault,
the bag house and the goliath crane; L3 adds the caster annex with its billet yard, a second
ladle and a wider bag house.
"""
import math
from mathutils import Vector

PALETTE.update({
    'e_graphite': (.030, .032, .036),      # electrodes: blacker than the frame steel
})

EAF_ROLES = {'stair': 'r_deck', 'walkway': 'r_deck', 'handrail': 'r_yellow', 'rail': 'r_yellow',
             'pipe': 'white_pipe', 'duct': 'white_pipe', 'opening': 'ink_black',
             'gear': 'f_frame', 'wall_grey': 'f_base', 'window_frame': 'p_insulator'}

# ---- melt shop -------------------------------------------------------------------------
SHOP = (-2.40, 2.00, -0.30, 1.90)     # x0, x1, y0, y1
BAY = (-1.25, 1.80)                   # the open charging bay in the front wall
BASE_Z = .58                          # brick base course under the cladding, as the furnace's aisle
RISE = .55                            # roof rise; the ridge runs along X
LINTEL_H = .26                        # the bay's head member: the sightline head is its underside
MARGIN = .20

# ---- the furnace ------------------------------------------------------------------------
PLATFORM_Z = .85                      # operating floor
PLATFORM = (-1.25, 1.45, 0.00, 1.40)  # x0, x1, y0, y1
BX, BY = -.10, .40                    # forward in the shop: every unit back costs a unit of eave; left of centre so the mast shows
BOWL_R, BOWL_RISE, BOWL_WALL = .85, .85, .09
RIM_Z = 1.80
MELT_DROP = .16
ROD_R, ROD_RING = .11, .34
# 75/195/315: the three screen columns come out evenly spread (see the old builder's note).
# Index 0 is the back rod and the shortest; index 1 the left rod and the tallest, so its arm
# passes over the front rod's top on the way from the mast.
ROD_ANGLES = (75.0, 195.0, 315.0)
ROD_TOPS = (2.75, 3.25, 2.95)
ROD_SUBMERGE = .10
MAST_X = 1.00                         # beside the furnace on the lit side, clear of its screen width and left of the bay's jamb on screen
MAST_W = .28
ARM_DROP = .35                        # an arm meets its rod this far under the rod top

# ---- plant --------------------------------------------------------------------------
VAULT = (2.05, 2.95, -.30, .60)       # transformer vault against the front half of the shop's end wall
VAULT_H = 2.70
BUS_Z = 3.00                          # bus tubes over the vault roof into the end wall, under the mast cap
BAG = (3.00, 3.65, 1.10, 1.90)        # bag house behind the vault; L3 deepens it toward the front
BAG_Z = (1.50, 3.40)
STACK_XY = (4.20, 1.80)               # one thin chimney right of the bag house, same place at every level
DUCT_Y = 1.45                         # the fume duct leaves the end wall on this line
STACK_TOP = 5.40
FLUE_Z = .95                          # clean-gas flue from the bag house into the chimney base
GROUND_FLUE_Z = .45                   # L1's ground flue
SCRAP = (-2.20, -1.45, -1.40, -.65)   # brick scrap bay, front left
CRANE_Y = -1.00
STAIR_X = -1.00                       # the platform stair climbs through the bay's left edge, clear of the crane leg
LADLE_XY = (.75, -.95)
CASTER = (2.20, 3.30, -1.30, -.45)    # L3 annex, front right; the strand leaves its lit end
CASTER_H = 1.90


def _e_rod_xy(i):
    a = math.radians(ROD_ANGLES[i])
    return BX+ROD_RING*math.cos(a), BY+ROD_RING*math.sin(a)


def _e_melt_radius():
    r_in, rise_in = BOWL_R-BOWL_WALL, BOWL_RISE-BOWL_WALL
    d = MELT_DROP/rise_in
    return r_in*math.sqrt(max(0.0, 1.0-d*d))


def _e_shell_r(z):
    """Outer radius of the shell at height z."""
    d = max(0.0, min(BOWL_RISE, RIM_Z-z))
    return BOWL_R*math.sqrt(max(0.0, 1.0-(d/BOWL_RISE)**2))


def _e_sightline_tests():
    """Everything that has to be seen through the bay, as (name, x, y, z)."""
    rm = _e_melt_radius()
    t = [('melt near lip', BX, BY-rm, RIM_Z-MELT_DROP), ('melt centre', BX, BY, RIM_Z-MELT_DROP),
         ('melt far lip', BX, BY+rm, RIM_Z-MELT_DROP), ('shell far rim', BX, BY+BOWL_R, RIM_Z)]
    for i in range(3):
        rx, ry = _e_rod_xy(i)
        t.append((f'rod {i+1} tip', rx, ry, ROD_TOPS[i]))
    t.append(('mast top', MAST_X, BY+MAST_W/2, max(ROD_TOPS)-ARM_DROP+.20))
    return t


def _e_solve_eave():
    """The lowest eave that shows the bath, every rod tip and the mast through the bay. The
    sightline from an interior point crosses the front wall plane at z + (y - y0): one unit
    of depth costs one unit of height. The bay's head is the lintel's underside."""
    y0 = SHOP[2]
    return max(z+(y-y0) for _, _, y, z in _e_sightline_tests())+MARGIN+LINTEL_H


def _e_check_sightlines(eave):
    head = eave-LINTEL_H
    y0 = SHOP[2]
    out, worst = [], None
    for name, _, y, z in _e_sightline_tests():
        cross = z+(y-y0); margin = head-cross
        out.append('  %-14s crosses the bay plane at z=%.2f head=%.2f margin=%+.2f' % (name, cross, head, margin))
        if worst is None or margin < worst[1]: worst = (name, margin)
    if worst[1] <= 0: raise RuntimeError('EAF sightline buried: %s %+.2f' % worst)
    return out


def _e_begin():
    K = _r_begin('BLDG_eaf_v2')
    ROLES.update(EAF_ROLES)
    _v2_brick_print(K)
    return K


def _e_frustum(K, name, x0, x1, y0, y1, z_top, z_bot, tx, ty, mat):
    """Four-sided hopper: the full rectangle at z_top down to a small centred one at z_bot."""
    cx, cy = (x0+x1)/2, (y0+y1)/2
    top = [(x0, y0), (x1, y0), (x1, y1), (x0, y1)]
    bot = [(cx-tx/2, cy-ty/2), (cx+tx/2, cy-ty/2), (cx+tx/2, cy+ty/2), (cx-tx/2, cy+ty/2)]
    me = bpy.data.meshes.new(name); bm = bmesh.new()
    vt = [bm.verts.new((x, y, z_top)) for x, y in top]; vb = [bm.verts.new((x, y, z_bot)) for x, y in bot]
    for i in range(4):
        j = (i+1) % 4
        bm.faces.new([vt[i], vt[j], vb[j], vb[i]])
    bm.faces.new(list(reversed(vb)))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me); bm.free()
    return K.obj(name, me, mat)


def _e_bowl(K, name, cx, cy, rim_z, r, rise, wall, mat, lip_mat, seg=28, rings=8):
    """Open half-ellipsoid shell with a real wall: outer, inner and the rim annulus between,
    the annulus in the refractory lip material. Never capped."""
    me = bpy.data.meshes.new(name); bm = bmesh.new()

    def shell(rad, ris):
        g = []
        for i in range(rings+1):
            t = (math.pi/2)*i/rings
            rr, dz = rad*math.cos(t), ris*math.sin(t)
            g.append([bm.verts.new((cx+rr*math.cos(2*math.pi*j/seg), cy+rr*math.sin(2*math.pi*j/seg), rim_z-dz)) for j in range(seg)])
        return g
    out, inn = shell(r, rise), shell(r-wall, rise-wall)
    for g in (out, inn):
        for i in range(rings):
            for j in range(seg):
                k = (j+1) % seg
                bm.faces.new([g[i][j], g[i][k], g[i+1][k], g[i+1][j]])
    for j in range(seg):
        k = (j+1) % seg
        bm.faces.new([out[0][j], out[0][k], inn[0][k], inn[0][j]])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me); bm.free()
    ob = K.obj(name, me, mat, True)
    ob.data.materials.append(lip_mat)
    for poly in ob.data.polygons[-seg:]:
        poly.material_index = 1; poly.use_smooth = False
    return ob


# ------------------------------------------------------------------ the melt shop

def _e_shop(K, eave):
    x0, x1, y0, y1 = SHOP
    w, d = x1-x0, y1-y0
    cx, cy = (x0+x1)/2, (y0+y1)/2
    wall, frame, brick = K.mat('f2_refractory'), K.mat('f_frame'), K.mat('f_brick')
    K.box('shop_footing', cx, cy, .08, w+.10, d+.10, .16, K.mat('f_base'))
    K.box('shop_floor', cx, cy, .13, w-.16, d-.16, .02, K.mat('f_base'))
    t = .08

    def slab(nm, sx_, sy_, lx, ly):
        # Brick base course under the cladding, stacked in one plane: nothing buried.
        K.box(nm+'_base', sx_, sy_, (.10+BASE_Z)/2, lx, ly, BASE_Z-.10, brick)
        K.box(nm, sx_, sy_, (BASE_Z+eave)/2, lx, ly, eave-BASE_Z, wall)
    slab('shop_back', cx, y1-t/2, w, t)
    for s, xe in ((-1, x0+t/2), (1, x1-t/2)):
        slab('shop_end'+str(s), xe, cy, t, d-2*t)
    # Front wall: a pier each side of the bay, and the lintel over it.
    bx0, bx1 = BAY
    slab('shop_pier_l', (x0+bx0)/2, y0+t/2, bx0-x0, t)
    slab('shop_pier_r', (bx1+x1)/2, y0+t/2, x1-bx1, t)
    K.box('shop_lintel', (bx0+bx1)/2, y0+.05, eave-LINTEL_H/2, bx1-bx0+.02, .13, LINTEL_H, frame)
    K.box('shop_bay_shadow', (bx0+bx1)/2, y0+t+.02, eave-LINTEL_H-.09, bx1-bx0-.02, .02, .18, K.mat('ink_black'))
    # Dark portal columns on the wall faces, carrying the eave: the bay's jambs, the corners
    # and one per structural bay along the back and the end walls.
    for px in [c for c in (bx0-.045, bx1+.045, x0+.06, x1-.06) if all(abs(c-o) > .15 or c == o for o in (bx0-.045, bx1+.045))]:
        K.box('shop_column_front', px, y0-.03, (.12+eave)/2, .11, .07, eave-.12, frame)
    for px in [x0+.06+(w-.12)*i/4 for i in range(5)]:
        K.box('shop_column_back', px, y1+.03, (.12+eave)/2, .11, .07, eave-.12, frame)
    for s, xe in ((-1, x0-.03), (1, x1+.03)):
        for py in (y0+.06, cy, y1-.06):
            K.box('shop_column_end', xe, py, (.12+eave)/2, .07, .11, eave-.12, frame)
    # Gables over the end walls, and the roof: two standing-seam slopes to the ridge.
    for s, xe in ((-1, x0+t/2), (1, x1-t/2)):
        K.prism('shop_gable'+str(s), (xe, cy, 0), (0, 1), [(-d/2, eave), (0, eave+RISE), (d/2, eave)], t, wall)
    k = RISE/(d/2); o = .09
    for s in (-1, 1):
        ya, yb = (-d/2-o, 0) if s < 0 else (0, d/2+o)
        za, zb = (eave-k*o, eave+RISE) if s < 0 else (eave+RISE, eave-k*o)
        K.prism('shop_roof'+str(s), (cx, cy, 0), (0, 1), [(ya, za), (yb, zb), (yb, zb+.055), (ya, za+.055)], w+.16, K.mat('f_roof'))
    K.dirbox('shop_ridge', (x0-.08, cy, eave+RISE+.04), (x1+.08, cy, eave+RISE+.04), .16, .07, K.mat('f_roof'))
    K._fine_mode = True
    n = max(2, round(w/.26))
    for j in range(n+1):
        px = x0+j*w/n
        for side in (-1, 1):
            K.dirbox('shop_roof_seam', (px, cy+side*(d/2+.06), eave+.05), (px, cy+side*.40, eave+RISE*(1-.40/(d/2))+.06), .012, .012, K.mat('f_roof'))
    K._fine_mode = False
    # Louvred monitor along the ridge: the heat vent of every hot hall.
    mw = w*.70; mz = eave+RISE
    K.box('shop_monitor_base', cx, cy, mz+.06, mw, .44, .12, K.mat('f_roof'))
    K.box('shop_monitor_frame', cx, cy, mz+.26, mw-.06, .34, .30, frame)
    K.prism('shop_monitor_roof', (cx, cy, 0), (0, 1), [(-.25, mz+.39), (0, mz+.53), (.25, mz+.39), (.25, mz+.44), (0, mz+.58), (-.25, mz+.44)], mw+.10, K.mat('f_roof'))
    K._fine_mode = True
    for i in range(4):
        for s in (-1, 1):
            K.box('shop_louvre', cx, cy+s*.18, mz+.15+i*.065, mw-.14, .035, .024, K.mat('f_zinc'))
    K._fine_mode = False
    # Rainwater: gutters on both eaves; the front downpipes drop to drains at the corners,
    # the back one past the vault's end to its own drain.
    for s, gy in ((-1, y0-o-.02), (1, y1+o+.02)):
        K.box('shop_gutter'+str(s), cx, gy, eave-k*o+.02, w+.12, .07, .06, K.mat('silver'))
    _v2_downpipe(K, 'shop_dp_fl', x0+.12, y0-o-.02, eave-k*o, 0.0)
    _v2_downpipe(K, 'shop_dp_fr', x1-.12, y0-o-.02, eave-k*o, 0.0)
    _v2_downpipe(K, 'shop_dp_bl', x0+.12, y1+o+.02, eave-k*o, 0.0)
    # Windows and doors in the catalogue vocabulary, half-size frames. The right end wall
    # carries one window over the bus-tube collars and a door; the back wall three windows,
    # a door and a louvre; the left pier a window and a door.
    K._fine_mode = True
    _pp_window(K, 'shop_window_end', '+X', (x1+.055, 1.35, 2.55), .44, .58, k=.6)
    _pp_window(K, 'shop_window_pier', '-Y', (-1.60, y0-.055, 2.45), .50, .62, k=.6)
    _pp_window(K, 'shop_window_pier_hi', '-Y', (-1.60, y0-.055, 3.55), .50, .50, k=.6)
    for i, wx in enumerate((-1.55, -.45, .65)):
        _pp_window(K, f'shop_window_back{i}', '+Y', (wx, y1+.055, 2.45), .50, .62, k=.6)
    _pp_louvre(K, 'shop_louvre_back', '+Y', (1.45, y1+.03, 3.45), w=.50, h=.42)
    _pp_louvre(K, 'shop_louvre_end', '+X', (x1+.03, .35, 3.55), w=.44, h=.40)
    K._fine_mode = False
    _pp_door(K, 'shop_door_pier', '-Y', (x0+.85, y0-.02, .14+.95/2), .50, .95)
    _pp_door(K, 'shop_door_end', '+X', (x1+.02, 1.35, .14+.95/2), .50, .95)
    _pp_door(K, 'shop_door_back', '+Y', (1.45, y1+.02, .14+.95/2), .50, .95)
    for nm, (sx_, sy_) in (('pier', (x0+.85, y0-.14)), ('end', (x1+.14, 1.35)), ('back', (1.45, y1+.14))):
        K.box('shop_step_'+nm, sx_, sy_, .04, .66 if nm != 'end' else .20, .20 if nm != 'end' else .66, .08, K.mat('stone'))
    # Canopy hood in the roof space over the furnace, with the duct's start at its right end.
    hz = eave-.50
    K.box('hood', BX+.10, BY+.25, hz, 1.60, .90, .22, K.mat('f_zinc'))
    _e_frustum(K, 'hood_throat', BX-.70, BX+.90, BY-.20, BY+.70, hz-.11, hz-.52, 1.10, .50, K.mat('f_zinc'))
    for s in (-1, 1):
        K.dirbox('hood_hanger', (BX+.10+s*.55, BY+.25, hz+.11), (BX+.10+s*.55, BY+.25, eave+.02), .06, .06, frame)
    return dict(eave=eave, hood=(BX+.90, BY+.25, hz))


# ------------------------------------------------------------------ the furnace

def _e_platform(K):
    """Operating platform: black-grey deck on dark columns, yellow rails along the front with
    a gap where the shell overhangs, and a straight stair climbing through the bay's left edge
    from the yard."""
    x0, x1, y0, y1 = PLATFORM
    z = PLATFORM_Z
    deck = K.mat('r_deck'); frame = K.mat('f_frame')
    K.box('platform_deck', (x0+x1)/2, (y0+y1)/2, z-.04, x1-x0, y1-y0, .08, deck)
    K.box('platform_fascia', (x0+x1)/2, y0-.01, z-.09, x1-x0, .03, .12, frame)
    for px in (x0+.12, (x0+x1)/2, x1-.12):
        for py in (y0+.12, y1-.12):
            K.dirbox('platform_column', (px, py, .14), (px, py, z-.08), .09, .09, frame)
    K.dirbox('platform_beam_front', (x0, y0+.12, z-.13), (x1, y0+.12, z-.13), .07, .09, frame)
    # Rails: front edge either side of the shell, and the right end.
    gap0, gap1 = BX-BOWL_R-.06, BX+BOWL_R+.06
    _r_rail(K, 'platform_rail_fl', (x0, y0, z), (gap0, y0, z))
    _r_rail(K, 'platform_rail_fr', (gap1, y0, z), (x1, y0, z))
    _r_rail(K, 'platform_rail_r', (x1, y0, z), (x1, y1, z))
    # The stair: treads from the yard up to the deck at the platform's left end.
    sx = STAIR_X; sw = .30
    foot_y, head_y = -1.05, y0
    n = 9
    for i in range(n):
        f0 = i/n; f1 = (i+1)/n
        ty = foot_y+(head_y-foot_y)*(f0+f1)/2
        tz = .14+(z-.14)*f1
        K.box(f'stair_tread{i}', sx, ty, tz-.015, sw, (head_y-foot_y)/n+.01, .03, deck)
        K.box(f'stair_riser{i}', sx, ty+(head_y-foot_y)/n/2-.005, tz-.015-(z-.14)/n/2, sw-.02, .01, (z-.14)/n, deck)
    for s in (-1, 1):
        K.dirbox(f'stair_stringer{s}', (sx+s*sw/2, foot_y, .10), (sx+s*sw/2, head_y, z-.06), .035, .12, frame)
        K._fine_mode = True
        for j in range(4):
            fj = j/3
            py = foot_y+(head_y-foot_y)*fj; pz = .14+(z-.14)*fj
            K.dircyl(f'stair_post{s}{j}', (sx+s*sw/2, py, pz), (sx+s*sw/2, py, pz+.24), .014, K.mat('r_yellow'), segments=8)
        K.dircyl(f'stair_handrail{s}', (sx+s*sw/2, foot_y, .14+.24), (sx+s*sw/2, head_y, z+.24), .013, K.mat('r_yellow'), segments=8)
        K._fine_mode = False
    K.box('stair_foot', sx, foot_y-.08, .05, sw+.16, .22, .10, K.mat('f_base'))


def _e_furnace(K):
    """The shell on its rocker, the bath, the electrodes and the mast."""
    frame, zinc = K.mat('f_frame'), K.mat('f_zinc')
    # Rocker pedestal through the deck; the shell overhangs it on every side.
    K.cyl('furnace_pedestal', BX, BY, (PLATFORM_Z+RIM_Z-BOWL_RISE+.12)/2, .42, RIM_Z-BOWL_RISE+.12-PLATFORM_Z, frame, segments=24)
    for s in (-1, 1):
        K.cyl(f'furnace_trunnion{s}', BX+s*BOWL_R*.82, BY, RIM_Z-BOWL_RISE*.50, .10, .34, frame, axis='X', segments=14)
    _e_bowl(K, 'furnace_shell', BX, BY, RIM_Z, BOWL_R, BOWL_RISE, BOWL_WALL, K.mat('f_shell'), K.mat('f_oxide'))
    # Water-cooled panel hoops: silver bands proud of the shell, a dark-metal furnace's one
    # bright detail, as on the furnace's shafts.
    K._fine_mode = True
    for z in (1.54, 1.34, 1.14):
        rr = _e_shell_r(z)
        K.washer(f'furnace_hoop{int(z*100)}', (BX, BY, z), (0, 0, 1), rr-.02, rr+.065, .07, zinc)
    K._fine_mode = False
    # Tapping spout at the front right, over the ladle car.
    a = math.radians(-55)
    sx, sy = BX+(BOWL_R-.05)*math.cos(a), BY+(BOWL_R-.05)*math.sin(a)
    K.rotbox('furnace_spout', sx+.16*math.cos(a), sy+.16*math.sin(a), RIM_Z-.10, .42, .22, .14, K.mat('f_oxide'), 'Z', -55)
    K.rotbox('furnace_spout_trough', sx+.18*math.cos(a), sy+.18*math.sin(a), RIM_Z-.04, .36, .12, .04, K.mat('ink_black'), 'Z', -55)
    # The bath.
    melt = _emissive('e_melt', (.95, .32, .02), 1.0)
    melt_z = RIM_Z-MELT_DROP; rm = _e_melt_radius()
    K.cyl('furnace_melt', BX, BY, melt_z, rm, .05, melt, segments=28)
    K.washer('furnace_lining', (BX, BY, melt_z+.012), (0, 0, 1), rm-.07, rm+.085, .036, K.mat('f_oxide'))
    # Electrodes: plain graphite rods with flat ends, sunk under the melt so the pool draws
    # over the cut; silver clamps and the arms back to the mast.
    for i in range(3):
        rx, ry = _e_rod_xy(i); z1 = ROD_TOPS[i]
        K.cyl(f'electrode{i}', rx, ry, (melt_z-ROD_SUBMERGE+z1)/2, ROD_R, z1-(melt_z-ROD_SUBMERGE), K.mat('e_graphite'), segments=20)
        az = z1-ARM_DROP
        K.cyl(f'electrode{i}_clamp', rx, ry, az, ROD_R+.06, .22, zinc, segments=20)
        K._fine_mode = True
        K.washer(f'electrode{i}_ring', (rx, ry, az-.20), (0, 0, 1), ROD_R-.005, ROD_R+.035, .06, zinc)
        K._fine_mode = False
        # Arm: a short bracket from the mast column's face to the rod's line, then the
        # straight arm along -X to the clamp, both with collars at the joints.
        mx = MAST_X-MAST_W/2
        K.dirbox(f'electrode{i}_bracket', (MAST_X, BY, az), (MAST_X, ry, az), .14, .14, frame)
        K.dirbox(f'electrode{i}_arm', (mx+.02, ry, az), (rx+ROD_R, ry, az), .11, .13, zinc)
        K.box(f'electrode{i}_arm_root', mx-.02, ry, az, .10, .20, .20, frame)
    # The mast: a dark square column on the deck, a cap, its own footing through the deck.
    mt = max(ROD_TOPS)-ARM_DROP+.20
    K.box('mast', MAST_X, BY, (PLATFORM_Z+.08+mt)/2, MAST_W, MAST_W, mt-PLATFORM_Z-.08, frame)
    K.box('mast_cap', MAST_X, BY, mt+.03, MAST_W+.08, MAST_W+.08, .06, zinc)
    K.box('mast_base', MAST_X, BY, PLATFORM_Z+.04, MAST_W+.16, MAST_W+.16, .08, zinc)
    # Bus-tube terminals on the mast's back face: the three tubes from the vault end here.
    for k in range(3):
        K.box(f'mast_terminal{k}', MAST_X+.02, BY+(k-1)*.15, BUS_Z, .10, .08, .14, zinc)
    return dict(mast_top=mt)


# ------------------------------------------------------------------ transformer vault

def _e_vault(K, full, step=True):
    """Brick transformer vault against the front half of the shop's end wall: stone coping,
    membrane roof, cooling louvres on its lit faces, a door, and three roof bushings from
    which the bus tubes run over its roof into the shop's end wall, where they end on the
    mast's terminals. L1 has a low switch kiosk in the same place with the same tubes."""
    x0, x1, y0, y1 = VAULT
    x1s = SHOP[1]
    if not full:
        kx0, kx1, ky0, ky1 = x0, x0+.72, y0+.05, y0+.80
        roof = _r_block(K, 'vault', kx0, kx1, ky0, ky1, 1.35, wall='f_brick')
        _pp_door(K, 'vault_door', '-Y', ((kx0+kx1)/2, ky0-.02, .08+.75/2), .40, .75, ribs=3)
        K._fine_mode = True
        _pp_louvre(K, 'vault_louvre', '+X', (kx1+.03, (ky0+ky1)/2, .85), w=.36, h=.30)
        K._fine_mode = False
        bx = (kx0+kx1)/2
    else:
        roof = _r_block(K, 'vault', x0, x1, y0, y1, VAULT_H, wall='f_brick')
        _pp_door(K, 'vault_door', '-Y', (x0+.30, y0-.02, .08+.85/2), .42, .85)
        if step: K.box('vault_step', x0+.30, y0-.14, .04, .56, .20, .08, K.mat('stone'))
        K._fine_mode = True
        for z in (1.05, 2.00):
            _pp_louvre(K, f'vault_louvre{int(z*10)}', '+X', (x1+.03, (y0+y1)/2, z), w=.56, h=.46)
        _pp_louvre(K, 'vault_louvre_front', '-Y', (x1-.28, y0-.03, 1.95), w=.40, h=.40)
        K._fine_mode = False
        bx = x0+.55
    # Roof bushings on the back half of the roof, and the tubes: up, then square along -X
    # into the end wall through collars, then inside to the mast.
    K._fine_mode = True
    for k in range(3):
        py = BY+(k-1)*.15
        K.cyl(f'bus{k}_bushing', bx, py, roof+.11, .055, .22, K.mat('p_insulator'), segments=12)
        K.washer(f'bus{k}_bushing_flange', (bx, py, roof+.02), (0, 0, 1), .06, .11, .04, K.mat('f_frame'), seg=12)
        pts = [(bx, py, roof+.20), (bx, py, BUS_Z), (x1s+.01, py, BUS_Z)]
        K.pipe_run(f'bus{k}', pts, .038, mat=K.mat('f_zinc'), bend=.09)
        _v2_flange(K, f'bus{k}_collar', x1s+.02, py, BUS_Z, 'x', w=.16, h=.16)
        K.dirbox(f'bus{k}_inside', (x1s-.05, py, BUS_Z), (MAST_X+MAST_W/2+.05, py, BUS_Z), .07, .07, K.mat('f_zinc'))
    K._fine_mode = False
    if not full:
        # The kiosk is low, so the tubes rise on a post against the wall before turning in.
        px = bx-.02
        K.dirbox('bus_post', (px, BY+.32, roof+.10), (px, BY+.32, BUS_Z-.06), .06, .06, K.mat('f_frame'))
        K.dirbox('bus_post_arm', (px, BY-.22, BUS_Z-.06), (px, BY+.32, BUS_Z-.06), .05, .05, K.mat('f_frame'))


# ------------------------------------------------------------------ fume plant and chimney

def _e_chimney(K):
    """The one thin black-topped brick chimney, in the same place at every level."""
    sx, sy = STACK_XY
    K.box('stack_footing', sx, sy, .08, .80, .80, .16, K.mat('f_base'))
    K.box('stack_base', sx, sy, .16+.55, .62, .62, 1.10, K.mat('f_brick'))
    K.box('stack_plate', sx, sy, 1.30, .70, .70, .08, K.mat('stone'))
    barrel = STACK_TOP-.24-1.34
    K.cone('stack_barrel', sx, sy, 1.34+barrel/2, .27, .21, barrel, K.mat('f_brick'))
    K.cyl('stack_cap', sx, sy, STACK_TOP-.24+.08, .24, .16, K.mat('f_frame'))
    K.cyl('stack_top', sx, sy, STACK_TOP-.08+.04, .21, .08, K.mat('ink_black'))
    K._fine_mode = True
    for f in (.36, .72):
        z = 1.34+barrel*f; r = .27-.06*f
        K.washer('stack_band', (sx, sy, z), (0, 0, 1), r-.01, r+.035, .07, K.mat('stone'))
    K._fine_mode = False


def _e_fume(K, eave, deep):
    """Fume duct out of the shop's end wall high up, over the vault, into the bag house's lid;
    cleaned gas from the bag house's right face into the chimney base. The bag house is a clad
    filter box on a dark frame with a hopper under it discharging into a skip. L3 deepens it."""
    x1s = SHOP[1]
    dz = eave-.60
    bx0, bx1, by0, by1 = BAG
    if deep: by0 -= .45
    bz0, bz1 = BAG_Z
    cxb = (bx0+bx1)/2
    K.pipe_run('fume_duct', [(x1s-.02, DUCT_Y, dz), (cxb, DUCT_Y, dz), (cxb, DUCT_Y, bz1+.08)], .19, mat=K.mat('white_pipe'), bend=.30)
    _v2_flange(K, 'fume_collar_shop', x1s+.03, DUCT_Y, dz, 'x', w=.50, h=.50)
    K.washer('fume_collar_bag', (cxb, DUCT_Y, bz1+.10), (0, 0, 1), .18, .26, .06, K.mat('f_frame'), seg=20)
    # A post carries the duct between the wall and the bag house.
    px = x1s+(bx0-x1s)*.55
    K.box('fume_post_foot', px, DUCT_Y, .05, .18, .18, .10, K.mat('f_base'))
    K.dirbox('fume_post', (px, DUCT_Y, .10), (px, DUCT_Y, dz-.21), .07, .07, K.mat('f_frame'))
    K.dirbox('fume_saddle', (px, DUCT_Y-.20, dz-.22), (px, DUCT_Y+.20, dz-.22), .08, .05, K.mat('f_frame'))
    # Bag house.
    K.box('bag', cxb, (by0+by1)/2, (bz0+bz1)/2, bx1-bx0, by1-by0, bz1-bz0, K.mat('f2_filter'))
    K.box('bag_lid', cxb, (by0+by1)/2, bz1+.04, bx1-bx0+.10, by1-by0+.10, .08, K.mat('f_roof'))
    K._fine_mode = True
    n = max(4, round((bx1-bx0)/.17))
    for i in range(1, n):
        rx = bx0+(bx1-bx0)*i/n
        K.box(f'bag_rib{i}', rx, by0-.015, (bz0+bz1)/2, .04, .03, bz1-bz0-.08, K.mat('f_frame'))
    m = max(4, round((by1-by0)/.17))
    for j in range(1, m):
        ry = by0+(by1-by0)*j/m
        K.box(f'bag_rib_end{j}', bx1+.015, ry, (bz0+bz1)/2, .03, .04, bz1-bz0-.08, K.mat('f_frame'))
    K._fine_mode = False
    drop = bz0-.62
    tx = max(.34, (bx1-bx0)-2*.42*drop); ty = max(.30, (by1-by0)-2*.42*drop)
    _e_frustum(K, 'bag_hopper', bx0, bx1, by0, by1, bz0+.02, .62, tx, ty, K.mat('f2_filter'))
    K.box('bag_throat', cxb, (by0+by1)/2, .50, tx-.04, ty-.04, .26, K.mat('f_frame'))
    K.box('bag_skip', cxb, (by0+by1)/2, .20, .56, .46, .40, K.mat('f_frame'))
    K.box('bag_skip_dust', cxb, (by0+by1)/2, .38, .46, .36, .06, K.mat('f_base'))
    for sx_ in (bx0+.12, bx1-.12):
        for sy_ in (by0+.12, by1-.12):
            K.box('bag_foot', sx_, sy_, .05, .24, .24, .10, K.mat('f_base'))
            K.dirbox('bag_leg', (sx_, sy_, .10), (sx_, sy_, bz0-.02), .12, .12, K.mat('f_frame'))
    for ry in (by0+.12, by1-.12):
        K.dirbox('bag_beam', (bx0+.06, ry, bz0-.08), (bx1-.06, ry, bz0-.08), .10, .14, K.mat('f_frame'))
    _r_ladder_cage(K, 'bag_ladder', bx0+.30, by0-.05, bz0+.05, bz1+.12, face='-Y')
    # Clean gas: out of the right face low down, straight into the chimney base.
    sx, sy = STACK_XY
    fy = sy-.15
    K.dircyl('clean_flue', (bx1+.02, fy, FLUE_Z), (sx-.31, fy, FLUE_Z), .13, K.mat('white_pipe'), segments=16)
    _v2_flange(K, 'clean_flue_collar', bx1+.03, fy, FLUE_Z, 'x', w=.34, h=.34)
    K.washer('clean_flue_collar_stack', (sx-.32, fy, FLUE_Z), (1, 0, 0), .12, .18, .04, K.mat('f_frame'), seg=16)


def _e_ground_flue(K, eave):
    """L1: the fume duct leaves the end wall, drops to the ground beside the chimney and runs
    into its base as a low flue, as the furnace's L1 does."""
    x1s = SHOP[1]
    dz = eave-.60
    sx, sy = STACK_XY
    dx = sx-.95
    K.pipe_run('fume_duct', [(x1s-.02, DUCT_Y, dz), (dx, DUCT_Y, dz), (dx, DUCT_Y, GROUND_FLUE_Z), (dx, sy-.15, GROUND_FLUE_Z), (sx-.31, sy-.15, GROUND_FLUE_Z)], .17, mat=K.mat('white_pipe'), bend=.28)
    _v2_flange(K, 'fume_collar_shop', x1s+.03, DUCT_Y, dz, 'x', w=.46, h=.46)
    K.washer('fume_collar_stack', (sx-.32, sy-.15, GROUND_FLUE_Z), (1, 0, 0), .16, .22, .04, K.mat('f_frame'), seg=16)
    px = x1s+(dx-x1s)*.5
    K.box('fume_post_foot', px, DUCT_Y, .05, .18, .18, .10, K.mat('f_base'))
    K.dirbox('fume_post', (px, DUCT_Y, .10), (px, DUCT_Y, dz-.19), .07, .07, K.mat('f_frame'))
    K.dirbox('fume_saddle', (px, DUCT_Y-.20, dz-.20), (px, DUCT_Y+.20, dz-.20), .08, .05, K.mat('f_frame'))
    K.box('fume_drop_foot', dx, DUCT_Y, .05, .30, .30, .10, K.mat('f_base'))


# ------------------------------------------------------------------ yard

def _e_scrap_bay(K, crane):
    """Brick scrap bay open to the front, a heap inside, a charging bucket, and from L2 a
    yellow goliath crane over it with its grab."""
    x0, x1, y0, y1 = SCRAP
    h = .95
    brick = K.mat('f_brick')
    K.box('scrap_footing', (x0+x1)/2, (y0+y1)/2, .04, x1-x0+.10, y1-y0+.10, .08, K.mat('f_base'))
    K.box('scrap_wall_back', (x0+x1)/2, y1-.06, .08+h/2, x1-x0, .12, h, brick)
    for s, xe in ((-1, x0+.06), (1, x1-.06)):
        K.box(f'scrap_wall_end{s}', xe, (y0+y1)/2, .08+h/2, .12, y1-y0, h, brick)
        K.box(f'scrap_coping_end{s}', xe, (y0+y1)/2, .08+h+.03, .16, y1-y0+.04, .06, K.mat('stone'))
    K.box('scrap_coping_back', (x0+x1)/2, y1-.06, .08+h+.03, x1-x0+.08, .16, .06, K.mat('stone'))
    # The heap: a mound and a few lumps in the two metals.
    cx, cy = (x0+x1)/2, (y0+y1)/2+.05
    K.dome_cap('scrap_heap', cx, cy, .09, .40, .78, K.mat('f_steel'), rings=6)
    K._fine_mode = True
    for i, (dx, dy, s_, m) in enumerate(((-.22, -.18, .14, 'f_zinc'), (.20, -.22, .12, 'f_frame'), (.05, .22, .16, 'f_zinc'),
                                         (-.28, .14, .11, 'f_frame'), (.26, .10, .10, 'f_zinc'), (0, -.02, .13, 'f_frame'))):
        K.rotbox(f'scrap_lump{i}', cx+dx*.8, cy+dy*.8, .08+s_/2+(.78 if i == 5 else .45), s_*1.6, s_, s_, K.mat(m), 'Z', 20*i)
    K._fine_mode = False
    # Charging bucket on the yard beside the bay, bail up.
    bx, by = -.65, -1.20
    K.cone('bucket', bx, by, .08+.27, .20, .29, .54, K.mat('f_shell'))
    K.cyl('bucket_rim', bx, by, .08+.54+.03, .31, .06, K.mat('f_zinc'), segments=20)
    K.cyl('bucket_inside', bx, by, .08+.54+.062, .26, .01, K.mat('ink_black'), segments=20)
    K._fine_mode = True
    K.washer('bucket_bail', (bx, by, .08+.60), (0, 1, 0), .27, .305, .03, K.mat('f_frame'), seg=20)
    K._fine_mode = False
    if crane:
        # Goliath crane: two dark portal legs outside the bay walls, a yellow bridge girder
        # along X, a trolley, the hoist rope and the grab over the heap.
        z = 2.35
        for s, lx in ((-1, x0-.20), (1, x1+.14)):
            for dy in (-.22, .22):
                K.box(f'crane_foot{s}{dy > 0}', lx, CRANE_Y+dy, .05, .18, .18, .10, K.mat('f_base'))
                K.dirbox(f'crane_leg{s}{dy > 0}', (lx, CRANE_Y+dy, .10), (lx, CRANE_Y+dy*.45, z-.14), .09, .09, K.mat('f_frame'))
            K.dirbox(f'crane_cross{s}', (lx, CRANE_Y-.20, z-.14), (lx, CRANE_Y+.20, z-.14), .12, .12, K.mat('f_frame'))
        K.dirbox('crane_bridge', (x0-.30, CRANE_Y, z), (x1+.30, CRANE_Y, z), .18, .16, K.mat('r_yellow'))
        K.box('crane_trolley', cx+.10, CRANE_Y, z+.14, .34, .32, .14, K.mat('f_frame'))
        K._fine_mode = True
        K.dircyl('crane_rope', (cx+.10, CRANE_Y, z-.08), (cx+.10, CRANE_Y, .08+.42+.30), .018, K.mat('f_frame'), segments=6)
        K._fine_mode = False
        K.box('crane_grab_head', cx+.10, CRANE_Y, .08+.42+.24, .22, .22, .14, K.mat('f_frame'))
        for k in range(4):
            a = math.radians(45+90*k)
            K.dirbox(f'crane_tine{k}', (cx+.10, CRANE_Y, .08+.42+.18), (cx+.10+.20*math.cos(a), CRANE_Y+.20*math.sin(a), .08+.42-.02), .05, .05, K.mat('f_frame'))


def _e_ladle_car(K, name, x, y):
    """The furnace family's ladle car, lifted on to the apron's top."""
    before = {ob.name for ob in K.col.objects}
    _v2_ladles(K, name, x, y)
    for ob in K.col.objects:
        if ob.name not in before: ob.location.z += .06


def _e_caster(K):
    """L3: a brick caster annex with a membrane roof at the front right, the glowing strand
    leaving its lit end wall on rollers, and cut billets stacked beside it."""
    x0, x1, y0, y1 = CASTER
    roof = _r_block(K, 'caster', x0, x1, y0, y1, CASTER_H, wall='f_brick')
    K._fine_mode = True
    _pp_window(K, 'caster_window_a', '-Y', ((x0+x1)/2-.22, y0-.055, 1.15), .40, .50, k=.6)
    _pp_window(K, 'caster_window_b', '-Y', ((x0+x1)/2+.22, y0-.055, 1.15), .40, .50, k=.6)
    _pp_louvre(K, 'caster_louvre', '+X', (x1+.03, (y0+y1)/2-.22, 1.40), w=.36, h=.32)
    K._fine_mode = False
    _pp_door(K, 'caster_door', '-Y', (x1-.30, y0-.02, .08+.85/2), .42, .85)
    K.box('caster_vent', (x0+x1)/2, (y0+y1)/2, roof+.12, .26, .26, .24, K.mat('silver'))
    K.box('caster_vent_cap', (x0+x1)/2, (y0+y1)/2, roof+.26, .32, .32, .04, K.mat('f_frame'))
    # The strand leaves the end wall on rollers and runs out along X; billets beside it.
    sy = y0+.70
    strand = _emissive('e_strand', (1.0, .20, .055), .34)
    _v2_flange(K, 'strand_collar', x1+.03, sy, .46, 'x', w=.26, h=.26)
    K.box('strand', x1+.46, sy, .46, .86, .24, .08, strand)
    for k in range(5):
        K.cyl(f'strand_roller{k}', x1+.14+k*.19, sy, .36, .08, .32, K.mat('f_frame'), axis='Y', segments=12)
    K.box('strand_bed', x1+.48, sy, .22, .92, .40, .04, K.mat('f_base'))
    for r in range(2):
        for c in range(3):
            K.box(f'billet{r}{c}', x1+.45, sy+.40+c*.14, .06+.06+r*.12, .85, .12, .12, K.mat('f_zinc'))


# ------------------------------------------------------------------ build

def build_eaf_v2(level=1):
    assert level in (1, 2, 3)
    K = _e_begin()
    eave = _e_solve_eave()
    report = _e_check_sightlines(eave)
    # Paving follows the plant as an L, never to a far corner: the sprite's width is a budget.
    _r_pad(K, 'site_pad_front', -1.40, SHOP[1], -1.75, SHOP[2])
    _r_pad(K, 'site_pad_vault', SHOP[1], VAULT[1]+.15, VAULT[2]-.20, 1.00)
    _r_pad(K, 'site_pad_bag', BAG[0]-.10, STACK_XY[0]+.42, .95, STACK_XY[1]+.42)
    if level == 3:
        _r_pad(K, 'site_pad_caster', SHOP[1], CASTER[1]+.12, CASTER[2]-.20, VAULT[2]-.20)
    _e_shop(K, eave)
    _e_platform(K)
    _e_furnace(K)
    _e_vault(K, full=level >= 2, step=level < 3)
    if level >= 2:
        _e_fume(K, eave, deep=level == 3)
    else:
        _e_ground_flue(K, eave)
    _e_chimney(K)
    _e_scrap_bay(K, crane=level >= 2)
    _e_ladle_car(K, 'ladle', LADLE_XY[0], LADLE_XY[1])
    if level == 3:
        _e_ladle_car(K, 'ladle_b', LADLE_XY[0]+.75, LADLE_XY[1]-.10)
        _e_caster(K)
    print('\n'.join(['SIGHTLINES (eave %.2f):' % eave]+report))
    result = _r_finish(K, level, 'eaf v2: refractory melt shop with open bay, furnace on its platform, vault, bag house, chimney, scrap bay')
    result.update(eave=round(eave, 3))
    return result
