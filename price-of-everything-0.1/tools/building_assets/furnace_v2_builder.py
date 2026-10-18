"""Furnace V2: a generic shaft-furnace works for every high-temperature recipe.

Executed in sprite_kit's namespace after furnace_builder.py, so it shares the
furnace palette and the brick shed, rail and deck helpers. The works is composed
from large masses that survive 64 px: an L-shaped brick range of stockhouse tower
and regenerator wing, silos, a level charging bridge, straight-sided shaft furnaces
with downcomers to the regenerator, a long refractory hall with a louvred monitor
roof and glowing working bays, and one thin chimney. L1 is a simplified old blast
furnace. No bosh taper, no hot-blast stoves, no yellow rails, no polished steel:
nothing that says iron rather than glass, copper or graphite.
"""
import math
from mathutils import Vector

# The catalogue factory's material vocabulary. Names matter: the 3D export prints brick
# coursing on 'brick', standing seams on 'f_roof', gravel on 'membrane', panel joints on
# 'f2_refractory' and paving on 'f_base' tops (export_models.py PATTERNS).
PALETTE.update({
    'f_brick': (.380, .165, .095),         # the catalogue factory's warm clay brick
    'f_roof': (.250, .300, .330),          # pitched roofs: the factory's standing-seam sheet
    'membrane': (.120, .125, .130),        # flat roofs: the factory's gravel membrane
    'stone': (.600, .560, .470),           # lintels, sills, cornices, chimney bands
    'white_pipe': (.700, .660, .580),      # process pipework, as on the factory
    'interior': (.040, .036, .032),        # the dark room seen through the glass
    'f2_refractory': (.215, .225, .225),   # hall cladding, kept under the vertical-face ceiling
    'f2_filter': (.15, .16, .165),
    'f2_drum': (.10, .115, .125),          # shaft furnace plate, a step lighter than f_shell
})

HALL_H = 1.10            # the L1 cast hall's height, so the drums show as much shell as L1's vessel
SHAFT_R = .60
SHAFT_TOP = 3.35         # the same height as L1's old vessel
BRIDGE_Z = 3.82          # the lift top: L1's incline and L2/L3's bridge both end here
HOUSING_RISE = .32       # refractory collar round each shaft, this far above the roof line
HOUSING_R = SHAFT_R+.08
STACK_XY = (3.90, -.65)  # one thin black-topped chimney, same place at every level
STACK_TOP = 4.94
HOUSE_EAVE = 4.10        # every lift housing shares one eave and one ridge
HOUSE_RISE = .22
TOWER_H = 4.45           # the lift tower clears the elevator head house under its eaves
STONE = 'stone'          # stone lintels and sills, as on the catalogue factory


# The catalogue factory plate is lit by Godot; this sprite is lit by Blender and the face
# mask. The same base colour therefore prints lighter and more orange here. Measured on the
# printed sprites (lit face, brick body): factory (141, 86, 62), furnace with the factory
# value (164, 111, 79). A per-channel linear ratio, tuned so the mean of the two lit faces
# matches the factory, is applied to the sprite's brick texture only; the material's own
# base colour keeps the factory value for the GLB.
SPRITE_BRICK_RATIO = (.76, .69, .80)
# The joints take the same ratio with less blue, which matches the factory's warm tan
# joint (155, 115, 91) instead of a cooler grey.
SPRITE_MORTAR_RATIO = (.76, .69, .62)
# building_paint.gdshaderinc: course 0.075, brick 0.21, joint lines 0.005 either side of
# the joint (0.010 wide), mortar = 60% lime (0.74, 0.70, 0.62) over the brick, ±5% per brick.
JOINT_HALF = .005


def _v2_gable_house(K, name, cx, cy, z0, along, across, ridge, wall='f_sheet', eave=None, roof='f_roof'):
    """A small gabled housing whose ridge runs along `ridge` ('x' or 'y'). A conveyor
    enters through a gable wall, never through a roof slope, so the junction is a
    square cut with its own outline. Walls from z0 to HOUSE_EAVE, roof to the ridge."""
    E = HOUSE_EAVE if eave is None else eave
    sx, sy = (along, across) if ridge == 'x' else (across, along)
    tdir = (0, 1) if ridge == 'x' else (1, 0)
    K.box(name+'_walls', cx, cy, (z0+E)/2, sx, sy, E-z0, K.mat(wall))
    K.prism(name+'_gable', (cx, cy, 0), tdir, [(-across/2, E), (0, E+HOUSE_RISE), (across/2, E)], along, K.mat(wall))
    k = HOUSE_RISE/(across/2); o = .07
    for s_ in (-1, 1):
        a, b = (-across/2-o, 0) if s_ < 0 else (0, across/2+o)
        za, zb = (E-k*o, E+HOUSE_RISE) if s_ < 0 else (E+HOUSE_RISE, E-k*o)
        K.prism(name+'_roof'+str(s_), (cx, cy, 0), tdir, [(a, za+.005), (b, zb+.005), (b, zb+.055), (a, za+.055)], along+.10, K.mat(roof))


def _v2_gallery_cover(K, name, p0, p1, w=.42, top=BRIDGE_Z+.17):
    """A shallow ridged cover along a level conveyor, so it reads as a covered gallery
    and runs into the housings' gables at the same pitch."""
    p0, p1 = Vector(p0), Vector(p1)
    along_x = abs(p1.x-p0.x) > abs(p1.y-p0.y)
    mid = (p0+p1)/2; length = (p1-p0).length
    prof = [(-w/2, top), (0, top+.07), (w/2, top), (w/2, top+.03), (0, top+.10), (-w/2, top+.03)]
    K.prism(name, (mid.x, mid.y, 0), (0, 1) if along_x else (1, 0), prof, length, K.mat('f_roof'))


def _v2_bent_gallery(K, name, path, y, half_w, half_h, mat):
    """A rectangular conveyor gallery along a polyline in the XZ plane at fixed y, built as
    one mesh with mitred bends, so a level run can turn into a climb with a clean fold
    instead of two boxes meeting at a skew. `path` is [(x, z), ...]."""
    import bmesh
    P = [Vector((x, 0, z)) for x, z in path]
    def normal(a, b):
        d = (b-a).normalized(); return Vector((-d.z, 0, d.x))
    rings = []
    for i, p in enumerate(P):
        if i == 0: m = normal(P[0], P[1]); sc = 1.0
        elif i == len(P)-1: m = normal(P[-2], P[-1]); sc = 1.0
        else:
            n0, n1 = normal(P[i-1], p), normal(p, P[i+1])
            m = (n0+n1).normalized(); sc = 1.0/m.dot(n0)
        o = m*half_h*sc
        rings.append([(p.x-o.x, y-half_w, p.z-o.z), (p.x-o.x, y+half_w, p.z-o.z),
                      (p.x+o.x, y+half_w, p.z+o.z), (p.x+o.x, y-half_w, p.z+o.z)])
    verts = [v for r in rings for v in r]; faces = []
    for i in range(len(rings)-1):
        a, b = 4*i, 4*(i+1)
        for k in range(4):
            faces.append((a+k, a+(k+1) % 4, b+(k+1) % 4, b+k))
    faces.append((3, 2, 1, 0)); n = 4*(len(rings)-1); faces.append((n, n+1, n+2, n+3))
    mesh = bpy.data.meshes.new(name); mesh.from_pydata(verts, [], faces); mesh.update()
    bm = bmesh.new(); bm.from_mesh(mesh); bmesh.ops.recalc_face_normals(bm, faces=bm.faces); bm.to_mesh(mesh); bm.free()
    return K.obj(name, mesh, K.mat(mat))


def _v2_flange(K, name, x, y, z, face, w=.48, h=.44):
    """A collar where a conveyor or duct passes a wall: a thin frame proud of the face."""
    if face in ('x', '-x', '+x'):
        K.box(name, x, y, z, .04, w, h, K.mat('f_frame'))
    else:
        K.box(name, x, y, z, w, .04, h, K.mat('f_frame'))


def _v2_factory_glass():
    """The catalogue factory's window glass: warm teal slate, see-through (BLENDED, alpha
    0.72), which the 3D export routes to the glass shader."""
    mt = bpy.data.materials.get('factory_glass') or bpy.data.materials.new('factory_glass')
    mt.use_nodes = True
    b = mt.node_tree.nodes.get('Principled BSDF')
    b.inputs['Base Color'].default_value = (.070, .140, .190, 1)
    b.inputs['Roughness'].default_value = 1.0
    if 'Specular IOR Level' in b.inputs: b.inputs['Specular IOR Level'].default_value = 0.0
    b.inputs['Alpha'].default_value = .72
    mt.surface_render_method = 'BLENDED'
    mt.use_backface_culling = False
    return mt


def _v2_window(K, name, face, centre, w, h, cols=2, rows=2):
    """The catalogue factory's window: cream frames and glazing bars, stone sill and
    a stone lintel above."""
    K.window(name, face, centre, w, h, cols=cols, rows=rows, sill=True)
    cx, cy, cz = centre
    glass = bpy.data.objects.get(name+'_glass')
    if glass is not None:
        glass.data.materials.clear(); glass.data.materials.append(_v2_factory_glass())
    # The dark room behind the pane, between the wall and the see-through glass.
    if face in ('-X', '+X'):
        K.box(name+'_interior', cx-(-1 if face == '-X' else 1)*.004, cy, cz, .006, w, h, K.mat('interior'))
    else:
        K.box(name+'_interior', cx, cy-(-1 if face == '-Y' else 1)*.004, cz, w, .006, h, K.mat('interior'))
    if face in ('-X', '+X'):
        sgn = -1 if face == '-X' else 1
        K.box(name+'_lintel', cx+sgn*.025, cy, cz+h/2+.075, .05, w+.16, .08, K.mat(STONE))
    else:
        sgn = -1 if face == '-Y' else 1
        K.box(name+'_lintel', cx, cy+sgn*.025, cz+h/2+.075, w+.16, .05, .08, K.mat(STONE))


def _v2_downpipe(K, name, x, y, z_top, z_bot, ground=True):
    """Rainwater downpipe: hopper head at the gutter, brackets, a shoe at the foot and a
    kerbed drain grate when it reaches the ground."""
    K.box(name+'_hopper', x, y, z_top-.04, .10, .10, .10, K.mat('silver'))
    K.dircyl(name+'_pipe', (x, y, z_top-.09), (x, y, z_bot+.07), .028, K.mat('silver'), segments=10)
    K.box(name+'_shoe', x, y, z_bot+.05, .08, .08, .06, K.mat('silver'))
    if ground:
        K.box(name+'_grate', x, y, .015, .20, .20, .03, K.mat('f_frame'))
    K._fine_mode = True
    z = z_top-.50
    while z > z_bot+.30:
        K.box(name+'_bracket', x, y, z, .07, .07, .025, K.mat('f_frame'))
        z -= .70
    K._fine_mode = False


def _v2_eave_gutters(K, name, x, y, w, d, h):
    """Eaves gutters along both long sides of an _f_shed roof (ridge along X)."""
    for s_ in (-1, 1):
        K.box(name+'_gutter'+str(s_), x, y+s_*(d/2+.12), h+.05, w+.16, .07, .06, K.mat('silver'))


def _v2_brick_print(K):
    """Print the catalogue factory's brick on the sprite: the stretcher bond, joint width,
    lime mix and brick-to-brick variation of building_paint.gdshaderinc. World-space
    coordinates, so courses line up across the separate wall boxes; the course direction
    follows the face normal and blends round cylinders; top faces stay plain. The
    material's base colour stays the flat palette value, which is what the GLB export
    reads, and the name keeps 'brick' so the 3D view's own pattern applies to it."""
    mt = K.mat('f_brick')
    nt = mt.node_tree; nodes = nt.nodes; links = nt.links
    bsdf = nodes.get('Principled BSDF')
    factory = PALETTE['f_brick']
    lime = (.74, .70, .62)
    brick = tuple(c*r for c, r in zip(factory, SPRITE_BRICK_RATIO))
    mortar = tuple((c*.4+l*.6)*r for c, l, r in zip(factory, lime, SPRITE_MORTAR_RATIO))
    geo = nodes.new('ShaderNodeNewGeometry')
    pos = nodes.new('ShaderNodeSeparateXYZ'); links.new(geo.outputs['Position'], pos.inputs['Vector'])
    nrm = nodes.new('ShaderNodeSeparateXYZ'); links.new(geo.outputs['Normal'], nrm.inputs['Vector'])
    def brick_tex(along):
        v = nodes.new('ShaderNodeCombineXYZ')
        links.new(pos.outputs[along], v.inputs['X']); links.new(pos.outputs['Z'], v.inputs['Y'])
        t = nodes.new('ShaderNodeTexBrick')
        t.offset = .5; t.offset_frequency = 2; t.squash = 1.0; t.squash_frequency = 2
        t.inputs['Color1'].default_value = (*[c*.95 for c in brick], 1)
        t.inputs['Color2'].default_value = (*[c*1.05 for c in brick], 1)
        t.inputs['Mortar'].default_value = (*mortar, 1)
        t.inputs['Scale'].default_value = 1.0
        # Blender applies Mortar Size on each side of a joint, so this is the half width.
        t.inputs['Mortar Size'].default_value = JOINT_HALF
        t.inputs['Mortar Smooth'].default_value = 0.0
        t.inputs['Bias'].default_value = 0.0
        t.inputs['Brick Width'].default_value = .21
        t.inputs['Row Height'].default_value = .075
        links.new(v.outputs['Vector'], t.inputs['Vector'])
        return t
    along_x = brick_tex('X')   # walls facing ±Y: courses run along world X
    along_y = brick_tex('Y')   # walls facing ±X: courses run along world Y
    def absval(sock):
        m = nodes.new('ShaderNodeMath'); m.operation = 'ABSOLUTE'; links.new(sock, m.inputs[0]); return m
    ax = absval(nrm.outputs['X']); ay = absval(nrm.outputs['Y']); az = absval(nrm.outputs['Z'])
    total = nodes.new('ShaderNodeMath'); total.operation = 'ADD'; links.new(ax.outputs[0], total.inputs[0]); links.new(ay.outputs[0], total.inputs[1])
    total.inputs[1].default_value = 0.0
    safe = nodes.new('ShaderNodeMath'); safe.operation = 'MAXIMUM'; links.new(total.outputs[0], safe.inputs[0]); safe.inputs[1].default_value = 1e-4
    fac = nodes.new('ShaderNodeMath'); fac.operation = 'DIVIDE'; links.new(ax.outputs[0], fac.inputs[0]); links.new(safe.outputs[0], fac.inputs[1])
    walls = nodes.new('ShaderNodeMixRGB'); walls.blend_type = 'MIX'
    links.new(fac.outputs[0], walls.inputs['Fac']); links.new(along_x.outputs['Color'], walls.inputs[1]); links.new(along_y.outputs['Color'], walls.inputs[2])
    # Top and bottom faces keep the flat colour.
    topness = nodes.new('ShaderNodeMath'); topness.operation = 'SMOOTH_MIN' if False else 'GREATER_THAN'
    links.new(az.outputs[0], topness.inputs[0]); topness.inputs[1].default_value = .7
    final = nodes.new('ShaderNodeMixRGB'); final.blend_type = 'MIX'
    links.new(topness.outputs[0], final.inputs['Fac']); links.new(walls.outputs['Color'], final.inputs[1]); final.inputs[2].default_value = (*brick, 1)
    links.new(final.outputs['Color'], bsdf.inputs['Base Color'])


def _v2_hall(K, name, x, y, w, d, h, bays):
    """Refractory-clad hall on a dark portal frame over a brick base course, open working
    bays with a recessed heat cue, and a louvred monitor along the ridge."""
    wall = K.mat('f2_refractory'); frame = K.mat('f_frame'); brick = K.mat('f_brick')
    K.box(name+'_footing', x, y, .08, w+.10, d+.10, .16, K.mat('f_base'))
    ph = .42
    # Each wall is a brick base course under the cladding, stacked in one plane. A
    # separate plinth laid against or into the wall showed through the cladding in the
    # 3D view; two stacked slabs leave nothing overlapping.
    zb = .16+ph
    def slab(nm, cx, cy, sx, sy):
        K.box(nm+'_base', cx, cy, (.10+zb)/2, sx, sy, zb-.10, brick)
        K.box(nm, cx, cy, (zb+h+.10)/2, sx, sy, h+.10-zb, wall)
    slab(name+'_back', x, y+d/2-.04, w, .08)
    for s in (-1, 1):
        slab(name+'_side'+str(s), x+s*(w/2-.04), y, .08, d)
        # Portal columns stand on the wall's face; buried columns showed through it in 3D.
        K.box(name+'_portal'+str(s), x+s*(w/2-.045), y-d/2-.065, .1+h/2, .085, .05, h, frame)
    front = y-d/2
    dw = .70
    cursor = x-w/2
    for i, cx in enumerate(bays):
        lo, hi = cx-dw/2, cx+dw/2
        slab(name+'_pier'+str(i), (cursor+lo)/2, front, lo-cursor, .08)
        K.box(name+'_lintel'+str(i), cx, front, h-.06, dw, .10, .32, frame)
        K.box(name+'_opening_shadow'+str(i), cx, front+.40, .49, dw-.06, .035, .70, K.mat('ink_black'))
        K.box(name+'_bay'+str(i)+'_heat', cx, front+.36, .40, dw*.44, .04, .16, K.mat('ember'))
        cursor = hi
    slab(name+'_pier_end', (cursor+x+w/2)/2, front, x+w/2-cursor, .08)
    # Portal columns between bays carry the frame through the cladding.
    K._fine_mode = True
    for i, cx in enumerate(bays):
        for s in (-1, 1):
            K.box(name+'_mullion'+str(i)+str(s), cx+s*(dw/2+.03), front-.065, h/2+.10, .05, .05, h-.08, frame)
    K._fine_mode = False
    rise = .26
    K.prism(name+'_gable', (x, y, 0), (0, 1), [(-d/2, h+.10), (0, h+.10+rise), (d/2, h+.10)], w, wall)
    for s in (-1, 1):
        ya, yb = (-d/2-.09, 0) if s < 0 else (0, d/2+.09)
        za, zb = (h+.08, h+.10+rise) if s < 0 else (h+.10+rise, h+.08)
        K.prism(name+'_roof'+str(s), (x, y, 0), (0, 1), [(ya, za), (yb, zb), (yb, zb+.055), (ya, za+.055)], w+.16, K.mat('f_roof'))
    # Louvred monitor along the ridge: the heat vent that every hot hall has.
    mw = w*.74; mz = h+.10+rise
    K.box(name+'_monitor_base', x, y, mz+.06, mw, .36, .12, K.mat('f_roof'))
    K.box(name+'_monitor_frame', x, y, mz+.22, mw-.06, .26, .22, frame)
    K.prism(name+'_monitor_roof', (x, y, 0), (0, 1), [(-.20, mz+.31), (0, mz+.43), (.20, mz+.31), (.20, mz+.36), (0, mz+.48), (-.20, mz+.36)], mw+.10, K.mat('f_roof'))
    K._fine_mode = True
    for i in range(3):
        for s in (-1, 1):
            K.box(name+'_louvre'+str(i)+str(s), x, y+s*.14, mz+.15+i*.06, mw-.14, .035, .022, K.mat('f_zinc'))
    for j in range(max(2, round(w/.26))+1):
        px = x-w/2+j*w/max(2, round(w/.26))
        for side in (-1, 1):
            K.dirbox(name+'_roof_seam', (px, y+side*(d/2+.06), h+.15), (px, y+side*.33, h+.10+rise*(1-.33/(d/2))+.06), .012, .012, K.mat('f_roof'))
    K._fine_mode = False
    # Rainwater goods as on the catalogue factory: front gutter and one downpipe.
    K.box(name+'_gutter', x, front-.07, h+.06, w+.10, .07, .06, K.mat('f_zinc'))
    K.dircyl(name+'_downpipe', (x+w/2-.16, front-.08, h+.03), (x+w/2-.16, front-.08, .22), .03, K.mat('f_zinc'), segments=10)
    K.box(name+'_drain', x+w/2-.16, front-.10, .05, .18, .14, .10, K.mat('f_base'))


def _v2_shaft(K, name, x, y, through_roof_z, gates=('left', 'right')):
    """Straight-sided shaft furnace: dark metal shell with silver hoops, the family
    crown (railed deck and charging lock) at L1's height, concrete ring, and a
    refractory housing where it rises through the hall roof: a ceramic collar from
    inside the roof up to a dark cap ring, so the junction reads as a built joint
    rather than a drum pushed through a roof."""
    K.cyl(name+'_ring', x, y, .12, SHAFT_R+.14, .24, K.mat('f_base'))
    K.cyl(name+'_drum', x, y, SHAFT_TOP/2+.12, SHAFT_R, SHAFT_TOP-.24, K.mat('f_shell'))
    z0 = through_roof_z-.45
    housing_top = through_roof_z+HOUSING_RISE
    K.cyl(name+'_housing', x, y, (z0+housing_top)/2, HOUSING_R, housing_top-z0, K.mat('f2_refractory'))
    K.washer(name+'_housing_cap', (x, y, housing_top), (0, 0, 1), SHAFT_R-.005, HOUSING_R+.05, .08, K.mat('f_frame'))
    K.cyl(name+'_head_ring', x, y, SHAFT_TOP-.07, SHAFT_R+.03, .14, K.mat('f_zinc'))
    K.cyl(name+'_top_plate', x, y, SHAFT_TOP+.04, SHAFT_R, .08, K.mat('f_frame'))
    _v2_crown(K, name+'_crown', x, y, SHAFT_TOP, w=1.30, d=1.22, gates=gates)
    K._fine_mode = True
    # Silver hoops up the shaft above the housing.
    z = housing_top+.38
    while z < SHAFT_TOP-.55:
        K.washer(name+'_hoop', (x, y, z), (0, 0, 1), SHAFT_R-.005, SHAFT_R+.04, .06, K.mat('f_zinc'))
        z += .45
    K._fine_mode = False
    # Service ladder on the lit +X face, standing on the housing cap, up to the crown
    # deck through the gate in its right-hand rail.
    K.ladder(name+'_ladder', x+SHAFT_R+.04, y, housing_top+.04, SHAFT_TOP+.25, face='+X', w=.22, mat=K.mat('f_frame'), rung=.24)
    return housing_top


def _v2_tower(K, x, y, silos, elevator_x, elevator_y):
    """Brick stockhouse tower with pitched roof, bucket elevator casing on its lit flank
    under a gabled head house centred on the charging bridge, and round raw-material
    silos feeding the elevator boot. The head house sits below the tower's eaves, so its
    roof butts the tower wall instead of running into the tower roof."""
    w = 1.30; d = 1.30; h = TOWER_H
    _f_shed(K, 'stockhouse', x, y, w, d, h, door=False)
    K._fine_mode = True
    _v2_window(K, 'stockhouse_window_front', '-Y', (x, y-d/2-.055, h-2.10), .62, .50, cols=2, rows=2)
    _v2_window(K, 'stockhouse_window_front_hi', '-Y', (x, y-d/2-.055, h-.75), .62, .50, cols=2, rows=2)
    _v2_window(K, 'stockhouse_window_side', '+X', (x+w/2+.055, y+.40, h-.75), .30, .50, cols=1, rows=2)
    # Rear: the -X face carries two windows and a door; the +Y face one window above
    # the regenerator wing's roof.
    _v2_window(K, 'stockhouse_window_rear', '-X', (x-w/2-.055, y+.10, h-2.10), .62, .50, cols=2, rows=2)
    _v2_window(K, 'stockhouse_window_rear_hi', '-X', (x-w/2-.055, y+.10, h-.75), .62, .50, cols=2, rows=2)
    _v2_window(K, 'stockhouse_window_back', '+Y', (x, y+d/2+.055, h-.75), .62, .50, cols=2, rows=2)
    K._fine_mode = False
    K.door('stockhouse_rear_door', '-X', (x-w/2-.02, y-.32, .55), .50, .90)
    K.box('stockhouse_rear_step', x-w/2-.14, y-.32, .04, .20, .66, .08, K.mat(STONE))
    _v2_eave_gutters(K, 'stockhouse', x, y, w, d, h)
    _v2_downpipe(K, 'stockhouse_dp_front', x-w/2+.12, y-d/2-.12, h+.05, 0.0)
    # The back downpipe drops past the regenerator wing's end wall to its own drain.
    _v2_downpipe(K, 'stockhouse_dp_back', x-w/2-.06, y+d/2+.12, h+.05, 0.0)
    K.door('stockhouse_door', '-Y', (x-.30, y-d/2-.06, .60), .50, .98)
    # Elevator casing on the +X flank, with head house at the bridge.
    ex = elevator_x
    ey = elevator_y
    K.box('elevator_casing', ex, ey, (BRIDGE_Z+.10)/2+.05, .40, .52, BRIDGE_Z+.10, K.mat('f_sheet'))
    hx0 = x+w/2+.005
    _v2_gable_house(K, 'elevator_head', hx0+.31, ey, BRIDGE_Z-.30, .62, .70, 'x')
    K.box('elevator_boot', ex, ey-.10, .32, .44, .74, .44, K.mat('f_frame'))
    K._fine_mode = True
    for z in (1.1, 2.1, 3.1):
        if z < BRIDGE_Z-.6:
            K.box('elevator_casing_seam', ex+.205, ey, z, .012, .50, .012, K.mat('f_frame'))
    K.box('elevator_inspection', ex+.21, ey, 2.10, .025, .30, .50, K.mat('f_frame'))
    K._fine_mode = False
    for i, (sx, sy) in enumerate(silos):
        K.box(f'silo{i}_pad', sx, sy, .08, .80, .80, .16, K.mat('f_base'))
        # Four legs carry a ring girder under the body; a tie ring braces them lower down.
        for lx, ly in ((-.26, -.26), (.26, -.26), (-.26, .26), (.26, .26)):
            K.box(f'silo{i}_leg', sx+lx, sy+ly, .625, .07, .07, .93, K.mat('f_frame'))
        K.washer(f'silo{i}_support_ring', (sx, sy, 1.13), (0, 0, 1), .30, .41, .08, K.mat('f_frame'))
        K.washer(f'silo{i}_tie_ring', (sx, sy, .55), (0, 0, 1), .34, .40, .05, K.mat('f_frame'))
        K.cone(f'silo{i}_hopper', sx, sy, .86, .10, .33, .52, K.mat('f_zinc'))
        K.cyl(f'silo{i}_body', sx, sy, 2.07, .33, 1.90, K.mat('f_zinc'))
        K.dome_cap(f'silo{i}_cap', sx, sy, 3.02, .33, .12, K.mat('f_zinc'), rings=4)
        K._fine_mode = True
        K.washer(f'silo{i}_band', (sx, sy, 1.55), (0, 0, 1), .325, .35, .05, K.mat('f_frame'))
        K.washer(f'silo{i}_band_hi', (sx, sy, 2.55), (0, 0, 1), .325, .35, .05, K.mat('f_frame'))
        K._fine_mode = False
        # Feed from the hopper into the elevator boot, with a visible support.
        # Feeds run square to the buildings: along X to the elevator line, then along Y
        # into the boot. Later silos end on the first silo's corner as a tee.
        boot = (ex-.02, ey-.10)
        if i == 0:
            pts = [(sx, sy, .62), (sx, sy+.001, .42), (boot[0], sy, .42), (boot[0], boot[1], .42)]
        else:
            pts = [(sx, sy, .62), (sx, sy+.001, .42), (boot[0], sy, .42), (boot[0], silos[0][1]-.07, .42)]
        K.pipe_run(f'silo{i}_feed', pts, .07, mat=K.mat('white_pipe'), bend=.10)


WING_Y0, WING_Y1 = 1.40, 2.35   # the regenerator range behind the hall, front and back faces
WING_TOP = 1.91                 # top of its brick, under the cornice and flat roof
WING_X0 = -2.62                 # 3 cm inside the tower's left face, so the two read as one L
AISLE_TOP = 1.12                # the back aisle's flat roof, under the hall's back eave


def _v2_back_range(K, hall_x0, hall_x1, hall_back_y, wing_x1, feet):
    """The tower and regenerator as one L-shaped brick range, and a back aisle that closes
    the hall up to it. The regenerator is a long low wing along the back of the hall
    running out from the tower; each downcomer lands on its roof through a collar, and the
    waste gas leaves its far end by the low flue into the chimney base. The back aisle is
    a flat-roofed refractory lean-to between the hall's back wall and the wing, so the
    drums rise out of roofs on every side."""
    # Back aisle: long faces hidden inside the hall wall and the wing; ends and roof show.
    ay0, ay1 = hall_back_y-.02, WING_Y0+.05
    aw = hall_x1-hall_x0; ax = (hall_x0+hall_x1)/2; ay = (ay0+ay1)/2
    K.box('aisle_footing', ax, ay, .08, aw+.06, ay1-ay0, .16, K.mat('f_base'))
    # Brick base course under the cladding, stacked in one plane like the hall's walls.
    K.box('aisle_base', ax, ay, (.16+.58)/2, aw, ay1-ay0, .58-.16, K.mat('f_brick'))
    K.box('aisle_body', ax, ay, (.58+AISLE_TOP-.08)/2, aw, ay1-ay0, AISLE_TOP-.08-.58, K.mat('f2_refractory'))
    K.box('aisle_roof', ax, ay, AISLE_TOP-.04, aw+.08, ay1-ay0, .08, K.mat('membrane'))
    # Wing: brick on a footing, stone cornice, flat roof.
    wx0, wx1 = WING_X0, wing_x1
    wx = (wx0+wx1)/2; wy = (WING_Y0+WING_Y1)/2; ww = wx1-wx0; wd = WING_Y1-WING_Y0
    K.box('wing_footing', wx, wy, .08, ww+.08, wd+.08, .16, K.mat('f_base'))
    K.box('wing_body', wx, wy, (.16+WING_TOP)/2, ww, wd, WING_TOP-.16, K.mat('f_brick'))
    # The cornice stops at the tower's back wall where the wing runs into it.
    tower_x1, tower_back = -1.35, 1.55
    K.box('wing_cornice_tower', (wx0-.05+tower_x1)/2, (tower_back+.01+WING_Y1+.05)/2, WING_TOP+.035,
          tower_x1-(wx0-.05), WING_Y1+.05-(tower_back+.01), .07, K.mat('stone'))
    K.box('wing_cornice', (tower_x1+wx1+.05)/2, wy, WING_TOP+.035, wx1+.05-tower_x1, wd+.10, .07, K.mat('stone'))
    K.box('wing_roof', (tower_x1+wx1)/2, wy, WING_TOP+.095, wx1-tower_x1-.04, wd-.04, .05, K.mat('membrane'))
    K.box('wing_roof_tower', (wx0+tower_x1)/2+.02, (tower_back+WING_Y1)/2, WING_TOP+.095,
          tower_x1-wx0-.04, WING_Y1-tower_back-.04, .05, K.mat('membrane'))
    # Flashing where the wing roof meets the tower's back wall.
    K.box('wing_flashing', (wx0+tower_x1)/2, tower_back+.03, WING_TOP+.15, tower_x1-wx0, .05, .08, K.mat('f_frame'))
    roof = WING_TOP+.12
    # Regenerator dome over the chambers nearest the tower.
    K.cyl('wing_crown', -.40, wy, roof+.07, .40, .14, K.mat('f_zinc'))
    K.dome_cap('wing_dome', -.40, wy, roof+.14, .40, .20, K.mat('f_zinc'), rings=6)
    K._fine_mode = True
    # Louvred vents along the back face, which the rear view shows.
    for i, vx in enumerate([v for v in (-.90, .10, 1.10, 2.10, 3.00) if wx0+.30 < v < wx1-.30]):
        K.box(f'wing_vent{i}', vx, WING_Y1+.015, 1.20, .42, .03, .30, K.mat('f_frame'))
        for j in range(4):
            K.box(f'wing_vent{i}_louvre', vx, WING_Y1+.03, 1.10+j*.07, .38, .03, .02, K.mat('f_roof'))
    K._fine_mode = False
    # Brick pilasters along the back, a scupper and downpipe between some of them, a
    # personnel door near the tower and a factory window on the wing's end wall.
    bays = [v for v in (-1.40, -.40, .60, 1.60, 2.60) if wx0+.40 < v < wx1-.40]
    for i, px in enumerate(bays):
        K.box(f'wing_pilaster{i}', px, WING_Y1+.025, (.16+WING_TOP)/2, .14, .05, WING_TOP-.16, K.mat('f_brick'))
    for i, px in enumerate(bays[1::2]):
        _v2_downpipe(K, f'wing_dp{i}', px+.16, WING_Y1+.10, WING_TOP, 0.0)
    K.box('wing_gutter', (wx0+wx1)/2, WING_Y1+.10, WING_TOP+.02, wx1-wx0, .08, .07, K.mat('silver'))
    K.door('wing_rear_door', '+Y', (-1.90, WING_Y1+.02, .55), .50, .90)
    K.box('wing_rear_step', -1.90, WING_Y1+.14, .04, .66, .20, .08, K.mat(STONE))
    K._fine_mode = True
    _v2_window(K, 'wing_end_window', '-X', (wx0-.055, (tower_back+WING_Y1)/2, 1.15), .40, .50, cols=2, rows=2)
    K._fine_mode = False
    # Each downcomer lands on the wing roof through a collar.
    for i, (fx, fy) in enumerate(feet):
        K.washer(f'wing_collar{i}', (fx, fy, roof+.03), (0, 0, 1), .14, .24, .06, K.mat('f_frame'))
    # Waste gas leaves the far end by the low flue into the chimney base.
    K.washer('wing_flue_collar', (wx1+.02, WING_Y0+wd/2, FLUE_Z), (1, 0, 0), .12, .20, .05, K.mat('f_frame'))
    _v2_low_flue(K, 'flue', (wx1-.02, WING_Y0+wd/2, FLUE_Z))


FLUE_Z = .45       # low flues run at this height behind the hall
L1_DUCT_Y = 1.50   # L1's downcomer drops to the ground on this line
DUCT_Y = (WING_Y0+WING_Y1)/2   # L2/L3 downcomers land on the wing roof on this line


def _v2_downcomer(K, name, pts, brackets=()):
    """Top-gas take-off: a pipe from the top of the vessel that runs back and drops
    straight down, to the ground at L1 and on to the regenerator wing at L2/L3.
    `brackets` are (shell point, z) pairs tying the drop to the shell."""
    K.pipe_run(name, pts, .15, mat=K.mat('white_pipe'), bend=.26)
    drop = pts[-1]
    K._fine_mode = True
    for i, (shell, z) in enumerate(brackets):
        K.dirbox(name+'_bracket'+str(i), (shell[0], shell[1], z), (drop[0], drop[1], z), .07, .07, K.mat('f_frame'))
    K._fine_mode = False


def _v2_low_flue(K, name, start, via_x=None):
    """Ground-level flue from `start` round the back to the chimney base."""
    sx, sy = STACK_XY
    pts = [start]
    if via_x is not None and abs(start[0]-via_x) > .01:
        pts.append((via_x, start[1], FLUE_Z))
    pts += [(sx, start[1], FLUE_Z), (sx, sy+.31, FLUE_Z)]
    K.pipe_run(name, pts, .13, mat=K.mat('white_pipe'), bend=.20)


def _v2_chimney(K):
    """The one thin black-topped brick chimney, in the same place at every level."""
    sx, sy = STACK_XY
    # Chimney: square brick base, slim tapered brick barrel, dark cap, black top.
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


def _v2_rail(K, name, a, b, h=.23, gate=False):
    """The furnace family's guard rail in dark steel instead of ochre."""
    a, b = Vector(a), Vector(b)
    count = max(1, math.ceil((b-a).length/.55))
    gap = gate if isinstance(gate, tuple) else (.35, .65)
    for i in range(count+1):
        if gate and gap[0] < i/count < gap[1]: continue
        p = a.lerp(b, i/count)
        K.dircyl(name+'_post'+str(i), p, p+Vector((0, 0, h)), .014, K.mat('f_frame'), segments=8)
    for z in (h*.47, h):
        if gate:
            for lo, hi in ((0, gap[0]), (gap[1], 1)):
                K.dircyl(name+'_gate', a.lerp(b, lo)+Vector((0, 0, z)), a.lerp(b, hi)+Vector((0, 0, z)), .013, K.mat('f_frame'), segments=8)
        else:
            K.dircyl(name+'_rail', a+Vector((0, 0, z)), b+Vector((0, 0, z)), .013, K.mat('f_frame'), segments=8)


def _v2_crown(K, name, x, y, top, w=1.24, d=1.16, gates=(), ridge='x'):
    """The one furnace crown for every level: a railed zinc deck on the vessel top and
    a small gabled charging house on it, enclosing the charging lock whose centre is the
    lift top (BRIDGE_Z). The conveyor arrives through a gable wall, so `ridge` runs along
    the conveyor. `gates` names the rail sides a conveyor or ladder passes through:
    'front', 'rear', 'left', 'right'."""
    dz = top+.25
    assert abs(dz+.22-BRIDGE_Z) < 1e-6, 'crown lock must sit at the lift top'
    K.box(name+'_deck', x, y, dz-.04, w, d, .08, K.mat('f_zinc'))
    K._fine_mode = True
    g = {'front': (.33, .67), 'rear': (.28, .72), 'left': (.28, .72), 'right': (.28, .72)}
    _v2_rail(K, name+'_front', (x-w/2, y-d/2, dz), (x+w/2, y-d/2, dz), gate=g['front'] if 'front' in gates else False)
    _v2_rail(K, name+'_rear', (x-w/2, y+d/2, dz), (x+w/2, y+d/2, dz), gate=g['rear'] if 'rear' in gates else False)
    _v2_rail(K, name+'_left', (x-w/2, y-d/2, dz), (x-w/2, y+d/2, dz), gate=g['left'] if 'left' in gates else False)
    _v2_rail(K, name+'_right', (x+w/2, y-d/2, dz), (x+w/2, y+d/2, dz), gate=g['right'] if 'right' in gates else False)
    K._fine_mode = False
    # Dark iron walls under a zinc roof, as the bare charging lock and its cap were.
    _v2_gable_house(K, name+'_house', x, y, dz, .62, .70, ridge, wall='f_frame', roof='f_zinc')


def _v2_old_stockhouse_dressing(K, x, y, w, d, h):
    """L1's stockhouse: a factory window on the front and on the rear
    gable side, a rear door, eaves gutters and downpipes."""
    K._fine_mode = True
    _v2_window(K, 'stockhouse_window_front', '-Y', (x+.25, y-d/2-.055, 1.05), .50, .45, cols=2, rows=2)
    _v2_window(K, 'stockhouse_window_rear', '-X', (x-w/2-.055, y+.20, 1.05), .50, .45, cols=2, rows=2)
    _v2_window(K, 'stockhouse_window_back', '+Y', (x+.10, y+d/2+.055, 1.05), .50, .45, cols=2, rows=2)
    K._fine_mode = False
    K.door('stockhouse_door', '-Y', (x-.32, y-d/2-.06, .55), .46, .88)
    K.door('stockhouse_rear_door', '-X', (x-w/2-.02, y-.32, .55), .46, .88)
    _v2_eave_gutters(K, 'stockhouse', x, y, w, d, h)
    for s_ in (-1, 1):
        _v2_downpipe(K, 'stockhouse_dp'+str(s_), x-w/2+.12, y+s_*(d/2+.12), h+.05, 0.0)


def _v2_old_furnace(K, x=.30):
    """L1: a simplified version of the old blast furnace. The tapered dark-metal vessel
    on four raking columns with a crown deck and charging lock, a supported incline
    from a low stockhouse standing where L2's tower will stand, a one-bay cast hall in
    the family's refractory cladding, and the same chimney as L2/L3. No stoves, no
    galleries."""
    top = 3.35
    profile = [(.18, .46), (.62, .46), (1.05, .68), (1.45, .68), (3.05, .33), (top, .30)]
    vertices = []; faces = []; seg = 32
    for z, r in profile:
        vertices.extend((x+r*math.cos(i*2*math.pi/seg), r*math.sin(i*2*math.pi/seg), z) for i in range(seg))
    for j in range(len(profile)-1):
        for i in range(seg):
            k = (i+1) % seg
            faces.append((j*seg+i, j*seg+k, (j+1)*seg+k, (j+1)*seg+i))
    faces.extend((tuple(reversed(range(seg))), tuple((len(profile)-1)*seg+i for i in range(seg))))
    mesh = bpy.data.meshes.new('old_vessel'); mesh.from_pydata(vertices, [], faces); mesh.update()
    K.obj('old_vessel', mesh, K.mat('f_shell'), smooth=True)
    K.cyl('old_vessel_foundation', x, 0, .10, .52, .20, K.mat('f_base'))
    K._fine_mode = True
    for z, r in (profile[1], (1.25, .68), profile[3], (2.25, .505), (3.05, .33)):
        K.washer('old_vessel_hoop', (x, 0, z), (0, 0, 1), r-.006, r+.035, .06, K.mat('f_zinc'))
    K._fine_mode = False
    # Four raking columns on their own footings, carrying the crown deck.
    for sx in (-1, 1):
        for sy in (-1, 1):
            foot = (x+sx*.90, sy*.80, .24); head = (x+sx*.50, sy*.48, top+.20)
            K.box('old_foot', foot[0], foot[1], .12, .36, .36, .24, K.mat('f_base'))
            K.dirbox('old_column', foot, head, .105, .13, K.mat('f_frame'))
    for z0, z1, w0, w1, y0, y1 in ((.35, 1.70, .88, .72, .79, .67), (1.70, top+.15, .72, .50, .67, .48)):
        K.dirbox('old_brace', (x-w0, y0, z0), (x+w1, y1, z1), .055, .065, K.mat('f_frame'))
    dz = top+.25
    _v2_crown(K, 'old_crown', x, 0, top, gates=('rear', 'right'), ridge='y')
    K.ladder('old_ladder', x+.70, 0, .20, dz, face='+X', w=.22, mat=K.mat('f_frame'), rung=.24)
    # Charging route, square to the buildings: an incline leaves the stockhouse through
    # its +X gable, runs straight along X behind the vessel and enters a head house's
    # -X gable; a short covered stub at the lift top runs from the head house into the
    # charging house's +Y gable over the deck. The stockhouse stands where L2's tower
    # stands; it is taller than before so the incline clears its roof.
    sy, sh = 1.15, 1.75
    _f_shed(K, 'stockhouse', -2.00, .90, 1.30, 1.30, sh, door=False)
    _v2_old_stockhouse_dressing(K, -2.00, .90, 1.30, 1.30, sh)
    hx, hy, hz0 = x, sy, 2.55
    _v2_gable_house(K, 'charge_head', hx, hy, hz0, .56, .56, 'x')
    for s_ in (-1, 1):
        K.box('charge_head_foot', hx+s_*.20, hy, .08, .24, .24, .16, K.mat('f_base'))
        K.dirbox('charge_head_leg', (hx+s_*.20, hy, .16), (hx+s_*.20, hy, hz0), .07, .07, K.mat('f_frame'))
    K._fine_mode = True
    K.dirbox('charge_head_brace', (hx-.20, hy, .40), (hx+.20, hy, hz0-.20), .045, .05, K.mat('f_frame'))
    for z in (1.10, 2.10):
        K.dirbox('charge_head_tie', (hx-.20, hy, z), (hx+.20, hy, z), .045, .05, K.mat('f_frame'))
    K._fine_mode = False
    stub0, stub1 = (x, hy-.26, BRIDGE_Z), (x, .29, BRIDGE_Z)
    K.dirbox('charge_stub', stub0, stub1, .36, .30, K.mat('f_zinc'))
    # The cover runs between the two flanges' outer faces, clear of both plates.
    _v2_gallery_cover(K, 'charge_stub_cover', (x, hy-.325, 0), (x, .355, 0))
    _v2_flange(K, 'charge_stub_flange_head', x, hy-.30, BRIDGE_Z, 'y')
    _v2_flange(K, 'charge_stub_flange_house', x, .33, BRIDGE_Z, 'y')
    # The gallery leaves a small gabled tail house standing on the stockhouse roof, so
    # from every side it comes out of a wall, never out of a roof slope. It is one bent
    # mesh: level out of the tail house's +X gable, a mitred knuckle on a trestle, the
    # climb, a second knuckle, level into the head house's -X gable. Both walls are met
    # square-on; the bends ink as fold lines.
    z0, z1 = 2.30, 2.95
    tail_x1 = -1.33
    _v2_gable_house(K, 'charge_tail', tail_x1-.26, sy, 1.70, .52, .56, 'x', eave=2.60)
    k0, k1 = -1.12, hx-.40
    path = [(-1.70, z0), (k0, z0), (k1, z1), (hx-.10, z1)]
    _v2_bent_gallery(K, 'charge_conveyor', path, sy, .19, .15, 'f_zinc')
    _v2_flange(K, 'charge_conveyor_flange_stock', tail_x1+.02, sy, z0, 'x')
    _v2_flange(K, 'charge_conveyor_flange_head', hx-.28-.02, sy, z1, 'x')
    K._fine_mode = True
    # A trestle under the lower knuckle; the head house carries the upper one.
    for s_ in (-1, 1):
        K.box('charge_foot', k0, sy+s_*.27, .08, .25, .25, .16, K.mat('f_base'))
        K.dirbox('charge_leg', (k0, sy+s_*.27, .16), (k0, sy+s_*.27, z0-.17), .065, .07, K.mat('f_frame'))
    K.dirbox('charge_bearing', (k0, sy-.28, z0-.17), (k0, sy+.28, z0-.17), .08, .09, K.mat('f_frame'))
    K.dirbox('charge_brace', (k0, sy-.27, .20), (k0, sy+.27, z0-.20), .045, .05, K.mat('f_frame'))
    # Seams across the top of the climb.
    dx, dz = k1-k0, z1-z0; ln = math.hypot(dx, dz); nx, nz = -dz/ln, dx/ln
    for j in range(1, 5):
        cx, cz = k0+dx*j/5+nx*.165, z0+dz*j/5+nz*.165
        K.dirbox('charge_seam', (cx, sy-.20, cz), (cx, sy+.20, cz), .015, .015, K.mat('f_frame'))
    K._fine_mode = False
    # One-bay cast hall on the hearth in the family cladding, tap runner inside,
    # ladle on bogies outside.
    _v2_hall(K, 'casthouse', x, -1.26, 2.20, 1.30, 1.10, bays=(x,))
    K.box('old_tap_runner', x, -.64, .38, .17, .62, .12, K.mat('f_oxide'))
    _v2_ladles(K, 'ladle', x-.05, -1.26-.65-.72)
    # Top gas: downcomer past the right-hand columns to the ground, low flue round the
    # back into the chimney base.
    zt = top-.08; px = x+1.15
    _v2_downcomer(K, 'downcomer', [(x+.10, .27, zt), (px, .27, zt), (px, L1_DUCT_Y, zt), (px, L1_DUCT_Y, FLUE_Z)])
    K.box('downcomer_pad', px, L1_DUCT_Y, .08, .40, .40, .16, K.mat('f_base'))
    _v2_low_flue(K, 'flue', (px, L1_DUCT_Y, FLUE_Z))
    _v2_chimney(K)


def _v2_ladles(K, n, x, y):
    for s in (-1, 1):
        K.box(n+'_rail'+str(s), x+s*.22, y, .08, .035, 1.35, .045, K.mat('f_frame'))
    for j in range(5):
        K.box(n+'_sleeper'+str(j), x, y-.52+j*.26, .035, .65, .075, .055, K.mat('f_base'))
    K.box(n+'_wagon', x, y, .25, .48, .63, .10, K.mat('f_frame'))
    for sx in (-1, 1):
        for sy in (-1, 1):
            K.cyl(n+'_wheel', x+sx*.245, y+sy*.23, .16, .11, .055, K.mat('f_frame'), axis='X', segments=16)
    K.cone(n, x, y, .46, .18, .24, .33, K.mat('f_zinc'))
    K.cyl(n+'_refractory', x, y, .631, .20, .015, K.mat('f_oxide'))
    K.cyl(n+'_inside', x, y, .655, .16, .012, K.mat('ink_black'))


def build_furnace_v2(level=1):
    assert level in (1, 2, 3)
    setup_rig(ortho_scale=11.6, target=(0, 0, 1))
    fs = bpy.context.scene.view_layers[0].freestyle_settings
    fs.linesets['ink'].linestyle.thickness = 1.45
    fs.linesets['ink_fine'].linestyle.thickness = .80
    K = Kit(open_collection('BLDG_furnace_v2'))
    _v2_brick_print(K)
    for ls in fs.linesets:
        ls.select_by_face_marks = True; ls.face_mark_negation = 'EXCLUSIVE'; ls.face_mark_condition = 'ONE'
    if level == 1:
        _v2_old_furnace(K)
        return _v2_finish(K, level, shafts=1)
    hall_y = -.25; hall_d = 2.30
    shaft_y = .66   # back half of the hall, clear of the monitor roof
    # The chimney keeps its fixed place; the regenerator wing runs behind the hall from
    # the tower. L3 lengthens the hall to the second shaft.
    if level == 3:
        shafts = (.30, 2.10); hall_x0, hall_x1 = -.90, 3.10; bays = (.30, 1.40, 2.50)
        silos = ((-2.00, -.55), (-2.00, -1.40))
    else:
        shafts = (.30,); hall_x0, hall_x1 = -.90, 1.70; bays = (.30, 1.20)
        silos = ((-2.00, -.55),)
    hall_w = hall_x1-hall_x0; hall_x = (hall_x0+hall_x1)/2
    _v2_hall(K, 'hall', hall_x, hall_y, hall_w, hall_d, HALL_H, bays)
    rise = .26
    roof_z_at_shaft = HALL_H+.10+rise*(1-abs(shaft_y-hall_y)/(hall_d/2))+.06
    for i, sx in enumerate(shafts):
        # The bridge enters every crown from the left and leaves the first one on the
        # right when a second shaft follows.
        _v2_shaft(K, f'shaft{i}', sx, shaft_y, roof_z_at_shaft)
    _v2_tower(K, -2.00, .90, silos, elevator_x=-1.15, elevator_y=shaft_y)
    # Level charging bridge from the elevator head into the first lock, and on to the
    # second at L3. Each span ends at a lock face on a flange; none runs through a lock.
    # Each span leaves a gable and enters a gable: the elevator head house on the tower,
    # then each charging house. A shallow ridged cover runs between the gables.
    head_x1 = -1.35+.005+.62
    spans = [(head_x1-.02, shafts[0]-.29)] + [(a+.29, b-.29) for a, b in zip(shafts, shafts[1:])]
    for j, (x0, x1) in enumerate(spans):
        K.conveyor_bridge(f'charge_bridge{j}', (x0, shaft_y, BRIDGE_Z), (x1, shaft_y, BRIDGE_Z), w=.36, h=.34, ribs=max(2, round((x1-x0)/.30)))
        # The cover stops just short of each flange, so its ends never share the flange's plane.
        _v2_gallery_cover(K, f'charge_bridge{j}_cover', (x0+.065, shaft_y, 0), (x1-.065, shaft_y, 0))
        _v2_flange(K, f'charge_bridge{j}_flange0', x0+.04, shaft_y, BRIDGE_Z, 'x')
        _v2_flange(K, f'charge_bridge{j}_flange1', x1-.04, shaft_y, BRIDGE_Z, 'x')
    # Downcomers: each leaves its shell just under the crown through a flange, runs
    # back over the aisle and drops on to the regenerator wing's roof.
    zt = SHAFT_TOP-.33; feet = []
    for i, sx in enumerate(shafts):
        px, py = sx+.75, DUCT_Y
        a = math.atan2(py-shaft_y, px-sx); ca, sa = math.cos(a), math.sin(a)
        shell = (sx+SHAFT_R*ca, shaft_y+SHAFT_R*sa)
        _v2_downcomer(K, f'downcomer{i}', [(sx+(SHAFT_R-.05)*ca, shaft_y+(SHAFT_R-.05)*sa, zt), (px, py, zt), (px, py, WING_TOP+.08)],
                      brackets=[(shell, (zt+WING_TOP)/2+.15)])
        K.washer(f'downcomer{i}_flange', (shell[0], shell[1], zt), (ca, sa, 0), .14, .21, .05, K.mat('f_frame'))
        feet.append((px, py))
    wing_x1 = max(hall_x1+.12, feet[-1][0]+.40)
    _v2_back_range(K, hall_x0, hall_x1, hall_y+hall_d/2, wing_x1, feet)
    _v2_chimney(K)
    _v2_ladles(K, 'ladle', bays[-1]-.05, hall_y-hall_d/2-.72)
    if level == 3:
        _v2_ladles(K, 'ladle_b', bays[0]-.05, hall_y-hall_d/2-.72)
    return _v2_finish(K, level, shafts=len(shafts))


def _v2_finish(K, level, shafts):
    # Zinc keeps its printed reflection band; no polished steel in this family.
    for ob in K.col.objects:
        if ob.type == 'MESH' and len(ob.data.materials) == 1 and ob.data.materials[0] == K.mat('f_zinc'):
            K.gloss(ob, dark=.24, light=1.45, dark_from=.35, glint=(-.88, -.60))
    bpy.context.view_layer.update()
    pts = [o.matrix_world @ v.co for o in K.col.objects if o.type == 'MESH' for v in o.data.vertices]
    u = [(v.x+v.y)/math.sqrt(2) for v in pts]; z = [(2*v.z-v.x+v.y)/math.sqrt(6) for v in pts]
    uc, zc = (min(u)+max(u))/2, (min(z)+max(z))/2
    target = Vector((uc/math.sqrt(2), uc/math.sqrt(2), zc*math.sqrt(6)/2))
    bpy.context.scene.camera.location = target+Vector((1, -1, 1)).normalized()*26
    warnings = [w for w in K.validate(ground=-.01) if not w.startswith('bbox world')]
    assert not warnings, warnings
    return dict(level=level, objects=len(K.col.objects), furnace_shafts=shafts,
                style='V2: L1 simplified old blast furnace; L2/L3 shaft-furnace works with monitor hall, back aisle, L-shaped tower and regenerator range, downcomers and chimney', warnings=warnings)
