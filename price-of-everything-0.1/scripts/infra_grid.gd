extends GridContainer
## Presentational infrastructure grid. Renders a set of slot dicts (each an icon
## button + label) and reports interactions via signals. ALL data lookup and the
## build action stay in tile_info_panel — this widget never touches Catalog /
## MatchState / BuildMode; it only renders what set_slots() is given and emits
## back. Extracted from tile_info_panel.gd (Slice B).
##
## Slot dict shape (built by the panel):
##   {
##     cell_size: Vector2, icon: Texture2D, state: "exists"|"add"|"unavailable",
##     button_tooltip: String, display_label: String, label_tooltip: String,
##     max_label_lines: int,
##     instance: Dictionary,      # when state == "exists"
##     internal_name: String,     # when state == "add"
##   }

signal slot_activated(instance: Dictionary)   # an existing infrastructure building was clicked
signal add_requested(internal_name: String)   # an empty "add" slot was pressed

const GRID_COLUMNS := 3
const H_SEPARATION := 8
const V_SEPARATION := 4
const BUTTON_SIZE := Vector2(42, 42)
const LABEL_FONT_SIZE := 14

func set_slots(slots: Array) -> void:
	for child in get_children():
		child.queue_free()
	columns = GRID_COLUMNS
	add_theme_constant_override("h_separation", H_SEPARATION)
	add_theme_constant_override("v_separation", V_SEPARATION)
	for slot in slots:
		add_child(_make_cell(slot))

func _make_cell(slot: Dictionary) -> Control:
	var cell := VBoxContainer.new()
	cell.custom_minimum_size = slot.get("cell_size", Vector2.ZERO)
	cell.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	cell.add_theme_constant_override("separation", 4)

	var button := Button.new()
	button.custom_minimum_size = BUTTON_SIZE
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	button.focus_mode = Control.FOCUS_NONE
	button.expand_icon = true
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
	button.text = ""
	button.icon = slot.get("icon", null)
	button.tooltip_text = str(slot.get("button_tooltip", ""))

	match str(slot.get("state", "")):
		"exists":
			var inst: Dictionary = slot.get("instance", {})
			button.pressed.connect(func() -> void: slot_activated.emit(inst))
		"add":
			_style_add_button(button, true)
			var internal_name := str(slot.get("internal_name", ""))
			button.pressed.connect(func() -> void: add_requested.emit(internal_name))
		_:  # "unavailable"
			_style_add_button(button, false)
			button.disabled = true
	cell.add_child(button)

	var name_label := Label.new()
	var max_label_lines := int(slot.get("max_label_lines", 2))
	name_label.text = str(slot.get("display_label", ""))
	var label_tooltip := str(slot.get("label_tooltip", ""))
	if label_tooltip != "":
		name_label.tooltip_text = label_tooltip
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_OFF if max_label_lines == 1 else TextServer.AUTOWRAP_WORD_SMART
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.max_lines_visible = max_label_lines
	name_label.clip_text = true
	name_label.theme_type_variation = &"Caption"
	name_label.add_theme_color_override("font_color", DS.PALETTE.ACCENT)
	name_label.custom_minimum_size = Vector2(0, 22 if max_label_lines == 1 else 36)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cell.add_child(name_label)
	return cell

func _style_add_button(button: Button, enabled: bool) -> void:
	var base: Color = DS.PALETTE.ACTION_BLUE if enabled else DS.PALETTE.BG_INSET
	var hover: Color = DS.PALETTE.ACTION_BLUE_HOVER if enabled else DS.PALETTE.BG_INSET
	button.add_theme_stylebox_override("normal", _button_style(base))
	button.add_theme_stylebox_override("hover", _button_style(hover))
	button.add_theme_stylebox_override("pressed", _button_style(hover))
	button.add_theme_stylebox_override("disabled", _button_style(DS.PALETTE.BG_INSET))

func _button_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.content_margin_left = 6
	style.content_margin_top = 6
	style.content_margin_right = 6
	style.content_margin_bottom = 6
	return style
