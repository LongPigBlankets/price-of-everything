extends Node
## Windowed screenshot of the decision modal (docs/decision-events-spec.md §7):
## three advocate strips (portrait + stance + loyalty stakes), a gated choice,
## and the low-cash loan note. Writes /tmp/poe_decision_shot.png.
##   "$GODOT_BIN" --path . res://tools/decision_shot.tscn --quit-after 900

func _ready() -> void:
	# Small window: proves the modal stays on-screen (choices wrap, card scrolls) —
	# a wide fixed card once ran off a narrow window and soft-locked the game.
	get_window().size = Vector2i(1024, 680)
	var game: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(game)
	await _settle(140)

	var cam := get_viewport().get_camera_2d()
	if cam != null:
		cam.edge_pan_enabled = false

	# Seat a tenured board so all three union_demands advocates speak, and run the
	# cash low so the mediator choice (£40) shows the distress-loan note.
	for aid: String in ["vera", "tom", "eleanor"]:
		if not MatchState.permanent_advisor_ids.has(aid):
			MatchState.permanent_advisor_ids.append(aid)
		if not MatchState.recruited_advisor_ids.has(aid):
			MatchState.recruited_advisor_ids.append(aid)
		MatchState.advisor_hired_turn[aid] = int(TurnManager.current_turn) - 5
		MatchState.advisor_loyalty[aid] = 0.0
	MatchState.advisor_seats = {"cfo": "vera", "coo": "tom", "hr_director": "eleanor"}
	MatchState.money = 25.0
	MatchState.money_changed.emit(MatchState.money)

	DecisionState.enabled = true
	DecisionState.auto_resolve = false
	DecisionState.pending = {
		"uid": "shot_1", "def_id": "union_demands",
		"target": {"scope": "building_type", "building_id": "b_001", "name": "Coal Mine"},
		"turn_drawn": int(TurnManager.current_turn),
	}
	DecisionState._maybe_present()
	await _settle(20)

	get_viewport().get_texture().get_image().save_png("/tmp/poe_decision_shot.png")
	print("[decision_shot] wrote /tmp/poe_decision_shot.png")
	get_tree().quit(0)

func _settle(n: int) -> void:
	for _i in n:
		await get_tree().process_frame
