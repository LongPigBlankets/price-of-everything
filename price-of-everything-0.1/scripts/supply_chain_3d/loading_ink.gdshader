shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
uniform float progress = 0.0;
void fragment() {
	if (UV.x > progress) discard;
	float aa = max(fwidth(UV.y), 0.08);
	float coverage = 1.0 - smoothstep(0.44-aa, 0.44+aa, abs(UV.y));
	vec3 ink = COLOR.r < 0.25 ? vec3(0.40,0.43,0.42) :
		(COLOR.r < 0.75 ? vec3(0.25,0.39,0.47) : vec3(0.21,0.27,0.36));
	ALBEDO = OUTPUT_IS_SRGB ? ink : mix(ink/12.92,pow((ink+0.055)/1.055,vec3(2.4)),step(vec3(0.04045),ink));
	ALPHA = coverage * (COLOR.r < 0.25 ? 0.78 : 0.92);
}
