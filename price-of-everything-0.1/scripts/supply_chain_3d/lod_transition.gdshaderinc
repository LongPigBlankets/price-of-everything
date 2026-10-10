// Complementary screen-space coverage keeps both LODs opaque and depth-correct.
// Stable geometry pays no transparency/sorting cost outside the two-frame handover.
uniform int lod_side = 0; // 1: local detail, -1: far representation, 0: unchanged.
uniform float lod_blend = 1.0;
float lod_sample(vec2 pixel) {
	return fract(52.9829189 * fract(dot(floor(pixel), vec2(0.06711056, 0.00583715))));
}
bool lod_hidden(vec2 pixel) {
	if (lod_side == 0) { return false; }
	return lod_side > 0 ? lod_sample(pixel) >= lod_blend : lod_sample(pixel) < lod_blend;
}
