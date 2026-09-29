"""Lithium-ion battery (g_059): the sodium-ion pack's crate with red cells and "Li-ion" on the cover.

Reference: assets/icons/goods/medium/g_059_lithium_battery.png (shipped AI art): the same slotted
steel crate, cell grid, raised plates and charcoal cover as the sodium-ion battery (g_060), with
coral-red cells and plates (about (208,95,95) on the lit tops) and a dark-red washer under each
cell's left (+) terminal; the right (-) terminal's washer is plain.
The builder is sodium_kit.build_ion_pack, unchanged (the approved sodium-ion icon renders from the
same file byte for byte); this file only picks the colours and the lettering, and adds the + washers.
"""

LI_REVISION = 'lithium_v1'
LI_CELL = (0.70, 0.107, 0.098)               # linear: lit top (218,92,88), -Y side (206,86,82), +X side (160,65,62) + dots
LI_PLUS = (0.402, 0.045, 0.048)              # linear: the + washer's lit top (170,60,62), a shade under the cells


def build_lithium_battery():
    """Lithium-ion battery v1: the approved sodium-ion pack with red cells and "Li-ion"."""
    info = build_ion_pack('lithium_battery', LI_CELL, 'Li-ion', LI_REVISION)
    K = Kit(bpy.data.collections['ICON_lithium_battery'])
    plus_m = pw_toon('lithium_battery_plus_washer', LI_PLUS, ((0.70, 0.40), (0.95, 0.70), (9.0, 1.0)))
    # Each cell's left terminal is its + (as shipped): a red washer a hair wider and taller than the
    # grey one, so it covers it; same part label as the terminal, so no line between washer and post.
    for term in [o for o in K.col.objects if o.name.endswith('_terminal_a')]:
        vs = [term.matrix_world @ v.co for v in term.data.vertices]
        c = (sum(v.x for v in vs) / len(vs), sum(v.y for v in vs) / len(vs))
        ring = pw_lathe_z(K, term.name.replace('_terminal_a', '_plus_washer'),
                          [(0, CELL_TOP - 0.003), (R_WASH + 0.0015, CELL_TOP - 0.003), (R_WASH + 0.0015, CELL_TOP + H_WASH + 0.0005),
                           (0, CELL_TOP + H_WASH + 0.0005)], plus_m, c)
        ring['part_label'] = term['part_label']
        info['structural_hosts'].append(ring.name)
    info['dimensions']['plus_washer'] = {'colour_linear': LI_PLUS, 'radius': R_WASH + 0.0015}
    return info
