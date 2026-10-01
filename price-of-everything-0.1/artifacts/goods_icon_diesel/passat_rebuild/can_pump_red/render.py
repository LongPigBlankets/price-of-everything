import os,sys,json,math
here=os.path.dirname(os.path.abspath(__file__))
for fn in ('sprite_kit.py','goods_icon_kit.py','passat.py'):exec(compile(open(os.path.join(here,fn)).read(),fn,'exec'))
argv=sys.argv[sys.argv.index('--')+1:];out,nm=argv
os.makedirs(out,exist_ok=True)
metrics=globals()['build_'+nm]()
bpy.context.view_layer.update()
checks=Kit(bpy.data.collections['ICON_'+nm]).validate()
print('VALIDATION',checks)
assert not any('BELOW' in x or 'CROSSES' in x for x in checks),checks
metrics['validation']=checks
metrics['frame']=render_icon('ICON_'+nm,os.path.join(out,nm+'_raw.png'))
cam=bpy.context.scene.camera;assert cam.data.type=='ORTHO'
assert all(abs(math.degrees(a)-b)<.01 for a,b in zip(cam.rotation_euler,(54.7356,0,45)))
metrics['camera_degrees']=[math.degrees(x) for x in cam.rotation_euler]
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(out,nm+'.blend'))
with open(os.path.join(out,'metrics.json'),'w') as f:json.dump(metrics,f,indent=2,default=str)
