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

	TurnManager.current_turn = 89
	PolicyState._arm_carbon_notice()   # re-arm for the jumped turn (reservation at 89)
	TurnManager.fast_mode = true
	TurnManager.commit_turn()
	if TurnManager.is_resolving:
		await TurnManager.turn_resolution_completed
	await _settle(30)

	print("[notice_shot] turn=%d pending=%s blocked=%s" % [
		TurnManager.current_turn,
		str(DecisionState.has_pending()),
		str(DecisionState.has_pending())])
	await _shot("/tmp/poe_policy_notice.png")

	# Prove the "Understood" click unblocks the turn.
	if not DecisionState.pending_queue.is_empty():
		var uid := str((DecisionState.pending_queue[0] as Dictionary).get("uid", ""))
		var err: String = DecisionState.resolve("understood", uid)
		print("[notice_shot] resolve('understood') -> '%s' pending_after=%s" % [err, str(DecisionState.has_pending())])
	get_tree().quit(0)

func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("[notice_shot] saved ", path)

func _settle(frames: int) -> void:
	for _i in frames:
		await get_tree().process_frame
