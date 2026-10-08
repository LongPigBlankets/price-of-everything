shader_type spatial;
render_mode unshaded, cull_back, fog_disabled;
// The sprite pipeline uses material colours, navy crease ink and face-driven stipple,
// not cast shadows. Keep the pattern attached to the model as the camera orbits.
uniform vec4 ink : source_color = vec4(0.20, 0.25, 0.36, 1.0);
uniform float ink_pixels = 1.6;
uniform float spacing = 0.014;
uniform float stipple_strength = 0.22;
varying vec3 model_position;
varying vec3 face_normal;

void vertex() {
	model_position = VERTEX;
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
	// Blender's source palette is linear. A restrained, compressive paper response
	// approximates its AgX sprite render without the glossy PBR/default-sun treatment.
	vec3 paint = clamp(pow(max(COLOR.rgb, vec3(0.0)), vec3(0.60)) + 0.025, vec3(0.0), vec3(0.86));
	paint *= 1.0 - 0.18 * smoothstep(0.35, 0.85, max(max(paint.r, paint.g), paint.b));
	// The kit's cream mullions are mostly covered by navy Freestyle in the sprite.
	// Keep their fine geometry readable in 3D with the same muted frame colour.
	if (COLOR.r > 0.74 && COLOR.g > 0.72 && COLOR.b > 0.66 && COLOR.b < COLOR.r) {
		paint = vec3(0.30, 0.35, 0.43);
	}
	float luma = dot(paint, vec3(0.2126, 0.7152, 0.0722));
	bool glass = paint.b > paint.r * 1.45 && luma < 0.38;
	if (glass) { paint *= 0.80; }
	// render_sprite.py's mask direction (-.30, -.62, .72), converted to Godot Y-up.
	float mask = dot(normalize(face_normal), normalize(vec3(-0.30, 0.72, 0.62))) * 0.48 + 0.52;
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
	// UV contains triangle barycentrics (glTF flips V). UV2.x holds the three
	// opposite-edge bits. Only modelled creases/borders carry ink, never mesh diagonals.
	vec3 barycentric = vec3(UV.x, 1.0 - UV.y, UV.y - UV.x);
	vec3 aa = max(fwidth(barycentric), vec3(0.00001));
	vec3 lines = 1.0 - smoothstep(vec3(0.0), aa * ink_pixels, barycentric);
	float bits = floor(UV2.x + 0.5);
	vec3 edges = vec3(mod(bits, 2.0), mod(floor(bits / 2.0), 2.0), mod(floor(bits / 4.0), 2.0));
	float stroke = max(max(lines.x * edges.x, lines.y * edges.y), lines.z * edges.z);
	vec3 ink_srgb = OUTPUT_IS_SRGB ? ink.rgb : linear_to_srgb(ink.rgb);
	paint = mix(paint, ink_srgb, stroke * 0.88);
	ALBEDO = OUTPUT_IS_SRGB ? paint : srgb_to_linear(paint);
}
