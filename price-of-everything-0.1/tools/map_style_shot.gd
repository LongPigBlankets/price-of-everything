extends Node2D
## A/B harness for the map ink & wash restyle (docs/map_ink_wash_restyle_spec.md
## P0): boots the match scene, then captures the same three framings in classic
## and in ink mode — wide (whole landmass), coast (first port area), inland
## (farm belt) — and finishes with a toggle round-trip back to classic.
## Writes /tmp/poe_mapstyle_<framing>_<mode>.png.
## Windowed only (the hill texture LOD and vector meshes need a GPU):
##   <godot> --path . res://tools/map_style_shot.tscn --quit-after 1600

const COAST_TILE := "tile_5_9"    # port-adjacent west-coast tile (tutorial area)
const INLAND_TILE := "tile_9_10"  # farm-belt tile (same one farm_shot uses)

var _wm: Node = null
var _terrain: TileMapLayer = null
var _cam: Camera2D = null
var _wide_center := Vector2.ZERO
var _wide_zoom := 0.1

func _ready() -> void:
	_wm = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(_wm)
	for _i in 40:   # map build + first draws settle
		await get_tree().process_frame
	_terrain = _wm.get_node("%TerrainLayer")
	# The hover hex grid follows the real mouse — hide it so captures are clean
	# regardless of where the cursor sits during the windowed run.
	var grid: Node = _wm.find_child("HexGridOverlay", true, false)
	if grid != null:
		(grid as CanvasItem).visible = false
	var mn := Vector2(1e30, 1e30)
	var mx := Vector2(-1e30, -1e30)
	for coord in _terrain.tiles:
		var p: Vector2 = _terrain.map_to_local(_terrain.map_coord_for_tile_coord(coord))
		mn = mn.min(p)
		mx = mx.max(p)
	_wide_center = (mn + mx) * 0.5
	var span := mx - mn
	var vp := get_viewport().get_visible_rect().size
	_wide_zoom = minf(vp.x / (span.x + 1200.0), vp.y / (span.y + 1200.0))
	_cam = Camera2D.new()
	add_child(_cam)
	_cam.make_current()
	await _capture_set("classic")
	MapStyle.set_ink(true)
	await _capture_set("ink")
	MapStyle.set_ink(false)   # round-trip: the game must land back in classic
	for _i in 5:
		await get_tree().process_frame
	print("[SHOT] toggle round-trip ok (back to classic)")
	get_tree().quit(0)

func _capture_set(mode: String) -> void:
	await _shot(_wide_center, _wide_zoom, "wide", mode, 30)
	await _shot(_tile_pos(COAST_TILE), 0.55, "coast", mode, 12)
	await _shot(_tile_pos(INLAND_TILE), 0.45, "inland", mode, 12)

func _tile_pos(tile_id: String) -> Vector2:
	var coord: Vector2i = _terrain.id_to_coord(tile_id)
	if coord == Vector2i(-1, -1) or not _terrain.tiles.has(coord):
		push_warning("map_style_shot: unknown tile '%s' — falling back to map center" % tile_id)
		return _wide_center
	return _terrain.map_to_local(_terrain.map_coord_for_tile_coord(coord))

func _shot(pos: Vector2, zoom: float, framing: String, mode: String, settle: int) -> void:
	_cam.position = pos
	_cam.zoom = Vector2(zoom, zoom)
	for _i in settle:   # give redraws (and the lazy hill re-bake) time to land
		await get_tree().process_frame
	var path := "/tmp/poe_mapstyle_%s_%s.png" % [framing, mode]
	get_viewport().get_texture().get_image().save_png(path)
	print("[SHOT] %s" % path)
