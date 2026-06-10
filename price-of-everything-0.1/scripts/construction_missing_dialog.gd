extends PanelContainer
# Shown when the player clicks a tile to build but the required construction materials are
# not present on that tile. Built entirely in code (mirrors capacity_dialog.gd) and parented
# to the HUD by world_map.gd. One instance is reused across builds via open().
#
# PHASE 1: only "Cancel construction" is wired. "Buy from market and construct" and "Use
# unused stockpile from another tile" are laid out but disabled — Phases 3 and 4 enable them
# and emit buy_requested / use_stockpile_requested. No money is deducted and no tile space is
# reserved while this dialog is up; cancelling simply closes it.

const GoodIcons := preload("res://scripts/good_icons.gd")
const GOODS_FRAME := preload("res://assets/ui/goods_frame.tres")  # skinny pipe frame (nine-patch)

const BADGE_DIAMETER := 22
const BADGE_TEXT_SIZE := 13
const BADGE_NAVY := Color(0.0, 0.119856, 0.243095, 1.0)
const BADGE_PAPER := Color(0.995234, 0.930806, 0.763265, 1.0)
const CELL_SIZE := 72.0

signal cancelled
signal buy_requested(building_id: String, recipe_id: String, tile_id: String)
signal use_stockpile_requested(building_id: String, recipe_id: String, tile_id: String)

var _missing_grid: GridContainer
var _eta_label: Label
var _buy_button: Button
var _use_button: Button

var _building_id: String = ""
var _recipe_id: String = ""
var _tile_id: String = ""


func _ready() -> void:
	_build_ui()
	visible = false


# Populate with the missing materials for this build and show the dialog.
# missing: {good_id: qty_short}.
func open(building_id: String, recipe_id: String, tile_id: String, missing: Dictionary) -> void:
	_building_id = building_id
	_recipe_id = recipe_id
	_tile_id = tile_id
	_populate_missing(missing)
	_update_eta()
	_update_use_button(missing)
	visible = true
	move_to_front()


func _update_use_button(missing: Dictionary) -> void:
	# Offer cross-tile sourcing only when a single tile's spare stock covers the whole shortfall.
	var source: Dictionary = Construction.find_source_tile(_tile_id, missing)
	if source.is_empty():
		_use_button.disabled = true
		_use_button.text = "No spare stockpile available"
	else:
		_use_button.disabled = false
		_use_button.text = "Use spare stockpile from %s" % Catalog.tile_label(str(source.get("tile_id", "")))


func _update_eta() -> void:
	var lead: int = 0
	var port: String = TransportService.nearest_port_tile(_tile_id)
	if port != "":
		lead = int(TransportService.route(port, _tile_id).get("turns", 0))
	var duration: int = int(Catalog.get_building(_building_id).get("build_duration", 0))
	_eta_label.text = "Estimated delivery ~%d turn%s · build %d turn%s · ready in ~%d turns" % [
		lead, "" if lead == 1 else "s", duration, "" if duration == 1 else "s", lead + duration
	]


func _build_ui() -> void:
	theme = DS.theme
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 0.5
	anchor_bottom = 0.5
	offset_left = -320.0
	offset_right = 320.0
	offset_top = -210.0
	offset_bottom = 210.0
	custom_minimum_size = Vector2(640, 420)
	clip_contents = true

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	add_child(margin)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	margin.add_child(vb)

	var title := Label.new()
	title.text = "Required resources missing"
	title.add_theme_font_size_override("font_size", 18)
	vb.add_child(title)
	vb.add_child(HSeparator.new())

	var body := Label.new()
	body.text = "You do not have the required resources on this tile to build this. How would you like to proceed?"
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_font_size_override("font_size", 13)
	vb.add_child(body)

	# Missing materials in a framed 3x2 grid (the skinny pipe frame from the overflow panel).
	# A 3-wide grid holds up to 6 cells, covering the busiest build (coal_power, 5 materials).
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", GOODS_FRAME)
	frame.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vb.add_child(frame)

	_missing_grid = GridContainer.new()
	_missing_grid.columns = 3
	_missing_grid.add_theme_constant_override("h_separation", 12)
	_missing_grid.add_theme_constant_override("v_separation", 12)
	frame.add_child(_missing_grid)

	# Delivery + build ETA, computed from the existing routing (nearest port -> tile).
	_eta_label = Label.new()
	_eta_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_eta_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_eta_label.add_theme_font_size_override("font_size", 12)
	vb.add_child(_eta_label)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(spacer)

	vb.add_child(HSeparator.new())

	# Action row: Use stockpile | Buy from market | Cancel. Buy/Use disabled until later phases.
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_child(row)

	_use_button = _make_button("Use unused stockpile from another tile", 1.5)
	_use_button.disabled = true
	_use_button.pressed.connect(_on_use_pressed)
	row.add_child(_use_button)

	_buy_button = _make_button("Buy from market and construct", 1.5)
	_buy_button.pressed.connect(_on_buy_pressed)
	row.add_child(_buy_button)

	var cancel_button := _make_button("Cancel construction", 1.0)
	cancel_button.pressed.connect(_on_cancel_pressed)
	row.add_child(cancel_button)


func _make_button(text: String, ratio: float) -> Button:
	var b := Button.new()
	b.text = text
	b.clip_text = false
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.size_flags_vertical = Control.SIZE_EXPAND_FILL
	b.size_flags_stretch_ratio = ratio
	b.custom_minimum_size = Vector2(80, 48)
	return b


func _populate_missing(missing: Dictionary) -> void:
	for child in _missing_grid.get_children():
		child.queue_free()
	for good_id in missing:
		_missing_grid.add_child(_make_cell(str(good_id), int(missing[good_id])))


func _make_cell(good_id: String, qty: int) -> Control:
	var slot := Control.new()
	slot.custom_minimum_size = Vector2(CELL_SIZE, CELL_SIZE)
	var icon := GoodIcons.texture_for(good_id, Catalog.get_internal_name(good_id))
	if icon != null:
		var tr := TextureRect.new()
		tr.texture = icon
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.set_anchors_preset(Control.PRESET_FULL_RECT)
		slot.add_child(tr)
	else:
		var ph := Label.new()
		ph.text = Catalog.get_display_name(good_id)
		ph.add_theme_font_size_override("font_size", 9)
		ph.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		ph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		ph.set_anchors_preset(Control.PRESET_FULL_RECT)
		slot.add_child(ph)
	slot.add_child(_make_qty_badge(qty))
	return slot


func _make_qty_badge(qty: int) -> Control:
	var qty_text := str(qty)
	var h: int = BADGE_DIAMETER
	var w: int = h if qty_text.length() <= 1 else maxi(h, qty_text.length() * 9 + 12)
	var badge := PanelContainer.new()
	badge.custom_minimum_size = Vector2(w, h)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	badge.offset_left = -w + 6
	badge.offset_top = -h + 6
	badge.offset_right = 6
	badge.offset_bottom = 6
	var style := StyleBoxFlat.new()
	style.bg_color = BADGE_NAVY
	style.border_color = BADGE_PAPER
	style.set_border_width_all(2)
	style.set_corner_radius_all(int(h / 2.0))
	badge.add_theme_stylebox_override("panel", style)
	var ls := LabelSettings.new()
	ls.font_color = BADGE_PAPER
	ls.font_size = BADGE_TEXT_SIZE
	var label := Label.new()
	label.text = qty_text
	label.label_settings = ls
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.add_child(label)
	return badge


func _on_cancel_pressed() -> void:
	visible = false
	cancelled.emit()


func _on_buy_pressed() -> void:
	visible = false
	buy_requested.emit(_building_id, _recipe_id, _tile_id)


func _on_use_pressed() -> void:
	visible = false
	use_stockpile_requested.emit(_building_id, _recipe_id, _tile_id)
