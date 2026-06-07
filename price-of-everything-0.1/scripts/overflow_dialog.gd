extends PanelContainer
## Modal shown when CONSTRUCTION MATERIALS arrive at a tile whose stockpile is
## full and so can't unload. The goods wait on the tile (held by MatchState as an
## overflow shipment) and retry each turn. Mirrors capacity_dialog.gd's style.
## Has NO close button — the player must pick one of the two actions.
##
## Instantiated by world_map.gd and parented to the HUD. Listens to
## MatchState.overflow_shipment_held; only build-material overflows prompt here.

signal go_to_stockpile_requested(tile_id: String)

var _title: Label
var _queue: Array = []          # tile_ids awaiting a decision
var _seen: Dictionary = {}      # tile_id -> true while queued/current (avoid dupes)
var _current_tile: String = ""

func _ready() -> void:
	if DS and DS.theme:
		theme = DS.theme
	_build_ui()
	visible = false
	if MatchState.has_signal("overflow_shipment_held"):
		MatchState.overflow_shipment_held.connect(_on_overflow_held)

func _build_ui() -> void:
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 0.5
	anchor_bottom = 0.5
	offset_left = -320
	offset_right = 320
	offset_top = -120
	offset_bottom = 120
	custom_minimum_size = Vector2(640, 240)
	clip_contents = true

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	add_child(margin)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	margin.add_child(vb)

	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 15)
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(_title)

	vb.add_child(HSeparator.new())

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var sell := Button.new()
	sell.text = "Sell surplus for me to make room"
	sell.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sell.custom_minimum_size = Vector2(0, 44)
	sell.pressed.connect(_on_sell_surplus)
	row.add_child(sell)
	var go := Button.new()
	go.text = "Go to tile stockpile"
	go.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	go.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	go.custom_minimum_size = Vector2(0, 44)
	go.pressed.connect(_on_go_to_stockpile)
	row.add_child(go)
	vb.add_child(row)

func _on_overflow_held(record: Dictionary) -> void:
	# Only build-material overflows prompt the player here.
	if str(record.get("construction_instance_id", "")) == "":
		return
	var tile := str(record.get("destination_tile", ""))
	if tile == "" or _seen.has(tile):
		return
	_seen[tile] = true
	_queue.append({"tile": tile, "building": _building_name_for(record)})
	if not visible:
		_show_next()

func _show_next() -> void:
	if _queue.is_empty():
		_current_tile = ""
		visible = false
		return
	var entry: Dictionary = _queue.pop_front()
	_current_tile = str(entry.tile)
	_title.text = "The building materials for %s have arrived at %s but the stockpile is full. They will wait until you have made space before unloading." % [
		str(entry.building), Catalog.tile_label(_current_tile)]
	visible = true
	move_to_front()

func _on_sell_surplus() -> void:
	if _current_tile != "":
		MatchState.enable_sell_surplus(_current_tile)
		MatchState.request_toast("Auto-selling surplus on %s to make room" % Catalog.tile_label(_current_tile), "success")
	_finish_current()

func _on_go_to_stockpile() -> void:
	if _current_tile != "":
		go_to_stockpile_requested.emit(_current_tile)
	_finish_current()

func _finish_current() -> void:
	_seen.erase(_current_tile)
	_current_tile = ""
	_show_next()

func _building_name_for(record: Dictionary) -> String:
	var iid := str(record.get("construction_instance_id", ""))
	var dest := str(record.get("destination_tile", ""))
	for p in Construction.projects_on_tile(dest):
		if str(p.get("instance_id", "")) == iid:
			var rec: Dictionary = Catalog.get_recipe(str(p.get("recipe_id", "")))
			var rn := str(rec.get("display_name", "")).strip_edges()
			if rn != "":
				return rn
			return str(Catalog.get_building(p.get("building_id", "")).get("display_name", "a building"))
	return Catalog.get_display_name(str(record.get("good_id", "")))
