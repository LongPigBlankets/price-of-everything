extends Node
## Windowed screenshots of the Turn Briefing (docs/turn-briefing-panel-spec.md):
##   /tmp/poe_briefing_panel.png — expanded: 2 decisions + alerts + news + info
##   /tmp/poe_briefing_strip.png — collapsed strip under the top bar
##   "$GODOT_BIN" --path . res://tools/briefing_shot.tscn --quit-after 900

func _ready() -> void:
	var game: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(game)
	await _settle(140)
	var cam := get_viewport().get_camera_2d()
	if cam != null:
		cam.edge_pan_enabled = false

	# Seat a tenured board so advocates speak on the decision cards.
	for aid: String in ["vera", "tom", "eleanor"]:
		if not MatchState.permanent_advisor_ids.has(aid):
			MatchState.permanent_advisor_ids.append(aid)
		if not MatchState.recruited_advisor_ids.has(aid):
			MatchState.recruited_advisor_ids.append(aid)
		MatchState.advisor_hired_turn[aid] = int(TurnManager.current_turn) - 5
		MatchState.advisor_loyalty[aid] = 0.0
	MatchState.advisor_seats = {"cfo": "vera", "coo": "tom", "hr_director": "eleanor"}

	# Two queued decisions (the mini-menu case).
	DecisionState.enabled = true
	DecisionState.pending_queue = [
		{"uid": "shot_1", "def_id": "union_demands",
			"target": {"scope": "building_type", "building_id": "b_001", "name": "Coal Mine"},
			"turn_drawn": int(TurnManager.current_turn)},
		{"uid": "shot_2", "def_id": "brokers_offer",
			"target": {"scope": "company", "good_id": "g_001", "name": "Coal"},
			"turn_drawn": int(TurnManager.current_turn)},
	]

	# Starved buildings for the Alerts section, then a bankruptcy-grade runway
	# (money set AFTER the builds so their collateral doesn't lift it back out).
	var s1 := MatchState.add_building("b_002", "r_003", "tile_6_9", MatchState.LOCAL_PLAYER)
	var s2 := MatchState.add_building("b_002", "r_005", "tile_7_9", MatchState.LOCAL_PLAYER)
	Production.missing_by_building = {
		s1: [{"internal_name": "power"}],
		s2: [{"internal_name": "iron_ore"}],
	}
	MatchState.money = -(LoanState.available_capacity() + 40.0)

	# News + info items via the bell (single source of truth).
	EventScheduler.emit_event({"kind": "carbon_announcement", "severity": "warning",
		"title": "Carbon tax announced",
		"body": "Parliament will levy a charge per unit of coal and crude burned, effective turn 90. Green generation is exempt. Coal-heavy operations have 39 turns to adapt.",
		"persistent": true})
	EventScheduler.emit_event({"kind": "research_unlocked", "severity": "info",
		"title": "Unlocked: Fractional Distillation",
		"body": "You can now build the Oil Refinery and lay Reinforced Pipeline for hazardous liquids.",
		"persistent": false})
	EventScheduler.emit_event({"kind": "bridge_loan", "severity": "info",
		"title": "Bridge loan taken — £300",
		"body": "Your balance went into the red, so £300 was borrowed automatically to bridge you until next turn. Loan capacity left: £600.",
		"persistent": false})

	TurnBriefing.expand()
	await _settle(20)
	get_viewport().get_texture().get_image().save_png("/tmp/poe_briefing_panel.png")
	print("[briefing_shot] wrote /tmp/poe_briefing_panel.png")

	TurnBriefing.collapse()
	await _settle(10)
	get_viewport().get_texture().get_image().save_png("/tmp/poe_briefing_strip.png")
	print("[briefing_shot] wrote /tmp/poe_briefing_strip.png")
	get_tree().quit(0)

func _settle(n: int) -> void:
	for _i in n:
		await get_tree().process_frame
