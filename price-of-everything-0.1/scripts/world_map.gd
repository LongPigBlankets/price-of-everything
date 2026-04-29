extends Node2D

@onready var terrain_layer: TileMapLayer = %TerrainLayer
@onready var info_panel: PanelContainer = %TileInfoPanel
@onready var building_panel: PanelContainer = %BuildingDetailPanel
@onready var end_turn_button: Button = %EndTurnButton
@onready var phase_label: Label = %PhaseLabel
@onready var turn_counter: Label = %TurnCounter
@onready var building_visuals: Node2D = %BuildingVisuals

signal building_placed(tile_id: String, building_id: String, coord: Vector2i)

func _ready() -> void:
	terrain_layer.tile_selected.connect(info_panel.show_tile)
	info_panel.building_clicked.connect(building_panel.show_building)
	BuildMode.build_attempted.connect(_on_build_attempted)
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
	var test_id = MatchState.add_building("b_001", "r_001", "tile_5_7")
	print("Added building, ID: ", test_id)
	print("Buildings on tile_5_7: ", MatchState.get_buildings_on_tile("tile_5_7"))
	print("All buildings: ", MatchState.buildings)
	print("State dump: ", MatchState.debug_dump())

func _on_end_turn_pressed() -> void:
	TurnManager.commit_turn()

func _on_build_attempted(building_id: String, tile_id: String) -> void:
	var coord := _id_to_coord(tile_id)
	if coord == Vector2i(-1, -1):
		return
	
	var recipe_id: String = BuildMode.current_recipe_id
	if recipe_id == "":
		push_warning("Build attempted with no recipe selected")
		return
	
	# Add to MatchState (single source of truth)
	var instance_id := MatchState.add_building(building_id, recipe_id, tile_id)
	
	var _building_name := _get_building_display_name(building_id)
	print("Built %s (instance %s, recipe %s) on %s" % [building_id, instance_id, recipe_id, tile_id])
	
	building_placed.emit(tile_id, building_id, recipe_id, instance_id, coord)

func _get_building_display_name(building_id: String) -> String:
	match building_id:
		"b_001": return "Mine"
		"b_002": return "Furnace"
		"b_003": return "Coal Power Plant"
		"b_004": return "Port"
		"b_005": return "Roads"
		_: return "Unknown"

func _id_to_coord(id: String) -> Vector2i:
	var parts := id.split("_")
	if parts.size() != 3 or parts[0] != "tile":
		return Vector2i(-1, -1)
	if not parts[1].is_valid_int() or not parts[2].is_valid_int():
		return Vector2i(-1, -1)
	return Vector2i(int(parts[1]) - 1, int(parts[2]) - 1)

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
