extends Node
## DS2: Building Detail's lamp over a whole panel (docs/ds2-theme.md §4, scripts/bdp_v3_light.gd), with what gives
## its own light left at full strength. The panel is lit by the same lamp at the screen's top-left, falling off
## from NEAR to FAR of the screen's diagonal down to DARKEST, and its text takes back half the darkening, as on
## Building Detail. Unlike Building Detail's single multiply overlay drawn last, the lamp is applied to each
## part as it draws (every canvas item in the panel, its sheets included, parts added later as well):
##   a plain part (steel, plastic, keys, icons, wells)   darkened by the lamp            (shade)
##   text (Label, RichTextLabel, LineEdit)               darkened by half                (text)
##   what gives its own light (LED segments, dot matrix  not darkened at all: its emissive material is
##     dots, meter cells: BdpV3Light.emissive_material)  taken off
##   lamp glows (BdpV3Light.glow_material, additive)     added at full strength          (glow)
## The image is the overlay's for everything but the lights: a multiply overlay over an 8 bit frame cannot give
## back light to a segment that is already at full (a white or bright green LED clamps and dims by up to a fifth
## in the far corner); drawn this way it never dims. A part that brings its own shader keeps it, unlit.
##   LampOverlay.attach(panel)   on (idempotent)
##   LampOverlay.detach(panel)   off: every part gets back the material it had
##   LampOverlay.find(panel)     the panel's lamp, or null

const Light := preload("res://scripts/bdp_v3_light.gd")
const NODE_NAME := "Ds2LampOverlay"
const ORIGINAL := "ds2_lamp_original"

static var _shade: ShaderMaterial
static var _text: ShaderMaterial
static var _glow: ShaderMaterial

var _panel: Control


static func _item_material(strength: float) -> ShaderMaterial:
	var m: ShaderMaterial = Light._material("shader_type canvas_item;\n" + Light._LAMP + """
uniform float strength = 1.0;
void fragment() {
	COLOR.rgb *= pow(lamp(SCREEN_UV, SCREEN_PIXEL_SIZE), strength);
}
""")
	m.set_shader_parameter("strength", strength)
	return m


## A plain part: all of the lamp's darkening.
static func shade_material() -> ShaderMaterial:
	if _shade == null:
		_shade = _item_material(1.0)
	return _shade


## Text: the darkening less the share it takes back (BdpV3Light.TEXT_GIVE_BACK).
static func text_material() -> ShaderMaterial:
	if _text == null:
		_text = _item_material(1.0 - Light.TEXT_GIVE_BACK)
	return _text


## A glow, added at full strength.
static func glow_material() -> ShaderMaterial:
	if _glow == null:
		var shader := Shader.new()
		shader.code = "shader_type canvas_item;\nrender_mode blend_add;\n"
		_glow = ShaderMaterial.new()
		_glow.shader = shader
	return _glow


static func attach(panel: Control, _corner_px: float = 0.0, _grow_px: float = 0.0) -> Node:
	var existing := find(panel)
	if existing != null:
		return existing
	var o: Node = load("res://scripts/ds2/lamp_overlay.gd").new()
	panel.add_child(o)
	return o


static func detach(panel: Control) -> void:
	var o := find(panel)
	if o == null:
		return
	o.call("_unlight_all")
	panel.remove_child(o)
	o.queue_free()


static func find(panel: Node) -> Node:
	return panel.get_node_or_null(NODE_NAME) if panel != null else null


static func is_text(n: Node) -> bool:
	return n is Label or n is RichTextLabel or n is LineEdit


## The material the lamp gives `n`, from the one it has; `n`'s own when the lamp leaves it be.
static func lit_material(n: CanvasItem, had: Material) -> Material:
	if had == null or had == Light.text_material():
		return text_material() if is_text(n) else shade_material()
	if had == Light.emissive_material():
		return null
	if had == Light.glow_material():
		return glow_material()
	return had


func _init() -> void:
	name = NODE_NAME


func _enter_tree() -> void:
	_panel = get_parent() as Control
	if _panel == null:
		return
	get_tree().node_added.connect(_on_node_added)
	_light(_panel)
	for n in _panel.find_children("*", "", true, false):
		_light(n)


func _exit_tree() -> void:
	if get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.disconnect(_on_node_added)


func _on_node_added(n: Node) -> void:
	if _panel != null and _panel.is_ancestor_of(n):
		_light(n)


static func _light(n: Node) -> void:
	var item := n as CanvasItem
	if item == null or item.use_parent_material or item.has_meta(ORIGINAL):
		return
	var had := item.material
	var lit := lit_material(item, had)
	if lit == had:
		return
	item.set_meta(ORIGINAL, [had])
	item.material = lit


func _unlight_all() -> void:
	if _panel == null:
		return
	for n in [_panel] + _panel.find_children("*", "", true, false):
		var item := n as CanvasItem
		if item != null and item.has_meta(ORIGINAL):
			item.material = (item.get_meta(ORIGINAL) as Array)[0]
			item.remove_meta(ORIGINAL)
