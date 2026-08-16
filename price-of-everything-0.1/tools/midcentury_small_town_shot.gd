extends Node2D
## Focused second-attempt evidence for compact-town post-parcel micro-massing.

const TARGETS := {
	"pepper_core": {"tile": "tile_5_4", "zoom": 1.20},
	"pepper_docks": {"tile": "tile_6_5", "zoom": 1.20},
	"klade_core": {"tile": "tile_2_4", "zoom": 1.20},
	"klade_docks": {"tile": "tile_3_3", "zoom": 1.20},
}

func _ready() -> void:
	get_viewport().set_disable_input(true)
	var game := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(game)
	for _i in 150:
		await get_tree().process_frame
	var terrain := game.get_node("%TerrainLayer") as TileMapLayer
	var camera := get_viewport().get_camera_2d()
	var ui := game.get_node_or_null("UILayer") as CanvasLayer
	if ui != null:
		ui.visible = false
	var grid := game.find_child("HexGridOverlay", true, false) as CanvasItem
	if grid != null:
		grid.visible = false
	camera.set_process(false)
	camera.set_physics_process(false)
	MapStyle.set_midcentury(true)
	for _i in 30:
		await get_tree().process_frame
	for name_value in TARGETS:
		var name := str(name_value)
		var target: Dictionary = TARGETS[name]
		var coord: Vector2i = terrain.id_to_coord(str(target.tile))
		camera.position = terrain.map_to_local(terrain.map_coord_for_tile_coord(coord))
		camera.zoom = Vector2.ONE * float(target.zoom)
		if "_target_zoom" in camera:
			camera.set("_target_zoom", camera.zoom)
		for _i in 18:
			await get_tree().process_frame
		RenderingServer.force_draw()
		var image := get_viewport().get_texture().get_image()
		var size := Vector2i(mini(960, image.get_width()), mini(540, image.get_height()))
		var origin := Vector2i((image.get_width() - size.x) / 2,
			(image.get_height() - size.y) / 2)
		image.get_region(Rect2i(origin, size)).save_png(
			"/tmp/poe_small_town_%s.png" % name)
		print("[SMALL TOWN] /tmp/poe_small_town_%s.png" % name)
	var fabric := game.find_child("UrbanFabricVisuals", true, false) as UrbanFabricVisuals
	var metrics := fabric.metrics()
	var record := {"settlements": {}, "profiles": metrics.get("tile_profiles", {})}
	for key_value in metrics.get("settlements", {}):
		var key := str(key_value)
		var settlement: Dictionary = metrics.settlements[key]
		if (settlement.get("tiles", []) as Array).any(func(tile_id: Variant):
			return str(tile_id) in ["tile_5_4", "tile_6_5", "tile_2_4", "tile_3_3"]):
			record.settlements[key] = settlement
	var file := FileAccess.open("/tmp/poe_small_town_metrics.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(record, "  "))
	file.close()
	MapStyle.set_midcentury(false)
	game.queue_free()
	for _i in 8:
		await get_tree().process_frame
	RenderingServer.force_draw()
	get_tree().quit(0)
