"""Render loading stills from the current building builders and capsule earth plate.

blender -b --factory-startup --python tools/loading_carousel/render_tiles.py -- \
    --building industrial_factory --out /absolute/output --res 1024

The two looks share geometry, smoke and camera, so the day/night dissolve stays aligned.
No game models, sprite assets or continent bakes are modified.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path
import sys

import bpy
from mathutils import Matrix, Vector

ROOT = Path(__file__).resolve().parents[2]
KIT = ROOT / '.claude/skills/blender-building-sprites'
DETAIL = ROOT / 'price-of-everything-0.1/tools/building_assets'
CAPSULE = ROOT / 'tools/steam_capsule'
SPECS = {
    'industrial_factory': ('factory_builder.py', 'build_factory', 'BLDG_factory'),
    'furnace': ('furnace_v2_builder.py', 'build_furnace_v2', 'BLDG_furnace_v2'),
    'power_plant': ('power_plant_v2_builder.py', 'build_power_plant_v2', 'BLDG_power_plant_v2'),
    'petro_refinery': ('refinery_v2_builder.py', 'build_petro_refinery_v2', 'BLDG_petro_refinery_v2'),
    'farm': ('builders.py', 'build_farm', 'BLDG_farm'),
    'offshore_wind_farm': ('wind_farm_builder.py', 'build_offshore_wind_farm', 'BLDG_offshore_wind'),
}
ap = argparse.ArgumentParser()
ap.add_argument('--building', choices=SPECS, required=True)
ap.add_argument('--out', type=Path, required=True)
ap.add_argument('--res', type=int, default=1024)
ap.add_argument('--save', action='store_true')
args = ap.parse_args(sys.argv[sys.argv.index('--') + 1:])
args.out.mkdir(parents=True, exist_ok=True)
sources = {}


def execute(path, ns):
    sources[str(path.relative_to(ROOT))] = hashlib.sha256(path.read_bytes()).hexdigest()
    exec(compile(path.read_text(), str(path), 'exec'), ns)


for ob in list(bpy.data.objects):
    if ob.type == 'MESH':
        bpy.data.objects.remove(ob, do_unlink=True)
ns = {'__file__': str(KIT / 'render_sprite.py')}
execute(KIT / 'sprite_kit.py', ns)
execute(KIT / 'props_kit.py', ns)
family = args.building
filename, function, collection = SPECS[family]
if family in ('furnace', 'power_plant', 'petro_refinery'):
    execute(DETAIL / 'furnace_builder.py', ns)
if family in ('power_plant', 'petro_refinery'):
    execute(DETAIL / 'furnace_v2_builder.py', ns)
if family == 'power_plant':
    execute(DETAIL / 'refinery_v2_builder.py', ns)
execute((DETAIL if (DETAIL / filename).exists() else KIT) / filename, ns)
ns[function](3)
objects = [o for o in bpy.data.collections[collection].objects if o.type == 'MESH']
# The offshore builder's rectangular water slab is replaced by the capsule sea hex.
if family == 'offshore_wind_farm':
    for ob in list(objects):
        if ob.name in ('sea', 'water', 'sea_wall', 'seabed') or ob.name.startswith('water_'):
            objects.remove(ob)
            bpy.data.objects.remove(ob, do_unlink=True)

bpy.context.view_layer.update()
pts = [o.matrix_world @ v.co for o in objects for v in o.data.vertices]
centre = Vector(((min(p.x for p in pts) + max(p.x for p in pts))/2,
                 (min(p.y for p in pts) + max(p.y for p in pts))/2, 0))
R = 4.0
# Use the hex's inscribed circle as a strict footprint boundary, including rotor tips.
reach = max(math.hypot(p.x-centre.x, p.y-centre.y) for p in pts)
scale = R * math.sqrt(3)/2 * .88 / reach
ground = min(p.z for p in pts)
transform = Matrix.Translation(Vector((0, 0, .012))) @ Matrix.Scale(scale, 4) @ Matrix.Translation(-centre-Vector((0,0,ground)))
for ob in objects:
    ob.matrix_world = transform @ ob.matrix_world
bpy.context.view_layer.update()
execute(Path(__file__).with_name('material_patterns.py'), ns)
ns['apply_brick_patterns'](objects, scale, centre, ground)

# Separate namespace: legacy builders contain their own rig and palette definitions.
plate_ns = {'__file__': str(KIT / 'render_sprite.py')}
execute(KIT / 'sprite_kit.py', plate_ns)
execute(CAPSULE / 'earth_plate.py', plate_ns)
execute(CAPSULE / 'smoke.py', plate_ns)
plate_ns['LENSES'] = []  # The capsule's local copper lens belongs under its mine.
plate_col = bpy.data.collections.new('LoadingHex')
bpy.context.scene.collection.children.link(plate_col)
K = plate_ns['Kit'](plate_col)
sea = family == 'offshore_wind_farm'
plate, info = plate_ns['build_earth_plate'](K, land=[] if sea else [(0,0)],
    sea=[(0,0)] if sea else [], R=R, river=[])

# The capsule's puff geometry and deterministic plumes, anchored to today's stack names.
stacks = {}
if family == 'industrial_factory':
    stacks['chimney_tip'] = ('smoke', 1.25, 1.55, .35)
if family in ('furnace', 'power_plant'):
    stacks['stack_top'] = ('smoke', 1.25, 1.65, .36)
if family == 'power_plant':
    stacks['tower_void'] = ('steam', 1.0, 1.0, .43)
plate_ns['STACKS'] = stacks
plate_ns['build_smoke']()

scene = bpy.context.scene
plate_ns['setup_rig'](res=args.res)
scene.view_settings.view_transform = 'AgX'
scene.view_settings.look = 'None'
scene.view_settings.exposure = 0
scene.view_settings.gamma = 1
scene.render.image_settings.file_format = 'PNG'
scene.render.image_settings.color_mode = 'RGBA'
scene.render.resolution_percentage = 100
scene.eevee.taa_render_samples = 48
scene.render.filter_size = 1.2
fs = scene.view_layers[0].freestyle_settings
for lines in list(fs.linesets):
    if lines.name not in ('ink', 'ink_fine'):
        fs.linesets.remove(lines)
for lines in fs.linesets:
    lines.select_by_face_marks = True
    lines.face_mark_negation = 'EXCLUSIVE'
    lines.face_mark_condition = 'ONE'
    lines.linestyle.thickness *= args.res / 1536

cam = bpy.data.objects['Camera']
scene.camera = cam
elev = math.radians(30)
cam.rotation_euler = (math.pi/2-elev, 0, math.radians(45))
right = Vector((1,1,0)).normalized()
up = Vector((-math.sin(elev)/math.sqrt(2), math.sin(elev)/math.sqrt(2), math.cos(elev)))
toward = Vector((math.cos(elev)/math.sqrt(2), -math.cos(elev)/math.sqrt(2), math.sin(elev)))
bpy.context.view_layer.update()
pts = [o.matrix_world @ Vector(c) for o in bpy.data.objects if o.type == 'MESH' and not o.hide_render for c in o.bound_box]
sx, sy = [p.dot(right) for p in pts], [p.dot(up) for p in pts]
target = right*((min(sx)+max(sx))/2) + up*((min(sy)+max(sy))/2)
cam.location = target + toward*40
cam.data.ortho_scale = max(max(sx)-min(sx), max(sy)-min(sy))*1.16
cam.data.clip_end = 200

sun = bpy.data.objects['Light']
sun.data.type = 'SUN'
sun.data.use_shadow = False
# Upper-left light in the final picture; no post-render mirroring of the buildings.
sun_dir = Vector((-0.45, -0.65, .82)).normalized()
sun.rotation_euler = sun_dir.to_track_quat('Z','Y').to_euler()
bg = scene.world.node_tree.nodes.get('Background')


def point(name, pos, energy, colour):
    data = bpy.data.lights.new(name, 'POINT')
    data.energy, data.color, data.shadow_soft_size = energy, colour, .65
    ob = bpy.data.objects.new(name, data)
    scene.collection.objects.link(ob)
    ob.location = pos
    return ob


night_lamps = []
warm = (1, .55, .20)
window_mat = bpy.data.materials.new('LoadingWindowLight')
window_mat.use_nodes = True
bsdf = window_mat.node_tree.nodes.get('Principled BSDF')
bsdf.inputs['Base Color'].default_value = (*warm, 1)
bsdf.inputs['Emission Color'].default_value = (*warm, 1)
bsdf.inputs['Emission Strength'].default_value = 1.7
bsdf.inputs['Roughness'].default_value = 1
windows = [o for o in objects if o.name.endswith('_glass') and not o.name.startswith('roof')]
# Factory slope panes are named sky_0, sky_1, etc.; their cream mullions stay unlit.
skylights = [o for o in objects if family == 'industrial_factory'
             and o.name.startswith('sky_') and o.name[4:].isdigit()]
windows += skylights
night_materials = {o: window_mat for o in windows}
hall_glazing = [o for o in objects if o.name in ('hall_glazing-1', 'hall_glazing1')]
interior_lamps = []
if hall_glazing:
    # Keep the turbine roof see-through: light the machinery below it rather than
    # covering the roof with the opaque material used by ordinary window panes.
    glass = hall_glazing[0].data.materials[0].copy()
    glass.name = 'LoadingLitTurbineGlass'
    node = glass.node_tree.nodes.get('Principled BSDF')
    node.inputs['Base Color'].default_value = (.52, .40, .24, 1)
    node.inputs['Emission Color'].default_value = (*warm, 1)
    node.inputs['Emission Strength'].default_value = .25
    node.inputs['Alpha'].default_value = .16
    for ob in hall_glazing:
        night_materials[ob] = glass
    for ob in objects:
        if ob.name.startswith('turbine') and ob.name.endswith('_pedestal'):
            bounds = [ob.matrix_world @ Vector(c) for c in ob.bound_box]
            p = sum(bounds, Vector())/8
            p.z = max(v.z for v in bounds) + .60*scale
            lamp = point('Turbine hall work light', p, 70*scale*scale, (1, .72, .42))
            lamp.data.shadow_soft_size = .20*scale
            interior_lamps.append(lamp)
    night_lamps += interior_lamps


def heat_material(name, axes):
    """A yellow hot centre fading through orange to a red edge on an existing opening."""
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    node = nodes.get('Principled BSDF')
    tex = nodes.new('ShaderNodeTexCoord')
    offset = nodes.new('ShaderNodeVectorMath')
    offset.operation = 'SUBTRACT'
    offset.inputs[1].default_value = (.5, .5, .5)
    plane = nodes.new('ShaderNodeVectorMath')
    plane.operation = 'MULTIPLY'
    plane.inputs[1].default_value = axes
    radius = nodes.new('ShaderNodeVectorMath')
    radius.operation = 'LENGTH'
    ramp = nodes.new('ShaderNodeValToRGB')
    ramp.color_ramp.elements[0].color = (1, 1, .0005, 1)
    ramp.color_ramp.elements[1].color = (.50, .0003, .00005, 1)
    ramp.color_ramp.elements.new(.25).color = (1, 1, .0005, 1)
    ramp.color_ramp.elements.new(.60).color = (1, .20, .0005, 1)
    links.new(tex.outputs['Generated'], offset.inputs[0])
    links.new(offset.outputs[0], plane.inputs[0])
    links.new(plane.outputs[0], radius.inputs[0])
    links.new(radius.outputs['Value'], ramp.inputs[0])
    links.new(ramp.outputs['Color'], node.inputs['Base Color'])
    links.new(ramp.outputs['Color'], node.inputs['Emission Color'])
    node.inputs['Emission Strength'].default_value = 2.5
    node.inputs['Roughness'].default_value = 1
    return mat


heat_sources = []
if family == 'furnace':
    bay_heat = heat_material('LoadingFurnaceHeat', (2, 0, 2))
    molten = heat_material('LoadingMoltenLadle', (2, 2, 0))
    for ob in objects:
        bay = ob.name.endswith('_heat')
        ladle = ob.name.startswith('ladle') and ob.name.endswith('_inside')
        if not (bay or ladle):
            continue
        ob.data.materials.clear()
        ob.data.materials.append(bay_heat if bay else molten)
        bounds = [ob.matrix_world @ Vector(c) for c in ob.bound_box]
        p = sum(bounds, Vector())/8
        p += Vector((0, -.14*scale, .02*scale)) if bay else Vector((0, 0, .08*scale))
        lamp = point('Furnace heat spill', p, (8 if bay else 4)*scale*scale, (1, .06, .002))
        lamp.data.shadow_soft_size = .12*scale
        # Heat remains present in daylight; its spill becomes clearer at night.
        heat_sources.append(ob)

if not sea:
    night_lamps.append(point('Yard light', (1.0,-2.1,.65), 65, warm))
if sea:
    # Small red aviation lights on the actual nacelles, not on the blade tips.
    beacon_col = bpy.data.collections.new('LoadingBeacons')
    scene.collection.children.link(beacon_col)
    bk = plate_ns['Kit'](beacon_col)
    beacon_mat = window_mat.copy()
    node = beacon_mat.node_tree.nodes.get('Principled BSDF')
    node.inputs['Base Color'].default_value = (1,.03,.01,1)
    node.inputs['Emission Color'].default_value = (1,.03,.01,1)
    for ob in objects:
        if not ob.name.startswith('nac'):
            continue
        p = ob.matrix_world @ Vector((0,0,0))
        bounds = [ob.matrix_world @ Vector(c) for c in ob.bound_box]
        p = Vector((sum(v.x for v in bounds)/8, sum(v.y for v in bounds)/8, max(v.z for v in bounds)+.015))
        bk.cyl('Beacon', p.x,p.y,p.z,.026,.04,beacon_mat,segments=10)
    for ob in beacon_col.objects:
        ob.hide_render = True
else:
    beacon_col = None

for lamp in night_lamps:
    lamp.hide_render = True
saved_mats = {o: list(o.data.materials) for o in night_materials}
for look in ('day','night'):
    night = look == 'night'
    sun.data.color = (1.0,.78,.51) if not night else (.49,.61,1.0)
    sun.data.energy = 3.15 if not night else .38
    bg.inputs[0].default_value = (.62,.72,1,1) if not night else (.32,.43,.78,1)
    bg.inputs[1].default_value = .44 if not night else .24
    for lamp in night_lamps:
        lamp.hide_render = not night
    if beacon_col:
        for ob in beacon_col.objects:
            ob.hide_render = not night
    for ob, lit_mat in night_materials.items():
        ob.data.materials.clear()
        for mat in ([lit_mat]*len(saved_mats[ob]) if night else saved_mats[ob]):
            ob.data.materials.append(mat)
    path = args.out / f'{family}-{look}.png'
    scene.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)

if args.save:
    bpy.ops.wm.save_as_mainfile(filepath=str(args.out / f'{family}.blend'))

# The capsule print pass shades by face orientation, rather than by the material's colour.
mat = bpy.data.materials.new('LoadingShade')
mat.use_nodes = True
nt = mat.node_tree
nt.nodes.clear()
geo = nt.nodes.new('ShaderNodeNewGeometry')
dot = nt.nodes.new('ShaderNodeVectorMath')
dot.operation = 'DOT_PRODUCT'
dot.inputs[1].default_value = tuple(sun_dir)
rng = nt.nodes.new('ShaderNodeMapRange')
rng.inputs['From Min'].default_value = -1
rng.inputs['From Max'].default_value = 1
rng.inputs['To Min'].default_value = .04
rng.inputs['To Max'].default_value = 1
emission = nt.nodes.new('ShaderNodeEmission')
output = nt.nodes.new('ShaderNodeOutputMaterial')
nt.links.new(geo.outputs['Normal'], dot.inputs[0])
nt.links.new(dot.outputs['Value'], rng.inputs['Value'])
nt.links.new(rng.outputs['Result'], emission.inputs['Color'])
nt.links.new(emission.outputs[0], output.inputs['Surface'])
scene.view_layers[0].material_override = mat
scene.render.use_freestyle = False
scene.view_settings.view_transform = 'Standard'
if beacon_col:
    for ob in beacon_col.objects:
        ob.hide_render = True
scene.render.filepath = str(args.out / f'{family}-shade.png')
bpy.ops.render.render(write_still=True)
model = ROOT / f'price-of-everything-0.1/assets/supply_chain_3d/{family}_lvl3.glb'
(args.out / f'{family}.json').write_text(json.dumps(dict(building=family, level=3,
    resolution=args.res, source_sha256=sources, model_sha256=hashlib.sha256(model.read_bytes()).hexdigest(),
    footprint_radius=reach*scale, hex_inradius=R*math.sqrt(3)/2,
    ground_z=.012, windows=len(windows), skylights=len(skylights),
    turbine_roof_panes=len(hall_glazing), interior_lamps=len(interior_lamps),
    heat_sources=len(heat_sources)), indent=2)+'\n')
