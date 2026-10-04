extends Node
## Captures of the Victory panel under the demo rules, part filled, in today's look and in DS2
## (UiPrefs.use_victory_ds2): the panel open, and with a track won.
##   AGENT_GODOT_WINDOW=1 godot --path . res://tools/victory_ds2_shot.tscn --quit-after 20000 -- --no-telemetry
## Writes victory_<look>_<view>.png into $VICTORY_SHOT_DIR (or /tmp).

const ShotHarness := preload("res://tools/shot_harness.gd")

var _out := "/tmp"


func _ready() -> void:
	var dir := OS.get_environment("VICTORY_SHOT_DIR")
	if dir != "":
		_out = dir
	DirAccess.make_dir_recursive_absolute(_out)
	ShotHarness.arm_watchdog(self, 180.0)
	ShotHarness.prepare_window(get_window(), Vector2i(1920, 1080))
	TelemetryState.enabled = false
	var rules := {"speed_turns": 100, "policy_timeline": "demo_itch", "victory_set": "demo_itch"}
	MatchState.ruleset = rules
	TurnManager.apply_ruleset(rules)
	VictoryState.apply_ruleset(rules)
	var game: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(game)
	await _settle(120)
	DecisionState.enabled = false
	VictoryState.demo_crown_points = 650
	VictoryState.demo_long_hauls = 4
	VictoryState.track_best["crown"] = 0.65
	VictoryState.track_best["tiers"] = 0.8
	VictoryState.track_best["distance"] = 0.4
	VictoryState.track_best["green_demo"] = 0.25
	VictoryState.track_best["estate"] = 0.1
	VictoryState._last_summary = {"produced": {"g_001": 5, "g_021": 3},
		"power_supply": 3000, "power_supply_by_quality": {"green_intermittent": 1000.0}}
	VictoryState._refresh_breakdown()
	VictoryState._emit_refresh()
	await _settle(10)
	var panel := game.find_child("VictoryPanel", true, false) as Control
	if panel == null:
		push_error("victory_ds2_shot: no VictoryPanel")
		get_tree().quit(1)
		return
	for look: String in ["v2", "ds2"]:
		print("[VICTORY_SHOT] look ", look)
		if "use_victory_ds2" in UiPrefs:
			UiPrefs.set("use_victory_ds2", look == "ds2")
			if UiPrefs.has_signal("victory_ds2_changed"):
				UiPrefs.emit_signal("victory_ds2_changed", look == "ds2")
		elif look == "ds2":
			break
		panel.show()
		PanelStack.push(panel)
		await _wait(0.8)
		await _shot("victory_%s_open" % look)
		VictoryState.won = true
		VictoryState.won_turn = 64
		VictoryState._emit_refresh()
		await _wait(0.5)
		await _shot("victory_%s_won" % look)
		VictoryState.won = false
		VictoryState._emit_refresh()
		PanelStack.remove(panel)
		panel.hide()
		await _settle(10)
	get_tree().quit()


func _shot(name: String) -> void:
	print("[VICTORY_SHOT] shot ", name)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_out.path_join(name + ".png"))
	await get_tree().process_frame


func _settle(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout
