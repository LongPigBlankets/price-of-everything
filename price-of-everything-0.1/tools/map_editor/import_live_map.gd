extends Node
## Imports the live map — its roads and its procedurally generated fabric — into an authored
## document you can then open in the editor and tweak.
##
##   <godot> --path . res://tools/map_editor/import_live_map.tscn --quit-after 30000 -- \
##       --name=procedural [--tiles=tile_10_16,tile_23_8]
##
## With no `--tiles` it imports the WHOLE map. With them, only those tiles — which is the
## point: the authored/procedural split is per tile, so importing a handful leaves every
## other tile generating itself exactly as before.
##
## SHAPES OVER FIVE CORNERS ARE SIMPLIFIED (owner, 2026-08-16). The procedural fabric runs to
## 43 corners, and a 43-handle outline is movable but not reshapeable — the reason to import
## is to tweak. Simplification costs a little fidelity: an imported mass sits close to, not
## exactly on, the one it replaces.
##
## Roads and fabric are imported TOGETHER for a tile, because the fabric is derived from the
## roads; importing one without the other would leave a tile whose buildings answer to a road
## layout it no longer has.

const AuthoredMap := preload("res://scripts/authored_map.gd")
const BuildingVisualsRef := preload("res://scenes/building_visuals.gd")
const AuthoredRoadStyle := preload("res://scripts/authored_road_style.gd")

## Above this, an outline is simplified. The free polygon's own cap is six, so five leaves a
## corner of headroom for a shape that lands exactly on the limit.
const MAX_CORNERS := 5
## Douglas-Peucker tolerance, world units. Raised until the shape is under the cap.
const SIMPLIFY_START := 3.0
const SIMPLIFY_STEP := 2.5
const SIMPLIFY_LIMIT := 60.0

const SETTLE_FRAMES := 240

var _name := "procedural"
var _only_tiles: Dictionary = {}


func _ready() -> void:
	_parse_options()
	MapStyle.set_midcentury(true)
	var world := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(world)
	for _i in SETTLE_FRAMES:
		await get_tree().process_frame

	var terrain := get_tree().get_first_node_in_group("hex_map")
	var fabric := world.get_node_or_null(NodePath("UrbanFabricVisuals"))
	var visuals := world.get_node_or_null(NodePath("BuildingVisuals"))
	if terrain == null or fabric == null or visuals == null:
		push_error("[LIVE] the world did not build")
		get_tree().quit(1)
		return

	var roads: Array = _import_roads(terrain)
	var specials: Array = []
	var simplified := 0
	var corners_before := 0
	var corners_after := 0
	for record_value in (fabric.get("_decorative_mass_records") as Array):
		var record: Dictionary = record_value
		var poly: PackedVector2Array = record.get("poly", PackedVector2Array())
		if poly.size() < 3:
			continue
		if not _wanted(_tile_of(terrain, _centre_of(poly))):
			continue
		corners_before += poly.size()
		var shaped := poly
		if poly.size() > MAX_CORNERS:
			shaped = _simplify_to_cap(poly)
			simplified += 1
		corners_after += shaped.size()
		var outline: Array = []
		for point in shaped:
			outline.append([point.x, point.y])
		specials.append({"id": "s:procedural:%d" % specials.size(), "kind": "poly",
			"sides": [], "outline": outline})

	var slots: Dictionary = _import_slots(terrain, visuals)
	var tiles: Dictionary = {}
	for road in roads:
		for tile_id in (road.get("tiles", []) as Array):
			tiles[str(tile_id)] = true
	for special in specials:
		tiles[_tile_of(terrain, _centre_of(_outline_of(special)))] = true
	for tile_id in slots.keys():
		tiles[str(tile_id)] = true
	tiles.erase("")
	var tile_list := tiles.keys()
	tile_list.sort()

	var document := AuthoredMap.empty_document()
	document["settlements"] = {"procedural": {
		"tiles": tile_list,
		"next_id": roads.size() + specials.size() + 1,
		"roads": roads,
		"specials": specials,
		"slots": slots,
	}}
	var directory := ProjectSettings.globalize_path(AuthoredMap.DOC_DIR)
	DirAccess.make_dir_recursive_absolute(directory)
	var problem: String = AuthoredMap.save_to(document, "%s/%s.json" % [directory, _name])
	if problem != "":
		push_error("[LIVE] %s" % problem)
		get_tree().quit(1)
		return
	print("[LIVE] imported %d roads, %d shapes (%d simplified, %d corners -> %d), %d tiles with slots"
		% [roads.size(), specials.size(), simplified, corners_before, corners_after, slots.size()])
	print("[LIVE] %d tiles covered — saved as '%s' (NOT made active; open it from the editor)"
		% [tile_list.size(), _name])
	get_tree().quit(0)


## Built network edges as authored strokes. Tier maps onto a class, and the edge's own tiles
## list is exactly the touched-tile set the unlock rule wants.
func _import_roads(terrain: Node) -> Array:
	var out: Array = []
	var network := RoadNetwork.instance()
	var ids := network.edges.keys()
	ids.sort()   # stable ids across imports
	for edge_id in ids:
		var edge: Dictionary = network.edges[edge_id]
		if str(edge.get("state", "")) != "built":
			continue
		var geometry: Array = edge.get("geometry", []) as Array
		if geometry.size() < 2:
			continue
		var tiles: Array = []
		var wanted := false
		for coord_value in (edge.get("tiles", []) as Array):
			var tile_id := _tile_id_of(terrain, coord_value)
			if tile_id == "":
				continue
			tiles.append(tile_id)
			if _wanted(tile_id):
				wanted = true
		if not wanted:
			continue
		# The routed polyline carries a point every ~12-18 u; simplified to corners so the
		# stroke is editable rather than a chain of hundreds of vertices.
		# The LIVE network stores Vector2 points and Vector2i tiles; only the JSON bake turns
		# them into [x, y] pairs. Both are accepted so this tool works either way.
		var points := PackedVector2Array()
		for entry in geometry:
			points.append(_as_vector(entry))
		var simple := _rdp(points, 6.0)
		var authored: Array = []
		for point in simple:
			authored.append([point.x, point.y])
		tiles.sort()
		out.append({
			"id": "r:procedural:%d" % out.size(),
			"class": "major" if str(edge.get("tier", "local")) == "trunk" else "mid",
			"points": authored,
			"tiles": tiles,
			"unlockable": _any_roadless(terrain, tiles),
		})
	return out


## Existing gameplay buildings become slots, so an imported tile keeps its buildings exactly
## where they are instead of re-packing them the first time it is played.
func _import_slots(terrain: Node, visuals: Node) -> Dictionary:
	var out: Dictionary = {}
	for placement_value in (visuals.get("_placements") as Array):
		var placement: Dictionary = placement_value
		var tile_id := str(placement.get("tile_id", ""))
		if tile_id == "" or not _wanted(tile_id):
			continue
		var verts: PackedVector2Array = placement.get("verts", PackedVector2Array())
		var angle := 0.0
		if verts.size() >= 2:
			angle = (verts[1] - verts[0]).angle()
		var half: Vector2 = placement.get("half", Vector2(30, 30))
		# A placement's `half` is the CROPPED box, which already carries ART_BLOCK_MARGIN on
		# each side; the class ceilings are drawn-art extents. Comparing the two directly
		# over-states every building by 12 u and pushes it a class too big.
		var drawn := maxf(half.x, half.y) * 2.0 - BuildingVisualsRef.ART_BLOCK_MARGIN * 2.0
		var slot_class := AuthoredMap.slot_class_for(drawn, false)
		if not out.has(tile_id):
			out[tile_id] = {"pins": []}
		var centre_rel: Vector2 = placement.get("center_rel", Vector2.ZERO)
		(out[tile_id]["pins"] as Array).append({
			"pos": [centre_rel.x, centre_rel.y], "angle": angle, "size": slot_class})
	return out


## Raise the tolerance until the outline is under the cap. Ends at a triangle rather than
## failing: a shape that will not simplify is one nobody could edit anyway.
func _simplify_to_cap(points: PackedVector2Array) -> PackedVector2Array:
	var tolerance := SIMPLIFY_START
	var best := points
	while tolerance < SIMPLIFY_LIMIT:
		best = _rdp(points, tolerance)
		if best.size() <= MAX_CORNERS:
			return best
		tolerance += SIMPLIFY_STEP
	return best if best.size() >= 3 else points


func _rdp(points: PackedVector2Array, tolerance: float) -> PackedVector2Array:
	if points.size() < 3:
		return points
	var keep := {0: true, points.size() - 1: true}
	var stack: Array = [[0, points.size() - 1]]
	while not stack.is_empty():
		var span: Array = stack.pop_back()
		var first: int = span[0]
		var last: int = span[1]
		var worst := -1
		var worst_distance := tolerance
		for i in range(first + 1, last):
			var closest := Geometry2D.get_closest_point_to_segment(points[i], points[first], points[last])
			var distance := points[i].distance_to(closest)
			if distance > worst_distance:
				worst_distance = distance
				worst = i
		if worst > 0:
			keep[worst] = true
			stack.append([first, worst])
			stack.append([worst, last])
	var indices := keep.keys()
	indices.sort()
	var out := PackedVector2Array()
	for index in indices:
		out.append(points[int(index)])
	return out


## A point that may be a Vector2, a Vector2i, or a two-element array.
func _as_vector(value: Variant) -> Vector2:
	match typeof(value):
		TYPE_VECTOR2:
			return value
		TYPE_VECTOR2I:
			return Vector2(value)
		TYPE_ARRAY:
			var values: Array = value
			if values.size() >= 2:
				return Vector2(float(values[0]), float(values[1]))
	return Vector2.ZERO


func _wanted(tile_id: String) -> bool:
	return _only_tiles.is_empty() or _only_tiles.has(tile_id)


func _centre_of(points: PackedVector2Array) -> Vector2:
	if points.is_empty():
		return Vector2.ZERO
	var total := Vector2.ZERO
	for point in points:
		total += point
	return total / float(points.size())


func _outline_of(record: Dictionary) -> PackedVector2Array:
	var out := PackedVector2Array()
	for entry in (record.get("outline", []) as Array):
		var values: Array = entry as Array
		if values != null and values.size() >= 2:
			out.append(Vector2(float(values[0]), float(values[1])))
	return out


func _tile_of(terrain: Node, world: Vector2) -> String:
	var coord: Vector2i = terrain.call("tile_coord_for_map_coord", terrain.call("local_to_map", world))
	var tiles: Dictionary = terrain.get("tiles")
	return str((tiles[coord] as Dictionary).get("id", "")) if tiles.has(coord) else ""


func _tile_id_of(terrain: Node, coord_value: Variant) -> String:
	var point := _as_vector(coord_value)
	var coord := Vector2i(int(round(point.x)), int(round(point.y)))
	var tiles: Dictionary = terrain.get("tiles")
	return str((tiles[coord] as Dictionary).get("id", "")) if tiles.has(coord) else ""


func _any_roadless(terrain: Node, tiles: Array) -> bool:
	var all_tiles: Dictionary = terrain.get("tiles")
	for tile_id in tiles:
		var coord: Vector2i = terrain.call("id_to_coord", str(tile_id))
		if not all_tiles.has(coord):
			continue
		if not ((all_tiles[coord] as Dictionary).get("infrastructure_present", []) as Array).has("roads"):
			return true
	return false


func _parse_options() -> void:
	for argument in OS.get_cmdline_user_args():
		var text := str(argument)
		if text.begins_with("--name="):
			_name = text.substr(7)
		elif text.begins_with("--tiles="):
			for tile in text.substr(8).split(",", false):
				_only_tiles[str(tile)] = true
