// The building print paint, shared by the opaque and see-through shaders.
// The sprite pipeline uses material colours, navy crease ink and face-driven stipple,
// with directional face lighting. Grounding shadows are drawn on the terrain.
uniform vec4 ink : source_color = vec4(0.20, 0.25, 0.36, 1.0);
uniform float stroke_width_scale = 1.0;
uniform float stroke_opacity = 0.88;
uniform float spacing = 0.014;
uniform float stipple_strength = 0.22;
varying vec3 model_position;
varying vec3 face_normal;
varying vec3 world_point;
uniform vec2 grade_range = vec2(-100000.0, 100000.0);
uniform int detail_level = 2;
uniform bool lit_windows = false;
uniform bool curtain_wall = false;
uniform vec3 foliage_tint = vec3(1.0);
// 0 = as authored (the company's own and unclassified), 2 = decorative scenery, 3 = an NPC's.
instance uniform float sc_role = 0.0;
// How far scenery and NPC works step back toward grey.
uniform float decor_grey = 0.65;
uniform float npc_grey = 0.80;
// Blender units per model unit (the export's family span), so patterns keep one real size
// across families. 0 = not exported with patterns; the fallback is a typical span.
instance uniform float pattern_scale = 0.0;
varying vec3 model_normal;

void vertex() {
	model_position = VERTEX;
	model_normal = NORMAL;
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
// A printed line pattern: coverage of lines `width` wide every `period`, fading to the
// average coverage once the lines are too fine to resolve.
float pattern_line(float coord, float period, float width) {
	float d = abs(fract(coord / period + 0.5) - 0.5) * period;
	float w = max(fwidth(coord), 0.00001);
	float line = 1.0 - smoothstep(width - w, width + w, d);
	return mix(line, min(1.0, 2.0 * width / period), smoothstep(0.12 * period, 0.40 * period, w));
}
float pattern_hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
// A cell-by-cell speckle in -1..1, silent once a cell is smaller than a pixel.
float pattern_speckle(vec2 p, float cell) {
	float v = pattern_hash(floor(p / cell)) * 2.0 - 1.0;
	return v * (1.0 - smoothstep(0.4 * cell, 1.0 * cell, length(fwidth(p))));
}
// The export writes a material pattern into the colour's alpha (export_models.py PATTERNS):
// 1 brick, 2 wall panels, 3 roof gravel, 4 paving, 5 standing-seam metal roof.
vec3 material_pattern(vec3 paint, float code, vec3 p, vec3 n) {
	if (code < 0.5) return paint;
	bool top = n.y > 0.7;
	bool wall = abs(n.y) < 0.4;
	// Along-the-wall coordinate for vertical faces, the plan for top faces.
	float u = abs(n.x) > abs(n.z) ? p.z : p.x;
	if (code < 1.5 && wall) {
		// Brick: stretcher bond, mortar lines and a little variation brick to brick.
		float course = 0.075;
		float row = floor(p.y / course);
		float along = u + mod(row, 2.0) * 0.105;
		float mortar = max(pattern_line(p.y, course, 0.0050), pattern_line(along, 0.21, 0.0050));
		float brick = pattern_speckle(vec2(along, p.y + 0.5 * course), 0.21) * 0.05;
		// Light lime mortar, as on a printed elevation: the joints read pale against the brick.
		return mix(paint * (1.0 + brick), vec3(0.74, 0.70, 0.62), mortar * 0.60);
	}
	if (code < 2.5 && wall) {
		// Cladding panels: fine joints and a faint render speckle.
		float joint = max(pattern_line(u, 0.62, 0.0055), pattern_line(p.y, 0.52, 0.0055));
		paint *= 1.0 + pattern_speckle(vec2(u, p.y), 0.018) * 0.025;
		return mix(paint, paint * 0.76, joint * 0.80);
	}
	if (code < 3.5 && top) {
		// Roof gravel: two sizes of speckle and the odd dark stone.
		float fine = pattern_speckle(p.xz, 0.016) * 0.035 + pattern_speckle(p.xz + 7.3, 0.045) * 0.02;
		float stone = step(0.96, pattern_hash(floor(p.xz / 0.024) + 3.1)) * (1.0 - smoothstep(0.010, 0.024, length(fwidth(p.xz))));
		return paint * (1.0 + fine - 0.12 * stone);
	}
	if (code > 4.5 && code < 5.5 && n.y > 0.3 && n.y < 0.97) {
		// Standing-seam metal roof: seams run down the slope, spaced along the ridge.
		vec2 ridge = normalize(vec2(-n.z, n.x) + vec2(0.00001));
		float along = dot(p.xz, ridge);
		float seam = pattern_line(along, 0.085, 0.0045);
		return mix(paint, paint * 0.80, seam * 0.85);
	}
	if (code < 4.5 && top) {
		// Paving: slab joints and a slight tone per slab.
		float joint = max(pattern_line(p.x, 0.50, 0.0065), pattern_line(p.z, 0.50, 0.0065));
		paint *= 1.0 + pattern_speckle(p.xz, 0.50) * 0.03 + pattern_speckle(p.xz, 0.02) * 0.02;
		return mix(paint, paint * 0.78, joint * 0.85);
	}
	return paint;
}
vec3 role_paint(vec3 paint, vec3 normal, bool glass) {
	if (sc_role < 1.5) return paint;
	float luma = dot(paint, vec3(0.2126, 0.7152, 0.0722));
	// Scenery and NPC works step back: greyer, and NPC works toward paper white.
	bool npc = sc_role > 2.5;
	vec3 grey = vec3(luma) * (npc ? vec3(1.04, 1.02, 0.97) : vec3(0.98, 0.99, 1.02));
	vec3 quiet = mix(paint, grey, (npc ? npc_grey : decor_grey) * (glass ? 0.7 : 1.0));
	return npc ? mix(quiet, vec3(0.88, 0.86, 0.81), 0.18) : quiet * 1.02;
}
void fragment() {
	vec3 visible_normal = FRONT_FACING ? face_normal : -face_normal;
	// Blender's source palette is linear. A restrained, compressive paper response
	// approximates its AgX sprite render without the glossy PBR/default-sun treatment.
	vec3 paint = clamp(pow(max(COLOR.rgb, vec3(0.0)), vec3(0.60)) + 0.025, vec3(0.0), vec3(0.86));
	paint *= 1.0 - 0.18 * smoothstep(0.35, 0.85, max(max(paint.r, paint.g), paint.b));
#ifndef GLASS
	// Opaque faces: alpha = 1 - pattern / 8. Glass faces: alpha is their opacity.
	float span = pattern_scale > 0.0 ? pattern_scale : 7.0;
	paint = material_pattern(paint, floor((1.0 - COLOR.a) * 8.0 + 0.5), model_position * span, normalize(model_normal));
#endif
	// The tree PNGs have a more muted green response than the building palette's
	// approximation. Species materials calibrate leaves; bark and building paint stay intact.
	if (COLOR.g > COLOR.r * 1.15) { paint *= foliage_tint; }
	// Preserve the source palette: cream walls and silver mullions are paint, not ink.
	float luma = dot(paint, vec3(0.2126, 0.7152, 0.0722));
#ifdef GLASS
	// Every face of the see-through shader is glass, whatever its tint.
	bool glass = true;
#else
	bool glass = paint.b > paint.r * 1.45 && luma < 0.38;
#endif
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
#ifndef NO_POSITION_GRADE
	paint *= mix(vec3(0.66, 0.74, 1.0), vec3(1.0, 0.92, 0.72), t);
#endif
	paint = role_paint(paint, visible_normal, glass);
	// UV contains triangle barycentrics (glTF flips V). UV2.x holds the three
	// opposite-edge bits. Only modelled creases/borders carry ink, never mesh diagonals.
	vec3 barycentric = vec3(UV.x, 1.0 - UV.y, UV.y - UV.x);
	vec3 dx = dFdx(barycentric);
	vec3 dy = dFdy(barycentric);
	vec3 aa = max(sqrt(dx * dx + dy * dy), vec3(0.00001));
	// UV2.y is the source stroke width in model units (glTF flips V). The original
	// 2.4px / 1.05px lines shrink with the sprite, rather than staying 1.6 screen pixels.
	float model_per_pixel = max(length(dFdx(model_position)), length(dFdy(model_position)));
	float half_width = max(0.0, 1.0 - UV2.y) * stroke_width_scale * 0.5 / max(0.000001, model_per_pixel);
	vec3 distance_px = barycentric / aa;
	// Integrate subpixel ink coverage; do not impose a minimum opaque line width.
	vec3 lines = clamp(distance_px + 0.5, vec3(0.0), vec3(half_width))
		- clamp(distance_px - 0.5, vec3(0.0), vec3(half_width));
	float bits = floor(UV2.x + 0.5);
	vec3 edges = vec3(mod(bits, 2.0), mod(floor(bits / 2.0), 2.0), mod(floor(bits / 4.0), 2.0));
	float stroke = max(max(lines.x * edges.x, lines.y * edges.y), lines.z * edges.z);
	vec3 ink_srgb = OUTPUT_IS_SRGB ? ink.rgb : linear_to_srgb(ink.rgb);
	paint = mix(paint, ink_srgb, stroke * stroke_opacity);
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
#ifdef GLASS
	// Lit glass keeps its own opacity, so a lit hall still shows its interior.
	ALPHA = COLOR.a;
#endif
	if ((lod_hidden(FRAGCOORD.xy) || loading_hidden(world_point.xz, FRAGCOORD.xy))) { discard; }
}
