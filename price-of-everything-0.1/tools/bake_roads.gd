extends Node
## Starting anchor network bake (roads-v2 spec 4.5b). Run headless:
##     <godot> --headless res://tools/bake_roads.tscn
##
## Reads the hand-authored anchor tiles (tiles with "roads" in
## infrastructure_present in tile_properties.csv), routes a deterministic
## minimum-spanning network between them over the baked navgrid — on virgin
## terrain plus the deterministic game-start forests — and writes the realized
## geometry to data/roads_baked.json. A fresh match loads this as
## RoadNetwork's initial state, so runtime jobs collapse to cheap
## connect-to-anchor routing.
##
## Determinism: anchors sorted by tile id; Prim's MST with id tie-breaks;
## edges routed shortest-first (the spine accretes and the reuse discount
## grafts longer edges onto it); forest instance ids match world_map's
## deterministic seeding exactly.

const OLD_GROWTH_BUILDING := "b_016"
const NORTH_MAX_ROW := 6
const OLD_GROWTH_TILE_TYPES := ["rural", "hill"]
const TRUNK_LENGTH := 1500.0
const OUT_PATH := "res://data/roads_baked.json"

@onready var terrain: HexMap = %TerrainLayer

func _ready() -> void:
	await get_tree().process_frame
	var started := Time.get_ticks_msec()
	print("\n==== roads-v2 starting network bake ====")
	var nav := NavGrid.instance()
	if not nav.is_ready():
		push_error("bake_roads: navgrid missing — run tools/bake_hills.tscn first")
		get_tree().quit(1)
		return
	RoadCrossings.build(terrain)
	_seed_start_forests()
	_seed_start_buildings()

	var anchors := _anchor_tiles()
	print("bake_roads: %d anchor tiles (infrastructure_present 'roads')" % anchors.size())
	if anchors.size() < 2:
		push_error("bake_roads: need at least 2 anchor tiles")
		get_tree().quit(1)
		return

	var mst := _prim_mst(anchors)
	mst.sort_custom(func(a, b): return float(a.length) < float(b.length))
	var network := RoadNetwork.new()
	var realizer := RoadRealizer.new()
	var routed := 0
	var failed := 0
	for edge in mst:
		var a: Dictionary = edge.a
		var b: Dictionary = edge.b
		var identity: String = RoadRegions.identity_for_tile(str(a.id))
		var result := realizer.route(nav, network, a.center, b.center, {
			"identity": identity,
			"salt": RoadHash.pick("seed|%s|%s" % [a.id, b.id], 1 << 30),
		})
		if not result.ok:
			failed += 1
			print("bake_roads: FAILED %s -> %s (%s)" % [a.id, b.id, result.reason])
			continue
		var na := network.ensure_node("anchor:" + str(a.id), RoadNetwork.KIND_JUNCTION, a.center, a.coord)
		var nb := network.ensure_node("anchor:" + str(b.id), RoadNetwork.KIND_JUNCTION, b.center, b.coord)
		var tier := RoadNetwork.TIER_TRUNK if float(edge.length) > TRUNK_LENGTH else RoadNetwork.TIER_LOCAL
		realizer.commit(network, na.id, nb.id, tier, result, 0)
		routed += 1
		print("bake_roads: %s -> %s  %s, %d pts, %d bridges (%s)" % [
			a.id, b.id, tier, result.geometry.size(), result.bridges.size(), identity])

	# Phase 4: each region holding an anchor tile grows its style web at bake
	# time (Stoneshore's orbital, sparse-city minihub webs, rural through-routes)
	# so cities have street fabric at turn 0 — also what the building visuals
	# will front onto.
	var styled: Array = []
	var style_regions := {}
	for a3 in anchors:
		var region_id := RoadRegions.region_of(str(a3.id))
		if region_id != RoadRegions.DEFAULT_REGION_ID:
			style_regions[region_id] = true
	var region_keys := style_regions.keys()
	region_keys.sort()
	for region_id2 in region_keys:
		var rep := RoadRegionJobs.realize_region(str(region_id2), terrain, nav, network, realizer, 0)
		styled.append(str(region_id2))
		print("bake_roads: region %-16s (%s)  jobs=%d committed=%d failed=%d overflow=%.0f%%%s" % [
			region_id2, RoadRegions.identity(str(region_id2)), int(rep.jobs), int(rep.committed),
			int(rep.failed), float(rep.overflow) * 100.0, " REWORKED" if bool(rep.reworked) else ""])

	var anchor_ids: Array = []
	for a2 in anchors:
		anchor_ids.append(str(a2.id))
	var doc := {
		"version": 1,
		"hills_hash": HillBaked.source_hash(),
		"anchors": anchor_ids,
		"style_regions": styled,
		"network": network.export_state(),
	}
	var file := FileAccess.open(OUT_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(doc))
	file.close()
	print("bake_roads: wrote %s — %d/%d edges routed, %d failed (%.1fs)" % [
		OUT_PATH, routed, mst.size(), failed,
		float(Time.get_ticks_msec() - started) / 1000.0])
	get_tree().quit(0 if failed == 0 else 1)

## Mirrors world_map._place_northern_old_growth_forests with the SAME
## deterministic instance ids, so the realizer's forest discs match a fresh
## match exactly.
func _seed_start_forests() -> void:
	var seeded := 0
	for coord_key in terrain.tiles:
		var coord: Vector2i = coord_key
		var tile_data: Dictionary = terrain.tiles[coord]
		if coord.y + 1 > NORTH_MAX_ROW:
			continue
		if not OLD_GROWTH_TILE_TYPES.has(str(tile_data.get("type", "")).strip_edges().to_lower()):
			continue
		var tile_id := str(tile_data.get("id", ""))
		if tile_id == "":
			continue
		MatchState.add_building(OLD_GROWTH_BUILDING, "", tile_id, "tile_data",
			"forest_%s_%s" % [OLD_GROWTH_BUILDING, tile_id], false)
		seeded += 1
	print("bake_roads: seeded %d deterministic game-start forests" % seeded)

## Mirrors world_map._place_start_buildings (the pre-existing NPC pool): the
## new-growth forests in it (b_015) are road obstacles, and their footprint
## discs are seeded from the SAME deterministic instance ids a fresh match uses.
func _seed_start_buildings() -> void:
	var seeded := 0
	for entry in StartBuildings.entries():
		var tile_id := str(entry.tile)
		if terrain.id_to_coord(tile_id) == Vector2i(-1, -1):
			continue
		if MatchState.buildings.has(str(entry.instance_id)):
			continue
		MatchState.add_building(str(entry.building), str(entry.recipe), tile_id,
			str(entry.owner), str(entry.instance_id), false)
		seeded += 1
	print("bake_roads: seeded %d deterministic start buildings" % seeded)

func _anchor_tiles() -> Array:
	var anchors: Array = []
	for coord in terrain.tiles:
		var tile_data: Dictionary = terrain.tiles[coord]
		var infra: Array = tile_data.get("infrastructure_present", [])
		if not infra.has("roads"):
			continue
		anchors.append({
			"id": str(tile_data.get("id", "")),
			"coord": coord,
			"center": terrain.map_to_local(terrain.map_coord_for_tile_coord(coord)),
		})
	anchors.sort_custom(func(a, b): return str(a.id) < str(b.id))
	return anchors

func _prim_mst(anchors: Array) -> Array:
	var in_tree := {0: true}
	var edges: Array = []
	while in_tree.size() < anchors.size():
		var best_d := 1e30
		var best_from := -1
		var best_to := -1
		for i in in_tree:
			for j in anchors.size():
				if in_tree.has(j):
					continue
				var d: float = (anchors[i].center as Vector2).distance_to(anchors[j].center)
				if d < best_d - 0.01 or (absf(d - best_d) <= 0.01 and str(anchors[j].id) < str(anchors[best_to].id if best_to >= 0 else "~")):
					best_d = d
					best_from = i
					best_to = j
		if best_to < 0:
			break
		in_tree[best_to] = true
		edges.append({"a": anchors[best_from], "b": anchors[best_to], "length": best_d})
	return edges
