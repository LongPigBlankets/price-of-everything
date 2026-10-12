"""Frozen offshore L1/L2/L3 exterior geometry and load-path audit.
blender --background --python-exit-code 1 --python audit_offshore.py -- REVISION [LEVEL]
"""
import bpy,json,sys,hashlib,re
from pathlib import Path
from mathutils import Vector
from mathutils.bvhtree import BVHTree
revision=Path(sys.argv[sys.argv.index('--')+1]).resolve()
args=sys.argv[sys.argv.index('--')+1:]
level=int(args[1]) if len(args)>1 else 1
bpy.ops.wm.open_mainfile(filepath=str(revision/f'offshore_oil_platform_L{level}.blend'))
obs={o.name:o for o in bpy.data.collections['BLDG_offshore_oil_platform'].objects if o.type=='MESH'}
bounds={};trees={}
for n,o in obs.items():
    p=[o.matrix_world@v.co for v in o.data.vertices]
    bounds[n]=([min(v[i] for v in p) for i in range(3)],[max(v[i] for v in p) for i in range(3)])
    trees[n]=BVHTree.FromPolygons(p,[f.vertices[:] for f in o.data.polygons])
def hit(a,b):
    al,ah=bounds[a];bl,bh=bounds[b]
    return min(min(ah[j],bh[j])-max(al[j],bl[j]) for j in range(3))>1e-5 and bool(trees[a].overlap(trees[b]))
def intentional(a,b):
    for x,y in ((a,b),(b,a)):
        if obs[x].get('joint_pipe')==y:return True
        if x=='main_deck' and y.startswith(('helideck_cantilever','stair_stringer','treatment_stringer')):return True
        if x.startswith('deck_edge') and re.fullmatch(r'(front|rear|right|left|right_rear)_guard_post(?:\.\d+)?',y):return True
        if x=='treatment_landing_girder' and y in ('treatment_column.003','treatment_girder.001','treatment_crossbeam.001','treatment_floor','treatment_brace.001'):return True
    return {a,b} in (
        {'deck_crossbeam.004','treatment_export_bracket'},
        {'production_line_seg3','treatment_feed_seg0'},
        {'production_line_elb3','treatment_feed_seg0'},
        {'treatment_vessel_0','treatment_feed_seg4'},
        {'treatment_vessel_0_head','treatment_top_link_seg0'},
        {'treatment_vessel_1','treatment_export_seg0'},
        {'treatment_vessel_1_head','treatment_top_link_seg2'},
        {'BOP','production_line_seg0'},{'production_line_seg3','flare_feed_seg0'},
        # Explicit nozzles and tees for the L2 processing module.
        {'export_line_seg2','upgrade_feed_seg0'},
        {'export_line_elb3','upgrade_compressor_out_seg3'},
        {'upgrade_vessel_0_head0','upgrade_interstage_seg0'},
        {'upgrade_vessel_0_head1','upgrade_feed_seg6'},
        {'upgrade_vessel_1_head0','upgrade_interstage_seg2'},
        {'upgrade_vessel_1_head1','upgrade_compressor_in_seg0'},
        {'compressor_housing','upgrade_compressor_in_seg5'},
        {'compressor_housing','upgrade_compressor_out_seg0'})
contacts=[];unexpected=[];names=list(obs)
for i,a in enumerate(names):
    for b in names[i+1:]:
        if obs[a].get('assembly')==obs[b].get('assembly') or not hit(a,b):continue
        (contacts if intentional(a,b) else unexpected).append([a,b])
checks=[]
def clear(a,others):
    for b in others:assert not hit(a,b),('Unexpected contact',a,b)
    checks.append(a+' clear')
def support(a,b):
    al,ah=bounds[a];bl,bh=bounds[b]
    assert al[2]<=bh[2]+1e-5 and al[2]>=bl[2]-1e-5,(a,b,'vertical bearing missing')
    assert all(min(ah[j],bh[j])-max(al[j],bl[j])>1e-5 for j in (0,1)),(a,b,'bearing overlap missing')
    checks.append(a+' supported')
assert not unexpected,unexpected
piers={}
for sx in (-1,1):
    for sy in ((-1,1,-2,2) if level==3 else ((-1,1,-2) if level>=2 else (-1,1))):
        py=-3.20 if sy==-2 else (3.20 if sy==2 else sy*1.40)
        prefix='lattice_pier_%s_%s'%(sx,sy)
        parts=[n for n in obs if n.startswith(prefix)]
        chords=[n for n in parts if '_chord' in n]
        heads=[n for n in parts if '_head_' in n]
        braces=[n for n in parts if '_brace' in n]
        assert len(chords)==4 and len(heads)==4 and len(braces)==8,'Incomplete lattice pier'
        for n in chords:assert abs(bounds[n][0][2])<1e-5,'Pier does not meet baseline'
        for head in heads:
            chord=next(c for c in chords if all(min(bounds[head][1][j],bounds[c][1][j])-max(bounds[head][0][j],bounds[c][0][j])>1e-5 for j in (0,1)))
            support(head,chord)
            assert any(hit(head,k) for k in obs if k.startswith(('deck_primary_beam','deck_crossbeam'))),'Pier head misses deck framing'
        for brace in braces:
            assert sum(bool(trees[brace].overlap(trees[c])) for c in chords)>=2,('Brace does not connect two chords',brace)
        # All bracing stays within one .80m footprint: no skirt between piers.
        for n in parts:
            lo,hi=bounds[n]
            assert lo[0]>=sx*2.25-.40 and hi[0]<=sx*2.25+.40
            assert lo[1]>=py-.40 and hi[1]<=py+.40
        piers[prefix]=parts
assert not any(n.startswith(('platform_leg','jacket_diagonal','jacket_horizontal')) for n in obs),'Solid columns or shared perimeter web returned'
assert len(piers)==(8 if level==3 else (6 if level>=2 else 4))
checks.append(str(len(piers))+' separate braced lattice piers with open bays')
lo,hi=bounds['helideck']
assert abs((hi[0]-lo[0])-(hi[1]-lo[1]))<1e-5 and len(obs['helideck'].data.vertices)==8,'Helideck must be square'
assert len([n for n in obs if n.startswith('helipad_square')])==4,'Square landing mark missing'
assert 'helipad_circle' not in obs,'Circular landing mark returned'
checks.append('square helipad retained')
for name in ('quarters','crane_pedestal','crane_foot_flange','separator_saddle','separator_saddle.001','drill_floor_leg','drill_floor_leg.001','drill_floor_leg.002','drill_floor_leg.003'):
    support(name,'main_deck')
for name in ['quarters_vent']+[n for n in obs if n.startswith('helideck_access') and n!='helideck_access_landing']:
    clear(name,['helideck'])
for name in ('production_line_seg2','export_line_seg4'):
    if name in obs:clear(name,[n for n in obs if obs[n].get('assembly')=='structure'])
clear('drillstring',[n for n in obs if n.startswith(('main_deck','drill_floor_','derrick_'))])
rope=sorted([n for n in obs if n.startswith('reeving_')],key=lambda n:int(n.split('_')[1]))
assert len(rope)==39,('Missing reeving segments',len(rope))
# Every rope section has a common circular endpoint with its successor.
def ends(n):
    o=obs[n]
    return [sum([o.matrix_world@o.data.vertices[i].co for i in f.vertices],Vector())/len(f.vertices)
            for f in o.data.polygons if len(f.vertices)>4]

for a,b in zip(rope,rope[1:]):
    assert min((p-q).length for p in ends(a) for q in ends(b))<1e-5,(a,b,'disconnected rope')
for n in rope:
    clear(n,[k for k in obs if k.startswith(('derrick_','crown_girder','crown_bearing'))])
clear('crane_rope',[n for n in obs if n.startswith('crane_boom_')])
# Same-assembly parts need explicit clearance checks too: assembly grouping
# must not hide a hydraulic ram cutting through a lattice or a gas line
# occupying a structural chord.
clear('crane_luff_cylinder',[n for n in obs if n.startswith(('crane_boom_', 'crane_root_frame', 'crane_tip_'))])
flare_structure=[n for n in obs if n.startswith(('flare_chord','flare_upper_chord','flare_lattice','flare_crossframe','flare_root_upright','flare_burner_mount'))]
for n in obs:
    if n.startswith('flare_feed'):clear(n,flare_structure)
frames=[n for n in obs if n.startswith('flare_crossframe')]
assert len(frames)==18,'Flare needs six complete triangular station frames'
def joined(a,b):
    assert trees[a].overlap(trees[b]),('Disconnected joint',a,b)
for a in ('flare_crossframe.015','flare_crossframe.016','flare_crossframe.017'):
    assert sum(bool(trees[a].overlap(trees[b])) for b in ('flare_chord','flare_chord.001','flare_upper_chord'))>=2,('Open flare tip frame',a)
joined('flare_burner_mount','flare_upper_chord')
joined('flare_burner_mount','flare_tip')
joined('flare_root_upright','flare_upper_chord')
for a,b in (('crane_root_frame','crane_boom_chord'),('crane_root_frame.001','crane_boom_chord.001')):
    joined(a,b)
    joined(a,'crane_boom_top')
joined('crane_luff_cylinder','crane_ram_trunnion')
checks.append('flare tip triangle, burner support and crane root connections complete')
if 'crane_tip_sheave' in obs:
    assert trees['crane_rope'].overlap(trees['crane_tip_sheave']),'Crane rope not seated against sheave'
    assert trees['crane_luff_cylinder'].overlap(trees['crane_luff_pin']),'Luff cylinder has no pin'
    checks.append('crane sheave and luff pin connected')
# Drillstring must coincide with the conductor and top-drive axes in plan.
for n in ('conductor','BOP','well_riser','top_drive','drillstring'):
    lo,hi=bounds[n];assert abs((lo[0]+hi[0])/2-.75)<1e-5 and abs((lo[1]+hi[1])/2-.45)<1e-5,(n,'off well axis')
assert abs(bounds['drillstring'][1][2]-bounds['top_drive'][0][2])<1e-5,'Top-drive connection gap'
assert any(trees['top_drive'].overlap(trees[n]) for n in obs if n.startswith('block_clevis')),'Missing top-drive clevis'
if level>=2:
    for n in obs:
        if '_saddle' in n and n.startswith('upgrade_vessel_') or n.startswith('compressor_foot'):
            support(n,'main_deck')
    for i in (0,1):
        name='upgrade_vessel_'+str(i)
        for saddle in (name+'_saddle',name+'_saddle.001'):
            joined(saddle,name)
        joined(name+'_gauge_stem',name)
    support('compressor_housing','compressor_foot')
    support('compressor_housing','compressor_foot.001')
    for n in obs:
        if n.startswith('upgrade_') and obs[n].get('assembly')=='upgrade_pipework':
            clear(n,[k for k in obs if obs[k].get('assembly') in ('crane','stairs','structure','guards')])
    # Keep the central extension aisle open, from stair approach to front rail.
    aisle=([-.06,-3.65,2.24],[.36,-1.75,4.0])
    for n in obs:
        if obs[n].get('assembly') not in ('upgrade_pipework','compressor','upgrade_vessel_0','upgrade_vessel_1'):continue
        lo,hi=bounds[n]
        assert not all(min(hi[j],aisle[1][j])-max(lo[j],aisle[0][j])>1e-5 for j in range(3)),('Aisle obstructed',n)
    pipe_groups=('upgrade_feed','upgrade_interstage','upgrade_compressor_in','upgrade_compressor_out')
    for i,prefix in enumerate(pipe_groups):
        for n in obs:
            if n.startswith(prefix):clear(n,[k for k in obs if any(k.startswith(p) for p in pipe_groups[i+1:])])
    checks.append('L2 vessel saddles, compressor support, pipe clearances and unobstructed central aisle')
if level==3:
    columns=[n for n in obs if n.startswith('treatment_column')]
    assert len(columns)==4
    for n in columns:
        support(n,'main_deck')
        assert any(hit(n,k) for k in obs if k.startswith('treatment_girder')),(n,'Upper bearing missing')
    for n in obs:
        if n.startswith('treatment_stair') and re.fullmatch(r'treatment_stair(?:\.\d+)?',n):
            assert any(hit(n,k) for k in obs if k.startswith('treatment_stringer')),(n,'Unsupported stair tread')
    support('treatment_landing_column','main_deck')
    for i in (0,1):
        n='treatment_vessel_'+str(i)
        support(n+'_skirt','treatment_floor')
        support(n,n+'_skirt')
    for n in obs:
        if obs[n].get('assembly')=='treatment_pipework' and n!='treatment_export_bracket':
            clear(n,[k for k in obs if obs[k].get('assembly') in ('treatment_access','treatment_structure','crane','flare','drilling','guards','structure')])
    runs=('treatment_feed','treatment_top_link','treatment_export')
    for i,prefix in enumerate(runs):
        for n in obs:
            if n.startswith(prefix) and 'support' not in n and 'bracket' not in n:
                clear(n,[k for k in obs if any(k.startswith(p) for p in runs[i+1:]) and 'bracket' not in k])
    checks.append('L3 upper platform load path, stair treads, vessel bearings and separate pipe runs')
collars=[n for n in obs if obs[n].get('joint_host')]
assert len(collars)==(12 if level==3 else (8 if level==2 else 2))
for n in collars:
    joined(n,obs[n]['joint_host'])
    joined(n,obs[n]['joint_pipe'])
checks.append(str(len(collars))+' pipe-entry collars attached to host and pipe')
result=dict(pipe_entry_collars=len(collars),level=level,source_sha256=hashlib.sha256((revision/'source/builders.py').read_bytes()).hexdigest(),objects=len(obs),
            intended_cross_assembly_contacts=contacts,unexpected_intersections=unexpected,checks=checks,
            continuous_reeving_segments=len(rope),scope='Depicted exterior, selected clearances/supports and rope continuity; simplified equipment internals. Not load-capacity certification.')
(revision/f'offshore-engineering-check-L{level}.json').write_text(json.dumps(result,indent=2)+'\n')
print('OFFSHORE_GEOMETRY_PASS L'+str(level),len(obs),'objects;',len(checks),'targeted checks;',len(rope),'connected rope segments',flush=True)
