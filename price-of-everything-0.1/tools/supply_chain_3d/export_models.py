"""Export the existing sprite builders as one vertex-coloured mesh per building level.
Run from any directory: blender --background --factory-startup --python <this file>.
Only writes assets/supply_chain_3d; never changes sprite builders or regular-map assets.
The largest footprint of a family's levels sets a shared scale, preserving upgrade sizes.
"""
import bpy, json, pathlib, sys, math
from mathutils import Vector
ROOT = pathlib.Path(__file__).resolve().parents[3]
KIT = ROOT / '.claude/skills/blender-building-sprites'
OUT = ROOT / 'price-of-everything-0.1/assets/supply_chain_3d'
OUT.mkdir(parents=True, exist_ok=True)
ns_map = {'__name__': 'builder_catalog', '__file__': str(KIT/'bake_sprite.py')}
exec(compile((KIT/'bake_sprite.py').read_text(), str(KIT/'bake_sprite.py'), 'exec'), ns_map)
specs = ns_map['BUILDINGS']
manifest_path = OUT / 'manifest.json'
manifest = json.loads(manifest_path.read_text()) if manifest_path.exists() else {}
# Some builders resolve helper kits relative to Blender's --python argument.
sys.argv[sys.argv.index('--python')+1] = str(KIT/'render_sprite.py')
requested = sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else []
for name, spec in specs.items():
    if requested and name not in requested: continue
    if name == 'mine': continue # use the surface pit version on the board
    family = []
    for level in spec['levels'] or (0,):
        bpy.ops.wm.read_factory_settings(use_empty=False)
        for ob in list(bpy.data.objects):
            if ob.name not in ('Camera', 'Light'): bpy.data.objects.remove(ob, do_unlink=True)
        ns = {'__file__':str(KIT/spec['file'])}
        exec(compile((KIT/'sprite_kit.py').read_text(), str(KIT/'sprite_kit.py'), 'exec'), ns)
        exec(compile((KIT/spec['file']).read_text(), str(KIT/spec['file']), 'exec'), ns)
        ns[spec['fn']](level) if level else ns[spec['fn']]()
        col = bpy.data.collections[spec['col']]
        deps = bpy.context.evaluated_depsgraph_get()
        verts, faces, colours = [], [], []
        for ob in col.all_objects:
            if ob.type != 'MESH': continue
            evaluated = ob.evaluated_get(deps)
            me = evaluated.to_mesh(); me.calc_loop_triangles()
            offset = len(verts)
            verts.extend(tuple(ob.matrix_world @ v.co) for v in me.vertices)
            for tri in me.loop_triangles:
                faces.append(tuple(offset+i for i in tri.vertices))
                mat = me.materials[tri.material_index] if tri.material_index < len(me.materials) else None
                colour = (0.35,0.35,0.32,1)
                if mat:
                    colour = tuple(mat.diffuse_color)
                    if mat.use_nodes:
                        bsdf = next((n for n in mat.node_tree.nodes if n.type=='BSDF_PRINCIPLED'),None)
                        if bsdf: colour = tuple(bsdf.inputs['Base Color'].default_value)
                colours.append(colour)
            evaluated.to_mesh_clear()
        if not verts: raise RuntimeError('Empty asset: '+name)
        lo = [min(v[i] for v in verts) for i in range(3)]
        hi = [max(v[i] for v in verts) for i in range(3)]
        family.append((level or 1, verts, faces, colours, lo, hi))
    span = max(max(f[5][0]-f[4][0],f[5][1]-f[4][1]) for f in family)
    for level, verts, faces, colours, lo, hi in family:
        bpy.ops.wm.read_factory_settings(use_empty=True)
        center = ((lo[0]+hi[0])/2, (lo[1]+hi[1])/2)
        vertices = [((v[0]-center[0])/span,(v[1]-center[1])/span,(v[2]-lo[2])/span) for v in verts]
        me = bpy.data.meshes.new(name); me.from_pydata(vertices,[],faces); me.update()
        attr = me.color_attributes.new(name='Color',type='FLOAT_COLOR',domain='CORNER')
        for poly, colour in zip(me.polygons,colours):
            for i in poly.loop_indices: attr.data[i].color = colour
        mat = bpy.data.materials.new('Paint'); mat.use_nodes=True
        bsdf = mat.node_tree.nodes.get('Principled BSDF')
        bsdf.inputs['Roughness'].default_value=0.88
        vc = mat.node_tree.nodes.new('ShaderNodeVertexColor'); vc.layer_name='Color'
        mat.node_tree.links.new(vc.outputs['Color'],bsdf.inputs['Base Color'])
        me.materials.append(mat)
        ob = bpy.data.objects.new(name,me); bpy.context.collection.objects.link(ob)
        ob.select_set(True); bpy.context.view_layer.objects.active=ob
        key = f'{name}_lvl{level}'
        bpy.ops.export_scene.gltf(filepath=str(OUT/(key+'.glb')),export_format='GLB',use_selection=True,export_yup=True,export_materials='EXPORT',export_normals=True,export_cameras=False,export_lights=False)
        manifest[key] = {'height':(hi[2]-lo[2])/span,'width':(hi[0]-lo[0])/span,'depth':(hi[1]-lo[1])/span,'triangles':len(faces)}
        print('EXPORTED',key,len(faces),'triangles',flush=True)
(OUT/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
print('EXPORTED_TOTAL',len(manifest),flush=True)
