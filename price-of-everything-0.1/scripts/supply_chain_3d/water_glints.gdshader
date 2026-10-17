shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, fog_disabled;
#include "res://scripts/supply_chain_3d/lod_transition.gdshaderinc"
varying vec2 loading_world;
uniform vec3 glint : source_color = vec3(1.0, 0.96, 0.82);
void vertex() { loading_world = (MODEL_MATRIX * vec4(VERTEX,1.0)).xz; }
void fragment() {
	float beat = pow(max(0.0, sin(TIME * 1.6 * UV.y + UV.x)), 6.0);
	ALBEDO = glint;
	ALPHA = beat;
	if ((lod_hidden(FRAGCOORD.xy) || loading_hidden(loading_world, FRAGCOORD.xy))) { discard; }
}
