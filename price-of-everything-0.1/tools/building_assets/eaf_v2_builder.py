"""The electric arc furnace in the catalogue look: the furnace in its chamber.

Executed in sprite_kit's namespace after furnace_builder.py, furnace_v2_builder.py,
refinery_v2_builder.py and power_plant_v2_builder.py, whose palette and helpers it shares.
Staged as family 'eaf_v2'; it installs as 'eaf'.

Screen vocabulary at this camera: back = +Y (top-right), right = +X (lower-right),
front = -Y (bottom-left), left = -X (upper-left).

Composition (owner, 20 and 21 October 2026, simplified on the last pass): only the furnace,
the building over it and what the furnace needs. The bowl is large and low inside a process
chamber with an open portal front under a single slanted roof plane, high at the opening and
dropping to the back, so the opening stays tall and little roof shows; the operating deck is
raised around the bowl with a stair down into the yard, and the electrodes stand over it on
arms from a dark mast. Brick side walls with windows. One large transformer stands on the
left with its leads up to wall bushings. Behind the chamber a bag house on tall legs, drawn
as a filter, and behind that the steel stacks. L3 widens the chamber to the right for a
second shell served from the other side of the same mast, with its own hood, spout and
ladle, a wider filter with two fans and a second stack.

Flows: transformer -> leads -> wall bushings -> bus tubes -> mast -> arms -> electrodes ->
bath; bath -> spout -> launder -> ladle car; fume -> hood -> duct -> bag house (in at the
end) -> fan (out at the top) -> flue -> stack; dust -> hopper -> rotary valve -> bin; rain ->
gutter -> downpipe -> drain.

Fixed across levels: the transformer, the furnace and its mast, the first stack. L1: one
bowl, the duct straight into the stack. L2: bag house. L3: wider chamber, second bowl and
ladle, wider bag house with two fans, second stack.
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
HALL = (-1.30, 2.45, -.80, 1.60)      # x0, x1, y0, y1 of the process chamber (L1, L2)
HALL_X1_L3 = 4.55                     # L3 widens to the right for the second shell
EAVE_F, EAVE_B = 4.30, 3.10           # the slanted roof: high at the open front, low at the back
LINTEL_H = .26                        # the dark fascia across the open front; the sightline head is its underside
WIN_ROWS = (1.75, 2.70)               # two rows of two windows on the chamber's right wall, between its columns
WIN_YS = (-.25, .95)                  # the bays between the right wall's three columns

# ---- the furnace ------------------------------------------------------------------------
BX, BY = -.10, -.10                   # large and low, forward in the chamber
BOWL_R, BOWL_RISE, BOWL_WALL = 1.10, 1.00, .10
RIM_Z = 1.55
MELT_DROP = .16
DECK_Z = 1.15                         # the operating deck raised round the bowl
DECK_Y = (-1.45, 1.45)                # the deck's front and back edges
DECK_X0 = -1.18
ROD_R, ROD_RING = .12, .45
ROD_ANGLES = (75.0, 195.0, 315.0)
ROD_TOPS = (2.55, 3.05, 2.80)
ROD_SUBMERGE = .10
MAST_W = .28
MAST_X = BX+BOWL_R+.04+MAST_W/2      # right of the first shell; L3's second shell hangs off its other side
BX2 = MAST_X+MAST_W/2+.04+BOWL_R     # the second shell (L3)
ARM_DROP = .35
STAIR_X = -.95
BUS_Z = 3.45                          # bus tubes from the chamber's left wall across to the mast

# ---- plant --------------------------------------------------------------------------
TX_XY, TX_S = (-2.50, BY), 2.0        # one large transformer left of the open front
TX2_XY = (-2.80, .70)                 # the second, set back and a little further out (L2, L3)
TX_PAD = {1: (-3.25, -1.75, -.65, .45), 2: (-3.50, -1.75, -.65, 1.20), 3: (-3.50, -1.75, -.65, 1.20)}
BUNKER = (-1.25, -.05, 1.95, 2.95)    # closed storage bunker behind the chamber's left end
BUNKER_Z = (2.00, 4.40)
HOOD_DY = 1.00                        # hoods at the back of each rim; the ducts rise through the roof
DUCT_Z = 4.20                         # the duct runs back over the roof's right part, under the stack platform
DUCT_X = 3.40                         # and drops behind the chamber, outside the L1/L2 wall and over the L3 roof
BAG_Z = (2.10, 3.50)                  # the bag house box stands on tall legs so it shows over the back eave
BAG_Y = (1.90, 2.50)
BAG_X = {2: (.60, 2.50), 3: (.10, 2.50)}
FLUE_Z = 4.90
STACK_XY = (2.57, 3.00)               # the first stack behind the bag house's lit end, same place at every level
STACK2_XY = (1.60, 3.00)              # the second stack (L3)
STACK_TOP = 5.60                      # the L3 budget: stacks at the back cost height, the wide chamber costs it at the front
LADLE_Y = -1.95                       # under the launders


def _e_x1(level):
    return HALL_X1_L3 if level == 3 else HALL[1]


def _e_bowls(level):
    return [BX, BX2] if level == 3 else [BX]


def _e_rod_xy(i, bx=BX, mirror=False):
    a = math.radians(ROD_ANGLES[i])
    return bx+(-1 if mirror else 1)*ROD_RING*math.cos(a), BY+ROD_RING*math.sin(a)


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


def _e_sightline_tests(level):
    rm = _e_melt_radius()
    t = []
    for n, bx in enumerate(_e_bowls(level)):
        t += [(f'melt {n+1} far lip', bx, BY+rm, RIM_Z-MELT_DROP), (f'shell {n+1} far rim', bx, BY+BOWL_R, RIM_Z)]
        for i in range(3):
            rx, ry = _e_rod_xy(i, bx, n == 1); t.append((f'bowl {n+1} rod {i+1} tip', rx, ry, ROD_TOPS[i]))
    t.append(('mast top', MAST_X, BY+MAST_W/2, max(ROD_TOPS)-ARM_DROP+.22))
    return t


def _e_check_sightlines(level):
    """Every point the owner wants seen must cross the front plane under the fascia: with a
    roof that drops toward the back, the front eave alone decides it. And nothing may sit
    behind the right wall's front corner on screen (x+y past the jamb's), or the wall hides it."""
    head = EAVE_F-LINTEL_H; y0 = HALL[2]
    jamb = _e_x1(level)-.06+y0
    for name, x, y, z in _e_sightline_tests(level):
        if z+(y-y0) >= head: raise RuntimeError('EAF sightline buried: %s crosses at %.2f, head %.2f' % (name, z+(y-y0), head))
        if x+y >= jamb: raise RuntimeError('EAF %s hidden behind the right wall: x+y %.2f, jamb %.2f' % (name, x+y, jamb))


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


# ------------------------------------------------------------------ the building

def _e_house(K, level):
    """The process chamber: brick side walls under the roof's fall, brick back wall, the open
    front under a dark fascia with dark jamb columns, and one slanted roof plane. L3 is
    wider to the right."""
    x0, _, y0, y1 = HALL
    x1 = _e_x1(level)
    d = y1-y0; cy = (y0+y1)/2
    brick, frame = K.mat('f_brick'), K.mat('f_frame')
    K.box('house_footing', (x0+x1)/2, cy, .08, x1-x0+.10, d+.10, .16, K.mat('f_base'))
    K.box('house_floor', (x0+x1)/2, cy, .13, x1-x0-.16, d-.16, .02, K.mat('f_base'))
    t = .16
    K.box('chamber_back', (x0+x1)/2, y1-t/2, (.10+EAVE_B)/2, x1-x0, t, EAVE_B-.10, brick)
    for nm, xe in (('chamber_left', x0+t/2), ('chamber_right', x1-t/2)):
        K.prism(nm, (xe, 0, 0), (0, 1), [(y0, .10), (y1, .10), (y1, EAVE_B), (y0, EAVE_F)], t, brick)
    K.box('chamber_fascia', (x0+x1)/2, y0+.06, EAVE_F-LINTEL_H/2, x1-x0+.02, .14, LINTEL_H, frame)
    K.box('chamber_bay_shadow', (x0+x1)/2, y0+t+.02, EAVE_F-LINTEL_H-.09, x1-x0-.02, .02, .18, K.mat('ink_black'))
    for px in (x0+.06, x1-.06):
        K.box('chamber_column', px, y0-.03, (.12+EAVE_F)/2, .11, .07, EAVE_F-.12, frame)
    if level == 3:
        K.box('chamber_column', MAST_X, y0-.03, (.12+EAVE_F)/2, .11, .07, EAVE_F-.12, frame)
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
    _pp_louvre(K, 'chamber_louvre_end', '+X', (x1+.03, WIN_YS[0], 3.45), w=.44, h=.34)  # in the front bay, where the roof is still high
    K._fine_mode = False
    _pp_door(K, 'chamber_door_end', '+X', (x1+.02, -.25, .14+.95/2), .50, .95)
    K.box('chamber_step_end', x1+.14, -.25, .04, .20, .66, .08, K.mat('stone'))
    # Wall bushings on the left wall's outside, where the transformer's leads land.
    K._fine_mode = True
    for k_ in range(3):
        ty = BY+(k_-1)*.15
        K.cyl(f'wall_bushing{k_}', x0-.11, ty, BUS_Z, .055, .22, K.mat('p_insulator'), axis='X', segments=12)
        K.washer(f'wall_bushing{k_}_flange', (x0-.02, ty, BUS_Z), (1, 0, 0), .06, .11, .04, frame, seg=12)
    K._fine_mode = False


# ------------------------------------------------------------------ the furnace

def _e_deck(K, tag, x0, x1, bx, rail_right, stair):
    """One bay of the operating deck: a black-grey annular floor whose hole follows the
    shell, on dark columns, a yellow rail on its open front edge (and right edge at the
    end), and a straight stair from the yard up to its front edge."""
    y0, y1 = DECK_Y
    z = DECK_Z
    deck, frame = K.mat('r_deck'), K.mat('f_frame')
    n = 32
    outer = [(p[0], p[1]) for p in Kit.poly_rect(x0, x1, y0, y1, n)]
    start = min(range(n), key=lambda j: math.hypot(outer[j][0]-x0, outer[j][1]-y0))
    outer = outer[start:]+outer[:start]
    hole_r = BOWL_R+.08
    a0 = math.atan2(y0-BY, x0-bx)
    inner = [(bx+hole_r*math.cos(a0+2*math.pi*j/n), BY+hole_r*math.sin(a0+2*math.pi*j/n)) for j in range(n)]
    K.poly_ring(f'platform_deck{tag}', outer, inner, z-.08, z, deck)
    K.box(f'platform_fascia_f{tag}', (x0+x1)/2, y0-.01, z-.09, x1-x0, .03, .12, frame)
    cols = [(x0+.12, y0+.12), (x0+.12, y1-.12), (x1-.12, y0+.12), (x1-.12, y1-.12)]
    if x1-x0 > 2.0:
        cols += [((x0+x1)/2, y0+.12), ((x0+x1)/2, y1-.12)]
    for px, py in cols:
        K.dirbox(f'platform_column{tag}', (px, py, .14), (px, py, z-.08), .09, .09, frame)
    _r_rail(K, f'platform_rail_f{tag}', (x0, y0, z), (x1, y0, z))
    if rail_right:
        K.box(f'platform_fascia_r{tag}', x1+.01, (y0+y1)/2, z-.09, .03, y1-y0, .12, frame)
        _r_rail(K, f'platform_rail_r{tag}', (x1, y0, z), (x1, y1, z))
    if not stair: return
    sx = STAIR_X; sw = .30
    foot_y, head_y = y0-.95, y0
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


def _e_platform(K, level):
    if level == 3:
        _e_deck(K, '', DECK_X0, MAST_X, BX, False, True)
        _e_deck(K, '_b', MAST_X, BX2+BOWL_R+.55, BX2, True, False)
    else:
        _e_deck(K, '', DECK_X0, BX+BOWL_R+.55, BX, True, True)


def _e_shell(K, tag, bx, mirror):
    """One large low shell on its rocker, the bath, the spout and launder, the hood, and the
    electrodes on arms from the mast (from its left side for the first shell, its right for
    the second)."""
    frame, zinc = K.mat('f_frame'), K.mat('f_zinc')
    base = .14
    K.cyl(f'furnace_pedestal{tag}', bx, BY, (base+RIM_Z-BOWL_RISE+.14)/2, .50, RIM_Z-BOWL_RISE+.14-base, frame, segments=24)
    for s_ in (-1, 1):
        K.cyl(f'furnace_trunnion{tag}{s_}', bx+s_*BOWL_R*.84, BY, RIM_Z-BOWL_RISE*.50, .10, .34, frame, axis='X', segments=14)
    _e_bowl(K, f'furnace_shell{tag}', bx, BY, RIM_Z, BOWL_R, BOWL_RISE, BOWL_WALL, K.mat('f_shell'), K.mat('f_oxide'))
    K._fine_mode = True
    for z in (RIM_Z-.20, RIM_Z-.34):
        rr = _e_shell_r(z)
        K.washer(f'furnace_hoop{tag}{int(z*100)}', (bx, BY, z), (0, 0, 1), rr-.02, rr+.065, .07, zinc)
    K._fine_mode = False
    sy = BY-BOWL_R
    K.box(f'furnace_spout{tag}', bx, sy-.02, RIM_Z-.10, .34, .30, .14, K.mat('f_oxide'))
    ly0, ly1 = DECK_Y[0]-.25, sy-.10
    K.box(f'furnace_launder{tag}', bx, (ly0+ly1)/2, RIM_Z-.16, .26, ly1-ly0, .10, K.mat('f_oxide'))
    K.box(f'furnace_launder_trough{tag}', bx, (ly0+ly1)/2, RIM_Z-.10, .16, ly1-ly0-.04, .03, K.mat('ink_black'))
    melt = _emissive('e_melt', (.95, .32, .02), 1.0)
    melt_z = RIM_Z-MELT_DROP; rm = _e_melt_radius()
    K.cyl(f'furnace_melt{tag}', bx, BY, melt_z, rm, .05, melt, segments=28)
    K.washer(f'furnace_lining{tag}', (bx, BY, melt_z+.012), (0, 0, 1), rm-.07, rm+.085, .036, K.mat('f_oxide'))
    side = 1 if mirror else -1
    mx = MAST_X+side*MAST_W/2
    for i in range(3):
        rx, ry = _e_rod_xy(i, bx, mirror); z1 = ROD_TOPS[i]
        K.cyl(f'electrode{tag}{i}', rx, ry, (melt_z-ROD_SUBMERGE+z1)/2, ROD_R, z1-(melt_z-ROD_SUBMERGE), K.mat('e_graphite'), segments=20)
        az = z1-ARM_DROP
        K.cyl(f'electrode{tag}{i}_clamp', rx, ry, az, ROD_R+.06, .22, zinc, segments=20)
        K._fine_mode = True
        K.washer(f'electrode{tag}{i}_ring', (rx, ry, az-.20), (0, 0, 1), ROD_R-.005, ROD_R+.035, .06, zinc)
        K._fine_mode = False
        if not mirror:  # the second shell's arms share the first's brackets on the mast
            K.dirbox(f'electrode{tag}{i}_bracket', (MAST_X, BY, az), (MAST_X, ry, az), .14, .14, frame)
        K.dirbox(f'electrode{tag}{i}_arm', (mx-side*.02, ry, az), (rx-side*ROD_R, ry, az), .11, .13, zinc)
        K.box(f'electrode{tag}{i}_arm_root', mx+side*.02, ry, az, .10, .20, .20, frame)
    hx, hy = bx+.60, BY+HOOD_DY
    K.box(f'hood{tag}', hx, hy, RIM_Z+.60, .80, .50, .40, zinc)
    K.box(f'hood_mouth{tag}', hx, hy-.26, RIM_Z+.55, .60, .06, .30, K.mat('ink_black'))
    K.box(f'hood_stand{tag}', hx+.30, hy+.10, (DECK_Z+RIM_Z+.40)/2, .12, .12, RIM_Z+.40-DECK_Z, frame)
    rz = _e_roof_z(hy)
    K.washer(f'hood_duct_collar{tag}', (hx, hy, rz+.04), (0, 0, 1), .18, .27, .08, frame, seg=20)
    return (hx, hy, RIM_Z+.80)


def _e_furnace(K, level):
    frame, zinc = K.mat('f_frame'), K.mat('f_zinc')
    starts = [_e_shell(K, '', BX, False)]
    if level == 3:
        starts.append(_e_shell(K, '_b', BX2, True))
    mt = max(ROD_TOPS)-ARM_DROP+.22
    K.box('mast', MAST_X, BY, (DECK_Z+.08+mt)/2, MAST_W, MAST_W, mt-DECK_Z-.08, frame)
    K.box('mast_cap', MAST_X, BY, mt+.03, MAST_W+.08, MAST_W+.08, .06, zinc)
    K.box('mast_base', MAST_X, BY, DECK_Z+.04, MAST_W+.16, MAST_W+.16, .08, zinc)
    for k in range(3):
        K.box(f'mast_terminal{k}', MAST_X-MAST_W/2-.02, BY+(k-1)*.15, BUS_Z, .10, .08, .14, zinc)
    return starts


# ------------------------------------------------------------------ fume plant and stacks

def _e_stack(K, tag, xy):
    """A tall modern steel stack: dark base plinth, warm-white tapered steel shell with dark
    bands, an access platform with a yellow barrier near the top, a caged ladder up its
    front, a dark cap."""
    sx, sy = xy
    K.box(f'stack{tag}_footing', sx, sy, .08, .80, .80, .16, K.mat('f_base'))
    K.box(f'stack{tag}_plinth', sx, sy, .16+.25, .66, .66, .50, K.mat('f_frame'))
    barrel = STACK_TOP-.20-.66
    K.cone(f'stack{tag}_barrel', sx, sy, .66+barrel/2, .30, .23, barrel, K.mat('r_shell'))
    K.cyl(f'stack{tag}_cap', sx, sy, STACK_TOP-.20+.08, .25, .16, K.mat('f_frame'))
    K.cyl(f'stack_top', sx, sy, STACK_TOP-.04, .22, .08, K.mat('ink_black'))

    def rad(z):
        return .30-.07*(z-.66)/barrel
    K._fine_mode = True
    for z in (1.80, 3.00):
        K.washer(f'stack{tag}_band', (sx, sy, z), (0, 0, 1), rad(z)-.01, rad(z)+.035, .06, K.mat('f_frame'))
    K._fine_mode = False
    pz = STACK_TOP-.95
    K.washer(f'stack{tag}_deck', (sx, sy, pz), (0, 0, 1), rad(pz)-.004, rad(pz)+.24, .05, K.mat('r_deck'), seg=24)
    _r_ring_rail(K, f'stack{tag}_rail', sx, sy, pz+.025, rad(pz)+.22, h=.22, posts=10)
    _r_ladder_cage(K, f'stack{tag}_ladder', sx+.33, sy, .70, pz, face='+X')  # the lit side, clear of the duct and flue
    return rad


def _e_bag_house(K, level):
    """A bag house behind the chamber that reads as a filter: a wide plain clad box on tall
    dark legs so it shows over the back eave, a flanged inlet transition on its lit end, a
    top walkway with a yellow barrier and the caged ladder from the ground up that end, one
    induced-draught fan on the lid (two at L3) with its outlet on top, and a hopper with a
    rotary valve and a dust chute into a bin."""
    bx0, bx1 = BAG_X[level]
    by0, by1 = BAG_Y
    bz0, bz1 = BAG_Z
    cxb, cyb = (bx0+bx1)/2, (by0+by1)/2
    frame = K.mat('f_frame')
    K.box('bag', cxb, cyb, (bz0+bz1)/2, bx1-bx0, by1-by0, bz1-bz0, K.mat('f2_filter'))
    K.box('bag_lid', cxb, cyb, bz1+.03, bx1-bx0+.06, by1-by0+.06, .06, frame)
    K.box('bag_walkway', cxb, cyb, bz1+.10, bx1-bx0+.30, by1-by0+.30, .05, K.mat('r_deck'))
    wx0, wx1, wy0, wy1 = bx0-.15, bx1+.15, by0-.15, by1+.15
    ly = by0+.15
    _r_rail(K, 'bag_rail_f', (wx0, wy0, bz1+.12), (wx1, wy0, bz1+.12))
    _r_rail(K, 'bag_rail_r0', (wx1, wy0, bz1+.12), (wx1, ly-.20, bz1+.12))
    _r_rail(K, 'bag_rail_r1', (wx1, ly+.20, bz1+.12), (wx1, wy1, bz1+.12))
    _r_rail(K, 'bag_rail_b', (wx1, wy1, bz1+.12), (wx0, wy1, bz1+.12))
    _r_ladder_cage(K, 'bag_ladder', wx1+.04, ly, .10, bz1+.12, face='+X')
    K.box('bag_ladder_foot', wx1+.04, ly, .05, .30, .36, .10, K.mat('f_base'))
    iz = bz0+(bz1-bz0)*.50
    iy = by1-.22
    K.box('bag_inlet', bx1+.14, iy, iz, .28, .36, .46, K.mat('f2_filter'))
    _v2_flange(K, 'bag_inlet_flange', bx1+.29, iy, iz, 'x', w=.44, h=.54)
    fans = [cxb] if level < 3 else [bx0+.65, bx1-.55]
    fy = cyb+.05
    outs = []
    for i, fx in enumerate(fans):
        K.box(f'bag_fan{i}_pedestal', fx, fy, bz1+.20, .40, .44, .16, frame)
        K.cyl(f'bag_fan{i}', fx, fy, bz1+.52, .26, .40, K.mat('r_shell'), axis='Y', segments=20)
        K.cyl(f'bag_fan{i}_motor', fx, fy-.37, bz1+.52, .12, .30, frame, axis='Y', segments=14)
        K.box(f'bag_fan{i}_outlet', fx, fy, bz1+.84, .24, .24, .16, K.mat('r_shell'))
        outs.append((fx, fy, bz1+.80))
    drop = .72
    tx = max(.34, (bx1-bx0)-2*.42*drop); ty = max(.30, (by1-by0)-2*.42*drop)
    _e_frustum(K, 'bag_hopper', bx0, bx1, by0, by1, bz0+.02, bz0-drop, tx, ty, K.mat('f2_filter'))
    K.box('bag_valve', cxb, cyb, bz0-drop-.11, tx+.06, ty+.06, .22, frame)
    K.cyl('bag_valve_motor', cxb+tx/2+.12, cyb, bz0-drop-.11, .07, .18, frame, axis='X', segments=12)
    K.box('bag_dust_chute', cxb, cyb, (bz0-drop-.22+.48)/2, .16, .16, bz0-drop-.22-.48, K.mat('f_zinc'))
    K.box('bag_bin', cxb, cyb, .22, .54, .46, .44, K.mat('f_zinc'))
    K.box('bag_bin_lid', cxb, cyb, .46, .58, .50, .04, frame)
    legs = [(bx0+.12, by0+.12), (bx0+.12, by1-.12), (bx1-.12, by0+.12), (bx1-.12, by1-.12)]
    if bx1-bx0 > 2.0:
        legs += [((bx0+bx1)/2, by0+.12), ((bx0+bx1)/2, by1-.12)]
    for sx_, sy_ in legs:
        K.box('bag_foot', sx_, sy_, .05, .24, .24, .10, K.mat('f_base'))
        K.dirbox('bag_leg', (sx_, sy_, .10), (sx_, sy_, bz0-.02), .12, .12, frame)
    for ry in (by0+.12, by1-.12):
        for bz in (.90, bz0-.08):
            K.dirbox('bag_beam', (bx0+.06, ry, bz), (bx1-.06, ry, bz), .10, .14, frame)
    K._fine_mode = True
    K.dirbox('bag_brace', (bx1-.12, by0+.12, .16), (bx1-.12, by1-.12, .84), .05, .05, frame)
    K.dirbox('bag_brace', (bx1-.12, by1-.12, .96), (bx1-.12, by0+.12, bz0-.14), .05, .05, frame)
    K._fine_mode = False
    return dict(inlet=(bx1+.30, iy, iz), fans=outs)


def _e_fume(K, starts, level):
    """From each hood: up through the chamber roof, back over the roof's right part at one
    height, down behind the chamber and into the bag house's lit end (L2, L3); each fan on
    the lid sends the clean gas up and by a short flue into a stack. L1 has no filter: the
    duct runs straight back into the first stack."""
    frame, base, white = K.mat('f_frame'), K.mat('f_base'), K.mat('white_pipe')
    x1 = _e_x1(level)
    hy = BY+HOOD_DY
    sx, sy = STACK_XY
    if level >= 2:
        bag = _e_bag_house(K, level)
        ix, iy, iz = bag['inlet']
        main = starts[0]  # the main run starts at the leftmost hood and passes over the others
        pts = [main, (main[0], main[1], DUCT_Z), (DUCT_X, hy, DUCT_Z), (DUCT_X, iy, DUCT_Z), (DUCT_X, iy, iz), (ix-.02, iy, iz)]
        K.pipe_run('fume_duct', pts, .20, mat=white, bend=.26)
        for n, (hx, hy_, hz) in enumerate(starts[1:]):
            K.pipe_run(f'fume_duct_{n}', [(hx, hy_, hz), (hx, hy_, DUCT_Z-.20)], .20, mat=white, bend=.10)
            K.cyl(f'fume_duct_{n}_tee', hx, hy_, DUCT_Z-.08, .24, .16, white, segments=20)
        K.box('fume_drop_foot', DUCT_X, iy, .05, .20, .20, .10, base)
        K.dirbox('fume_drop_post', (DUCT_X, iy, .10), (DUCT_X, iy, iz-.24), .08, .08, frame)
        stacks = [STACK_XY] if level < 3 else [STACK2_XY, STACK_XY]
        for n, ((fx, fy, fz), (tx, ty)) in enumerate(zip(bag['fans'], stacks)):
            K.pipe_run(f'clean_flue{n}', [(fx, fy, fz), (fx, fy, FLUE_Z), (fx, ty, FLUE_Z), (tx-.26, ty, FLUE_Z)], .14, mat=white, bend=.22)
            K.washer(f'clean_flue{n}_collar', (tx-.27, ty, FLUE_Z), (1, 0, 0), .13, .19, .04, frame, seg=16)
    else:
        hx, hy_, hz = starts[0]
        pts = [(hx, hy_, hz), (hx, hy_, DUCT_Z), (sx, hy_, DUCT_Z), (sx, sy-.27, DUCT_Z)]
        K.pipe_run('fume_duct', pts, .20, mat=white, bend=.30)
        K.washer('fume_collar_stack', (sx, sy-.28, DUCT_Z), (0, 1, 0), .18, .24, .04, frame, seg=16)
        for py in (hy_, (HALL[3]+sy)/2+.05):
            K.box('fume_post_foot', sx, py, .05, .16, .16, .10, base)
            K.dirbox('fume_post', (sx, py, .10), (sx, py, DUCT_Z-.24), .08, .08, frame)
            K.dirbox('fume_saddle', (sx-.22, py, DUCT_Z-.25), (sx+.22, py, DUCT_Z-.25), .09, .06, frame)
        return
    # The run across the roof's edge is carried where it leaves the building.
    px = x1+.13
    if px < DUCT_X-.30:
        K.box('fume_post_foot_e', px, hy, .05, .16, .16, .10, base)
        K.dirbox('fume_post_e', (px, hy, .10), (px, hy, DUCT_Z-.24), .08, .08, frame)
        K.dirbox('fume_saddle_e', (px, hy-.22, DUCT_Z-.25), (px, hy+.22, DUCT_Z-.25), .09, .06, frame)
    else:
        rz = _e_roof_z(hy)
        K.box('fume_roof_stand_foot', DUCT_X-.40, hy, rz+.04, .20, .20, .06, K.mat('f_zinc'))
        K.dirbox('fume_roof_stand', (DUCT_X-.40, hy, rz+.07), (DUCT_X-.40, hy, DUCT_Z-.24), .08, .08, frame)
        K.dirbox('fume_saddle_r', (DUCT_X-.40, hy-.22, DUCT_Z-.25), (DUCT_X-.40, hy+.22, DUCT_Z-.25), .09, .06, frame)


# ------------------------------------------------------------------ power

def _e_power(K, level):
    """One large oil-filled transformer on kerbed gravel left of the open front (a second one
    set back behind it from L2), their leads rising to the bushings on the chamber's left wall; inside, bus bushings carry the tubes
    across the chamber above the electrodes to the mast's terminals, hung from the roof."""
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
    tx0, tx1, ty0, ty1 = TX_PAD[level]
    K.box('tx_gravel', (tx0+tx1)/2, (ty0+ty1)/2, .035, tx1-tx0, ty1-ty0, .07, K.mat('membrane'))
    K.box('tx_kerb', (tx0+tx1)/2, (ty0+ty1)/2, .02, tx1-tx0+.08, ty1-ty0+.08, .04, K.mat('f_base'))
    units = [TX_XY] if level == 1 else [TX_XY, TX2_XY]
    for n, (cx, cy) in enumerate(units):
        K.transformer(f'tx{n}', cx, cy, .07, s=TX_S, fins=6)
    for ob in K.col.objects:
        if ob.name.startswith('tx') and ob.type == 'MESH':
            mats = ob.data.materials
            for i, m in enumerate(mats):
                if m == K.mat('f_frame'): mats[i] = K.mat('p_tx')
    K._fine_mode = True
    bush_z = .07+.70*TX_S
    for n, (cx, cy) in enumerate(units):
        for k in range(3):
            bx = cx+(k-1)*.14*TX_S
            K.dircyl(f'tx{n}_lead{k}', (bx, cy, bush_z), (wx-.22, BY+(k-1)*.15, BUS_Z), .012, K.mat('f_frame'), segments=6)
    K._fine_mode = False


def _e_bunker(K):
    """A closed storage bunker for scrap and whatever else the furnace takes, behind the
    chamber's left end: a zinc-clad body with a lid and loading hatch on a dark four-post
    frame with ring beams and bracing, a hopper under it and a discharge throat. Closed,
    because an arc furnace takes many different charges."""
    x0, x1, y0, y1 = BUNKER
    z0, z1 = BUNKER_Z
    cx, cy = (x0+x1)/2, (y0+y1)/2
    frame, zinc = K.mat('f_frame'), K.mat('f_zinc')
    K.box('bunker_pad', cx, cy, .05, x1-x0+.20, y1-y0+.20, .10, K.mat('f_base'))
    for px in (x0+.10, x1-.10):
        for py in (y0+.10, y1-.10):
            K.dirbox('bunker_post', (px, py, .10), (px, py, z0+.02), .12, .12, frame)
    for py in (y0+.10, y1-.10):
        K.dirbox('bunker_ring', (x0+.04, py, z0-.06), (x1-.04, py, z0-.06), .10, .12, frame)
    for px in (x0+.10, x1-.10):
        K.dirbox('bunker_ring', (px, y0+.04, z0-.06), (px, y1-.04, z0-.06), .12, .10, frame)
    K._fine_mode = True
    K.dirbox('bunker_brace', (x0+.10, y0+.10, .16), (x1-.10, y0+.10, z0-.16), .05, .05, frame)
    K.dirbox('bunker_brace', (x1-.10, y0+.10, .16), (x1-.10, y1-.10, z0-.16), .05, .05, frame)
    K._fine_mode = False
    _e_frustum(K, 'bunker_hopper', x0+.04, x1-.04, y0+.04, y1-.04, z0+.02, z0-.55, .34, .30, zinc)
    K.box('bunker_throat', cx, cy, z0-.66, .30, .26, .22, frame)
    K.box('bunker_body', cx, cy, (z0+z1)/2, x1-x0, y1-y0, z1-z0, zinc)
    K.box('bunker_lid', cx, cy, z1+.03, x1-x0+.06, y1-y0+.06, .06, frame)
    K.box('bunker_hatch', cx-.22, cy-.18, z1+.085, .40, .34, .05, frame)
    K._fine_mode = True
    K.box('bunker_hatch_hinge', cx-.22, cy-.36, z1+.10, .42, .03, .03, zinc)
    for dz in (z0+.60, z0+1.30, z0+2.00):
        K.box('bunker_band', x1+.01, cy, dz, .02, y1-y0+.02, .03, frame)
        K.box('bunker_band_f', cx, y0-.01, dz, x1-x0+.02, .02, .03, frame)
    K._fine_mode = False
    _r_ladder_cage(K, 'bunker_ladder', x1+.04, cy+.20, .10, z1+.06, face='+X')


def _e_ladle_car(K, name, x, y):
    before = {ob.name for ob in K.col.objects}
    _v2_ladles(K, name, x, y)
    for ob in K.col.objects:
        if ob.name not in before: ob.location.z += .06


# ------------------------------------------------------------------ build

def build_eaf_v2(level=1):
    assert level in (1, 2, 3)
    K = _e_begin()
    _e_check_sightlines(level)
    x1 = _e_x1(level)
    _r_pad(K, 'site_pad_front', HALL[0]-.10, BX+1.10, -2.60, HALL[2])
    _e_house(K, level)
    _e_platform(K, level)
    starts = _e_furnace(K, level)
    _e_fume(K, starts, level)
    _e_stack(K, '', STACK_XY)
    if level == 3:
        _e_stack(K, '_b', STACK2_XY)
    _e_power(K, level)
    _e_bunker(K)
    _e_ladle_car(K, 'ladle', BX, LADLE_Y)
    if level == 3:
        _e_ladle_car(K, 'ladle_b', BX2, LADLE_Y)
    return _r_finish(K, level, 'eaf v2: furnace in its chamber under a slanted roof, one transformer, bag house and stacks behind')
