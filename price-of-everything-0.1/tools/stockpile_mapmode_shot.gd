extends Node2D
## Dev tool: render the Stockpile mapmode's four states side by side. A real game reaches them
## over dozens of turns, so this stocks four neighbouring tiles directly through the real
## Stockpile API — including overfilling one, which is what sets the refusal counter the flash
## reads. Two frames are saved 0.3 s apart so both halves of the flash are on record.
##   "$GODOT_BIN" --path . res://tools/stockpile_mapmode_shot.tscn --quit-after 900
var _wm

func _ready() -> void:
	get_window().size = Vector2i(1920, 1080)
	_wm = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(_wm)
	for _i in range(160):
		await get_tree().process_frame

	var terrain = _wm.find_child("TerrainLayer", true, false)
	if terrain == null:
		print("[STOCK_MM] no terrain layer"); get_tree().quit(1); return
	var good_id := ""
	for g in Catalog.all_goods():
		good_id = str((g as Dictionary).get("id", ""))
		if good_id != "":
			break

	# Four adjacent land tiles so one screenshot holds every state.
	var picks: Array = []
	var centre := Vector2.ZERO
	for coord in terrain.tiles:
		var td: Dictionary = terrain.tiles[coord]
		var ttype := str(td.get("type", ""))
		if ttype == "sea" or ttype == "deep_sea":
			continue
		var tid := str(td.get("id", ""))
		if tid == "":
			continue
		picks.append({"id": tid, "coord": coord})
		centre += terrain.map_to_local(terrain.map_coord_for_tile_coord(coord))
		if picks.size() == 4:
			break
	if picks.size() < 4:
		print("[STOCK_MM] not enough land tiles"); get_tree().quit(1); return
	centre /= float(picks.size())

	# 30% / 85% / 97% / overfilled — the last one's surplus is what get_refused() reports.
	var fills := [0.30, 0.85, 0.97, 1.0]
	for i in picks.size():
		var tid: String = str(picks[i].id)
		var cap := Stockpile.get_capacity(tid)
		var want := int(round(cap * float(fills[i])))
		Stockpile.add(tid, good_id, want)
		if i == 3:
			Stockpile.add(tid, good_id, 250)   # no room left: 250 units turned away
		print("[STOCK_MM] %s used=%d/%d refused=%d" % [
			tid, Stockpile.get_used_capacity(tid), cap, Stockpile.get_refused(tid)])

	# Filling a tile to the brim legitimately raises the "reached maximum capacity" prompt.
	# That is the game reacting correctly to the setup; it just sits over the map, so close it.
	for _i in range(4):
		await get_tree().process_frame
	for node in _wm.find_children("*", "PanelContainer", true, false):
		if node.get_script() != null and str(node.get_script().resource_path).ends_with("capacity_dialog.gd"):
			(node as Control).hide()

	var cam := get_viewport().get_camera_2d()
	if cam != null:
		cam.set("edge_pan_enabled", false)
		cam.position = centre
		cam.zoom = Vector2(1.7, 1.7)

	MapMode.set_sentinel_mode(MapMode.Mode.STOCKPILE, MapMode.STOCKPILE_SENTINEL)
	for _i in range(12):
		await get_tree().process_frame

	var overlay = _wm.find_child("StockpileOverlay", true, false)
	print("[STOCK_MM] mode=%d tinted_tiles=%d has_blocked=%s" % [
		MapMode.current_mode, (overlay._tiles.size() if overlay else -1),
		str(overlay._has_blocked if overlay else false)])
	for entry in (overlay._tiles if overlay else []):
		print("[STOCK_MM]   colour=%s blocked=%s" % [
			(entry.color as Color).to_html(false), str(entry.blocked)])

	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://stockpile_mapmode_shot.png")
	# The other half of the flash: the overlay toggles every FLASH_SECONDS.
	var was: bool = overlay._flash_on if overlay else false
	for _i in range(90):
		await get_tree().process_frame
		if overlay != null and overlay._flash_on != was:
			break
	print("[STOCK_MM] flash flipped %s -> %s" % [str(was), str(overlay._flash_on if overlay else false)])
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://stockpile_mapmode_flash.png")
	print("SAVED stockpile_mapmode_shot.png + _flash.png")
	get_tree().quit()
