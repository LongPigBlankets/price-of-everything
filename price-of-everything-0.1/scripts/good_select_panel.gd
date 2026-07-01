extends PanelContainer
# A left-docked panel of tickbox rows (framed market-style icon + good name +
# checkbox). Reused for Producing / Consuming (each ticked good is highlighted on
# the map) and Deposits (default all ticked; un-ticking hides that deposit). A
# search bar filters the list; Deposits also gets a "Clear all" row.

const UIHelpers := preload("res://scripts/ui_helpers.gd")
const HEADER_HEIGHT := 40.0
const ROW_HEIGHT := 72
const ICON_FRAME_SIZE := 64
const SEARCH_HEIGHT := 30
const CLEAR_ROW_HEIGHT := 30
const DEPOSITS_EXTRA_HEIGHT := 30      # taller panel to fit the Clear-all row
const HINT_BOTTOM_MARGIN := 135.0      # instruction panel sits this far above screen bottom
const HINT_HEIGHT := 40.0

var _kind := ""                 # "producing" / "consuming" / "deposits"
var _title: Label = null
var _content: VBoxContainer = null
var _search: LineEdit = null
var _clear_row: HBoxContainer = null
var _row_meta := {}             # good_id -> {row: HBoxContainer, name: String, cb: CheckBox}
var _base_offset_bottom := 0.0
var _hint_holder: Control = null
var _hint_label: Label = null
var _dragging := false
var _drag_offset := Vector2.ZERO

func _ready() -> void:
	visible = false
	_base_offset_bottom = offset_bottom
	_build_shell()
	MapMode.selections_changed.connect(func(_m, _s) -> void: _sync())
	MapMode.mode_cleared.connect(_sync)
	MapMode.deposit_filter_changed.connect(_sync)
	visibility_changed.connect(_on_visibility_changed)

func _build_shell() -> void:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	add_child(margin)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	margin.add_child(vb)
	# Header: title + close.
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	vb.add_child(header)
	_title = Label.new()
	_title.theme_type_variation = &"Title"
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_title)
	var close := Button.new()
	close.text = "X"
	close.custom_minimum_size = Vector2(20, 20)
	close.add_theme_font_size_override("font_size", 20)
	close.pressed.connect(hide)
	header.add_child(close)
	vb.add_child(HSeparator.new())
	# Search bar, anchored at the top of the list (all kinds).
	_search = LineEdit.new()
	_search.placeholder_text = "Search…"
	_search.clear_button_enabled = true
	_search.custom_minimum_size = Vector2(0, SEARCH_HEIGHT)
	_search.text_changed.connect(_on_search_changed)
	vb.add_child(_search)
	# Scrolling tick list.
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(scroll)
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 4)
	scroll.add_child(_content)
	# Clear-all row (Deposits only) — a fixed bottom row with an underlined link.
	_clear_row = HBoxContainer.new()
	_clear_row.custom_minimum_size = Vector2(0, CLEAR_ROW_HEIGHT)
	_clear_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_clear_row.visible = false
	var clear_btn := LinkButton.new()
	clear_btn.text = "Clear all"
	clear_btn.underline = LinkButton.UNDERLINE_MODE_ALWAYS
	clear_btn.pressed.connect(_on_clear_all)
	_clear_row.add_child(clear_btn)
	vb.add_child(_clear_row)

## Open the panel for a kind: "producing", "consuming" or "deposits".
func open_for(kind: String) -> void:
	if kind != _kind:
		_kind = kind
		if _search != null:
			_search.text = ""
		_build_rows()
	_title.text = kind.capitalize()
	# Deposits gets a Clear-all row, so make the panel a little taller for it.
	_clear_row.visible = _kind == "deposits"
	offset_bottom = _base_offset_bottom + (DEPOSITS_EXTRA_HEIGHT if _kind == "deposits" else 0)
	_sync()
	show()
	PanelStack.push(self)

func _build_rows() -> void:
	for c in _content.get_children():
		c.queue_free()
	_row_meta.clear()
	for good in _goods_for_kind():
		var gid := str(good.get("id", ""))
		if gid == "":
			continue
		var disp := str(good.get("display_name", gid))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		row.custom_minimum_size = Vector2(0, ROW_HEIGHT)
		row.add_child(UIHelpers.make_framed_good_icon(gid, str(good.get("internal_name", "")), ICON_FRAME_SIZE))
		var name_lbl := Label.new()
		name_lbl.text = disp
		name_lbl.theme_type_variation = &"Body"
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(name_lbl)
		var cb := UIHelpers.make_custom_checkbox()
		cb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		cb.toggled.connect(_on_toggled.bind(gid))
		row.add_child(cb)
		_content.add_child(row)
		_row_meta[gid] = {"row": row, "name": disp, "cb": cb}

func _goods_for_kind() -> Array:
	if _kind == "deposits":
		var out: Array = []
		for g in Catalog.all_goods():
			if str(g.get("good_type", "")) == "raw" and str(g.get("internal_name", "")) != "pure_water":
				out.append(g)
		return out
	return Catalog.all_goods()

func _picker_mode() -> int:
	return MapMode.Mode.TILES_CONSUMING if _kind == "consuming" else MapMode.Mode.TILES_PRODUCING

func _on_toggled(pressed: bool, good_id: String) -> void:
	if _kind == "deposits":
		MapMode.set_deposit_hidden(good_id, not pressed)  # ticked = visible
	else:
		MapMode.toggle_selection(_picker_mode(), good_id)
	# _sync (via the MapMode signal) re-applies the authoritative tick states.

func _on_search_changed(query: String) -> void:
	var q := query.strip_edges().to_lower()
	for gid in _row_meta:
		var meta: Dictionary = _row_meta[gid]
		var row: Control = meta["row"]
		row.visible = q == "" or str(meta["name"]).to_lower().contains(q)

func _on_clear_all() -> void:
	if _kind == "deposits":
		MapMode.hide_all_deposits(_row_meta.keys())  # un-tick every deposit
	else:
		MapMode.clear_all()

func _sync() -> void:
	# For pickers, once MAX_SELECTIONS goods are ticked the rest are disabled so
	# the player can't exceed the cap. Deposits are a visibility filter, no cap.
	var mine := MapMode.current_mode == _picker_mode()
	var at_cap := mine and MapMode.selections.size() >= MapMode.MAX_SELECTIONS
	for gid in _row_meta:
		var cb: CheckBox = _row_meta[gid]["cb"]
		if _kind == "deposits":
			cb.set_pressed_no_signal(not MapMode.is_deposit_hidden(gid))
			cb.disabled = false
		else:
			var selected := mine and MapMode.is_selected(gid)
			cb.set_pressed_no_signal(selected)
			cb.disabled = at_cap and not selected
	_update_hint()

# ── Bottom-centre instruction panel (Producing / Consuming) ──────────────────
# A single-row, content-width panel 150px above the screen bottom. Shows while the
# picker list is open or a producing/consuming selection is active.
func _on_visibility_changed() -> void:
	if not visible:
		PanelStack.remove(self)
	_update_hint()

func _update_hint() -> void:
	_ensure_hint_panel()
	if _hint_holder == null:
		return
	var picker_open := visible and _kind != "" and _kind != "deposits"
	var mode: int = MapMode.current_mode
	var active := mode == MapMode.Mode.TILES_PRODUCING or mode == MapMode.Mode.TILES_CONSUMING
	if not (picker_open or active):
		_hint_holder.hide()
		return
	var consuming := (_kind == "consuming") if picker_open else (mode == MapMode.Mode.TILES_CONSUMING)
	var label := "Consuming" if consuming else "Producing"
	var verb := "consumed" if consuming else "produced"
	_hint_label.text = "%s — Select up to %d goods to see where they are being %s." % [label, MapMode.MAX_SELECTIONS, verb]
	_hint_holder.show()

func _ensure_hint_panel() -> void:
	if _hint_holder != null:
		return
	var host := get_parent()
	if host == null:
		return
	var holder := CenterContainer.new()
	holder.name = "PickHintHolder"
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.anchor_left = 0.0
	holder.anchor_right = 1.0
	holder.anchor_top = 1.0
	holder.anchor_bottom = 1.0
	holder.offset_left = 0.0
	holder.offset_right = 0.0
	holder.offset_bottom = -HINT_BOTTOM_MARGIN
	holder.offset_top = -(HINT_BOTTOM_MARGIN + HINT_HEIGHT)
	holder.grow_horizontal = Control.GROW_DIRECTION_BOTH
	holder.grow_vertical = Control.GROW_DIRECTION_BEGIN
	holder.hide()
	var panel := PanelContainer.new()
	var style := get_theme_stylebox("panel")
	if style != null:
		panel.add_theme_stylebox_override("panel", style)
	panel.custom_minimum_size = Vector2(0, HINT_HEIGHT)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 18)
	m.add_theme_constant_override("margin_right", 18)
	m.add_theme_constant_override("margin_top", 4)
	m.add_theme_constant_override("margin_bottom", 4)
	panel.add_child(m)
	_hint_label = Label.new()
	_hint_label.theme_type_variation = &"Body"
	_hint_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	m.add_child(_hint_label)
	holder.add_child(panel)
	host.add_child(holder)
	_hint_holder = holder

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if event.position.y > HEADER_HEIGHT:
				return
			_dragging = true
			_drag_offset = global_position - get_global_mouse_position()
			accept_event()
		else:
			_dragging = false
			accept_event()
	elif event is InputEventMouseMotion and _dragging:
		global_position = get_global_mouse_position() + _drag_offset
		accept_event()
