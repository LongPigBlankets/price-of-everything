extends Node
## Captures of the turn briefing ("THIS TURN") and the updates dock (docs/briefing-ds2-plan.md). Boots the real
## game, seeds a small empire with one crowded tile and one tile short of its inputs, and plays turns until the
## turn 3 decision ("A Retired Man Who Misses the Work") arrives, then walks the briefing through its states: a
## decision with figures and alerts lit, two decisions queued, a three choice decision with a locked choice, a
## window picked, alerts only, each lit window, the rows timed as they arrive and opened by the player with the
## pen's lamp, and nothing waiting.
##   BRIEFING_TOUR_DIR=<dir> <godot> --path . res://tools/briefing_tour_shot.tscn --quit-after 40000 -- --no-telemetry
## Writes NN_<state>_full.png (the whole screen, half size), NN_<state>_panel.png (the briefing's card) and
## NN_<state>_dock.png (the bottom left corner with the dock) into the directory, artifacts/briefing_ds2/ds2_v1/
## by default.

var _wm: Node
var _dir := ""
var _n := 0


func _ready() -> void:
	_dir = OS.get_environment("BRIEFING_TOUR_DIR")
	if _dir == "":
		_dir = ProjectSettings.globalize_path("res://artifacts/briefing_ds2/ds2_v1")
	DirAccess.make_dir_recursive_absolute(_dir)
	_wm = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(_wm)
	await _settle(140)
	var cam := get_viewport().get_camera_2d()
	if cam != null:
		cam.edge_pan_enabled = false
	DecisionState.enabled = true
	_seed_empire()
	TurnManager.fast_mode = true
	# Play until the founder's decision is on the board (turn 3 in a sandbox start).
	for _i in 6:
		if DecisionState.has_pending():
			break
		TurnManager.commit_turn()
		if TurnManager.is_resolving:
			await TurnManager.turn_resolution_completed
		await _settle(8)
		_log_items("after commit")
	await _settle(20)
	_log_items("decision turn")
	await _tour()
	get_tree().quit(0)


## The briefing's states.
func _tour() -> void:
	var dock := _dock()
	if dock != null:
		dock.call("collapse", false)
	# 1. The founder's decision with its figures, and the alerts the turn opened with.
	TurnBriefing.expand()
	await _settle(24)
	await _capture("decision_with_figures", true)
	# 2. Two decisions queued: the letter says 1 of 2.
	var err := DecisionState.force_draw("union_demands")
	print("[BRIEF] draw union_demands -> '%s'" % err)
	await _settle(8)
	TurnBriefing.expand()
	await _settle(20)
	await _capture("two_decisions", true)
	# 3. A window picked while a decision waits: its readout and rows under the annunciator.
	var panel: Control = TurnBriefing._panel
	var worst := ""
	for w: Dictionary in TurnBriefing.alert_windows():
		if str(w.tone) != "" and worst == "":
			worst = str(w.kind)
	if worst != "" and panel != null:
		panel.call("_on_window_pressed", worst)
		await _settle(20)
		var scroll: ScrollContainer = panel.find_child("Scroll", true, false)
		if scroll != null:
			scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)
		await _settle(8)
		await _capture("window_picked_under_letter", true)
	# 4. The founder answered: the second letter, three choices, a locked one.
	for it: Dictionary in TurnBriefing.items():
		if str(it.kind) == "decision" and str((it.view as Dictionary).get("def_id", "")) == "family_friend":
			print("[BRIEF] resolve coo -> '%s'" % DecisionState.resolve("coo", str(it.uid)))
	await _settle(12)
	TurnBriefing.expand()
	await _settle(20)
	await _capture("three_choices", true)
	# 5. Every decision answered: alerts only, the worst window picked by itself.
	for it2: Dictionary in TurnBriefing.items().duplicate():
		if str(it2.kind) == "decision":
			var view: Dictionary = it2.view
			var pick := ""
			for c: Dictionary in view.choices:
				if bool(c.get("available", true)) and pick == "":
					pick = str(c.id)
			print("[BRIEF] resolve %s -> '%s'" % [pick, DecisionState.resolve(pick, str(it2.uid))])
	await _settle(12)
	TurnBriefing.expand()
	await _settle(20)
	_log_items("alerts only")
	await _capture("alerts_only", true)
	# 6. Each lit window picked.
	panel = TurnBriefing._panel
	for w2: Dictionary in TurnBriefing.alert_windows():
		if str(w2.tone) == "" or panel == null:
			continue
		if str(panel.call("picked")) != str(w2.kind):
			panel.call("_on_window_pressed", str(w2.kind))
		await _settle(16)
		await _capture("window_%s" % str(w2.kind), true)
	# 7. The rows as they arrive, timed, then opened by the player; the pen's lamp lit by the alerts.
	TurnBriefing.collapse()
	await _settle(8)
	if dock != null:
		dock.call("clear")
		MatchState.request_toast("Markets Party wins the election. It plans changes to energy and environmental policy.", "caution")
		dock.call("push_research", "Interchangeable Tooling")
		MatchState.request_toast("Built Motor Factory A. Makes 4 Motor/turn. Cost £120.", "success")
		await _settle(30)
		await _capture("dock_rows_timed", false)
		dock.call("collapse", false)
		dock.call("open_all", "")
		await _settle(30)
		await _capture("dock_opened_by_player", false)
		dock.call("collapse", false)
		await _settle(12)
		await _capture("dock_closed_pen_lamp", false)
	# 8. Nothing waiting and every alert silenced: the pen opens the panel on a dark annunciator.
	for it3: Dictionary in TurnBriefing.items().duplicate():
		TurnBriefing.dismiss(str(it3.id))
	await _settle(12)
	if dock != null:
		dock.call("_open_decisions")
	else:
		TurnBriefing.expand()
	await _settle(20)
	await _capture("nothing_waiting", true)


## Six going buildings on their own tiles, three more crowded onto one small tile so its store
## is overcommitted, and two on a tile whose inputs the company can't afford to keep buying.
func _seed_empire() -> void:
	MatchState.money = 3000.0
	var specs := [
		["b_003", "r_004", "tile_10_2"], ["b_024", "r_146", "tile_11_2"], ["b_001", "r_001", "tile_12_2"],
		["b_007", "r_008", "tile_13_2"], ["b_007", "r_009", "tile_13_2"], ["b_008", "r_030", "tile_10_3"],
		["b_020", "r_039", "tile_11_3"], ["b_012", "r_012", "tile_12_3"], ["b_011", "r_024", "tile_12_3"],
	]
	for sp: Array in specs:
		BuildingState.tile_land_owned[str(sp[2])] = 200
		BuildingState.add_building(str(sp[0]), str(sp[1]), str(sp[2]), MatchState.LOCAL_PLAYER, "")
		var recipe: Dictionary = Catalog.get_recipe(str(sp[1]))
		for inp: Variant in recipe.get("inputs", []):
			Stockpile.add(str(sp[2]), str((inp as Dictionary).get("good_id", "")), 400)


func _dock() -> Control:
	return _wm.get_node_or_null("UILayer/HUD/ToastLayer") as Control


func _log_items(tag: String) -> void:
	var parts: PackedStringArray = []
	for it: Dictionary in TurnBriefing.items():
		parts.append("%s[%s/%s] %s" % [str(it.id), str(it.section), str(it.severity), str(it.title)])
	print("[BRIEF] t%d %s: money %.0f, expanded %s, %d items: %s" % [
		int(TurnManager.current_turn), tag, float(MatchState.money), str(TurnBriefing.expanded), parts.size(), " | ".join(parts)])


func _capture(state: String, with_panel: bool) -> void:
	_n += 1
	var stem := "%02d_%s" % [_n, state]
	await _settle(2)
	RenderingServer.force_draw(false)
	var img := get_viewport().get_texture().get_image()
	var k := Vector2(img.get_size()) / get_viewport().get_visible_rect().size
	var full := img.duplicate() as Image
	full.resize(img.get_width() / 2, img.get_height() / 2)
	full.save_png(_dir.path_join(stem + "_full.png"))
	if with_panel:
		var card: Control = TurnBriefing._panel.get("_card") if TurnBriefing._panel != null else null
		if card != null and card.is_visible_in_tree():
			_crop(img, k, card.get_global_rect().grow(10), stem + "_panel.png")
	# The bottom left corner: the dock and whatever rises out of it.
	var vp := get_viewport().get_visible_rect().size
	_crop(img, k, Rect2(0, vp.y * 0.35, 520, vp.y * 0.65), stem + "_dock.png")
	print("[BRIEF] captured %s" % stem)


func _crop(img: Image, k: Vector2, g: Rect2, file: String) -> void:
	var r := Rect2i(Vector2i(g.position * k), Vector2i(g.size * k)).intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	if r.size.x > 0 and r.size.y > 0:
		img.get_region(r).save_png(_dir.path_join(file))


func _settle(n: int) -> void:
	for _i in n:
		await get_tree().process_frame
