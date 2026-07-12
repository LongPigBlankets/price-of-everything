extends Control
## Hall of Records — a compact sibling of the New Game screen. Slides in over the
## main-menu goods board and lists every recorded VICTORY (date + victory name),
## newest first; losses are never recorded. Each entry is a clickable row that
## expands to show the win's turn, secured-track count and epithet.
## Pure UI over PlayerProfile.get_wins(); emits `back_requested`; the main menu
## owns visibility. Referenced from main_menu via a preload const (no class_name).

signal back_requested

const NAVY := Color(0, 0.07, 0.14)
const OFF_WHITE := Color(0.995234, 0.930806, 0.763265)

var _rows_box: VBoxContainer


func _ready() -> void:
	_build()


func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		back_requested.emit()
		get_viewport().set_input_as_handled()


func refresh() -> void:
	if _rows_box == null:
		return
	for c in _rows_box.get_children():
		c.queue_free()
	var wins: Array = PlayerProfile.get_wins()
	if wins.is_empty():
		var empty := Label.new()
		empty.text = "No victories recorded yet — win a game to enter the records."
		empty.theme_type_variation = &"Caption"
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_rows_box.add_child(empty)
		return
	for win in wins:
		_rows_box.add_child(_make_win_row(win))


func _build() -> void:
	# Navy plate matching the menu frame.
	var plate := Panel.new()
	plate.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var sb := StyleBoxFlat.new()
	sb.bg_color = NAVY
	sb.border_color = OFF_WHITE
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(22)
	plate.add_theme_stylebox_override("panel", sb)
	add_child(plate)

	# Back button, top-right.
	var back := Button.new()
	back.text = "Back"
	back.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	back.offset_left = -120
	back.offset_top = 24
	back.offset_right = -24
	back.pressed.connect(func() -> void: back_requested.emit())
	plate.add_child(back)

	# Content column: banner up top, the record list scrolling beneath.
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 64)
	margin.add_theme_constant_override("margin_right", 64)
	margin.add_theme_constant_override("margin_top", 28)
	margin.add_theme_constant_override("margin_bottom", 28)
	plate.add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	margin.add_child(col)

	var banner := Label.new()
	banner.text = "HALL OF RECORDS"
	banner.theme_type_variation = &"Title"
	banner.add_theme_font_size_override("font_size", 56)
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(banner)

	var blurb := Label.new()
	blurb.text = "Every victory, entered on the day it was won."
	blurb.theme_type_variation = &"Caption"
	blurb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(blurb)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)

	_rows_box = VBoxContainer.new()
	_rows_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows_box.add_theme_constant_override("separation", 8)
	scroll.add_child(_rows_box)

	refresh()


# One record: a clickable row ("date — victory name") that expands a detail line.
func _make_win_row(win: Dictionary) -> Control:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 2)

	var row := Button.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.custom_minimum_size = Vector2(0, 44)
	row.alignment = HORIZONTAL_ALIGNMENT_LEFT
	row.text = "%s    —    %s" % [str(win.get("date", "?")), str(win.get("title", "Victory"))]
	row.add_theme_font_size_override("font_size", 18)
	box.add_child(row)

	var detail := Label.new()
	var secured := int(win.get("secured", 0))
	detail.text = "Won on turn %d · %d track%s secured. %s" % [
		int(win.get("turn", 0)), secured, "" if secured == 1 else "s", str(win.get("epithet", ""))]
	detail.theme_type_variation = &"Caption"
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.visible = false
	box.add_child(detail)

	row.pressed.connect(func() -> void: detail.visible = not detail.visible)
	return box
