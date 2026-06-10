extends PanelContainer
## Modal opened by clicking a grouped notification row in the bell ("35 Buildings
## Starved of Inputs"). Lists each member event with a "Go to" button (focuses
## the tile via MatchState.focus_tile_requested) and a per-member dismiss.
##
## Pure read/UI: it reads grouped event data the bell hands it and acts through
## EventScheduler.dismiss / MatchState.focus_tile_requested. The bell repopulates
## it (or closes it) whenever the active set changes, so dismissing members keeps
## the list live and an emptied group closes the modal.

const WIDTH := 460.0
const MAX_HEIGHT := 520.0

var _group_key := ""
var _title_label: Label = null
var _count_label: Label = null
var _list: VBoxContainer = null


func _ready() -> void:
	theme = DS.theme
	theme_type_variation = &"Outlined"
	visible = false
	z_index = 200
	custom_minimum_size = Vector2(WIDTH, 0)
	# Centre on screen.
	set_anchors_preset(Control.PRESET_CENTER)
	pivot_offset = Vector2.ZERO
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_ui()


func _build_ui() -> void:
	var margin := MarginContainer.new()
	for s in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + s, 14)
	add_child(margin)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	margin.add_child(vb)

	# Header: title + count + close.
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	_title_label = Label.new()
	_title_label.theme_type_variation = &"Section"
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_title_label)
	var close := Button.new()
	close.text = "✕"
	close.custom_minimum_size = Vector2(26, 26)
	close.pressed.connect(close_modal)
	header.add_child(close)
	vb.add_child(header)

	_count_label = Label.new()
	_count_label.theme_type_variation = &"Caption"
	_count_label.add_theme_color_override("font_color", DS.PALETTE.TEXT_MUTED)
	vb.add_child(_count_label)
	vb.add_child(HSeparator.new())

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(WIDTH - 28, 0)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 4)
	scroll.add_child(_list)

	# Footer: dismiss the whole group.
	vb.add_child(HSeparator.new())
	var footer := HBoxContainer.new()
	var clear := Button.new()
	clear.text = "Dismiss all in this group"
	clear.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	clear.pressed.connect(func():
		EventScheduler.dismiss_group(_group_key)
		close_modal())
	footer.add_child(clear)
	vb.add_child(footer)


func open_group(group_key: String, title: String, members: Array) -> void:
	_group_key = group_key
	_title_label.text = title
	_populate(members)
	var vh := get_viewport_rect().size.y
	custom_minimum_size = Vector2(WIDTH, minf(MAX_HEIGHT, vh - 80.0))
	visible = true
	move_to_front()
	PanelStack.push(self)  # idempotent (de-dups internally)


## Re-render the member list (called by the bell when the active set changes).
func refresh(members: Array) -> void:
	if not visible:
		return
	_populate(members)


func _populate(members: Array) -> void:
	for child in _list.get_children():
		child.queue_free()
	_count_label.text = "%d building%s" % [members.size(), "" if members.size() == 1 else "s"]
	for ev in members:
		_list.add_child(_make_member_row(ev))


func _make_member_row(ev: Dictionary) -> Control:
	var row := PanelContainer.new()
	row.theme_type_variation = &"Card"
	var m := MarginContainer.new()
	for s in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + s, 8)
	row.add_child(m)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	m.add_child(hb)

	var deeplink: Dictionary = ev.get("deeplink", {})
	var tile_id := str(deeplink.get("tile_id", ""))

	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 0)
	var name_label := Label.new()
	name_label.text = str(ev.get("title", ""))
	name_label.theme_type_variation = &"Body"
	col.add_child(name_label)
	if tile_id != "":
		var where := Label.new()
		where.text = Catalog.tile_label(tile_id)
		where.theme_type_variation = &"Caption"
		where.add_theme_color_override("font_color", DS.PALETTE.TEXT_DIM)
		col.add_child(where)
	hb.add_child(col)

	if tile_id != "":
		var go := Button.new()
		go.text = "Go to"
		go.custom_minimum_size = Vector2(64, 28)
		go.pressed.connect(func():
			MatchState.focus_tile_requested.emit(tile_id)
			close_modal())
		hb.add_child(go)

	var dismiss := Button.new()
	dismiss.text = "✕"
	dismiss.custom_minimum_size = Vector2(26, 28)
	dismiss.tooltip_text = "Dismiss"
	dismiss.pressed.connect(func(): EventScheduler.dismiss(str(ev.id)))
	hb.add_child(dismiss)
	return row


func close_modal() -> void:
	visible = false
	PanelStack.remove(self)  # safe if not present


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and not visible:
		PanelStack.remove(self)
