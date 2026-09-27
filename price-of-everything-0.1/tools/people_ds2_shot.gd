extends Node
## Captures of the People panel in its v2 and DS2 looks (UiPrefs.use_people_ds2), in the real HUD, cropped to
## the panel: an empire with something to show (the ledger shot's buildings, stock on their tiles, cash, Vera
## seated as CFO and Tom as COO, four turns played), each tab paged top to bottom in each look; then, in DS2,
## the council's sheets (the picker, a candidate's dossier), Labour at its extremes and at its floor.
## Needs a window:
##   PEOPLE_SHOT_DIR=<dir> <godot> --path . res://tools/people_ds2_shot.tscn --quit-after 20000 -- --no-telemetry
## Writes people_<look>_<tab>_p<page>.png and the named DS2 views into $PEOPLE_SHOT_DIR (or the user data folder).

var _wm: Node
var _dir := ""


func _ready() -> void:
	_dir = OS.get_environment("PEOPLE_SHOT_DIR")
	if _dir == "":
		_dir = OS.get_user_data_dir()
	DirAccess.make_dir_recursive_absolute(_dir)
	_wm = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(_wm)
	await _settle(140)
	var cam := get_viewport().get_camera_2d()
	if cam != null:
		cam.edge_pan_enabled = false
	DecisionState.enabled = false
	MatchState.money = 25000.0
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
			Stockpile.add(str(sp[2]), str((inp as Dictionary).get("good_id", "")), 60)
	AdvisorState.permanent_advisor_ids = ["vera", "tom"]
	AdvisorState.all_seats_unlocked = true
	AdvisorState.assign_advisor_to_seat("cfo", "vera")
	AdvisorState.assign_advisor_to_seat("coo", "tom")
	TurnManager.fast_mode = true
	for _i in 4:
		TurnManager.commit_turn()
		if TurnManager.is_resolving:
			await TurnManager.turn_resolution_completed
		await _settle(6)
	var hud: Node = _wm.get_node("UILayer/HUD")
	hud.call("_hide_all_panels")
	hud.call("_on_people_pressed")
	await _settle(20)
	var panel: Control = hud.get("people_panel")
	if panel == null or not panel.visible:
		print("[PEOPLE_SHOT] the panel did not open")
		get_tree().quit(1)
		return
	for look in ["v2", "ds2"]:
		UiPrefs.set_use_people_ds2(look == "ds2")
		await _settle(20)
		for t in 2:
			_show_tab(panel, t)
			await _settle(14)
			await _pages(panel, "people_%s_%s" % [look, ["advisors", "labour"][t]])
	await _ds2_views(panel)
	await _labour_views(panel)
	print("[PEOPLE_SHOT] panel %s, min width %.0f" % [str(panel.get_global_rect()), panel.get_combined_minimum_size().x])
	UiPrefs.set_use_people_ds2(false)
	get_tree().quit(0)


## The DS2 Advisors tab's other views: the seats not yet opened (padlocks), a council with room (an open seat),
## the picker with candidates, a candidate's dossier with a seat chosen, a seated advisor's dossier.
func _ds2_views(panel: Control) -> void:
	var shell: Control = panel.find_child("PeopleDs2", false, false)
	if shell == null:
		return
	shell.call("show_tab", 0)
	var tab: Control = shell.call("body", 0)
	# A full council (2/2): every empty seat padlocked.
	AdvisorState.max_advisor_slots = 2
	AdvisorState.advisors_changed.emit()
	await _settle(16)
	await _shot(panel, "people_ds2_advisors_full")
	# A slot free (2/3) before the rest of the seats are opened: the open seats' Assign keys, the others' requirement.
	AdvisorState.all_seats_unlocked = false
	AdvisorState.max_advisor_slots = 3
	AdvisorState.advisors_changed.emit()
	await _settle(16)
	await _shot(panel, "people_ds2_advisors_unopened")
	AdvisorState.all_seats_unlocked = true
	AdvisorState.recruited_advisor_ids = ["gerald", "eleanor", "hitomi", "marcus"]
	AdvisorState.advisors_changed.emit()
	await _settle(16)
	await _shot(panel, "people_ds2_advisors_open")
	tab.call("_set_view", {"mode": "picker", "back": "roster"})
	await _settle(30)
	await _shot(panel, "people_ds2_picker")
	tab.call("_set_view", {"mode": "detail", "sel_id": "gerald", "selected_seat": "vp_logistics", "back": "picker"})
	await _settle(30)
	await _shot(panel, "people_ds2_dossier_candidate")
	tab.call("_set_view", {"mode": "detail", "sel_id": "tom", "back": "roster"})
	await _settle(30)
	await _shot(panel, "people_ds2_dossier_seated")
	tab.call("_set_view", {"mode": "roster"})
	await _settle(8)


## The DS2 Labour tab's other views, where the look has them.
func _labour_views(panel: Control) -> void:
	var shell: Control = panel.find_child("PeopleDs2", false, false)
	if shell == null:
		return
	shell.call("show_tab", 1)
	var tab: Control = shell.call("body", 1)
	if tab == null or not tab.has_method("shot_views"):
		return
	for v: Dictionary in tab.call("shot_views"):
		var setup: Callable = v.setup
		setup.call()
		await _settle(int(v.get("frames", 16)))
		await _pages(panel, "people_ds2_labour_%s" % str(v.name))


func _show_tab(panel: Control, t: int) -> void:
	var shell: Control = panel.find_child("PeopleDs2", false, false)
	if shell != null:
		shell.call("show_tab", t)
		return
	for c in panel.find_children("*", "TabContainer", true, false):
		(c as TabContainer).current_tab = t
		return


## Page the tallest visible scroll in the panel from top to bottom, one crop a page.
func _pages(panel: Control, stem: String) -> void:
	var sc: ScrollContainer = null
	var best := -1.0
	for c in panel.find_children("*", "ScrollContainer", true, false):
		var s := c as ScrollContainer
		if s.is_visible_in_tree() and s.get_v_scroll_bar().max_value > best:
			best = s.get_v_scroll_bar().max_value
			sc = s
	var page := 0
	var y := 0
	while true:
		if sc != null:
			sc.scroll_vertical = y
		await _settle(4)
		await _shot(panel, "%s_p%d" % [stem, page])
		page += 1
		if sc == null:
			break
		var bar := sc.get_v_scroll_bar()
		var maxv := int(bar.max_value - bar.page)
		if y >= maxv or page >= 6:
			break
		y = mini(y + int(sc.size.y * 0.85), maxv)
	if sc != null:
		sc.scroll_vertical = 0


## Hide everything beside the panel's own line of ancestors (briefings, popups, docks, the map), so the crop
## is the panel alone. Returns what was hidden, for _restore.
func _isolate(panel: Node) -> Array:
	var hidden: Array = []
	var n: Node = panel
	while n != null and n != get_tree().root:
		var parent := n.get_parent()
		if parent == null:
			break
		for sib in parent.get_children():
			if sib == n:
				continue
			if (sib is CanvasItem and (sib as CanvasItem).visible) or (sib is CanvasLayer and (sib as CanvasLayer).visible) \
					or (sib is Window and (sib as Window).visible):
				sib.set("visible", false)
				hidden.append(sib)
		n = parent
	for layer in get_tree().root.find_children("*", "CanvasLayer", true, false):
		var cl := layer as CanvasLayer
		if cl.visible and not cl.is_ancestor_of(panel):
			cl.visible = false
			hidden.append(cl)
	return hidden


func _restore(hidden: Array) -> void:
	for h in hidden:
		if is_instance_valid(h):
			h.set("visible", true)


func _shot(panel: Control, file: String) -> void:
	var hidden := _isolate(panel)
	await _settle(2)
	RenderingServer.force_draw(false)
	var img := get_viewport().get_texture().get_image()
	var k := Vector2(img.get_size()) / get_viewport().get_visible_rect().size
	var g := panel.get_global_rect().grow(8)
	var r := Rect2i(Vector2i(g.position * k), Vector2i(g.size * k)).intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	img.get_region(r).save_png(_dir.path_join(file + ".png"))
	print("[PEOPLE_SHOT] saved ", file)
	_restore(hidden)


func _settle(n: int) -> void:
	for _i in n:
		await get_tree().process_frame
