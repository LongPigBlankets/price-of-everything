extends RefCounted
## Presentation experiments installed only into the disposable Stoneshore project.
const Trial := preload("res://tools/supply_chain_3d/density_trial.gd")
const Authored := preload("res://scripts/authored_map.gd")
const Painter := preload("res://scripts/authored_fabric_painter.gd")
const Shapes := preload("res://scripts/tree_shapes.gd")
const Assets := preload("res://scripts/supply_chain_3d/assets.gd")
const Model := preload("res://scripts/empire_board_model.gd")
const Ground := preload("res://scripts/empire_board_ground.gd")
const Index := preload("res://scripts/supply_chain_3d/road_index.gd")
const Legacy := preload("res://scripts/empire_board.gd")
static var _trees: Array = []
static var _trees_loaded := false
static var _rings: Array = []
static var tree_metrics := {}

static func enabled() -> bool:
	return Trial.mode in ["coastal_lanes", "coastal_two", "coastal_housing"]

static func lanes(level: int) -> int:
	return 2 if Trial.mode == "coastal_two" else clampi(level, 1, 3) * 2

static func widths(road_class: String) -> Array:
	var level: int = {"minor": 1, "mid": 2, "major": 3}.get(road_class, 2)
	# 3u per lane, plus a 0.6u shoulder on each side; one consistent edge weight.
	var bed := lanes(level) * 1.5 + 0.6
	return [bed + 0.9, bed + 0.65, bed + 0.25, bed]

static func lane_lines(level: int, half_width: float) -> Array:
	var count := lanes(level)
	if count == 2: return [[0.0, true]]
	var lines := [[-0.35, false], [0.35, false]]
	var lane_width := (half_width - 0.6) * 2.0 / count
	for i in range(1, count / 2):
		lines.append([-lane_width * i, true])
		lines.append([lane_width * i, true])
	return lines

static func _load_trees() -> void:
	if _trees_loaded: return
	_trees_loaded = true
	var settlements := Authored.settlements()
	var keys := settlements.keys()
	keys.sort()
	for key in keys:
		var settlement: Dictionary = settlements[key]
		for record in Authored.tree_records(settlement, str(key)):
			var id := str(record.id)
			if str(record.kind) == "mixed":
				for point in Painter.clump_points(record):
					var seed_key := "%s|%.0f|%.0f" % [id, point.x, point.y]
					_add_tree(point, Shapes.pick_kind(seed_key, Painter.CLUMP_MIX), seed_key)
			else:
				_add_tree(Vector2(record.position[0], record.position[1]), Shapes.Kind.SMALL if record.kind == "small" else Shapes.Kind.LARGE, id)
		for forest in settlement.get("forests", []):
			if Painter.felled_forests.has(str(forest.id)): continue
			for point in Painter.woodland_points(forest):
				var seed_key := "%s|tree|%.0f|%.0f" % [forest.id, point.x, point.y]
				_add_tree(point, Shapes.pick_kind(seed_key, [55, 25, 20]), seed_key)

static func _add_tree(p: Vector2, species: int, seed_key: String) -> void:
	_trees.append(tree_record(p, species, seed_key))

static func tree_record(p: Vector2, species: int, seed_key: String) -> Dictionary:
	# The same species and crown footprint as the regular map, using existing 3D art.
	var kind: String = ["small", "fir", "large"][species]
	var key := Assets.key_for("tree", species + 1)
	var radius := Shapes.radius(species)
	var scale := radius * 2.0 / maxf(Assets.dimensions(key).x, 0.01)
	return {"pos": p, "kind": kind, "height": Assets.projected_height(key) * scale,
		"radius": radius, "source": seed_key, "edge": ""}

static func trees(tid: String, tile: Dictionary, relief: Dictionary, standing: Array, roads: Array, lines: Array, rivers: Array) -> Array:
	_load_trees()
	var hex := Model.hex_points(tile.center)
	var bounds := Rect2(tile.center - Model.HEX_HALF, Model.HEX_HALF * 2.0)
	var result: Array = []
	var metrics := {"source_candidates": 0, "water": 0, "buildings": 0, "roads": 0, "utilities": 0, "accepted": 0, "position_delta": 0.0, "extra_accepted": 0}
	var candidates := _trees.duplicate()
	if Trial.mode == "coastal_housing":
		candidates.append_array(load("res://tools/supply_chain_3d/housing_trial.gd").extra_trees(tid, tile.center))
	for tree in candidates:
		var p: Vector2 = tree.pos
		if not bounds.has_point(p) or not Geometry2D.is_point_in_polygon(p, hex): continue
		metrics.source_candidates += 1
		if Ground.is_water(relief, p): metrics.water += 1; continue
		var blocked := false
		for s in standing:
			if s.has("harbour"):
				blocked = (s.harbour.bounds as Rect2).grow(tree.radius).has_point(p)
			elif s.has("footprint") and not s.footprint.is_empty():
				blocked = _near_polygon(p, s.footprint, tree.radius + 1.0)
			else:
				blocked = (s.pos as Vector2).distance_to(p) < float(s.get("pad", s.side)) * 0.5 + float(tree.radius)
			if blocked: break
		if blocked: metrics.buildings += 1; continue
		for road in roads:
			if p.distance_to(Geometry2D.get_closest_point_to_segment(p, road.a, road.b)) < float(road.widths[0]) + float(tree.radius) * 0.35:
				blocked = true; break
		if blocked: metrics.roads += 1; continue
		for line in lines:
			if not Model.PIPE_MODES.has(str(line.mode)): continue
			for i in range(line.pts.size() - 1):
				if p.distance_to(Geometry2D.get_closest_point_to_segment(p, line.pts[i].p, line.pts[i + 1].p)) < 3.0 + float(tree.radius): blocked = true
		for river in rivers:
			for i in range(river.points.size() - 1):
				if p.distance_to(Geometry2D.get_closest_point_to_segment(p, river.points[i], river.points[i + 1])) < 16.0: blocked = true
		if blocked: metrics.utilities += 1; continue
		result.append(tree.duplicate())
		if str(tree.source).begins_with("housing_green:"): metrics.extra_accepted += 1
	metrics.accepted = result.size()
	tree_metrics[tid] = metrics
	return result

static func _near_polygon(p: Vector2, poly: PackedVector2Array, reach: float) -> bool:
	if Geometry2D.is_point_in_polygon(p, poly): return true
	for i in poly.size():
		if p.distance_to(Geometry2D.get_closest_point_to_segment(p, poly[i], poly[(i + 1) % poly.size()])) < reach: return true
	return false

static func water_bands(tile: Dictionary) -> Array:
	if _rings.is_empty():
		var land: Array = []
		for rec in HillBaked.sea():
			if int(rec.b) == 5: land.append(rec.p)
		var water: Color = MapStyle.sea_colors()[4]
		# Offset whole coast polygons, not independent line segments. The land is
		# painted afterwards, so only the seaward part remains and all joins meet.
		for band in [[28.0, water.lightened(0.14)], [15.0, water.lightened(0.30)], [3.5, water.lightened(0.46)]]:
			for polygon in land:
				for expanded in Geometry2D.offset_polygon(polygon, band[0], Geometry2D.JOIN_ROUND):
					_rings.append({"p": expanded, "box": Legacy._box_of(expanded), "colour": band[1]})
	var result: Array = []
	var hex := Model.hex_points(tile.center)
	var bounds := Legacy._box_of(hex)
	for ring in _rings:
		if not bounds.intersects(ring.box): continue
		for piece in Legacy._clip(ring.p, hex): result.append({"p": piece, "colour": ring.colour})
	return result
