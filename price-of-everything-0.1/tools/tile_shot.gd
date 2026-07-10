extends Node2D
## TEMP: closeup render of one tile (env TILE_ID), saved as tile_shot.png.
var _frame := 0
func _ready() -> void:
	var packed := load("res://scenes/main.tscn") as PackedScene
	var wm = packed.instantiate()
	add_child(wm)
	for _i in 20:
		await get_tree().process_frame
	var terrain = wm.get_node("%TerrainLayer")
	var tid := OS.get_environment("TILE_ID")
	var coord: Vector2i = terrain.id_to_coord(tid)
	var cam := Camera2D.new()
	cam.position = terrain.map_to_local(terrain.map_coord_for_tile_coord(coord))
	cam.zoom = Vector2(1.05, 1.05)
	if "edge_pan_enabled" in cam:
		cam.edge_pan_enabled = false
	add_child(cam)
	cam.make_current()
	for _j in 10:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("res://tile_shot_%s.png" % tid)
	print("SAVED tile_shot_%s.png" % tid)
	get_tree().quit()
