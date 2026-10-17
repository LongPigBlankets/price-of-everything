shader_type spatial;
// See-through faces of the same buildings (the export's 'Glass' slot), painted like the rest.
render_mode unshaded, cull_disabled, fog_disabled, blend_mix, depth_draw_never;
#include "res://scripts/supply_chain_3d/lod_transition.gdshaderinc"
#define GLASS
#include "res://scripts/supply_chain_3d/building_paint.gdshaderinc"
