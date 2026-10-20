"""The electric arc furnace in the catalogue look: the furnace inside its chamber.

Executed in sprite_kit's namespace after furnace_builder.py, furnace_v2_builder.py,
refinery_v2_builder.py and power_plant_v2_builder.py, whose palette and helpers it shares.
Staged as family 'eaf_v2'; it installs as 'eaf'.

Screen vocabulary at this camera: back = +Y (top-right), right = +X (lower-right),
front = -Y (bottom-left), left = -X (upper-left).

Composition (owner, 20 October 2026, after dreamloop round 2): the furnace INSIDE the
building, seen through the open front as in the old model, under a single slanted roof plane
over the process chamber that is high at the open front and drops toward the back, so the
opening stays tall and little roof shows; the bowl and the electrodes visible; brick side
walls with windows; the transformers on one side; the centre of the picture the bowl.

The process chamber has an open portal front under a dark fascia, a brick right wall and
back wall, and a brick left wing lower than the chamber with factory windows, which is also
the transformer house: its roof bushings feed the bus tubes that cross into the chamber to
the mast, and two yard transformers stand in front of it. Inside, the furnace on its
black-grey operating platform with yellow rails and a stair down into the yard: a dark-metal
shell with silver hoops, the bath baked as light, three graphite electrodes on arms from a
dark mast beside the shell. A hood at the back of the rim sends the fume up through the roof
and over to the bag house and on to one thin brick chimney. Behind the chamber a brick
elevator tower rising above the roof, with the head house and gallery to a chute house on the
roof whose chute drops through the roof into the bath; a storage wing fed by tall silos and
by the covered scrap conveyor from the scrap bay under its goliath crane. The tap hole and
ladle car at the front right of the bowl.

Fixed across levels: chamber, wing, furnace, mast, tower, chimney. L1: one yard transformer,
short bunker, ground flue, no crane. L2: storage wing, two silos, bag house, crane, conveyor,
two transformers. L3: third silo, third transformer, second ladle, deeper bag house.
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
HALL = (-2.40, 2.00, -.90, 1.60)      # x0, x1, y0, y1 of the whole building
WING_X1 = -1.20                       # the brick left wing ends here; the chamber is to its right
LWING_H = 2.80                        # the wing's flat roof (the transformer house)
EAVE_F, EAVE_B = 4.30, 3.10           # the chamber's slanted roof: high at the open front, low at the back
LINTEL_H = .26                        # the dark fascia across the open front; the sightline head is its underside
BASE_Z = .58
PIER_X = 1.80                         # a narrow brick pier closes the opening on the right

# ---- the furnace ------------------------------------------------------------------------
PLATFORM_Z = .85
PLATFORM = (-1.05, 1.45, -.60, 1.10)  # x0, x1, y0, y1
BX, BY = -.40, -.20                   # left of the chamber's centre and forward, straddling the front line
BOWL_R, BOWL_RISE, BOWL_WALL = 1.00, .90, .10
RIM_Z = 1.85
MELT_DROP = .16
ROD_R, ROD_RING = .12, .40
ROD_ANGLES = (75.0, 195.0, 315.0)
ROD_TOPS = (2.70, 3.20, 2.90)
ROD_SUBMERGE = .10
MAST_X = .85                          # right of the shell; its x+y must stay under the right pier's, or the pier hides it
MAST_W = .28
ARM_DROP = .35
STAIR_X = -.95

# ---- plant --------------------------------------------------------------------------
HOOD_XY = (BX+.55, BY+.95)            # hood at the back of the rim; the duct rises through the roof
DUCT_Z = 4.05                         # the duct's run over the roof
BAG = (3.00, 3.65, .60, 1.40)
BAG_Z = (1.50, 3.40)
STACK_XY = (4.00, 1.70)               # one thin chimney, same place at every level
STACK_TOP = 5.40
FLUE_Z = .95
GROUND_FLUE_Z = .45
BUS_Z = 3.55                          # bus tubes from the wing roof across the chamber to the mast
TX_YARD = (-2.35, -1.25, -1.75, -1.05)  # transformer yard in front of the left wing
TOWER = (-1.55, -.25, 1.70, 3.00)
TOWER_H = 4.40
WING = (-.25, 1.90, 1.70, 2.90)       # storage wing from the tower along the back of the chamber
WING_H = 2.40
SILOS = ((.70, 3.40), (1.50, 3.40), (2.30, 3.40))
SILO_LEG = 2.60
ELEV_Y = 2.70
ELEV_TOP = 5.05
CHUTE_Y = 1.15                        # chute house on the roof; the chute drops through the roof into the bath
SCRAP = (2.15, 2.95, -1.45, -.65)
CRANE_Y = -1.05
CONVEYOR_X = 2.50
TAP_X = .55
LADLE_XY = (.60, -1.12)


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
    roof that drops toward the back, the front eave alone decides it (the ray rises faster
    than the roof)."""
    head = EAVE_F-LINTEL_H; y0 = HALL[2]
    for name, _, y, z in _e_sightline_tests():
        if z+(y-y0) >= head: raise RuntimeError('EAF sightline buried: %s crosses at %.2f, head %.2f' % (name, z+(y-y0), head))


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


def _e_bent_gallery_y(K, name, path, x, half_w, half_h, mat):
    """A rectangular conveyor gallery along a polyline in the YZ plane at fixed x, one mesh
    with mitred bends (the furnace's `_v2_bent_gallery` turned through 90 degrees)."""
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


# ------------------------------------------------------------------ the furnace house

def _e_house(K):
    """The chamber with its open front and slanted roof, the brick right wall and back wall,
    and the lower brick left wing with its windows (the transformer house)."""
    x0, x1, y0, y1 = HALL
    d = y1-y0; cy = (y0+y1)/2
    brick, frame = K.mat('f_brick'), K.mat('f_frame')
    K.box('house_footing', (x0+x1)/2, cy, .08, x1-x0+.10, d+.10, .16, K.mat('f_base'))
    K.box('house_floor', (WING_X1+x1)/2, cy, .13, x1-WING_X1-.16, d-.16, .02, K.mat('f_base'))
    t = .16
    # Left wing: a brick block with a stone coping and membrane roof, windows and a door.
    wx0, wx1 = x0, WING_X1
    K.box('wing_walls', (wx0+wx1)/2, cy, (.10+LWING_H)/2, wx1-wx0, d, LWING_H-.10, brick)
    K.box('wing_coping', (wx0+wx1)/2, cy, LWING_H+.03, wx1-wx0+.06, d+.06, .06, K.mat('stone'))
    K.box('wing_roof', (wx0+wx1)/2, cy, LWING_H+.07, wx1-wx0-.10, d-.10, .04, K.mat('membrane'))
    K._fine_mode = True
    for i, wx in enumerate((wx0+.35, wx0+.85)):
        _pp_window(K, f'wing_window{i}', '-Y', (wx, y0-.055, 1.90), .40, .55, k=.6)
    _pp_window(K, 'wing_window_hi', '-Y', (wx0+.60, y0-.055, .95), .40, .55, k=.6)
    _pp_louvre(K, 'wing_louvre_front', '-Y', (wx0+.60, y0-.03, 2.45), w=.56, h=.30)
    _pp_louvre(K, 'wing_louvre_back', '+Y', (wx0+.60, y1+.03, 1.90), w=.56, h=.46)
    K._fine_mode = False
    # The chamber: the wing's wall continues up as refractory cladding to the roof on the left,
    # a brick right wall with a narrow pier at the opening, a brick back wall. Side walls are
    # trapezoids under the slanted roof.
    def side(nm, x, mat, z0):
        K.prism(nm, (x, 0, 0), (0, 1), [(y0, z0), (y1, z0), (y1, EAVE_B), (y0, EAVE_F)], t, mat)
    side('chamber_left_clerestory', WING_X1-t/2+.08, K.mat('f2_refractory'), LWING_H+.09)
    side('chamber_right', x1-t/2, brick, .10)
    K.box('chamber_back', (WING_X1+x1)/2, y1-t/2, (.10+EAVE_B)/2, x1-WING_X1, t, EAVE_B-.10, brick)
    K.box('chamber_pier', (PIER_X+x1)/2, y0+t/2, (.10+EAVE_F)/2, x1-PIER_X, t, EAVE_F-.10, brick)
    # The open front: dark fascia across the opening and columns at its jambs.
    K.box('chamber_fascia', (WING_X1+PIER_X)/2, y0+.06, EAVE_F-LINTEL_H/2, PIER_X-WING_X1+.02, .14, LINTEL_H, frame)
    K.box('chamber_bay_shadow', (WING_X1+PIER_X)/2, y0+t+.02, EAVE_F-LINTEL_H-.09, PIER_X-WING_X1-.02, .02, .18, K.mat('ink_black'))
    for px in (WING_X1+.06, PIER_X-.045):
        K.box('chamber_column', px, y0-.03, (.12+EAVE_F)/2, .11, .07, EAVE_F-.12, frame)
    for py in (y0+.06, cy, y1-.06):
        K.box('chamber_column_end', x1+.03, py, (.12+_e_roof_z(py)-.10)/2, .07, .11, _e_roof_z(py)-.22, frame)
    # The slanted roof: one plane with standing seams running down the slope, a dark edge
    # beam at the front and a gutter at the low back eave.
    k = (EAVE_F-EAVE_B)/d; o = .10
    rx0, rx1 = WING_X1-.10, x1+.10
    K.prism('chamber_roof', ((rx0+rx1)/2, 0, 0), (0, 1), [(y0-o, EAVE_F+k*o), (y1+o, EAVE_B-k*o), (y1+o, EAVE_B-k*o+.06), (y0-o, EAVE_F+k*o+.06)], rx1-rx0, K.mat('f_roof'))
    K._fine_mode = True
    n = max(2, round((rx1-rx0)/.26))
    for j in range(n+1):
        px = rx0+j*(rx1-rx0)/n
        K.dirbox('chamber_roof_seam', (px, y0-.02, _e_roof_z(y0-.02)+.012), (px, y1+.02, _e_roof_z(y1+.02)+.012), .012, .012, K.mat('f_roof'))
    K._fine_mode = False
    K.box('chamber_gutter', (rx0+rx1)/2, y1+o+.03, EAVE_B-k*o+.02, rx1-rx0+.04, .07, .06, K.mat('silver'))
    _v2_downpipe(K, 'chamber_dp', x1-.12, y1+o+.03, EAVE_B-k*o, 0.0)
    _v2_downpipe(K, 'wing_dp', x0+.12, y1+.12, LWING_H, 0.0)
    K.box('wing_gutter', (wx0+wx1)/2, y1+.10, LWING_H+.02, wx1-wx0, .08, .07, K.mat('silver'))
    # Windows and a door on the lit right wall, a louvre high in it.
    K._fine_mode = True
    for i, (wy, wz) in enumerate(((.15, 1.75), (.90, 1.75), (.15, 2.70), (.90, 2.70))):
        _pp_window(K, f'chamber_window{i}', '+X', (x1+.055, wy, wz), .40, .55, k=.6)
    _pp_louvre(K, 'chamber_louvre_end', '+X', (x1+.03, .50, 3.50), w=.50, h=.36)
    K._fine_mode = False
    _pp_door(K, 'chamber_door_end', '+X', (x1+.02, -.50, .14+.95/2), .50, .95)
    K.box('chamber_step_end', x1+.14, -.50, .04, .20, .66, .08, K.mat('stone'))


# ------------------------------------------------------------------ the furnace

def _e_platform(K):
    """Operating platform: black-grey deck on dark columns, yellow rails along its front
    either side of the shell, and a straight stair from the yard up through the opening."""
    x0, x1, y0, y1 = PLATFORM
    z = PLATFORM_Z
    deck, frame = K.mat('r_deck'), K.mat('f_frame')
    K.box('platform_deck', (x0+x1)/2, (y0+y1)/2, z-.04, x1-x0, y1-y0, .08, deck)
    K.box('platform_fascia', (x0+x1)/2, y0-.01, z-.09, x1-x0, .03, .12, frame)
    for px in (x0+.12, (x0+x1)/2, x1-.12):
        for py in (y0+.12, y1-.12):
            K.dirbox('platform_column', (px, py, .14), (px, py, z-.08), .09, .09, frame)
    gap0, gap1 = BX-BOWL_R-.06, BX+BOWL_R+.06
    _r_rail(K, 'platform_rail_fl', (x0, y0, z), (max(x0, gap0), y0, z))
    _r_rail(K, 'platform_rail_fr', (gap1, y0, z), (x1, y0, z))
    _r_rail(K, 'platform_rail_r', (x1, y0, z), (x1, y1, z))
    sx = STAIR_X; sw = .30
    foot_y, head_y = y0-1.15, y0
    n = 9
    for i in range(n):
        f1 = (i+1)/n
        ty = foot_y+(head_y-foot_y)*(i+.5)/n
        tz = .14+(z-.14)*f1
        K.box(f'stair_tread{i}', sx, ty, tz-.015, sw, (head_y-foot_y)/n+.01, .03, deck)
        K.box(f'stair_riser{i}', sx, ty+(head_y-foot_y)/n/2-.005, tz-.015-(z-.14)/n/2, sw-.02, .01, (z-.14)/n, deck)
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
    """The shell on its rocker, the bath, the electrodes on arms from the mast, the hood."""
    frame, zinc = K.mat('f_frame'), K.mat('f_zinc')
    K.cyl('furnace_pedestal', BX, BY, (PLATFORM_Z+RIM_Z-BOWL_RISE+.12)/2, .42, RIM_Z-BOWL_RISE+.12-PLATFORM_Z, frame, segments=24)
    for s_ in (-1, 1):
        K.cyl(f'furnace_trunnion{s_}', BX+s_*BOWL_R*.82, BY, RIM_Z-BOWL_RISE*.50, .10, .34, frame, axis='X', segments=14)
    _e_bowl(K, 'furnace_shell', BX, BY, RIM_Z, BOWL_R, BOWL_RISE, BOWL_WALL, K.mat('f_shell'), K.mat('f_oxide'))
    K._fine_mode = True
    for z in (RIM_Z-.26, RIM_Z-.46, RIM_Z-.66):
        rr = _e_shell_r(z)
        K.washer(f'furnace_hoop{int(z*100)}', (BX, BY, z), (0, 0, 1), rr-.02, rr+.065, .07, zinc)
    K._fine_mode = False
    # Tapping spout at the front right, over the ladle car.
    a = math.radians(-55)
    sx, sy = BX+(BOWL_R-.05)*math.cos(a), BY+(BOWL_R-.05)*math.sin(a)
    K.rotbox('furnace_spout', sx+.16*math.cos(a), sy+.16*math.sin(a), RIM_Z-.10, .42, .22, .14, K.mat('f_oxide'), 'Z', -55)
    K.rotbox('furnace_spout_trough', sx+.18*math.cos(a), sy+.18*math.sin(a), RIM_Z-.04, .36, .12, .04, K.mat('ink_black'), 'Z', -55)
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
    K.box('mast', MAST_X, BY, (PLATFORM_Z+.08+mt)/2, MAST_W, MAST_W, mt-PLATFORM_Z-.08, frame)
    K.box('mast_cap', MAST_X, BY, mt+.03, MAST_W+.08, MAST_W+.08, .06, zinc)
    K.box('mast_base', MAST_X, BY, PLATFORM_Z+.04, MAST_W+.16, MAST_W+.16, .08, zinc)
    for k in range(3):
        K.box(f'mast_terminal{k}', MAST_X-MAST_W/2-.02, BY+(k-1)*.15, BUS_Z, .10, .08, .14, zinc)
    # Hood at the back of the rim; its duct rises through the roof with a collar.
    hx, hy = HOOD_XY
    K.box('hood', hx, hy, RIM_Z+.55, .80, .50, .40, zinc)
    K.box('hood_mouth', hx, hy-.26, RIM_Z+.50, .60, .06, .30, K.mat('ink_black'))
    K.box('hood_stand', hx+.30, hy+.10, (PLATFORM_Z+RIM_Z+.35)/2, .12, .12, RIM_Z+.35-PLATFORM_Z, frame)
    rz = _e_roof_z(hy)
    K.washer('hood_duct_collar', (hx, hy, rz+.04), (0, 0, 1), .18, .27, .08, frame, seg=20)
    return dict(mast_top=mt, duct_start=(hx, hy, RIM_Z+.75))


# ------------------------------------------------------------------ fume plant and chimney

def _e_chimney(K):
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


def _e_bag_house(K, deep):
    bx0, bx1, by0, by1 = BAG
    if deep: by0 -= .45
    bz0, bz1 = BAG_Z
    cxb, cyb = (bx0+bx1)/2, (by0+by1)/2
    K.box('bag', cxb, cyb, (bz0+bz1)/2, bx1-bx0, by1-by0, bz1-bz0, K.mat('f2_filter'))
    K.box('bag_lid', cxb, cyb, bz1+.04, bx1-bx0+.10, by1-by0+.10, .08, K.mat('f_roof'))
    K._fine_mode = True
    n = max(4, round((bx1-bx0)/.17))
    for i in range(1, n):
        K.box(f'bag_rib{i}', bx0+(bx1-bx0)*i/n, by0-.015, (bz0+bz1)/2, .04, .03, bz1-bz0-.08, K.mat('f_frame'))
    m = max(4, round((by1-by0)/.17))
    for j in range(1, m):
        K.box(f'bag_rib_end{j}', bx1+.015, by0+(by1-by0)*j/m, (bz0+bz1)/2, .03, .04, bz1-bz0-.08, K.mat('f_frame'))
    K._fine_mode = False
    drop = bz0-.62
    tx = max(.34, (bx1-bx0)-2*.42*drop); ty = max(.30, (by1-by0)-2*.42*drop)
    _e_frustum(K, 'bag_hopper', bx0, bx1, by0, by1, bz0+.02, .62, tx, ty, K.mat('f2_filter'))
    K.box('bag_throat', cxb, cyb, .50, tx-.04, ty-.04, .26, K.mat('f_frame'))
    K.box('bag_skip', cxb, cyb, .20, .56, .46, .40, K.mat('f_frame'))
    K.box('bag_skip_dust', cxb, cyb, .38, .46, .36, .06, K.mat('f_base'))
    for sx_ in (bx0+.12, bx1-.12):
        for sy_ in (by0+.12, by1-.12):
            K.box('bag_foot', sx_, sy_, .05, .24, .24, .10, K.mat('f_base'))
            K.dirbox('bag_leg', (sx_, sy_, .10), (sx_, sy_, bz0-.02), .12, .12, K.mat('f_frame'))
    for ry in (by0+.12, by1-.12):
        K.dirbox('bag_beam', (bx0+.06, ry, bz0-.08), (bx1-.06, ry, bz0-.08), .10, .14, K.mat('f_frame'))
    _r_ladder_cage(K, 'bag_ladder', bx0+.30, by0-.05, bz0+.05, bz1+.12, face='-Y')
    # Clean gas: out of the right face low down, straight into the chimney base.
    sx, sy = STACK_XY
    fy = min(by1-.15, sy-.15)
    K.dircyl('clean_flue', (bx1+.02, fy, FLUE_Z), (sx-.31, fy, FLUE_Z), .13, K.mat('white_pipe'), segments=16)
    _v2_flange(K, 'clean_flue_collar', bx1+.03, fy, FLUE_Z, 'x', w=.34, h=.34)
    K.washer('clean_flue_collar_stack', (sx-.32, fy, FLUE_Z), (1, 0, 0), .12, .18, .04, K.mat('f_frame'), seg=16)
    return cxb, cyb


def _e_fume(K, start, level):
    """From the hood: up through the roof, along the roof's fall toward the right and over
    the right wall, then down into the bag house's lid (L2, L3) or to the ground and into
    the chimney base as a low flue (L1)."""
    sx, sy = STACK_XY
    hx, hy, hz = start
    x1 = HALL[1]
    if level >= 2:
        cxb, cyb = _e_bag_house(K, deep=level == 3)
        pts = [(hx, hy, hz), (hx, hy, DUCT_Z), (cxb, hy, DUCT_Z), (cxb, cyb, DUCT_Z), (cxb, cyb, BAG_Z[1]+.08)]
        K.pipe_run('fume_duct', pts, .20, mat=K.mat('white_pipe'), bend=.32)
        K.washer('fume_collar_bag', (cxb, cyb, BAG_Z[1]+.10), (0, 0, 1), .19, .27, .06, K.mat('f_frame'), seg=20)
    else:
        dx = sx-.95
        pts = [(hx, hy, hz), (hx, hy, DUCT_Z), (dx, hy, DUCT_Z), (dx, hy, GROUND_FLUE_Z), (dx, sy-.15, GROUND_FLUE_Z), (sx-.31, sy-.15, GROUND_FLUE_Z)]
        K.pipe_run('fume_duct', pts, .19, mat=K.mat('white_pipe'), bend=.30)
        K.washer('fume_collar_stack', (sx-.32, sy-.15, GROUND_FLUE_Z), (1, 0, 0), .18, .24, .04, K.mat('f_frame'), seg=16)
        K.box('fume_drop_foot', dx, hy, .05, .32, .32, .10, K.mat('f_base'))
    # A trestle carries the run just outside the right wall.
    px = x1+.55
    K.box('fume_post_foot', px, hy, .05, .18, .18, .10, K.mat('f_base'))
    K.dirbox('fume_post', (px, hy, .10), (px, hy, DUCT_Z-.24), .08, .08, K.mat('f_frame'))
    K.dirbox('fume_saddle', (px, hy-.22, DUCT_Z-.25), (px, hy+.22, DUCT_Z-.25), .09, .06, K.mat('f_frame'))


# ------------------------------------------------------------------ power

def _e_power(K, level):
    """The left wing is the transformer house: roof bushings and the bus tubes that rise
    and cross into the chamber over the bath to the mast's terminals, carried on a post at
    the wing's inner edge. Yard transformers stand on gravel in front of the wing (one at
    L1, two at L2, three at L3), each with a bus duct into the wing's front wall."""
    x0, x1, y0, y1 = HALL
    roof = LWING_H+.09
    bx, by = x0+.55, .20
    K._fine_mode = True
    for k in range(3):
        px, py = bx+.14*k, by+(k-1)*.15
        K.cyl(f'bus{k}_bushing', px, py, roof+.11, .055, .22, K.mat('p_insulator'), segments=12)
        K.washer(f'bus{k}_bushing_flange', (px, py, roof+.02), (0, 0, 1), .06, .11, .04, K.mat('f_frame'), seg=12)
        ty = BY+(k-1)*.15
        pts = [(px, py, roof+.20), (px, py, BUS_Z), (px, ty, BUS_Z), (MAST_X-MAST_W/2-.07, ty, BUS_Z)]
        K.pipe_run(f'bus{k}', pts, .038, mat=K.mat('f_zinc'), bend=.09)
    K._fine_mode = False
    K.dirbox('bus_post', (WING_X1+.26, BY-.03, roof), (WING_X1+.26, BY-.03, BUS_Z-.08), .07, .07, K.mat('f_frame'))
    K.dirbox('bus_post_arm', (WING_X1+.26, BY-.22, BUS_Z-.08), (WING_X1+.26, BY+.22, BUS_Z-.08), .05, .06, K.mat('f_frame'))
    K.box('bus_post_foot', WING_X1+.26, BY-.03, roof+.03, .18, .18, .06, K.mat('f_frame'))
    tx0, tx1, ty0, ty1 = TX_YARD
    K.box('tx_gravel', (tx0+tx1)/2, (ty0+ty1)/2, .035, tx1-tx0, ty1-ty0, .07, K.mat('membrane'))
    K.box('tx_kerb', (tx0+tx1)/2, (ty0+ty1)/2, .02, tx1-tx0+.08, ty1-ty0+.08, .04, K.mat('f_base'))
    n = {1: 1, 2: 2, 3: 3}[level]
    for i in range(n):
        x = tx0+.38+i*.36 if n == 3 else tx0+.30+i*.52
        K.transformer(f'tx{i}', x, (ty0+ty1)/2, .07, s=.95, fins=4)
        K.dirbox(f'tx{i}_duct', (x, (ty0+ty1)/2+.17, .07+.44), (x, y0-.01, .07+.44), .09, .11, K.mat('f_zinc'))
        _v2_flange(K, f'tx{i}_collar', x, y0-.02, .07+.44, 'y', w=.16, h=.18)
    for ob in K.col.objects:
        if ob.name.startswith('tx') and ob.type == 'MESH':
            mats = ob.data.materials
            for i, m in enumerate(mats):
                if m == K.mat('f_frame'): mats[i] = K.mat('p_tx')


# ------------------------------------------------------------------ storage range

def _e_silo(K, i, sx, sy, feed_to):
    """A zinc silo on a tall four-leg frame with a hopper, discharging by a pipe into the
    wing's back wall. The legs are tall so the body shows over the house roof."""
    L = SILO_LEG
    K.box(f'silo{i}_pad', sx, sy, .08, .84, .84, .16, K.mat('f_base'))
    for lx, ly in ((-.27, -.27), (.27, -.27), (-.27, .27), (.27, .27)):
        K.box(f'silo{i}_leg', sx+lx, sy+ly, .16+L/2, .08, .08, L, K.mat('f_frame'))
    K.washer(f'silo{i}_support_ring', (sx, sy, .16+L), (0, 0, 1), .30, .42, .08, K.mat('f_frame'))
    for z in (.16+L*.33, .16+L*.66):
        K.washer(f'silo{i}_tie_ring', (sx, sy, z), (0, 0, 1), .35, .41, .05, K.mat('f_frame'))
    z0 = .16+L
    K.cone(f'silo{i}_hopper', sx, sy, z0-.26, .10, .33, .52, K.mat('f_zinc'))
    K.cyl(f'silo{i}_body', sx, sy, z0+.95, .33, 1.90, K.mat('f_zinc'))
    K.dome_cap(f'silo{i}_cap', sx, sy, z0+1.90, .33, .12, K.mat('f_zinc'), rings=4)
    K._fine_mode = True
    K.washer(f'silo{i}_band', (sx, sy, z0+.45), (0, 0, 1), .325, .35, .05, K.mat('f_frame'))
    K.washer(f'silo{i}_band_hi', (sx, sy, z0+1.45), (0, 0, 1), .325, .35, .05, K.mat('f_frame'))
    K._fine_mode = False
    fx, fy, fz = feed_to
    pts = [(sx, sy, z0-.52), (sx, sy+.001, fz), (sx, fy, fz)] if abs(fx-sx) < .05 else [(sx, sy, z0-.52), (sx, sy+.001, fz), (fx, sy, fz), (fx, fy, fz)]
    K.pipe_run(f'silo{i}_feed', pts, .07, mat=K.mat('white_pipe'), bend=.10)


def _e_storage_range(K, level):
    """Behind the house: a brick elevator tower rising above its roof, with the bucket
    elevator casing on the tower's lit flank up to a head house and a short covered gallery
    to the chute house over the back of the rim; from L2 a storage wing along the back of
    the house fed by tall silos behind it and by the scrap conveyor."""
    tx0, tx1, ty0, ty1 = TOWER
    tcx, tcy = (tx0+tx1)/2, (ty0+ty1)/2
    _f_shed(K, 'tower', tcx, tcy, tx1-tx0, ty1-ty0, TOWER_H, door=False)
    K._fine_mode = True
    _v2_window(K, 'tower_window_end', '+X', (tx1+.055, tcy+.30, TOWER_H-.75), .30, .50, cols=1, rows=2)
    _v2_window(K, 'tower_window_end_lo', '+X', (tx1+.055, tcy+.30, TOWER_H-1.75), .30, .50, cols=1, rows=2)
    _v2_window(K, 'tower_window_back', '+Y', (tcx, ty1+.055, TOWER_H-.75), .62, .50, cols=2, rows=2)
    _v2_window(K, 'tower_window_rear', '-X', (tx0-.055, tcy, TOWER_H-.75), .62, .50, cols=2, rows=2)
    K._fine_mode = False
    K.door('tower_rear_door', '-X', (tx0-.02, tcy-.30, .55), .50, .90)
    _v2_eave_gutters(K, 'tower', tcx, tcy, tx1-tx0, ty1-ty0, TOWER_H)
    _v2_downpipe(K, 'tower_dp_back', tx0-.06, ty1+.12, TOWER_H+.05, 0.0)
    # Elevator casing on the tower's lit flank, boot at the wing roof, head house on top.
    ex = tx1+.22
    base = WING_H+.09 if level >= 2 else .16
    K.box('elevator_casing', ex, ELEV_Y, (base+.44+ELEV_TOP-.30)/2, .44, .52, ELEV_TOP-.30-base-.44, K.mat('f_sheet'))
    K.box('elevator_boot', ex, ELEV_Y, base+.22, .50, .60, .44, K.mat('f_frame'))
    K._fine_mode = True
    for z in (base+1.0, base+1.9):
        K.box('elevator_casing_seam', ex+.225, ELEV_Y, z, .012, .50, .012, K.mat('f_frame'))
    K._fine_mode = False
    _v2_gable_house(K, 'elevator_head', ex, ELEV_Y, ELEV_TOP-.55, .66, .72, 'y', eave=ELEV_TOP-.08)
    gz = ELEV_TOP-.30
    hy0 = ELEV_Y-.36
    K.conveyor_bridge('charge_gallery', (ex, hy0+.01, gz), (ex, CHUTE_Y+.35, gz), w=.36, h=.34, ribs=3)
    _v2_gallery_cover(K, 'charge_gallery_cover', (ex, hy0-.08, 0), (ex, CHUTE_Y+.42, 0), top=gz+.17)
    _v2_flange(K, 'charge_gallery_flange_head', ex, hy0-.04, gz, 'y')
    _v2_flange(K, 'charge_gallery_flange_chute', ex, CHUTE_Y+.40, gz, 'y')
    # The chute house stands on two legs on the house roof over the back of the rim; the
    # chute drops from its front gable into the bath.
    _v2_gable_house(K, 'chute_house', ex, CHUTE_Y, gz-.42, .62, .70, 'y', eave=gz+.08)
    for s in (-1, 1):
        for dy in (-.22, .22):
            K.box('chute_house_foot', ex+s*.22, CHUTE_Y+dy, _e_roof_z(CHUTE_Y+dy)+.05, .18, .18, .08, K.mat('f_zinc'))
            K.dirbox('chute_house_leg', (ex+s*.22, CHUTE_Y+dy, _e_roof_z(CHUTE_Y+dy)+.09), (ex+s*.22, CHUTE_Y+dy, gz-.42), .08, .08, K.mat('f_frame'))
    # The chute drops from the house's floor through the roof into the bath: a square
    # casing with a collar at the roof.
    cz = _e_roof_z(CHUTE_Y-.10)
    K.box('chute', ex, CHUTE_Y-.10, (cz-.30+gz-.42)/2, .30, .30, gz-.42-(cz-.30), K.mat('f_zinc'))
    K.box('chute_collar', ex, CHUTE_Y-.10, cz+.05, .42, .42, .10, K.mat('f_frame'))
    if level == 1:
        # A short brick bunker where the wing will stand, feeding the tower's boot.
        _r_block(K, 'wing', tx1, tx1+1.10, ty0, ty0+1.10, 1.60, wall='f_brick')
        return
    # Storage wing: brick, stone coping, membrane roof, windows and a door on its lit end.
    wx0, wx1, wy0, wy1 = WING
    roof = _r_block(K, 'wing', wx0, wx1, wy0, wy1, WING_H, wall='f_brick')
    K._fine_mode = True
    _pp_window(K, 'wing_window_end', '+X', (wx1+.055, (wy0+wy1)/2+.28, 1.35), .40, .50, k=.6)
    _pp_window(K, 'wing_window_back0', '+Y', (.50, wy1+.055, 1.35), .44, .50, k=.6)
    _pp_window(K, 'wing_window_back1', '+Y', (1.30, wy1+.055, 1.35), .44, .50, k=.6)
    K._fine_mode = False
    _pp_door(K, 'wing_door_end', '+X', (wx1+.02, (wy0+wy1)/2-.28, .08+.85/2), .42, .85)
    K.box('wing_step', wx1+.14, (wy0+wy1)/2-.28, .04, .20, .56, .08, K.mat('stone'))
    K.box('wing_gutter', (wx0+wx1)/2, wy1+.10, roof-.02, wx1-wx0, .08, .07, K.mat('silver'))
    _v2_downpipe(K, 'wing_dp', wx1+.10, wy1+.10, roof-.05, 0.0)
    # Tall silos behind the wing discharge into its back wall.
    for i, (sx, sy) in enumerate(SILOS[:3 if level == 3 else 2]):
        fx = min(sx, wx1-.20)
        _e_silo(K, i, sx, sy, (fx, wy1+.02, 1.90))
        _v2_flange(K, f'silo{i}_collar', fx, wy1+.03, 1.90, 'y', w=.22, h=.22)


# ------------------------------------------------------------------ yard

def _e_scrap_bay(K, crane):
    """Brick scrap bay open to the front at the front right, the heap showing over its
    walls, a charging bucket, and from L2 a yellow goliath crane over it."""
    x0, x1, y0, y1 = SCRAP
    h = .95
    brick = K.mat('f_brick')
    K.box('scrap_footing', (x0+x1)/2, (y0+y1)/2, .04, x1-x0+.10, y1-y0+.10, .08, K.mat('f_base'))
    K.box('scrap_wall_back', (x0+x1)/2, y1-.06, .08+h/2, x1-x0, .12, h, brick)
    for s, xe in ((-1, x0+.06), (1, x1-.06)):
        K.box(f'scrap_wall_end{s}', xe, (y0+y1)/2, .08+h/2, .12, y1-y0, h, brick)
        K.box(f'scrap_coping_end{s}', xe, (y0+y1)/2, .08+h+.03, .16, y1-y0+.04, .06, K.mat('stone'))
    K.box('scrap_coping_back', (x0+x1)/2, y1-.06, .08+h+.03, x1-x0+.08, .16, .06, K.mat('stone'))
    cx, cy = (x0+x1)/2, (y0+y1)/2+.05
    K.dome_cap('scrap_heap', cx, cy, .09, .38, .78, K.mat('f_steel'), rings=6)
    K._fine_mode = True
    for i, (dx, dy, s_, m) in enumerate(((-.22, -.18, .14, 'f_zinc'), (.20, -.22, .12, 'f_frame'), (.05, .22, .16, 'f_zinc'),
                                         (-.28, .14, .11, 'f_frame'), (.26, .10, .10, 'f_zinc'), (0, -.02, .13, 'f_frame'))):
        K.rotbox(f'scrap_lump{i}', cx+dx*.8, cy+dy*.8, .08+s_/2+(.78 if i == 5 else .45), s_*1.6, s_, s_, K.mat(m), 'Z', 20*i)
    K._fine_mode = False
    if crane:
        z = 2.35
        for s, lx in ((-1, x0-.12), (1, x1+.14)):
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


def _e_scrap_conveyor(K):
    """Covered conveyor from the scrap bay's back, climbing beside the house's end wall,
    level along the range's end, into the range's end wall square-on through a flange."""
    x = CONVEYOR_X
    y_top = WING[2]+.50
    path = [(SCRAP[3]+.02, .95), (SCRAP[3]+.40, .95), (y_top-.55, 2.05), (y_top+.30, 2.05)]
    _e_bent_gallery_y(K, 'scrap_conveyor', path, x, .19, .15, 'f_zinc')
    _v2_gallery_cover(K, 'scrap_conveyor_cover', (x, y_top-.50, 0), (x, y_top+.30, 0), w=.44, top=2.05+.17)
    # The level top run turns into the range's end wall through a short stub and flange.
    K.dirbox('scrap_conveyor_stub', (x, y_top+.30, 2.05), (WING[1]-.02, y_top+.30, 2.05), .34, .30, K.mat('f_zinc'))
    _v2_flange(K, 'scrap_conveyor_flange', WING[1]+.03, y_top+.30, 2.05, 'x', w=.46, h=.42)
    K._fine_mode = True
    for ky in (SCRAP[3]+.40, (SCRAP[3]+.40+y_top-.55)/2, y_top-.55):
        kz = .95+(2.05-.95)*((ky-(SCRAP[3]+.40))/((y_top-.55)-(SCRAP[3]+.40))) if ky > SCRAP[3]+.40 else .95
        for s in (-1, 1):
            K.box('scrap_conveyor_foot', x+s*.26, ky, .05, .16, .16, .10, K.mat('f_base'))
            K.dirbox('scrap_conveyor_leg', (x+s*.26, ky, .10), (x+s*.26, ky, kz-.18), .06, .06, K.mat('f_frame'))
        K.dirbox('scrap_conveyor_bearing', (x-.27, ky, kz-.18), (x+.27, ky, kz-.18), .07, .08, K.mat('f_frame'))
    K._fine_mode = False
    K.box('scrap_conveyor_hopper', x, SCRAP[3]-.20, .60, .50, .50, .50, K.mat('f_zinc'))
    K.box('scrap_conveyor_hopper_mouth', x, SCRAP[3]-.20, .86, .40, .40, .02, K.mat('ink_black'))


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
    _r_pad(K, 'site_pad_front', HALL[0], HALL[1], -1.85, HALL[2])
    _r_pad(K, 'site_pad_scrap', HALL[1], 3.05, -1.85, 2.30)
    _r_pad(K, 'site_pad_plant', 3.05, STACK_XY[0]+.42, .40, STACK_XY[1]+.42)
    _e_house(K)
    _e_platform(K)
    furnace = _e_furnace(K)
    _e_fume(K, furnace['duct_start'], level)
    _e_chimney(K)
    _e_power(K, level)
    _e_storage_range(K, level)
    _e_scrap_bay(K, crane=level >= 2)
    if level >= 2:
        _e_scrap_conveyor(K)
    _e_ladle_car(K, 'ladle', LADLE_XY[0], LADLE_XY[1])
    if level == 3:
        _e_ladle_car(K, 'ladle_b', LADLE_XY[0]+.75, LADLE_XY[1]+.05)
    return _r_finish(K, level, 'eaf v2: furnace inside its chamber under a slanted roof, brick wing with transformers, tower and silos, bag house, chimney')
