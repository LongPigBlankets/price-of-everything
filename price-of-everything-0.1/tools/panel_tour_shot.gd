extends Node
## Captures of a HUD panel in every tab, paged top to bottom, as it looks today: the "before"
## for a DS2 move. Plays a few turns first so prices, stock and people have something to show.
##   PANEL_TOUR=market,resources,people PANEL_TOUR_DIR=<dir> \
##     <godot> --path . res://tools/panel_tour_shot.tscn --quit-after 20000 -- --no-telemetry
## Writes <panel>_<nn>_<tab>_p<page>.png (panel crops) and <panel>_full.png per panel.
## PANEL_TOUR_RESOURCES_DS2=1 switches the Resources panel to its DS2 look first, and opens the first good held.

var _wm: Node
var _dir := ""


func _ready() -> void:
	_dir = OS.get_environment("PANEL_TOUR_DIR")
	if _dir == "":
		_dir = OS.get_user_data_dir()
	DirAccess.make_dir_recursive_absolute(_dir)
	var which := OS.get_environment("PANEL_TOUR").split(",", false)
	if which.is_empty():
		which = PackedStringArray(["market", "resources", "people"])
	if OS.get_environment("PANEL_TOUR_RESOURCES_DS2") == "1":
		UiPrefs.set_use_resources_ds2(true)
	_wm = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(_wm)
	await _settle(140)
	var cam := get_viewport().get_camera_2d()
	if cam != null:
		cam.edge_pan_enabled = false
	# No decision modal over the panels, and an empire with something to show: the ledger shot's
	# buildings, stock on their tiles, cash, and two advisors seated.
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
	for name: String in which:
		var opener: String = {"market": "_on_market_pressed", "resources": "_on_resources_pressed", "people": "_on_people_pressed"}.get(name, "")
		if opener == "":
			continue
		hud.call("_hide_all_panels")
		hud.call(opener)
		await _settle(20)
		var panel: Control = {"market": hud.get("market_panel"), "resources": hud.get("resource_panel"), "people": hud.get("people_panel")}[name]
		if panel == null or not panel.visible:
			print("[TOUR] %s did not open" % name)
			continue
		var ds2 := panel.find_child("ResourcesDs2", true, false)
		if name == "resources" and ds2 != null:
			ds2.call("sort_by", "stored")
			var held: Array = ds2.call("shown_rows")
			if not held.is_empty():
				ds2.call("toggle_good", str(held[0].good_id))
			await _settle(8)
		_clear_overlays(_wm)
		await _settle(4)
		_full(name)
		var tabs := _first_tabs(panel)
		var n := 0
		if tabs == null:
			n = await _pages(panel, name, n, "main")
		else:
			for t in tabs.get_tab_count():
				tabs.current_tab = t
				await _settle(12)
				_clear_overlays(_wm)
				await _settle(2)
				n = await _pages(panel, name, n, tabs.get_tab_title(t).to_lower().replace(" ", "_"))
		print("[TOUR] %s: %d captures, panel %s" % [name, n, str(panel.get_global_rect())])
	get_tree().quit(0)


## The turn briefing and advisor popups sit over the panels; the captures are of the panel.
const OVERLAY_SCRIPTS := ["turn_briefing_panel.gd", "turn_briefing.gd", "cfo_intro_popup.gd"]

func _clear_overlays(n: Node) -> void:
	var sc: Script = n.get_script() as Script
	if sc != null and n is CanvasItem and str(sc.resource_path).get_file() in OVERLAY_SCRIPTS:
		(n as CanvasItem).visible = false
	for c in n.get_children():
		_clear_overlays(c)


func _first_tabs(root: Node) -> TabContainer:
	for c in root.find_children("*", "TabContainer", true, false):
		if (c as Control).is_visible_in_tree():
			return c
	return null


## Page the tallest visible scroll in the panel from top to bottom, one crop a page.
func _pages(panel: Control, name: String, n: int, tab: String) -> int:
	var sc: ScrollContainer = null
	var best := 0.0
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
		n += 1
		await _shot(panel, "%s_%02d_%s_p%d" % [name, n, tab, page])
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
	return n


## Hide everything beside the panel's own line of ancestors (briefings, popups, docks, the
## map), so the crop is the panel alone. Returns what was hidden, for _restore.
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
	# A CanvasLayer draws whatever its parent's visibility (popups hang off the top bar and the dock).
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
	_restore(hidden)


func _full(name: String) -> void:
	RenderingServer.force_draw(false)
	var img := get_viewport().get_texture().get_image()
	img.resize(img.get_width() / 2, img.get_height() / 2)
	img.save_png(_dir.path_join(name + "_full.png"))


func _settle(n: int) -> void:
	for _i in n:
		await get_tree().process_frame
