shader_type spatial;
render_mode unshaded, cull_disabled;
uniform bool draw_grid = true;
varying vec2 local_point;
varying vec2 map_point;
float grain(vec2 p) { return fract(sin(dot(p, vec2(127.1,311.7))) * 43758.5453); }
void vertex() {
	local_point = VERTEX.xz;
	map_point = (MODEL_MATRIX * vec4(VERTEX,1.0)).xz;
}
void fragment() {
	vec2 corners[6] = vec2[6](vec2(270,0),vec2(135,240),vec2(-135,240),vec2(-270,0),vec2(-135,-240),vec2(135,-240));
	float nearest = 10000.0;
	float along = 0.0;
	for (int i=0; i<6; i++) {
		vec2 a = corners[i];
		vec2 b = corners[(i+1)%6];
		vec2 tangent = normalize(b-a);
		float d = abs(dot(local_point-a, vec2(-tangent.y,tangent.x)));
		if (d < nearest) { nearest = d; along = dot(local_point-(a+b)*0.5,tangent); }
	}
	float aa = max(fwidth(nearest),0.3);
	float line = 1.0-smoothstep(0.9-aa,0.9+aa,nearest);
	float dash = smoothstep(-0.05,0.15,cos(along * 6.2831853/28.0));
	vec3 paper = vec3(0.88,0.84,0.73) + (grain(floor(map_point*1.5))-0.5)*0.022;
	vec3 ink = vec3(0.19,0.25,0.36);
	vec3 paint = mix(paper,ink,draw_grid ? line*dash*0.78 : 0.0);
	ALBEDO = OUTPUT_IS_SRGB ? paint : mix(paint/12.92,pow((paint+0.055)/1.055,vec3(2.4)),step(vec3(0.04045),paint));
}
