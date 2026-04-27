extends Node2D

@onready var terrain_layer: TileMapLayer = %TerrainLayer
@onready var info_panel: PanelContainer = %TileInfoPanel
@onready var building_panel: PanelContainer = %BuildingDetailPanel
@onready var end_turn_button: Button = %EndTurnButton
@onready var phase_label: Label = %PhaseLabel
@onready var turn_counter: Label = %TurnCounter

func _ready() -> void:
	terrain_layer.tile_selected.connect(info_panel.show_tile)
	info_panel.building_clicked.connect(building_panel.show_building)
	
	# Wire End Turn button to TurnManager
	end_turn_button.pressed.connect(_on_end_turn_pressed)
	
	# Wire TurnManager signals to UI updates
	TurnManager.phase_started.connect(_on_phase_started)
	TurnManager.turn_advanced.connect(_on_turn_advanced)
	TurnManager.turn_resolution_started.connect(_on_resolution_started)
	TurnManager.turn_resolution_completed.connect(_on_resolution_completed)
	
	# Initialize UI with current state
	_update_turn_counter(TurnManager.current_turn)
	_update_phase_label(TurnManager.current_phase)
	
	print("WorldMap ready, signals connected")

func _on_end_turn_pressed() -> void:
	TurnManager.commit_turn()

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
