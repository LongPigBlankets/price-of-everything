"""Supply-chain civic infill, using the office kit's 1.1u floor module.

Two office silhouettes, a grey L block and public-space plots. Original Blender
office/sprite builders remain the reference; these are renderer-only assets.
"""
import math
import bpy

PALETTE.update({
    'civic_grey': (.265, .280, .295), 'civic_stone': (.31, .305, .28),
    'civic_paving': (.255, .26, .25), 'civic_lawn': (.16, .25, .105),
    'civic_water': (.10, .245, .31), 'civic_hedge': (.09, .18, .085),
    'civic_frame': (.36, .37, .38),
})
FLOOR = 1.1
BAY = .9


def _building_rig():
    # Housing was authored at .45u per storey. Match its ink per storey, rather
    # than thinning the line just because these source models use larger units.
    setup_rig(ortho_scale=11.0 * FLOOR / .45)


def _paint(ob):
    """Painted detail should not acquire the building's silhouette stroke."""
    marks = ob.data.attributes.get('freestyle_face')
    if marks is None: marks = ob.data.attributes.new('freestyle_face', 'BOOLEAN', 'FACE')
    for face in marks.data: face.value = True
    return ob


def _window(k, name, face, center, width=.55, height=.68):
    before = set(k.col.objects)
    k.window(name, face, center, width, height, 2, 1, sill=True)
    for ob in set(k.col.objects) - before:
        _paint(ob)
        if not ob.name.endswith('_glass'):
            ob.data.materials.clear()
            ob.data.materials.append(k.mat('civic_frame'))
            # Retain modelled frames, but the old bright, wide trim made a
            # second outline around every opening. Halve its thickness.
            if ob.name.endswith(('_fl', '_fr', '_mv1')):
                axis = 0 if face.endswith('Y') else 1
            else:
                axis = 2
            midpoint = (min(v.co[axis] for v in ob.data.vertices) + max(v.co[axis] for v in ob.data.vertices)) / 2
            for v in ob.data.vertices: v.co[axis] = midpoint + (v.co[axis] - midpoint) * .5


def _facade(k, name, cx, cy, width, depth, floors, base=.10, walls='chalk', faces=('-Y', '+Y', '-X', '+X'), pitch=0.0):
    height = floors * FLOOR
    k.box(name, cx, cy, base + height / 2, width, depth, height, k.mat(walls))
    # Recessed dark roof stays visible inside separate parapet edges.
    _paint(k.box(name+'_roof', cx, cy, base+height+.015, width-.10, depth-.10, .04, k.mat('deck')))
    for sx in (-1, 1):
        k.box(name+f'_parapet_x{sx}', cx+sx*(width/2-.05), cy, base+height+.075, .10, depth, .15, k.mat(walls))
    for sy in (-1, 1):
        k.box(name+f'_parapet_y{sy}', cx, cy+sy*(depth/2-.05), base+height+.075, width-.10, .10, .15, k.mat(walls))
    for face in faces:
        along = width if face.endswith('Y') else depth
        bays = max(2, int((along-.10+1e-6) / pitch)) if pitch else max(2, int(along / .85))
        for floor in range(floors):
            for bay in range(bays):
                at = (bay-(bays-1)/2)*pitch if pitch else (bay+.5)*along/bays-along/2
                z = base + floor*FLOOR + .58
                center = (cx+at, cy+(-1 if face[0]=='-' else 1)*depth/2, z) if face.endswith('Y') else (cx+(-1 if face[0]=='-' else 1)*width/2, cy+at, z)
                _window(k, f'{name}_{face}_{floor}_{bay}', face, center, min(.58, along/bays-.20))
        # Slim floor stringcourses; keep the masonry dominant over dark ink.
        for floor in range(1, floors):
            z = base + floor*FLOOR
            if face.endswith('Y'):
                _paint(k.box(f'{name}_{face}_course{floor}', cx, cy+(-1 if face[0]=='-' else 1)*(depth/2+.025), z,
                             width, .055, .035, k.mat(walls)))
            else:
                _paint(k.box(f'{name}_{face}_course{floor}', cx+(-1 if face[0]=='-' else 1)*(width/2+.025), cy, z,
                             .055, depth, .035, k.mat(walls)))
    return base + height + .15


def _plant(k, name, x, y, z):
    k._fine_mode = True
    k.box(name+'_plinth', x, y, z+.08, .80, .62, .16, k.mat('stack_grey'))
    k.box(name+'_unit', x, y, z+.22, .64, .48, .20, k.mat('silver'))
    for dx in (-.17, .17):
        _paint(k.cyl(name+f'_fan{dx}', x+dx, y, z+.33, .12, .015, k.mat('darkmetal'), segments=12))
    k._fine_mode = False


def _entry(k, x, y):
    # A legible entrance pavilion with canopy, brick jambs and glazed doors.
    k.box('entry_frame', x, y-.10, .56, 1.05, .30, 1.12, k.mat('wall_brick'))
    _window(k, 'entry_glass', '-Y', (x, y-.26, .55), .79, .89)
    k.box('entry_canopy', x, y-.40, 1.17, 1.36, .92, .10, k.mat('roof_deck'))
    _paint(k.box('entry_step', x, y-.43, .055, 1.44, .96, .11, k.mat('civic_stone')))


def build_civic_office(level=1):
    _building_rig()
    k = Kit(open_collection('BLDG_civic_office'))
    if level == 1:
        # Long civic office: central entrance, three storeys, roof plant.
        roof = _facade(k, 'bar', 0, 0, 6.4, 2.85, 3)
        _entry(k, 0, -1.425)
        for x in (-2.7, 2.7):
            _paint(k.box('pilaster'+str(x), x, -1.455, 1.75, .08, .07, 3.30, k.mat('chalk')))
        _plant(k, 'plant_a', -1.9, .25, roof)
        _plant(k, 'plant_b', 1.8, .25, roof)
        _paint(k.box('rooflight', 0, .3, roof+.06, 1.35, .55, .10, k.mat('window_glass')))
    else:
        # Set-back corner office: a fourth storey above a broad three-floor base.
        roof = _facade(k, 'podium', 0, 0, 5.8, 3.7, 3, walls='civic_grey')
        top = _facade(k, 'setback', .25, .3, 4.4, 2.7, 1, base=roof-.08)
        _entry(k, -.45, -1.85)
        _plant(k, 'plant', .7, .55, top)
        k.box('terrace_planter', -2.4, -.9, roof+.15, .30, 1.1, .26, k.mat('civic_stone'))
        _paint(k.box('terrace_green', -2.4, -.9, roof+.31, .26, 1.04, .14, k.mat('civic_hedge')))
    print('CIVIC', level, 'objects', len(k.col.objects))
    return {'level': level, 'storey_height': FLOOR}


def build_civic_l(level=1):
    _building_rig()
    k = Kit(open_collection('BLDG_civic_l'))
    # Two bars form a real open L, not a rectangle painted to suggest a courtyard.
    roof = _facade(k, 'street_wing', 0, -1.6, 6.3, 2.05, 4, walls='civic_grey', faces=('-Y','-X','+X'))
    _facade(k, 'return_wing', -2.15, .95, 2.0, 3.12, 4, walls='civic_grey', faces=('-X','+X','+Y'))
    # The exposed courtyard elevation of the street wing.
    for floor in range(4):
        for i in range(4): _window(k, f'court_{floor}_{i}', '+Y', (-.65+i*.88, -.575, .68+floor*FLOOR))
    _entry(k, .65, -2.625)
    _plant(k, 'plant', -2.1, .95, roof)
    _paint(k.box('courtyard', .55, .82, .035, 3.3, 2.35, .07, k.mat('civic_paving')))
    _paint(k.box('courtyard_bed', .55, 1.05, .10, 1.9, .60, .12, k.mat('civic_hedge')))
    return {'level': level, 'storey_height': FLOOR}


def build_civic_long(level=1, columns=7):
    """Whole window bays: only the number of repeated facade units changes."""
    assert 4 <= columns <= 10
    _building_rig()
    k = Kit(open_collection('BLDG_civic_long'))
    width = columns * BAY + .10
    roof = _facade(k, 'bar', 0, 0, width, 2.85, 3, pitch=BAY)
    _entry(k, 0, -1.425)
    for i, x in enumerate((-width/2+.5, width/2-.5)):
        _paint(k.box(f'pilaster{i}', x, -1.455, 1.75, .08, .07, 3.30, k.mat('chalk')))
    _plant(k, 'plant_a', -width/2+.85, .25, roof)
    if columns >= 6: _plant(k, 'plant_b', width/2-.85, .25, roof)
    _paint(k.box('rooflight', .35 if columns < 6 else 0, .3, roof+.06, 1.10, .55, .10, k.mat('window_glass')))
    return {'level': level, 'storey_height': FLOOR,
            'civic_module': {'shape': 'long', 'columns': columns, 'return_columns': 0, 'bay_pitch': BAY}}


def build_civic_corner(level=1, columns=7, return_columns=3):
    """A joined L envelope with independent whole-bay wing lengths."""
    assert 4 <= columns <= 8 and 2 <= return_columns <= 4
    _building_rig()
    k = Kit(open_collection('BLDG_civic_corner'))
    width, wing = columns * BAY + .10, 2.05
    depth = wing + return_columns * BAY + .10
    x0, x1, y0, y1 = -width/2, width/2, -depth/2, depth/2
    inner_x, inner_y = x0 + wing, y0 + wing
    outline = [(x0,y0),(x1,y0),(x1,inner_y),(inner_x,inner_y),(inner_x,y1),(x0,y1)]
    top = .1 + 4*FLOOR
    # One concave body and roof: no doubled walls or contour seams where wings meet.
    k.poly_prism('body', outline, .1, top, k.mat('civic_grey'))
    inset = [(x0+.1,y0+.1),(x1-.1,y0+.1),(x1-.1,inner_y-.1),
             (inner_x-.1,inner_y-.1),(inner_x-.1,y1-.1),(x0+.1,y1-.1)]
    _paint(k.poly_prism('roof', inset, top+.005, top+.045, k.mat('deck')))
    entry_x = (inner_x+x1)/2
    for edge, (a,b) in enumerate(zip(outline, outline[1:]+outline[:1])):
        horizontal = abs(a[1]-b[1]) < 1e-6
        length = abs(b[0]-a[0]) if horizontal else abs(b[1]-a[1])
        # CCW boundary: outward normal is the right-hand side of each edge.
        face = ('-Y' if b[0]>a[0] else '+Y') if horizontal else ('+X' if b[1]>a[1] else '-X')
        cx, cy = (a[0]+b[0])/2, (a[1]+b[1])/2
        nx, ny = ((0,-1 if face=='-Y' else 1) if horizontal else (1 if face=='+X' else -1,0))
        k.box(f'parapet{edge}', cx-nx*.05, cy-ny*.05, top+.075,
              length if horizontal else .10, .10 if horizontal else length, .15, k.mat('civic_grey'))
        count = max(1, int((length-.10+1e-6)/BAY))
        for floor in range(4):
            for bay in range(count):
                along = (bay-(count-1)/2)*BAY
                wx, wy = (cx+along,cy) if horizontal else (cx,cy+along)
                if edge == 0 and floor == 0 and abs(wx-entry_x) < .65: continue
                _window(k, f'e{edge}_f{floor}_b{bay}', face, (wx,wy,.68+floor*FLOOR), .58)
            if floor:
                _paint(k.box(f'course{edge}_{floor}', cx+nx*.025, cy+ny*.025, .1+floor*FLOOR,
                             length if horizontal else .055, .055 if horizontal else length, .035, k.mat('civic_grey')))
    _entry(k, entry_x, y0)
    _plant(k, 'plant', x0+wing/2, y1-.75, top+.15)
    cw, cd = x1-inner_x-.2, y1-inner_y-.2
    _paint(k.box('courtyard', (inner_x+x1)/2, (inner_y+y1)/2, .035, cw, cd, .07, k.mat('civic_paving')))
    # Repeat fixed planter units too; no stretching of the courtyard furniture.
    for i in range(max(1, int(cw/1.3))):
        px = inner_x+.65+i*1.3
        _paint(k.box(f'court_bed{i}', px, y1-.55, .10, .9, .6, .12, k.mat('civic_hedge')))
    return {'level': level, 'storey_height': FLOOR,
            'civic_module': {'shape': 'l', 'columns': columns, 'return_columns': return_columns, 'bay_pitch': BAY}}


def _bench(k, name, x, y):
    k._fine_mode = True
    for dx in (-.29, .29): k.box(name+str(dx), x+dx, y, .14, .075, .34, .28, k.mat('darkmetal'))
    for i in range(3): _paint(k.box(name+f'_seat{i}', x, y-.12+i*.12, .30, .86, .095, .075, k.mat('wall_brick')))
    _paint(k.box(name+'_back', x, y+.20, .49, .86, .065, .24, k.mat('wall_brick')))
    k._fine_mode = False


def build_civic_park(level=1):
    setup_rig()
    k = Kit(open_collection('BLDG_civic_park'))
    _paint(k.box('edge', 0, 0, .02, 5.8, 4.6, .04, k.mat('civic_stone')))
    # Abutting lawn/path regions: no coplanar grid overlays or heavy outlines.
    for x in (-1.575, 1.575):
        for y in (-1.075, 1.075):
            _paint(k.box(f'lawn{x}{y}', x, y, .05, 2.45, 1.45, .06, k.mat('civic_lawn')))
    for i, (x,y) in enumerate([(-2,-1.1),(2,-1.1),(-2,1.1),(2,1.1)]):
        k.tree(f'park_tree{i}', x, y, h=1.65, r=.48, seed=70+i)
    for x in (-.85,.85): _bench(k, 'bench'+str(x), x, 1.35)
    return {'level': level}


def build_civic_plaza(level=1):
    setup_rig()
    k = Kit(open_collection('BLDG_civic_plaza'))
    _paint(k.box('square', 0, 0, .03, 5.8, 4.6, .06, k.mat('civic_stone')))
    # Small recessed paving joints are tonal, not navy wire lines.
    for x in range(-3,4):
        _paint(k.box(f'pave_x{x}', x*.72, 0, .063, .018, 4.38, .006, k.mat('civic_paving')))
    for y in range(-2,3):
        _paint(k.box(f'pave_y{y}', 0, y*.72, .063, 5.58, .018, .006, k.mat('civic_paving')))
    k.cyl('fountain_rim', 0, 0, .17, .84, .23, k.mat('stack_grey'), segments=24)
    _paint(k.cyl('fountain_water', 0, 0, .292, .70, .02, k.mat('civic_water'), segments=24))
    k.cyl('fountain_pedestal', 0, 0, .44, .15, .34, k.mat('civic_stone'), segments=12)
    k.cyl('fountain_bowl', 0, 0, .62, .34, .09, k.mat('stack_grey'), segments=16)
    for i,(x,y) in enumerate([(-2.05,-1.25),(2.05,1.25)]):
        k.box(f'planter{i}', x, y, .17, .90, .90, .24, k.mat('stack_grey'))
        k.tree(f'plaza_tree{i}', x, y, h=1.48, r=.44, seed=80+i)
    for x in (-1.6,1.6): _bench(k, 'bench'+str(x), x, -.8)
    return {'level': level}
