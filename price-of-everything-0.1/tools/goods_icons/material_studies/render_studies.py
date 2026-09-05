"""Blender --background --factory-startup --python render_studies.py -- OUTPUT [goods...]."""
import sys,json
from pathlib import Path
here=Path(__file__).resolve().parent
for src in ('sprite_kit.py','base_kit.py','goods_icon_kit.py','ore_builders.py'):
    exec(compile((here/src).read_text(),str(here/src),'exec'),globals())
args=sys.argv[sys.argv.index('--')+1:]
out=Path(args[0]).resolve(); out.mkdir(parents=True,exist_ok=True)
for name in args[1:] or ['limestone','electrical_components','ethylene']:
    built=globals()['build_'+name]()
    K=built if isinstance(built,Kit) else Kit(bpy.data.collections['ICON_'+name])
    print('VALIDATION',name,K.validate(),flush=True)
    depsgraph=bpy.context.evaluated_depsgraph_get()
    counts={ob.name:{'control_faces':len(ob.data.polygons),
                     'evaluated_faces':len(ob.evaluated_get(depsgraph).data.polygons)}
            for ob in K.col.objects if ob.type=='MESH'}
    (out/(name+'_geometry.json')).write_text(json.dumps(counts,indent=2))
    hide_other_icons(K.col.name)
    frame_collection(K.col)
    bpy.ops.wm.save_as_mainfile(filepath=str(out/(name+'.blend')))
    render_icon(K.col.name,str(out/('icon_'+name+'_raw.png')))
    print('COMPLETE',name,flush=True)
