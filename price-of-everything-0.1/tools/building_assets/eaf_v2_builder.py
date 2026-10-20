"""The electric arc furnace, rebuilt from scratch in the catalogue look: the electrode house.

Executed in sprite_kit's namespace after furnace_builder.py, furnace_v2_builder.py,
refinery_v2_builder.py and power_plant_v2_builder.py, whose palette and helpers it shares.
Staged as family 'eaf_v2'; it installs as 'eaf'.

Screen vocabulary at this camera: back = +Y (top-right), right = +X (lower-right),
front = -Y (bottom-left), left = -X (upper-left).

Composition (dreamloop round 2, direction D, with the owner's asks: a larger bath and a back
range for storage, hoppers and power). A closed refractory furnace house on a brick base
course; the furnace is so large that its shell rises through the roof inside a refractory
housing, the family's vessel-through-roof joint, so the open bath glows above the roof with
the three graphite electrodes standing over it on arms from a dark mast. A side-draft hood at
the rim takes the fume by a white duct to the bag house and on to one thin brick chimney.
Behind the house a brick storage range with zinc silos on legs feeding it, a bucket elevator
and a level gallery that delivers a chute into the back of the bath. The transformer vault
stands at the back right with its bus tubes rising to the mast. Scrap waits in a brick bay at
the front right under a goliath crane and climbs a covered conveyor into the storage range.
The tap hole glows in the front wall over the ladle car.

Flows: scrap bay -> crane -> conveyor -> storage range; silos -> storage range; storage ->
elevator -> gallery -> chute -> bath; vault -> bus tubes -> mast -> arms -> electrodes ->
bath; bath -> tap hole -> ladle car; fume -> hood -> duct -> bag house -> flue -> chimney;
dust -> hopper -> skip; rain -> gutters -> downpipes -> drains.

Fixed across levels: the house, the furnace, the mast, the chimney and the vault's place.
L1: one silo and a short bunker instead of the range, a switch kiosk, the duct dropping to a
ground flue, no crane. L2: the full range with elevator and gallery, two silos, the vault,
the bag house, the goliath crane. L3: a third silo, a second ladle, a deeper bag house and a
second transformer on the vault's apron.
"""
import math
from mathutils import Vector

PALETTE.update({
    'e_graphite': (.030, .032, .036),      # electrodes: blacker than the frame steel
})

EAF_ROLES = {'stair': 'r_deck', 'walkway': 'r_deck', 'handrail': 'r_yellow', 'rail': 'r_yellow',
             'pipe': 'white_pipe', 'duct': 'white_pipe', 'opening': 'ink_black',
             'gear': 'f_frame', 'wall_grey': 'f_base', 'window_frame': 'p_insulator'}

# ---- furnace house ------------------------------------------------------------------------
HALL = (-1.90, 1.90, -.90, 1.60)      # x0, x1, y0, y1
EAVE = 3.10
RISE = .50                            # roof rise; the ridge runs along X
BASE_Z = .58                          # brick base course under the cladding

# ---- the furnace ------------------------------------------------------------------------
BX, BY = .00, .35                     # on the ridge line, so the housing cuts the roof symmetrically
BOWL_R, BOWL_RISE, BOWL_WALL = 1.05, .95, .10
RIM_Z = 4.30
MELT_DROP = .16
HOUSING_R = BOWL_R+.08
HOUSING_TOP = RIM_Z-.38               # the shell shows above the refractory housing from here
ROD_R, ROD_RING = .13, .42
ROD_ANGLES = (75.0, 195.0, 315.0)     # even screen columns (see the dreamloop notes)
ROD_TOPS = (5.55, 5.95, 5.75)
ROD_SUBMERGE = .10
MAST_X = 1.50                         # beside the furnace on the lit side, clear of its screen width
MAST_W = .30
ARM_DROP = .40

# ---- plant --------------------------------------------------------------------------
HOOD_XY = (BX+.95, BY+.72)            # side-draft hood at the rim, back right
DUCT_Z = RIM_Z-.05
BAG = (3.00, 3.65, 1.30, 2.10)        # bag house behind the vault; L3 deepens it toward the front
BAG_Z = (1.50, 3.40)
STACK_XY = (4.15, 1.85)               # one thin chimney, same place at every level
STACK_TOP = 5.40
FLUE_Z = .95
GROUND_FLUE_Z = .45
VAULT = (3.00, 3.80, .15, .95)        # transformer vault at the front of the yard, in view
VAULT_H = 2.50
BUS_Z = 5.55                          # bus tubes over everything to the mast's head
TOWER = (-1.55, -.25, 1.70, 3.00)     # brick elevator tower behind the house, rising above its roof
TOWER_H = 4.40
WING = (-.25, 1.90, 1.70, 2.90)       # storage wing from the tower along the back of the house
WING_H = 2.40
SILOS = ((.70, 3.40), (1.50, 3.40), (2.30, 3.40))    # tall silos behind the wing; the third at L3
SILO_LEG = 2.60                       # legs tall enough for the bodies to show over the house roof
ELEV_Y = 2.70                         # bucket elevator casing on the tower's lit flank
ELEV_TOP = 5.05
CHUTE_Y = 1.62                        # chute house over the back of the rim
SCRAP = (2.05, 2.85, -1.45, -.65)     # brick scrap bay, front right
CRANE_Y = -1.05
CONVEYOR_X = 2.45                     # the covered conveyor climbs beside the house's end wall
TAP_X = .70
LADLE_XY = (.70, -1.15)


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
    """Top of the roof sheet at y across the house."""
    x0, x1, y0, y1 = HALL
    cy = (y0+y1)/2
    return EAVE+RISE*(1-abs(y-cy)/((y1-y0)/2))+.06


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
    x0, x1, y0, y1 = HALL
    w, d = x1-x0, y1-y0
    cx, cy = (x0+x1)/2, (y0+y1)/2
    wall, frame, brick = K.mat('f2_refractory'), K.mat('f_frame'), K.mat('f_brick')
    K.box('house_footing', cx, cy, .08, w+.10, d+.10, .16, K.mat('f_base'))
    t = .08

    def slab(nm, sx_, sy_, lx, ly):
        # Brick base course under the cladding, stacked in one plane: nothing buried.
        K.box(nm+'_base', sx_, sy_, (.10+BASE_Z)/2, lx, ly, BASE_Z-.10, brick)
        K.box(nm, sx_, sy_, (BASE_Z+EAVE)/2, lx, ly, EAVE-BASE_Z, wall)
    slab('house_front', cx, y0+t/2, w, t)
    slab('house_back', cx, y1-t/2, w, t)
    for s, xe in ((-1, x0+t/2), (1, x1-t/2)):
        slab('house_end'+str(s), xe, cy, t, d-2*t)
    # Dark portal columns on the wall faces, carrying the eave.
    for px in [x0+.06+(w-.12)*i/4 for i in range(5)]:
        for side, py in (('front', y0-.03), ('back', y1+.03)):
            K.box('house_column_'+side, px, py, (.12+EAVE)/2, .11, .07, EAVE-.12, frame)
    for s, xe in ((-1, x0-.03), (1, x1+.03)):
        for py in (y0+.06, cy, y1-.06):
            K.box('house_column_end', xe, py, (.12+EAVE)/2, .07, .11, EAVE-.12, frame)
    # Gables and the standing-seam roof to the ridge; the furnace housing cuts through it.
    for s, xe in ((-1, x0+t/2), (1, x1-t/2)):
        K.prism('house_gable'+str(s), (xe, cy, 0), (0, 1), [(-d/2, EAVE), (0, EAVE+RISE), (d/2, EAVE)], t, wall)
    k = RISE/(d/2); o = .09
    for s in (-1, 1):
        ya, yb = (-d/2-o, 0) if s < 0 else (0, d/2+o)
        za, zb = (EAVE-k*o, EAVE+RISE) if s < 0 else (EAVE+RISE, EAVE-k*o)
        K.prism('house_roof'+str(s), (cx, cy, 0), (0, 1), [(ya, za), (yb, zb), (yb, zb+.055), (ya, za+.055)], w+.16, K.mat('f_roof'))
    for s, (ra, rb) in ((-1, (x0-.08, BX-HOUSING_R-.02)), (1, (BX+HOUSING_R+.02, x1+.08))):
        K.dirbox('house_ridge'+str(s), (ra, cy, EAVE+RISE+.04), (rb, cy, EAVE+RISE+.04), .16, .07, K.mat('f_roof'))
    K._fine_mode = True
    n = max(2, round(w/.26))
    for j in range(n+1):
        px = x0+j*w/n
        if abs(px-BX) < HOUSING_R+.05: continue
        for side in (-1, 1):
            K.dirbox('house_roof_seam', (px, cy+side*(d/2+.06), EAVE+.05), (px, cy+side*.40, EAVE+RISE*(1-.40/(d/2))+.06), .012, .012, K.mat('f_roof'))
    # Roof vents either side of the housing, where a monitor cannot run.
    for vx in (x0+.55, x1-.55):
        for vy in (cy-.45, cy+.45):
            K.box('house_vent', vx, vy, _e_roof_z(vy)+.10, .22, .22, .18, K.mat('silver'))
            K.box('house_vent_cap', vx, vy, _e_roof_z(vy)+.21, .27, .27, .04, frame)
    K._fine_mode = False
    # Rainwater: gutters on both eaves and three downpipes to drains.
    for s, gy in ((-1, y0-o-.02), (1, y1+o+.02)):
        K.box('house_gutter'+str(s), cx, gy, EAVE-k*o+.02, w+.12, .07, .06, K.mat('silver'))
    _v2_downpipe(K, 'house_dp_fl', x0+.12, y0-o-.02, EAVE-k*o, 0.0)
    _v2_downpipe(K, 'house_dp_fr', x1-.12, y0-o-.02, EAVE-k*o, 0.0)
    _v2_downpipe(K, 'house_dp_bl', x0+.12, y1+o+.02, EAVE-k*o, 0.0)
    # Windows and doors, half-size frames: the front carries two pairs of windows and a
    # personnel door beside the tap hole, the lit end wall a window, door and louvre.
    K._fine_mode = True
    for i, wx in enumerate((-1.30, -.70, 1.20)):
        _pp_window(K, f'house_window_front{i}', '-Y', (wx, y0-.055, 1.75), .46, .60, k=.6)
        _pp_window(K, f'house_window_front_hi{i}', '-Y', (wx, y0-.055, 2.60), .46, .40, k=.6)
    _pp_window(K, 'house_window_end', '+X', (x1+.055, .90, 1.75), .44, .60, k=.6)
    _pp_louvre(K, 'house_louvre_end', '+X', (x1+.03, .90, 2.65), w=.44, h=.40)
    _pp_louvre(K, 'house_louvre_front', '-Y', (-.10, y0-.03, 2.60), w=.50, h=.40)
    K._fine_mode = False
    _pp_door(K, 'house_door_front', '-Y', (-.10, y0-.02, .14+.95/2), .50, .95)
    _pp_door(K, 'house_door_end', '+X', (x1+.02, .20, .14+.95/2), .50, .95)
    K.box('house_step_front', -.10, y0-.14, .04, .66, .20, .08, K.mat('stone'))
    K.box('house_step_end', x1+.14, .20, .04, .20, .66, .08, K.mat('stone'))
    # The tap hole: a dark reveal with the glow of the tapping bay, over the ladle car.
    glow = _emissive('e_glow', (1.0, .42, .09), .42)
    K.box('tap_reveal', TAP_X, y0-.03, .14+.36, .56, .05, .72, K.mat('ink_black'))
    K.box('tap_glow', TAP_X, y0-.02, .14+.33, .40, .05, .50, glow)
    K.box('tap_lintel', TAP_X, y0-.04, .14+.76, .66, .06, .08, K.mat('stone'))
    K.box('tap_launder', TAP_X, y0-.22, .14+.30, .18, .40, .10, K.mat('f_oxide'))


# ------------------------------------------------------------------ the furnace

def _e_furnace(K):
    """The shell through the roof in its refractory housing, the open bath above the roof,
    the electrodes on arms from the mast, the side-draft hood at the rim."""
    frame, zinc = K.mat('f_frame'), K.mat('f_zinc')
    roof_z = _e_roof_z(BY)
    # Refractory housing from inside the roof up to a dark cap ring at the shell.
    z0 = roof_z-.45
    K.cyl('furnace_housing', BX, BY, (z0+HOUSING_TOP)/2, HOUSING_R, HOUSING_TOP-z0, K.mat('f2_refractory'), segments=28)
    K.washer('furnace_housing_cap', (BX, BY, HOUSING_TOP), (0, 0, 1), _e_shell_r(HOUSING_TOP)-.01, HOUSING_R+.05, .10, frame, seg=28)
    _e_bowl(K, 'furnace_shell', BX, BY, RIM_Z, BOWL_R, BOWL_RISE, BOWL_WALL, K.mat('f_shell'), K.mat('f_oxide'))
    K._fine_mode = True
    for z in (RIM_Z-.18, RIM_Z-.30):
        rr = _e_shell_r(z)
        K.washer(f'furnace_hoop{int(z*100)}', (BX, BY, z), (0, 0, 1), rr-.02, rr+.065, .07, zinc)
    K._fine_mode = False
    # The bath.
    melt = _emissive('e_melt', (.95, .32, .02), 1.0)
    melt_z = RIM_Z-MELT_DROP; rm = _e_melt_radius()
    K.cyl('furnace_melt', BX, BY, melt_z, rm, .05, melt, segments=28)
    K.washer('furnace_lining', (BX, BY, melt_z+.012), (0, 0, 1), rm-.07, rm+.085, .036, K.mat('f_oxide'))
    # Electrodes with silver clamps on arms from the mast.
    for i in range(3):
        rx, ry = _e_rod_xy(i); z1 = ROD_TOPS[i]
        K.cyl(f'electrode{i}', rx, ry, (melt_z-ROD_SUBMERGE+z1)/2, ROD_R, z1-(melt_z-ROD_SUBMERGE), K.mat('e_graphite'), segments=20)
        az = z1-ARM_DROP
        K.cyl(f'electrode{i}_clamp', rx, ry, az, ROD_R+.06, .24, zinc, segments=20)
        K._fine_mode = True
        K.washer(f'electrode{i}_ring', (rx, ry, az-.22), (0, 0, 1), ROD_R-.005, ROD_R+.035, .06, zinc)
        K._fine_mode = False
        mx = MAST_X-MAST_W/2
        K.dirbox(f'electrode{i}_bracket', (MAST_X, BY, az), (MAST_X, ry, az), .15, .15, frame)
        K.dirbox(f'electrode{i}_arm', (mx+.02, ry, az), (rx+ROD_R, ry, az), .12, .14, zinc)
        K.box(f'electrode{i}_arm_root', mx-.02, ry, az, .10, .22, .22, frame)
    # The mast rises through the roof on the lit side, with a collar at the roof.
    mt = max(ROD_TOPS)-ARM_DROP+.22
    mz = _e_roof_z(BY)
    K.box('mast', MAST_X, BY, (mz-.40+mt)/2, MAST_W, MAST_W, mt-mz+.40, frame)
    K.box('mast_cap', MAST_X, BY, mt+.03, MAST_W+.08, MAST_W+.08, .06, zinc)
    K.box('mast_collar', MAST_X, BY, mz+.06, MAST_W+.16, MAST_W+.16, .12, zinc)
    for k in range(3):
        K.box(f'mast_terminal{k}', MAST_X+MAST_W/2+.02, BY+(k-1)*.15, BUS_Z, .10, .08, .14, zinc)
    # Side-draft hood at the rim, back right, open toward the bath; the duct leaves its back.
    hx, hy = HOOD_XY
    K.box('hood', hx, hy, DUCT_Z, .62, .54, .50, zinc)
    K.box('hood_mouth', hx-.30, hy-.26, DUCT_Z, .06, .40, .40, K.mat('ink_black'))
    K.box('hood_stand', hx+.10, hy+.10, (HOUSING_TOP+DUCT_Z-.25)/2, .12, .12, DUCT_Z-.25-HOUSING_TOP, frame)
    return dict(mast_top=mt, duct_start=(hx+.30, hy, DUCT_Z))


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
    """From the hood at the rim: along +X over the house's eave, then down into the bag
    house's lid (L2, L3), or to the ground and into the chimney base as a low flue (L1)."""
    sx, sy = STACK_XY
    if level >= 2:
        cxb, cyb = _e_bag_house(K, deep=level == 3)
        pts = [start, (cxb, start[1], DUCT_Z), (cxb, cyb, DUCT_Z), (cxb, cyb, BAG_Z[1]+.08)]
        K.pipe_run('fume_duct', pts, .21, mat=K.mat('white_pipe'), bend=.32)
        K.washer('fume_collar_bag', (cxb, cyb, BAG_Z[1]+.10), (0, 0, 1), .20, .28, .06, K.mat('f_frame'), seg=20)
    else:
        dx = sx-.95
        pts = [start, (dx, start[1], DUCT_Z), (dx, start[1], GROUND_FLUE_Z), (dx, sy-.15, GROUND_FLUE_Z), (sx-.31, sy-.15, GROUND_FLUE_Z)]
        K.pipe_run('fume_duct', pts, .19, mat=K.mat('white_pipe'), bend=.30)
        K.washer('fume_collar_stack', (sx-.32, sy-.15, GROUND_FLUE_Z), (1, 0, 0), .18, .24, .04, K.mat('f_frame'), seg=16)
        K.box('fume_drop_foot', dx, start[1], .05, .32, .32, .10, K.mat('f_base'))
    # A trestle carries the run where it leaves the house's eave.
    px = 2.85
    K.box('fume_post_foot', px, start[1], .05, .18, .18, .10, K.mat('f_base'))
    K.dirbox('fume_post', (px, start[1], .10), (px, start[1], DUCT_Z-.24), .08, .08, K.mat('f_frame'))
    K.dirbox('fume_saddle', (px, start[1]-.22, DUCT_Z-.25), (px, start[1]+.22, DUCT_Z-.25), .09, .06, K.mat('f_frame'))


# ------------------------------------------------------------------ power

def _e_vault(K, level):
    """Brick transformer vault behind the bag house: stone coping, membrane roof, cooling
    louvres on its lit faces, a door, three roof bushings and the bus tubes rising over
    everything to the mast's head. L1 has a low switch kiosk in the same place; L3 adds a
    yard transformer on the vault's apron."""
    x0, x1, y0, y1 = VAULT
    if level == 1:
        kx0, kx1, ky0, ky1 = x0, x0+.70, y0, y0+.70
        roof = _r_block(K, 'vault', kx0, kx1, ky0, ky1, 1.35, wall='f_brick')
        _pp_door(K, 'vault_door', '-Y', ((kx0+kx1)/2, ky0-.02, .08+.75/2), .40, .75, ribs=3)
        K._fine_mode = True
        _pp_louvre(K, 'vault_louvre', '+X', (kx1+.03, (ky0+ky1)/2, .85), w=.36, h=.30)
        K._fine_mode = False
        bx, by0_ = (kx0+kx1)/2, ky0+.35
    else:
        roof = _r_block(K, 'vault', x0, x1, y0, y1, VAULT_H, wall='f_brick')
        _pp_door(K, 'vault_door', '-Y', (x0+.26, y0-.02, .08+.85/2), .42, .85)
        K.box('vault_step', x0+.26, y0-.14, .04, .56, .20, .08, K.mat('stone'))
        K._fine_mode = True
        for z in (1.00, 1.90):
            _pp_louvre(K, f'vault_louvre{int(z*10)}', '+X', (x1+.03, (y0+y1)/2, z), w=.52, h=.44)
        _pp_louvre(K, 'vault_louvre_front', '-Y', (x1-.24, y0-.03, 1.80), w=.36, h=.40)
        K._fine_mode = False
        bx, by0_ = x0+.30, y0+.25
    # Bushings on the roof; each tube rises on its own line, runs -Y past the bag house and
    # the duct, then -X on its mast terminal's line. Nested, so nothing crosses.
    K._fine_mode = True
    for k in range(3):
        px, py = bx+.14*k, by0_+.14*k
        K.cyl(f'bus{k}_bushing', px, py, roof+.11, .055, .22, K.mat('p_insulator'), segments=12)
        K.washer(f'bus{k}_bushing_flange', (px, py, roof+.02), (0, 0, 1), .06, .11, .04, K.mat('f_frame'), seg=12)
        ty = BY+(k-1)*.15
        pts = [(px, py, roof+.20), (px, py, BUS_Z), (px, ty, BUS_Z), (MAST_X+MAST_W/2+.07, ty, BUS_Z)]
        K.pipe_run(f'bus{k}', pts, .038, mat=K.mat('f_zinc'), bend=.09)
    K._fine_mode = False
    # A lattice post carries the three tubes where they cross the yard.
    px = 2.85
    K.box('bus_post_foot', px, BY, .05, .18, .18, .10, K.mat('f_base'))
    K.dirbox('bus_post', (px, BY-.03, .10), (px, BY-.03, BUS_Z-.08), .07, .07, K.mat('f_frame'))
    K.dirbox('bus_post_arm', (px, BY-.22, BUS_Z-.08), (px, BY+.22, BUS_Z-.08), .05, .06, K.mat('f_frame'))
    if level == 3:
        K.transformer('yard_tx', x1+.45, (y0+y1)/2, .07, s=1.1, fins=5)
        for ob in K.col.objects:
            if ob.name.startswith('yard_tx') and ob.type == 'MESH':
                mats = ob.data.materials
                for i, m in enumerate(mats):
                    if m == K.mat('f_frame'): mats[i] = K.mat('p_tx')
        K.dirbox('yard_tx_duct', (x1+.01, (y0+y1)/2, 1.20), (x1+.30, (y0+y1)/2, 1.20), .14, .16, K.mat('f_zinc'))
        _v2_flange(K, 'yard_tx_collar', x1+.02, (y0+y1)/2, 1.20, 'x', w=.22, h=.24)


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
        K.box('chute_house_foot', ex+s*.22, CHUTE_Y+.12, _e_roof_z(CHUTE_Y+.12)+.05, .20, .20, .08, K.mat('f_zinc'))
        K.dirbox('chute_house_leg', (ex+s*.22, CHUTE_Y+.12, _e_roof_z(CHUTE_Y+.12)+.09), (ex+s*.22, CHUTE_Y+.12, gz-.42), .08, .08, K.mat('f_frame'))
    K.prism('chute', (ex, 0, 0), (0, -1), [(-(CHUTE_Y-.35), gz-.20), (-(CHUTE_Y-.35)-.55, gz-.62), (-(CHUTE_Y-.35)-.55, gz-.80), (-(CHUTE_Y-.35), gz-.38)], .30, K.mat('f_zinc'))
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
    # Paving follows the plant as touching rectangles: the apron in front of the house, the
    # yard right of it under the scrap bay, duct trestle and bag house.
    _r_pad(K, 'site_pad_front', HALL[0]-.10, HALL[1], -1.85, HALL[2])
    _r_pad(K, 'site_pad_scrap', HALL[1], 2.95, -1.85, 2.30)
    _r_pad(K, 'site_pad_plant', 2.95, STACK_XY[0]+.42, -.10, STACK_XY[1]+.42)
    _e_house(K)
    furnace = _e_furnace(K)
    _e_fume(K, furnace['duct_start'], level)
    _e_chimney(K)
    _e_vault(K, level)
    _e_storage_range(K, level)
    _e_scrap_bay(K, crane=level >= 2)
    if level >= 2:
        _e_scrap_conveyor(K)
    _e_ladle_car(K, 'ladle', LADLE_XY[0], LADLE_XY[1])
    if level == 3:
        _e_ladle_car(K, 'ladle_b', LADLE_XY[0]+.75, LADLE_XY[1]+.05)
    result = _r_finish(K, level, 'eaf v2 D: furnace house with the bath above the roof, storage range, vault, bag house, chimney')
    return result
