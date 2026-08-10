extends Node
## Dev tool: verify Andrew Keeler's departure is actually SEEN. He used to vanish from the
## council with nothing but a bell entry, which the owner never noticed. Seats him, runs his
## tenure out, and screenshots the turn the chair empties.
##   "$GODOT_BIN" --path . res://tools/founder_departs_shot.tscn --quit-after 1200

func _ready() -> void:
	var game: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(game)
	await _settle(140)
	var cam := get_viewport().get_camera_2d()
	if cam != null:
		cam.edge_pan_enabled = false
	TurnManager.fast_mode = true

	# Take the real arc, not a shortcut: run to his turn-3 offer and answer it, so the seat and
	# the tenure clock are set the way a player's game sets them.
	for _i in 4:
		if _pending_ids().has("family_friend"):
			break
		TurnManager.commit_turn()
		if TurnManager.is_resolving:
			await TurnManager.turn_resolution_completed
		await _settle(8)
	var offer_uid := _uid_of("family_friend")
	print("[founder_shot] offer at turn %d -> resolve('coo'): '%s'" % [
		TurnManager.current_turn, DecisionState.resolve("coo", offer_uid)])
	print("[founder_shot] seated: seat=%s leaves_turn=%d" % [
		MatchState.founder_seat, MatchState.founder_leaves_turn])

	# Stand on his last turn so this commit retires him during NARRATIVE.
	TurnManager.current_turn = MatchState.founder_leaves_turn
	TurnBriefing.collapse()
	await _settle(10)

	TurnManager.commit_turn()
	if TurnManager.is_resolving:
		await TurnManager.turn_resolution_completed
	await _settle(30)

	print("[founder_shot] turn=%d seat_now='%s' pending=%s expanded=%s" % [
		TurnManager.current_turn, MatchState.founder_seat, str(_pending_ids()),
		str(TurnBriefing.expanded)])
	await _shot("res://founder_departs_shot.png")

	# It must also BLOCK the turn: an unresolved decision is what makes the notice unmissable.
	print("[founder_shot] blocks_end_turn=%s" % str(DecisionState.has_pending()))

	var err: String = DecisionState.resolve("understood", _uid_of("founder_departs"))
	print("[founder_shot] resolve -> '%s' pending_after=%s" % [err, str(DecisionState.has_pending())])
	await _settle(10)
	await _shot("res://founder_departs_after.png")
	get_tree().quit(0)


func _pending_ids() -> Array:
	var ids: Array = []
	for d in DecisionState.pending_queue:
		ids.append(str((d as Dictionary).get("def_id", "")))
	return ids

func _uid_of(def_id: String) -> String:
	for d in DecisionState.pending_queue:
		if str((d as Dictionary).get("def_id", "")) == def_id:
			return str((d as Dictionary).get("uid", ""))
	return ""


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("[founder_shot] saved ", path)

func _settle(frames: int) -> void:
	for _i in frames:
		await get_tree().process_frame
