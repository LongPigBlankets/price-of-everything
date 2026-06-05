shader_type canvas_item;
// 3x3 box blur over whatever rendered behind this control. Used to "frost" the recipe flow
// diagram while a building is under construction / awaiting materials.
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float blur_px : hint_range(0.0, 16.0) = 5.0;

void fragment() {
	vec2 ps = SCREEN_PIXEL_SIZE * blur_px;
	vec4 c = vec4(0.0);
	c += texture(screen_tex, SCREEN_UV + vec2(-ps.x, -ps.y));
	c += texture(screen_tex, SCREEN_UV + vec2(0.0, -ps.y));
	c += texture(screen_tex, SCREEN_UV + vec2(ps.x, -ps.y));
	c += texture(screen_tex, SCREEN_UV + vec2(-ps.x, 0.0));
	c += texture(screen_tex, SCREEN_UV);
	c += texture(screen_tex, SCREEN_UV + vec2(ps.x, 0.0));
	c += texture(screen_tex, SCREEN_UV + vec2(-ps.x, ps.y));
	c += texture(screen_tex, SCREEN_UV + vec2(0.0, ps.y));
	c += texture(screen_tex, SCREEN_UV + vec2(ps.x, ps.y));
	COLOR = c / 9.0;
}
