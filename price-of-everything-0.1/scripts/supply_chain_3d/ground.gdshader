shader_type spatial;
render_mode unshaded, cull_disabled;
uniform sampler2D artwork : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform bool textured = false;
uniform bool strata = false;
uniform float road_fade = 0.0;
uniform vec2 grade_range = vec2(0.0, 1.0);
varying vec3 world_point;
varying vec3 world_normal;
vec3 to_linear(vec3 c) { return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c)); }
vec3 to_srgb(vec3 c) { return mix(c * 12.92, 1.055 * pow(max(c, vec3(0.0)), vec3(1.0 / 2.4)) - 0.055, step(vec3(0.0031308), c)); }
void vertex() {
	world_point = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}
void fragment() {
	vec3 paint = textured ? texture(artwork, UV).rgb : COLOR.rgb;
	if (textured && !OUTPUT_IS_SRGB) paint = to_srgb(paint);
	paint = mix(paint, vec3(0.50, 0.52, 0.35), road_fade);
	vec3 n = normalize(world_normal);
	float slope = length(n.xz) / max(0.08, n.y);
	float facing = dot(normalize(n.xz + vec2(0.00001)), vec2(0.70710678));
	float shading = 1.0 - clamp(slope / 0.13235, 0.0, 1.0) * (0.20 - 0.16 * max(0.0, facing));
	if (strata) shading = 0.75 + 0.25 * max(0.0, dot(n, normalize(vec3(0.7, 0.3, 0.7))));
	float projected_y = (world_point.x + world_point.z) * 0.40824829 - world_point.y * 0.81649658;
	float t = clamp((projected_y - grade_range.x) / max(1.0, grade_range.y - grade_range.x), 0.0, 1.0);
	vec3 wash = t > 0.5 ? mix(vec3(1.0), vec3(1.0, 0.80, 0.44), (t - 0.5) * 0.52)
		: mix(vec3(1.0), vec3(0.05, 0.08, 0.22), (0.5 - t) * 0.20);
	vec3 grade = mix(vec3(0.66, 0.74, 1.0), vec3(1.0, 0.92, 0.72), t);
	paint *= wash * grade * shading * 0.90;
	ALBEDO = OUTPUT_IS_SRGB ? paint : to_linear(paint);
}
