extends RefCounted
## Visual experiment only. Installed into a disposable project by prepare_density_trial.py.
const PILOT := ["tile_4_9", "tile_4_10", "tile_5_9", "tile_5_10", "tile_6_9"]
const Assets := preload("res://scripts/supply_chain_3d/assets.gd")
const Sprites := preload("res://scripts/building_sprites.gd")
const Model := preload("res://scripts/empire_board_model.gd")
static var mode := "relief"

static func configure() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--density-variant="): mode = arg.trim_prefix("--density-variant=")

static func scope() -> Array:
	var ids := PILOT.duplicate()
	for ring in 2:
		for tid in ids.duplicate():
			for nb in Catalog.tile_neighbours(tid):
				if not ids.has(nb): ids.append(nb)
	return ids

static func urban(tid: String) -> bool:
	return tid in ["tile_4_9", "tile_4_10", "tile_5_10"]

static func scale_for(s: Dictionary) -> float:
	return 0.8 if mode == "small" and str(s.get("kind", "")) == "house" and urban(str(s.tile)) else 1.0

static func gap(s: Dictionary) -> float:
	return 1.5 if mode == "hybrid" and urban(str(s.tile)) else 4.0

static func paths(input: Array) -> Array:
	if mode != "hybrid": return input
	return input.filter(func(p: Dictionary) -> bool:
		if p.class != "minor": return true
		for point in p.points:
			if Rect2(2000, 4970, 980, 1140).has_point(point): return false
		return true)

static func populate(model: Dictionary) -> void:
	if mode == "coastal_housing":
		load("res://tools/supply_chain_3d/housing_trial.gd").populate(model)
		return
	if mode in ["relief", "coastal_lanes", "coastal_two"]: return
	for s in model.standing:
		# Allocate greenery before commercial infill, retaining existing landmarks.
		if mode == "hybrid" and str(s.get("decor_family", "")) in ["civic_park", "civic_plaza"]:
			s.iid = str(s.iid).replace("z_civic:", "z0_green:")
		var scale := scale_for(s)
		s.side *= scale
		if s.has("pad"): s.pad *= scale
		if scale != 1.0: s.trial_scale = scale
	# Reuse the existing housing scale. Smaller plots change variety, not floor size.
	var samples := {}
	for s in model.standing:
		if str(s.kind) == "house" and not s.has("decor_family") and not s.get("tall", false) and urban(str(s.tile)):
			samples[str(s.tile)] = float(s.side)
	for tid in ["tile_4_9", "tile_4_10", "tile_5_10"]:
		if not model.tiles.has(tid): continue
		var center: Vector2 = model.tiles[tid].center
		for y in range(-180, 181, 40):
			for x in range(-180, 181, 40):
				var id := "zz_infill:%s:%d:%d" % [tid, x, y]
				var variety := 1 + absi(hash(id)) % 3
				var side := float(samples.get(tid, 43.0))
				model.standing.append({"iid": id, "kind": "house", "tile": tid, "pos": center + Vector2(x,y),
					"side": side, "pad": side, "level": 3, "sprite": Sprites.texture_for("house", variety),
					"name": "Infill housing", "infill": true, "polluting": false})

static func tree_spots(tid: String, tile: Dictionary, roads: Array, original: Array) -> Array:
	if mode != "hybrid" or not urban(tid): return original
	var spots := original.duplicate()
	var lengths := {}
	for road in roads:
		if str(road.tile) != tid: continue
		var key := str(road.get("source", ""))
		var start := float(lengths.get(key, 0.0))
		var length: float = road.a.distance_to(road.b)
		var along := ceilf(start / 32.0) * 32.0 - start
		while along < length:
			var tangent: Vector2 = (road.b-road.a).normalized()
			for direction in [-1.0, 1.0]:
				var p: Vector2 = road.a + tangent * along + tangent.orthogonal() * direction * (float(road.widths[0]) + 9.0)
				spots.append({"p": p - tile.center, "kind": "small", "scale": 0.85, "edge": ""})
			along += 32.0
		lengths[key] = start + length
	return spots
