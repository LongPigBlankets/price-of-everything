shader_type spatial;
render_mode unshaded, cull_disabled;
#include "res://scripts/supply_chain_3d/detail_mask.gdshaderinc"
uniform sampler2D artwork : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform bool textured = false;
uniform bool strata = false;
uniform float road_fade = 0.0;
uniform vec4 artwork_rect = vec4(0.0, 0.0, 1.0, 1.0);
uniform vec2 grade_range = vec2(0.0, 1.0);
// Grass is pushed toward a brighter, more saturated green and broken into large
// patches. The hue stays the source palette's; only saturation and value move.
uniform float grass_saturation = 1.30;
uniform float grass_value = 1.17;
uniform float grass_patches = 0.22;
uniform float grass_hue = 0.014;
// Plan-space soot around polluting works, painted by the board (white = sooty).
global uniform sampler2D sc3d_soot_map : filter_linear;
global uniform vec4 sc3d_soot_rect;
global uniform float sc3d_soot_on;
varying vec3 world_point;
varying vec3 world_normal;
vec3 to_linear(vec3 c) { return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c)); }
vec3 to_srgb(vec3 c) { return mix(c * 12.92, 1.055 * pow(max(c, vec3(0.0)), vec3(1.0 / 2.4)) - 0.055, step(vec3(0.0031308), c)); }
vec3 rgb2hsv(vec3 c) {
	vec4 k = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, k.wz), vec4(c.gb, k.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + 1e-10)), d / (q.x + 1e-10), q.x);
}
vec3 hsv2rgb(vec3 c) {
	vec3 p = abs(fract(c.xxx + vec3(1.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0);
	return c.z * mix(vec3(1.0), clamp(p - 1.0, 0.0, 1.0), c.y);
}
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}
vec3 grass(vec3 paint, vec2 at) {
	vec3 hsv = rgb2hsv(paint);
	float green = smoothstep(0.11, 0.15, hsv.x) * (1.0 - smoothstep(0.38, 0.44, hsv.x))
		* smoothstep(0.10, 0.20, hsv.y) * smoothstep(0.22, 0.34, hsv.z);
	if (green <= 0.0) return paint;
	// Two octaves: meadows a few hundred units across, and a finer mottle.
	float broad = noise(at / 520.0) * 0.65 + noise(at / 170.0 + 17.0) * 0.35;
	float fine = noise(at / 38.0 + 41.0);
	float patch = (broad - 0.5) * 2.0;
	hsv.y = mix(hsv.y, clamp(hsv.y * grass_saturation * (1.0 + 0.10 * patch), 0.0, 0.85), green);
	hsv.z = mix(hsv.z, clamp(hsv.z * grass_value * (1.0 + grass_patches * patch + 0.035 * (fine - 0.5)), 0.0, 0.92), green);
	// A touch greener overall, so the map's warm wash does not turn it yellow; lighter
	// meadows lean yellow, darker ones lean blue-green.
	hsv.x = mix(hsv.x, hsv.x + grass_hue - 0.018 * patch, green);
	return hsv2rgb(hsv);
}
void vertex() {
	world_point = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}
void fragment() {
	bool hidden = lod_hidden(FRAGCOORD.xy) || replaced_by_detail(world_point.xz, FRAGCOORD.xy);
	if (lod_side == 0 && local_detail_blend >= 1.0 && hidden) { discard; }
	vec3 paint = textured ? texture(artwork, artwork_rect.xy + UV * artwork_rect.zw).rgb : COLOR.rgb;
	if (textured && !OUTPUT_IS_SRGB) paint = to_srgb(paint);
	paint = mix(paint, vec3(0.50, 0.52, 0.35), road_fade);
	if (!strata) paint = grass(paint, world_point.xz);
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
	if (sc3d_soot_on > 0.5 && !strata) {
		vec2 soot_uv = (world_point.xz - sc3d_soot_rect.xy) / sc3d_soot_rect.zw;
		float soot = texture(sc3d_soot_map, soot_uv).r;
		float luma = dot(paint, vec3(0.2126, 0.7152, 0.0722));
		vec3 grimy = mix(vec3(luma), paint, 0.30) * vec3(0.78, 0.73, 0.66);
		paint = mix(paint, grimy, clamp(soot, 0.0, 1.0) * 0.85);
	}
	ALBEDO = OUTPUT_IS_SRGB ? paint : to_linear(paint);
	if (hidden) { discard; }
}
