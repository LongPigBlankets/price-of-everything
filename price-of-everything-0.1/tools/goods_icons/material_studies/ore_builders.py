"""Distinct polyhedral fracture meshes for coal and iron; no limestone ring cages.
Owner correction: many facets, more polygons, approximately 30% visible grey on iron.
Reference photography informs fractures only; the goods icons govern colours and finish.
"""
def fractured_rock(K, name, centre, r, seed, squash=(1.0, 0.92, 0.80), mats=(None, None, None), cuts=2, noise_amp=0.11, subdiv=2, planes=8, rust_depth=(0.60, 0.74), crack_range=(2, 4), grey_depth=(0.74, 0.83), subsurf_levels=2, crease=0.7):
    """Cut a noisy polyhedron, add shallow secondary fracture relief, then bevel edges.
    Every relief face is explicitly planar. Material-tagged cleavage cuts set iron's
    grey coverage; multiple rust cuts and secondary ridges create the other facets.
    Seeded geometry is independent from the limestone cage. Legacy subsurf arguments
    are accepted for call compatibility, but no subdivision modifier is applied.
    """
    import bmesh, random
    from mathutils import noise, Vector, Matrix
    rng = random.Random(seed)
    sun = Vector(SUN_DIR).normalized()
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=subdiv, radius=r)   # level 2 = 320 facets, dissolved later
    off = Vector((rng.random() * 50, rng.random() * 50, rng.random() * 50))
    for v in bm.verts:
        n = noise.noise((v.co * (1.1 / r)) + off)          # -1..1, low frequency: big lumps only
        v.co = v.co * (1.0 + noise_amp * n)                # gentle: keep facets flat enough to dissolve
        v.co = Vector((v.co.x * squash[0], v.co.y * squash[1], v.co.z * squash[2]))
    # A broad lower body and narrow crown, established before planar cuts.
    zlo=min(v.co.z for v in bm.verts);zhi=max(v.co.z for v in bm.verts)
    for v in bm.verts:
        t=(v.co.z-zlo)/(zhi-zlo)
        taper=1.55-.95*t
        v.co.x*=taper;v.co.y*=taper
    cut_layer = bm.faces.layers.int.new("cut")
    grey_dirs = []
    for k in range(planes):
        d = Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-0.6, 0.65))).normalized()
        if k < cuts:
            bias = Vector((0.55, -0.85, 0.80)) if k == 0 else Vector((-0.6, -0.95, 0.45))
            d = (d * 0.4 + bias).normalized()
            grey_dirs.append(d)
        else:
            for _try in range(8):
                if all(d.dot(gd) < 0.5 for gd in grey_dirs):
                    break
                d = Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-0.6, 0.65))).normalized()
        ext = max(v.co.dot(d) for v in bm.verts)
        dist = ext * (rng.uniform(*grey_depth) if k < cuts else rng.uniform(*rust_depth))
        res = bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:],
                                     plane_co=d * dist, plane_no=d, clear_outer=True, clear_inner=False)
        edges = [g for g in res["geom_cut"] if isinstance(g, bmesh.types.BMEdge)]
        if edges:
            fill = bmesh.ops.holes_fill(bm, edges=edges, sides=0)
            for f in fill["faces"]:
                f[cut_layer] = 1 if k < cuts else 0
    for gd in grey_dirs:
        hi_dir = (gd * 0.45 + sun * 0.85).normalized()                 # toward the light: highlight
        dist2 = max(v.co.dot(hi_dir) for v in bm.verts) * rng.uniform(0.95, 0.98)
        res = bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:],
                                     plane_co=hi_dir * dist2, plane_no=hi_dir, clear_outer=True, clear_inner=False)
        edges = [g for g in res["geom_cut"] if isinstance(g, bmesh.types.BMEdge)]
        if edges:
            fill = bmesh.ops.holes_fill(bm, edges=edges, sides=0)
            for f in fill["faces"]:
                f[cut_layer] = 2
    # A real broad bottom plane, rather than a pointed balancing contact.
    zlo=min(v.co.z for v in bm.verts);zhi=max(v.co.z for v in bm.verts)
    floor=zlo+(zhi-zlo)*.15
    cut=bmesh.ops.bisect_plane(bm,geom=bm.verts[:]+bm.edges[:]+bm.faces[:],
        plane_co=(0,0,floor),plane_no=(0,0,-1),clear_outer=True)
    edges=[g for g in cut['geom_cut'] if isinstance(g,bmesh.types.BMEdge)]
    for f in bmesh.ops.holes_fill(bm,edges=edges,sides=0)['faces']:f[cut_layer]=0
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    for f in bm.faces:
        f.material_index = f[cut_layer]                                # 0 rust / 1 grey / 2 grey-hi
    cam = Vector((1, -1, 1)).normalized()
    crack_cand = []
    for e in bm.edges:
        if len(e.link_faces) != 2:
            continue
        f0, f1 = e.link_faces
        if (f0.material_index == f1.material_index
                and e.calc_face_angle(0.0) < math.radians(18)          # across a ~flat face
                and (f0.normal + f1.normal).normalized().dot(cam) > 0.26
                and e.calc_length() > r * 0.14):
            crack_cand.append(e)
    rng.shuffle(crack_cand)
    for e in crack_cand[:rng.randint(*crack_range)]:                    # few (owner: too many detached lines on hero)
        e.smooth = False                                               # sharp -> survives dissolve, inks as a crack
    bmesh.ops.dissolve_limit(bm, angle_limit=math.radians(9.0),
                             verts=bm.verts[:], edges=bm.edges[:], delimit={'MATERIAL', 'SHARP'})
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    for face in list(bm.faces):
        if face.normal.z < -.95 or face.calc_area()<r*r*.26 or len(face.verts)<3:
            continue
        boundary=list(face.verts);count=len(boundary)
        mi=face.material_index
        point=face.calc_center_median()+face.normal*r*rng.uniform(.14,.22)
        mid=bm.verts.new(point)
        bm.faces.remove(face)
        for i in range(count):
            f=bm.faces.new([boundary[i],boundary[(i+1)%count],mid])
            f.material_index=mi
    bmesh.ops.recalc_face_normals(bm,faces=bm.faces)
    bottom=min(v.co.z for v in bm.verts)
    for v in bm.verts:
        v.co = v.co + Vector((centre[0],centre[1],.045-bottom))
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me); bm.free()
    ob = K.obj(name, me, mats[0])
    ob.data.materials.append(mats[1])
    ob.data.materials.append(mats[2])
    for p in ob.data.polygons:
        p.use_smooth = False
    import bmesh as _bm
    bm2 = _bm.new(); bm2.from_mesh(me)
    bm2.edges.ensure_lookup_table()
    mats_of = [p.material_index for p in me.polygons]
    mark, crease_set = set(), set()
    for e in bm2.edges:
        lf = e.link_faces
        if len(lf) != 2:
            continue
        mi, mj = mats_of[lf[0].index], mats_of[lf[1].index]
        mats_bound = mi != mj and {mi, mj} != {1, 2}
        is_crack = not e.smooth
        elen = e.calc_length()
        is_rim = (e.calc_face_angle(0.0) > math.radians(14) and elen > 0.19 * r) or (mats_bound and elen > 0.12 * r)
        if is_rim or is_crack:
            mark.add(e.index)
        if is_rim and not is_crack:
            crease_set.add(e.index)
    bm2.free()
    em = me.attributes.get("freestyle_edge") or me.attributes.new("freestyle_edge", 'BOOLEAN', 'EDGE')
    for i, d in enumerate(em.data):
        d.value = i in mark
    cr = me.attributes.get("crease_edge") or me.attributes.new("crease_edge", 'FLOAT', 'EDGE')
    for i, d in enumerate(cr.data):
        d.value = crease if i in crease_set else 0.0
    bevel=ob.modifiers.new('Narrow fracture edge rounding','BEVEL')
    bevel.width=r*.018;bevel.segments=3;bevel.limit_method='ANGLE'
    bevel.angle_limit=math.radians(22);bevel.harden_normals=True
    weighted=ob.modifiers.new('Preserve planar face normals','WEIGHTED_NORMAL')
    weighted.keep_sharp=True;weighted.weight=50
    return ob


def ore_rig(name):
    setup_icon_rig();fs=_ore_linestyle()
    fs.linesets['ink'].select_crease=False
    fs.linesets['ink_fine'].select_crease=False
    fs.linesets['ink_edge'].linestyle.thickness=3.8
    col=open_collection('ICON_'+name)
    ID_SEPARATION_COLS.add(col.name)
    return Kit(col)


def build_coal():
    """D≈1.8. Angular fractured hero 1.0D high, asymmetric flanks 0.6D.
    More fractured facets; muted blue-grey on selected upward cleavage faces only.
    """
    K=ore_rig('coal')
    dark=toon_mat('coal_charcoal',(.030,.033,.038),steps=((.66,.18),(.90,.72),(9,1)))
    blue=toon_mat('coal_bluegrey',(.115,.175,.225),steps=((.66,.30),(.90,.67),(9,1)))
    specs=[((.05,.28),1.02,41,(1.06,.97,.98)),
           ((-.72,-.29),.66,42,(1.02,.94,.94)),
           ((.67,-.38),.69,43,(1.,.91,.99))]
    for i,((x,y),r,seed,sq) in enumerate(specs):
        ob=fractured_rock(K,'coal_fracture_'+str(i),(x,y,r*sq[2]*.72),r,seed,
            squash=sq,mats=(dark,blue,blue),cuts=0,planes=11,
            rust_depth=(.66,.86),noise_amp=.18,subdiv=3,
            crack_range=(0,0),subsurf_levels=2,crease=.90)
        for face in ob.data.polygons:
            face.material_index=1 if face.normal.z>.65 else 0
    for i,(x,y,r) in enumerate([(-.20,-1.0,.20),(.21,-1.03,.18),(.58,-.94,.21)]):
        sides=3+i  # triangular / quadrilateral / pentagonal prism:5/6/7 faces.
        verts=[]
        for level in (0,1):
            for j in range(sides):
                angle=2*math.pi*j/sides+.3+i*.4
                px=math.cos(angle)*r;py=math.sin(angle)*r*.85
                scale=1 if level==0 else .72
                verts.append((x+px*scale,y+py*scale,.025+level*(r*1.12+px*.16)))
        faces=[tuple(reversed(range(sides))),tuple(range(sides,sides*2))]
        faces += [(j,(j+1)%sides,(j+1)%sides+sides,j+sides) for j in range(sides)]
        ob=mesh_object(K,'coal_chip_'+str(i),verts,faces,dark,False)
        ob.data.materials.append(blue);ob.data.polygons[1].material_index=1
        marks=ob.data.attributes.new('freestyle_edge','BOOLEAN','EDGE')
        for mark in marks.data:mark.value=True
    bpy.context.view_layer.update();return K


def hematite_streak_material():
    """Broken anisotropic metallic seams across the fracture geometry, not grey caps.
    Object-space coordinates keep the pattern attached to the editable rock mesh.
    Hard colour thresholds preserve the goods' flat poster palette.
    """
    mat=toon_mat('hematite_streaks',(.41,.075,.045))
    nt=mat.node_tree
    base_mix=next(n for n in nt.nodes if n.bl_idname=='ShaderNodeMix')
    tex=nt.nodes.new('ShaderNodeTexCoord')
    mapping=nt.nodes.new('ShaderNodeMapping')
    mapping.inputs['Rotation'].default_value=(.15,.55,-.25)
    mapping.inputs['Scale'].default_value=(1.,1.,1.)
    stretch=nt.nodes.new('ShaderNodeVectorMath');stretch.operation='MULTIPLY'
    stretch.inputs[1].default_value=(14.,2.5,.9)
    nt.links.new(mapping.outputs['Vector'],stretch.inputs[0])
    nt.links.new(tex.outputs['Generated'],mapping.inputs['Vector'])
    noise=nt.nodes.new('ShaderNodeTexNoise')
    noise.inputs['Scale'].default_value=1.3
    noise.inputs['Detail'].default_value=2.0
    noise.inputs['Roughness'].default_value=.6
    nt.links.new(stretch.outputs['Vector'],noise.inputs['Vector'])
    palette=nt.nodes.new('ShaderNodeValToRGB');palette.label='Broken silver seams and sparse glints'
    palette.color_ramp.interpolation='CONSTANT'
    els=palette.color_ramp.elements
    els[0].position=0;els[0].color=(.41,.075,.045,1)
    els[1].position=.545;els[1].color=(.18,.22,.255,1)
    hi=els.new(.665);hi.color=(.37,.41,.46,1)
    coarse=nt.nodes.new('ShaderNodeTexNoise');coarse.inputs['Scale'].default_value=4.5
    coarse.inputs['Detail'].default_value=1.0
    nt.links.new(tex.outputs['Generated'],coarse.inputs['Vector'])
    gate=nt.nodes.new('ShaderNodeMath');gate.operation='GREATER_THAN';gate.inputs[1].default_value=.42
    nt.links.new(coarse.outputs['Fac'],gate.inputs[0])
    broken=nt.nodes.new('ShaderNodeMath');broken.operation='MULTIPLY'
    nt.links.new(noise.outputs['Fac'],broken.inputs[0]);nt.links.new(gate.outputs[0],broken.inputs[1])
    nt.links.new(broken.outputs[0],palette.inputs['Fac'])
    nt.links.new(palette.outputs['Color'],base_mix.inputs[6])
    return mat


def facet_edge_metal(ob):
    """Surface-distance seams tied to selected real edges of the left fracture faces.
    Right-facing polygons keep the previous, owner-liked streak material untouched.
    """
    import bmesh
    from mathutils import Vector
    bm=bmesh.new();bm.from_mesh(ob.data);bm.normal_update()
    candidates=[]
    camera=Vector((1,-1,1)).normalized()
    for edge in bm.edges:
        a,b=[v.co.copy() for v in edge.verts];mid=(a+b)*.5
        visible=any(f.normal.dot(camera)>.18 for f in edge.link_faces)
        if visible and mid.x+mid.y<.48 and edge.calc_length()>.24 and edge.calc_face_angle(0)>math.radians(16):
            candidates.append((edge.calc_length(),a,b))
    candidates.sort(key=lambda v:v[0],reverse=True)
    segments=candidates[:14];bm.free()
    mat=toon_mat('hematite_left_facet_seams',(.41,.075,.045));nt=mat.node_tree
    base=next(n for n in nt.nodes if n.bl_idname=='ShaderNodeMix')
    pos=nt.nodes.new('ShaderNodeNewGeometry').outputs['Position']
    def mathnode(op,a,b):
        node=nt.nodes.new('ShaderNodeMath');node.operation=op
        for idx,value in enumerate((a,b)):
            if isinstance(value,(int,float)):node.inputs[idx].default_value=value
            else:nt.links.new(value,node.inputs[idx])
        return node.outputs[0]
    def vectornode(op,a,b):
        node=nt.nodes.new('ShaderNodeVectorMath');node.operation=op
        for idx,value in enumerate((a,b)):
            if isinstance(value,(tuple,list,Vector)):node.inputs[idx].default_value=value
            else:nt.links.new(value,node.inputs[idx])
        return node.outputs['Value'] if op in ('DOT_PRODUCT','DISTANCE') else node.outputs['Vector']
    minimum=None
    for _,a,b in segments:
        d=b-a
        along=mathnode('DIVIDE',vectornode('DOT_PRODUCT',vectornode('SUBTRACT',pos,a),d),d.length_squared)
        along=mathnode('MINIMUM',mathnode('MAXIMUM',along,0),1)
        scaled=nt.nodes.new('ShaderNodeVectorMath');scaled.operation='SCALE'
        scaled.inputs[0].default_value=d;nt.links.new(along,scaled.inputs['Scale'])
        closest=vectornode('ADD',scaled.outputs['Vector'],a)
        distance=vectornode('DISTANCE',pos,closest)
        minimum=distance if minimum is None else mathnode('MINIMUM',minimum,distance)
    noise=nt.nodes.new('ShaderNodeTexNoise');noise.inputs['Scale'].default_value=19
    noise.inputs['Detail'].default_value=2;nt.links.new(pos,noise.inputs['Vector'])
    width=mathnode('ADD',mathnode('MULTIPLY',noise.outputs['Fac'],.1125),.012)
    metal=mathnode('LESS_THAN',minimum,width)
    coarse=nt.nodes.new('ShaderNodeTexNoise');coarse.inputs['Scale'].default_value=4.2
    nt.links.new(pos,coarse.inputs['Vector'])
    metal=mathnode('MULTIPLY',metal,mathnode('GREATER_THAN',coarse.outputs['Fac'],.39))
    glint=mathnode('MULTIPLY',mathnode('LESS_THAN',minimum,.018),mathnode('GREATER_THAN',noise.outputs['Fac'],.57))
    mask=mathnode('ADD',metal,mathnode('MULTIPLY',metal,glint))
    palette=nt.nodes.new('ShaderNodeValToRGB');palette.color_ramp.interpolation='CONSTANT'
    els=palette.color_ramp.elements;els[0].color=(.41,.075,.045,1)
    els[1].position=.4;els[1].color=(.18,.22,.255,1)
    hi=els.new(.9);hi.color=(.37,.41,.46,1)
    nt.links.new(mathnode('MULTIPLY',mask,.5),palette.inputs['Fac'])
    nt.links.new(palette.outputs['Color'],base.inputs[6])
    ob.data.materials.append(mat);index=len(ob.data.materials)-1
    crown_cutoff=max(v.co.z for v in ob.data.vertices)-.24
    for face in ob.data.polygons:
        if face.center.x+face.center.y<.38 and face.center.z<crown_cutoff:face.material_index=index
    # Let the wider metal carry most left-hand facet boundaries without dark ink.
    marks=ob.data.attributes.get('freestyle_edge')
    suppressed=0
    for edge in ob.data.edges:
        midpoint=sum((ob.data.vertices[i].co for i in edge.vertices),Vector())*.5
        if midpoint.x+midpoint.y<.38 and midpoint.z<crown_cutoff and marks.data[edge.index].value:
            marks.data[edge.index].value=False;suppressed+=1
    ob['left_internal_ink_edges_removed']=suppressed
    ob['left_seam_width_multiplier']=1.5
    ob['edge_seam_count']=len(segments)


def crown_metal_streak(ob):
    """One short taper on a top-facing crown facet, layered into its toon base colour."""
    from mathutils import Vector
    faces=[f for f in ob.data.polygons if f.normal.z>.35 and f.area>.065 and abs(f.center.x+f.center.y-.4)<.7]
    face=max(faces,key=lambda f:f.center.z)
    points=[ob.data.vertices[i].co.copy() for i in face.vertices]
    a,b=max([(points[i],points[(i+1)%len(points)]) for i in range(len(points))],key=lambda ab:(ab[1]-ab[0]).length)
    centre=face.center.copy();a=a.lerp(centre,.25);b=b.lerp(centre,.25);direction=b-a
    for mat in {m for m in ob.data.materials}:
        nt=mat.node_tree;mix=next(n for n in nt.nodes if n.bl_idname=='ShaderNodeMix')
        original=mix.inputs[6].links[0].from_socket
        pos=nt.nodes.new('ShaderNodeNewGeometry').outputs['Position']
        def mathn(op,x,y):
            n=nt.nodes.new('ShaderNodeMath');n.operation=op
            for i,v in enumerate((x,y)):
                if isinstance(v,(int,float)):n.inputs[i].default_value=v
                else:nt.links.new(v,n.inputs[i])
            return n.outputs[0]
        diff=nt.nodes.new('ShaderNodeVectorMath');diff.operation='SUBTRACT'
        nt.links.new(pos,diff.inputs[0]);diff.inputs[1].default_value=a
        dot=nt.nodes.new('ShaderNodeVectorMath');dot.operation='DOT_PRODUCT'
        nt.links.new(diff.outputs[0],dot.inputs[0]);dot.inputs[1].default_value=direction
        t=mathn('DIVIDE',dot.outputs['Value'],direction.length_squared)
        t=mathn('MINIMUM',mathn('MAXIMUM',t,0),1)
        scale=nt.nodes.new('ShaderNodeVectorMath');scale.operation='SCALE'
        scale.inputs[0].default_value=direction;nt.links.new(t,scale.inputs['Scale'])
        point=nt.nodes.new('ShaderNodeVectorMath');point.operation='ADD'
        nt.links.new(scale.outputs[0],point.inputs[0]);point.inputs[1].default_value=a
        dist=nt.nodes.new('ShaderNodeVectorMath');dist.operation='DISTANCE'
        nt.links.new(pos,dist.inputs[0]);nt.links.new(point.outputs[0],dist.inputs[1])
        width=mathn('MULTIPLY',mathn('SUBTRACT',1,mathn('ABSOLUTE',mathn('SUBTRACT',mathn('MULTIPLY',t,2),1),0)),.045)
        mask=mathn('LESS_THAN',dist.outputs['Value'],width)
        overlay=nt.nodes.new('ShaderNodeMixRGB');overlay.blend_type='MIX'
        nt.links.new(mask,overlay.inputs[0]);nt.links.new(original,overlay.inputs[1])
        overlay.inputs[2].default_value=(.30,.35,.40,1)
        nt.links.new(overlay.outputs[0],mix.inputs[6])
    ob['crown_streak_endpoints']=[list(a),list(b)]


def soften_front_ink(ob):
    """A dedicated thin taper for internal edges of the small foreground nugget."""
    col=bpy.data.collections.new('IRON_fine_internal_lines')
    bpy.context.scene.collection.children.link(col);col.objects.link(ob)
    fs=bpy.context.scene.view_layers[0].freestyle_settings
    old=fs.linesets['ink_edge'];old.select_by_collection=True
    old.collection=col;old.collection_negation='EXCLUSIVE'
    for name in ('ink','ink_fine'):
        lines=fs.linesets[name];lines.select_by_collection=True
        lines.collection=col;lines.collection_negation='EXCLUSIVE'
    fine=fs.linesets.new('iron_front_tapered_edges')
    for prop in ('select_silhouette','select_border','select_crease','select_ridge_valley',
                 'select_suggestive_contour','select_material_boundary','select_contour','select_external_contour'):
        if hasattr(fine,prop):setattr(fine,prop,False)
    fine.select_edge_mark=True;fine.select_by_collection=True
    fine.collection=col;fine.collection_negation='INCLUSIVE'
    fine.linestyle=old.linestyle.copy();fine.linestyle.name='Iron front fine wedges'
    fine.linestyle.thickness=1.7
    for mod in fine.linestyle.thickness_modifiers:
        if mod.type=='ALONG_STROKE':
            curve=mod.curve.curves[0]
            for pt in curve.points:
                pt.location.y=.08 if pt.location.x<.01 or pt.location.x>.99 else .85
            mod.curve.update()


def build_iron_ore():
    """D≈1.8. Three non-layered fractured lumps. Rust dominant; grey target30%.
    Grey cleavage caps are shallow and bounded by multiple rust facets.
    """
    K=ore_rig('iron_ore')
    rust=toon_mat('iron_rust',(.41,.075,.045))
    grey=toon_mat('iron_grey',(.18,.22,.255))
    hi=toon_mat('iron_fracture_highlight',(.37,.41,.46))
    specs=[((.12,.27),1.02,31,2,11,(1.,.90,1.06),(.88,.94)),
           ((-.60,-.33),.70,32,1,10,(1.,.86,1.02),(.805,.875)),
           ((.61,-.49),.66,33,1,10,(1.,.95,.91),(.805,.875))]
    streaks=hematite_streak_material()
    for i,((x,y),r,seed,cuts,planes,sq,gd) in enumerate(specs):
        rock_mats=(streaks,streaks,streaks) if i==0 else (rust,grey,hi)
        ob=fractured_rock(K,'iron_fracture_'+str(i),(x,y,r*sq[2]*.72),r,seed,
            squash=sq,mats=rock_mats,cuts=cuts,planes=planes,
            rust_depth=(.67,.86),grey_depth=gd,noise_amp=.16,subdiv=3,
            crack_range=(0,0),subsurf_levels=3,crease=.78)
        if i==0:
            facet_edge_metal(ob)
        if i==2:soften_front_ink(ob)
    bpy.context.view_layer.update();return K
