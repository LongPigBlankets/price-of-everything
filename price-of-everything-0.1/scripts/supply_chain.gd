extends RefCounted
## Supply-chain neighbourhood of one building, and the disposition applied to those
## neighbours when the building is sold or demolished (feature: supply-chain panel).
##
## Edges are the same recipe-capability inference the Empire view uses (empire_graph.gd):
##   feeder  = a player building whose OUTPUT good is one of the target's INPUT goods
##   dependent = a player building whose INPUT good is one of the target's OUTPUT goods
## The sim pools goods per tile (no building->building routing), so this is "who could
## supply/consume", collapsed to one row per building with the shared goods listed.

const BuildingNaming := preload("res://scripts/building_naming.gd")


## { feeders: [row], dependents: [row], target_name: String }
## row = { iid, name, goods: [good_id], good_names: [String] }
static func neighbours(target_iid: String) -> Dictionary:
	var target: Dictionary = MatchState.get_building(target_iid)
	var recipe: Dictionary = Catalog.get_recipe(str(target.get("recipe_id", "")))
	var target_inputs := _good_set(recipe.get("inputs", []))
	var target_outputs := _good_set(recipe.get("outputs", []))
	var feeders: Array = []
	var dependents: Array = []
	for b in MatchState.buildings.values():
		if not MatchState.is_player_owned(b):
			continue
		var iid := str(b.get("instance_id", ""))
		if iid == target_iid:
			continue
		var r: Dictionary = Catalog.get_recipe(str(b.get("recipe_id", "")))
		# Goods this building outputs that the target consumes → it feeds the target.
		var feeds := _shared(_good_set(r.get("outputs", [])), target_inputs)
		if not feeds.is_empty():
			feeders.append(_row(b, feeds))
		# Goods this building consumes that the target produces → it depends on the target.
		var needs := _shared(_good_set(r.get("inputs", [])), target_outputs)
		if not needs.is_empty():
			dependents.append(_row(b, needs))
	feeders.sort_custom(func(a, c): return str(a.name) < str(c.name))
	dependents.sort_custom(func(a, c): return str(a.name) < str(c.name))
	return {
		"feeders": feeders,
		"dependents": dependents,
		"target_name": BuildingNaming.label_for_tile(str(target.get("tile_id", "")), target_iid,
			str(target.get("building_id", "")), str(target.get("recipe_id", ""))),
	}


## Apply the player's chosen dispositions before the target leaves. `modes` maps a
## neighbour iid to "auto" or "pause".
##   pause → mothball the neighbour (MatchState.set_building_paused).
##   auto  → keep it running and let the market fill the gap: unpause, and for a
##           dependent, clear any tile-only lock on the goods the target supplied so
##           buy_market_inputs will top them up. (Feeders' surplus auto-sells already.)
static func apply(feeders: Array, dependents: Array, modes: Dictionary) -> void:
	for row in feeders:
		_apply_one(str(row.iid), str(modes.get(str(row.iid), "auto")), [])
	for row in dependents:
		_apply_one(str(row.iid), str(modes.get(str(row.iid), "auto")), row.get("goods", []))


static func _apply_one(iid: String, mode: String, market_goods: Array) -> void:
	if mode == "pause":
		MatchState.set_building_paused(iid, true)
		return
	MatchState.set_building_paused(iid, false)
	for gid in market_goods:
		# Allow the market to fulfil what the target used to supply locally.
		MatchState.set_input_tile_only(iid, str(gid), false)


static func _good_set(entries: Array) -> Dictionary:
	var out: Dictionary = {}
	for e in entries:
		var gid := str((e as Dictionary).get("good_id", ""))
		if gid != "":
			out[gid] = true
	return out


static func _shared(a: Dictionary, b: Dictionary) -> Array:
	var out: Array = []
	for gid in a:
		if b.has(gid):
			out.append(gid)
	return out


static func _row(b: Dictionary, goods: Array) -> Dictionary:
	var names: Array = []
	for gid in goods:
		names.append(Catalog.get_display_name(str(gid)))
	return {
		"iid": str(b.get("instance_id", "")),
		"name": BuildingNaming.label_for_tile(str(b.get("tile_id", "")), str(b.get("instance_id", "")),
			str(b.get("building_id", "")), str(b.get("recipe_id", ""))),
		"goods": goods,
		"good_names": names,
	}
