"""Editable first studies. Dimensions are relative to each good's principal width D.

Run with render_studies.py; the support kit is frozen beside this file so subsequent
experiments with other goods do not silently change these sources.
"""
import random


def mesh_object(K, name, verts, faces, mat, smooth=True):
    me = bpy.data.meshes.new(name)
    me.from_pydata(verts, [], faces)
    me.update()
    return K.obj(name, me, mat, smooth=smooth)


def lathe_cage(K, name, centre, profile, mat, segments=24, levels=2):
    """Quad control cage revolved about Z; profile is [(z,radius), ...]."""
    x, y, z = centre
    verts = [(x+r*math.cos(2*math.pi*i/segments),
              y+r*math.sin(2*math.pi*i/segments), z+h)
             for h,r in profile for i in range(segments)]
    faces = [tuple(reversed(range(segments)))]
    for j in range(len(profile)-1):
        for i in range(segments):
            a=j*segments+i; b=j*segments+(i+1)%segments
            faces.append((a,b,b+segments,a+segments))
    faces.append(tuple(range((len(profile)-1)*segments,len(profile)*segments)))
    ob=mesh_object(K,name,verts,faces,mat)
    sd=ob.modifiers.new('Editable silhouette cage','SUBSURF')
    sd.levels=levels; sd.render_levels=levels
    return ob


def tube(K, name, pts, radius, mat, vertical_start=False, start_direction=None, end_direction=None):
    cu=bpy.data.curves.new(name,'CURVE'); cu.dimensions='3D'
    cu.resolution_u=20; cu.bevel_depth=radius; cu.bevel_resolution=4
    sp=cu.splines.new('BEZIER'); sp.bezier_points.add(len(pts)-1)
    for bp,p in zip(sp.bezier_points,pts):
        bp.co=p; bp.handle_left_type='AUTO'; bp.handle_right_type='AUTO'
    if vertical_start or start_direction:
        # The first segment is an exact straight exit, with a vertical tangent at its end.
        direction=mathutils.Vector((0,0,1) if vertical_start else start_direction).normalized()
        for idx in (0,1):
            bp=sp.bezier_points[idx]
            bp.handle_left_type='FREE'; bp.handle_right_type='FREE'
            bp.handle_left=bp.co-direction*.06
            bp.handle_right=bp.co+direction*.06
    if end_direction:
        direction=mathutils.Vector(end_direction).normalized()
        for idx in (-2,-1):
            bp=sp.bezier_points[idx]
            bp.handle_left_type='FREE'; bp.handle_right_type='FREE'
            bp.handle_left=bp.co-direction*.045; bp.handle_right=bp.co+direction*.045
    ob=bpy.data.objects.new(name,cu); K.col.objects.link(ob)
    cu.materials.append(mat)
    bpy.context.view_layer.objects.active=ob; ob.select_set(True)
    bpy.ops.object.convert(target='MESH'); ob.select_set(False)
    # Curved cables get their outer silhouette from export, never longitudinal crease ink.
    noink(ob)
    return ob


def build_limestone():
    """D=1.4: seven sedimentary chunks, height .62D; cream/chalk/ochre strata.
    Owner refinement: add 1–2 chunks on the right and multiple coloured strata.
    Two interlocking right-hand chunks balance the original five, with broad bedding bands.
    """
    setup_icon_rig(); fs=_ore_linestyle()
    fs.linesets['ink'].select_crease=False
    fs.linesets['ink_fine'].select_crease=False
    fs.linesets['ink_edge'].linestyle.thickness=6.0
    col=open_collection('ICON_limestone'); K=Kit(col)
    mat=toon_mat('limestone_cream',(.95,.66,.29))
    chalk=toon_mat('limestone_chalk',(.98,.80,.48))
    ochre=toon_mat('limestone_ochre',(.67,.42,.18))
    buff=toon_mat('limestone_buff',(.83,.56,.25))
    ID_SEPARATION_COLS.add(col.name)
    if len(_ID_COLOURS)==6: _ID_COLOURS.append((1,1,1))
    specs=[(-.68,-.05,.10,1.0,12),(.55,.02,.10,1.03,23),
           (.08,.70,.12,.92,34),(.05,.36,.78,.93,45),(.05,-.62,.12,.86,56),
           (1.04,.59,.10,.80,67),(.65,.67,.65,.73,78)]
    for idx,(cx,cy,z,s,seed) in enumerate(specs):
        rng=random.Random(seed); n=8
        radial=[rng.uniform(.91,1.08) for _ in range(n)]
        wave=[rng.uniform(-.055,.055) for _ in range(n)]
        # Broad, asymmetric eight-sided cross section, softened by subdivision.
        rings=[(.0,.76),(.10,.98),(.28,1.03),(.38,1.02),(.56,1.0),
               (.68,.97),(.77,.94),(.88,.76)]
        verts=[]
        for j,(h,r) in enumerate(rings):
            for i in range(n):
                a=2*math.pi*i/n+.15*seed
                verts.append((cx+.78*s*r*radial[i]*math.cos(a),
                              cy+.65*s*r*radial[i]*math.sin(a),
                              z+s*(h+wave[i]*(.3 if j==0 else 1))))
        faces=[tuple(reversed(range(n)))]
        for j in range(len(rings)-1):
            for i in range(n):
                a=j*n+i; b=j*n+(i+1)%n
                faces.append((a,b,b+n,a+n))
        faces.append(tuple(range((len(rings)-1)*n,len(rings)*n)))
        ob=mesh_object(K,'layered_chunk_%02d'%idx,verts,faces,mat)
        for material in (chalk,ochre,buff): ob.data.materials.append(material)
        bands=[3,0,1,2,1,0,0]
        for j,mi in enumerate(bands):
            for face in ob.data.polygons[1+j*n:1+(j+1)*n]: face.material_index=mi
        crease=ob.data.attributes.new('crease_edge','FLOAT','EDGE')
        marks=ob.data.attributes.new('freestyle_edge','BOOLEAN','EDGE')
        for e in ob.data.edges:
            a,b=e.vertices; ra,rb=a//n,b//n
            crease.data[e.index].value=.65 if ra==rb else .55
            if ra==rb and ra in (2,4,6): marks.data[e.index].value=True
        sd=ob.modifiers.new('Rounded sedimentary cage','SUBSURF')
        sd.levels=2; sd.render_levels=2
    bpy.context.view_layer.update()
    return K


def build_electrical_components():
    """D=1 breaker width: height 1.7D, depth .50D, proud switch .30D.
    Bulb diameter .65D, cable diameter .11D. Yellow housing and owner-requested copper tips.
    Owner refinement: reference switch's upright root, folded tip and end face, without
    flaring; fine interior frames, copper strands and cable-base seams. Top/front yellow
    fields have a small deliberate tone difference.
    """
    setup_icon_rig(); col=open_collection('ICON_electrical_components'); K=Kit(col)
    fs=bpy.context.scene.view_layers[0].freestyle_settings
    fs.linesets['ink'].select_crease=True
    fs.linesets['ink_fine'].select_crease=True
    yellow=toon_mat('breaker_yellow',(.93,.68,.14),steps=((.66,.50),(.92,.86),(9.0,1.0)))
    steel=toon_mat('electrical_steel',(.40,.50,.54))
    dark=toon_mat('cable_warm_grey',(.28,.265,.205))
    switch_mat=toon_mat('switch_charcoal',(.12,.13,.13))
    switch_mount=toon_mat('switch_mount_warm_grey',(.22,.215,.17))
    switch_top=toon_mat('switch_top_plane',(.26,.245,.18))
    copper=toon_mat('exposed_copper',(.67,.32,.19))
    ivory=toon_mat('bulb_ivory',(.72,.69,.49))
    navy=K.mat('ic_navy')
    x,y=-.55,-.20
    K.box('rear_insulator',x,y+.26,1.02,1.04,.10,1.85,switch_mat)
    K.box('terminal_body',x,y-.03,1.02,1.0,.52,1.70,yellow)
    K.box('proud_switch_cover',x,y-.17,1.02,1.04,.55,.91,yellow)
    # A 0.01D navy border is geometry, not a thick frame plus a second Freestyle outline.
    noink(K.box('switch_mount_outline',x,y-.456,1.02,.31,.025,.45,navy))
    noink(K.box('switch_mount_face',x,y-.468,1.02,.29,.003,.43,switch_mount))
    noink(K.box('switch_pivot_slot',x,y-.484,1.04,.17,.015,.33,navy))
    # Reference close-up: upright root -> short folded top -> distinct end face.
    # Extruding ONE side profile keeps width constant; there is no paddle flare.
    yz=[(-.430,1.18),(-.495,1.18),(-.550,1.065),(-.735,.975),
        (-.700,.875),(-.470,1.00)]
    width=.145
    verts=[(x+side*width/2,y+dy,z) for side in (-1,1) for dy,z in yz]
    n=len(yz)
    faces=[tuple(reversed(range(n))),tuple(range(n,2*n))]
    for i in range(n): faces.append((i,(i+1)%n,(i+1)%n+n,i+n))
    K._fine_mode=True
    lever=mesh_object(K,'reference_flick_switch',verts,faces,switch_mat,False)
    lever.data.materials.append(switch_top)
    lever.data.polygons[4].material_index=1 # folded top surface, between profile points 2/3
    K._fine_mode=False
    for z in (.37,1.67):
        for dx in (-.29,.29):
            bolt_dot(K,'terminal_screw', (x+dx,y-.303,z),'Y',.075,navy)
    # Cable enters a proud gland, visibly connected at both ends.
    K._fine_mode=True
    K.cyl('top_gland',x,y,1.91,.12,.16,steel,segments=48)
    K._fine_mode=False
    seam_ring(K,'top_gland_breaker_seam',(x,y,1.873),.122,'Z',navy)
    bx,by=.66,.70
    tube(K,'bulb_supply_cable',[(x,y,1.91),(x,y,2.20),(-.36,.00,2.47),
         (.10,.39,2.34),(.32,.48,.65),(.57,.67,.51),(bx,by,.99)],.055,dark,
         vertical_start=True)
    K.cyl('bulb_contact',bx,by,.99,.10,.20,dark,segments=48)
    K.cyl('bulb_socket',bx,by,1.15,.20,.27,steel,segments=48)
    for z in (1.07,1.26):
        K.cyl('socket_thread',bx,by,z,.215,.045,steel,segments=48)
    lathe_cage(K,'bulb_globe', (bx,by,1.25),
        [(0,.14),(.06,.15),(.16,.18),(.31,.29),(.48,.35),(.66,.30),(.80,.16),(.84,.035)],ivory)
    # Filament is deliberately drawn on the front, not hidden behind a glass shader.
    normal=mathutils.Vector((1,-1,0)).normalized()
    right=mathutils.Vector((1,1,0)).normalized()
    def fp(x,z,r): return mathutils.Vector((bx,by,z))+normal*r+right*x
    tube(K,'filament_stems',[fp(-.05,1.46,.205),fp(-.09,1.76,.345),
         fp(-.10,1.88,.322),fp(.10,1.88,.322),fp(.09,1.76,.345),
         fp(.05,1.46,.205)],.012,navy)
    K._fine_mode=True
    K.cyl('supply_gland',-1.06,y,.22,.083,.12,steel,axis='X',segments=48)
    K._fine_mode=False
    seam_ring(K,'supply_gland_breaker_seam',(-1.053,y,.22),.085,'X',navy)
    tube(K,'loose_supply',[(x-.27,y,.24),(-1.12,-.18,.20),(-1.17,-.66,.18),
          (-.69,-.91,.16),(-.22,-.79,.16)],.066,dark)
    for i in range(3):
        tube(K,'exposed_wire_%d'%i,[(-.25,-.79,.16),(-.04,-.77+(i-1)*.05,.16),
             (.11,-.76+(i-1)*.13,.16)],.021,copper)
    # Third complete cable to an analog voltmeter, placed below the bulb.
    mx,my=1.28,.16
    K._fine_mode=True
    K.cyl('breaker_meter_gland',.01,-.10,.29,.082,.14,steel,axis='X',segments=48)
    K._fine_mode=False
    seam_ring(K,'meter_gland_breaker_seam',(-.046,-.10,.29),.084,'X',navy)
    tube(K,'voltmeter_lead',[(.075,-.10,.29),(.24,-.10,.29),(.43,-.025,.16),
         (.74,my,.22),(.875,my,.22)],.047,dark,
         start_direction=(1,0,0),end_direction=(1,0,0))
    K.cyl('meter_cable_gland',.875,my,.22,.075,.12,steel,axis='X',segments=48)
    K.box('voltmeter_case',mx,my,.34,.78,.38,.56,steel)
    # Thin 0.01D inset border. Face-mark both pieces to prevent doubled outline strokes.
    noink(K.box('voltmeter_bezel',mx,my-.201,.35,.64,.024,.42,navy))
    noink(K.box('voltmeter_dial',mx,my-.2075,.35,.62,.013,.40,ivory))
    def dial(x,z): return (mx+x,my-.245,z)
    arc=[dial(.235*math.cos(a),.24+.19*math.sin(a))
         for a in [math.radians(25+i*130/24) for i in range(25)]]
    tube(K,'voltmeter_scale',arc,.008,navy)
    for i in range(7):
        a=math.radians(25+i*130/6)
        tube(K,'meter_tick_%d'%i,[dial(r*math.cos(a),.24+r*.81*math.sin(a))
             for r in (.207,.238)],.006,navy)
    tube(K,'voltmeter_needle',[dial(0,.24),dial(.105,.39)],.010,navy)
    bolt_dot(K,'needle_pivot',dial(0,.24),'Y',.026,navy)
    face_text(K,'voltmeter_V','V',(mx,my-.253,.49),.09,navy,(0,-1,0))
    bpy.context.view_layer.update()
    return K


def seam_ring(K,name,centre,radius,axis,ink):
    """Fine navy bead exactly at the gland/wall intersection, 0.009D diameter."""
    c=mathutils.Vector(centre)
    pts=[]
    for i in range(97):
        a=2*math.pi*i/96
        offset=(radius*math.cos(a),radius*math.sin(a),0) if axis=='Z' else (0,radius*math.cos(a),radius*math.sin(a))
        pts.append(c+mathutils.Vector(offset))
    return tube(K,name,pts,.0045,ink)


def label(K, name, text, centre, width, height, ink, paper):
    """Flat engraved-style label aimed toward the icon camera; remains editable text."""
    normal=mathutils.Vector((1,-1,0)).normalized()
    right=mathutils.Vector((1,1,0)).normalized(); up=mathutils.Vector((0,0,1))
    c=mathutils.Vector(centre)
    verts=[c+right*a*width/2+up*b*height/2 for a,b in [(-1,-1),(1,-1),(1,1),(-1,1)]]
    mesh_object(K,name+'_plate',verts,[(0,1,2,3)],paper,False)
    cu=bpy.data.curves.new(name,'FONT'); cu.body=text; cu.align_x='CENTER'; cu.align_y='CENTER'
    cu.size=height*.69; cu.extrude=0
    ob=bpy.data.objects.new(name,cu); K.col.objects.link(ob)
    ob.location=c+normal*.008
    ob.rotation_euler=normal.to_track_quat('Z','Y').to_euler(); cu.materials.append(ink)
    # Convert so all render/framing/validation passes consistently see the text.
    bpy.context.view_layer.objects.active=ob; ob.select_set(True)
    bpy.ops.object.convert(target='MESH'); ob.select_set(False)
    noink(ob)
    xs=[v.co.x for v in ob.data.vertices]
    scale=min(1.0,width*.85/(max(xs)-min(xs)))
    for v in ob.data.vertices: v.co*=scale


def face_text(K,name,text,centre,size,mat,normal):
    cu=bpy.data.curves.new(name,'FONT'); cu.body=text
    cu.align_x='CENTER'; cu.align_y='CENTER'; cu.size=size
    ob=bpy.data.objects.new(name,cu); K.col.objects.link(ob)
    ob.location=centre
    n=mathutils.Vector(normal).normalized()
    up=mathutils.Vector((0,1,0) if abs(n.z)>.99 else (0,0,1))
    right=up.cross(n).normalized(); up=n.cross(right).normalized()
    ob.rotation_euler=mathutils.Matrix((right,up,n)).transposed().to_euler()
    cu.materials.append(mat)
    bpy.context.view_layer.objects.active=ob; ob.select_set(True)
    bpy.ops.object.convert(target='MESH'); ob.select_set(False); noink(ob)
    return ob


def curved_label(K, text, z, radius, width, height, paper, ink):
    """Paper and tessellated glyphs share the neck's cylindrical coordinates."""
    theta0=-math.pi/4
    def wrap(u,v,r=radius):
        a=theta0+u/radius
        return (r*math.cos(a),r*math.sin(a),z+v)
    n=48
    verts=[wrap(-width/2+width*i/n,v) for v in (-height/2,height/2) for i in range(n+1)]
    faces=[(i,i+1,i+n+2,i+n+1) for i in range(n)]
    patch=mesh_object(K,'curved_formula_label',verts,faces,paper); noink(patch)
    border=[wrap(-width/2+width*i/n,-height/2,radius+.003) for i in range(n+1)]
    border += [wrap(width/2,height/2,radius+.003)]
    border += [wrap(width/2-width*i/n,height/2,radius+.003) for i in range(1,n+1)]
    border += [border[0]]
    # Polyline-style corners, sampled densely around the circumference.
    cu=bpy.data.curves.new('label_border','CURVE'); cu.dimensions='3D'
    cu.bevel_depth=.005; cu.bevel_resolution=3
    sp=cu.splines.new('POLY'); sp.points.add(len(border)-1)
    for p,co in zip(sp.points,border): p.co=(*co,1)
    ob=bpy.data.objects.new('label_border',cu); K.col.objects.link(ob); cu.materials.append(ink)
    bpy.context.view_layer.objects.active=ob; ob.select_set(True)
    bpy.ops.object.convert(target='MESH'); ob.select_set(False); noink(ob)
    glyphs=face_text(K,'wrapped_formula',text,(0,0,0),height*.70,ink,(0,0,1))
    xs=[v.co.x for v in glyphs.data.vertices]; ys=[v.co.y for v in glyphs.data.vertices]
    scale=min(width*.82/(max(xs)-min(xs)),height*.69/(max(ys)-min(ys)))
    cx=(min(xs)+max(xs))/2; cy=(min(ys)+max(ys))/2
    bm=bmesh.new(); bm.from_mesh(glyphs.data)
    bmesh.ops.triangulate(bm,faces=list(bm.faces))
    bmesh.ops.subdivide_edges(bm,edges=list(bm.edges),cuts=3,use_grid_fill=True)
    bm.to_mesh(glyphs.data); bm.free()
    for v in glyphs.data.vertices:
        v.co=wrap((v.co.x-cx)*scale,(v.co.y-cy)*scale,radius+.009)


def glass_window_nodes(nt, only_glass_object=False):
    """Binary clear front window: reveal real liquid while retaining pale glass silhouette.
    Same window is applied to the mask override, so liquid-top normals drive its halftone.
    """
    geo=nt.nodes.new('ShaderNodeNewGeometry')
    dot=nt.nodes.new('ShaderNodeVectorMath'); dot.operation='DOT_PRODUCT'
    nt.links.new(geo.outputs['Normal'],dot.inputs[0]); nt.links.new(geo.outputs['Incoming'],dot.inputs[1])
    facing=nt.nodes.new('ShaderNodeMath'); facing.operation='GREATER_THAN'; facing.inputs[1].default_value=.38
    nt.links.new(dot.outputs['Value'],facing.inputs[0])
    sep=nt.nodes.new('ShaderNodeSeparateXYZ'); nt.links.new(geo.outputs['Position'],sep.inputs[0])
    low=nt.nodes.new('ShaderNodeMath'); low.operation='LESS_THAN'; low.inputs[1].default_value=1.92
    nt.links.new(sep.outputs['Z'],low.inputs[0])
    both=nt.nodes.new('ShaderNodeMath'); both.operation='MULTIPLY'
    nt.links.new(facing.outputs[0],both.inputs[0]); nt.links.new(low.outputs[0],both.inputs[1])
    # Keep the rear glass opaque: it supplies the pale interior behind the liquid.
    # Shading normals alone may face the ray on both sides of a thin shell.
    front=nt.nodes.new('ShaderNodeMath'); front.operation='SUBTRACT'; front.inputs[0].default_value=1
    nt.links.new(geo.outputs['Backfacing'],front.inputs[1])
    window=nt.nodes.new('ShaderNodeMath'); window.operation='MULTIPLY'
    nt.links.new(both.outputs[0],window.inputs[0]); nt.links.new(front.outputs[0],window.inputs[1])
    result=window.outputs[0]
    if only_glass_object:
        info=nt.nodes.new('ShaderNodeObjectInfo')
        tag=nt.nodes.new('ShaderNodeMath'); tag.operation='LESS_THAN'; tag.inputs[1].default_value=.5
        nt.links.new(info.outputs['Alpha'],tag.inputs[0])
        mul=nt.nodes.new('ShaderNodeMath'); mul.operation='MULTIPLY'
        nt.links.new(result,mul.inputs[0]); nt.links.new(tag.outputs[0],mul.inputs[1]); result=mul.outputs[0]
    out=next(n for n in nt.nodes if n.type=='OUTPUT_MATERIAL')
    original=out.inputs['Surface'].links[0].from_socket
    mix=nt.nodes.new('ShaderNodeMixShader'); transparent=nt.nodes.new('ShaderNodeBsdfTransparent')
    nt.links.new(original,mix.inputs[1]); nt.links.new(transparent.outputs[0],mix.inputs[2])
    nt.links.new(result,mix.inputs[0]); nt.links.new(mix.outputs[0],out.inputs['Surface'])


_original_shade_mask_material=shade_mask_material
def shade_mask_material():
    mat=_original_shade_mask_material()
    glass_window_nodes(mat.node_tree,only_glass_object=True)
    return mat


def build_ethylene():
    """D=1.8 flask body diameter; height 1.58D, neck diameter .34D, rim .43D.
    Owner refinement: one liquid volume and coloured circular cap share a boundary;
    glass-coloured mouth; paper AND formula wrap around the cylindrical neck.
    """
    setup_icon_rig(); col=open_collection('ICON_ethylene'); K=Kit(col)
    glass=toon_mat('flask_pale',(.72,.86,.87))
    teal=toon_mat('flask_teal',(.42,.68,.64),steps=((.66,.50),(.92,.76),(9.0,1.0)))
    liquid_top=toon_mat('liquid_top',(.37,.62,.58))
    paper=toon_mat('label_paper',(.97,.95,.84))
    navy=K.mat('ic_navy')
    profile=[(.08,.27),(.10,.48),(.22,.70),(.45,.87),(.75,.94),
             (1.02,.94),(1.28,.84),(1.49,.65),(1.62,.43),(1.77,.32),
             (1.91,.31),(2.72,.31),(2.77,.31)]
    shell=toon_mat('glass_shell',(.72,.86,.87)); glass_window_nodes(shell.node_tree)
    body=lathe_cage(K,'flask_control_cage',(0,0,0),profile,shell,64)
    body.color=(1,1,1,.1) # tag for identical transparency in the shading-mask pass
    noink(body)
    liquid_profile=[(.15,.24),(.18,.42),(.25,.61),(.38,.74),(.55,.83),
                    (.72,.87),(.88,.88),(.94,.875)]
    liquid=lathe_cage(K,'continuous_liquid_volume',(0,0,0),liquid_profile,teal,96,levels=0)
    liquid.data.materials.append(liquid_top)
    liquid.data.polygons[-1].material_index=1
    # The cap is planar; its exact perimeter also terminates every liquid side face.
    liquid.data.polygons[-1].use_smooth=False
    tube(K,'liquid_surface_rim',[(.875*math.cos(a),.875*math.sin(a),.943)
         for a in [2*math.pi*i/96 for i in range(97)]],.008,navy)
    K.cyl('neck_rim',0,0,2.77,.385,.10,glass,segments=64)
    K.cyl('recessed_mouth',0,0,2.828,.303,.014,navy,segments=64)
    K.cyl('mouth_inner',0,0,2.837,.265,.012,glass,segments=64)
    curved_label(K,'C₂H₄',2.34,.315,.65,.40,paper,navy)
    bpy.context.view_layer.update()
    return K
