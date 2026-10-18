"""Catalogue brick coursing in Blender, in the source model's metre coordinates.

Matches building_paint.gdshaderinc: 0.075m courses, 0.21m stretcher bond, 0.005m joints.
The source models encode the material role by name; their Blender flat colour alone
does not include the game's procedural surface paint.
"""
def apply_brick_patterns(objects, scale, centre, ground):
    used = {m for ob in objects for m in ob.data.materials if m and 'brick' in m.name.lower()}
    for material in used:
        if not material.use_nodes:
            continue
        nt = material.node_tree
        bsdf = next((n for n in nt.nodes if n.type == 'BSDF_PRINCIPLED'), None)
        if not bsdf:
            continue
        colour = tuple(bsdf.inputs['Base Color'].default_value)
        geo = nt.nodes.new('ShaderNodeNewGeometry')
        unscale = nt.nodes.new('ShaderNodeVectorMath'); unscale.operation = 'SCALE'
        unscale.inputs[3].default_value = 1/scale
        offset = nt.nodes.new('ShaderNodeVectorMath'); offset.operation = 'ADD'
        offset.inputs[1].default_value = (centre.x, centre.y, ground-.012/scale)
        nt.links.new(geo.outputs['Position'], unscale.inputs[0])
        nt.links.new(unscale.outputs[0], offset.inputs[0])
        xyz = nt.nodes.new('ShaderNodeSeparateXYZ')
        nt.links.new(offset.outputs[0], xyz.inputs[0])
        normal = nt.nodes.new('ShaderNodeSeparateXYZ')
        nt.links.new(geo.outputs['Normal'], normal.inputs[0])
        axes = []
        for axis in ('X','Y','Z'):
            a = nt.nodes.new('ShaderNodeMath'); a.operation = 'ABSOLUTE'
            nt.links.new(normal.outputs[axis], a.inputs[0]); axes.append(a)
        side = nt.nodes.new('ShaderNodeMath'); side.operation = 'GREATER_THAN'
        nt.links.new(axes[0].outputs[0], side.inputs[0]); nt.links.new(axes[1].outputs[0], side.inputs[1])
        along = nt.nodes.new('ShaderNodeMixRGB')
        nt.links.new(side.outputs[0], along.inputs[0])
        nt.links.new(xyz.outputs['X'], along.inputs[1]); nt.links.new(xyz.outputs['Y'], along.inputs[2])
        uv = nt.nodes.new('ShaderNodeCombineXYZ')
        nt.links.new(along.outputs[0], uv.inputs['X']); nt.links.new(xyz.outputs['Z'], uv.inputs['Y'])
        brick = nt.nodes.new('ShaderNodeTexBrick')
        brick.offset = .5; brick.offset_frequency = 2
        brick.inputs['Scale'].default_value = 1
        brick.inputs['Brick Width'].default_value = .21
        brick.inputs['Row Height'].default_value = .075
        brick.inputs['Mortar Size'].default_value = .005
        brick.inputs['Mortar Smooth'].default_value = .002
        brick.inputs['Color1'].default_value = colour
        brick.inputs['Color2'].default_value = tuple(c*.94 for c in colour[:3])+(1,)
        # Restrained pale lime joints, under the same lighting/AgX response as the brick.
        brick.inputs['Mortar'].default_value = (.47,.40,.31,1)
        nt.links.new(uv.outputs[0], brick.inputs['Vector'])
        wall = nt.nodes.new('ShaderNodeMath'); wall.operation = 'LESS_THAN'
        nt.links.new(axes[2].outputs[0], wall.inputs[0]); wall.inputs[1].default_value = .4
        paint = nt.nodes.new('ShaderNodeMixRGB'); paint.inputs[1].default_value = colour
        nt.links.new(wall.outputs[0], paint.inputs[0]); nt.links.new(brick.outputs['Color'], paint.inputs[2])
        nt.links.new(paint.outputs[0], bsdf.inputs['Base Color'])
    print('CATALOGUE: brick coursing on',len(used),'materials')
