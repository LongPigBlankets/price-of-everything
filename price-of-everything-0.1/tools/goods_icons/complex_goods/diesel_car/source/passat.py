"""Fresh B5.5-inspired sedan body. No geometry from the rejected car cage.

D = retained tyre diameter .86. Body curves sampled from the owner's supplied
Passat sedan profile; axle spacing sets the common scale. Actual dimensions are
measured from the mesh and written to metrics.json.
Owner: rebuild from scratch; target 2004 Passat sedan; retain wheel/can construction.
"""
import bmesh
from mathutils import Vector

def build_diesel_car():
    setup_icon_rig();col=open_collection('ICON_diesel_car');K=Kit(col)
    body=toon_mat('tn_passat_body',(.23,.32,.37))
    dark=toon_mat('tn_passat_dark',(.17,.24,.29))
    silver=toon_mat('tn_passat_silver',(.52,.58,.62))
    navy=K.mat('ic_navy')
    lens=toon_mat('tn_passat_lens',(.73,.84,.88),steps=((.66,.9),(.92,.9),(9,.9)))
    white=toon_mat('tn_passat_white',(.94,.96,.96),steps=((.66,1),(.92,1),(9,1)))
    grille=toon_mat('tn_passat_grille',(.04,.065,.095),steps=((.66,.65),(.92,.65),(9,.65)))
    plate=toon_mat('tn_passat_plate',(.52,.58,.62),steps=((.66,.85),(.92,.85),(9,.85)))
    red=toon_mat('tn_passat_tail',(.37,.035,.055))
    amber=toon_mat('tn_passat_amber',(.85,.26,.065))
    def mesh(name,vs,fs,mat,ink=False):
        me=bpy.data.meshes.new(name);me.from_pydata(vs,[],fs);me.update()
        bm=bmesh.new();bm.from_mesh(me);bmesh.ops.recalc_face_normals(bm,faces=bm.faces);bm.to_mesh(me);bm.free()
        ob=K.obj(name,me,mat,True)
        for f in me.polygons:f.use_smooth=True
        if not ink:noink(ob)
        return ob
    def cat(points,steps=8):
        pts=[Vector(p) for p in points];out=[]
        for i in range(len(pts)-1):
            a=pts[max(0,i-1)];b=pts[i];c=pts[i+1];d=pts[min(len(pts)-1,i+2)]
            for j in range(steps):
                t=j/steps;out.append(.5*(2*b+(-a+c)*t+(2*a-5*b+4*c-d)*t*t+(-a+3*b-3*c+d)*t*t*t))
        return out+[pts[-1]]
    # Distinct bonnet, straight windscreen rake, roof crown, and upright cargo tail.
    # y, half width, belt height, top width, roof-edge height, crown height
    # Owner's supplied profile, manually sampled in image pixels. The two axle
    # centres establish a common scale, so the traced roof curvature is not guessed.
    profile_scale=3.69/(1390-325)
    def trace(px,py):return (-1.40+(px-325)*profile_scale,(710-py)*profile_scale)
    profile_trace=[(60,413),(100,409),(180,392),(300,372),(430,354),(482,341),
                   (545,300),(625,254),(704,225),(800,204),(905,191),(1020,187),
                   (1130,194),(1230,213),(1320,245),(1400,279),(1490,313),
                   (1580,319),(1660,327),(1687,347),(1700,392)]
    sections=[]
    for px,py in profile_trace:
        y,crown=trace(px,py)
        belt=1.23 if y<2.70 else 1.20-(y-2.70)*.07
        belt=min(belt,crown-.095)
        width=1.19-.075*(abs(y-.5)/3.3)**3
        cabin=max(0,min(1,(crown-1.28)/.42))
        rw=1.00-.11*cabin
        edge=crown-(.060 if cabin>.5 else (.030 if px<=60 else .043 if px<=100 else .085))
        sections.append((y,width,belt,rw,edge,crown))
    # Nose and rear termination are lower rounded shoulders below the traced decks.
    sections.insert(0,(-2.52,1.13,.92,.98,.99,1.02))
    sections.append((3.43,1.01,.92,.87,.99,1.06))
    def nose_round(x,z):
        # Rounded plan AND vertical section: bumper centre forward, bonnet lip and
        # lower apron recede. Shared by side rings and front grid for exact joins.
        a=abs(x)
        # Upright fascia below the bonnet lip, turning continuously into the wings.
        # The circular outer section reaches a side-facing tangent at the shoulder.
        plan=.012*(a/.33)**2 if a<=.33 else .012+.86-math.sqrt(max(.00001,.86**2-(min(a,1.189)-.33)**2))
        return plan + .06*((z-.70)/.65)**2
    def tail_round(x,z):return .15*(abs(x)/1.19)**4+.04*((z-.70)/.48)**2
    dense=cat(sections,7);vs=[];rings=[]
    for y,w,belt,rw,edge,crown in dense:
        rear_t=max(0,min(1,(y-2.60)/.83));rear_t=rear_t*rear_t*(3-2*rear_t)
        front_t=max(0,min(1,(-1.90-y)/.62))
        bottom=.23+.20*rear_t+.035*front_t
        # Pronounced shoulder separates door skin from narrower glasshouse.
        profile=[(0,bottom),(.80*w,bottom),(.94*w,bottom+.045),(.985*w,max(.36,bottom+.10)),
                 (w,.72),(.998*w,belt-.12),(.985*w,belt-.025),(.960*w,belt+.006),
                 (rw+.035,max(belt+.010,edge-.045)),(rw,edge),(.72*rw,crown-.010),(0,crown)]
        # Convex quadratic corner rounds avoid Catmull overshoot/horns where the
        # steep glasshouse meets the shallow roof crown.
        pp=[Vector(p) for p in profile];half=[pp[0]]
        for k in range(1,len(pp)-1):
            a=pp[k].lerp(pp[k-1],.32);b=pp[k].lerp(pp[k+1],.32)
            last=half[-1]
            for j in range(1,6):half.append(last.lerp(a,j/5))
            for j in range(1,7):
                t=j/6;half.append((1-t)**2*a+2*t*(1-t)*pp[k]+t*t*b)
        last=half[-1]
        for j in range(1,7):half.append(last.lerp(pp[-1],j/6))
        full=half+ [Vector((-p.x,p.y)) for p in reversed(half[1:-1])]
        ring=[]
        for x,z in full:
            # Nose wraps around the lamp ends; rear bumper also has rounded corners.
            nose=max(0,min(1,(-1.62-y)/.9));tail=max(0,min(1,(y-2.75)/.68))
            yy=y+nose_round(x,z)*nose-tail_round(x,z)*tail
            ring.append(len(vs));vs.append((x,yy,z))
        rings.append(ring)
    fs=[];N=len(rings[0])
    for a,b in zip(rings,rings[1:]):
        for i in range(N):j=(i+1)%N;fs.append((a[i],a[j],b[j],b[i]))
    # Curved end skins need a surface grid. A single non-planar n-gon produces
    # arbitrary diagonal triangulation and tears surface-mounted lamps/plates.
    for endpoint,yy in ((0,-2.52),(-1,3.43)):
        boundary=rings[endpoint];cz=.53 if endpoint==0 else .72;center=Vector((0,yy+(nose_round(0,cz) if endpoint==0 else -tail_round(0,cz)),cz));prev=None;center_id=len(vs);vs.append(tuple(center))
        for j in range(1,29):
            current=[]
            for idx in boundary:
                q=center.lerp(Vector(vs[idx]),j/28)
                if endpoint==0:q.y=yy+nose_round(q.x,q.z)
                else:q.y=yy-tail_round(q.x,q.z)
                if j==28:current.append(idx)
                else:current.append(len(vs));vs.append(tuple(q))
            for i in range(N):
                k=(i+1)%N
                if prev is None:fs.append((center_id,current[k],current[i]))
                else:fs.append((prev[i],prev[k],current[k],current[i]))
            prev=current
    shell=mesh('passat_new_continuous_body',vs,fs,body)
    # Real arch openings, retaining the previous wheel mesh design.
    helpers=bpy.data.collections.new('PASSAT_CONSTRUCTION');bpy.context.scene.collection.children.link(helpers)
    axles=(-1.40,2.29);R=.43
    for i,y in enumerate(axles):
        cutter=noink(K.cyl('arch_tool_'+str(i),0,y,R,.452,3.2,body,axis='X',segments=96,smooth=True))
        col.objects.unlink(cutter);helpers.objects.link(cutter);cutter.hide_render=True
        mod=shell.modifiers.new('wheel_arch_'+str(i),'BOOLEAN');mod.operation='DIFFERENCE';mod.solver='EXACT';mod.object=cutter
    bpy.context.view_layer.update();ev=shell.evaluated_get(bpy.context.evaluated_depsgraph_get())
    def project(q,axis,offset=.018):
        if axis=='FRONT':q=(q[0],q[1]*.84)
        if axis=='Z':origin=Vector((q[0],q[1],4));direction=Vector((0,0,-1))
        elif axis=='X':origin=Vector((3,q[0],q[1]));direction=Vector((-1,0,0))
        elif axis=='BACK':origin=Vector((q[0],5,q[1]));direction=Vector((0,-1,0))
        else:origin=Vector((q[0],-5,q[1]));direction=Vector((0,1,0))
        hit,loc,normal,index=ev.ray_cast(origin,direction)
        assert hit,('surface miss',axis,tuple(q))
        return loc-direction*offset
    def outline(points,rounding=.08):
        pts=[Vector(p) for p in points];edge=[]
        for i,p in enumerate(pts):
            a=p+(pts[i-1]-p)*rounding;b=p+(pts[(i+1)%len(pts)]-p)*rounding
            for j in range(8):
                t=j/8;edge.append((1-t)**2*a+2*t*(1-t)*p+t*t*b)
        if rounding==0:edge=pts
        dense=[]
        for a,b in zip(edge,edge[1:]+edge[:1]):
            n=max(1,int((b-a).length/.025)+1)
            for k in range(n):dense.append(a+(b-a)*k/n)
        return dense
    def patch(name,points,axis,mat,rounding=.08,border=0,offset=.018):
        edge=outline(points,rounding);center=sum(edge,Vector((0,0)))/len(edge)
        vs=[project(center,axis,offset)];fs=[];N=len(edge);bands=36
        for j in range(1,bands+1):
            for p in edge:vs.append(project(center.lerp(p,j/bands),axis,offset))
        for i in range(N):fs.append((0,1+i,1+(i+1)%N))
        for j in range(bands-1):
            for i in range(N):
                a=1+j*N+i;b=1+j*N+(i+1)%N;fs.append((a,b,b+N,a+N))
        ob=mesh(name,vs,fs,mat)
        if border:noink(K.sweep(name+'_border',[project(p,axis,offset+.004) for p in edge+edge[:1]],border,navy,seg=8))
        return ob
    def line(name,points,axis,mat=navy,r=.008):
        path=[]
        for a,b in zip(points,points[1:]):
            a=Vector(a);b=Vector(b);n=max(2,int((a-b).length/.025))
            for i in range(n):path.append(project(a.lerp(b,i/n),axis,.025))
        path.append(project(points[-1],axis,.025));noink(K.sweep(name,path,r,mat,seg=8))
    # Glazing follows the same photographed profile curves, including its arched
    # upper side-window boundary and nearly level belt line.
    def traced(points):return [trace(x,y) for x,y in points]
    # Owner: rounded OUT toward the hood, as in the original goods icon.
    # Sample the full cowl arc; corner rounding alone leaves a straight bottom.
    windscreen_cowl=[(x,-.82-.28*(1-(x/.965)**2))
                     for x in (-.965+1.93*i/64 for i in range(65))]
    windscreen_points=windscreen_cowl+[(.78,.23),(.72,.285),(0,.315),(-.72,.285),(-.78,.23)]
    patch('windscreen',windscreen_points,'Z',navy,.035)
    windscreen_cowl_corner=min(outline(windscreen_points,.035),key=lambda p:(p-Vector((.965,-.82))).length)
    patch('front_door_glass',traced([(531,367),(932,351),(941,222),(835,228),(750,248),(660,289)]),'X',navy,.12)
    patch('rear_door_glass',traced([(966,349),(1255,337),(1230,257),(1120,233),(966,221)]),'X',navy,.12)
    patch('quarter_glass',traced([(1290,337),(1380,334),(1371,302),(1280,267)]),'X',navy,.17)
    patch('rear_windscreen',[(-.79,1.86),(.79,1.86),(.85,2.60),(-.85,2.60)],'Z',navy,.10)
    line('boot_lid_seam',[(-.85,2.81),(-.83,3.20),(.83,3.20),(.85,2.81)],'Z',navy,.008)
    line('front_door_seam',traced([(511,376),(507,460),(511,579),(928,579),(943,357)]),'X')
    line('rear_door_seam',traced([(928,579),(1230,579),(1260,461),(1265,350)]),'X')
    line('belt_trim',traced([(520,396),(960,382),(1280,369),(1620,388)]),'X',silver,.009)
    line('door_rub_strip',traced([(513,516),(940,509),(1240,507)]),'X',navy,.019)
    for i,(px,py) in enumerate(((878,414),(1240,402))):
        y,z=trace(px,py)
        patch('handle_'+str(i),[(y-.12,z+.03),(y+.12,z+.03),(y+.12,z-.025),(y-.12,z-.025)],'X',navy,.25)
    # Owner: map the goods icon's dipping lamp sill and lifted wheelward ends.
    # These cubic controls are sampled from g_056_ice_car.png at native1972×1661.
    # One canonical near-side projection supplies coordinates to both mirrored lamps.
    def bezier_path(start,segments):
        out=[];a=Vector(start)
        for b,c,d in segments:
            b=Vector(b);c=Vector(c);d=Vector(d)
            for j in range(16):
                t=j/16;out.append((1-t)**3*a+3*(1-t)**2*t*b+3*(1-t)*t*t*c+t**3*d)
            a=d
        return out
    lamp_top=[((476,1090),(491,1095),(510,1098)),((542,1102),(579,1107),(608,1109))]
    lamp_outer=[((632,1110),(650,1128),(662,1165)),((635,1175),(601,1184),(575,1185))]
    lamp_bottom=[((530,1188),(470,1173),(434,1162)),((445,1138),(455,1115),(466,1100))]
    white_edge=bezier_path((466,1100),lamp_top+[((596,1130),(584,1161),(575,1185))]+lamp_bottom)
    amber_edge=bezier_path((608,1109),lamp_outer+[((584,1161),(596,1130),(608,1109))])
    full_edge=bezier_path((466,1100),lamp_top+lamp_outer+lamp_bottom)
    right=Vector((1,1,0)).normalized();up=Vector((-1,1,2)).normalized()
    near_U=Vector((.815,.580,0));near_V=Vector((-.255,.359,.898));near_N=Vector((.521,-.732,.440)).normalized()
    reference_scale=.00310
    def screen(p):return Vector((p.dot(right),p.dot(up)))
    reference_center=Vector((536,1140))
    def ref_delta(p):return Vector(((p[0]-536)*reference_scale,(1140-p[1])*reference_scale))
    su,sv,sn=screen(near_U),screen(near_V),screen(near_N)
    det=su.x*sv.y-su.y*sv.x
    def reference_uv(p):
        target=ref_delta(p);u=v=0
        for _ in range(8):
            q=target-sn*(-.34*u*u)
            u=(q.x*sv.y-q.y*sv.x)/det;v=(su.x*q.y-su.y*q.x)/det
        return Vector((u,v))
    hit,near_center,_,_=ev.ray_cast(Vector((.82,-5,.80)),Vector((0,1,0)));assert hit
    # The radiator opening shares the reference's brow alignment with the lamps.
    grille_edge=bezier_path((187,942),[
        ((256,1004),(354,1060),(436,1093)),
        ((422,1118),(405,1146),(391,1152)),
        ((382,1159),(375,1156),(362,1151)),
        ((301,1124),(232,1085),(192,1053)),
        ((179,1042),(174,1036),(176,1020)),
        ((176,997),(182,963),(187,942))])
    radiator=toon_mat('tn_passat_radiator',(.070,.110,.150),steps=((.66,.65),(.92,.65),(9,.65)))
    # Align the top outer corners to the actual lamp brows. The old high rounded
    # corners made the connector drop diagonally and attach short of the border.
    grille_shape=[(-.54,1.0714),(-.27,1.067),(0,1.065),(.27,1.067),(.54,1.0714),
                  (.455,.85),(.39,.812),(.30,.81),(-.30,.81),(-.39,.812),(-.455,.85)]
    patch('grille',grille_shape,'FRONT',radiator,.035,.010)
    grille_upper_join=min(outline(grille_shape,.035),key=lambda p:(p-Vector((.54,1.0714))).length)
    headlamp_cutters=[]
    hood_lamp_points={}
    def headlight(side):
        # Fit the canonical near contour to the actual shell; mirror these 3D
        # surface points, not an independent tilted carrier. The far side therefore
        # disappears naturally when its corner normals turn away from the viewer.
        samples={};view=Vector((1,-1,1)).normalized()
        def body_sample(u,v):
            key=(round(u,8),round(v,8))
            if key not in samples:
                probe=near_center+near_U*u+near_V*v+near_N*(-.34*u*u)
                hit,p,n,index=ev.ray_cast(probe+view*4,-view)
                assert hit,('lamp misses body',u,v)
                p.x*=side;n.x*=side
                samples[key]=(p,n)
            return samples[key]
        def surface(u,v,depth=0):
            p,n=body_sample(u,v);return p+n*depth
        lift=-.004
        opening=[reference_uv(p) for p in full_edge]
        mid=sum(opening,Vector((0,0)))/len(opening)
        mouth=[mid+(q-mid)*1.03 for q in opening]
        # A shallow closed volume follows LOCAL body normals through the shell.
        # It never clears a camera-facing tunnel through the outer wing.
        count=len(mouth);bands=18;layer_uv=[mid]
        for j in range(1,bands+1):
            layer_uv.extend(mid.lerp(q,j/bands) for q in mouth)
        cap_faces=[]
        for i in range(count):cap_faces.append((0,1+i,1+(i+1)%count))
        for j in range(bands-1):
            for i in range(count):
                a=1+j*count+i;b=1+j*count+(i+1)%count;cap_faces.append((a,b,b+count,a+count))
        layer=len(layer_uv)
        cutvs=[surface(q.x,q.y,d) for d in (-.028,.014) for q in layer_uv]
        cutfaces=[tuple(reversed(f)) for f in cap_faces]+[tuple(i+layer for i in f) for f in cap_faces]
        start=1+(bands-1)*count
        for i in range(count):
            a=start+i;b=start+(i+1)%count;cutfaces.append((a,b,b+layer,a+layer))
        cutter=mesh('lamp_recess_tool_'+str(side),cutvs,cutfaces,body)
        col.objects.unlink(cutter);helpers.objects.link(cutter);cutter.hide_render=True
        headlamp_cutters.append(cutter)
        bezelvs=[];bezelfaces=[];bands=6
        for j in range(bands+1):
            t=j/bands
            for q in opening:
                uv=mid+(q-mid)*(1+.08*t)
                bezelvs.append(surface(uv.x,uv.y,lift*(1-t)+.002*t))
        for j in range(bands):
            for i in range(count):
                k=(i+1)%count;a=j*count+i;b=j*count+k;bezelfaces.append((a,b,b+count,a+count))
        mesh('painted_lamp_bezel_'+str(side),bezelvs,bezelfaces,body)
        def face(name,points,mat,offset=0,border=0):
            edge=outline(points,.12);c=sum(edge,Vector((0,0)))/len(edge)
            vs=[surface(c.x,c.y,lift+offset)];faces=[];count=len(edge);bands=24
            for j in range(1,bands+1):
                for q in edge:
                    q=c.lerp(q,j/bands);vs.append(surface(q.x,q.y,lift+offset))
            for i in range(count):faces.append((0,1+i,1+(i+1)%count))
            for j in range(bands-1):
                for i in range(count):
                    a=1+j*count+i;b=1+j*count+(i+1)%count;faces.append((a,b,b+count,a+count))
            ob=mesh(name+'_'+str(side),vs,faces,mat)
            if border:
                # Ink follows the carrier skin as a ribbon. Raised round strokes
                # occluded the amber lens when viewed across the curved far lamp.
                rimvs=[];rimfaces=[]
                for i,q in enumerate(edge):
                    tangent=(edge[(i+1)%count]-edge[(i-1)%count]).normalized()
                    perp=Vector((-tangent.y,tangent.x))
                    for sign in (-1,1):
                        uv=q+perp*border*sign
                        rimvs.append(surface(uv.x,uv.y,lift+offset+.006))
                for i in range(count):
                    j=(i+1)%count;rimfaces.append((2*i,2*i+1,2*j+1,2*j))
                mesh(name+'_rim_'+str(side),rimvs,rimfaces,navy)
        hood_lamp_points[side]={}
        for name,p in [('inner',(466,1100)),('outer',(608,1109))]:
            uv=reference_uv(p);hood_lamp_points[side][name]=surface(uv.x,uv.y,.005)
        face('headlamp_housing',[reference_uv(p) for p in white_edge],lens,0,.010)
        face('headlamp_amber',[reference_uv(p) for p in amber_edge],amber,.004,.008)
        for i,(px,py,rx,ry,hx,hy,hrx,hry) in enumerate(((493,1126,27,29,506,1122,13,18),(556,1135,25,29,560,1131,11,17))):
            circle=[reference_uv((px+rx*math.cos(k*2*math.pi/64),py+ry*math.sin(k*2*math.pi/64))) for k in range(64)]
            face('headlamp_reflector_'+str(i),circle,dark,.003)
            circle=[reference_uv((hx+hrx*math.cos(k*2*math.pi/64),hy+hry*math.sin(k*2*math.pi/64))) for k in range(64)]
            face('headlamp_glint_'+str(i),circle,white,.006)
    for side in (-1,1):
        def signed(p):return [(side*x,z) for x,z in p]
        headlight(side)
        patch('bumper_rub_'+str(side),signed([(.40,.735),(1.12,.78),(1.12,.685),(.40,.65)]),'FRONT',grille,.12)
        patch('lower_corner_'+str(side),signed([(.58,.53),(1.02,.57),(.99,.33),(.58,.32)]),'FRONT',grille,.18,.008)
    # Owner rejected an inset closed lid: the reference bonnet meets the grille
    # brow and lamp tops, with side seams running back into the cowl. Its two
    # inner strokes describe pressed hood creases, not a separate panel perimeter.
    def fitted_seam(name,controls,r=.008):
        controls=[Vector(p) for p in controls];path=[];view=Vector((1,-1,1)).normalized()
        for q in cat(controls,12):
            query=Vector((q.x*side,q.y,q.z))
            hit,p,n,index=ev.ray_cast(query+view*3,-view)
            assert hit,('hood seam misses body',name,tuple(q))
            p.x*=side;n.x*=side
            path.append(p+n*.014)
        noink(K.sweep(name,path,r,navy,seg=10))
    for side in (-1,1):
        # This joins the existing radiator-top stroke instead of drawing a second
        # parallel line across the front of the bonnet.
        canonical_start=project(grille_upper_join,'FRONT',.022)
        canonical_end=hood_lamp_points[1]['inner']
        join=[Vector((side*p.x,p.y,p.z)) for p in (canonical_start,canonical_end)]
        noink(K.sweep('bonnet_grille_join_'+str(side),join,.009,navy,seg=12))
        outer=hood_lamp_points[side]['outer']
        side_points=[outer]+[project((side*x,y),'Z',.006) for x,y in ((1.04,-1.95),(1.045,-1.55),(1.00,-1.08))]
        side_points.append(project((side*windscreen_cowl_corner.x,windscreen_cowl_corner.y),'Z',.018))
        fitted_seam('bonnet_fender_seam_'+str(side),side_points,.008)
        line('bonnet_pressed_crease_'+str(side),[(side*.48,-2.25),(side*.56,-1.93),(side*.68,-1.42),(side*.83,-1.01)],'Z',navy,.008)
    patch('lower_intake',[(-.50,.54),(.50,.54),(.48,.32),(-.48,.32)],'FRONT',grille,.10,.008)
    patch('number_plate',[(-.29,.77),(.29,.77),(.29,.625),(-.29,.625)],'FRONT',plate,.08,0,.034)
    # Keep the existing steel-wheel construction; place it at the new axle/track dimensions.
    for axle,y in enumerate(axles):
        x=1.075
        noink(K.cyl('tyre_'+str(axle),x,y,R,R,.24,navy,axis='X',segments=64,smooth=True))
        noink(K.cyl('sidewall_'+str(axle),x+.13,y,R,.405,.055,dark,axis='X',segments=64,smooth=True))
        K.cyl('rim_'+str(axle),x+.165,y,R,.255,.030,silver,axis='X',segments=64,smooth=True)
        face=x+.185;bolt_dot(K,'hub_'+str(axle),(face,y,R),'X',.042,navy)
        for k in range(5):
            angle=2*math.pi*k/5+math.radians(18)
            bolt_dot(K,'slot_'+str(axle)+str(k),(face,y+math.cos(angle)*.165,R+math.sin(angle)*.165),'X',.05,navy)
    mirror=K.box('new_door_mirror',1.245,-.48,1.26,.27,.25,.14,body)
    bevel=mirror.modifiers.new('rounded_mirror','BEVEL');bevel.width=.055;bevel.segments=5
    noink(mirror)
    patch('tail_lamp',[(3.12,1.10),(3.23,1.025),(3.30,.76),(3.17,.79)],'X',red,.08,.009)
    # Complete both sides of the rebuilt car, including the retained wheel assemblies.
    # The goods view sees the right side, but front/side inspection must show a whole car.
    from mathutils import Matrix
    bpy.context.view_layer.update()
    reflection=Matrix.Diagonal((-1,1,1,1))
    paired=('tyre_','sidewall_','rim_','hub_','slot_','front_door_','rear_door_',
            'quarter_glass','handle_','belt_trim','door_rub_strip','new_door_mirror','tail_lamp')
    for ob in list(col.objects):
        if ob.type=='MESH' and ob.name.startswith(paired):
            copy=ob.copy();copy.data=ob.data.copy();copy.name='far_'+ob.name
            col.objects.link(copy);copy.matrix_world=reflection@ob.matrix_world
    # Keep tyre/rim surfaces free of body stipple; the mask shader recognizes this
    # object index. This does not alter the wheel palette or exterior contour.
    for ob in col.objects:
        name=ob.name.removeprefix('far_')
        if name.startswith(('tyre_','sidewall_','rim_','hub_','slot_')):ob.pass_index=73
    shell.data.materials.append(navy)
    for i,cutter in enumerate(headlamp_cutters):
        mod=shell.modifiers.new('headlamp_recess_'+str(i),'BOOLEAN');mod.operation='DIFFERENCE';mod.solver='EXACT';mod.object=cutter
    can=build_reference_jerrycan(K,col,origin=(2.03,-1.62,0),yaw_deg=90,D=1.18,prefix='diesel_can')
    bpy.context.view_layer.update()
    coords=[v.co for v in shell.data.vertices]
    dimensions=[max(p[i] for p in coords)-min(p[i] for p in coords) for i in range(3)]
    profile_envelope={}
    for p in coords:
        yy=round(float(p.y),3)
        profile_envelope[yy]=max(profile_envelope.get(yy,-99),float(p.z))
    return {'revision':'windscreen_bow_final','body_dimensions_xyz':dimensions,'wheelbase':3.69,'wheel_diameter':.86,'profile_scale':profile_scale,'profile_reference_points':profile_trace,'roof_curve':[(float(max((vs[i] for i in ring),key=lambda p:p[2])[1]),float(max((vs[i] for i in ring),key=lambda p:p[2])[2])) for ring in rings],'objects':len(col.objects),'third_party_geometry_used':False}
