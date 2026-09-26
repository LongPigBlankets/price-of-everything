extends Control
## Building Detail v3: a worn steel control plate stacked from the layers that
## tools/button_mockup/cluster.html?export renders into res://assets/ui/bdp_v3/. Every layer of a
## plate shares one frame, so they stack without offsets. The frame is scaled to this control's
## width, and the control keeps the frame's aspect ratio.
##
## Keys are cream keycaps; their navy text is drawn here rather than baked, so values stay live.
## Layout numbers are in the renderer's pixels: Godot captures at CAPTURE_SCALE times logical size.
##
## Draw order: the back layers (plate, shadows, raised icons), the glow (additive, own canvas item),
## then the front layers, the keycaps and their text. Presentation only: it reports key presses
## and holds no game state.

signal key_pressed(key: String)

const TransportTip := preload("res://scripts/ds2/dot_card.gd")
const CAPTURE_SCALE := 1.875
const NAVY := Color("#0b2340")
const DANGER_INK := Color("#8f1f19")
const FONT_BOLD: FontFile = preload("res://assets/fonts/BarlowCondensed-Bold.ttf")
const FONT_SEMI: FontFile = preload("res://assets/fonts/BarlowCondensed-SemiBold.ttf")
## Darkening while a key is held, on top of the pressed render.
const PRESS_TINT := Color(0.93, 0.93, 0.93)

const DIR := "res://assets/ui/bdp_v3/"
static var _textures := {}


## A layer of the v3 renders by name, loaded once.
static func tex(layer: String) -> Texture2D:
	if not _textures.has(layer):
		_textures[layer] = load(DIR + layer + ".png")
	return _textures[layer]


## The frame's size in layout pixels, where its top-left sits relative to this control (a frame can
## reach beyond the control, e.g. above it), and the size of the control itself in layout pixels.
var frame_size := Vector2.ONE
var frame_offset := Vector2.ZERO
var body_size := Vector2.ONE
var _back: Array[Texture2D] = []
var _front: Array[Texture2D] = []
var _glow_texture: Texture2D = null
## name -> {rect: Rect2, face: Rect2, normal: Texture2D, pressed: Texture2D, lines: Array,
##          caret: bool, enabled: bool, tooltip: String}
var _keys := {}
var _key_order: Array[String] = []
var _held := ""
var _hover := ""
var _glow_layer: Control
var _front_layer: Control


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	# The layers are rendered at about twice the size they draw at.
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_glow_layer = _overlay("Glow")
	# Additive, and giving back the darkening of the lamp over the panel: a glow gives off its own light.
	_glow_layer.material = load("res://scripts/bdp_v3_light.gd").glow_material()
	_glow_layer.draw.connect(_draw_glow)
	_front_layer = _overlay("Front")
	_front_layer.draw.connect(_draw_front)


func _overlay(layer_name: String) -> Control:
	var c := Control.new()
	c.name = layer_name
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(c)
	return c


# --- setup (subclasses) ----------------------------------------------------------------------

func set_frame(frame: Vector2, offset: Vector2 = Vector2.ZERO, body: Vector2 = Vector2.ZERO) -> void:
	frame_size = frame
	frame_offset = offset
	body_size = body if body != Vector2.ZERO else frame
	_update_min_height()


func set_layers(back: Array[Texture2D], glow: Texture2D, front: Array[Texture2D]) -> void:
	_back = back
	_glow_texture = glow
	_front = front
	_redraw()


## Adds or replaces a key. `rect` and `face` are in layout pixels; `lines` are dictionaries of
## {text, y (fraction of the face height), size (layout px), semi (bool), colour, align ("left"/"center")}.
func set_key(key: String, rect: Rect2, face: Rect2, normal: Texture2D, pressed: Texture2D, lines: Array,
		caret: bool, enabled: bool, tooltip: String = "", tip: Dictionary = {}) -> void:
	if not _keys.has(key):
		_key_order.append(key)
	# A key with a `tip` shows it on the dot-matrix card the tile view's keys use (dot_card.gd), its
	# words in plain text as the tooltip's text.
	if not tip.is_empty():
		tooltip = TransportTip.plain(tip)
	_keys[key] = {"rect": rect, "face": face, "normal": normal, "pressed": pressed, "lines": lines,
		"caret": caret, "enabled": enabled, "tooltip": tooltip, "tip": tip}
	tooltip_text = " " if tooltip != "" or tooltip_text != "" else ""
	_redraw()


func key_enabled(key: String) -> bool:
	return _keys.has(key) and bool(_keys[key].enabled)


## The key's rect in this control's coordinates.
func key_rect(key: String) -> Rect2:
	if not _keys.has(key):
		return Rect2()
	return _to_local(_keys[key].rect)


# --- layout ----------------------------------------------------------------------------------

func _scale() -> float:
	return size.x / body_size.x if body_size.x > 0.0 and size.x > 0.0 else 1.0 / CAPTURE_SCALE


func _to_local(r: Rect2) -> Rect2:
	var k := _scale()
	return Rect2(r.position * k, r.size * k)


func _update_min_height() -> void:
	var w := size.x if size.x > 0.0 else body_size.x / CAPTURE_SCALE
	custom_minimum_size = Vector2(0.0, roundf(w * body_size.y / body_size.x))


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_update_min_height()
		_redraw()


func _redraw() -> void:
	queue_redraw()
	if _glow_layer != null:
		_glow_layer.queue_redraw()
		_front_layer.queue_redraw()


# --- drawing ---------------------------------------------------------------------------------

func _frame_rect() -> Rect2:
	return Rect2(frame_offset * _scale(), frame_size * _scale())


func _draw() -> void:
	for t in _back:
		draw_texture_rect(t, _frame_rect(), false)


func _draw_glow() -> void:
	if _glow_texture != null:
		_glow_layer.draw_texture_rect(_glow_texture, _frame_rect(), false)


func _draw_front() -> void:
	var c := _front_layer
	for t in _front:
		c.draw_texture_rect(t, _frame_rect(), false)
	for key in _key_order:
		var k: Dictionary = _keys[key]
		var held := key == _held and bool(k.enabled)
		var tex: Texture2D = k.pressed if held else k.normal
		c.draw_texture_rect(tex, _frame_rect(), false, PRESS_TINT if held else Color.WHITE)
		_draw_key_text(c, k)


func _draw_key_text(c: Control, k: Dictionary) -> void:
	var s := _scale()
	var face: Rect2 = k.face
	var caret_room := 38.0 if bool(k.caret) else 20.0
	for line: Dictionary in k.lines:
		var font: Font = FONT_SEMI if bool(line.get("semi", false)) else FONT_BOLD
		var text := str(line.get("text", ""))
		var max_w := (face.size.x - caret_room) * s
		var font_size := _fit(font, text, maxi(8, roundi(float(line.get("size", 30)) * s)), max_w)
		var cy := (face.position.y + face.size.y * float(line.get("y", 0.5))) * s
		var baseline := cy + (font.get_ascent(font_size) - font.get_descent(font_size)) * 0.5
		var colour: Color = line.get("colour", NAVY)
		var x := (face.position.x + 10.0) * s
		var align := HORIZONTAL_ALIGNMENT_LEFT
		var width := -1.0
		if str(line.get("align", "left")) == "center":
			x = face.position.x * s
			width = face.size.x * s
			align = HORIZONTAL_ALIGNMENT_CENTER
		c.draw_string(font, Vector2(x, baseline), text, align, width, font_size, colour)
	if bool(k.caret):
		var caret_size := roundi(face.size.y * 0.62 * s)
		var cy2 := (face.position.y + face.size.y * 0.5 - 2.0) * s
		var base2 := cy2 + (FONT_SEMI.get_ascent(caret_size) - FONT_SEMI.get_descent(caret_size)) * 0.5
		var cw := FONT_SEMI.get_string_size("›", HORIZONTAL_ALIGNMENT_LEFT, -1, caret_size).x
		c.draw_string(FONT_SEMI, Vector2((face.end.x - 11.0) * s - cw * 0.5, base2), "›", HORIZONTAL_ALIGNMENT_LEFT, -1, caret_size, NAVY)


## The largest size up to `size` at which `text` fits in `max_w`.
static func _fit(font: Font, text: String, font_size: int, max_w: float) -> int:
	var fs := font_size
	while fs > 8 and font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > max_w:
		fs -= 1
	return fs


# --- input -----------------------------------------------------------------------------------

func _key_at(p: Vector2) -> String:
	for key in _key_order:
		if key_rect(key).has_point(p):
			return key
	return ""


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var over := _key_at((event as InputEventMouseMotion).position)
		if over != _hover:
			_hover = over
			mouse_default_cursor_shape = Control.CURSOR_ARROW if over == "" \
				else (Control.CURSOR_POINTING_HAND if key_enabled(over) else Control.CURSOR_FORBIDDEN)
	elif event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var mb := event as InputEventMouseButton
		var at := _key_at(mb.position)
		if mb.pressed:
			if at != "" and key_enabled(at):
				_held = at
				_redraw()
				accept_event()
		elif _held != "":
			var released_on := _held
			_held = ""
			_redraw()
			accept_event()
			if at == released_on:
				key_pressed.emit(released_on)


func _get_tooltip(at_position: Vector2) -> String:
	var key := _key_at(at_position)
	return str(_keys[key].tooltip) if key != "" else ""


func _make_custom_tooltip(_for_text: String) -> Object:
	var key := _key_at(get_local_mouse_position())
	var tip: Dictionary = _keys[key].get("tip", {}) if key != "" else {}
	return TransportTip.make(tip, self) if not tip.is_empty() else null
