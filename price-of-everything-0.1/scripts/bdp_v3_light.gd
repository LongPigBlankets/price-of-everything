extends RefCounted
## Building Detail v3: the lamp over the panel. The panel is lit by a lamp at the top-left of the screen:
## the further a point is from it, the darker. One overlay over the whole panel multiplies that in, so
## it follows whatever is on screen at each point: content lit by where it is now as it scrolls, and
## the whole panel as it is dragged. Nothing runs on a scroll; each pixel works out its own light.
##
## The panel's text takes a share of the darkening back (TEXT_GIVE_BACK), so it stays readable as the
## steel round it darkens, and its glows take all of it back, since they give off their own light.
## Everything shares one material of each kind, so the panel draws in as few batches as before.

## The lamp, in screen UV; how far from it (as a share of the screen's diagonal) the light starts to
## fall and where it reaches its darkest, falling evenly between; and how dark that is. The panel
## usually spans about a third of the diagonal, so it takes a gentle, even fall from top-left to
## bottom-right wherever it sits.
const LAMP_UV := Vector2(0.0, 0.0)
const NEAR := 0.25
const FAR := 0.9
const DARKEST := 0.7
## Share of the darkening that the text takes back (the text is not relit past its own colour).
const TEXT_GIVE_BACK := 0.5

const _LAMP := """
uniform vec2 lamp_uv = vec2(0.0, 0.0);
uniform float near_d = 0.25;
uniform float far_d = 0.9;
uniform float darkest = 0.7;
float lamp(vec2 screen_uv, vec2 pixel_size) {
	vec2 aspect = vec2(pixel_size.y / pixel_size.x, 1.0);
	float d = length((screen_uv - lamp_uv) * aspect) / length(aspect);
	return mix(1.0, darkest, clamp((d - near_d) / (far_d - near_d), 0.0, 1.0));
}
"""

const _SHADE := "shader_type canvas_item;\nrender_mode blend_mul;\n" + _LAMP + """
uniform vec2 rect_size = vec2(1.0);
uniform float corner = 0.0;
varying vec2 local;
void vertex() {
	local = VERTEX;
}
void fragment() {
	// Outside the panel's rounded corners the map shows through: leave it be.
	vec2 q = abs(local - rect_size * 0.5) - (rect_size * 0.5 - vec2(corner));
	float outside = step(corner, length(max(q, vec2(0.0))));
	COLOR = vec4(vec3(mix(lamp(SCREEN_UV, SCREEN_PIXEL_SIZE), 1.0, outside)), 1.0);
}
"""

const _GIVE_BACK := "shader_type canvas_item;\n" + _LAMP + """
uniform float give_back = 0.5;
void fragment() {
	COLOR.rgb = min(COLOR.rgb * pow(lamp(SCREEN_UV, SCREEN_PIXEL_SIZE), -give_back), vec3(1.0));
}
"""

const _GLOW := "shader_type canvas_item;\nrender_mode blend_add;\n" + _LAMP + """
void fragment() {
	COLOR.rgb *= 1.0 / lamp(SCREEN_UV, SCREEN_PIXEL_SIZE);
}
"""

static var _shade: ShaderMaterial
static var _text: ShaderMaterial
static var _glow: ShaderMaterial
static var _emissive: ShaderMaterial


static func _material(code: String) -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = code
	var m := ShaderMaterial.new()
	m.shader = shader
	m.set_shader_parameter("lamp_uv", LAMP_UV)
	m.set_shader_parameter("near_d", NEAR)
	m.set_shader_parameter("far_d", FAR)
	m.set_shader_parameter("darkest", DARKEST)
	return m


## The overlay's material (one per overlay: it carries the panel's size for its rounded corners).
static func shade_material() -> ShaderMaterial:
	if _shade == null:
		_shade = _material(_SHADE)
	return _shade.duplicate() as ShaderMaterial


## Shared by all of the panel's text.
static func text_material() -> ShaderMaterial:
	if _text == null:
		_text = _material(_GIVE_BACK)
		_text.set_shader_parameter("give_back", TEXT_GIVE_BACK)
	return _text


## Shared by what gives its own light, drawn normally (LED segments): all of the overlay's shade is given
## back, so the lamp doesn't dim it.
static func emissive_material() -> ShaderMaterial:
	if _emissive == null:
		_emissive = _material(_GIVE_BACK)
		_emissive.set_shader_parameter("give_back", 1.0)
	return _emissive


## Shared by the glows (drawn additively).
static func glow_material() -> ShaderMaterial:
	if _glow == null:
		_glow = _material(_GLOW)
	return _glow


## The lamp's light at a screen UV, as the shaders work it out (for tests and tools).
static func light_at(screen_uv: Vector2, screen_size: Vector2) -> float:
	var aspect := Vector2(screen_size.x / screen_size.y, 1.0)
	var d := ((screen_uv - LAMP_UV) * aspect).length() / aspect.length()
	return lerpf(1.0, DARKEST, clampf((d - NEAR) / (FAR - NEAR), 0.0, 1.0))
