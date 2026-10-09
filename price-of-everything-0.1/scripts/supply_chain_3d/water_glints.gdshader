shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, fog_disabled;
uniform vec3 glint : source_color = vec3(1.0, 0.96, 0.82);
void fragment() {
	float beat = pow(max(0.0, sin(TIME * 1.6 * UV.y + UV.x)), 6.0);
	ALBEDO = glint;
	ALPHA = beat;
}
