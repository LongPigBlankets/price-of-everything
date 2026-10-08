shader_type spatial;
// Painted housing windows are single quads on all four walls. The sprite rig
// renders both sides; back-face culling erased the rear windows while orbiting.
render_mode unshaded, cull_disabled, fog_disabled;
// The sprite pipeline uses material colours, navy crease ink and face-driven stipple,
// with directional face lighting. Grounding shadows are drawn on the terrain.
uniform vec4 ink : source_color = vec4(0.20, 0.25, 0.36, 1.0);
uniform float spacing = 0.014;
uniform float stipple_strength = 0.22;
varying vec3 model_position;
varying vec3 face_normal;
varying vec3 world_point;
uniform vec2 grade_range = vec2(-100000.0, 100000.0);
uniform int detail_level = 2;
uniform bool lit_windows = false;
uniform bool curtain_wall = false;

void vertex() {
	model_position = VERTEX;
	world_point = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	face_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

vec3 linear_to_srgb(vec3 c) {
	return mix(c * 12.92, 1.055 * pow(max(c, vec3(0.0)), vec3(1.0 / 2.4)) - 0.055, step(vec3(0.0031308), c));
}
vec3 srgb_to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}
float dots(vec2 p, float density, vec2 offset) {
	vec2 grid = p * density + offset;
	float distance = length(fract(grid + 0.5) - 0.5);
	float aa = max(length(fwidth(grid)), 0.015);
	float dot = 1.0 - smoothstep(0.16 - aa * 0.5, 0.16 + aa * 0.5, distance);
	// Unresolved dots converge to average coverage instead of shimmering at distance.
	return mix(dot, 0.0804, smoothstep(0.3, 0.9, aa));
}
void fragment() {
	vec3 visible_normal = FRONT_FACING ? face_normal : -face_normal;
	// Blender's source palette is linear. A restrained, compressive paper response
	// approximates its AgX sprite render without the glossy PBR/default-sun treatment.
	vec3 paint = clamp(pow(max(COLOR.rgb, vec3(0.0)), vec3(0.60)) + 0.025, vec3(0.0), vec3(0.86));
	paint *= 1.0 - 0.18 * smoothstep(0.35, 0.85, max(max(paint.r, paint.g), paint.b));
	// Preserve the source palette: cream walls and silver mullions are paint, not ink.
	float luma = dot(paint, vec3(0.2126, 0.7152, 0.0722));
	bool glass = paint.b > paint.r * 1.45 && luma < 0.38;
	// render_sprite.py's mask direction (-.30, -.62, .72), converted to Godot Y-up.
	float mask = dot(normalize(visible_normal), normalize(vec3(-0.30, 0.72, 0.62))) * 0.48 + 0.52;
	float shade = linear_to_srgb(vec3(clamp(mask, 0.0, 1.0))).r;
	float darkness = clamp((0.86 - shade) / (0.86 - 0.56), 0.0, 1.0);
	// Project the print grid in the sprite rig's original isometric plane. This keeps
	// dots round at the home angle and attached to the building when it rotates.
	vec2 plane = vec2((model_position.x - model_position.z) * 0.70710678,
		(model_position.x + model_position.z) * 0.40824829 - model_position.y * 0.81649658);
	vec2 grid = vec2(plane.x + plane.y, plane.y - plane.x) * 0.70710678 / spacing;
	float dot_mask = dots(grid, 1.0, vec2(0.0));
	if (darkness > 0.45) { dot_mask = max(dot_mask, dots(grid, 1.0, vec2(0.5, 0.0))); }
	if (darkness > 0.78) { dot_mask = max(dot_mask, dots(grid, 2.0, vec2(0.0, 0.5))); }
	if (!glass && luma > 0.1) { paint *= 1.0 - dot_mask * darkness * stipple_strength; }
	// Matte directional light is separate from the printed dot mask. A fixed sun
	// makes different faces read as volumes throughout an orbit, without gloss.
	float diffuse = dot(normalize(visible_normal), normalize(vec3(0.50, 0.74, 0.45)));
	// The source rig is nearly ambient; its materials and stipple carry most of the
	// contrast. Do not multiply a second strong blue shadow into the board's grade.
	vec3 face_light = mix(vec3(0.90, 0.92, 0.96), vec3(1.0, 1.0, 0.98), smoothstep(-0.45, 0.8, diffuse));
	paint *= face_light;
	float projected_y = (world_point.x + world_point.z) * 0.40824829 - world_point.y * 0.81649658;
	float t = clamp((projected_y - grade_range.x) / max(1.0, grade_range.y - grade_range.x), 0.0, 1.0);
	paint *= mix(vec3(0.66, 0.74, 1.0), vec3(1.0, 0.92, 0.72), t);
	// UV contains triangle barycentrics (glTF flips V). UV2.x holds the three
	// opposite-edge bits. Only modelled creases/borders carry ink, never mesh diagonals.
	vec3 barycentric = vec3(UV.x, 1.0 - UV.y, UV.y - UV.x);
	vec3 dx = dFdx(barycentric);
	vec3 dy = dFdy(barycentric);
	vec3 aa = max(sqrt(dx * dx + dy * dy), vec3(0.00001));
	// UV2.y is the source stroke width in model units (glTF flips V). The original
	// 2.4px / 1.05px lines shrink with the sprite, rather than staying 1.6 screen pixels.
	float model_per_pixel = max(length(dFdx(model_position)), length(dFdy(model_position)));
	float half_width = max(0.0, 1.0 - UV2.y) * 0.5 / max(0.000001, model_per_pixel);
	vec3 distance_px = barycentric / aa;
	// Integrate subpixel ink coverage; do not impose a minimum opaque line width.
	vec3 lines = clamp(distance_px + 0.5, vec3(0.0), vec3(half_width))
		- clamp(distance_px - 0.5, vec3(0.0), vec3(half_width));
	float bits = floor(UV2.x + 0.5);
	vec3 edges = vec3(mod(bits, 2.0), mod(floor(bits / 2.0), 2.0), mod(floor(bits / 4.0), 2.0));
	float stroke = max(max(lines.x * edges.x, lines.y * edges.y), lines.z * edges.z);
	vec3 ink_srgb = OUTPUT_IS_SRGB ? ink.rgb : linear_to_srgb(ink.rgb);
	paint = mix(paint, ink_srgb, stroke * 0.88);
	if (lit_windows && glass) {
		float lit = 1.0;
		if (curtain_wall) {
			vec2 panes = vec2(abs(face_normal.x) > abs(face_normal.z) ? model_position.z : model_position.x, model_position.y) * vec2(14.0, 16.0);
			vec2 cell = floor(panes);
			vec2 within = fract(panes);
			float random = fract(sin(dot(cell, vec2(12.9898, 78.233))) * 43758.5453);
			vec2 aa = fwidth(panes);
			vec2 inside = smoothstep(vec2(0.16) - aa, vec2(0.16) + aa, within) * (1.0 - smoothstep(vec2(0.80) - aa, vec2(0.80) + aa, within));
			lit = inside.x * inside.y * step(0.64, random);
		}
		paint = mix(paint, vec3(1.0, 0.87, 0.57) * (1.0 - stroke * 0.50), 0.86 * lit);
	}
	ALBEDO = OUTPUT_IS_SRGB ? paint : srgb_to_linear(paint);
}
