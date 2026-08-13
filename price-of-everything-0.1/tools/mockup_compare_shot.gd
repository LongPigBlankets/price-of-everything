extends Node2D
## Close framings of the tiles the owner cited when comparing the live map
## against the board-game mockup: the two port tiles (Arin, Stoneshore) and the
## two dense urban tiles. Same camera-hijack pattern as map_style_shot.gd.
##   <godot> --path . res://tools/mockup_compare_shot.tscn --quit-after 1600

const TARGETS := {
	"arinport": "tile_11_17",     # Arin City (Arin Estuary Docks)
	"arindocks": "tile_10_17",    # Arin City Docks
	"stoneshore": "tile_4_9",     # Stoneshore (dense urban)
	"stonedocks": "tile_5_10",    # Stoneshore Docks
	"arinold": "tile_10_16",      # Arin City Old Quarter
}

var _wm: Node = null
var _terrain: TileMapLayer = null
var _cam: Camera2D = null

func _ready() -> void:
	get_viewport().set_disable_input(true)
	_wm = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(_wm)
	for _i in 150:
		await get_tree().process_frame
	print("[SHOT] settle done")
	_terrain = _wm.get_node("%TerrainLayer")
	var grid: Node = _wm.find_child("HexGridOverlay", true, false)
	if grid != null:
		(grid as CanvasItem).visible = false
	_cam = get_viewport().get_camera_2d()
	if _cam == null:
		push_error("mockup_compare_shot: no game camera")
		get_tree().quit(1)
		return
	_cam.set_process(false)
	_cam.set_physics_process(false)
	if "edge_pan_enabled" in _cam:
		_cam.set("edge_pan_enabled", false)
	MapStyle.set_midcentury(false)
	MapStyle.set_ink(true)
	MapStyle.set_plate(false)
	for _i in 20:
		await get_tree().process_frame
	for key in TARGETS:
		var tid: String = TARGETS[key]
		_report(tid)
		await _shot(_tile_pos(tid), 1.35, key + "_ink")
	MapStyle.set_midcentury(true)
	for _i in 20:
		await get_tree().process_frame
	for key in TARGETS:
		var tid: String = TARGETS[key]
		await _shot(_tile_pos(tid), 1.35, key + "_midcentury")
	# The hero-slice gauntlet compares map art, not HUD composition. Preserve a
	# fixed 2:1 crop at the same camera/zoom on every iteration.
	var ui := _wm.get_node_or_null("UILayer") as CanvasLayer
	if ui != null:
		ui.visible = false
	await _hero_shot(_tile_pos(TARGETS.arinold), 1.35,
		"/tmp/poe_hero_arinold_midcentury.png")
	_write_hero_metrics("/tmp/poe_hero_arinold_metrics.json")
	MapStyle.set_midcentury(false)
	get_tree().quit(0)

func _report(tid: String) -> void:
	var coord: Vector2i = _terrain.id_to_coord(tid)
	var bv: Node = _wm.get_node("%BuildingVisuals")
	var tmpl: Dictionary = (bv.get("_tile_block_templates") as Dictionary).get(tid, {})
	print("[AUTO] %s lots=%d cell=%s road_edges=%d buildings=%d" % [tid,
		(tmpl.get("lots", []) as Array).size(), str(tmpl.get("cell", Vector2.ZERO)),
		RoadNetwork.instance().edges_on_tile(coord).size(),
		MatchState.get_buildings_on_tile(tid).size()])

func _tile_pos(tile_id: String) -> Vector2:
	var coord: Vector2i = _terrain.id_to_coord(tile_id)
	if coord == Vector2i(-1, -1) or not _terrain.tiles.has(coord):
		push_warning("mockup_compare_shot: unknown tile '%s'" % tile_id)
		return Vector2.ZERO
	return _terrain.map_to_local(_terrain.map_coord_for_tile_coord(coord))

func _shot(pos: Vector2, zoom: float, framing: String) -> void:
	_cam.position = pos
	_cam.zoom = Vector2(zoom, zoom)
	if "_target_zoom" in _cam:
		_cam.set("_target_zoom", Vector2(zoom, zoom))
	for _i in 14:
		await get_tree().process_frame
	RenderingServer.force_draw()
	var path := "/tmp/poe_mock_%s.png" % framing
	get_viewport().get_texture().get_image().save_png(path)
	print("[SHOT] %s" % path)

func _hero_shot(pos: Vector2, zoom: float, path: String) -> void:
	_cam.position = pos
	_cam.zoom = Vector2(zoom, zoom)
	if "_target_zoom" in _cam:
		_cam.set("_target_zoom", Vector2(zoom, zoom))
	for _i in 18:
		await get_tree().process_frame
	RenderingServer.force_draw()
	var image := get_viewport().get_texture().get_image()
	var crop_size := Vector2i(mini(960, image.get_width()), mini(480, image.get_height()))
	var crop_origin := Vector2i((image.get_width() - crop_size.x) / 2,
		(image.get_height() - crop_size.y) / 2)
	image.get_region(Rect2i(crop_origin, crop_size)).save_png(path)
	print("[SHOT] %s (map-only hero crop)" % path)

func _write_hero_metrics(path: String) -> void:
	var fabric := _wm.find_child("UrbanFabricVisuals", true, false)
	if fabric == null or not fabric.has_method("metrics"):
		push_error("mockup_compare_shot: UrbanFabricVisuals metrics unavailable")
		return
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("mockup_compare_shot: cannot write metrics '%s'" % path)
		return
	file.store_string(JSON.stringify(fabric.call("metrics"), "  "))
	print("[SHOT] %s (hero metrics)" % path)
