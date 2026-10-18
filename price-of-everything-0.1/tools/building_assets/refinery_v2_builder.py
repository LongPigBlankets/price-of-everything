"""The petrochemical refinery and the polymerisation refinery, rebuilt from the owner's two
reference illustrations (17 October 2026) in the catalogue look.

Executed in sprite_kit's namespace after furnace_builder.py and furnace_v2_builder.py, whose
palette and helpers it shares (windows, rails, downpipes, gutters, flanges). Staged as
families 'petro_refinery_v2' and 'poly_plant_v2'; they install as 'petro_refinery' and
'poly_plant'.

Screen vocabulary at this camera: back = +Y (top-right), right = +X (lower-right),
front = -Y (bottom-left), left = -X (upper-left).

Petrochemical refinery (reference 1): storage tanks in a bund at the left, distillation
columns with orange platforms at the back, a pipe rack carrying their lines forward, a
render-clad control building at the front, a flare on a lattice tower at the right, and a
tanker loading canopy at the front left. Flows: crude from the tanks along the rack into the
columns; column overheads and products back along the rack to the exchanger and the loading
arm; relief to the flare.

Polymerisation refinery (reference 2): stirred reactors with top drives at the left, pellet
silos on a steel frame with a top walkway at the back, a clad process building with a roller
door at the centre, an extruder and pelletiser line at the front left, and a bagging canopy
at the right. Flows: monomer into the reactors; polymer down to the extruder hopper; pellets
blown along a sleepered line to the silo frame, up and along the walkway into each silo; the
silo cones discharge into a collector running forward into the bagging canopy.

Fixed across levels (the furnace rule): the flare, the control building and the process
building stand in the same places at every level; upgrades add plant around them.
"""
import math
from mathutils import Vector

PALETTE.update({
    'r_shell': (.600, .590, .560),     # vessel and tank shells: the references' warm white
    'r_deck': (.070, .075, .080),      # every walkway floor, platform and stair tread: black-grey
    'r_yellow': (.520, .352, .045),    # barriers, rails and ladders: the factory's safety yellow
    'r_cab': (.150, .260, .380),       # tanker cab
    'r_bag': (.700, .690, .650),       # bulk bags
})

# The kit's process assemblies paint through roles. Remapped only while a refinery builds.
# Floors are black-grey, barriers yellow; the kit's accent (column bands, silo cones) takes the
# vessel white, so the plants carry no orange.
REFINERY_ROLES = {'column': 'r_shell', 'drum': 'r_shell', 'vessel': 'r_shell', 'accent': 'r_shell',
                  'walkway': 'r_deck', 'handrail': 'r_yellow', 'stair': 'r_deck', 'pipe': 'white_pipe'}


# Triangle budget. The kit's defaults (32-segment cylinders, 24-segment sweeps, 10-step
# elbows) are finer than the sprite or the 3D view can show, and a refinery has dozens of
# columns, rings and pipe bends. These caps apply only while a refinery builds.
_KIT_CAPS = {'cyl': ('segments', 24), 'dircyl': ('segments', 14), 'sweep': ('seg', 12),
             'washer': ('seg', 24), 'elbow': ('steps', 6)}


def _r_cap_segments():
    import inspect
    for method, (arg, cap) in _KIT_CAPS.items():
        original = getattr(Kit, method)
        if getattr(original, '_capped', False): continue
        params = list(inspect.signature(original).parameters)
        default = inspect.signature(original).parameters[arg].default
        index = params.index(arg)-1     # position among the arguments after self
        def capped(self, *a, _f=original, _arg=arg, _cap=cap, _default=default, _i=index, **k):
            if len(a) > _i:
                a = a[:_i]+(min(a[_i], _cap),)+a[_i+1:]
            else:
                k[_arg] = min(k.get(_arg, _default), _cap)
            return _f(self, *a, **k)
        capped._capped = True
        setattr(Kit, method, capped)


def _r_begin(collection):
    _r_cap_segments()
    setup_rig(ortho_scale=11.6, target=(0, 0, 1))
    fs = bpy.context.scene.view_layers[0].freestyle_settings
    fs.linesets['ink'].linestyle.thickness = 1.45
    fs.linesets['ink_fine'].linestyle.thickness = .80
    ROLES.update(REFINERY_ROLES)
    K = Kit(open_collection(collection))
    for ls in fs.linesets:
        ls.select_by_face_marks = True; ls.face_mark_negation = 'EXCLUSIVE'; ls.face_mark_condition = 'ONE'
    return K


def _r_finish(K, level, style):
    for ob in K.col.objects:
        if ob.type == 'MESH' and len(ob.data.materials) == 1 and ob.data.materials[0] in (K.mat('f_zinc'), K.mat('r_shell')):
            K.gloss(ob, dark=.24, light=1.40, dark_from=.35, glint=(-.88, -.60))
    bpy.context.view_layer.update()
    pts = [o.matrix_world @ v.co for o in K.col.objects if o.type == 'MESH' for v in o.data.vertices]
    u = [(v.x+v.y)/math.sqrt(2) for v in pts]; z = [(2*v.z-v.x+v.y)/math.sqrt(6) for v in pts]
    uc, zc = (min(u)+max(u))/2, (min(z)+max(z))/2
    target = Vector((uc/math.sqrt(2), uc/math.sqrt(2), zc*math.sqrt(6)/2))
    bpy.context.scene.camera.location = target+Vector((1, -1, 1)).normalized()*26
    warnings = [w for w in K.validate(ground=-.01) if not w.startswith('bbox world')]
    assert not warnings, warnings
    return dict(level=level, objects=len(K.col.objects), style=style, warnings=warnings)


# ------------------------------------------------------------------ shared parts

def _r_pad(K, name, x0, x1, y0, y1, t=.06):
    """A paved concrete pad under a group of plant. Equipment stands on its top."""
    K.box(name, (x0+x1)/2, (y0+y1)/2, t/2, x1-x0, y1-y0, t, K.mat('f_base'))
    return t


def _r_block(K, name, x0, x1, y0, y1, h, z0=0.0, wall='white_wall'):
    """Flat-roofed block: one solid wall mass, a stone coping proud of it, a membrane roof
    inside the coping. Nothing is buried in a hollow wall, so nothing shows through in 3D."""
    cx, cy, w, d = (x0+x1)/2, (y0+y1)/2, x1-x0, y1-y0
    K.box(name+'_footing', cx, cy, z0+.04, w+.08, d+.08, .08, K.mat('f_base'))
    K.box(name+'_walls', cx, cy, z0+.08+(h-.08)/2, w, d, h-.08, K.mat(wall))
    K.box(name+'_coping', cx, cy, z0+h+.03, w+.06, d+.06, .06, K.mat('stone'))
    K.box(name+'_roof', cx, cy, z0+h+.07, w-.10, d-.10, .04, K.mat('membrane'))
    return z0+h+.09


def _r_roof_units(K, name, xy, z):
    for i, (x, y) in enumerate(xy):
        K.box(f'{name}{i}', x, y, z+.07, .22, .22, .14, K.mat('silver'))
        K.box(f'{name}{i}_cap', x, y, z+.155, .26, .26, .03, K.mat('f_frame'))


def _r_lamp(K, name, x, y, h=1.15):
    K._fine_mode = True
    K.box(name+'_base', x, y, .04, .10, .10, .08, K.mat('f_base'))
    K.dircyl(name+'_post', (x, y, .08), (x, y, h), .022, K.mat('f_frame'), segments=8)
    K.dircyl(name+'_arm', (x, y, h), (x+.14, y-.14, h), .016, K.mat('f_frame'), segments=8)
    K.box(name+'_head', x+.16, y-.16, h-.02, .09, .09, .04, K.mat('silver'))
    K._fine_mode = False


def _r_pipe_rack(K, name, a, b, z=1.05, half=.26, pipes=3, spacing=.70, footing_z=0.0):
    """A pipe rack along a world axis from a to b (x, y): portal bents on footings, a beam
    each side, and pipes resting on the crossbeams."""
    a, b = Vector((a[0], a[1], 0)), Vector((b[0], b[1], 0))
    along = (b-a).normalized(); side = Vector((-along.y, along.x, 0))
    n = max(1, round((b-a).length/spacing))
    for i in range(n+1):
        p = a.lerp(b, i/n)
        for s in (-1, 1):
            q = p+side*half*s
            K.box(f'{name}_foot{i}{s}', q.x, q.y, footing_z+.05, .16, .16, .10, K.mat('f_base'))
            K.dirbox(f'{name}_col{i}{s}', (q.x, q.y, footing_z+.10), (q.x, q.y, z), .07, .07, K.mat('f_frame'))
        K.dirbox(f'{name}_beam{i}', p-side*(half+.04)+Vector((0, 0, z)), p+side*(half+.04)+Vector((0, 0, z)), .07, .08, K.mat('f_frame'))
    for s in (-1, 1):
        K.dirbox(f'{name}_rail{s}', a+side*half*s+Vector((0, 0, z+.07)), b+side*half*s+Vector((0, 0, z+.07)), .05, .06, K.mat('f_frame'))
    lines = []
    for k in range(pipes):
        off = (k-(pipes-1)/2)*(2*half-.12)/max(1, pipes-1) if pipes > 1 else 0.0
        r = .055 if k != pipes//2 else .075
        p0 = a+side*off+Vector((0, 0, z+.04+r)); p1 = b+side*off+Vector((0, 0, z+.04+r))
        K.dircyl(f'{name}_pipe{k}', p0-along*.12, p1+along*.12, r, K.mat('white_pipe'), segments=14)
        lines.append((p0, p1, r))
    return lines


def _r_ring_rail(K, name, cx, cy, z, r, h=.20, posts=12):
    """A circular guardrail as thin rings on posts. The kit's ring_rail draws its rails as
    solid discs, which cover a tank roof."""
    K._fine_mode = True
    for tag, dz in (('top', h), ('mid', h*.55)):
        K.washer(f'{name}_{tag}', (cx, cy, z+dz), (0, 0, 1), r-.014, r+.014, .028, K.mat('r_yellow'), seg=36)
    for k in range(posts):
        a = 2*math.pi*k/posts
        K.box(f'{name}_p{k}', cx+r*math.cos(a), cy+r*math.sin(a), z+h/2, .032, .032, h, K.mat('r_yellow'))
    K._fine_mode = False


def _r_rail(K, name, a, b, h=.22):
    """A straight guardrail in barrier yellow: posts, a mid rail and a top rail."""
    a, b = Vector(a), Vector(b)
    n = max(1, math.ceil((b-a).length/.55))
    K._fine_mode = True
    for i in range(n+1):
        p = a.lerp(b, i/n)
        K.dircyl(f'{name}_post{i}', p, p+Vector((0, 0, h)), .014, K.mat('r_yellow'), segments=8)
    for z in (h*.5, h):
        K.dircyl(f'{name}_bar', a+Vector((0, 0, z)), b+Vector((0, 0, z)), .013, K.mat('r_yellow'), segments=8)
    K._fine_mode = False


def _r_ladder_cage(K, name, x, y, z0, z1, face='+X'):
    K.ladder(name, x, y, z0, z1, face=face, w=.22, mat=K.mat('r_yellow'), rung=.22)


# ------------------------------------------------------------------ petrochemical refinery

FLARE_XY = (2.95, 1.25)
CONTROL = (-1.05, .95, -2.05, -.70)     # x0, x1, y0, y1 of the control building


def _p_tank(K, name, cx, cy, r, h):
    K.flat_tank(name, cx, cy, r, h, band=False, stair=True, vent=True, mat=K.mat('r_shell'))
    _r_ring_rail(K, name+'_crown_rail', cx, cy, h+.09, r-.05, h=.16, posts=14)


def _p_bund(K, x0, x1, y0, y1):
    t, h = .10, .26
    # The floor stops inside the walls, so no floor face shares a plane with a wall face.
    K.box('bund_floor', (x0+x1)/2, (y0+y1)/2, .02, x1-x0-2*t, y1-y0-2*t, .04, K.mat('f_base'))
    for nm, cx, cy, sx, sy in (('front', (x0+x1)/2, y0+t/2, x1-x0, t), ('back', (x0+x1)/2, y1-t/2, x1-x0, t),
                               ('left', x0+t/2, (y0+y1)/2, t, y1-y0-2*t), ('right', x1-t/2, (y0+y1)/2, t, y1-y0-2*t)):
        K.box('bund_'+nm, cx, cy, h/2, sx, sy, h, K.mat('stone'))


def _p_column(K, name, cx, cy, top, r, platforms):
    K.frac_column(name, cx, cy, top, r, trays=max(5, round(top/.6)), platforms=platforms, skirt_h=.45)
    # The kit's platform barrier is a solid band; in yellow it reads as a thick ring. Replace
    # it with the open post-and-rail barrier the tanks and reactors use.
    pw = max(.10, r*.45)
    for j, pz in enumerate(platforms):
        band = bpy.data.objects.get(f'{name}_rail{j}')
        if band is not None: bpy.data.objects.remove(band, do_unlink=True)
        _r_ring_rail(K, f'{name}_barrier{j}', cx, cy, pz+.025, r+pw-.016, h=.20, posts=12)
    # Ladder up the lit face to the top platform.
    _r_ladder_cage(K, name+'_ladder', cx+r+.03, cy, .45, platforms[-1] if platforms else top-.4, face='+X')


def _p_flare(K):
    x, y = FLARE_XY
    K.box('flare_pad', x, y, .04, 1.25, 1.25, .08, K.mat('f_base'))
    for sx in (-1, 1):
        for sy in (-1, 1):
            K.box('flare_foot', x+sx*.45, y+sy*.45, .12, .20, .20, .08, K.mat('f_base'))
    K.derrick('flare_tower', x, y, .16, 3.70, .90, .34, bays=6, leg_r=.032)
    K.dircyl('flare_stack', (x, y, .16), (x, y, 4.20), .085, K.mat('f_frame'), segments=16)
    for z, w in ((1.95, .70), (3.70, .44)):
        K.box('flare_platform', x, y, z, w, w, .05, K.mat('r_deck'))
    K.flare_tip('flare', x, y, 4.20, r=.12, flame=False)
    # One droplet mesh, its pointed underside tucked inside the shield, leaning screen-right
    # with the 2D view's wind. Baked because the 3D view has no animated flame.
    # Its own emissive, dimmer and more saturated than the kit ember: the print sends anything
    # as light as the ember toward paper and drains it to peach.
    flame_mat = _emissive('r_flame', (0.95, 0.32, 0.02), 1.0)
    fh = .95
    K.flame('flare_flame', x, y, 4.20+.22, .20, fh, flame_mat, lean=fh*.26)
    return (x, y, 4.20)


def _p_canopy(K, x0, x1, y0, y1, h=1.05):
    for i, cx in enumerate((x0+.10, x1-.10)):
        for j, cy in enumerate((y0+.10, y1-.10)):
            K.box(f'canopy_foot{i}{j}', cx, cy, .05, .16, .16, .10, K.mat('f_base'))
            K.dirbox(f'canopy_col{i}{j}', (cx, cy, .10), (cx, cy, h), .07, .07, K.mat('f_frame'))
    for cy in (y0+.10, y1-.10):
        K.dirbox('canopy_beam', (x0+.05, cy, h), (x1-.05, cy, h), .07, .09, K.mat('f_frame'))
    K.prism('canopy_roof', ((x0+x1)/2, (y0+y1)/2, 0), (0, 1),
            [(-(y1-y0)/2-.10, h+.05), ((y1-y0)/2+.10, h+.13), ((y1-y0)/2+.10, h+.17), (-(y1-y0)/2-.10, h+.09)],
            x1-x0+.20, K.mat('f_roof'))


def _p_tanker(K, x, y):
    """A parked road tanker pointing +X: cab, chassis, barrel, wheels."""
    K.box('tanker_chassis', x, y, .17, 1.30, .30, .06, K.mat('f_frame'))
    K.dircyl('tanker_barrel', (x-.62, y, .40), (x+.34, y, .40), .20, K.mat('r_shell'), segments=24)
    for e in (x-.62, x+.34):
        K.cyl('tanker_end', e, y, .40, .205, .02, K.mat('f_frame'), axis='X', segments=24)
    K.box('tanker_cab', x+.58, y, .36, .30, .32, .36, K.mat('r_cab'))
    K.box('tanker_screen', x+.735, y, .44, .012, .26, .12, K.mat('glass'))
    for wx in (x-.48, x-.24, x+.62):
        for s in (-1, 1):
            K.cyl('tanker_wheel', wx, y+s*.15, .10, .085, .06, K.mat('ink_black'), axis='Y', segments=16)


def build_petro_refinery_v2(level=1):
    assert level in (1, 2, 3)
    K = _r_begin('BLDG_petro_refinery_v2')
    # Tanks in their bund at the left; the back tank at every level, the front from L2.
    tanks = [(-2.35, 1.55)] + ([(-2.35, -.35)] if level >= 2 else [])
    _p_bund(K, -3.30, -1.40, -1.30 if level >= 2 else .55, 2.55)
    for i, (tx, ty) in enumerate(tanks):
        _p_tank(K, f'tank{i}', tx, ty, .78, 1.05)
    # Process pad and columns at the back; the tall column at every level.
    _r_pad(K, 'process_pad', -.95, 2.20, .35, 2.55)
    cols = [('col_tall', .55, 1.55, 4.60, .40, (1.60, 3.10, 4.25))]
    if level >= 2: cols.append(('col_left', -.55, .95, 3.60, .33, (1.60, 3.25)))
    # The third column stands in front of the tall one, clear of the flare tower's screen column.
    if level >= 3: cols.append(('col_right', 1.75, 1.00, 3.20, .32, (1.60, 2.85)))
    for nm, cx, cy, top, r, plats in cols:
        _p_column(K, nm, cx, cy, top, r, plats)
    # Rack along X in front of the columns, carrying lines forward to the plant.
    rack_y = .02
    rack_x1 = 2.55 if level >= 2 else 1.60
    lines = _r_pipe_rack(K, 'rack', (-1.25, rack_y), (rack_x1, rack_y), z=1.05, pipes=3)
    top_line = lines[1]
    rack_z = top_line[0].z
    # Each column: an overhead line from its head down to the rack, and a bottoms line.
    for nm, cx, cy, top, r, plats in cols:
        K.pipe_run(nm+'_overhead', [(cx-r*.5, cy-r*.3, top+.10), (cx-r-.18, cy-r*.3, top+.10), (cx-r-.18, cy-r*.3, rack_z+.20),
                                    (cx-r-.18, rack_y+.10, rack_z+.20), (cx-r-.18, rack_y+.10, rack_z)], .06, mat=K.mat('white_pipe'), bend=.14)
        K.pipe_run(nm+'_bottoms', [(cx, cy-r, .70), (cx, rack_y+.24, .70), (cx, rack_y+.24, rack_z-.13)], .06, mat=K.mat('white_pipe'), bend=.12)
    # Feed from each tank into the rack's near end.
    # Each tank has its own line and its own riser into the rack.
    for i, (tx, ty) in enumerate(tanks):
        lx, rx = (-1.52, -1.42) if i == 0 else (-1.64, -1.08)   # risers clear of the bent at x -1.25
        K.pipe_run(f'tank{i}_feed', [(tx+.78, ty, .35), (lx, ty, .35), (lx, rack_y-.16+.10*i, .35), (rx, rack_y-.16+.10*i, .35),
                                     (rx, rack_y-.16+.10*i, rack_z-.10)], .055, mat=K.mat('white_pipe'), bend=.10)
    # Exchanger bullet on its own pad, fed from the rack's far end (L2+).
    if level >= 2:
        _r_pad(K, 'exchanger_pad', 1.55, 2.95, -1.35, -.55)
        K.bullet('exchanger', (1.75, -.95, .42), (2.80, -.95, .42), .26)
        K.pipe_run('exchanger_feed', [(rack_x1, rack_y, rack_z), (rack_x1+.20, rack_y, rack_z), (rack_x1+.20, -.95, rack_z),
                                      (2.80+.20, -.95, rack_z), (2.80+.20, -.95, .42), (2.80, -.95, .42)], .055, mat=K.mat('white_pipe'), bend=.12)
    # Relief line from the rack to the flare, at every level.
    fx, fy, ftop = _p_flare(K)
    K.pipe_run('relief', [(rack_x1-.10, rack_y+.18, rack_z+.08), (rack_x1-.10, fy-.62, rack_z+.08), (fx-.62, fy-.62, rack_z+.08),
                          (fx-.62, fy-.62, .40), (fx-.09, fy-.62, .40), (fx-.09, fy, .40)], .06, mat=K.mat('white_pipe'), bend=.12)
    # Control building at the front, fixed at every level.
    x0, x1, y0, y1 = CONTROL
    roof_z = _r_block(K, 'control', x0, x1, y0, y1, 1.05)
    K._fine_mode = True
    _v2_window(K, 'control_strip', '-Y', ((x0+x1)/2+.20, y0-.055, .72), 1.10, .22, cols=5, rows=1)
    K._fine_mode = False
    K.gate('control_door', '-Y', (x0+.32, y0-.02, .50), .48, .74)
    K.box('control_porch', x1+.18, (y0+y1)/2-.20, .55, .36, .60, .90, K.mat('white_wall'))
    K.box('control_porch_roof', x1+.20, (y0+y1)/2-.20, 1.03, .44, .68, .05, K.mat('membrane'))
    K.door('control_side_door', '+X', (x1+.37, (y0+y1)/2-.20, .44), .34, .66)
    _r_roof_units(K, 'control_vent', [(x0+.45, y0+.45), (x1-.40, y1-.35), (x1-.40, y0+.40)], roof_z)
    # Tanker loading at the front left, from L2: canopy, arm from the rack, a parked tanker.
    if level >= 2:
        _p_canopy(K, -3.00, -1.35, -2.20, -1.40)
        _p_tanker(K, -2.15, -1.80)
        K.pipe_run('loading_line', [(-1.25, rack_y, rack_z), (-1.25, -1.47, rack_z), (-1.25, -1.47, 1.05+.05), (-2.05, -1.47, 1.05+.05)],
                   .05, mat=K.mat('white_pipe'), bend=.12)
        K.pipe_run('loading_arm', [(-2.05, -1.47, 1.10), (-2.05, -1.80, 1.10), (-2.05, -1.80, .64)], .04, mat=K.mat('white_pipe'), bend=.08)
    return _r_finish(K, level, 'refinery v2: bund tanks, columns, rack, control building, flare, loading')


# ------------------------------------------------------------------ polymerisation refinery

PROCESS = (-.45, 1.75, -1.65, .05)
DECK_W = .20                        # reactor shoulder walkway width     # x0, x1, y0, y1 of the process building
SILO_Y = 1.45
SILO_XS = (.15, 1.15, 2.15)


def _y_reactor(K, name, cx, cy, r, h):
    """Stirred reactor on legs: dished shell, top drive, crown platform with a rail."""
    leg_top = .55
    for i in range(4):
        t = math.pi/4+i*math.pi/2
        lx, ly = cx+r*.82*math.cos(t), cy+r*.82*math.sin(t)
        K.box(f'{name}_foot{i}', lx, ly, .05, .18, .18, .10, K.mat('f_base'))
        K.dirbox(f'{name}_leg{i}', (lx, ly, .10), (lx, ly, leg_top+.25), .07, .07, K.mat('f_frame'))
    K.cyl(name+'_shell', cx, cy, leg_top+h/2, r, h, K.mat('r_shell'))
    K.dome_cap(name+'_bottom', cx, cy, leg_top, r, -.22*r, K.mat('r_shell'), rings=5)
    K.dome_cap(name+'_head', cx, cy, leg_top+h, r, .30*r, K.mat('r_shell'), rings=5)
    K._fine_mode = True
    for z in (leg_top+h*.33, leg_top+h*.66):
        K.washer(name+'_band', (cx, cy, z), (0, 0, 1), r-.005, r+.03, .05, K.mat('f_frame'))
    K._fine_mode = False
    deck = leg_top+h-.02
    K.washer(name+'_deck', (cx, cy, deck), (0, 0, 1), r-.004, r+DECK_W, .05, K.mat('r_deck'), seg=40)
    _r_ring_rail(K, name+'_rail', cx, cy, deck+.025, r+DECK_W-.02, h=.20, posts=12)
    K.agitator(name+'_drive', cx, cy, leg_top+h+.30*r, s=1.0)
    _r_ladder_cage(K, name+'_ladder', cx+r+DECK_W+.01, cy, .10, deck, face='+X')
    return leg_top, deck


def _y_silo_frame(K, xs, y, top):
    """Steel frame carrying the silos, with a walkway and rail along their tops."""
    x0, x1 = xs[0]-.55, xs[-1]+.55
    posts = [(x, y+.55) for x in (x0, x1)+tuple((a+b)/2 for a, b in zip(xs, xs[1:]))] + [(x0, y-.55), (x1, y-.55)]
    for x, py in posts:
        K.box('frame_foot', x, py, .05, .18, .18, .10, K.mat('f_base'))
        K.dirbox('frame_col', (x, py, .10), (x, py, top), .08, .08, K.mat('f_frame'))
    for z in (1.05, top):
        K.dirbox('frame_beam_back', (x0-.04, y+.55, z), (x1+.04, y+.55, z), .07, .08, K.mat('f_frame'))
        for x in (x0, x1):
            K.dirbox('frame_beam_end', (x, y-.59, z), (x, y+.59, z), .07, .08, K.mat('f_frame'))
    K.dirbox('frame_beam_front', (x0-.04, y-.55, top), (x1+.04, y-.55, top), .07, .08, K.mat('f_frame'))
    K.box('frame_walkway', (x0+x1)/2, y-.40, top+.03, x1-x0, .34, .05, K.mat('r_deck'))
    _r_rail(K, 'frame_walk_rail', (x0, y-.57, top+.055), (x1, y-.57, top+.055), h=.22)
    K.ladder('frame_ladder', x1+.06, y-.40, .10, top+.06, face='+X', w=.22, mat=K.mat('r_yellow'), rung=.22)


def _y_extruder(K, x0, y):
    """Extruder line along X: feed hopper, barrel on a stand, die and pelletiser boxes."""
    K.box('extruder_pad', x0+.95, y, .03, 2.10, .80, .06, K.mat('f_base'))
    for x in (x0+.25, x0+1.05, x0+1.75):
        K.box('extruder_stand', x, y, .30, .10, .44, .48, K.mat('f_frame'))
    K.box('extruder_bed', x0+1.00, y, .58, 1.80, .46, .08, K.mat('f_frame'))
    K.dircyl('extruder_barrel', (x0+.30, y, .76), (x0+1.55, y, .76), .13, K.mat('silver'), segments=18)
    K._fine_mode = True
    for i in range(5):
        K.washer('extruder_heater', (x0+.50+i*.22, y, .76), (1, 0, 0), .13, .16, .08, K.mat('f_frame'))
    K._fine_mode = False
    K.box('extruder_drive', x0+.15, y, .84, .30, .40, .40, K.mat('r_shell'))
    K.cone('extruder_hopper', x0+.45, y, 1.20, .06, .22, .34, K.mat('r_shell'))
    K.box('pelletiser', x0+1.75, y, .80, .32, .38, .40, K.mat('r_shell'))
    K.box('pelletiser_cap', x0+1.75, y, 1.02, .36, .42, .04, K.mat('f_frame'))
    return (x0+.45, y, 1.37), (x0+1.75, y, 1.02)


def _y_canopy(K, x0, x1, y0, y1, h=1.10):
    _p_canopy(K, x0, x1, y0, y1, h=h)
    for i, (bx, by) in enumerate([(x0+.40, y0+.40), (x0+.40, y0+.85), (x0+.85, y0+.40)]):
        K.box(f'pallet{i}', bx, by, .03, .40, .40, .06, K.mat('f_sheet'))
        K.box(f'bag{i}', bx, by, .24, .32, .32, .36, K.mat('r_bag'))
        K._fine_mode = True
        for s in (-1, 1):
            K.box(f'bag{i}_loop', bx+s*.10, by, .45, .03, .20, .06, K.mat('r_bag'))
        K._fine_mode = False
    # Bagging hopper fed from the silo collector.
    hx, hy = x1-.45, y1-.40
    K.box('bagger_frame', hx, hy, .45, .40, .40, .06, K.mat('f_frame'))
    for sx in (-1, 1):
        for sy in (-1, 1):
            K.dirbox('bagger_leg', (hx+sx*.17, hy+sy*.17, 0.0), (hx+sx*.17, hy+sy*.17, .45), .05, .05, K.mat('f_frame'))
    K.cone('bagger_hopper', hx, hy, .70, .06, .20, .44, K.mat('r_shell'))
    return (hx, hy, .92)


def build_poly_plant_v2(level=1):
    assert level in (1, 2, 3)
    K = _r_begin('BLDG_poly_plant_v2')
    n = level
    # Process building at the centre, fixed at every level.
    x0, x1, y0, y1 = PROCESS
    roof_z = _r_block(K, 'process', x0, x1, y0, y1, 1.40)
    K._fine_mode = True
    _v2_window(K, 'process_clerestory', '-Y', ((x0+x1)/2, y0-.055, 1.12), 1.70, .18, cols=6, rows=1)
    _v2_window(K, 'process_side', '+X', (x1+.055, (y0+y1)/2, 1.12), 1.20, .18, cols=4, rows=1)
    K._fine_mode = False
    K.gate('process_roller', '-Y', (x0+1.30, y0-.02, .52), .72, .84)
    K.door('process_door', '-Y', (x0+.32, y0-.02, .44), .30, .66)
    _r_roof_units(K, 'process_vent', [(x0+.50, y0+.55), (x1-.55, y0+.50), (x1-.55, y1-.45)], roof_z)
    # Reactors at the left: one at L1, two at L2, three at L3.
    # Spaced so the shoulder walkways keep a clear gap between neighbours.
    reactors = [('reactor_a', -2.50, .00, .58, 1.55), ('reactor_b', -1.25, 1.05, .55, 1.50), ('reactor_c', -2.40, 2.05, .40, 1.05)][:n]
    _r_pad(K, 'reactor_pad', -3.35, -.65, -.85, 2.75 if n >= 3 else 1.75)
    tops = []
    for nm, cx, cy, r, h in reactors:
        leg_top, deck = _y_reactor(K, nm, cx, cy, r, h)
        tops.append((nm, cx, cy, r, leg_top, deck))
    # Silos on their frame at the back: one at L1, two at L2, three at L3.
    xs = SILO_XS[:n]
    silo_top = 3.25
    for i, sx in enumerate(xs):
        K.pellet_silo(f'silo{i}', sx, SILO_Y, .42, 1.05, .62, silo_top)
    _y_silo_frame(K, xs, SILO_Y, silo_top+.12)
    # Extruder line at the front left from L2; at L1 the reactor feeds the building directly.
    if n >= 2:
        hopper, pellet_out = _y_extruder(K, -3.05, -1.25)
        # Polymer from each reactor's bottom outlet into the extruder hopper.
        # Each reactor has its own run and its own inlet on the hopper's crown.
        for (nm, cx, cy, r, leg_top, deck), dx, ry in zip(tops[:2], (-.07, .07), (-.80, -.60)):
            hx = hopper[0]+dx
            K.pipe_run(nm+'_out', [(cx, cy, leg_top-.12), (cx, cy, .30), (cx, ry, .30), (hx, ry, .30),
                                   (hx, ry, hopper[2]+.10), (hx, hopper[1], hopper[2]+.10), (hx, hopper[1], hopper[2])],
                       .05, mat=K.mat('white_pipe'), bend=.10)
        # Pellets blown back along sleepers to the silo frame, up it and along the walkway.
        px, py, pz = pellet_out
        run_x = xs[0]-.55-.18
        K.pipe_run('pellet_line', [(px, py, pz), (px, py, .25), (px, -1.95, .25), (run_x, -1.95, .25), (run_x, SILO_Y-.75, .25),
                                   (run_x, SILO_Y-.75, silo_top+.40), (xs[-1], SILO_Y-.75, silo_top+.40)], .06, mat=K.mat('white_pipe'), bend=.14)
        K._fine_mode = True
        for i in range(6):
            sx_ = px+(run_x-px)*(i+.5)/6
            K.box('pellet_sleeper', sx_, -1.95, .07, .08, .24, .14, K.mat('f_base'))
        K._fine_mode = False
    else:
        nm, cx, cy, r, leg_top, deck = tops[0]
        run_x = xs[0]-.55-.18
        K.pipe_run('pellet_line', [(cx, cy, leg_top-.12), (cx, cy, .30), (run_x, cy, .30), (run_x, SILO_Y-.75, .30),
                                   (run_x, SILO_Y-.75, silo_top+.40), (xs[-1], SILO_Y-.75, silo_top+.40)], .06, mat=K.mat('white_pipe'), bend=.14)
    for i, sx in enumerate(xs):
        K.pipe_run(f'silo{i}_fill', [(sx, SILO_Y-.75, silo_top+.40), (sx, SILO_Y-.75, silo_top+.55), (sx, SILO_Y, silo_top+.55), (sx, SILO_Y, silo_top+.05)],
                   .045, mat=K.mat('white_pipe'), bend=.08)
    # Bagging canopy at the right; the silo cones discharge into a collector running to it.
    bx = _y_canopy(K, x1+.05, x1+1.40, y0, y0+1.30)
    coll_z = .48
    K.pipe_run('collector', [(xs[0], SILO_Y, .55), (xs[0], SILO_Y, coll_z), (xs[-1]+.70, SILO_Y, coll_z), (xs[-1]+.70, bx[1], coll_z),
                             (bx[0], bx[1], coll_z), (bx[0], bx[1], bx[2]-.20)], .06, mat=K.mat('white_pipe'), bend=.12)
    for i, sx in enumerate(xs[1:], 1):
        K.dircyl(f'silo{i}_drop', (sx, SILO_Y, .55), (sx, SILO_Y, coll_z), .05, K.mat('white_pipe'), segments=12)
    if n >= 3:
        hut = _r_block(K, 'control_hut', -3.30, -2.65, -1.95, -1.45, .80)
        K.door('control_hut_door', '+X', (-2.65+.05, -1.70, .40), .26, .56)
    return _r_finish(K, level, 'poly v2: reactors, silo frame, process building, extruder, bagging canopy')
