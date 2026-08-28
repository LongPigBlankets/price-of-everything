extends Node2D
## Dev tool: photograph the SAME tile once per company livery, so the eight colours can be
## compared on real buildings rather than as swatches. Needs a window (NOT --headless):
##   <godot> --path . res://tools/livery_sweep_shot.tscn --quit-after 12000 -- \
##       --tile=tile_5_10 --zoom=2.2 --out=artifacts/livery
##
## Default tile is tile_5_10, the metal_magnate start's furnace + power plant: two
## PLAYER-owned stamped buildings on otherwise sparse ground, which is exactly the pair the
## stamp alternation produces (first a rectangle, then an L). A dense town tile would bury
## them in decorative fabric and a mine tile would show only exempt art.
##
## The livery is swapped by writing the match ruleset and repainting -- `_wash_for` reads
## `PlayerColours.active_color()` at DRAW time, so no rebuild of the world is needed.

const PlayerColours := preload("res://scripts/player_colours.gd")

var _wm: Node
var _terrain: TileMapLayer
var _cam: Camera2D


func _ready() -> void:
	var opt := _options()
	var tile_id := str(opt.get("tile", "tile_5_10"))
	var zoom := float(opt.get("zoom", 2.2))
	var out_prefix := str(opt.get("out", "artifacts/livery"))
	var size := Vector2i(900, 700)
	var offset := _parse_vec(str(opt.get("offset", "")))

	# Arm the start BEFORE main.tscn is built, exactly as main_menu does — otherwise the
	# world comes up as the bare NPC map and every building on it is paper-white, which is
	# the one thing this shot cannot show. metal_magnate puts a furnace and a power plant on
	# tile_5_10 (the two stamps) and mines on tile_6_8 / tile_7_10 (exempt art), all
	# player-owned, standing among the NPC buildings already there.
	var start_path := str(opt.get("start", "res://data/starts/metal_magnate.json"))
	SaveLoad.prepare_new_game(start_path, {})

	get_viewport().set_disable_input(true)
	_wm = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(_wm)
	for _i in 150:
		await get_tree().process_frame
	_terrain = _wm.get_node("%TerrainLayer")
	var grid := _wm.find_child("HexGridOverlay", true, false) as CanvasItem
	if grid != null:
		grid.visible = false
	var ui := _wm.get_node_or_null("UILayer") as CanvasLayer
	if ui != null:
		ui.visible = false
	_cam = get_viewport().get_camera_2d()
	if _cam == null:
		push_error("livery_sweep: no game camera")
		get_tree().quit(1)
		return
	_cam.set_process(false)
	_cam.set_physics_process(false)
	if "edge_pan_enabled" in _cam:
		_cam.set("edge_pan_enabled", false)
	MapStyle.set_midcentury(false)

	var visuals := _wm.find_child("BuildingVisuals", true, false)
	if visuals == null:
		push_error("livery_sweep: no BuildingVisuals node")
		get_tree().quit(1)
		return
	_report_tile(visuals, tile_id)

	var pos := _tile_pos(tile_id)
	if pos == Vector2.INF:
		push_error("livery_sweep: unknown tile %s" % tile_id)
		get_tree().quit(3)
		return

	for entry_value in PlayerColours.all():
		var entry: Dictionary = entry_value
		var key := str(entry["key"])
		MatchState.ruleset["company_colour"] = key
		(visuals as CanvasItem).queue_redraw()
		await _shot(pos + offset, zoom, size, "%s_%s.png" % [out_prefix, key])
	print("[LIVERY SWEEP] done")
	get_tree().quit(0)


## Say what is actually on the tile before shooting it, so a blank frame is diagnosed here
## rather than by squinting at eight identical PNGs.
func _report_tile(visuals: Node, tile_id: String) -> void:
	var placements: Variant = visuals.get("_placements")
	if not (placements is Array):
		return
	var n := 0
	for p_value in (placements as Array):
		var p: Dictionary = p_value
		if str(p.get("tile_id", "")) != tile_id:
			continue
		n += 1
		print("[LIVERY SWEEP] %s: %s  npc=%s  verts=%d  cat=%s" % [tile_id,
			str(p.get("iname", "")), str(p.get("is_npc", true)),
			(p.get("verts", PackedVector2Array()) as PackedVector2Array).size(),
			str(p.get("cat", ""))])
	print("[LIVERY SWEEP] %s holds %d placement(s)" % [tile_id, n])


func _tile_pos(tile_id: String) -> Vector2:
	if not _terrain.has_method("id_to_coord"):
		return Vector2.INF
	var coord: Vector2i = _terrain.id_to_coord(tile_id)
	if coord == Vector2i(-1, -1):
		return Vector2.INF
	return _terrain.map_to_local(_terrain.map_coord_for_tile_coord(coord))


func _shot(pos: Vector2, zoom: float, size: Vector2i, path: String) -> void:
	_cam.position = pos
	_cam.zoom = Vector2(zoom, zoom)
	if "_target_zoom" in _cam:
		_cam.set("_target_zoom", _cam.zoom)
	for _i in 12:
		await get_tree().process_frame
	RenderingServer.force_draw()
	var image := get_viewport().get_texture().get_image()
	var crop := Vector2i(mini(size.x, image.get_width()), mini(size.y, image.get_height()))
	var origin := Vector2i((image.get_width() - crop.x) / 2, (image.get_height() - crop.y) / 2)
	image.get_region(Rect2i(origin, crop)).save_png(path)
	print("[LIVERY SWEEP] %s" % path)


func _options() -> Dictionary:
	var out := {}
	for arg in OS.get_cmdline_user_args():
		var a := str(arg)
		if not a.begins_with("--") or not a.contains("="):
			continue
		var bits := a.substr(2).split("=", true, 1)
		if bits.size() == 2:
			out[str(bits[0])] = str(bits[1])
	return out


func _parse_vec(raw: String) -> Vector2:
	var bits := raw.split(",")
	if bits.size() == 2 and str(bits[0]).is_valid_float() and str(bits[1]).is_valid_float():
		return Vector2(float(bits[0]), float(bits[1]))
	return Vector2.ZERO
