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
        verts, faces, colours, normals, edge_masks = [], [], [], [], []
        for ob in col.all_objects:
            if ob.type != 'MESH': continue
            evaluated = ob.evaluated_get(deps)
            me = evaluated.to_mesh(); me.calc_loop_triangles()
            offset = len(verts)
            verts.extend(tuple(ob.matrix_world @ v.co) for v in me.vertices)
            # Keep modelled creases and material boundaries, never triangulation diagonals.
            adjacent = {}
            for poly in me.polygons:
                for edge in poly.edge_keys:
                    adjacent.setdefault(tuple(sorted(edge)), []).append(poly)
            ink = set()
            for edge, polys in adjacent.items():
                if len(polys) != 2 or polys[0].material_index != polys[1].material_index or polys[0].normal.dot(polys[1].normal) < 0.70:
                    ink.add(edge)
            normal_matrix = ob.matrix_world.to_3x3().inverted().transposed()
            for tri in me.loop_triangles:
                indices = list(tri.vertices)
                edge_masks.append(sum(1 << j for j in range(3)
                    if tuple(sorted((indices[(j+1)%3], indices[(j+2)%3]))) in ink))
                normals.extend(tuple((normal_matrix @ me.corner_normals[j].vector).normalized()) for j in tri.loops)
                faces.append(tuple(offset+i for i in tri.vertices))
                mat = me.materials[tri.material_index] if tri.material_index < len(me.materials) else None
                colour = (0.35,0.35,0.32,1)
                if mat:
                    colour = tuple(mat.diffuse_color)
                    if mat.use_nodes:
                        bsdf = next((n for n in mat.node_tree.nodes if n.type=='BSDF_PRINCIPLED'),None)
                        if bsdf:
                            colour = tuple(bsdf.inputs['Base Color'].default_value)
                            if bsdf.inputs['Emission Strength'].default_value > 0:
                                # The kit's furnace embers and navy seam beads are emissive.
                                colour = tuple(bsdf.inputs['Emission Color'].default_value)
                colours.append(colour)
            evaluated.to_mesh_clear()
        if not verts: raise RuntimeError('Empty asset: '+name)
        lo = [min(v[i] for v in verts) for i in range(3)]
        hi = [max(v[i] for v in verts) for i in range(3)]
        family.append((level or 1, verts, faces, colours, lo, hi, normals, edge_masks))
    span = max(max(f[5][0]-f[4][0],f[5][1]-f[4][1]) for f in family)
    for level, verts, faces, colours, lo, hi, normals, edge_masks in family:
        bpy.ops.wm.read_factory_settings(use_empty=True)
        center = ((lo[0]+hi[0])/2, (lo[1]+hi[1])/2)
        vertices = [((v[0]-center[0])/span,(v[1]-center[1])/span,(v[2]-lo[2])/span) for v in verts]
        me = bpy.data.meshes.new(name); me.from_pydata(vertices,[],faces); me.update()
        for poly in me.polygons: poly.use_smooth = True
        me.normals_split_custom_set(normals)
        bary = me.uv_layers.new(name='Barycentric')
        edges = me.uv_layers.new(name='InkEdges')
        for poly, mask in zip(me.polygons, edge_masks):
            for corner, loop in enumerate(poly.loop_indices):
                bary.data[loop].uv = ((1, 0), (0, 1), (0, 0))[corner]
                edges.data[loop].uv = (mask, 0)
        me.uv_layers.active_index = 0
        attr = me.color_attributes.new(name='Color',type='FLOAT_COLOR',domain='CORNER')
        for poly, colour in zip(me.polygons,colours):
            for i in poly.loop_indices: attr.data[i].color = colour
        mat = bpy.data.materials.new('Paint'); mat.use_nodes=True
        bsdf = mat.node_tree.nodes.get('Principled BSDF')
        bsdf.inputs['Roughness'].default_value=1.0
        bsdf.inputs['Specular IOR Level'].default_value=0.0
        vc = mat.node_tree.nodes.new('ShaderNodeVertexColor'); vc.layer_name='Color'
        mat.node_tree.links.new(vc.outputs['Color'],bsdf.inputs['Base Color'])
        me.materials.append(mat)
        ob = bpy.data.objects.new(name,me); bpy.context.collection.objects.link(ob)
        ob.select_set(True); bpy.context.view_layer.objects.active=ob
        key = f'{name}_lvl{level}'
        bpy.ops.export_scene.gltf(filepath=str(OUT/(key+'.glb')),export_format='GLB',use_selection=True,export_yup=True,export_materials='EXPORT',export_normals=True,export_cameras=False,export_lights=False)
        manifest[key] = {'height':(hi[2]-lo[2])/span,'width':(hi[0]-lo[0])/span,'depth':(hi[1]-lo[1])/span,'triangles':len(faces),'ink_edges':True}
        print('EXPORTED',key,len(faces),'triangles',flush=True)
(OUT/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
print('EXPORTED_TOTAL',len(manifest),flush=True)
