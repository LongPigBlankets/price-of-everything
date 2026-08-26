extends Node2D
## Does the mission module show on TURN 1 for the demo starts, or only from turn 2?
##
## This is the REAL boot path, not a stub: it sets the pending start snapshot the way New Game
## does, then instantiates main.tscn, which applies it during finish_build and emits
## match_loaded — the hook MiniQuest now resolves the chain on. Then it reads the actual top-bar
## module's `visible` while TurnManager is still on turn 1, having ended no turn.
##
##   Godot --path . res://tools/turn_one_shot.tscn --quit-after 8000
##
## Windowed (headless cannot lay out/paint the bar). One start per run — the pending snapshot is
## consumed once — so it is driven by `args`, defaulting to metal_magnate.

var _wm


func _ready() -> void:
	var start_id := "metal_magnate"
	if OS.get_cmdline_user_args().size() > 0:
		start_id = OS.get_cmdline_user_args()[0]
	# Pretend New Game just prepared this start, so main.tscn's apply_pending picks it up. The
	# start_id override is what New Game's panel injects (new_game_panel.gd) and what
	# expand_start_config merges into the ruleset — without it ruleset.start_id is empty, which
	# is a fault of this harness, not the game.
	SaveLoad.prepare_new_game("res://data/starts/%s.json" % start_id,
		{"ruleset": {"start_id": start_id, "tutorial_enabled": false}})
	var packed := load("res://scenes/main.tscn") as PackedScene
	_wm = packed.instantiate()
	add_child(_wm)
	await _settle(220)   # let the world build and apply_pending fire

	var bar: Node = _find_topbar(_wm)
	var qb = bar.get("_quest_btn") if bar != null else null
	var want := "magnate" if start_id == "metal_magnate" else "glass"
	# No turn is ended anywhere in this harness, and nothing calls _refresh_quest by hand — this
	# reads the state a player sees the instant the board finishes loading, still on turn 1.
	print("[TURN1BOOT] start=%s turn=%d ruleset.start_id=%s" %
		[start_id, int(TurnManager.current_turn), str(MatchState.ruleset.get("start_id", ""))])
	print("[TURN1BOOT] MiniQuest.chain=%s available=%s | module visible=%s (want chain=%s, visible on turn 1) %s" %
		[MiniQuest.chain, str(MiniQuest.is_available()),
		str(qb.visible) if qb != null else "<no module>", want,
		"OK" if MiniQuest.chain == want and qb != null and qb.visible and int(TurnManager.current_turn) == 1
			else "WRONG"])
	get_tree().quit()


func _find_topbar(n: Node) -> Node:
	if n.get_script() != null and String(n.get_script().resource_path).ends_with("top_bar.gd"):
		return n
	for c in n.get_children():
		var f: Node = _find_topbar(c)
		if f != null:
			return f
	return null


func _settle(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame
