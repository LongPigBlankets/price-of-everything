"""Inspection render only: expose the authored L3 lift without changing its scene."""
import bpy, math, sys
from pathlib import Path
from mathutils import Vector

root=Path(sys.argv[sys.argv.index('--')+1]).resolve()
bpy.ops.wm.open_mainfile(filepath=str(root/'furnace_L3.blend'))
scene=bpy.context.scene
visible=[]
for ob in bpy.data.collections['BLDG_furnace'].objects:
    show=ob.name.startswith(('charge_','elevator_'))
    show=show and not any(token in ob.name for token in ('facade','inspection','access_handle'))
    show=show and ob.name not in ('charge_lower_case','charge_upper_case')
    ob.hide_render=not show
    if show and ob.type=='MESH':visible.append(ob)
points=[ob.matrix_world@v.co for ob in visible for v in ob.data.vertices]
u=[(v.x+v.y)/math.sqrt(2) for v in points]
z=[(2*v.z-v.x+v.y)/math.sqrt(6) for v in points]
uc,zc=(min(u)+max(u))/2,(min(z)+max(z))/2
target=Vector((uc/math.sqrt(2),uc/math.sqrt(2),zc*math.sqrt(6)/2))
scene.camera.location=target+Vector((1,-1,1)).normalized()*26
scene.camera.data.ortho_scale=max(max(u)-min(u),max(z)-min(z))*1.18
scene.render.filepath=str(root/'review/lift-cutaway-raw.png')
(root/'review').mkdir(exist_ok=True)
bpy.ops.render.render(write_still=True)
