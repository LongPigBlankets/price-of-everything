"""Render a staged building's window and light masks and its effect anchors from a frozen
revision: the general form of furnace_v2_fx.py, configured per family below.

blender --background --factory-startup --python building_fx.py -- <revision> <family>

Opens each level's saved scene and records, in raw render pixels:
  smoke   chimney mouths (the top face of each named object), drawn as smoke or steam
  steam   steam vents such as a cooling tower's throat
  cables  conductors, as the two ends of each named line object, front to back
Then renders two masks with every surface black except the lit set: window panes
(objects named *_glass) for 'windows', and the family's light objects for 'light'.
package_building_fx.py aligns all of it to the 800 px sprites. Nothing in the game is
touched.
"""
import bpy, json, sys
from pathlib import Path
from mathutils import Vector
from bpy_extras.object_utils import world_to_camera_view

FAMILIES = {
    # The flare's flame is baked into the art; the light mask lets the board light it.
    'petro_refinery_v2': dict(smoke=(), steam=(), cables=(), light=('flare_flame',)),
    'poly_plant_v2': dict(smoke=(), steam=(), cables=(), light=()),
    'power_plant_v2': dict(smoke=('stack_top',), steam=('tower_void',), cables=('line_phase', 'line_rise'), light=()),
    # The bath and the caster strand are baked light; the bath also gets the arc's shifting hot spot.
    'eaf_v2': dict(smoke=('stack_top',), steam=(), cables=(), light=('furnace_melt', 'strand'), fires=('furnace_melt',)),
}

root = Path(sys.argv[sys.argv.index('--')+1])
family = sys.argv[sys.argv.index('--')+2]
config = FAMILIES[family]
(root/'fx_raw').mkdir(exist_ok=True)
report_path = root/'fx_raw'/'report.json'
report = json.loads(report_path.read_text()) if report_path.exists() else {}


def world_points(ob):
    return [ob.matrix_world@v.co for v in ob.data.vertices]


for level in (1, 2, 3):
    bpy.ops.wm.open_mainfile(filepath=str(root/f'{family}_L{level}.blend'))
    scene = bpy.context.scene
    res = scene.render.resolution_x
    scale = res/scene.camera.data.ortho_scale

    def raw(p):
        q = world_to_camera_view(scene, scene.camera, p)
        return [q.x*res, (1-q.y)*res]
    objects = [o for o in bpy.data.collections['BLDG_'+family].objects if o.type == 'MESH']
    entry = {'smoke': [], 'steam': [], 'cables': [], 'fires': []}
    for kind in ('smoke', 'steam'):
        for ob in objects:
            if ob.name.split('.')[0] not in config[kind]: continue
            pts = world_points(ob)
            lo = [min(p[i] for p in pts) for i in range(3)]; hi = [max(p[i] for p in pts) for i in range(3)]
            x, y = raw(Vector(((lo[0]+hi[0])/2, (lo[1]+hi[1])/2, hi[2]+.01)))
            entry[kind].append({'x': x, 'y': y, 'radius': (hi[0]-lo[0])/2*scale})
    for ob in objects:
        if not ob.name.split('.')[0].startswith(config['cables']) or not config['cables']: continue
        pts = world_points(ob)
        a, b = max(((p, q) for p in pts for q in pts), key=lambda pq: (pq[0]-pq[1]).length)
        if a.y > b.y: a, b = b, a
        entry['cables'].append([raw(a), raw(b)])
    for ob in objects:
        if ob.name.split('.')[0] not in config.get('fires', ()): continue
        xs, ys = zip(*(raw(p) for p in world_points(ob)))
        entry['fires'].append({'x0': min(xs), 'y0': min(ys), 'x1': max(xs), 'y1': max(ys)})
    lit_light = [o for o in objects if o.name.split('.')[0] in config['light']]
    entry['glass'] = sum(o.name.endswith('_glass') for o in objects)
    entry['light'] = len(lit_light)
    report[f'{family}/{level}'] = entry
    for kind in ('windows', 'light'):
        if kind == 'windows' and not entry['glass']: continue
        if kind == 'light' and not lit_light: continue
        white = bpy.data.materials.new('fx_white_'+kind); white.use_nodes = True
        black = bpy.data.materials.new('fx_black_'+kind); black.use_nodes = True
        for m, c in ((white, (1, 1, 1, 1)), (black, (0, 0, 0, 1))):
            nt = m.node_tree; nt.nodes.clear()
            e = nt.nodes.new('ShaderNodeEmission'); e.inputs['Color'].default_value = c
            out = nt.nodes.new('ShaderNodeOutputMaterial'); nt.links.new(e.outputs[0], out.inputs['Surface'])
        for ob in objects:
            lit = ob.name.endswith('_glass') if kind == 'windows' else ob in lit_light
            ob.data.materials.clear(); ob.data.materials.append(white if lit else black)
            for polygon in ob.data.polygons: polygon.material_index = 0
        scene.render.use_freestyle = False
        scene.view_layers[0].use_freestyle = False
        scene.view_settings.view_transform = 'Standard'
        scene.render.filepath = str(root/'fx_raw'/f'{family}_lvl{level}_{kind}.png')
        bpy.ops.render.render(write_still=True)
report_path.write_text(json.dumps(report, indent=2)+'\n')
print('BUILDING FX RENDERED', family, flush=True)
