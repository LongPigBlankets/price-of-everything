extends RefCounted
## Read-only estimates and observed surplus trends. No future events or simulation advances.
const Status := preload("res://scripts/building_status.gd")
static var kept_until: Dictionary = {}
var _samples: Dictionary = {}
var _warned: Dictionary = {}
var _last_turn := -1

static func key(tile: String, good: String) -> String:
	return tile + ":" + good

static func retain_intentionally(tile: String, good: String) -> void:
	kept_until[key(tile, good)] = TurnManager.current_turn + 8

static func output_allocations(building: Dictionary, good: String, quantity: int) -> Dictionary:
	var iid := str(building.get("instance_id", ""))
	var origin := str(building.get("tile_id", ""))
	var result: Dictionary = {}
	var split := MatchState.get_output_split_destinations(iid, good)
	if not split.is_empty():
		var remaining := quantity
		var automatic: Array = []
		for destination: Dictionary in split:
			var requested := int(destination.get("qty", 0))
			if requested <= 0:
				automatic.append(destination)
			else:
				var sent := mini(requested, remaining)
				var tile := str(destination.get("tile_id", ""))
				result[tile] = int(result.get(tile, 0)) + sent
				remaining -= sent
		for index in automatic.size():
			var sent := ceili(float(remaining) / float(automatic.size() - index))
			var tile := str(automatic[index].get("tile_id", ""))
			result[tile] = int(result.get(tile, 0)) + sent
			remaining -= sent
		result[origin] = int(result.get(origin, 0)) + remaining
		return result
	var destination: Variant = Production._output_stockpile_coord(building, good)
	if destination == null:
		return result
	var sent := quantity
	var cap := MatchState.get_output_ship_quantity(iid, good)
	if str(destination) != origin and cap > 0:
		sent = mini(sent, cap)
		result[origin] = quantity - sent
	result[str(destination)] = int(result.get(str(destination), 0)) + sent
	return result

static func estimate(tile: String, good: String) -> Dictionary:
	var incoming := 0
	var consumed := 0
	var outward := 0
	for building: Dictionary in BuildingState.buildings.values():
		if not BuildingState.is_player_owned(building) or BuildingWorks.is_building_paused(str(building.get("instance_id", ""))):
			continue
		var recipe := Catalog.get_recipe(str(building.get("recipe_id", "")))
		if str(building.get("tile_id", "")) == tile:
			for item: Dictionary in recipe.get("inputs", []):
				if str(item.get("good_id", "")) == good:
					consumed += Production._scaled_input_qty(item, building)
		for item: Dictionary in Status.flow_output_items(recipe):
			var gid := str(item.get("good_id", ""))
			if gid == "":
				gid = str(Catalog.get_good_by_internal_name(str(item.get("internal_name", ""))).get("id", ""))
			if gid != good:
				continue
			var single := recipe.duplicate()
			single["outputs"] = [item]
			var quantity := Status.effective_output_qty(building, single)
			incoming += int(output_allocations(building, good, quantity).get(tile, 0))
	for move: Dictionary in TransportState.recurring_moves:
		var quantity := int((move.get("goods", {}) as Dictionary).get(good, 0))
		if str(move.get("dest", "")) == tile:
			incoming += quantity
		if str(move.get("source", "")) == tile:
			outward += quantity
	for sale: Dictionary in MatchState.recurring_sells:
		if str(sale.get("source", "")) == tile:
			outward += int((sale.get("goods", {}) as Dictionary).get(good, 0))
	return {"incoming": incoming, "consumed": consumed, "outward": outward,
		"growth": maxi(0, incoming - consumed - outward),
		"auto_sell": MatchState.should_auto_sell_good(tile, good)}

func reset() -> void:
	_samples.clear()
	_warned.clear()
	_last_turn = -1
	kept_until.clear()

func sample(turn: int) -> Array:
	if turn <= _last_turn:
		return []
	_last_turn = turn
	var current: Dictionary = {}
	for tile_value in Stockpile.tiles_with_stock():
		var tile := str(tile_value)
		if not tile.begins_with("tile_"):
			continue
		var reserve := Production.compute_sell_reserve_for_tile(tile)
		var totals := Stockpile.get_tile_totals(tile)
		for good_value in totals:
			var good := str(good_value)
			var stored := int(totals.get(good, 0))
			var excess := maxi(0, stored - int(reserve.get(good, 0)) - MatchState.auto_sell_keep_for(tile, good))
			current[key(tile, good)] = {"tile": tile, "good": good, "stored": stored, "excess": excess}
	var hits: Array = []
	for id in current:
		var item: Dictionary = current[id]
		var history: Array = _samples.get(id, [])
		history.append({"stored": int(item.stored), "excess": int(item.excess)})
		if history.size() > 4:
			history.pop_front()
		_samples[id] = history
		if history.size() < 4 or int(kept_until.get(id, 0)) > turn or turn - int(_warned.get(id, -99)) < 8:
			continue
		var growing := true
		for i in range(1, 4):
			growing = growing and int(history[i].stored) > int(history[i - 1].stored) and int(history[i].excess) > int(history[i - 1].excess)
		if not growing:
			continue
		item["growth"] = float(int(history[3].stored) - int(history[0].stored)) / 3.0
		hits.append(item)
	for id in _samples.keys():
		if not current.has(id):
			_samples.erase(id)
	# One stockpile card per turn; other candidates remain eligible next turn.
	hits.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.growth) > float(b.growth))
	if hits.is_empty():
		return []
	_warned[key(str(hits[0].tile), str(hits[0].good))] = turn
	return [hits[0]]
