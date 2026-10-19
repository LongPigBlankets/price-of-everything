// The Paper WPA print in the game: every surface lands on blue-black ink (#1f2b36) and cream
// stock (#ece0c6), the way tools/supply_chain_3d/paper_wpa_catalog.py prints a catalogue plate
// (printed) and a map sheet (printed_map). The print acts on the colour the screen shows:
// board.gd's Environment tonemaps with Filmic at white 1, so the paint goes through that curve,
// is printed, and is handed back as the value the curve turns into the print.
#ifndef PRINT_LOOK
#define PRINT_LOOK
// 0 = as painted, 1 = printed. Offline bakes leave it at 0, so atlases are never printed twice.
global uniform float sc3d_print;
// 0..1: how far decorative scenery steps back behind the works.
global uniform float sc3d_calm;

// OKLab of the ink and the paper.
const vec3 PRINT_INK = vec3(0.28301993, -0.01043475, -0.02403735);
const vec3 PRINT_PAPER = vec3(0.90946789, 0.00246259, 0.03682202);
// The plates' paper and ink texture strengths.
const float PRINT_MOTTLE = 0.022;
const float PRINT_FIBRE = 0.0039;
const float PRINT_TOOTH = 0.0065;
const float PRINT_INK_FIBRE = 0.0078;
const float PRINT_INK_GRAIN = 0.0195;

vec3 print_to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}
vec3 print_to_srgb(vec3 c) {
	c = clamp(c, vec3(0.0), vec3(1.0));
	return mix(c * 12.92, 1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055, step(vec3(0.0031308), c));
}
// Godot's Filmic curve (tonemap.glsl, exposure bias 2) at white 1, and its inverse.
vec3 print_filmic(vec3 x) {
	return ((x * (0.88 * x + 0.06) + 0.002) / (x * (0.88 * x + 0.6) + 0.06) - 0.0333333) / 0.57835498;
}
vec3 print_unfilmic(vec3 y) {
	vec3 k = clamp(y, vec3(0.0), vec3(1.0)) * 0.57835498 + 0.0333333;
	vec3 a = 0.88 * (k - 1.0);
	vec3 b = 0.6 * (k - 0.1);
	vec3 c = 0.2 * (0.3 * k - 0.01);
	return (-b - sqrt(max(b * b - 4.0 * a * c, vec3(0.0)))) / (2.0 * a);
}
vec3 print_oklab(vec3 c) {
	vec3 lms = vec3(dot(c, vec3(0.4122214708, 0.5363325363, 0.0514459929)),
		dot(c, vec3(0.2119034982, 0.6806995451, 0.1073969566)),
		dot(c, vec3(0.0883024619, 0.2817188376, 0.6299787005)));
	lms = pow(max(lms, vec3(0.0)), vec3(1.0 / 3.0));
	return vec3(dot(lms, vec3(0.2104542553, 0.7936177850, -0.0040720468)),
		dot(lms, vec3(1.9779984951, -2.4285922050, 0.4505937099)),
		dot(lms, vec3(0.0259040371, 0.7827717662, -0.8086757660)));
}
vec3 print_from_oklab(vec3 lab) {
	vec3 lms = vec3(dot(lab, vec3(1.0, 0.3963377774, 0.2158037573)),
		dot(lab, vec3(1.0, -0.1055613458, -0.0638541728)),
		dot(lab, vec3(1.0, -0.0894841775, -1.2914855480)));
	lms = lms * lms * lms;
	return vec3(dot(lms, vec3(4.0767416621, -3.3077115913, 0.2309699292)),
		dot(lms, vec3(-1.2684380046, 2.6097574011, -0.3413193965)),
		dot(lms, vec3(-0.0041960863, -0.7034186147, 1.7076147010)));
}
// Lights (lit windows, glows, a flare) keep their colour rather than draining to paper.
float print_light(vec3 lab) {
	return clamp((length(lab.yz) - 0.035) / 0.05, 0.0, 1.0) * smoothstep(0.86, 0.94, lab.x);
}
// printed(): a building as on its catalogue plate. Near-neutrals soften toward the stock and the
// ink, strong accents keep (and gain) their colour.
vec3 print_plate(vec3 lab) {
	float l2 = PRINT_INK.x + (PRINT_PAPER.x - PRINT_INK.x) * clamp((lab.x - 0.24) / 0.60, 0.0, 1.0);
	float t = (l2 - PRINT_INK.x) / (PRINT_PAPER.x - PRINT_INK.x);
	float toward_paper = pow(clamp((t - 0.74) / 0.26, 0.0, 1.0), 1.5) * (1.0 - print_light(lab));
	float toward_ink = clamp((0.22 - t) / 0.22, 0.0, 1.0);
	float accent = clamp((length(lab.yz) - 0.035) / 0.05, 0.0, 1.0);
	float keep = (0.92 + 0.43 * accent) * (1.0 - toward_paper) * (1.0 - toward_ink);
	return vec3(l2, lab.yz * keep + PRINT_PAPER.yz * toward_paper + PRINT_INK.yz * toward_ink + vec2(0.0, 0.008));
}
float print_hue_weight(float hue, float centre, float width) {
	float x = clamp(1.0 - abs(mod(hue - centre + 180.0, 360.0) - 180.0) / width, 0.0, 1.0);
	return x * x * (3.0 - 2.0 * x);
}
// printed_map(): the landscape over a gentler range, grass muted toward sage, the sea kept
// blue, warm roofs and brick kept as accents.
vec3 print_map(vec3 lab) {
	float hue = length(lab.yz) > 0.000001 ? mod(degrees(atan(lab.z, lab.y)), 360.0) : 0.0;
	float l2 = PRINT_INK.x + (PRINT_PAPER.x - PRINT_INK.x) * clamp((lab.x - 0.20) / 0.70, 0.0, 1.0);
	float t = (l2 - PRINT_INK.x) / (PRINT_PAPER.x - PRINT_INK.x);
	float toward_paper = pow(clamp((t - 0.84) / 0.16, 0.0, 1.0), 1.5) * (1.0 - print_light(lab));
	float toward_ink = clamp((0.16 - t) / 0.16, 0.0, 1.0);
	float keep = 0.86 - 0.30 * print_hue_weight(hue, 125.0, 40.0) - 0.10 * print_hue_weight(hue, 255.0, 45.0)
		+ 0.20 * print_hue_weight(hue, 40.0, 30.0);
	keep *= (1.0 - toward_paper) * (1.0 - toward_ink);
	return vec3(l2, lab.yz * keep + PRINT_PAPER.yz * toward_paper + PRINT_INK.yz * toward_ink + vec2(0.0, 0.010));
}
float print_hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}
float print_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(print_hash(i), print_hash(i + vec2(1.0, 0.0)), u.x),
		mix(print_hash(i + vec2(0.0, 1.0)), print_hash(i + vec2(1.0, 1.0)), u.x), u.y);
}
// The stock's mottle, fibres and tooth, and ink grain where coverage is thin (mid tones).
// `pixel` is the screen position: the paper is the sheet the view is printed on.
vec3 print_grain(vec3 c, vec2 pixel, float paperness) {
	float mottle = (print_noise(pixel / 220.0) * 0.65 + print_noise(pixel / 80.0 + 17.0) * 0.35 - 0.5) * 4.0;
	float fibre = (print_noise(pixel * vec2(1.0 / 7.0, 1.0 / 1.6) + 3.0) - 0.5) * 4.0;
	float tooth = (print_noise(pixel / 2.4 + 9.0) - 0.5) * 4.0;
	float grain = (print_hash(floor(pixel) + 0.5) - 0.5) * 3.46;
	float stock = PRINT_MOTTLE * mottle + PRINT_FIBRE * fibre + PRINT_TOOTH * tooth;
	float luma = dot(c, vec3(0.2126, 0.7152, 0.0722));
	vec3 inked = (c * (1.0 + PRINT_INK_FIBRE * fibre) + PRINT_INK_GRAIN * grain * 4.0 * luma * (1.0 - luma)) * (1.0 + 0.05 * stock);
	return mix(inked, c * (1.0 + stock), smoothstep(0.80, 0.98, paperness));
}
// `paint`: a shader's sRGB colour before the tonemap. `as_landscape`: terrain and trees take the map
// sheet's print, buildings the plate's. `calm`: how far this piece of scenery steps back; 0 for
// the works. Calm scenery is printed with less ink: the map's gentler range, drifting toward the
// stock, so its darks lift and its colour quietens; its lights pale but stay.
vec3 print_paint(vec3 paint, vec2 pixel, bool as_landscape, float calm) {
	if (sc3d_print <= 0.0) return paint;
	vec3 lab = print_oklab(print_filmic(print_to_linear(clamp(paint, vec3(0.0), vec3(1.0)))));
	vec3 lab2 = as_landscape ? print_map(lab) : print_plate(lab);
	if (calm > 0.0) {
		lab2 = mix(mix(lab2, print_map(lab), calm), vec3(PRINT_PAPER.x - 0.05, PRINT_PAPER.yz),
			0.38 * calm * (1.0 - 0.6 * print_light(lab)));
	}
	vec3 printed = print_to_srgb(print_from_oklab(lab2));
	printed = print_grain(printed, pixel, (lab2.x - PRINT_INK.x) / (PRINT_PAPER.x - PRINT_INK.x));
	return mix(paint, print_to_srgb(print_unfilmic(print_to_linear(printed))), sc3d_print);
}
#endif
