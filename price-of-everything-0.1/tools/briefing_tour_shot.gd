extends Node
## Captures of the turn briefing ("THIS TURN") and the updates dock as they look today: the
## "before" for the briefing's DS2 move (docs/briefing-ds2-plan.md). Boots the real game, seeds a
## small empire with one crowded tile and one tile short of its inputs, and plays turns until the
## turn 3 decision ("A Retired Man Who Misses the Work") arrives, then walks the briefing through
## its states: decision only, decision with alerts, collapsed (the pen), reopened from the pen,
## alerts only with the footer "All caught up", each alert's detail, and empty.
##   BRIEFING_TOUR_DIR=<dir> <godot> --path . res://tools/briefing_tour_shot.tscn --quit-after 40000 -- --no-telemetry
## Writes NN_<state>_full.png (the whole screen, half size), NN_<state>_panel.png (the briefing's
## card) and NN_<state>_dock.png (the bottom left corner with the dock) into the directory.

var _wm: Node
var _dir := ""
var _n := 0


func _ready() -> void:
	_dir = OS.get_environment("BRIEFING_TOUR_DIR")
	if _dir == "":
		_dir = ProjectSettings.globalize_path("res://artifacts/briefing_ds2/before")
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

	# 1. The decision alone: the alerts quietened for this view, brought back after it.
	var alert_ids: Array = []
	for it: Dictionary in TurnBriefing.items():
		if str(it.id).begins_with("alert:") and bool(it.get("dismissible", false)):
			alert_ids.append(str(it.id))
	for id: String in alert_ids:
		TurnBriefing.dismiss(id)
	await _settle(4)
	TurnBriefing.expand()
	await _settle(16)
	await _capture("decision_only", true)
	TurnBriefing._alert_dismissed.clear()
	TurnBriefing._queue_refresh()
	await _settle(6)

	# 2. The decision with the alerts, as the turn actually opened.
	TurnBriefing.expand()
	await _settle(16)
	await _capture("decision_and_alerts", true)

	# 3. Collapsed: the panel goes; the dock's pen keeps the count.
	TurnBriefing.collapse()
	await _settle(12)
	await _capture("collapsed", false)

	# 4. The dock's slide-out opened on every row (the toasts of the turn).
	var dock := _dock()
	if dock != null:
		dock.call("open_all", "")
		await _settle(30)
		await _capture("dock_open", false)
		dock.call("collapse", false)
		await _settle(6)

	# 5. The pen reopens the briefing on its decision.
	if dock != null:
		dock.call("_open_decisions")
	else:
		TurnBriefing.expand()
	await _settle(16)
	await _capture("reopened_from_pen", true)

	# 6. The decision answered: alerts only, the footer says the turn can end.
	var uid := ""
	for it2: Dictionary in TurnBriefing.items():
		if str(it2.kind) == "decision":
			uid = str(it2.uid)
			break
	if uid != "":
		var err := DecisionState.resolve("coo", uid)
		print("[BRIEF] resolve coo -> '%s'" % err)
	await _settle(10)
	TurnBriefing.expand()
	await _settle(16)
	_log_items("after resolve")
	await _capture("alerts_caught_up", true)

	# 7. Each alert or update in the detail pane.
	for it3: Dictionary in TurnBriefing.items():
		TurnBriefing.expand(str(it3.id))
		await _settle(12)
		await _capture("item_%s" % str(it3.id).replace(":", "_").replace("/", "_"), true)

	# 8. Everything dismissed: nothing left to show.
	for it4: Dictionary in TurnBriefing.items().duplicate():
		TurnBriefing.dismiss(str(it4.id))
	await _settle(12)
	_log_items("after dismiss all")
	TurnBriefing.expand()
	await _settle(12)
	await _capture("empty", false)

	# 9. A clean screen at full size, no dialog and the dock closed: the ground a study is laid on.
	_hide_scripted(get_tree().root, "capacity_dialog.gd")
	if dock != null:
		dock.call("collapse", false)
	await _settle(12)
	RenderingServer.force_draw(false)
	get_viewport().get_texture().get_image().save_png(_dir.path_join("%02d_clean_screen.png" % (_n + 1)))
	print("[BRIEF] captured clean screen")
	get_tree().quit(0)


func _hide_scripted(n: Node, file: String) -> void:
	var sc: Script = n.get_script() as Script
	if sc != null and n is CanvasItem and str(sc.resource_path).get_file() == file:
		(n as CanvasItem).visible = false
	for c in n.get_children():
		_hide_scripted(c, file)


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
