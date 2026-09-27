extends Control
## The People panel in DS2 (docs/people-ds2-plan.md), built into the panel (scripts/people_panel.gd) while
## UiPrefs.use_people_ds2 is on. With the switch off the panel builds today's look itself.
##
## The shell is a painted steel cabinet in machinery green (people_backing: three bolted sheets, two hinges down
## the left), one width for both tabs. A fixed head: the PEOPLE nameplate (the tile view's black enamel, the name
## printed white), the two latching tab keys on their key bed (the open one latched down), Close. Under it the
## ribbed seam, where the open tab's body scrolls on Building Detail's steel rail. The lamp lights the panel part
## by part (scripts/ds2/lamp_overlay.gd), its sheets and parts added later too, as Building Detail's.

signal close_requested
## A press or drag on the head, which moves the panel as the v2 title bar does.
signal drag_input(event: InputEvent)

const Parts := preload("res://scripts/people_ds2/parts.gd")
const LatchKey := preload("res://scripts/ds2/latch_key.gd")
const Key := preload("res://scripts/bdp_v3_key.gd")
const Seam := preload("res://scripts/bdp_v3_seam.gd")
const LampOverlay := preload("res://scripts/ds2/lamp_overlay.gd")
const Nine := preload("res://scripts/bdp_v3_nine.gd")
const UIFonts := preload("res://scripts/ui_fonts.gd")
const AdvisorsTab := preload("res://scripts/people_ds2/advisors_ds2.gd")
const LabourTab := preload("res://scripts/people_ds2/labour_ds2.gd")

const TABS := ["Advisors", "Labour"]
## From layout.json (people_backing), in layout px: the render's shadow room and the foot drawn whole.
const BACKING_MARGIN := 24.0
const BACKING_FOOT := 420.0
## The content's room inside the cabinet's edge (clear of its hinges and its right hand screws).
const MARGIN_X := 26
const MARGIN_TOP := 18
const MARGIN_BOTTOM := 20
## The nameplate (the tile view's tile_nameplate: 14 layout px of margin, 60 kept at each end) and its print.
const NAMEPLATE: Texture2D = preload("res://assets/ui/bdp_v3/tile_nameplate.png")
const NAMEPLATE_MARGIN := 14.0
const NAMEPLATE_CAP := 60.0
const NAMEPLATE_SIZE := Vector2(132, 38)
const NAME_INK := Color("#eef1f5")
## The tile view's key bed round the tab keys, and the keys' width.
const KEYBED: Texture2D = preload("res://assets/ui/bdp_v3/tile_keybed.png")
const KEYBED_MARGIN := 14.0
const KEYBED_CORNER := 40.0
const TAB_KEY_W := 146.0
const CLOSE_KEY_PX := 40.0

var _keys: Array = []
var _bodies: Array[Control] = []
var _tab := 0
var _margin: MarginContainer
var _seam: Control
var _seam_slot: Control


func _init() -> void:
	name = "PeopleDs2"
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _ready() -> void:
	if DS and DS.theme:
		theme = DS.theme
	_margin = MarginContainer.new()
	_margin.name = "Margin"
	_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_margin.add_theme_constant_override("margin_left", MARGIN_X)
	_margin.add_theme_constant_override("margin_right", MARGIN_X)
	_margin.add_theme_constant_override("margin_top", MARGIN_TOP)
	_margin.add_theme_constant_override("margin_bottom", MARGIN_BOTTOM)
	add_child(_margin)
	var col := VBoxContainer.new()
	col.name = "Cabinet"
	col.add_theme_constant_override("separation", 10)
	_margin.add_child(col)
	col.add_child(_head())
	# The seam's place in the column; the strip itself is drawn over the body (it reaches down over its top).
	_seam_slot = Control.new()
	_seam_slot.name = "SeamSlot"
	_seam_slot.custom_minimum_size.y = Seam.strip_height()
	_seam_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_seam_slot)
	var host := Control.new()
	host.name = "Bodies"
	host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(host)
	for script: GDScript in [AdvisorsTab, LabourTab]:
		var body: Control = script.new()
		body.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		host.add_child(body)
		_bodies.append(body)
	_seam = Seam.new()
	_seam.name = "PeopleSeam"
	_seam.set("outset", MARGIN_X - 4.0 / Parts.LAYOUT)
	add_child(_seam)
	_seam_slot.item_rect_changed.connect(_place_seam)
	show_tab(_tab)
	LampOverlay.attach(self)


func _place_seam() -> void:
	if _seam == null or _seam_slot == null:
		return
	_seam.position = _seam_slot.get_global_rect().position - get_global_rect().position
	_seam.size = _seam_slot.size


## The cabinet: its sheets cropped from the top, the foot with its lower hinge drawn whole.
func _draw() -> void:
	Parts.crop_v(self, Parts.tex("people_backing"), Rect2(Vector2.ZERO, size), BACKING_MARGIN, BACKING_FOOT)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


# --- the head ------------------------------------------------------------------------------------

func _head() -> HBoxContainer:
	var head := HBoxContainer.new()
	head.name = "Head"
	head.add_theme_constant_override("separation", 22)
	head.mouse_filter = Control.MOUSE_FILTER_STOP
	head.mouse_default_cursor_shape = Control.CURSOR_MOVE
	head.gui_input.connect(func(e: InputEvent) -> void: drag_input.emit(e))
	var plate := Control.new()
	plate.name = "Nameplate"
	plate.custom_minimum_size = NAMEPLATE_SIZE
	plate.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	plate.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	plate.mouse_filter = Control.MOUSE_FILTER_PASS
	plate.draw.connect(func() -> void: _draw_nameplate(plate))
	head.add_child(plate)
	var bed := PanelContainer.new()
	bed.name = "TabKeyBed"
	var pad := StyleBoxEmpty.new()
	pad.content_margin_left = 10
	pad.content_margin_right = 10
	pad.content_margin_top = 9
	pad.content_margin_bottom = 10
	bed.add_theme_stylebox_override("panel", pad)
	bed.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bed.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	bed.draw.connect(func() -> void:
		Nine.paint(bed, KEYBED, Rect2(Vector2.ZERO, bed.size).grow(KEYBED_MARGIN / Parts.LAYOUT), (KEYBED_MARGIN + KEYBED_CORNER) * Parts.TEXELS))
	head.add_child(bed)
	var keys := HBoxContainer.new()
	keys.add_theme_constant_override("separation", 10)
	bed.add_child(keys)
	for i in TABS.size():
		var k: Control = LatchKey.new()
		k.name = "TabKey_%s" % TABS[i]
		k.set("text", TABS[i])
		k.custom_minimum_size.x = TAB_KEY_W
		k.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		var at := i
		k.connect("pressed", func() -> void: show_tab(at))
		keys.add_child(k)
		_keys.append(k)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(gap)
	var close: TextureButton = Key.make("close", CLOSE_KEY_PX)
	close.name = "CloseKey"
	close.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	close.pressed.connect(func() -> void: close_requested.emit())
	head.add_child(close)
	return head


## The tile view's black enamel nameplate, three-sliced, PEOPLE printed white in Bebas, centred.
func _draw_nameplate(n: Control) -> void:
	Parts.draw_h3(n, NAMEPLATE, Rect2(Vector2.ZERO, n.size), NAMEPLATE_MARGIN, NAMEPLATE_CAP - NAMEPLATE_MARGIN)
	var font: Font = UIFonts.BEBAS
	var fs := 30
	var text := "PEOPLE"
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var base := n.size.y * 0.5 + (font.get_ascent(fs) - font.get_descent(fs)) * 0.5
	var x := (n.size.x - w) * 0.5
	n.draw_string(font, Vector2(x, base - 1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0, 0.7))
	n.draw_string(font, Vector2(x, base), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, NAME_INK)


# --- tabs ----------------------------------------------------------------------------------------

## Shows tab `i` (0 Advisors, 1 Labour), its key latched and the other's up.
func show_tab(i: int) -> void:
	_tab = clampi(i, 0, TABS.size() - 1)
	for j in _bodies.size():
		_bodies[j].visible = j == _tab
		_keys[j].set("latched", j == _tab)


func current_tab() -> int:
	return _tab


func body(i: int) -> Control:
	return _bodies[i]
