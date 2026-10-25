extends RefCounted
## Validate before any migration/reset/import. Missing additive fields remain valid.
## FIELDS lists the value shapes consumed by subsystem import_state/import_fields.
## Update it with the owning import when adding a saved field; never infer it from a live match.
const DemoBuild := preload("res://scripts/demo_build.gd")
const MAX_FILE_BYTES := 64 * 1024 * 1024
const MAX_DEPTH := 32
const MAX_NODES := 1000000
const MAX_COLLECTION := 100000
const MAX_STRING := 65536
const FIELDS := {
	"match": {
		"dictionary": [
			"advisor_hired_turn",
			"advisor_loyalty",
			"advisor_mission5_streak",
			"advisor_missions_completed",
			"advisor_seats",
			"advisor_walk_streak",
			"advisors_hired_streaks",
			"arrival_turns",
			"auto_sell_goods",
			"auto_sell_impact",
			"auto_sell_keep",
			"awaiting_special_orders",
			"buildings",
			"demolish_queue",
			"deposit_remaining",
			"fired_advisor_cooldowns",
			"ghost_holdings",
			"pending_purchases",
			"infrastructure_usage_last_turn",
			"infrastructure_usage_streaks",
			"input_tile_only",
			"last_sea_port_charges",
			"last_sea_port_usage",
			"link_congestion_paid",
			"link_over_history",
			"middleman_service",
			"middleman_shipments_by_good",
			"mini_quest",
			"output_ship_quantities",
			"output_special_order_destinations",
			"output_split_destinations",
			"output_stockpile_destinations",
			"partially_surveyed_tiles",
			"paused_buildings",
			"port_sales_by_class",
			"port_sales_by_port",
			"profitable_run_streaks",
			"queued_local_sales",
			"queued_stockpile_market_sales",
			"revealed_deposits",
			"ruleset",
			"seaport_subscribed",
			"sell_surplus_tiles",
			"stockpile_feed_streaks",
			"surplus_destinations",
			"surveyed_tiles",
			"surveying_in_progress",
			"surveying_reveal",
			"tile_battery_cells",
			"tile_land_owned",
			"tile_land_priced",
			"tile_land_standalone",
			"transport_usage_snapshot",
			"unlock_progress",
			"unlocked_titles",
			"workforce_policies",
			"workforce_policy_effects"
		],
		"array": [
			"advisor_crossed_milestones",
			"advisor_mission_policies",
			"cfo_tax_credit_pool",
			"favourite_builds",
			"move_log",
			"one_off_charges",
			"overflow_shipments",
			"pending_battery_fills",
			"pending_retrofits",
			"pending_transport_shipments",
			"pending_upgrades",
			"permanent_advisor_ids",
			"recent_profits",
			"recruited_advisor_ids",
			"recurring_bulk_sells",
			"recurring_buys",
			"recurring_moves",
			"recurring_sells",
			"scheduled_moves",
			"transaction_log",
			"labour_target_shifts",
			"union_grandfathered_ids"
		],
		"number": [
			"advisor_peak_profit",
			"advisor_profit_streak",
			"union_active_turns",
			"union_signed_turn",
			"work_week_hours",
			"advisor_rng_seed",
			"advisors_hired_last_turn",
			"agenda_last_build_turn",
			"bonus_free_unlocks",
			"founder_leaves_turn",
			"freight_credit_units",
			"idle_labour_pay_share",
			"labour_multiplier",
			"labour_output_pressure_pct",
			"labour_satisfaction",
			"land_economy_level",
			"land_economy_warned",
			"last_sea_shipping_turn",
			"max_advisor_slots",
			"middleman_free_units",
			"money",
			"next_instance_counter",
			"port_sale_total",
			"public_roads_last_turn",
			"recent_profits_last_turn",
			"route_objective",
			"sell_mode",
			"shipment_id_counter"
		],
		"string": [
			"construct_material_source",
			"construct_output_destination",
			"founder_seat",
			"power_priority_coal_gas",
			"power_priority_wind_solar",
			"scenario_name"
		],
		"bool": [
			"advisor_slot_profit_unlocked",
			"all_seats_unlocked",
			"cfo_tax_credit_intro_shown",
			"cheats_used",
			"construct_auto_buy_land",
			"construct_start_half_capacity",
			"global_trade_license_paid",
			"rail_hubs_seeded",
			"seaport_auto_subscribe",
			"union_halving_active"
		]
	},
	"turn": {
		"number": [
			"current_turn"
		],
		"bool": [
			"game_ended"
		]
	},
	"stockpile": {
		"dictionary": [
			"by_tile",
			"fill_history",
			"peak_used",
			"refused",
			"warehouse_levels"
		]
	},
	"loans": {
		"dictionary": [
			"transit_credit"
		],
		"array": [
			"loans",
			"profit_history",
			"revenue_history"
		],
		"number": [
			"next_loan_id"
		]
	},
	"construction": {
		"dictionary": [
			"projects"
		]
	},
	"market": {
		"dictionary": [
			"impact_pct",
			"lifetime_sold",
			"net_history",
			"price_history",
			"recovery_step"
		]
	},
	"special_orders": {
		"dictionary": [
			"fulfilled_count_when_removed_by_good"
		],
		"array": [
			"active_orders"
		],
		"number": [
			"fulfilled_count",
			"last_spawn_turn",
			"next_order_counter",
			"rng_seed"
		]
	},
	"production": {
		"dictionary": [
			"direct_feed",
			"full_output_streak_by_building",
			"intermittency_by_building",
			"intermittency_by_tile",
			"lifetime_pl_by_building",
			"produced_by_building"
		]
	},
	"cost_solver": {
		"dictionary": [
			"per_building",
			"per_good"
		]
	},
	"company_rankings": {
		"dictionary": [
			"player_goods_produced"
		],
		"array": [
			"player_rank_history",
			"player_revenue_history"
		],
		"bool": [
			"announcement_fired"
		]
	},
	"events": {
		"dictionary": [
			"active",
			"starvation_last_turn",
			"starvation_streaks"
		],
		"array": [
			"history",
			"scheduled",
			"watches"
		],
		"number": [
			"next_event_seq"
		],
		"bool": [
			"first_market_sale_told"
		]
	},
	"modifiers": {
		"dictionary": [
			"modifiers"
		],
		"array": [
			"history"
		],
		"number": [
			"next_id"
		]
	},
	"decisions": {
		"dictionary": [
			"cooldown_until",
			"fired_once",
			"flags",
			"pending",
			"reservations",
			"scheduled_pull"
		],
		"array": [
			"history",
			"pending_queue",
			"recent_draws"
		],
		"number": [
			"next_pulse_turn",
			"next_uid",
			"rng_seed"
		]
	},
	"solvency": {
		"array": [
			"history"
		],
		"number": [
			"bad_streak",
			"tutorial_rescues"
		],
		"bool": [
			"bankrupt",
			"distressed_offered"
		]
	},
	"briefing": {
		"dictionary": [
			"alert_dismissed",
			"silenced_windows"
		]
	},
	"victory": {
		"dictionary": [
			"produced_by_good",
			"purchases_lifetime",
			"purchases_this_turn",
			"track_best",
			"track_secured_turn"
		],
		"array": [
			"history_buildings",
			"history_output",
			"history_revenue",
			"richest_window",
			"score_history"
		],
		"number": [
			"autarkic_streak",
			"demo_crown_points",
			"demo_crown_turns",
			"demo_long_hauls",
			"logistics_efficient",
			"logistics_total",
			"produced_units_lifetime",
			"won_turn"
		],
		"bool": [
			"won"
		]
	},
	"policy": {
		"number": [
			"ban_override_turn"
		],
		"bool": [
			"insider_tip_fired",
			"seeded"
		]
	},
	"telemetry": {
		"array": [
			"events"
		],
		"number": [
			"playtime_s",
			"session",
			"started_at"
		],
		"string": [
			"run_id",
			"start"
		]
	},
	"roads.network": {
		"dictionary": [
			"edges",
			"nodes"
		],
		"number": [
			"next_edge",
			"next_node"
		]
	},
	"roads.works": {
		"array": [
			"farm_links",
			"farm_promoted",
			"linked_pairs",
			"orders",
			"styled_regions"
		],
		"number": [
			"next_order"
		]
	},
	"match.mini_quest": {
		"dictionary": [
			"board_baseline",
			"board_choices",
			"board_done",
			"board_granted",
			"done",
			"generic_done",
			"generic_granted",
			"granted"
		],
		"number": [
			"buildings_built",
			"buildings_opened",
			"deposits_coal_step",
			"infra_built",
			"units_sold_total"
		],
		"string": [
			"chain",
			"followed_board",
			"monetised_good"
		]
	},
	"roads": {
		"dictionary": [
			"network",
			"works"
		]
	},
	"loans.transit_credit": {
		"bool": [
			"enabled"
		],
		"number": [
			"balance"
		]
	},
	"match.transport_usage_snapshot": {
		"dictionary": [
			"flow"
		],
		"array": [
			"shipments"
		],
		"number": [
			"accounting_version"
		]
	},
	"match.middleman_service": {
		"dictionary": [
			"buildings"
		]
	},
	"match.ruleset": {
		"number": ["speed_turns"],
		"string": ["name", "difficulty", "start_id", "victory_set", "logistics_model"],
		"bool": ["tutorial_enabled", "survey_all_tiles", "middleman_new_buildings"]
	}
}

const NUMERIC_ARRAYS := ["recent_profits", "advisor_crossed_milestones", "profit_history", "revenue_history", "player_revenue_history", "player_rank_history", "richest_window", "history_revenue", "history_output", "history_buildings"]
const STRING_ARRAYS := ["union_grandfathered_ids", "permanent_advisor_ids", "recruited_advisor_ids", "advisor_mission_policies", "styled_regions", "linked_pairs", "farm_promoted", "farm_links"]
const RECORD_MAPS := ["match.buildings", "construction.projects", "match.middleman_service.buildings", "match.deposit_remaining", "modifiers.modifiers", "events.active", "cost_solver.per_building", "cost_solver.per_good", "production.produced_by_building", "production.lifetime_pl_by_building", "production.direct_feed", "roads.network.nodes", "roads.network.edges"]
const NUMBER_MAPS := ["stockpile.warehouse_levels", "stockpile.peak_used", "stockpile.refused", "market.impact_pct", "market.recovery_step", "market.lifetime_sold", "match.advisor_loyalty", "match.advisor_hired_turn", "match.fired_advisor_cooldowns", "match.advisor_missions_completed", "victory.track_best", "victory.produced_by_good", "company_rankings.player_goods_produced"]
var _nodes := 0


func validate(snapshot: Variant, version: int, demo: bool, from_disk := false) -> String:
	_nodes = 0
	var error := _tree(snapshot, "save", 0)
	if error != "": return error
	if not snapshot is Dictionary: return "save must be an object"
	var snap: Dictionary = snapshot
	if from_disk and (not snap.has("match") or not snap.has("turn")):
		return "save must contain match and turn objects"
	if snap.has("start") and not snap.start is bool:
		return "start must be a boolean"
	if snap.has("save_version"):
		if not _number(snap.save_version) or snap.save_version != floorf(float(snap.save_version)) or float(snap.save_version) < 1:
			return "save_version must be a positive whole number"
		if float(snap.save_version) > version: return "save is from a newer game version"
	for path in ["match.advisor_rng_state", "special_orders.rng_state", "decisions.rng_state"]:
		var state := _at(snap, path)
		if state[0] and state[1] != null and not (_number(state[1]) or (state[1] is String and str(state[1]).is_valid_int())):
			return path + " must be a number or decimal integer string"
	for path in ["meta", "turn", "match", "stockpile", "loans", "construction", "market", "special_orders", "production", "cost_solver", "company_rankings", "events", "modifiers", "decisions", "solvency", "briefing", "victory", "policy", "telemetry", "infrastructure", "roads"]:
		if snap.has(path) and not snap[path] is Dictionary: return path + " must be an object"
	for path in FIELDS:
		var found := _at(snap, path)
		if not found[0]: continue
		if not found[1] is Dictionary: return path + " must be an object"
		var data: Dictionary = found[1]
		for kind in FIELDS[path]:
			for key in FIELDS[path][kind]:
				if not data.has(key): continue
				var value: Variant = data[key]
				if not _kind(value, kind): return path + "." + key + " must be " + kind
				if kind == "array":
					for item in value:
						var expected := "number" if key in NUMERIC_ARRAYS else ("string" if key in STRING_ARRAYS else "dictionary")
						if not _kind(item, expected): return path + "." + key + " has an invalid item"
	for path in RECORD_MAPS + NUMBER_MAPS:
		var found := _at(snap, path)
		if not found[0]: continue
		if not found[1] is Dictionary: return path + " must be an object"
		for item in found[1].values():
			if not _kind(item, "dictionary" if path in RECORD_MAPS else "number"):
				return path + " has an invalid entry"
	var turn: Dictionary = snap.get("turn", {})
	if turn.has("current_turn") and (not _number(turn.current_turn) or float(turn.current_turn) != floorf(float(turn.current_turn)) or float(turn.current_turn) < 1 or float(turn.current_turn) > 1000000):
		return "turn.current_turn is outside the supported range"
	var match_data: Dictionary = snap.get("match", {})
	if match_data.has("money") and absf(float(match_data.money)) > 1.0e15:
		return "match.money is outside the supported range"
	if match_data.has("labour_satisfaction") and absf(float(match_data.labour_satisfaction)) > 100.0:
		return "match.labour_satisfaction is outside the supported range"
	if match_data.has("work_week_hours") and not int(match_data.work_week_hours) in [35, 40, 45, 50]:
		return "match.work_week_hours must be 35, 40, 45 or 50"
	var rules: Dictionary = match_data.get("ruleset", {})
	if rules.has("speed_turns") and (float(rules.speed_turns) != floorf(float(rules.speed_turns)) or float(rules.speed_turns) < 1 or float(rules.speed_turns) > 1000000):
		return "ruleset.speed_turns is outside the supported range"
	var buildings: Dictionary = match_data.get("buildings", {})
	var tile_ids := {}
	for id in Catalog.all_tile_ids(): tile_ids[str(id)] = true
	for id in buildings:
		var b: Dictionary = buildings[id]
		if b.has("instance_id") and b.instance_id != str(id): return "building instance ID does not match its key"
		error = _building(b, tile_ids, from_disk or demo, demo)
		if error != "": return "building " + str(id) + ": " + error
	error = _stockpile(snap.get("stockpile", {}), tile_ids, from_disk or demo, demo)
	if error != "": return error
	error = _infrastructure(snap.get("infrastructure", {}), tile_ids, from_disk)
	if error != "": return error
	error = _roads(snap.get("roads", {}))
	if error != "": return error
	error = _economic_records(snap, tile_ids, from_disk or demo, demo)
	if error != "": return error
	if demo: return _demo_policy(match_data, turn)
	return ""


func _tree(value: Variant, path: String, depth: int) -> String:
	_nodes += 1
	if _nodes > MAX_NODES or depth > MAX_DEPTH: return "save is too large or deeply nested"
	if value is Dictionary or value is Array:
		if value.size() > MAX_COLLECTION: return path + " contains too many entries"
		for key in value:
			var child: Variant = value[key] if value is Dictionary else key
			# Native snapshots may carry interned text and coordinate keys; JSON turns
			# text keys into Strings. Neither case permits objects or executable values.
			if value is Dictionary and not (key is String or key is StringName or key is int or key is Vector2i): return path + " has an invalid key (" + type_string(typeof(key)) + ")"
			if (key is String or key is StringName) and str(key).length() > MAX_STRING: return path + " contains an oversized key"
			var error := _tree(child, path, depth + 1)
			if error != "": return error + (" at " + str(key).left(80) if value is Dictionary else " in an array item")
	elif value is String or value is StringName:
		if str(value).length() > MAX_STRING: return path + " contains an oversized string"
	elif value is float:
		if not is_finite(value): return path + " contains a non-finite number"
	elif value is Vector2 or value is Vector2i:
		if not is_finite(float(value.x)) or not is_finite(float(value.y)): return path + " contains invalid coordinates"
	elif value != null and not (value is int or value is bool):
		return path + " contains an unsupported value"
	return ""


func _at(snap: Dictionary, path: String) -> Array:
	var value: Variant = snap
	for key in path.split("."):
		if not value is Dictionary or not value.has(key): return [false, null]
		value = value[key]
	return [true, value]


func _number(value: Variant) -> bool:
	return value is int or value is float


func _kind(value: Variant, kind: String) -> bool:
	match kind:
		"dictionary": return value is Dictionary
		"array": return value is Array
		"number": return _number(value)
		"string": return value is String or value is StringName
		"bool": return value is bool
	return false


func _building(b: Dictionary, tiles: Dictionary, check_ids: bool, demo: bool) -> String:
	for key in ["building_id", "recipe_id", "tile_id", "instance_id", "owner"]:
		if b.has(key) and not b[key] is String: return key + " must be text"
	if b.has("level") and (not _number(b.level) or float(b.level) != floorf(float(b.level)) or float(b.level) < 1 or float(b.level) > 3): return "level must be between 1 and 3"
	if not check_ids: return ""
	var bid := str(b.get("building_id", ""))
	if bid == "" or Catalog.get_building(bid).is_empty(): return "unknown building ID " + bid
	if not tiles.has(str(b.get("tile_id", ""))): return "unknown tile ID"
	if demo and DemoBuild.is_gated_building(bid): return "building is not available in this demo"
	var rid := str(b.get("recipe_id", ""))
	if rid != "":
		var recipe := Catalog.get_recipe(rid)
		if recipe.is_empty(): return "unknown recipe ID " + rid
		if str(recipe.get("building_id", "")) != bid: return "recipe does not belong to this building"
	return ""


func _stockpile(data: Dictionary, tiles: Dictionary, check_ids: bool, demo: bool) -> String:
	for tile in data.get("by_tile", {}):
		if check_ids and not tiles.has(str(tile)): return "stockpile has an unknown tile"
		var goods: Variant = data.by_tile[tile]
		if not goods is Dictionary: return "stockpile tile must contain goods quantities"
		for gid in goods:
			if not _number(goods[gid]) or float(goods[gid]) != floorf(float(goods[gid])) or float(goods[gid]) < 0: return "stockpile has an invalid quantity"
			if check_ids and Catalog.get_good(str(gid)).is_empty(): return "stockpile has an unknown good ID"
			if demo and DemoBuild.RECYCLING_GOOD_IDS.has(str(gid)) and float(goods[gid]) > 0: return "stockpile contains goods unavailable in this demo"
	return ""


func _infrastructure(data: Dictionary, tiles: Dictionary, check_ids: bool) -> String:
	for tile in data:
		if check_ids and not tiles.has(str(tile)): return "infrastructure has an unknown tile"
		var entry: Variant = data[tile]
		if entry is Array:
			for item in entry:
				if not item is String: return "infrastructure list must contain names"
		elif entry is Dictionary:
			for key in ["present", "infrastructure_present"]:
				if entry.has(key):
					if not entry[key] is Array: return "infrastructure names must be an array"
					for item in entry[key]:
						if not item is String: return "infrastructure list must contain names"
			for key in ["levels", "infrastructure_levels"]:
				if entry.has(key):
					if not entry[key] is Dictionary: return "infrastructure levels must be an object"
					for level in entry[key].values():
						if not _number(level) or float(level) != floorf(float(level)) or float(level) < 1 or float(level) > 3: return "infrastructure level must be between 1 and 3"
		else: return "infrastructure entry has an invalid shape"
	return ""


func _pair(value: Variant) -> bool:
	return value is Array and value.size() == 2 and _number(value[0]) and _number(value[1]) and absf(float(value[0])) <= 200000 and absf(float(value[1])) <= 200000


func _roads(data: Dictionary) -> String:
	var network: Dictionary = data.get("network", {})
	var nodes: Dictionary = network.get("nodes", {})
	for node in nodes.values():
		if not node.get("kind") is String: return "road node is missing its kind"
		for key in ["pos", "tile", "tangent"]:
			if not _pair(node.get(key)): return "road node has invalid " + key
	for edge in network.get("edges", {}).values():
		for key in ["a", "b", "tier", "state"]:
			if not edge.get(key) is String: return "road edge is missing " + key
		if not nodes.has(edge.a) or not nodes.has(edge.b): return "road edge refers to a missing node"
		if not _number(edge.get("planned_turn")): return "road edge has no planned turn"
		for key in ["geometry", "tiles"]:
			if not edge.get(key) is Array: return "road edge has invalid " + key
			for point in edge[key]:
				if not _pair(point): return "road edge contains invalid coordinates"
		if not edge.get("bridges") is Array: return "road edge has invalid bridges"
		for bridge in edge.bridges:
			if not bridge is Dictionary or not _pair(bridge.get("point")) or not _pair(bridge.get("tangent")): return "road bridge has invalid coordinates"
	for order in data.get("works", {}).get("orders", []):
		for key in ["id", "salt", "turn"]:
			if not _number(order.get(key)): return "road order is missing " + key
		for key in ["tile_id", "state", "attach_id", "tier", "edge_id"]:
			if not order.get(key) is String: return "road order is missing " + key
		for key in ["start", "goal", "coord"]:
			if not _pair(order.get(key)): return "road order has invalid " + key
	return ""


func _demo_policy(data: Dictionary, turn: Dictionary) -> String:
	var allowed := DemoBuild.START_IDS + ["tutorial", "default", ""]
	var scenario := str(data.get("scenario_name", "")).to_lower().replace(" ", "_")
	if scenario == "metals_magnate": scenario = "metal_magnate"
	if scenario not in allowed: return "this scenario is not available in the demo"
	var rules: Dictionary = data.get("ruleset", {})
	if rules.has("start_id") and str(rules.start_id) not in allowed: return "this start is not available in the demo"
	if rules.has("speed_turns") and (not _number(rules.speed_turns) or float(rules.speed_turns) != 100): return "the demo supports 100-turn games"
	if rules.has("difficulty") and (not rules.difficulty is String or str(rules.difficulty).to_lower() != "normal"): return "the demo supports Normal difficulty"
	if str(rules.get("name", "standard")) not in ["standard", "tutorial"]: return "this ruleset is not available in the demo"
	if rules.has("victory_set") and str(rules.victory_set) != "demo_itch": return "this victory ruleset is not available in the demo"
	if int(turn.get("current_turn", 1)) > 101 or (int(turn.get("current_turn", 1)) > 100 and not bool(turn.get("game_ended", false))): return "this save is past the demo turn limit"
	for key in ["recruited_advisor_ids", "permanent_advisor_ids"]:
		for advisor in data.get(key, []):
			if advisor not in ["andrew", "vera", "gerald"]: return "an advisor is not available in this demo"
	var seats: Dictionary = data.get("advisor_seats", {})
	for seat in seats:
		if seat not in ["cfo", "coo", "technical_director", "chief_markets"]: return "an advisor seat is not available in this demo"
		if seats[seat] not in ["andrew", "vera", "gerald", ""]: return "an advisor is not available in this demo"
	var slots: Variant = data.get("max_advisor_slots", 2)
	if not _number(slots) or float(slots) != floorf(float(slots)) or float(slots) < 2 or float(slots) > 5: return "invalid advisor slot count"
	for title in data.get("unlocked_titles", {}):
		var current := "Multimodal Containerized Freight" if title == "Containerized Freight" else str(title)
		var definition: Dictionary = ResearchState.get_unlock_def(current)
		if definition.is_empty() or DemoBuild.is_gated_research(str(definition.get("category", "")), str(definition.get("action", ""))):
			return "research is not available in this demo"
	return ""


func _economic_records(snap: Dictionary, tiles: Dictionary, check_ids: bool, demo: bool) -> String:
	for record in snap.get("modifiers", {}).get("modifiers", {}).values():
		for key in ["domain", "target"]:
			if not record.get(key) is String: return "modifier is missing " + key
		for key in ["mult", "add", "pct"]:
			if not _number(record.get(key)): return "modifier has invalid " + key
		if record.has("target_match") and not record.target_match is Dictionary: return "modifier target must be an object"
		for key in ["expires_turn", "added_turn"]:
			if record.has(key) and not _number(record[key]): return "modifier has invalid " + key
	for goods in snap.get("match", {}).get("deposit_remaining", {}).values():
		for quantity in goods.values():
			if not _number(quantity) or float(quantity) < 0: return "deposit ledger has an invalid quantity"
	for loan in snap.get("loans", {}).get("loans", []):
		for key in ["id", "principal_initial", "principal_remaining", "payment_per_turn", "turns_remaining", "interest_paid", "interest_rate", "grace_remaining"]:
			if loan.has(key) and not _number(loan[key]): return "loan has invalid " + key
	var projects: Dictionary = snap.get("construction", {}).get("projects", {})
	for project in projects.values():
		var error := _building(project, tiles, check_ids, demo)
		if error != "": return "construction project: " + error
		for key in ["turns_remaining", "construction_duration", "reserved_space", "level", "build_cost"]:
			if project.has(key) and not _number(project[key]): return "construction project has invalid " + key
		for key in ["required_materials", "missing_materials"]:
			if project.has(key):
				if not project[key] is Dictionary: return "construction materials must be an object"
				for qty in project[key].values():
					if not _number(qty) or float(qty) < 0: return "construction has invalid material quantities"
	var services: Dictionary = snap.get("match", {}).get("middleman_service", {}).get("buildings", {})
	for service in services.values():
		for key in ["inputs", "outputs", "input_modes", "output_modes", "bridge"]:
			if service.has(key) and not service[key] is Dictionary: return "provider service has invalid " + key
	var shipments: Array = snap.get("match", {}).get("pending_transport_shipments", [])
	for shipment in shipments:
		for key in ["source_tile", "destination_tile"]:
			if shipment.has(key) and not shipment[key] is String: return "shipment has invalid " + key
		for key in ["remaining", "duration", "transport_cost", "purchase_cost"]:
			if shipment.has(key) and not _number(shipment[key]): return "shipment has invalid " + key
		if shipment.has("items"):
			if not shipment.items is Array: return "shipment items must be an array"
			for item in shipment.items:
				if not item is Dictionary: return "shipment has an invalid item"
				if not item.get("good_id", "") is String or not _number(item.get("qty", 0)) or float(item.get("qty", 0)) < 0: return "shipment has an invalid good or quantity"
				var gid := str(item.get("good_id", ""))
				if check_ids and gid != "power" and Catalog.get_good(gid).is_empty(): return "shipment contains an unknown good"
				if demo and DemoBuild.RECYCLING_GOOD_IDS.has(gid): return "shipment contains goods unavailable in this demo"
	for level in snap.get("stockpile", {}).get("warehouse_levels", {}).values():
		if float(level) != floorf(float(level)) or float(level) < 0 or float(level) > 3: return "warehouse level must be between 0 and 3"
	for path in ["market.net_history", "market.price_history", "stockpile.fill_history"]:
		var found := _at(snap, path)
		if not found[0]: continue
		for entries in found[1].values():
			if not entries is Array: return path + " has an invalid history"
			for point in entries:
				if path != "market.price_history":
					if not _number(point): return path + " has an invalid number"
				elif not point is Dictionary: return path + " has an invalid point"
				else:
					for key in ["turn", "price", "sale", "sold", "bought", "cost_basis"]:
						if point.has(key) and point[key] != null and not _number(point[key]): return path + " has an invalid " + key
	return ""


static func normalize_demo(snapshot: Dictionary) -> Dictionary:
	var snap := snapshot.duplicate(true)
	var data: Dictionary = snap.get("match", {})
	var rules: Dictionary = data.get("ruleset", {}).duplicate(true)
	rules["speed_turns"] = 100
	rules["difficulty"] = "normal"
	rules["victory_set"] = "demo_itch"
	rules["survey_all_tiles"] = true
	data["ruleset"] = rules
	data["all_seats_unlocked"] = false
	data["max_advisor_slots"] = mini(int(data.get("max_advisor_slots", 2)), 3)
	var surveyed := {}
	for tile in Catalog.all_tile_ids(): surveyed[str(tile)] = true
	data["surveyed_tiles"] = surveyed
	data["partially_surveyed_tiles"] = {}
	data["surveying_in_progress"] = {}
	data["surveying_reveal"] = {}
	snap["match"] = data
	return snap
