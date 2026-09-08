"""Broad-face ore cages, deliberately avoiding the legacy nuggets' tiny facet web.
Loaded after goods_icon_kit.py. All random shape variation uses explicit per-rock seeds.
"""

from mathutils import Vector

def ore_cage(K,name,centre,r,height,seed,mats,kind='iron',silver_faces=(0,1)):
    """An irregular eight-sided control cage with softened, creased corners.
    The iron faces are actual material regions of the same mesh, not floating decals.
    """
    rng=random.Random(seed)
    base=[(-.64,-.88),(.52,-.88),(.89,-.49),(.86,.52),
          (.51,.88),(-.56,.89),(-.91,.48),(-.90,-.49)]
    spread=(.92,1.07) if kind=='coal' else (.82,1.13)
    base=[(x*rng.uniform(*spread),y*rng.uniform(*spread)) for x,y in base]
    wave=[rng.uniform(-.065,.065) for _ in base]
    if kind=='coal':
        rings=[(0,.73),(.10,1.0),(.91,.98),(1.0,.86)]
    else:
        rings=[(0,.65),(.15,1.0),(.80,.96),(1.0,.68)]
    cx,cy,cz=centre;n=8;verts=[]
    fracture_bottom=[rng.uniform(.18,.39) for _ in range(n)]
    lean=(rng.uniform(-.12,.12),rng.uniform(-.10,.10)) if kind=='iron' else (0,0)
    for j,(z,rad) in enumerate(rings):
        for i,(x,y) in enumerate(base):
            hz=z
            verts.append((cx+r*(x*rad+lean[0]*z),cy+r*(y*rad+lean[1]*z),
                          cz+height*(hz+wave[i]*(.15 if j==0 else 1))))
    faces=[tuple(reversed(range(n)))]
    for j in range(len(rings)-1):
        for i in range(n):
            a=j*n+i;b=j*n+(i+1)%n;faces.append((a,b,b+n,a+n))
    faces.append(tuple(range((len(rings)-1)*n,len(rings)*n)))
    ob=mesh_object(K,name,verts,faces,mats[0],True)
    for mat in mats[1:]:ob.data.materials.append(mat)
    for j in range(len(rings)-1):
        for i in range(n):
            face=ob.data.polygons[1+j*n+i]
            if kind=='coal':
                face.material_index=1 if j==2 or (j==1 and i==7 and seed==41) else 0

    ob.data.polygons[-1].material_index=1 if kind=='coal' else 0
    if kind=='iron':
        # One true cleavage plane cuts through both crown and flank.
        bm=bmesh.new();bm.from_mesh(ob.data)
        normal=Vector(({31:.23,32:-.05,33:.50}[seed],-1,.64)).normalized()
        origin=Vector(centre)+Vector((0,0,height*.50))
        extent=max((v.co-origin).dot(normal) for v in bm.verts)
        distance=extent*({31:.48,32:.34,33:.33}[seed])
        cut=bmesh.ops.bisect_plane(bm,geom=bm.verts[:]+bm.edges[:]+bm.faces[:],
            plane_co=origin+normal*distance,plane_no=normal,clear_outer=True)
        edges=[g for g in cut['geom_cut'] if isinstance(g,bmesh.types.BMEdge)]
        for face in bmesh.ops.holes_fill(bm,edges=edges,sides=0)['faces']:
            face.material_index=1
        bmesh.ops.recalc_face_normals(bm,faces=bm.faces)
        bm.to_mesh(ob.data);bm.free();ob.data.update()
    crease=ob.data.attributes.new('crease_edge','FLOAT','EDGE')
    marks=ob.data.attributes.new('freestyle_edge','BOOLEAN','EDGE')
    for e in ob.data.edges:
        a,b=e.vertices;ra,rb=a//n,b//n
        crease.data[e.index].value=.84 if kind=='coal' else .58
        if kind=='coal':
            marks.data[e.index].value=(ra==rb==2) or (ra!=rb and a%n in (0,2,4,6) and min(ra,rb)==1)
        else:
            # Only the broad cap boundary and selected long side turns receive ink.
            edge_faces=[p for p in ob.data.polygons if a in p.vertices and b in p.vertices]
            mi={p.material_index for p in edge_faces}
            material_edge=len(mi)>1 and mi!={1,2}
            marks.data[e.index].value=material_edge
    sd=ob.modifiers.new('Broad rock control cage','SUBSURF')
    sd.levels=1 if kind=='coal' else 2;sd.render_levels=sd.levels
    return ob


def build_coal():
    """D≈1.8: three angular lumps, one tall hero, three small cubic fragments.
    Match reference charcoal sides (~40/18 luma) and blue-grey top (~120 luma).
    No silver glint caps and no triangulated facet network.
    """
    setup_icon_rig();fs=_ore_linestyle()
    fs.linesets['ink'].select_crease=False;fs.linesets['ink_fine'].select_crease=False
    fs.linesets['ink_edge'].linestyle.thickness=4.0
    col=open_collection('ICON_coal');K=Kit(col)
    charcoal=toon_mat('ore_coal_charcoal',(.028,.030,.035),steps=((.66,.20),(.92,.80),(9,1)))
    blue=toon_mat('ore_coal_blue',(.115,.195,.28))
    specs=[((-.08,.26,.055),.95,1.67,41),((-.68,-.46,.055),.60,1.02,42),
           ((.63,-.05,.055),.64,1.19,43)]
    for i,(c,r,h,seed) in enumerate(specs):
        ore_cage(K,'coal_chunk_%d'%i,c,r,h,seed,(charcoal,blue),'coal')
    for i,(x,y,s) in enumerate([(-.08,-.92,.25),(.19,-.77,.30),(.52,-.71,.24)]):
        ob=K.box('coal_fragment_%d'%i,x,y,s/2,s,s,s,charcoal)
        ob.data.materials.append(blue)
        for face in ob.data.polygons:
            if face.normal.z>.5:face.material_index=1
    ID_SEPARATION_COLS.add(col.name)
    bpy.context.view_layer.update();return K


def build_iron_ore():
    """D≈1.8: three broad, rounded rust-red lumps with large grey fracture faces.
    Preserve prior owner preference for fewer large chunks and larger silver on the flanks.
    Surface colours follow the shipped rust (~168/72/56) and silver (~112/128/136).
    """
    setup_icon_rig();fs=_ore_linestyle()
    fs.linesets['ink'].select_crease=False;fs.linesets['ink_fine'].select_crease=False
    fs.linesets['ink_edge'].linestyle.thickness=3.4
    col=open_collection('ICON_iron_ore');K=Kit(col)
    rust=toon_mat('ore_rust',(.41,.075,.045))
    silver=toon_mat('ore_silver',(.18,.22,.255),steps=((.66,.50),(.84,.72),(9,1)))
    highlight=toon_mat('ore_silver_highlight',(.37,.41,.46))
    specs=[((.02,.25,.055),.97,1.65,31,(0,1)),
           ((-.61,-.40,.055),.65,1.08,32,(0,1,7)),
           ((.59,-.32,.055),.66,1.03,33,(0,1,7))]
    for i,(c,r,h,seed,grey) in enumerate(specs):
        ore_cage(K,'iron_chunk_%d'%i,c,r,h,seed,(rust,silver,highlight),'iron',grey)
    ID_SEPARATION_COLS.add(col.name)
    bpy.context.view_layer.update();return K
