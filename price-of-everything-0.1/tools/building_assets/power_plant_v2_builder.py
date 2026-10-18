"""The power plant, rebuilt from the owner's approved reference (power-plant-b4) in the
catalogue look: a fuel-neutral thermal station that reads as coal or gas.

Executed in sprite_kit's namespace after furnace_builder.py, furnace_v2_builder.py and
refinery_v2_builder.py, whose palette and helpers it shares. Staged as family
'power_plant_v2'; it installs as 'power_plant'.

Screen vocabulary at this camera: back = +Y (top-right), right = +X (lower-right),
front = -Y (bottom-left), left = -X (upper-left).

Composition: a tall clad heat block (boiler or heat-recovery steam generator) at the back,
a slim chimney beside it fed by a flue duct, a long turbine hall in front with a glazed
roof over its turbine-generator sets and crane, a hyperboloid cooling tower at the left on
its basin, a transformer yard in the corridor beside the hall with a takeoff gantry by the
chimney, and four fuel and service lines out of the heat block's back wall into the ground.
Flows: fuel into the heat block; flue gas to the chimney; steam to the turbines; cooling
water between the hall and the tower basin; power from the hall end along bus ducts to the
transformers and out over the gantry.

Fixed across levels: the heat block, chimney, flue duct, service pipes, turbine hall and
transformer yard stand in the same places. L1 has no cooling tower (owner ruling for the
old plant), the boiler stands in the open, the chimney is half height, one turbine and two
transformers; L2 adds the cooling tower, a shorter windowless heat block, the full chimney,
the second turbine and two more transformers; L3 has the full-height block with windows,
the switch kiosk and a tall lattice pylon in place of the gantry.
"""
import math
from mathutils import Vector

PALETTE.update({
    'p_concrete': (.520, .500, .460),    # cooling tower shell: pale weathered concrete
    'p_turbine': (.200, .300, .270),     # turbine casings: green-grey, light enough to read under glass
    'p_tx': (.300, .320, .320),          # transformer tanks
    'p_insulator': (.640, .610, .560),   # bushings and insulator discs
})

POWER_ROLES = {'gear': 'p_turbine', 'wall_shell': 'p_concrete', 'scaffold': 'f_frame',
               'window_frame': 'p_insulator', 'wall_grey': 'f_base', 'pipe': 'silver',
               'opening': 'ink_black'}

BLOCK = (-1.90, .60, -.30, 1.60)      # x0, x1, y0, y1 of the heat block, left of centre to leave the back right for the pylon
BLOCK_H = 3.00
HALL_Y = (-2.98, -.60)                # turbine hall depth: a shallow roof to the same ridge height
HALL_X0 = -1.10
HALL_EAVE = 1.55
HALL_RISE = .58
WIN = (.25, .38)                      # turbine hall windows: two floors of small factory windows
WIN_Z = (.52, 1.15)
FLOOR_Z = .86
STACK = (1.35, 1.00)                # beside the heat block
STACK_TOP = 5.00
TOWER_XY = (-2.80, -1.55)     # left of the turbine hall, level with its centre, as in the reference
YARD = (2.55, 4.15, -2.95, .45)       # x0, x1, y0, y1: the corridor beside the hall, back to the chimney


def _pp_begin():
    K = _r_begin('BLDG_power_plant_v2')
    ROLES.update(POWER_ROLES)
    _pp_interior_ink()
    _v2_brick_print(K)
    return K


def _pp_interior_ink():
    """Ink for what stands under the glazed roof. Freestyle treats glass as opaque, so the
    turbines would print as faint colour with no lines. Objects linked into PP_INTERIOR get a
    line set that draws through ONE surface: each roof pane is a single plane, while every
    wall is a box (two surfaces), so the plant is inked through the glass and never through
    a wall."""
    col = bpy.data.collections.get('PP_INTERIOR')
    if col is None:
        col = bpy.data.collections.new('PP_INTERIOR')
        bpy.context.scene.collection.children.link(col)
    for ob in list(col.objects):
        col.objects.unlink(ob)
    fs = bpy.context.scene.view_layers[0].freestyle_settings
    ls = fs.linesets.get('ink_interior') or fs.linesets.new('ink_interior')
    ls.select_silhouette = ls.select_border = ls.select_crease = True
    ls.select_by_visibility = True
    ls.visibility = 'RANGE'; ls.qi_start = 0; ls.qi_end = 1
    ls.select_by_collection = True
    ls.collection = col
    ls.collection_negation = 'INCLUSIVE'
    ls.linestyle.color = (0.055, 0.065, 0.13)
    ls.linestyle.thickness = .80


def _pp_mark_interior(K, before):
    col = bpy.data.collections['PP_INTERIOR']
    for ob in K.col.objects:
        if ob.name not in before and ob.name not in col.objects:
            col.objects.link(ob)


def _pp_pane(K, name, pts, mat):
    """One glazing pane as a single quad: a single surface for the interior line set."""
    m = bpy.data.meshes.new(name)
    bm = bmesh.new()
    vs = [bm.verts.new(p) for p in pts]
    bm.faces.new(vs)
    bm.to_mesh(m); bm.free()
    return K.obj(name, m, mat)


def _pp_roof_glass():
    """Roof glazing: lighter and more see-through than the factory's window glass, so the
    turbines under it read in the sprite and in the 3D view's glass shader."""
    mt = bpy.data.materials.get('roof_glass') or bpy.data.materials.new('roof_glass')
    mt.use_nodes = True
    b = mt.node_tree.nodes.get('Principled BSDF')
    b.inputs['Base Color'].default_value = (.250, .340, .380, 1)
    b.inputs['Roughness'].default_value = 1.0
    if 'Specular IOR Level' in b.inputs: b.inputs['Specular IOR Level'].default_value = 0.0
    b.inputs['Alpha'].default_value = .24
    mt.surface_render_method = 'BLENDED'
    mt.use_backface_culling = False
    return mt


def _pp_recolour(K, prefix, old, new):
    for ob in K.col.objects:
        if ob.name.startswith(prefix) and ob.type == 'MESH':
            mats = ob.data.materials
            for i, m in enumerate(mats):
                if m == K.mat(old): mats[i] = K.mat(new)


# ------------------------------------------------------------------ heat block and chimney

def _pp_heat_block(K, h, windows):
    """The clad heat block: L2 a shorter, windowless block; L3 the full height with strip
    windows on all four faces."""
    x0, x1, y0, y1 = BLOCK
    roof_z = _r_block(K, 'block', x0, x1, y0, y1, h)
    # Panel joints and bands on all four faces, a shade darker than the cladding.
    joint = K.tone(K.mat('white_wall'), .78, 'joint')
    K._fine_mode = True
    zc, hh = .08+(h-.08)/2, h-.08
    for i in range(1, 5):
        x = x0+(x1-x0)*i/5
        for tag, y in (('front', y0-.006), ('back', y1+.006)):
            K.box('block_joint_'+tag, x, y, zc, .025, .012, hh, joint)
    for i in range(1, 4):
        y = y0+(y1-y0)*i/4
        for tag, x in (('side', x1+.006), ('left', x0-.006)):
            K.box('block_joint_'+tag, x, y, zc, .012, .025, hh, joint)
    for z in (h*.37, h*.68):
        for tag, y in (('front', y0-.006), ('back', y1+.006)):
            K.box('block_band_'+tag, (x0+x1)/2, y, z, x1-x0, .012, .025, joint)
        for tag, x in (('side', x1+.006), ('left', x0-.006)):
            K.box('block_band_'+tag, x, (y0+y1)/2, z, .012, y1-y0, .025, joint)
    if windows:
        # High strip windows on all four faces: the band that says "hall full of plant".
        wz = h-.45
        _v2_window(K, 'block_strip_front', '-Y', ((x0+x1)/2, y0-.055, wz), 2.00, .24, cols=8, rows=1)
        _v2_window(K, 'block_strip_side', '+X', (x1+.055, (y0+y1)/2-.10, wz), 1.40, .24, cols=6, rows=1)
        _v2_window(K, 'block_strip_back', '+Y', ((x0+x1)/2, y1+.055, wz), 2.00, .24, cols=8, rows=1)
        _v2_window(K, 'block_strip_left', '-X', (x0-.055, (y0+y1)/2, wz), 1.40, .24, cols=6, rows=1)
    K._fine_mode = False
    # Wall louvres low on the back and left faces, clear of the service pipes.
    for i, x in enumerate((x0+.35, x1-.30)):
        _pp_louvre(K, f'block_louvre_back{i}', '+Y', (x, y1, 1.05))
    for i, y in enumerate((y0+.45, y1-.45)):
        _pp_louvre(K, f'block_louvre_left{i}', '-X', (x0, y, 1.05))
    _pp_roof_plant(K, roof_z)
    # Rainwater: one downpipe on the side face.
    _v2_downpipe(K, 'block_downpipe', x1+.06, y1-.12, h+.05, .08)
    return dict(front=y0, back=y1, right=x1, top=roof_z)


OPEN = (-1.30, .10, .10, 1.20)      # x0, x1, y0, y1 of L1's exposed boiler casing
OPEN_H = 2.00


def _pp_open_boiler(K):
    """L1 has no building: the plant it would hold stands in the open. A boiler casing with
    buckstay bands and burner ports in a steel frame, a railed deck on top carrying the
    steam drum, and a ladder up the front."""
    x0, x1, y0, y1 = OPEN
    h = OPEN_H
    cx, cy = (x0+x1)/2, (y0+y1)/2
    K.box('boiler_plinth', cx, cy, .06, x1-x0+.40, y1-y0+.40, .12, K.mat('f_base'))
    K.box('boiler_casing', cx, cy, (.12+h)/2, x1-x0, y1-y0, h-.12, K.mat('p_tx'))
    K._fine_mode = True
    for z in (.55, 1.00, 1.45, 1.85):
        K.box('boiler_buckstay_front', cx, y0-.012, z, x1-x0+.02, .024, .05, K.mat('f_frame'))
        K.box('boiler_buckstay_side', x1+.012, cy, z, .024, y1-y0+.02, .05, K.mat('f_frame'))
        K.box('boiler_buckstay_back', cx, y1+.012, z, x1-x0+.02, .024, .05, K.mat('f_frame'))
        K.box('boiler_buckstay_left', x0-.012, cy, z, .024, y1-y0+.02, .05, K.mat('f_frame'))
    K._fine_mode = False
    for i, bx in enumerate((cx-.35, cx+.35)):
        K.cyl(f'boiler_burner{i}', bx, y0-.03, .78, .11, .06, K.mat('f_frame'), axis='Y', segments=14)
        K.cyl(f'boiler_burner{i}_port', bx, y0-.065, .78, .06, .02, K.mat('ink_black'), axis='Y', segments=12)
    # Steel frame round the casing, a deck over it and a yellow barrier round the deck.
    fx0, fx1, fy0, fy1 = x0-.12, x1+.12, y0-.12, y1+.12
    for x in (fx0, fx1):
        for y in (fy0, fy1):
            K.box('frame_foot', x, y, .14, .14, .14, .06, K.mat('f_base'))
            K.dirbox('frame_col', (x, y, .14), (x, y, h+.10), .08, .08, K.mat('f_frame'))
    for z in (1.05, h+.10):
        for y in (fy0, fy1):
            K.dirbox('frame_beam_x', (fx0-.04, y, z), (fx1+.04, y, z), .07, .08, K.mat('f_frame'))
        for x in (fx0, fx1):
            K.dirbox('frame_beam_y', (x, fy0-.04, z), (x, fy1+.04, z), .07, .08, K.mat('f_frame'))
    dz = h+.17
    K.box('boiler_deck', cx, cy, dz, fx1-fx0, fy1-fy0, .05, K.mat('r_deck'))
    for a, b in (((fx0, fy0), (fx1, fy0)), ((fx1, fy0), (fx1, fy1)), ((fx1, fy1), (fx0, fy1)), ((fx0, fy1), (fx0, fy0))):
        _r_rail(K, 'boiler_deck_rail', (*a, dz+.025), (*b, dz+.025), h=.22)
    _r_ladder_cage(K, 'boiler_ladder', fx1-.25, fy0-.05, .12, dz, face='-Y')
    # Steam drum along the deck on two saddles.
    for i, sx_ in enumerate((cx-.40, cx+.40)):
        K.box(f'drum_saddle{i}', sx_, cy, dz+.10, .10, .30, .16, K.mat('f_frame'))
    K.dircyl('steam_drum', (cx-.65, cy, dz+.36), (cx+.65, cy, dz+.36), .19, K.mat('r_shell'), segments=20)
    for sx_ in (cx-.65, cx+.65):
        K.cyl('steam_drum_end', sx_, cy, dz+.36, .20, .04, K.mat('f_frame'), axis='X', segments=20)
    return dict(front=y0, back=y1, right=x1, top=dz)


def _pp_window(K, name, face, centre, w, h, cols=2, rows=2, k=.5):
    """The catalogue factory window (`_v2_window`: cream frame and glazing bars, sill, stone
    lintel, teal glass over a dark room) with every frame member scaled by `k`. The kit's
    fixed 5 cm frame and 2.6 cm bars suit a full-size window and swamp a small one."""
    import mathutils
    out, across = K._face_axes(face)
    C = mathutils.Vector(centre)+out*EPS
    ax = abs(across.x) > .5
    def put(nm, off, along, tall, deep, mat):
        p_ = C+across*off[0]+mathutils.Vector((0, 0, off[1]))+out*off[2]
        K.box(nm, p_.x, p_.y, p_.z, along if ax else deep, deep if ax else along, tall, mat)
    frame = K.mat('window_frame')
    put(name+'_glass', (0, 0, 0), w, h, .01, _v2_factory_glass())
    put(name+'_interior', (0, 0, -.004-EPS), w, h, .006, K.mat('interior'))
    fw = .05*k
    for sgn in (-1, 1):
        put(name+'_fside', (sgn*w/2, 0, .005), fw, h+.10*k, .012, frame)
        put(name+'_fend', (0, sgn*h/2, .005), w+.09*k, fw, .012, frame)
    # Sill and lintel slimmer than the frame scale alone gives: at this size the kit's
    # proportions read as heavy bands above and below every window.
    put(name+'_sill', (0, -h/2-.004, .010), w+.05*k, .016, .02, frame)
    for c in range(1, cols):
        put(name+'_mv', (-w/2+c*w/cols, 0, .004), .026*k, h, .01, frame)
    for r in range(1, rows):
        put(name+'_mh', (0, -h/2+r*h/rows, .004), w, .026*k, .01, frame)
    put(name+'_lintel', (0, h/2+fw/2+.012, .025-EPS), w+.06*k, .022, .05, K.mat(STONE))


def _pp_door(K, name, face, centre, w, h, ribs=4, k=.7):
    """The kit's door and roller gate with its lintel and rib insets scaled by `k`."""
    import mathutils
    out, across = K._face_axes(face)
    C = mathutils.Vector(centre)+out*EPS
    ax = abs(across.x) > .5
    def put(nm, p_, along, tall, deep, mat):
        K.box(nm, p_.x, p_.y, p_.z, along if ax else deep, deep if ax else along, tall, mat)
    put(name+'_leaf', C, w, h, .01, K.mat('door_leaf'))
    for r in range(1, ribs+1):
        put(name+'_rib', C+out*-.004+mathutils.Vector((0, 0, -h/2+r*h/(ribs+1))), w-.06*k, .018*k, .008, K.mat('scaffold'))
    put(name+'_lintel', C+out*-.006+mathutils.Vector((0, 0, h/2+.03*k)), w+.16*k, .06*k, .012, K.mat('window_frame'))


def _pp_louvre(K, name, face, c, w=.46, h=.40):
    """A wall louvre: a zinc frame proud of the cladding with dark blades across it."""
    x, y, z = c
    out = .025
    if face in ('+Y', '-Y'):
        sg = 1 if face == '+Y' else -1
        K.box(name, x, y+sg*out/2, z, w, out, h, K.mat('f_zinc'))
        K._fine_mode = True
        for k in range(4):
            K.box(name+'_blade', x, y+sg*(out+.006), z-h*.32+k*h*.21, w-.08, .012, .045, K.mat('f_frame'))
        K._fine_mode = False
    else:
        sg = 1 if face == '+X' else -1
        K.box(name, x+sg*out/2, y, z, out, w, h, K.mat('f_zinc'))
        K._fine_mode = True
        for k in range(4):
            K.box(name+'_blade', x+sg*(out+.006), y, z-h*.32+k*h*.21, .012, w-.08, .045, K.mat('f_frame'))
        K._fine_mode = False


def _pp_roof_plant(K, z):
    """Three rows along the heat block's roof, symmetrical about its centre: small vents,
    a row of electrical cabinets on a plinth, small vents."""
    x0, x1, y0, y1 = BLOCK
    cx, cy = (x0+x1)/2, (y0+y1)/2
    K._fine_mode = True
    for row, dy in (('front', -.55), ('back', .55)):
        for k in range(6):
            vx = cx+(k-2.5)*.38
            K.box(f'roof_vent_{row}{k}', vx, cy+dy, z+.06, .14, .14, .12, K.mat('silver'))
            K.box(f'roof_vent_{row}{k}_cap', vx, cy+dy, z+.135, .19, .19, .03, K.mat('f_frame'))
    K._fine_mode = False
    K.box('roof_plinth', cx, cy, z+.03, 2.10, .46, .06, K.mat('f_base'))
    for k in range(3):
        ex = cx+(k-1)*.70
        K.box(f'roof_cabinet{k}', ex, cy, z+.06+.14, .52, .38, .28, K.mat('p_tx'))
        K.box(f'roof_cabinet{k}_top', ex, cy, z+.06+.29, .56, .42, .03, K.mat('f_frame'))
        K._fine_mode = True
        for f in range(3):
            K.box(f'roof_cabinet{k}_fin', ex-.12+f*.12, cy-.195, z+.06+.14, .05, .012, .20, K.mat('f_frame'))
        K._fine_mode = False


def _pp_chimney(K, top):
    sx, sy = STACK
    def rad(z):
        return .29-.07*(z-.16)/(top-.52)
    K.box('stack_footing', sx, sy, .08, .78, .78, .16, K.mat('f_base'))
    K.cone('stack_barrel', sx, sy, .16+(top-.36-.16)/2, .29, .22, top-.36-.16, K.mat('r_shell'))
    K.cyl('stack_cap', sx, sy, top-.36+.14, .25, .28, K.mat('f_frame'))
    K.cyl('stack_top', sx, sy, top-.04, .21, .08, K.mat('ink_black'))
    K._fine_mode = True
    for z in (1.20, 2.40, 3.55):
        if z > top-1.0: continue
        K.washer('stack_band', (sx, sy, z), (0, 0, 1), rad(z)-.01, rad(z)+.03, .06, K.mat('f_frame'))
    K._fine_mode = False
    # Access platform near the top: black-grey deck, yellow barrier, caged ladder up the front.
    pz = top-.80
    K.washer('stack_deck', (sx, sy, pz), (0, 0, 1), rad(pz)-.004, rad(pz)+.24, .05, K.mat('r_deck'), seg=24)
    _r_ring_rail(K, 'stack_rail', sx, sy, pz+.025, rad(pz)+.22, h=.22, posts=10)
    _r_ladder_cage(K, 'stack_ladder', sx, sy-.31, .18, pz, face='-Y')
    return rad


def _pp_flue_duct(K, x1, z, rad):
    """Flue gas from the heat block's (or the open boiler's) side face into the chimney, on a
    lattice support."""
    sx, sy = STACK
    r = .17
    stack_r = rad(z)
    K.dircyl('flue_duct', (x1+.02, sy, z), (sx-stack_r+.04, sy, z), r, K.mat('white_pipe'), segments=18)
    _v2_flange(K, 'flue_collar_block', x1+.03, sy, z, 'x', w=.46, h=.46)
    K.washer('flue_collar_stack', (sx-stack_r-.02, sy, z), (1, 0, 0), r-.01, r+.04, .05, K.mat('f_frame'), seg=18)
    # Support frame under the duct.
    mx = (x1+sx-stack_r)/2
    for dy in (-.18, .18):
        K.box('flue_foot', mx, sy+dy, .05, .14, .14, .10, K.mat('f_base'))
        K.dirbox('flue_post', (mx, sy+dy, .10), (mx, sy+dy, z-r), .07, .07, K.mat('f_frame'))
    K.dirbox('flue_saddle', (mx, sy-.22, z-r-.02), (mx, sy+.22, z-r-.02), .08, .06, K.mat('f_frame'))
    K._fine_mode = True
    for k in range(3):
        za, zb = .10+(z-r-.10)*k/3, .10+(z-r-.10)*(k+1)/3
        K.dircyl('flue_brace', (mx, sy-.18, za), (mx, sy+.18, zb), .016, K.mat('f_frame'), segments=6)
    K._fine_mode = False


def _pp_steam_lines(K, front):
    """Two steam lines from the heat block (or open boiler) front into the hall's back wall."""
    for i, x in enumerate((-.70, -.05)):
        K.dircyl(f'steam_line{i}', (x, front-.01, 1.25), (x, HALL_Y[1]+.01, 1.25), .085, K.mat('white_pipe'), segments=14)
        _v2_flange(K, f'steam_line{i}_collar', x, front-.02, 1.25, 'y', w=.22, h=.22)


# ------------------------------------------------------------------ turbine hall

def _pp_turbine_hall(K, x1, turbines):
    """Brick walls on black pillars, tall factory windows and a roller door on the front, and a
    glazed roof over the turbine-generator sets and crane: brick, glass and black steel only."""
    x0 = HALL_X0; y0, y1 = HALL_Y
    w, d = x1-x0, y1-y0
    cx, cy = (x0+x1)/2, (y0+y1)/2
    h = HALL_EAVE; zb = .52
    brick, wall, frame = K.mat('f_brick'), K.mat('white_wall'), K.mat('f_frame')
    K.box('hall_footing', cx, cy, .06, w+.10, d+.10, .12, K.mat('f_base'))
    K.box('hall_floor', cx, cy, .13, w-.16, d-.16, .02, K.mat('f_base'))

    def slab(nm, sx_, sy_, lx, ly):
        K.box(nm, sx_, sy_, (.12+h)/2, lx, ly, h-.12, brick)
    t = .08
    slab('hall_front', cx, y0+t/2, w, t)
    slab('hall_back', cx, y1-t/2, w, t)
    for s, xe in ((-1, x0+t/2), (1, x1-t/2)):
        slab('hall_end'+str(s), xe, cy, t, d-2*t)
    # Gables over the end walls.
    for s, xe in ((-1, x0+t/2), (1, x1-t/2)):
        K.prism('hall_gable'+str(s), (xe, cy, 0), (0, 1), [(-d/2, h), (0, h+HALL_RISE), (d/2, h)], t, brick)
    # Pale lining inside, clear of the brick by a hair: seen through the glass roof, bare
    # brick on the far walls turns the whole roof red.
    lt, g = .012, .003
    K.box('hall_lining_front', cx, y0+t+g+lt/2, (.14+h)/2, w-2*t-2*g, lt, h-.14, wall)
    K.box('hall_lining_back', cx, y1-t-g-lt/2, (.14+h)/2, w-2*t-2*g, lt, h-.14, wall)
    for s, xe in ((-1, x0+t+g+lt/2), (1, x1-t-g-lt/2)):
        K.box('hall_lining_end'+str(s), xe, cy, (.14+h)/2, lt, d-2*t-2*g, h-.14, wall)
        K.prism('hall_lining_gable'+str(s), (xe, cy, 0), (0, 1), [(-d/2+t, h), (0, h+HALL_RISE-.04), (d/2-t, h)], lt, wall)
    # Portal columns on the front face, windows between them, the roller door at the centre.
    bays = max(3, round(w/.80))
    door_bay = bays//2
    # Black pillars on the long faces, the end ones on the corners, carrying the eave.
    for i in range(bays+1):
        px = x0+.04+(w-.08)*i/bays
        for side, py in (('front', y0-.035), ('back', y1+.035)):
            K.box(f'hall_pillar_{side}', px, py, (.12+h)/2+.02, .11, .07, h-.08, frame)
    for i in range(bays):
        bx = x0+.04+(w-.08)*(i+.5)/bays
        if i == door_bay:
            # A ground-floor roller door, with the upper floor's windows above it.
            _pp_door(K, 'hall_roller', '-Y', (bx, y0-.02, .12+.45/2), .39, .45, ribs=4)
        K._fine_mode = True
        for k, dx in enumerate((-.17, .17)):
            if i != door_bay:
                _pp_window(K, f'hall_window{i}_{k}_g', '-Y', (bx+dx, y0-.055, WIN_Z[0]), *WIN)
            _pp_window(K, f'hall_window{i}_{k}_u', '-Y', (bx+dx, y0-.055, WIN_Z[1]), *WIN)
        K._fine_mode = False
    # Two floors: small factory windows in pairs on each, and a stone floor band between. The
    # right end, where the bus ducts leave, has no band to run through their collars.
    for nm, c, sz in (('front', (cx, y0-.012), (w, .025)), ('back', (cx, y1+.012), (w, .025)),
                      ('left', (x0-.012, cy), (.025, d))):
        K.box('hall_floor_band_'+nm, c[0], c[1], FLOOR_Z, sz[0], sz[1], .05, K.mat('stone'))
    # The right end wall carries the bus ducts, so its windows go on the left end, over the
    # cooling-water pipes.
    K._fine_mode = True
    for j, ye in enumerate(((y0+cy)/2+.02, (cy+y1)/2-.02)):
        for k, dy in enumerate((-.17, .17)):
            for f, z in zip('gu', WIN_Z):
                _pp_window(K, f'hall_end_window{j}_{k}_{f}', '-X', (x0-.055, ye+dy, z), *WIN)
    K._fine_mode = False
    # Glazed roof: a dark steel glazing grid over see-through panes, with metal strips at
    # the eaves and the ridge.
    glass = _pp_roof_glass()
    k = HALL_RISE/(d/2); o = .08
    for s in (-1, 1):
        ya, yb = (-d/2-o, 0) if s < 0 else (0, d/2+o)
        za, zz = (h-k*o, h+HALL_RISE) if s < 0 else (h+HALL_RISE, h-k*o)
        _pp_pane(K, 'hall_glazing'+str(s), [(x0-.03, cy+ya, za+.03), (x1+.03, cy+ya, za+.03), (x1+.03, cy+yb, zz+.03), (x0-.03, cy+yb, zz+.03)], glass)
        # Eave strip.
        ye = -d/2-o if s < 0 else d/2+o
        yi = ye+(-s)*.16
        zi = h-k*o+k*.16
        K.prism('hall_eave_strip'+str(s), (cx, cy, 0), (0, 1),
                [(min(ye, yi), (h-k*o if s < 0 else zi)+.01), (max(ye, yi), (zi if s < 0 else h-k*o)+.01),
                 (max(ye, yi), (zi if s < 0 else h-k*o)+.065), (min(ye, yi), (h-k*o if s < 0 else zi)+.065)], w+.10, K.mat('f_roof'))
    K.dirbox('hall_ridge', (x0-.05, cy, h+HALL_RISE+.04), (x1+.05, cy, h+HALL_RISE+.04), .16, .07, K.mat('f_roof'))
    K._fine_mode = True
    nbar = max(4, round(w/.42))
    for j in range(nbar+1):
        px = x0-.02+(w+.04)*j/nbar
        for s in (-1, 1):
            K.dirbox('hall_glazing_bar', (px, cy+s*(d/2+o-.14), h-k*(o-.14)+.05), (px, cy, h+HALL_RISE+.04), .025, .025, frame)
    for s in (-1, 1):
        K.dirbox('hall_purlin', (x0, cy+s*d/4, h+HALL_RISE/2+.05), (x1, cy+s*d/4, h+HALL_RISE/2+.05), .025, .025, frame)
    K._fine_mode = False
    # Gutter and downpipe on the front eave.
    K.box('hall_gutter', cx, y0-o-.02, h-k*o+.02, w+.12, .07, .06, K.mat('silver'))
    _v2_downpipe(K, 'hall_downpipe', x0+.10, y0-o-.02, h-k*o, .12)
    # Inside: turbine-generator sets on the floor, crane rails and a yellow crane bridge.
    before = {ob.name for ob in K.col.objects}
    # The sets stand on a raised turbine deck towards the back wall, where the sightlines
    # through the glass reach them; on the floor by the front wall the eave hides them.
    deck_z, ty = .42, cy+.22
    for i, (tx, length) in enumerate(turbines):
        K.box(f'turbine{i}_pedestal', tx, ty, (.14+deck_z)/2, length+.40, .66, deck_z-.14, K.mat('f_base'))
        K.turbine(f'turbine{i}', tx, ty, deck_z, length=length, s=1.0)
    K._fine_mode = True
    for s in (-1, 1):
        K.dirbox('crane_rail', (x0+.10, cy+s*(d/2-.16), h-.12), (x1-.10, cy+s*(d/2-.16), h-.12), .05, .05, frame)
    K._fine_mode = False
    bx = x0+(x1-x0)*.62
    K.dirbox('crane_bridge', (bx, y0+.12, h-.06), (bx, y1-.12, h-.06), .10, .10, K.mat('r_yellow'))
    K.box('crane_hoist', bx, cy-.10, h-.16, .16, .18, .10, K.mat('r_yellow'))
    _pp_mark_interior(K, before)
    return dict(x0=x0, x1=x1, y0=y0, y1=y1)


# ------------------------------------------------------------------ cooling tower

def _pp_cooling_tower(K, scale):
    cx, cy = TOWER_XY
    rb, rt, hgt = 1.16*scale, .80*scale, 3.90*scale
    basin_r = rb+.15
    K.cyl('tower_basin', cx, cy, .15, basin_r, .30, K.mat('f_base'), segments=32)
    K.washer('tower_basin_kerb', (cx, cy, .31), (0, 0, 1), basin_r-.08, basin_r+.01, .03, K.mat('stone'), seg=32)
    tower = K.cooling_tower('tower', cx, cy, .30, hgt, r_base=rb, r_throat=rt, throat_frac=.72,
                            seg=TOWER_SEG, rings=20, leg_h=.30*scale, legs=12, bands=0)
    # Lift bands and rim on the shell's own facets, proud of it by more than the 3D view's
    # outline shell (about 4.5 cm), which otherwise pokes through and breaks them up.
    shell_z0, sh = .30+.30*scale, hgt-.30*scale
    for b in range(1, 4):
        z = shell_z0+sh*b/4.4
        _pp_band(K, f'tower_band{b}', cx, cy, z, tower['radius_at'](z))
    rim = bpy.data.objects.get('tower_rim')
    if rim is not None: bpy.data.objects.remove(rim, do_unlink=True)
    _pp_band(K, 'tower_rim', cx, cy, tower['top']-.02, tower['r_top'], out=.06, inset=.06, t=.06)
    return dict(cx=cx, cy=cy, basin_r=basin_r)


TOWER_SEG = 32


def _pp_band(K, name, cx, cy, z, r, seg=TOWER_SEG, out=.055, inset=.03, t=.05):
    """A flat band ring on the same facets as the shell, sunk into it and proud by `out`."""
    m = bpy.data.meshes.new(name)
    bm = bmesh.new()
    rings = []
    for rr, dz in ((r-inset, -t/2), (r+out, -t/2), (r+out, t/2), (r-inset, t/2)):
        rings.append([bm.verts.new((cx+rr*math.cos(2*math.pi*j/seg), cy+rr*math.sin(2*math.pi*j/seg), z+dz)) for j in range(seg)])
    for i in range(4):
        A, B = rings[i], rings[(i+1) % 4]
        for j in range(seg):
            k = (j+1) % seg
            bm.faces.new([A[j], A[k], B[k], B[j]])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(m); bm.free()
    return K.obj(name, m, K.mat('f_frame'))


def _pp_cooling_pipes(K, tower, hall):
    """Two cooling-water lines straight from the hall's left end wall into the tower basin."""
    cx, cy, br = tower['cx'], tower['cy'], tower['basin_r']
    z = .20
    for i, y in enumerate((cy-.25, cy+.25)):
        xb = cx+math.sqrt(max(0.0, br*br-(y-cy)**2))-.06
        K.dircyl(f'cooling{i}', (hall['x0']+.02, y, z), (xb, y, z), .085, K.mat('white_pipe'), segments=14)
        K._fine_mode = True
        K.box('cooling_sleeper', (hall['x0']+xb)/2, y, .05, .10, .26, .10, K.mat('f_base'))
        K._fine_mode = False
        _v2_flange(K, f'cooling{i}_collar', hall['x0']-.005, y, z, 'x', w=.24, h=.24)


# ------------------------------------------------------------------ fuel, transformers

def _pp_service_pipes(K, back):
    """Four fuel and service lines, fuel-neutral: out of the heat block's (or the open
    boiler's) back wall, an elbow down, and into the ground through concrete collars, tied
    by a steel strap."""
    x0, x1 = BLOCK[:2]
    y1 = back
    cx = (x0+x1)/2
    xs = [cx+d for d in (-.45, -.15, .15, .45)]
    z, out = 1.55, .42
    _r_pad(K, 'service_pad', xs[0]-.30, xs[-1]+.30, y1+.10, y1+out+.22)
    for i, x in enumerate(xs):
        K.pipe_run(f'service{i}', [(x, y1+.01, z), (x, y1+out, z), (x, y1+out, .10)], .075, mat=K.mat('white_pipe'), bend=.16)
        _v2_flange(K, f'service{i}_collar', x, y1+.02, z, 'y', w=.22, h=.22)
        K.box(f'service{i}_ground', x, y1+out, .09, .24, .24, .10, K.mat('f_base'))
    # Steel strap tying the four drops, carried on two posts.
    K.dirbox('service_strap', (xs[0]-.16, y1+out+.10, .95), (xs[-1]+.16, y1+out+.10, .95), .05, .07, K.mat('f_frame'))
    for x in (xs[0]-.16, xs[-1]+.16):
        K.dirbox('service_post', (x, y1+out+.10, .06), (x, y1+out+.10, .99), .06, .06, K.mat('f_frame'))


def _pp_fence(K, x0, x1, y0, y1, h=.30):
    K._fine_mode = True
    for a, b in (((x0, y0), (x1, y0)), ((x1, y0), (x1, y1)), ((x1, y1), (x0, y1)), ((x0, y1), (x0, y0))):
        A, B = Vector((*a, .07)), Vector((*b, .07))
        n = max(1, math.ceil((B-A).length/.40))
        for i in range(n+1):
            p = A.lerp(B, i/n)
            K.dircyl('fence_post', p, p+Vector((0, 0, h)), .014, K.mat('f_frame'), segments=6)
        for z in (.10, h):
            K.dircyl('fence_rail', A+Vector((0, 0, z)), B+Vector((0, 0, z)), .010, K.mat('f_frame'), segments=6)
    K._fine_mode = False


def _pp_yard(K, n_tx, kiosk, hall_x1, pylon=False):
    """The transformer yard in the corridor beside the turbine hall, running back towards
    the chimney: transformers in a column, an overhead three-phase line along the corridor
    from a light front frame to the takeoff gantry at the back, a short dropper from each
    transformer's bushings up to the line, and a bus duct from the hall's end wall to each."""
    x0, x1, y0, y1 = YARD
    K.box('yard_gravel', (x0+x1)/2, (y0+y1)/2, .035, x1-x0, y1-y0, .07, K.mat('membrane'))
    K.box('yard_kerb', (x0+x1)/2, (y0+y1)/2, .02, x1-x0+.08, y1-y0+.08, .04, K.mat('f_base'))
    _pp_fence(K, x0+.04, x1-.04, y0+.04, y1-.04)
    s_ = 1.30
    tx = 3.22
    spots = [(tx, y) for y in (-2.45, -1.75, -1.05, -.35)][:n_tx]
    for i, (x, y) in enumerate(spots):
        K.transformer(f'tx{i}', x, y, .07, s=s_, fins=5)
    _pp_recolour(K, 'tx', 'p_turbine', 'p_tx')
    # Phases directly above the bushings, so each dropper is a short vertical.
    phases = [tx+k*.14*s_ for k in (-1, 0, 1)]
    bush_z = .07+.68*s_
    line_z = 1.32
    # Takeoff at the back of the yard by the chimney: a gantry with strings over the phases
    # at L1 and L2; at L3 a light frame there, and the line rises to a tall lattice pylon
    # behind the yard.
    gy = y1-.25
    ga, gb = phases[0]-(phases[1]-phases[0]), phases[2]+(phases[1]-phases[0])
    ha = (line_z-.07)/.78
    fy = y0+.20

    def h_frame(name, y):
        for px in (ga, gb):
            K.box(name+'_foot', px, y, .10, .12, .12, .06, K.mat('f_base'))
            K.dirbox(name+'_post', (px, y, .07), (px, y, line_z+.10), .06, .06, K.mat('f_frame'))
        K.dirbox(name+'_beam', (ga-.04, y, line_z+.06), (gb+.04, y, line_z+.06), .05, .06, K.mat('f_frame'))
        for px in phases:
            K.dircyl(name+'_insulator', (px, y, line_z+.03), (px, y, line_z-.08), .022, K.mat('p_insulator'), segments=8)
    if not pylon:
        K.substation_gantry('gantry', (ga, gy), (gb, gy), .07, ha, strings=3, busbar=False)
    K._fine_mode = True
    h_frame('line_frame', fy)
    if pylon:
        h_frame('line_frame_back', gy)
    for k, px in enumerate(phases):
        K.dircyl('line_phase', (px, fy, line_z), (px, gy, line_z), .010, K.mat('f_frame'), segments=6)
        for i, (x, y) in enumerate(spots):
            K.dircyl(f'tx{i}_dropper', (px, y, bush_z), (px, y, line_z), .009, K.mat('f_frame'), segments=6)
    K._fine_mode = False
    if pylon:
        _pp_pylon(K, phases, gy, line_z)
    # Bus ducts from the hall's end wall onto each transformer's front edge. Transformers
    # beyond the hall's back wall get an elbow round from the last bay.
    z = .95
    drop_x = tx-.20
    hall_back = HALL_Y[1]
    for i, (x, y) in enumerate(spots):
        land = y-.13
        if land < hall_back-.15:
            path = [(hall_x1, land), (drop_x, land)]
        else:
            yo = hall_back-.15
            path = [(hall_x1, yo), (hall_x1+.42, yo), (hall_x1+.42, land), (drop_x, land)]
        for j, (a, b) in enumerate(zip(path, path[1:])):
            K.dirbox(f'busduct{i}_{j}', (*a, z), (*b, z), .14, .16, K.mat('f_zinc'))
        for j, p_ in enumerate(path[1:-1]):
            K.box(f'busduct{i}_elbow{j}', p_[0], p_[1], z, .16, .16, .18, K.mat('f_zinc'))
        K.dirbox(f'busduct{i}_drop', (drop_x, land, z+.08), (drop_x, land, .07+.44*s_), .14, .16, K.mat('f_zinc'))
        _v2_flange(K, f'busduct{i}_collar', hall_x1+.01, path[0][1], z, 'x', w=.22, h=.24)
        K._fine_mode = True
        px = (hall_x1+drop_x)/2 if len(path) == 2 else hall_x1+.42
        py = path[0][1] if len(path) == 2 else (path[1][1]+path[2][1])/2
        K.dirbox('busduct_post', (px, py, .07), (px, py, z-.08), .05, .05, K.mat('f_frame'))
        K._fine_mode = False
    if kiosk:
        kx, ky = x1-.30, y0+.55
        K.box('kiosk', kx, ky, .30, .30, .46, .46, K.mat('white_wall'))
        K.box('kiosk_roof', kx, ky, .55, .36, .52, .04, K.mat('f_frame'))
        _pp_door(K, 'kiosk_door', '+X', (kx+.155, ky, .07+.24/2), .13, .24, ribs=2)


PYLON_XY = (2.70, 1.05)            # the back right corner, behind the yard


def _pp_pylon(K, phases, from_y, from_z):
    """L3's takeoff: a tall lattice transmission pylon in the back right corner, on its own
    gravel, square to the grid like the rest of the plant, with the three phases rising to
    the insulators on its near arms. The arm positions follow the kit's pylon geometry, which
    builds the arms along Y; `turn` turns the whole pylon about its own axis."""
    px, py = PYLON_XY
    H, w, arm, z0 = 3.20, .64, .48, .07
    turn = 0.0                              # square to the grid, like the rest of the plant
    before = {ob.name for ob in K.col.objects}
    K.pylon('pylon', px, py, z0, H, w_base=w, tiers=3, insulators=True, arm_len=arm)
    from mathutils import Matrix
    M = Matrix.Translation((px, py, 0)) @ Matrix.Rotation(turn, 4, 'Z') @ Matrix.Translation((-px, -py, 0))
    for ob in K.col.objects:
        if ob.name not in before:
            ob.matrix_world = M @ ob.matrix_world
    K.box('pylon_gravel', px, py, .035, .90, .90, .07, K.mat('membrane'))
    K.box('pylon_kerb', px, py, .02, .98, .98, .04, K.mat('f_base'))
    body = H*.92; w_mid, w_top, sh = w*.42, w*.30, .45
    def half_at(z):
        t = max(0.0, min(1.0, (z-z0)/body))
        if t <= sh: return (w+(w_mid-w)*(t/sh))/2
        return (w_mid+(w_top-w_mid)*((t-sh)/(1-sh)))/2
    dep = H*.055
    K._fine_mode = True
    for t, x in enumerate(phases):
        az = z0+body*(.93-.20*t)
        d = half_at(az)+arm*(1+.20*t)
        tx_, ty_ = px+d*math.sin(turn), py-d*math.cos(turn)
        end_z = az+dep*.30-.02-H*.085
        K.dircyl('line_rise', (x, from_y, from_z), (tx_, ty_, end_z), .010, K.mat('f_frame'), segments=6)
    K._fine_mode = False


# ------------------------------------------------------------------ build

def build_power_plant_v2(level=1):
    assert level in (1, 2, 3)
    K = _pp_begin()
    # Paving follows the plant: a front apron under the hall and chimney, a back strip under
    # the heat block. The yard has its own kerbed gravel; the tower stands on its basin.
    _r_pad(K, 'site_pad_front', -2.55 if level >= 2 else -1.45, 2.95, -3.35, .45)
    _r_pad(K, 'site_pad_back', -2.55, 2.80, .45, 1.85)
    # The heat plant grows: open boiler at L1, a shorter windowless block at L2, the full
    # block with windows at L3. The chimney is half height at L1.
    if level == 1:
        heat = _pp_open_boiler(K)
        flue_z = 1.40
    else:
        heat = _pp_heat_block(K, 2.00 if level == 2 else BLOCK_H, windows=level == 3)
        flue_z = 1.40 if level == 2 else 2.05
    rad = _pp_chimney(K, 2.70 if level == 1 else STACK_TOP)
    _pp_flue_duct(K, heat['right'], flue_z, rad)
    _pp_steam_lines(K, heat['front'])
    _pp_service_pipes(K, heat['back'])
    # The hall is the same length at every level; L1 runs one set, L2 and L3 two.
    hall_x1 = 2.25
    turbines = [(-.15, 1.30), (1.45, 1.30)][:1 if level == 1 else 2]
    hall = _pp_turbine_hall(K, hall_x1, turbines)
    if level >= 2:
        tower = _pp_cooling_tower(K, 1.0)
        _pp_cooling_pipes(K, tower, hall)
    _pp_yard(K, 2 if level == 1 else 4, level >= 3, hall_x1, pylon=level >= 3)
    return _r_finish(K, level, 'power v2: heat block, chimney, glazed turbine hall, cooling tower, transformer yard')
