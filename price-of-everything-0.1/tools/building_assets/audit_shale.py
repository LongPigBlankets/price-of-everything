"""Audit frozen shale scenes: separate assemblies, connected ports and load supports.
blender --background --python-exit-code 1 --python audit_shale.py -- <revision-dir>
The exterior mesh test exempts only listed cross-assembly nozzle/tee joints.
Rigid assembly internals are supplemented by targeted mounting/clearance checks.
"""
import bpy,json,pathlib,sys,re,hashlib
from mathutils.bvhtree import BVHTree
revision=pathlib.Path(sys.argv[sys.argv.index('--')+1]).resolve()

def box(ob):
    pts=[ob.matrix_world@v.co for v in ob.data.vertices]
    lo=tuple(min(v[i] for v in pts) for i in range(3))
    hi=tuple(max(v[i] for v in pts) for i in range(3))
    return lo,hi,pts

def intentional(a,b):
    pair=sorted((a,b))
    if pair==sorted(('blender_lower','water_to_blender_seg0')):return True
    for pattern,header in [(r'pump_suction_\d+_seg1','low_pressure_header_seg0'),
                           (r'pump_discharge_\d+_seg0','high_pressure_header_seg0'),
                           (r'well_branch_\d+_seg0','zipper_manifold_seg0')]:
        if header in pair and any(re.fullmatch(pattern,n) for n in pair):return True
    return False

results={}
for level in (1,2,3):
    bpy.ops.wm.open_mainfile(filepath=str(revision/f'fracking_oil_well_L{level}.blend'))
    objects={o.name:o for o in bpy.data.collections['BLDG_fracking_oil_well'].objects if o.type=='MESH'}
    bounds={name:box(ob)[:2] for name,ob in objects.items()}
    trees={name:BVHTree.FromPolygons(box(ob)[2],[p.vertices[:] for p in ob.data.polygons]) for name,ob in objects.items()}
    unexpected=[];contacts=[];mount_checks=0;port_checks=0
    names=list(objects)
    for i,a in enumerate(names):
        for b in names[i+1:]:
            if objects[a].get('assembly')==objects[b].get('assembly'):continue
            alo,ahi=bounds[a];blo,bhi=bounds[b]
            if min(min(ahi[j],bhi[j])-max(alo[j],blo[j]) for j in range(3))<1e-5:continue
            if not trees[a].overlap(trees[b]):continue
            (contacts if intentional(a,b) else unexpected).append([a,b])
    def supported(name,candidates):
        global mount_checks
        lo,hi=bounds[name]
        ok=[]
        for other in candidates:
            blo,bhi=bounds[other]
            if abs(lo[2]-bhi[2])<1e-5 and all(min(hi[j],bhi[j])-max(lo[j],blo[j])>1e-5 for j in (0,1)):ok.append(other)
        assert ok,f'{name} has no bearing support: {candidates}'
        mount_checks+=1
    def mates(a,b,axis):
        global port_checks
        alo,ahi=bounds[a];blo,bhi=bounds[b]
        assert abs(ahi[axis]-blo[axis])<1e-5,(a,b,'port-end gap')
        for j in range(3):
            if j!=axis:assert abs((alo[j]+ahi[j]-blo[j]-bhi[j])/2)<1e-5,(a,b,'off-axis')
        port_checks+=1
    for i in range(level+1):
        prefix=f'frac_pump_{i}'
        supports=[n for n in names if n.startswith(prefix+'_crossmember')]
        supported(prefix+'_power_foot',supports)
        supported(prefix+'_engine_foot',supports)
        mates(prefix+'_discharge_port',f'pump_discharge_{i}_seg0',0)
        mates(f'pump_suction_{i}_seg0',prefix+'_suction_port',2)
    for i in range(level):
        supported(f'well_isolation_{i}',[f'branch_support_{i}_post'])
        mates(f'well_branch_{i}_seg2',f'frac_tree_{i}_inlet',0)
    supported('additive_tote',['additive_bracket'])
    supported('additive_bracket',['blender_lower'])
    for n in ('blender_tub','blender_lip','blender_drive'):
        assert not trees['additive_tote'].overlap(trees[n]),('additive tank clash',n)
    auger_parts=[n for n in names if n.startswith('sand_auger_') and n!='sand_auger_motor']
    for n in auger_parts:
        for other in ('blender_tub','blender_lip','blender_floor'):
            assert not trees[n].overlap(trees[other]),('auger clash',n,other)
    assert trees['auger_support_post'].overlap(trees['sand_auger_elb1']),'Unsupported auger bend'
    assert len(contacts)==1+2*(level+1)+level,('Missing or extra connected tees',level,contacts)
    results[f'L{level}']=dict(objects=len(objects),expected_connected_joins=contacts,unexpected_intersections=unexpected,
                             mounting_checks=mount_checks,coaxial_port_checks=port_checks,pumps=level+1,trees=level)
    assert not unexpected,unexpected
result=dict(source_sha256=hashlib.sha256((revision/'source/builders.py').read_bytes()).hexdigest(),levels=results,
            scope='Exterior surface BVH plus selected support/port checks. Rigid assembly internals and hidden pressure-vessel details are simplified.')
(revision/'engineering-check.json').write_text(json.dumps(result,indent=2)+'\n')
print('SHALE_GEOMETRY_PASS', {k:dict(mounts=v['mounting_checks'],ports=v['coaxial_port_checks']) for k,v in results.items()},flush=True)
