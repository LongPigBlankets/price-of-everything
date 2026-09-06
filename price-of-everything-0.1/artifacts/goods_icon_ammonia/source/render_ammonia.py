import os,sys,json
here=os.path.dirname(os.path.abspath(__file__))
for fn in ('sprite_kit.py','goods_icon_kit.py'):
    exec(compile(open(os.path.join(here,fn)).read(),fn,'exec'))
out=sys.argv[sys.argv.index('--')+1]
os.makedirs(out,exist_ok=True)
metrics=build_ammonia()
metrics['frame']=render_icon('ICON_ammonia',os.path.join(out,'ammonia_raw.png'))
bpy.ops.file.pack_all()
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(out,'ammonia.blend'))
with open(os.path.join(out,'build_metrics.json'),'w') as f: json.dump(metrics,f,indent=2)
