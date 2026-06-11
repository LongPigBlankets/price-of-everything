class_name RoadCrossings
extends RefCounted
## Predetermined river crossings (roads-v2 spec 2.2, designer ruling #8).
## Per river tile, per ARM: a seeded pick among the 1/4, 1/2 and 3/4
## arc-length points of the arm's in-tile polyline. Branch tiles (2 arms) get
## one crossing per arm. Inputs are static (bake + CSV), so crossings are
## fixed for the whole game and never serialized. Quartile points are interior
## to the tile by construction, so adjacent tiles cannot mint duplicate
## crossings at a shared seam (asserted in tests).

const BRIDGE_LENGTH := 42.0          # matches v1 road_visuals bridge art
const GATE_OFFSET := BRIDGE_LENGTH * 0.5 + 6.0
const GATE_RADIUS := 18.0            # river cells within this of a gate segment are routable
const FRACTIONS := [0.25, 0.5, 0.75]

static var _by_tile: Dictionary = {}     # tile_id -> Array[crossing]
static var _built := false

## crossing: {point, river_tangent, bridge_tangent, gate_a, gate_b, tile_id, arm}

static func build(terrain: HexMap) -> void:
	_by_tile.clear()
	for coord in terrain.tiles:
		var tile_data: Dictionary = terrain.tiles[coord]
		if not tile_data.get("has_river", false):
			continue
		var tile_id := str(tile_data.get("id", ""))
		var center: Vector2 = terrain.map_to_local(terrain.map_coord_for_tile_coord(coord))
		var arms := RiverGeometry.arms(tile_data, terrain.river_properties, center)
		var crossings: Array = []
		for arm_i in arms.size():
			var arm: PackedVector2Array = arms[arm_i]
			if arm.size() < 2:
				continue
			var pick: int = RoadHash.pick("%s|arm%d|crossing" % [tile_id, arm_i], FRACTIONS.size())
			var at := RiverGeometry.point_at_fraction(arm, FRACTIONS[pick])
			if at.is_empty():
				continue
			var river_tangent: Vector2 = at.tangent
			var bridge_tangent := Vector2(-river_tangent.y, river_tangent.x)
			var point: Vector2 = at.point
			crossings.append({
				"point": point,
				"river_tangent": river_tangent,
				"bridge_tangent": bridge_tangent,
				"gate_a": point + bridge_tangent * GATE_OFFSET,
				"gate_b": point - bridge_tangent * GATE_OFFSET,
				"tile_id": tile_id,
				"arm": arm_i,
			})
		if not crossings.is_empty():
			_by_tile[tile_id] = crossings
	_built = true

static func is_built() -> bool:
	return _built

static func for_tile(tile_id: String) -> Array:
	return _by_tile.get(tile_id, [])

static func all_tiles() -> Array:
	return _by_tile.keys()

## Crossings whose gate machinery could matter inside a world-space rect
## (used by the realizer to whitelist river cells near gates).
static func in_rect(rect: Rect2) -> Array:
	var out: Array = []
	for tile_id in _by_tile:
		for crossing in _by_tile[tile_id]:
			if rect.has_point(crossing.point):
				out.append(crossing)
	return out

static func reset_for_tests() -> void:
	_by_tile.clear()
	_built = false
