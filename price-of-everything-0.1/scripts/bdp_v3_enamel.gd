extends Control
## Building Detail v3: the recipe diagram's vitreous enamel sign, set into the panel behind the diagram's
## icons. The render (res://assets/ui/bdp_v3/recipe_enamel.png, from
## tools/button_mockup/cluster.html?export) is the recess's cut, a steel chamfer down to the enamel,
## and the enamel: a cream rim in the cut's shadow, a navy band and pinstripe, and a few chips at its
## corners. It is drawn as a 9-slice with the cut on this control's rect. The grunge on the field
## (recipe_grunge.png) is
## a layer of its own, and a shader fades it out round every watched control (the goods icons and the
## arrow), so the wear only sits in the space between them; it gathers towards the band.
##
## The watched controls move whenever the diagram is laid out, so their rects are checked each frame
## while the sign is visible and handed to the shader when they change.

const Nine := preload("res://scripts/bdp_v3_nine.gd")
const PLATE: Texture2D = preload("res://assets/ui/bdp_v3/recipe_enamel.png")
const GRUNGE: Texture2D = preload("res://assets/ui/bdp_v3/recipe_grunge.png")
const CAPTURE_SCALE := 1.875
const TEXELS_PER_PIXEL := 2.0
## From layout.json (recipe_enamel), in layout pixels: the render's room outside the cut, the 9-slice
## corner, and how far in from the cut the field starts.
const MARGIN := 3.0
const CORNER := 44.0
const FIELD_INSET := 21.0
## Clear space round each watched control before the grunge comes back, and how softly it does.
const HOLE_PAD := 6.0
const HOLE_SOFT := 10.0
const MAX_HOLES := 12

const GRUNGE_SHADER := """shader_type canvas_item;
uniform sampler2D grunge : filter_linear_mipmap, repeat_enable;
uniform vec2 grunge_px = vec2(480.0, 240.0);
uniform vec2 field_size = vec2(1.0);
uniform vec4 holes[12];
uniform int hole_count = 0;
uniform float hole_soft = 10.0;
uniform float edge_px = 16.0;
varying vec2 local;
void vertex() {
	local = VERTEX;
}
void fragment() {
	vec4 g = texture(grunge, local / grunge_px);
	float edge = min(min(local.x, local.y), min(field_size.x - local.x, field_size.y - local.y));
	float gather = mix(1.5, 0.85, smoothstep(0.0, edge_px, edge));
	float keep = 1.0;
	for (int i = 0; i < 12; i++) {
		if (i >= hole_count) {
			break;
		}
		vec2 half_size = holes[i].zw * 0.5;
		vec2 d = abs(local - (holes[i].xy + half_size)) - half_size;
		float dist = length(max(d, vec2(0.0))) + min(max(d.x, d.y), 0.0);
		keep = min(keep, smoothstep(0.0, hole_soft, dist));
	}
	COLOR = vec4(g.rgb, clamp(g.a * gather, 0.0, 1.0) * keep);
}
"""

var _grunge: Control
var _material: ShaderMaterial
var _watched: Array[Control] = []
var _hole_rects: Array[Rect2] = []


func _init() -> void:
	name = "BdpV3Enamel"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var shader := Shader.new()
	shader.code = GRUNGE_SHADER
	_material = ShaderMaterial.new()
	_material.shader = shader
	_material.set_shader_parameter("grunge", GRUNGE)
	_material.set_shader_parameter("grunge_px", GRUNGE.get_size() / TEXELS_PER_PIXEL)
	_material.set_shader_parameter("hole_soft", HOLE_SOFT)
	_grunge = Control.new()
	_grunge.name = "Grunge"
	_grunge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_grunge.material = _material
	_grunge.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var inset := FIELD_INSET / CAPTURE_SCALE
	_grunge.offset_left = inset
	_grunge.offset_top = inset
	_grunge.offset_right = -inset
	_grunge.offset_bottom = -inset
	_grunge.draw.connect(func() -> void: _grunge.draw_rect(Rect2(Vector2.ZERO, _grunge.size), Color.WHITE))
	_grunge.resized.connect(func() -> void: _material.set_shader_parameter("field_size", _grunge.size))
	add_child(_grunge)


## The controls the grunge keeps clear of (at most MAX_HOLES).
func watch(controls: Array[Control]) -> void:
	_watched = controls.slice(0, MAX_HOLES)
	_hole_rects.clear()


## The clear zones last handed to the shader, in the field's coordinates.
func hole_rects() -> Array[Rect2]:
	return _hole_rects


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


func _process(_delta: float) -> void:
	if not is_visible_in_tree():
		return
	var to_field := _grunge.get_global_transform().affine_inverse()
	var rects: Array[Rect2] = []
	for c in _watched:
		if is_instance_valid(c) and c.is_visible_in_tree():
			var r := c.get_global_rect()
			rects.append(Rect2(to_field * r.position, r.size).grow(HOLE_PAD))
	if rects == _hole_rects:
		return
	_hole_rects = rects
	var packed: Array[Vector4] = []
	for r in rects:
		packed.append(Vector4(r.position.x, r.position.y, r.size.x, r.size.y))
	while packed.size() < MAX_HOLES:
		packed.append(Vector4.ZERO)
	_material.set_shader_parameter("holes", packed)
	_material.set_shader_parameter("hole_count", rects.size())


func _draw() -> void:
	Nine.paint(self, PLATE, Rect2(Vector2.ZERO, size).grow(MARGIN / CAPTURE_SCALE), (MARGIN + CORNER) * TEXELS_PER_PIXEL / CAPTURE_SCALE)
