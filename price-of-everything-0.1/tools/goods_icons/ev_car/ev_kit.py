"""EV car (g_057 ev_car) study: the owner's downloaded SUV, a rough approximation to be brought to the shipped art
(owner: "the downloaded file was only intended as a rough approximation, we still need it modified so it looks more
like the old model. for example the detail inside the car, the wheels and the front"). ev_prep.py makes
ev_prepped.blend: the grille covered flat in the body colour, the brand mark gone, a solid roof, open windows onto the
cabin, five-spoke wheels, tan cladding round the arches and sills and on the bumpers. This builder puts it through the
set's toon, ink and stipple in the shipped art's colours."""
EV_BLEND = 'ev_prepped.blend'
EV_SOURCES = ('Plane.002', 'ev_roof', 'ev_grille_cover', 'ev_wheel_r_f', 'ev_wheel_r_b', 'ev_wheel_l_f', 'ev_wheel_l_b', 'ev_lamp_l', 'ev_lamp_r', 'ev_nose_l', 'ev_nose_r')
EV_PARTS = {  # source material -> (part, label); the exporter draws a line wherever two labels meet on screen
    'ana renk': ('body', 1), 'lastil': ('black', 3), 'wheel_inner': ('black', 3), 'tyre': ('tyre', 3),
    'metal': ('trim', 4), 'cladding': ('cladding', 4), 'rim': ('rim', 4),
    'on emis': ('lamp_front', 5), 'arka emis': ('lamp_rear', 5),
    'Material.001': ('cabin', 6), 'Material.005': ('cabin', 6), 'Material.006': ('cabin', 6), 'Material.004': ('cabin', 6)}   # v4: one interior colour
EV_TONES = {  # (shade, mid, lit), read off the shipped art
    'body': ((64, 82, 108), (82, 102, 128), (120, 137, 153)), 'black': ((58, 58, 62), (58, 58, 62), (58, 58, 62)),
    'tyre': ((66, 66, 64), (85, 85, 81), (98, 98, 94)), 'trim': ((160, 156, 144), (190, 186, 172), (206, 202, 190)),
    'cladding': ((132, 130, 118), (159, 157, 144), (176, 174, 160)), 'rim': ((126, 125, 116), (158, 157, 147), (178, 177, 168)),
    'lamp_front': ((190, 192, 184), (214, 214, 204), (232, 232, 224)), 'lamp_rear': ((150, 50, 48), (186, 64, 60), (210, 90, 84)),
    'cabin': ((68, 66, 72), (68, 66, 72), (68, 66, 72))}   # v4: flat, no tone steps
EV_CREASE, EV_MIN_LINE = 55.0, 0.14


def ev_split(K, ob, mats, M, tag, sharp=45.0):
    """One object per part of a source (the exporter draws a boundary wherever part labels meet), smooth with hard
    edges; M: the source's world matrix, moved to the icon's origin"""
    names = [m.name if m else None for m in ob.data.materials]; out = []
    for part in sorted({p for p, _ in EV_PARTS.values()}):
        keep = {i for i, n in enumerate(names) if EV_PARTS.get(n, ('cabin', 6))[0] == part}
        if not keep:
            continue
        bm = bmesh.new(); bm.from_mesh(ob.data); bm.transform(M)
        bmesh.ops.delete(bm, geom=[f for f in bm.faces if f.material_index not in keep], context='FACES')
        bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context='VERTS')
        if not bm.faces:
            bm.free(); continue
        for e in bm.edges:
            e.smooth = not (len(e.link_faces) == 2 and math.degrees(e.calc_face_angle()) > sharp)
        for f in bm.faces:
            f.smooth = True; f.material_index = 0
        nm = 'ev_%s' % part if tag == 'car' else 'ev_%s_%s' % (part, tag)
        me = bpy.data.meshes.new(nm); bm.to_mesh(me); bm.free()
        o = K.obj(nm, me, mats[part], False); noink(o)
        for p in o.data.polygons:
            p.use_smooth = True
        o['part_label'] = [l for p_, l in EV_PARTS.values() if p_ == part][0]; out.append(o)
    return out


def build_ev_car():
    setup_icon_rig(); K = Kit(open_collection('ICON_ev_car'))
    mats = {k: pl_toon('ev_' + k, *v) for k, v in EV_TONES.items()}
    with bpy.data.libraries.load(str(here / EV_BLEND), link=False) as (src, dst):
        dst.objects = [n for n in src.objects if n in EV_SOURCES]
    srcs = [o for o in dst.objects if o is not None]
    for o in srcs:                                   # linked, so their world matrices are evaluated
        K.col.objects.link(o)
    bpy.context.view_layer.update()
    car = next(o for o in srcs if o.name.startswith('Plane.002'))
    # the car's ground and centre to the origin (its wheels' bottoms on z = 0)
    mw = car.matrix_world; P = [mw @ v.co for v in car.data.vertices]
    wz = min(min((o.matrix_world @ v.co).z for v in o.data.vertices) for o in srcs if o.name.startswith('ev_wheel'))
    off = Vector((-(min(p.x for p in P) + max(p.x for p in P)) / 2, -(min(p.y for p in P) + max(p.y for p in P)) / 2, -wz))
    for o in srcs:
        tag = 'car' if o is car else o.name.replace('ev_', '')
        ev_split(K, o, mats, Matrix.Translation(off) @ o.matrix_world, tag)
        bpy.data.objects.remove(o, do_unlink=True)
    bpy.context.view_layer.update()
    nlines = pl_mesh_lines(K, bpy.data.objects['ev_body'], 1, EV_CREASE, 'ev_body', EV_MIN_LINE)
    # v4: the interior in one colour, undotted, with thin (2 px) lines at its main creases only
    cab = bpy.data.objects['ev_cabin']; at = cab.data.attributes.new('icon_stipple_clear', 'FLOAT', 'CORNER')
    for d_ in at.data:
        d_.value = 1.0
    pl_mesh_lines(K, cab, 6, 75.0, 'ev_cabin', 0.15)
    for o in K.col.objects:
        if o.name.startswith('ev_cabin_line'):
            o['ink_width'] = 2; o['ink_tip'] = 1; o['ink_centre'] = 1
    charger(K)
    info = contract(K, [], 'blue electric SUV (the downloaded model brought to the shipped art: covered front, solid roof, '
                    'open windows onto the cabin, five-spoke wheels, tan cladding)', inner=PL_INNER)
    info['structural_hosts'] = [o.name for o in K.col.objects if o.name.startswith('ev_tyre')][:1]
    info['revision'] = 'ev_car_study_v4'; info['outline']['component_boundaries'] = True; info['stipple']['strength'] = 0.38
    info['stipple']['groups'] = [{'name': 'shaded_faces', 'labels': [1, 2, 3, 4, 5, 6, 7], 'thresholds': [0.575, 0.50, 0.30]}]
    info['dimensions'] = {'body_lines': nlines, 'offset': list(off)}
    return info


# v5 (owner: "add the charger next"): the shipped art's charging post, standing beside the car's front door: a green post
# with a rounded top, a dark screen and a bright bolt on its front (+X) face, a holster on its side, on a pale plinth; a
# pale green cable from the holster down to the ground and up to a plug on the front wing
# placed as shipped: out in front of the car's side (a world move of (+d, -d) keeps its place along the car on screen
# and brings it toward the viewer), about 0.9 of the car's height on screen
POST = dict(x=1.84, y=-0.66, w=0.78, d=0.30, h=1.70, r=0.09)   # v6: up past the mirrors, as shipped   # the shipped post's broad front face


def ev_box(K, name, x0, x1, y0, y1, z0, z1, mat, label, bevel=0.0, top_only=True):
    bm = bmesh.new(); bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co = Vector((x0 if v.co.x < 0 else x1, y0 if v.co.y < 0 else y1, z0 if v.co.z < 0 else z1))
    if bevel:
        es = [e for e in bm.edges if all(v.co.z > z1 - 1e-6 for v in e.verts)] if top_only else bm.edges[:]
        bmesh.ops.bevel(bm, geom=es, offset=bevel, segments=4, affect='EDGES', profile=0.5)
    me = bpy.data.meshes.new(name); bm.to_mesh(me); bm.free()
    o = K.obj(name, me, mat, False); noink(o); o['part_label'] = label
    return o


def charger(K):
    P = POST; x0, x1 = P['x'] - P['d'] / 2, P['x'] + P['d'] / 2; y0, y1 = P['y'] - P['w'] / 2, P['y'] + P['w'] / 2
    green = pl_toon('ev_post', (100, 126, 87), (130, 159, 118), (142, 169, 123))
    plinth_m = pl_toon('ev_plinth', (112, 138, 118), (139, 167, 147), (156, 182, 160))
    screen_m = pl_toon('ev_screen', (84, 108, 72), (92, 118, 80), (100, 126, 87))
    bolt_m = pl_toon('ev_bolt', (63, 176, 89), (63, 176, 89), (78, 196, 104))
    holster_m = pl_toon('ev_holster', (100, 93, 84), (121, 112, 101), (136, 127, 116))
    cable_m = pl_toon('ev_cable', (118, 150, 104), (150, 185, 130), (168, 200, 148))
    plinth = ev_box(K, 'ev_plinth', x0 - 0.08, x1 + 0.08, y0 - 0.08, y1 + 0.08, 0.0, 0.07, plinth_m, 7, 0.012, False)
    post = ev_box(K, 'ev_post', x0, x1, y0, y1, 0.07, P['h'], green, 2, P['r'])
    bpy.context.view_layer.update()
    pl_mesh_lines(K, post, 2, 40.0, 'ev_post', 0.05); pl_mesh_lines(K, plinth, 7, 40.0, 'ev_plinth', 0.05)
    xf = x1 + 0.003                                     # the front face's plate: the screen and the bolt
    def plate(name, pts, mat, lift):
        me = bpy.data.meshes.new(name); me.from_pydata([(xf + lift, y, z) for y, z in pts], [], [tuple(range(len(pts)))]); me.update()
        o = K.obj(name, me, mat, False); noink(o); o['part_label'] = 2
        at = o.data.attributes.new('icon_stipple_clear', 'FLOAT', 'CORNER')
        for d_ in at.data:
            d_.value = 1.0
        tagged_line(K, name + '_rim', [(xf + lift + E, y, z) for y, z in pts], 2, 0, True)
        return o
    sw, sz0, sz1 = P['w'] * 0.66, P['h'] * 0.62, P['h'] * 0.88
    plate('ev_screen', [(P['y'] - sw / 2, sz0), (P['y'] + sw / 2, sz0), (P['y'] + sw / 2, sz1), (P['y'] - sw / 2, sz1)], screen_m, 0.0)
    bh, bw, bz = 0.50, 0.36, P['h'] * 0.16               # the bolt: a zigzag, top right to bottom left
    shape = [(0.0, 1.0), (0.40, 1.0), (0.13, 0.60), (0.35, 0.60), (-0.35, 0.0), (-0.13, 0.46), (-0.35, 0.46)]   # a fat bolt,
    # its tip bottom left, as shipped
    plate('ev_bolt', [(P['y'] + bw * a, bz + bh * b) for a, b in shape], bolt_m, 0.0)
    # v6 (owner: "the pistol isnt right ... the car charging port isnt clear"), as shipped: the holster a tall rounded
    # panel on the post's side toward the car's front (-Y); on the car a raised dark port housing on the wing above the
    # front arch, the pistol a flat green handle out of it, slanting down and out; the cable from the handle's foot
    # straight down, along the ground and up into the holster's foot in a U
    port_m = pl_toon('ev_port', (58, 66, 80), (70, 80, 96), (84, 94, 110))
    hz0, hz1 = P['h'] * 0.36, P['h'] * 0.60
    ev_box(K, 'ev_holster', P['x'] - P['d'] * 0.32, P['x'] + P['d'] * 0.32, y0 - 0.012, y0 + 0.002, hz0, hz1, holster_m, 4, 0.006, False)
    bpy.context.view_layer.update()
    body = bpy.data.objects['ev_body']; mw = body.matrix_world
    from mathutils.bvhtree import BVHTree
    tree = BVHTree.FromPolygons([mw @ v.co for v in body.data.vertices], [tuple(p.vertices) for p in body.data.polygons])
    py, pz = -0.98, 0.80                                 # above the front arch's rear top
    hit = tree.ray_cast(Vector((3.0, py, pz)), Vector((-1, 0, 0)), 5.0)
    px = hit[0].x if hit[0] is not None else 0.95
    ev_box(K, 'ev_port', px - 0.04, px + 0.075, py - 0.15, py + 0.15, pz - 0.11, pz + 0.11, port_m, 4, 0.02, False)
    a0 = Vector((px + 0.07, py + 0.03, pz - 0.01))       # the pistol: a flat bar, broad face to the viewer, twice the cable
    pistol_path = [a0, a0 + Vector((0.09, 0.03, -0.06)), a0 + Vector((0.17, 0.06, -0.20)), a0 + Vector((0.21, 0.07, -0.40))]
    pistol, _, _ = pl_sweep(K, 'ev_pistol', pl_catmull(pistol_path, 6), pl_rrect(0.15, 0.06, 0.015, 3), (1, 0, 0.6), cable_m, 7)
    foot = pistol_path[-1]
    ctrl = [foot, foot + Vector((0.01, 0.0, -0.12)), Vector((foot.x + 0.03, foot.y - 0.02, 0.10)), Vector((foot.x + 0.12, foot.y - 0.10, 0.045)),
            Vector((P['x'] - 0.25, y0 - 0.26, 0.045)), Vector((P['x'] - 0.02, y0 - 0.20, 0.08)), Vector((P['x'], y0 - 0.10, 0.30)),
            Vector((P['x'], y0 - 0.03, hz0 + 0.06))]
    cable = K.sweep('ev_cable', pl_catmull(ctrl, 10), 0.030, cable_m, seg=12); noink(cable); cable['part_label'] = 3
    return post
