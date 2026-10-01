import sys,json,math
from pathlib import Path
here=Path(__file__).resolve().parent
for fn in ['sprite_kit.py','base_kit.py','ore_builders.py','legacy_batch.py','typography.py','goods_icon_kit.py','pure_water_kit.py','power_kit.py','alkaline_kit.py','chair_geom.py','plastics_kit.py']:exec(compile((here/fn).read_text(),str(here/fn),'exec'),globals())
args=sys.argv[sys.argv.index('--')+1:];out=Path(args[0]).resolve();out.mkdir(parents=True,exist_ok=True)
for name in args[1:]:
    info=globals()['build_'+name]();K=Kit(bpy.data.collections['ICON_'+name]);bpy.context.view_layer.update()
    cam=bpy.context.scene.camera;assert cam.data.type=='ORTHO';angles=[math.degrees(a) for a in cam.rotation_euler];assert all(abs(a-b)<.01 for a,b in zip(angles,(54.7356,0,45)))
    info['camera_degrees']=angles;info['validation']=K.validate()
    assert not any(msg.startswith('BELOW GROUND') for msg in info['validation']),info['validation']
    hosts=info.get('structural_hosts') or {'crude_oil':['drum_shell','closed_lid'],'processed_oil':['drum_shell','visible_liquid_surface'],'graphite':['graphite_solid_block'],'refined_ree':['base_brown','base_grey','middle_ochre','middle_green','top_navy','sample_dish','powder_mound'],'sand':['central_sand_heap']+['%s_sack_%d'%(side,level) for side in ['left','right','front'] for level in [0,1]],'pet_coke':['left_chunk','front_chunk','long_hero']}[name]
    info['mesh_checks']={}
    for host in hosts:
        ob=next((ob for ob in K.col.objects if ob.name==host),None)
        if ob is None:ob=next(ob for ob in K.col.objects if ob.name.split('.')[0]==host)
        bm=bmesh.new();bm.from_mesh(ob.data)
        bad=sum(not edge.is_manifold for edge in bm.edges);zero=sum(face.calc_area()<1e-12 for face in bm.faces)
        info['mesh_checks'][host]={'vertices':len(bm.verts),'faces':len(bm.faces),'non_manifold_edges':bad,'zero_area_faces':zero};bm.free()
        assert bad==0 and zero==0,(name,host,bad,zero)
    print(name,info,flush=True)
    if 'outline' in info:(out/(name+'_raw_outline.json')).write_text(json.dumps(info['outline'],indent=2))
    if 'stipple' in info:(out/(name+'_raw_stipple.json')).write_text(json.dumps(info['stipple'],indent=2))
    info['frame']=render_icon(K.col.name,str(out/(name+'_raw.png')))
    # Thin ropes already carry their own ink; don't inflate them by the body contour.
    exempt=[ob for ob in K.col.objects if ob.get('outline_exempt') or (info.get('outline',{}).get('standard_weights') and ob.get('edge_ink'))]
    if exempt or info.get('outline',{}).get('standard_weights'):
        scene=bpy.context.scene;fs=scene.render.use_freestyle;scene.render.use_freestyle=False
        for ob in exempt:ob.hide_render=True
        scene.render.filepath=str(out/(name+'_raw_contour.png'));bpy.ops.render.render(write_still=True)
        for ob in exempt:ob.hide_render=False
        scene.render.use_freestyle=fs;scene.render.filepath=str(out/(name+'_raw.png'))
    # Explicit semantic component mask for sacks/chunks; all details inherit host IDs.
    if any(ob.get('part_label') for ob in K.col.objects):
        old=[];scene=bpy.context.scene;fs=scene.render.use_freestyle;scene.render.use_freestyle=False
        for ob in K.col.objects:
            old.append((ob,list(ob.data.materials),[p.material_index for p in ob.data.polygons]))
            label=ob.get('part_label',7);srgb=label*info.get('outline',{}).get('id_step',32)/255;linear=((srgb+.055)/1.055)**2.4
            mat=bpy.data.materials.get('semantic_'+str(label)) or bpy.data.materials.new('semantic_'+str(label))
            mat.use_nodes=True;nt=mat.node_tree;nt.nodes.clear();e=nt.nodes.new('ShaderNodeEmission');e.inputs[0].default_value=(linear,linear,linear,1);o=nt.nodes.new('ShaderNodeOutputMaterial');nt.links.new(e.outputs[0],o.inputs[0])
            ob.data.materials.clear();ob.data.materials.append(mat)
        scene.render.filepath=str(out/(name+'_raw_id.png'));bpy.ops.render.render(write_still=True)
        if info.get('outline',{}).get('host_ownership'):
            for ob in exempt:ob.hide_render=True
            scene.render.filepath=str(out/(name+'_raw_host_id.png'));bpy.ops.render.render(write_still=True)
            for ob in exempt:ob.hide_render=False
        for ob,mats,indices in old:
            ob.data.materials.clear()
            for mat in mats:ob.data.materials.append(mat)
            for polygon,index in zip(ob.data.polygons,indices):polygon.material_index=index
        scene.render.use_freestyle=fs;scene.render.filepath=str(out/(name+'_raw.png'))
    if info.get('outline',{}).get('standard_weights'):
        from bpy_extras.object_utils import world_to_camera_view
        from mathutils.bvhtree import BVHTree
        scene=bpy.context.scene;resolution=scene.render.resolution_x*scene.render.resolution_percentage/100
        verts=[];faces=[];depsgraph=bpy.context.evaluated_depsgraph_get()
        for solid in K.col.objects:
            if solid.get('edge_ink') or solid.pass_index==73:continue
            evaluated=solid.evaluated_get(depsgraph);me=evaluated.to_mesh();offset=len(verts)
            verts.extend(evaluated.matrix_world@v.co for v in me.vertices)
            faces.extend(tuple(offset+i for i in f.vertices) for f in me.polygons)
            evaluated.to_mesh_clear()
        tree=BVHTree.FromPolygons(verts,faces)
        toward_camera=scene.camera.rotation_euler.to_matrix()@Vector((0,0,1))
        paths=[]
        for ob in K.col.objects:
            flat=ob.get('line_path')
            if not flat:continue
            vertices=[Vector(flat[i:i+3]) for i in range(0,len(flat),3)]
            samples=[]
            for a,b in zip(vertices,vertices[1:]):
                n=max(1,math.ceil((b-a).length*resolution/scene.camera.data.ortho_scale/.3))
                samples.extend(a.lerp(b,j/n) for j in range(n))
            samples.append(vertices[-1]);points=[];visible=[]
            for point in samples:
                uv=world_to_camera_view(scene,scene.camera,point);points.append([uv.x*resolution,(1-uv.y)*resolution])
                hit,normal,index,distance=tree.ray_cast(point+toward_camera*100,-toward_camera,101)
                visible.append(hit is None or distance>=100-.0003)
            paths.append({'name':ob.name,'points':points,'visible':visible,'label':ob.get('part_label',0),'ink_width':ob.get('ink_width',0),'ink_tip':ob.get('ink_tip',1),'ink_centre':ob.get('ink_centre',1)})
        (out/(name+'_raw_paths.json')).write_text(json.dumps(paths,indent=2))
        saved=[];scene=bpy.context.scene;fs=scene.render.use_freestyle;scene.render.use_freestyle=False
        for ob in K.col.objects:
            saved.append((ob,list(ob.data.materials),[p.material_index for p in ob.data.polygons]))
            value=1 if ob.get('edge_ink') else 0
            mat=bpy.data.materials.get('_line_mask_'+str(value)) or bpy.data.materials.new('_line_mask_'+str(value))
            mat.use_nodes=True;nt=mat.node_tree;nt.nodes.clear();e=nt.nodes.new('ShaderNodeEmission');e.inputs[0].default_value=(value,value,value,1);o=nt.nodes.new('ShaderNodeOutputMaterial');nt.links.new(e.outputs[0],o.inputs[0])
            ob.data.materials.clear();ob.data.materials.append(mat)
        scene.render.filepath=str(out/(name+'_raw_ink.png'));bpy.ops.render.render(write_still=True)
        for ob,mats,indices in saved:
            ob.data.materials.clear()
            for mat in mats:ob.data.materials.append(mat)
            for polygon,index in zip(ob.data.polygons,indices):polygon.material_index=index
        scene.render.use_freestyle=fs;scene.render.filepath=str(out/(name+'_raw.png'))
    bpy.ops.wm.save_as_mainfile(filepath=str(out/(name+'.blend')))
    (out/(name+'_metrics.json')).write_text(json.dumps(info,indent=2))
