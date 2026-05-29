extends Node2D

@onready var terrain_layer: HexMap = %TerrainLayer
@onready var info_panel: PanelContainer = %TileInfoPanel
@onready var building_panel: PanelContainer = %BuildingDetailPanel
@onready var end_turn_button: Button = %EndTurnButton
@onready var phase_label: Label = %PhaseLabel
@onready var turn_counter: Label = %TurnCounter
@onready var building_visuals: Node2D = %BuildingVisuals

signal building_placed(tile_id: String, building_id: String, recipe_id: String, instance_id: String, coord: Vector2i)

func _ready() -> void:
	terrain_layer.tile_selected.connect(_on_tile_selected)
	info_panel.building_clicked.connect(building_panel.show_building)
	BuildMode.build_attempted.connect(_on_build_attempted)
	BuildMode.infrastructure_attempted.connect(_on_infrastructure_attempted)  # NEW
	end_turn_button.pressed.connect(_on_end_turn_pressed)
	
	TurnManager.phase_started.connect(_on_phase_started)
	TurnManager.turn_advanced.connect(_on_turn_advanced)
	TurnManager.turn_resolution_started.connect(_on_resolution_started)
	TurnManager.turn_resolution_completed.connect(_on_resolution_completed)
	
	_update_turn_counter(TurnManager.current_turn)
	_update_phase_label(TurnManager.current_phase)
	
	# Wire visuals to react to building placements
	building_placed.connect(building_visuals.on_building_placed)
	
	print("WorldMap ready, signals connected")
	print("MatchState ready. Money: ", MatchState.money, ". Buildings: ", MatchState.buildings.size())

func _on_tile_selected(tile_data: Dictionary) -> void:
	info_panel.show_tile(tile_data)

func _on_end_turn_pressed() -> void:
	TurnManager.commit_turn()

func _on_build_attempted(building_id: String, tile_id: String) -> void:
	var coord := terrain_layer.id_to_coord(tile_id)
	if coord == Vector2i(-1, -1):
		return
	
	var recipe_id: String = BuildMode.current_recipe_id
	if recipe_id == "":
		push_warning("Build attempted with no recipe selected")
		return
	var recipe: Dictionary = Catalog.get_recipe(recipe_id)
	if recipe.is_empty():
		push_warning("Build attempted with unknown recipe %s" % recipe_id)
		return
	if terrain_layer.tiles.has(coord):
		var tile_data: Dictionary = terrain_layer.tiles[coord]
		if not _tile_meets_recipe_requirements(tile_data, recipe):
			print("[Build] FAILED: recipe requirements not met on %s" % tile_id)
			return
	
	# Look up cost
	var building_data: Dictionary = Catalog.get_building(building_id)
	var cost: float = building_data.get("base_price", 0.0)
	
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
	var cost: float = building_data.get("base_price", 0.0)
	
	# Check + deduct
	if not MatchState.deduct_money(cost):
		print("[Build] FAILED: insufficient money for %s. Need £%.2f, have £%.2f" % [infra_type, cost, MatchState.money])
		return
	
	infra.append(infra_type)
	tile["infrastructure_present"] = infra
	terrain_layer.tiles[coord] = tile
	
	print("Built %s on %s — cost £%.2f" % [infra_type, tile_id, cost])
	
	var infra_building_id: String = building_data.get("id", "")
	var instance_id := ""
	if infra_building_id != "":
		instance_id = MatchState.add_building(infra_building_id, "", tile_id)
	building_placed.emit(tile_id, infra_building_id, "", instance_id, coord)

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
	
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_1:
		var current = MatchState.sell_mode
		var new_mode = MatchState.SellMode.STOCKPILE_ALL if current == MatchState.SellMode.SELL_ALL else MatchState.SellMode.SELL_ALL
		MatchState.set_sell_mode(new_mode)
		var name = "STOCKPILE" if new_mode == MatchState.SellMode.STOCKPILE_ALL else "SELL_ALL"
		print("[DEBUG] Sell mode toggled to: ", name)
