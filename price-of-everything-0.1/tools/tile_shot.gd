extends Node2D
## GENERAL-PURPOSE TILE SCREENSHOT TOOL.
##
## One frame per tile, same camera and zoom for every frame, so a set is
## directly comparable. UI, HUD and the hex grid are hidden; the map style is
## forced, so a shot never depends on whatever the last session left selected.
##
## USAGE (from the Godot project root, WINDOWED — headless renders nothing):
##   <godot> --path . res://tools/tile_shot.tscn --quit-after 6000 -- \
##       --tiles=tile_23_8,tile_24_7 --zoom=1.15 --out=/tmp/poe_tile
##
## Every option may also be given as an environment variable, which is handy
## when the command line is already crowded. The command line wins.
##   POE_SHOT_TILES  POE_SHOT_ZOOM  POE_SHOT_SIZE  POE_SHOT_OUT
##   POE_SHOT_STYLE  POE_SHOT_OFFSET
##
## OPTIONS
##   --tiles=a,b,c   tile ids (required). Ids are resolved through id_to_coord,
##                   never by arithmetic on the numbers in the id.
##   --zoom=1.15     larger = closer. 1.35 ~ one tile, 0.6 ~ a region.
##   --start=<id>    seed a scripted start first (data/starts/<id>.json), so its
##                   buildings are on the board in the frame. POE_SHOT_START works too.
##   --size=960x720  output crop, centred on the viewport.
##   --out=/tmp/poe_tile   prefix; each frame lands at <prefix>_<tile_id>.png
##   --style=midcentury|ink|classic|plate
##   --offset=0,-900 world-units nudge applied to every frame, so you can shoot
##                   the water north of a town, or the approach to a port.
##
## Writes <prefix>_<tile>.png per tile and prints one line each, then quits 0.
## Prints the resolved settings first, so a set of frames is self-describing.

## The window every shot is taken in, so two runs are comparable (see _ready).
const WINDOW_SIZE := Vector2i(1920, 1080)
const DEFAULT_ZOOM := 1.15
const DEFAULT_SIZE := Vector2i(960, 720)
const DEFAULT_OUT := "/tmp/poe_tile"
const DEFAULT_STYLE := "midcentury"

var _wm: Node
var _terrain: TileMapLayer
var _cam: Camera2D

func _ready() -> void:
	var opt := _options()
	var tiles: Array = []
	for raw in str(opt.get("tiles", "")).split(",", false):
		var t := str(raw).strip_edges()
		if t != "":
			tiles.append(t)
	if tiles.is_empty():
		push_error("tile_shot: no --tiles=… given (or POE_SHOT_TILES). Nothing to do.")
		get_tree().quit(2)
		return
	var zoom := float(opt.get("zoom", DEFAULT_ZOOM))
	var size := _parse_size(str(opt.get("size", "")))
	var out_prefix := str(opt.get("out", DEFAULT_OUT))
	var style := str(opt.get("style", DEFAULT_STYLE))
	var offset := _parse_vec(str(opt.get("offset", "")))
	print("[TILE SHOT] tiles=%s zoom=%.2f size=%dx%d style=%s offset=(%.0f,%.0f) out=%s" % [
		",".join(PackedStringArray(tiles)), zoom, size.x, size.y, style,
		offset.x, offset.y, out_prefix])

	# Optional: seed a scripted start before booting, so a start's buildings are on the
	# board in the frame (--start=metal_magnate or POE_SHOT_START).
	var start_id := str(opt.get("start", ""))
	if start_id != "":
		SaveLoad.prepare_new_game("res://data/starts/%s.json" % start_id,
			{"ruleset": {"start_id": "", "tutorial_enabled": false}})
		print("[TILE SHOT] seeded start: %s" % start_id)

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
	# PIN THE WINDOW. Two runs of this tool got different window heights (1205 then 1080),
	# which changes the canvas scale and therefore how much world lands inside a fixed centre
	# crop — so an A/B pair shot in two runs compared two different framings while both
	# honestly reported the same camera zoom. `--resolution` does not survive here; setting it
	# explicitly does.
	DisplayServer.window_set_size(WINDOW_SIZE)
	await get_tree().process_frame
	_cam = get_viewport().get_camera_2d()
	if _cam == null:
		push_error("tile_shot: no game camera")
		get_tree().quit(1)
		return
	_cam.set_process(false)
	_cam.set_physics_process(false)
	# Disabling _process stops the per-frame zoom smoothing but NOT the establishing-zoom
	# TWEEN, which drives `zoom` on its own schedule. Two runs of this tool at the same
	# --zoom therefore captured at two different zooms depending on how far that tween had
	# got — which is exactly the sort of thing that makes an A/B comparison lie. Kill both
	# camera tweens before the frame budget starts.
	for field in ["_intro_tween", "_pan_tween"]:
		var tween: Variant = _cam.get(field)
		if tween is Tween and (tween as Tween).is_valid():
			(tween as Tween).kill()
	if "edge_pan_enabled" in _cam:
		_cam.set("edge_pan_enabled", false)
	_apply_style(style)
	for _i in 24:
		await get_tree().process_frame

	var missing: Array = []
	for tid in tiles:
		var pos := _tile_pos(str(tid))
		if pos == Vector2.INF:
			missing.append(tid)
			continue
		await _shot(pos + offset, zoom, size, "%s_%s.png" % [out_prefix, tid])
	if not missing.is_empty():
		push_error("tile_shot: unknown tile ids %s" % str(missing))
		get_tree().quit(3)
		return
	print("[TILE SHOT] done")
	get_tree().quit(0)

## Environment first, command line (after a bare `--`) second, so the explicit
## argument always wins — same precedence the port/limits seams use.
func _options() -> Dictionary:
	var out := {}
	for pair in [["tiles", "POE_SHOT_TILES"], ["zoom", "POE_SHOT_ZOOM"],
			["size", "POE_SHOT_SIZE"], ["out", "POE_SHOT_OUT"],
			["style", "POE_SHOT_STYLE"], ["offset", "POE_SHOT_OFFSET"],
			["start", "POE_SHOT_START"]]:
		var env := OS.get_environment(str(pair[1]))
		if env != "":
			out[str(pair[0])] = env
	for arg in OS.get_cmdline_user_args():
		var a := str(arg)
		if not a.begins_with("--") or not a.contains("="):
			continue
		var bits := a.substr(2).split("=", true, 1)
		if bits.size() == 2:
			out[str(bits[0])] = str(bits[1])
	return out

func _parse_size(raw: String) -> Vector2i:
	var bits := raw.to_lower().split("x")
	if bits.size() == 2 and str(bits[0]).is_valid_int() and str(bits[1]).is_valid_int():
		return Vector2i(int(bits[0]), int(bits[1]))
	return DEFAULT_SIZE

func _parse_vec(raw: String) -> Vector2:
	var bits := raw.split(",")
	if bits.size() == 2 and str(bits[0]).is_valid_float() and str(bits[1]).is_valid_float():
		return Vector2(float(bits[0]), float(bits[1]))
	return Vector2.ZERO

func _apply_style(style: String) -> void:
	match style:
		"ink":
			MapStyle.set_midcentury(false)
		"classic", "plate":
			MapStyle.set_midcentury(false)
		_:
			MapStyle.set_midcentury(true)

## World position of a tile id. Resolved through the terrain layer's own
## id_to_coord — NEVER by arithmetic on the digits in the id, which resolves to
## the wrong tile (ids are coord+1, and that bug once cost days of measuring
## the wrong settlement).
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
		_cam.set("_target_zoom", Vector2(zoom, zoom))
	for _i in 18:
		await get_tree().process_frame
	RenderingServer.force_draw()
	# The zoom AS CAPTURED, not as requested: the camera is reconfigured by the map build on
	# its own schedule, so a run that shoots before or after that lands is a different picture.
	# Two runs of an A/B pair silently differing here is worse than no comparison at all.
	print("[TILE SHOT] captured at zoom=%.3f (asked %.3f), viewport=%s" % [
		_cam.zoom.x, zoom, str(get_viewport().get_visible_rect().size)])
	var image := get_viewport().get_texture().get_image()
	var crop := Vector2i(mini(size.x, image.get_width()), mini(size.y, image.get_height()))
	var origin := Vector2i((image.get_width() - crop.x) / 2, (image.get_height() - crop.y) / 2)
	image.get_region(Rect2i(origin, crop)).save_png(path)
	print("[TILE SHOT] %s" % path)
