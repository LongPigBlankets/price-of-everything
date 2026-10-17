"""Six reference-led goods. Units normalised to drum D=1 or named host width.
Owner: crude oil, sand, processed oil, pet coke, graphite, refined REE; review topology in loops.
Original depictions govern: closed/oily vs open/amber drum; six pillow sacks; three fluted
coke chunks; contiguous laminated graphite; five cubes 2+2+1 and a shallow powder dish.
"""
import math,bmesh
from mathutils import Vector
REVISION='v13'

def mesh(K,name,verts,faces,mat,smooth=False,ink=False):
    me=bpy.data.meshes.new(name);me.from_pydata(verts,[],faces);me.update()
    bm=bmesh.new();bm.from_mesh(me);bmesh.ops.remove_doubles(bm,verts=bm.verts[:],dist=.00001);bmesh.ops.recalc_face_normals(bm,faces=bm.faces);bm.to_mesh(me);bm.free()
    ob=K.obj(name,me,mat,smooth)
    if not ink:noink(ob)
    return ob

def stroke(K,name,points,r=.006,mat=None,closed=False):
    pts=list(points)
    if closed:pts.append(pts[0])
    return noink(K.sweep(name,pts,r,mat or K.mat('ic_navy'),seg=10))

def start(name):
    setup_icon_rig();col=open_collection('ICON_'+name);return Kit(col)

def end(K,topology,dimensions):
    bpy.context.view_layer.update()
    return {'revision':REVISION,'topology':topology,'dimensions':dimensions,'objects':len(K.col.objects)}

def lathe(K,name,profile,mat,segments=96,ink=False):
    vs=[(r*math.cos(a*2*math.pi/segments),r*math.sin(a*2*math.pi/segments),z) for r,z in profile for a in range(segments)]
    fs=[]
    for i in range(len(profile)-1):
        for k in range(segments):j=(k+1)%segments;fs.append((i*segments+k,i*segments+j,(i+1)*segments+j,(i+1)*segments+k))
    return mesh(K,name,vs,fs,mat,True,ink)

def ringpath(radius,z,n=128):return [(radius*math.cos(k*2*math.pi/n),radius*math.sin(k*2*math.pi/n),z) for k in range(n)]

def build_drum(name,opened):
    K=start(name);navy=K.mat('ic_navy')
    steel=toon_mat('batch_drum_steel',(.145,.20,.21),steps=((.66,.32),(.835,.60),(9,1)));lid=toon_mat('batch_drum_lid',(.125,.17,.17));edge=toon_mat('batch_drum_edge',(.065,.105,.14))
    H=1.40;R=.50
    # Closed, thick-walled shell: outer wall folds over rim into inner wall and floor.
    shell=lathe(K,'drum_shell',[(0,.018),(.475,.018),(.492,.035),(R,.07),(R,H-.04),(.488,H-.01),(.455,H-.01),(.455,.08),(0,.08)],steel)
    for poly in shell.data.polygons:poly.use_smooth=False
    for label,z,w in [('bottom',.045,.046),('lower',.49,.035),('upper',.965,.035),('top',H-.018,.042)]:
        lathe(K,label+'_rolled_ring',[(.493,z-w/2),(.515,z-w/2),(.521,z),(.515,z+w/2),(.493,z+w/2),(.493,z-w/2)],edge)
        stroke(K,label+'_lower_ink',ringpath(.518,z-w/2),.0065,navy,True)
        stroke(K,label+'_upper_ink',ringpath(.518,z+w/2),.0065,navy,True)
    if opened:
        amber=toon_mat('batch_processed_amber',(.58,.27,.055))
        noink(K.cyl('visible_liquid_surface',0,0,H-.091,.451,.034,amber,axis='Z',segments=128,smooth=True))
        stroke(K,'liquid_edge',ringpath(.451,H-.073),.005,navy,True)
        # Triangle is curved to the cylinder, all vertices and inset fill share mapping.
        def triangle(name,points,mat,offset):
            vs=[];fs=[];N=24
            A,B,C=[Vector(p) for p in points]
            def project(q):
                theta=-math.pi/4+q.x/.502
                return ((.503+offset)*math.cos(theta),(.503+offset)*math.sin(theta),q.y)
            for row in range(N+1):
                for col in range(N-row+1):vs.append(project(A+(B-A)*col/N+(C-A)*row/N))
            starts=[sum(N-r+1 for r in range(row)) for row in range(N+1)]
            for row in range(N):
                for col in range(N-row):
                    a=starts[row]+col;b=a+1;c=starts[row+1]+col
                    fs.append((a,b,c))
                    if col<N-row-1:fs.append((b,c+1,c))
            return mesh(K,name,vs,fs,mat)
        yellow=toon_mat('batch_warning',(.94,.68,.11),steps=((.66,1),(.92,1),(9,1)))
        triangle('warning_border',[(-.155,.575),(.155,.575),(0,.905)],navy,0)
        triangle('warning_yellow',[(-.126,.598),(.126,.598),(0,.865)],yellow,.003)
    else:
        # Lid seals across the bore BELOW the rolled rim; blot rests on that lid.
        z=H-.036;noink(K.cyl('closed_lid',0,0,z-.012,.459,.025,lid,axis='Z',segments=128,smooth=True))
        stroke(K,'lid_seal',ringpath(.46,z),.006,navy,True)
        points=[]
        for k in range(120):
            a=k*2*math.pi/120;r=.27*(1+.18*math.cos(2*a)+.14*math.sin(3*a)+.05*math.cos(5*a))
            points.append((r*math.cos(a),r*.87*math.sin(a)+.024,z+.010))
        oil=toon_mat('batch_black_oil',(.003,.005,.013),steps=((.66,1),(.92,1),(9,1)))
        mesh(K,'oil_blot',[(0,.024,z+.010)]+points,[(0,k+1,(k+1)%120+1) for k in range(120)],oil)
        # Two offset bung sockets visibly belong to the closed top, outside the blot.
        for i,(x,y,r) in enumerate([(-.22,-.24,.061),(.18,.30,.041)]):
            noink(K.cyl('bung_floor_'+str(i),x,y,z+.008,r,.01,navy,axis='Z',segments=48,smooth=True))
            ob=K.washer('bung_collar_'+str(i),(x,y,z+.016),(0,0,1),r*.65,r,.018,edge,seg=48);noink(ob)
            stroke(K,'bung_outline_'+str(i),[(x+r*math.cos(a*2*math.pi/64),y+r*math.sin(a*2*math.pi/64),z+.027) for a in range(64)],.0045,navy,True)
    return end(K,'open shell and recessed amber surface' if opened else 'sealed lid with two bung sockets and surface oil blot',{'diameter':1.042,'height':H,'body_hoops':2,'open':opened})

def build_crude_oil():return build_drum('crude_oil',False)
def build_processed_oil():return build_drum('processed_oil',True)

def build_graphite():
    K=start('graphite');mat=toon_mat('batch_graphite',(.10,.10,.11));navy=K.mat('ic_navy')
    W=1.80;H=1.80;N=38
    # One manifold host block: laminations are continuous fine surface grooves.
    noink(K.box('graphite_solid_block',0,0,H/2,W,W,H,mat))
    for i in range(N):
        z=(i+.5)*H/N
        if i:
            zz=i*H/N
            stroke(K,'front_layer_%02d'%i,[(x,-W/2-.001,zz+.006*math.sin(x*8+i*.63)*math.sin(math.pi*(x/W+.5))) for x in [-W/2+j*W/48 for j in range(49)]],.006 if i%4==0 else .0026,navy)
            stroke(K,'right_layer_%02d'%i,[(W/2+.001,y,zz+.006*math.sin(y*7+i*.57)*math.sin(math.pi*(y/W+.5))) for y in [-W/2+j*W/48 for j in range(49)]],.006 if i%4==0 else .0026,navy)
    stroke(K,'top_front',[(-W/2,-W/2,H),(W/2,-W/2,H),(W/2,W/2,H)],.008,navy)
    stroke(K,'central_corner',[(W/2,-W/2,0),(W/2,-W/2,H)],.008,navy)
    return end(K,'one closed manifold block; solid top; both visible faces have 37 continuous lamination lines',{'width':W,'depth':W,'height':H,'layers':N,'air_gaps':0})

def build_refined_ree():
    K=start('refined_ree');navy=K.mat('ic_navy')
    data=[('base_brown',(-.46,-.38,.45),.90,(.35,.20,.12)),('base_grey',(.45,.32,.45),.90,(.27,.32,.35)),('middle_ochre',(-.37,-.26,1.225),.65,(.67,.39,.09)),('middle_green',(.29,.37,1.225),.65,(.23,.38,.19)),('top_navy',(-.07,.09,1.825),.55,(.05,.055,.115))]
    for name,c,size,color in data:
        mat=toon_mat('batch_'+name,color)
        noink(K.box(name,*c,size,size,size,mat))
        # Canonical cube edges replace Freestyle's unreliable coplanar contact contours.
        for axis in range(3):
            other=[a for a in range(3) if a!=axis]
            for sa in [-1,1]:
                for sb in [-1,1]:
                    pts=[]
                    for sign in [-1,1]:
                        q=list(c);q[axis]+=sign*size/2;q[other[0]]+=sa*size/2;q[other[1]]+=sb*size/2;pts.append(q)
                    stroke(K,name+'_edge_'+str(axis)+str(sa)+str(sb),pts,.011,navy)
    porcelain=toon_mat('batch_powder_porcelain',(.88,.91,.94),steps=((.66,.9),(.92,1),(9,1)))
    white=toon_mat('batch_powder_white',(.94,.94,.91))
    dish=lathe(K,'sample_dish',[(0,.020),(.44,.020),(.475,.045),(.475,.082),(.433,.103),(.407,.065),(0,.055)],porcelain)
    for ob in [dish]:
        for v in ob.data.vertices:v.co+=Vector((.67,-.48,0))
    for z,r in [(.091,.46),(.065,.407)]:stroke(K,'dish_ring_'+str(z),[(x+.67,y-.48,zz) for x,y,zz in ringpath(r,z)],.009,navy,True)
    mound=lathe(K,'powder_mound',[(0,.065),(.345,.065),(.025,.408),(0,.425)],white)
    for v in mound.data.vertices:v.co+=Vector((.67,-.48,0))
    return end(K,'five supported solid cubes in 2+2+1 stack and a separate shallow dish/powder cone',{'base_cube':.9,'middle_cube':.65,'top_cube':.55,'cube_count':5,'dish_radius':.475})

def pillow(K,name,c,rx,ry,h,yaw,mat,tied=0):
    existing=set(K.col.objects);angle=math.radians(yaw);verts=[];faces=[]
    def world(x,y,z):
        if not tied:
            tilt=math.radians(10);d=(x-y)/math.sqrt(2);l=(x+y)/math.sqrt(2)
            dd=d*math.cos(tilt)-z*math.sin(tilt);z=d*math.sin(tilt)+z*math.cos(tilt)
            x=(l+dd)/math.sqrt(2);y=(l-dd)/math.sqrt(2)
        return (c[0]+x*math.cos(angle)-y*math.sin(angle),c[1]+x*math.sin(angle)+y*math.cos(angle),c[2]+z+(0.025 if not tied and name.endswith('_0') else 0))
    if tied:
        # A volume-filled oval sack tapers to a raised gathered neck; no flat perimeter rail.
        count=48;levels=48
        def section(t):
            q=-1.12+2.12*t
            # Long narrow gathered neck, then a round belly and blunt soft inner end.
            keys=[(-1.12,0),(-1.05,.12),(-.88,.19),(-.72,.56),(-.4,.89),(0,1),(.4,.94),(.75,.67),(.94,.32),(1,0)]
            for j in range(len(keys)-1):
                if keys[j][0]<=q<=keys[j+1][0]:
                    dx=keys[j+1][0]-keys[j][0];u=(q-keys[j][0])/dx
                    low=keys[max(0,j-1)];high=keys[min(len(keys)-1,j+2)]
                    m0=(keys[j+1][1]-low[1])/(keys[j+1][0]-low[0]);m1=(high[1]-keys[j][1])/(high[0]-keys[j][0])
                    rr=max(0,(2*u**3-3*u*u+1)*keys[j][1]+(u**3-2*u*u+u)*dx*m0+(-2*u**3+3*u*u)*keys[j+1][1]+(u**3-u*u)*dx*m1);break
            z=.08*max(0,-q)**2-.045*max(0,q)**2
            return q,rr,z
        def surf(t,ang,offset=0):
            q,rr,z=section(t)
            return world(q*rx*(-tied),(ry*rr+offset)*math.cos(ang),z+(h/2*rr+offset)*math.sin(ang))
        for j in range(levels+1):
            for k in range(count):verts.append(surf(j/levels,k*2*math.pi/count))
        for j in range(levels):
            for k in range(count):kn=(k+1)%count;faces.append((j*count+k,j*count+kn,(j+1)*count+kn,(j+1)*count+k))
        mesh(K,name,verts,faces,mat,True)
        # Three pleated folds lead into an actual tied neck, never around the whole belly.
        for j,ang in enumerate((.55,1.6,2.65)):
            stroke(K,name+'_gather_fold_'+str(j),[surf(.09+t*.19,ang+.12*math.sin(t*math.pi),.004) for t in [i/16 for i in range(17)]],.0048)
        q,rr,z=section(.08);neckx=q*rx*(-tied)
        stroke(K,name+'_binding',[world(neckx,(ry*rr+.009)*math.cos(t*2*math.pi/48),z+(h/2*rr+.009)*math.sin(t*2*math.pi/48)) for t in range(49)],.009)
        # A soft fan of gathered fabric beyond the binding, built as two-sided cloth.
        fanv=[];fanf=[];N=20
        for j in range(5):
            t=j/4
            for k in range(N+1):
                v=-1+2*k/N;x=neckx+t*.17*tied
                yy=v*(.048+.105*t);zz=z+.015+.04*t+.014*math.cos(v*3*math.pi)*t
                fanv.append(world(x,yy,zz))
        for j in range(4):
            for k in range(N):a=j*(N+1)+k;fanf.append((a,a+1,a+N+2,a+N+1))
        mesh(K,name+'_cloth_fan',fanv,fanf,mat,True)
        for sg in [-1,1]:
            stroke(K,name+'_cord_tail_'+str(sg),[world(neckx,sg*.05,z+.04),world(neckx+.07*tied,sg*.11,z+.015),world(neckx+.13*tied,sg*.15,z-.055)],.006)
    else:
        # Four pinched corners extend beyond the bowed-in edges of the stuffed pillow.
        N=32
        for side in [1,-1]:
            for j in range(N+1):
                v=-1+2*j/N
                for i in range(N+1):
                    u=-1+2*i/N;x=rx*u*(.84+.16*v*v);y=ry*v*(.84+.16*u*u)
                    z=side*h/2*max(0,(1-u*u)*(1-v*v))**.43-.035*u*u*v*v
                    verts.append(world(x,y,z))
        stride=(N+1)**2
        for side in range(2):
            for j in range(N):
                for i in range(N):
                    a=side*stride+j*(N+1)+i;face=(a,a+1,a+N+2,a+N+1);faces.append(face if side==0 else face[::-1])
        mesh(K,name,verts,faces,mat,True)
    label=1+sum(ob.get('sack_root',False) for ob in existing)
    bpy.data.objects[name]['sack_root']=True
    for ob in set(K.col.objects)-existing:ob['part_label']=label

def build_sand():
    K=start('sand');sand=toon_mat('batch_sand',(.80,.52,.245),steps=((.66,.44),(.92,.78),(9,1)));sack=toon_mat('batch_sack',(.49,.38,.20))
    seg=96;levels=48;verts=[];faces=[]
    # Broad elliptical pile, with depth contained behind the foreground sacks.
    for j in range(levels+1):
        t=j/levels;r=(1-t)**.70
        for k in range(seg):
            a=k*2*math.pi/seg;rr=r*(1+.045*math.sin(3*a+.4)+.025*math.cos(5*a))
            lateral=rr*1.55*math.cos(a)-.055*t
            cap=.68+.32*min(1,t/.22);lateral=max(-cap,min(cap,lateral))
            depth=rr*.62*math.sin(a)-.12
            depth=max(-.42,min(.22+.35*t,depth))
            depth+=.40*r*max(0,math.sin(a))**2*math.exp(-((lateral-.12-.10*math.sin(t*math.pi))/.22)**2)
            z=.035+1.87*t+.028*r*math.sin(a*3+t*3)
            verts.append(((lateral+depth)/math.sqrt(2),(lateral-depth)/math.sqrt(2),z))
    for j in range(levels):
        for k in range(seg):n=(k+1)%seg;a=j*seg+k;faces.append((a,j*seg+n,(j+1)*seg+n,a+seg))
    faces.append(tuple(reversed(range(seg))));mesh(K,'central_sand_heap',verts,faces,sand,True)['part_label']=7
    for level,z in enumerate((.28,.69)):
        pillow(K,'left_sack_'+str(level),(-.39,-.63,z),.62,.40,.48 if level==0 else .64,12,sack,-1)
        pillow(K,'right_sack_'+str(level),(.63,.39,z),.62,.40,.48 if level==0 else .64,78,sack,1)
        pillow(K,'front_sack_'+str(level),(.56,-.56,z-.005),.49,.49,.52 if level==0 else .72,0,sack)
    return end(K,'broad heap behind six rounded sacks; gathered necks, cloth fans and pinched front pillows',{'heap_height':1.905,'sacks':6,'sack_layers':2})

def fluted_chunk(K,name,p0,p1,r,mat,phase=0):
    existing=set(K.col.objects);a=Vector(p0);b=Vector(p1);axis=(b-a).normalized();u=axis.cross(Vector((0,0,1))).normalized();v=axis.cross(u).normalized()
    n=64;sections=[(0,.50),(.035,.74),(.09,.90),(.20,1.03),(.40,1.08),(.62,1.05),(.81,.96),(.94,.83),(1,.56)];verts=[]
    def point(t,scale,k):
        ang=k*2*math.pi/n;twist=.06*math.sin(t*math.pi*1.5+phase)
        # Rounded longitudinal ridges with unequal widths/depths and an uneven centreline.
        rr=r*scale*(1+.09*math.sin(3*ang+phase)-.18*math.cos(6*ang+twist)+.035*math.cos(9*ang+phase))
        return a.lerp(b,t)+u*(rr*math.cos(ang)+.05*math.sin(t*math.pi)*math.sin(phase))+v*(rr*.82*math.sin(ang)+.025*math.sin(t*math.pi*2+phase))
    for t,scale in sections:
        for k in range(n):verts.append(tuple(point(t,scale,k)))
    faces=[tuple(reversed(range(n))),tuple((len(sections)-1)*n+k for k in range(n))]
    for j in range(len(sections)-1):
        for k in range(n):nn=(k+1)%n;faces.append((j*n+k,j*n+nn,(j+1)*n+nn,(j+1)*n+k))
    ob=mesh(K,name,verts,faces,mat,True)
    view=Vector((1,-1,1)).normalized()
    for j in range(6):
        k=j*n/6;ang=k*2*math.pi/n;normal=u*math.cos(ang)+v*math.sin(ang)
        if normal.dot(view)>.15:
            stroke(K,name+'_flute_'+str(j),[tuple(point(t,s,k)+normal*.008) for t,s in sections],.010)
    label=1+sum(item.get('chunk_root',False) for item in existing);ob['chunk_root']=True
    for item in set(K.col.objects)-existing:item['part_label']=label
    return ob

def build_pet_coke():
    K=start('pet_coke');mat=toon_mat('batch_coke',(.16,.145,.13))
    fluted_chunk(K,'left_chunk',(-.84,-.55,.30),(-.37,.39,.48),.30,mat,.3)
    fluted_chunk(K,'front_chunk',(.30,-.23,.28),(-.53,-.30,.36),.31,mat,1.1)
    fluted_chunk(K,'long_hero',(.62,.28,.34),(-.44,.03,1.16),.30,mat,2.0)
    return end(K,'three elongated closed angular chunks with broad longitudinal flutes and uneven tapered ends',{'pieces':3,'hero_length':1.36,'hero_width':.60})
