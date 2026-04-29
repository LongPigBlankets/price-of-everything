extends Node2D

const SliceMarkerScene: PackedScene = preload("res://scenes/slice_marker.tscn")

@onready var terrain_layer: TileMapLayer = %TerrainLayer

var current_overlays: Array = []

func _ready() -> void:
	MapMode.selections_changed.connect(_on_selections_changed)
	MapMode.mode_cleared.connect(_on_mode_cleared)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton \
			and event.button_index == MOUSE_BUTTON_RIGHT \
			and event.pressed \
			and MapMode.current_mode != MapMode.Mode.NONE:
		MapMode.clear_all()
		get_viewport().set_input_as_handled()

func _on_selections_changed(mode: int, selections: Array) -> void:
	_clear_overlays()
	_render_overlay(mode, selections)

func _on_mode_cleared() -> void:
	_clear_overlays()

func _clear_overlays() -> void:
	for node in current_overlays:
		if is_instance_valid(node):
			node.queue_free()
	current_overlays.clear()

func _render_overlay(mode: int, selections: Array) -> void:
	for coord in terrain_layer.tiles:
		var tile_data: Dictionary = terrain_layer.tiles[coord]
		var colors_for_tile: Array[Color] = []
		for s in selections:
			if _tile_matches(mode, tile_data, s.good_id):
				colors_for_tile.append(s.color)
		if not colors_for_tile.is_empty():
			var marker := SliceMarkerScene.instantiate()
			marker.position = terrain_layer.map_to_local(coord)
			marker.set_colors(colors_for_tile)
			add_child(marker)
			current_overlays.append(marker)

func _tile_matches(mode: int, tile_data: Dictionary, good_id: String) -> bool:
	match mode:
		MapMode.Mode.POTENTIALS:
			return _tile_has_potential(tile_data, good_id)
		MapMode.Mode.TILES_PRODUCING:
			return _tile_produces(tile_data, good_id)
		MapMode.Mode.TILES_CONSUMING:
			return _tile_consumes(tile_data, good_id)
	return false

func _tile_has_potential(tile_data: Dictionary, good_id: String) -> bool:
	if good_id == "solar" or good_id == "g_solar":
		return tile_data.get("solar_potential", 0) > 0
	if good_id == "wind" or good_id == "g_wind":
		return tile_data.get("wind_potential", 0) > 0
	var deposits: Array = tile_data.get("deposits", [])
	if deposits.is_empty():
		return false
	var internal := Catalog.get_internal_name(good_id)
	return deposits.has(good_id) or deposits.has(internal)

func _tile_produces(tile_data: Dictionary, good_id: String) -> bool:
	var tile_id: String = tile_data.get("id", "")
	var name := Catalog.get_internal_name(good_id)
	match tile_id:
		"tile_12_2": return name == "iron_ore"
		"tile_12_3": return name == "coal"
		"tile_12_4": return name == "coal" or name == "iron_ore"
	return false

func _tile_consumes(tile_data: Dictionary, good_id: String) -> bool:
	return _tile_produces(tile_data, good_id)
