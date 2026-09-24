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
	if va_box != null:
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = true
		va_box.get_node("Head").gui_input.emit(click)
	var open_leds: int = shown_leds.call().size()
	var pounds: Array = econ_card.find_children("MoneyLed", "", true, false) if econ_card != null else []
	var econ_bar: Control = econ_card.find_child("BdpV3ValueBar", true, false) if econ_card != null else null
	var econ_lamps: Array = econ_card.find_children("TransportLamp", "", true, false) if econ_card != null else []
	_check(econ_card != null and closed_leds == 3 and open_leds == 7 and pounds.size() >= 7
		and econ_card.find_child("Transport", true, false) != null and econ_card.find_child("NetValueAdded", true, false) != null,
		"bdp v3: value added in production and transport open to show their parts, every figure an LED screen after a £ (%d shown closed, %d with value added open)" % [closed_leds, open_leds])
	_check(econ_bar != null and econ_bar.row_label(0) == "Revenue if sold" and econ_bar.row_keys(0).size() >= 1
		and econ_bar.row_keys(1).has("inputs") and econ_bar.row_keys(1).has("labour") and econ_lamps.size() == 2,
		"bdp v3: revenue (if sold) and costs show as two bars, and each side's transport has a lamp (%s | %s)" % [econ_bar.row_keys(0) if econ_bar != null else [], econ_bar.row_keys(1) if econ_bar != null else []])
	if va_box != null:
		panel._v3_econ_open.clear()
	var line_h: float = load("res://scripts/bdp_v3_title.gd").line_height()
	var key_px: float = panel._close_key.size.y * load("res://scripts/bdp_v3_key.gd").KEY_SIDE / load("res://scripts/bdp_v3_key.gd").TEXTURE_SIDE
	_check(absf(key_px - line_h) < 1.5 and absf((panel._pin_key.position.y - panel._close_key.position.y) - load("res://scripts/bdp_v3_title.gd").line_pitch()) < 1.5,
		"bdp v3: Close and Location are each a title line tall, one beside each line (%.1f px keys, lines %.1f)" % [key_px, line_h])
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
	var mod_key: Control = panel.find_child("BdpV3ModKey", true, false)
	var mod_sheet: Control = panel.find_child("ModifiersSheet", true, false)
	var navy_ok := mod_sheet != null
	if mod_sheet != null:
		for l: Label in mod_sheet.find_children("*", "Label", true, false):
			navy_ok = navy_ok and l.get_theme_color("font_color") in [load("res://scripts/bdp_v3_plate.gd").NAVY] + panel.V3_INK.values()
	var was_open: bool = mod_sheet.visible if mod_sheet != null else true
	if mod_key != null:
		mod_key.toggled.emit(true)
	_check(mod_key != null and not was_open and mod_sheet.visible and navy_ok,
		"bdp v3: Modifiers is a white key that opens a white plastic sheet printed in navy")
	if mod_key != null:
		mod_key.toggled.emit(false)
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
