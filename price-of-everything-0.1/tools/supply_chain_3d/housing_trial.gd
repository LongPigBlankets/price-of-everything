extends RefCounted
## Chosen Stoneshore look: fixed housing scale, compact plots and protected greenery.
const Assets := preload("res://scripts/supply_chain_3d/assets.gd")
const Sprites := preload("res://scripts/building_sprites.gd")
const Coastal := preload("res://tools/supply_chain_3d/coastal_road_trial.gd")
const Trial := preload("res://tools/supply_chain_3d/density_trial.gd")
const HOUSE_SIDE := 50.4
const HOUSE_LIMIT := 24
const OFFICE_LIMIT := {"tile_4_9": 6, "tile_4_10": 5, "tile_5_10": 9}
static var _tree_buckets := {}

static func enabled() -> bool:
	return Trial.mode == "coastal_housing"

static func is_housing(s: Dictionary) -> bool:
	return str(s.get("kind", "")) == "house" and not s.get("tall", false) and not s.has("decor_family")

static func populate(model: Dictionary) -> void:
	for s in model.standing:
		if is_housing(s):
			s.side = HOUSE_SIDE
			s.pad = HOUSE_SIDE
			s.fixed_housing_scale = true
			s.erase("footprint")
		if str(s.get("decor_family", "")) in ["civic_park", "civic_plaza"] and Trial.urban(str(s.tile)):
			s.iid = str(s.iid).replace("z_civic:", "z0_green:")
			s.side = 40.0; s.pad = 40.0
		elif s.has("decor_family") and Trial.urban(str(s.tile)):
			# Keep the selected version's office allocation before housing infill.
			s.iid = str(s.iid).replace("z_civic:", "z1_civic:")
	for tid in ["tile_4_9", "tile_4_10", "tile_5_10"]:
		if not model.tiles.has(tid): continue
		var center: Vector2 = model.tiles[tid].center
		var count := 0
		for y in range(-180, 181, 36):
			for x in range(-180, 181, 36):
				var id := "z2_housing:%s:%04d" % [tid, count]
				var variety := 1 + absi(hash(id)) % 3
				# More single rows than paired terraces: both retain the same house size.
				if count % 3 == 0: variety = 1
				model.standing.append({"iid": id, "kind": "house", "tile": tid, "pos": center + Vector2(x, y),
					"side": HOUSE_SIDE, "pad": HOUSE_SIDE, "level": 3,
					"sprite": Sprites.texture_for("house", variety), "fixed_housing_scale": true,
					"name": "Housing", "infill": true, "polluting": false, "max_relief": 3.0})
				# Reserve a second pocket park independently of the first park/plaza.
				if count % 9 == 0:
					model.standing.append({"iid": "z0_green:%s:extra:%04d" % [tid, count], "kind": "house", "tile": tid,
						"pos": center + Vector2(x, y), "side": 40.0, "pad": 40.0, "level": 1,
						"decor_family": "civic_park", "space_slot": "second", "sprite": null,
						"name": "Pocket park", "max_relief": 2.0, "polluting": false})
				count += 1

static func clears_trees(poly: PackedVector2Array, iid: String) -> bool:
	if not iid.begins_with("z2_housing:"): return true
	if _tree_buckets.is_empty():
		Coastal._load_trees()
		for tree in Coastal._trees:
			var cell := Vector2i((tree.pos / 64.0).floor())
			(_tree_buckets.get_or_add(cell, []) as Array).append(tree)
	var bounds := Rect2(poly[0], Vector2.ZERO)
	for p in poly: bounds = bounds.expand(p)
	bounds = bounds.grow(8.0)
	var low := Vector2i((bounds.position / 64.0).floor())
	var high := Vector2i((bounds.end / 64.0).floor())
	for y in range(low.y, high.y + 1):
		for x in range(low.x, high.x + 1):
			for tree in _tree_buckets.get(Vector2i(x, y), []):
				if Coastal._near_polygon(tree.pos, poly, tree.radius + 1.0): return false
	return true

static func extra_trees(tid: String, center: Vector2) -> Array:
	if not Trial.urban(tid): return []
	var result: Array = []
	for y in range(-210, 211, 30):
		for x in range(-210, 211, 30):
			var key := "housing_green:%s:%d:%d" % [tid, x, y]
			var roll := absi(hash(key))
			if roll % 5 != 0: continue
			var p := center + Vector2(x, y) + Vector2(roll % 7 - 3, (roll / 7) % 7 - 3)
			var near_existing := false
			for tree in Coastal._trees:
				if p.distance_squared_to(tree.pos) < 12.0 * 12.0: near_existing = true; break
			if near_existing: continue
			var species := 0 if roll % 3 == 0 else 2
			result.append(Coastal.tree_record(p, species, key))
	return result
