extends Node
## Dev tool: verify the carbon-levy "Understood" notice. Jumps to turn 89, commits one
## turn (the reservation fires in turn 89's NARRATIVE), and screenshots turn 90's
## auto-expanded Turn Briefing showing the blocking notice. Needs a window:
##   "$GODOT_BIN" --path . res://tools/policy_notice_shot.tscn --quit-after 1200

func _ready() -> void:
	var game: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(game)
	await _settle(140)
	var cam := get_viewport().get_camera_2d()
	if cam != null:
		cam.edge_pan_enabled = false

	TurnManager.fast_mode = true
	# Andrew's turn-3 offer would draw on the first commit here and then block EVERY commit
	# after it (an unresolved decision stops the turn), so the tool sat at turn 84 and shot the
	# same offer three times instead of the three notices. This run is about policy, not the
	# founder arc: mark it fired so it never draws.
	DecisionState._fired_once["family_friend"] = true

	# 0a. Election news at turn 84, then the insider tip at 86 (Rufus, 3/3 Influencing,
	# seated in Government Affairs).
	MatchState.advisor_seats["government_affairs"] = "rufus"
	TurnManager.current_turn = 83
	TurnManager.commit_turn()
	if TurnManager.is_resolving:
		await TurnManager.turn_resolution_completed
	await _settle(20)
	TurnBriefing.expand()
	await _settle(16)
	print("[notice_shot] election: turn=%d" % TurnManager.current_turn)
	await _shot("/tmp/poe_policy_election.png")
	TurnBriefing.collapse()
	await _settle(6)

	# 0b. Two more turns → the tip fires when turn 86 opens.
	for _i in 2:
		TurnManager.commit_turn()
		if TurnManager.is_resolving:
			await TurnManager.turn_resolution_completed
	await _settle(20)
	TurnBriefing.expand()
	await _settle(16)
	print("[notice_shot] tip: turn=%d fired=%s" % [TurnManager.current_turn, str(PolicyState._insider_tip_fired)])
	await _shot("/tmp/poe_policy_insider_tip.png")
	TurnBriefing.collapse()
	await _settle(6)

	# 1. Carbon levy notice at turn 90 (reserved for turn 89's NARRATIVE).
	TurnManager.current_turn = 89
	PolicyState._arm_notices()
	TurnManager.commit_turn()
	if TurnManager.is_resolving:
		await TurnManager.turn_resolution_completed
	await _settle(30)
	print("[notice_shot] carbon: turn=%d pending=%s" % [TurnManager.current_turn, str(DecisionState.has_pending())])
	await _shot("/tmp/poe_policy_notice.png")
	if not DecisionState.pending_queue.is_empty():
		var uid := str((DecisionState.pending_queue[0] as Dictionary).get("uid", ""))
		var err: String = DecisionState.resolve("understood", uid)
		print("[notice_shot] carbon resolve -> '%s' pending_after=%s" % [err, str(DecisionState.has_pending())])
	await _settle(10)

	# 2. Green subsidy notice at turn 100 (reserved for turn 99's NARRATIVE).
	TurnManager.current_turn = 99
	PolicyState._arm_notices()
	TurnManager.commit_turn()
	if TurnManager.is_resolving:
		await TurnManager.turn_resolution_completed
	await _settle(30)
	print("[notice_shot] subsidy: turn=%d pending=%s" % [TurnManager.current_turn, str(DecisionState.has_pending())])
	await _shot("/tmp/poe_policy_subsidy_notice.png")
	if not DecisionState.pending_queue.is_empty():
		var uid2 := str((DecisionState.pending_queue[0] as Dictionary).get("uid", ""))
		var err2: String = DecisionState.resolve("understood", uid2)
		print("[notice_shot] subsidy resolve -> '%s' pending_after=%s" % [err2, str(DecisionState.has_pending())])
	await _settle(10)

	# 3. Subsidy wind-down warning at turn 180 (reserved for turn 179's NARRATIVE).
	TurnManager.current_turn = 179
	PolicyState._arm_notices()
	TurnManager.commit_turn()
	if TurnManager.is_resolving:
		await TurnManager.turn_resolution_completed
	await _settle(30)
	print("[notice_shot] wind-down: turn=%d pending=%s" % [TurnManager.current_turn, str(DecisionState.has_pending())])
	await _shot("/tmp/poe_policy_end_notice.png")
	if not DecisionState.pending_queue.is_empty():
		var uid3 := str((DecisionState.pending_queue[0] as Dictionary).get("uid", ""))
		var err3: String = DecisionState.resolve("understood", uid3)
		print("[notice_shot] wind-down resolve -> '%s' pending_after=%s" % [err3, str(DecisionState.has_pending())])
	get_tree().quit(0)

func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("[notice_shot] saved ", path)

func _settle(frames: int) -> void:
	for _i in frames:
		await get_tree().process_frame
