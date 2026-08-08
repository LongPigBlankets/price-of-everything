extends Node2D
# Dev-only: farms AND forests on one tile, to check that fields tuck UNDER the canopy
# (FarmUnderlay draws below ForestVisuals) instead of painting over the trees.
# Run (windowed, NOT --headless, so it actually renders):
#   Godot --path . res://tools/farm_forest_shot.tscn --quit-after 600   -> res://farm_forest_shot.png

var _bv
var _fv
var _frame := 0

func _ready() -> void:
	var terrain := TileMapLayer.new()
	terrain.tile_set = load("res://assets/main_tileset.tres")
	terrain.set_script(load("res://scripts/hex_map.gd"))
	add_child(terrain)
	await get_tree().process_frame
	await get_tree().process_frame
	RoadNetwork.reset()
	# ForestVisuals must exist BEFORE BuildingVisuals so the underlay can slot in front of it,
	# mirroring the node order in main.tscn.
	_fv = Node2D.new()
	_fv.name = "ForestVisuals"
	_fv.set_script(load("res://scripts/forest_visuals.gd"))
	add_child(_fv)
	_bv = preload("res://scenes/building_visuals.gd").new()
	_bv.name = "BuildingVisuals"
	add_child(_bv)
	await get_tree().process_frame
	_fv.terrain_layer = terrain
	_bv.terrain_layer = terrain

	var tile_id := "tile_9_10"
	var coord: Vector2i = terrain.id_to_coord(tile_id)
	# Two woods first, so the farm layout sees them as obstacles to nestle under.
	for i in 2:
		var fid: String = MatchState.add_building("b_016", "", tile_id, "npc", "forest_%d" % i)
		if _fv.has_method("on_building_placed"):
			_fv.on_building_placed(tile_id, "b_016", "", fid, coord)
	for i in 8:
		var iid: String = MatchState.add_building("b_014", "", tile_id, "npc", "shot_%d" % i)
		_bv.on_building_placed(tile_id, "b_014", "", iid, coord)
	_bv._rebuild_subcomponents(tile_id)

	var c: Vector2 = terrain.map_to_local(terrain.map_coord_for_tile_coord(coord))
	var cam := Camera2D.new()
	cam.position = c
	cam.zoom = Vector2(2.5, 2.5)
	add_child(cam)
	cam.make_current()
	_fv.queue_redraw()
	_bv.queue_redraw()

func _process(_d: float) -> void:
	_frame += 1
	if _frame == 10:
		var img := get_viewport().get_texture().get_image()
		img.save_png("res://farm_forest_shot.png")
		print("SAVED farm_forest_shot.png ", img.get_width(), "x", img.get_height())
		get_tree().quit()
