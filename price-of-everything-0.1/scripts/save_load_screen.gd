extends Control
class_name SaveLoadScreen
## Full-screen modal for loading or saving games: a dimmed backdrop with a black
## rounded-corner panel inset 80px from every screen edge. LOAD mode lists the
## save slots (pick one, hit the "Load Game" CTA); SAVE mode takes a name and
## writes the slot on "Save Game". Used by the main menu and the in-game pause
## menu — closing (Cancel / Esc / PanelStack) frees the node.

enum Mode { LOAD, SAVE }

const EDGE_OFFSET := 80.0
const PANEL_BLACK := Color(0.03, 0.03, 0.045)
const OFF_WHITE := Color(0.995234, 0.930806, 0.763265)
const ROW_SELECTED := Color(0.16, 0.22, 0.30)

var mode: int = Mode.LOAD

var _selected_slot := ""
var _cta: Button
var _error_label: Label
var _name_edit: LineEdit


static func open(parent: Node, screen_mode: int) -> SaveLoadScreen:
	var screen := SaveLoadScreen.new()
	screen.mode = screen_mode
	parent.add_child(screen)
	return screen


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP  # modal: swallow clicks behind the panel

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var panel := Panel.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = EDGE_OFFSET
	panel.offset_top = EDGE_OFFSET
	panel.offset_right = -EDGE_OFFSET
	panel.offset_bottom = -EDGE_OFFSET
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL_BLACK
	sb.border_color = OFF_WHITE
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(24)
	panel.add_theme_stylebox_override("panel", sb)
	add_child(panel)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 40)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "LOAD GAME" if mode == Mode.LOAD else "SAVE GAME"
	title.theme_type_variation = &"Title"
	title.add_theme_color_override("font_color", OFF_WHITE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	_error_label = Label.new()
	_error_label.add_theme_color_override("font_color", Color(0.9, 0.3, 0.3))
	_error_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_error_label.hide()
	vbox.add_child(_error_label)

	if mode == Mode.LOAD:
		_build_load_body(vbox)
	else:
		_build_save_body(vbox)

	# Cancel bottom-left, CTA bottom-right.
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 16)
	vbox.add_child(buttons)
	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.custom_minimum_size = Vector2(160, 54)
	cancel.pressed.connect(hide)
	buttons.add_child(cancel)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(spacer)
	_cta = Button.new()
	_cta.text = "Load Game" if mode == Mode.LOAD else "Save Game"
	_cta.theme_type_variation = &"Primary"
	_cta.custom_minimum_size = Vector2(220, 54)
	_cta.disabled = true
	_cta.pressed.connect(_on_cta_pressed)
	buttons.add_child(_cta)

	PanelStack.push(self)
	visibility_changed.connect(_on_visibility_changed)


func _build_load_body(vbox: VBoxContainer) -> void:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 6)
	scroll.add_child(rows)

	var slots: Array = SaveLoad.list_slots()
	if slots.is_empty():
		var empty := Label.new()
		empty.text = "No saves yet."
		empty.add_theme_color_override("font_color", OFF_WHITE)
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		rows.add_child(empty)
		return

	var group := ButtonGroup.new()
	for s in slots:
		var row := Button.new()
		row.toggle_mode = true
		row.button_group = group
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.custom_minimum_size = Vector2(0, 48)
		row.text = "%s      turn %d   ·   £%.2f      %s" % [
			str(s.slot), int(s.turn), float(s.money), str(s.timestamp)]
		var selected_sb := StyleBoxFlat.new()
		selected_sb.bg_color = ROW_SELECTED
		selected_sb.set_corner_radius_all(10)
		row.add_theme_stylebox_override("pressed", selected_sb)
		row.toggled.connect(_on_row_toggled.bind(str(s.slot)))
		rows.add_child(row)


func _build_save_body(vbox: VBoxContainer) -> void:
	var hint := Label.new()
	hint.text = "Name your save:"
	hint.theme_type_variation = &"Section"
	hint.add_theme_color_override("font_color", OFF_WHITE)
	vbox.add_child(hint)

	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "e.g. before_the_big_loan"
	_name_edit.custom_minimum_size = Vector2(0, 54)
	_name_edit.text_changed.connect(func(text: String) -> void:
		_cta.disabled = text.strip_edges() == ""
	)
	_name_edit.text_submitted.connect(func(_text: String) -> void:
		if not _cta.disabled:
			_on_cta_pressed()
	)
	vbox.add_child(_name_edit)
	_name_edit.call_deferred("grab_focus")

	# Push the buttons row to the bottom like the load list does.
	var filler := Control.new()
	filler.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(filler)


func _on_row_toggled(pressed: bool, slot: String) -> void:
	if pressed:
		_selected_slot = slot
		_cta.disabled = false


func _on_cta_pressed() -> void:
	if mode == Mode.LOAD:
		_do_load()
	else:
		_do_save()


func _do_load() -> void:
	if _selected_slot == "":
		return
	var loading := LoadingScreen.show_global(get_tree())
	var err: String = SaveLoad.load_slot(_selected_slot)
	if err != "":
		loading.queue_free()
		_show_error(err)
	# On success the scene changes; the loading screen dismisses itself once the
	# map is ready and this whole screen goes down with the old scene.


func _do_save() -> void:
	var slot := _name_edit.text.strip_edges()
	if slot == "":
		return
	var err: String = SaveLoad.save_slot(slot)
	if err != "":
		_show_error(err)
		return
	MatchState.request_toast("Game saved as '%s'." % slot, "success")
	hide()


func _show_error(message: String) -> void:
	_error_label.text = message
	_error_label.show()


func _on_visibility_changed() -> void:
	# Hidden by Cancel, Esc, or PanelStack.close_top(): this screen is built per
	# open, so it frees rather than lingering invisible.
	if not visible:
		PanelStack.remove(self)
		queue_free()


func _unhandled_input(event: InputEvent) -> void:
	# Self-contained Esc so the screen also closes in the main menu, where no
	# world_map/PanelStack key handling exists.
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		hide()
		get_viewport().set_input_as_handled()
