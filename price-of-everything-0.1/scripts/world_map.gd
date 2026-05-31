extends Node2D

@onready var terrain_layer: HexMap = %TerrainLayer
@onready var info_panel: PanelContainer = %TileInfoPanel
@onready var building_panel: PanelContainer = %BuildingDetailPanel
@onready var end_turn_button: Button = %EndTurnButton
@onready var phase_label: Label = %PhaseLabel
@onready var turn_counter: Label = %TurnCounter
@onready var encyclopedia_button: Button = %EncyclopediaButton
@onready var building_visuals: Node2D = %BuildingVisuals
@onready var building_connection_visuals: Node2D = %BuildingConnectionVisuals
@onready var search_overlay: Control = %SearchOverlay
@onready var river_layer: TileMapLayer = $RiverLayer
@onready var hud_content: Control = $UILayer/HUD/HUDContent
@onready var _hud: Control = $UILayer/HUD
@onready var _toast_layer: Control = $UILayer/HUD/ToastLayer

const DENSITY_SOFT_CAPACITY := 100.0

signal building_placed(tile_id: String, building_id: String, recipe_id: String, instance_id: String, coord: Vector2i)

var _stockpile_select_prompt: PanelContainer = null
var _pending_stockpile_selection: Dictionary = {}
var _dim_overlay: ColorRect = null
var _stockpile_legend: PanelContainer = null

func _ready() -> void:
	# DS assigns its Theme to the root Window, but Controls do not inherit a
	# Window's theme — so apply it to the HUD Control subtree (where every panel
	# lives) for DS fonts / type variations / button styles to actually resolve.
	_hud.theme = DS.theme
	river_layer.clear()
	terrain_layer.tile_selected.connect(_on_tile_selected)
	terrain_layer.stockpile_destination_selected.connect(_on_stockpile_destination_selected)
	info_panel.building_clicked.connect(building_panel.show_building)
	BuildMode.build_attempted.connect(_on_build_attempted)
	BuildMode.infrastructure_attempted.connect(_on_infrastructure_attempted)  # NEW
	end_turn_button.pressed.connect(_on_end_turn_pressed)
	encyclopedia_button.pressed.connect(_on_encyclopedia_pressed)
	if search_overlay.has_signal("recipe_build_requested"):
		search_overlay.recipe_build_requested.connect(_on_search_recipe_build_requested)

	TurnManager.phase_started.connect(_on_phase_started)
	TurnManager.turn_advanced.connect(_on_turn_advanced)
	TurnManager.turn_resolution_started.connect(_on_resolution_started)
	TurnManager.turn_resolution_completed.connect(_on_resolution_completed)
	MatchState.output_stockpile_selection_started.connect(_on_output_stockpile_selection_started)
	MatchState.output_stockpile_selection_cancelled.connect(_on_output_stockpile_selection_cancelled)

	_update_turn_counter(TurnManager.current_turn)
	_update_phase_label(TurnManager.current_phase)
	_build_stockpile_select_prompt()
	_build_dim_overlay()
	_build_stockpile_legend()

	# Wire visuals to react to building placements
	building_placed.connect(building_visuals.on_building_placed)

	# Wire building connection visuals to building detail panel
	building_panel.building_connections_changed.connect(
		building_connection_visuals.on_building_connections_changed
	)

	print("WorldMap ready, signals connected")
	print("MatchState ready. Money: ", MatchState.money, ". Buildings: ", MatchState.buildings.size())

func _on_tile_selected(tile_data: Dictionary) -> void:
	info_panel.show_tile(tile_data)

func _on_output_stockpile_selection_started(selection: Dictionary) -> void:
	_pending_stockpile_selection = selection.duplicate()
	var good_id: String = selection.get("good_id", "")
	terrain_layer.begin_stockpile_destination_selection(good_id)
	_show_stockpile_select_prompt(selection)
	_enter_stockpile_ui_mode()

func _on_output_stockpile_selection_cancelled() -> void:
	_pending_stockpile_selection.clear()
	terrain_layer.end_stockpile_destination_selection()
	_hide_stockpile_select_prompt()
	_exit_stockpile_ui_mode()

func _on_stockpile_destination_selected(tile_data: Dictionary) -> void:
	if _pending_stockpile_selection.is_empty():
		return
	var instance_id: String = _pending_stockpile_selection.get("instance_id", "")
	var good_id: String = _pending_stockpile_selection.get("good_id", "")
	var tile_id: String = tile_data.get("id", "")
	MatchState.set_output_stockpile_destination(instance_id, tile_id, good_id)
	_pending_stockpile_selection.clear()
	_hide_stockpile_select_prompt()
	_exit_stockpile_ui_mode()

# ----- Stockpile selection UI mode -----

func _enter_stockpile_ui_mode() -> void:
	info_panel.hide()
	building_panel.hide()
	if _hud.has_method("hide_bottom_menu"):
		_hud.hide_bottom_menu()
	if _dim_overlay != null:
		_dim_overlay.visible = true
	if _stockpile_legend != null:
		_stockpile_legend.visible = true

func _exit_stockpile_ui_mode() -> void:
	if _hud.has_method("show_bottom_menu"):
		_hud.show_bottom_menu()
	if _dim_overlay != null:
		_dim_overlay.visible = false
	if _stockpile_legend != null:
		_stockpile_legend.visible = false

# ----- Dim overlay -----

func _build_dim_overlay() -> void:
	_dim_overlay = ColorRect.new()
	_dim_overlay.name = "StockpileDimOverlay"
	_dim_overlay.color = Color(0.0, 0.0, 0.0, 0.10)
	_dim_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dim_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim_overlay.visible = false
	hud_content.add_child(_dim_overlay)
	# Move to index 0 so all existing panels render on top
	hud_content.move_child(_dim_overlay, 0)

# ----- Stockpile legend -----

func _build_stockpile_legend() -> void:
	_stockpile_legend = PanelContainer.new()
	_stockpile_legend.name = "StockpileLegend"
	_stockpile_legend.visible = false
	_stockpile_legend.custom_minimum_size = Vector2(210, 0)
	_stockpile_legend.anchor_left = 0.0
	_stockpile_legend.anchor_right = 0.0
	_stockpile_legend.anchor_top = 1.0
	_stockpile_legend.anchor_bottom = 1.0
	_stockpile_legend.offset_left = 12.0
	_stockpile_legend.offset_right = 222.0
	_stockpile_legend.offset_top = -160.0
	_stockpile_legend.offset_bottom = -24.0
	_stockpile_legend.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var style := StyleBoxFlat.new()
	style.bg_color = Color(DS.PALETTE.BG_PANEL, 0.92)
	style.border_color = Color(0.995, 0.93, 0.76, 0.5)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	_stockpile_legend.add_theme_stylebox_override("panel", style)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stockpile_legend.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 5)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "Tile colours"
	title.add_theme_font_size_override("font_size", 11)
	title.add_theme_color_override("font_color", Color(0.995, 0.93, 0.76, 0.7))
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(title)

	vbox.add_child(_make_legend_row(Color(0.35, 1.0, 0.35, 1.0), "Consumes this good"))
	vbox.add_child(_make_legend_row(Color(0.1,  0.45, 0.1,  1.0), "Has buildings"))
	vbox.add_child(_make_legend_row(Color(0.3,  0.3,  0.3,  1.0), "Empty tile"))

	hud_content.add_child(_stockpile_legend)

func _make_legend_row(color: Color, text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var swatch := Panel.new()
	swatch.custom_minimum_size = Vector2(14, 14)
	swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sw_style := StyleBoxFlat.new()
	sw_style.bg_color = color
	sw_style.corner_radius_top_left = 2
	sw_style.corner_radius_top_right = 2
	sw_style.corner_radius_bottom_left = 2
	sw_style.corner_radius_bottom_right = 2
	swatch.add_theme_stylebox_override("panel", sw_style)
	row.add_child(swatch)

	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85, 1.0))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(label)
	return row

func _on_end_turn_pressed() -> void:
	TurnManager.commit_turn()

func _on_encyclopedia_pressed() -> void:
	if search_overlay != null and search_overlay.has_method("open_encyclopedia"):
		search_overlay.open_encyclopedia()

func _on_search_recipe_build_requested(building_id: String, recipe_id: String) -> void:
	BuildMode.enter_build_mode(building_id, recipe_id)

func _on_build_attempted(building_id: String, tile_id: String) -> void:
	print("[Build] attempt: building=%s tile=%s" % [building_id, tile_id])
	var coord := terrain_layer.id_to_coord(tile_id)
	if coord == Vector2i(-1, -1):
		print("[Build] FAILED: tile_id %s did not resolve to a coord (id_to_coord returned -1,-1)" % tile_id)
		return

	var recipe_id: String = BuildMode.current_recipe_id
	if recipe_id == "":
		print("[Build] FAILED: no recipe selected (BuildMode.current_recipe_id is empty)")
		push_warning("Build attempted with no recipe selected")
		return
	var recipe: Dictionary = Catalog.get_recipe(recipe_id)
	if recipe.is_empty():
		print("[Build] FAILED: unknown recipe %s (Catalog.get_recipe returned empty)" % recipe_id)
		push_warning("Build attempted with unknown recipe %s" % recipe_id)
		return
	if not terrain_layer.tiles.has(coord):
		print("[Build] WARNING: terrain_layer.tiles has no entry for coord %s (skipping requirement check)" % str(coord))
	else:
		var tile_data: Dictionary = terrain_layer.tiles[coord]
		if not _tile_meets_recipe_requirements(tile_data, recipe):
			print("[Build] FAILED: recipe requirements not met on %s (recipe=%s requirements=%s deposits=%s)" % [tile_id, recipe_id, str(recipe.get("requirements", [])), str(tile_data.get("deposits", []))])
			return

	# Look up cost
	var building_data: Dictionary = Catalog.get_building(building_id)
	var space_check := _space_check_for_build(tile_id, building_id)
	if not bool(space_check.get("allowed", false)):
		return
	var cost: float = float(building_data.get("base_price", 0.0)) * float(space_check.get("cost_multiplier", 1.0))

	# Check + deduct money
	if not MatchState.deduct_money(cost):
		print("[Build] FAILED: insufficient money. Need £%.2f, have £%.2f" % [cost, MatchState.money])
		return

	# Add to MatchState (single source of truth)
	var instance_id := MatchState.add_building(building_id, recipe_id, tile_id)

	var _building_name := _get_building_display_name(building_id)
	print("Built %s (instance %s, recipe %s) on %s — cost £%.2f" % [building_id, instance_id, recipe_id, tile_id, cost])

	building_placed.emit(tile_id, building_id, recipe_id, instance_id, coord)

func _get_building_display_name(building_id: String) -> String:
	return Catalog.get_building_display_name(building_id)

func _tile_meets_recipe_requirements(tile_data: Dictionary, recipe: Dictionary) -> bool:
	for req in recipe.get("requirements", []):
		if not _tile_meets_build_req(tile_data, req):
			return false
	return true

func _tile_meets_build_req(tile_data: Dictionary, req: Dictionary) -> bool:
	match req.get("type", ""):
		"deposit":
			var deposits: Array = tile_data.get("deposits", [])
			return deposits.has(req.get("value", ""))
		"produces":
			return _tile_produces_good(tile_data, req.get("value", ""))
		"potential":
			var value: String = req.get("value", "")
			if value == "wind":
				return tile_data.get("wind_potential", 0) > 0
			if value == "solar":
				return tile_data.get("solar_potential", 0) > 0
			return false
	return false

func _tile_produces_good(tile_data: Dictionary, internal_name: String) -> bool:
	var tile_id: String = tile_data.get("id", "")
	if tile_id == "":
		return false
	var instance_ids: Array = MatchState.tile_buildings.get(tile_id, [])
	for inst_id in instance_ids:
		var building: Dictionary = MatchState.buildings.get(inst_id, {})
		if building.is_empty():
			continue
		var recipe: Dictionary = Catalog.get_recipe(building.get("recipe_id", ""))
		if recipe.get("output_name", "") == internal_name:
			return true
		for output in recipe.get("outputs", []):
			if output.get("internal_name", "") == internal_name:
				return true
	return false

func _on_infrastructure_attempted(infra_type: String, tile_id: String) -> void:
	var coord := terrain_layer.id_to_coord(tile_id)
	if coord == Vector2i(-1, -1):
		return
	if not terrain_layer.tiles.has(coord):
		return

	var tile: Dictionary = terrain_layer.tiles[coord]
	var infra: Array = tile.get("infrastructure_present", [])

	# Already present — silently bail (no charge, no error)
	if infra.has(infra_type):
		print("Tile %s already has %s" % [tile_id, infra_type])
		return

	# Lookup cost
	var building_data: Dictionary = Catalog.get_building_by_internal_name(infra_type)
	var infra_building_id: String = building_data.get("id", "")
	var cost: float = float(building_data.get("base_price", 0.0))
	if infra_building_id != "":
		var space_check := _space_check_for_build(tile_id, infra_building_id)
		if not bool(space_check.get("allowed", false)):
			return
		var cost_multiplier := float(space_check.get("cost_multiplier", 1.0))
		cost *= cost_multiplier
		_try_build_infrastructure(tile_id, coord, tile, infra, infra_type, infra_building_id, cost)
		return

	_try_build_infrastructure(tile_id, coord, tile, infra, infra_type, infra_building_id, cost)

func _try_build_infrastructure(tile_id: String, coord: Vector2i, tile: Dictionary, infra: Array, infra_type: String, infra_building_id: String, cost: float) -> void:
	# Check + deduct
	if not MatchState.deduct_money(cost):
		print("[Build] FAILED: insufficient money for %s. Need £%.2f, have £%.2f" % [infra_type, cost, MatchState.money])
		return

	infra.append(infra_type)
	tile["infrastructure_present"] = infra
	terrain_layer.tiles[coord] = tile
	Catalog.add_tile_infrastructure(tile_id, infra_type)  # so the router uses built roads/rail

	print("Built %s on %s — cost £%.2f" % [infra_type, tile_id, cost])

	var instance_id := ""
	if infra_building_id != "":
		instance_id = MatchState.add_building(infra_building_id, "", tile_id)
	building_placed.emit(tile_id, infra_building_id, "", instance_id, coord)

func _space_check_for_build(tile_id: String, building_id: String) -> Dictionary:
	var building_data: Dictionary = Catalog.get_building(building_id)
	var added_space := maxf(0.0, float(building_data.get("tile_size_used", 1.0)))
	var current_space := MatchState.get_tile_space_used(tile_id)
	var projected_space := current_space + added_space
	if projected_space > float(MatchState.MAX_TILE_LAND):
		print("[Build] FAILED: tile %s is full (need %s, max %s)" % [tile_id, str(projected_space), str(MatchState.MAX_TILE_LAND)])
		_show_tile_space_error("There is no more room on that tile. Demolish buildings to make room.")
		return {"allowed": false, "cost_multiplier": 1.0}
	var land_owned := MatchState.get_tile_land_owned(tile_id)
	if projected_space > float(land_owned):
		print("[Build] FAILED: insufficient land on tile %s (need %s, own %s)" % [tile_id, str(projected_space), str(land_owned)])
		_show_tile_space_error("You cannot build that. You do not own sufficient land on tile %s" % tile_id)
		return {"allowed": false, "cost_multiplier": 1.0}
	var cost_multiplier := 1.0
	if projected_space > DENSITY_SOFT_CAPACITY:
		cost_multiplier = 1.5
		_show_tile_space_caution("Local opposition to density on tile %s will increase material and money costs for new buildings by 50%%" % tile_id)
	return {"allowed": true, "cost_multiplier": cost_multiplier}

func _show_tile_space_error(message: String) -> void:
	if _toast_layer != null and _toast_layer.has_method("show_error"):
		_toast_layer.call("show_error", message)
	else:
		push_warning(message)

func _show_tile_space_caution(message: String) -> void:
	if _toast_layer != null and _toast_layer.has_method("show_caution"):
		_toast_layer.call("show_caution", message)
	else:
		push_warning(message)

func _infra_building_id_for(infra_type: String) -> String:
	# Maps infrastructure internal_name -> the building_id used for visual icons
	match infra_type:
		"cables": return "b_006"
		"roads": return "b_005"
		_: return ""

func _on_phase_started(phase: int) -> void:
	_update_phase_label(phase)
	print("Phase: ", TurnManager.get_phase_name(phase))

func _on_turn_advanced(new_turn: int) -> void:
	_update_turn_counter(new_turn)

func _on_resolution_started() -> void:
	end_turn_button.disabled = true

func _on_resolution_completed() -> void:
	end_turn_button.disabled = false

func _update_turn_counter(turn: int) -> void:
	turn_counter.text = "Turn %d / %d" % [turn, TurnManager.MAX_TURNS]

func _update_phase_label(phase: int) -> void:
	phase_label.text = "Phase: %s" % TurnManager.get_phase_name(phase)

func _build_stockpile_select_prompt() -> void:
	_stockpile_select_prompt = PanelContainer.new()
	_stockpile_select_prompt.name = "StockpileSelectPrompt"
	_stockpile_select_prompt.visible = false
	_stockpile_select_prompt.custom_minimum_size = Vector2(520, 30)
	_stockpile_select_prompt.anchor_left = 0.5
	_stockpile_select_prompt.anchor_right = 0.5
	_stockpile_select_prompt.anchor_top = 1.0
	_stockpile_select_prompt.anchor_bottom = 1.0
	_stockpile_select_prompt.offset_left = -260.0
	_stockpile_select_prompt.offset_right = 260.0
	_stockpile_select_prompt.offset_top = -158.0
	_stockpile_select_prompt.offset_bottom = -128.0
	_stockpile_select_prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(DS.PALETTE.BG_PANEL, 0.94)
	style.border_color = Color(0.995, 0.93, 0.76, 0.6)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	_stockpile_select_prompt.add_theme_stylebox_override("panel", style)
	hud_content.add_child(_stockpile_select_prompt)

	var label := Label.new()
	label.name = "Label"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 13)
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stockpile_select_prompt.add_child(label)

func _show_stockpile_select_prompt(selection: Dictionary) -> void:
	if _stockpile_select_prompt == null:
		return
	var label := _stockpile_select_prompt.get_node_or_null("Label") as Label
	if label != null:
		var good_id: String = selection.get("good_id", "")
		label.text = "Select tile to send %s to for stockpiling" % Catalog.get_display_name(good_id)
	_stockpile_select_prompt.visible = true

func _hide_stockpile_select_prompt() -> void:
	if _stockpile_select_prompt != null:
		_stockpile_select_prompt.visible = false

func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed:
		return

	if event.keycode == KEY_ESCAPE and search_overlay != null and search_overlay.visible:
		search_overlay.call("close_search")
		get_viewport().set_input_as_handled()
		return

	if event.keycode == KEY_X and _should_open_search(event):
		search_overlay.call("open_search")
		get_viewport().set_input_as_handled()
		return

	match event.keycode:
		KEY_ESCAPE:
			if not _pending_stockpile_selection.is_empty():
				MatchState.cancel_output_stockpile_selection()
			else:
				PanelStack.close_top()
			get_viewport().set_input_as_handled()

		KEY_1:
			var current = MatchState.sell_mode
			var new_mode = MatchState.SellMode.STOCKPILE_ALL if current == MatchState.SellMode.SELL_ALL else MatchState.SellMode.SELL_ALL
			MatchState.set_sell_mode(new_mode)
			var mode_name = "STOCKPILE" if new_mode == MatchState.SellMode.STOCKPILE_ALL else "SELL_ALL"
			print("[DEBUG] Sell mode toggled to: ", mode_name)

func _should_open_search(event: InputEventKey) -> bool:
	if search_overlay == null or search_overlay.visible:
		return false
	if event.echo or event.ctrl_pressed or event.alt_pressed or event.meta_pressed:
		return false
	if not _pending_stockpile_selection.is_empty():
		return false
	return not _is_text_entry_focused()

func _is_text_entry_focused() -> bool:
	var focus_owner := get_viewport().gui_get_focus_owner()
	return focus_owner is LineEdit or focus_owner is TextEdit
