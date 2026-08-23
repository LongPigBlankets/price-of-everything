extends Node
## Dev-only: capture the Victory panel under the DEMO ruleset, so the five new tracks are
## checked as a player sees them and not only as assertions.
## Run (windowed, NOT --headless, so it actually renders):
##   Godot --path . res://tools/demo_victory_shot.tscn --quit-after 1200

func _ready() -> void:
	# The demo ruleset lands BEFORE the HUD is built — the order a real match uses.
	var rules := {"speed_turns": 100, "policy_timeline": "demo_itch", "victory_set": "demo_itch"}
	MatchState.ruleset = rules
	TurnManager.apply_ruleset(rules)
	VictoryState.apply_ruleset(rules)
	var game: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(game)
	await _settle(60)
	# Part-filled tracks, so the meters, the metric lines and the forecast all have
	# something to say — an all-zero panel would hide a formatting mistake.
	VictoryState.demo_crown_turns = 13
	VictoryState.demo_long_hauls = 4
	VictoryState.track_best["crown"] = 0.65
	VictoryState.track_best["tiers"] = 1.0
	VictoryState.track_best["distance"] = 0.4
	VictoryState.track_best["green_demo"] = 0.25
	VictoryState.track_best["estate"] = 0.5
	VictoryState._last_summary = {"produced": {"g_001": 5, "g_021": 3},
		"power_supply": 3000, "power_supply_by_quality": {"green_intermittent": 1000.0}}
	VictoryState._refresh_breakdown()
	VictoryState._emit_refresh()   # the top bar updates on the signal, as it does in a match
	await _settle(10)

	var bd: Dictionary = VictoryState.get_breakdown()
	print("[DEMO_VICTORY] total=%d threshold=%d tracks=%d" % [
		int(bd.get("total", 0)), int(bd.get("win_threshold", 0)),
		(bd.get("tracks", []) as Array).size()])
	for t_variant: Variant in (bd.get("tracks", []) as Array):
		var t: Dictionary = t_variant
		print("[DEMO_VICTORY]   %-9s %4d/%d  %s" % [
			str(t.get("name", "")), int(t.get("contribution", 0)), int(t.get("max_score", 0)),
			str(t.get("metric_text", ""))])

	# The node named BottomMenu is the strip, not the controller — find the node that
	# actually carries bottom_menu.gd by looking for its method.
	var menu: Node = _find_by_method(game, "_on_victory_widget_clicked")
	print("[DEMO_VICTORY] bottom menu: %s  script=%s  has=%s" % [
		("found" if menu != null else "NOT FOUND"),
		str(menu.get_script().resource_path) if menu != null and menu.get_script() != null else "none",
		str(menu.has_method("_on_victory_widget_clicked")) if menu != null else "n/a"])
	if menu != null and menu.has_method("_on_victory_widget_clicked"):
		menu._on_victory_widget_clicked()
		await _settle(30)
		var vp: Variant = menu.get("victory_panel")
		print("[DEMO_VICTORY] panel visible: %s" % str((vp as Control).visible if vp != null else "no panel"))
	get_viewport().get_texture().get_image().save_png("user://poe_demo_victory.png")
	print("SAVED poe_demo_victory.png")
	get_tree().quit(0)

func _find_by_method(n: Node, method: String) -> Node:
	if n.has_method(method):
		return n
	for c in n.get_children():
		var hit := _find_by_method(c, method)
		if hit != null:
			return hit
	return null

func _settle(frames: int) -> void:
	for _i in frames:
		await get_tree().process_frame
