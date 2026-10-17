// Loading-only coverage uses the same opaque dissolve as LOD handovers.
// Separate per-board uniforms keep the retained owned scene untouched.
uniform bool loading_mask = false;
uniform sampler2D loading_tiles : filter_nearest, repeat_disable;
uniform vec2 loading_origin = vec2(0.0);
uniform vec4 loading_grid = vec4(0.0,0.0,1.0,1.0);
bool loading_hidden(vec2 world, vec2 pixel) {
	if (!loading_mask) return false;
	vec2 p = world-loading_origin;
	float column = floor(p.x/405.0+0.5);
	for (int i=-1;i<=1;i++) {
		float q = column+float(i);
		float stagger = mod(q,2.0)*0.5;
		float r = floor(p.y/480.0-stagger+0.5);
		vec2 delta = abs(p-vec2(q*405.0,(r+stagger)*480.0));
		if (delta.y<=240.001 && delta.x<=270.001-delta.y*0.5625) {
			vec2 cell = vec2(q,r)-loading_grid.xy;
			if (any(lessThan(cell,vec2(0.0))) || any(greaterThanEqual(cell,loading_grid.zw))) return false;
			return lod_sample(pixel)>=texture(loading_tiles,(cell+0.5)/loading_grid.zw).r;
		}
	}
	return false;
}
