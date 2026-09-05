extends Node
## Dev probe: run a demo start IDLE — no player actions, no cheats — to the demo's
## 100-turn cap, exactly as the New Game screen boots it (demo_itch policy timeline and
## victory set, Normal difficulty). Logs money, the start's key price, carbon-levy level,
## pending decisions (auto-answered, as a player clicking through), and victory progress.
## The floor a fumbling player experiences; pair with the e2e harness for the ceiling.
##   <godot> --headless --path . res://tools/demo_idle_probe.tscn --quit-after 6000 -- --start=metal_magnate

var _ended := ""

func _ready() -> void:
	var start_id := "metal_magnate"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--start="):
			start_id = a.trim_prefix("--start=")
	SaveLoad.prepare_new_game("res://data/starts/%s.json" % start_id, {"ruleset": {
		"start_id": start_id,
		"difficulty": "normal",
		"speed_turns": 100,
		"policy_timeline": "demo_itch",
		"victory_set": "demo_itch",
		"tutorial_enabled": false,
		"survey_all_tiles": true,
		"company_colour": "diesel_red",
	}})
	TurnManager.game_ended_signal.connect(func(reason: String) -> void: _ended = reason)
	var game: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(game)
	for _i in 200:
		await get_tree().process_frame
	var key_good := "iron_ingots" if start_id == "metal_magnate" else "glass"
	var gid := str(Catalog.get_good_by_internal_name(key_good).get("id", ""))
	print("[PROBE] %s ready: money=%.1f turn=%d tracks=%s" % [
		start_id, MatchState.money, TurnManager.current_turn, str(VictoryState.TRACK_ORDER)])
	for _i in range(100):
		if _ended != "":
			break
		# Answer pending decisions BEFORE committing, as a player must — a blocking
		# notice would otherwise refuse the commit and hang the await below.
		if DecisionState.has_pending():
			for v in DecisionState.pending_views():
				print("[PROBE] t%d decision pending: %s" % [
					TurnManager.current_turn, str((v as Dictionary).get("title", "?"))])
			DecisionState.auto_resolve_pending()
		TurnManager.commit_turn()
		await TurnManager.turn_resolution_completed
		var pts := 0.0
		for k in VictoryState.TRACK_ORDER:
			pts += float(VictoryState.track_best.get(k, 0.0)) * float(VictoryState.TRACK_MAX.get(k, 1000))
		if TurnManager.current_turn % 5 == 0 or _ended != "":
			print("[PROBE] t%03d money=%9.1f price(%s)=%7.2f levy_lvl=%d pts=%5.0f won=%s" % [
				TurnManager.current_turn, MatchState.money, key_good,
				MarketState.get_price(gid), PolicyState.co2_tax_level(TurnManager.current_turn),
				pts, str(VictoryState.won)])
	print("[PROBE] END %s: turn=%d money=%.1f ended='%s' won=%s track_best=%s" % [
		start_id, TurnManager.current_turn, MatchState.money, _ended,
		str(VictoryState.won), str(VictoryState.track_best)])
	get_tree().quit(0)
