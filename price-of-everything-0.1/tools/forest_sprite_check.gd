extends Node
## DO THE TREES ACTUALLY GO AWAY? The demolish check proves the records are right; this one
## looks at the screen, because "it still shows on the map" is a claim about pixels.
##
##   <godot> --path . res://tools/forest_sprite_check.tscn --quit-after 300000
##
## WINDOWED ONLY — a headless run draws nothing and every count would be zero, which reads
## exactly like success.
##
## Four cases, each measured as the count of tree-coloured pixels over one tile:
##   1. an authored wood (a New Growth Forest the start layout places) before and after felling
##   2. an old-growth wood the LAND owns — the one that could not be demolished at all
##   3. a forest the player plants on clear ground: it must SHOW
##   4. and stop showing once felled
##
## Writes a PNG per step beside the counts so a surprising number can be looked at.

const AuthoredFabricPainter := preload("res://scripts/authored_fabric_painter.gd")
const NEW_GROWTH := "b_015"
const OLD_GROWTH := "b_016"
const SETTLE_FRAMES := 240
const PAINT_FRAMES := 14
const SHOT_PREFIX := "/tmp/poe_forest"
## A wood covers a good part of its tile; a stray green pixel or two is not a wood. Below this
## share of the frame, nothing is standing.
const TREE_PIXEL_FLOOR := 400
## How much greener than red and blue a canopy pixel is, and the band its green sits in.
## Measured off the real frames: canopy renders around (70, 99, 66), a roof (116, 110, 98),
## grass (152, 158, 104).
const GREEN_MARGIN := 0.05
const CANOPY_DARK_MIN := 0.20
const CANOPY_DARK_MAX := 0.55
## Every Nth pixel. The window is DPI-scaled — a 1000x800 window captures at 3600x2260 here —
## so a full scan is eight million reads through GDScript per frame, for no more answer.
const SCAN_STEP := 3

var _world: Node = null
var _camera: Camera2D = null
var _failures := 0
## The planting tile before anything stands on it.
var _bare_frame: Image = null


func _ready() -> void:
	get_window().size = Vector2i(1000, 800)
	_world = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(_world)
	for _i in SETTLE_FRAMES:
		await get_tree().process_frame
	_camera = get_viewport().get_camera_2d()
	if _camera != null:
		_camera.set_process(false)
	for node_name in ["UILayer", "HexGridOverlay"]:
		var node := _world.get_node_or_null(NodePath(node_name))
		if node != null:
			node.set("visible", false)

	# CASE 1 + 2 — the woods already on the map.
	var authored := _find_wood(NEW_GROWTH)
	if authored.is_empty():
		authored = _find_wood(OLD_GROWTH)
	if not authored.is_empty():
		# The owner's own sequence: a wood a COMPANY owns is bought first, exactly as the Buy
		# button does it. Only the woods the LAND owns are demolished where they stand.
		if str(authored.get("owner", "")) != MatchState.LAND_OWNER:
			MatchState.set_building_owner(str(authored["iid"]), MatchState.LOCAL_PLAYER)
		await _fell_and_measure(authored, "bought")
	else:
		print("[SPRITE] no authored wood found to test")
		_failures += 1

	var land_wood := _find_wood(OLD_GROWTH, true)
	if land_wood.is_empty():
		print("[SPRITE] no land-owned wood found — nothing to test the ownership rule on")
	else:
		await _fell_and_measure(land_wood, "land-owned")

	# CASE 3 + 4 — a wood the player plants, on ground the document has nothing to say about.
	var bare := _bare_tile()
	if bare == "":
		print("[SPRITE] no bare tile found for the planting test")
		_failures += 1
	else:
		# The same ground with nothing on it, to compare the planted wood against.
		_bare_frame = await _shoot(bare, "bare")
		var iid: String = MatchState.add_building(NEW_GROWTH, "", bare, MatchState.LOCAL_PLAYER,
			"planted_%s" % bare, false)
		_world.building_placed.emit(bare, NEW_GROWTH, "", iid,
			_world.terrain_layer.id_to_coord(bare))
		# It has to SHOW first. With the document active, the forest layer used to stand every
		# canopy down for the whole map, so a wood the player planted drew nothing at all —
		# measured here as: the tile looks different with the wood on it than without.
		var planted := await _shoot(bare, "planted")
		var grew := _lost_canopy(planted, _bare_frame)
		print("[SPRITE] planted a forest on %s: %d canopy px appeared"
			% [bare, int(grew["count"])])
		if int(grew["count"]) < TREE_PIXEL_FLOOR:
			print("[SPRITE] FAILED: a forest the player planted draws no trees")
			_failures += 1
		await _fell_and_measure({"iid": iid, "tile": bare, "building": NEW_GROWTH,
			"owner": MatchState.LOCAL_PLAYER}, "planted")

	print("[SPRITE] %s" % ("PASS — every wood shows while it stands and goes when it is felled"
		if _failures == 0 else "%d FAILURE(S)" % _failures))
	get_tree().quit(1 if _failures > 0 else 0)


## Fell one wood and check the trees leave the screen with it.
##
## MEASURED WHERE THE WOOD WAS, not over the frame. A frame at editing zoom holds several
## tiles and usually a second wood, so counting green over the whole picture says almost
## nothing — the first version of this test called a felled wood "still drawn" because its
## neighbour was. The felled canopy is found instead by asking which tree-coloured pixels
## STOPPED being tree-coloured; whatever is still green inside that footprint afterwards is a
## wood that refused to come down.
func _fell_and_measure(wood: Dictionary, label: String) -> void:
	var iid := str(wood["iid"])
	var tile_id := str(wood["tile"])
	var before := await _shoot(tile_id, "%s_before" % label)
	var started: Dictionary = MatchState.start_demolish(iid)
	if not bool(started.get("ok", false)):
		print("[SPRITE] FAILED: %s wood %s (%s) refuses to demolish — %s"
			% [label, iid, str(wood.get("owner", "")), str(started.get("reason", ""))])
		_failures += 1
		return
	MatchState.tick_demolish()
	var after := await _shoot(tile_id, "%s_after" % label)
	var lost := _lost_canopy(before, after)
	var footprint: Rect2i = lost["bounds"]
	var residual := _trees_in(after, footprint)
	print("[SPRITE] %-12s %s on %s: canopy %d px removed, %d still drawn inside it"
		% [label, iid, tile_id, int(lost["count"]), residual])
	if int(lost["count"]) < TREE_PIXEL_FLOOR:
		print("[SPRITE] FAILED: felling %s removed no trees from the screen" % label)
		_failures += 1
	elif residual > int(lost["count"]) / 20:
		print("[SPRITE] FAILED: %s wood is STILL DRAWN after felling" % label)
		_failures += 1


## Pixels that were canopy and are not any more: the felled wood's own footprint, and how
## many pixels it covered.
##
## The footprint is the MIDDLE 90% of those pixels in each axis, not their full extent. A
## frame holds more than one wood and a few pixels always change for unrelated reasons — a
## ship moving, an edge anti-aliasing differently — and a single stray one at the far corner
## stretched the box across the whole picture, which then counted a neighbouring wood as this
## one refusing to come down.
func _lost_canopy(before: Image, after: Image) -> Dictionary:
	var xs: Array[int] = []
	var ys: Array[int] = []
	for y in range(0, before.get_height(), SCAN_STEP):
		for x in range(0, before.get_width(), SCAN_STEP):
			if _is_tree(before.get_pixel(x, y)) and not _is_tree(after.get_pixel(x, y)):
				xs.append(x)
				ys.append(y)
	if xs.is_empty():
		return {"count": 0, "bounds": Rect2i()}
	xs.sort()
	ys.sort()
	var trim := int(xs.size() * 0.05)
	var low := Vector2i(xs[trim], ys[trim])
	var high := Vector2i(xs[xs.size() - 1 - trim], ys[ys.size() - 1 - trim])
	return {"count": xs.size(),
		"bounds": Rect2i(low, high - low + Vector2i(SCAN_STEP, SCAN_STEP))}


func _trees_in(image: Image, bounds: Rect2i) -> int:
	if bounds.size.x <= 0 or bounds.size.y <= 0:
		return 0
	var count := 0
	for y in range(bounds.position.y, mini(bounds.end.y, image.get_height()), SCAN_STEP):
		for x in range(bounds.position.x, mini(bounds.end.x, image.get_width()), SCAN_STEP):
			if _is_tree(image.get_pixel(x, y)):
				count += 1
	return count


## Frame a tile, let it paint, and return the frame. `force_draw` rather than awaiting
## frame_post_draw: an occluded window never presents it.
func _shoot(tile_id: String, label: String) -> Image:
	var coord: Vector2i = _world.terrain_layer.id_to_coord(tile_id)
	_camera.position = _world.terrain_layer.map_to_local(
		_world.terrain_layer.map_coord_for_tile_coord(coord))
	_camera.zoom = Vector2(1.1, 1.1)
	if "_target_zoom" in _camera:
		_camera.set("_target_zoom", _camera.zoom)
	for _i in PAINT_FRAMES:
		await get_tree().process_frame
	RenderingServer.force_draw()
	var image := get_viewport().get_texture().get_image()
	image.save_png("%s_%s.png" % [SHOT_PREFIX, label])
	return image


## Canopy green: clearly GREEN-DOMINANT, and dark.
##
## Two earlier versions of this test were wrong in opposite directions, and both were caught
## by looking at the pixels they matched rather than at the totals. "Greenish and dark" also
## describes the grass a wood stands on. Matching the palette colours within a per-channel
## tolerance instead let GREY through — a building roof at (116,110,98) sits inside a ±0.1 box
## around the canopy's (92,118,81), because a box does not care that one of them is green.
##
## The margin is what separates them: rendered canopy runs about 30/255 greener than it is red
## or blue (the parchment multiply darkens everything, so absolute values drift but the
## dominance does not), while a roof is within a few points of neutral and grass is barely
## green at all and much lighter.
func _is_tree(colour: Color) -> bool:
	return colour.g - colour.r >= GREEN_MARGIN and colour.g - colour.b >= GREEN_MARGIN \
		and colour.g >= CANOPY_DARK_MIN and colour.g <= CANOPY_DARK_MAX


## A standing wood, optionally restricted to the ones the LAND owns.
func _find_wood(building_id: String, land_owned: bool = false) -> Dictionary:
	var ids := MatchState.buildings.keys()
	ids.sort()   # same subject every run
	for iid in ids:
		var building: Dictionary = MatchState.buildings[iid]
		if str(building.get("building_id", "")) != building_id:
			continue
		var owner := str(building.get("owner", ""))
		if land_owned != (owner == MatchState.LAND_OWNER):
			continue
		if MatchState.demolish_queue.has(str(iid)):
			continue
		return {"iid": str(iid), "tile": str(building.get("tile_id", "")),
			"building": building_id, "owner": owner}
	return {}


## A land tile with nothing on it and no authored wood — clear ground to plant on.
func _bare_tile() -> String:
	var authored: Dictionary = _world.get("_authored_forest_areas_by_tile")
	var coords: Array = (_world.terrain_layer.tiles as Dictionary).keys()
	coords.sort()
	for coord in coords:
		var tile: Dictionary = _world.terrain_layer.tiles[coord]
		var kind := str(tile.get("type", ""))
		if kind != "rural" and kind != "hill":
			continue
		var tile_id := str(tile.get("id", ""))
		if tile_id == "" or authored.has(tile_id):
			continue
		if not (MatchState.tile_buildings.get(tile_id, []) as Array).is_empty():
			continue
		return tile_id
	return ""
