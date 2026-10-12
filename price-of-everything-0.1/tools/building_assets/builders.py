"""Detailed rural/water families over the approved building Kit (not the goods rig).

Dimensions in metres, barn width D=1.8: barn depth 1.3D, eave .70D,
ridge 1.05D; silo diameter .47D, height 1.5D. Pump house width D=1.6,
depth .85D, eave .8D; main pipe diameter .16D. Desal hall width D=2.4,
depth .65D, height .6D; membrane diameter .10D, length .6D.
Trees: young crown radius .34, mature .60; trunks remain visible below crowns.
All additions grow away from fixed service points. Seeds are explicit integers.
Assets have no shared ground plates. Keep only functional crop beds, basin floors,
equipment foundations and structural footings beneath the individual assemblies.
"""
import math
import random
from mathutils import Vector, Matrix

PALETTE.update({
    'field': (.20, .225, .12), 'crop': (.24, .29, .10),
    'crop_dark': (.12, .19, .075), 'soil': (.16, .13, .095),
    'water': (.09, .22, .27), 'water_light': (.16, .31, .35),
    'terracotta': (.318, .118, .082),
    'greenhouse_glass': (.20, .36, .50),
    'equipment_yellow': (.68, .44, .018),
    'equipment_black': (.055, .060, .066),
    'helideck_green': (.065, .21, .145),
    'offshore_red': (.47, .095, .045),
    'flame_orange': (.90, .29, .025),
})

# The original .12 vertex jitter creates folds steep enough for Freestyle crease
# stubs on dense crowns. Preserve the approved clump topology and flat shading,
# while reducing only that high-frequency displacement.
_props_blob = Kit._blob
def _canopy_blob(self, *args, **kwargs):
    kwargs['jitter'] = .035
    return _props_blob(self, *args, **kwargs)
Kit._blob = _canopy_blob


def noink(ob):
    a = ob.data.attributes.get('freestyle_face')
    if a is None:
        a = ob.data.attributes.new('freestyle_face', 'BOOLEAN', 'FACE')
    for v in a.data:
        v.value = True
    return ob


def begin(name):
    setup_rig(ortho_scale=11.6, target=(0, 0, 1))
    for lines in bpy.context.scene.view_layers[0].freestyle_settings.linesets:
        lines.select_by_face_marks = True
        lines.face_mark_negation = 'EXCLUSIVE'
        lines.face_mark_condition = 'ONE'
    return Kit(open_collection('BLDG_' + name))


def finish(K, level):
    # Fixed projection scale across levels; only recenter, never auto-zoom each level.
    bpy.context.view_layer.update()
    pts = [o.matrix_world @ v.co for o in K.col.objects if o.type == 'MESH' for v in o.data.vertices]
    u = [(v.x + v.y) / math.sqrt(2) for v in pts]
    z = [(2*v.z - v.x + v.y) / math.sqrt(6) for v in pts]
    uc, zc = (min(u)+max(u))/2, (min(z)+max(z))/2
    target = Vector((uc/math.sqrt(2), uc/math.sqrt(2), zc*math.sqrt(6)/2))
    bpy.context.scene.camera.location = target + Vector((1,-1,1)).normalized()*26
    warnings = K.validate(ground=-.25)
    return dict(level=level, objects=len(K.col.objects), warnings=warnings)


def house(K, name, x, y, w, d, h, wall='brick', rise=.55):
    K.box(name+'_walls',x,y,h/2,w,d,h,K.mat(wall))
    K.prism(name+'_gable',(x,y,0),(1,0),[(-w/2,h),(0,h+rise),(w/2,h)],d,K.mat(wall))
    for sign in (-1,1):
        # Roof extruded along X profile, ridge along Y.
        xa, xb = (-w/2-.10,0) if sign<0 else (0,w/2+.10)
        za, zb = (h-.055,h+rise) if sign<0 else (h+rise,h-.055)
        K.prism(name+'_roof'+str(sign),(x,y,0),(1,0),
                [(xa,za),(xb,zb),(xb,zb+.075),(xa,za+.075)],d+.20,K.mat('roof'))
    K._fine_mode = True
    for side in (-1,1):
        K.box(name+'_gutter'+str(side), x+side*(w/2+.09),y,h-.03,.045,d+.18,.05,K.mat('darkmetal'))
    K.pipe_run(name+'_downpipe',[(x+w/2+.07,y-d/2+.12,h-.08),
                                (x+w/2+.07,y-d/2+.12,.12)],.025,bend=.07)
    K._fine_mode = False


def silo(K, name, x, y, h=2.65):
    K.cyl(name,x,y,h/2,.42,h,K.mat('tank_grey'))
    K.dome_cap(name+'_cap',x,y,h,.44,.20,K.mat('roof'))
    K._fine_mode=True
    for z in (.25,.75,1.25,1.75,2.25):
        if z<h: K.seam(name+'_ring'+str(z),x,y,z,.426)
    K.ladder(name+'_ladder',x+.445,y,.12,h,face='+X',w=.18,rung=.22,mat=K.mat('darkmetal'))
    K._fine_mode=False


def beds(K, count):
    # Intentionally broad planted ribbons, with sparse leaves in the fine/no-ink tier.
    for j in range(count):
        y=-1.10+j*.61
        K.box('bed%d'%j,-1.85,y,.055,2.45,.46,.11,K.mat('soil'))
        for r in (-1,1):
            noink(K.box('crop%d_%d'%(j,r),-1.85,y+r*.115,.135,2.25,.13,.16,
                       K.mat('crop' if j%2 else 'crop_dark')))
            for i in range(9):
                noink(K.prism('leaves%d_%d_%d'%(j,r,i),(-2.94+i*.25,y+r*.115,.20),
                              (1,0),[(0,0),(.065,.115),(.13,.035),(.19,.09),(.21,0)],
                              .10,K.mat('crop' if (i+j)%3 else 'crop_dark')))
        K._fine_mode=True
        K.pipe_run('drip%d'%j,[(-3.0,y,.13),(-.63,y,.13)],.018)
        K._fine_mode=False


def build_farm(level=1):
    K=begin('farm')
    # Owner, 2026-10-10: the shown complete farm is L3; lower levels lose
    # substantial elements. Keep the accepted L3 geometry exactly as presented.
    # L1 and L2 share the deeper field and yard; only silo + trough upgrade.
    rows={1:4,2:4,3:5}[level]
    house(K,'barn',.8,.7,1.8,2.30,1.25,rise=.65)
    K.door('barn_door','-Y',(.8,-.45,.51),.92,1.02,ribs=5)
    K._fine_mode=True
    # Proud boards and X-braces survive the kit door's recessed ribs.
    for x in (.44,.62,.80,.98,1.16):
        K.box('door_board'+str(x),x,-.483,.51,.018,.016,.96,K.mat('darkmetal'))
    for a,b in [((.37,-.50,.08),(1.22,-.50,.94)),((1.22,-.50,.08),(.37,-.50,.94))]:
        K.dircyl('barn_brace',a,b,.022,K.mat('mullion'),segments=6,smooth=False)
    for y in (-.20,.20,.60,1.00,1.40,1.80):
        K.dircyl('roof_seam',(.8,y,1.98),(1.79,y,1.29),.012,K.mat('darkmetal'),segments=6)
    K._fine_mode=False
    K.window('loft','-Y',(.8,-.45,1.52),.35,.35,cols=2,rows=1)
    for y in (.15,.95,1.70):
        K.window('barn_window'+str(y),'+X',(1.7,y,.83),.39,.50,cols=2,rows=2)
    beds(K,rows)
    # L1: barn + fields. L2: one silo. L3: twin silos + glasshouse.
    if level>=2:
        silo(K,'grain_silo',2.03,1.85,h=2.20)
    if level>=3:
        silo(K,'grain_silo2',1.98,.65,h=2.60)
    K._fine_mode=True
    K.pipe_run('field_header',[(-3.02,-1.10,.16),(-3.02,1.34,.16)],.035)
    K.box('irrigation_box',-3.02,1.66,.24,.27,.32,.48,K.mat('door'))
    K._fine_mode=False
    if level>=3:
        # A distinct glass growing house on the free rear side.
        house(K,'glasshouse',-1.80,2.02,2.18,.67,.67,wall='chalk',rise=.30)
        for i in range(5):
            K.window('greenhouse_pane%d'%i,'-Y',(-2.62+i*.41,1.68,.41),.34,.43,cols=1,rows=1)
        K._fine_mode=True
        for ob in K.col.objects:
            if ob.name.startswith('glasshouse_roof'):
                ob.data.materials.clear()
                ob.data.materials.append(K.mat('greenhouse_glass'))
        for y in (1.73,2.02,2.31):
            K.dircyl('glass_roof_rib',(-2.96,y,.79),(-1.8,y,1.07),.021,K.mat('mullion'),segments=6)
            K.dircyl('glass_roof_rib',(-1.8,y,1.07),(-.64,y,.79),.021,K.mat('mullion'),segments=6)
        K._fine_mode=False
    # Yard details stay readable and do not inflate the silhouette.
    K._fine_mode=True
    for i in range({1:2,2:2,3:3}[level]):
        K.box('produce_crate%d'%i,.1+i*.30,-1.0,.17,.25,.32,.34,K.mat('earth'))
    if level>=2:
        K.box('water_trough',1.75,-.95,.22,.88,.48,.44,K.mat('chalk'))
        noink(K.box('trough_water',1.75,-.95,.449,.70,.31,.025,K.mat('water')))
    K._fine_mode=False
    return finish(K,level)



PUMPJACK = dict(pivot_z=2.55, rear_arm=1.22, head_radius=1.86,
               crank_x=-1.16, crank_z=1.02, crank_radius=.27,
               rest_crank=50.0, wire_radius=.013, carrier_z=1.08)


def pumpjack_pose(crank_degrees=50.0):
    """Solve the closed four-bar, selecting the conventional rear-rocker branch."""
    p=PUMPJACK
    rest=math.radians(p['rest_crank'])
    cx,cz=p['crank_x'],p['crank_z']
    r,rear,h=p['crank_radius'],p['rear_arm'],p['pivot_z']
    length=math.hypot(-rear-cx-r*math.cos(rest),h-cz-r*math.sin(rest))
    theta=math.radians(crank_degrees)
    qx,qz=cx+r*math.cos(theta),cz+r*math.sin(theta)
    dx,dz=qx,qz-h
    distance=math.hypot(dx,dz)
    along=(rear*rear-length*length+distance*distance)/(2*distance)
    across=math.sqrt(max(0,rear*rear-along*along))
    candidates=[(along*dx/distance+s*across*(-dz/distance),
                 h+along*dz/distance+s*across*dx/distance) for s in (-1,1)]
    ex,ez=min(candidates,key=lambda v:v[0])
    alpha=math.atan2(-(ez-h),-ex)
    radius=p['head_radius']+p['wire_radius']
    return dict(crank=(qx,qz),equalizer=(ex,ez),beam_angle=alpha,
                pitman_length=length,carrier_z=p['carrier_z']+radius*alpha)


def pumpjack(K, name, x, y, crank_degrees=50.0):
    """Conventional crank-balanced unit; D=1m support-base width.

    Pivot 2.55D, horsehead radius 1.86D, rear lever 1.22D, crank .27D.
    A solved four-bar drives two outboard pitmans; the horsehead is concentric
    with the centre bearing. Bridle length and vertical rod axis are invariant.
    Belt/gear drive, cranks and pitmans occupy separate Y lanes. Closed housings
    simplify internal gears; bearing bores and polished-rod passage are explicit.
    """
    p=PUMPJACK;pose=pumpjack_pose(crank_degrees)
    h=p['pivot_z'];radius=p['head_radius'];rw=p['wire_radius']
    steel,light,accent=K.mat('darkmetal'),K.mat('tank_grey'),K.mat('terracotta')
    seen=set(K.col.objects)
    def pt(a,b,c):return (x+a,y+b,c)
    def tag(group):
        nonlocal seen
        for ob in set(K.col.objects)-seen:
            ob['pumpjack']=name;ob['assembly']=group
        seen=set(K.col.objects)
    def bar(tagname,a,b,width,depth,mat,lane=0):
        dx,dz=b[0]-a[0],b[1]-a[1];length=math.hypot(dx,dz)
        nx,nz=-dz/length*width/2,dx/length*width/2
        return K.prism(name+'_'+tagname,pt(0,lane,0),(1,0),
                       [(a[0]+nx,a[1]+nz),(b[0]+nx,b[1]+nz),
                        (b[0]-nx,b[1]-nz),(a[0]-nx,a[1]-nz)],depth,mat)
    def ring(tagname,a,lane,inner,outer,depth,mat):
        return K.washer(name+'_'+tagname,pt(a[0],lane,a[1]),(0,1,0),inner,outer,depth,mat,seg=24)
    # All pedestals bear directly on this equipment foundation, not a site plate.
    K.box(name+'_foundation',x-.575,y,.12,3.75,1.32,.24,K.mat('chalk'))
    for side in (-1,1):
        K.box(name+'_skid',x-.575,y+side*.43,.32,3.65,.12,.16,steel)
    tag('foundation')
    for side in (-1,1):
        lane=side*.34
        for front in (-1,1):
            foot=front*.60;top=front*.10
            K.prism(name+'_samson',pt(0,lane,0),(1,0),
                    [(foot-.08,.40),(foot+.08,.40),(top+.055,2.32),(top-.055,2.32)],.13,light)
        bar('cross_tie',(-.46,.95),(.46,.95),.09,.13,steel,lane)
    K.box(name+'_bearing_saddle',x,y,2.355,.42,.86,.07,steel)
    for side in (-1,1):
        K.box(name+'_bearing_foot',x,y+side*.32,2.41,.22,.18,.04,light)
        ring('bearing_housing',(0,h),side*.32,.068,.135,.16,light)
    # Side ladder is attached to the support, clear of the beam and drive lanes.
    K._fine_mode=True
    K.ladder(name+'_service_ladder',x+.75,y-.51,.41,2.30,face='+X',w=.21,rung=.24,mat=steel)
    for z in (.70,2.10):
        leg_x=.60-(z-.40)*.50/1.92
        bar('ladder_standoff',(leg_x,z),(.75,z),.045,.045,steel,-.34)
        K.box(name+'_ladder_bracket',x+.75,y-.465,z,.045,.25,.045,steel)
    K._fine_mode=False
    tag('support')
    # Beam-side bearing sleeves are bored; the fixed shaft is not buried in a web.
    beam_start=set(K.col.objects)
    for side in (-1,1):
        ring('beam_sleeve',(0,h),side*.12,.068,.13,.09,steel)
        K.box(name+'_beam_saddle_neck',x,y+side*.12,h+.135,.16,.09,.07,steel)
    K.box(name+'_walking_web',x+.21,y,h+.28,2.94,.14,.20,light)
    for z in (h+.145,h+.415):
        K.box(name+'_walking_flange',x+.21,y,z,2.94,.32,.07,steel)
    # Tail bearing sits under the rear flange and receives the equalizer shaft.
    ring('tail_bearing',(-p['rear_arm'],h),0,.064,.125,.20,steel)
    K.box(name+'_tail_neck',x-p['rear_arm'],y,h+.135,.17,.20,.07,steel)
    outer=[(radius*math.cos(t),h+radius*math.sin(t))
           for t in [math.radians(18-i*58/24) for i in range(25)]]
    inner=[((radius-.40)*math.cos(t),h+(radius-.40)*math.sin(t))
           for t in [math.radians(-40+i*58/24) for i in range(25)]]
    K.prism(name+'_horsehead',pt(0,0,0),(1,0),outer+inner,.42,accent)
    anchor=math.radians(18)
    for side in (-1,1):
        K.box(name+'_bridle_anchor',x+radius*math.cos(anchor),y+side*.13,
              h+radius*math.sin(anchor),.09,.075,.09,steel)
    alpha=pose['beam_angle']
    pivot=Vector(pt(0,0,h))
    rotation=Matrix.Translation(pivot)@Matrix.Rotation(-alpha,4,'Y')@Matrix.Translation(-pivot)
    for ob in set(K.col.objects)-beam_start:ob.matrix_world=rotation@ob.matrix_world
    tag('beam')
    K.cyl(name+'_pivot_shaft',x,y,h,.063,.91,steel,axis='Y',segments=24)
    for side in (-1,1):K.cyl(name+'_pivot_cap',x,y+side*.465,h,.084,.04,steel,axis='Y',segments=20)
    tag('pivot_shaft')
    # Reducer and motor feet meet the concrete top, with room for rotating weights.
    K.box(name+'_gear_pedestal',x-1.25,y,.445,.76,.58,.41,light)
    K.box(name+'_gearbox',x-1.25,y,.95,.76,.50,.60,steel)
    K.box(name+'_motor_foot',x-2.06,y,.37,.45,.52,.26,light)
    K.cyl(name+'_motor',x-2.06,y,.70,.20,.38,accent,axis='Y',segments=24)
    tag('drive_housings')
    # Enclosed V-belt drive is inboard of the crank planes, on a separate input axis.
    motor=(-2.06,.70);input_axis=(-1.57,1.07)
    for label,a,r in (('motor',motor,.12),('input',input_axis,.19)):
        K.cyl(name+'_'+label+'_shaft',x+a[0],y-.265,a[1],.042,.17,light,axis='Y',segments=16)
        K.cyl(name+'_'+label+'_pulley',x+a[0],y-.35,a[1],r,.055,light,axis='Y',segments=24)
        ring(label+'_belt_wrap',a,-.35,r-.006,r+.008,.025,steel)
    dx,dz=input_axis[0]-motor[0],input_axis[1]-motor[1]
    d=math.hypot(dx,dz);ux,uz=dx/d,dz/d
    projection=(.12-.19)/d
    for sign in (-1,1):
        nx=projection*ux+sign*math.sqrt(1-projection*projection)*(-uz)
        nz=projection*uz+sign*math.sqrt(1-projection*projection)*ux
        a=(motor[0]+.126*nx,motor[1]+.126*nz)
        b=(input_axis[0]+.196*nx,input_axis[1]+.196*nz)
        bar('drive_belt',a,b,.016,.025,steel,-.35)
    # Hollow-backed sheet-metal guard, with no solid volume crossing the crankshaft.
    # Convex envelope of both pulleys plus 50mm; its rim clears both belt spans.
    points=sorted((a[0]+(r+.05)*math.cos(i*math.tau/32),
                   a[1]+(r+.05)*math.sin(i*math.tau/32))
                  for a,r in ((motor,.12),(input_axis,.19)) for i in range(32))
    def half_hull(points):
        result=[]
        for c in points:
            while len(result)>1:
                a,b=result[-2:]
                if (b[0]-a[0])*(c[1]-a[1])-(b[1]-a[1])*(c[0]-a[0])>0:break
                result.pop()
            result.append(c)
        return result
    profile=half_hull(points)[:-1]+half_hull(list(reversed(points)))[:-1]
    K.prism(name+'_belt_guard_face',pt(0,-.425,0),(1,0),profile,.018,steel)
    for a,b in zip(profile,profile[1:]+profile[:1]):
        bar('belt_guard_rim',a,b,.018,.15,steel,-.35)
    # Rear support bears on the skid; the front bracket mounts on the reducer.
    # Both meet the guard outside the belt/sheave envelope.
    K.box(name+'_belt_guard_rear_support',x-2.06,y-.405,.47,.045,.04,.14,steel)
    K.box(name+'_belt_guard_front_support',x-1.57,y-.23,1.28,.045,.04,.06,steel)
    K.box(name+'_belt_guard_front_bracket',x-1.57,y-.325,1.30,.045,.19,.025,steel)
    # A small brake disc/caliper sits on the reducer's opposite input-side face.
    K.cyl(name+'_brake_disc',x-1.57,y+.31,1.07,.14,.045,light,axis='Y',segments=24)
    K.cyl(name+'_brake_shaft',x-1.57,y+.28,1.07,.042,.12,light,axis='Y',segments=16)
    # Slotted caliper: two pads beside the disc and bridge above its outer edge.
    for lane in (.274,.346):
        K.box(name+'_brake_pad',x-1.57,y+lane,1.20,.16,.025,.10,steel)
    K.box(name+'_brake_bridge',x-1.57,y+.31,1.255,.16,.11,.02,steel)
    K.box(name+'_brake_mount',x-1.57,y+.257,1.245,.16,.035,.055,steel)
    tag('belt_drive')
    cx,cz=p['crank_x'],p['crank_z'];qx,qz=pose['crank']
    theta=math.radians(crank_degrees);u=(math.cos(theta),math.sin(theta))
    K.cyl(name+'_crankshaft',x+cx,y,cz,.065,1.35,light,axis='Y',segments=24)
    for side in (-1,1):
        lane=side*.61
        ring('crank_hub',(cx,cz),lane,.068,.12,.10,accent)
        bar('crank_arm',(cx-.41*u[0],cz-.41*u[1]),
            (cx-.09*u[0],cz-.09*u[1]),.12,.10,accent,lane)
        bar('crank_arm',(cx+.09*u[0],cz+.09*u[1]),(qx,qz),.12,.10,accent,lane)
        # Counterweight annular sector lies opposite the crank pin, clear of skids.
        def sector(r):return [(cx+r*math.cos(theta+math.pi+math.radians(a)),
                              cz+r*math.sin(theta+math.pi+math.radians(a))) for a in (-32,-16,0,16,32)]
        K.prism(name+'_counterweight',pt(0,lane,0),(1,0),sector(.49)+list(reversed(sector(.31))),.14,accent)
        K.cyl(name+'_shaft_cap',x+cx,y+side*.675,cz,.086,.04,steel,axis='Y',segments=20)
        K.dircyl(name+'_crank_pin',pt(qx,side*.59,qz),pt(qx,side*.825,qz),.048,steel,segments=20)
        K.cyl(name+'_crank_pin_cap',x+qx,y+side*.825,qz,.072,.025,steel,axis='Y',segments=20)
    tag('crank')
    ex,ez=pose['equalizer']
    K.cyl(name+'_equalizer_shaft',x+ex,y,ez,.06,1.67,light,axis='Y',segments=24)
    for side in (-1,1):K.cyl(name+'_equalizer_cap',x+ex,y+side*.843,ez,.078,.022,steel,axis='Y',segments=20)
    tag('equalizer')
    for side in (-1,1):
        lane=side*.75
        dx,dz=ex-qx,ez-qz;length=math.hypot(dx,dz);ux,uz=dx/length,dz/length
        ring('pitman_lower_eye',(qx,qz),lane,.052,.10,.09,light)
        ring('pitman_upper_eye',(ex,ez),lane,.064,.11,.09,light)
        bar('pitman',(qx+.085*ux,qz+.085*uz),(ex-.095*ux,ez-.095*uz),.085,.075,light,lane)
    tag('pitmans')
    # Wrapped bridle follows the head to the vertical tangent, then the carrier.
    K._fine_mode=True
    wire_x=radius+rw;carrier=pose['carrier_z']
    for side in (-1,1):
        points=[]
        for i in range(17):
            t=anchor+( -alpha-anchor)*i/16
            points.append(pt(wire_x*math.cos(t+alpha),side*.13,h+wire_x*math.sin(t+alpha)))
        points.append(pt(wire_x,side*.13,carrier+.055))
        K.sweep(name+'_bridle',points,rw,steel,seg=10)
    K.washer(name+'_carrier_bore',pt(wire_x,0,carrier),(0,0,1),.028,.08,.09,light,seg=24)
    for side in (-1,1):K.box(name+'_carrier_wing',x+wire_x,y+side*.14,carrier,.16,.16,.09,light)
    for side in (-1,1):K.cyl(name+'_rope_socket',x+wire_x,y+side*.13,carrier+.055,.027,.11,steel,segments=16)
    K.cyl(name+'_polished_rod',x+wire_x,y,(.44+carrier+.19)/2,.026,carrier+.19-.44,K.mat('silver'),segments=20)
    K.washer(name+'_rod_clamp',pt(wire_x,0,carrier+.105),(0,0,1),.027,.071,.12,steel,seg=24)
    K._fine_mode=False
    tag('bridle_rod')
    K.box(name+'_well_pad',x+wire_x,y,.10,.57,.60,.20,K.mat('chalk'))
    K.washer(name+'_wellhead',pt(wire_x,0,.35),(0,0,1),.045,.14,.34,steel,seg=24)
    K.washer(name+'_stuffing_box',pt(wire_x,0,.58),(0,0,1),.029,.085,.12,light,seg=24)
    K.dircyl(name+'_side_nozzle',pt(wire_x+.11,0,.35),pt(wire_x+.245,0,.35),.068,steel,segments=20)
    K.washer(name+'_outlet_flange',pt(wire_x+.22,0,.35),(1,0,0),.070,.105,.026,light,seg=24)
    tag('wellhead')
    return pose


def oil_tank(K, name, x, y):
    K.flat_tank(name,x,y,.52,1.43,band=False,stair=False,vent=True,
                mat=K.mat('tank_grey'),roof_rise=.075)
    K._fine_mode=True
    K.seam(name+'_weld',x,y,.40,.528)
    K.ladder(name+'_ladder',x+.54,y,.12,1.50,face='+X',w=.20,rung=.22,mat=K.mat('darkmetal'))
    K._fine_mode=False


def build_oil_well(level=1):
    """Owner: 'Next we need oil well (non fracking)'.

    One conventional pumpjack + tank; L2 adds a second storage tank, separator
    and control cabinet; L3 adds a second pumpjack. Shared site and equipment
    anchors leave both horseheads visible. No fracturing trucks or drilling mast.
    """
    K=begin('oil_well')
    pumpjack(K,'jack_a',-.70,-.94)
    oil_tank(K,'stock_tank_a',2.22,.18)
    K._fine_mode=True
    outlet=-.70+PUMPJACK['head_radius']+PUMPJACK['wire_radius']+.245
    K.pipe_run('gathering_a',[(outlet,-.94,.35),(1.50,-.94,.35),(1.50,.18,.35),(1.75,.18,.35)],
               .065,mat=K.mat('darkmetal'),bend=.035,ends=('','collar'))
    valve(K,'well_a_valve',1.50,-.60,.35)
    K._fine_mode=False
    if level>=2:
        oil_tank(K,'stock_tank_b',2.22,1.70)
        for xx in (-1.18,-.22):
            K.box('separator_saddle',xx,2.13,.30,.18,.58,.60,K.mat('darkmetal'))
        K.cyl('separator',-.70,2.13,.79,.29,1.76,K.mat('chalk'),axis='X',segments=32)
        for xx in (-1.58,.18):
            K.cyl('separator_head',xx,2.13,.79,.295,.07,K.mat('tank_grey'),axis='X')
        K.box('control_plinth',-2.72,-2.16,.13,.60,.54,.26,K.mat('chalk'))
        K.box('control_cabinet',-2.72,-2.16,.60,.48,.42,.72,K.mat('tank_grey'))
        K._fine_mode=True
        K.box('control_door',-2.72,-2.382,.60,.39,.025,.59,K.mat('roof'))
        K.box('control_handle',-2.57,-2.41,.61,.025,.03,.14,K.mat('silver'))
        K.pipe_run('separator_feed',[(1.50,.18,.35),(1.50,2.13,.35),(.18,2.13,.35),(.18,2.13,.79)],
                   .065,mat=K.mat('darkmetal'),bend=.14,ends=('collar','collar'))
        K.pipe_run('tank_connection',[(1.50,1.70,.35),(1.75,1.70,.35)],.065,mat=K.mat('darkmetal'))
        K.cyl('separator_gauge_stem',-.70,2.13,1.14,.025,.18,K.mat('darkmetal'),segments=12)
        K.cyl('separator_gauge',-.70,2.10,1.27,.10,.07,K.mat('chalk'),axis='Y',segments=20)
        valve(K,'separator_valve',.55,2.13,.35)
        K._fine_mode=False
    if level>=3:
        pumpjack(K,'jack_b',-.70,.84)
        K._fine_mode=True
        K.pipe_run('gathering_b',[(outlet,.84,.35),(1.50,.84,.35)],.065,
                   mat=K.mat('darkmetal'),ends=('',''))
        valve(K,'well_b_valve',1.50,1.06,.35)
        K._fine_mode=False
    return finish(K,level)


def basin(K,name,x,y,w,d):
    K.box(name+'_base',x,y,.10,w,d,.20,K.mat('pad'))
    noink(K.box(name+'_water',x,y,.23,w-.16,d-.16,.08,K.mat('water')))
    for sx in (-1,1): K.box(name+'_side'+str(sx),x+sx*(w/2-.055),y,.22,.11,d,.44,K.mat('chalk'))
    for sy in (-1,1): K.box(name+'_end'+str(sy),x,y+sy*(d/2-.055),.22,w,.11,.44,K.mat('chalk'))
    K._fine_mode=True
    for i in range(3):
        noink(K.box(name+'_ripple%d'%i,x-w*.20+i*w*.20,y,.28,.15,d*.4,.008,K.mat('water_light')))
    K._fine_mode=False


def frac_tree(K,name,x,y):
    """Two master valves, top inlet block and side actuators; no drilling mast."""
    steel,accent=K.mat('equipment_black'),K.mat('equipment_yellow')
    K.cyl(name+'_casing',x,y,.18,.15,.36,steel,segments=20)
    for z in (.12,.31,.68,1.04,1.43):
        K.cyl(name+'_flange',x,y,z,.22,.065,K.mat('tank_grey'),segments=20)
    K.cyl(name+'_bore_body',x,y,.86,.105,1.12,steel,segments=20)
    for z in (.49,.85):
        K.box(name+'_gate_body',x,y,z,.31,.31,.26,accent)
        K.cyl(name+'_bonnet',x,y-.21,z,.095,.16,steel,axis='Y',segments=16)
        K.cyl(name+'_actuator',x,y-.39,z,.115,.22,K.mat('tank_grey'),axis='Y',segments=16)
    K.box(name+'_inlet_block',x,y,1.27,.35,.31,.24,accent)
    K.cyl(name+'_top_cap',x,y,1.48,.145,.04,steel,segments=20)
    K.dircyl(name+'_inlet', (x-.28,y,1.27),(x-.14,y,1.27),.075,steel,segments=16)
    K.washer(name+'_inlet_flange',(x-.25,y,1.27),(1,0,0),.078,.125,.055,K.mat('tank_grey'),seg=20)


def oil_drop(K,name,x,y,z,w=.31,h=.43):
    """Flat painted teardrop on a -Y-facing tank end; no embossed border."""
    profile=[(0,h*.56),(-w*.36,h*.06),(-w*.50,-h*.14),(-w*.44,-h*.31),
             (-w*.26,-h*.43),(0,-h*.47),(w*.26,-h*.43),(w*.44,-h*.31),
             (w*.50,-h*.14),(w*.36,h*.06)]
    return noink(K.prism(name,(x,y,z),(1,0),profile,.006,K.mat('equipment_black')))


def frac_water_tank(K,name,x,y):
    """Low horizontal water vessel: shell on two bearing saddles, end outlet."""
    steel,grey=K.mat('equipment_black'),K.mat('tank_grey')
    for side in (-1,1):
        K.box(name+'_runner',x+side*.32,y,.08,.12,2.10,.16,steel)
    for yy in (-.64,.64):
        K.box(name+'_saddle',x,y+yy,.24,.76,.15,.16,steel)
    K.cyl(name+'_body',x,y,.61,.40,1.96,grey,axis='Y',segments=32)
    for yy in (-.97,.97):
        K.cyl(name+'_end_rim',x,y+yy,.61,.413,.055,steel,axis='Y',segments=32)
    K.cyl(name+'_label_face',x,y-1.001,.61,.352,.013,grey,axis='Y',segments=32)
    oil_drop(K,name+'_oil_drop',x,y-1.012,.65)
    K._fine_mode=True
    K.cyl(name+'_hatch',x,y,1.03,.15,.065,steel,segments=20)
    K.cyl(name+'_vent',x,y+.63,1.08,.035,.20,steel,segments=12)
    K.cyl(name+'_vent_cap',x,y+.63,1.19,.065,.025,steel,segments=16)
    K.dircyl(name+'_outlet',(x,y-.94,.32),(x,y-1.10,.32),.07,steel,segments=16)
    K._fine_mode=False


def frac_pump(K,name,x,y):
    """Compact diesel drive, coupling, reciprocating power end and triplex fluid end.
    Trailer deck raised .40m; suction z=.94, discharge z=1.10.
    Tandem wheel D=.44m, wheelbase=.50m; chassis L=2.10m=4.77D.
    """
    before=set(K.col.objects)
    steel,grey,accent=K.mat('equipment_black'),K.mat('tank_grey'),K.mat('equipment_yellow')
    for side in (-1,1):K.box(name+'_runner',x-.14,y+side*.34,.08,2.10,.13,.16,steel)
    for xx in (-.85,.23):K.box(name+'_crossmember',x+xx,y,.18,.14,.81,.08,steel)
    # Two bearing brackets leave an open central passage for the suction drop.
    for side in (-1,1):K.box(name+'_head_crossmember',x+.52,y+side*.31,.18,.14,.19,.08,steel)
    K.box(name+'_engine_foot',x-.59,y,.29,.73,.57,.14,steel)
    K.box(name+'_engine',x-.60,y,.66,.73,.58,.61,accent)
    K.box(name+'_valve_cover',x-.60,y,.99,.58,.42,.08,steel)
    K.box(name+'_radiator',x-1.04,y,.69,.13,.65,.83,steel)
    K.box(name+'_radiator_foot',x-1.00,y,.225,.22,.65,.13,steel)
    K._fine_mode=True
    for z in (.39,.50,.61,.72,.83,.94):K.box(name+'_grille',x-1.111,y,z,.012,.53,.025,grey)
    K.cyl(name+'_exhaust',x-.76,y+.17,1.13,.035,.40,steel,segments=12)
    K.cyl(name+'_exhaust_cap',x-.76,y+.17,1.34,.065,.025,steel,segments=12)
    K._fine_mode=False
    K.cyl(name+'_coupling',x-.085,y,.70,.12,.32,steel,axis='X',segments=20)
    K.box(name+'_power_foot',x+.23,y,.37,.38,.56,.30,steel)
    K.box(name+'_power_end',x+.23,y,.70,.38,.60,.37,grey)
    for lane in (-.21,0,.21):
        K.cyl(name+'_plunger',x+.46,y+lane,.70,.047,.12,steel,axis='X',segments=12)
    K.box(name+'_fluid_end',x+.65,y,.70,.34,.70,.28,accent)
    for side in (-1,1):K.box(name+'_head_foot',x+.65,y+side*.29,.39,.17,.08,.34,steel)
    K.dircyl(name+'_suction_port',(x+.64,y,.54),(x+.64,y,.60),.07,steel,segments=16)
    K.dircyl(name+'_discharge_port',(x+.78,y,.70),(x+.88,y,.70),.055,steel,segments=16)

    # Raise the complete supported power train onto a road-mobile tandem trailer.
    for ob in set(K.col.objects)-before:ob.location.z+=.40
    for xx in (-.80,-.30):
        K.cyl(name+'_axle',x+xx,y,.22,.055,1.10,steel,axis='Y',segments=12)
        for side in (-1,1):
            K.box(name+'_suspension',x+xx,y+side*.34,.33,.19,.11,.18,steel)
            K.cyl(name+'_tyre',x+xx,y+side*.54,.22,.22,.18,steel,axis='Y',segments=24)
            K.cyl(name+'_hub',x+xx,y+side*.637,.22,.105,.02,grey,axis='Y',segments=16)
    for side in (-1,1):
        K.box(name+'_landing_leg',x+.68,y+side*.34,.23,.085,.085,.46,steel)
        K.box(name+'_landing_foot',x+.68,y+side*.34,.035,.21,.20,.07,steel)


def build_fracking_oil_well(level=1):
    """Active shale-completion spread, schematic equipment counts (2/3/4 pumps).

    Every level preserves water/sand -> blender -> LP header -> pumps -> separate
    HP header -> isolating manifold -> frac trees. Elevated angular sand bins,
    diagonal enclosed auger and tandem-wheel trailers define the silhouette. Port centers are shared with each connected pipe route.
    Narrow runners/feet only: no shared ground plate and no synthetic outer ink.
    """
    K=begin('fracking_oil_well')
    steel,grey,accent=K.mat('equipment_black'),K.mat('tank_grey'),K.mat('equipment_yellow')
    seen=set(K.col.objects)
    def tag(group):
        nonlocal seen
        for ob in set(K.col.objects)-seen:ob['assembly']=group
        seen=set(K.col.objects)
    def pipe(name,points,r=.055):
        clean=[points[0]]
        for point in points[1:]:
            if math.dist(point,clean[-1])>1e-6:clean.append(point)
        K.pipe_run(name,clean,r,mat=steel,bend=.11,ends=('',''))
    def foot(name,x,y,z,width=.16):
        K.box(name+'_foot',x,y,.045,width+.12,width+.12,.09,steel)
        K.box(name+'_post',x,y,(.09+z)/2,width,width,z-.09,steel)
    # Storage stays anchored as the second water tank is added.
    tank_x=[-2.40]+([-3.55] if level>=2 else [])
    for i,xx in enumerate(tank_x):
        frac_water_tank(K,'water_'+str(i),xx,1.20);tag('water_'+str(i))
    # Blender: open mixing hopper over a supported drive and slurry outlet.
    bx,by=-2.40,-1.15
    for side in (-1,1):K.box('blender_runner',bx+side*.38,by,.07,.12,1.02,.14,steel)
    K.box('blender_lower',bx,by,.36,.90,.88,.44,grey)
    K.box('blender_drive',bx-.27,by,.66,.30,.46,.20,steel)
    K.washer('blender_tub',(bx+.08,by,.74),(0,0,1),.27,.32,.36,accent,seg=24)
    K.cyl('blender_floor',bx+.08,by,.57,.30,.025,accent,segments=24)
    K.washer('blender_lip',(bx+.08,by,.935),(0,0,1),.265,.35,.04,grey,seg=24)
    noink(K.cyl('blender_opening',bx+.08,by,.62,.262,.012,K.mat('glass'),segments=24))
    K.dircyl('blender_outlet',(bx+.36,by,.35),(bx+.54,by,.35),.075,steel,segments=16)
    K.box('additive_bracket',bx-.36,by+.36,.64,.24,.25,.12,steel)
    K.box('additive_tote',bx-.36,by+.36,.87,.24,.25,.34,K.mat('chalk'))
    pipe('additive_feed',[(bx-.24,by+.36,.80),(bx+.08,by+.36,.80),
                          (bx+.08,by+.24,.80)],.024)
    tag('blender')
    # Containerized proppant hoppers: tapered outlets and exposed braced trestles.
    # Bin width D=.96m, legs H=1.40D, body H=1.15D (L3 1.77D).
    sx,sy=-2.40,-2.40
    sand_x=[sx]+([sx-1.22] if level>=2 else [])
    top=3.10 if level==3 else 2.50
    for i,xx in enumerate(sand_x):
        name='sand_bin_'+str(i)
        for dx in (-.44,.44):
            for dy in (-.44,.44):
                K.box(name+'_leg',xx+dx,sy+dy,.70,.095,.095,1.40,steel)
                K.box(name+'_foot',xx+dx,sy+dy,.04,.20,.20,.08,steel)
        K.sqcol(name+'_hopper',xx,sy,.77,1.40,.20,.96,accent)
        K.box(name+'_body',xx,sy,(1.40+top)/2,.96,.96,top-1.40,accent)
        K.box(name+'_lid',xx,sy,top+.035,1.03,1.03,.07,steel)
        for z in (1.40,top-.08):K.box(name+'_band',xx,sy,z,1.0,1.0,.075,steel)
        K._fine_mode=True
        for dx in (-.455,.455):
            for dy in (-.455,.455):
                K.box(name+'_corner',xx+dx,sy+dy,(1.40+top)/2,.065,.065,top-1.40,steel)
        # Front diagonal braces remain below the tapered bin and clear the auger.
        for dy in (-.44,.44):
            K.dircyl(name+'_brace',(xx-.44,sy+dy,.18),(xx+.44,sy+dy,1.35),.026,steel,segments=6,smooth=False)
        K._fine_mode=False
        K.dircyl(name+'_outlet',(xx,sy,.67),(xx,sy,.82),.095,steel,segments=16)
    if level>=2:
        pipe('sand_crossfeed',[(sand_x[1],sy,.70),(sx,sy,.70),(sx,sy,.77)],.09)
        foot('sand_transfer_support',(sand_x[1]+sx)/2,sy,.64,.10)
    if level==3:
        K._fine_mode=True
        K.ladder('sand_access',sand_x[1]-.55,sy,.10,top+.08,face='-X',w=.24,mat=steel)
        for z in (.40,1.55,2.85):K.box('sand_ladder_mount',sand_x[1]-.50,sy,z,.12,.22,.05,steel)
        K._fine_mode=False
    pipe('sand_auger',[(sx,sy,.77),(sx,sy+.20,.77),(bx+.08,by-.14,1.30),
                       (bx+.08,by-.14,.76)],.10)
    K.cyl('sand_auger_motor',sx,sy-.15,.77,.115,.30,steel,axis='Y',segments=20)
    foot('auger_support',sx,sy+.27,.70,.10)
    tag('sand')
    # Water collector takes only water; its inlet meets the blender's lower body.
    for i,xx in enumerate(tank_x):
        pipe('water_feed_'+str(i),[(xx,.10,.32),(xx,-.03,.32)],.07)
    if level>=2:pipe('water_collector',[(tank_x[-1],-.03,.32),(bx,-.03,.32)],.07)
    pipe('water_to_blender',[(bx,-.03,.32),(bx,by+.40,.32)],.07)
    tag('water_feed')
    # All pump ports point toward two distinct pressure lanes.
    rows=[-1.40+i*1.40 for i in range(level+1)]
    for i,yy in enumerate(rows):
        frac_pump(K,'frac_pump_'+str(i),-.10,yy);tag('pump_'+str(i))
        pipe('pump_suction_'+str(i),[(.54,yy,.94),(.54,yy,.35),(1.03,yy,.35)],.07)
        pipe('pump_discharge_'+str(i),[(.78,yy,1.10),(1.23,yy,1.10),(1.23,yy,.70),(1.45,yy,.70)],.055)
        tag('pump_lines_'+str(i))
    end=rows[-1]+.32
    pipe('low_pressure_header',[(1.03,-1.72,.35),(1.03,end,.35)],.085)
    pipe('blender_slurry',[(bx+.54,by,.35),(-1.59,by,.35),(-1.59,-2.12,.35),
                           (1.03,-2.12,.35),(1.03,-1.72,.35)],.07)
    for yy in (-1.62,end-.10):foot('suction_support',1.03,yy,.30,.10)
    tag('low_pressure')
    pipe('high_pressure_header',[(1.45,-1.78,.70),(1.45,end,.70)],.065)
    for yy in (-1.64,end-.10):foot('pressure_support',1.45,yy,.65,.10)
    tag('high_pressure')
    pipe('pressure_trunk',[(1.45,-1.78,.70),(1.45,-2.08,.70),(1.96,-2.08,.70),(1.96,-1.72,.70)],.065)
    pipe('zipper_manifold',[(1.96,-1.72,.70),(1.96,(level-1)*1.40-1.40+.30,.70)],.065)
    for yy in (-1.65,(level-1)*1.40-1.40+.20):foot('zipper_support',1.96,yy,.65,.10)
    tag('manifold')
    for i in range(level):
        yy=-1.40+i*1.40
        frac_tree(K,'frac_tree_'+str(i),2.95,yy);tag('tree_'+str(i))
        pipe('well_branch_'+str(i),[(1.96,yy,.70),(2.44,yy,.70),(2.44,yy,1.27),(2.67,yy,1.27)],.065)
        K.box('well_isolation_'+str(i),2.20,yy,.70,.19,.19,.20,accent)
        K.cyl('well_valve_stem_'+str(i),2.20,yy,.91,.028,.23,steel,segments=12)
        K.washer('well_valve_wheel_'+str(i),(2.20,yy,1.04),(0,0,1),.08,.13,.025,accent,seg=16)
        K.dircyl('valve_spoke_'+str(i),(2.08,yy,1.04),(2.32,yy,1.04),.015,steel,segments=8)
        K.cyl('well_check_valve_'+str(i),2.44,yy,.96,.10,.19,grey,segments=16)
        foot('branch_support_'+str(i),2.20,yy,.60,.10)
        tag('well_branch_'+str(i))
    # Control panel stays in a service gap. L3 gains a separate control shelter.
    K.box('control_foot',-1.73,-.38,.045,.48,.32,.09,steel)
    K.box('control_cabinet',-1.73,-.38,.43,.40,.25,.68,grey)
    K._fine_mode=True
    K.box('control_display',-1.73,-.514,.54,.27,.022,.19,K.mat('glass'))
    K._fine_mode=False
    tag('controls')
    if level==3:
        K.box('control_shelter',-3.68,-1.16,.64,.82,1.14,1.28,K.mat('chalk'))
        K.box('control_roof',-3.68,-1.16,1.31,.92,1.24,.06,K.mat('equipment_black'))
        K._fine_mode=True
        K.window('control_window','+X',(-3.257,-1.35,.89),.43,.35,cols=2,rows=1)
        K.door('control_door','-Y',(-3.68,-1.744,.40),.35,.78)
        K._fine_mode=False
        tag('shelter')
    return finish(K,level)


def valve(K,name,x,y,z):
    K.cyl(name+'_stem',x,y,z+.10,.035,.20,K.mat('silver'))
    K.cyl(name+'_wheel',x,y,z+.21,.115,.035,K.mat('terracotta'),segments=16)
    noink(K.cyl(name+'_hub',x,y,z+.232,.052,.012,K.mat('darkmetal'),segments=12))


def water_tower(K, x=2.85, y=2.38):
    """Elevated storage: four braced legs, hopper bottom, tank and service balcony.

    Tank D=1.32; shell .62D tall, floor 2.2D above ground. Supports splay
    from .78D at the feet to .60D at the tank. The air below is the level cue.
    """
    steel=K.mat('darkmetal')
    for sx in (-1,1):
        for sy in (-1,1):
            K.box('tower_foot',x+sx*.52,y+sy*.52,.09,.25,.25,.18,K.mat('chalk'))
            K.dircyl('tower_leg',(x+sx*.52,y+sy*.52,.12),
                     (x+sx*.40,y+sy*.40,2.92),.065,steel,segments=8,smooth=False)
    K._fine_mode=True
    for axis in ('X','Y'):
        for side in (-1,1):
            for a,b in ((-1,1),(1,-1)):
                if axis=='X':
                    p=(x+a*.51,y+side*.51,.40); q=(x+b*.41,y+side*.41,2.65)
                else:
                    p=(x+side*.51,y+a*.51,.40); q=(x+side*.41,y+b*.41,2.65)
                K.dircyl('tower_crossbrace',p,q,.028,steel,segments=6,smooth=False)
    K._fine_mode=False
    K.cone('tower_hopper',x,y,2.79,.22,.66,.26,K.mat('tank_grey'))
    K.cyl('tower_tank',x,y,3.31,.66,.82,K.mat('chalk'))
    K.dome_cap('tower_roof',x,y,3.72,.70,.20,K.mat('roof'))
    K.cyl('tower_roof_rim',x,y,3.72,.70,.06,steel)
    K._fine_mode=True
    for z in (2.94,3.48): K.seam('tower_shell_band',x,y,z,.672)
    K.tank_balcony('tower_access',x,y,2.93,.66,width=.17,mat=steel)
    K.ladder('tower_ladder',x+.56,y-.40,.18,2.98,face='+X',w=.22,rung=.23,mat=steel)
    K.pipe_run('tower_riser',[(2.0,1.26,.48),(2.0,2.38,.48),(x,2.38,.48),(x,y,2.71)],
               .095,bend=.18,ends=('collar','collar'))
    K._fine_mode=False


def build_water_pump(level=1):
    K=begin('water_pump')
    house(K,'pump_house',.40,1.04,1.65,1.30,1.28,wall='chalk',rise=.38)
    K.door('service_door','-Y',(.72,.39,.47),.45,.94,ribs=3)
    K.window('control_window','-Y',(-.07,.39,.85),.48,.45,cols=2,rows=2)
    K.window('side_window','+X',(1.225,1.04,.82),.56,.48,cols=3,rows=2)
    basin(K,'intake',-1.65,.25,1.13,2.65)
    # Grating bridges the wet well; the pipe really enters the water.
    K._fine_mode=True
    for i in range(7): K.box('intake_grate%d'%i,-1.65,.50+i*.10,.46,1.04,.038,.04,K.mat('darkmetal'))
    # The previously shown L3 becomes L2, with all three pumps and switchgear.
    n=1 if level==1 else 3
    for i in range(n):
        x=-.56+i*.86
        K.pump_skid('duty_pump%d'%i,x,-.83,scale=1.45,mat=K.mat('terracotta'))
        K.pipe_run('pump_branch%d'%i,[(x+.19,-.83,.48),(x+.19,-.35,.48)],.072,bend=.14)
        valve(K,'isolation%d'%i,x+.19,-.37,.48)
        K.pipe_run('suction_branch%d'%i,[(x-.15,-.83,.27),(x-.15,-1.17,.27)],.065,bend=.12)
    K.pipe_run('suction_header',[(-1.25,-1.17,.27),(-.71+(n-1)*.86,-1.17,.27)],.09,bend=.12)
    K.pipe_run('suction',[(-1.65,-.62,.23),(-1.65,-.62,.65),(-1.25,-.62,.65),(-1.25,-1.17,.65),(-1.25,-1.17,.27)],.13,bend=.16)
    K.pipe_run('delivery',[(-.37,-.35,.48),(1.70,-.35,.48),(1.70,.57,.48)],.13,bend=.20)
    # Delivery terminates in a capped underground network connection.
    K.pipe_run('outlet',[(1.70,.57,.48),(2.13,.57,.48),(2.13,.57,.08)],.13,bend=.18,ends=('','flange'))
    K._fine_mode=False
    if level>=2:
        silo(K,'surge_vessel',2.0,1.26,h=1.82)
        K.pipe_run('surge_link',[(1.70,.57,.48),(1.70,1.26,.48),(2.0,1.26,.48)],.075,bend=.13)
    if level>=2:
        K.box('switchgear',2.08,-.99,.52,.58,.42,1.04,K.mat('steel_navy'))
        K._fine_mode=True
        for x in (1.98,2.18):
            K.box('cabinet_seam'+str(x),x,-1.219,.51,.018,.016,.88,K.mat('mullion'))
        K.box('meter',1.91,-1.23,.80,.12,.025,.12,K.mat('glass'))
        K._fine_mode=False
    if level>=3:
        water_tower(K)
    return finish(K,level)


def membrane_rack(K,name,x,y,count):
    K._fine_mode=True
    for yy in (y-.58,y+.58):
        for xx in (x-.52,x+.52): K.box(name+'_leg',xx,yy,.52,.08,.08,1.04,K.mat('darkmetal'))
        for z in (.19,.63,1.04): K.box(name+'_rail',x,yy,z,1.20,.09,.07,K.mat('darkmetal'))
    for row in range(2):
        for col in range(count):
            xx=x+(col-(count-1)/2)*.29
            z=.38+row*.44
            K.cyl(name+'_membrane',xx,y,z,.112,1.42,K.mat('silver'),axis='Y',segments=24)
            for yy in (y-.73,y+.73):
                K.cyl(name+'_endcap',xx,yy,z,.121,.065,K.mat('steel_navy'),axis='Y',segments=24)
                K.pipe_run(name+'_port',[(xx,yy,z),(xx,yy+(-.06 if yy<y else .06),z)],.027,bend=.04)
    for col in range(count):
        xx=x+(col-(count-1)/2)*.29
        K.pipe_run(name+'_riser',[(xx,y-.79,.38),(xx,y-.79,.82)],.031,bend=.06)
        K.pipe_run(name+'_rear_riser',[(xx,y+.79,.38),(xx,y+.79,.82)],.031,bend=.06)
    K.pipe_run(name+'_rear_header',[(x-.5,y+.79,.55),(x+.55,y+.79,.55)],.054,bend=.10)
    K.pipe_run(name+'_header',[(x-.5,y-.79,.55),(x+.55,y-.79,.55)],.054,bend=.10)
    K._fine_mode=False


def build_desal(level=1):
    K=begin('desal')
    house(K,'process_hall',.75,1.22,2.45,1.42,1.34,wall='chalk',rise=.15)
    K.door('control_entry','-Y',(1.62,.51,.48),.45,.96,ribs=3)
    for x in (-.14,.54): K.window('hall_window'+str(x),'-Y',(x,.51,.91),.51,.44,cols=3,rows=1)
    basin(K,'seawater',-2.23,-.58,1.22,2.48)
    K._fine_mode=True
    for y in (-1.35,-.69,-.03): K.box('screen'+str(y),-2.23,y,.46,1.12,.065,.045,K.mat('darkmetal'))
    K._fine_mode=False
    membrane_rack(K,'RO_A',-.86,-.67,3)
    if level>=2: membrane_rack(K,'RO_B',.57,-.67,3)
    K.flat_tank('freshwater',2.23,1.23,.54,1.80,band=False,stair=False,vent=True,mat=K.mat('tank_grey'))
    K._fine_mode=True
    K.ladder('tank_access',2.79,1.23,.10,1.91,w=.22,mat=K.mat('darkmetal'))
    K.ring_rail('tank_rail',2.23,1.23,1.91,.52,h=.18,posts=8)
    K.pump_skid('high_pressure',-1.15,-1.66,scale=1.25,mat=K.mat('terracotta'))
    K.pipe_run('feed',[(-2.23,-1.53,.26),(-2.23,-1.53,.55),(-1.13,-1.53,.55),(-1.13,-1.4,.55)],.085,bend=.16)
    K.pipe_run('product',[(-.30,-1.46,.55),(2.30,-1.46,.55),(2.30,1.23,.55)],.075,bend=.17)
    for x in (-.8,.63,1.85): valve(K,'valve'+str(x),x,-1.46,.55)
    # Distinct brine return, turning down into the site boundary.
    K.pipe_run('brine',[(-1.36,.12,.55),(-1.70,.12,.55),(-1.70,1.72,.55),(-2.7,1.72,.55),(-2.7,1.72,.09)],.065,bend=.16)
    if level>=2:
        K.pipe_run('rear_collector',[(-.31,.12,.55),(1.12,.12,.55)],.054,bend=.10)
    K._fine_mode=False
    if level>=3:
        # New visible capability: vertical pretreatment filters, no chimney/cooling tower.
        for i in range(3):
            x=-2.35+i*.63
            K.cyl('filter%d'%i,x,1.26,.93,.235,1.66,K.mat('steel_navy'))
            K.dome_cap('filter_cap%d'%i,x,1.26,1.76,.235,.12,K.mat('tank_grey'))
            K._fine_mode=True
            K.pipe_run('filter_in%d'%i,[(x,1.26,.40),(x,1.78,.40)],.05,bend=.10)
            K._fine_mode=False
        K.pipe_run('filter_manifold',[(-2.35,1.78,.40),(-.52,1.78,.40)],.085,bend=.12)
        K.box('recovery_unit',1.65,-.63,.39,.53,.66,.78,K.mat('terracotta'))
        K.pipe_run('recovery_link',[(1.65,-.96,.30),(1.65,-1.46,.30),(1.65,-1.46,.55)],.06,bend=.10)
    return finish(K,level)


def woodland(level,old):
    name='old_forest' if old else 'new_forest'
    K=begin(name)
    if old:
        # Stronger, local recesses in old crowns; the lit foliage retains the kit hue.
        shade=K.mat('canopy_dark')
        shade.diffuse_color=(.065,.135,.045,1)
        shade.node_tree.nodes.get('Principled BSDF').inputs['Base Color'].default_value=(.065,.135,.045,1)
    count={1:6,2:9,3:12}[level]
    rng=random.Random(431 if old else 173)
    # Permanent positions: successive levels add trees without relocating existing ones.
    sites=[(-1.9,.9),(-.45,1.05),(1.25,1.20),(-2.1,-.75),(-.65,-.53),(1.2,-.46),
           (-1.25,1.60),(.38,1.63),(2.15,.6),(-2.25,.15),(.20,-1.23),(2.13,-.90)]
    for i,(x,y) in enumerate(sites[:count]):
        h=(2.8 if old else 1.8)*rng.uniform(.83,1.13)
        r=(.58 if old else .36)*rng.uniform(.87,1.12)
        # Mature branching silhouette vs visibly spaced plantation saplings.
        K.tree('tree%d'%i,x,y,h=h,r=r,seed=1200+i*37+(100 if old else 0))
        if not old:
            K._fine_mode=True
            K.box('guard%d'%i,x+.12,y,.32,.035,.035,.64,K.mat('mullion'))
            K._fine_mode=False
    K._fine_mode=True
    if old:
        K.cyl('fallen_log',1.72,-1.22,.19,.16,.95,K.mat('bark'),axis='X',segments=10,smooth=False)
        for x in (1.24,2.20): K.cyl('cut_wood',x,-1.22,.19,.145,.012,K.mat('earth'),axis='X',segments=10,smooth=False)
        for i in range(4):
            K._blob('undergrowth%d'%i,-2.1+i*1.25,-1.1,.16,.18,K.mat('canopy_dark'),random.Random(i+4),scale=(1,.8,.6))
    else:
        K.box('nursery_sign',-.42,-1.48,.52,.52,.045,.24,K.mat('chalk'))
        for x in (-.61,-.23): K.box('sign_post',x,-1.48,.25,.04,.04,.50,K.mat('bark'))
    K._fine_mode=False
    return finish(K,level)


def build_new_forest(level=1): return woodland(level,False)
def build_old_forest(level=1): return woodland(level,True)


def build_offshore_oil_platform(level=1):
    """Fixed-jacket platform. Deck D=5.6m, L1 depth .68D, L2 depth 1.02D.
    L2 extends the front with two process vessels (.10D diameter) and compressor;
    L3 adds a raised rear module, paired process columns and two more piers.
    All earlier equipment keeps its coordinates. Owner: better crane-base outlining.
    Four separate lattice piers carry the deck; open derrick height .61D above drill floor.
    Crown, travelling block, drillstring and conductor share one well axis.
    The deck is a load-bearing part of the platform, never a seabed/ground tile.
    """
    assert level in (1,2,3), 'Offshore level must be 1, 2 or 3'
    front=-3.80 if level>=2 else -1.90
    rear=3.90 if level==3 else 1.90
    pier_rows=(-1,1,-2,2) if level==3 else ((-1,1,-2) if level>=2 else (-1,1))
    K=begin('offshore_oil_platform')
    steel,grey=K.mat('equipment_black'),K.mat('tank_grey')
    yellow,red=K.mat('equipment_yellow'),K.mat('offshore_red')
    chalk=K.mat('chalk')
    seen=set(K.col.objects)
    def tag(group):
        nonlocal seen
        for ob in set(K.col.objects)-seen:ob['assembly']=group
        seen=set(K.col.objects)
    def rod(name,p,q,r=.04,mat=None):
        return K.dircyl(name,p,q,r,mat or steel,segments=8,smooth=False)
    def rail(name,p,q):
        p,q=Vector(p),Vector(q)
        for z in (.20,.40):rod(name+'_bar',p+Vector((0,0,z)),q+Vector((0,0,z)),.019,yellow)
        n=max(1,math.ceil((p-q).length/.55))
        for i in range(n+1):
            v=p.lerp(q,i/n);rod(name+'_post',v,v+Vector((0,0,.41)),.021,yellow)
    def open_floor(name,cx,cy,z,w,d,hole,t,mat):
        # Four panels around a real square well opening.
        for sign in (-1,1):
            K.box(name+'_side',cx+sign*(w+hole)/4,cy,z,(w-hole)/2,d,t,mat)
            K.box(name+'_end',cx,cy+sign*(d+hole)/4,z,hole,(d-hole)/2,t,mat)
    # Owner reference: separate scaffolding-like pillars. Each is a narrow
    # four-chord lattice pier; braces stay inside its footprint, leaving open bays.
    for sx in (-1,1):
        for sy in pier_rows:
            px,py=sx*2.25,(-3.20 if sy==-2 else (3.20 if sy==2 else sy*1.40))
            prefix='lattice_pier_%s_%s'%(sx,sy)
            for dx in (-.31,.31):
                for dy in (-.31,.31):
                    K.cyl(prefix+'_chord',px+dx,py+dy,.98,.052,1.96,steel,segments=12)
            for side in (-1,1):
                K.box(prefix+'_head_x',px,py+side*.31,1.98,.76,.14,.14,steel)
                K.box(prefix+'_head_y',px+side*.31,py,1.98,.14,.76,.14,steel)
            K._fine_mode=True
            for axis in (0,1):
                for side in (-1,1):
                    def node(sign,z):
                        return (px+sign*.31,py+side*.31,z) if axis==0 else (px+side*.31,py+sign*.31,z)
                    for z in (.10,.98,1.88):rod(prefix+'_rail',node(-1,z),node(1,z),.030,steel)
                    # Opposing diagonal directions over two storeys, joined at rail nodes.
                    rod(prefix+'_brace',node(-1,.10),node(1,.98),.031,steel)
                    rod(prefix+'_brace',node(1,.98),node(-1,1.88),.031,steel)
            K._fine_mode=False
    for yy in [-1.40,1.40]+([-3.20] if level>=2 else [])+([3.20] if level==3 else []):K.box('deck_primary_beam',0,yy,1.97,5.6,.22,.30,steel)
    for xx in (-2.25,-1.1,.25,1.45,2.25):K.box('deck_crossbeam',xx,(front+rear)/2,2.04,.16,rear-front,.16,steel)
    # One welded deck mesh with actual well and service-pipe penetrations.
    holes=[(.55,.95,.25,.65),(1.59,1.79,.72,.92)]
    if level>=2:holes += [(2.40,2.60,-.75,-.55),(-.30,-.10,-2.52,-2.32),
                         (-.32,-.12,-3.02,-2.82),(.48,.68,-3.00,-2.80)]
    if level==3:holes += [(-.85,-.65,3.68,3.82)]
    xs=sorted(set([-2.8,2.8]+[h[i] for h in holes for i in (0,1)]))
    ys=sorted(set([front,rear]+[h[i] for h in holes for i in (2,3)]))
    cells={(i,j) for i in range(len(xs)-1) for j in range(len(ys)-1)
           if not any(h[0]<(xs[i]+xs[i+1])/2<h[1] and h[2]<(ys[j]+ys[j+1])/2<h[3] for h in holes)}
    verts=[];faces=[];indices={}
    def vert(pt):
        if pt not in indices:indices[pt]=len(verts);verts.append(pt)
        return indices[pt]
    def face(pts):faces.append([vert(pt) for pt in pts])
    for i,j in cells:
        x0,x1=xs[i:i+2];y0,y1=ys[j:j+2];z0,z1=2.10,2.22
        face([(x0,y0,z1),(x1,y0,z1),(x1,y1,z1),(x0,y1,z1)])
        face([(x0,y1,z0),(x1,y1,z0),(x1,y0,z0),(x0,y0,z0)])
        if (i-1,j) not in cells:face([(x0,y0,z0),(x0,y0,z1),(x0,y1,z1),(x0,y1,z0)])
        if (i+1,j) not in cells:face([(x1,y1,z0),(x1,y1,z1),(x1,y0,z1),(x1,y0,z0)])
        if (i,j-1) not in cells:face([(x1,y0,z0),(x1,y0,z1),(x0,y0,z1),(x0,y0,z0)])
        if (i,j+1) not in cells:face([(x0,y1,z0),(x0,y1,z1),(x1,y1,z1),(x1,y1,z0)])
    mesh=bpy.data.meshes.new('main_deck');mesh.from_pydata(verts,[],faces);mesh.update()
    K.obj('main_deck',mesh,grey)
    for yy in (front,rear):K.box('deck_edge',0,yy,2.14,5.65,.085,.20,yellow)
    for xx in (-2.8,2.8):K.box('deck_edge',xx,(front+rear)/2,2.14,.085,rear-front,.20,yellow)
    tag('structure')
    # Accommodation block and cantilever helideck at the opposite end from flare.
    K.box('quarters',-1.75,-.22,2.75,1.72,1.90,1.06,chalk)
    K.box('quarters_roof',-1.75,-.22,3.31,1.80,1.98,.06,red)
    K._fine_mode=True
    for xx in (-2.28,-1.76,-1.24):K.window('quarters_window','-Y',(xx,-1.182,2.93),.32,.25,cols=1,rows=1)
    K.door('quarters_door','+X',(-.881,-.51,2.58),.39,.70)
    K.box('quarters_vent',-.84,.58,3.04,.12,.26,.26,steel)
    K._fine_mode=False
    hx,hy=-2.20,-.14
    K.box('helideck',hx,hy,3.42,2.38,2.38,.14,K.mat('helideck_green'))
    for yy in (-.80,.54):
        K.box('helideck_girder',hx,yy,3.34,2.28,.11,.12,steel)
        rod('helideck_cantilever',(-2.51,yy,2.22),(-3.28,yy,3.34),.06,steel)
    K._fine_mode=True
    for side in (-1,1):
        noink(K.box('helipad_square',hx+side*.75,hy,3.496,.04,1.54,.008,chalk))
        noink(K.box('helipad_square',hx,hy+side*.75,3.496,1.54,.04,.008,chalk))
    for xx in (-.22,.22):noink(K.box('helipad_H',hx+xx,hy,3.500,.095,.70,.008,chalk))
    noink(K.box('helipad_H_cross',hx,hy,3.501,.44,.095,.008,chalk))
    # A low safety-net rim avoids railings projecting into the landing surface.
    for side in (-1,1):
        rod('helideck_net_rim',(hx+side*1.25,hy-1.25,3.38),(hx+side*1.25,hy+1.25,3.38),.022,steel)
        rod('helideck_net_rim',(hx-1.25,hy+side*1.25,3.38),(hx+1.25,hy+side*1.25,3.38),.022,steel)
        for offset in (-1.14,0,1.14):
            rod('helideck_net_spoke',(hx+side*1.14,hy+offset,3.38),(hx+side*1.25,hy+offset,3.38),.020,steel)
            rod('helideck_net_spoke',(hx+offset,hy+side*1.14,3.38),(hx+offset,hy+side*1.25,3.38),.020,steel)
    K._fine_mode=False
    K._fine_mode=True
    K.ladder('helideck_access',-.78,.25,2.22,3.51,face='+X',w=.28,mat=steel)
    for z in (2.45,3.14):K.box('helideck_ladder_mount',-.84,.25,z,.14,.27,.04,steel)
    K.box('helideck_access_landing',-.995,.25,3.46,.49,.38,.06,steel)
    K._fine_mode=False
    tag('quarters_helideck')
    # Raised drill floor on four legs, with an unbroken open well axis.
    dx,dy=.75,.45
    for sx in (-1,1):
        for sy in (-1,1):K.box('drill_floor_leg',dx+sx*.62,dy+sy*.62,2.54,.15,.15,.64,steel)
    open_floor('drill_floor',dx,dy,2.89,1.50,1.50,.24,.14,grey)
    # Open tapered derrick. Each diagonal is on a face, never across the bore.
    base,top=2.96,6.36
    def mp(sx,sy,z):
        half=.62-(.62-.23)*(z-base)/(top-base)
        return (dx+sx*half,dy+sy*half,z)
    for sx in (-1,1):
        for sy in (-1,1):rod('derrick_chord',mp(sx,sy,base),mp(sx,sy,top),.055,red)
    K._fine_mode=True
    for j in range(5):
        z0=base+j*(top-base)/5;z1=base+(j+1)*(top-base)/5
        for axis in (0,1):
            for side in (-1,1):
                a=mp(-1,side,z0) if axis==0 else mp(side,-1,z0)
                b=mp(1,side,z1) if axis==0 else mp(side,1,z1)
                c=mp(-1,side,z1) if axis==0 else mp(side,-1,z1)
                rod('derrick_brace',a,b,.023,red)
                # Rear top bay is open for the fast line; the crown frame ties its heads.
                if not (j==4 and axis==0 and side==1):rod('derrick_rail',c,b,.028,red)
    K._fine_mode=False
    # Two bearing girders leave the reeving path open through the crown.
    for xx in (dx-.24,dx+.24):
        K.box('crown_girder',xx,dy,6.40,.11,.64,.12,steel)
        K.box('crown_bearing',xx,dy,6.53,.11,.22,.17,red)
    K.cyl('crown_axle',dx,dy,6.58,.041,.58,steel,axis='X',segments=16)
    K.cyl('crown_sheave',dx,dy,6.58,.14,.21,grey,axis='X',segments=24)
    K.cyl('travelling_sheave',dx,dy,5.34,.14,.20,grey,axis='X',segments=24)
    K.cyl('travelling_axle',dx,dy,5.34,.038,.30,steel,axis='X',segments=16)
    for xx in (dx-.13,dx+.13):
        K.box('travelling_cheek',xx,dy,5.34,.04,.36,.36,yellow)
        rod('block_clevis',(xx,dy,5.16),(dx,dy,5.02),.032,steel)
    K.cyl('top_drive',dx,dy,4.86,.11,.32,steel,segments=16)
    K.cyl('drillstring',dx,dy,2.85,.033,3.70,grey,segments=12)
    # A dead-end crossbar is tied back to the two rear mast heads.
    K.box('deadline_anchor',dx,dy+.152,6.24,.54,.065,.08,steel)
    for xx in (dx-.24,dx+.24):K.box('deadline_bracket',xx,dy+.20,6.24,.075,.14,.08,steel)
    K.cyl('conductor',dx,dy,.73,.092,1.46,steel,segments=20)
    K.cyl('BOP',dx,dy,1.65,.17,.38,red,segments=16)
    K.cyl('well_riser',dx,dy,2.25,.10,.82,steel,segments=16)
    K.washer('rotary_table',(dx,dy,2.976),(0,0,1),.055,.18,.025,steel,seg=24)
    # Drawworks on its own raised, supported rear shelf. Fast line outside mast.
    K.box('drawworks_shelf',dx,1.55,2.89,1.05,.64,.14,steel)
    for xx in (dx-.43,dx+.43):K.box('drawworks_shelf_leg',xx,1.67,2.55,.11,.11,.66,steel)
    for xx in (dx-.28,dx+.28):K.box('drawworks_bearing',xx,1.55,3.095,.10,.40,.27,red)
    K.cyl('drawworks_drum',dx,1.55,3.17,.18,.51,steel,axis='X',segments=20)
    # Exact tangent from the drum to the crown, then wrap and return around the
    # travelling sheave. One continuous rope, ending on the dead-end crossbar.
    radius=.152
    vy,vz=1.55-dy,3.35-6.58
    tangent=math.atan2(vz,vy)+math.acos(radius/math.hypot(vy,vz))
    rope=[(dx,1.55,3.35)]
    for i in range(19):
        angle=tangent+(math.pi-tangent)*i/18
        rope.append((dx,dy+radius*math.cos(angle),6.58+radius*math.sin(angle)))
    rope.append((dx,dy-radius,5.34))
    for i in range(1,19):
        angle=math.pi+math.pi*i/18
        rope.append((dx,dy+radius*math.cos(angle),5.34+radius*math.sin(angle)))
    rope.append((dx,dy+radius,6.20))
    K._fine_mode=True
    for i,(a,b) in enumerate(zip(rope,rope[1:])):noink(rod('reeving_'+str(i),a,b,.013,steel))
    K._fine_mode=False
    tag('drilling')
    # Access stairs stay outside the well axis and meet the drill-floor edge.
    for i in range(6):K.box('drill_stair',.75,-1.32+i*.18,2.26+i*.12,.58,.22,.08,grey)
    for xx in (.45,1.05):rod('stair_stringer',(xx,-1.43,2.22),(xx,-.34,2.88),.045,steel)
    K._fine_mode=True
    for xx in (.44,1.06):rail('stair_rail',(xx,-1.39,2.30),(xx,-.36,2.91))
    K._fine_mode=False
    tag('stairs')
    # Small process separator, pipe connection to the well and an export riser.
    for yy in (-.20,.63):K.box('separator_saddle',2.12,yy,2.36,.51,.14,.28,steel)
    K.cyl('separator',2.12,.22,2.65,.30,1.20,grey,axis='Y',segments=24)
    K.cyl('separator_hatch',2.12,.22,2.98,.12,.075,steel,segments=16)
    K.pipe_run('production_line',[(dx+.15,dy,1.65),(1.69,dy,1.65),(1.69,.82,1.65),
        (1.69,.82,2.65),(2.12,.82,2.65)],.050,mat=steel,bend=.12,ends=('',''))
    K.pipe_run('export_line',[(2.12,-.38,2.65),(2.12,-.65,2.65),(2.12,-.65,2.80),
        (2.98,-.65,2.80),(2.98,-.65,.04)],.055,mat=steel,bend=.12,ends=('',''))
    tag('process')
    # Small pedestal crane: pivot, luffing cylinder, triangulated jib and hanging hook.
    cx,cy=1.96,-1.37
    K.cyl('crane_pedestal',cx,cy,2.57,.20,.70,yellow,segments=20)
    K.cyl('crane_slew',cx,cy,2.96,.27,.10,steel,segments=20)
    # Explicit local joint ink: the cylinder/deck intersection has no mesh edge
    # for Freestyle. A mounting flange and seam rings make the base readable.
    K.cyl('crane_foot_flange',cx,cy,2.25,.255,.06,yellow,segments=32)
    noink(K.seam('crane_foot_seam',cx,cy,2.292,.207,t=.024))
    noink(K.seam('crane_foot_rim',cx,cy,2.239,.258,t=.024))
    noink(K.seam('crane_neck_seam',cx,cy,2.892,.207,t=.024))
    K.box('crane_body',cx,cy,3.14,.56,.43,.30,yellow)
    K.box('crane_counterweight',cx-.35,cy,3.15,.23,.50,.30,steel)
    p,q=Vector((cx+.18,cy,3.25)),Vector((3.75,-2.20,5.15))
    side=Vector((-(q-p).y,(q-p).x,0)).normalized()*.12
    # Closed root triangle and transverse hinge tie all three chords to the body.
    rod('crane_root_hinge',p-side*1.60,p+side*1.60,.070,steel)
    for offset in (-side,side):rod('crane_root_frame',p+offset,p+Vector((0,0,.22)),.033,yellow)
    for offset in (-side*1.40,side*1.40):
        K.box('crane_root_cheek',p.x+offset.x,p.y+offset.y,3.26,.17,.14,.25,yellow)
    for offset in (-side,side):rod('crane_boom_chord',p+offset,q+offset,.033,yellow)
    rod('crane_boom_top',p+Vector((0,0,.22)),q+Vector((0,0,.10)),.033,yellow)
    K._fine_mode=True
    for i in range(5):
        a=p.lerp(q,i/5);b=p.lerp(q,(i+1)/5)
        rod('crane_boom_brace',a-side,b+side,.018,yellow)
        rod('crane_boom_brace',a+side,a+Vector((0,0,.22-.12*i/5)),.018,yellow)
    rod('crane_tip_axle',q-side,q+side,.034,steel)
    for offset in (-side,side):rod('crane_tip_crosshead',q+offset,q+Vector((0,0,.10)),.028,yellow)
    K.dircyl('crane_tip_sheave',q-side*.42,q+side*.42,.095,grey,segments=20)
    forward=Vector(((q-p).x,(q-p).y,0)).normalized()
    rope_top=q+forward*.108
    rod('crane_rope',rope_top,(rope_top.x,rope_top.y,2.92),.017,steel)
    K.washer('crane_hook',(rope_top.x,rope_top.y,2.84),(0,1,0),.048,.078,.036,steel,seg=16)
    # Outboard hydraulic ram: clear of every face of the lattice, with its own
    # body-side trunnion and an overhung pin at the .4 panel station.
    normal=side.normalized()
    lug=p.lerp(q,.40)
    ram_top=lug+normal*.28
    ram_base=Vector((cx+.06,cy,3.04))+normal*.28
    rod('crane_luff_pin',lug+side,ram_top+normal*.045,.055,grey)
    rod('crane_ram_trunnion',ram_base-normal*.13,ram_base+normal*.06,.065,steel)
    rod('crane_luff_cylinder',ram_base,ram_top,.050,grey)
    K._fine_mode=False
    tag('crane')
    # Outboard flare on the far corner, separated from accommodation and helipad.
    p,q=Vector((2.27,1.46,2.34)),Vector((3.00,3.20,3.64))
    K.box('flare_root',p.x,p.y,2.28,.40,.40,.12,steel)
    side=Vector((-(q-p).y,(q-p).x,0)).normalized()*.15
    for offset in (-side,side):rod('flare_chord',p+offset,q+offset,.039,steel)
    rod('flare_upper_chord',p+Vector((0,0,.32)),q+Vector((0,0,.17)),.039,steel)
    K._fine_mode=True
    # Close every triangular bay, including both ends: no free chord ends.
    for i in range(6):
        v=p.lerp(q,i/5);upper=v+Vector((0,0,.32-.15*i/5))
        rod('flare_crossframe',v-side,v+side,.026,steel)
        rod('flare_crossframe',v-side,upper,.026,steel)
        rod('flare_crossframe',v+side,upper,.026,steel)
    # Upright foot at the root carries the raised third chord down to the base.
    rod('flare_root_upright',p,p+Vector((0,0,.32)),.050,steel)
    for i in range(5):
        a=p.lerp(q,i/5);b=p.lerp(q,(i+1)/5)
        rod('flare_lattice',a-side,b+side,.022,steel)
        rod('flare_lattice',a+side,b+Vector((0,0,.32-.15*(i+1)/5)),.022,steel)
    # Feed pipe runs outside the truss instead of converging with its upper chord.
    feed_offset=-side.normalized()*.27
    root_feed=p+feed_offset+Vector((0,0,.15))
    tip_feed=q+feed_offset+Vector((0,0,.20))
    K.pipe_run('flare_feed',[(2.12,.82,2.65),(2.12,1.15,2.65),root_feed,
        tip_feed,(tip_feed.x,tip_feed.y,4.02),(3.00,3.20,4.02)],.038,mat=steel,bend=.06,ends=('',''))
    K.washer('flare_burner_mount',(3.00,3.20,3.86),(0,0,1),.043,.085,.14,steel,seg=20)
    K.cyl('flare_tip',3.00,3.20,4.02,.070,.20,steel,segments=16)
    K._fine_mode=False
    K.cone('flare_flame',3.00,3.20,4.32,.095,.015,.44,K.mat('flame_orange'),segments=9)
    tag('flare')
    if level>=2:
        # Front process module: two dished vessels, with paired bearing saddles.
        # Keep a clear central route from the original stair to the new front rail.
        for i,yy in enumerate((-2.42,-3.22)):
            name='upgrade_vessel_'+str(i)
            K.bullet(name,(-2.15,yy,2.84),(-.75,yy,2.84),.28,saddles=False)
            for xx in (-1.95,-.95):
                K.box(name+'_saddle',xx,yy,2.40,.17,.48,.36,steel)
            K._fine_mode=True
            rod(name+'_gauge_stem',(-1.18,yy,3.10),(-1.18,yy,3.26),.025,steel)
            K.cyl(name+'_gauge',-1.18,yy-.018,3.25,.082,.07,steel,axis='Y',segments=16)
            noink(K.cyl(name+'_gauge_face',-1.18,yy-.057,3.25,.063,.008,chalk,axis='Y',segments=16))
            K._fine_mode=False
            tag(name)
        # Enclosed compressor/cooler package. Dark ventilation and two roof fans
        # provide a different silhouette and clear material hierarchy.
        for xx in (1.02,1.88):K.box('compressor_foot',xx,-2.90,2.28,.15,1.05,.12,steel)
        K.box('compressor_housing',1.45,-2.90,2.84,1.30,1.05,1.00,K.mat('helideck_green'))
        K.box('compressor_roof',1.45,-2.90,3.36,1.38,1.13,.04,grey)
        K._fine_mode=True
        K.box('compressor_grille',1.45,-3.438,2.87,.97,.026,.46,steel)
        for xx in (1.09,1.21,1.33,1.45,1.57,1.69,1.81):
            noink(K.box('compressor_louvre',xx,-3.456,2.87,.033,.012,.40,grey))
        for xx in (1.10,1.80):
            K.cyl('compressor_fan',xx,-2.90,3.397,.205,.034,steel,segments=24)
            noink(K.cyl('compressor_fan_hub',xx,-2.90,3.421,.056,.014,grey,segments=16))
            for aa in (0,math.pi/2):
                rod('compressor_fan_guard',(xx-.17*math.cos(aa),-2.90-.17*math.sin(aa),3.416),
                    (xx+.17*math.cos(aa),-2.90+.17*math.sin(aa),3.416),.012,grey)
        K._fine_mode=False
        tag('compressor')
        # Four connections; the feed crosses beneath the clear central aisle
        # and rises through genuine deck openings, never through solid plating.
        # Only their named terminals may meet equipment from another assembly.
        K.pipe_run('upgrade_feed',[(2.50,-.65,2.80),(2.50,-.65,1.70),(1.72,-.65,1.70),(1.72,-2.02,1.70),
            (-.20,-2.02,1.70),(-.20,-2.42,1.70),(-.20,-2.42,2.84),(-.48,-2.42,2.84)],.045,mat=steel,bend=.10,ends=('',''))
        K.pipe_run('upgrade_interstage',[(-2.42,-2.42,2.84),(-2.60,-2.42,2.84),
            (-2.60,-3.22,2.84),(-2.42,-3.22,2.84)],.04,mat=steel,bend=.07,ends=('',''))
        K.pipe_run('upgrade_compressor_in',[(-.48,-3.22,2.84),(-.22,-3.22,2.84),(-.22,-2.92,2.84),
            (-.22,-2.92,1.70),(.58,-2.92,1.70),(.58,-2.92,2.84),(.81,-2.92,2.84)],.045,mat=steel,bend=.10,ends=('',''))
        K.pipe_run('upgrade_compressor_out',[(2.09,-2.90,3.05),(2.62,-2.90,3.05),
            (2.62,-.65,3.05),(2.98,-.65,3.05),(2.98,-.65,2.79)],.045,mat=steel,bend=.07,ends=('',''))
        tag('upgrade_pipework')
    if level==3:
        # New landmark: a two-level rear treatment module. The four columns
        # bear on the extended main deck; braces stay out of the access stair.
        for xx in (-2.40,0.0):
            for yy in (2.10,3.50):
                K.box('treatment_column',xx,yy,2.95,.14,.14,1.46,steel)
        for yy in (2.10,3.50):K.box('treatment_girder',-1.20,yy,3.61,2.70,.16,.18,steel)
        for xx in (-2.40,0.0):K.box('treatment_crossbeam',xx,2.80,3.63,.16,1.70,.14,steel)
        K.box('treatment_floor',-1.20,2.80,3.71,2.70,1.70,.14,grey)
        K._fine_mode=True
        for yy in (2.10,3.50):
            rod('treatment_brace',(-2.40,yy,2.27),(0.0,yy,3.60),.035,steel)
        rod('treatment_brace',(-2.40,2.10,2.27),(-2.40,3.50,3.60),.035,steel)
        K._fine_mode=False
        tag('treatment_structure')
        # Compact straight stair with a supported side landing and open gate.
        for i in range(9):
            K.box('treatment_stair',.65,2.02+i*.16,2.22+(i+1)*(1.56/9)-.04,.58,.20,.08,grey)
        for xx in (.34,.96):
            rod('treatment_stringer',(xx,1.92,2.225),(xx,3.30,3.72),.044,steel)
            rod('treatment_stair_head_tie',(xx,3.30,3.72),(xx,3.525,3.59),.044,steel)
        K.box('treatment_landing',.575,3.525,3.71,.85,.25,.14,grey)
        K.box('treatment_landing_girder',.47,3.525,3.59,1.06,.12,.16,steel)
        for xx in (.86,):K.box('treatment_landing_column',xx,3.525,2.91,.11,.11,1.38,steel)
        K._fine_mode=True
        for xx in (.34,.96):rail('treatment_stair_rail',(xx,1.94,2.30),(xx,3.30,3.80))
        rail('treatment_right_landing_guard',(.96,3.30,3.78),(.96,3.62,3.78))
        rail('treatment_front_guard',(-2.52,1.98,3.78),(.12,1.98,3.78))
        rail('treatment_left_guard',(-2.52,1.98,3.78),(-2.52,3.62,3.78))
        rail('treatment_rear_guard',(-2.52,3.62,3.78),(.96,3.62,3.78))
        rail('treatment_right_guard',(.12,1.98,3.78),(.12,3.32,3.78))
        K._fine_mode=False
        tag('treatment_access')
        # Contrasting heights preserve a stepped silhouette at small sizes.
        for i,(xx,body_top) in enumerate(((-1.90,5.40),(-.75,5.00))):
            name='treatment_vessel_'+str(i)
            K.cyl(name+'_skirt',xx,2.68,3.88,.245,.20,steel,segments=24)
            K.cyl(name,xx,2.68,(3.98+body_top)/2,.32,body_top-3.98,grey,segments=32)
            K.dome_cap(name+'_head',xx,2.68,body_top-.006,.32,.18,grey,seg=32)
            K._fine_mode=True
            noink(K.seam(name+'_base_seam',xx,2.68,3.998,.325,t=.025))
            noink(K.seam(name+'_top_seam',xx,2.68,body_top-.02,.325,t=.025))
            K.cyl(name+'_manway',xx,2.354,4.40,.105,.075,steel,axis='Y',segments=20)
            noink(K.cyl(name+'_manway_lid',xx,2.312,4.40,.083,.012,grey,axis='Y',segments=20))
            K._fine_mode=False
            tag(name)
        # Wet-gas feed around the outside of the upper platform, through the
        # clear space between rail bars. Two low supports carry its long run.
        K.pipe_run('treatment_feed',[(1.82,.82,2.65),(1.82,3.50,2.65),(1.82,3.50,4.085),
            (1.82,3.82,4.085),(-1.90,3.82,4.085),(-1.90,2.99,4.085)],.045,mat=steel,bend=.09,ends=('',''))
        for yy in (2.30,3.38):rod('treatment_feed_support',(1.82,yy,2.22),(1.82,yy,2.65),.032,steel)
        K.pipe_run('treatment_top_link',[(-1.90,2.68,5.56),(-1.90,2.68,5.80),
            (-.75,2.68,5.80),(-.75,2.68,5.16)],.045,mat=steel,bend=.09,ends=('',''))
        K.pipe_run('treatment_export',[(-.75,2.99,4.25),(-.75,3.25,4.25),(-.75,3.25,3.90),
            (-.75,3.75,3.90),(-.75,3.75,1.70),(3.02,3.75,1.70),(3.02,3.75,.04)],.045,mat=steel,bend=.08,ends=('',''))
        rod('treatment_export_bracket',(2.25,3.75,1.98),(3.02,3.75,1.70),.035,steel)
        tag('treatment_pipework')
    K._fine_mode=True
    # Rail segments leave a service gap around the outboard equipment bases.
    rail('front_guard',(-2.73,front+.04,2.23),(2.73 if level>=2 else 1.44,front+.04,2.23))
    rail('right_guard',(2.74,front+.12,2.23),(2.74,1.05,2.23))
    rail('rear_guard',(-2.73,rear-.04,2.23),(2.73 if level==3 else 1.65,rear-.04,2.23))
    if level==3:rail('right_rear_guard',(2.74,2.10,2.23),(2.74,rear-.12,2.23))
    for ya,yb in ((front+.12,-1.0),(-.60,.34),(.74,rear-.12)):
        rail('left_guard',(-2.74,ya,2.23),(-2.74,yb,2.23))
    K._fine_mode=False
    tag('guards')
    # Owner: visible rings where pipework enters equipment, especially the green
    # cabinet. True annuli grip the pipe and overlap the host skin; no loose discs.
    def collar(name,centre,axis,radius,host,pipe,outer=None):
        previous=K._fine_mode;K._fine_mode=True
        ob=K.washer(name,centre,axis,radius-.002,outer or radius+.070,.060,grey,seg=28)
        ob['assembly']=bpy.data.objects[host]['assembly']
        ob['joint_host']=host;ob['joint_pipe']=pipe
        K._fine_mode=previous
    collar('bop_pipe_collar',(.91,.45,1.65),(1,0,0),.050,'BOP','production_line_seg0')
    collar('separator_outlet_collar',(2.12,-.395,2.65),(0,1,0),.055,'separator','export_line_seg0')
    if level>=2:
        for i,yy in enumerate((-2.42,-3.22)):
            collar('vessel_'+str(i)+'_left_collar',(-2.41,yy,2.84),(1,0,0),.040,
                'upgrade_vessel_'+str(i)+'_head0','upgrade_interstage_seg'+str(0 if i==0 else 2))
            collar('vessel_'+str(i)+'_right_collar',(-.495,yy,2.84),(1,0,0),.045,
                'upgrade_vessel_'+str(i)+'_head1','upgrade_feed_seg6' if i==0 else 'upgrade_compressor_in_seg0')
        collar('compressor_inlet_collar',(.795,-2.92,2.84),(1,0,0),.045,'compressor_housing','upgrade_compressor_in_seg5')
        collar('compressor_outlet_collar',(2.105,-2.90,3.05),(1,0,0),.045,'compressor_housing','upgrade_compressor_out_seg0')
    if level==3:
        collar('treatment_inlet_collar',(-1.90,2.985,4.085),(0,1,0),.045,'treatment_vessel_0','treatment_feed_seg4',outer=.090)
        collar('treatment_outlet_collar',(-.75,2.985,4.25),(0,1,0),.045,'treatment_vessel_1','treatment_export_seg0')
        collar('treatment_top_collar_0',(-1.90,2.68,5.550),(0,0,1),.045,'treatment_vessel_0_head','treatment_top_link_seg0')
        collar('treatment_top_collar_1',(-.75,2.68,5.150),(0,0,1),.045,'treatment_vessel_1_head','treatment_top_link_seg2')
    return finish(K,level)
