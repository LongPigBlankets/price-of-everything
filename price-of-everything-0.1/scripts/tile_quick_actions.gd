extends RefCounted
## What a tile's quick menu (right click on the map) can do, and the doing of it: sell the tile's surplus, sell all
## of one good, buy all the land left, sell the spare land, and build a favourite. Each `*_option` says whether
## the action can run here and what it will do, in the words the menu prints; each verb does it through the same
## engine paths the panels use. tile_quick_menu.gd only draws these.
##
## Selling goes to the global market at once (MatchState.queue_sell) where it is open, else to Local Suppliers in
## this turn's sell phase (MatchState.queue_local_sale). Buying land is a stand-alone purchase (LandPrice). Selling
## land sells whole patches of bought land no building uses, at LandPrice.sale_price.

const LandPrice := preload("res://scripts/land_price.gd")
const MiddlemanService := preload("res://scripts/middleman_service.gd")
const MiddlemanLocations := preload("res://scripts/middleman_locations.gd")
const ConstructionRules := preload("res://scripts/construction_rules.gd")


## Where a sale from the tile goes: "market" (the global market, now), "local" (Local Suppliers, this turn) or ""
## (nowhere), with the reason when nowhere.
static func sale_route(tile_id: String) -> Dictionary:
	if MiddlemanService.global_market_open():
		return {"route": "market", "why": ""}
	if MiddlemanService.active() and MiddlemanLocations.coefficient(tile_id) > 0.0:
		return {"route": "local", "why": ""}
	return {"route": "", "why": "Nobody buys goods here yet."}


## Units of each good the route can take from the tile, from `goods` ({good_id: units}).
static func _sellable(tile_id: String, goods: Dictionary, route: String) -> Dictionary:
	var out := {}
	for gid in goods:
		var g := str(gid)
		var qty := int(goods[gid])
		if qty <= 0 or not Catalog.is_good_sellable(g):
			continue
		if route == "local":
			if not MiddlemanService.material_tradeable(g, "output"):
				continue
			qty -= MatchState.queued_local_units(tile_id, g)
			if qty <= 0:
				continue
		out[g] = qty
	return out


## The tile's surplus: stock above what its own buildings need to keep running (the reserve the standing Sell
## surplus order keeps) and above any "keep" the player set.
static func surplus(tile_id: String) -> Dictionary:
	var reserve: Dictionary = Production.compute_sell_reserve_for_tile(tile_id)
	var out := {}
	var totals: Dictionary = Stockpile.get_tile_totals(tile_id)
	for gid in totals:
		var qty := int(totals[gid]) - int(reserve.get(gid, 0)) - MatchState.auto_sell_keep_for(tile_id, str(gid))
		if qty > 0:
			out[str(gid)] = qty
	return out


static func _units(goods: Dictionary) -> int:
	var n := 0
	for gid in goods:
		n += int(goods[gid])
	return n


static func _route_words(route: String) -> String:
	return "to the global market" if route == "market" else "to Local Suppliers this turn"


## {ok, title, words, goods}: selling the tile's surplus.
static func surplus_option(tile_id: String) -> Dictionary:
	var r := sale_route(tile_id)
	var out := {"ok": false, "title": "Sell all surplus", "words": str(r.why), "goods": {}}
	if str(r.route) == "":
		return out
	var goods := _sellable(tile_id, surplus(tile_id), str(r.route))
	out.goods = goods
	if goods.is_empty():
		out.words = "Nothing here beyond what its buildings need."
		return out
	out.ok = true
	out.words = "%s units %s." % [_count(_units(goods)), _route_words(str(r.route))]
	return out


## [{good_id, name, qty, ok, words}]: each good on the tile, and whether all of it can be sold from here.
static func goods_options(tile_id: String) -> Array:
	var r := sale_route(tile_id)
	var rows: Array = []
	var totals: Dictionary = Stockpile.get_tile_totals(tile_id)
	var ids: Array = totals.keys()
	ids.sort_custom(func(a: Variant, b: Variant) -> bool: return Catalog.get_display_name(str(a)) < Catalog.get_display_name(str(b)))
	for gid in ids:
		var g := str(gid)
		if int(totals[gid]) <= 0:
			continue
		var can := _sellable(tile_id, {g: int(totals[gid])}, str(r.route)) if str(r.route) != "" else {}
		var row := {"good_id": g, "name": Catalog.get_display_name(g), "qty": int(totals[gid]), "ok": not can.is_empty()}
		if str(r.route) == "":
			row.words = str(r.why)
		elif can.is_empty():
			row.words = "Not sold %s." % _route_words(str(r.route)).trim_suffix(" this turn")
		else:
			row.words = "%s units %s." % [_count(int(can[g])), _route_words(str(r.route))]
		rows.append(row)
	return rows


## {ok, title, words}: the sell-a-good entry, which opens the goods list.
static func goods_entry(tile_id: String) -> Dictionary:
	var rows := goods_options(tile_id)
	var sellable := rows.filter(func(r: Dictionary) -> bool: return bool(r.ok))
	if rows.is_empty():
		return {"ok": false, "title": "Sell all of a good", "words": "No goods here."}
	if sellable.is_empty():
		return {"ok": false, "title": "Sell all of a good", "words": str(rows[0].words)}
	return {"ok": true, "title": "Sell all of a good", "words": "%d %s to choose from." % [sellable.size(), "good" if sellable.size() == 1 else "goods"]}


## Sell `goods` ({good_id: units}) from the tile by its route. Returns {ok, words} for a toast.
static func sell(tile_id: String, goods: Dictionary) -> Dictionary:
	var r := sale_route(tile_id)
	var route := str(r.route)
	var can := _sellable(tile_id, goods, route) if route != "" else {}
	if can.is_empty():
		return {"ok": false, "words": str(r.why) if route == "" else "Nothing here can be sold."}
	if route == "local":
		MatchState.queue_local_sale(tile_id, can)
		return {"ok": true, "words": "Local Suppliers buy %s units at the end of this turn." % _count(_units(can))}
	var sold: Dictionary = MatchState.queue_sell(tile_id, can)
	if sold.is_empty():
		return {"ok": false, "words": "No route to a port from here."}
	return {"ok": true, "words": "Selling %s units to the global market for %s." % [
		_count(int(sold.get("total_qty", 0))), LandPrice.pounds(roundf(float(sold.get("revenue", 0.0))))]}


## {ok, title, words, patches, units, cost, rises}: buying every patch left for sale, on its own.
static func buy_land_option(tile_id: String) -> Dictionary:
	var out := {"ok": false, "title": "Buy all land", "words": "", "patches": 0, "units": 0, "cost": 0.0, "rises": []}
	var cap := BuildingState.max_tile_land(tile_id)
	var patches := BuildingState.get_tile_land_patches_available(tile_id, cap)
	if Catalog.tile_type(tile_id) in ["sea", "deep_sea"] or patches <= 0:
		out.words = "No land left for sale here."
		return out
	var q := LandPrice.quote(tile_id, patches, true)
	out.patches = patches
	out.units = BuildingState.get_tile_land_units_available(tile_id, cap)
	out.cost = float(q.total)
	out.rises = LandPrice.standalone_rises(tile_id).filter(func(t: String) -> bool: return not (Catalog.tile_type(t) in ["sea", "deep_sea"]))
	if MatchState.money < float(q.total):
		out.words = "%s land costs %s. Not enough cash." % [_count(int(out.units)), LandPrice.pounds(float(q.total))]
		return out
	out.ok = true
	out.words = "%s land for %s, bought on its own." % [_count(int(out.units)), LandPrice.pounds(float(q.total))]
	return out


## What buying all the land says before it buys: the price, and the neighbours that rise.
static func buy_land_confirm(tile_id: String) -> String:
	var o := buy_land_option(tile_id)
	var text := "Land bought on its own costs double. %s land costs %s." % [_count(int(o.units)), LandPrice.pounds(float(o.cost))]
	var names: Array = (o.rises as Array).map(func(t: String) -> String: return place(t))
	if names.is_empty():
		return text
	return text + " Land next door on %s then rises by twice its starting price." % _and_list(names)


static func buy_all_land(tile_id: String) -> bool:
	var o := buy_land_option(tile_id)
	return bool(o.ok) and BuildingState.purchase_tile_land(tile_id, int(o.patches), BuildingState.max_tile_land(tile_id), true)


## {ok, title, words, patches, paid}: selling the spare land the player bought.
static func sell_land_option(tile_id: String) -> Dictionary:
	var patches := BuildingState.spare_land_patches(tile_id)
	var out := {"ok": patches > 0, "title": "Sell all spare land", "patches": patches,
		"paid": float(patches) * LandPrice.sale_price(tile_id)}
	if patches > 0:
		out.words = "%s land for %s." % [_count(patches * BuildingState.LAND_PATCH_SIZE), LandPrice.pounds(float(out.paid))]
	elif BuildingState.spare_land_units(tile_id) > 0:
		out.words = "Only land you bought can be sold."
	else:
		out.words = "No spare land here."
	return out


## [{favourite, ok, title, words, quote}]: every favourite, priced on this tile at its level.
static func favourite_options(tile_id: String, tile_data: Dictionary = {}) -> Array:
	var rows: Array = []
	for fav: Dictionary in MatchState.favourite_builds:
		var bid := str(fav.get("building_id", ""))
		var rid := str(fav.get("recipe_id", ""))
		var level := int(fav.get("level", 1))
		var q := ConstructionRules.quote(bid, rid, tile_id, tile_data, {"level": level, "buy_land": true})
		var row := {"favourite": fav, "ok": bool(q.get("ok", false)), "quote": q, "title": favourite_title(fav)}
		var blocks: Array = q.get("blocks", [])
		if not blocks.is_empty():
			row.words = str((blocks[0] as Dictionary).get("text", ""))
		else:
			row.words = "%s, %d turns." % [LandPrice.pounds(roundf(float(q.get("total", 0.0)))), int(q.get("build_turns", 0))]
		rows.append(row)
	return rows


## {ok, title, words}: the build-a-favourite entry, which opens the favourites list.
static func favourite_entry(tile_id: String, tile_data: Dictionary = {}) -> Dictionary:
	if MatchState.favourite_builds.is_empty():
		return {"ok": false, "title": "Build a favourite", "words": "Star a building in its panel to add it."}
	var buildable := favourite_options(tile_id, tile_data).filter(func(r: Dictionary) -> bool: return bool(r.ok))
	if buildable.is_empty():
		return {"ok": false, "title": "Build a favourite", "words": "None can be built here."}
	return {"ok": true, "title": "Build a favourite", "words": "%d of %d can be built here." % [buildable.size(), MatchState.favourite_builds.size()]}


## The favourite's name in a list: building, recipe and level.
static func favourite_title(fav: Dictionary) -> String:
	var name := Catalog.get_building_display_name(str(fav.get("building_id", "")))
	var recipe := str(Catalog.get_recipe(str(fav.get("recipe_id", ""))).get("display_name", ""))
	var level := int(fav.get("level", 1))
	var text := name if recipe == "" or recipe == name else "%s, %s" % [name, recipe.to_lower()]
	return text + ("" if level <= 1 else ", level %d" % level)


## Build the favourite on the tile at its level, buying the land it needs. True when it was placed.
static func build_favourite(tile_id: String, fav: Dictionary) -> bool:
	return BuildMode.attempt_direct_build(str(fav.get("building_id", "")), str(fav.get("recipe_id", "")), tile_id, true,
		int(fav.get("level", 1)))


## A tile's name as the player reads it, without its map coordinates.
static func place(tile_id: String) -> String:
	var n := Catalog.tile_name(tile_id)
	return n if n != "" else Catalog.tile_label(tile_id)


static func _count(n: int) -> String:
	var digits := str(absi(n))
	var grouped := ""
	while digits.length() > 3:
		grouped = "," + digits.right(3) + grouped
		digits = digits.left(digits.length() - 3)
	return ("-" if n < 0 else "") + digits + grouped


static func _and_list(names: Array) -> String:
	if names.size() <= 1:
		return "".join(names)
	return ", ".join(names.slice(0, names.size() - 1)) + " and " + str(names.back())
