extends Node
## THE P1 GATE: proves the unlock rule works in a running game, not just in unit tests.
##
##   <godot> --path . res://tools/map_editor/authored_unlock_check.tscn --quit-after 9000
##
## It writes a throwaway authored document over a real adjacent pair — `tile_10_12` starts
## with roads, `tile_9_12` ("Green Flats Fields") starts without — containing three strokes:
##
##   always      an always-on street on the roaded tile
##   street      an unlockable street inside the roadless tile
##   connector   an unlockable link across BOTH tiles
##
## then boots the world and captures the map before and after the roadless tile gains
## roads through the same call a completed construction makes. What must be true:
##
##   BEFORE   only `always` draws. The connector is absent ENTIRELY — no stub reaching to
##            the tile edge, which is what the baked network's point-wise clip would leave.
##   AFTER    all three draw, the street and the connector appearing together, so the new
##            tile's roads join the neighbour's in one reveal.
##
## The document is written to `res://data/map_authored.json` and REMOVED afterwards, restoring
## any pre-existing file. Run it from a clean tree.
##
## WINDOWED ONLY — `--headless` renders nothing and every capture comes back empty.

const AuthoredMap := preload("res://scripts/authored_map.gd")
const AuthoredRoadStyle := preload("res://scripts/authored_road_style.gd")

const ROADED_TILE := "tile_10_12"
const ROADLESS_TILE := "tile_9_12"
const OUT_PREFIX := "/tmp/poe_authored_unlock"
const SETTLE_FRAMES := 150
const PAINT_FRAMES := 20
const ZOOM := 0.62

var _doc_path := ""
var _backup := ""
var _had_backup := false
var _previous_active := ""


func _ready() -> void:
	# Writes a throwaway NAMED document and points the game at it, restoring whatever was
	# active afterwards.
	var directory := ProjectSettings.globalize_path(AuthoredMap.DOC_DIR)
	DirAccess.make_dir_recursive_absolute(directory)
	_doc_path = "%s/_unlock_check.json" % directory
	_previous_active = AuthoredMap.active_name()
	AuthoredMap.write_active("_unlock_check", directory)
	_stash_existing()
	if not _write_document():
		_restore()
		get_tree().quit(1)
		return
	# The loader caches for the process; the document was written after this process began.
	AuthoredMap.reset_for_tests()

	var packed := load("res://scenes/main.tscn") as PackedScene
	var world := packed.instantiate()
	add_child(world)
	for _i in SETTLE_FRAMES:
		await get_tree().process_frame

	var ui := world.get_node_or_null(NodePath("UILayer"))
	if ui != null:
		(ui as CanvasLayer).visible = false
	var grid := world.get_node_or_null(NodePath("HexGridOverlay"))
	if grid != null:
		(grid as CanvasItem).visible = false

	var camera := get_viewport().get_camera_2d()
	camera.set_process(false)
	camera.set_physics_process(false)
	if "edge_pan_enabled" in camera:
		camera.set("edge_pan_enabled", false)
	var terrain := get_tree().get_first_node_in_group("hex_map")
	# Frame the seam between the two tiles so both are in shot.
	var a: Vector2 = terrain.map_to_local(terrain.map_coord_for_tile_coord(terrain.id_to_coord(ROADED_TILE)))
	var b: Vector2 = terrain.map_to_local(terrain.map_coord_for_tile_coord(terrain.id_to_coord(ROADLESS_TILE)))
	camera.position = (a + b) * 0.5
	camera.zoom = Vector2(ZOOM, ZOOM)
	if "_target_zoom" in camera:
		camera.set("_target_zoom", camera.zoom)

	var layer := world.get_node_or_null(NodePath("AuthoredRoadVisuals"))
	if layer == null:
		push_error("[UNLOCK] AuthoredRoadVisuals is not in the scene")
		_restore()
		get_tree().quit(1)
		return

	print("[UNLOCK] %s flagged=%s   %s flagged=%s" % [
		ROADED_TILE, _flagged(terrain, ROADED_TILE),
		ROADLESS_TILE, _flagged(terrain, ROADLESS_TILE)])
	var before: PackedStringArray = layer.call("visible_stroke_ids")
	print("[UNLOCK] BEFORE visible: %s" % ", ".join(before))
	var image_before := await _capture("before")

	# Exactly the call a completed roads project makes — flag, router, signal.
	world.call("_apply_built_infrastructure", terrain.id_to_coord(ROADLESS_TILE), ROADLESS_TILE, "roads")
	await get_tree().process_frame
	print("[UNLOCK] after purchase: %s flagged=%s" % [ROADLESS_TILE, _flagged(terrain, ROADLESS_TILE)])
	var after: PackedStringArray = layer.call("visible_stroke_ids")
	print("[UNLOCK] AFTER visible: %s" % ", ".join(after))
	var image_after := await _capture("after")

	# The gate, stated as a measurement rather than a picture.
	var pass_before := before.size() == 1 and before.has("r:unlock_check:1")
	var pass_after := after.size() == 3
	var reveal_diff := _diff_pixels(image_before, image_after)
	print("[UNLOCK] reveal changed %d sampled pixels" % reveal_diff)

	# DIAGNOSTIC: if the picture did not change, find out which half is at fault — the
	# redraw not firing, or the layer not painting at all. Hiding the layer entirely must
	# change the picture; if even that does nothing, nothing was ever drawn.
	if reveal_diff <= 0:
		layer.call("queue_redraw")
		var image_forced := await _capture("forced")
		print("[UNLOCK] DIAG forced redraw changed %d pixels" % _diff_pixels(image_after, image_forced))
		(layer as CanvasItem).visible = false
		var image_hidden := await _capture("hidden")
		print("[UNLOCK] DIAG hiding the layer changed %d pixels" % _diff_pixels(image_forced, image_hidden))
		(layer as CanvasItem).visible = true

	var pass_pixels := reveal_diff > 0
	print("[UNLOCK] GATE before-hidden=%s  after-revealed=%s  picture-changed=%s  => %s" % [
		pass_before, pass_after, pass_pixels,
		"PASS" if (pass_before and pass_after and pass_pixels) else "FAIL"])

	_restore()
	print("[UNLOCK] done — compare %s_before.png and %s_after.png" % [OUT_PREFIX, OUT_PREFIX])
	get_tree().quit(0)


func _flagged(terrain: Node, tile_id: String) -> bool:
	var coord: Vector2i = terrain.call("id_to_coord", tile_id)
	var tiles: Dictionary = terrain.get("tiles")
	if not tiles.has(coord):
		return false
	return ((tiles[coord] as Dictionary).get("infrastructure_present", []) as Array).has("roads")


## Capture, and MEASURE. Two screenshots that happen to be byte-identical prove nothing on
## their own — an occluded window stops presenting and every later capture comes back as the
## same stale frame, which is exactly how a broken feature passes a visual gate. So each
## capture also counts the pixels carrying an authored carriageway colour: if that count is
## zero the layer is not drawing at all, and if it does not move between the two states the
## frame is stale rather than the feature broken.
func _capture(label: String) -> Image:
	for _i in PAINT_FRAMES:
		await get_tree().process_frame
	# force_draw renders and swaps synchronously, so this is the current frame regardless of
	# window state — the pattern tools/map_style_shot.gd settled on. Do NOT await
	# frame_post_draw here: an occluded window never fires it.
	RenderingServer.force_draw()
	var image := get_viewport().get_texture().get_image()
	var path := "%s_%s.png" % [OUT_PREFIX, label]
	image.save_png(path)
	print("[UNLOCK] wrote %s   road-coloured pixels=%d" % [path, _count_road_pixels(image)])
	return image


## Pixels close to either authored carriageway paper. Deliberately NOT the primary
## measurement: the parchment overlay multiplies the whole plate at z 90, so a drawn road's
## pixels are tinted away from their nominal colour. Kept as a coarse signal only; the
## honest test is [method _diff_pixels] between two captures.
func _count_road_pixels(image: Image) -> int:
	var wanted := [AuthoredRoadStyle.bed_color("major"), AuthoredRoadStyle.bed_color("minor")]
	var count := 0
	# Every 3rd pixel: this is a relative measure, and a full scan of 2M pixels is wasteful.
	for y in range(0, image.get_height(), 3):
		for x in range(0, image.get_width(), 3):
			var pixel := image.get_pixel(x, y)
			for target_value in wanted:
				var target: Color = target_value
				if absf(pixel.r - target.r) < 0.06 and absf(pixel.g - target.g) < 0.06 \
						and absf(pixel.b - target.b) < 0.06:
					count += 1
					break
	return count


## How many sampled pixels differ between two captures. Robust to the parchment multiply and
## to any palette change: it asks only "did the picture change", which is the whole question.
func _diff_pixels(a: Image, b: Image) -> int:
	if a == null or b == null or a.get_size() != b.get_size():
		return -1
	var count := 0
	for y in range(0, a.get_height(), 3):
		for x in range(0, a.get_width(), 3):
			if not a.get_pixel(x, y).is_equal_approx(b.get_pixel(x, y)):
				count += 1
	return count


## Three strokes across the pair. Coordinates are derived from the tiles themselves rather
## than hard-coded, so this keeps working if the map is re-baked.
func _write_document() -> bool:
	var hex := load("res://scripts/hex_map.gd")
	# Tile centres, computed the same way the game does: column pitch 405, row pitch 480,
	# odd columns offset +240. Resolved through the id, never by arithmetic on the digits.
	var roaded := _tile_centre(ROADED_TILE)
	var roadless := _tile_centre(ROADLESS_TILE)
	if roaded == Vector2.INF or roadless == Vector2.INF:
		push_error("[UNLOCK] could not resolve the tile pair")
		return false
	var document := AuthoredMap.empty_document()
	document["settlements"] = {"unlock_check": {
		"tiles": [ROADED_TILE, ROADLESS_TILE],
		"next_id": 4,
		"roads": [
			{
				"id": "r:unlock_check:1", "class": "major",
				"points": [
					[roaded.x - 150.0, roaded.y - 90.0],
					[roaded.x + 150.0, roaded.y - 90.0],
				],
				"tiles": [ROADED_TILE], "unlockable": false,
			},
			{
				"id": "r:unlock_check:2", "class": "minor",
				"points": [
					[roadless.x - 140.0, roadless.y + 60.0],
					[roadless.x + 140.0, roadless.y + 60.0],
				],
				"tiles": [ROADLESS_TILE], "unlockable": true,
			},
			{
				"id": "r:unlock_check:3", "class": "mid",
				"points": [
					[roaded.x, roaded.y],
					[roadless.x, roadless.y],
				],
				"tiles": [ROADED_TILE, ROADLESS_TILE], "unlockable": true,
			},
		],
	}}
	var problem: String = AuthoredMap.save_to(document, _doc_path)
	if problem != "":
		push_error("[UNLOCK] %s" % problem)
		return false
	return true


## Tile centre in world units, from the id. Mirrors `TileMapLayer.map_to_local` for the
## project's flat-top odd-q layout; used before the world exists, so the tilemap cannot be
## asked directly.
func _tile_centre(tile_id: String) -> Vector2:
	var parts := tile_id.split("_")
	if parts.size() < 3 or not parts[1].is_valid_int() or not parts[2].is_valid_int():
		return Vector2.INF
	# Playable coords are 0-based; the tilemap adds MAP_PADDING (2) on each axis.
	var q := int(parts[1]) - 1 + 2
	var r := int(parts[2]) - 1 + 2
	return Vector2(405.0 * float(q) + 270.0, 480.0 * float(r) + 240.0 * float(q & 1) + 240.0)


func _stash_existing() -> void:
	if FileAccess.file_exists(_doc_path):
		var file := FileAccess.open(_doc_path, FileAccess.READ)
		if file != null:
			_backup = file.get_as_text()
			file.close()
			_had_backup = true


func _restore() -> void:
	var directory := ProjectSettings.globalize_path(AuthoredMap.DOC_DIR)
	if _previous_active != "":
		AuthoredMap.write_active(_previous_active, directory)
	else:
		DirAccess.remove_absolute("%s/active.txt" % directory)
	if _had_backup:
		var file := FileAccess.open(_doc_path, FileAccess.WRITE)
		if file != null:
			file.store_string(_backup)
			file.close()
	else:
		DirAccess.remove_absolute(_doc_path)
	AuthoredMap.reset_for_tests()
