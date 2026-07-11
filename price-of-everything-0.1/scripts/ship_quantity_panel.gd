extends PanelContainer
## CTRL+click "send a specific amount every turn" panel: after picking a destination
## tile in the ship-to-tile map mode, this lists the PLAYER buildings on that tile
## consuming the routed good — icon | recipe | need/turn | what the market-bought
## share currently costs — with a quantity box + Confirm at the bottom.
##
## Pure UI: emits `confirmed(qty)` / `cancelled`; world_map owns the actual routing
## (set_output_stockpile_destination + set_output_ship_quantity). Rows reuse the
## building-ledger metal plates; the frame is the DS default panel (navy + parchment).

signal confirmed(qty: int)
signal cancelled

const LedgerRowStyle := preload("res://scripts/ledger_row_style.gd")
const BuildingIcon := preload("res://scripts/building_icon.gd")
const BuildingLevels := preload("res://scripts/building_levels.gd")

const PANEL_W := 620.0
const ICON_COL := 48.0
const NEED_COL := 96.0
const MARKET_COL := 150.0

var _good_id := ""
var _tile_id := ""
var _spin: SpinBox = null


func _ready() -> void:
	# Centre the panel; sized to content up to a capped height.
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 0.5
	anchor_bottom = 0.5
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	custom_minimum_size = Vector2(PANEL_W, 0)
	visible = false


func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_close(false)


func open(selection: Dictionary, tile_id: String) -> void:
	_good_id = str(selection.get("good_id", ""))
	_tile_id = tile_id
	for c in get_children():
		c.queue_free()
	_build()
	reset_size()
	visible = true


func _close(ok: bool) -> void:
	visible = false
	if ok:
		confirmed.emit(int(_spin.value) if _spin != null else 0)
	else:
		cancelled.emit()


func _build() -> void:
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 4)
	add_child(margin)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	margin.add_child(col)

	# Header: title + close.
	var head := HBoxContainer.new()
	col.add_child(head)
	var title := Label.new()
	title.text = "Ship %s to %s" % [Catalog.get_display_name(_good_id), Catalog.tile_label(_tile_id)]
	title.theme_type_variation = &"BuildingName"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close := Button.new()
	close.text = "✕"
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(func() -> void: _close(false))
	head.add_child(close)

	var blurb := Label.new()
	blurb.text = "Your buildings on this tile consuming %s:" % Catalog.get_display_name(_good_id)
	blurb.theme_type_variation = &"Caption"
	col.add_child(blurb)

	# Column headers (plain labels, geometry matching the row cells — ledger pattern).
	var rows := _consumer_rows()
	if rows.is_empty():
		var none := Label.new()
		none.text = "No buildings you own here consume %s yet — it will pile up in the tile stockpile." % Catalog.get_display_name(_good_id)
		none.theme_type_variation = &"Caption"
		none.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(none)
	else:
		var hdr := HBoxContainer.new()
		hdr.add_theme_constant_override("separation", 8)
		var hdr_margin := MarginContainer.new()
		hdr_margin.add_theme_constant_override("margin_left", 12)
		hdr_margin.add_theme_constant_override("margin_right", 12)
		hdr_margin.add_child(hdr)
		col.add_child(hdr_margin)
		hdr.add_child(_hcell("", ICON_COL))
		hdr.add_child(_hcell("RECIPE", 0.0, true))
		hdr.add_child(_hcell("NEEDS / TURN", NEED_COL))
		hdr.add_child(_hcell("FROM MARKET NOW", MARKET_COL))

		var scroll := ScrollContainer.new()
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.custom_minimum_size = Vector2(0, minf(64.0 * rows.size() + 8.0, 300.0))
		col.add_child(scroll)
		var body := VBoxContainer.new()
		body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		body.add_theme_constant_override("separation", 7)
		scroll.add_child(body)
		for r in rows:
			body.add_child(_build_row(r))

	col.add_child(HSeparator.new())

	# "Send this quantity" + number box + Confirm.
	var send_row := HBoxContainer.new()
	send_row.add_theme_constant_override("separation", 10)
	col.add_child(send_row)
	var send_label := Label.new()
	send_label.text = "Send this quantity"
	send_label.theme_type_variation = &"Body"
	send_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	send_row.add_child(send_label)
	_spin = SpinBox.new()
	_spin.min_value = 1
	_spin.max_value = 9999
	_spin.step = 1
	_spin.custom_minimum_size = Vector2(120, 34)
	# Sensible default: the tile's total per-turn need for the good (or 10).
	var total_need := 0
	for r in _consumer_rows():
		total_need += int(r.need)
	_spin.value = maxi(1, total_need if total_need > 0 else 10)
	send_row.add_child(_spin)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	send_row.add_child(spacer)
	var per_turn := Label.new()
	per_turn.text = "every turn"
	per_turn.theme_type_variation = &"Caption"
	per_turn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	send_row.add_child(per_turn)

	var confirm := Button.new()
	confirm.text = "Confirm"
	confirm.theme_type_variation = &"Primary"
	confirm.custom_minimum_size = Vector2(0, 44)
	confirm.pressed.connect(func() -> void: _close(true))
	col.add_child(confirm)


func _hcell(text: String, width: float, expand: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = &"Caption"
	l.add_theme_color_override("font_color", DS.PALETTE.TEXT_MUTED)
	l.clip_text = true
	if expand:
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	else:
		l.custom_minimum_size = Vector2(width, 0)
	return l


# One consumer row on a ledger metal plate: icon | recipe | need/turn | market cost.
func _build_row(r: Dictionary) -> Control:
	var row := PanelContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_stylebox_override("panel", LedgerRowStyle.new())
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(hbox)

	var icon_holder := Control.new()
	icon_holder.custom_minimum_size = Vector2(ICON_COL, 36)
	hbox.add_child(icon_holder)
	var tex: Texture2D = BuildingIcon.clean_texture(str(r.building_id), str(r.internal))
	if tex != null:
		var tr := TextureRect.new()
		tr.texture = tex
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.set_anchors_preset(Control.PRESET_FULL_RECT)
		icon_holder.add_child(tr)

	var name := Label.new()
	name.text = str(r.recipe_name)
	name.theme_type_variation = &"Body"
	name.clip_text = true
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hbox.add_child(name)

	var need := Label.new()
	need.text = "%d" % int(r.need)
	need.theme_type_variation = &"Numeric"
	need.custom_minimum_size = Vector2(NEED_COL, 0)
	need.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hbox.add_child(need)

	var market := Label.new()
	market.text = ("£%.2f (%d)" % [float(r.market_cost), int(r.market_qty)]) if int(r.market_qty) > 0 else "—"
	market.theme_type_variation = &"Numeric"
	market.add_theme_color_override("font_color", DS.PALETTE.WARN if int(r.market_qty) > 0 else DS.PALETTE.TEXT_MUTED)
	market.custom_minimum_size = Vector2(MARKET_COL, 0)
	market.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hbox.add_child(market)
	return row


## The player's buildings on the destination tile that consume the good, with their
## per-turn need and the share currently bought from the MARKET. Local supply =
## on-tile player producers of the good (effective output), allocated to consumers
## in stable instance order; whatever local supply can't cover is priced at the
## current buy price (base price + market markup).
func _consumer_rows() -> Array:
	var consumers: Array = []
	var local_supply := 0
	var iids: Array = MatchState.tile_buildings.get(_tile_id, []).duplicate()
	iids.sort()
	for iid in iids:
		var inst: Dictionary = MatchState.buildings.get(str(iid), {})
		if inst.is_empty() or not MatchState.is_player_owned(inst):
			continue
		var recipe: Dictionary = Catalog.get_recipe(str(inst.get("recipe_id", "")))
		if recipe.is_empty():
			continue
		var level := int(inst.get("level", 1))
		for o in recipe.get("outputs", []):
			if str((o as Dictionary).get("good_id", "")) == _good_id:
				local_supply += int(round(float((o as Dictionary).get("qty", 0)) * BuildingLevels.mult("output", level)))
		for inp in recipe.get("inputs", []):
			if str((inp as Dictionary).get("good_id", "")) != _good_id:
				continue
			var need := int(round(float((inp as Dictionary).get("qty", 0)) * BuildingLevels.mult("input", level)))
			var bd: Dictionary = Catalog.get_building(str(inst.get("building_id", "")))
			consumers.append({
				"building_id": str(inst.get("building_id", "")),
				"internal": str(bd.get("internal_name", "")),
				"recipe_name": str(recipe.get("display_name", "")),
				"need": need,
				"market_qty": 0,
				"market_cost": 0.0,
			})
	var buy_price := MarketState.get_price(_good_id) * (1.0 + EconomyConfig.MARKET_BUY_MARKUP)
	var remaining := local_supply
	for c in consumers:
		var covered: int = mini(remaining, int(c.need))
		remaining -= covered
		c.market_qty = int(c.need) - covered
		c.market_cost = float(c.market_qty) * buy_price
	return consumers
