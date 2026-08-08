extends Node
## Frame a named set of tiles and save a PNG. Windowed only (draw code never runs headless).
##   REGION_TILES=tile_4_9,tile_5_10 REGION_ZOOM=0.8 REGION_OUT=/tmp/x.png \
##     <godot> --path . res://tools/region_shot.tscn --quit-after 3000
##
## Same camera rules as map_style_shot, for the same reasons: drive the GAME camera
## with its _process stopped (a second Camera2D loses to the controller's re-centre)
## and await frame_post_draw before saving (get_image returns the last PRESENTED
## frame, which is how several "different" captures once came out byte-identical).

func _ready() -> void:
	get_viewport().set_disable_input(true)
	var wm: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(wm)
	for _i in 180:
		await get_tree().process_frame
	var terrain: Node = wm.get_node("%TerrainLayer")
	var grid: Node = wm.find_child("HexGridOverlay", true, false)
	if grid != null:
		(grid as CanvasItem).visible = false
	var cam: Camera2D = get_viewport().get_camera_2d()
	if cam == null:
		push_error("region_shot: no game camera")
		get_tree().quit(1)
		return
	cam.set_process(false)
	cam.set_physics_process(false)
	if "edge_pan_enabled" in cam:
		cam.set("edge_pan_enabled", false)

	var ids := OS.get_environment("REGION_TILES").split(",", false)
	var c := Vector2.ZERO
	var n := 0
	for tid in ids:
		var coord: Vector2i = terrain.id_to_coord(tid.strip_edges())
		if coord == Vector2i(-1, -1):
			continue
		c += terrain.map_to_local(terrain.map_coord_for_tile_coord(coord))
		n += 1
	if n == 0:
		push_error("region_shot: no valid tiles in REGION_TILES")
		get_tree().quit(1)
		return
	var zoom := float(OS.get_environment("REGION_ZOOM")) if OS.get_environment("REGION_ZOOM") != "" else 0.8
	cam.position = c / float(n)
	cam.zoom = Vector2(zoom, zoom)
	if "_target_zoom" in cam:
		cam.set("_target_zoom", Vector2(zoom, zoom))
	for _j in 40:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var out := OS.get_environment("REGION_OUT")
	if out == "":
		out = "/tmp/poe_region_shot.png"
	get_viewport().get_texture().get_image().save_png(out)
	print("[REGIONSHOT] %s  centre=%s zoom=%.2f tiles=%d" % [out, str(cam.position), zoom, n])
	get_tree().quit()
