"""Steel ironworks: compact A / complete A / twin B, with C's materials.

Executed in sprite_kit's namespace by the frozen building pipeline. Coordinates
of the first process line are retained across all levels. Exterior process cues
are illustrative; this is a game asset, not a capacity or structural design.
"""
import math
from mathutils import Vector, Matrix

PALETTE.update({
    'f_shell': (.055, .068, .078),
    'f_frame': (.035, .043, .050),
    'f_sheet': (.13, .075, .046),
    'f_copper': (.39, .155, .065),
    'f_brick': (.34, .105, .062),
    'f_mortar': (.22, .091, .056),
    'f_roof': (.065, .082, .090),
    'f_zinc': (.66, .70, .72),
    'f_steel': (.38, .43, .48),
    'f_base': (.37, .355, .30),
    'f_ochre': (.52, .31, .055),
    'f_oxide': (.34, .125, .055),
})


def _f_rail(K, name, a, b, h=.23, gate=False):
    """A lightweight guard with real posts; omit the middle for ladder access."""
    a, b = Vector(a), Vector(b)
    count = max(1, math.ceil((b-a).length/.55))
    gap = gate if isinstance(gate, tuple) else (.35,.65)
    for i in range(count+1):
        if gate and gap[0] < i/count < gap[1]: continue
        p = a.lerp(b, i/count)
        K.dircyl(name+'_post'+str(i), p, p+Vector((0,0,h)), .014, K.mat('f_ochre'), segments=8)
    for z in (h*.47,h):
        if gate:
            for lo,hi in ((0,gap[0]),(gap[1],1)):
                K.dircyl(name+'_gate',a.lerp(b,lo)+Vector((0,0,z)),a.lerp(b,hi)+Vector((0,0,z)),.013,K.mat('f_ochre'),segments=8)
        else:
            K.dircyl(name+'_rail',a+Vector((0,0,z)),b+Vector((0,0,z)),.013,K.mat('f_ochre'),segments=8)


def _f_deck(K, name, x, y, z, w, d, gate=False):
    K.box(name+'_deck',x,y,z-.04,w,d,.08,K.mat('f_zinc'))
    K._fine_mode=True
    _f_rail(K,name+'_front',(x-w/2,y-d/2,z),(x+w/2,y-d/2,z))
    _f_rail(K,name+'_rear',(x-w/2,y+d/2,z),(x+w/2,y+d/2,z),gate=(.10,.40) if gate else False)
    _f_rail(K,name+'_left',(x-w/2,y-d/2,z),(x-w/2,y+d/2,z))
    _f_rail(K,name+'_right',(x+w/2,y-d/2,z),(x+w/2,y+d/2,z))
    K._fine_mode=False


def _f_shed(K,name,x,y,w,d,h,door=True,bays=None):
    """Portal shed, open doorway made from separate wall pieces, no painted hole."""
    masonry='cleaning' not in name
    wall=K.mat('f_brick' if masonry else 'f_sheet'); frame=K.mat('f_frame')
    K.box(name+'_footing',x,y,.08,w+.10,d+.10,.16,K.mat('f_base'))
    K.box(name+'_back',x,y+d/2-.04,h/2+.10,w,.08,h,wall)
    for s in (-1,1):
        K.box(name+'_side'+str(s),x+s*(w/2-.04),y,h/2+.10,.08,d,h,wall)
        K.box(name+'_portal'+str(s),x+s*(w/2-.06),y-d/2,.1+h/2,.075,.11,h,frame)
    front=y-d/2
    dw=min(.72,w*.50)
    if bays is not None:
        # One continuous hall with actual door apertures and no internal end walls.
        cursor=x-w/2
        for i,cx in enumerate(bays):
            lo,hi=cx-dw/2,cx+dw/2
            K.box(name+'_pier'+str(i),(cursor+lo)/2,front,h/2+.10,lo-cursor,.08,h,wall)
            K.box(name+'_lintel'+str(i),cx,front,h-.04,dw,.10,.28,wall)
            K.box(name+'_opening_shadow'+str(i),cx,front+.40,.49,dw-.06,.035,.70,K.mat('ink_black'))
            K.box(name+'_bay'+str(i)+'_heat',cx,front+.36,.40,dw*.44,.04,.16,K.mat('ember'))
            cursor=hi
        K.box(name+'_pier_end',(cursor+x+w/2)/2,front,h/2+.10,x+w/2-cursor,.08,h,wall)
    elif door:
        for s in (-1,1):
            K.box(name+'_pier'+str(s),x+s*(w+dw)/4,front,h/2+.10,(w-dw)/2,.08,h,wall)
        K.box(name+'_lintel',x,front,h-.04,dw,.10,.28,wall)
        K.box(name+'_opening_shadow',x,front+.40,.49,dw-.06,.035,.70,K.mat('ink_black'))
        # A small recessed heat cue; no permanent pour or glowing vessel shell.
        if 'casthouse' in name:
            K.box(name+'_heat',x,front+.36,.40,dw*.44,.04,.16,K.mat('ember'))
    else:
        K.box(name+'_front',x,front,h/2+.10,w,.08,h,wall)
    rise=.23
    K.prism(name+'_gable',(x,y,0),(0,1),[(-d/2,h+.10),(0,h+.10+rise),(d/2,h+.10)],w,wall)
    for s in (-1,1):
        ya,yb=(-d/2-.09,0) if s<0 else (0,d/2+.09)
        za,zb=(h+.08,h+.10+rise) if s<0 else (h+.10+rise,h+.08)
        K.prism(name+'_roof'+str(s),(x,y,0),(0,1),[(ya,za),(yb,zb),(yb,zb+.055),(ya,za+.055)],w+.16,K.mat('f_roof'))
    K._fine_mode=True
    # Standing seams follow the roof slope, as in the Paper WPA factory.
    for j in range(max(2,round(w/.24))+1):
        px=x-w/2+j*w/max(2,round(w/.24))
        for side in (-1,1):
            K.dirbox(name+'_roof_seam',(px,y+side*(d/2+.06),h+.15),(px,y,h+.10+rise+.06),.012,.012,K.mat('f_roof'))
    # Broad panel divisions survive at icon scale; omit dense corrugation.
    for i in range(1,1 if masonry else max(2,round(w/.32))):
        px=x-w/2+i*w/max(2,round(w/.32))
        if not door or abs(px-x)>dw/2+.035:
            K.box(name+'_seam'+str(i),px,front-.048,h/2+.12,.014,.012,h-.06,frame)
    for s in (-1,1):
        if w>1.8 and bays is None:
            K.window(name+'_window'+str(s),'-Y',(x+s*w*.33,front-.055,h*.76),w*.19,.18,cols=2,rows=1,sill=False)
    if bays is not None:
        for i,cx in enumerate(bays):
            for side in (-1,1):
                K.window(name+f'_bay{i}_window{side}','-Y',(cx+side*.72,front-.055,h*.76),.42,.18,cols=2,rows=1,sill=False)
    K._fine_mode=False


def _f_gallery_axes(a,b):
    direction=(b-a).normalized()
    across=Vector((direction.y,-direction.x,0))
    if across.length<1e-6:across=Vector((1,0,0))
    across.normalize();up=across.cross(direction).normalized()
    return Matrix((across,direction,up)).transposed()


def _f_gallery_box(K,name,a,b,w,h,mat):
    a,b=Vector(a),Vector(b);center=(a+b)/2
    old=Vector((0,1,0)).rotation_difference((b-a).normalized()).to_matrix()
    rotation=_f_gallery_axes(a,b)@old.transposed()
    ob=K.dirbox(name,a,b,w,h,mat)
    for vertex in ob.data.vertices:vertex.co=center+rotation@(vertex.co-center)
    ob.data.update()
    return ob


def _f_duct(K,name,a,b,w=.38,h=.42,open_top=0):
    """Four real casing walls, with an open bore and optional inlet roof opening."""
    a,b=Vector(a),Vector(b);length=(b-a).length
    rot=_f_gallery_axes(a,b)
    verts=[];faces=[];t=.025
    parts=[((0,length/2,-h/2+t/2),(w,length,t)),
           ((-w/2+t/2,length/2,0),(t,length,h)),
           ((w/2-t/2,length/2,0),(t,length,h)),
           ((0,length*(1+open_top)/2,h/2-t/2),(w,length*(1-open_top),t))]
    for center,size in parts:
        base=len(verts)
        for x,y,z in ((-1,-1,-1),(1,-1,-1),(1,1,-1),(-1,1,-1),(-1,-1,1),(1,-1,1),(1,1,1),(-1,1,1)):
            local=Vector((center[0]+x*size[0]/2,center[1]+y*size[1]/2,center[2]+z*size[2]/2))
            verts.append(a+rot@local)
        faces.extend(tuple(base+i for i in f) for f in ((0,3,2,1),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)))
    mesh=bpy.data.meshes.new(name);mesh.from_pydata(verts,[],faces);mesh.update()
    ob=K.obj(name,mesh,K.mat('f_zinc'));ob['route_start']=list(a);ob['route_end']=list(b)
    return ob


def _f_lift_segment(K,name,a,b,ribs,inlet=False):
    a,b=Vector(a),Vector(b)
    rot=_f_gallery_axes(a,b)
    across=rot@Vector((1,0,0));up=rot@Vector((0,0,1))
    roof_open=float(inlet) if not isinstance(inlet,bool) else (.18 if inlet else 0)
    _f_duct(K,name+'_case',a,b,open_top=roof_open)
    # Carry and return belt, with terminal drums inside the enclosed gallery.
    _f_gallery_box(K,name+'_carry_belt',a,b,.30,.025,K.mat('f_frame'))
    _f_gallery_box(K,name+'_return_belt',a-up*.13,b-up*.13,.30,.02,K.mat('f_frame'))
    for j,p in enumerate((a,b)):
        K.dircyl(name+'_drum'+str(j),p-across*.15-up*.065,p+across*.15-up*.065,.067,K.mat('f_frame'),segments=16)
    K._fine_mode=True
    for side in (-1,1):
        offset=across*(side*.196)-up*.18
        K.dirbox(name+'_edge',a+offset,b+offset,.035,.035,K.mat('f_frame'))
    for j in range(1,ribs):
        point=a.lerp(b,j/ribs)
        for side in (-1,1):
            K.dirbox(name+'_side_seam',point+across*(side*.197)-up*.21,point+across*(side*.197)+up*.21,.012,.012,K.mat('f_frame'))
        if j/ribs>roof_open:
            K.dirbox(name+'_top_seam',point-across*.20+up*.216,point+across*.20+up*.216,.012,.012,K.mat('f_frame'))
    K._fine_mode=False
    return a,b


def _f_elevator_tower(K):
    """Brick enclosure with real feed/discharge ports and removable inspection panel."""
    x=-2.08;y=.285;w=1.28;d=1.25;h=4.05;front=y-d/2
    _f_shed(K,'handling_annex',x,y,w,d,h,door=False)
    # Replace the generic full front wall with a perforated facade.
    wall=bpy.data.objects.get('handling_annex_front');bpy.data.objects.remove(wall,do_unlink=True)
    holes=[(-2.70,-2.23,.94,1.65)]
    xs=sorted(set([x-w/2,x+w/2]+[v for hole in holes for v in hole[:2]]))
    zs=sorted(set([.1,h+.1]+[v for hole in holes for v in hole[2:]]))
    for ix,(lo,hi) in enumerate(zip(xs,xs[1:])):
        for iz,(bottom,top) in enumerate(zip(zs,zs[1:])):
            mx=(lo+hi)/2;mz=(bottom+top)/2
            if any(a<mx<b and c<mz<e for a,b,c,e in holes):continue
            ob=K.box(f'elevator_facade_{ix}_{iz}',mx,front,mz,hi-lo,.08,top-bottom,K.mat('f_brick'))
            # Coplanar subdivision edges are not building joints.
            marks=ob.data.attributes.new('freestyle_face','BOOLEAN','FACE')
            for face in marks.data:face.value=True
    # The upper conveyor exits the right wall through a genuine gallery port.
    wall=bpy.data.objects.get('handling_annex_side1');bpy.data.objects.remove(wall,do_unlink=True)
    for ya,yb in zip((-.34,-.30,.20),(-.30,.20,.91)):
        for za,zb in zip((.10,3.58,4.13),(3.58,4.13,4.15)):
            if ya==-.30 and za==3.58:continue
            ob=K.box('elevator_side_facade',-1.48,(ya+yb)/2,(za+zb)/2,.08,yb-ya,zb-za,K.mat('f_brick'))
            marks=ob.data.attributes.new('freestyle_face','BOOLEAN','FACE')
            for face in marks.data:face.value=True
    K.box('elevator_inspection_panel',-2.32,front-.055,2.40,.43,.035,.72,K.mat('f_sheet'))
    K.box('elevator_access_handle',-2.18,front-.08,2.40,.025,.025,.13,K.mat('f_zinc'))
    K.box('annex_loading_door',-2.73,y-.02,.52,.035,.58,.86,K.mat('door'))
    # Rear maintenance elevation: ventilated head machinery, service glazing,
    # and accessible door hardware. Keep a quiet masonry field between features.
    K._fine_mode=True
    K.window('tower_rear_service_window','+Y',(-2.08,.925,2.40),.66,.40,cols=2,rows=1)
    for face,cx,cy in (('rear',-2.08,.925),('side',-2.735,.285)):
        along_x=face=='rear'
        K.box('tower_'+face+'_vent_recess',cx,cy,3.51,.70 if along_x else .025,.025 if along_x else .64,.37,K.mat('f_frame'))
        for i in range(5):
            K.box('tower_'+face+'_vent_louvre',cx,cy+.02 if along_x else cy,3.36+i*.075,
                  .65 if along_x else .04,.04 if along_x else .59,.022,K.mat('f_roof'))
    K.window('tower_side_service_window','-X',(-2.735,.285,2.40),.60,.40,cols=2,rows=1)
    for yy in (y-.33,y+.29):
        K.box('tower_door_jamb',-2.755,yy,.53,.045,.045,.90,K.mat('f_frame'))
    K.box('tower_door_lintel',-2.755,y-.02,.99,.045,.67,.06,K.mat('f_frame'))
    K.box('tower_door_handle',-2.775,y+.18,.52,.025,.025,.13,K.mat('f_zinc'))
    for z in (.27,.77):
        K.box('tower_door_hinge',-2.775,y-.26,z,.026,.07,.045,K.mat('f_frame'))
    K._fine_mode=False


def _f_brick_courses(K):
    """World-aligned running bond, clipped to actual masonry faces and openings.

    Thin uninked mortar faces retain flat palette colours in the GLB as well as
    the sprite. These are surface marks, not separate outlined brick boxes.
    """
    bpy.context.view_layer.update()
    verts=[];faces=[]
    def clip(poly,axis,bound,keep_greater):
        result=[]
        for a,b in zip(poly,poly[1:]+poly[:1]):
            ia=(a[axis]>=bound) if keep_greater else (a[axis]<=bound)
            ib=(b[axis]>=bound) if keep_greater else (b[axis]<=bound)
            if ia:result.append(a)
            if ia!=ib:
                t=(bound-a[axis])/(b[axis]-a[axis])
                result.append(tuple(a[k]+t*(b[k]-a[k]) for k in range(2)))
        return result
    def patch(poly,u0,u1,z0,z1,axis,plane,normal):
        for ax,bound,greater in ((0,u0,True),(0,u1,False),(1,z0,True),(1,z1,False)):
            poly=clip(poly,ax,bound,greater)
            if len(poly)<3:return
        # A clip plane through an existing corner can repeat that vertex.
        clean=[]
        for p in poly:
            if not clean or sum((p[k]-clean[-1][k])**2 for k in range(2))>1e-16:
                clean.append(p)
        if len(clean)>1 and sum((clean[0][k]-clean[-1][k])**2 for k in range(2))<1e-16:
            clean.pop()
        poly=clean
        if len(poly)<3:return
        area=sum(a[0]*b[1]-b[0]*a[1] for a,b in zip(poly,poly[1:]+poly[:1]))
        if abs(area)<1e-9:return
        start=len(verts)
        for u,z in poly:
            p=Vector((u,plane,z) if axis==0 else (plane,u,z)) + normal*.002
            verts.append(tuple(p))
        faces.append(tuple(range(start,len(verts))))
    selected=[o for o in K.col.objects if o.type=='MESH'
              and o.name.startswith(('handling_annex_','elevator_facade_','elevator_side_facade','shared_casthouse_'))
              and K.mat('f_brick') in list(o.data.materials)]
    for ob in selected:
        for face in ob.data.polygons:
            n=(ob.matrix_world.to_3x3()@face.normal).normalized()
            if abs(n.z)>.01:continue
            axis=0 if abs(n.y)>.9 else 1
            points=[ob.matrix_world@ob.data.vertices[i].co for i in face.vertices]
            poly=[(p[axis],p.z) for p in points];plane=points[0][1-axis]
            lo,hi=min(p[0] for p in poly),max(p[0] for p in poly)
            bottom,top=min(p[1] for p in poly),max(p[1] for p in poly)
            # 0.25-wide bricks, 0.115 course height, narrow dark mortar.
            for row in range(math.floor(bottom/.115),math.ceil(top/.115)+1):
                z=row*.115
                patch(poly,lo,hi,z-.004,z+.004,axis,plane,n)
                offset=(row%2)*.125
                for col in range(math.floor((lo-offset)/.25),math.ceil((hi-offset)/.25)+1):
                    u=col*.25+offset
                    patch(poly,u-.004,u+.004,z+.004,z+.111,axis,plane,n)
    mesh=bpy.data.meshes.new('masonry_running_bond')
    mesh.from_pydata(verts,[],faces);mesh.update()
    ob=K.obj('masonry_running_bond',mesh,K.mat('f_mortar'))
    marks=mesh.attributes.new('freestyle_face','BOOLEAN','FACE')
    for face in marks.data:face.value=True
    ob['course_height']=.115;ob['brick_width']=.25


def _f_two_stage_lift(K):
    _f_elevator_tower(K)
    lower=_f_lift_segment(K,'charge_lower',(-1.25,-.60,1.60),(-2.50,-.60,1.60),4,inlet=.30)
    upper=_f_lift_segment(K,'charge_upper',(-2.02,-.08,3.75),(-.26,0,4.20),6,inlet=True)
    _f_duct(K,'charge_feed_hood',(-1.43,-.60,1.94),(-1.43,-.60,1.66),w=.30,h=.30)
    for side in (-1,1):
        K.box('charge_feed_foot',-1.25,-.60+side*.26,.08,.25,.23,.16,K.mat('f_base'))
        K.box('charge_feed_leg',-1.25,-.60+side*.26,.82,.085,.085,1.48,K.mat('f_frame'))
    # Explicit gravity transfers through the two facade ports.
    _f_duct(K,'elevator_inlet_chute',(-2.50,-.60,1.60),(-2.48,-.08,1.11),w=.30,h=.24)
    _f_duct(K,'elevator_head_chute',(-2.02,-.08,4.14),(-1.85,-.08,3.94),w=.24,h=.20)
    # Enclosed bucket elevator: paired chain legs, head/boot wheels and buckets.
    cx=-2.32;cy=-.08;bottom=1.18;top=3.98;r=.16
    for name,z in (('boot',bottom),('head',top)):
        K.cyl('elevator_'+name+'_wheel',cx,cy,z,r,.18,K.mat('f_frame'),axis='Y',segments=24)
        K.dircyl('elevator_'+name+'_shaft',(cx,cy-.16,z),(cx,cy+.25,z),.025,K.mat('f_zinc'),segments=12)
    K.box('elevator_boot_floor',cx,cy,.96,.54,.38,.025,K.mat('f_frame'))
    for side in (-1,1):
        K.box('elevator_boot_side',cx+side*.26,cy,1.04,.025,.38,.16,K.mat('f_frame'))
        K.box('elevator_boot_cheek',cx,cy+side*.18,1.04,.54,.025,.16,K.mat('f_frame'))
    K.cyl('elevator_drive_motor',cx,cy+.30,top,.11,.25,K.mat('f_sheet'),axis='Y',segments=16)
    for side in (-1,1):
        px=cx+side*r
        K.box('elevator_chain_'+str(side),px,cy,(top+bottom)/2,.025,.12,top-bottom,K.mat('f_frame'))
        for j in range(12):
            z=bottom+.10+j*(top-bottom-.2)/11
            # Open-topped cups attached to each chain; no solid pretend hopper.
            bx=px+side*.065;vertical=-side
            K.box(f'elevator_bucket_floor_{side}_{j}',bx,cy,z,.13,.19,.018,K.mat('f_zinc'))
            K.box(f'elevator_bucket_outer_{side}_{j}',px+side*.125,cy,z+vertical*.045,.018,.19,.09,K.mat('f_zinc'))
            for sy in (-1,1):
                K.box(f'elevator_bucket_cheek_{side}_{j}_{sy}',bx,cy+sy*.09,z+vertical*.045,.13,.018,.09,K.mat('f_zinc'))
    # A cup tipping over the head makes the discharge direction inspectable.
    center=Vector((cx+r/math.sqrt(2),cy,top+r/math.sqrt(2)))
    turn=Matrix.Rotation(math.radians(135),3,'Y')
    parts=[('floor',(0,0,0),(.13,.19,.018)),('outer',(-.06,0,.045),(.018,.19,.09)),
           ('cheek0',(0,-.09,.045),(.13,.018,.09)),('cheek1',(0,.09,.045),(.13,.018,.09))]
    for tag,offset,size in parts:
        ob=K.box('elevator_tipping_bucket_'+tag,*offset,*size,K.mat('f_zinc'))
        for vertex in ob.data.vertices:vertex.co=center+turn@vertex.co
        ob.data.update()
    # Separate braced trestle, kept outside the four-column furnace footprint.
    a,b=upper;p=a.lerp(b,(-1.24-a.x)/(b.x-a.x));bearing=p.z-.23
    for side in (-1,1):
        y=p.y+side*.28
        K.box('charge_upper_foot',p.x,y,.08,.22,.22,.16,K.mat('f_base'))
        K.box('charge_upper_leg',p.x,y,(.16+bearing)/2,.105,.12,bearing-.16,K.mat('f_frame'))
    K.box('charge_upper_bearing',p.x,p.y,bearing,.20,.72,.10,K.mat('f_frame'))
    for z0,z1 in zip((.22,1.35,2.48),(1.35,2.48,bearing)):
        for side in (-1,1):
            K.dirbox('charge_upper_xbrace',(p.x,p.y+side*.28,z0),(p.x,p.y-side*.28,z1),.045,.045,K.mat('f_frame'))
    K.box('charge_tower_bearing',-2.50,-.43,1.35,.52,.62,.08,K.mat('f_frame'))
    K.box('charge_tower_upper_bearing',-1.48,-.05,3.66,.28,.66,.10,K.mat('f_frame'))


def _f_shell(K,name,x):
    # Continuous sealed profile: hearth -> bosh -> belly -> stack -> throat.
    profile=[(.18,.43),(.70,.43),(1.20,.67),(1.67,.67),(3.35,.32),(3.70,.29)]
    vertices=[]; faces=[]; seg=32
    for z,r in profile:
        vertices.extend((x+r*math.cos(i*2*math.pi/seg),r*math.sin(i*2*math.pi/seg),z) for i in range(seg))
    for j in range(len(profile)-1):
        for i in range(seg):
            k=(i+1)%seg
            faces.append((j*seg+i,j*seg+k,(j+1)*seg+k,(j+1)*seg+i))
    faces.extend((tuple(reversed(range(seg))),tuple((len(profile)-1)*seg+i for i in range(seg))))
    mesh=bpy.data.meshes.new(name); mesh.from_pydata(vertices,[],faces); mesh.update()
    K.obj(name,mesh,K.mat('f_shell'),smooth=True)
    # Dark iron over the complete furnace shell, from hearth to throat.
    K.cyl(name+'_foundation',x,0,.10,.49,.20,K.mat('f_base'))
    K._fine_mode=True
    for z,r in (profile[1],profile[2],profile[3],profile[4]):
        K.washer(name+'_joint',(x,0,z),(0,0,1),r-.006,r+.012,.025,K.mat('f_zinc'))
    # Hot-blast bustle ring has four connected radial tuyere branches.
    K.washer(name+'_bustle',(x,0,.70),(0,0,1),.52,.65,.16,K.mat('f_zinc'))
    for i in range(4):
        t=i*math.pi/2
        K.dircyl(name+'_tuyere'+str(i),(x+.41*math.cos(t),.41*math.sin(t),.70),(x+.59*math.cos(t),.59*math.sin(t),.70),.055,K.mat('f_zinc'))
    K._fine_mode=False


def _f_line(K,idx,level):
    x=idx*(2.50 if level==3 else 3.20); n='line'+str(idx)
    _f_shell(K,n+'_vessel',x)
    # Four raking columns have individual foundation blocks and crown bearings.
    for sx in (-1,1):
        for sy in (-1,1):
            foot=(x+sx*.91,sy*.80,.24); head=(x+sx*.50,sy*.48,3.92)
            K.box(n+'_foot',foot[0],foot[1],.12,.36,.36,.24,K.mat('f_base'))
            K.dirbox(n+'_column',foot,head,.105,.13,K.mat('f_frame'))
    # Back-face bracing leaves the main shell legible from the production camera.
    for z0,z1,w0,w1,y0,y1 in ((.35,1.80,.89,.73,.79,.67),(1.80,3.88,.73,.50,.67,.48)):
        K.dirbox(n+'_brace',(x-w0,y0,z0),(x+w1,y1,z1),.055,.065,K.mat('f_frame'))
    _f_deck(K,n+'_crown',x,0,3.95,1.24,1.16,gate=True)
    K.box(n+'_ladder_landing',x-.32,.79,3.91,.30,.46,.08,K.mat('f_zinc'))
    K.box(n+'_landing_crossbeam',x,.515,3.55,1.12,.09,.10,K.mat('f_frame'))
    K._fine_mode=True
    for side in (-1,1):
        _f_rail(K,n+'_landing_side',(x-.32+side*.15,.60,3.95),(x-.32+side*.15,1.02,3.95))
    K._fine_mode=False
    for sx in (-.47,-.17):
        K.dirbox(n+'_landing_bracket',(x+sx,.49,3.55),(x+sx,.96,3.88),.045,.05,K.mat('f_frame'))
    K.box(n+'_charging_lock',x,0,4.15,.56,.60,.40,K.mat('f_sheet'))
    K.box(n+'_lock_cap',x,0,4.37,.64,.66,.065,K.mat('f_zinc'))
    # L2/L3 add a real access platform, with a circular opening around the shell.
    if level>=2:
        K.washer(n+'_access',(x,0,2.45),(0,0,1),.50,.86,.065,K.mat('f_zinc'))
        K._fine_mode=True
        for i in range(12):
            t=2*math.pi*i/12
            a=(x+.83*math.cos(t),.83*math.sin(t),2.49)
            b=(x+.83*math.cos(t+math.pi/6),.83*math.sin(t+math.pi/6),2.49)
            # Deliberate access gap at the back ladder.
            if i!=3: _f_rail(K,n+'_midrail',a,b,h=.20)
        K._fine_mode=False
        for s in (-1,1):
            K.box(n+'_platform_bearing',x,s*.64,2.39,1.42,.09,.10,K.mat('f_frame'))
    K._fine_mode=True
    # Outside shell and frame, clear of off-gas piping; the landing bridges to crown.
    K.ladder(n+'_ladder',x-.32,1.04,.20,3.96,face='+Y',w=.22,rung=.24,mat=K.mat('f_ochre'))
    K._fine_mode=False
    # Closed off-gas route. A separate stove flue is the only atmospheric stack.
    gx=x+1.25; gy=1.24 if level==3 and idx==0 else .95
    K.pipe_run(n+'_uptake',[(x,.22,3.64),(x,gy,3.64),(gx,gy,3.64),(gx,gy,2.37)],.14,mat=K.mat('f_zinc'),bend=.25)
    K.cyl(n+'_dust_body',gx,gy,2.08,.27,.68,K.mat('f_zinc'))
    K.cone(n+'_dust_hopper',gx,gy,1.52,.10,.27,.44,K.mat('f_steel'))
    if level==3:
        # Explicit joints: Freestyle cannot infer the intersection of two solids.
        K._fine_mode=True
        K.washer(n+'_uptake_collar',(gx,gy,2.435),(0,0,1),.138,.19,.035,K.mat('f_frame'))
        K.washer(n+'_hopper_joint',(gx,gy,1.74),(0,0,1),.255,.282,.022,K.mat('f_frame'))
        K._fine_mode=False
    for s in (-1,1):
        K.box(n+'_dust_foot',gx+s*.28,gy,.09,.21,.22,.18,K.mat('f_base'))
        K.box(n+'_dust_leg',gx+s*.28,gy,.89,.055,.055,1.6,K.mat('f_frame'))
    _f_shed(K,n+'_cleaning',x+.62,1.47,.70,.62,.75,door=False)
    clean_y=1.67 if gy>1 else 1.47
    K.pipe_run(n+'_gas_clean',[(gx,gy,1.98),(gx,clean_y,1.98),(x+.62,clean_y,1.98),(x+.62,clean_y,.70 if gy>1 else .83)],.09,mat=K.mat('f_zinc'),bend=.16)
    # Three functional hot-blast stove cues, even on the simplified first level.
    for j in range(3):
        sx=x-.13+j*.55; sy=2.20
        K.box(n+'_stove_pad'+str(j),sx,sy,.10,.49,.52,.20,K.mat('f_base'))
        K.cyl(n+'_stove'+str(j),sx,sy,.96,.215,1.52,K.mat('f_steel'))
        K.dome_cap(n+'_stove_lid'+str(j),sx,sy,1.72,.215,.18,K.mat('f_steel'),rings=4)
        K.cyl(n+'_stove_band'+str(j),sx,sy,.38,.219,.15,K.mat('f_steel'))
        K.pipe_run(n+'_stove_hot'+str(j),[(sx,sy,.80),(sx,1.84,.80)],.06,mat=K.mat('f_zinc'),bend=.1)
        K.pipe_run(n+'_stove_gas'+str(j),[(sx,sy,1.10),(sx,2.57,1.10)],.038,mat=K.mat('f_frame'),bend=.08)
    K.pipe_run(n+'_hot_main',[(x+1.0,1.84,.80),(x,1.84,.80),(x,.59,.70)],.09,mat=K.mat('f_zinc'),bend=.12)
    K.pipe_run(n+'_gas_return',[(x+.62,1.47,.65),(x-.48,1.47,.65),(x-.48,2.57,.65),(x-.48,2.57,1.10),(x+.97,2.57,1.10)],.045,mat=K.mat('f_frame'),bend=.10)
    K.box(n+'_flue_base',x+1.24,2.53,.09,.35,.35,.18,K.mat('f_base'))
    K.cyl(n+'_flue',x+1.24,2.53,1.72,.105,3.08,K.mat('f_zinc'))
    K.cyl(n+'_flue_dark',x+1.24,2.53,3.267,.099,.012,K.mat('ink_black'))
    K.washer(n+'_flue_rim',(x+1.24,2.53,3.28),(0,0,1),.10,.12,.045,K.mat('f_zinc'))
    K.cyl(n+'_flue_band',x+1.24,2.53,2.91,.108,.30,K.mat('f_steel'))
    # Exhaust header is separate from the cleaned blast-furnace gas recovery line.
    for j in range(3):
        sx=x-.13+j*.55
        K.pipe_run(n+'_stove_exhaust'+str(j),[(sx,2.20,.36),(sx,2.82,.36)],.055,mat=K.mat('f_zinc'),bend=.10)
    K.pipe_run(n+'_flue_header',[(x-.13,2.82,.36),(x+1.24,2.82,.36),(x+1.24,2.53,.36)],.07,mat=K.mat('f_zinc'),bend=.10)
    # Casting bay connects to the actual hearth. Tracks terminate inside the bay.
    if level<3:
        _f_shed(K,n+'_casthouse',x,-1.26,2.20,1.02,1.02)
    if level==2:
        # Clerestory and extended service bay establish the fuller A frontage.
        _f_shed(K,n+'_casting_service',x-.0,-.97,1.40,.42,1.37,door=False)
    K.box(n+'_tap_runner',x,-.64,.38,.17,.62,.12,K.mat('f_oxide'))
    if level>=2:
        for s in (-1,1):
            K.box(n+'_rail'+str(s),x+s*.22,-1.80,.08,.035,1.55,.045,K.mat('f_frame'))
        for j in range(6):
            K.box(n+'_sleeper'+str(j),x,-2.48+j*.24,.035,.65,.075,.055,K.mat('f_base'))
        K.box(n+'_wagon',x,-2.04,.25,.48,.63,.10,K.mat('f_frame'))
        for sx in (-1,1):
            for sy in (-1,1):
                K.cyl(n+'_wheel',x+sx*.245,-2.04+sy*.23,.16,.11,.055,K.mat('f_frame'),axis='X',segments=16)
        K.cone(n+'_ladle',x,-2.04,.46,.18,.24,.33,K.mat('f_zinc'))
        K.cyl(n+'_ladle_refractory',x,-2.04,.631,.20,.015,K.mat('f_oxide'))
        K.cyl(n+'_ladle_inside',x,-2.04,.641,.16,.012,K.mat('ink_black'))


def build_furnace(level=1):
    assert level in (1,2,3)
    setup_rig(ortho_scale=11.6,target=(0,0,1))
    fs=bpy.context.scene.view_layers[0].freestyle_settings
    fs.linesets['ink'].linestyle.thickness=1.45
    fs.linesets['ink_fine'].linestyle.thickness=.80
    K=Kit(open_collection('BLDG_furnace'))
    for ls in bpy.context.scene.view_layers[0].freestyle_settings.linesets:
        ls.select_by_face_marks=True; ls.face_mark_negation='EXCLUSIVE'; ls.face_mark_condition='ONE'
    for idx in range(2 if level==3 else 1):
        _f_line(K,idx,level)
    # Supported inclined charging route, always present; no missing process at L1.
    _f_shed(K,'stockhouse',-2.02,-.28,1.20,1.12,.65 if level==3 else .95)
    if level==3:
        _f_shed(K,'shared_casthouse',1.25,-1.26,4.70,1.02,1.02,bays=(0,2.50))
        _f_two_stage_lift(K)
        for x in (0,2.50):
            K.box('shared_roof_vent',x,-1.26,1.47,.32,.28,.18,K.mat('f_roof'))
    else:
        a=Vector((-2.02,-.28,1.12)); b=Vector((0,0,4.15))
        K.dirbox('charge_conveyor',a,b,.38,.30,K.mat('f_zinc'))
        K._fine_mode=True
        for j in (1,2):
            p=a.lerp(b,j/3)
            for s in (-1,1):
                K.box('charge_foot',p.x,p.y+s*.27,.08,.25,.25,.16,K.mat('f_base'))
                K.dirbox('charge_leg',(p.x,p.y+s*.27,.16),(p.x,p.y+s*.27,p.z-.17),.065,.07,K.mat('f_frame'))
            K.dirbox('charge_bearing',(p.x,p.y-.28,p.z-.17),(p.x,p.y+.28,p.z-.17),.08,.09,K.mat('f_frame'))
            K.dirbox('charge_brace',(p.x,p.y-.27,.20),(p.x,p.y+.27,p.z-.20),.045,.05,K.mat('f_frame'))
        for j in range(1,7):
            p=a.lerp(b,j/7)
            K.dirbox('charge_seam',(p.x,p.y-.20,p.z+.16),(p.x,p.y+.20,p.z+.16),.015,.015,K.mat('f_frame'))
        K._fine_mode=False
    if level==2:
        annex_y=1.02
        _f_shed(K,'handling_annex',-2.08,annex_y,1.28,1.25,2.55,door=False)
        for z in ((1.02,) if level==3 else (1.02,2.12)):
            K.window('annex_strip','-Y',(-2.08,annex_y-.635,z),.82,.19,cols=3,rows=1,sill=False)
        if level<3:
            K.dirbox('stock_transfer',(-2.08,.43,2.1),(-2.02,.08,1.12),.27,.26,K.mat('f_zinc'))
        K.box('annex_loading_door',-2.73,annex_y-.02,.52,.035,.58,.86,K.mat('door'))
    if level==3:
        # Supported distribution gallery delivers to two independent charging locks.
        K.conveyor_bridge('burden_distribution',(.02,.0,4.20),(2.48,.0,4.20),w=.34,h=.30,ribs=5)
        for x in (.52,1.98):
            K.box('gallery_bearing',x,0,4.01,.18,.48,.14,K.mat('f_frame'))
        _f_brick_courses(K)
    # Graphic reflection bands remain legible in both the print and vertex-colour
    # GLB; actual shader specular alone would disappear in the game's renderer.
    for ob in K.col.objects:
        if ob.type=='MESH' and len(ob.data.materials)==1 and ob.data.materials[0]==K.mat('f_zinc'):
            K.gloss(ob,dark=.24,light=1.45,dark_from=.35,glint=(-.88,-.60))
        elif ob.type=='MESH' and len(ob.data.materials)==1 and ob.data.materials[0]==K.mat('f_steel'):
            # Strong reflected dark band and narrow bright strip, printed without
            # extra outlines. The dome and casing share one steel material family.
            K.gloss(ob,dark=.15,light=2.20,dark_from=.35,glint=(-.88,-.60))
    bpy.context.view_layer.update()
    pts=[o.matrix_world@v.co for o in K.col.objects if o.type=='MESH' for v in o.data.vertices]
    u=[(v.x+v.y)/math.sqrt(2) for v in pts]; z=[(2*v.z-v.x+v.y)/math.sqrt(6) for v in pts]
    uc,zc=(min(u)+max(u))/2,(min(z)+max(z))/2
    target=Vector((uc/math.sqrt(2),uc/math.sqrt(2),zc*math.sqrt(6)/2))
    bpy.context.scene.camera.location=target+Vector((1,-1,1)).normalized()*26
    warnings=[w for w in K.validate(ground=-.01) if not w.startswith('bbox world')]
    assert not warnings, warnings
    return dict(level=level,objects=len(K.col.objects),furnace_lines=2 if level==3 else 1,
                style='A layout / dark iron furnaces, polished steel stoves, brick and silver / B twin L3',warnings=warnings)
