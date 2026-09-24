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
		"good_id": "g_001", "qty": 100, "turns_remaining": 1,
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
		"good_id": "g_001", "qty": 450, "turns_remaining": 1,
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
		"is_sale": true, "turns_remaining": 1,
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


# The dummy Gameplay "Test setting": a seven-position rotary knob (scripts/rotary_selector.gd)
# that is staged in the panel and only committed on Apply, like every other settings tab.
func _test_settings_test_knob() -> void:
	var RotarySelector = load("res://scripts/rotary_selector.gd")
	var knob: Control = RotarySelector.new()
	add_child(knob)
	knob.value = 9
	_check(knob.value == 7, "test knob: values above 7 clamp to 7")
	knob.value = 0
	_check(knob.value == 1, "test knob: values below 1 clamp to 1")
	var c: Vector2 = knob._centre()
	_check(knob._position_towards(c + Vector2(-50, 0)) == 1, "test knob: pointing at 9 o'clock is position 1")
	_check(knob._position_towards(c + Vector2(0, -50)) == 4, "test knob: pointing at 12 o'clock is position 4")
	_check(knob._position_towards(c + Vector2(50, 0)) == 7, "test knob: pointing at 3 o'clock is position 7")
	_check(knob._position_towards(c + Vector2(-50, 40)) == 1, "test knob: below the knob on the left snaps to 1")
	_check(knob._label_at(knob._label_position(5)) == 5, "test knob: clicking a number hits that number")
	knob.queue_free()

	# Apply also commits the other tabs through PlayerProfile, which persists to disk, so
	# snapshot everything it writes and put it back afterwards.
	var saved: int = SettingsPanel.test_setting
	var fs_saved: bool = PlayerProfile.fullscreen
	var ws_saved: Vector2i = PlayerProfile.window_size
	var sc_saved: int = PlayerProfile.screen_index
	var al_saved: Dictionary = PlayerProfile.audio_levels.duplicate()
	var kb_saved: Dictionary = PlayerProfile.keybinds.duplicate()
	SettingsPanel.test_setting = 2
	var panel := SettingsPanel.open(self)
	_check(panel._test_knob.value == 2, "test setting: the knob opens on the current value")
	panel._test_knob.value = 6
	panel._on_back_pressed()
	_check(SettingsPanel.test_setting == 2, "test setting: Back discards the knob change")
	panel = SettingsPanel.open(self)
	panel._test_knob.value = 6
	panel._on_apply_pressed()
	_check(SettingsPanel.test_setting == 6, "test setting: Apply commits the knob position")
	SettingsPanel.test_setting = saved
	PlayerProfile.keybinds = kb_saved
	PlayerProfile.set_audio_levels(al_saved)
	PlayerProfile.window_size = ws_saved
	PlayerProfile.set_display(fs_saved, ws_saved, sc_saved)


# Panel gauge (scripts/panel_gauge.gd): for a spread of zone splits and needle positions,
# the LED shows the right colour, the needle points at the right angle and each zone band
# covers exactly its share of the scale.
const GAUGE_CASES := [
	# value, green %, amber %, LED mode, flash -> zone, LED, flashes
	[0.30, 37.5, 29.2, "AUTO", false, "green", "green", false],
	[0.375, 37.5, 29.2, "AUTO", false, "green", "green", false],   # boundary belongs to the lower zone
	[0.50, 37.5, 29.2, "AUTO", false, "amber", "amber", false],
	[0.90, 37.5, 29.2, "AUTO", false, "red", "red", true],         # auto flashes in the red
	[0.10, 0.0, 30.0, "AUTO", false, "amber", "amber", false],     # empty green is skipped
	[0.00, 0.0, 0.0, "AUTO", false, "red", "red", true],           # all red
	[0.99, 100.0, 0.0, "AUTO", false, "green", "green", false],    # all green
	[0.95, 60.0, 60.0, "AUTO", false, "amber", "amber", false],    # amber clamped to the 40% left
	[0.20, 50.0, 25.0, "RED", false, "green", "red", false],       # fixed colour ignores the zone
	[0.80, 50.0, 25.0, "AMBER", true, "red", "amber", true],       # fixed colour, flashing on request
	[0.80, 50.0, 25.0, "OFF", true, "red", "off", false],          # off never flashes
]


func _test_panel_gauge_rules() -> void:
	var Gauge = load("res://scripts/panel_gauge.gd")
	for c: Array in GAUGE_CASES:
		var tag := "gauge v=%s g=%s a=%s %s" % [c[0], c[1], c[2], c[3]]
		var mode: int = Gauge.LedMode[c[3]]
		_check(Gauge.zone_at(c[0], c[1], c[2]) == c[5], tag + ": needle is in the " + str(c[5]) + " zone")
		_check(Gauge.led_colour(mode, c[0], c[1], c[2]) == c[6], tag + ": LED is " + str(c[6]))
		_check(Gauge.led_flashes(mode, c[4], c[0], c[1], c[2]) == c[7], tag + ": LED flashing is " + str(c[7]))
	var b: Dictionary = Gauge.zone_bounds(60.0, 60.0)
	_check(b.amber == Vector2(0.6, 1.0) and b.red.x == b.red.y, "gauge: amber clamps to what green leaves and red is empty")
	for pair: Array in [[0.0, -150.0], [0.25, -75.0], [0.5, 0.0], [1.0, 150.0], [1.4, 150.0]]:
		_check(is_equal_approx(rad_to_deg(Gauge.needle_rotation(pair[0])), pair[1]),
			"gauge: value %s turns the needle %s° from 12 o'clock" % pair)


func _test_panel_gauge_draws_cases() -> void:
	var Gauge = load("res://scripts/panel_gauge.gd")
	var gauge: Control = Gauge.new()
	gauge.animate_needle = false
	add_child(gauge)
	await get_tree().process_frame
	for c: Array in GAUGE_CASES:
		var tag := "gauge v=%s g=%s a=%s %s" % [c[0], c[1], c[2], c[3]]
		gauge.green_percent = c[1]
		gauge.amber_percent = c[2]
		gauge.led_mode = Gauge.LedMode[c[3]]
		gauge.flash = c[4]
		gauge.value = c[0]
		gauge._time = 0.0          # the lit phase of a blink
		gauge._refresh()
		var expected: float = Gauge.needle_rotation(c[0])
		_check(is_equal_approx(gauge._layers["needle"].rotation, expected)
			and is_equal_approx(gauge._layers["needle_shadow"].rotation, expected),
			tag + ": needle and its shadow drawn at the value's angle")
		_check(gauge.shown_led() == c[6], tag + ": LED drawn " + str(c[6]))
		_check(gauge._layers["led_glow"].visible == (c[6] != "off") and gauge._layers["led_core"].visible == (c[6] != "off"),
			tag + ": LED glow and lit disc only while lit")
		if c[6] != "off":
			var core_colour: Color = gauge._core_texture.gradient.colors[2]
			_check(core_colour.is_equal_approx(Gauge.LED_COLOURS[c[6]]), tag + ": lit disc is " + str(c[6]))
		var bounds: Dictionary = Gauge.zone_bounds(c[1], c[2])
		var bands_ok := true
		for zone: String in Gauge.ZONES:
			var mat: ShaderMaterial = gauge._zone_materials[zone]
			var want: Vector2 = bounds[zone]
			bands_ok = bands_ok and is_equal_approx(mat.get_shader_parameter("from_v"), want.x) \
				and is_equal_approx(mat.get_shader_parameter("to_v"), want.y) \
				and gauge._layers["band_" + zone].visible == (want.y > want.x)
		_check(bands_ok, tag + ": each zone band covers its share and empty zones are hidden")
		if c[7]:
			gauge._time = 0.5         # the dark phase of a blink
			gauge._refresh()
			_check(gauge.shown_led() == "off", tag + ": flashing LED goes dark between blinks")
	gauge.queue_free()


func _test_settings_test_gauge() -> void:
	var panel := SettingsPanel.open(self)
	await get_tree().process_frame
	var gauge: Control = panel._test_gauge
	_check(gauge != null and gauge.is_inside_tree(), "settings: Gameplay tab carries the test gauge")
	# Drive the preview's own controls: rows are Needle, Green, Amber, Red, LED.
	var controls: VBoxContainer = gauge.get_parent().get_child(2)
	var slider := func(row: int) -> HSlider: return controls.get_child(row).get_child(1) as HSlider
	var red_readout: Label = controls.get_child(3).get_child(1)
	slider.call(0).value = 90.0
	_check(is_equal_approx(gauge.value, 0.9), "test gauge: the Needle slider moves the needle")
	slider.call(1).value = 80.0
	_check(is_equal_approx(gauge.green_percent, 80.0) and is_equal_approx(gauge.amber_percent, 20.0) \
		and is_equal_approx(slider.call(2).value, 20.0) and red_readout.text == "0%",
		"test gauge: raising green pulls amber back so the three still add to 100")
	slider.call(2).value = 5.0
	_check(red_readout.text == "15%", "test gauge: red shows what green and amber leave")
	var led_option: OptionButton = controls.get_child(4).get_child(1)
	led_option.item_selected.emit(3)
	_check(gauge.led_mode == gauge.LedMode.RED, "test gauge: the LED menu sets the LED mode")
	panel._on_back_pressed()


# Building Detail v3 (`toggle bdp v3`): the approved control plates. The rules behind the keys'
# text, when the upgrade arrow lights, the cheat, and that the panel swaps its controls and the
# keys open the same sheets as v2.
func _test_bdp_v3_rules() -> void:
	var Block = load("res://scripts/bdp_v3_block.gd")
	var Panel = load("res://scripts/building_detail_panel_v2.gd")
	_check(Block.truncate10("Motor") == "Motor" and Block.truncate10("Heavy Vehicle") == "Heavy Vehi..."
		and Block.truncate10("Aluminium1") == "Aluminium1",
		"bdp v3: good names cut to ten characters plus ... from eleven on")
	_check(Block.upgrade_detail(1) == "+100% Output" and Block.upgrade_detail(2) == "+75% Output",
		"bdp v3: upgrade line is the next level's output gain (L1->2 +100%, L2->3 +75%)")
	var one: Array = Block.value_lines("Market / unlinked")
	var two: Array = Block.value_lines("Tile stockpile (same tile)")
	var split: Array = Block.value_lines("Stoneshore: 20\nArin: 13\nCapital: 0")
	_check(one.size() == 1 and two.size() == 2 and str(two[1].text) == "(same tile)"
		and split.size() == 2 and str(split[1].text).ends_with("…"),
		"bdp v3: value key splits a bracketed qualifier onto a second line and shortens longer splits")

	var iid: String = BuildingState.add_building("b_007", "r_009", "tile_5_10", MatchState.LOCAL_PLAYER, "v3_rules")
	var b: Dictionary = BuildingState.get_building(iid)
	var internal := str(Catalog.get_building("b_007").get("internal_name", ""))
	var gate: String = preload("res://scripts/building_levels.gd").research_gate(internal, 2)
	_check(gate != "", "bdp v3: the factory's level-2 upgrade has a research gate to test (%s)" % gate)
	var had := ResearchState.unlocked_titles.has(gate)
	if gate != "":
		ResearchState.unlocked_titles.erase(gate)
		var locked: Dictionary = Panel.v3_upgrade_state(b)
		_check(not bool(locked.upgrade_lit) and str(locked.upgrade_tooltip).contains(gate),
			"bdp v3: upgrade arrow unlit, with the missing research in the tooltip, until %s is unlocked" % gate)
		ResearchState.unlocked_titles[gate] = true
	var open: Dictionary = Panel.v3_upgrade_state(b)
	_check(bool(open.upgrade_lit) and str(open.upgrade_title) == "Upgrade to Lv 2" and str(open.upgrade_detail) == "+100% Output",
		"bdp v3: upgrade arrow lit once the research is met")
	var maxed := b.duplicate()
	maxed["level"] = preload("res://scripts/building_levels.gd").MAX_LEVEL
	_check(not bool(Panel.v3_upgrade_state(maxed).upgrade_lit), "bdp v3: no lit arrow at the maximum level")
	if gate != "" and not had:
		ResearchState.unlocked_titles.erase(gate)
	var better: int = Block.better_recipe_count(b)
	_check(better >= 0 and better < Catalog.get_recipes_for_building("b_007").size(),
		"bdp v3: better-recipe count is among the other recipes (%d)" % better)
	BuildingState.buildings.erase(iid)

	var Lamp = load("res://scripts/bdp_v3_lamp.gd")
	_check(Lamp.colour_for("ok") == "green" and Lamp.colour_for("warn") == "amber" and Lamp.colour_for("bad") == "red"
		and Lamp.colour_for("info") == "off" and Lamp.colour_for("") == "off",
		"bdp v3: the status lamp is green for ok, amber for warn, red for bad and off otherwise")
	var Scroll = load("res://scripts/bdp_v3_scroll.gd")
	var thumb: StyleBox = Scroll.make(Scroll.THUMB, Scroll.THUMB_CAP, Scroll.THUMB_PERIOD, Scroll.THUMB_REPEAT_FROM)
	var sum := func(parts: Array) -> float:
		var total := 0.0
		for p: Array in parts:
			total += float(p[2])
		return total
	var tall: Array = thumb.slices(203.0)
	var period_px: float = Scroll.THUMB_PERIOD / 1.875
	var whole := true
	for i in range(1, tall.size() - 1):
		var periods: float = (float(tall[i][1]) - float(tall[i][0])) / (Scroll.THUMB_PERIOD * 2.0 / 1.875)
		whole = whole and is_equal_approx(periods, roundf(periods))
	var fill: float = sum.call(tall) - 2.0 * Scroll.THUMB_CAP / 1.875
	_check(is_equal_approx(sum.call(tall), 203.0) and whole and absf(fill / (roundf(fill / period_px) * period_px) - 1.0) < 0.05
		and is_equal_approx(float(tall[0][2]), Scroll.THUMB_CAP / 1.875),
		"bdp v3: a long slider keeps its ends and fills its length with whole periods of ridges")
	var tiny: Array = thumb.slices(10.0)
	_check(is_equal_approx(float(tiny[0][2]), 5.0) and is_equal_approx(sum.call(tiny), 10.0), "bdp v3: a very short slider halves its ends")
	var Counter = load("res://scripts/bdp_v3_counter.gd")
	_check(Counter.digits_for(54.17, 4, 2) == PackedInt32Array([5, 4, 1, 7]) and Counter.digits_for(10052, 5, 0) == PackedInt32Array([1, 0, 0, 5, 2])
		and Counter.digits_for(7.5, 4, 2) == PackedInt32Array([0, 7, 5, 0]) and Counter.digits_for(123456, 3, 0) == PackedInt32Array([9, 9, 9]),
		"bdp v3: a drum counter reads its value on its drums, leading zeros and all, and nines when it overflows")
	_check(Counter.drums_for(54.17, 2, 4) == 4 and Counter.drums_for(1234.5, 2, 4) == 6 and Counter.drums_for(10052, 0, 3) == 5,
		"bdp v3: a counter has as many drums as its value needs, and at least its minimum")
	var Led = load("res://scripts/bdp_v3_led.gd")
	_check(Led.cells_for("7.95") == [["7", true], ["9", false], ["5", false]] and Led.cells_for("123.40").size() == 5
		and Led.cells_for("--.--") == [["-", false], ["-", true], ["-", false], ["-", false]],
		"bdp v3: an LED figure takes a cell per digit, its point lit on the digit before it")
	var Econ = load("res://scripts/building_economics.gd")
	_check(Econ.transport_tone(1.0, 100.0) == "ok" and Econ.transport_tone(5.0, 100.0) == "warn" and Econ.transport_tone(9.0, 100.0) == "bad"
		and Econ.transport_tone(1.0, 0.0) == "bad" and Econ.transport_tone(0.0, 0.0) == "ok",
		"bdp v3: a transport lamp is green under 3% of its goods' value, amber under 8%, red above")
	var Bar = load("res://scripts/bdp_v3_value_bar.gd")
	var steel_id := str(Catalog.get_good_by_internal_name("steel").get("id", ""))
	var gain: Array = Bar.rows_for({"outputs": [{"good_id": steel_id, "value": 100.0}], "sold": false, "input_value": 50.0, "labour": 20.0, "upkeep": 10.0, "transport": 5.0})
	var loss: Array = Bar.rows_for({"outputs": [{"good_id": steel_id, "value": 100.0}], "sold": true, "input_value": 80.0, "labour": 20.0, "upkeep": 10.0, "transport": 10.0})
	_check(gain[0].label == "Revenue if sold" and is_equal_approx(float(gain[0].slices[-1].to), 1.0) and is_equal_approx(float(gain[1].slices[-1].to), 0.85)
		and gain[1].slices.size() == 4 and loss[0].label == "Revenue" and is_equal_approx(float(loss[0].slices[-1].to), 100.0 / 120.0)
		and is_equal_approx(float(loss[1].slices[-1].to), 1.0),
		"bdp v3: revenue and costs are two bars on one scale, the larger of the two filling it")
	var econ_iids: Array = []
	for pair in [["b_028", "r_225"], ["b_001", "r_001"], ["b_003", "r_004"], ["b_007", "r_009"]]:
		econ_iids.append(BuildingState.add_building(pair[0], pair[1], "tile_5_10", MatchState.LOCAL_PLAYER, "v3_econ_" + pair[1]))
	var battery: Dictionary = Econ.per_turn(BuildingState.get_building(econ_iids[0]))
	var mine: Dictionary = Econ.per_turn(BuildingState.get_building(econ_iids[1]))
	var plant_b: Dictionary = BuildingState.get_building(econ_iids[2])
	var plant: Dictionary = Econ.per_turn(plant_b)
	var motor_b: Dictionary = BuildingState.get_building(econ_iids[3])
	for o: Dictionary in Catalog.get_recipe("r_009").get("outputs", []):
		MatchState.route_output_to_market(econ_iids[3], str(o.get("good_id", "")))
	var motor: Dictionary = Econ.per_turn(motor_b)
	_check(not bool(battery.shown), "bdp v3: a building with neither inputs nor outputs (a battery) has no economics to show")
	_check(bool(mine.shown) and bool(mine.inputs_free) and mine.lamp_in == "off" and not bool(mine.output_free_to_ship),
		"bdp v3: a mine's inputs come free, and its output still pays to reach the market")
	_check(bool(plant.output_free_to_ship) and plant.lamp_out == "off" and not bool(plant.inputs_free)
		and is_equal_approx(float(plant.output_value), float(Production._effective_power_output(plant_b, Catalog.get_recipe("r_004"))) * Power.grid_export_price()),
		"bdp v3: a power plant's output is free to ship, valued at what the grid pays (£%.2f)" % float(plant.output_value))
	var port_charged := false
	for m: Dictionary in motor.methods_out:
		port_charged = port_charged or m.name == "Port"
	_check(bool(motor.sold) and float(motor.transport_out) > 0.0 and port_charged
		and is_equal_approx(float(motor.net_value_added), float(motor.value_added) - float(motor.transport))
		and is_equal_approx(float(motor.value_added), float(motor.output_value) - float(motor.input_value) - float(motor.labour) - float(motor.upkeep)),
		"bdp v3: a factory selling to market pays the port on its output, and its net value added is value added less transport (£%.2f)" % float(motor.net_value_added))
	var chlor_iid: String = BuildingState.add_building(str(Catalog.get_recipe("r_012").get("building_id", "")), "r_012", "tile_5_10", MatchState.LOCAL_PLAYER, "v3_econ_r_012")
	econ_iids.append(chlor_iid)
	var chlor: Dictionary = Econ.per_turn(BuildingState.get_building(chlor_iid))
	var chlor_rows: Array = Bar.rows_for(chlor)
	_check(chlor_rows[0].slices.size() == (Catalog.get_recipe("r_012").get("outputs", []) as Array).size(),
		"bdp v3: the revenue bar has a slice for each good sold (%d for chlor-alkali)" % chlor_rows[0].slices.size())
	for e_iid in econ_iids:
		BuildingState.buildings.erase(e_iid)
	var Panel2 = load("res://scripts/building_detail_panel_v2.gd")
	var cheap: Dictionary = Panel2.v3_cost_gauge_reading(8.0, 10.0)
	var dear: Dictionary = Panel2.v3_cost_gauge_reading(30.0, 10.0)
	var unknown: Dictionary = Panel2.v3_cost_gauge_reading(-1.0, 10.0)
	_check(is_equal_approx(float(cheap.value), 0.4) and bool(cheap.known) and is_equal_approx(float(dear.value), 1.0) and not bool(unknown.known),
		"bdp v3: the cost gauge reads unit cost as a share of twice the market price, and knows when the cost is unknown")
	_check(Panel2.v3_stock_tone(40, 32, 0, false) == "ok" and Panel2.v3_stock_tone(32, 32, 0, false) == "ok"
		and Panel2.v3_stock_tone(10, 32, 20, false) == "warn" and Panel2.v3_stock_tone(10, 32, 0, true) == "warn"
		and Panel2.v3_stock_tone(10, 32, 0, false) == "bad",
		"bdp v3: a shipment's lamp is green with enough to run, amber when short with something coming, red when short with nothing")
	var Section = load("res://scripts/bdp_v3_section.gd")
	var screws: PackedVector2Array = Section.screw_points(Vector2(400, 300))
	var on_top := 0
	var on_bottom := 0
	var on_left := 0
	var on_right := 0
	for sp in screws:
		on_top += int(is_equal_approx(sp.y, Section.SCREW_INSET))
		on_bottom += int(is_equal_approx(sp.y, 300.0 - Section.SCREW_INSET))
		on_left += int(is_equal_approx(sp.x, Section.SCREW_INSET))
		on_right += int(is_equal_approx(sp.x, 400.0 - Section.SCREW_INSET))
	_check(on_top == 4 and on_bottom == 4 and on_left == 6 and on_right == 6 and screws.size() == 16,
		"bdp v3: the plastic plate has four screws along its top and bottom and six down each side (%d)" % screws.size())
	var Door = load("res://scripts/bdp_v3_door.gd")
	var door_rows: Array = Door.rows(90.0)
	var door_h := 0.0
	for dr: Array in door_rows:
		door_h += float(dr[2])
	_check(is_equal_approx(door_h, 90.0) and door_rows.size() >= 3, "bdp v3: the rolling door fills its height with whole slats between its housing and bar")
	_check(Panel2.v3_door_rows(1) == 2 and Panel2.v3_door_rows(2) == 2 and Panel2.v3_door_rows(3) == 1 and Panel2.v3_door_rows(4) == 1
		and Panel2.v3_door_rows(5) == 0 and Panel2.v3_door_rows(6) == 0 and Panel2.v3_door_rows(8) == 0,
		"bdp v3: the shipments' door covers the bay's two empty rows for 1-2 goods, one for 3-4, none for 5-6")
	var Light = load("res://scripts/bdp_v3_light.gd")
	var screen := Vector2(1920, 1080)
	_check(Light.light_at(Vector2(0.05, 0.05), screen) > Light.light_at(Vector2(0.75, 0.15), screen)
		and Light.light_at(Vector2(0.75, 0.15), screen) > Light.light_at(Vector2(0.95, 0.9), screen)
		and is_equal_approx(Light.light_at(Vector2(1.0, 1.0), screen), Light.DARKEST),
		"bdp v3: the lamp over the panel is brightest at the screen's top-left and darkest at its far corner")
	var Seam = load("res://scripts/bdp_v3_seam.gd")
	var seam_parts: Array = Seam.slices(430.0)
	_check(seam_parts.size() == 3 and is_equal_approx(float(seam_parts[0][3]), Seam.CAP / 1.875)
		and is_equal_approx(float(seam_parts[2][3]), 430.0) and is_equal_approx(float(seam_parts[1][1]), Seam.EDGE.get_width() - float(seam_parts[1][0])),
		"bdp v3: the seam edge keeps its screwed ends and fits its length between them")
	var Title = load("res://scripts/bdp_v3_title.gd")
	var missing: Array = []
	for bd: Dictionary in Catalog.all_buildings():
		if not Title.can_show(str(bd.get("display_name", "")) + " — "):
			missing.append(str(bd.get("display_name", "")))
	for rd: Dictionary in Catalog.all_recipes():
		if not Title.can_show(str(rd.get("display_name", ""))):
			missing.append(str(rd.get("display_name", "")))
	_check(missing.is_empty(), "bdp v3: the raised title has a letter for every building and recipe name (missing in: %s)" % ", ".join(missing))
	_check(not Title.can_show("Café"), "bdp v3: a title with a letter the atlas lacks is left to the plain label")
	var rail: StyleBox = Scroll.make(Scroll.RAIL, Scroll.RAIL_CAP)
	_check(rail.slices(400.0).size() == 3 and rail.get_minimum_size() == Vector2(16, 32),
		"bdp v3: the rail is 16 px wide and keeps its ends (%s)" % str(rail.get_minimum_size()))


func _test_bdp_v3_panel() -> void:
	var was: bool = UiPrefs.use_bdp_v3
	UiPrefs.set_use_bdp_v3(false)
	var terminal: Node = load("res://scripts/debug_terminal.gd").new()
	add_child(terminal)
	await get_tree().process_frame
	terminal._cheats_unlocked = true
	var reply: String = terminal._run_command("toggle bdp v3")
	_check(UiPrefs.use_bdp_v3 and reply.contains("v3"), "bdp v3: `toggle bdp v3` switches the panel to v3 (%s)" % reply)
	terminal.queue_free()

	var iid: String = BuildingState.add_building("b_007", "r_009", "tile_5_10", MatchState.LOCAL_PLAYER, "v3_panel")
	var b: Dictionary = BuildingState.get_building(iid)
	# A cost-to-produce reading, as the cost solver would leave it, so the cost section is built.
	var saved_cost: Dictionary = CostSolver.last_result
	var motor := str(Catalog.get_good_by_internal_name("motor").get("id", ""))
	CostSolver.last_result = {"per_building": {iid: {"output_good_id": motor, "unit_cost": Catalog.get_base_price(motor) * 0.72,
		"output_costs": {motor: Catalog.get_base_price(motor) * 0.72}}}, "per_good": {}}
	var panel = load("res://scripts/building_detail_panel_v2.gd").new()
	add_child(panel)
	await get_tree().process_frame
	panel.show_building(b)
	await get_tree().process_frame
	var block: Control = panel.find_child("BdpV3Block", true, false)
	var footer: Control = panel.find_child("BdpV3Footer", true, false)
	_check(block != null and footer != null and panel.find_child("UpgradeButton", true, false) == null,
		"bdp v3: the control block and footer replace the v2 route cards and buttons")
	_check(panel._close_key.visible and not panel._close_button.visible, "bdp v3: the close keycap replaces the X button")
	_check(is_equal_approx(panel._close_key.size.x, panel._close_key.size.y), "bdp v3: the close key stays square (%s)" % str(panel._close_key.size))
	_check(panel._backing.visible and not panel._pipe_frame.visible, "bdp v3: the backing plate replaces the pipe border")
	var st: Dictionary = load("res://scripts/building_readout.gd").status(b, Catalog.get_recipe("r_009"), false)
	var Lamp = load("res://scripts/bdp_v3_lamp.gd")
	_check(panel._status_v3.visible and not panel._badge.visible and panel._status_v3_label.text == str(st.label)
		and panel._status_lamp.colour == Lamp.colour_for(str(st.tone)),
		"bdp v3: a lamp lit for the status replaces the badge (%s, %s)" % [str(st.label), panel._status_lamp.colour])
	var Scroll = load("res://scripts/bdp_v3_scroll.gd")
	var bar: VScrollBar = panel._scroll.get_v_scroll_bar()
	_check(Scroll.is_applied(panel._scroll) and is_equal_approx(bar.get_combined_minimum_size().x, 16.0),
		"bdp v3: the scrollbar is the steel rail with its slider, 16 px wide (%s)" % str(bar.get_combined_minimum_size()))
	_check(panel._title_v3.visible and not panel._title_label.visible and panel._title_v3.text == panel._title_label.text.to_upper()
		and panel._title_v3.letter_count() == panel._title_label.text.replace(" ", "").length(),
		"bdp v3: the title is set in raised letters, one per character (%d)" % panel._title_v3.letter_count())
	var strip: Control = panel.find_child("BuildingRecipeStrip", true, false)
	var enamel: Control = strip.find_child("BdpV3Enamel", false, false) if strip != null else null
	await get_tree().process_frame
	await get_tree().process_frame
	_check(enamel != null and enamel.hole_rects().size() == 4,
		"bdp v3: the recipe diagram sits on an enamel sign, its grunge kept clear of the 3 icons and the arrow (%d)" % (enamel.hole_rects().size() if enamel != null else -1))
	var arrow: Control = strip.find_child("RecipeArrow", true, false) if strip != null else null
	if arrow != null:
		var body: PanelContainer = arrow.get_node("ArrowBody")
		var head: Control = arrow.get_node("ArrowHead")
		var bst: StyleBoxFlat = body.get_theme_stylebox("panel")
		var content_w: float = body.get_child(0).get_combined_minimum_size().x
		var old_w := 20.0 + content_w
		var new_w := bst.content_margin_left + bst.content_margin_right + content_w
		_check(head.size == Vector2(35, 58) and is_equal_approx(body.size.y, 41.0) and absf(new_w / old_w - 0.9) < 0.02
			and bst.corner_radius_top_left == 0 and bst.corner_radius_bottom_left == 0,
			"bdp v3: the recipe arrow's head is 25%% larger (35 x 58) and its square body 10%% smaller round the same content (%.0f -> %.0f px)" % [old_w, new_w])
	_check(panel._pin_key.visible and not panel._subtitle_label.visible and panel._pin_key.tooltip_text.contains("(5, 10)"),
		"bdp v3: the Location key under Close replaces the level and location line (%s)" % panel._pin_key.tooltip_text)
	var focused: Array = []
	var on_focus := func(id: String) -> void: focused.append(id)
	MatchState.focus_building_requested.connect(on_focus)
	panel._pin_key.pressed.emit()
	MatchState.focus_building_requested.disconnect(on_focus)
	_check(focused == [iid], "bdp v3: the Location key asks the map to show the building")
	var body_label: Label = panel._body.find_children("*", "Label", true, false)[0]
	_check(panel._shade.visible and body_label.material == load("res://scripts/bdp_v3_light.gd").text_material(),
		"bdp v3: the lamp's overlay covers the panel and the text takes some of its light back")
	var diag: PanelContainer = panel.find_child("DiagnosticsCard", true, false)
	var diag_frame: Node = diag.get_parent().get_parent() if diag != null else null
	var lamps: Array = diag.find_children("BdpV3Lamp*", "", true, false) if diag != null else []
	var diag_label: Label = diag.find_children("*", "Label", true, false)[0] if diag != null else null
	_check(diag != null and diag.get_theme_stylebox("panel") is StyleBoxEmpty and diag.find_child("BdpV3Cable", false, false) != null
		and diag_frame != null and diag_frame.get("style") == "plastic" and not lamps.is_empty()
		and diag_label.get_theme_color("font_color") == DS.PALETTE["TEXT"],
		"bdp v3: the diagnostics sit on dark plastic, their rows led by lamps, their text white, a cable beside the lamps (%d lamps)" % lamps.size())
	var modules: Array = diag.find_children("*", "PanelContainer", true, false).filter(func(n: Node) -> bool: return n.has_meta("v3_diag_module")) if diag != null else []
	var cable: Node = diag.find_child("BdpV3Cable", false, false) if diag != null else null
	_check(not modules.is_empty() and cable != null and cable.taps.size() == modules.size(),
		"bdp v3: every diagnostics row is its own module, fed by a branch off the cable (%d modules)" % modules.size())
	var diag_heading: Node = diag_frame.content.get_child(0) if diag_frame != null else null
	var switch: Node = diag_heading.find_child("ViewSwitch", false, false) if diag_heading != null else null
	var raised: Node = diag_heading.find_child("BdpV3Heading", false, false) if diag_heading != null else null
	var shown_texts: Array = diag_heading.find_children("*", "Label", true, false).filter(func(l: Label) -> bool: return l.visible).map(func(l: Label) -> String: return l.text) if diag_heading != null else []
	_check(switch != null and switch.find_child("BdpV3Toggle", false, false) != null and switch.find_child("BdpV3Toggle", false, false).right
		and not shown_texts.has("always shown") and switch.find_child("SwitchVisual", false, false) != null
		and switch.find_child("SwitchVisual", false, false).text == "VISUAL" and switch.find_child("SwitchText", false, false) != null,
		"bdp v3: the diagnostics heading has a Visual / Text switch set to Text, lettered as the headings, not 'always shown' (%s)" % ", ".join(shown_texts))
	_check(raised != null and raised.letter_count() == "DIAGNOSTICS".length(),
		"bdp v3: section headings are set in raised letters like INPUTS and OUTPUTS (%d)" % (raised.letter_count() if raised != null else -1))
	var ships_card: Control = panel.find_child("ShipmentsV3", true, false)
	var cells: Array = ships_card.find_children("*", "HBoxContainer", true, false).filter(func(n: Node) -> bool: return n.has_meta("v3_shipment_cell")) if ships_card != null else []
	var stock_lamp: Node = cells[0].find_child("StockLamp", false, false) if not cells.is_empty() else null
	var hover_icon: Node = cells[0].get_child(0) if not cells.is_empty() else null
	var ship_door: Control = ships_card.find_child("ShipmentDoor", true, false) if ships_card != null else null
	var ship_text: Array = ships_card.find_children("*", "Label", true, false).filter(func(l: Label) -> bool: return l.text.contains("stored")) if ships_card != null else []
	_check(cells.size() == 2 and stock_lamp != null and stock_lamp.colour == "red" and hover_icon.get("detail_lines").size() >= 4
		and hover_icon.custom_minimum_size.x == panel.V3_SHIP_ICON and ship_text.is_empty()
		and ship_door != null and is_equal_approx(ship_door.custom_minimum_size.y, ship_door.rolled_up_height() + 2.0 * (panel.V3_SHIP_ICON + panel.V3_SHIP_GAP)),
		"bdp v3: inbound shipments show large icons and stock lamps, no text, with the door down over the two empty rows (%d)" % cells.size())
	var pill: Control = hover_icon.get_child(hover_icon.get_child_count() - 1) if hover_icon != null else null
	_check(hover_icon != null and hover_icon.find_child("IconWell", false, false) != null and pill != null
		and pill.offset_right <= 0.0 and pill.offset_bottom <= 0.0 and ships_card.get_parent().get_parent().get("style") == "dark",
		"bdp v3: shipment icons sit below thin metal frames on a dark plate, their quantity pills inside the icon")
	var cost_card: Control = panel.find_child("CostToProduceCard", true, false)
	var cost_gauges: Array = cost_card.find_children("CostGauge*", "", true, false) if cost_card != null else []
	var cost_wells: Array = cost_card.find_children("IconWell", "", true, false) if cost_card != null else []
	_check(cost_card != null and cost_card.get_parent().get_parent().get("style") == "dark" and not cost_gauges.is_empty()
		and cost_wells.size() == cost_gauges.size(),
		"bdp v3: cost to produce sits on its own dark plate, each gauge with its good's icon set in beside it (%d)" % cost_gauges.size())
	var leds: Array = cost_card.find_children("BdpV3Led*", "", true, false) if cost_card != null else []
	var cost_texts: Array = cost_card.find_children("*", "Label", true, false).map(func(l: Label) -> String: return l.text) if cost_card != null else []
	var motor_price := Catalog.get_base_price(motor) * 0.72
	_check(leds.size() == cost_gauges.size() and leds[0].figure() == "%.2f" % motor_price
		and cost_texts.any(func(t: String) -> bool: return t.begins_with("Market price £"))
		and not cost_texts.any(func(t: String) -> bool: return t.contains("%") or t == Catalog.get_display_name(motor)),
		"bdp v3: the unit cost shows on a mini screen in LED segments, with 'Market price' under it and no name or percentage (%s)" % ", ".join(cost_texts))
	var icon_h: float = cost_wells[0].get_parent().size.y + 2.0 * 7.0 / 1.875 if not cost_wells.is_empty() else 0.0
	_check(absf(icon_h - panel.V3_GAUGE_SIZE * panel.V3_GAUGE_BEZEL) < 1.5,
		"bdp v3: the cost icon, frame and all, is as tall as the gauge's bezel (%.1f px)" % icon_h)
	_check(panel.find_children("*", "Label", true, false).filter(func(l: Label) -> bool: return l.text.contains("ready to draw from the grid") and l.is_visible_in_tree()).is_empty(),
		"bdp v3: the power line is left out, the diagnostics say the same")
	var econ_card: Control = panel.find_child("EconomicsV3", true, false)
	var shown_leds := func() -> Array:
		return econ_card.find_children("BdpV3Led*", "", true, false).filter(func(n: Control) -> bool: return n.is_visible_in_tree()) if econ_card != null else []
	await get_tree().process_frame
	var closed_leds: int = shown_leds.call().size()
	var va_box: Control = econ_card.find_child("ValueAdded", true, false) if econ_card != null else null
	var va_key: Control = va_box.find_child("BdpV3ModKey", true, false) if va_box != null else null
	if va_key != null:
		for down in [true, false]:
			var click := InputEventMouseButton.new()
			click.button_index = MOUSE_BUTTON_LEFT
			click.pressed = down
			click.position = va_key.size * 0.5
			va_key._gui_input(click)
	var open_leds: int = shown_leds.call().size()
	var pounds: Array = econ_card.find_children("MoneyLed", "", true, false) if econ_card != null else []
	var econ_bar: Control = econ_card.find_child("BdpV3ValueBar", true, false) if econ_card != null else null
	var econ_lamps: Array = econ_card.find_children("TransportLamp", "", true, false) if econ_card != null else []
	_check(econ_card != null and closed_leds == 3 and open_leds == 7 and pounds.size() >= 7 and va_key != null and va_key.open
		and econ_card.find_child("Transport", true, false) != null and econ_card.find_child("NetValueAdded", true, false) != null,
		"bdp v3: value added in production and transport open from worn white keys to show their parts, every figure an LED screen after a £ (%d shown closed, %d with value added open)" % [closed_leds, open_leds])
	_check(econ_bar != null and econ_bar.row_label(0) == "Revenue if sold" and econ_bar.row_keys(0).size() >= 1
		and econ_bar.row_keys(1).has("inputs") and econ_bar.row_keys(1).has("labour") and econ_lamps.size() == 2,
		"bdp v3: revenue (if sold) and costs show as two bars, and each side's transport has a lamp (%s | %s)" % [econ_bar.row_keys(0) if econ_bar != null else [], econ_bar.row_keys(1) if econ_bar != null else []])
	var t_box: Control = econ_card.find_child("Transport", true, false) if econ_card != null else null
	var t_key: Control = t_box.get_node("Head").find_child("BdpV3ModKey", false, false) if t_box != null else null
	if t_key != null:
		t_key.toggled.emit(true)
	var t_in: Control = t_box.find_child("TransportInputs", true, false) if t_box != null else null
	var t_out: Control = t_box.find_child("TransportOutputs", true, false) if t_box != null else null
	var in_key: Control = t_in.find_child("BdpV3ModKey", true, false) if t_in != null else null
	var in_rows: Array = t_in.find_child("Parts", true, false).get_children().map(func(r: Node) -> String: return (r.get_child(0) as Label).text) if t_in != null else []
	_check(t_in != null and t_out != null and in_key != null and is_equal_approx(in_key.key_scale, panel.V3_NESTED_KEY_SCALE)
		and in_rows.has("Steel · Port") and in_rows.has("Copper Wiring · Port"),
		"bdp v3: transport opens to inputs and outputs, each to its goods' freight and port charges (%s)" % ", ".join(in_rows))
	if va_box != null:
		panel._v3_econ_open.clear()
	var line_h: float = load("res://scripts/bdp_v3_title.gd").line_height()
	var key_px: float = panel._close_key.size.y * load("res://scripts/bdp_v3_key.gd").KEY_SIDE / load("res://scripts/bdp_v3_key.gd").TEXTURE_SIDE
	_check(absf(key_px - line_h) < 1.5 and absf((panel._pin_key.position.y - panel._close_key.position.y) - load("res://scripts/bdp_v3_title.gd").line_pitch()) < 1.5,
		"bdp v3: Close and Location are each a title line tall, one beside each line (%.1f px keys, lines %.1f)" % [key_px, line_h])
	var Emblem = load("res://scripts/bdp_v3_emblem.gd")
	var emblem: Control = panel._emblem_v3
	_check(emblem.visible and emblem.face != null and is_equal_approx(emblem.size.y, Emblem.side())
		and panel._title_v3._para.get_line_count() == 2 and absf(Emblem.side() - panel._title_v3.custom_minimum_size.y) < 1.0
		and emblem.get_global_rect().position.x < panel._title_v3.get_global_rect().position.x,
		"bdp v3: the building's metal emblem stands top left, as tall as the title's two lines beside it (%.0f px, title %.0f px)" % [Emblem.side(), panel._title_v3.custom_minimum_size.y])
	var room: float = panel._scroll.size.x - panel._scroll.get_v_scroll_bar().size.x
	_check(panel._body.get_combined_minimum_size().x <= room + 0.5,
		"bdp v3: no section needs more width than the body has, which would push the scrollbar into the trim (%.0f of %.0f px)" % [panel._body.get_combined_minimum_size().x, room])
	var mod_row: Control = panel.find_child("ModifiersRow", true, false)
	_check(mod_row != null and mod_row.find_child("ModifiersIcon", false, false) != null and mod_row.find_child("BdpV3Heading", true, false) != null
		and mod_row.find_child("BdpV3ModKey", true, false) != null,
		"bdp v3: Modifiers is laid out as Inputs: a raised % sign, the heading, and a key")
	var labour: Control = panel.find_child("LabourV3", true, false)
	var counters: Array = labour.find_children("*", "Control", true, false).filter(func(n: Node) -> bool: return n.get_script() == load("res://scripts/bdp_v3_counter.gd")) if labour != null else []
	_check(counters.size() == 2 and counters[0].decimals == 2 and counters[1].decimals == 0,
		"bdp v3: labour shows its cost and its workers on drum counters (%d)" % counters.size())
	var labour_doors: Array = labour.find_children("*", "Control", true, false).filter(func(n: Node) -> bool: return n.get_script() == load("res://scripts/bdp_v3_labour_door.gd")) if labour != null else []
	var head_total := 0
	for d in labour_doors:
		head_total += int(d.count)
	_check(labour_doors.size() == 3 and head_total == int(BuildingReadout.labour(Catalog.get_building("b_007"), Catalog.get_recipe(str(BuildingState.buildings[iid].get("recipe_id", "")))).get("total", -1)),
		"bdp v3: Labour and Wages has a factory door per kind of worker, its headcount on the kick plate (%d doors, %d workers)" % [labour_doors.size(), head_total])
	mod_row = panel.find_child("ModifiersRow", true, false)
	var mod_key: Control = mod_row.find_child("BdpV3ModKey", true, false) if mod_row != null else null
	_check(mod_key != null and not mod_key.openable and mod_key.summary == "None" and panel.find_child("ModifiersSheet", true, false) == null,
		"bdp v3: with no modifiers, Modifiers reads None and opens nothing")
	var test_mod: String = Modifiers.add({"id": "bdp_v3_test_output", "domain": "recipe_output", "pct": 10.0, "label": "Test yield", "source": "test"})
	panel._rebuild(b)
	await get_tree().process_frame
	mod_row = panel.find_child("ModifiersRow", true, false)
	mod_key = mod_row.find_child("BdpV3ModKey", true, false) if mod_row != null else null
	var mod_sheet: Control = panel.find_child("ModifiersSheet", true, false)
	var navy_ok := mod_sheet != null
	if mod_sheet != null:
		for l: Label in mod_sheet.find_children("*", "Label", true, false):
			navy_ok = navy_ok and l.get_theme_color("font_color") in [load("res://scripts/bdp_v3_plate.gd").NAVY] + panel.V3_INK.values()
	var closed_first: bool = mod_key != null and not mod_key.open and mod_sheet != null and not mod_sheet.visible
	if mod_key != null:
		mod_key.toggled.emit(true)
	_check(closed_first and mod_key.openable and mod_sheet.visible and navy_ok,
		"bdp v3: with a modifier, Modifiers starts closed and opens on a white plastic sheet printed in navy")
	panel._v3_modifiers_open = false
	Modifiers.remove(test_mod)
	panel._rebuild(b)
	await get_tree().process_frame
	# The rebuilds replaced the body; the checks below use its new footer and control block.
	footer = panel.find_child("BdpV3Footer", true, false)
	block = panel.find_child("BdpV3Block", true, false)
	var Seam = load("res://scripts/bdp_v3_seam.gd")
	_check(panel._seam.visible and is_equal_approx(panel._scroll.offset_top, Seam.strip_height())
		and panel._seam.get_index() > panel._scroll.get_index() and panel._seam.get_parent() == panel._scroll.get_parent(),
		"bdp v3: the non-slip edge sits over the seam, drawn after the body, which starts at its lip")
	# Godot renames same-named siblings, so the frames are found by script rather than by name.
	var section_script = load("res://scripts/bdp_v3_section.gd")
	var frames: Array = panel.find_children("*", "MarginContainer", true, false).filter(func(n: Node) -> bool: return n.get_script() == section_script)
	var framed: Array = []
	for f in frames:
		for c in f.content.get_children():
			if c.has_meta("v3_section"):
				framed.append(str(c.get_meta("v3_section")))
	_check(framed.has("Diagnostics") and framed.has("Labour and Wages") and framed.has("Economics · per turn"),
		"bdp v3: the sections sit in steel frames (%s)" % ", ".join(framed))
	var money_frame: Control = null
	for f in frames:
		for c in f.content.get_children():
			if str(c.get_meta("v3_section", "")) == "Economics · per turn":
				money_frame = f
	var shares := false
	if money_frame != null:
		for c in money_frame.content.get_children():
			shares = shares or str(c.get_meta("v3_section", "")) == "Modifiers"
	_check(shares, "bdp v3: Modifiers and Economics share one frame")
	if footer != null:
		var outcome_clip: Control = footer.find_child("FooterSlideout", false, false)
		var sell_plate: Control = outcome_clip.find_child("SellOutcome", false, false) if outcome_clip != null else null
		var demo_plate: Control = outcome_clip.find_child("DemolishOutcome", false, false) if outcome_clip != null else null
		footer.lift("demolish")
		await get_tree().create_timer(0.35).timeout
		var refund: Dictionary = BuildingWorks.refund_cost(iid).get("materials", {})
		var refund_icons: Array = demo_plate.find_child("RefundGoods", true, false).get_children() if demo_plate != null and demo_plate.find_child("RefundGoods", true, false) != null else []
		var demo_texts: Array = demo_plate.find_children("*", "Label", true, false).map(func(l: Label) -> String: return l.text) if demo_plate != null else []
		_check(outcome_clip != null and outcome_clip.visible and demo_plate != null and absf(demo_plate.position.y) < 0.5
			and demo_texts.has("%s land will be freed up" % BuildingWorks.land_text(BuildingState.space_used(b))) and refund_icons.size() == refund.size(),
			"bdp v3: lifting Demolish's cover slides up the land it frees and its refund, a good icon each (%d)" % refund_icons.size())
		footer.drop("demolish")
		footer.lift("sell")
		await get_tree().create_timer(0.35).timeout
		var sell_led: Node = sell_plate.find_child("BdpV3Led", true, false) if sell_plate != null else null
		var sell_texts: Array = sell_plate.find_children("*", "Label", true, false).map(func(l: Label) -> String: return l.text) if sell_plate != null else []
		_check(sell_plate != null and absf(sell_plate.position.y) < 0.5 and demo_plate.position.y > 1.0 and sell_texts.has("Building will become NPC")
			and sell_led != null and sell_led.figure() == "%.2f" % float(load("res://scripts/building_price.gd").sale_price(b)),
			"bdp v3: lifting Sell's cover slides up that the building becomes NPC and what it sells for")
		footer.drop("sell")
		await get_tree().create_timer(0.35).timeout
		_check(not outcome_clip.visible, "bdp v3: the outcome slides away when the cover drops")
		var opened: Array = []
		footer.key_pressed.connect(func(k: String) -> void: opened.append(k))
		var click := func(key: String, pressed: bool) -> void:
			var e := InputEventMouseButton.new()
			e.button_index = MOUSE_BUTTON_LEFT
			e.pressed = pressed
			e.position = footer.key_rect(key).get_center()
			footer._gui_input(e)
		# Swap the review for a no-op so the click does not open the supply-chain panel.
		for conn in footer.key_pressed.get_connections():
			if conn.callable.get_object() == panel:
				footer.key_pressed.disconnect(conn.callable)
		click.call("demolish", true); click.call("demolish", false)
		_check(footer.is_open("demolish") and opened.is_empty(), "bdp v3: the first click on Demolish only lifts its cover")
		click.call("demolish", true); click.call("demolish", false)
		_check(opened == ["demolish"] and not footer.is_open("demolish"), "bdp v3: the second click presses Demolish and the cover drops")
		footer.lift("sell")
		footer._process(footer.OPEN_SECONDS + 0.1)
		_check(not footer.is_open("sell"), "bdp v3: an untouched lifted cover drops again")
	if block != null:
		block.key_pressed.emit("outputs")
		await get_tree().process_frame
		_check(panel._sheet != null and panel._sheet.find_child("BdpV3BackKey", true, false) != null,
			"bdp v3: Outputs opens the output sheet, whose Back is a keycap")
		var sheet_scroll := panel._sheet.find_child("ActionSheetScroll", true, false) as ScrollContainer
		_check(sheet_scroll != null and Scroll.is_applied(sheet_scroll), "bdp v3: the sheets scroll on the steel rail too")
		var slide: Control = panel._sheet.find_child("SheetSlide", true, false)
		_check(slide != null and slide.find_child("BdpV3SheetPlate", false, false) != null and slide.position.x > 0.0
			and panel.get_child(panel.get_child_count() - 1) == panel._shade,
			"bdp v3: a sheet is a steel plate that slides in, under the lamp (starting %.0f px along)" % (slide.position.x if slide != null else -1.0))
		panel._close_sheet()
		var r: Rect2 = block.key_rect("recipe")
		var press := func(pressed: bool) -> void:
			var e := InputEventMouseButton.new()
			e.button_index = MOUSE_BUTTON_LEFT
			e.pressed = pressed
			e.position = r.get_center()
			block._gui_input(e)
		press.call(true); press.call(false)
		await get_tree().process_frame
		_check(panel._sheet != null and str(panel._sheet.find_child("SheetTitle", true, false).text).to_lower().contains("recipe"),
			"bdp v3: clicking the Change recipes key opens the recipe sheet")
		panel._close_sheet()
	UiPrefs.set_use_bdp_v3(false)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(panel.find_child("BdpV3Block", true, false) == null and panel.find_child("UpgradeButton", true, false) != null,
		"bdp v3: switching it off brings the v2 controls straight back")
	_check(panel._badge.visible and not panel._status_v3.visible and not Scroll.is_applied(panel._scroll)
		and not panel._seam.visible and is_equal_approx(panel._scroll.offset_top, 0.0)
		and panel._title_label.visible and not panel._title_v3.visible
		and panel.find_child("BdpV3Enamel", true, false) == null
		and panel._subtitle_label.visible and not panel._pin_key.visible and not panel._shade.visible
		and panel._body.find_children("*", "Label", true, false)[0].material == null,
		"bdp v3: switching it off brings back the plain title, the badge and location line, the plain scrollbar, the unedged body, the plain diagram and unshaded text")
	panel.queue_free()
	CostSolver.last_result = saved_cost
	BuildingState.buildings.erase(iid)
	UiPrefs.set_use_bdp_v3(was)

func _test_topbar_ds2_flag() -> void:
	# The DS2 bar is built behind a session flag, off by default, switched by the debug cheat.
	var was: bool = UiPrefs.use_topbar_ds2
	UiPrefs.set_use_topbar_ds2(false)
	var seen := []
	var on_change := func(on: bool) -> void: seen.append(on)
	UiPrefs.topbar_ds2_changed.connect(on_change)
	var term: Node = load("res://scripts/debug_terminal.gd").new()
	term.set("_cheats_unlocked", true)
	var reply: String = str(term.call("_run_command", "toggle topbar ds2"))
	_check(UiPrefs.use_topbar_ds2 and seen == [true] and reply.contains("DS2"),
		"top bar ds2: the cheat switches the DS2 bar on and says so")
	UiPrefs.toggle_use_topbar_ds2()
	_check(not UiPrefs.use_topbar_ds2 and seen == [true, false], "top bar ds2: and off again")
	UiPrefs.topbar_ds2_changed.disconnect(on_change)
	term.free()
	UiPrefs.set_use_topbar_ds2(was)

func _test_topbar_ds2_strip() -> void:
	# The DS2 strip: the money on the screen's centre line, the works to its left, the office to its
	# right, the lamp over the strip; switched off, the bar is v3.1 exactly.
	var was: bool = UiPrefs.use_topbar_ds2
	UiPrefs.set_use_topbar_ds2(false)
	var inst: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(inst)
	for _i in 4:
		await get_tree().process_frame
	var bar: Control = inst.get_node("UILayer/HUD/TopBar")
	var hbox: HBoxContainer = bar.get_node("MarginContainer/HBoxContainer")
	var names := func() -> PackedStringArray:
		var out := PackedStringArray()
		for c: Node in hbox.get_children():
			if (c as Control).visible:
				out.append(str(c.name))
		return out
	var v31_names: PackedStringArray = names.call()
	UiPrefs.set_use_topbar_ds2(true)
	for _i in 6:
		await get_tree().process_frame
	var money: Control = bar.get_node("MarginContainer/HBoxContainer/MoneyWidget")
	var centre: float = money.get_global_rect().get_center().x
	var screen_mid: float = bar.get_viewport_rect().size.x * 0.5
	_check(absf(centre - screen_mid) <= 1.0, "top bar ds2: the money sits on the screen's centre line (%.1f vs %.1f)" % [centre, screen_mid])
	var order: PackedStringArray = names.call()
	_check(order.find("PowerModule") < order.find("MoneyWidget") and order.find("TransportModule") < order.find("MoneyWidget")
		and order.find("VictoryModule") > order.find("MoneyWidget") and order.find("CouncilModule") > order.find("MoneyWidget"),
		"top bar ds2: the works to the money's left, victory and the office to its right")
	var shade: Node2D = bar.get_node_or_null("Ds2Shade")
	_check(shade != null and shade.visible and bar.get_child(bar.get_child_count() - 1) == shade,
		"top bar ds2: the lamp's shade is over the strip, drawn last")
	UiPrefs.set_use_topbar_ds2(false)
	for _i in 4:
		await get_tree().process_frame
	_check(names.call() == v31_names and not shade.visible, "top bar ds2: switched off, the v3.1 order and look come back")
	inst.queue_free()
	await get_tree().process_frame
	UiPrefs.set_use_topbar_ds2(was)

func _test_money_figure_format() -> void:
	# The owner's LED money rule: at most five cells, the point free, K/M/B printed after.
	var Money := preload("res://scripts/ds2/money_figure.gd")
	var cases := {
		0.0: "£0.00", 5.5: "£5.50", 999.99: "£999.99", 999.996: "£1000", 5717.0: "£5717",
		9999.4: "£9999", 10000.0: "£10.0K", 15600.0: "£15.6K", 999949.0: "£999.9K",
		1010000.0: "£1.01M", 12345678.0: "£12.35M", 2500000000.0: "£2.50B",
		-120.0: "-£120.0", -9999.0: "-£9999", -15600.0: "-£15.6K", -555.0: "-£555.0",
	}
	var wrong := PackedStringArray()
	for v: float in cases:
		var got: String = Money.text(v)
		var figure: String = Money.led(v).figure
		if got != cases[v] or Money.cells(figure) > Money.MAX_CELLS:
			wrong.append("%s -> %s" % [v, got])
	_check(wrong.is_empty(), "money figure: the owner's five-cell rule %s" % ", ".join(wrong))

func _test_top_bar_icon_fit() -> void:
	# Every icon on the bar is fitted by its drawn art to one cap height (or the width limit for
	# a wide icon), centred in its box; only the tabled exceptions are drawn larger.
	var Bar := preload("res://scripts/top_bar.gd")
	var Ind := preload("res://scripts/bdp_v3_indicator.gd")
	var ok := true
	var bad := PackedStringArray()
	for tex: Texture2D in [Bar.ICON_COIN, Bar.ICON_POWER, Bar.ICON_VICTORY, Bar.ICON_RANKINGS, Bar.ICON_QUEST,
			Bar.ICON_COUNCIL, Bar.ICON_GOODS_GRAPH, Bar.ICON_ENCYCLOPEDIA, Bar.ICON_MENU, Bar.WAREHOUSE_ICON]:
		var fit: Dictionary = Bar._icon_fit(tex)
		var box: Vector2 = fit.box
		var dest: Rect2 = fit.dest
		var k: float = float(Bar.ICON_OPTICAL.get(tex.resource_path, 1.0))
		var capped: bool = absf(box.y - Bar.ICON_CAP * k) <= 1.0 or absf(box.x - Bar.ICON_MAX_W * k) <= 1.0
		var art: Rect2 = Ind.art_rect(tex)
		var scale: float = dest.size.x / tex.get_size().x
		var art_centre: Vector2 = dest.position + (art.position + art.size * 0.5) * scale
		var centred: bool = art_centre.distance_to(box * 0.5) <= 1.0
		if not (capped and centred and box.y <= Bar.MOD_H):
			ok = false
			bad.append("%s box=%s" % [tex.resource_path.get_file(), box])
	_check(ok, "top bar: every icon's art fills the cap height or the width limit, centred in its box %s" % ", ".join(bad))
	_check(Bar.BAR_H == 60.0 and Bar.MOD_H + 8.0 + Bar.EDGE_H <= Bar.BAR_H, "top bar: 60 px, its modules inside it")

func _test_updates_dock() -> void:
	# Every toast is a row in a slide-out over a 60 px bottom-left dock with three bells.
	var toasts: Control = load("res://scripts/toast_manager.gd").new()
	add_child(toasts)
	await get_tree().process_frame
	var dock: Control = toasts.find_child("UpdatesDock", true, false)
	_check(dock != null and is_equal_approx(dock.size.y, 60.0), "updates dock: 60 px tall")
	_check(dock != null and dock.get_global_rect().position.x < 40.0 \
		and dock.get_global_rect().end.y > toasts.size.y - 40.0, "updates dock: in the bottom-left corner")
	var bells_ok := true
	for tone: String in ["green", "amber", "red"]:
		bells_ok = bells_ok and toasts.find_child("Bell_%s" % tone, true, false) != null and toasts.unread(tone) == 0
	_check(bells_ok, "updates dock: a green, an amber and a red bell, none counting yet")
	_check(toasts.tone_of("success") == "green" and toasts.tone_of("info") == "green" \
		and toasts.tone_of("caution") == "amber" and toasts.tone_of("warning") == "red" \
		and toasts.tone_of("error") == "red", "updates dock: each toast type rings its bell")

	toasts._on_toast_requested("Built a steel furnace", "success")
	toasts._on_toast_requested("Local opposition to density", "caution")
	toasts._on_toast_requested("Cash is in the red", "warning")
	toasts._on_toast_requested("No route to market", "error")
	_check(toasts.row_count() == 4, "updates dock: every toast becomes a row")
	_check(toasts.unread("green") == 1 and toasts.unread("amber") == 1 and toasts.unread("red") == 2,
		"updates dock: each bell counts its rows")
	var rows: Control = toasts.find_child("Rows", true, false)
	_check(toasts.is_open() and rows.mouse_filter == Control.MOUSE_FILTER_IGNORE,
		"updates dock: a new row slides the rows out, letting clicks through")
	_check(not toasts._timer.is_stopped() and is_equal_approx(toasts._timer.wait_time, toasts.TOAST_DURATION),
		"updates dock: the rows collapse TOAST_DURATION after the last one")
	await get_tree().create_timer(0.3).timeout
	await get_tree().process_frame
	var sweeps := []
	for r: Node in toasts.find_child("RowList", true, false).get_children():
		if (r as Control).visible:
			sweeps.append(snappedf(r.get_node("Countdown").remaining, 0.001))
	_check(sweeps.size() == 4 and toasts.countdown() < 1.0 and toasts.countdown() > 0.8 \
		and sweeps.count(sweeps[0]) == 4 and absf(sweeps[0] - toasts.countdown()) < 0.05,
		"updates dock: every shown row carries the same countdown sweep, running down")
	toasts._on_timer()
	_check(not toasts.is_open() and toasts.unread("red") == 2, "updates dock: collapsing keeps the bells' counts")

	toasts.open_all()
	_check(toasts.is_open() and rows.mouse_filter == Control.MOUSE_FILTER_STOP,
		"updates dock: opened from the dock, the rows take the mouse")
	_check(toasts.unread("green") + toasts.unread("amber") + toasts.unread("red") == 0,
		"updates dock: opening from the dock clears the counts")
	_check(toasts._dock_style.border_color == toasts.DOCK_BORDER_HOT, "updates dock: its rim lights while its slide-out is up")
	var row_list: Node = toasts.find_child("RowList", true, false)
	var shown := func() -> int:
		return row_list.get_children().filter(func(r: Node) -> bool: return (r as Control).visible).size()
	_check(shown.call() == 4, "updates dock: opened from the dock, every kept row shows")
	toasts._on_timer()
	_check(not toasts.is_open() and toasts._dock_style.border_color == toasts.DOCK_BORDER,
		"updates dock: the dock's slide-out also closes when left alone, and its rim goes out")

	toasts._on_toast_requested("Ordered 5 Steel", "success")
	_check(toasts.is_open() and shown.call() == 1, "updates dock: opened by itself, only rows it hasn't shown")
	for i in toasts.HISTORY_MAX + 5:
		toasts.show_error("Refused %d" % i)
	_check(toasts.row_count() == toasts.HISTORY_MAX, "updates dock: keeps the newest HISTORY_MAX rows")
	_check(shown.call() == toasts.MAX_TOASTS, "updates dock: opened by itself, at most MAX_TOASTS rows")
	_check(toasts.row_texts()[-1] == "Refused %d" % (toasts.HISTORY_MAX + 4), "updates dock: the newest row is last")
	toasts.clear()
	_check(toasts.row_count() == 0 and not toasts.is_open() and toasts.unread("red") == 0,
		"updates dock: clearing empties the rows and the bells")
	toasts.queue_free()

func _test_updates_dock_filters_and_decisions() -> void:
	# A bell opens the slide-out on its own rows; the pen counts decisions and opens the briefing.
	var toasts: Control = load("res://scripts/toast_manager.gd").new()
	add_child(toasts)
	await get_tree().process_frame
	var rows: Node = toasts.find_child("RowList", true, false)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	var shown := func() -> PackedStringArray:
		var out := PackedStringArray()
		for r: Node in rows.get_children():
			if (r as Control).visible:
				out.append(str(r.get_meta("toast_message", "")))
		return out
	var pen: Control = toasts.find_child("Decisions", true, false)
	var icons: Array = pen.get_parent().get_children() if pen != null else []
	_check(pen != null and icons.find(pen) == 0 and icons.size() == 4,
		"updates dock: a pen sits before the three bells")

	toasts._on_toast_requested("Built a steel furnace", "success")
	toasts._on_toast_requested("Local opposition to density", "caution")
	toasts._on_toast_requested("Cash is in the red", "warning")
	toasts._on_toast_requested("No route to market", "error")
	toasts.collapse(false)
	toasts.find_child("Bell_red", true, false).gui_input.emit(click)
	_check(toasts.is_open() and toasts.filter() == "red" \
		and shown.call() == PackedStringArray(["Cash is in the red", "No route to market"]),
		"updates dock: clicking the red bell shows only the red rows")
	_check(toasts.unread("red") == 0 and toasts.unread("green") == 1 and toasts.unread("amber") == 1,
		"updates dock: a bell clears only its own count")
	toasts.find_child("Bell_amber", true, false).gui_input.emit(click)
	_check(toasts.is_open() and shown.call() == PackedStringArray(["Local opposition to density"]),
		"updates dock: another bell switches the rows to its colour")
	toasts.find_child("Bell_amber", true, false).gui_input.emit(click)
	_check(not toasts.is_open() and toasts.filter() == "", "updates dock: the same bell again closes the rows")
	toasts.find_child("UpdatesDock", true, false).gui_input.emit(click)
	_check(shown.call().size() == 4, "updates dock: clicking the dock between its icons shows every row")
	toasts.collapse(false)
	toasts.clear()
	toasts.open_all("green")
	var empty: Label = null
	for l: Node in toasts.find_children("*", "Label", true, false):
		if (l as Label).text.begins_with("No ") and (l as Label).visible:
			empty = l
	_check(empty != null and empty.text == "No updates yet", "updates dock: an empty bell says it has nothing yet")
	toasts.collapse(false)

	var items_before: Array = TurnBriefing._items
	var expanded_before: bool = TurnBriefing.expanded
	TurnBriefing._items = [
		{"id": "dec:1", "kind": "decision", "section": "decisions"},
		{"id": "dec:2", "kind": "decision", "section": "decisions"},
		{"id": "ev:9", "kind": "event", "section": "info"},
	]
	TurnBriefing.items_changed.emit()
	var pill: Control = pen.find_child("Count", true, false)
	_check(toasts.decisions() == 2 and pill != null and pill.visible and (pill.get_child(0) as Label).text == "2",
		"updates dock: the pen counts the decisions waiting")
	TurnBriefing.expanded = false
	var opened := [""]
	var saved_hide: bool = DecisionState.hide_updates
	DecisionState.hide_updates = false
	var on_expand := func(is_open: bool) -> void: opened[0] = "open" if is_open else "closed"
	TurnBriefing.expanded_changed.connect(on_expand)
	toasts.open_all()
	pen.gui_input.emit(click)
	_check(opened[0] == "open" and TurnBriefing.expanded and not toasts.is_open(),
		"updates dock: the pen opens the briefing on its decisions and puts the rows away")
	pen.gui_input.emit(click)
	_check(opened[0] == "closed" and not TurnBriefing.expanded, "updates dock: the pen again closes the briefing")
	TurnBriefing.expanded_changed.disconnect(on_expand)
	DecisionState.hide_updates = saved_hide
	TurnBriefing._items = items_before
	TurnBriefing.expanded = expanded_before
	TurnBriefing.items_changed.emit()
	toasts.queue_free()

func _test_updates_dock_research_and_notices() -> void:
	# Research unlocks sit above the other rows as green links; notices are amber and keyed.
	var toasts: Control = load("res://scripts/toast_manager.gd").new()
	add_child(toasts)
	await get_tree().process_frame
	var rows: Node = toasts.find_child("RowList", true, false)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true

	toasts._on_toast_requested("Built a steel furnace", "success")
	toasts.push_research("Interchangeable Tooling")
	toasts.push_research("Operational Team Managers")
	var texts: PackedStringArray = toasts.row_texts()
	_check(texts.size() == 3 and texts[0] == "Unlocked: Interchangeable Tooling" \
		and texts[1] == "Unlocked: Operational Team Managers" and texts[2] == "Built a steel furnace",
		"updates dock: unlocks read 'Unlocked: <name>' and sit above the other rows, in the order they came")
	_check(toasts.unread("green") == 3, "updates dock: unlocks ring the green bell")
	var research_row: Control = rows.get_child(0)
	_check(research_row.mouse_filter == Control.MOUSE_FILTER_STOP and toasts.find_child("Rows", true, false).mouse_filter == Control.MOUSE_FILTER_IGNORE,
		"updates dock: an unlock's row takes its click while the rest lets clicks through")
	var searched := [""]
	var on_search := func(tech: String) -> void: searched[0] = tech
	MatchState.research_search_requested.connect(on_search)
	research_row.gui_input.emit(click)
	MatchState.research_search_requested.disconnect(on_search)
	_check(searched[0] == "Interchangeable Tooling" and not toasts.is_open(),
		"updates dock: clicking an unlock opens the Research panel on it and puts the rows away")
	toasts.push_research("Interchangeable Tooling")
	_check(toasts.row_count() == 3, "updates dock: the same unlock twice keeps one row")

	for i in toasts.MAX_TOASTS + 2:
		toasts.show_caution("Caution %d" % i)
	toasts.push_research("High-Volume Press Lines")
	var shown: Array = rows.get_children().filter(func(r: Node) -> bool: return (r as Control).visible)
	_check(shown.size() == toasts.MAX_TOASTS and str(shown[0].get_meta("toast_message", "")) == "Unlocked: High-Volume Press Lines",
		"updates dock: an unlock shows first even when more rows arrived than fit")
	toasts.collapse(false)

	var turn_key := "upcoming:7"
	toasts.push_notice(turn_key, "Input bill coming next turn.\nRecommended buffer: £150")
	_check(toasts.has_row("notice:" + turn_key) and toasts.unread("amber") == toasts.MAX_TOASTS + 3,
		"updates dock: a notice is an amber row under its key")
	var count: int = toasts.row_count()
	toasts.push_notice(turn_key, "Input bill coming next turn.\nRecommended buffer: £150")
	_check(toasts.row_count() == count, "updates dock: the same notice again adds nothing")
	toasts.push_notice(turn_key, "Input bill coming next turn.\nRecommended buffer: £200")
	_check(toasts.row_count() == count and toasts.unread("amber") == toasts.MAX_TOASTS + 3 \
		and toasts.row_texts()[-1].ends_with("£200"), "updates dock: a changed notice replaces its row")
	toasts.remove_row("notice:" + turn_key)
	_check(not toasts.has_row("notice:" + turn_key) and toasts.row_count() == count - 1,
		"updates dock: a notice that no longer holds can be withdrawn")
	var ran := [false]
	toasts.push_notice("stock:tile_5_10:g_005:7", "Copper accumulating at Stoneshore (+19/turn).", func() -> void: ran[0] = true)
	var notice_row: Control = null
	for r: Node in rows.get_children():
		if str(r.get_meta("key", "")) == "notice:stock:tile_5_10:g_005:7":
			notice_row = r
	if notice_row != null:
		notice_row.gui_input.emit(click)
	_check(notice_row != null and ran[0], "updates dock: a notice's link runs when its row is clicked")
	toasts.queue_free()

func _test_bdp_v3_diag_visual() -> void:
	# The diagnostics' Visual / Text switch: the visual view's stage columns of icons over lamps, the readout
	# that names the icon under the pointer (else the worst check), and the readout kept in sight when the
	# case's foot is below the fold.
	var was: bool = UiPrefs.use_bdp_v3
	UiPrefs.set_use_bdp_v3(true)
	var iid: String = BuildingState.add_building("b_007", "r_009", "tile_5_10", MatchState.LOCAL_PLAYER, "v3_diag_visual")
	var b: Dictionary = BuildingState.get_building(iid)
	var panel = load("res://scripts/building_detail_panel_v2.gd").new()
	add_child(panel)
	await get_tree().process_frame
	panel.show_building(b)
	await get_tree().process_frame
	var Indicator = load("res://scripts/bdp_v3_indicator.gd")
	var find_view := func() -> Array:
		return [panel.find_child("DiagnosticsCard", true, false), panel.find_child("DiagnosticsVisual", true, false),
			panel.find_child("ViewSwitch", true, false).find_child("BdpV3Toggle", false, false)]
	var found: Array = find_view.call()
	var text_card: Control = found[0]
	var view: Control = found[1]
	var toggle: Control = found[2]
	_check(text_card != null and view != null and toggle != null and text_card.visible and not view.visible
		and view.get_parent() == text_card.get_parent() and toggle.right,
		"bdp v3 visual: the visual view is built in the diagnostics case beside the text, hidden while the switch is on Text")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	toggle._gui_input(click)
	await get_tree().process_frame
	await get_tree().process_frame
	var columns: Array = view.find_children("*", "PanelContainer", true, false).filter(func(n: Node) -> bool: return n.has_meta("v3_diag_column"))
	var is_indicator := func(n: Node) -> bool: return n.get_script() == Indicator
	var counts: Array = columns.map(func(c: Node) -> int: return c.find_children("*", "Control", true, false).filter(is_indicator).size())
	var titles: Array = columns.map(func(c: Node) -> String: return (c.find_children("*", "Label", true, false)[0] as Label).text)
	var inds: Array = view.find_children("*", "Control", true, false).filter(is_indicator)
	# Only the checks that apply show: the stages and counts the panel's own filtered lists give, in order.
	var expected: Array = panel.v3_diag_visual_checks(b, Catalog.get_recipe("r_009"), false, load("res://scripts/building_economics.gd").per_turn(b))
	var want_titles: Array = []
	var want_counts: Array = []
	for i in expected.size():
		if not (expected[i] as Array).is_empty():
			want_titles.append(str(panel.V3_DIAG_STAGES[i][0]))
			want_counts.append((expected[i] as Array).size())
	_check(view.visible and not text_card.visible and not toggle.right and titles == want_titles and counts == want_counts
		and titles[0] == "Inputs" and inds.all(func(n: Node) -> bool: return n.lamp != null and n.icon != null and n.tone != "off"),
		"bdp v3 visual: thrown to Visual, the case shows a column for each stage with checks that apply, inputs on the left (%s %s)" % [str(titles), str(counts)])
	_check(not inds.any(func(n: Node) -> bool: return n.label == "Deposit left"),
		"bdp v3 visual: a check that doesn't apply is left out, as the deposit for a factory")
	var applies := func(list: Array) -> Array: return list.filter(func(c: Dictionary) -> bool: return str(c.tone) != "off")
	var output_inds: Array = inds.filter(func(n: Node) -> bool: return n.stage == "Outputs")
	var output_want: Array = applies.call(load("res://scripts/building_readout.gd").output_checks(b, Catalog.get_recipe("r_009"), false))
	var output_got: Array = output_inds.map(func(n: Node) -> String: return "%s/%s" % [n.label, n.tone])
	_check(output_got == output_want.map(func(c: Dictionary) -> String: return "%s/%s" % [c.label, c.tone])
		and output_inds.all(func(n: Node) -> bool: return n.icon.resource_path.contains("diag_icon_") and n.lamps.size() == n.tones.size()),
		"bdp v3 visual: Outputs shows reach, transit, freight, port charge and sales, each with an icon and a lamp per tone (%s)" % ", ".join(output_got))
	var input_inds: Array = inds.filter(func(n: Node) -> bool: return n.stage == "Inputs")
	var input_want: Array = applies.call(load("res://scripts/building_readout.gd").input_checks(b, Catalog.get_recipe("r_009"), false))
	var input_got: Array = input_inds.map(func(n: Node) -> String: return "%s/%s" % [n.label, n.tone])
	_check(input_got == input_want.map(func(c: Dictionary) -> String: return "%s/%s" % [c.label, c.tone])
		and input_inds.all(func(n: Node) -> bool: return n.icon.resource_path.contains("diag_icon_")),
		"bdp v3 visual: Inputs shows the input checks that apply, each with its own icon (%s)" % ", ".join(input_got))
	var grids: Array = columns.map(func(c: Node) -> Node: return c.find_children("*", "GridContainer", true, false)[0])
	var cell_h: float = inds[0].custom_minimum_size.y if not inds.is_empty() else 0.0
	var five_rows: float = 5.0 * cell_h + 4.0 * 8.0
	_check(grids.all(func(g: Node) -> bool: return is_equal_approx(g.size.y, five_rows))
		and columns.all(func(c: Node) -> bool: return is_equal_approx(c.size.y, columns[0].size.y))
		and grids.all(func(g: Node) -> bool: return g.columns == 1),
		"bdp v3 visual: every column is one icon wide and five rows tall, whatever it holds (%.0f px)" % five_rows)
	var inbound_inds: Array = inds.filter(func(n: Node) -> bool: return n.stage == "Inbound")
	var inbound_want: Array = applies.call(load("res://scripts/building_readout.gd").inbound_checks(b, Catalog.get_recipe("r_009"), false, load("res://scripts/building_economics.gd").per_turn(b)))
	var inbound_got: Array = inbound_inds.map(func(n: Node) -> String: return "%s/%s" % [n.label, n.tone])
	_check(inbound_got == inbound_want.map(func(c: Dictionary) -> String: return "%s/%s" % [c.label, c.tone])
		and inbound_inds.all(func(n: Node) -> bool: return n.icon.resource_path.contains("diag_icon_")),
		"bdp v3 visual: Inbound shows route and mode, warehouse room, transit time and freight cost, each with its own icon (%s)" % ", ".join(inbound_got))
	var plant_inds: Array = inds.filter(func(n: Node) -> bool: return n.stage == "Plant")
	var plant_want: Array = applies.call(load("res://scripts/building_readout.gd").plant_checks(b, Catalog.get_recipe("r_009"), false, load("res://scripts/building_economics.gd").per_turn(b)))
	var plant_got: Array = plant_inds.map(func(n: Node) -> String: return "%s/%s" % [n.label, n.tone])
	_check(plant_got == plant_want.map(func(c: Dictionary) -> String: return "%s/%s" % [c.label, c.tone])
		and plant_inds.all(func(n: Node) -> bool: return n.icon.resource_path.contains("diag_icon_")),
		"bdp v3 visual: Plant shows the plant checks that apply, each with its own icon (%s)" % ", ".join(plant_got))
	# Power's three are the building's power checks, each with its own icon.
	var power_inds: Array = inds.filter(func(n: Node) -> bool: return n.stage == "Power")
	var want: Array = applies.call(load("res://scripts/building_readout.gd").power_checks(b, Catalog.get_recipe("r_009"), false))
	var got: Array = power_inds.map(func(n: Node) -> String: return "%s/%s" % [n.label, n.tone])
	var expect: Array = want.map(func(c: Dictionary) -> String: return "%s/%s" % [c.label, c.tone])
	_check(got == expect and power_inds.all(func(n: Node) -> bool: return n.icon.resource_path.contains("diag_icon_")),
		"bdp v3 visual: Power shows the power checks that apply, each with its own icon (%s)" % ", ".join(got))
	# 40 px icons, 12 px apart in a two-wide column, each render scaled so its art fills the box.
	var in_col: Array = columns[0].find_children("*", "Control", true, false).filter(is_indicator)
	var art_px: float = 0.0
	if not power_inds.is_empty():
		var p0: Control = power_inds[0]
		var art: Rect2 = Indicator.art_rect(p0.icon)
		art_px = maxf(art.size.x, art.size.y) * p0.art_dest().size.x / p0.icon.get_size().x
	var col_pad: float = in_col[0].get_global_rect().position.x - columns[0].get_global_rect().position.x if not in_col.is_empty() else -1.0
	var want_px: float = panel.V3_DIAG_ICON_PX
	_check(not in_col.is_empty() and is_equal_approx(want_px, 56.0) and is_equal_approx(in_col[0].size.x, want_px) and col_pad >= 6.0 - 0.5 and absf(art_px - want_px) < 0.5,
		"bdp v3 visual: icons are 56 px, at least 6 px in from their column's sides, their art trimmed to fill the box (%.1f px, %.1f in)" % [
			in_col[0].size.x if not in_col.is_empty() else -1.0, col_pad])
	var worst: Node = null
	for want_tone in ["bad", "warn"]:
		for n: Node in inds:
			if worst == null and n.tone == want_tone:
				worst = n
	var worst_name: String = "%s: %s" % [worst.stage, worst.label] if worst != null else ""
	var readout: Control = view.find_child("BdpV3Readout", true, false)
	_check(readout != null and worst != null and readout.shown_name() == worst_name and readout._lamp.colour == load("res://scripts/bdp_v3_lamp.gd").colour_for(worst.tone),
		"bdp v3 visual: with the pointer on no icon, the readout names the worst check, its lamp lit to match (%s)" % (readout.shown_name() if readout != null else "none"))
	var first: Control = inds[0] if not inds.is_empty() else null
	if first != null and readout != null:
		first.mouse_entered.emit()
		await get_tree().process_frame
		var detail_label: Label = readout.find_child("ReadoutDetail", true, false)
		_check(readout.shown_name() == "%s: %s" % [first.stage, first.label] and readout.shown_detail() == first.detail and first.hot
			and readout._lamp.colour == load("res://scripts/bdp_v3_lamp.gd").colour_for(first.tone)
			and detail_label.get_visible_line_count() >= 1 and detail_label.get_rect().end.y <= readout.find_child("ReadoutRow", true, false).size.y + 0.5,
			"bdp v3 visual: hovering an icon names it and its finding in the readout, the finding in sight (%s, %d line)" % [readout.shown_name(), detail_label.get_visible_line_count()])
		first.mouse_exited.emit()
		await get_tree().create_timer(panel.V3_DIAG_READOUT_SETTLE + 0.1).timeout
		_check(readout.shown_name() == worst_name and not first.hot,
			"bdp v3 visual: leaving the icons, the readout goes back to the worst check (%s)" % readout.shown_name())
	var room: float = panel._scroll.size.x - panel._scroll.get_v_scroll_bar().size.x
	_check(panel._body.get_combined_minimum_size().x <= room + 0.5,
		"bdp v3 visual: the columns need no more width than the body has (%.0f of %.0f px)" % [panel._body.get_combined_minimum_size().x, room])
	if readout != null and first != null:
		# Put the slot's foot 80 px below the scroll area's bottom edge: scroll down to it, or make the panel
		# shorter when it is already in view at the top.
		var slot: Control = readout.get_parent()
		panel._scroll.scroll_vertical = 0
		await get_tree().process_frame
		await get_tree().process_frame
		var below: float = slot.get_global_rect().end.y - panel._scroll.get_global_rect().end.y
		if below > 80.0:
			panel._scroll.scroll_vertical = int(below - 80.0)
		else:
			var h: float = panel.size.y - (80.0 - below)
			panel.custom_minimum_size.y = h
			panel.size.y = h
		for _i in 3:
			await get_tree().process_frame
		var edge: float = panel._scroll.get_global_rect().end.y
		var rr: Rect2 = readout.get_global_rect()
		_check(slot.get_global_rect().end.y > edge + 40.0 and absf(rr.end.y - edge) < 1.0 and rr.position.y >= first.get_global_rect().end.y,
			"bdp v3 visual: with the case's foot below the fold, the readout rises onto the scroll area's bottom edge, clear of the first row (bottom %.0f, edge %.0f)" % [rr.end.y, edge])
		panel._scroll.scroll_vertical += 200
		for _i in 3:
			await get_tree().process_frame
		_check(is_equal_approx(readout.position.y, panel.V3_DIAG_READOUT_GAP),
			"bdp v3 visual: with the case's foot in view, the readout sits back in its slot (%.1f)" % readout.position.y)
	panel._rebuild(b)
	await get_tree().process_frame
	found = find_view.call()
	_check(found[1] != null and found[1].visible and not found[0].visible and not found[2].right,
		"bdp v3 visual: the switch's side is kept when the panel rebuilds")
	# Closed, then opened on another building: the player's choice stays.
	panel._hide_panel()
	await get_tree().process_frame
	var other_iid: String = BuildingState.add_building("b_007", "r_009", "tile_5_10", MatchState.LOCAL_PLAYER, "v3_diag_visual_other")
	panel.show_building(BuildingState.get_building(other_iid))
	await get_tree().process_frame
	found = find_view.call()
	_check(UiPrefs.bdp_diag_visual and found[1] != null and found[1].visible and not found[0].visible and not found[2].right,
		"bdp v3 visual: closed and opened on another building, the panel still shows Visual")
	# While a tutorial step spotlights the rows, which its words describe, the rows show.
	var saved_tutorial := [Tutorial.active, Tutorial._index, Tutorial._steps]
	Tutorial.active = true
	Tutorial._steps = [{"id": "diag_test", "spotlight": {"kind": "node_name", "ref": "DiagnosticsCard"}}]
	Tutorial._index = 0
	var during_step: bool = panel._v3_diag_shows_visual()
	Tutorial.active = saved_tutorial[0]
	Tutorial._index = saved_tutorial[1]
	Tutorial._steps = saved_tutorial[2]
	_check(not during_step and panel._v3_diag_shows_visual(),
		"bdp v3 visual: a tutorial step that spotlights the diagnostics' rows shows them; after it, Visual again")
	found[2]._gui_input(click)
	await get_tree().process_frame
	_check(found[0].visible and not found[1].visible and found[2].right and not UiPrefs.bdp_diag_visual,
		"bdp v3 visual: thrown back to Text, the rows come back")
	panel.queue_free()
	BuildingState.buildings.erase(other_iid)
	BuildingState.buildings.erase(iid)
	UiPrefs.set_use_bdp_v3(was)


func _test_bdp_v3_power_checks() -> void:
	# The diagnostics' visual Power checks: three for any building that uses or makes power, their tones
	# agreeing with the text checklist's power rows; "off" for a building with no power at all.
	var BR = load("res://scripts/building_readout.gd")
	var iid: String = BuildingState.add_building("b_007", "r_009", "tile_5_10", MatchState.LOCAL_PLAYER, "v3_power_checks")
	var b: Dictionary = BuildingState.get_building(iid)
	var r: Dictionary = Catalog.get_recipe("r_009")
	var checks: Array = BR.power_checks(b, r, false)
	var keys: Array = checks.map(func(c: Dictionary) -> String: return str(c.key))
	var rows: Array = BR.diagnostics(b, r, Catalog.get_building("b_007"), false)
	var power_row: Dictionary = {}
	for row: Dictionary in rows:
		if str(row.get("ic", "")) == "bolt" and str(row.get("label", "")) in ["Unpowered", "Ready to draw power", "Powered"]:
			power_row = row
	_check(keys == ["power_supply", "intermittency", "cable"] and not power_row.is_empty()
		and str(checks[0].tone) == str(power_row.get("tone", "")) and checks.all(func(c: Dictionary) -> bool: return str(c.detail) != "" and str(c.detail).length() <= 120),
		"power checks: a factory drawing power gets supply, intermittency and cable checks, supply's tone the checklist's (%s vs %s: %s)" % [
			checks[0].tone if not checks.is_empty() else "?", power_row.get("tone", "?"), ", ".join(checks.map(func(c: Dictionary) -> String: return "%s %s" % [c.key, c.tone]))])
	var cap: int = Power.tile_power_cap("tile_5_10")
	_check((cap <= 0 and str(checks[2].tone) == "bad" and str(checks[2].detail).contains("No cables"))
		or (cap > 0 and str(checks[2].detail).contains("%d MW its cables carry" % cap)),
		"power checks: cable capacity reads the tile's cable cap (%d MW: %s)" % [cap, checks[2].detail])
	var plant_iid: String = BuildingState.add_building("b_003", "r_004", "tile_5_10", MatchState.LOCAL_PLAYER, "v3_power_checks_plant")
	var plant: Array = BR.power_checks(BuildingState.get_building(plant_iid), Catalog.get_recipe("r_004"), false)
	_check(str(plant[0].detail).begins_with("Makes ") and str(plant[1].tone) == "ok" and str(plant[1].detail).contains("Never intermittent"),
		"power checks: a coal plant is its own source and never intermittent (%s / %s)" % [plant[0].detail, plant[1].detail])
	var no_power: Array = BR.power_checks(b, r, true)
	_check(no_power.size() == 3 and no_power.all(func(c: Dictionary) -> bool: return str(c.tone) == "off"),
		"power checks: a building with no power gets all three checks unlit")
	BuildingState.buildings.erase(iid)
	BuildingState.buildings.erase(plant_iid)


func _test_bdp_v3_plant_checks() -> void:
	# The diagnostics' visual Plant checks: the carbon levy (none in force; paid; tipping the building
	# into a loss) and works under way (none; retooling).
	var BR = load("res://scripts/building_readout.gd")
	var iid: String = BuildingState.add_building("b_003", "r_004", "tile_5_10", MatchState.LOCAL_PLAYER, "v3_plant_checks")
	var b: Dictionary = BuildingState.get_building(iid)
	var r: Dictionary = Catalog.get_recipe("r_004")
	var was_turn: int = TurnManager.current_turn
	TurnManager.current_turn = 1
	var early: Array = BR.plant_checks(b, r, false)
	_check(early.map(func(c: Dictionary) -> String: return str(c.key)) == ["carbon", "works"]
		and str(early[0].tone) == "ok" and str(early[0].detail).contains("No carbon levy in force")
		and str(early[1].tone) == "off",
		"plant checks: before the levy a coal plant pays none, and with no works the works lamp is unlit (%s / %s)" % [early[0].detail, early[1].detail])
	TurnManager.current_turn = PolicyState.beat("p1") + 1
	var levy: float = PolicyState.run_carbon_levy(b, r)
	var paying: Array = BR.plant_checks(b, r, false, {"net_value_added": levy + 5.0})
	var tipped: Array = BR.plant_checks(b, r, false, {"net_value_added": -levy * 0.5})
	var sunk: Array = BR.plant_checks(b, r, false, {"net_value_added": -levy * 2.0})
	_check(levy > 0.0 and str(paying[0].tone) == "warn" and str(paying[0].detail).contains("£%.2f" % levy) and str(paying[0].detail).contains("coal")
		and str(tipped[0].tone) == "bad" and str(tipped[0].detail).contains("into a loss")
		and str(sunk[0].tone) == "warn",
		"plant checks: with the levy in force a coal plant pays it (amber), red only when the levy alone turns profit into loss (£%.2f: %s)" % [levy, paying[0].detail])
	TurnManager.current_turn = was_turn
	BuildingWorks.pending_retrofits.append({"instance_id": iid, "turns_remaining": 2})
	var retool: Dictionary = BR.plant_checks(b, r, false)[1]
	BuildingWorks.pending_retrofits.pop_back()
	_check(str(retool.tone) == "warn" and str(retool.detail).begins_with("Retooling. 2 turns left"),
		"plant checks: a retooling building's works lamp is amber, with the turns left (%s)" % retool.detail)
	BuildingState.buildings.erase(iid)


func _test_bdp_v3_inbound_checks() -> void:
	# The diagnostics' visual Inbound checks: their order, unlit for a building with no inputs, and each
	# one's bands: a missing route, the warehouse full / nearly full / roomy, transit by the slowest
	# input, and freight toned by the economics' input transport lamp.
	var BR = load("res://scripts/building_readout.gd")
	var tile := "tile_2_2"
	var iid: String = BuildingState.add_building("b_007", "r_009", tile, MatchState.LOCAL_PLAYER, "v3_inbound_checks")
	var b: Dictionary = BuildingState.get_building(iid)
	var r: Dictionary = Catalog.get_recipe("r_009")
	var checks: Array = BR.inbound_checks(b, r, false, load("res://scripts/building_economics.gd").per_turn(b))
	_check(checks.map(func(c: Dictionary) -> String: return str(c.key)) == ["route", "warehouse", "transit", "freight"]
		and checks.all(func(c: Dictionary) -> bool: return str(c.detail) != "" and str(c.detail).length() <= 120),
		"inbound checks: a factory with inputs gets route, warehouse, transit and freight checks (%s)" % ", ".join(checks.map(func(c: Dictionary) -> String: return "%s %s" % [c.key, c.tone])))
	var none: Array = BR.inbound_checks(b, {"inputs": []}, false)
	_check(none.size() == 4 and none.all(func(c: Dictionary) -> bool: return str(c.tone) == "off"),
		"inbound checks: a building that takes no inputs gets all four unlit")
	var steel_id := str(Catalog.get_good_by_internal_name("steel").get("id", ""))
	var wire_id := str(Catalog.get_good_by_internal_name("copper_wiring").get("id", ""))
	var by := func(gid: String, modes: Array, reachable: bool = true) -> Dictionary:
		return {"good_id": gid, "name": "x", "reachable": reachable, "turns": 2, "from": "the market",
			"route": {"legs": modes.map(func(m: String) -> Dictionary: return {"mode": m})}}
	var blocked: Dictionary = BR._route_check(b, r, [by.call(steel_id, [], false)])
	var roads: Dictionary = BR._route_check(b, r, [by.call(steel_id, ["roads"])])
	var rails: Dictionary = BR._route_check(b, r, [by.call(steel_id, ["rail"])])
	var both: Dictionary = BR._route_check(b, r, [by.call(steel_id, ["rail"]), by.call(wire_id, ["roads"])])
	_check(str(blocked.tone) == "bad" and str(blocked.detail) == "No route in. Connect the tile by rail."
		and str(roads.tone) == "warn" and str(roads.detail) == "Comes by road from the market. Rail would be cheaper."
		and str(rails.tone) == "ok" and both.tones == ["warn", "ok"] and str(both.detail).begins_with("Copper wiring: Comes by road"),
		"inbound checks: each input's route, a lamp each: red with no route, amber when rail or pipe would be cheaper (%s / %s)" % [roads.detail, both.detail])
	var steel := str(Catalog.get_good_by_internal_name("steel").get("id", ""))
	var cap: int = Stockpile.get_capacity(tile)
	var used0: int = Stockpile.get_used_capacity(tile)
	var added: int = Stockpile.add(tile, steel, cap - used0)
	var full: Dictionary = BR._warehouse_check(b, r)
	Stockpile.consume(tile, steel, int(cap * 0.05))
	var near: Dictionary = BR._warehouse_check(b, r)
	Stockpile.consume(tile, steel, int(cap * 0.5))
	var room: Dictionary = BR._warehouse_check(b, r)
	Stockpile.consume(tile, steel, Stockpile.get_at_tile(tile, steel))
	_check(cap > 0 and added > 0 and str(full.tone) in ["warn", "bad"] and str(full.detail).begins_with("Warehouse full")
		and str(near.tone) == "warn" and str(near.detail).begins_with("Warehouse nearly full")
		and str(room.tone) == "ok" and str(room.detail).contains("Room for deliveries"),
		"inbound checks: warehouse room is amber or red when full, amber when nearly full, green with room (%s / %s / %s)" % [full.detail, near.detail, room.detail])
	var near_t: Dictionary = BR._transit_check([{"name": "steel", "turns": 1, "from": "the market"}, {"name": "copper wiring", "turns": 0, "from": "this tile"}])
	var mid_t: Dictionary = BR._transit_check([{"name": "steel", "turns": 3, "from": "the market"}, {"name": "copper wiring", "turns": 1, "from": "the market"}])
	var far_t: Dictionary = BR._transit_check([{"name": "steel", "turns": 6, "from": "the market"}])
	_check(str(near_t.tone) == "ok" and str(mid_t.tone) == "warn" and str(mid_t.detail) == "Slowest is steel, 3 turns from the market."
		and str(far_t.tone) == "bad",
		"inbound checks: transit is green within a turn, amber to four, red beyond, naming the slowest input (%s)" % mid_t.detail)
	var freight: Dictionary = BR._freight_check({"shown": true, "transport_in": 5.0, "input_value": 100.0, "lamp_in": "warn"})
	var free: Dictionary = BR._freight_check({"shown": true, "transport_in": 0.0, "input_value": 40.0, "inputs_free": false, "lamp_in": "ok"})
	_check(str(freight.tone) == "warn" and str(freight.detail) == "£5.00 a turn to bring inputs in, 5% of their value."
		and str(free.tone) == "ok",
		"inbound checks: freight takes the economics' input transport lamp and gives the cost and its share (%s)" % freight.detail)
	BuildingState.buildings.erase(iid)


func _test_bdp_v3_input_checks() -> void:
	# The diagnostics' visual Inputs checks: their order; stock cover from the tile's stock (the scarcest
	# input, and short of one); a supplier of the company's own routed here; a mine's deposit; and all
	# unlit but the deposit for a building that takes no inputs.
	var BR = load("res://scripts/building_readout.gd")
	var tile := "tile_2_2"
	var iid: String = BuildingState.add_building("b_007", "r_009", tile, MatchState.LOCAL_PLAYER, "v3_input_checks")
	var b: Dictionary = BuildingState.get_building(iid)
	var r: Dictionary = Catalog.get_recipe("r_009")
	var checks: Array = BR.input_checks(b, r, false)
	_check(checks.map(func(c: Dictionary) -> String: return str(c.key)) == ["source", "stock", "upstream", "deposit"]
		and str(checks[2].tone) == "off" and str(checks[3].tone) == "off" and str(checks[3].detail).begins_with("Not a mine")
		and checks.all(func(c: Dictionary) -> bool: return str(c.detail) != "" and str(c.detail).length() <= 120),
		"inputs checks: a factory gets source, stock, upstream and deposit; no own supplier and no deposit leave those unlit (%s)" % ", ".join(checks.map(func(c: Dictionary) -> String: return "%s %s" % [c.key, c.tone])))
	var steel := str(Catalog.get_good_by_internal_name("steel").get("id", ""))
	var wire := str(Catalog.get_good_by_internal_name("copper_wiring").get("id", ""))
	Stockpile.add(tile, steel, 100)
	Stockpile.add(tile, wire, 70)
	var covered: Dictionary = BR._stock_check(b, r, false)
	Stockpile.consume(tile, wire, 60)
	var short: Dictionary = BR._stock_check(b, r, false)
	Stockpile.consume(tile, steel, Stockpile.get_at_tile(tile, steel))
	Stockpile.consume(tile, wire, Stockpile.get_at_tile(tile, wire))
	_check(str(covered.tone) == "ok" and str(covered.detail) == "Stock covers 2 runs. Copper wiring runs short first."
		and str(short.tone) in ["warn", "bad"] and str(short.detail).begins_with("Short of copper wiring for the next run. 10 of 32"),
		"inputs checks: stock cover counts the runs the scarcest input covers, and names an input short for the next run (%s / %s)" % [covered.detail, short.detail])
	var steel_recipes: Array = Catalog.recipes_producing(steel)
	var mill_iid := ""
	if not steel_recipes.is_empty():
		var sr: Dictionary = steel_recipes[0]
		mill_iid = BuildingState.add_building(str(sr.get("building_id", "")), str(sr.get("recipe_id", "")), "tile_3_2", MatchState.LOCAL_PLAYER, "v3_input_checks_mill")
		MatchState.set_output_stockpile_destination(mill_iid, tile, steel)
	var upstream: Dictionary = BR._upstream_check(b, r)
	Stockpile.add(tile, steel, 100)
	Stockpile.add(tile, wire, 100)
	var sources: Dictionary = BR._source_check(b, r, false)
	Stockpile.consume(tile, steel, Stockpile.get_at_tile(tile, steel))
	Stockpile.consume(tile, wire, Stockpile.get_at_tile(tile, wire))
	if mill_iid != "":
		MatchState.clear_output_stockpile_destination(mill_iid, steel)
		BuildingState.buildings.erase(mill_iid)
	_check(mill_iid != "" and str(upstream.tone) != "off" and str(upstream.detail).contains("Your ") and str(upstream.detail).contains("steel"),
		"inputs checks: a steel supplier of the company's own, routed here, is watched by upstream health (%s: %s)" % [upstream.tone, upstream.detail])
	_check(sources.tones == ["warn", "ok"] and str(sources.detail) == "Copper wiring: Bought at the market. The rest: 1 green.",
		"inputs checks: source has a lamp per input, green for steel from the company's own mill, amber for wiring bought (%s)" % sources.detail)
	var mine_iid: String = BuildingState.add_building("b_001", "r_001", tile, MatchState.LOCAL_PLAYER, "v3_input_checks_mine")
	var mine: Dictionary = BuildingState.get_building(mine_iid)
	var mine_r: Dictionary = Catalog.get_recipe("r_001")
	var mine_checks: Array = BR.input_checks(mine, mine_r, false)
	Production.last_turn_summary["deposits_running_out"] = [{"instance_id": mine_iid, "remaining": 40, "per_turn": 10, "turns_left": 4}]
	var running_out: Dictionary = BR._deposit_check(mine, mine_r)
	Production.last_turn_summary["deposits_running_out"] = []
	var has_token: bool = Production._recipe_deposit_token(mine_r) != ""
	_check(has_token and str(mine_checks[3].tone) != "off" and str(running_out.tone) == "warn" and str(running_out.detail).begins_with("About 4 turns of")
		and ((mine_r.get("inputs", []) as Array).size() > 0 or (str(mine_checks[0].tone) == "off" and str(mine_checks[1].tone) == "off")),
		"inputs checks: a mine's deposit is read, amber with the turns left when running out (%s / %s)" % [mine_checks[3].detail, running_out.detail])
	BuildingState.buildings.erase(mine_iid)
	BuildingState.buildings.erase(iid)


func _test_bdp_v3_output_checks() -> void:
	# The diagnostics' visual Outputs checks, each over every good the recipe makes: their order; all
	# unlit for a power plant; reach red with no route out, amber when a cheaper mode exists; transit and
	# freight by the checklist's bands; the port by its traffic against its cap; sales as unsold stock when
	# it piles up, else price against the glut; several goods combined into lamps by tone, worst first.
	var BR = load("res://scripts/building_readout.gd")
	var tile := "tile_2_2"
	var iid: String = BuildingState.add_building("b_007", "r_009", tile, MatchState.LOCAL_PLAYER, "v3_output_checks")
	var b: Dictionary = BuildingState.get_building(iid)
	var r: Dictionary = Catalog.get_recipe("r_009")
	var checks: Array = BR.output_checks(b, r, false)
	_check(checks.map(func(c: Dictionary) -> String: return str(c.key)) == ["reach", "transit_out", "freight_out", "port", "sales"]
		and checks.all(func(c: Dictionary) -> bool: return str(c.detail) != "" and (c.tones as Array).size() >= 1),
		"outputs checks: a factory gets reach, transit, freight, port charge and sales, each with its lamps' tones (%s)" % ", ".join(checks.map(func(c: Dictionary) -> String: return "%s %s" % [c.key, c.tone])))
	var plant_iid: String = BuildingState.add_building("b_003", "r_004", tile, MatchState.LOCAL_PLAYER, "v3_output_checks_plant")
	var plant: Array = BR.output_checks(BuildingState.get_building(plant_iid), Catalog.get_recipe("r_004"), false)
	BuildingState.buildings.erase(plant_iid)
	_check(plant.size() == 5 and plant.all(func(c: Dictionary) -> bool: return str(c.tone) == "off") and str(plant[0].detail).contains("cable"),
		"outputs checks: a power plant's goods checks are unlit, its power leaving by cable (%s)" % plant[0].detail)
	var gid := BuildingStatus.primary_output_good_id(r)
	var qty: int = BuildingStatus.primary_output_qty(r)
	var g := {"gid": gid, "qty": qty, "name": "Motor"}
	var none := {"reachable": false, "target": "tile_9_9", "turns": 0, "cost": 0.0, "destination": "Market (via Port)"}
	var far := {"reachable": true, "target": "tile_9_9", "turns": 3, "cost": 16.0, "destination": "Market (via Port)"}
	var freight: Dictionary = BR._freight_out_check(far, b, g)
	var no_route: Dictionary = BR._reach_check(none, b, g)
	var id_of := func(internal: String) -> String: return str(Catalog.get_good_by_internal_name(internal).get("id", ""))
	var steel_id: String = id_of.call("steel")
	var water_id: String = id_of.call("pure_water")
	var chlorine_id: String = id_of.call("chlorine")
	_check(str(no_route.tone) == "warn" and str(BR._transit_out_check(none, b, g).tone) == "bad"
		and str(BR._transit_out_check(far, b, g).tone) == "warn"
		and BR._cheaper_mode(steel_id, ["roads"]) == "rail" and BR._cheaper_mode(steel_id, ["rail"]) == "" and BR._cheaper_mode(steel_id, []) == "rail"
		and BR._cheaper_mode(water_id, ["roads", "rail"]) == "pipes" and BR._cheaper_mode(water_id, ["reinf_pipes"]) == ""
		and BR._cheaper_mode(chlorine_id, ["roads"]) == "reinf_pipes" and BR._cheaper_mode(chlorine_id, ["reinf_pipes"]) == ""
		and str(freight.tone) == ("ok" if 16.0 / qty < 0.15 else "warn") and str(freight.detail).contains("a unit to ship"),
		"outputs checks: reach is amber, never red, when a cheaper infrastructure suits the good (rail; pipeline; reinforced for hazards), and no route out makes transit red (%s)" % no_route.detail)
	# The port: green with room, amber within 10% of its cap for the good's transport class, red at it.
	var port_tile := "tile_5_10"
	var sold_there := {"has_market": true, "target": port_tile, "reachable": true, "destination": "Market", "turns": 1, "cost": 0.0}
	TransportState._ensure_sea_shipping_turn()
	var saved_usage: Dictionary = TransportState._sea_port_usage_this_turn.duplicate(true)
	var saved_charges: Dictionary = TransportState._sea_port_charges_this_turn.duplicate(true)
	var kind := Catalog.get_transport_class(gid)
	var cap: int = TransportState.seaport_throughput_cap(gid)
	TransportState._sea_port_charges_this_turn[port_tile] = {gid: {"good_id": gid, "transport_class": kind, "at_cap": false}}
	var port_at := func(share: float) -> Dictionary:
		TransportState._sea_port_usage_this_turn[port_tile] = {kind: int(cap * share)}
		return BR._port_check(b, sold_there, g)
	var roomy: Dictionary = port_at.call(0.5)
	var near: Dictionary = port_at.call(0.95)
	var full: Dictionary = port_at.call(1.0)
	TransportState._sea_port_usage_this_turn = saved_usage
	TransportState._sea_port_charges_this_turn = saved_charges
	_check(str(roomy.tone) == "ok" and str(near.tone) == "warn" and str(near.detail).contains("close to the cap")
		and str(full.tone) == "bad" and str(full.detail).contains("pays double"),
		"outputs checks: the port is green with room, amber within 10%% of its cap, red at it (%s)" % full.detail)
	var saved_impact: float = MarketState.get_impact_pct(gid)
	var route: Dictionary = BR.output_route(b, r)
	MarketState.impact_pct[gid] = -12.0
	var sunk: Dictionary = BR._sales_check(b, route, g)
	MarketState.impact_pct[gid] = -7.0
	var dipped: Dictionary = BR._sales_check(b, route, g)
	MarketState.impact_pct[gid] = saved_impact
	var stock_tile := tile if bool(route.get("has_market", false)) or str(route.get("target", "")) == "" else str(route.get("target", ""))
	Stockpile.add(stock_tile, gid, qty * 4)
	var piled: Dictionary = BR._sales_check(b, route, g)
	Stockpile.add(stock_tile, gid, qty * 3)
	var heaped: Dictionary = BR._sales_check(b, route, g)
	Stockpile.consume(stock_tile, gid, Stockpile.get_at_tile(stock_tile, gid))
	_check(str(sunk.tone) == "bad" and str(sunk.icon) == "glut" and str(sunk.detail).contains("12% under its base price") and str(dipped.tone) == "warn"
		and str(piled.tone) == "warn" and str(piled.icon) == "unsold" and str(piled.detail).contains("%d waiting unsold" % (qty * 4))
		and str(heaped.tone) == "bad" and str(heaped.detail).contains("7 turns of output"),
		"outputs checks: sales is the glut (coin, amber 5%% under, red 10%%) while output sells, unsold stock (pallet, amber 3 turns, red 6) once it piles up (%s / %s)" % [sunk.detail, heaped.detail])
	var combined: Dictionary = BR._combine_goods("reach", "Reach", [
		{"tone": "ok", "name": "Chlorine", "detail": "Fine."}, {"tone": "bad", "name": "Hydrogen", "detail": "Can't reach the port."},
		{"tone": "warn", "name": "Soda", "detail": "Dear."}, {"tone": "ok", "name": "Salt", "detail": "Fine."}])
	_check(combined.tones == ["bad", "warn", "ok"] and str(combined.tone) == "bad"
		and str(combined.detail) == "Hydrogen: Can't reach the port. The rest: 1 amber, 2 green.",
		"outputs checks: several goods make one check, a lamp per tone worst first, the worst named (%s)" % combined.detail)
	var alike: Dictionary = BR._combine_goods("route", "Route and mode", [
		{"tone": "ok", "name": "steel", "detail": "Lands at the port on this tile."}, {"tone": "ok", "name": "copper wiring", "detail": "Lands at the port on this tile."}])
	_check(alike.tones == ["ok"] and str(alike.detail) == "Steel and copper wiring: Lands at the port on this tile.",
		"outputs checks: goods that share a finding are named together (%s)" % alike.detail)
	var ind: Control = load("res://scripts/bdp_v3_indicator.gd").new()
	add_child(ind)
	ind.configure(40.0, 0.72)
	ind.set_check({"stage": "Outputs", "label": "Reach", "tone": "bad", "tones": ["bad", "warn", "ok"], "detail": "x"}, null, null)
	var colours: Array = ind.lamps.map(func(l: Node) -> String: return str(l.colour))
	_check(colours == ["red", "amber", "green"] and ind.custom_minimum_size.x >= 3.0 * ind.lamp.custom_minimum_size.x,
		"outputs checks: an indicator over three tones shows three lamps side by side, red, amber, green (%s)" % ", ".join(colours))
	ind.queue_free()
	BuildingState.buildings.erase(iid)
