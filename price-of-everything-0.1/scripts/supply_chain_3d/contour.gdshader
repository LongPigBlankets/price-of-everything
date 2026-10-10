shader_type spatial;
// The outer line is separate from the fine crease/window treatment. Its radius
// comes from the source sprite's four-pixel dilation, in the model's own units.
render_mode unshaded, cull_front, fog_disabled;
uniform vec2 grade_range = vec2(-100000.0, 100000.0);
varying vec3 world_point;
void vertex() {
	world_point = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX += NORMAL * UV.x;
}
vec3 to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}
void fragment() {
	float y = (world_point.x + world_point.z) * 0.40824829 - world_point.y * 0.81649658;
	float t = clamp((y - grade_range.x) / max(1.0, grade_range.y - grade_range.x), 0.0, 1.0);
	vec3 ink = vec3(47.0, 59.0, 89.0) / 255.0;
	ink *= mix(vec3(0.90, 0.92, 0.96), vec3(1.0, 1.0, 0.98), t);
	ink *= mix(vec3(0.66, 0.74, 1.0), vec3(1.0, 0.92, 0.72), t);
	ALBEDO = OUTPUT_IS_SRGB ? ink : to_linear(ink);
}
