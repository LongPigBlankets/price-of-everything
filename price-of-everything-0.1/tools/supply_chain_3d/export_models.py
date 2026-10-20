"""Export the existing sprite builders as one vertex-coloured mesh per building level.
Run from any directory: blender --background --factory-startup --python <this file>.
Only writes assets/supply_chain_3d; never changes sprite builders or regular-map assets.
The largest footprint of a family's levels sets a shared scale, preserving upgrade sizes.
"""
import bpy, json, pathlib, sys, math, os
from mathutils import Vector
ROOT = pathlib.Path(os.environ.get('POE_PROJECT_ROOT', str(pathlib.Path(__file__).resolve().parents[3])))
KIT = pathlib.Path(os.environ.get('POE_SPRITE_KIT', str(ROOT / '.claude/skills/blender-building-sprites')))
OUT = pathlib.Path(os.environ.get('POE_MODEL_OUTPUT', str(ROOT / 'price-of-everything-0.1/assets/supply_chain_3d')))
OUT.mkdir(parents=True, exist_ok=True)
# Opaque faces carry a printed material pattern in the colour's alpha channel, read by
# building_paint.gdshaderinc: 1 brick coursing, 2 wall panel joints, 3 roof gravel, 4 paving,
# 5 standing-seam metal roof.
# Alpha = 1 - code / 8, so 1.0 (the old export) still means no pattern. See-through faces
# (BLENDED materials with Alpha < 1) go to a second 'Glass' slot and keep their real alpha.
PATTERNS = {'white_wall': 2, 'chalk': 2, 'ht_white': 2, 'deck': 3, 'membrane': 3, 'apron': 4, 'pad': 4, 'cream': 4,
            # Furnace: refractory cladding panels, standing-seam roofs, paved footing tops.
            'f2_refractory': 2, 'f_roof': 5, 'f_base': 4,
            'roof_metal': 5}
def material_alpha(mat):
    """The face's opacity: below 1 only for BLENDED materials, which export as 'Glass'."""
    if not mat or not mat.use_nodes or getattr(mat, 'surface_render_method', '') != 'BLENDED': return 1.0
    bsdf = next((n for n in mat.node_tree.nodes if n.type=='BSDF_PRINCIPLED'),None)
    return min(1.0, float(bsdf.inputs['Alpha'].default_value)) if bsdf else 1.0
def pattern_code(material_name):
    base = material_name.split('.')[0]
    if 'brick' in base: return 1
    return PATTERNS.get(base, 0)
ns_map = {'__name__': 'builder_catalog', '__file__': str(KIT/'bake_sprite.py')}
exec(compile((KIT/'bake_sprite.py').read_text(), str(KIT/'bake_sprite.py'), 'exec'), ns_map)
specs = dict(ns_map['BUILDINGS'])
specs['tree'] = dict(file='tree_builder.py', fn='build_tree', col='BLDG_tree', levels=(1, 2, 3))
specs['pylon'] = dict(file=str(pathlib.Path(__file__).with_name('pylon_builder.py')),
                      fn='build_pylon', col='BLDG_pylon', levels=())
for family in ('civic_office', 'civic_l', 'civic_park', 'civic_plaza'):
    specs[family] = dict(file=str(pathlib.Path(__file__).with_name('civic_builder.py')),
                        fn='build_'+family, col='BLDG_'+family,
                        levels=(1, 2) if family == 'civic_office' else (1,),
                        detailed=True, outer_contour=family in ('civic_office', 'civic_l'))
# Bounded reusable whole-bay combinations; the runtime selects, never stretches.
for family in ('civic_u_office', 'civic_semi', 'civic_bauhaus', 'civic_commercial', 'civic_pond', 'civic_grove'):
    specs[family] = dict(file=str(pathlib.Path(__file__).with_name('district_builder.py')),
        fn='build_'+family, col='BLDG_'+family, levels=(1,), detailed=True, outer_contour=True)
for columns in range(4, 11):
    specs[f'civic_long_{columns:02d}'] = dict(file=str(pathlib.Path(__file__).with_name('civic_builder.py')),
        fn='build_civic_long', col='BLDG_civic_long', levels=(1,), detailed=True,
        kwargs={'columns': columns})
for columns in range(4, 9):
    for returns in range(2, 5):
        specs[f'civic_corner_{columns:02d}x{returns:02d}'] = dict(file=str(pathlib.Path(__file__).with_name('civic_builder.py')),
            fn='build_civic_corner', col='BLDG_civic_corner', levels=(1,), detailed=True,
            kwargs={'columns': columns, 'return_columns': returns})
# The detailed asset pipeline can export a frozen reviewed builder revision. Existing
# families continue to use their original source and exact export path.
DETAIL_SOURCE = pathlib.Path(os.environ.get('POE_DETAIL_SOURCE', str(ROOT / 'price-of-everything-0.1/tools/building_assets')))
for family in ('farm', 'water_pump', 'new_forest', 'old_forest', 'desal', 'oil_well', 'fracking_oil_well'):
    specs[family] = dict(file=str(DETAIL_SOURCE / 'builders.py'), fn='build_' + family,
                        col='BLDG_' + family, levels=(1, 2, 3), detailed=True, outer_contour=False)
specs['offshore_oil_platform'] = dict(file=str(DETAIL_SOURCE / 'builders.py'), fn='build_offshore_oil_platform',
    col='BLDG_offshore_oil_platform', levels=(1,2,3), detailed=True, outer_contour=False)
# The furnace is the generic shaft-furnace works (furnace_v2_builder.py), executed after
# furnace_builder.py, whose palette and shed helpers it shares. It carries the outer ink
# contour like the catalogue factory. 'furnace_v2' is the same builder under its staging
# name, for reviewed revisions built by tools/building_assets/pipeline.py.
specs['furnace'] = dict(file=str(DETAIL_SOURCE / 'furnace_v2_builder.py'), fn='build_furnace_v2',
    col='BLDG_furnace_v2', levels=(1,2,3), detailed=True, outer_contour=True,
    prelude=(str(DETAIL_SOURCE / 'furnace_builder.py'),))
specs['furnace_v2'] = dict(specs['furnace'])
# The rebuilt refineries (refinery_v2_builder.py), staged under their working names; their
# reviewed revisions install as 'petro_refinery' and 'poly_plant'.
for staged in ('petro_refinery_v2', 'poly_plant_v2'):
    specs[staged] = dict(file=str(DETAIL_SOURCE / 'refinery_v2_builder.py'), fn='build_' + staged,
        col='BLDG_' + staged, levels=(1, 2, 3), detailed=True, outer_contour=True,
        prelude=(str(DETAIL_SOURCE / 'furnace_builder.py'), str(DETAIL_SOURCE / 'furnace_v2_builder.py')))
# The rebuilt power plant (power_plant_v2_builder.py), staged; installs as 'power_plant'.
specs['power_plant_v2'] = dict(file=str(DETAIL_SOURCE / 'power_plant_v2_builder.py'), fn='build_power_plant_v2',
    col='BLDG_power_plant_v2', levels=(1, 2, 3), detailed=True, outer_contour=True,
    prelude=(str(DETAIL_SOURCE / 'furnace_builder.py'), str(DETAIL_SOURCE / 'furnace_v2_builder.py'),
             str(DETAIL_SOURCE / 'refinery_v2_builder.py')))
# The rebuilt electric arc furnace (eaf_v2_builder.py), staged; installs as 'eaf'.
specs['eaf_v2'] = dict(file=str(DETAIL_SOURCE / 'eaf_v2_builder.py'), fn='build_eaf_v2',
    col='BLDG_eaf_v2', levels=(1, 2, 3), detailed=True, outer_contour=True,
    prelude=(str(DETAIL_SOURCE / 'furnace_builder.py'), str(DETAIL_SOURCE / 'furnace_v2_builder.py'),
             str(DETAIL_SOURCE / 'refinery_v2_builder.py'), str(DETAIL_SOURCE / 'power_plant_v2_builder.py')))
# Export independent vessels from the same reviewed port builder. These are
# components, with the port's unit scale and their own grounded local origin.
PORT_SHIPS = {'boxa': ('boxA', 'SHIP_BOXER_A'), 'boxb': ('boxB', 'SHIP_BOXER_B'),
              'tanker': ('tank', 'SHIP_TANKER')}
for vessel, (prefix, source) in PORT_SHIPS.items():
    for medium in (False, True):
        specs['port_ship_' + vessel + ('_medium' if medium else '')] = dict(
            specs['port'], port_ship=prefix, ship_source=source, medium_ship=medium,
            outer_contour=not medium)
# Renderer-only derivatives. Never rewrite the complete farm or its builder.
specs['farm_building'] = dict(specs['farm'], farm_part='building')
specs['farm_crop_cell'] = dict(specs['farm'], farm_part='cell')
specs['farm_crop_cell_medium'] = dict(specs['farm'], farm_part='cell', medium_crop=True)
manifest_path = OUT / 'manifest.json'
manifest = json.loads(manifest_path.read_text()) if manifest_path.exists() else {}
# Some builders resolve helper kits relative to Blender's --python argument.
sys.argv[sys.argv.index('--python')+1] = str(KIT/'render_sprite.py')
requested = sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else []
contours_only = '--contours-only' in requested
requested = [arg for arg in requested if arg != '--contours-only']
if 'civic_modules' in requested: requested += [key for key in specs if key.startswith(('civic_long_', 'civic_corner_'))]
if 'port' in requested: requested += [key for key in specs if key.startswith('port_ship_')]
for name, spec in specs.items():
    if requested and name not in requested: continue
    if name == 'mine': continue # use the surface pit version on the board
    family = []
    component_spans = []
    attachments = {}
    storeys = {}
    modules = {}
    for level in spec['levels'] or (0,):
        bpy.ops.wm.read_factory_settings(use_empty=False)
        for ob in list(bpy.data.objects):
            if ob.name not in ('Camera', 'Light'): bpy.data.objects.remove(ob, do_unlink=True)
        ns = {'__file__':str(KIT/spec['file'])}
        exec(compile((KIT/'sprite_kit.py').read_text(), str(KIT/'sprite_kit.py'), 'exec'), ns)
        if spec.get('detailed'):
            exec(compile((KIT/'props_kit.py').read_text(), str(KIT/'props_kit.py'), 'exec'), ns)
        for prelude in spec.get('prelude', ()):
            # A builder that extends another family's palette and helpers runs after it.
            exec(compile((KIT/prelude).read_text(), str(KIT/prelude), 'exec'), ns)
        exec(compile((KIT/spec['file']).read_text(), str(KIT/spec['file']), 'exec'), ns)
        built = ns[spec['fn']](level, **spec.get('kwargs', {})) if level else ns[spec['fn']]()
        if isinstance(built, dict) and 'storey_height' in built:
            storeys[level or 1] = built['storey_height']
        if isinstance(built, dict) and 'civic_module' in built:
            modules[level or 1] = built['civic_module']
        if isinstance(built, dict) and 'cable_anchors' in built:
            attachments[level or 1] = built['cable_anchors']
        col = bpy.data.collections[spec['col']]
        if spec.get('medium_ship'):
            # Five solid cargo stacks retain the source silhouette and colour
            # pattern without individual container seams. Tankers keep hull,
            # house and deck only.
            prefix = spec['port_ship']
            for column in range(5):
                cargo = [ob for ob in col.objects if ob.name.startswith(f'{prefix}_box') and ob.name.endswith(f'_{column}')]
                if not cargo: continue
                points = [ob.matrix_world @ Vector(corner) for ob in cargo for corner in ob.bound_box]
                low = [min(p[i] for p in points) for i in range(3)]
                high = [max(p[i] for p in points) for i in range(3)]
                bpy.ops.mesh.primitive_cube_add(size=1, location=[(a+b)/2 for a,b in zip(low,high)])
                band = bpy.context.object
                band.name = f'{prefix}_cargo{column}'
                band.scale = [b-a for a,b in zip(low,high)]
                band.data.materials.append(max(cargo, key=lambda ob: ob.location.z).data.materials[0])
                for collection in list(band.users_collection): collection.objects.unlink(band)
                col.objects.link(band)
            bpy.context.view_layer.update()

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
            if spec.get('farm_part'):
                field = ob.name.startswith(('bed', 'crop', 'leaves', 'drip', 'field_header', 'irrigation_box'))
                keep = not field
                if spec['farm_part'] == 'cell':
                    keep = ob.name == 'bed0' or ob.name.startswith(('crop0_', 'drip0'))
                    keep |= ob.name.startswith('leaves0_') and ob.name.endswith('_4')
                    if spec.get('medium_crop') and ob.name.startswith(('leaves', 'drip')): keep = False
                if not keep:
                    evaluated.to_mesh_clear()
                    continue
                if spec['farm_part'] == 'cell':
                    # Cut one repeat interval from the source row, without scaling
                    # its width, plants, height or spacing. Adjacent copies meet.
                    inverse = ob.matrix_world.inverted()
                    for v in me.vertices:
                        point = ob.matrix_world @ v.co
                        point.x = min(max(point.x, -1.96), -1.71)
                        v.co = inverse @ point
                    me.update(); me.calc_loop_triangles()
            ship_object = any(ob.name == prefix or ob.name.startswith(prefix + '_')
                              for prefix, _ in PORT_SHIPS.values())
            if name == 'port' and ship_object:
                evaluated.to_mesh_clear()
                continue
            if spec.get('port_ship'):
                prefix = spec['port_ship']
                keep = ob.name == prefix or ob.name.startswith(prefix + '_')
                if spec.get('medium_ship'):
                    keep = ob.name in (prefix, prefix+'_deck', prefix+'_boot', prefix+'_house', prefix+'_bridge') or ob.name.startswith(prefix+'_cargo')
                if not keep:
                    evaluated.to_mesh_clear()
                    continue
            # The sprite's rectangular ocean/land backdrop belongs to the regular
            # map only. Keep the actual quay, ships and equipment in the 3D world.
            if name == 'port' and ob.name in ('water', 'land', 'land_edge', 'road_w'):
                evaluated.to_mesh_clear()
                continue
            if name == 'port' and (ob.name == 'road_n' or ob.name.startswith('rdash')):
                shore_x = ns['BAY'][0]
                if max((ob.matrix_world @ v.co).x for v in me.vertices) <= shore_x:
                    evaluated.to_mesh_clear()
                    continue
                # Trim the approach road to the quay after removing its land slab.
                inverse = ob.matrix_world.inverted()
                for v in me.vertices:
                    point = ob.matrix_world @ v.co
                    point.x = max(point.x, shore_x)
                    v.co = inverse @ point
                me.update()
                me.calc_loop_triangles()
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
            if spec.get('outer_contour', True) and thickness > 0.000001 and (not marks or not all(marks.data[p.index].value for p in me.polygons)):
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
                # Glass gets no shell: seen through the pane, its inner faces read as a solid sheet.
                contour_faces.extend(tuple(start + vi for vi in tri.vertices) for tri in me.loop_triangles
                    if material_alpha(me.materials[tri.material_index] if tri.material_index < len(me.materials) else None) >= 0.999)
            normal_matrix = ob.matrix_world.to_3x3().inverted().transposed()
            for tri in me.loop_triangles:
                indices = list(tri.vertices)
                if spec.get('farm_part') == 'cell':
                    a, b, c = [ob.matrix_world @ me.vertices[i].co for i in indices]
                    if (b-a).cross(c-a).length_squared < 1e-14: continue
                edge_masks.append(0 if spec.get('farm_part') == 'cell' else sum(1 << j for j in range(3)
                    if tuple(sorted((indices[(j+1)%3], indices[(j+2)%3]))) in ink))
                ink_widths.append(model_width)
                normals.extend(tuple((normal_matrix @ me.corner_normals[j].vector).normalized()) for j in tri.loops)
                faces.append(tuple(offset+i for i in tri.vertices))
                mat = me.materials[tri.material_index] if tri.material_index < len(me.materials) else None
                colour = (0.35,0.35,0.32,1)
                alpha = 1.0
                if mat:
                    colour = tuple(mat.diffuse_color)
                    if mat.use_nodes:
                        bsdf = next((n for n in mat.node_tree.nodes if n.type=='BSDF_PRINCIPLED'),None)
                        if bsdf:
                            colour = tuple(bsdf.inputs['Base Color'].default_value)
                            if bsdf.inputs['Emission Strength'].default_value > 0:
                                # The kit's furnace embers and navy seam beads are emissive.
                                colour = tuple(bsdf.inputs['Emission Color'].default_value)
                    alpha = material_alpha(mat)
                glass = alpha < 0.999
                code = 0 if glass or not mat else pattern_code(mat.name)
                # The fifth value marks a see-through face; only RGBA reaches the mesh.
                colours.append((colour[0], colour[1], colour[2], alpha if glass else 1.0 - code / 8.0, glass))
            evaluated.to_mesh_clear()
        if not verts: raise RuntimeError('Empty asset: '+name)
        lo = [min(v[i] for v in frame_points) for i in range(3)]
        hi = [max(v[i] for v in frame_points) for i in range(3)]
        component_span = max(hi[0]-lo[0], hi[1]-lo[1])
        component_spans.append(component_span)
        if spec.get('port_ship') or spec.get('farm_part'):
            lo = [min(v[i] for v in verts) for i in range(3)]
            hi = [max(v[i] for v in verts) for i in range(3)]
        pit = None
        if name == 'mine_flush':
            p = ns['MINE_LEVELS'][level]
            rim = ns['Kit'].poly_bean(*ns['PC'], p['rx'], p['ry'], n=ns['SEG'],
                                     lobe=0.10, dent=0.14, phase=math.radians(28))
            pit = {'ground': p['ground'], 'step': p['depth'] / (p['benches'] + 1), 'rim': rim}
        family.append((level or 1, verts, faces, colours, lo, hi, normals, edge_masks, ink_widths, pit, (contour_verts, contour_faces, contour_normals, contour_widths)))
    span = max(component_spans) if spec.get('farm_part') else component_span if spec.get('port_ship') else max(max(f[5][0]-f[4][0],f[5][1]-f[4][1]) for f in family)
    for level, verts, faces, colours, lo, hi, normals, edge_masks, ink_widths, pit, contour in family:
        bpy.ops.wm.read_factory_settings(use_empty=True)
        center = ns[spec['ship_source']][:2] if spec.get('port_ship') else ((lo[0]+hi[0])/2, (lo[1]+hi[1])/2)
        vertices = [((v[0]-center[0])/span,(v[1]-center[1])/span,(v[2]-lo[2])/span) for v in verts]
        mat = bpy.data.materials.new('Paint'); mat.use_nodes=True
        bsdf = mat.node_tree.nodes.get('Principled BSDF')
        bsdf.inputs['Roughness'].default_value=1.0
        bsdf.inputs['Specular IOR Level'].default_value=0.0
        # No colour node: with export_vertex_color='ACTIVE' the exporter then writes the full
        # RGBA attribute, keeping alpha (the pattern codes and glass opacity). Godot replaces
        # these materials anyway.
        def part(part_name, material, wanted):
            """One exported object holding the faces whose glass flag equals `wanted`."""
            ids = [i for i, colour in enumerate(colours) if bool(colour[4]) == wanted]
            if not ids: return None
            me = bpy.data.meshes.new(part_name); me.from_pydata(vertices,[],[faces[i] for i in ids]); me.update()
            for poly in me.polygons: poly.use_smooth = True
            me.normals_split_custom_set([normals[3 * i + k] for i in ids for k in range(3)])
            bary = me.uv_layers.new(name='Barycentric')
            edges = me.uv_layers.new(name='InkEdges')
            for poly, i in zip(me.polygons, ids):
                for corner, loop in enumerate(poly.loop_indices):
                    bary.data[loop].uv = ((1, 0), (0, 1), (0, 0))[corner]
                    edges.data[loop].uv = (edge_masks[i], ink_widths[i] / span)
            me.uv_layers.active_index = 0
            attr = me.color_attributes.new(name='Color',type='FLOAT_COLOR',domain='CORNER')
            for poly, i in zip(me.polygons, ids):
                for loop in poly.loop_indices: attr.data[loop].color = colours[i][:4]
            me.materials.append(material)
            ob = bpy.data.objects.new(part_name,me); bpy.context.collection.objects.link(ob)
            ob.select_set(True)
            return ob
        # See-through faces go out as a second object named 'Glass' (and with a 'Glass'
        # material): Blender's glTF exporter writes no vertex colour for a second material on
        # one mesh, so the game merges the two objects back into one mesh, glass last.
        ob = part(name, mat, False)
        glass_mat = mat.copy(); glass_mat.name = 'Glass'
        part(name + '_Glass', glass_mat, True)
        bpy.context.view_layer.objects.active=ob
        key = f'{name}_lvl{level}'
        if not contours_only:
            bpy.ops.export_scene.gltf(filepath=str(OUT/(key+'.glb')),export_format='GLB',use_selection=True,export_yup=True,export_materials='EXPORT',export_vertex_color='ACTIVE',export_normals=True,export_cameras=False,export_lights=False)
            manifest[key] = {'span': span, 'height':(hi[2]-lo[2])/span,'width':(hi[0]-lo[0])/span,'depth':(hi[1]-lo[1])/span,'triangles':len(faces),'ink_edges':True}
            manifest[key]['source_ink_widths'] = True
            if level in storeys: manifest[key]['storey_height'] = storeys[level] / span
            if level in modules:
                manifest[key]['civic_module'] = dict(modules[level], bay_pitch=modules[level]['bay_pitch'] / span)
            if spec.get('farm_part') == 'cell':
                manifest[key]['component'] = {'pitch': [.25/span, .61/span], 'medium': spec.get('medium_crop', False)}
            if spec.get('port_ship'):
                manifest[key]['component'] = {'waterline': (ns['WATER_Z']-lo[2])/span,
                                              'medium': spec['medium_ship']}

            if level in attachments:
                # Blender Z-up -> glTF/Godot Y-up, with the mesh's exact framing.
                manifest[key]['cable_anchors'] = [[(p[0]-center[0])/span, (p[2]-lo[2])/span,
                                                  -(p[1]-center[1])/span] for p in attachments[level]]
        if name == 'port' and not contours_only:
            def harbour_point(x, y, z):
                return [(x-center[0])/span, (z-lo[2])/span, -(y-center[1])/span]
            x0, x1, y0, y1 = ns['BAY']
            raw_bounds = ([min(v[i] for v in verts) for i in range(3)],
                          [max(v[i] for v in verts) for i in range(3)])
            manifest[key]['harbour'] = {
                'ships': [{'near': 'port_ship_'+vessel+'_lvl1', 'medium': 'port_ship_'+vessel+'_medium_lvl1',
                           'berth': harbour_point(*ns[source][:2], ns['WATER_Z']),
                           'length': ns[source][2]/span, 'beam': ns[source][3]/span,
                           'mouth': (x1-ns[source][0])/span}
                          for vessel, (_, source) in PORT_SHIPS.items()],
                'waterline': (ns['WATER_Z']-lo[2])/span,
                'deck': (ns['QUAY_Z']-lo[2])/span,
                'across': (y1-y0)/span,
                'anchor': harbour_point(x0+ns['ARM_W'], (y0+y1)/2, ns['WATER_Z']),
                'ship_water': [harbour_point(cx+dx*length*0.38, cy+dy*beam*0.25, ns['WATER_Z'])
                               for cx, cy, length, beam in (ns['SHIP_BOXER_A'], ns['SHIP_BOXER_B'], ns['SHIP_TANKER'])
                               for dx in (-1, 1) for dy in (-1, 1)],
                'shore_edge': [harbour_point(x0, y, ns['QUAY_Z']) for y in (y0, (y0+y1)/2, y1)],
                'road_entry': harbour_point(x0, y1-ns['ROAD_W']/2, ns['QUAY_Z']+.027),
                'road_width': ns['ROAD_W']/span,
                'pier_tip': harbour_point(x1-0.5, y0+ns['ARM_W']/2, ns['QUAY_Z']),
                'basin': harbour_point(x1-1.0, (y0+y1)/2, ns['WATER_Z']),
                'bounds_min': harbour_point(raw_bounds[0][0], raw_bounds[1][1], raw_bounds[0][2]),
                'bounds_max': harbour_point(raw_bounds[1][0], raw_bounds[0][1], raw_bounds[1][2]),
                'backdrop_removed': True,
            }
        manifest.setdefault(key, {})
        # The old tree sprites are sized by their projected height, not footprint.
        projected = [(v[0] - v[1]) * 0.40824829 - (v[2] - lo[2]) * 0.81649658 for v in verts]
        manifest[key]['projected_height'] = (max(projected) - min(projected)) / span
        if not spec.get('outer_contour', True):
            # Keep all painted geometry and fine ink; the runtime already supports
            # assets without a separate expanded silhouette shell.
            manifest[key]['contour'] = False
            print('EXPORTED',key,len(faces),'triangles; no outer contour',flush=True)
            continue
        for selected in list(bpy.context.selected_objects): selected.select_set(False)
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
