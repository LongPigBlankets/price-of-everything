extends Node
## Parity check for scripts/construction_rules.gd against the real build.
##
## Boots the game, then for each scenario asks ConstructionRules.quote() what a build will do,
## makes the build through the same calls the construct panel and the map use
## (BuildMode.attempt_direct_build, BuildMode.infrastructure_attempted) and compares: placed or
## refused, what attempt_direct_build answered, the first reason, the cash spent and the land
## bought (a refused build keeps neither). Each scenario is undone
## (project cancelled, cash, land, stock and settings restored) before the next.
##
##   <godot> --headless --path . res://tests/construction_rules_parity.tscn --quit-after 20000
##
## Prints one ENGINE line per scenario (the engine's own outcome, for comparing runs before
## and after a change to world_map) and a PARITY line where the helper disagrees. Exits 1 on
## any disagreement.

const Rules := preload("res://scripts/construction_rules.gd")

var _world: Node
var _toasts: Array = []
var _checks := 0
var _failures := 0
var _crowd_serial := 0


func _ready() -> void:
	_world = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(_world)
	await _settle(160)
	var camera := get_viewport().get_camera_2d()
	if camera != null:
		camera.set("edge_pan_enabled", false)
	MatchState.toast_requested.connect(func(m: String, _t: String) -> void: _toasts.append(m))
	MatchState.build_rejected_no_funds.connect(func(m: String) -> void: _toasts.append(m))

	var home := "tile_5_10"
	var sea := _find_tile(func(td: Dictionary) -> bool: return str(td.get("type", "")) == "sea")
	var deep := _find_tile(func(td: Dictionary) -> bool: return str(td.get("type", "")) == "deep_sea")
	var coal_recipe := _recipe_with_deposit("coal")
	var mine_id := str(coal_recipe.get("building_id", ""))
	var dry := _find_tile(func(td: Dictionary) -> bool:
		var t := str(td.get("type", ""))
		return t in ["rural", "hill"] and not Rules.deposits_include(td.get("deposits", []), "coal") \
			and BuildingState.get_tile_space_used(str(td.get("id", ""))) < 20.0)
	var offshore := str(Catalog.get_building_by_internal_name("offshore_wind_farm").get("id", ""))
	var solar := str(Catalog.get_building_by_internal_name("solar_farm").get("id", ""))
	print("[PARITY] tiles home=%s sea=%s deep=%s dry=%s mine=%s/%s ruleset=%s" % [home, sea, deep, dry, mine_id,
		str(coal_recipe.get("recipe_id", "")), str(MatchState.ruleset.get("logistics_model", ""))])

	# Buildings, the default game.
	await _build("factory, buys land", "b_002", "r_005", home, {"money": 50000.0, "land": 0})
	await _build("factory, land already owned", "b_002", "r_005", home, {"money": 50000.0, "land": 60})
	await _build("factory, no cash", "b_002", "r_005", home, {"money": 30.0, "land": 60})
	await _build("factory, cash for land only", "b_002", "r_005", home, {"money": 60.0, "land": 0})
	await _build("factory, auto buy off", "b_002", "r_005", home, {"money": 50000.0, "land": 0, "auto_buy": false})
	await _build("factory, auto buy off, confirm buys", "b_002", "r_005", home,
		{"money": 50000.0, "land": 0, "auto_buy": false, "buy_land": true})
	await _build("factory, kit on the tile", "b_002", "r_005", home, {"money": 50000.0, "land": 60, "stock_kit": true})
	await _build("factory, kit on the tile, no cash", "b_002", "r_005", home,
		{"money": 5.0, "land": 60, "stock_kit": true})
	await _build("factory, same tile source", "b_002", "r_005", home, {"money": 50000.0, "land": 60, "source": "same_tile"})
	await _build("factory, buys land, then the kit refuses", "b_002", "r_005", home,
		{"money": 50000.0, "land": 0, "source": "same_tile"})
	await _build("factory, any tile source, none spare", "b_002", "r_005", home,
		{"money": 50000.0, "land": 60, "source": "any_tile"})
	await _build("factory, any tile source, spare elsewhere", "b_002", "r_005", home,
		{"money": 50000.0, "land": 60, "source": "any_tile", "stock_kit_at": dry})
	await _build("factory, market source", "b_002", "r_005", home, {"money": 50000.0, "land": 60, "source": "market"})
	await _build("factory on sea", "b_002", "r_005", sea, {"money": 50000.0})
	if offshore != "":
		var off_recipe := _first_recipe(offshore)
		await _build("offshore wind on land", offshore, off_recipe, home, {"money": 50000.0, "land": 60})
	if solar != "":
		await _build("solar farm", solar, _first_recipe(solar), home, {"money": 50000.0, "land": 60})
	if mine_id != "" and dry != "":
		await _build("coal mine, surveyed, no coal", mine_id, str(coal_recipe.recipe_id), dry,
			{"money": 50000.0, "land": 60, "surveyed": true})
		await _build("coal mine, unsurveyed", mine_id, str(coal_recipe.recipe_id), dry,
			{"money": 50000.0, "land": 60, "unsurveyed": true})
	await _build("factory, tile full", "b_002", "r_005", dry, {"money": 50000.0, "land": 60, "crowd": 199.0})
	await _build("factory, past the planning limit", "b_002", "r_005", dry, {"money": 50000.0, "land": 60, "crowd": 120.0})
	await _build("factory, cash below the land price", "b_002", "r_005", home, {"money": 5.0, "land": 0})

	# Infrastructure, the default game.
	await _infra("cables where there are none", "cables", dry, {"money": 50000.0, "land": 60})
	await _infra("cables where the tile has them", "cables", home, {"money": 50000.0, "land": 60})
	await _infra("cables, kit on the tile", "cables", dry, {"money": 50000.0, "land": 60, "stock_kit_infra": "cables"})
	await _infra("cables, no cash", "cables", dry, {"money": 1.0, "land": 60})
	await _infra("cables, kit on the tile, past the planning limit", "cables", dry,
		{"money": 50000.0, "land": 60, "stock_kit_infra": "cables", "crowd": 120.0})
	await _infra("roads on sea", "roads", sea, {"money": 50000.0})
	await _infra("rails on sea", "rails", sea, {"money": 50000.0})
	await _infra("pipes on sea", "pipes", sea, {"money": 50000.0})
	await _infra("reinforced pipes on sea", "reinf_pipes", sea, {"money": 50000.0})
	await _infra("cables on sea", "cables", sea, {"money": 50000.0})
	if deep != "":
		await _infra("cables on deep sea", "cables", deep, {"money": 50000.0})
		await _infra("rails on deep sea", "rails", deep, {"money": 50000.0})
	await _infra("pipes, land short, auto buy off", "pipes", dry, {"money": 50000.0, "land": 0, "auto_buy": false})
	await _infra_twice("cables twice", "cables", dry, {"money": 50000.0, "land": 60})

	# The Logistics Intermediary game.
	var saved_ruleset: Dictionary = MatchState.ruleset.duplicate(true)
	MatchState.ruleset["logistics_model"] = "middleman_v1"
	await _build("intermediary: middleman source", "b_002", "r_005", home, {"money": 50000.0, "land": 60, "source": "middleman"})
	await _build("intermediary: market source, no licence", "b_002", "r_005", home,
		{"money": 50000.0, "land": 60, "source": "market"})
	await _build("intermediary: same tile source, no contracts", "b_002", "r_005", home,
		{"money": 50000.0, "land": 60, "source": "same_tile"})
	await _infra("intermediary: cables, no tendering", "cables", dry, {"money": 50000.0, "land": 60})
	MatchState.ruleset = saved_ruleset

	print("[PARITY] %d checks, %d disagreements" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)


# --- Scenarios --------------------------------------------------------------------------------

func _build(label: String, building_id: String, recipe_id: String, tile_id: String, setup: Dictionary) -> void:
	var saved := await _arrange(tile_id, setup, building_id)
	var td: Dictionary = _world.call("_tile_data_by_id", tile_id)
	var q: Dictionary = Rules.quote(building_id, recipe_id, tile_id, td,
		{"buy_land": bool(setup.get("buy_land", false))})
	var before := _snapshot(tile_id)
	BuildMode._last_attempt_ms = -100000
	_toasts.clear()
	var answered := BuildMode.attempt_direct_build(building_id, recipe_id, tile_id, bool(setup.get("buy_land", false)))
	await _settle(2)
	var after := _snapshot(tile_id)
	_compare(label, q, before, after, tile_id)
	var placed := int(after.projects) > int(before.projects) or int(after.buildings) > int(before.buildings)
	_expect(label, "answer", answered == placed, "attempt_direct_build answered %s, placed=%s" % [str(answered), str(placed)])
	await _undo(tile_id, saved)


func _infra(label: String, infra_type: String, tile_id: String, setup: Dictionary) -> void:
	var building_id := str(Catalog.get_building_by_internal_name(infra_type).get("id", ""))
	var saved := await _arrange(tile_id, setup, building_id)
	var td: Dictionary = _world.call("_tile_data_by_id", tile_id)
	var q: Dictionary = Rules.quote(building_id, "", tile_id, td, {})
	var before := _snapshot(tile_id)
	_toasts.clear()
	BuildMode.infrastructure_attempted.emit(infra_type, tile_id)
	await _settle(2)
	_compare(label, q, before, _snapshot(tile_id), tile_id)
	await _undo(tile_id, saved)


## The second of two identical infrastructure orders: the first is left running.
func _infra_twice(label: String, infra_type: String, tile_id: String, setup: Dictionary) -> void:
	var building_id := str(Catalog.get_building_by_internal_name(infra_type).get("id", ""))
	var saved := await _arrange(tile_id, setup, building_id)
	BuildMode.infrastructure_attempted.emit(infra_type, tile_id)
	await _settle(2)
	var td: Dictionary = _world.call("_tile_data_by_id", tile_id)
	var q: Dictionary = Rules.quote(building_id, "", tile_id, td, {})
	var before := _snapshot(tile_id)
	_toasts.clear()
	BuildMode.infrastructure_attempted.emit(infra_type, tile_id)
	await _settle(2)
	_compare(label, q, before, _snapshot(tile_id), tile_id)
	await _undo(tile_id, saved)


# --- Comparison -------------------------------------------------------------------------------

func _compare(label: String, q: Dictionary, before: Dictionary, after: Dictionary, tile_id: String) -> void:
	var placed := int(after.projects) > int(before.projects) or int(after.buildings) > int(before.buildings)
	var spent := float(before.money) - float(after.money)
	var land_bought := int(after.land) - int(before.land)
	var status := ""
	for iid: Variant in Construction.construction_projects:
		if not before.project_ids.has(iid):
			status = str((Construction.construction_projects[iid] as Dictionary).get("status", ""))
	var first_block := str((q.blocks[0] as Dictionary).key) if not (q.blocks as Array).is_empty() else ""
	print("[ENGINE] %s | placed=%s spent=%.2f land=%+d status=%s | %s" % [label, str(placed), spent, land_bought,
		status, str(_toasts[0]) if not _toasts.is_empty() else ""])
	print("[RULES]  %s | ok=%s first=%s fee=%.2f materials=%.2f land=%.2f total=%.2f warnings=%s" % [label,
		str(q.ok), first_block, float(q.get("fee", 0.0)), float(q.get("materials", 0.0)), float(q.get("land", 0.0)),
		float(q.get("total", 0.0)), ",".join(PackedStringArray((q.warnings as Array).map(func(w: Variant) -> String: return str((w as Dictionary).key))))])
	_expect(label, "placed", placed == bool(q.ok), "engine placed=%s, rules ok=%s (%s)" % [str(placed), str(q.ok), first_block])
	# Cash and land: a placed build spends the quote's total, land included. A refused one spends
	# nothing and keeps no land: land bought on the way is returned with its cash.
	var land_plan: Dictionary = q.get("land_plan", {})
	var expected_spent := float(q.total) if bool(q.ok) else 0.0
	var expected_land := int(land_plan.get("owned_after", 0)) - int(land_plan.get("owned", 0)) \
		if bool(q.ok) and bool(land_plan.get("will_buy", false)) else 0
	_expect(label, "cash", absf(spent - expected_spent) < 0.02,
		"engine spent %.2f, rules expect %.2f" % [spent, expected_spent])
	_expect(label, "land", land_bought == expected_land,
		"engine bought %d land, rules expect %d" % [land_bought, expected_land])


func _expect(label: String, what: String, ok: bool, detail: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		print("[PARITY] MISMATCH %s: %s: %s" % [label, what, detail])


# --- State ------------------------------------------------------------------------------------

func _snapshot(tile_id: String) -> Dictionary:
	return {"money": MatchState.money, "land": BuildingState.get_tile_land_owned(tile_id),
		"projects": Construction.construction_projects.size(), "buildings": BuildingState.buildings.size(),
		"project_ids": Construction.construction_projects.keys()}


func _arrange(tile_id: String, setup: Dictionary, building_id: String) -> Dictionary:
	var saved := {
		"money": MatchState.money, "land": BuildingState.tile_land_owned.duplicate(true),
		"auto_buy": MatchState.construct_auto_buy_land, "source": MatchState.construct_material_source,
		"surveyed": MatchState.surveyed_tiles.duplicate(true), "partial": MatchState.partially_surveyed_tiles.duplicate(true),
		"projects": Construction.construction_projects.keys(), "buildings": BuildingState.buildings.keys(),
		"stock": {}, "stock_tiles": [tile_id, str(setup.get("stock_kit_at", ""))],
	}
	for t: Variant in saved.stock_tiles:
		if str(t) != "":
			(saved.stock as Dictionary)[str(t)] = _stock_of(str(t))
	MatchState.money = float(setup.get("money", 50000.0))
	if setup.has("land"):
		BuildingState.tile_land_owned[tile_id] = int(setup.land)
	MatchState.construct_auto_buy_land = bool(setup.get("auto_buy", true))
	MatchState.pending_build_material_source = ""
	MatchState.construct_material_source = str(setup.get("source", "middleman"))
	if bool(setup.get("surveyed", false)):
		MatchState.surveyed_tiles[tile_id] = true
	if bool(setup.get("unsurveyed", false)):
		MatchState.surveyed_tiles.erase(tile_id)
		MatchState.partially_surveyed_tiles.erase(tile_id)
	if bool(setup.get("stock_kit", false)):
		_stock_kit(tile_id, building_id)
	if str(setup.get("stock_kit_infra", "")) != "":
		_stock_kit(tile_id, building_id)
	if str(setup.get("stock_kit_at", "")) != "":
		BuildingState.tile_land_owned[str(setup.stock_kit_at)] = maxi(10, BuildingState.get_tile_land_owned(str(setup.stock_kit_at)))
		_stock_kit(str(setup.stock_kit_at), building_id)
	if setup.has("crowd"):
		# NPC buildings with the land to take the tile's use to `crowd`.
		var need := float(setup.crowd) - BuildingState.get_tile_space_used(tile_id)
		while need > 0.5:
			var iid := BuildingState.add_building("b_002", "", tile_id, "npc", "parity_crowd_%d" % _crowd_serial, false)
			_crowd_serial += 1
			if iid == "":
				break
			need = float(setup.crowd) - BuildingState.get_tile_space_used(tile_id)
	await _settle(1)
	return saved


func _undo(tile_id: String, saved: Dictionary) -> void:
	for iid: Variant in Construction.construction_projects.keys():
		if not (saved.projects as Array).has(iid):
			Construction.cancel(str(iid))
	for iid: Variant in BuildingState.buildings.keys():
		if not (saved.buildings as Array).has(iid):
			BuildingState.buildings.erase(iid)
			for t: Variant in BuildingState.tile_buildings:
				(BuildingState.tile_buildings[t] as Array).erase(iid)
	for t: Variant in saved.stock:
		_set_stock(str(t), saved.stock[t])
	BuildingState.tile_land_owned = saved.land
	MatchState.money = float(saved.money)
	MatchState.construct_auto_buy_land = bool(saved.auto_buy)
	MatchState.construct_material_source = str(saved.source)
	MatchState.pending_build_material_source = ""
	MatchState.surveyed_tiles = saved.surveyed
	MatchState.partially_surveyed_tiles = saved.partial
	await _settle(2)


func _stock_kit(tile_id: String, building_id: String) -> void:
	var reqs: Dictionary = Construction.requirements_for(building_id)
	for good_id: Variant in reqs:
		Stockpile.add(tile_id, str(good_id), int(reqs[good_id]))


func _stock_of(tile_id: String) -> Dictionary:
	var out := {}
	for good: Variant in Catalog.all_goods():
		var gid := str((good as Dictionary).get("id", ""))
		var n := Stockpile.get_at_tile(tile_id, gid)
		if n != 0:
			out[gid] = n
	return out


func _set_stock(tile_id: String, wanted: Dictionary) -> void:
	for good: Variant in Catalog.all_goods():
		var gid := str((good as Dictionary).get("id", ""))
		var have := Stockpile.get_at_tile(tile_id, gid)
		var want := int(wanted.get(gid, 0))
		if have > want:
			Stockpile.consume(tile_id, gid, have - want)
		elif want > have:
			Stockpile.add(tile_id, gid, want - have)


# --- Lookups ----------------------------------------------------------------------------------

func _find_tile(pred: Callable) -> String:
	var terrain: Node = _world.get("terrain_layer")
	var ids: Array = []
	for coord: Variant in terrain.get("tiles"):
		var td: Dictionary = terrain.get("tiles")[coord]
		if pred.call(td):
			ids.append(str(td.get("id", "")))
	ids.sort()
	return str(ids[0]) if not ids.is_empty() else ""


func _recipe_with_deposit(token: String) -> Dictionary:
	for recipe: Variant in Catalog.all_recipes():
		for req: Variant in (recipe as Dictionary).get("requirements", []):
			if str((req as Dictionary).get("type", "")) == "deposit" and str((req as Dictionary).get("value", "")) == token:
				return recipe
	return {}


func _first_recipe(building_id: String) -> String:
	for recipe: Variant in Catalog.all_recipes():
		if str((recipe as Dictionary).get("building_id", "")) == building_id:
			return str((recipe as Dictionary).get("recipe_id", ""))
	return ""


func _settle(frames: int) -> void:
	for _i in frames:
		await get_tree().process_frame
