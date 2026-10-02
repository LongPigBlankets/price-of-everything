extends Control
## Supply chain board: what is shown on it. A cream key in the bottom right corner, an eye with
## a cog at its corner, opens a small dark plate of tickboxes above it. Each tickbox is one of
## the board's `show` switches; `changed` says one was flipped.

signal changed(key: String, on: bool)

const CreamKey := preload("res://scripts/ds2/cream_key.gd")
const Section := preload("res://scripts/bdp_v3_section.gd")
const Plate := preload("res://scripts/bdp_v3_plate.gd")

const NAVY := Color("#0b2340")
const CREAM := Color("#efe6cd")
const ROWS := [
	["decor", "See decorative buildings"], ["trees", "See trees"], ["roads", "See roads"],
	["pipes", "See pipes"], ["reinf_pipes", "See reinforced pipes"], ["cables", "See cables"],
	["goods", "See goods on tiles"], ["pollution", "See pollution"],
]
const MARGIN := 18.0
## The key is drawn in three slices across. This is its two end caps and no middle: the
## smallest it can be, and near enough square.
const KEY_SIDE := (2.0 * 60.0 - 2.0 * 16.0) / 1.875
const BOX := 20.0

var key: Button
var panel: MarginContainer
var _state: Dictionary = {}
var _boxes: Dictionary = {}


## The cog-on-an-eye icon, printed navy on the key's face.
class Icon extends Control:
	func _draw() -> void:
		var ink := Color("#0b2340")
		var c := size * 0.5 + Vector2(-2.0, -2.0)
		var w := size.x * 0.27
		var h := size.y * 0.17
		var lid := PackedVector2Array()
		for i in range(21):
			var t := float(i) / 20.0
			lid.append(c + Vector2(lerpf(-w, w, t), -sin(t * PI) * h))
		for i in range(21):
			var t := float(i) / 20.0
			lid.append(c + Vector2(lerpf(w, -w, t), sin(t * PI) * h))
		draw_polyline(lid, ink, 2.0, true)
		draw_circle(c, h * 0.62, ink, true, -1.0, true)
		# The cog, on a cream ground of its own so it reads over the eye's corner.
		var g := c + Vector2(w * 0.78, h * 1.25)
		var r := size.x * 0.11
		draw_circle(g, r + 3.6, Color("#efe6cd"), true, -1.0, true)
		for i in range(8):
			var d := Vector2.from_angle(TAU * float(i) / 8.0)
			draw_line(g + d * r * 0.7, g + d * (r + 2.2), ink, 2.4, true)
		draw_circle(g, r, ink, true, -1.0, true)
		draw_circle(g, r * 0.42, Color("#efe6cd"), true, -1.0, true)


## A tickbox: a small cream cap in a dark bezel, a navy tick printed on it when it is on.
class Tick extends Button:
	var on := true:
		set(v):
			on = v
			queue_redraw()

	func _init() -> void:
		flat = true
		focus_mode = Control.FOCUS_NONE
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		for state in ["normal", "hover", "pressed", "disabled", "focus", "hover_pressed"]:
			add_theme_stylebox_override(state, StyleBoxEmpty.new())
		alignment = HORIZONTAL_ALIGNMENT_LEFT

	func _draw() -> void:
		var side := 20.0
		var box := Rect2(0.0, (size.y - side) * 0.5, side, side)
		draw_rect(box.grow(1.5), Color("#1a1d24"))
		draw_rect(box, Color("#efe6cd") if on else Color("#b9b19a"))
		draw_rect(Rect2(box.position, Vector2(side, 2.0)), Color(1.0, 1.0, 1.0, 0.35))
		if on:
			var a := box.position + Vector2(4.5, 10.5)
			var b := box.position + Vector2(8.5, 14.5)
			var c := box.position + Vector2(15.5, 5.5)
			draw_line(a, b, Color("#0b2340"), 2.6, true)
			draw_line(b, c, Color("#0b2340"), 2.6, true)
		var font: Font = get_theme_font("font")
		var fs := 14
		draw_string(font, Vector2(side + 10.0, size.y * 0.5 + (font.get_ascent(fs) - font.get_descent(fs)) * 0.5),
			text_shown, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, DS.PALETTE.TEXT)

	var text_shown := ""


func _init() -> void:
	name = "Visibility"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


## `state` is the board's switches, key -> bool; the tickboxes show it and write to it.
func setup(state: Dictionary) -> void:
	_state = state
	key = CreamKey.make("VisibilityKey", "", "", KEY_SIDE)
	var tall: float = CreamKey.height_for()
	key.tooltip_text = "What the board shows"
	key.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	key.offset_left = -MARGIN - KEY_SIDE
	key.offset_top = -MARGIN - tall
	key.offset_right = -MARGIN
	key.offset_bottom = -MARGIN
	var icon := Icon.new()
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	key.add_child(icon)
	key.pressed.connect(func() -> void: set_open(not panel.visible))
	add_child(key)

	panel = Section.new()
	panel.name = "VisibilityPanel"
	panel.set("style", "slab")
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var content: VBoxContainer = panel.get("content")
	content.add_theme_constant_override("separation", 6)
	for row in ROWS:
		var tick := Tick.new()
		tick.name = "Show_" + str(row[0])
		tick.text_shown = str(row[1])
		tick.on = bool(_state.get(row[0], true))
		tick.custom_minimum_size = Vector2(BOX + 10.0 + Plate.FONT_SEMI.get_string_size(str(row[1]),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x + 30.0, 26.0)
		var id := str(row[0])
		tick.pressed.connect(func() -> void:
			tick.on = not tick.on
			_state[id] = tick.on
			changed.emit(id, tick.on))
		content.add_child(tick)
		_boxes[id] = tick
	add_child(panel)
	panel.visible = false
	panel.resized.connect(_place)
	resized.connect(_place)
	_place()


func set_open(open: bool) -> void:
	panel.visible = open
	key.set("chosen", open)
	_place()


func is_open() -> bool:
	return panel.visible


## The plate stands above the key, its right edge on the key's.
func _place() -> void:
	if panel == null:
		return
	var want := panel.get_combined_minimum_size()
	panel.size = want
	panel.position = Vector2(size.x - MARGIN - want.x, size.y - MARGIN - KEY_SIDE - 10.0 - want.y)
