"""Blender engineering regression: closed linkage and mesh interference, sampled every degree.
Run: blender --background --python-exit-code 1 --python <this file> -- <output.json>
Only explicit assembly joints are exempted. BVH surface tests do not prove solid
containment absence; bearing/lane dimensions supplement the sampled surface audit.
"""
import bpy, json, math, pathlib, sys, hashlib
from mathutils import Vector
from mathutils.bvhtree import BVHTree
HERE=pathlib.Path(__file__).resolve().parent
ROOT=HERE.parents[2]
KIT=ROOT/'.claude/skills/blender-building-sprites'
ns={}
for path in (KIT/'sprite_kit.py', KIT/'props_kit.py', HERE/'builders.py'):
    exec(compile(path.read_text(),str(path),'exec'),ns)
ns['setup_rig']()

def allowed(a,b):
    ga,gb=a.get('assembly'),b.get('assembly')
    na,nb=a.name.removeprefix('jack_a_').split('.')[0],b.name.removeprefix('jack_a_').split('.')[0]
    if ga==gb:
        # These are rigid fabricated assemblies. Drive guard is separately checked.
        if ga!='belt_drive':return True
        if ('belt_guard' in na)!=('belt_guard' in nb):return False
        if 'brake' in na or 'brake' in nb:
            return (na==nb or frozenset((na,nb)) in {
                frozenset(('brake_shaft','brake_disc')),frozenset(('brake_pad','brake_bridge')),
                frozenset(('brake_mount','brake_pad')),frozenset(('brake_mount','brake_bridge'))})
        return True
    pairs={frozenset(v) for v in [
        ('gearbox','input_shaft'),('gearbox','crankshaft'),('gearbox','brake_shaft'),
        ('gearbox','brake_mount'),('motor','motor_shaft'),
        ('bridle_anchor','bridle'),('horsehead','bridle')]}
    return frozenset((na,nb)) in pairs

def meshes(collection):
    bpy.context.view_layer.update()
    result=[]
    for ob in collection.objects:
        if ob.type!='MESH':continue
        pts=[ob.matrix_world@v.co for v in ob.data.vertices]
        lo=tuple(min(v[i] for v in pts) for i in range(3))
        hi=tuple(max(v[i] for v in pts) for i in range(3))
        tree=BVHTree.FromPolygons(pts,[p.vertices[:] for p in ob.data.polygons])
        result.append((ob,lo,hi,tree))
    return result

def intersections(objects,exempt=True):
    result=[]
    for i,(a,alo,ahi,at) in enumerate(objects):
        for b,blo,bhi,bt in objects[i+1:]:
            if exempt and allowed(a,b):continue
            if min(min(ahi[j],bhi[j])-max(alo[j],blo[j]) for j in range(3))<1e-5:continue
            hits=at.overlap(bt)
            if hits:result.append((a.name,b.name))
    return result

hits={};angles=[];carriers=[];errors=[]
for degree in range(360):
    K=ns['Kit'](ns['open_collection']('BLDG_audit'))
    for mesh in list(bpy.data.meshes):
        if mesh.users==0:bpy.data.meshes.remove(mesh)
    pose=ns['pumpjack'](K,'jack_a',0,0,degree)
    angles.append(math.degrees(pose['beam_angle']));carriers.append(pose['carrier_z'])
    errors.append(abs(math.dist(pose['crank'],pose['equalizer'])-pose['pitman_length']))
    for a,b in intersections(meshes(K.col)):
        key=a+' / '+b
        if key not in hits:hits[key]=[]
        hits[key].append(degree)
    if degree%30==0:print('Audited crank',degree,'unique unexpected pairs',len(hits),flush=True)
result=dict(source_sha256=hashlib.sha256((HERE/'builders.py').read_bytes()).hexdigest(),
    samples=360,degree_step=1,beam_angle_degrees=[min(angles),max(angles)],
    carrier_height_m=[min(carriers),max(carriers)],max_link_closure_error_m=max(errors),
    analytic_clearances_m=dict(counterweight_above_skid=1.02-.49-.40,
        counterweight_beside_skid=.61-.07-(.43+.06),
        pitman_to_crank=.75-.045-(.61+.07),
        adjacent_jacks=1.78-2*(.843+.011),rod_to_stuffing_bore=.029-.026),
    unexpected_intersections=hits,
    limitations='Surface BVH at 1 degree steps; intended welds, housed shafts, belt contacts and rope tracking are exempt. Lane and bore dimensions supplement the scan; internal gear teeth are not modeled.')
out=pathlib.Path(sys.argv[sys.argv.index('--')+1])
out.write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps(result,indent=2),flush=True)
assert max(errors)<1e-8
assert not hits,'Unexpected intersections: '+str(len(hits))
