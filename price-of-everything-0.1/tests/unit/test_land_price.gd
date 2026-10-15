extends "res://tests/test_base.gd"
## Land prices (scripts/land_price.gd, docs/land-pricing-spec.md): bands, the building ramp, neighbours,
## stand-alone purchases, the economy index, and the surfaces that quote them.

const FEATURE := "land"
const LandPrice := preload("res://scripts/land_price.gd")
const MiddlemanLocations := preload("res://scripts/middleman_locations.gd")
const TAGS := {
	"_test_land_save_round_trip_and_migration": ["land", "save_load"],
	"_test_land_surfaces_match_quote": ["land", "construction"],
	"_test_land_refused_build_returns_priced_land": ["land", "construction"],
}


## One tile of each band, chosen as the first in id order: {band: tile_id}. Only tiles whose neighbours are
## all outside the test's own fixtures matter, so the first of each is enough.
func _tile_of_band() -> Dictionary:
	var out := {}
	var tiles: Array = MiddlemanLocations._terrain().keys()
	tiles.sort()
	for t: String in tiles:
		var b := LandPrice.band(t)
		if not out.has(b) and Catalog.tile_type(t) not in ["sea", "deep_sea"]:
			out[b] = t
	return out


## A rural tile with a rural neighbour, for the neighbour rules: [tile, neighbour, another neighbour].
func _rest_cluster() -> Array:
	var tiles: Array = MiddlemanLocations._terrain().keys()
	tiles.sort()
	for t: String in tiles:
		if LandPrice.band(t) != "rest" or Catalog.tile_type(t) != "rural":
			continue
		var rural: Array = []
		for n: String in Catalog.tile_neighbours(t):
			if LandPrice.band(n) == "rest" and Catalog.tile_type(n) == "rural":
				rural.append(n)
		if rural.size() >= 2:
			return [t, rural[0], rural[1]]
	return []


func _fresh() -> void:
	MatchState.reset()
	Stockpile.clear_all()
	BuildingState.land_economy_level = 0
	MatchState.money = 100000.0


func _test_land_band_prices() -> void:
	_fresh()
	var by_band := _tile_of_band()
	var want := {"hub_city": 100.0, "city": 60.0, "town": 40.0, "rest": 20.0}
	for b: String in want:
		_check(by_band.has(b) and absf(float(LandPrice.quote(str(by_band[b]), 1, false).per_patch) - float(want[b])) < 0.001,
			"land: a fresh %s tile quotes £%d a patch" % [b, int(want[b])])
	var counts := {"hub_city": 0, "city": 0, "town": 0, "rest": 0}
	for t: String in MiddlemanLocations._terrain():
		if Catalog.tile_type(t) in ["sea", "deep_sea"]:
			continue
		counts[LandPrice.band(t)] += 1
	print("[land] land tiles by band: %s" % str(counts))
	_check(int(counts.hub_city) == 27 and int(counts.city) == 31 and int(counts.town) == 34 and int(counts.rest) == 303,
		"land: the bands hold 27 hub city, 31 city, 34 town and 303 other land tiles")
	_check(LandPrice.band("tile_14_2") == "hub_city", "land: the inland hub's city is a hub city")
	# A port the player builds lifts Local Suppliers' class, never the land band.
	var town := str(by_band.town)
	var port := BuildingState.add_building("b_004", "", town, MatchState.LOCAL_PLAYER, "land_port", false)
	_check(MiddlemanLocations.settlement_class(town) == "hub_city" and LandPrice.band(town) == "town",
		"land: a built port makes a hub for Local Suppliers but leaves the land band fixed")
	BuildingState.remove_building(port)
	_fresh()


func _test_land_ramp_adds() -> void:
	_fresh()
	var tile := str(_rest_cluster()[0])
	var s := LandPrice.starting_price(tile)
	for i in 4:
		BuildingState.add_building("b_002", "", tile, MatchState.LOCAL_PLAYER, "land_ramp_%d" % i, false)
	var q := LandPrice.quote(tile, 1, false)
	_check(LandPrice.counted_buildings(tile) == 4 and absf(float(q.per_patch) - 3.0 * s) < 0.001,
		"land: four counted buildings give 3.0 x S, not 1.5^4 x S")
	_fresh()


func _test_land_exempt_and_infrastructure_do_not_count() -> void:
	_fresh()
	var tile := str(_rest_cluster()[0])
	var start := BuildingState.add_building("b_002", "", tile, MatchState.LOCAL_PLAYER, "land_start", false)
	BuildingState.buildings[start]["land_exempt"] = true
	BuildingState.add_building("b_005", "", tile, MatchState.LOCAL_PLAYER, "land_road", false)
	BuildingState.add_building("b_004", "", tile, MatchState.LOCAL_PLAYER, "land_port2", false)
	BuildingState.add_building("b_002", "", tile, "npc_rival", "land_npc", false)
	_check(LandPrice.counted_buildings(tile) == 0,
		"land: the starting estate, infrastructure and other companies' buildings do not count")
	# The start config stamps its estate exempt.
	var snap: Dictionary = SaveLoad.expand_start_config({"buildings": [
		{"building_id": "b_002", "tile_id": tile, "recipe_id": ""},
		{"building_id": "b_002", "tile_id": tile, "recipe_id": "", "owner": "npc_rival"}]})
	var exempt := 0
	for inst: Dictionary in (snap.match.buildings as Dictionary).values():
		if bool(inst.get("land_exempt", false)):
			exempt += 1
	_check(exempt == 1, "land: a start's own buildings arrive land exempt")
	_fresh()


func _test_land_under_construction_counts() -> void:
	_fresh()
	var tile := str(_rest_cluster()[0])
	Construction.construction_projects["land_proj"] = {"instance_id": "land_proj", "building_id": "b_002",
		"tile_id": tile, "status": "under_construction", "reserved_space": 0.0}
	_check(LandPrice.counted_buildings(tile) == 1, "land: a building under construction counts")
	Construction.construction_projects.erase("land_proj")
	_fresh()


func _test_land_buying_a_rival_works_moves_no_price() -> void:
	_fresh()
	var by_band := _tile_of_band()
	var tile := str(by_band.hub_city)
	var iid := BuildingState.add_building("b_002", "", tile, "npc_rival", "land_rival", false)
	var tiles: Array = MiddlemanLocations._terrain().keys()
	var before := {}
	for t: String in tiles:
		before[t] = float(LandPrice.quote(t, 1, false).total)
	BuildingState.set_building_owner(iid, MatchState.LOCAL_PLAYER)
	var moved := 0
	for t: String in tiles:
		if absf(float(LandPrice.quote(t, 1, false).total) - float(before[t])) > 0.0001:
			moved += 1
	_check(tiles.size() >= 395 and moved == 0,
		"land: buying a rival's building leaves every one of %d tiles' quotes unchanged" % tiles.size())
	_check(bool(BuildingState.buildings[iid].get("land_exempt", false)) and not BuildingState.tile_land_priced.has(tile),
		"land: the bought works is land exempt and its footprint is not priced land")
	_fresh()


func _test_land_neighbours() -> void:
	_fresh()
	var c := _rest_cluster()
	var tile := str(c[0])
	var s := LandPrice.starting_price(tile)
	BuildingState.purchase_tile_land(str(c[1]), 1)
	BuildingState.purchase_tile_land(str(c[2]), 1)
	_check(absf(LandPrice.adjacency_share(tile) - 0.25) < 0.0001 and absf(float(LandPrice.quote(tile, 1, false).per_patch) - 1.25 * s) < 0.001,
		"land: two neighbours with bought land still add 0.25 once")
	_fresh()
	BuildingState.purchase_tile_land(tile, 1)
	_check(LandPrice.adjacency_share(tile) == 0.0, "land: a tile's own land does not raise its own price")
	# Land granted under a bought building is not bought land.
	_fresh()
	var iid := BuildingState.add_building("b_002", "", str(c[1]), "npc_rival", "land_grant", false)
	BuildingState.set_building_owner(iid, MatchState.LOCAL_PLAYER)
	_check(LandPrice.adjacency_share(tile) == 0.0, "land: the footprint of a bought building raises no neighbour")
	_fresh()


func _test_land_standalone() -> void:
	_fresh()
	var c := _rest_cluster()
	var tile := str(c[0])
	var next := str(c[1])
	var s := LandPrice.starting_price(tile)
	var cash := MatchState.money
	BuildingState.purchase_tile_land(tile, 1, BuildingState.MAX_TILE_LAND, true)
	_check(absf((cash - MatchState.money) - 2.0 * s) < 0.001, "land: a stand-alone purchase charges double")
	_check(absf(LandPrice.adjacency_share(next) - 2.0) < 0.0001, "land: and raises its neighbours to 2.0 at once")
	cash = MatchState.money
	BuildingState.purchase_tile_land(next, 1, BuildingState.MAX_TILE_LAND, true)
	_check(absf((cash - MatchState.money) - LandPrice.starting_price(next) * 3.0 * 2.0) < 0.001,
		"land: a second stand-alone purchase beside it in the same turn pays S x 3 x 2")
	# The 200% replaces the 25%: a tile beside both a stand-alone tile and ordinary bought land.
	_fresh()
	BuildingState.purchase_tile_land(str(c[1]), 1, BuildingState.MAX_TILE_LAND, true)
	BuildingState.purchase_tile_land(str(c[2]), 1)
	_check(absf(LandPrice.adjacency_share(tile) - 2.0) < 0.0001, "land: the 200% replaces the 25% and does not add to it")
	_check(not (tile in LandPrice.standalone_rises(str(c[1]))), "land: a confirm names only neighbours that would still rise")
	# Selling all the bought land clears the flag.
	BuildingState.sell_tile_land(str(c[1]), 1, 0.0)
	_check(not BuildingState.tile_land_standalone.has(str(c[1])) and absf(LandPrice.adjacency_share(tile) - 0.25) < 0.0001,
		"land: selling all the bought land clears the stand-alone flag")
	_fresh()


func _test_land_economy_index() -> void:
	_fresh()
	var g0 := LandPrice.base_revenue()
	_check(LandPrice.doublings(g0 * 0.99) == 0 and LandPrice.doublings(g0 * 2.0) == 1 and LandPrice.doublings(g0 * 4.5) == 2
		and LandPrice.doublings(0.0) == 0, "land: doublings count whole doublings over G0 and never go negative")
	var by_band := _tile_of_band()
	BuildingState.land_economy_level = 1
	var town := str(by_band.town)
	var rest := str(by_band.rest)
	_check(absf(LandPrice.economy_share(town) - 0.25) < 0.0001 and LandPrice.economy_share(rest) == 0.0,
		"land: at twice G0 urban tiles gain 0.25 and other tiles nothing")
	BuildingState.land_economy_level = 3
	_check(LandPrice.tick_economy() == 3, "land: a dip in revenue does not lower the latched level")
	BuildingState.land_economy_level = -1
	_check(LandPrice.economy_level() == LandPrice.doublings(CompanyRankings.global_revenue()),
		"land: an unknown level is read from the standings")
	_fresh()


func _test_land_refused_build_returns_priced_land() -> void:
	_fresh()
	var tile := str(_rest_cluster()[0])
	var owned := BuildingState.get_tile_land_owned(tile)
	var cash := MatchState.money
	BuildingState.purchase_tile_land(tile, 2)
	var paid := cash - MatchState.money
	BuildingState.return_tile_land(tile, owned, paid)
	_check(BuildingState.get_tile_land_owned(tile) == owned and absf(MatchState.money - cash) < 0.001
		and not BuildingState.tile_land_priced.has(tile),
		"land: a refused build returns the land, the cash and the priced land count")
	_fresh()


func _test_land_advisor_applies_last() -> void:
	_fresh()
	var tile := str(_rest_cluster()[0])
	var plain := float(LandPrice.quote(tile, 2, false).total)
	var id := Modifiers.add({"domain": "purchase_cost", "pct": -20.0, "label": "test"})
	var q := LandPrice.quote(tile, 2, false)
	_check(absf(float(q.total) - plain * 0.8) < 0.001 and absf(float(q.per_patch) * 2.0 - plain) < 0.001
		and float(q.advisor_pct) == -20.0, "land: the adviser modifier applies after the formula")
	Modifiers.remove(id)
	_fresh()


func _test_land_save_round_trip_and_migration() -> void:
	_fresh()
	var c := _rest_cluster()
	BuildingState.purchase_tile_land(str(c[0]), 1, BuildingState.MAX_TILE_LAND, true)
	BuildingState.purchase_tile_land(str(c[1]), 2)
	BuildingState.land_economy_level = 2
	BuildingState.land_economy_warned = 3
	var saved := BuildingState.export_fields()
	var before := float(LandPrice.quote(str(c[2]), 1, false).total)
	_fresh()
	BuildingState.import_fields(JSON.parse_string(JSON.stringify(saved)))
	_check(BuildingState.tile_land_standalone.has(str(c[0])) and int(BuildingState.tile_land_priced.get(str(c[1]), 0)) == 20
		and BuildingState.land_economy_level == 2 and BuildingState.land_economy_warned == 3
		and absf(float(LandPrice.quote(str(c[2]), 1, false).total) - before) < 0.001,
		"land: priced land, stand-alone tiles and the economy level survive a save")
	var old := {"save_version": 16, "match": {"buildings": {
		"a": {"instance_id": "a", "building_id": "b_002", "tile_id": str(c[0]), "owner": MatchState.LOCAL_PLAYER},
		"b": {"instance_id": "b", "building_id": "b_002", "tile_id": str(c[0]), "owner": "npc_rival"}}}}
	var migrated: Dictionary = SaveLoad._migrate(old)
	_check(int(migrated.save_version) == SaveLoad.SAVE_VERSION and bool(migrated.match.buildings.a.get("land_exempt", false))
		and not migrated.match.buildings.b.has("land_exempt") and int(migrated.match.land_economy_level) == -1,
		"land: a v16 save migrates with its estate exempt and its level read on load")
	_fresh()
	BuildingState.import_fields(migrated.match)
	_check(LandPrice.counted_buildings(str(c[0])) == 0 and BuildingState.tile_land_priced.is_empty(),
		"land: so an old estate opens at band prices")
	_fresh()


func _test_land_terms_sum_and_determinism() -> void:
	_fresh()
	var c := _rest_cluster()
	var tile := str(c[0])
	BuildingState.add_building("b_002", "", tile, MatchState.LOCAL_PLAYER, "land_t1", false)
	BuildingState.purchase_tile_land(str(c[1]), 1)
	BuildingState.land_economy_level = 1
	for standalone: bool in [false, true]:
		var q := LandPrice.quote(tile, 3, standalone)
		var sum := 0.0
		for term: Dictionary in q.terms:
			sum += float(term.amount)
		_check(absf(sum - float(q.per_patch)) < 0.001, "land: the quote's lines sum to the patch price (stand-alone %s)" % str(standalone))
		_check(JSON.stringify(q) == JSON.stringify(LandPrice.quote(tile, 3, standalone)), "land: the same state gives the same quote")
	_fresh()


func _test_land_surfaces_match_quote() -> void:
	_fresh()
	var tile := str(_rest_cluster()[0])
	BuildingState.add_building("b_002", "", tile, MatchState.LOCAL_PLAYER, "land_s1", false)
	BuildingState.tile_land_owned[tile] = int(ceil(BuildingState.get_tile_player_space_used(tile)))
	MatchState.set_construct_auto_buy_land(true, false)
	var plan: Dictionary = preload("res://scripts/construction_rules.gd").land_plan(tile, "b_002")
	var want := LandPrice.quote(tile, int(plan.patches), false)
	_check(int(plan.patches) > 0 and absf(float(plan.cost) - float(want.total)) < 0.001,
		"land: the construct plan's land cost equals the quote")
	var hover: Dictionary = preload("res://scripts/construction_hover.gd").preview(tile, "b_002", "")
	_check(absf(float(hover.land) - float(want.total)) < 0.001, "land: the build hover prices land as the quote")
	var tq: Dictionary = preload("res://scripts/tvp_v3/transport_quote.gd").quote(tile, "b_005")
	var road_patches := ceili((BuildingState.get_tile_player_space_used(tile) + float(Catalog.get_building("b_005").get("tile_size_used", 1.0))
		- float(BuildingState.get_tile_land_owned(tile))) / float(BuildingState.LAND_PATCH_SIZE))
	_check(road_patches <= 0 or absf(float(tq.land_cost) - float(LandPrice.quote(tile, road_patches, false).total)) < 0.001,
		"land: a link's quote prices land as the quote")
	# Paying as you go on a fresh tile: the first build pays the band price, and the build after it one step more.
	var cash := MatchState.money
	BuildingState.purchase_tile_land(tile, int(plan.patches))
	_check(absf((cash - MatchState.money) - float(want.total)) < 0.001, "land: buying for a build charges what the plan said")
	_fresh()


func _test_land_readouts() -> void:
	_fresh()
	var c := _rest_cluster()
	var tile := str(c[0])
	BuildingState.add_building("b_002", "", tile, MatchState.LOCAL_PLAYER, "land_r1", false)
	BuildingState.add_building("b_002", "", tile, MatchState.LOCAL_PLAYER, "land_r2", false)
	BuildingState.purchase_tile_land(str(c[1]), 1)
	var panel := preload("res://scripts/tile_info_panel_v2.gd")
	var lines: Array = panel.land_price_lines(tile)
	var labels: Array = lines.map(func(l: Array) -> String: return str(l[0]))
	var s := LandPrice.starting_price(tile)
	_check(labels.has("2 buildings here") and labels.has("Next to your land") and labels.has("Per patch")
		and str(lines[labels.find("Per patch")][1]) == LandPrice.pounds(s * 2.25),
		"land: the tile panel prints the band, each rise and the patch price")
	var text: String = panel.buy_land_confirm_text(tile, 20)
	_check(text.contains(LandPrice.pounds(s * 2.25 * 2.0 * 2.0)) and text.contains(Catalog.tile_label(str(c[2]))),
		"land: the stand-alone confirm shows the doubled price and names a neighbour that will rise")
	_check(LandPrice.pounds(1250.0) == "£1,250" and LandPrice.pounds(40.0) == "£40" and LandPrice.pounds(12.5) == "£12.50",
		"land: prices print as whole pounds with thousands separators")
	var overlay := preload("res://scripts/land_price_overlay.gd")
	_check(overlay.shade(20.0) != overlay.shade(100.0) and overlay.shade(400.0) == overlay.shade(4000.0),
		"land: the map mode shades by price and saturates at the top")
	_check(MapMode.SENTINEL_MODES.has(MapMode.Mode.LAND_PRICE), "land: the land price map mode is a whole map mode")
	var search: Node = preload("res://scripts/search_overlay.gd").new()
	var body: String = search.call("_mechanic_body", "land_prices")
	search.free()
	_check(body.contains("£100") and body.contains("£20") and body.contains("costs double"),
		"land: the encyclopedia states the land price rules from the live constants")
	_check(preload("res://scripts/top_bar.gd").economy_line().begins_with("All companies took"),
		"land: the rankings print global revenue and the next doubling")
	_fresh()


## Worked example A: Metal Magnate's next furnace on Greyroad needs one patch, at the town price, because the
## starting estate is exempt.
func _test_land_example_metal_magnate() -> void:
	_fresh()
	var cfg: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/starts/metal_magnate.json"))
	var snap: Dictionary = SaveLoad.expand_start_config(cfg)
	BuildingState.import_fields(snap.match)
	BuildingState._rebuild_tile_index()
	var tile := "tile_9_9"
	MatchState.set_construct_auto_buy_land(true, false)
	var plan: Dictionary = preload("res://scripts/construction_rules.gd").land_plan(tile, "b_002")
	_check(LandPrice.band(tile) == "town" and int(plan.free) == 14 and int(plan.patches) == 1 and absf(float(plan.cost) - 40.0) < 0.001,
		"land: Metal Magnate's first new furnace on Greyroad buys 1 patch for £40")
	_check(LandPrice.economy_level() == 0, "land: a fresh start opens with the economy level at 0")
	_fresh()
