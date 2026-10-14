"""Renderer-only district landmarks, built with the existing matte civic kit."""
from pathlib import Path
exec(compile(Path(__file__).with_name('civic_builder.py').read_text(),
             str(Path(__file__).with_name('civic_builder.py')), 'exec'))

PALETTE.update({
    'district_cream': (.37, .355, .325),
    'district_blue': (.048, .100, .185),
    'district_trim': (.40, .415, .43),
    'district_brick': (.30, .145, .105),
    'district_awning': (.12, .23, .21),
    'bauhaus_plaster': (.64, .59, .48),
})


def _quads(k, name, quads, material):
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata([p for q in quads for p in q], [],
                     [tuple(range(i*4, i*4+4)) for i in range(len(quads))])
    mesh.update()
    return _paint(k.obj(name, mesh, k.mat(material)))


def _panel(k, name, a, b, z, width, height, cols=2, rows=1, glass='window_glass'):
    """Painted grid on any perimeter edge, including the angled bay cheeks.

    One glass quad and one frame mesh avoid thousands of tiny framed boxes.
    CCW edges give outward-facing normals; all elevations are modelled.
    """
    dx, dy = b[0]-a[0], b[1]-a[1]
    length = math.hypot(dx, dy)
    ux, uy = dx/length, dy/length
    cx, cy = (a[0]+b[0])/2, (a[1]+b[1])/2
    def quad(x0, x1, z0, z1, proud):
        return [(cx+ux*x+uy*proud, cy+uy*x-ux*proud, zz)
                for x, zz in [(x0,z0),(x1,z0),(x1,z1),(x0,z1)]]
    _quads(k, name+'_glass', [quad(-width/2,width/2,z-height/2,z+height/2,.014)], glass)
    fw = .024
    frames = []
    for col in range(cols+1):
        x = -width/2+width*col/cols
        frames.append(quad(x-fw/2,x+fw/2,z-height/2-fw/2,z+height/2+fw/2,.020))
    for row in range(rows+1):
        zz = z-height/2+height*row/rows
        frames.append(quad(-width/2,width/2,zz-fw/2,zz+fw/2,.020))
    _quads(k, name+'_frames', frames, 'district_trim')


def _perimeter_windows(k, name, outline, floors, base=.1, floor_height=FLOOR, pitch=.9):
    for edge,(a,b) in enumerate(zip(outline,outline[1:]+outline[:1])):
        length = math.dist(a,b)
        count = max(1,int((length-.10+1e-6)/pitch))
        for floor in range(floors):
            for bay in range(count):
                t = .5 + (bay-(count-1)/2)*pitch/length
                x,y = a[0]+(b[0]-a[0])*t,a[1]+(b[1]-a[1])*t
                ux,uy=(b[0]-a[0])/length,(b[1]-a[1])/length
                _panel(k,f'{name}_{edge}_{floor}_{bay}',(x-ux*.5,y-uy*.5),(x+ux*.5,y+uy*.5),
                       base+floor*floor_height+floor_height*.55,
                       min(.62,length/count-.20), floor_height*.63)


def build_civic_u_office(level=1):
    """Twenty-floor central bar, twelve-floor wings and a real open courtyard."""
    _building_rig()
    k=Kit(open_collection('BLDG_civic_u_office'))
    outline=[(-4.1,-3.1),(-2.25,-3.1),(-2.25,1.15),(2.25,1.15),
             (2.25,-3.1),(4.1,-3.1),(4.1,3.2),(-4.1,3.2)]
    low=.1+12*FLOOR
    # Explicit concave cap triangles keep the central void open through export.
    # Blender's automatic ngon triangulation can bridge the deep U indentation.
    roof_triangles=[(0,1,2),(0,2,7),(2,3,7),(3,6,7),(3,5,6),(3,4,5)]
    vertices=[(x,y,z) for z in (.1,low) for x,y in outline]
    faces=[tuple(reversed(t)) for t in roof_triangles]
    faces += [tuple(i+8 for i in t) for t in roof_triangles]
    faces += [(i,(i+1)%8,(i+1)%8+8,i+8) for i in range(8)]
    mesh=bpy.data.meshes.new('u_body');mesh.from_pydata(vertices,[],faces);mesh.update()
    k.obj('u_body',mesh,k.mat('civic_grey'))
    _perimeter_windows(k,'lower',outline,12)
    # The central extension carries eight additional floors: twenty in total.
    top=_facade(k,'central_crown',0,2.175,8.2,2.05,8,base=low,walls='civic_grey',pitch=BAY)
    for x in (-3.175,3.175):
        _paint(k.box('wing_deck'+str(x),x,-.975,low+.02,1.65,4.05,.04,k.mat('deck')))
        for xx in (x-.875,x+.875):
            k.box('wing_parapet',xx,-.975,low+.085,.10,4.25,.17,k.mat('civic_grey'))
        k.box('wing_tip',x,-3.05,low+.085,1.85,.10,.17,k.mat('civic_grey'))
        for y in (-2.35,.15):
            _paint(k.box('roof_garden',x,y,low+.16,1.05,.60,.24,k.mat('civic_hedge')))
        _plant(k,'wing_plant'+str(x),x,-1.1,low+.05)
    _paint(k.box('court',0,-.9,.035,4.30,4.2,.07,k.mat('civic_paving')))
    for x in (-1.50,1.50):
        k.box('court_planter',x,-1.1,.16,.48,2.5,.25,k.mat('civic_stone'))
        _paint(k.box('court_hedge',x,-1.1,.35,.40,2.4,.25,k.mat('civic_hedge')))
    _entry(k,0,1.15)
    for x in (-2.7,2.7): _plant(k,'crown_plant'+str(x),x,2.15,top)
    return {'level':level,'storey_height':FLOOR}


def _pitched_roof(k,name,cx,cy,width,depth,eaves,rise,wall='district_cream'):
    k.prism(name+'_gable',(cx,cy,eaves),(0,1),[(-depth/2,0),(depth/2,0),(0,rise)],width,k.mat(wall))
    pitch=math.atan2(rise,depth/2)
    for sign in (-1,1):
        oh=.08
        k.rotbox(name+'_slope'+str(sign),cx,cy+sign*(depth/4+oh/2),
                 eaves+rise/2-oh*math.tan(pitch)/2+.025,
                 width+2*oh,(depth/2+oh)/math.cos(pitch),.05,
                 k.mat('roof'),'X',math.degrees(pitch)*-sign)


def build_civic_semi(level=1):
    """A mirrored pair, with two-storey canted bays and paired central doors."""
    # This pair's fixed 50u height gives slightly taller source-space storeys.
    # Keep its world-space silhouette stroke comparable to existing housing.
    setup_rig(ortho_scale=21.0)
    k=Kit(open_collection('BLDG_civic_semi'))
    k.box('shared_pair',0,0,1.15,4.8,2.7,2.3,k.mat('district_brick'))
    _pitched_roof(k,'shared_roof',0,0,4.8,2.7,2.3,.9)
    # Both halves use precisely mirrored features, not merely similar variants.
    for sign in (-1,1):
        cx=sign*1.5
        bay=[(cx-.55,-1.34),(cx-.55,-1.62),(cx-.34,-1.90),
             (cx+.34,-1.90),(cx+.55,-1.62),(cx+.55,-1.34)]
        k.poly_prism('bay'+str(sign),bay,.08,2.3,k.mat('district_cream'))
        for floor in range(2):
            for edge in (1,2,3):
                a,b=bay[edge],bay[edge+1]
                _panel(k,f'bay_{sign}_{floor}_{edge}',a,b,.68+floor*1.1,
                       math.dist(a,b)-.11,.68,2 if edge==2 else 1,2)
        # Low hipped bay cap remains below the main roof ridge.
        _paint(k.poly_prism('bay_cap',bay,2.30,2.36,k.mat('roof')))
        dx=sign*.40
        _panel(k,'door'+str(sign),(dx-.5,-1.35),(dx+.5,-1.35),.48,.48,.90,1,1,'door_leaf')
        _panel(k,'overdoor'+str(sign),(dx-.5,-1.35),(dx+.5,-1.35),1.78,.55,.68,2,2)
        k.box('porch'+str(sign),dx,-1.54,1.06,.72,.60,.075,k.mat('roof'))
        _paint(k.box('step'+str(sign),dx,-1.60,.04,.72,.65,.08,k.mat('civic_stone')))
        k.box('chimney'+str(sign),sign*.18,.22,3.15,.22,.28,.65,k.mat('district_brick'))
        _paint(k.box('chimney_cap',sign*.18,.22,3.49,.28,.34,.05,k.mat('civic_stone')))
        for y in (-.65,.65):
            a,b=((2.4,y-.5),(2.4,y+.5)) if sign>0 else ((-2.4,y+.5),(-2.4,y-.5))
            for floor in range(2):_panel(k,f'side{sign}{y}{floor}',a,b,.68+floor*1.1,.53,.68,2,2)
        for xx in (sign*.55,sign*1.7):
            for floor in range(2):
                _panel(k,f'rear{xx}{floor}',(xx+.5,1.35),(xx-.5,1.35),.68+floor*1.1,.58,.68,2,2)
    return {'level':level,'storey_height':FLOOR}


def build_civic_bauhaus(level=1):
    """Two-storey works, a third floor on the right third, and left-hand stacks."""
    _building_rig()
    k=Kit(open_collection('BLDG_civic_bauhaus'))
    width,depth,height=7.6,4.5,3.7
    right_start=width/6
    upper_width=width/3
    upper_x=(right_start+width/2)/2
    k.box('works',0,0,height/2+.1,width,depth,height,k.mat('bauhaus_plaster'))
    # Lower deck stops at the raised right-hand third: no roof line through it.
    deck_width=width*2/3
    deck_x=-width/6
    _paint(k.box('lower_roof',deck_x,0,height+.12,deck_width-.08,depth-.12,.06,k.mat('deck')))
    k.box('left_roof_edge',-width/2,0,height+.20,.07,depth+.07,.13,k.mat('roof'))
    for y in (-depth/2,depth/2):
        k.box('lower_roof_edge',deck_x,y,height+.20,deck_width,.07,.13,k.mat('roof'))
    upper_base=height+.10
    k.box('right_third_floor',upper_x,0,upper_base+.9,upper_width,depth,1.8,k.mat('bauhaus_plaster'))
    roof_z=upper_base+1.8
    _paint(k.box('upper_roof',upper_x,0,roof_z+.02,upper_width-.12,depth-.12,.06,k.mat('deck')))
    for x in (right_start,width/2):
        k.box('upper_roof_edge',x,0,roof_z+.10,.07,depth+.07,.13,k.mat('roof'))
    for y in (-depth/2,depth/2):
        k.box('upper_roof_edge',upper_x,y,roof_z+.10,upper_width,.07,.13,k.mat('roof'))
    outline=[(-width/2,-depth/2),(width/2,-depth/2),(width/2,depth/2),(-width/2,depth/2)]
    for edge,(a,b) in enumerate(zip(outline,outline[1:]+outline[:1])):
        length=math.dist(a,b); count=4 if edge%2==0 else 2
        for i in range(count):
            t=(i+.5)/count;cx=a[0]+(b[0]-a[0])*t;cy=a[1]+(b[1]-a[1])*t
            ux,uy=(b[0]-a[0])/length,(b[1]-a[1])/length
            for floor in range(2):
                # The front entrance owns its full bay. Rear loading annex owns
                # the lower right facade. Neither gets glazing behind a doorway.
                if floor==0 and ((edge==0 and i==3) or (edge==2 and i<2)):
                    continue
                _panel(k,f'works_{edge}_{i}_{floor}',(cx-ux*.5,cy-uy*.5),(cx+ux*.5,cy+uy*.5),
                       1.03+floor*1.8,length/count-.34,1.10,5,3,'district_blue')
    upper_outline=[(right_start,-depth/2),(width/2,-depth/2),(width/2,depth/2),(right_start,depth/2)]
    for edge,(a,b) in enumerate(zip(upper_outline,upper_outline[1:]+upper_outline[:1])):
        length=math.dist(a,b);count=1 if edge%2==0 else 2
        ux,uy=(b[0]-a[0])/length,(b[1]-a[1])/length
        for i in range(count):
            t=(i+.5)/count;cx=a[0]+(b[0]-a[0])*t;cy=a[1]+(b[1]-a[1])*t
            _panel(k,f'upper_works_{edge}_{i}',(cx-ux*.5,cy-uy*.5),(cx+ux*.5,cy+uy*.5),
                   upper_base+.93,length/count-.34,1.10,5,3,'district_blue')
    # Both furnace stacks now belong to the far-left service bay.
    for y in (-.65,1.38):
        k.cyl('pale_stack',-3.20,y,4.25,.28,8.30,k.mat('bauhaus_plaster'),segments=16)
        k.cyl('stack_dark_cap',-3.20,y,8.43,.29,.16,k.mat('darkmetal'),segments=16)
    _entry(k,2.85,-depth/2)
    k.box('loading_annex',1.2,2.42,.90,3.5,.58,1.8,k.mat('bauhaus_plaster'))
    for i in range(3):
        x=.10+i*1.08
        _panel(k,'loading'+str(i),(x+.5,2.72),(x-.5,2.72),.76,.80,1.25,1,5,'door_leaf')
    _plant(k,'vent',2.35,.55,roof_z+.13)
    return {'level':level,'storey_height':FLOOR}


def build_civic_commercial(level=1):
    """Four-floor shopping block: glazed arcades, awnings and a roof terrace."""
    _building_rig()
    k=Kit(open_collection('BLDG_civic_commercial'))
    # Three street floors plus a smaller fourth floor create two useful masses.
    roof=_facade(k,'street_block',0,0,5.8,3.8,3,walls='district_cream',faces=('-X','+X','+Y'))
    top=_facade(k,'setback',0,.40,4.4,2.6,1,base=roof-.08,walls='civic_grey')
    for floor in (1,2):
        for bay in range(6):
            x=(bay-2.5)*.90
            _panel(k,f'upper_shop_{floor}_{bay}',(x-.5,-1.9),(x+.5,-1.9),
                   .68+floor*FLOOR,.62,.70)
    # Wide display windows make the retail frontage legible even at medium LOD.
    for x in (-1.95,-.65,.65,1.95):
        _panel(k,'shop'+str(x),(x-.5,-1.925),(x+.5,-1.925),.68,1.10,.96,3,1,'district_blue')
        k.box('awning'+str(x),x,-2.13,1.29,1.20,.60,.10,k.mat('district_awning'))
        _paint(k.box('fascia'+str(x),x,-1.956,1.44,1.16,.035,.20,k.mat('district_awning')))
    for x in (-2.4,2.4):
        _paint(k.box('terrace_planter',x,-.20,roof+.17,.35,2.1,.30,k.mat('civic_hedge')))
    _plant(k,'retail_plant',.5,.7,top)
    return {'level':level,'storey_height':FLOOR}


def _green_ring(rx, ry, phase=0.0, count=48):
    return [(rx*math.cos(t)*(1+.065*math.sin(3*t+phase)+.035*math.cos(5*t)),
             ry*math.sin(t)*(1+.075*math.cos(4*t+phase)))
            for t in [i*2*math.pi/count for i in range(count)]]


def _green_patch(k, name, ring, z, material):
    # The shoreline is a single closed polygon, with no sprite water rectangle.
    vertices=[(0,0,z)]+[(x,y,z) for x,y in ring]
    mesh=bpy.data.meshes.new(name)
    mesh.from_pydata(vertices,[],[(0,i+1,(i+1)%len(ring)+1) for i in range(len(ring))])
    mesh.update()
    return _paint(k.obj(name,mesh,k.mat(material)))


def build_civic_pond(level=1):
    """Small landscaped pond with a one-unit bank at map scale and wooded grass."""
    setup_rig(ortho_scale=18)
    PALETTE['pond_deep']=(.075,.18,.27)
    k=Kit(open_collection('BLDG_civic_pond'))
    _green_patch(k,'wooded_lawn',_green_ring(4.4,3.35),.015,'civic_lawn')
    # A broad earth bank and progressively deeper water colour, fully contained
    # inside a flat green plot. Runtime fitting rejects a height-step underneath.
    _green_patch(k,'pond_bank',_green_ring(2.62,1.9,.7),.026,'civic_paving')
    _green_patch(k,'shallow_water',_green_ring(2.48,1.76,.7),.030,'civic_water')
    PALETTE['pond_deep']=(.075,.18,.27)
    _green_patch(k,'deep_water',[(x-.14,y+.08) for x,y in _green_ring(2.12,1.39,.7)],.034,'pond_deep')
    for i,angle in enumerate([.15,.72,1.3,1.92,2.48,3.08,3.75,4.3,5.35,5.92]):
        x=3.45*math.cos(angle);y=2.7*math.sin(angle)
        k.tree(f'pond_tree{i}',x,y,h=1.20+(i%3)*.22,r=.48+(i%2)*.08,seed=240+i)
    for i,(x,y) in enumerate([(-2.1,-2.05),(-1.0,-2.6)]): _bench(k,f'pond_bench{i}',x,y)
    return {'level':level}


def build_civic_grove(level=1):
    """Informal pocket woodland: grass, an angled walking path and varied trees."""
    setup_rig(ortho_scale=18)
    k=Kit(open_collection('BLDG_civic_grove'))
    _green_patch(k,'grove_grass',_green_ring(3.4,2.9,.3),.015,'civic_lawn')
    path=[(-3.1,-1.0),(-1.1,-.3),(.5,.6),(3.0,.95)]
    for i,(a,b) in enumerate(zip(path,path[1:])):
        dx,dy=b[0]-a[0],b[1]-a[1];length=math.hypot(dx,dy);nx,ny=-dy/length*.19,dx/length*.19
        _quads(k,'grove_path'+str(i),[[(a[0]+nx,a[1]+ny,.035),(a[0]-nx,a[1]-ny,.035),
                                    (b[0]-nx,b[1]-ny,.035),(b[0]+nx,b[1]+ny,.035)]],'civic_stone')
    for i,(x,y) in enumerate([(-2.3,1.0),(-1.3,1.8),(0,2.0),(1.6,1.7),(2.3,-.9),(.7,-1.7),(-1.4,-1.6)]):
        k.tree(f'grove_tree{i}',x,y,h=1.10+(i%3)*.22,r=.48,seed=260+i)
    _bench(k,'grove_bench',-.4,-.15)
    return {'level':level}
