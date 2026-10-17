shader_type spatial;
// Painted housing windows are single quads on all four walls. The sprite rig
// renders both sides; back-face culling erased the rear windows while orbiting.
render_mode unshaded, cull_disabled, fog_disabled;
#include "res://scripts/supply_chain_3d/lod_transition.gdshaderinc"
#include "res://scripts/supply_chain_3d/building_paint.gdshaderinc"
