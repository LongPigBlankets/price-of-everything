"""Reference-led desktop computer: monitor, supporting stand and separate tower."""
import math,bmesh
from mathutils import Vector,Matrix
REVISION='fibreglass_lithium_v13'
legacy_refined_ree=build_refined_ree

def stroke(K,name,points,r=.006,mat=None,closed=False):
    pts=[Vector(p) for p in points]
    if closed:pts.append(pts[0])
    ob=noink(K.sweep(name,pts,r,mat or K.mat('ic_navy'),seg=6))
    ob['edge_ink']=True;ob['outline_exempt']=True
    ob['line_path']=[float(c) for p in pts for c in p]
    return ob

def contract(K,hosts,description,inner=6):
    bpy.context.scene.render.use_freestyle=False
    bpy.context.view_layer.update()
    labels=sorted({o.get('part_label',1) for o in K.col.objects})
    return {'revision':REVISION,'objects':len(K.col.objects),'structural_hosts':hosts,'topology':description,
      'outline':{'host_ownership':True,'component_boundaries':False,'standard_weights':{'outer':12,'inner':inner}},
      'stipple':{'version':1,'dot_radius_fraction':.0025,'spacing_fraction':.017,'strength':.30,
        'groups':[{'name':'shadowed_faces','labels':labels,'thresholds':[.65,.53,.42]}]}}

def rounded_box(K,name,c,d,mat,label,r=.03):
    ob=noink(K.box(name,*c,*d,mat));ob['part_label']=label
    if r:
        bpy.context.view_layer.objects.active=ob;ob.select_set(True)
        bevel=ob.modifiers.new('rounded_edges','BEVEL');bevel.width=r;bevel.segments=5
        bpy.ops.object.modifier_apply(modifier=bevel.name);noink(ob)
    return ob

def rect_points(cy,cz,w,h,r,segments=12):
    pts=[]
    for y,z,a in [(cy+w/2-r,cz+h/2-r,0),(cy-w/2+r,cz+h/2-r,90),(cy-w/2+r,cz-h/2+r,180),(cy+w/2-r,cz-h/2+r,270)]:
        for k in range(segments+1):
            th=math.radians(a+90*k/segments);pts.append((y+r*math.cos(th),z+r*math.sin(th)))
    return pts

def front_outline(K,name,x,y,z,w,h,r,label,width=6):
    ob=stroke(K,name,[(x,yy,zz) for yy,zz in rect_points(y,z,w,h,r)],.001,closed=True)
    ob['part_label']=label;ob['ink_width']=width;ob['ink_tip']=1;ob['ink_centre']=1
    return ob



def surface_patch(K,name,vertices,faces,mat,label):
    ob=mesh(K,name,vertices,faces,mat);ob['part_label']=label;ob.pass_index=73;return ob

def tagged_line(K,name,pts,label,width=6,closed=False):
    ob=stroke(K,name,pts,.001,closed=closed);ob['part_label']=label;ob['ink_width']=width;ob['ink_tip']=1;ob['ink_centre']=1;return ob

def tube_z(K,name,c,outer,inner,z0,z1,mat,label):
    n=192;vs=[]
    for r,z in [(outer,z0),(outer,z1),(inner,z1),(inner,z0)]:vs.extend((c[0]+r*math.cos(k*2*math.pi/n),c[1]+r*math.sin(k*2*math.pi/n),z) for k in range(n))
    fs=[(j*n+k,j*n+(k+1)%n,((j+1)%4)*n+(k+1)%n,((j+1)%4)*n+k) for j in range(4) for k in range(n)]
    ob=mesh(K,name,vs,fs,mat,True);ob['part_label']=label
    for f in ob.data.polygons:
        if abs(f.normal.z)>.5:f.use_smooth=False
    return ob

def build_fibreglass():
    """Reference: upright woven roll, connected upright unfurled sheet, yellow/blue slab.
    Roll D1.36 height2.22=1.63D; small core0.24D; tail0.95D across.
    White woven fibres are pale surface strips, never heavy navy tile borders.
    """
    setup_icon_rig();K=Kit(open_collection('ICON_fibreglass'));hosts=[]
    cloth=toon_mat('fibreglass_cloth',(.40,.48,.52),steps=((.69,.65),(.94,.84),(9,1)))
    fibre=toon_mat('fibreglass_weave',(.88,.90,.88),steps=((.69,.72),(.94,.88),(9,1)))
    yellow=toon_mat('laminate_yellow',(.84,.67,.27),steps=((.69,.65),(.94,.84),(9,1)))
    blue=toon_mat('laminate_blue',(.38,.51,.60),steps=((.69,.65),(.94,.84),(9,1)))
    coremat=toon_mat('cardboard_core',(.30,.25,.18),steps=((.69,.65),(.94,.84),(9,1)))
    lower=rounded_box(K,'blue_laminate',(0,0,.072),(2.45,2.13,.14),blue,1,.008);hosts.append(lower.name)
    upper=rounded_box(K,'yellow_laminate',(0,0,.19),(2.45,2.13,.14),yellow,1,.008);hosts.append(upper.name)
    for z in [.141,.2606]:tagged_line(K,'slab_edge_'+str(z),[(-1.222,-1.062,z),(1.222,-1.062,z),(1.222,1.062,z)],1)
    cx=-.36;cy=-.27;R=.68;z0=.25;z1=2.47
    roll=tube_z(K,'woven_roll',(cx,cy),R,.16,z0,z1,cloth,2);hosts.append(roll.name)
    core=noink(K.cyl('core_bottom',cx,cy,z1-.20,.159,.04,coremat,segments=96));core['part_label']=2;hosts.append(core.name)
    for r in [R-.001,.162]:tagged_line(K,'roll_top_'+str(r),[(cx+r*math.cos(k*2*math.pi/256),cy+r*math.sin(k*2*math.pi/256),z1+.0008) for k in range(256)],2,6,True)
    # Fine pale spiral across the annular top: continuous wound layers around the core.
    vs=[];steps=1200
    for k in range(steps):
        t=k/(steps-1);a=2*math.pi*4.2*t;r=.185+.474*t
        for offset in [-.009,.009]:vs.append((cx+(r+offset)*math.cos(a),cy+(r+offset)*math.sin(a),z1+.0014))
    surface_patch(K,'wound_glass_layers',vs,[(2*k,2*k+1,2*k+3,2*k+2) for k in range(steps-1)],fibre,2)
    # Weave fitted to the roll. Angular spacing and horizontal pitch are material scale.
    for k in range(40):
        a=k*2*math.pi/40;half=.013
        vs=[(cx+(R+.0012)*math.cos(th),cy+(R+.0012)*math.sin(th),z) for z in [z0,z1-.004] for th in [a-half,a+half]]
        surface_patch(K,'roll_warp_'+str(k),vs,[(0,1,3,2)],fibre,2)
    for j in range(18):
        z=z0+.045+j*(z1-z0-.09)/17;vs=[]
        for k in range(193):
            a=k*2*math.pi/192
            for dz in [-.008,.008]:vs.append((cx+(R+.0014)*math.cos(a),cy+(R+.0014)*math.sin(a),z+dz))
        surface_patch(K,'roll_weft_'+str(j),vs,[(2*k,2*k+1,2*k+3,2*k+2) for k in range(192)],fibre,2)
    # The sheet is tangent to the back of the roll and curves gently toward the viewer.
    def tail(t):return Vector((cx+1.29*t,cy+R+.15*math.sin(math.pi*t)-.17*t*t,0))
    def normal(t):
        d=Vector((1.29,.15*math.pi*math.cos(math.pi*t)-.34*t,0));return Vector((d.y,-d.x,0)).normalized()
    ns=96;vs=[]
    for k in range(ns+1):
        t=k/ns;p=tail(t);n=normal(t)
        for dz,side in [(z0,-1),(z1,-1),(z1,1),(z0,1)]:vs.append(tuple(p+n*.015*side+Vector((0,0,dz))))
    fs=[(4*k+j,4*(k+1)+j,4*(k+1)+(j+1)%4,4*k+(j+1)%4) for k in range(ns) for j in range(4)];fs.extend([(3,2,1,0),tuple(4*ns+j for j in range(4))])
    sheet=mesh(K,'unfurled_sheet',vs,fs,cloth,True);sheet['part_label']=2;hosts.append(sheet.name)
    # Both sides carry the same cloth weave; the camera decides visibility.
    for side in [-1,1]:
        for k in range(12):
            t=k/11;vs=[]
            for z in [z0,z1]:
                for tt in [max(0,t-.006),min(1,t+.006)]:vs.append(tuple(tail(tt)+normal(tt)*.016*side+Vector((0,0,z))))
            surface_patch(K,'sheet_warp_%s_%s'%(side,k),vs,[(0,1,3,2)],fibre,2)
        for j in range(18):
            z=z0+.045+j*(z1-z0-.09)/17;vs=[]
            for k in range(ns+1):
                t=k/ns
                for dz in [-.008,.008]:vs.append(tuple(tail(t)+normal(t)*.016*side+Vector((0,0,z+dz))))
            surface_patch(K,'sheet_weft_%s_%s'%(side,j),vs,[(2*k,2*k+1,2*k+3,2*k+2) for k in range(ns)],fibre,2)
    tagged_line(K,'tail_top',[tuple(tail(k/ns)+Vector((0,0,z1+.001))) for k in range(ns+1)],2)
    tagged_line(K,'tail_end',[tuple(tail(1)+normal(1)*.016+Vector((0,0,z))) for z in [z0,z1]],2)
    info=contract(K,hosts,'upright hollow woven roll with continuous pale spiral and connected curved sheet on two laminate slabs')
    info['outline']['component_boundaries']=True;info['dimensions']={'roll_diameter':1.36,'roll_height':2.22,'core_diameter':.32,'tail_span':1.29,'weave_rows':18,'roll_warps':40};return info

BAG_PROFILE=[(.02,.88,.68),(.07,.985,.756),(.14,1.005,.77),(.25,.982,.759),(.39,.957,.736),(.52,.969,.747),(.70,.98,.75),(1.20,.96,.73),(1.60,.93,.70),(1.76,.91,.69)]
def bag_dims(z):
    if z<=BAG_PROFILE[0][0]:return BAG_PROFILE[0][1:]
    for a,b in zip(BAG_PROFILE,BAG_PROFILE[1:]):
        if z<=b[0]:
            t=(z-a[0])/(b[0]-a[0]);return (a[1]*(1-t)+b[1]*t,a[2]*(1-t)+b[2]*t)
    return BAG_PROFILE[-1][1:]
def bag_front(x,z):
    a,b=bag_dims(z);return -b*max(.001,1-(abs(x)/a)**8.0)**(1/8.0)
def bag_ring(a,b,z,n=128,wave=0):
    pts=[]
    for k in range(n):
        t=2*math.pi*k/n;c=math.cos(t);s=math.sin(t);d=(abs(c)**8.0+abs(s)**8.0)**(-1/8.0)
        scale=1.
        if z<.55:
            envelope=math.sin(math.pi*max(0,min(1,z/.55)))
            for angle,shift,amount in [(-.70,.20,.095),(-1.03,-.16,.065),(-1.85,.16,.055),(.24,-.2,.08),(2.35,.10,.05)]:
                delta=(t-angle-shift*z+math.pi)%(2*math.pi)-math.pi
                scale-=amount*envelope*math.exp(-(delta/.11)**2)
                scale+=amount*.34*envelope*math.exp(-((delta-.14)/.10)**2)
        pts.append((a*d*c*scale,b*d*s*scale,z+wave*(.5-.5*math.cos(4*t))+.006*math.sin(3*t)))
    return pts

def build_lithium_carbonate():
    """Deep soft pink bulk sack, wide attached flat lifting loops, folded mouth,
    contained white powder mound and conformed Arial Bold Li2CO3 label. W1.96,H1.88;
    two straps width.17 and rise.74 above rim; label1.20x.68.
    """
    setup_icon_rig();K=Kit(open_collection('ICON_lithium_carbonate'));hosts=[]
    pink=toon_mat('lithium_pink',(.69,.29,.43),steps=((.69,.65),(.94,.84),(9,1)))
    powder=toon_mat('carbonate_white',(.89,.90,.87),steps=((.69,.60),(.94,.80),(9,1)))
    powder_side=toon_mat('carbonate_pyramid_side',(.63,.67,.67),steps=((.69,.78),(.94,.94),(9,1)))
    fold_dark=toon_mat('bag_weighted_fold_shadow',(.49,.185,.29),steps=((.69,.75),(.94,.92),(9,1)))
    fold_light=toon_mat('bag_weighted_fold_light',(.76,.35,.48),steps=((.69,.80),(.94,.94),(9,1)))
    paper=toon_mat('label_white',(.96,.96,.93),steps=((.69,.92),(.94,1),(9,1)))
    n=128;spec=BAG_PROFILE+[(1.72,.938,.72),(1.865,.94,.72),(1.86,.867,.645),(1.70,.85,.63),(1.30,.78,.56)]
    vs=[]
    for j,(z,a,b) in enumerate(spec):vs.extend(bag_ring(a,b,z,n,.04 if z>=1.70 else 0))
    fs=[(j*n+k,j*n+(k+1)%n,(j+1)*n+(k+1)%n,(j+1)*n+k) for j in range(len(spec)-1) for k in range(n)];fs.extend([tuple(reversed(range(n))),tuple((len(spec)-1)*n+k for k in range(n))])
    bag=mesh(K,'deep_bulk_sack',vs,fs,pink,True);bag['part_label']=1;hosts.append(bag.name)
    for z,a,b,title in [(1.72,.939,.721,'fold_bottom'),(1.866,.941,.721,'mouth_crest')]:tagged_line(K,title,bag_ring(a,b,z,n,.04),1,6,True)
    # Powder perimeter below the lip; central powder rises modestly above it.
    vs=[];nr=20
    for j in range(1,nr+1):
        r=j/nr
        for k in range(n):
            t=2*math.pi*k/n;c=math.cos(t);s=math.sin(t);d=(abs(c)**8.0+abs(s)**8.0)**(-1/8.0)
            rounded_r=(math.sqrt(r*r+.48*.48)-.48)/(math.sqrt(1+.48*.48)-.48)
            z=1.81+.37*(1-rounded_r)
            vs.append((.854*r*d*c-.52*(1-r),.631*r*d*s+.29*(1-r),z))
    centre=len(vs);vs.append((-.52,.29,2.18));bottom=len(vs);vs.append((0,0,1.25))
    fs=[(centre,k,(k+1)%n) for k in range(n)]+[(j*n+k,j*n+(k+1)%n,(j+1)*n+(k+1)%n,(j+1)*n+k) for j in range(nr-1) for k in range(n)]+[(bottom,(nr-1)*n+(k+1)%n,(nr-1)*n+k) for k in range(n)]
    mound=mesh(K,'contained_powder',vs,fs,powder,True);mound['part_label']=1;hosts.append(mound.name)
    mound.data.materials.append(powder_side)
    for f in mound.data.polygons:
        angle=(f.index%n+.5)*2*math.pi/n
        if math.cos(angle)>abs(math.sin(angle)) and f.normal.z>0:f.material_index=1
    # Ribbon loops with conforming tails: real closed straps, not round rope handles.
    for number,x in enumerate([-.73,.73]):
        rows=[]
        for z in [1.18,1.45,1.60,1.72,1.90,1.96]:rows.append(('front',z))
        for k in range(1,64):rows.append(('arch',math.pi*k/64))
        rows.extend([('back',1.96),('back',1.90),('back',1.72),('back',1.60),('back',1.45),('back',1.18)])
        vs=[]
        for kind,t in rows:
            for side in [-1,1]:
                for dx in [-.085,.085]:
                    xx=x+dx
                    if kind=='arch':
                        extent=.72*max(.001,1-(abs(xx)/.94)**8.0)**(1/8.0)+.025
                        phase=t/math.pi;anchors=[(0,0,0),(.18,.20,.36),(.38,.46,.68),(.61,.47,.70),(.82,.27,.42),(1,0,0)]
                        for aa,bb in zip(anchors,anchors[1:]):
                            if aa[0]<=phase<=bb[0]:
                                f=(phase-aa[0])/(bb[0]-aa[0]);outward=aa[1]*(1-f)+bb[1]*f;rise=aa[2]*(1-f)+bb[2]*f;break
                        xx+=(-1 if x<0 else 1)*outward;y=-extent*math.cos(t);z=1.96+rise
                        ny=-math.cos(t);nz=math.sin(t)
                    else:
                        z=t;outer=.72*max(.001,1-(abs(xx)/.94)**8.0)**(1/8.0)+.025
                        blend=max(0,min(1,(z-1.55)/.17));extent=(-bag_front(xx,z))*(1-blend)+outer*blend
                        y=-extent*(1 if kind=='front' else -1);ny=-1 if kind=='front' else 1;nz=0
                    vs.append((xx,y+ny*(.014+side*.017),z+nz*(.014+side*.017)))
        # Each row order is inner-left,inner-right,outer-left,outer-right.
        fs=[]
        for j in range(len(rows)-1):
            a=4*j;b=a+4
            fs.extend([(a,b,b+1,a+1),(a+2,a+3,b+3,b+2),(a,a+2,b+2,b),(a+1,b+1,b+3,a+3)])
        fs.extend([(0,1,3,2),tuple(4*(len(rows)-1)+i for i in [0,2,3,1])])
        strap=mesh(K,'lifting_webbing_'+str(number),vs,fs,pink,True);strap['part_label']=number+2;hosts.append(strap.name)
    # White label and every glyph follow the same front wall surface.
    w=1.18;h=.65;zmid=.91;vs=[];nu=32;nv=18
    for j in range(nv+1):
        z=zmid-h/2+h*j/nv
        for i in range(nu+1):x=-w/2+w*i/nu;vs.append((x,bag_front(x,z)-.008,z))
    patch=surface_patch(K,'chemical_label',vs,[(j*(nu+1)+i,j*(nu+1)+i+1,(j+1)*(nu+1)+i+1,(j+1)*(nu+1)+i) for j in range(nv) for i in range(nu)],paper,1)
    points=[];perimeter=rect_points(0,zmid,w,h,.018)
    for a,b in zip(perimeter,perimeter[1:]+perimeter[:1]):
        for k in range(max(2,math.ceil(math.dist(a,b)/.01))):
            t=k/max(2,math.ceil(math.dist(a,b)/.01));x=a[0]*(1-t)+b[0]*t;z=a[1]*(1-t)+b[1]*t;points.append((x,bag_front(x,z)-.011,z))
    tagged_line(K,'label_border',points,1,6,True)
    text=formula_mesh(K.col,'carbonate_formula','Li2CO3',K.mat('ic_navy'),1.02,.29,True)
    for v in text.data.vertices:
        x=v.co.x;z=v.co.y+zmid;v.co=(x,bag_front(x,z)-.014,z)
    text['part_label']=1
    # Coarse cloth fold planes across the swollen base, fitted to the deformed sack.
    from mathutils.bvhtree import BVHTree
    bpy.context.view_layer.update();tree=BVHTree.FromObject(bag,bpy.context.evaluated_depsgraph_get())
    def project(u,z,face='front',offset=.004):
        origin=Vector((u,-4,z)) if face=='front' else Vector((4,u,z));direction=Vector((0,1,0)) if face=='front' else Vector((-1,0,0))
        hit,normal,index,distance=tree.ray_cast(origin,direction)
        assert hit is not None,(u,z,face)
        return tuple(hit-direction*offset)
    def fold_patch(name,coords,face,mat):
        ob=mesh(K,name,[(u,z,0) for u,z in coords],[tuple(range(len(coords)))],mat)
        bm=bmesh.new();bm.from_mesh(ob.data);bmesh.ops.triangulate(bm,faces=bm.faces[:]);bmesh.ops.subdivide_edges(bm,edges=bm.edges[:],cuts=36,use_grid_fill=True);bm.to_mesh(ob.data);bm.free()
        for v in ob.data.vertices:v.co=project(v.co.x,v.co.y,face,.011)
        ob['part_label']=1;ob.pass_index=73
    planes=[
      ('front',[(-.91,.40),(-.67,.25),(-.47,.08),(-.72,.16)],fold_dark),
      ('front',[(-.91,.39),(-.72,.16),(-.86,.10),(-.945,.23)],fold_light),
      ('front',[(.40,.08),(.76,.21),(.91,.52),(.85,.19)],fold_dark),
      ('front',[(-.60,.115),(-.34,.29),(-.45,.135),(-.02,.065)],fold_light),
      ('side',[(-.66,.18),(-.37,.49),(-.52,.14),(-.23,.07)],fold_light),
      ('side',[(.55,.50),(.46,.19),(.11,.075),(.35,.27)],fold_dark),
      ('side',[(-.18,.075),(.12,.30),(.07,.14),(.28,.065)],fold_light)]
    for i,(face,coords,mat) in enumerate(planes):fold_patch('weighted_fold_plane_'+str(i),coords,face,mat)
    folds=[('front',[(-.62,1.60),(-.46,1.43),(-.28,1.36)]),('front',[(.82,1.65),(.70,1.46),(.66,1.30)]),
      ('front',[(-.91,.40),(-.70,.24),(-.47,.08)]),('front',[(.91,.52),(.76,.21),(.40,.08)]),
      ('front',[(-.60,.115),(-.34,.16),(-.16,.11)]),('front',[(-.80,.55),(-.78,.43),(-.66,.34)]),
      ('side',[(-.66,.18),(-.51,.29),(-.37,.49)]),('side',[(.55,.50),(.46,.19),(.11,.075)]),
      ('side',[(-.18,.075),(.10,.18),(.23,.13)]),('side',[(-.02,.52),(.10,.43),(.26,.40)])]
    for i,(face,path) in enumerate(folds):
        pts=[]
        for a,b in zip(path,path[1:]):
            for k in range(41):
                t=k/40;pts.append(project(a[0]*(1-t)+b[0]*t,a[1]*(1-t)+b[1]*t,face,.009))
        if i==6:
            # Refit the near-corner crease to the visible folded skin, retaining
            # its projection. Account for the subsequent 1.2 depth transform.
            toward=Vector((1,-1/1.2,1)).normalized();fitted=[]
            dense=[]
            for a,b in zip(pts,pts[1:]):dense.extend(Vector(a).lerp(Vector(b),j/8) for j in range(8))
            dense.append(Vector(pts[-1]))
            for point in dense:
                hit,normal,index,distance=tree.ray_cast(Vector(point)+toward*5,-toward)
                fitted.append(tuple(hit+toward*.025) if hit is not None else point)
            pts=fitted
        line=tagged_line(K,'cloth_crease_'+str(i),pts,1,4);line['ink_tip']=.04;line['ink_centre']=1
    # Square footprint and tighter fabric corners. Transform the entire assembly,
    # including its surface-fitted label and paths, in one shared coordinate system.
    for ob in K.col.objects:
        for v in ob.data.vertices:v.co.y*=1.20
        if ob.get('line_path'):
            flat=list(ob['line_path'])
            for i in range(1,len(flat),3):flat[i]*=1.20
            ob['line_path']=flat
        ob.data.update()
    info=contract(K,hosts,'deep pink rounded-square supersack with folded mouth, attached flat lifting loops, recessed powder perimeter and conformed chemical label')
    info['outline']['component_boundaries']=True;info['dimensions']={'body_width':2.01,'body_depth':1.848,'mouth_height':1.865,'loop_top':2.66,'loop_width':.17,'label_width':1.18,'label_height':.65,'powder_peak':2.18,'powder_edge':1.81,'powder_peak_xy':[-.52,.348],'powder_apex_rounding':.48,'outward_strap_pull':.47,'fold_planes':7,'corner_exponent':8.0,'strap_cuff_clearance':.025};return info
