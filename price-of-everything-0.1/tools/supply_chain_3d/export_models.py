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
specs = dict(ns_map['BUILDINGS'])
specs['tree'] = dict(file='tree_builder.py', fn='build_tree', col='BLDG_tree', levels=(1, 2, 3))
manifest_path = OUT / 'manifest.json'
manifest = json.loads(manifest_path.read_text()) if manifest_path.exists() else {}
# Some builders resolve helper kits relative to Blender's --python argument.
sys.argv[sys.argv.index('--python')+1] = str(KIT/'render_sprite.py')
requested = sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else []
contours_only = '--contours-only' in requested
requested = [arg for arg in requested if arg != '--contours-only']
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
        verts, faces, colours, normals, edge_masks, ink_widths = [], [], [], [], [], []
        # Keep the source framing even when a mine's cut-pass earth is omitted.
        frame_points = []
        contour_verts, contour_faces, contour_normals, contour_widths = [], [], [], []
        fine = bpy.data.collections.get('FINE_INK')
        for ob in col.all_objects:
            if ob.type != 'MESH': continue
            evaluated = ob.evaluated_get(deps)
            me = evaluated.to_mesh(); me.calc_loop_triangles()
            frame_points.extend(tuple(ob.matrix_world @ v.co) for v in me.vertices)
            if ob.get('cut'):
                evaluated.to_mesh_clear()
                continue
            offset = len(verts)
            verts.extend(tuple(ob.matrix_world @ v.co) for v in me.vertices)
            # Keep modelled creases and material boundaries, never triangulation diagonals.
            adjacent = {}
            for poly in me.polygons:
                for edge in poly.edge_keys:
                    adjacent.setdefault(tuple(sorted(edge)), []).append(poly)
            ink = set()
            marks = me.attributes.get('freestyle_face')
            for edge, polys in adjacent.items():
                # Housing's painted windows, doors, spandrels and silver rules are
                # deliberately excluded by the original Freestyle face-mark rule.
                if marks and any(marks.data[p.index].value for p in polys):
                    continue
                if len(polys) != 2 or polys[0].material_index != polys[1].material_index or polys[0].normal.dot(polys[1].normal) < 0.70:
                    ink.add(edge)
            lineset = 'ink_fine' if fine and ob.name in fine.objects else 'ink'
            source_width = bpy.context.scene.view_layers[0].freestyle_settings.linesets[lineset].linestyle.thickness
            model_width = source_width * bpy.context.scene.camera.data.ortho_scale / bpy.context.scene.render.resolution_x
            # A separate closed shell carries only the outer silhouette. Welded,
            # angle-weighted normals avoid cracks at the colour mesh's split corners.
            # Painted facade quads must not acquire their own heavy border; fine
            # lattice/equipment retain the kit's thinner ink hierarchy.
            scale = ob.matrix_world.to_scale()
            thickness = min((max(v.co[i] for v in me.vertices) - min(v.co[i] for v in me.vertices)) * abs(scale[i]) for i in range(3))
            if thickness > 0.000001 and (not marks or not all(marks.data[p.index].value for p in me.polygons)):
                sums = {}
                for poly in me.polygons:
                    for i, vi in enumerate(poly.vertices):
                        v = me.vertices[vi].co
                        left = me.vertices[poly.vertices[i - 1]].co - v
                        right = me.vertices[poly.vertices[(i + 1) % len(poly.vertices)]].co - v
                        angle = left.angle(right, 0.0)
                        token = tuple(round(c, 5) for c in v)
                        sums[token] = sums.get(token, Vector()) + poly.normal * angle
                start = len(contour_verts)
                normal_matrix = ob.matrix_world.to_3x3().inverted().transposed()
                radius = 4.0 * bpy.context.scene.camera.data.ortho_scale / bpy.context.scene.render.resolution_x
                if lineset == 'ink_fine': radius *= 1.05 / 2.4
                # Thin facade parts sit almost flush with their neighbours. A
                # full shell can push their back faces through the visible paint,
                # producing navy stripes across glass, mullions and door ribs.
                # Limit extrusion to a quarter of each part's smallest thickness.
                radius = min(radius, thickness * 0.25)
                for v in me.vertices:
                    contour_verts.append(tuple(ob.matrix_world @ v.co))
                    token = tuple(round(c, 5) for c in v.co)
                    contour_normals.append(tuple((normal_matrix @ sums[token]).normalized()))
                    contour_widths.append(radius)
                contour_faces.extend(tuple(start + vi for vi in tri.vertices) for tri in me.loop_triangles)
            normal_matrix = ob.matrix_world.to_3x3().inverted().transposed()
            for tri in me.loop_triangles:
                indices = list(tri.vertices)
                edge_masks.append(sum(1 << j for j in range(3)
                    if tuple(sorted((indices[(j+1)%3], indices[(j+2)%3]))) in ink))
                ink_widths.append(model_width)
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
        lo = [min(v[i] for v in frame_points) for i in range(3)]
        hi = [max(v[i] for v in frame_points) for i in range(3)]
        pit = None
        if name == 'mine_flush':
            p = ns['MINE_LEVELS'][level]
            rim = ns['Kit'].poly_bean(*ns['PC'], p['rx'], p['ry'], n=ns['SEG'],
                                     lobe=0.10, dent=0.14, phase=math.radians(28))
            pit = {'ground': p['ground'], 'step': p['depth'] / (p['benches'] + 1), 'rim': rim}
        family.append((level or 1, verts, faces, colours, lo, hi, normals, edge_masks, ink_widths, pit, (contour_verts, contour_faces, contour_normals, contour_widths)))
    span = max(max(f[5][0]-f[4][0],f[5][1]-f[4][1]) for f in family)
    for level, verts, faces, colours, lo, hi, normals, edge_masks, ink_widths, pit, contour in family:
        bpy.ops.wm.read_factory_settings(use_empty=True)
        center = ((lo[0]+hi[0])/2, (lo[1]+hi[1])/2)
        vertices = [((v[0]-center[0])/span,(v[1]-center[1])/span,(v[2]-lo[2])/span) for v in verts]
        me = bpy.data.meshes.new(name); me.from_pydata(vertices,[],faces); me.update()
        for poly in me.polygons: poly.use_smooth = True
        me.normals_split_custom_set(normals)
        bary = me.uv_layers.new(name='Barycentric')
        edges = me.uv_layers.new(name='InkEdges')
        for poly, mask, width in zip(me.polygons, edge_masks, ink_widths):
            for corner, loop in enumerate(poly.loop_indices):
                bary.data[loop].uv = ((1, 0), (0, 1), (0, 0))[corner]
                edges.data[loop].uv = (mask, width / span)
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
        if not contours_only:
            bpy.ops.export_scene.gltf(filepath=str(OUT/(key+'.glb')),export_format='GLB',use_selection=True,export_yup=True,export_materials='EXPORT',export_normals=True,export_cameras=False,export_lights=False)
            manifest[key] = {'height':(hi[2]-lo[2])/span,'width':(hi[0]-lo[0])/span,'depth':(hi[1]-lo[1])/span,'triangles':len(faces),'ink_edges':True}
            manifest[key]['source_ink_widths'] = True
        manifest.setdefault(key, {})
        # The old tree sprites are sized by their projected height, not footprint.
        projected = [(v[0] - v[1]) * 0.40824829 - (v[2] - lo[2]) * 0.81649658 for v in verts]
        manifest[key]['projected_height'] = (max(projected) - min(projected)) / span
        ob.select_set(False)
        cv, cf, cn, cw = contour
        cm = bpy.data.meshes.new(name + '_contour')
        cm.from_pydata([((v[0]-center[0])/span,(v[1]-center[1])/span,(v[2]-lo[2])/span) for v in cv], [], cf)
        cm.update()
        for poly in cm.polygons: poly.use_smooth = True
        cm.normals_split_custom_set_from_vertices(cn)
        widths = cm.uv_layers.new(name='ContourWidth')
        for loop in cm.loops: widths.data[loop.index].uv = (cw[loop.vertex_index] / span, 0.0)
        cm.materials.append(mat)
        co = bpy.data.objects.new(name + '_contour', cm)
        bpy.context.collection.objects.link(co)
        co.select_set(True)
        bpy.context.view_layer.objects.active = co
        bpy.ops.export_scene.gltf(filepath=str(OUT/(key+'_contour.glb')), export_format='GLB', use_selection=True,
                                 export_yup=True, export_materials='EXPORT', export_normals=True, export_cameras=False, export_lights=False)
        manifest[key]['contour'] = True
        if pit:
            manifest[key]['pit'] = {'sink': (pit['ground'] - lo[2]) / span, 'step': pit['step'] / span,
                'rim': [[(p[0]-center[0])/span, -(p[1]-center[1])/span] for p in pit['rim']]}
        print('EXPORTED',key,len(faces),'triangles',flush=True)
(OUT/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
print('EXPORTED_TOTAL',len(manifest),flush=True)
