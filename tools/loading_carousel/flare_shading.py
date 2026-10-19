"""Loading-only relief of the catalogue's painted shade bands under the flare."""
def flare_factor(nodes, links, position, reach):
    geo = nodes.new('ShaderNodeNewGeometry')
    delta = nodes.new('ShaderNodeVectorMath'); delta.operation = 'SUBTRACT'
    delta.inputs[0].default_value = position
    links.new(geo.outputs['Position'], delta.inputs[1])
    direction = nodes.new('ShaderNodeVectorMath'); direction.operation = 'NORMALIZE'
    links.new(delta.outputs[0], direction.inputs[0])
    facing = nodes.new('ShaderNodeVectorMath'); facing.operation = 'DOT_PRODUCT'
    links.new(geo.outputs['Normal'], facing.inputs[0]); links.new(direction.outputs[0], facing.inputs[1])
    positive = nodes.new('ShaderNodeMath'); positive.operation = 'MAXIMUM'
    positive.inputs[1].default_value = 0; links.new(facing.outputs['Value'], positive.inputs[0])
    distance = nodes.new('ShaderNodeVectorMath'); distance.operation = 'LENGTH'
    links.new(delta.outputs[0], distance.inputs[0])
    falloff = nodes.new('ShaderNodeMath'); falloff.operation = 'MULTIPLY_ADD'
    falloff.inputs[1].default_value = 1/reach; falloff.inputs[2].default_value = 1
    links.new(distance.outputs['Value'], falloff.inputs[0])
    result = nodes.new('ShaderNodeMath'); result.operation = 'DIVIDE'
    links.new(positive.outputs[0], result.inputs[0]); links.new(falloff.outputs[0], result.inputs[1])
    strength = nodes.new('ShaderNodeMath'); strength.operation = 'MULTIPLY'; strength.use_clamp = True
    strength.inputs[1].default_value = 2.0; links.new(result.outputs[0], strength.inputs[0])
    return strength.outputs[0]


def relight_columns(objects, lamp, reach):
    overrides = {}
    for ob in objects:
        if not ob.name.startswith('col_') or not ob.data.materials:
            continue
        mats = list(ob.data.materials)
        base = mats[0].node_tree.nodes.get('Principled BSDF').inputs['Base Color'].default_value[:]
        changed = False
        for i, src in enumerate(mats):
            if not src.name.endswith('_shade'):
                continue
            mat = src.copy(); mat.name = src.name+'_flare'
            nodes, links = mat.node_tree.nodes, mat.node_tree.links
            bsdf = nodes.get('Principled BSDF')
            mix = nodes.new('ShaderNodeMixRGB')
            mix.inputs[1].default_value = bsdf.inputs['Base Color'].default_value[:]
            mix.inputs[2].default_value = base
            links.new(flare_factor(nodes, links, lamp.location, reach), mix.inputs[0])
            links.new(mix.outputs[0], bsdf.inputs['Base Color'])
            mats[i] = mat; changed = True
        if changed:
            overrides[ob] = mats
    return overrides
