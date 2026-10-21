"""The electric arc furnace in the catalogue look: the furnace in its chamber.

Executed in sprite_kit's namespace after furnace_builder.py, furnace_v2_builder.py,
refinery_v2_builder.py and power_plant_v2_builder.py, whose palette and helpers it shares.
Staged as family 'eaf_v2'; it installs as 'eaf'.

Screen vocabulary at this camera: back = +Y (top-right), right = +X (lower-right),
front = -Y (bottom-left), left = -X (upper-left).

Composition (owner, 20 and 21 October 2026): the furnace inside a process chamber with an
open portal front under a single slanted roof plane, high at the opening and dropping to the
back, so the opening stays tall and little roof shows. The bowl is large and low, with the
operating deck raised around it and a stair down into the yard; the electrodes stand over it
on arms from a dark mast. Brick side walls with windows. On the left a brick transformer
house set back, merged with the rear storage range into an L, and a switchyard of large
transformers in front of it under an overhead line into the house's wall bushings. On the
right a bag house that reads as a filter (plain clad box, flanged inlet, top walkway, fan on
the lid) and a tall modern steel stack at the back. Scrap arrives in a closed receiving bin
on the covered conveyor into the storage wing, because an EAF takes many inputs. The spout
tips into a launder over the deck edge into the ladle car.

Flows: receiving bin -> conveyor -> storage wing; silos -> wing; wing -> elevator -> gallery
-> chute -> bath; transformers -> droppers -> line -> house bushings -> bus tubes -> mast ->
arms -> electrodes -> bath; bath -> spout -> launder -> ladle car; fume -> hood -> duct ->
bag house (in at the side) -> fan (out at the top) -> flue -> stack; dust -> hopper -> rotary
valve -> bin; rain -> gutters -> downpipes -> drains.

Fixed across levels: chamber, house, furnace and mast, storage tower, stack. L1: one
transformer, short bunker, ground flue. L2: storage wing, two silos, bag house, conveyor,
two transformers. L3: third silo and transformer, second ladle, deeper bag house.
"""
import math
from mathutils import Vector

PALETTE.update({
    'e_graphite': (.030, .032, .036),      # electrodes: blacker than the frame steel
})

EAF_ROLES = {'stair': 'r_deck', 'walkway': 'r_deck', 'handrail': 'r_yellow', 'rail': 'r_yellow',
             'pipe': 'white_pipe', 'duct': 'white_pipe', 'opening': 'ink_black',
             'gear': 'f_frame', 'wall_grey': 'f_base', 'window_frame': 'p_insulator'}

# ---- the building --------------------------------------------------------------------
HALL = (-1.20, 2.55, -.90, 1.60)      # x0, x1, y0, y1 of the process chamber
EAVE_F, EAVE_B = 4.30, 3.10           # the slanted roof: high at the open front, low at the back
LINTEL_H = .26                        # the dark fascia across the open front; the sightline head is its underside
WIN_ROWS = (1.75, 2.70)               # two rows of two windows on the chamber's right wall, between its columns
WIN_YS = (-.25, .95)                  # the bays between the right wall's three columns
TXHOUSE = (-2.80, -1.20, .20, 2.90)   # the L's left leg: the transformer house
STORE = (-1.20, 1.90, 1.70, 2.90)     # the L's back leg: the store
L_EAVE, L_RISE = 3.40, .50            # one roof over both legs, two gable runs meeting in valleys
LINE_Z = 2.50                         # overhead three-phase line over the switchyard into the house's wall bushings
TX_YARD = (-2.70, -1.30, -1.48, .00)  # switchyard in front of the house
TX_X = -2.02                          # the transformers stand in a row along Y on this line

# ---- the furnace ------------------------------------------------------------------------
BX, BY = .15, -.10                    # large and low, forward in the chamber
BOWL_R, BOWL_RISE, BOWL_WALL = 1.10, 1.00, .10
RIM_Z = 1.55
MELT_DROP = .16
DECK_Z = 1.15                         # the operating deck raised round the bowl
PLATFORM = (-1.10, 2.05, -1.45, 1.45) # the deck's outer rectangle; the hole follows the shell
ROD_R, ROD_RING = .12, .45
ROD_ANGLES = (75.0, 195.0, 315.0)
ROD_TOPS = (2.55, 3.05, 2.80)
ROD_SUBMERGE = .10
MAST_X = 1.42                         # right of the shell; its x+y must stay under the right jamb's, or the wall hides it
MAST_W = .28
ARM_DROP = .35
STAIR_X = -.95
BUS_Z = 3.45                          # bus tubes from the chamber's left wall across to the mast

# ---- plant --------------------------------------------------------------------------
HOOD_XY = (BX+.60, BY+1.00)           # hood at the back of the rim; the duct rises through the roof
DUCT_Z = 4.60                         # the duct runs over the chamber roof's right edge
BAG = (2.62, 3.22, 1.85, 2.65)        # bag house at the back right, behind the stack
BAG_Z = (1.50, 3.00)
FLUE_Z = 4.10                         # clean-gas flue from the fan forward into the stack's back
DUCT_DROP_X = 3.00                    # the duct drops outside the chamber's right wall, clear of the elevator
GROUND_FLUE_Z = .45
STACK_XY = (3.65, 1.00)               # one tall steel stack at the front right, same place at every level
STACK_TOP = 7.20
TANK_XY = (2.10, 3.35)                # the cooling-water tower at the back, its tank above the bag house (L2, L3)
ELEV_XY = (2.90, .35)                 # bucket elevator outside the chamber's right wall, clear of the duct
ELEV_TOP = 4.60
CHUTE_XY = (-.55, .35)                # chute house on the roof over the bath, left of the electrodes
BIN_XY = (2.90, -1.15)                # closed receiving bin at the conveyor's foot
CONVEYOR_X = 2.90
LADLE_XY = (BX, -1.95)                # under the launder


def _e_rod_xy(i):
    a = math.radians(ROD_ANGLES[i])
    return BX+ROD_RING*math.cos(a), BY+ROD_RING*math.sin(a)


def _e_melt_radius():
    r_in, rise_in = BOWL_R-BOWL_WALL, BOWL_RISE-BOWL_WALL
    d = MELT_DROP/rise_in
    return r_in*math.sqrt(max(0.0, 1.0-d*d))


def _e_shell_r(z):
    d = max(0.0, min(BOWL_RISE, RIM_Z-z))
    return BOWL_R*math.sqrt(max(0.0, 1.0-(d/BOWL_RISE)**2))


def _e_roof_z(y):
    """Top of the chamber's slanted roof at y: high at the open front, low at the back."""
    x0, x1, y0, y1 = HALL
    return EAVE_F+(EAVE_B-EAVE_F)*(y-y0)/(y1-y0)+.06


def _e_sightline_tests():
    rm = _e_melt_radius()
    t = [('melt far lip', BX, BY+rm, RIM_Z-MELT_DROP), ('shell far rim', BX, BY+BOWL_R, RIM_Z)]
    for i in range(3):
        rx, ry = _e_rod_xy(i); t.append((f'rod {i+1} tip', rx, ry, ROD_TOPS[i]))
    t.append(('mast top', MAST_X, BY+MAST_W/2, max(ROD_TOPS)-ARM_DROP+.22))
    return t


def _e_check_sightlines():
    """Every point the owner wants seen must cross the front plane under the fascia: with a
    roof that drops toward the back, the front eave alone decides it."""
    head = EAVE_F-LINTEL_H; y0 = HALL[2]
    for name, _, y, z in _e_sightline_tests():
        if z+(y-y0) >= head: raise RuntimeError('EAF sightline buried: %s crosses at %.2f, head %.2f' % (name, z+(y-y0), head))
    jamb = HALL[1]-.06+y0
    if MAST_X+MAST_W/2+BY >= jamb: raise RuntimeError('EAF mast hidden behind the right wall: x+y %.2f, jamb %.2f' % (MAST_X+MAST_W/2+BY, jamb))


def _e_begin():
    K = _r_begin('BLDG_eaf_v2')
    ROLES.update(EAF_ROLES)
    _v2_brick_print(K)
    return K


def _e_frustum(K, name, x0, x1, y0, y1, z_top, z_bot, tx, ty, mat):
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


def _e_bent_gallery_y(K, name, path, x, half_w, half_h, mat):
    """A rectangular conveyor gallery along a polyline in the YZ plane at fixed x, one mesh
    with mitred bends."""
    P = [Vector((0, y, z)) for y, z in path]

    def normal(a, b):
        d = (b-a).normalized(); return Vector((0, -d.z, d.y))
    rings = []
    for i, p in enumerate(P):
        if i == 0: m = normal(P[0], P[1]); sc = 1.0
        elif i == len(P)-1: m = normal(P[-2], P[-1]); sc = 1.0
        else:
            n0, n1 = normal(P[i-1], p), normal(p, P[i+1])
            m = (n0+n1).normalized(); sc = 1.0/m.dot(n0)
        o = m*half_h*sc
        rings.append([(x-half_w, p.y-o.y, p.z-o.z), (x+half_w, p.y-o.y, p.z-o.z),
                      (x+half_w, p.y+o.y, p.z+o.z), (x-half_w, p.y+o.y, p.z+o.z)])
    verts = [v for r in rings for v in r]; faces = []
    for i in range(len(rings)-1):
        a, b = 4*i, 4*(i+1)
        for k in range(4):
            faces.append((a+k, a+(k+1) % 4, b+(k+1) % 4, b+k))
    faces.append((3, 2, 1, 0)); n = 4*(len(rings)-1); faces.append((n, n+1, n+2, n+3))
    mesh = bpy.data.meshes.new(name); mesh.from_pydata(verts, [], faces); mesh.update()
    bm = bmesh.new(); bm.from_mesh(mesh); bmesh.ops.recalc_face_normals(bm, faces=bm.faces); bm.to_mesh(mesh); bm.free()
    return K.obj(name, mesh, K.mat(mat))


# ------------------------------------------------------------------ the buildings

def _e_l_building(K):
    """One L-shaped brick building behind and beside the chamber: the transformer house as
    the left leg and the store as the back leg, under one roof of two gable runs at the same
    ridge height meeting in valleys at the inside corner. The house's front carries two tall
    dark-iron louvred bays, a roller door for transformer access, a row of high windows and
    three porcelain wall bushings where the overhead line lands; the store's lit end carries a
    door and windows."""
    ax0, ax1, ay0, ay1 = TXHOUSE
    bx0, bx1, by0, by1 = STORE
    E, R = L_EAVE, L_EAVE+L_RISE
    brick, frame = K.mat('f_brick'), K.mat('f_frame')
    t = .16
    K.box('l_footing_a', (ax0+ax1)/2, (ay0+ay1)/2, .08, ax1-ax0+.10, ay1-ay0+.10, .16, K.mat('f_base'))
    K.box('l_footing_b', (bx0+bx1)/2, (by0+by1)/2, .08, bx1-bx0+.10, by1-by0+.10, .16, K.mat('f_base'))
    K.box('l_walls_a', (ax0+ax1)/2, (ay0+ay1)/2, (.10+E)/2, ax1-ax0, ay1-ay0, E-.10, brick)
    K.box('l_walls_b', (bx0+bx1)/2, (by0+by1)/2, (.10+E)/2, bx1-bx0, by1-by0, E-.10, brick)
    # Gables: the house's front and back, the store's lit end.
    xr = (ax0+ax1)/2; yr = (by0+by1)/2
    for nm, gy in (('l_gable_front', ay0+t/2), ('l_gable_back', ay1-t/2)):
        K.prism(nm, (xr, gy, 0), (1, 0), [(-(ax1-ax0)/2, E), (0, R), ((ax1-ax0)/2, E)], t, brick)
    K.prism('l_gable_end', (bx1-t/2, yr, 0), (0, 1), [(-(by1-by0)/2, E), (0, R), ((by1-by0)/2, E)], t, brick)
    # Roofs: the house's ridge along Y, the store's ridge along X, both at R; the store's
    # roof runs into the house's slope and emerges from it, which is the L's valley.
    o = .09
    ka = L_RISE/((ax1-ax0)/2); kb = L_RISE/((by1-by0)/2)
    prof_a = [(ax0-o-xr, E-ka*o), (0, R), (ax1+o-xr, E-ka*o), (ax1+o-xr, E-ka*o+.055), (0, R+.055), (ax0-o-xr, E-ka*o+.055)]
    K.prism('l_roof_a', (xr, (ay0+ay1)/2, 0), (1, 0), prof_a, ay1-ay0+.16, K.mat('f_roof'))
    prof_b = [(by0-o-yr, E-kb*o), (0, R), (by1+o-yr, E-kb*o), (by1+o-yr, E-kb*o+.055), (0, R+.055), (by0-o-yr, E-kb*o+.055)]
    K.prism('l_roof_b', ((xr+bx1+.08)/2, yr, 0), (0, 1), prof_b, bx1+.08-xr, K.mat('f_roof'))
    K.dirbox('l_ridge_a', (xr, ay0-.08, R+.04), (xr, ay1+.08, R+.04), .16, .07, K.mat('f_roof'))
    K.dirbox('l_ridge_b', (xr, yr, R+.04), (bx1+.08, yr, R+.04), .16, .07, K.mat('f_roof'))
    # Valley flashings where the store's slopes meet the house's slope.
    # Wide valley flashings: the two roof slabs cross here and their outline shells would
    # otherwise show a ragged seam in the 3D view.
    K.dirbox('l_valley_front', (ax1+.08, by0-.08, E+.03), (xr, yr, R+.05), .22, .08, frame)
    K.dirbox('l_valley_back', (xr, yr, R+.05), (ax1+.08, by1+.08, E+.03), .22, .08, frame)
    K._fine_mode = True
    for j in range(1, 9):
        py = ay0+(ay1-ay0)*j/9
        K.dirbox('l_roof_seam_a', (ax1+.06, py, E+.01), (xr+.30, py, R-ka*.30+.01), .012, .012, K.mat('f_roof'))
    for j in range(1, 9):
        px = xr+.40+(bx1-xr-.40)*j/9
        K.dirbox('l_roof_seam_b', (px, by0-.06, E+.01), (px, yr-.30, R-kb*.30+.01), .012, .012, K.mat('f_roof'))
    K._fine_mode = False
    # Rainwater: gutters on the eaves that show, downpipes to drains.
    K.box('l_gutter_a', ax1+.10, (ay0+by0)/2, E-ka*o+.02, .07, by0-ay0+.12, .06, K.mat('silver'))
    K.box('l_gutter_b', (ax1+bx1)/2, by0-.10, E-kb*o+.02, bx1-ax1+.12, .07, .06, K.mat('silver'))
    K.box('l_gutter_w', ax0-.10, (ay0+ay1)/2, E-ka*o+.02, .07, ay1-ay0+.12, .06, K.mat('silver'))
    _v2_downpipe(K, 'l_dp_front', ax1+.10, ay0+.12, E-ka*o, 0.0)
    _v2_downpipe(K, 'l_dp_end', bx1+.10, by0-.10, E-kb*o, 0.0)
    _v2_downpipe(K, 'l_dp_west', ax0-.10, ay0+.12, E-ka*o, 0.0)
    # The house front: louvred bays, roller door, high windows, wall bushings.
    f = ay0
    for i, lx in enumerate((ax0+.40, ax0+1.00)):
        K.box(f'txhouse_louvre{i}_frame', lx, f-.02, 1.95, .46, .04, 1.40, frame)
        K._fine_mode = True
        for j in range(8):
            K.box(f'txhouse_louvre{i}_blade', lx, f-.045, 1.36+j*.17, .38, .012, .05, K.mat('f_zinc'))
        K._fine_mode = False
        K.box(f'txhouse_louvre{i}_sill', lx, f-.03, 1.22, .54, .06, .06, K.mat('stone'))
    _pp_door(K, 'txhouse_roller', '-Y', (ax1-.42, f-.01, .14+1.20/2), .66, 1.20, ribs=6)
    K._fine_mode = True
    for i, lx in enumerate((ax0+.40, ax0+1.00, ax1-.42)):
        _pp_window(K, f'txhouse_window{i}', '-Y', (lx, f-.015, 2.85), .36, .40, k=.6)
    for k in range(3):
        px = TX_X+(k-1)*.20
        K.cyl(f'txhouse_bushing{k}', px, f-.12, LINE_Z, .055, .24, K.mat('p_insulator'), axis='Y', segments=12)
        K.washer(f'txhouse_bushing{k}_flange', (px, f-.01, LINE_Z), (0, 1, 0), .06, .11, .04, frame, seg=12)
    # The store's lit end: a door and two windows.
    _pp_window(K, 'store_window0', '+X', (bx1+.055, yr+.30, 1.40), .40, .50, k=.6)
    _pp_window(K, 'store_window1', '+X', (bx1+.055, yr+.30, 2.50), .40, .50, k=.6)
    K._fine_mode = False
    _pp_door(K, 'store_door', '+X', (bx1+.02, yr-.30, .14+.90/2), .46, .90)
    K.box('store_step', bx1+.14, yr-.30, .04, .20, .60, .08, K.mat('stone'))
    K.door('txhouse_rear_door', '-X', (ax0-.02, (ay0+ay1)/2+.40, .55), .50, .90)


def _e_house(K):
    """The process chamber: brick side walls under the roof's fall, brick back wall, the open
    front under a dark fascia with dark jamb columns, and one slanted roof plane."""
    x0, x1, y0, y1 = HALL
    d = y1-y0; cy = (y0+y1)/2
    brick, frame = K.mat('f_brick'), K.mat('f_frame')
    K.box('house_footing', (x0+x1)/2, cy, .08, x1-x0+.10, d+.10, .16, K.mat('f_base'))
    K.box('house_floor', (x0+x1)/2, cy, .13, x1-x0-.16, d-.16, .02, K.mat('f_base'))
    _e_l_building(K)
    t = .16
    K.box('chamber_back', (x0+x1)/2, y1-t/2, (.10+EAVE_B)/2, x1-x0, t, EAVE_B-.10, brick)
    for nm, xe in (('chamber_left', x0+t/2), ('chamber_right', x1-t/2)):
        K.prism(nm, (xe, 0, 0), (0, 1), [(y0, .10), (y1, .10), (y1, EAVE_B), (y0, EAVE_F)], t, brick)
    K.box('chamber_fascia', (x0+x1)/2, y0+.06, EAVE_F-LINTEL_H/2, x1-x0+.02, .14, LINTEL_H, frame)
    K.box('chamber_bay_shadow', (x0+x1)/2, y0+t+.02, EAVE_F-LINTEL_H-.09, x1-x0-.02, .02, .18, K.mat('ink_black'))
    for px in (x0+.06, x1-.06):
        K.box('chamber_column', px, y0-.03, (.12+EAVE_F)/2, .11, .07, EAVE_F-.12, frame)
    for py in (y0+.06, cy, y1-.06):
        K.box('chamber_column_end', x1+.03, py, (.12+_e_roof_z(py)-.10)/2, .07, .11, _e_roof_z(py)-.22, frame)
    k = (EAVE_F-EAVE_B)/d; o = .10
    rx0, rx1 = x0-.10, x1+.10
    K.prism('chamber_roof', ((rx0+rx1)/2, 0, 0), (0, 1), [(y0-o, EAVE_F+k*o), (y1+o, EAVE_B-k*o), (y1+o, EAVE_B-k*o+.06), (y0-o, EAVE_F+k*o+.06)], rx1-rx0, K.mat('f_roof'))
    K._fine_mode = True
    n = max(2, round((rx1-rx0)/.26))
    for j in range(1, n):
        px = rx0+j*(rx1-rx0)/n
        K.dirbox('chamber_roof_seam', (px, y0-.02, _e_roof_z(y0-.02)+.012), (px, y1+.02, _e_roof_z(y1+.02)+.012), .012, .012, K.mat('f_roof'))
    K.dirbox('chamber_roof_beam_front', (x0, y0+.22, EAVE_F-k*.22-.10), (x1, y0+.22, EAVE_F-k*.22-.10), .08, .12, frame)
    K._fine_mode = False
    K.box('chamber_gutter', (rx0+rx1)/2, y1+o+.03, EAVE_B-k*o+.02, rx1-rx0+.04, .07, .06, K.mat('silver'))
    _v2_downpipe(K, 'chamber_dp', x1-.12, y1+o+.03, EAVE_B-k*o, 0.0)
    K._fine_mode = True
    for r, wz in enumerate(WIN_ROWS):
        for c, wy in enumerate(WIN_YS):
            _pp_window(K, f'chamber_window{r}{c}', '+X', (x1+.055, wy, wz), .40, .55, k=.6)
    _pp_louvre(K, 'chamber_louvre_end', '+X', (x1+.03, .95, 3.45), w=.44, h=.34)
    K._fine_mode = False
    _pp_door(K, 'chamber_door_end', '+X', (x1+.02, -.25, .14+.95/2), .50, .95)
    K.box('chamber_step_end', x1+.14, -.25, .04, .20, .66, .08, K.mat('stone'))


# ------------------------------------------------------------------ the furnace

def _e_platform(K):
    """The operating deck raised round the bowl: a black-grey annular floor whose hole
    follows the shell, on dark columns, yellow rails on its open edges, and a straight stair
    from the yard up to its front edge."""
    x0, x1, y0, y1 = PLATFORM
    z = DECK_Z
    deck, frame = K.mat('r_deck'), K.mat('f_frame')
    n = 32
    outer = [(p[0], p[1]) for p in Kit.poly_rect(x0, x1, y0, y1, n)]
    start = min(range(n), key=lambda j: math.hypot(outer[j][0]-x0, outer[j][1]-y0))
    outer = outer[start:]+outer[:start]
    hole_r = BOWL_R+.08
    a0 = math.atan2(y0-BY, x0-BX)
    inner = [(BX+hole_r*math.cos(a0+2*math.pi*j/n), BY+hole_r*math.sin(a0+2*math.pi*j/n)) for j in range(n)]
    K.poly_ring('platform_deck', outer, inner, z-.08, z, deck)
    K.box('platform_fascia_f', (x0+x1)/2, y0-.01, z-.09, x1-x0, .03, .12, frame)
    K.box('platform_fascia_r', x1+.01, (y0+y1)/2, z-.09, .03, y1-y0, .12, frame)
    for px in (x0+.12, x1-.12):
        for py in (y0+.12, (y0+y1)/2, y1-.12):
            K.dirbox('platform_column', (px, py, .14), (px, py, z-.08), .09, .09, frame)
    for py in (y0+.12, y1-.12):
        K.dirbox('platform_column', (x1-.90, py, .14), (x1-.90, py, z-.08), .09, .09, frame)
    _r_rail(K, 'platform_rail_f', (x0, y0, z), (x1, y0, z))
    _r_rail(K, 'platform_rail_r', (x1, y0, z), (x1, y1, z))
    sx = STAIR_X; sw = .30
    foot_y, head_y = y0-1.10, y0
    steps = 9
    for i in range(steps):
        f1 = (i+1)/steps
        ty = foot_y+(head_y-foot_y)*(i+.5)/steps
        tz = .14+(z-.14)*f1
        K.box(f'stair_tread{i}', sx, ty, tz-.015, sw, (head_y-foot_y)/steps+.01, .03, deck)
        K.box(f'stair_riser{i}', sx, ty+(head_y-foot_y)/steps/2-.005, tz-.015-(z-.14)/steps/2, sw-.02, .01, (z-.14)/steps, deck)
    for s_ in (-1, 1):
        K.dirbox(f'stair_stringer{s_}', (sx+s_*sw/2, foot_y, .10), (sx+s_*sw/2, head_y, z-.06), .035, .12, frame)
        K._fine_mode = True
        for j in range(4):
            fj = j/3
            py = foot_y+(head_y-foot_y)*fj; pz = .14+(z-.14)*fj
            K.dircyl(f'stair_post{s_}{j}', (sx+s_*sw/2, py, pz), (sx+s_*sw/2, py, pz+.24), .014, K.mat('r_yellow'), segments=8)
        K.dircyl(f'stair_handrail{s_}', (sx+s_*sw/2, foot_y, .14+.24), (sx+s_*sw/2, head_y, z+.24), .013, K.mat('r_yellow'), segments=8)
        K._fine_mode = False
    K.box('stair_foot', sx, foot_y-.08, .05, sw+.16, .22, .10, K.mat('f_base'))


def _e_furnace(K):
    """The large low shell on its rocker, the bath, the spout and launder, the electrodes
    on arms from the mast, the hood."""
    frame, zinc = K.mat('f_frame'), K.mat('f_zinc')
    base = .14
    K.cyl('furnace_pedestal', BX, BY, (base+RIM_Z-BOWL_RISE+.14)/2, .50, RIM_Z-BOWL_RISE+.14-base, frame, segments=24)
    for s_ in (-1, 1):
        K.cyl(f'furnace_trunnion{s_}', BX+s_*BOWL_R*.84, BY, RIM_Z-BOWL_RISE*.50, .10, .34, frame, axis='X', segments=14)
    _e_bowl(K, 'furnace_shell', BX, BY, RIM_Z, BOWL_R, BOWL_RISE, BOWL_WALL, K.mat('f_shell'), K.mat('f_oxide'))
    K._fine_mode = True
    for z in (RIM_Z-.20, RIM_Z-.34):
        rr = _e_shell_r(z)
        K.washer(f'furnace_hoop{int(z*100)}', (BX, BY, z), (0, 0, 1), rr-.02, rr+.065, .07, zinc)
    K._fine_mode = False
    # Spout at the front of the rim, and a launder over the deck's front edge to the ladle.
    sy = BY-BOWL_R
    K.box('furnace_spout', BX, sy-.02, RIM_Z-.10, .34, .30, .14, K.mat('f_oxide'))
    ly0, ly1 = PLATFORM[2]-.25, sy-.10
    K.box('furnace_launder', BX, (ly0+ly1)/2, RIM_Z-.16, .26, ly1-ly0, .10, K.mat('f_oxide'))
    K.box('furnace_launder_trough', BX, (ly0+ly1)/2, RIM_Z-.10, .16, ly1-ly0-.04, .03, K.mat('ink_black'))
    melt = _emissive('e_melt', (.95, .32, .02), 1.0)
    melt_z = RIM_Z-MELT_DROP; rm = _e_melt_radius()
    K.cyl('furnace_melt', BX, BY, melt_z, rm, .05, melt, segments=28)
    K.washer('furnace_lining', (BX, BY, melt_z+.012), (0, 0, 1), rm-.07, rm+.085, .036, K.mat('f_oxide'))
    for i in range(3):
        rx, ry = _e_rod_xy(i); z1 = ROD_TOPS[i]
        K.cyl(f'electrode{i}', rx, ry, (melt_z-ROD_SUBMERGE+z1)/2, ROD_R, z1-(melt_z-ROD_SUBMERGE), K.mat('e_graphite'), segments=20)
        az = z1-ARM_DROP
        K.cyl(f'electrode{i}_clamp', rx, ry, az, ROD_R+.06, .22, zinc, segments=20)
        K._fine_mode = True
        K.washer(f'electrode{i}_ring', (rx, ry, az-.20), (0, 0, 1), ROD_R-.005, ROD_R+.035, .06, zinc)
        K._fine_mode = False
        mx = MAST_X-MAST_W/2
        K.dirbox(f'electrode{i}_bracket', (MAST_X, BY, az), (MAST_X, ry, az), .14, .14, frame)
        K.dirbox(f'electrode{i}_arm', (mx+.02, ry, az), (rx+ROD_R, ry, az), .11, .13, zinc)
        K.box(f'electrode{i}_arm_root', mx-.02, ry, az, .10, .20, .20, frame)
    mt = max(ROD_TOPS)-ARM_DROP+.22
    K.box('mast', MAST_X, BY, (DECK_Z+.08+mt)/2, MAST_W, MAST_W, mt-DECK_Z-.08, frame)
    K.box('mast_cap', MAST_X, BY, mt+.03, MAST_W+.08, MAST_W+.08, .06, zinc)
    K.box('mast_base', MAST_X, BY, DECK_Z+.04, MAST_W+.16, MAST_W+.16, .08, zinc)
    for k in range(3):
        K.box(f'mast_terminal{k}', MAST_X-MAST_W/2-.02, BY+(k-1)*.15, BUS_Z, .10, .08, .14, zinc)
    hx, hy = HOOD_XY
    K.box('hood', hx, hy, RIM_Z+.60, .80, .50, .40, zinc)
    K.box('hood_mouth', hx, hy-.26, RIM_Z+.55, .60, .06, .30, K.mat('ink_black'))
    K.box('hood_stand', hx+.30, hy+.10, (DECK_Z+RIM_Z+.40)/2, .12, .12, RIM_Z+.40-DECK_Z, frame)
    rz = _e_roof_z(hy)
    K.washer('hood_duct_collar', (hx, hy, rz+.04), (0, 0, 1), .18, .27, .08, frame, seg=20)
    return dict(mast_top=mt, duct_start=(hx, hy, RIM_Z+.80))


# ------------------------------------------------------------------ fume plant and stack

def _e_stack(K):
    """A tall modern steel stack at the front right, in the open where every level shows
    it whole: dark base plinth, warm-white tapered steel shell with dark bands, an access
    platform with a yellow barrier near the top, a caged ladder up its front, a dark cap."""
    sx, sy = STACK_XY
    K.box('stack_footing', sx, sy, .08, .80, .80, .16, K.mat('f_base'))
    K.box('stack_plinth', sx, sy, .16+.25, .70, .70, .50, K.mat('f_frame'))
    barrel = STACK_TOP-.20-.66
    K.cone('stack_barrel', sx, sy, .66+barrel/2, .30, .23, barrel, K.mat('r_shell'))
    K.cyl('stack_cap', sx, sy, STACK_TOP-.20+.08, .25, .16, K.mat('f_frame'))
    K.cyl('stack_top', sx, sy, STACK_TOP-.04, .22, .08, K.mat('ink_black'))

    def rad(z):
        return .30-.07*(z-.66)/barrel
    K._fine_mode = True
    for z in (1.80, 3.00, 4.50, 5.70):
        K.washer('stack_band', (sx, sy, z), (0, 0, 1), rad(z)-.01, rad(z)+.035, .06, K.mat('f_frame'))
    K._fine_mode = False
    pz = STACK_TOP-.95
    K.washer('stack_deck', (sx, sy, pz), (0, 0, 1), rad(pz)-.004, rad(pz)+.24, .05, K.mat('r_deck'), seg=24)
    _r_ring_rail(K, 'stack_rail', sx, sy, pz+.025, rad(pz)+.22, h=.22, posts=10)
    _r_ladder_cage(K, 'stack_ladder', sx, sy-.33, .70, pz, face='-Y')
    return rad


def _e_bag_house(K, deep):
    """A bag house that reads as a filter, standing behind the stack: a wide plain clad box
    on a dark frame, a flanged inlet transition on its front, a top walkway with a yellow
    barrier and the caged ladder from the ground up its lit face, an induced-draught fan on
    the lid whose outlet feeds the clean-gas flue, and a hopper with a rotary valve into a
    dust bin."""
    bx0, bx1, by0, by1 = BAG
    if deep: by0 -= .30
    bz0, bz1 = BAG_Z
    cxb, cyb = (bx0+bx1)/2, (by0+by1)/2
    frame = K.mat('f_frame')
    K.box('bag', cxb, cyb, (bz0+bz1)/2, bx1-bx0, by1-by0, bz1-bz0, K.mat('f2_filter'))
    K.box('bag_lid', cxb, cyb, bz1+.03, bx1-bx0+.06, by1-by0+.06, .06, frame)
    K.box('bag_walkway', cxb, cyb, bz1+.10, bx1-bx0+.30, by1-by0+.30, .05, K.mat('r_deck'))
    wx0, wx1, wy0, wy1 = bx0-.15, bx1+.15, by0-.15, by1+.15
    # The ladder climbs the lit face from the ground to the walkway, and the barrier
    # leaves it a gap where it arrives.
    ly = cyb-.25
    _r_rail(K, 'bag_rail_f', (wx0, wy0, bz1+.12), (wx1, wy0, bz1+.12))
    _r_rail(K, 'bag_rail_r0', (wx1, wy0, bz1+.12), (wx1, ly-.20, bz1+.12))
    _r_rail(K, 'bag_rail_r1', (wx1, ly+.20, bz1+.12), (wx1, wy1, bz1+.12))
    _r_rail(K, 'bag_rail_b', (wx1, wy1, bz1+.12), (wx0, wy1, bz1+.12))
    _r_ladder_cage(K, 'bag_ladder', wx1+.04, ly, .10, bz1+.12, face='+X')
    K.box('bag_ladder_foot', wx1+.04, ly, .05, .30, .36, .10, K.mat('f_base'))
    iz = bz0+(bz1-bz0)*.55
    ix = DUCT_DROP_X
    K.box('bag_inlet', ix, by0-.14, iz, .44, .28, .50, K.mat('f2_filter'))
    _v2_flange(K, 'bag_inlet_flange', ix, by0-.29, iz, 'y', w=.52, h=.58)
    fy = cyb+.05
    K.box('bag_fan_pedestal', cxb, fy, bz1+.20, .40, .44, .16, frame)
    K.cyl('bag_fan', cxb, fy, bz1+.52, .26, .40, K.mat('r_shell'), axis='Y', segments=20)
    K.cyl('bag_fan_motor', cxb, fy-.37, bz1+.52, .12, .30, frame, axis='Y', segments=14)
    K.box('bag_fan_outlet', cxb, fy, bz1+.84, .24, .24, .16, K.mat('r_shell'))
    drop = bz0-.72
    tx = max(.34, (bx1-bx0)-2*.42*drop); ty = max(.30, (by1-by0)-2*.42*drop)
    _e_frustum(K, 'bag_hopper', bx0, bx1, by0, by1, bz0+.02, .72, tx, ty, K.mat('f2_filter'))
    K.box('bag_valve', cxb, cyb, .60, tx+.06, ty+.06, .22, frame)
    K.cyl('bag_valve_motor', cxb+tx/2+.12, cyb, .60, .07, .18, frame, axis='X', segments=12)
    K.box('bag_bin', cxb, cyb, .22, .54, .46, .44, K.mat('f_zinc'))
    K.box('bag_bin_lid', cxb, cyb, .46, .58, .50, .04, frame)
    for sx_ in (bx0+.12, bx1-.12):
        for sy_ in (by0+.12, by1-.12):
            K.box('bag_foot', sx_, sy_, .05, .24, .24, .10, K.mat('f_base'))
            K.dirbox('bag_leg', (sx_, sy_, .10), (sx_, sy_, bz0-.02), .12, .12, frame)
    for ry in (by0+.12, by1-.12):
        K.dirbox('bag_beam', (bx0+.06, ry, bz0-.08), (bx1-.06, ry, bz0-.08), .10, .14, frame)
    return dict(cx=cxb, cy=cyb, inlet=(ix, by0-.30, iz), fan=(cxb, fy, bz1+.80))


def _e_fume(K, start, level):
    """From the hood: up through the chamber roof, over the roof's right edge and the yard
    on a post, down outside the chamber's right wall and back into the bag house's inlet
    (L2, L3); the fan on the lid sends the clean gas up and forward by the flue into the
    back of the stack. L1 has no filter: the duct drops to the ground and runs into the
    stack base as a low flue."""
    sx, sy = STACK_XY
    hx, hy, hz = start
    dx = DUCT_DROP_X
    frame, base, white = K.mat('f_frame'), K.mat('f_base'), K.mat('white_pipe')
    if level >= 2:
        bag = _e_bag_house(K, deep=level == 3)
        ix, iy, iz = bag['inlet']
        pts = [(hx, hy, hz), (hx, hy, DUCT_Z), (dx, hy, DUCT_Z), (dx, hy, iz), (dx, iy+.02, iz)]
        K.pipe_run('fume_duct', pts, .20, mat=white, bend=.26)
        fx, fy, fz = bag['fan']
        K.pipe_run('clean_flue', [(fx, fy, fz), (fx, fy, FLUE_Z), (sx, fy, FLUE_Z), (sx, sy+.31, FLUE_Z)], .14, mat=white, bend=.22)
        K.washer('clean_flue_collar_stack', (sx, sy+.33, FLUE_Z), (0, 1, 0), .13, .19, .04, frame, seg=16)
        K.box('clean_flue_foot', sx, fy, .05, .18, .18, .10, base)
        K.dirbox('clean_flue_post', (sx, fy, .10), (sx, fy, FLUE_Z-.17), .07, .07, frame)
    else:
        # The hood's y and the stack's are close enough that the low flue runs straight in.
        pts = [(hx, hy, hz), (hx, hy, DUCT_Z), (dx, hy, DUCT_Z), (dx, hy, GROUND_FLUE_Z), (sx-.36, hy, GROUND_FLUE_Z)]
        K.pipe_run('fume_duct', pts, .19, mat=white, bend=.20)
        K.washer('fume_collar_stack', (sx-.36, hy, GROUND_FLUE_Z), (1, 0, 0), .18, .24, .04, frame, seg=16)
        K.box('fume_drop_foot', dx, hy, .05, .30, .30, .10, base)
    px = HALL[1]+.13
    K.box('fume_post_foot', px, hy, .05, .16, .16, .10, base)
    K.dirbox('fume_post', (px, hy, .10), (px, hy, DUCT_Z-.24), .08, .08, frame)
    K.dirbox('fume_saddle', (px, hy-.22, DUCT_Z-.25), (px, hy+.22, DUCT_Z-.25), .09, .06, frame)


# ------------------------------------------------------------------ power

def _e_power(K, level):
    """Bus bushings on the chamber's left wall carry the tubes across the chamber above the
    electrodes to the mast's terminals, hung from the roof. In the switchyard in front of the
    transformer house, large oil-filled transformers stand in a row along Y under an overhead
    three-phase line on H-frame gantries, which lands on the house's front-wall bushings.
    One transformer at L1, two at L2, three at L3."""
    wx = HALL[0]
    K._fine_mode = True
    for k in range(3):
        ty = BY+(k-1)*.15
        K.cyl(f'bus{k}_bushing', wx+.11, ty, BUS_Z, .055, .22, K.mat('p_insulator'), axis='X', segments=12)
        K.washer(f'bus{k}_bushing_flange', (wx+.02, ty, BUS_Z), (1, 0, 0), .06, .11, .04, K.mat('f_frame'), seg=12)
        K.dircyl(f'bus{k}', (wx+.20, ty, BUS_Z), (MAST_X-MAST_W/2-.07, ty, BUS_Z), .038, K.mat('f_zinc'), segments=10)
    hx = (wx+MAST_X)/2
    K.dirbox('bus_hanger', (hx, BY, _e_roof_z(BY)-.05), (hx, BY, BUS_Z+.05), .05, .05, K.mat('f_frame'))
    K.dirbox('bus_hanger_bar', (hx, BY-.22, BUS_Z+.05), (hx, BY+.22, BUS_Z+.05), .05, .05, K.mat('f_frame'))
    K._fine_mode = False
    tx0, tx1, ty0, ty1 = TX_YARD
    K.box('tx_gravel', (tx0+tx1)/2, (ty0+ty1)/2, .035, tx1-tx0, ty1-ty0, .07, K.mat('membrane'))
    K.box('tx_kerb', (tx0+tx1)/2, (ty0+ty1)/2, .02, tx1-tx0+.08, ty1-ty0+.08, .04, K.mat('f_base'))
    n = {1: 1, 2: 2, 3: 3}[level]
    sc = 1.45 if n < 3 else 1.15
    ys = {1: [-.74], 2: [-1.08, -.34], 3: [-1.16, -.70, -.24]}[n]
    for i, y in enumerate(ys):
        K.transformer(f'tx{i}', TX_X, y, .07, s=sc, fins=5)
    for ob in K.col.objects:
        if ob.name.startswith('tx') and ob.type == 'MESH':
            mats = ob.data.materials
            for i, m in enumerate(mats):
                if m == K.mat('f_frame'): mats[i] = K.mat('p_tx')
    phases = [TX_X+(k-1)*.20 for k in range(3)]
    for gy in (ty0+.15, TXHOUSE[2]-.45):
        for px in (TX_X-.42, TX_X+.42):
            K.box('gantry_foot', px, gy, .10, .14, .14, .06, K.mat('f_base'))
            K.dirbox('gantry_post', (px, gy, .07), (px, gy, LINE_Z+.14), .06, .06, K.mat('f_frame'))
        K.dirbox('gantry_beam', (TX_X-.46, gy, LINE_Z+.10), (TX_X+.46, gy, LINE_Z+.10), .05, .06, K.mat('f_frame'))
        K._fine_mode = True
        for px in phases:
            K.dircyl('gantry_insulator', (px, gy, LINE_Z+.07), (px, gy, LINE_Z-.04), .022, K.mat('p_insulator'), segments=8)
        K._fine_mode = False
    K._fine_mode = True
    bush_z = .07+.68*sc
    for k, px in enumerate(phases):
        K.dircyl(f'line_phase{k}', (px, ty0+.15, LINE_Z), (px, TXHOUSE[2]-.16, LINE_Z), .010, K.mat('f_frame'), segments=6)
        for i, y in enumerate(ys):
            bx = TX_X+(k-1)*.14*sc
            K.dircyl(f'tx{i}_dropper{k}', (bx, y, bush_z), (px, y, LINE_Z), .009, K.mat('f_frame'), segments=6)
    K._fine_mode = False


# ------------------------------------------------------------------ tank

def _e_tank(K):
    """The cooling-water tower at the back (L2, L3): a warm-white tank with a domed cap on
    a dark four-leg trestle, tall enough that the tank shows above the bag house, a caged
    ladder up its lit side, and a white riser down to a water line along the ground into
    the chamber's back wall for the shell's water-cooled hoops."""
    tx, ty = TANK_XY
    r, leg, ring_z, tank_z0, tank_h = .40, .28, 2.42, 2.55, .95
    frame, base, shell = K.mat('f_frame'), K.mat('f_base'), K.mat('r_shell')
    K.box('tank_pad', tx, ty, .04, 1.00, 1.00, .08, base)
    for dx in (-1, 1):
        for dy in (-1, 1):
            K.box('tank_foot', tx+dx*.30, ty+dy*.30, .13, .18, .18, .10, base)
            K.dirbox('tank_leg', (tx+dx*.30, ty+dy*.30, .18), (tx+dx*leg, ty+dy*leg, ring_z), .09, .09, frame)
    for dy in (-1, 1):
        K.dirbox('tank_ring', (tx-leg-.04, ty+dy*leg, ring_z+.04), (tx+leg+.04, ty+dy*leg, ring_z+.04), .08, .08, frame)
    for dx in (-1, 1):
        K.dirbox('tank_ring', (tx+dx*leg, ty-leg-.04, ring_z+.04), (tx+dx*leg, ty+leg+.04, ring_z+.04), .08, .08, frame)
    K._fine_mode = True
    for a, b in (((tx+leg, ty-leg, .30), (tx+leg, ty+leg, ring_z-.10)), ((tx+leg, ty+leg, .30), (tx+leg, ty-leg, ring_z-.10)),
                 ((tx-leg, ty-leg, .30), (tx+leg, ty-leg, ring_z-.10)), ((tx+leg, ty-leg, .30), (tx-leg, ty-leg, ring_z-.10))):
        K.dirbox('tank_brace', a, b, .04, .04, frame)
    K._fine_mode = False
    K.cyl('tank_floor', tx, ty, ring_z+.08+.04, r-.02, .08, frame)
    K.cyl('tank', tx, ty, tank_z0+tank_h/2, r, tank_h, shell)
    K.dome_cap('tank_cap', tx, ty, tank_z0+tank_h, r, .16, shell)
    K._fine_mode = True
    K.washer('tank_band', (tx, ty, tank_z0+.20), (0, 0, 1), r-.01, r+.025, .04, frame)
    K.cyl('tank_vent', tx+.12, ty-.12, tank_z0+tank_h+.20, .035, .18, frame, segments=10)
    K.cyl('tank_vent_cap', tx+.12, ty-.12, tank_z0+tank_h+.30, .06, .03, frame, segments=10)
    K._fine_mode = False
    _r_ladder_cage(K, 'tank_ladder', tx+r+.03, ty, .10, tank_z0+tank_h-.05, face='+X')
    rx, ry = tx+.18, ty-.18
    K.pipe_run('cooling_line', [(rx, ry, tank_z0-.02), (rx, ry, .60), (rx, HALL[3]+.01, .60)], .07, mat=K.mat('white_pipe'), bend=.14)
    _v2_flange(K, 'cooling_collar', rx, HALL[3]+.02, .60, 'y', w=.20, h=.20)


# ------------------------------------------------------------------ yard

def _e_receiving_bin(K):
    """A closed receiving bin at the conveyor's foot: a zinc box with a lid and a loading
    hatch, its hopper carried on a dark four-post frame with a ring beam and bracing,
    discharging into the conveyor's boot. Closed, because an arc furnace takes many
    different charges."""
    bx, by = BIN_XY
    frame = K.mat('f_frame')
    K.box('bin_pad', bx, by, .05, 1.14, 1.00, .10, K.mat('f_base'))
    for dx in (-.46, .46):
        for dy in (-.40, .40):
            K.dirbox('bin_post', (bx+dx, by+dy, .10), (bx+dx, by+dy, 1.06), .12, .12, frame)
    for dy in (-.40, .40):
        K.dirbox('bin_ring', (bx-.52, by+dy, 1.02), (bx+.52, by+dy, 1.02), .10, .12, frame)
    for dx in (-.46, .46):
        K.dirbox('bin_ring', (bx+dx, by-.46, 1.02), (bx+dx, by+.46, 1.02), .12, .10, frame)
    K._fine_mode = True
    K.dirbox('bin_brace', (bx-.46, by-.40, .16), (bx+.46, by-.40, .96), .05, .05, frame)
    K.dirbox('bin_brace', (bx+.46, by-.40, .16), (bx+.46, by+.40, .96), .05, .05, frame)
    K._fine_mode = False
    _e_frustum(K, 'bin_hopper', bx-.46, bx+.46, by-.40, by+.40, 1.05, .50, .30, .26, K.mat('f_zinc'))
    K.box('bin_body', bx, by, 1.35, .96, .84, .60, K.mat('f_zinc'))
    K.box('bin_lid', bx, by, 1.68, 1.02, .90, .06, frame)
    K.box('bin_hatch', bx-.22, by-.18, 1.73, .34, .30, .05, frame)
    K._fine_mode = True
    K.box('bin_hatch_hinge', bx-.22, by-.34, 1.75, .36, .03, .03, K.mat('f_zinc'))
    for dz in (.88, 1.20, 1.52):
        K.box('bin_band', bx, by-.43, dz, .98, .02, .03, frame)
    K._fine_mode = False
    K.box('bin_throat', bx, by, .40, .26, .22, .20, frame)


def _e_charging(K):
    """The charging chain from the receiving bin: a covered conveyor climbs beside the
    chamber's right wall into the boot of a bucket elevator standing outside that wall, the
    elevator raises the charge to a gabled head house above the roof, and a covered gallery
    runs over the roof to the chute house, whose chute drops through the roof into the bath."""
    ex, ey = ELEV_XY
    cx = CONVEYOR_X
    yb = BIN_XY[1]+.30
    # Conveyor: level out of the bin, climb, level into the elevator boot.
    boot_z = 1.25
    path = [(yb+.02, .95), (yb+.40, .95), (ey-.60, boot_z), (ey-.30, boot_z)]
    _e_bent_gallery_y(K, 'charge_conveyor', path, cx, .19, .15, 'f_zinc')
    _v2_flange(K, 'charge_conveyor_flange', cx, ey-.28, boot_z, 'y', w=.46, h=.42)
    K._fine_mode = True
    for ky in (yb+.40, (yb+.40+ey-.60)/2, ey-.60):
        kz = .95+(boot_z-.95)*((ky-(yb+.40))/((ey-.60)-(yb+.40))) if ky > yb+.40 else .95
        for s in (-1, 1):
            K.box('charge_conveyor_foot', cx+s*.26, ky, .05, .16, .16, .10, K.mat('f_base'))
            K.dirbox('charge_conveyor_leg', (cx+s*.26, ky, .10), (cx+s*.26, ky, kz-.18), .06, .06, K.mat('f_frame'))
        K.dirbox('charge_conveyor_bearing', (cx-.27, ky, kz-.18), (cx+.27, ky, kz-.18), .07, .08, K.mat('f_frame'))
    K._fine_mode = False
    # Bucket elevator: boot on a footing, casing up to the head house above the roof line.
    K.box('elevator_footing', ex, ey, .08, .70, .76, .16, K.mat('f_base'))
    K.box('elevator_boot', ex, ey, .16+.36, .54, .62, .72, K.mat('f_frame'))
    K.box('elevator_casing', ex, ey, (.88+ELEV_TOP-.30)/2, .44, .52, ELEV_TOP-.30-.88, K.mat('f_sheet'))
    K._fine_mode = True
    for z in (1.9, 2.9, 3.9):
        K.box('elevator_casing_seam', ex+.225, ey, z, .012, .50, .012, K.mat('f_frame'))
    K.box('elevator_inspection', ex+.225, ey, 3.0, .025, .30, .50, K.mat('f_frame'))
    K._fine_mode = False
    _v2_gable_house(K, 'elevator_head', ex, ey, ELEV_TOP-.55, .66, .72, 'x', eave=ELEV_TOP-.08)
    # Gallery over the roof to the chute house, square into both gables.
    gz = ELEV_TOP-.30
    hx, hy = CHUTE_XY
    K.conveyor_bridge('charge_gallery', (ex-.28, ey, gz), (hx+.32, ey, gz), w=.36, h=.34, ribs=4)
    _v2_gallery_cover(K, 'charge_gallery_cover', (ex-.40, ey, 0), (hx+.38, ey, 0), top=gz+.17)
    _v2_flange(K, 'charge_gallery_flange_head', ex-.30, ey, gz, 'x')
    _v2_flange(K, 'charge_gallery_flange_chute', hx+.35, ey, gz, 'x')
    _v2_gable_house(K, 'chute_house', hx, ey, gz-.42, .62, .70, 'x', eave=gz+.08)
    for s_ in (-1, 1):
        for dx in (-.22, .22):
            K.box('chute_house_foot', hx+dx, ey+s_*.22, _e_roof_z(ey+s_*.22)+.05, .18, .18, .08, K.mat('f_zinc'))
            K.dirbox('chute_house_leg', (hx+dx, ey+s_*.22, _e_roof_z(ey+s_*.22)+.09), (hx+dx, ey+s_*.22, gz-.42), .08, .08, K.mat('f_frame'))
    cz = _e_roof_z(hy)
    K.box('chute', hx, hy, (cz-.30+gz-.42)/2, .30, .30, gz-.42-(cz-.30), K.mat('f_zinc'))
    K.box('chute_collar', hx, hy, cz+.05, .42, .42, .10, K.mat('f_frame'))


def _e_ladle_car(K, name, x, y):
    before = {ob.name for ob in K.col.objects}
    _v2_ladles(K, name, x, y)
    for ob in K.col.objects:
        if ob.name not in before: ob.location.z += .06


# ------------------------------------------------------------------ build

def build_eaf_v2(level=1):
    assert level in (1, 2, 3)
    K = _e_begin()
    _e_check_sightlines()
    _r_pad(K, 'site_pad_front', HALL[0]-.10, HALL[1]+.10, -2.65, HALL[2])
    _r_pad(K, 'site_pad_yard', HALL[1]+.10, 4.10, -1.75, 1.80)
    _e_house(K)
    _e_platform(K)
    furnace = _e_furnace(K)
    _e_fume(K, furnace['duct_start'], level)
    _e_stack(K)
    _e_power(K, level)
    if level >= 2:
        _e_tank(K)
    _e_receiving_bin(K)
    _e_charging(K)
    _e_ladle_car(K, 'ladle', LADLE_XY[0], LADLE_XY[1])
    if level == 3:
        _e_ladle_car(K, 'ladle_b', LADLE_XY[0]+.75, LADLE_XY[1]+.05)
    return _r_finish(K, level, 'eaf v2: furnace in its chamber under a slanted roof, transformer house and switchyard, storage L, steel stack in front of the bag house')
