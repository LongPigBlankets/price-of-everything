shader_type canvas_item;
// A part shown as unavailable: its colours taken to grey and dimmed a little (the construct catalogue's cards
// that can't be built there or can't be paid for).
uniform float dim = 0.88;

void fragment() {
	vec4 c = texture(TEXTURE, UV) * COLOR;
	float g = dot(c.rgb, vec3(0.299, 0.587, 0.114));
	COLOR = vec4(vec3(g) * dim, c.a);
}
