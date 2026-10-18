"""Render the furnace's window and heat masks and its chimney anchors from a frozen revision.

blender --background --factory-startup --python furnace_v2_fx.py -- <revision>

Opens each level's saved scene, records the chimney top in raw render pixels, then renders
two masks with every surface black except the lit set: glass panes for 'windows', the
working bays' heat cues for 'light'. package_furnace_v2_fx.py aligns them to the sprites.
Nothing in the game is touched.
"""
import bpy, json, sys
from pathlib import Path
from mathutils import Vector
from bpy_extras.object_utils import world_to_camera_view

root = Path(sys.argv[sys.argv.index('--')+1])
(root/'fx_raw').mkdir(exist_ok=True)
report = {}


def bounds(ob):
    pts = [ob.matrix_world@v.co for v in ob.data.vertices]
    return [min(p[i] for p in pts) for i in range(3)], [max(p[i] for p in pts) for i in range(3)]


for level in (1, 2, 3):
    bpy.ops.wm.open_mainfile(filepath=str(root/f'furnace_v2_L{level}.blend'))
    scene = bpy.context.scene
    objects = [o for o in bpy.data.collections['BLDG_furnace_v2'].objects if o.type == 'MESH']
    top = next(o for o in objects if o.name == 'stack_top')
    lo, hi = bounds(top)
    p = world_to_camera_view(scene, scene.camera, Vector(((lo[0]+hi[0])/2, (lo[1]+hi[1])/2, hi[2]+.01)))
    res = scene.render.resolution_x
    report[str(level)] = {'raw_smoke_anchors': [{'x': p.x*res, 'y': (1-p.y)*res,
                                                 'radius': (hi[0]-lo[0])/2*res/scene.camera.data.ortho_scale}],
                          'glass': sum(o.name.endswith('_glass') for o in objects),
                          'heat': sum(o.name.endswith('_heat') for o in objects)}
    assert report[str(level)]['glass'] > 0 and report[str(level)]['heat'] > 0, report[str(level)]
    for kind in ('windows', 'light'):
        white = bpy.data.materials.new('fx_white_'+kind); white.use_nodes = True
        black = bpy.data.materials.new('fx_black_'+kind); black.use_nodes = True
        for m, c in ((white, (1, 1, 1, 1)), (black, (0, 0, 0, 1))):
            nt = m.node_tree; nt.nodes.clear()
            e = nt.nodes.new('ShaderNodeEmission'); e.inputs['Color'].default_value = c
            out = nt.nodes.new('ShaderNodeOutputMaterial'); nt.links.new(e.outputs[0], out.inputs['Surface'])
        for ob in objects:
            lit = ob.name.endswith('_glass') if kind == 'windows' else ob.name.endswith('_heat')
            ob.data.materials.clear(); ob.data.materials.append(white if lit else black)
            # Reset every face to the one slot: reflection-band faces used other indices.
            for polygon in ob.data.polygons: polygon.material_index = 0
        scene.render.use_freestyle = False
        scene.view_layers[0].use_freestyle = False
        scene.view_settings.view_transform = 'Standard'
        scene.render.filepath = str(root/'fx_raw'/f'furnace_v2_lvl{level}_{kind}.png')
        bpy.ops.render.render(write_still=True)
(root/'fx_raw'/'report.json').write_text(json.dumps(report, indent=2)+'\n')
print('FURNACE V2 FX RENDERED', flush=True)
