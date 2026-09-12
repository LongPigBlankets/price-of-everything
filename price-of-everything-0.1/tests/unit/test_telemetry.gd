extends "res://tests/test_base.gd"
## Telemetry rows and interaction counts.

const FEATURE := "telemetry"
## Tests that also belong to other features (run under any of their tags).
const TAGS := {
	"_test_telemetry_schema3_row": ["production", "telemetry"],
}

func _test_telemetry_schema3_row() -> void:
	# Schema 3 adds the diagnosis fields the first playtest wanted and could not answer:
	# what the player owned, why each building was or wasn't running, and where the money
	# went. See docs/early-game-onboarding-spec.md §7.
	MatchState.reset()
	MatchState.scenario_name = "metal_magnate"
	Production.last_turn_run.clear()
	Production.missing_by_building.clear()
	Production.blocked_reason_by_building.clear()
	BuildingState.buildings["inst_tel_run"] = {
		"instance_id": "inst_tel_run", "building_id": "b_001",
		"recipe_id": "r_001", "tile_id": "tile_3_3", "level": 2,
	}
	BuildingState.buildings["inst_tel_dark"] = {
		"instance_id": "inst_tel_dark", "building_id": "b_002",
		"recipe_id": "r_005", "tile_id": "tile_3_4", "level": 1,
	}
	Production.last_turn_run["inst_tel_run"] = true
	Production.missing_by_building["inst_tel_dark"] = [
		{"good_id": "power", "internal_name": "power", "need": 40, "have": 0}]

	var summary := {
		"money_in": 500.0, "money_out": 300.0,
		"goods_sales_revenue": 500.0, "power_sales_revenue": 0.0,
		"goods_purchased_cost": 120.0, "labour_paid": 40.0, "maintenance_paid": 22.0,
		"taxes_paid": 8.0, "produced": {}, "power_supply": 600, "power_demand": 200,
	}
	var row: Dictionary = TelemetryState._build_row(summary)

	var roster: Array = row.get("buildings_list", [])
	var states: Array = row.get("building_states", [])
	_check(roster.size() == 2 and states.size() == roster.size()
		and int(row.get("buildings", 0)) == roster.size(),
		"schema 3: roster and states are index-aligned and match the building count")
	var idx_run: int = roster.find("mine(l2)")
	_check(idx_run >= 0, "schema 3: roster names buildings as internal_name(level)")
	_check(idx_run >= 0 and str(states[idx_run]) == "running",
		"schema 3: a building that ran reports running")
	var idx_dark: int = roster.find("smelter(l1)") if roster.find("smelter(l1)") >= 0 else (1 - idx_run)
	_check(str(states[idx_dark]) == "no_power",
		"schema 3: a building missing power reports no_power, not a generic stall")

	var costs: Dictionary = row.get("costs", {})
	_check(is_equal_approx(float(costs.get("inputs", 0.0)), 120.0)
		and is_equal_approx(float(costs.get("labour", 0.0)), 40.0)
		and is_equal_approx(float(costs.get("tax", 0.0)), 8.0),
		"schema 3: the cost breakdown carries the money_out components")
	var costs_total: float = 0.0
	for k in costs:
		costs_total += float(costs[k])
	_check(costs_total <= float(summary.get("money_out", 0.0)) + 0.01,
		"schema 3: the cost breakdown sums into money_out (never on top of it)")

	# Freight split: seven positional values that reconcile against the transport line, so the
	# sheet never has to infer the composition again (it did, once, by hand).
	var freight := {
		"money_in": 0.0, "money_out": 0.0, "produced": {},
		"transport_paid": 61.50,
		"transport_breakdown": {
			"port_inbound": 15.0, "port_outbound": 20.0, "roads": 14.5,
			"rail": 8.0, "pipes": 3.0, "reinf_pipes": 1.0,
		},
	}
	var freight_row: Dictionary = TelemetryState._build_row(freight)
	var split: Array = freight_row.get("transport", [])
	_check(split.size() == TelemetryState.TRANSPORT_LINES.size(),
		"schema 3: the freight split carries one value per transport line")
	var split_total: float = 0.0
	for v in split:
		split_total += float(v)
	_check(is_equal_approx(split_total, float(freight.get("transport_paid", 0.0))),
		"schema 3: the freight split reconciles against transport_paid (%.2f)" % split_total)
	_check(is_equal_approx(float(split[0]), 15.0) and is_equal_approx(float(split[1]), 20.0),
		"schema 3: import and export port charges land in their fixed positions")

	BuildingState.buildings.erase("inst_tel_run")
	BuildingState.buildings.erase("inst_tel_dark")
	Production.last_turn_run.clear()
	Production.missing_by_building.clear()

func _test_telemetry_interactions() -> void:
	var telemetry = load("res://scripts/telemetry_state.gd").new()
	telemetry.enabled = true
	telemetry._armed = true
	telemetry._run_id = "interaction-test"
	telemetry._session_id = "interaction-session"
	telemetry._interaction_checkpoint_queued = true # pure capture test: no disk or network
	telemetry._collect = false
	telemetry.track_interaction("search_used", "market_panel")
	_check(telemetry._events.is_empty(), "interaction telemetry: opt-out captures nothing")
	telemetry._collect = true
	telemetry.track_interaction("search_used", "market_panel")
	telemetry.track_interaction("good_encyclopedia_opened", "encyclopedia", "g_008")
	var event: Dictionary = telemetry._events[0]
	_check(int(event.turn) == int(TurnManager.current_turn) and event.interface == "market_panel", "interaction telemetry: records the action turn and interface")
	_check(not event.has("query") and not event.has("text"), "interaction telemetry: excludes search text")
	_check(telemetry._events[0].event_id != telemetry._events[1].event_id, "interaction telemetry: unique event identities")
	var counts: Dictionary = telemetry._interaction_counts(int(TurnManager.current_turn))
	_check(counts.search_used == 1 and counts.good_encyclopedia_opened == 1 and counts.research_panel_opened == 0, "interaction telemetry: explicit per-turn counts including zeros")
	_check(telemetry._interaction_counts(int(TurnManager.current_turn) + 1).search_used == 0, "interaction telemetry: does not move actions into the next turn")
	var saved: Dictionary = telemetry.export_state()
	_check(saved.events.size() == 2, "interaction telemetry: saves interactions for resumed runs")
	telemetry._events.clear()
	_check(saved.events.size() == 2, "interaction telemetry: save snapshot is independent")
	telemetry.import_state(saved)
	_check(telemetry._events.size() == 2, "interaction telemetry: restores interaction history")
	telemetry.free()
