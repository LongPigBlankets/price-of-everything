extends Node
## Captures of the market panel, today's look and the DS2 look (`toggle market ds2`), each cropped to the
## panel: every tab paged top to bottom, the sell panel in each quantity mode, one off and recurring, and
## (DS2) the impact hover card and the slip's chart hover. Seeds a working empire first: the tour's
## buildings with stock on their tiles, a few turns played with sales and purchases each turn so the price
## history carries quantities, recurring sales, buys and moves, and special orders.
##   MARKET_SHOT_DIR=<dir> [MARKET_SHOT_LOOKS=v2,ds2] \
##     <godot> --path . res://tools/market_ds2_shot.tscn --quit-after 60000 -- --no-telemetry
## Writes <look>_<nn>_<view>.png into $MARKET_SHOT_DIR (default /tmp/poe_market_shot).
## The game runs in a SubViewport of a fixed size, LOGICAL at two pixels each, so every capture has the
## same pixels whatever the display. Briefings, popups and the map are hidden for each capture
## (_isolate, as tools/panel_tour_shot.gd), so the crop is the panel alone.

const LOGICAL := Vector2i(1920, 1200)
const COAL := "g_001"

var _vp: SubViewport
var _wm: Node
var _dir := ""
var _n := 0
var _look := ""


func _ready() -> void:
	_dir = OS.get_environment("MARKET_SHOT_DIR")
	if _dir == "":
		_dir = "/tmp/poe_market_shot"
	DirAccess.make_dir_recursive_absolute(_dir)
	var looks := OS.get_environment("MARKET_SHOT_LOOKS").split(",", false)
	if looks.is_empty():
		looks = PackedStringArray(["v2", "ds2"])
	_vp = SubViewport.new()
	_vp.size = LOGICAL * 2
	_vp.size_2d_override = LOGICAL
	_vp.size_2d_override_stretch = true
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vp.gui_embed_subwindows = true
	add_child(_vp)
	_wm = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	_vp.add_child(_wm)
	await _settle(140)
	var cam := _vp.get_camera_2d()
	if cam != null:
		cam.set("edge_pan_enabled", false)
	await _seed_empire()
	for look: String in looks:
		_look = look
		_n = 0
		if "use_market_ds2" in UiPrefs:
			UiPrefs.call("set_use_market_ds2", look == "ds2")
		elif look == "ds2":
			print("[MARKET_SHOT] no DS2 look yet")
			continue
		await _tour()
	print("[MARKET_SHOT] done, %s" % _dir)
	get_tree().quit(0)


# --- the empire ---------------------------------------------------------------------------------

func _seed_empire() -> void:
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
	for t in ["tile_12_2", "tile_10_3", "tile_5_10"]:
		Stockpile.add(t, COAL, 120)
	TurnManager.fast_mode = true
	for turn in 8:
		# A sale and a purchase each turn, so the history carries quantities.
		MatchState.queue_sell("tile_12_2", {COAL: 10 + turn * 3})
		MatchState.queue_buy("tile_13_2", COAL, 6 + turn)
		TurnManager.commit_turn()
		if TurnManager.is_resolving:
			await TurnManager.turn_resolution_completed
		await _settle(6)
	MatchState.add_recurring_sell("tile_10_3", {COAL: 12})
	MatchState.add_recurring_buy("tile_13_2", COAL, 5)
	MatchState.add_recurring_bulk_sell({"good_id": COAL, "finished_only": false, "per_tile_keep": 20, "tiles": ["tile_5_10"]})
	TransportState.add_recurring_move("tile_10_2", "tile_12_2", {COAL: 8})
	for good in ["steel", "copper_ingots", "motor"]:
		SpecialOrderState.create_order(good)
	Stockpile.add("tile_10_3", COAL, 40)


# --- the tour -----------------------------------------------------------------------------------

func _tour() -> void:
	var hud: Node = _wm.get_node("UILayer/HUD")
	hud.call("_hide_all_panels")
	hud.call("_on_market_pressed")
	await _settle(20)
	var panel: Control = hud.get("market_panel")
	if panel == null or not panel.visible:
		print("[MARKET_SHOT] the market did not open")
		return
	await _shot(panel, "open")
	var keys: Array = panel.call("tab_keys") if panel.has_method("tab_keys") else []
	for key: String in keys:
		panel.call("show_tab", key)
		await _settle(12)
		await _pages(panel, key)
	panel.call("show_tab", keys[0] if not keys.is_empty() else "prices")
	await _settle(8)
	if panel.has_method("capture_views"):
		for view: Dictionary in panel.call("capture_views"):
			await _view(panel, view)
	# The sell panel, each quantity mode, one off and recurring.
	panel.call("open_sell_panel", COAL)
	await _settle(10)
	var sell: Control = panel.call("sell_panel")
	for spec: Array in [["all", 0, false], ["all_but", 30, false], ["only", 15, false], ["only", 15, true], ["all", 0, true]]:
		sell.call("set_mode", str(spec[0]))
		sell.call("set_qty", int(spec[1]))
		sell.call("set_recurring", bool(spec[2]))
		await _settle(6)
		await _shot(panel, "sell_%s%s" % [str(spec[0]), "_recurring" if bool(spec[2]) else ""])
	var guard: Control = sell.find_child("ConfirmSale", true, false)
	if guard != null:
		guard.call("lift")
		await _settle(4)
		await _shot(panel, "sell_cover_lifted")
		guard.call("drop")
	sell.call("close")
	await _settle(4)
	hud.call("_hide_all_panels")


## One named view the panel offers for captures (DS2: hovers), each a {name, show: Callable, hide: Callable}.
func _view(panel: Control, view: Dictionary) -> void:
	await (view.show as Callable).call()
	await _settle(8)
	await _shot(panel, str(view.name))
	if view.has("hide"):
		(view.hide as Callable).call()
	await _settle(2)


## Page the tallest visible scroll in the panel from top to bottom, one crop a page.
func _pages(panel: Control, tab: String) -> void:
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
		await _shot(panel, "%s_p%d" % [tab, page])
		page += 1
		if sc == null:
			break
		var bar := sc.get_v_scroll_bar()
		var maxv := int(bar.max_value - bar.page)
		if y >= maxv or page >= 8:
			break
		y = mini(y + int(sc.size.y * 0.85), maxv)
	if sc != null:
		sc.scroll_vertical = 0


# --- capture ------------------------------------------------------------------------------------

func _shot(panel: Control, view: String) -> void:
	var hidden := _isolate(panel)
	await _settle(2)
	RenderingServer.force_draw(false)
	var img := _vp.get_texture().get_image()
	var k := Vector2(img.get_size()) / Vector2(LOGICAL)
	var g := panel.get_global_rect().grow(8)
	var r := Rect2i(Vector2i(g.position * k), Vector2i(g.size * k)).intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	_n += 1
	img.get_region(r).save_png(_dir.path_join("%s_%02d_%s.png" % [_look, _n, view]))
	_restore(hidden)


## Hide everything beside the panel's own line of ancestors (briefings, popups, docks, the map), so the
## crop is the panel alone. Returns what was hidden, for _restore.
func _isolate(panel: Node) -> Array:
	var hidden: Array = []
	var n: Node = panel
	while n != null and n != _vp:
		var parent := n.get_parent()
		if parent == null:
			break
		for sib in parent.get_children():
			if sib == n:
				continue
			if (sib is CanvasItem and (sib as CanvasItem).visible) or (sib is CanvasLayer and (sib as CanvasLayer).visible) \
					or (sib is Window and (sib as Window).visible):
				if sib is CanvasItem and (sib as CanvasItem).is_ancestor_of(panel):
					continue
				sib.set("visible", false)
				hidden.append(sib)
		n = parent
	for layer in _vp.find_children("*", "CanvasLayer", true, false):
		var cl := layer as CanvasLayer
		if cl.visible and not cl.is_ancestor_of(panel):
			cl.visible = false
			hidden.append(cl)
	return hidden


func _restore(hidden: Array) -> void:
	for h in hidden:
		if is_instance_valid(h):
			h.set("visible", true)


func _settle(n: int) -> void:
	for _i in n:
		await get_tree().process_frame
