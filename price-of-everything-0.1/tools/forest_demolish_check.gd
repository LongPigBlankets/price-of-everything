extends Node
## The owner's report, reproduced end to end: buy a forest, demolish it, and see what is left
## standing. Boots the real world, so it measures the map as it actually loads.
##
##   <godot> --headless --path . res://tools/forest_demolish_check.tscn --quit-after 120000
##
## Prints, and fails (exit 1) if the defect is present:
##   1. how many tiles carry TWO forest buildings — the phantom Old Growth Forest that used to
##      be seeded beside a New Growth Forest whose canopy had been imported into the document;
##   2. whether felling a bought wood removes both the building and its authored canopy;
##   3. whether anything is left standing on the tile afterwards.

const AuthoredFabricPainter := preload("res://scripts/authored_fabric_painter.gd")

const NEW_GROWTH := "b_015"
const OLD_GROWTH := "b_016"
const SETTLE_FRAMES := 240


func _ready() -> void:
	var world := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(world)
	for _i in SETTLE_FRAMES:
		await get_tree().process_frame

	var failures := 0
	var by_tile: Dictionary = {}
	for iid in MatchState.buildings:
		var building: Dictionary = MatchState.buildings[iid]
		var building_id := str(building.get("building_id", ""))
		if building_id != NEW_GROWTH and building_id != OLD_GROWTH:
			continue
		var tile_id := str(building.get("tile_id", ""))
		var seen: Array = by_tile.get(tile_id, [])
		seen.append({"iid": str(iid), "building": building_id, "owner": str(building.get("owner", ""))})
		by_tile[tile_id] = seen

	# THE DEFECT IS SPECIFICALLY A SEEDED WOOD BESIDE ANOTHER ONE. Two forests on a tile are
	# not wrong in themselves — the start layout puts two New Growth Forests on seven tiles,
	# which is its content and none of this check's business. What must never happen is an
	# authored-canopy seed (`forest_b_016_<tile>`, owned by the land) standing next to a
	# forest somebody can actually own.
	var doubled: Array = []
	var seeded_beside: Array = []
	for tile_id in by_tile:
		var here: Array = by_tile[tile_id]
		if here.size() <= 1:
			continue
		doubled.append(str(tile_id))
		var has_seed := false
		var has_other := false
		for entry_value in here:
			var entry: Dictionary = entry_value
			if str(entry["iid"]).begins_with("forest_%s_" % OLD_GROWTH):
				has_seed = true
			else:
				has_other = true
		if has_seed and has_other:
			seeded_beside.append(str(tile_id))
	doubled.sort()
	seeded_beside.sort()
	print("[FOREST] %d tiles carry a forest; %d carry more than one; %d carry a SEEDED wood"
		% [by_tile.size(), doubled.size(), seeded_beside.size()] + " beside another")
	if not seeded_beside.is_empty():
		print("[FOREST]   e.g. %s -> %s" % [seeded_beside[0], str(by_tile[seeded_beside[0]])])
		failures += 1

	# The owner's sequence, on a real wood: take one over as the buy flow does, fell it, and
	# check what the tile is left holding.
	var subject := _pick_authored_wood(world)
	if subject.is_empty():
		print("[FOREST] FAILED: found no wood standing on an authored canopy to test")
		get_tree().quit(1)
		return
	var iid := str(subject["iid"])
	var tile_id := str(subject["tile"])
	var areas: Array = subject["areas"]
	print("[FOREST] felling %s (%s) on %s, canopy %s"
		% [iid, str(subject["building"]), tile_id, str(areas)])

	MatchState.set_building_owner(iid, MatchState.LOCAL_PLAYER)
	var started: Dictionary = MatchState.start_demolish(iid)
	if not bool(started.get("ok", false)):
		print("[FOREST] FAILED: a bought wood refused to demolish — %s" % str(started.get("reason", "")))
		get_tree().quit(1)
		return
	MatchState.tick_demolish()
	for _i in 10:
		await get_tree().process_frame

	if MatchState.buildings.has(iid):
		print("[FOREST] FAILED: the building is still standing after demolition")
		failures += 1
	var left: Array = []
	for other in MatchState.tile_buildings.get(tile_id, []):
		var building_id := str(MatchState.get_building(str(other)).get("building_id", ""))
		if building_id == NEW_GROWTH or building_id == OLD_GROWTH:
			left.append("%s (%s)" % [str(other), building_id])
	if not left.is_empty():
		print("[FOREST] FAILED: %s still holds %s — this is the Old Growth Forest the owner"
			% [tile_id, str(left)] + " could not demolish")
		failures += 1
	var unfelled: Array = []
	for area_value in areas:
		if not AuthoredFabricPainter.felled_forests.has(str(area_value)):
			unfelled.append(str(area_value))
	if not unfelled.is_empty():
		print("[FOREST] FAILED: the canopy is still drawn — %s not felled" % str(unfelled))
		failures += 1

	print("[FOREST] %s" % ("PASS — the wood and its canopy are gone, the tile is clear"
		if failures == 0 else "%d FAILURE(S)" % failures))
	get_tree().quit(1 if failures > 0 else 0)


## A forest building standing on a tile the document has drawn a wood on — the case the bug
## lived in. Prefers a New Growth Forest, which is what a player actually buys.
func _pick_authored_wood(world: Node) -> Dictionary:
	var by_tile: Dictionary = world.get("_authored_forest_areas_by_tile")
	if by_tile == null:
		return {}
	var fallback: Dictionary = {}
	var tiles := by_tile.keys()
	tiles.sort()   # deterministic subject across runs
	for tile_value in tiles:
		var tile_id := str(tile_value)
		for iid in MatchState.tile_buildings.get(tile_id, []):
			var building: Dictionary = MatchState.get_building(str(iid))
			var building_id := str(building.get("building_id", ""))
			if building_id != NEW_GROWTH and building_id != OLD_GROWTH:
				continue
			var found := {"iid": str(iid), "tile": tile_id, "building": building_id,
				"areas": by_tile[tile_value]}
			if building_id == NEW_GROWTH:
				return found
			if fallback.is_empty():
				fallback = found
	return fallback
