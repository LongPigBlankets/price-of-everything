"""Audit frozen furnace scenes and render matching window/heat masks offline.

blender --background --factory-startup --python furnace_review.py -- <revision>
Does not install anything in the game. Uses the actual authored scene meshes.
"""
import bpy, bmesh, json, sys, math
from pathlib import Path
from mathutils import Vector
from mathutils.bvhtree import BVHTree
from bpy_extras.object_utils import world_to_camera_view

root=Path(sys.argv[sys.argv.index('--')+1])
(root/'fx_raw').mkdir(exist_ok=True)
report={}


def bounds(ob):
    pts=[ob.matrix_world@v.co for v in ob.data.vertices]
    return [min(p[i] for p in pts) for i in range(3)],[max(p[i] for p in pts) for i in range(3)]


def bvh(ob):
    vertices=[ob.matrix_world@v.co for v in ob.data.vertices]
    return BVHTree.FromPolygons(vertices,[p.vertices[:] for p in ob.data.polygons])


for level in (1,2,3):
    bpy.ops.wm.open_mainfile(filepath=str(root/f'furnace_L{level}.blend'))
    scene=bpy.context.scene
    objects=[o for o in bpy.data.collections['BLDG_furnace'].objects if o.type=='MESH']
    tests=[]
    def check(label,ok):
        tests.append({'check':label,'passed':bool(ok)})
        assert ok,label
    vessels=[o for o in objects if o.name in ('line0_vessel','line1_vessel')]
    check('Independent vessel count',len(vessels)==(2 if level==3 else 1))
    check('All geometry above ground',min(bounds(o)[0][2] for o in objects)>=-.001)
    for vessel in vessels:
        bm=bmesh.new(); bm.from_mesh(vessel.data)
        check(vessel.name+' sealed manifold shell',all(e.is_manifold for e in bm.edges))
        bm.free()
        tree=bvh(vessel)
        prefix=vessel.name.split('_')[0]
        ladder=[o for o in objects if o.name.startswith(prefix+'_ladder_') and 'landing' not in o.name]
        check(prefix+' access ladder exists',len(ladder)>2)
        check(prefix+' ladder clears vessel',all(not tree.overlap(bvh(o)) for o in ladder))
        stoves=[o for o in objects if o.name in [prefix+'_stove'+str(i) for i in range(3)]]
        check(prefix+' complete stove bank',len(stoves)==3)
        for i in range(len(stoves)):
            for j in range(i):
                check(prefix+f' stove clearance {j}/{i}',not bvh(stoves[i]).overlap(bvh(stoves[j])))
        check(prefix+' gas cleaning enclosure',any(o.name==prefix+'_cleaning_roof-1' for o in objects))
    if len(vessels)==2:
        check('Separate furnace vessels',not bvh(vessels[0]).overlap(bvh(vessels[1])))
        groups=[[o for o in objects if o.name.startswith(f'line{i}_')] for i in range(2)]
        boxes={o.name:bounds(o) for group in groups for o in group}
        collisions=[]
        for a in groups[0]:
            for b in groups[1]:
                alo,ahi=boxes[a.name];blo,bhi=boxes[b.name]
                if all(min(ahi[k],bhi[k])-max(alo[k],blo[k])>1e-5 for k in range(3)):
                    if bvh(a).overlap(bvh(b)):
                        collisions.append((a.name,b.name))
        check('Paired process lines clear one another: '+str(collisions),not collisions)
        roofs=[o for o in objects if o.name in ('shared_casthouse_roof-1','shared_casthouse_roof1')]
        check('One continuous two-slope casting hall roof',len(roofs)==2 and all(bounds(o)[0][0]<-1.1 and bounds(o)[1][0]>3.6 for o in roofs))
        check('Two casting hall heat openings',len([o for o in objects if o.name.startswith('shared_casthouse_bay') and o.name.endswith('_heat')])==2)
        wall_pieces=[o for o in objects if o.name.startswith('shared_casthouse_') and ('pier' in o.name or 'lintel' in o.name)]
        for x in (0,2.5):
            check(f'Open casting doorway at x={x}',not any(lo[0]<x<hi[0] and lo[2]<.5<hi[2] for lo,hi in map(bounds,wall_pieces)))
        lift=[o for o in objects if o.name in ('charge_lower_case','charge_upper_case')]
        check('Two distinct lift stretches',len(lift)==2)
        lift_clips=[(o.name,v.name) for o in lift for v in vessels if bvh(o).overlap(bvh(v))]
        check('Lift stretches clear furnace vessels: '+str(lift_clips),not lift_clips)
        check('Old direct lift removed',not any(o.name=='charge_conveyor' for o in objects))
        def named(name):return next(o for o in objects if o.name==name)
        for kind in ('column','foot','brace','platform_bearing'):
            signatures=[]
            for i in (0,1):
                prefix=f'line{i}_{kind}'
                group=[o for o in objects if o.name==prefix or o.name.startswith(prefix+'.')]
                signatures.append(sorted(sorted(tuple(round((o.matrix_world@v.co)[k]-(i*2.5 if k==0 else 0),5) for k in range(3)) for v in o.data.vertices) for o in group))
            check(kind+' meshes identical after translation',signatures[0]==signatures[1])
        for name,maximum in (('charge_lower_case',1),('charge_upper_case',20)):
            o=named(name);a=Vector(o['route_start']);b=Vector(o['route_end']);d=b-a
            angle=math.degrees(math.atan2(d.z,math.hypot(d.x,d.y)))
            check(name+f' inclination {angle:.2f} degrees',abs(angle)<=maximum)
            hit=bvh(o).ray_cast(a-d.normalized()*.02,d.normalized(),d.length+.04)[0]
            check(name+' open interior bore',hit is None)
        tower_walls=[o for o in objects if o.name.startswith(('elevator_facade_','elevator_side_facade','handling_annex_back','handling_annex_side','handling_annex_roof','handling_annex_gable'))]
        clips=[(a.name,b.name) for a in lift for b in tower_walls if bvh(a).overlap(bvh(b))]
        check('Galleries clear tower masonry through real ports: '+str(clips),not clips)
        inlet=named('elevator_inlet_chute');outlet=named('elevator_head_chute')
        check('Lower conveyor connects to elevator inlet',Vector(named('charge_lower_case')['route_end'])==Vector(inlet['route_start']))
        check('Both transfer chutes descend',all(o['route_start'][2]>o['route_end'][2] for o in (inlet,outlet)))
        for name in ('elevator_head_wheel','elevator_boot_wheel','elevator_drive_motor','elevator_chain_-1','elevator_chain_1','elevator_boot_floor'):
            check(name+' exists',any(o.name==name for o in objects))
        check('Elevator has open bucket cups',len([o for o in objects if o.name.startswith('elevator_bucket_floor')])==24)
        for side in (-1,1):
            floor=named(f'elevator_bucket_floor_{side}_0');wall=named(f'elevator_bucket_outer_{side}_0')
            fz=sum(bounds(floor)[i][2] for i in (0,1))/2
            wz=sum(bounds(wall)[i][2] for i in (0,1))/2
            check('Ascending cups open upward' if side<0 else 'Return cups inverted', (wz-fz)*(-side)>0)
        check('Tipping bucket at elevator head',any(o.name=='elevator_tipping_bucket_floor' for o in objects))
        check('Gallery has independent X-braced trestle',len([o for o in objects if o.name.startswith('charge_upper_xbrace')])==6)
        for i in range(2):
            for suffix in ('uptake_collar','hopper_joint'):
                collar=next(o for o in objects if o.name==f'line{i}_{suffix}')
                bm=bmesh.new();bm.from_mesh(collar.data)
                check(collar.name+' closed joint ring',all(e.is_manifold for e in bm.edges))
                bm.free()
    check('No broad site plate',not any('ground' in o.name.lower() for o in objects))
    anchors=[]
    for i in range(len(vessels)):
        rim=next(o for o in objects if o.name==f'line{i}_flue_rim')
        lo,hi=bounds(rim)
        p=world_to_camera_view(scene,scene.camera,Vector(((lo[0]+hi[0])/2,(lo[1]+hi[1])/2,(lo[2]+hi[2])/2+.01)))
        anchors.append({'x':p.x*1024,'y':(1-p.y)*1024,'radius':.12*1024/scene.camera.data.ortho_scale})
    report[str(level)]={'checks':tests,'mesh_objects':len(objects),
                        'triangles':sum(len(p.vertices)-2 for o in objects for p in o.data.polygons),
                        'raw_smoke_anchors':anchors}
    for kind in ('windows','light'):
        white=bpy.data.materials.new('review_white_'+kind); white.use_nodes=True
        black=bpy.data.materials.new('review_black_'+kind); black.use_nodes=True
        for m,c in ((white,(1,1,1,1)),(black,(0,0,0,1))):
            nt=m.node_tree;nt.nodes.clear()
            e=nt.nodes.new('ShaderNodeEmission');e.inputs['Color'].default_value=c
            out=nt.nodes.new('ShaderNodeOutputMaterial');nt.links.new(e.outputs[0],out.inputs['Surface'])
        for ob in objects:
            lit=ob.name.endswith('_glass') if kind=='windows' else ob.name.endswith('_heat')
            ob.data.materials.clear();ob.data.materials.append(white if lit else black)
            for polygon in ob.data.polygons: polygon.material_index=0
        scene.render.use_freestyle=False
        scene.view_layers[0].use_freestyle=False
        scene.view_settings.view_transform='Standard'
        scene.render.filepath=str(root/'fx_raw'/f'furnace_lvl{level}_{kind}.png')
        bpy.ops.render.render(write_still=True)
(root/'geometry-review.json').write_text(json.dumps(report,indent=2)+'\n')
print('FURNACE REVIEW PASSED',sum(len(row['checks']) for row in report.values()),'checks')
