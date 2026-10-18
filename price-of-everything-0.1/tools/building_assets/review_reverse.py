"""Render a saved building scene from the opposite azimuth, without editing it.

The camera turns 180 degrees about the vertical and recentres on the silhouette, then a
screen-relative face mask is rendered for the print pass, so the rear can be printed exactly
like the front sprite (review_sheet.py does that).

blender --background <revision>/<family>_L<n>.blend --python review_reverse.py -- <outdir> <level>
Writes <outdir>/<family>_L<n>_reverse_raw.png and _reverse_mask_raw.png; <family> is taken
from the .blend name."""
import sys
from pathlib import Path
import bpy
from mathutils import Vector

out = Path(sys.argv[sys.argv.index('--')+1]); level = sys.argv[sys.argv.index('--')+2]
family = Path(bpy.data.filepath).stem.rsplit('_L', 1)[0]
out.mkdir(parents=True, exist_ok=True)
scene = bpy.context.scene
cam = scene.camera
direction = Vector((-1, 1, 1)).normalized()
rotation = (-direction).to_track_quat('-Z', 'Y')
right = rotation @ Vector((1, 0, 0)); up = rotation @ Vector((0, 1, 0))
points = [ob.matrix_world @ v.co for ob in scene.objects
          if ob.type == 'MESH' and not ob.hide_render for v in ob.data.vertices]
u = [p.dot(right) for p in points]; v = [p.dot(up) for p in points]
target = right * ((min(u)+max(u))/2) + up * ((min(v)+max(v))/2)
cam.location = target + direction * 26
cam.rotation_euler = rotation.to_euler()
scene.render.filepath = str(out / f'{family}_L{level}_reverse_raw.png')
bpy.ops.render.render(write_still=True)
mat = bpy.data.materials.new('_reverse_shade_mask'); mat.use_nodes = True
nt = mat.node_tree; nt.nodes.clear()
geo = nt.nodes.new('ShaderNodeNewGeometry')
dot = nt.nodes.new('ShaderNodeVectorMath'); dot.operation = 'DOT_PRODUCT'
dot.inputs[1].default_value = (0.30, 0.62, 0.72)
rng = nt.nodes.new('ShaderNodeMapRange')
rng.inputs['From Min'].default_value = -1; rng.inputs['From Max'].default_value = 1
rng.inputs['To Min'].default_value = 0.04; rng.inputs['To Max'].default_value = 1; rng.clamp = True
emi = nt.nodes.new('ShaderNodeEmission'); output = nt.nodes.new('ShaderNodeOutputMaterial')
nt.links.new(geo.outputs['Normal'], dot.inputs[0]); nt.links.new(dot.outputs['Value'], rng.inputs['Value'])
nt.links.new(rng.outputs['Result'], emi.inputs['Color']); nt.links.new(emi.outputs['Emission'], output.inputs['Surface'])
scene.view_settings.view_transform = 'Standard'
scene.view_layers[0].material_override = mat
scene.view_layers[0].use_freestyle = False; scene.render.use_freestyle = False
scene.render.filepath = str(out / f'{family}_L{level}_reverse_mask_raw.png')
bpy.ops.render.render(write_still=True)
print('REVERSE_RENDER_OK', flush=True)
