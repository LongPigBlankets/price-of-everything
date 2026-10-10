// Exact flat-hex lookup in a small residency texture, not a per-fragment scan
// through hundreds of tiles. Only the far backdrop enables this mask.
#include "res://scripts/supply_chain_3d/lod_transition.gdshaderinc"
uniform bool local_detail_mask = false;
uniform float local_detail_blend = 1.0;
uniform sampler2D resident_tiles : filter_nearest, repeat_disable;
uniform vec2 residency_origin = vec2(0.0);
uniform vec4 residency_grid = vec4(0.0, 0.0, 1.0, 1.0);
bool replaced_by_detail(vec2 world, vec2 pixel) {
	if (!local_detail_mask) { return false; }
	if (local_detail_blend < 1.0 && lod_sample(pixel) >= local_detail_blend) { return false; }
	vec2 p = world - residency_origin;
	float column = floor(p.x / 405.0 + 0.5);
	for (int i = -1; i <= 1; i++) {
		float q = column + float(i);
		float stagger = mod(q, 2.0) * 0.5;
		float r = floor(p.y / 480.0 - stagger + 0.5);
		vec2 delta = abs(p - vec2(q * 405.0, (r + stagger) * 480.0));
		if (delta.y <= 240.001 && delta.x <= 270.001 - delta.y * 0.5625) {
			vec2 cell = vec2(q, r) - residency_grid.xy;
			if (any(lessThan(cell, vec2(0.0))) || any(greaterThanEqual(cell, residency_grid.zw))) { return false; }
			return texture(resident_tiles, (cell + 0.5) / residency_grid.zw).r > 0.5;
		}
	}
	return false;
}
