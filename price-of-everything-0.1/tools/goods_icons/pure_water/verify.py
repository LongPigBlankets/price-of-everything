import bpy,bmesh,json,sys,math,itertools
from pathlib import Path
from mathutils import Vector
from mathutils.bvhtree import BVHTree
root=Path(sys.argv[sys.argv.index('--')+1]).resolve()
result={}
for name in ['refined_ree','solar_panel','alloy_ore']:
    bpy.ops.wm.open_mainfile(filepath=str(root/(name+'.blend')))
    info=json.loads((root/(name+'_metrics.json')).read_text());scene=bpy.context.scene
    assert scene.camera.data.type=='ORTHO'
    assert all(abs(math.degrees(a)-b)<.01 for a,b in zip(scene.camera.rotation_euler,(54.7356,0,45)))
    dg=bpy.context.evaluated_depsgraph_get();records={};trees={};points={};axes={}
    for n in info['structural_hosts']:
        o=bpy.data.objects[n];ev=o.evaluated_get(dg);me=ev.to_mesh();bm=bmesh.new();bm.from_mesh(me)
        bad=sum(not e.is_manifold for e in bm.edges);zero=sum(f.calc_area()<1e-12 for f in bm.faces)
        assert bad==0 and zero==0,(name,n,bad,zero)
        records[n]={'vertices':len(bm.verts),'faces':len(bm.faces),'non_manifold':bad,'zero_area':zero,'volume':bm.calc_volume(signed=False)}
        points[n]=[o.matrix_world@v.co for v in me.vertices]
        axes[n]=[p.normal.copy() for p in me.polygons]
        trees[n]=BVHTree.FromPolygons(points[n],[tuple(p.vertices) for p in me.polygons])
        bm.free();ev.to_mesh_clear()
    pairs={}
    if name=='refined_ree':
        for cube in info['structural_hosts'][:5]:
            for dish in ['sample_dish','powder_mound']:
                hits=len(trees[cube].overlap(trees[dish]));pairs[cube+'/'+dish]={'surface_intersections':hits};assert hits==0
    elif name=='solar_panel':
        for a,b in itertools.combinations(info['structural_hosts'],2):
            test=axes[a]+axes[b]+[x.cross(y) for x in axes[a] for y in axes[b] if x.cross(y).length>1e-6]
            gaps=[]
            for axis in test:
                n=axis.normalized();aa=[v.dot(n) for v in points[a]];bb=[v.dot(n) for v in points[b]]
                gaps.append(max(min(bb)-max(aa),min(aa)-max(bb)))
            separation=max(gaps);pairs[a+'/'+b]={'sat_separation':separation};assert separation>-.00001,(a,b,separation)
    else:
        for a,b in itertools.combinations(info['structural_hosts'],2):
            hits=len(trees[a].overlap(trees[b]));pairs[a+'/'+b]={'surface_intersections':hits};assert hits==0,(a,b,hits)
    result[name]={'saved_meshes':records,'pairs':pairs,'camera_degrees':[math.degrees(x) for x in scene.camera.rotation_euler]}
(root/'saved_scene_verification.json').write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps(result))
