extends "res://tests/test_base.gd"
## Tile info, building detail and other panels.

const FEATURE := "ui"
## Tests that also belong to other features (run under any of their tags).
const TAGS := {
	"_test_capacity_dialog_expand": ["stockpile", "ui"],
	"_test_tile_view_special_order_route": ["events", "production", "special_orders", "stockpile", "ui"],
	"_test_tile_good_breakdown": ["research", "transport", "ui"],
	"_test_tile_view_player_building_filter": ["stockpile", "ui"],
}

func _test_capacity_dialog_expand() -> void:
	# The tile-at-capacity dialog's Expand button drives the real per-tile warehouse
	# upgrade (materials from empire stock or market), and Stop Production is disabled.
	var Cap := load("res://scripts/capacity_dialog.gd")
	var dlg: Node = Cap.new()
	add_child(dlg)
	await get_tree().process_frame
	var tile := "tile_16_4"
	Stockpile.set_warehouse_level(tile, 1)
	_check(Stockpile.get_warehouse_level(tile) == 1, "capacity dialog: tile starts at warehouse L1")
	# Stock the L1->L2 bill so the works pay from empire stock (no cash path needed).
	var costs: Dictionary = EconomyConfig.WAREHOUSE_UPGRADE_COSTS[2]
	var totals_before: Dictionary = {}
	for gid in costs:
		totals_before[gid] = Stockpile.get_total(str(gid))
		Stockpile.add(tile, str(gid), int(costs[gid]))
	# Present the dialog for this tile and check button states.
	dlg._on_tile_reached_capacity(tile)
	_check(dlg._current_tile == tile, "capacity dialog: shows the full tile")
	_check(not dlg._expand_btn.disabled, "capacity dialog: Expand enabled when affordable")
	_check(dlg._stop_btn.disabled, "capacity dialog: Stop Production is disabled")
	_check(dlg._stop_btn.tooltip_text == "Coming soon", "capacity dialog: Stop Production hover says 'Coming soon'")
	# Press Expand — the warehouse upgrades and the bill is consumed from stock.
	dlg._choose(Cap.ACTION_EXPAND)
	_check(Stockpile.get_warehouse_level(tile) == 2, "capacity dialog: Expand upgrades the warehouse to L2")
	var consumed_ok := true
	for gid in costs:
		if Stockpile.get_total(str(gid)) != int(totals_before[gid]):
			consumed_ok = false
	_check(consumed_ok, "capacity dialog: Expand consumed exactly the material bill from stock")
	Stockpile.set_warehouse_level(tile, 1)  # reset shared state for later tests
	dlg.queue_free()

func _test_tile_view_special_order_route() -> void:
	var saved_turn: int = TurnManager.current_turn
	var saved_money: float = MatchState.money
	MatchState.reset()
	Stockpile.clear_all()
	EventScheduler.reset()
	SpecialOrderState.reset()
	TurnManager.current_turn = 10
	MatchState.money = 500.0

	var order: Dictionary = SpecialOrderState.create_order("coal", 10, 5, 4, 0.25)
	var order_id := str(order.get("id", ""))
	var panel: Control = load("res://scripts/tile_info_panel_v2.gd").new()
	add_child(panel)
	panel.set("_current_tile_id", "tile_3_8")
	panel.set("_active_tab", "stock")
	panel.set("_stock_sel", {"good_id": "g_001", "name": "Coal", "qty": 6})
	panel.set("_stock_qty", 6)
	var menu: Control = panel.call("_make_stock_context_menu")
	_check(_node_tree_contains_text(menu, "Special Order"),
		"tile view: matching active order shows Special Order destination")
	menu.queue_free()
	panel.set("_stock_sel", {"good_id": "g_002", "name": "Iron Ore", "qty": 6})
	var other_menu: Control = panel.call("_make_stock_context_menu")
	_check(not _node_tree_contains_text(other_menu, "Special Order"),
		"tile view: non-matching goods do not show Special Order destination")
	other_menu.queue_free()
	panel.queue_free()

	Stockpile.add("tile_3_8", "g_001", 6)
	var ships_before := TransportState.get_pending_transport_shipments().size()
	var result: Dictionary = SpecialOrderState.queue_from_tile("tile_3_8", order_id, "g_001", 6, false)
	_check(not result.is_empty()
		and bool(result.get("special_order_committed", false))
		and int(result.get("total_qty", 0)) == 4
		and Stockpile.get_at_tile("tile_3_8", "g_001") == 2,
		"tile view: special-order sale clamps to remaining demand and consumes stock")
	var tagged := false
	for shipment in TransportState.get_pending_transport_shipments():
		var s: Dictionary = shipment
		if str(s.get("special_order_id", "")) == order_id and str(s.get("special_order_source_mode", "")) == "tile_view":
			tagged = true
	_check(TransportState.get_pending_transport_shipments().size() > ships_before and tagged,
		"tile view: special-order sale queues a tagged market shipment")

	var summary := _fresh_production_summary()
	for _i in range(25):
		Production._process_transport_arrivals(summary)
		if SpecialOrderState.get_order(order_id).is_empty():
			break
	_check(SpecialOrderState.get_order(order_id).is_empty()
		and EventScheduler._active.has("special_order_fulfilled:%s" % order_id),
		"tile view: tagged shipment fulfils the special order on arrival")

	EventScheduler.reset()
	SpecialOrderState.reset()
	TurnManager.current_turn = saved_turn
	MatchState.reset()
	Stockpile.clear_all()
	MatchState.money = saved_money

## MatchState.tile_good_breakdown() — the infra building detail panel's "Breakdown"
## table: per-good qty/cost/penalty for whatever transited one tile's infra last turn.
func _test_tile_good_breakdown() -> void:
	Modifiers.reset()
	MatchState.reset()
	TransportState.pending_transport_shipments.clear()
	TransportState._last_link_flow.clear()
	TransportState._last_transit_shipments.clear()

	# --- basic pass-through: one good, one leg, no congestion -----------------------
	# "reachable"/"turns" are set here (unlike route_congestion's own tests above) because
	# this route also feeds transport_cost_for_route() directly below, which — unlike
	# route_congestion() — refuses to price an "unreachable" route and, with no explicit
	# "reachable" key, falls back to reading "turns" (absent here too) against INF_TURNS.
	var route := {"tiles": ["t0", "t1"], "legs": [{"mode": "roads", "from": "t0", "to": "t1"}],
		"reachable": true, "turns": 1}
	TransportState.pending_transport_shipments.append({
		"good_id": "g_001", "qty": 100, "turns_remaining": 2,
		"tile_distance": 1, "transport_turns": 1,
		"tiles": route.tiles, "legs": route.legs,
	})
	TransportState.update_transport_congestion()
	var rows := TransportState.tile_good_breakdown("t0", "roads")
	_check(rows.size() == 1, "one good touching t0|roads -> one breakdown row (got %d)" % rows.size())
	_check(str(rows[0].get("good_id", "")) == "g_001", "the row is g_001")
	_check(int(rows[0].get("qty", -1)) == 100, "qty is the shipment's full 100 units")
	var expect_clear_cost: float = TransportService.transport_cost_for_route("g_001", 100, route)
	_check(expect_clear_cost > 0.0, "sanity: g_001 actually has a non-zero transport rate")
	_check(absf(float(rows[0].get("cost", -1.0)) - expect_clear_cost) < 0.01,
		"cost matches a direct transport_cost_for_route quote for the same qty/route (got %.4f, want %.4f)" % [float(rows[0].get("cost", -1.0)), expect_clear_cost])
	_check(absf(float(rows[0].get("penalty", -1.0))) < 0.01, "an uncongested link charges no penalty")
	_check(TransportState.tile_good_breakdown("t0", "pipes").is_empty(), "the same tile on a different mode sees nothing")
	_check(TransportState.tile_good_breakdown("elsewhere", "roads").is_empty(), "a non-touching tile sees nothing")
	_check(TransportState.tile_good_breakdown("t1", "roads").size() == 1, "the destination tile sees it too")

	# --- congestion: penalty equals what the SAME qty/route would cost congested minus
	# what it would cost clear — proven against the pricing model directly rather than
	# re-deriving the tier/headroom formula a second time in the test. -----------------
	TransportState.pending_transport_shipments.clear()
	TransportState.pending_transport_shipments.append({
		"good_id": "g_001", "qty": 450, "turns_remaining": 2,
		"tile_distance": 1, "transport_turns": 1,
		"tiles": route.tiles, "legs": route.legs,
	})
	TransportState.update_transport_congestion()
	_check(TransportState.route_congestion_tier(route) == 1, "sanity: 450 over roads L1's 300 cap is tier 1")
	var congested_rows := TransportState.tile_good_breakdown("t0", "roads")
	_check(congested_rows.size() == 1, "still one row once congested")
	var congested_cost := float(congested_rows[0].get("cost", -1.0))
	var congested_penalty := float(congested_rows[0].get("penalty", -1.0))
	# transport_cost_for_route is pure/read-only (never spends the founder freight
	# credit — that's land_cost_after_credit's job), so clearing the flow snapshot to
	# get a clear-link quote and then restoring it has no other side effects.
	var saved_flow: Dictionary = TransportState._last_link_flow.duplicate()
	TransportState._last_link_flow.clear()
	var clear_cost: float = TransportService.transport_cost_for_route("g_001", 450, route)
	TransportState._last_link_flow = saved_flow
	_check(congested_cost > clear_cost + 0.01, "congested cost exceeds the clear-link quote")
	_check(absf(congested_penalty - (congested_cost - clear_cost)) < 0.01,
		"penalty is exactly congested cost minus the clear-link quote (got %.4f, want %.4f)" % [congested_penalty, congested_cost - clear_cost])

	# --- sale shipment: multiple goods, split per item, same route -------------------
	TransportState.pending_transport_shipments.clear()
	TransportState.pending_transport_shipments.append({
		"is_sale": true, "turns_remaining": 2,
		"tile_distance": 1, "transport_turns": 1,
		"tiles": route.tiles, "legs": route.legs,
		"sale_record": {"tile_id": "t0", "items": [
			{"good_id": "g_001", "qty": 30, "revenue": 300.0},
			{"good_id": "g_002", "qty": 20, "revenue": 400.0},
		], "total_qty": 50, "total_revenue": 700.0},
	})
	TransportState.update_transport_congestion()
	var sale_rows := TransportState.tile_good_breakdown("t0", "roads")
	_check(sale_rows.size() == 2, "a 2-good sale shipment splits into 2 breakdown rows (got %d)" % sale_rows.size())
	var by_id := {}
	for r in sale_rows:
		by_id[str(r.get("good_id", ""))] = r
	_check(int((by_id.get("g_001", {}) as Dictionary).get("qty", -1)) == 30, "g_001 keeps its own item qty, not the shipment total")
	_check(int((by_id.get("g_002", {}) as Dictionary).get("qty", -1)) == 20, "g_002 keeps its own item qty, not the shipment total")
	_check(float((by_id.get("g_001", {}) as Dictionary).get("cost", -1.0)) > 0.0, "g_001 gets its own cost")
	_check(float((by_id.get("g_002", {}) as Dictionary).get("cost", -1.0)) > 0.0, "g_002 gets its own cost")

	# --- overland fallback: transport-class gating still applies, same rule tile_mode_flow uses ---
	TransportState.pending_transport_shipments.clear()
	TransportState.pending_transport_shipments.append({
		"good_id": "g_026", "qty": 50, "source_tile": "tile_a", "destination_tile": "port_x",
		"tiles": [], "legs": [], "turns_remaining": 2, "tile_distance": 3, "transport_turns": 2,
	})  # crude oil (liquid) -> pipes only
	TransportState.update_transport_congestion()
	_check(TransportState.tile_good_breakdown("tile_a", "pipes").size() == 1, "overland crude oil shows up under pipes")
	_check(TransportState.tile_good_breakdown("tile_a", "roads").is_empty(), "but not under roads — wrong transport class")

	Modifiers.reset()
	MatchState.reset()
	TransportState.pending_transport_shipments.clear()
	TransportState._last_link_flow.clear()
	TransportState._last_transit_shipments.clear()

func _test_tile_mode_flow_endpoints() -> void:
	# Goods routing OVERLAND (no leg data) still use their source/dest tile's infra for
	# the first/last mile — counted by transport class (regression: isolated road read 0).
	TransportState.pending_transport_shipments.clear()
	TransportState.pending_transport_shipments.append({
		"good_id": "g_001", "qty": 100, "source_tile": "tile_a", "destination_tile": "port_x",
		"tiles": [], "legs": [],
	})  # coal = solid_heavy → roads
	_check(TransportState.tile_mode_flow("tile_a", "roads") == 100,
		"overland coal counts toward the SOURCE tile's roads (got %d)" % TransportState.tile_mode_flow("tile_a", "roads"))
	_check(TransportState.tile_mode_flow("port_x", "roads") == 100, "and toward the DESTINATION tile's roads")
	_check(TransportState.tile_mode_flow("tile_a", "pipes") == 0, "coal (solid) does not count toward pipes")
	_check(TransportState.tile_mode_flow("elsewhere", "roads") == 0, "a non-endpoint tile counts nothing")
	# Crude oil = liquid → pipes, not roads.
	TransportState.pending_transport_shipments = [{
		"good_id": "g_026", "qty": 50, "source_tile": "tile_a", "destination_tile": "port_x",
		"tiles": [], "legs": [],
	}]
	_check(TransportState.tile_mode_flow("tile_a", "pipes") == 50, "overland crude oil counts toward the source tile's pipes")
	_check(TransportState.tile_mode_flow("tile_a", "roads") == 0, "crude oil (liquid) does not count toward roads")
	TransportState.pending_transport_shipments.clear()

# The hex grid overlay's brass selection mirrors the tile view panel: shows
# the panel's tile, follows tile changes, clears on close.
func _test_grid_selection_follows_panel() -> void:
	var terrain := TileMapLayer.new()
	terrain.name = "TerrainLayer"
	terrain.unique_name_in_owner = false
	terrain.tile_set = load("res://assets/main_tileset.tres")
	terrain.set_script(load("res://scripts/hex_map.gd"))
	add_child(terrain)
	await get_tree().process_frame
	var overlay: Node2D = load("res://scripts/hex_grid_overlay.gd").new()
	overlay.set_process(false)
	add_child(overlay)
	overlay.terrain = terrain   # %TerrainLayer only resolves inside the scene file
	var panel: Control = load("res://scripts/tile_info_panel_v2.gd").new()
	add_child(panel)
	await get_tree().process_frame
	panel.show_tile(terrain.tiles[Vector2i(5, 7)])
	overlay._sync_selection()
	_check(overlay._selected == Vector2i(5, 7), "grid: selection follows the panel's tile")
	panel.show_tile(terrain.tiles[Vector2i(8, 9)])
	overlay._sync_selection()
	_check(overlay._selected == Vector2i(8, 9), "grid: selection follows a tile change")
	panel.visible = false
	overlay._sync_selection()
	_check(overlay._selected == Vector2i(-999, -999), "grid: selection clears when the panel closes")
	panel.queue_free()
	overlay.queue_free()
	terrain.queue_free()
	await get_tree().process_frame

func _test_tile_view_player_building_filter() -> void:
	MatchState.reset()
	Stockpile.clear_all()
	var terrain := TileMapLayer.new()
	terrain.name = "TerrainLayer"
	terrain.unique_name_in_owner = false
	terrain.tile_set = load("res://assets/main_tileset.tres")
	terrain.set_script(load("res://scripts/hex_map.gd"))
	add_child(terrain)
	await get_tree().process_frame
	var panel: Control = load("res://scripts/tile_info_panel_v2.gd").new()
	add_child(panel)
	await get_tree().process_frame
	var tile_id := "tile_5_7"
	var coord: Vector2i = terrain.id_to_coord(tile_id)
	if not terrain.tiles.has(coord):
		_check(false, "tile view filter: fixture tile exists")
		panel.queue_free()
		terrain.queue_free()
		await get_tree().process_frame
		return
	BuildingState.add_building("b_001", "r_001", tile_id, MatchState.LOCAL_PLAYER, "tv_filter_player")
	BuildingState.add_building("b_001", "r_001", tile_id, "npc", "tv_filter_npc_1")
	BuildingState.add_building("b_001", "r_001", tile_id, "npc", "tv_filter_npc_2")
	panel.show_tile(terrain.tiles[coord])
	await get_tree().process_frame
	var checkbox: CheckBox = panel.find_child("PlayerBuildingsOnlyCheckbox", true, false)
	_check(checkbox != null and not checkbox.button_pressed,
		"tile view filter: checkbox starts off")
	_check(_node_tree_contains_text(panel, "Show your buildings only"),
		"tile view filter: label is inline with the buildings header")
	_check(_node_tree_contains_text(panel, "Your Buildings")
			and _node_tree_contains_text(panel, "NPC Buildings")
			and _node_tree_contains_text(panel, "(1)") and _node_tree_contains_text(panel, "(2)")
			and _node_tree_contains_text(panel, "Owned by"),
		"tile view filter: off state splits into Your Buildings (1) + NPC Buildings (2)")
	if checkbox != null:
		checkbox.button_pressed = true
		await get_tree().process_frame
	_check(bool(panel.get("_show_player_buildings_only"))
			and _node_tree_contains_text(panel, "(1)")
			and not _node_tree_contains_text(panel, "NPC Buildings")
			and not _node_tree_contains_text(panel, "Owned by"),
		"tile view filter: on state hides the NPC Buildings section")
	var other_coord: Vector2i = terrain.id_to_coord("tile_5_8")
	if terrain.tiles.has(other_coord):
		panel.show_tile(terrain.tiles[other_coord])
		await get_tree().process_frame
		var persisted: CheckBox = panel.find_child("PlayerBuildingsOnlyCheckbox", true, false)
		_check(persisted != null and persisted.button_pressed and bool(panel.get("_show_player_buildings_only")),
			"tile view filter: choice persists when opening another tile")
	MatchState.reset()
	Stockpile.clear_all()
	panel.queue_free()
	terrain.queue_free()
	await get_tree().process_frame

## Chimney counts per industry (owner spec 2026-08-27), pinned because they are a design
## decision rather than a derived number — nothing else in the code would notice if a
## refinery quietly dropped to one stack.
func _test_smoke_stacks() -> void:
	var visuals := preload("res://scenes/building_visuals.gd")
	var spec: Dictionary = visuals.SMOKE_STACKS
	for pair in [["furnace", 1], ["petro_refinery", 3], ["chem_plant", 2],
			["power_plant", 1], ["eaf", 1]]:
		var iname := str(pair[0])
		_check(spec.has(iname), "smoke: %s carries stacks" % iname)
		if spec.has(iname):
			_check(int((spec[iname] as Dictionary)["count"]) == int(pair[1]),
				"smoke: %s has %d stack(s)" % [iname, int(pair[1])])
	# The power plant's is "one larger" and the EAF's "a small one" — relative sizes, so it
	# is the ORDER that is the spec, not the millimetres.
	var r_power := float((spec["power_plant"] as Dictionary)["r"])
	var r_furnace := float((spec["furnace"] as Dictionary)["r"])
	var r_eaf := float((spec["eaf"] as Dictionary)["r"])
	_check(r_power > r_furnace, "smoke: the power plant's stack is the largest")
	_check(r_eaf < r_furnace, "smoke: the EAF's stack is the smallest")
	# Every stack-carrying building must be STAMPED — an exempt one keeps its ink-art
	# recipe, which draws chimneys of its own, and the two would fight.
	for iname_value in spec:
		_check(not visuals.STAMP_EXEMPT.has(str(iname_value)),
			"smoke: %s is stamped, so its stacks are the only ones drawn" % str(iname_value))

	# The smoke layer must be in the scene, or nothing animates and no test would notice.
	var scene := FileAccess.open("res://scenes/main.tscn", FileAccess.READ)
	_check(scene != null, "smoke: main.tscn is readable")
	if scene != null:
		var text := scene.get_as_text()
		scene.close()
		_check(text.contains("smoke_visuals.gd"), "smoke: main.tscn mounts the smoke layer")


## A building with more than one chimney gets them ADJACENT, IN A LINE (owner, 2026-08-27).
## Three flues scattered round a footprint read as three separate works; a row reads as one
## plant. This pins the row -- collinear, evenly spaced, and every stack still on the roof.
func _test_stacks_sit_in_a_line() -> void:
	var bv := preload("res://scenes/building_visuals.gd").new()
	var rect := PackedVector2Array([Vector2(0, 0), Vector2(120, 0),
		Vector2(120, 60), Vector2(0, 60)])
	var stacks: Array = bv._stack_points("petro_refinery", "inst_1", rect)
	_check(stacks.size() == 3, "stacks: a refinery has three (%d)" % stacks.size())
	if stacks.size() == 3:
		var a: Vector2 = stacks[0]["pos"]
		var b: Vector2 = stacks[1]["pos"]
		var c: Vector2 = stacks[2]["pos"]
		# Collinear: the cross product of the two gaps is zero for a straight row.
		var cross: float = absf((b - a).cross(c - b))
		_check(cross < 0.5, "stacks: the three are collinear (cross %.3f)" % cross)
		# Adjacent: equal gaps, each no wider than a couple of stack diameters.
		var g1 := a.distance_to(b)
		var g2 := b.distance_to(c)
		var r: float = float(stacks[0]["r"])
		_check(absf(g1 - g2) < 0.01, "stacks: evenly spaced (%.2f vs %.2f)" % [g1, g2])
		_check(g1 > r and g1 <= r * 2.5,
			"stacks: adjacent, about a diameter apart (%.2f for r %.2f)" % [g1, r])
		# On the roof, not straddling the outline.
		var outside := 0
		for stack_value in stacks:
			if not Geometry2D.is_point_in_polygon(stack_value["pos"] as Vector2, rect):
				outside += 1
		_check(outside == 0, "stacks: all inside the footprint (%d outside)" % outside)
	# A single-stack building is unaffected by the row logic.
	var one: Array = bv._stack_points("furnace", "inst_2", rect)
	_check(one.size() == 1, "stacks: a furnace still has exactly one (%d)" % one.size())
	bv.free()


## Grey smoke vs white steam (owner, 2026-08-27). The split must agree with what production
## actually levies — `co2_tax_multiplier` on an input good — rather than being a second,
## drifting opinion about which industries are dirty.
func _test_smoke_carbon_split() -> void:
	var bv := preload("res://scenes/building_visuals.gd").new()

	# Find a real dirty recipe and a real clean one, so this tests the CSV as shipped.
	var dirty_recipe := ""
	var clean_recipe := ""
	for recipe_value in Catalog.all_recipes():
		var recipe: Dictionary = recipe_value
		var inputs: Array = recipe.get("inputs", [])
		if inputs.is_empty():
			continue
		var burns := false
		for input_value in inputs:
			var gid := str((input_value as Dictionary).get("good_id", ""))
			if gid != "" and float(Catalog.get_good(gid).get("co2_tax_multiplier", 0.0)) > 0.0:
				burns = true
		# `recipe_id`, NOT `id` — the recipe dict uses the former and a wrong key here just
		# silently finds nothing.
		if burns and dirty_recipe == "":
			dirty_recipe = str(recipe.get("recipe_id", ""))
		elif not burns and clean_recipe == "":
			clean_recipe = str(recipe.get("recipe_id", ""))
	_check(dirty_recipe != "", "smoke: the catalog has a carbon-burning recipe")
	_check(clean_recipe != "", "smoke: the catalog has a carbon-free recipe")

	# An unknown instance must never be reported as emitting — the plume cannot invent
	# emissions for something that is not a building.
	_check(not bv._recipe_emits_carbon("no_such_instance"),
		"smoke: an unknown building emits no carbon")

	if dirty_recipe != "" and clean_recipe != "":
		var d_id := BuildingState.add_building("b_002", dirty_recipe, "tile_9_10", "npc",
			"smoke_dirty", false)
		var c_id := BuildingState.add_building("b_002", clean_recipe, "tile_9_10", "npc",
			"smoke_clean", false)
		_check(bv._recipe_emits_carbon(str(d_id)),
			"smoke: a fossil-burning recipe smokes grey (%s)" % dirty_recipe)
		_check(not bv._recipe_emits_carbon(str(c_id)),
			"smoke: a carbon-free recipe steams white (%s)" % clean_recipe)
		BuildingState.buildings.erase(str(d_id))
		BuildingState.buildings.erase(str(c_id))
	bv.free()


func _test_detail_panel_owner_resolution() -> void:
	# Regression: a player building handed a stale/cross-wired owner on the passed dict must
	# still resolve to the player (re-read from the live store), so it never renders in the
	# NPC frosted/blurred mode. A co-located NPC building of the same type must still resolve
	# to the NPC. (Mirrors tools/repro_npc_blur.gd, headless.)
	var npc_iid: String = BuildingState.add_building("b_002", "r_003", "tile_5_10", "Stoneshore Ironworks")
	var player_iid: String = BuildingState.add_building("b_002", "r_003", "tile_5_10", MatchState.LOCAL_PLAYER)
	# The resolver lives in BuildingReadout.owner_info now -- it re-reads the live store, which
	# is the whole point of the guard -- and both the detail panel and everything else that
	# needs an owner goes through it. Testing it there rather than through a panel's private
	# copy is what let the v1 panel be deleted without losing the regression.
	var readout := preload("res://scripts/building_readout.gd")
	_check(str(readout.owner_info(BuildingState.get_building(player_iid)).owner_id) == MatchState.LOCAL_PLAYER,
		"detail owner: canonical player dict -> player")
	var poisoned: Dictionary = BuildingState.get_building(player_iid).duplicate()
	poisoned["owner"] = "Stoneshore Ironworks"
	_check(str(readout.owner_info(poisoned).owner_id) == MatchState.LOCAL_PLAYER,
		"detail owner: stale-owner player dict re-resolves to player (no NPC frost)")
	_check(not bool(readout.owner_info(poisoned).is_npc),
		"detail owner: a re-resolved player building is not drawn as an NPC")
	_check(str(readout.owner_info(BuildingState.get_building(npc_iid)).owner_id) == "Stoneshore Ironworks"
			and bool(readout.owner_info(BuildingState.get_building(npc_iid)).is_npc),
		"detail owner: NPC building -> NPC owner (frost preserved)")
	_check(str(readout.owner_info({"instance_id": "stub_x", "building_id": "b_002"}).owner_id) == MatchState.LOCAL_PLAYER,
		"detail owner: construction stub (not in store, no owner) -> player")
	BuildingState.buildings.erase(npc_iid)
	BuildingState.buildings.erase(player_iid)
