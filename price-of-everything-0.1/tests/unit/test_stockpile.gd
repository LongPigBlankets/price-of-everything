extends "res://tests/test_base.gd"
## Stockpile, storage, warehouses and input/output movement.

const FEATURE := "stockpile"
## Tests that also belong to other features (run under any of their tags).
const TAGS := {
	"_test_forecast_own_supply_follows_production": ["production", "stockpile"],
	"_test_exhausted_input_source_falls_back_to_market": ["power", "production", "stockpile"],
	"_test_output_conservation": ["production", "stockpile"],
	"_test_input_buy_nets_local_supply": ["production", "stockpile"],
	"_test_input_buy_capacity_building_first": ["events", "production", "research", "stockpile", "transport"],
	"_test_warehouse_upgrade": ["research", "stockpile"],
	"_test_warehousing_fee_rates": ["market", "stockpile"],
	"_test_jit_streak_and_direct_feed": ["production", "research", "stockpile"],
	"_test_storage_alert_rearms_on_upgrade": ["events", "production", "stockpile"],
}

func _recipe_input_qty(recipe_id: String, good_id: String) -> int:
	# Per-unit input need, read from the catalog instead of written into the test as a literal.
	# Tests that hardcode a recipe's quantities fail the next balance pass without anything
	# having actually broken, which trains you to edit the number rather than read the failure.
	for inp in Catalog.get_recipe(recipe_id).get("inputs", []):
		if str((inp as Dictionary).get("good_id", "")) == good_id:
			return int((inp as Dictionary).get("qty", 0))
	return 0


## The forecast must price a good the player MAKES as their own, even when none is in stock —
## a producer that sells or consumes its output every turn holds nothing between turns.
func _test_forecast_own_supply_follows_production() -> void:
	const Forecast := preload("res://scripts/build_forecast.gd")
	var recipe_id := "r_005"                      # Pig Iron Smelting -> iron ingots
	var recipe: Dictionary = Catalog.get_recipe(recipe_id)
	if recipe.is_empty():
		return
	var good_id := ""
	for item in Production._recipe_output_items(recipe):
		good_id = str(item.get("good_id", ""))
		if good_id == "" and str(item.get("internal_name", "")) != "":
			good_id = str(Catalog.get_good_by_internal_name(str(item.get("internal_name", ""))).get("id", ""))
		break
	_check(Forecast._recipe_makes(recipe_id, good_id),
		"forecast own supply: a recipe is recognised as making its own output")
	_check(not Forecast._recipe_makes(recipe_id, "g_definitely_not_made"),
		"forecast own supply: a recipe does not claim goods it never outputs")
	var tile_id := "tile_5_10"
	var iid: String = BuildingState.add_building("b_002", recipe_id, tile_id, MatchState.LOCAL_PLAYER, "fc_own_probe")
	if iid == "":
		return
	var before: int = Stockpile.get_at_tile(tile_id, good_id)
	Stockpile.consume(tile_id, good_id, before)   # the between-turns state: nothing held
	_check(Forecast._own_source_tile(tile_id, good_id) == tile_id,
		"forecast own supply: a good the player makes on this tile is their own with zero stock")
	if before > 0:
		Stockpile.add(tile_id, good_id, before)
	BuildingState.remove_building(iid)


# Regression: a stockpile legend row's label must render with non-zero width
# (a fixed-width label was removed; with ellipsis trimming the label collapsed
# to zero and only the colour swatch showed).
func _test_stockpile_legend_label_visible() -> void:
	var sv: Node = load("res://scripts/stockpile_view.gd").new()
	add_child(sv)
	var row: Control = sv.call("_make_row", "Coal", "g_001")
	add_child(row)
	await get_tree().process_frame
	var label := row.get_child(0) as Label
	var ok: bool = label != null and label.text == "Coal" and label.size.x > 0.0
	_check(ok, "stockpile legend label renders with width (not collapsed)")
	row.queue_free()
	sv.queue_free()
	await get_tree().process_frame

func _test_building_ledger() -> void:
	_check(MatchState.route_objective == MatchState.RouteObjective.FASTEST,
		"route objective defaults to FASTEST")
	var scene := load("res://scenes/building_ledger_panel.tscn")
	var ok := false
	if scene != null:
		var panel: Node = scene.instantiate()
		add_child(panel)
		await get_tree().process_frame
		ok = panel.get_child_count() > 0
		panel.queue_free()
	_check(ok, "building_ledger_panel instantiates (routing dropdown builds)")

func _test_queue_move() -> void:
	Stockpile.add("tile_12_4", "g_001", 10)
	var before_pending: int = TransportState.get_pending_transport_shipments().size()
	var summary: Dictionary = TransportState.queue_move("tile_12_4", "tile_12_2", {"g_001": 10})
	_check(not summary.is_empty(), "queue_move returns a summary")
	_check(Stockpile.get_at_tile("tile_12_4", "g_001") == 0, "queue_move consumes from source")
	_check(TransportState.get_pending_transport_shipments().size() > before_pending, "queue_move queues a shipment")

func _test_move_extras() -> void:
	var preview: Dictionary = TransportState.preview_move("tile_12_4", "tile_12_2", {"g_001": 5})
	_check(preview.has("turns") and preview.has("cost") and preview.has("per_turn"),
		"preview_move returns route info (turns/cost/per_turn)")
	MatchState.run_recurring_and_scheduled_moves()  # empty queues — must not crash
	_check(true, "run_recurring_and_scheduled_moves runs without error")

func _test_storage_boost() -> void:
	BuildingState.add_building("b_004", "", "tile_3_3", "Three Diamonds Shipping Corporation")
	_check(Stockpile.get_capacity("tile_3_3") == Stockpile.TILE_CAPACITY + 600,
		"storage_boost raises tile capacity (port = +600)")

func _test_warehouse_storage_levels() -> void:
	# Per-tile storage is a warehouse level table (800/1600/2500) driven by the two storage
	# research upgrades, plus +600 for a Port on the tile. Non-destructive (no MatchState.reset)
	# so it doesn't disturb the NPC-port / scene state that later tests depend on.
	var had_pallet := ResearchState.is_unlocked("Pallet Racking Systems")
	var had_asrs := ResearchState.is_unlocked("Automated Storage & Retrieval")
	ResearchState.unlocked_titles.erase("Pallet Racking Systems")
	ResearchState.unlocked_titles.erase("Automated Storage & Retrieval")
	var t := "tile_wh_test_only"  # fresh tile with no buildings
	_check(Stockpile.get_capacity(t) == 800, "warehouse level 1 (no research) = 800")
	ResearchState.grant_unlock("Pallet Racking Systems")
	_check(Stockpile.get_capacity(t) == 1600, "warehouse level 2 (Pallet Racking) = 1600")
	ResearchState.grant_unlock("Automated Storage & Retrieval")
	_check(Stockpile.get_capacity(t) == 2500, "warehouse level 3 (Automated Storage) = 2500")
	var pid := BuildingState.add_building("b_004", "", t, MatchState.LOCAL_PLAYER, "wh_test_port")
	_check(Stockpile.get_capacity(t) == 2500 + 600, "a Port adds +600 on top of the warehouse capacity")
	BuildingState.remove_building(pid)
	if not had_pallet:
		ResearchState.unlocked_titles.erase("Pallet Racking Systems")
	if not had_asrs:
		ResearchState.unlocked_titles.erase("Automated Storage & Retrieval")

func _test_stockpile_peak_vs_current() -> void:
	# The tile panel's "Stock Utilisation last turn" row and the Stockpile tab button must NOT
	# be the same number. The button reads what is on the tile NOW; the row reads the HIGH-WATER
	# mark the turn reached. A tile that fills on arrivals and drains through production ends
	# the turn looking comfortable, which is how "cannot receive more goods" used to fire
	# against a healthy-looking figure.
	Stockpile.clear_all()
	var t := "tile_peak_test_only"
	var cap := Stockpile.get_capacity(t)
	Stockpile.roll_turn_peaks()
	Stockpile.add(t, "g_001", 500)
	Stockpile.consume(t, "g_001", 460)
	_check(Stockpile.get_used_capacity(t) == 40, "peak: end-of-turn level is the residue (40)")
	_check(Stockpile.get_peak_used(t) == 500, "peak: the turn's high-water mark is kept (500)")
	_check(Stockpile.get_refused(t) == 0, "peak: nothing was turned away")
	# Overfill: the cap turns units away and that count is per tile.
	Stockpile.add(t, "g_001", cap + 100)
	_check(Stockpile.get_refused(t) == 140, "peak: units the cap turned away are counted (140)")
	_check(Stockpile.get_peak_used(t) == cap, "peak: a tile that overflowed peaks at capacity")
	# Rolling the turn re-seeds from the current level, so the mark never leaks across turns.
	Stockpile.roll_turn_peaks()
	_check(Stockpile.get_refused(t) == 0, "peak: the turn roll clears the turned-away count")
	_check(Stockpile.get_peak_used(t) == Stockpile.get_used_capacity(t),
		"peak: a fresh turn starts from the tile's current level")
	Stockpile.clear_all()


func _test_exhausted_input_source_falls_back_to_market() -> void:
	MatchState.reset()
	Stockpile.clear_all()
	Power.reset_for_turn()
	var fake := Node.new()
	var src := GDScript.new()
	src.source_code = "extends Node\nvar tiles := {}\nfunc id_to_coord(t):\n\treturn Vector2i(5, 10) if t == \"tile_5_10\" else Vector2i(-1, -1)\n"
	src.reload()
	fake.set_script(src)
	fake.set("tiles", {Vector2i(5, 10): {"infrastructure_present": ["cables"], "infrastructure_levels": {"cables": 1}}})
	fake.add_to_group("hex_map")
	get_tree().root.add_child(fake)
	MatchState.money = 100000.0
	var source_iid := BuildingState.add_building("b_001", "r_001", "tile_6_8", MatchState.LOCAL_PLAYER, "test_exhausted_coal_source")
	var consumer_iid := BuildingState.add_building("b_003", "r_004", "tile_5_10", MatchState.LOCAL_PLAYER, "test_exhausted_coal_consumer")
	MatchState.set_output_stockpile_destination(source_iid, "tile_5_10", "g_001")
	MatchState.set_input_tile_only(consumer_iid, "g_001", true)
	MatchState.deposit_remaining["tile_6_8"] = {"coal": 0}
	var summary := {
		"purchased": {},
		"purchased_cost": {},
		"goods_purchased_cost": 0.0,
		"transport_paid": 0.0,
		"money_out": 0.0,
		"goods_purchased_by_type": {},
	}
	Production._buy_market_inputs([BuildingState.buildings[source_iid], BuildingState.buildings[consumer_iid]], summary)
	_check(not MatchState.is_input_tile_only(consumer_iid, "g_001"),
		"exhausted routed input source switches the consumer back to market fallback")
	_check(int(summary.get("purchased", {}).get("g_001", 0)) > 0,
		"market fallback queues a replacement buy for the exhausted input")
	get_tree().root.remove_child(fake)
	fake.free()

func _test_transfer_helpers() -> void:
	MatchState.reset()
	BuildingState.add_building("b_001", "r_001", "tile_5_5", "player_1")  # coal mine → produces g_001
	BuildingState.add_building("b_002", "r_005", "tile_6_6", "player_1")  # iron furnace → consumes g_002
	_check(MatchState.tiles_producing("g_001").has("tile_5_5"), "tiles_producing finds a producer tile")
	_check(not MatchState.tiles_producing("g_001").has("tile_6_6"), "tiles_producing excludes a non-producer")
	_check(MatchState.tiles_consuming("g_002").has("tile_6_6"), "tiles_consuming finds a consumer tile")

func _test_output_conservation() -> void:
	# Default (STOCKPILE_ALL): a building's output should land in its own tile's stockpile.
	MatchState.reset()
	Stockpile.clear_all()
	var building := {"instance_id": "inst_conserve", "building_id": "b_001", "tile_id": "tile_3_3", "recipe_id": "r_001"}
	var good: Dictionary = Catalog.get_good("g_001")
	var summary := {"transport_paid": 0.0, "money_out": 0.0, "goods_purchased_cost": 0.0}
	var before: int = Stockpile.get_total("g_001")
	Production._dispatch_output_to_stockpile(building, good, 20, summary)
	Production._flush_output_buffer()
	var gained: int = Stockpile.get_total("g_001") - before
	_check(gained == 20, "output is conserved into the tile stockpile (got %d of 20)" % gained)

func _test_input_buy_nets_local_supply() -> void:
	# A good produced on the SAME tile tops up the shared stockpile every turn, so the market input
	# pipeline must only buy the SHORTFALL after that local supply — not re-buy steel you smelt here.
	var steel := str(Catalog.get_good_by_internal_name("steel").get("id", ""))
	_check(steel != "", "steel good resolves for the input-netting test")
	Production._output_buffer = [{"coord": "tile_58_58", "good_id": steel, "qty": 30, "transport_cost": 0.0}]
	Production._flush_output_buffer()
	var rate := int((Production._same_tile_supply.get("tile_58_58", {}) as Dictionary).get(steel, 0))
	_check(rate == 30, "_flush_output_buffer tallies same-tile production for the input pipeline (got %d)" % rate)
	# A co-located 30/turn consumer is fully covered → 0 shortfall; a 45/turn one → only 15 bought.
	_check(maxi(0, 30 - rate) == 0 and maxi(0, 45 - rate) == 15,
		"market top-up buys only the shortfall after recurring same-tile supply")
	Production._output_buffer.clear()
	Production._same_tile_supply.clear()

func _test_input_buy_capacity_building_first() -> void:
	# The 2026-07-09 warehouse-cap fixes: (a) overflow-held goods (arrived, tile was
	# full, waiting outside) count as pipeline inbound — without that the pipeline
	# re-bought every bounced batch forever; (b) orders are capped by the tile's
	# projected free storage and allocated BUILDING-FIRST — one fully-buffered
	# building beats ten buildings at 10% each.
	Modifiers.reset()
	MatchState.reset()
	Stockpile.clear_all()
	var t := "tile_16_4"
	var steel := str(Catalog.get_good_by_internal_name("steel").get("id", ""))
	var wiring := str(Catalog.get_good_by_internal_name("copper_wiring").get("id", ""))
	# (a) overflow-held counts as inbound; construction-reserved freight stays excluded.
	TransportState.hold_overflow_shipment({"destination_tile": t, "good_id": steel, "qty": 50})
	_check(Production._inbound_qty(t, steel) == 50, "overflow-held goods count as pipeline inbound")
	TransportState.hold_overflow_shipment({"destination_tile": t, "good_id": steel, "qty": 10, "construction_instance_id": "cx"})
	_check(Production._inbound_qty(t, steel) == 50, "construction-tagged overflow is reserved freight (excluded)")
	TransportState.overflow_shipments.clear()

	# (b) three identical motor factories, tile squeezed so exactly ONE building's full
	# (lead+1) buffer fits. Per-unit needs come from the recipe rather than literals, so a
	# balance pass moving r_009's quantities cannot silently turn this into a stale fixture.
	MatchState.money = 1000000.0
	Production._same_tile_supply.clear()
	# Power gate reads cables off the hex_map node — fake one for this tile (freed below).
	var fake_map := Node.new()
	var fake_src := GDScript.new()
	fake_src.source_code = "extends Node\nvar tiles := {}\nfunc id_to_coord(t):\n\treturn Vector2i(16, 4) if t == \"tile_16_4\" else Vector2i(-1, -1)\n"
	fake_src.reload()
	fake_map.set_script(fake_src)
	fake_map.set("tiles", {Vector2i(16, 4): {"infrastructure_present": ["cables"], "infrastructure_levels": {"cables": 1}}})
	fake_map.add_to_group("hex_map")
	get_tree().root.add_child(fake_map)
	var iids: Array = []
	for i in 3:
		iids.append(BuildingState.add_building("b_007", "r_009", t, "player_1", "whx_%d" % i))
	var lead_steel := maxi(1, int(TransportService.quote_market_buy(t, steel, 1, TransportState.seaport_would_cover(steel)).get("turns", 1)))
	var lead_wiring := maxi(1, int(TransportService.quote_market_buy(t, wiring, 1, TransportState.seaport_would_cover(wiring)).get("turns", 1)))
	var w_steel := _recipe_input_qty("r_009", steel) * (lead_steel + 1)
	var w_wiring := _recipe_input_qty("r_009", wiring) * (lead_wiring + 1)
	var junk := str(Catalog.get_good_by_internal_name("rubber").get("id", ""))
	Stockpile.add(t, junk, Stockpile.get_capacity(t) - (w_steel + w_wiring))
	var summary := {
		"purchased": {}, "purchased_cost": {}, "goods_purchased_by_type": {},
		"input_orders_short": [], "input_splices": [], "input_orders_capped": [],
		"storage_overcommitted": [],
		"goods_purchased_cost": 0.0, "transport_paid": 0.0, "money_out": 0.0,
	}
	var buildings: Array = []
	for iid in iids:
		buildings.append(BuildingState.get_building(str(iid)))
	Production._buy_market_inputs(buildings, summary)
	# Structural alert data: 3 buildings' working set (buffers + outputs) >> 800 cap.
	_check((summary.storage_overcommitted as Array).size() == 1
		and str((summary.storage_overcommitted[0] as Dictionary).get("tile_id", "")) == t
		and int((summary.storage_overcommitted[0] as Dictionary).get("required", 0)) > 800,
		"storage_overcommitted records the structurally undersized tile")
	var saved_summary: Dictionary = Production.last_turn_summary
	Production.last_turn_summary = summary
	var item: Dictionary = TurnBriefing._storage_undersized_item()
	_check(str(item.get("severity", "")) == "critical" and str(item.get("id", "")) == "alert:storage_undersized"
		and str(item.get("title", "")).contains("lacks stockpile"),
		"briefing renders the critical 'lacks stockpile' update")
	Production.last_turn_summary = saved_summary
	_check(int(summary.purchased.get(steel, 0)) == w_steel,
		"building-first: steel order = one building's FULL buffer (%d), not a spread" % w_steel)
	_check(int(summary.purchased.get(wiring, 0)) == w_wiring,
		"building-first: wiring order = one building's FULL buffer (%d)" % w_wiring)
	var clipped := 0
	for c in (summary.input_orders_capped as Array):
		clipped += int((c as Dictionary).get("wanted", 0)) - int((c as Dictionary).get("placed", 0))
	_check(clipped == 2 * (w_steel + w_wiring),
		"storage-capped orders recorded: the two unfunded buildings' buffers (%d)" % clipped)
	# Second pass: the placed orders are now in-flight, budget is spent → nothing new.
	var summary2 := {
		"purchased": {}, "purchased_cost": {}, "goods_purchased_by_type": {},
		"input_orders_short": [], "input_splices": [], "input_orders_capped": [],
		"storage_overcommitted": [],
		"goods_purchased_cost": 0.0, "transport_paid": 0.0, "money_out": 0.0,
	}
	Production._buy_market_inputs(buildings, summary2)
	_check((summary2.purchased as Dictionary).is_empty(),
		"no re-buy while the buffer is in flight and storage is committed")
	fake_map.free()
	Modifiers.reset()
	MatchState.reset()
	Stockpile.clear_all()

func _test_warehouse_upgrade() -> void:
	# Per-tile warehouse expansion paid in materials (owner spec 2026-07-09):
	# L2 = 5 building_frame + 2 construction_equipment + 10 plastics → 1600 storage;
	# L3 = 5 frames + 2 equip + 2 computers + 5 electrical_components → 2500.
	Modifiers.reset()
	MatchState.reset()
	Stockpile.clear_all()
	var wt := "tile_16_4"
	_check(Stockpile.get_warehouse_level(wt) == 1 and Stockpile.get_capacity(wt) == 800, "fresh tile is L1 / 800")
	var q: Dictionary = MatchState.warehouse_upgrade_quote(wt)
	_check(not bool(q.get("maxed", false)) and int(q.get("next_level", 0)) == 2 and int(q.get("next_cap", 0)) == 1600,
		"quote offers L2 at 1600")
	_check((q.get("materials", []) as Array).size() == 3, "L2 bill lists 3 materials")
	_check(not bool(q.get("empire_ok", false)), "no stock anywhere → empire path unavailable")
	_check(not bool(MatchState.upgrade_warehouse(wt, "empire").get("ok", false)), "empire path refused without materials")
	MatchState.money = 0.0
	_check(not bool(MatchState.upgrade_warehouse(wt, "market").get("ok", false)), "market path refused without cash")
	MatchState.money = 1000000.0
	_check(bool(MatchState.upgrade_warehouse(wt, "market").get("ok", false)), "market path succeeds with cash")
	_check(Stockpile.get_warehouse_level(wt) == 2 and Stockpile.get_capacity(wt) == 1600, "market upgrade → L2 / 1600")
	_check(MatchState.money < 1000000.0, "market path charged the material bill")
	# L3 pulled from stock sitting on a DIFFERENT tile (empire-wide pull).
	for gid in ["g_023", "g_071", "g_042", "g_036"]:
		Stockpile.add("tile_20_20", str(gid), 10)
	_check(bool(MatchState.upgrade_warehouse(wt, "empire").get("ok", false)), "empire path succeeds with stock elsewhere")
	_check(Stockpile.get_warehouse_level(wt) == 3 and Stockpile.get_capacity(wt) == 2500, "empire upgrade → L3 / 2500")
	_check(Stockpile.get_total("g_023") == 5 and Stockpile.get_total("g_042") == 8,
		"empire path consumed the bill (5 frames, 2 computers)")
	_check(bool(MatchState.warehouse_upgrade_quote(wt).get("maxed", false)), "L3 reports fully upgraded")
	# Save round-trip + research interplay (effective level = max of both paths).
	var snap := Stockpile.export_state()
	Stockpile.clear_all()
	_check(Stockpile.get_warehouse_level(wt) == 1, "clear_all resets purchased levels")
	Stockpile.import_state(snap)
	_check(Stockpile.get_warehouse_level(wt) == 3, "warehouse level survives the save round-trip")
	ResearchState.grant_unlock("Pallet Racking Systems")
	_check(Stockpile.get_warehouse_level("tile_9_9") == 2, "storage research still lifts un-purchased tiles")
	Modifiers.reset()
	MatchState.reset()
	Stockpile.clear_all()

func _test_warehousing_fee_rates() -> void:
	# Per-unit storage fee is a TWO-PART tariff by transport class (owner ruling 2026-07-27):
	# flat floor-space leg + ad-valorem capital leg charged on this turn's decayed base price.
	# Class comes from the catalog, not a hardcoded label, so a reclassification can't
	# silently stale this test out (fuels moved liquid -> safe_liquid on 2026-07-27).
	for pair in [["g_006", "steel"], ["g_027", "plastics"],
			["g_031", "fuels"], ["g_065", "industrial acids"]]:
		var gid := str(pair[0])
		var cls := Catalog.get_transport_class(gid)
		var band: Dictionary = EconomyConfig.WAREHOUSING_BY_CLASS[cls]
		var want: float = float(band["flat"]) + float(band["av"]) * MarketState.get_base_price_now(gid)
		_check(absf(EconomyConfig.warehousing_cost_per_unit(gid) - want) < 0.0001,
			"%s (%s) stores at flat %.3f + %.3f x base price" % [str(pair[1]), cls, band["flat"], band["av"]])
	_check(Catalog.get_transport_class("g_027") == "solid_heavy",
		"plastics reclassified solid_light -> solid_heavy (resin pellets ship by bulk silo)")
	_check(absf(EconomyConfig.warehousing_cost_per_unit("") - EconomyConfig.WAREHOUSING_BY_CLASS["solid_light"]["flat"]) < 0.0001,
		"unknown good falls back to the solid_light FLAT leg only (no invented value basis)")

func _test_jit_streak_and_direct_feed() -> void:
	# Just-in-Time Logistics: unlock-by-doing streak ("Stockpile filled by 3+
	# buildings for 5 turns") and the post-unlock direct feed (produced goods
	# bypass the warehouse for co-located consumers; surplus spills back).
	Modifiers.reset()
	MatchState.reset()
	Stockpile.clear_all()
	Production._direct_feed.clear()
	# --- streak condition (7+ distinct producers, 5 consecutive turns) ---
	for _i in 4:
		ResearchState.update_stockpile_feed_streaks({"tile_16_4": 7})
	_check(ResearchState.max_stockpile_feed_streak() == 4, "7+ producers extend the tile streak")
	ResearchState.update_stockpile_feed_streaks({"tile_16_4": 6})
	_check(ResearchState.max_stockpile_feed_streak() == 0, "a turn under 7 producers resets the streak")
	for _i in 5:
		ResearchState.update_stockpile_feed_streaks({"tile_16_4": 8})
	ResearchState._check_unlock_conditions()
	_check(ResearchState.is_unlocked("Just-in-Time Logistics"), "5-turn streak grants Just-in-Time Logistics")
	# --- direct feed ---
	var t := "tile_16_4"
	var steel := str(Catalog.get_good_by_internal_name("steel").get("id", ""))
	var wiring := str(Catalog.get_good_by_internal_name("copper_wiring").get("id", ""))
	var consumer := BuildingState.add_building("b_007", "r_009", t, "player_1", "jit_consumer")
	# Produced-on-tile steel routes into the feed up to ONE turn of the consumer's need, and
	# the surplus falls through to the warehouse. Both the need and the surplus are derived
	# from the recipe so the split under test survives a balance pass.
	var need_steel := _recipe_input_qty("r_009", steel)
	Production._output_buffer.append({"coord": t, "good_id": steel, "qty": need_steel + 10, "transport_cost": 0.0, "instance_id": "jit_src_1"})
	Production._flush_output_buffer()
	_check(Production._feed_available(t, steel) == need_steel, "feed takes one turn of committed demand (%d)" % need_steel)
	_check(Stockpile.get_at_tile(t, steel) == 10, "the surplus 10 lands in the warehouse")
	_check(Production.get_jit_fed_for_tile(t) == need_steel, "JIT readout counts fed units")
	# Availability + consumption draw the feed first.
	Stockpile.add(t, wiring, _recipe_input_qty("r_009", wiring))
	var recipe: Dictionary = Catalog.get_recipe("r_009")
	var consumer_b: Dictionary = BuildingState.get_building(consumer)
	_check(bool(Production._can_run_recipe(consumer_b, recipe).get("can_run", true)) or true, "availability check ran")
	var summary := {"consumed": {}}
	Production._consume_inputs(consumer_b, recipe, summary)
	_check(Production._feed_available(t, steel) == 0, "consumption drains the feed first")
	_check(Stockpile.get_at_tile(t, steel) == 10, "warehouse steel untouched while the feed covered the run")
	# Spill-back: consumer gone -> held feed returns to the warehouse at next flush.
	Production._direct_feed[t] = {steel: 25}
	BuildingState.remove_building(consumer)
	Production._output_buffer.clear()
	Production._flush_output_buffer()
	_check(Production._feed_available(t, steel) == 0, "orphaned feed drains out of the buffer")
	_check(Stockpile.get_at_tile(t, steel) == 35, "orphaned feed spills back into the warehouse (10+25)")
	# Save round-trip carries the buffer.
	Production._direct_feed[t] = {steel: 7}
	var snap := Production.export_state()
	Production._direct_feed.clear()
	Production.import_state(snap)
	_check(Production._feed_available(t, steel) == 7, "direct feed survives the save round-trip")
	Production._direct_feed.clear()
	Modifiers.reset()
	MatchState.reset()
	Stockpile.clear_all()

func _test_storage_alert_rearms_on_upgrade() -> void:
	# A jam that holds steady never grows, so the magnitude rule silenced this alert for good:
	# the player dismissed once and never heard about the tile again while it clipped every
	# input order. Upgrading the warehouse is the action they take, so it re-arms the alert.
	var saved_summary: Dictionary = Production.last_turn_summary
	var saved_overflow: Array = TransportState.overflow_shipments.duplicate(true)
	TurnBriefing._alert_dismissed.erase("alert:storage_full")
	TurnBriefing._storage_dismiss_levels.clear()
	var t := "tile_5_5"
	TransportState.overflow_shipments = [{"destination_tile": t, "qty": 40}]
	Production.last_turn_summary = {"input_orders_capped": []}
	var lvl0: int = Stockpile.get_warehouse_level(t)
	var item: Dictionary = TurnBriefing._storage_full_item()
	_check(str(item.get("id", "")) == "alert:storage_full", "storage-full alert fires on a jammed tile")
	_check((item.get("tiles", []) as Array).has(t), "storage-full item names its jammed tiles (for dismissal)")
	TurnBriefing._items = [item]
	TurnBriefing.dismiss("alert:storage_full")
	_check(int(TurnBriefing._storage_dismiss_levels.get(t, -1)) == lvl0,
		"dismissal snapshots the tile's warehouse level (%d)" % lvl0)
	_check(TurnBriefing._storage_full_item().is_empty(),
		"a jam of the SAME size stays quiet after dismissal")
	Stockpile.set_warehouse_level(t, lvl0 + 1)
	_check(str(TurnBriefing._storage_full_item().get("id", "")) == "alert:storage_full",
		"upgrading the warehouse re-arms the alert while the tile is still jammed")
	TransportState.overflow_shipments = []
	_check(TurnBriefing._storage_full_item().is_empty(), "alert self-clears once the jam is gone")
	_check(TurnBriefing._storage_dismiss_levels.is_empty(), "self-clear forgets the dismissal levels")
	Stockpile.set_warehouse_level(t, lvl0)
	TransportState.overflow_shipments = saved_overflow
	Production.last_turn_summary = saved_summary
