extends Node
## Renders a saved map document in the real game and reports, tile by tile, what actually
## draws — the check to run after saving something in the editor.
##
##   <godot> --path . res://tools/map_editor/authored_render_check.tscn --quit-after 12000 \
##       -- --doc=capital-draft
##
## Options: `--doc=<name>` (default: whichever document is active), `--zoom`, `--size`,
## `--out`. It captures one frame per authored tile and prints a table:
##
##   tile          roads  flagged  visible   what it means
##   tile_23_8         4      yes        4   all four draw
##   tile_23_9         2       no        0   both are unlockable and correctly hidden
##
## It changes NOTHING: the active pointer is read, never written, and the document is not
## modified. WINDOWED ONLY — `--headless` renders nothing.

const AuthoredMap := preload("res://scripts/authored_map.gd")

const DEFAULT_ZOOM := 0.75
const DEFAULT_SIZE := Vector2i(1200, 760)
const DEFAULT_OUT := "/tmp/poe_authored_render"
const SETTLE_FRAMES := 150
const PAINT_FRAMES := 18

var _doc_name := ""
var _zoom := DEFAULT_ZOOM
var _size := DEFAULT_SIZE
var _out := DEFAULT_OUT


func _ready() -> void:
	_parse_options()
	get_window().size = _size
	if _doc_name != "":
		AuthoredMap.set_override(_doc_name)
	var name := AuthoredMap.active_name()
	if name == "":
		push_error("[RENDER] no document selected — save one in the editor, or pass --doc=<name>")
		get_tree().quit(1)
		return
	if not FileAccess.file_exists(AuthoredMap.path_for(name)):
		push_error("[RENDER] '%s' does not exist. On disk: %s"
			% [name, ", ".join(AuthoredMap.list_documents())])
		get_tree().quit(1)
		return
	print("[RENDER] document '%s'" % name)

	var settlements := AuthoredMap.settlements()
	if settlements.is_empty():
		# An empty result here means the loader REJECTED the document (it warns why) or the
		# document authors nothing — either way the game would draw none of it.
		push_error("[RENDER] '%s' loaded as empty — see the warning above for why" % name)
		get_tree().quit(1)
		return

	var world := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(world)
	for _i in SETTLE_FRAMES:
		await get_tree().process_frame
	var ui := world.get_node_or_null(NodePath("UILayer"))
	if ui != null:
		(ui as CanvasLayer).visible = false
	var grid := world.get_node_or_null(NodePath("HexGridOverlay"))
	if grid != null:
		(grid as CanvasItem).visible = false
	var layer := world.get_node_or_null(NodePath("AuthoredRoadVisuals"))
	if layer == null:
		push_error("[RENDER] AuthoredRoadVisuals is not in the scene")
		get_tree().quit(1)
		return

	var camera := get_viewport().get_camera_2d()
	camera.set_process(false)
	camera.set_physics_process(false)
	if "edge_pan_enabled" in camera:
		camera.set("edge_pan_enabled", false)
	var terrain := get_tree().get_first_node_in_group("hex_map")

	# What the renderer says is on screen right now, by stroke id.
	var visible_ids: Dictionary = {}
	for id in (layer.call("visible_stroke_ids") as PackedStringArray):
		visible_ids[str(id)] = true

	var rows: Array = []
	var hidden_total := 0
	for settlement_key in settlements.keys():
		var settlement: Dictionary = settlements[settlement_key]
		var per_tile: Dictionary = {}
		for stroke_value in (settlement.get("roads", []) as Array):
			var stroke: Dictionary = stroke_value
			for tile_value in (stroke.get("tiles", []) as Array):
				var tile_id := str(tile_value)
				if not per_tile.has(tile_id):
					per_tile[tile_id] = {"total": 0, "visible": 0, "unlockable": 0}
				var row: Dictionary = per_tile[tile_id]
				row["total"] = int(row["total"]) + 1
				if bool(stroke.get("unlockable", false)):
					row["unlockable"] = int(row["unlockable"]) + 1
				if visible_ids.has(str(stroke.get("id", ""))):
					row["visible"] = int(row["visible"]) + 1
		var tile_ids := per_tile.keys()
		tile_ids.sort()
		print("[RENDER] settlement '%s' — %d tiles" % [settlement_key, tile_ids.size()])
		print("[RENDER]   %-14s %6s %8s %8s %10s" % ["tile", "roads", "unlock", "flagged", "drawing"])
		for tile_id in tile_ids:
			var row: Dictionary = per_tile[tile_id]
			var flagged := _flagged(terrain, str(tile_id))
			print("[RENDER]   %-14s %6d %8d %8s %10d" % [tile_id, int(row["total"]),
				int(row["unlockable"]), "yes" if flagged else "no", int(row["visible"])])
			if int(row["visible"]) == 0:
				hidden_total += 1
			rows.append({"tile": str(tile_id), "row": row, "flagged": flagged})

	# One frame per authored tile, so every claim above has a picture behind it.
	for entry_value in rows:
		var entry: Dictionary = entry_value
		var tile_id: String = entry["tile"]
		var coord: Vector2i = terrain.call("id_to_coord", tile_id)
		if not (terrain.get("tiles") as Dictionary).has(coord):
			print("[RENDER]   ! %s is not a tile on this map" % tile_id)
			continue
		camera.position = terrain.call("map_to_local", terrain.call("map_coord_for_tile_coord", coord))
		camera.zoom = Vector2(_zoom, _zoom)
		if "_target_zoom" in camera:
			camera.set("_target_zoom", camera.zoom)
		for _i in PAINT_FRAMES:
			await get_tree().process_frame
		RenderingServer.force_draw()
		var path := "%s_%s.png" % [_out, tile_id]
		get_viewport().get_texture().get_image().save_png(path)
		print("[RENDER] wrote %s" % path)

	# WHY a stroke is hidden matters more than the fact of it. The connection rule is
	# all-or-nothing across every tile a stroke touches, so ONE roadless tile hides the whole
	# run — including the parts crossing tiles that are already roaded. Naming the blocking
	# tiles is the difference between "it works" and knowing what to do about it.
	for settlement_key in settlements.keys():
		var settlement: Dictionary = settlements[settlement_key]
		for stroke_value in (settlement.get("roads", []) as Array):
			var stroke: Dictionary = stroke_value
			var id := str(stroke.get("id", ""))
			if visible_ids.has(id) or not bool(stroke.get("unlockable", false)):
				continue
			var blocking: PackedStringArray = []
			var spans := (stroke.get("tiles", []) as Array).size()
			for tile_value in (stroke.get("tiles", []) as Array):
				if not _flagged(terrain, str(tile_value)):
					blocking.append(str(tile_value))
			print("[RENDER] hidden %s (%s, spans %d tiles) — waiting on: %s"
				% [id, str(stroke.get("class", "")), spans, ", ".join(blocking)])
	print("[RENDER] %d tile(s) authored, %d drawing nothing yet (unlockable, tile still roadless)"
		% [rows.size(), hidden_total])
	get_tree().quit(0)


func _flagged(terrain: Node, tile_id: String) -> bool:
	var coord: Vector2i = terrain.call("id_to_coord", tile_id)
	var tiles: Dictionary = terrain.get("tiles")
	if not tiles.has(coord):
		return false
	return ((tiles[coord] as Dictionary).get("infrastructure_present", []) as Array).has("roads")


func _parse_options() -> void:
	for argument in OS.get_cmdline_user_args():
		var text := str(argument)
		if text.begins_with("--doc="):
			_doc_name = text.substr(6)
		elif text.begins_with("--zoom="):
			_zoom = float(text.substr(7))
		elif text.begins_with("--out="):
			_out = text.substr(6)
		elif text.begins_with("--size="):
			var parts := text.substr(7).split("x", false)
			if parts.size() == 2 and parts[0].is_valid_int() and parts[1].is_valid_int():
				_size = Vector2i(int(parts[0]), int(parts[1]))
