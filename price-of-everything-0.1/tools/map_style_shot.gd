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
	# The windowed run steals focus — a stray keystroke from the user working
	# at the machine can open panels mid-capture (a G opened the Goods Graph
	# over one run's shots). Screenshots need no input; block it all.
	get_viewport().set_disable_input(true)
	_wm = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(_wm)
	for _i in 150:   # map build + post-load camera configure settle (house
		await get_tree().process_frame   # trap: it overrides pans before ~140)
	print("[SHOT] settle done — starting captures")
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
	# Drive the GAME's camera (house pattern) — a second Camera2D loses to the
	# controller's post-load configure + zoom smoothing, and every framing then
	# captures the same intro view (all shots came out byte-identical).
	_cam = get_viewport().get_camera_2d()
	if _cam == null:
		push_error("map_style_shot: no game camera found")
		get_tree().quit(1)
		return
	# Its _process() lerps zoom toward _target_zoom and then _clamp_to_bounds()
	# re-centres on the whole map — which silently made every framing capture
	# the same intro view. Stop the controller; we drive the transform.
	_cam.set_process(false)
	_cam.set_physics_process(false)
	if "edge_pan_enabled" in _cam:
		_cam.set("edge_pan_enabled", false)
	await _capture_set("classic")
	MapStyle.set_ink(true)
	await _capture_set("ink")
	MapStyle.set_plate(true)
	await _capture_set("plate")
	MapStyle.set_ink(false)   # round-trip: the game must land back in classic
	for _i in 5:
		await get_tree().process_frame
	# Leaving ink must also drop the plate sub-variant, or classic would render
	# with plate values still latched.
	if MapStyle.plate or MapStyle.is_plate():
		push_error("map_style_shot: plate survived set_ink(false)")
	print("[SHOT] toggle round-trip ok (back to classic)")
	get_tree().quit(0)

func _capture_set(mode: String) -> void:
	await _shot(_wide_center, _wide_zoom, "wide", mode, 30)
	await _shot(_tile_pos(COAST_TILE), 0.55, "coast", mode, 12)
	await _shot(_tile_pos(INLAND_TILE), 0.45, "inland", mode, 12)
	await _shot(_farm_pos(), 1.5, "farmclose", mode, 12)
	await _shot(_plant_pos(), 1.2, "plantclose", mode, 12)
	await _shot(_named_pos("electrolyser"), 1.6, "elyclose", mode, 12)
	await _shot(_named_pos("mine"), 1.5, "mineclose", mode, 12)
	await _shot(_player_pos(), 1.6, "playerclose", mode, 12)
	await _shot(_dense_pos(), 0.9, "denseclose", mode, 12)
	await _shot(_dense_pos(), 3.0, "blockclose", mode, 12)

## Centroid of the first farm field placement — so the close framing always
## lands on an actual farm regardless of the seeded layout.
func _farm_pos() -> Vector2:
	var bv: Node = get_tree().get_first_node_in_group("building_footprints")
	if bv != null:
		for placement in (bv.get("_placements") as Array):
			if str(placement.get("cat", "")) == "farm":
				var pts: PackedVector2Array = placement.get("verts", PackedVector2Array())
				if pts.size() >= 3:
					var c := Vector2.ZERO
					for p in pts:
						c += p
					return c / float(pts.size())
	return _tile_pos(INLAND_TILE)

## Centroid of the first sprite-arted industrial placement (priority order),
## so the plant framing shows the baked building art.
const PLANT_NAMES := ["petro_refinery", "chem_plant", "furnace", "eaf", "industrial_factory"]

func _plant_pos() -> Vector2:
	for want in PLANT_NAMES:
		var p := _named_pos(str(want))
		if p != Vector2.INF:
			return p
	return _tile_pos(COAST_TILE)

## Centroid of the first PLAYER-owned footprint — the framing that shows the
## plate's owned-block colours (NPC blocks are the light family).
func _player_pos() -> Vector2:
	var bv: Node = get_tree().get_first_node_in_group("building_footprints")
	if bv != null:
		for placement in (bv.get("_placements") as Array):
			if bool(placement.get("is_npc", true)) or str(placement.get("cat", "")) == "farm":
				continue
			var pts: PackedVector2Array = placement.get("verts", PackedVector2Array())
			if pts.size() >= 3:
				var c := Vector2.ZERO
				for p in pts:
					c += p
				print("[SHOT] player building '%s'" % str(placement.get("iname", "?")))
				return c / float(pts.size())
	return _tile_pos(COAST_TILE)

## Centre of the tile carrying the most footprints — the closest thing the map
## has to the reference's packed block fabric.
func _dense_pos() -> Vector2:
	var bv: Node = get_tree().get_first_node_in_group("building_footprints")
	if bv == null:
		return _tile_pos(COAST_TILE)
	var count: Dictionary = {}
	var sum: Dictionary = {}
	for placement in (bv.get("_placements") as Array):
		var tid := str(placement.get("tile_id", ""))
		var pts: PackedVector2Array = placement.get("verts", PackedVector2Array())
		if tid == "" or pts.size() < 3:
			continue
		var c := Vector2.ZERO
		for p in pts:
			c += p
		count[tid] = int(count.get(tid, 0)) + 1
		sum[tid] = (sum.get(tid, Vector2.ZERO) as Vector2) + c / float(pts.size())
	var best := ""
	var best_n := 0
	for tid2 in count:
		if int(count[tid2]) > best_n:
			best_n = int(count[tid2])
			best = str(tid2)
	if best == "":
		return _tile_pos(COAST_TILE)
	print("[SHOT] densest tile %s with %d footprints" % [best, best_n])
	return (sum[best] as Vector2) / float(best_n)

## Centroid of the first placement of `iname`, or INF when none is placed.
func _named_pos(iname: String) -> Vector2:
	var bv: Node = get_tree().get_first_node_in_group("building_footprints")
	if bv == null:
		return _tile_pos(COAST_TILE)
	for placement in (bv.get("_placements") as Array):
		if str(placement.get("iname", "")) == iname:
			var pts: PackedVector2Array = placement.get("verts", PackedVector2Array())
			if pts.size() >= 3:
				var c := Vector2.ZERO
				for p in pts:
					c += p
				print("[SHOT] %s footprint extent ~%.1fu" % [iname, _extent(pts)])
				return c / float(pts.size())
	return Vector2.INF

## Longest side of the placement's footprint, in world units — logged so the
## drawn size can be checked against the owner's target range.
func _extent(pts: PackedVector2Array) -> float:
	var mn := Vector2(1e30, 1e30)
	var mx := Vector2(-1e30, -1e30)
	for p in pts:
		mn = mn.min(p)
		mx = mx.max(p)
	return maxf((mx - mn).x, (mx - mn).y)

func _tile_pos(tile_id: String) -> Vector2:
	var coord: Vector2i = _terrain.id_to_coord(tile_id)
	if coord == Vector2i(-1, -1) or not _terrain.tiles.has(coord):
		push_warning("map_style_shot: unknown tile '%s' — falling back to map center" % tile_id)
		return _wide_center
	return _terrain.map_to_local(_terrain.map_coord_for_tile_coord(coord))

func _shot(pos: Vector2, zoom: float, framing: String, mode: String, settle: int) -> void:
	# Snap the controller's own targets too, or its smoothing lerps the view
	# back toward the intro framing between shots.
	_cam.position = pos
	_cam.zoom = Vector2(zoom, zoom)
	if "_target_zoom" in _cam:
		_cam.set("_target_zoom", Vector2(zoom, zoom))
	print("[SHOT] framing %s/%s begin" % [framing, mode])
	for _i in settle:   # give redraws (and the lazy hill re-bake) time to land
		await get_tree().process_frame
	# get_texture().get_image() returns whatever the GPU last PRESENTED — without
	# this the capture is a stale frame from an earlier framing (three different
	# shots came out byte-identical). Same guard the hill texture bake uses.
	# An occluded window stops presenting entirely: frame_post_draw never fires
	# and every later capture comes back as the same stale frame (all seven ink
	# framings hashed identical). force_draw() renders and swaps synchronously,
	# so the capture below is this framing regardless of window state.
	RenderingServer.force_draw()
	var path := "/tmp/poe_mapstyle_%s_%s.png" % [framing, mode]
	get_viewport().get_texture().get_image().save_png(path)
	print("[SHOT] %s" % path)
